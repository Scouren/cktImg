//! Connected D/S channel owners, complete gate interfaces, and reflected parent boundaries.
//!
//! Contents:
//! - `pub const Interface`
//! - `pub const Status`
//! - `pub const Dependency`
//! - `pub const Parents`
//! - `pub fn collect(arena: Allocator, ctx: context.Context, limits: reflection.Limits) !Parents`

const std = @import("std");
const context = @import("parent_context.zig");
const netlist = @import("netlist.zig");
const reflection = @import("parent_reflection.zig");
const Allocator = std.mem.Allocator;

/// Parent handles index `groups`; device and net handles index the bound netlist.
pub const Interface = struct { device: u32, gate: u32, consumer: u32, producer: ?u32, kind: enum { admitted_rail_control, channel_to_gate, formal_gate_input, unsupported_floating_internal_gate } };
/// The strongest conclusion supported by this input and the completed search.
pub const Status = enum { decline_input_boundary, decline_control_boundary, decline_involution, decline_enumeration_bound, single_channel_core_keep, single_reflection_core_keep, decline_control_cycle, raw_multigroup_candidate };
/// One directed output-to-gate edge between distinct reflected owners.
pub const Dependency = struct { source: u32, target: u32 };
/// Complete cold rows indexed by original graph handles. A cycle preserves its rows.
pub const Parents = struct {
    disposition: Status,
    reasons: std.EnumSet(context.Reason) = .empty,
    channel: []const u32 = &.{},
    groups: []const u32 = &.{},
    interfaces: []const Interface = &.{},
    dependencies: []const Dependency = &.{},
    channel_count: u32 = 0,
    group_count: u32 = 0,
    search: ?reflection.Result = null,
};
const none = std.math.maxInt(u32);

/// Reads the graph and source authority, writes cold group and interface rows into
/// `arena`. Cycles retain their certificate and group facts for diagnostic uses.
pub fn collect(arena: Allocator, ctx: context.Context, limits: reflection.Limits) !Parents {
    var r = Parents{ .disposition = .decline_input_boundary, .reasons = ctx.reasons };
    if (r.reasons.count() > 0) return r;
    const nl = ctx.nl;
    const n = nl.graph.edgeCount();
    const v = nl.graph.vertexCount();
    const order = try arena.alloc(u32, n);
    for (order, 0..) |*d, i| d.* = @intCast(i);
    std.sort.heap(u32, order, nl, lessDevice);
    var roots = try arena.alloc(u32, n);
    for (roots, 0..) |*d, i| d.* = @intCast(i);
    const driver = try arena.alloc(u32, v);
    @memset(driver, none);
    for (order) |d| {
        const ps = nl.graph.members(netlist.EdgeId.from(d));
        for ([2]netlist.VertexId{ ps[0], ps[2] }) |pin| {
            const k = ctx.kind[pin.index()];
            if (k == .supply or k == .sink) continue;
            if (driver[pin.index()] == none) driver[pin.index()] = d else roots[root(roots, d)] = root(roots, driver[pin.index()]);
        }
    }
    const components = try owners(arena, roots, order);
    r.channel = components.owner;
    r.channel_count = components.count;
    const ifaces = try arena.alloc(Interface, n);
    r.interfaces = ifaces;
    for (order, ifaces) |d, *i| {
        const gate = nl.graph.members(netlist.EdgeId.from(d))[1].index();
        const source = driver[gate];
        i.* = .{ .device = d, .gate = gate, .consumer = r.channel[d], .producer = if (source == none) null else r.channel[source], .kind = if (source != none) .channel_to_gate else switch (ctx.kind[gate]) {
            .formal => .formal_gate_input,
            .sink, .supply => .admitted_rail_control,
            .internal => .unsupported_floating_internal_gate,
        } };
        if (i.kind == .unsupported_floating_internal_gate) r.reasons.insert(.internal_gate_without_channel_owner);
    }
    if (r.reasons.count() > 0) {
        r.disposition = .decline_control_boundary;
        return r;
    }
    const search = try reflection.find(arena, ctx, order, limits);
    r.search = search;
    if (search.state == .exhausted) {
        r.disposition = .decline_enumeration_bound;
        r.reasons.insert(.bounded_search_incomplete);
        return r;
    }
    if (r.channel_count == 1) {
        r.group_count = 1;
        r.groups = r.channel;
        r.disposition = .single_channel_core_keep;
        return r;
    }
    if (search.state != .complete_unique) {
        r.disposition = .decline_involution;
        r.reasons.insert(if (search.state == .ambiguous) .multiple_full_ordered_involutions else .no_nontrivial_involution);
        return r;
    }
    for (search.first.?.devices, 0..) |e, d| roots[root(roots, @intCast(d))] = root(roots, e);
    const grouped = try owners(arena, roots, order);
    r.groups = grouped.owner;
    r.group_count = grouped.count;
    var edges: std.ArrayList(Dependency) = .empty;
    for (ifaces) |i| {
        if (i.producer == null) continue;
        const source = r.groups[driver[i.gate]];
        const target = r.groups[i.device];
        if (source == target) continue;
        for (edges.items) |e| {
            if (e.source == source and e.target == target) break;
        } else try edges.append(arena, .{ .source = source, .target = target });
    }
    r.dependencies = edges.items;
    const done = try arena.alloc(bool, r.group_count);
    @memset(done, false);
    var remaining: usize = done.len;
    while (remaining > 0) {
        const before = remaining;
        for (done, 0..) |*finished, g| {
            if (finished.*) continue;
            for (edges.items) |e| {
                if (e.target == g and !done[e.source]) break;
            } else {
                finished.* = true;
                remaining -= 1;
            }
        }
        if (before == remaining) {
            r.disposition = .decline_control_cycle;
            r.reasons.insert(.intergroup_gate_dependency_cycle);
            return r;
        }
    }
    r.disposition = if (r.group_count == 1) .single_reflection_core_keep else .raw_multigroup_candidate;
    return r;
}

// ---- private ----
fn lessDevice(nl: *const netlist.Netlist, a: u32, b: u32) bool {
    const names = nl.graph.edges.items(.name);
    return std.mem.lessThan(u8, names[a], names[b]);
}
fn root(roots: []u32, d: u32) u32 {
    var k = d;
    while (roots[k] != k) {
        roots[k] = roots[roots[k]];
        k = roots[k];
    }
    return k;
}
fn owners(arena: Allocator, roots: []u32, order: []const u32) !struct { owner: []const u32, count: u32 } {
    const ids = try arena.alloc(u32, roots.len);
    @memset(ids, none);
    const owner = try arena.alloc(u32, roots.len);
    var count: u32 = 0;
    for (order) |d| {
        const r = root(roots, d);
        if (ids[r] == none) {
            ids[r] = count;
            count += 1;
        }
        owner[d] = ids[r];
    }
    return .{ .owner = owner, .count = count };
}

test "bounded reflection distinguishes zero, one and two complete witnesses" {
    const testing = std.testing;
    var scratch = std.heap.ArenaAllocator.init(testing.allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const decl = ".model first nmos\n.model second nmos\n";
    const one = "Mleft red in1 0 0 first w=1\nMright blue in2 0 0 first w=1\n";
    const two = one ++ "Mthird gray in3 0 0 second w=2\nMfourth white in4 0 0 second w=2\n";
    for ([_]struct { devices: []const u8, ports: []const u8, want: reflection.State }{
        .{ .devices = one, .ports = "red blue in1 in2", .want = .complete_unique },
        .{ .devices = two, .ports = "red blue in1 in2 gray white in3 in4", .want = .ambiguous },
    }) |case| {
        const src = try std.fmt.allocPrint(a, "Deck\n{s}.subckt dut {s}\n{s}.ends dut\n", .{ decl, case.ports, case.devices });
        const body = try std.mem.concat(a, u8, &.{ "Deck\n", decl, case.devices });
        var nl = try netlist.parse(testing.allocator, &.{body}, null);
        defer nl.deinit(testing.allocator);
        const ctx = try context.bind(a, src, &nl, &context.standard_rails);
        const p = try collect(a, ctx, .{});
        try testing.expectEqual(case.want, p.search.?.state);
        if (case.want == .ambiguous) {
            const s = p.search.?;
            try testing.expect(!std.mem.eql(u32, s.first.?.devices, s.second.?.devices));
            var seen_incomplete = false;
            for (0..s.states) |budget| {
                const partial = try collect(a, ctx, .{ .states = budget });
                if (partial.search.?.first != null) {
                    try testing.expectEqual(.exhausted, partial.search.?.state);
                    try testing.expectEqual(@as(usize, 0), partial.groups.len);
                    seen_incomplete = true;
                }
            }
            try testing.expect(seen_incomplete);
        }
        const empty = try collect(a, ctx, .{ .states = 0 });
        try testing.expectEqual(.exhausted, empty.search.?.state);
        try testing.expect(empty.search.?.first == null);
    }
}

test "transported rail names and reordered devices preserve a complete reflected ownership" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ph = ".model mn nmos\n";
    const inputs = [2][]const u8{ "Ml red up vss vss mn\nMr blue down vss vss mn\n", "Md bbar yref bottom bottom mn\nMc abar xref bottom bottom mn\n" };
    for (inputs, 0..) |cards, i| {
        const raw = try std.fmt.allocPrint(a, "Deck\n{s}.subckt dut {s}\n{s}.ends\n", .{ ph, if (i == 0) "red blue up down vss" else "abar bbar xref yref bottom", cards });
        const body = try std.mem.concat(a, u8, &.{ "Deck\n", ph, cards });
        var nl = try netlist.parse(t.allocator, &.{body}, null);
        defer nl.deinit(t.allocator);
        const rails = [1]context.Rail{.{ .name = if (i == 0) "vss" else "bottom", .kind = .sink }};
        const ctx = try context.bind(a, raw, &nl, &rails);
        const r = try collect(a, ctx, .{});
        try t.expectEqual(Status.single_reflection_core_keep, r.disposition);
        try t.expectEqual(@as(u32, 2), r.channel_count);
        try t.expectEqual(@as(u32, 1), r.group_count);
        try t.expectEqualSlices(u32, &.{ 1, 0 }, r.search.?.first.?.devices);
    }
}
