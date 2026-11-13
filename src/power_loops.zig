//! Flying-capacitor loops: existing graph, roles and drawn rows -> one
//! optional group of ten device handles and seven semantic net handles.
//!
//! Human Rules:
//! - power_loops.1 (habit, bounded) A unique PMOS/coil/PMOS path from an
//!   externally controlled PMOS input bus to a grounded output reservoir
//!   closes a lower loop through another bus PMOS, a flying capacitor,
//!   a diode and a floating output capacitor. A unique two-resistor
//!   output-to-ground divider completes the group. All seven local nets
//!   are distinct and nonrail. Channel endpoints alone select the group.
//! - power_loops.2 (habit, bounded) Both floating caps stand upright,
//!   input-side coil net above the flying cap's lower node and output
//!   above the other cap's negative net. The divider runs downward and
//!   the lower MOS and diode lie flat. All 145 selected AnalogGenie
//!   drawings agree; the 734 AMSNet drawings select none. These are
//!   related converter variants, not independent examples. `forms`
//! - power_loops.3 (scope) The observed diode has its anode on the
//!   floating output's negative net. Reversal is unobserved and excluded,
//!   not an invalid circuit. Count every complete loop before this test.
//!   Duplicate members, competing paths/branches and shared groups
//!   abstain before forms or coordinates can hide an alternative.
//! - power_loops.4 (scope) Gate direction, lower-row equality and output
//!   branch order vary in the source. This topology result imposes none
//!   of them. Explicit forms, ends and placement instructions retain
//!   precedence in their owners. Evidence: docs/research/converter-loops.md,
//!   3,335 verified actual SVG lead endpoints and seven continuous local
//!   source wire trees per selected circuit. Geometry alone is no wire.
//! - power_loops.5 (scope) None of the 145 source groups has a grounded
//!   capacitor on either main gate or either coil endpoint. Such an
//!   extension needs its own branch-placement evidence, so the whole
//!   promoted pattern abstains after raw shared-member checks. This is
//!   an unobserved extension, not an invalid circuit.
//!
//! Data: at most one result per existing coil; all handles fit the graph's
//! u32 indices. Callers read the whole fixed group, on their stack only.
//! Queries allocate nothing and retain nothing. Every scan is bounded by
//! an existing edge/CSR row; independent coil queries read shared rows.
//! Owners apply forms, placement and wiring after the query. This free
//! function is their shared topology seam, not another netlist table.
//!
//! Contents:
//! - `pub const Member = enum(u4)`, `pub const Net = enum(u3)`
//! - `pub const Group = struct`
//! - `pub fn find(nl: *const Netlist, roles: []const Role, drawn: []const bool, coil: u32) ?Group`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const power_paths = @import("power_paths.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = @import("schematic.zig").Role;

/// Indices in `Group.devices`, in semantic input-to-output order.
pub const Member = enum(u4) { main_in, coil, main_out, lower, fly, diode, output_cap, grounded_cap, upper_r, lower_r };

/// Indices in `Group.nets`; the divider's ground is its other path end.
pub const Net = enum(u3) { bus, input_near, output_near, output, bottom, negative, feedback };

/// Complete, unique topology. Every handle is drawn and every listed net
/// is distinct and nonrail. Form and caller-geometry compatibility belong
/// to consumers; changing either cannot remove an electrical ambiguity.
pub const Group = struct {
    /// Existing device indices, indexed by `Member`.
    devices: [10]u32,
    /// Existing net indices, indexed by `Net`.
    nets: [7]u32,
};

comptime {
    assert(@sizeOf(Group) == 68);
}

const none = std.math.maxInt(u32);

/// Finds the unique complete loop around `coil`, rejecting a shared member
/// with any other complete loop before the caller applies form constraints.
/// `coil` is an existing device (noncoils return null); the two slices span
/// their existing graph tables. Returns only stack values; no allocation.
pub fn find(nl: *const Netlist, roles: []const Role, drawn: []const bool, coil: u32) ?Group {
    const c = &nl.graph;
    assert(coil < c.edgeCount() and drawn.len == c.edgeCount());
    assert(roles.len == c.vertexCount());
    const chosen = candidate(nl, roles, drawn, coil) orelse return null;
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .inductor or d == coil or !drawn[d]) continue;
        const other = candidate(nl, roles, drawn, @intCast(d)) orelse continue;
        for (chosen.devices) |member| {
            if (std.mem.indexOfScalar(u32, &other.devices, member) != null) return null;
        }
    }
    const diode = chosen.devices[@backingInt(Member.diode)];
    if (nl.path(EdgeId.from(diode)).?[0] != chosen.nets[@backingInt(Net.negative)]) return null;
    // Restrict the whole pattern before forms can move these branches.
    // Keep this after raw overlap detection: an unsupported extension
    // must not hide a competing complete group from another coil.
    const watched = [_]u32{
        c.members(EdgeId.from(chosen.devices[@backingInt(Member.main_in)]))[1].index(),
        c.members(EdgeId.from(chosen.devices[@backingInt(Member.main_out)]))[1].index(),
        chosen.nets[@backingInt(Net.input_near)],
        chosen.nets[@backingInt(Net.output_near)],
    };
    for (watched) |net| for (c.incident(VertexId.from(net))) |e| {
        if (!drawn[e.index()] or c.edges.items(.kind)[e.index()] != .capacitor) continue;
        const other = opposite(nl, e.index(), net) orelse continue;
        if (roles[other] == .sink) return null;
    };
    for (chosen.devices, 0..) |d, i| {
        assert(d < c.edgeCount() and drawn[d]);
        assert(std.mem.indexOfScalar(u32, chosen.devices[0..i], d) == null);
    }
    return chosen;
}

// ---- private ----

fn candidate(nl: *const Netlist, roles: []const Role, drawn: []const bool, coil: u32) ?Group {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    if (kinds[coil] != .inductor) return null;
    const mains = power_paths.seriesTopology(nl, roles, drawn, coil) orelse return null;
    const near = nl.path(EdgeId.from(coil)).?;
    const outer = [2]u32{ opposite(nl, mains[0], near[0]).?, opposite(nl, mains[2], near[1]).? };
    var direction: ?usize = null;
    for (outer, 0..) |bus, side| {
        if (!power_paths.inputBus(nl, roles, drawn, bus)) continue;
        const reservoir = for (c.incident(VertexId.from(outer[1 - side]))) |e| {
            if (!drawn[e.index()] or kinds[e.index()] != .capacitor) continue;
            const ground = opposite(nl, e.index(), outer[1 - side]) orelse continue;
            if (roles[ground] == .sink) break true;
        } else false;
        if (!reservoir) continue;
        if (direction != null) return null;
        direction = side;
    }
    const side = direction orelse return null;
    const main_in = mains[2 * side];
    const main_out = mains[2 * (1 - side)];
    const bus = outer[side];
    const input = near[side];
    const output_near = near[1 - side];
    const output = outer[1 - side];
    var loop: ?Group = null;
    for (c.incident(VertexId.from(bus))) |low| {
        const lower = low.index();
        if (!drawn[lower] or kinds[lower] != .mosfet or lower == main_in or lower == main_out) continue;
        // inputBus already certified every channel on this net as a
        // distinct-channel PMOS with gate-only control. Side pins do not
        // supply the channel; the flying capacitor supplies its load.
        const bottom = opposite(nl, lower, bus) orelse continue;
        for (c.incident(VertexId.from(input))) |fly| {
            if (!drawn[fly.index()] or kinds[fly.index()] != .capacitor) continue;
            if ((opposite(nl, fly.index(), input) orelse continue) != bottom) continue;
            for (c.incident(VertexId.from(bottom))) |diode| {
                if (!drawn[diode.index()] or kinds[diode.index()] != .diode) continue;
                const negative = opposite(nl, diode.index(), bottom) orelse continue;
                const nets = [6]u32{ bus, input, output_near, output, bottom, negative };
                if (!distinctSignals(roles, &nets)) continue;
                for (c.incident(VertexId.from(output))) |cap| {
                    if (!drawn[cap.index()] or kinds[cap.index()] != .capacitor) continue;
                    if ((opposite(nl, cap.index(), output) orelse continue) != negative) continue;
                    const next: Group = .{
                        .devices = .{ main_in, coil, main_out, lower, fly.index(), diode.index(), cap.index(), none, none, none },
                        .nets = .{ bus, input, output_near, output, bottom, negative, none },
                    };
                    // A MOS body may duplicate a CSR incidence. Only an
                    // identical tuple is a repeated visit, not a choice.
                    if (loop) |old| if (!std.mem.eql(u32, &old.devices, &next.devices)) return null;
                    loop = next;
                }
            }
        }
    }
    var group = loop orelse return null;
    var grounded: ?u32 = null;
    for (c.incident(VertexId.from(output))) |e| {
        if (!drawn[e.index()] or kinds[e.index()] != .capacitor) continue;
        const ground = opposite(nl, e.index(), output) orelse continue;
        if (roles[ground] != .sink) continue;
        if (grounded) |old| if (old != e.index()) return null;
        grounded = e.index();
    }
    group.devices[@backingInt(Member.grounded_cap)] = grounded orelse return null;
    var divider: ?[2]u32 = null;
    for (c.incident(VertexId.from(output))) |upper| {
        if (!drawn[upper.index()] or kinds[upper.index()] != .resistor) continue;
        const feedback = opposite(nl, upper.index(), output) orelse continue;
        if (roles[feedback].isRail() or std.mem.indexOfScalar(u32, group.nets[0..6], feedback) != null) continue;
        for (c.incident(VertexId.from(feedback))) |lower| {
            if (!drawn[lower.index()] or kinds[lower.index()] != .resistor) continue;
            const ground = opposite(nl, lower.index(), feedback) orelse continue;
            if (roles[ground] != .sink) continue;
            const pair: [2]u32 = .{ upper.index(), lower.index() };
            if (divider) |old| if (!std.mem.eql(u32, &old, &pair)) return null;
            divider = pair;
            group.nets[@backingInt(Net.feedback)] = feedback;
        }
    }
    const pair = divider orelse return null;
    group.devices[@backingInt(Member.upper_r)] = pair[0];
    group.devices[@backingInt(Member.lower_r)] = pair[1];
    assert(distinctSignals(roles, &group.nets));
    return group;
}

fn opposite(nl: *const Netlist, d: u32, net: u32) ?u32 {
    const ends = nl.path(EdgeId.from(d)) orelse return null;
    if (ends[0] == net) return ends[1];
    return if (ends[1] == net) ends[0] else null;
}

fn distinctSignals(roles: []const Role, nets: []const u32) bool {
    for (nets, 0..) |net, i| {
        if (roles[net].isRail() or std.mem.indexOfScalar(u32, nets[0..i], net) != null) return false;
    }
    return true;
}

fn expectLoop(text: []const u8, expected: bool, hidden: ?[]const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{text}, null);
    const roles = try @import("schematic.zig").guessRoles(a, &nl);
    const drawn = try a.alloc(bool, nl.graph.edgeCount());
    @memset(drawn, true);
    if (hidden) |name| drawn[nl.device(name).?.index()] = false;
    const group = find(&nl, roles, drawn, nl.device("l1").?.index());
    try std.testing.expectEqual(expected, group != null);
    if (group) |got| {
        const devices = [_][]const u8{ "min", "l1", "mout", "mlow", "cfly", "dloop", "cout", "cground", "rtop", "rbottom" };
        const nets = [_][]const u8{ "bus", "near_in", "near_out", "output", "bottom", "negative", "feedback" };
        for (got.devices, devices) |d, name| try std.testing.expectEqual(nl.device(name).?.index(), d);
        for (got.nets, nets) |net, name| try std.testing.expectEqual(nl.net(name).?.index(), net);
    }
}

test "power loops: semantic handles survive pin order, card order and duplicate body incidences" {
    // Oracle: the literal seven-net loop and named ten members, independent
    // of the selector's traversal. This also fixes every semantic array slot.
    const fixture =
        "Converter loop\n.model nch nmos\n.model pch pmos\n.model diode d\n" ++
        "L1 near_in near_out 1n\nMIN near_in gin bus vdd pch\nMLOW bottom glow bus vdd pch\n" ++
        "MOUT output gout near_out vdd pch\nMSHUNT near_out gshunt 0 0 nch\n" ++
        "CFLY near_in bottom 1p\nDLOOP negative bottom diode\nCOUT output negative 1p\n" ++
        "CGROUND output 0 1p\nRTOP output feedback 1k\nRBOTTOM feedback 0 1k\n";
    try expectLoop(fixture, true, null);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const changes = [_][2][]const u8{
        .{ "CFLY near_in bottom", "CFLY bottom near_in" },
        .{ "COUT output negative", "COUT negative output" },
        .{ "L1 near_in near_out", "L1 near_out near_in" },
        .{ "MIN near_in gin bus vdd", "MIN bus gin near_in near_in" },
        .{ "MLOW bottom glow bus vdd", "MLOW bus glow bottom bus" },
        .{ "MOUT output gout near_out vdd", "MOUT near_out gout output output" },
        .{ "RTOP output feedback", "RTOP feedback output" },
        .{ "RBOTTOM feedback 0", "RBOTTOM 0 feedback" },
    };
    var text: []const u8 = fixture;
    for (changes) |change| {
        text = try std.mem.replaceOwned(u8, a, text, change[0], change[1]);
        try expectLoop(text, true, null);
    }
    var lines: std.ArrayList([]const u8) = .empty;
    var split = std.mem.tokenizeScalar(u8, text, '\n');
    _ = split.next(); // Keep a title, then reverse every model/device card.
    while (split.next()) |line| try lines.append(a, line);
    std.mem.reverse([]const u8, lines.items);
    const reversed = try std.mem.concat(a, u8, &.{ "Reordered loop\n", try std.mem.join(a, "\n", lines.items), "\n" });
    try expectLoop(reversed, true, null);
}

test "power loops: incomplete and ambiguous electrical loops abstain before layout" {
    // Oracle: each mutation removes a required graph edge or introduces
    // a second complete choice. Forms are deliberately absent from find.
    const fixture =
        "Converter loop\n.model nch nmos\n.model pch pmos\n.model diode d\n" ++
        "L1 near_in near_out 1n\nMIN near_in gin bus vdd pch\nMLOW bottom glow bus vdd pch\n" ++
        "MOUT output gout near_out vdd pch\nMSHUNT near_out gshunt 0 0 nch\n" ++
        "CFLY near_in bottom 1p\nDLOOP negative bottom diode\nCOUT output negative 1p\n" ++
        "CGROUND output 0 1p\nRTOP output feedback 1k\nRBOTTOM feedback 0 1k\n";
    const cases = [_]struct { old: []const u8 = "", new: []const u8 = "", extra: []const u8 = "" }{
        .{ .extra = "CSECOND near_in bottom 1p\n" },
        .{ .extra = "CSECOND output negative 1p\n" },
        .{ .extra = "DSECOND negative bottom diode\n" },
        .{ .extra = "DSECOND bottom negative diode\n" },
        .{ .old = "DLOOP negative bottom", .new = "DLOOP bottom negative" },
        .{ .old = "negative", .new = "0" },
        .{ .old = "bottom", .new = "near_in" },
        .{ .extra = "MSECOND near_in gsecond bus vdd pch\n" },
        .{ .extra = "LSECOND near_in near_out 1n\n" },
        .{ .extra = "CSECOND output 0 1p\n" },
        .{ .extra = "RSECOND output feedback 1k\n" },
        .{ .extra = "RSECOND feedback 0 1k\n" },
        .{ .old = "CGROUND output 0 1p\n" },
        .{ .old = "RBOTTOM feedback 0 1k\n" },
        .{ .old = "MLOW bottom glow bus vdd pch", .new = "MLOW bottom glow bus vdd nch" },
        .{ .old = "glow", .new = "near_in" },
        .{ .old = "feedback", .new = "bottom" },
    };
    for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const changed = if (case.old.len == 0) fixture else try std.mem.replaceOwned(u8, a, fixture, case.old, case.new);
        try expectLoop(try std.mem.concat(a, u8, &.{ changed, case.extra }), false, null);
    }
    // Hidden components supply no drawn alternative; an explicit form
    // cannot do this because no form row enters the topology predicate.
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const extra = try std.mem.concat(arena.allocator(), u8, &.{ fixture, "CSECOND near_in bottom 1p\n" });
    try expectLoop(extra, true, "csecond");
    try expectLoop(fixture, false, "cfly");
}

test "power loops: otherwise complete loops sharing an output branch reject both groups" {
    // Oracle: two disjoint local loops share CGROUND/RTOP/RBOTTOM. Each
    // would qualify alone, so checking only each coil's immediate loop is
    // insufficient. Hiding the second coil removes that complete group.
    const text =
        "Shared loop output\n.model nch nmos\n.model pch pmos\n.model diode d\n" ++
        "L1 near_in near_out 1n\nMIN near_in gin bus vdd pch\nMLOW bottom glow bus vdd pch\n" ++
        "MOUT output gout near_out vdd pch\nMSHUNT near_out gshunt 0 0 nch\n" ++
        "CFLY near_in bottom 1p\nDLOOP negative bottom diode\nCOUT output negative 1p\n" ++
        "CGROUND output 0 1p\nRTOP output feedback 1k\nRBOTTOM feedback 0 1k\n" ++
        "L2 a2 b2 1n\nMI2 a2 gi2 bus2 vdd pch\nML2 bottom2 gl2 bus2 vdd pch\n" ++
        "MO2 output go2 b2 vdd pch\nMS2 b2 gs2 0 0 nch\n" ++
        "CF2 a2 bottom2 1p\nD2 neg2 bottom2 diode\nCO2 output neg2 1p\n";
    try expectLoop(text, false, null);
    try expectLoop(text, true, "l2");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{text}, null);
    const roles = try @import("schematic.zig").guessRoles(a, &nl);
    const drawn = try a.alloc(bool, nl.graph.edgeCount());
    @memset(drawn, true);
    try std.testing.expect(candidate(&nl, roles, drawn, nl.device("l1").?.index()) != null);
    try std.testing.expect(candidate(&nl, roles, drawn, nl.device("l2").?.index()) != null);
    try std.testing.expect(find(&nl, roles, drawn, nl.device("l2").?.index()) == null);
    // A scope-excluded second loop still shares raw members. Filtering
    // its added gate capacitor before overlap would admit L1 incorrectly.
    const extended = try std.mem.concat(a, u8, &.{ text, "CEXTRA go2 0 1p\n" });
    var with_branch = try netlist.parse(a, &.{extended}, null);
    const branch_roles = try @import("schematic.zig").guessRoles(a, &with_branch);
    const branch_drawn = try a.alloc(bool, with_branch.graph.edgeCount());
    @memset(branch_drawn, true);
    try std.testing.expect(candidate(&with_branch, branch_roles, branch_drawn, with_branch.device("l2").?.index()) != null);
    try expectLoop(extended, false, null);
    // Reversing only the competing loop's diode is another scope filter,
    // not permission to hide its shared output members from L1.
    const reversed = try std.mem.replaceOwned(u8, a, text, "D2 neg2 bottom2 diode", "D2 bottom2 neg2 diode");
    try expectLoop(reversed, false, null);
}

test "power loops: unobserved grounded gate and coil branches exclude the whole pattern" {
    // Scope oracle: the source inventory has no grounded caps on these
    // four nets. Both main gates and both coil ends are explicit cases;
    // capacitor card order cannot change admission. This is not a claim
    // that any extended circuit is electrically invalid.
    const fixture =
        "Converter loop\n.model nch nmos\n.model pch pmos\n.model diode d\n" ++
        "L1 near_in near_out 1n\nMIN near_in gin bus vdd pch\nMLOW bottom glow bus vdd pch\n" ++
        "MOUT output gout near_out vdd pch\nMSHUNT near_out gshunt 0 0 nch\n" ++
        "CFLY near_in bottom 1p\nDLOOP negative bottom diode\nCOUT output negative 1p\n" ++
        "CGROUND output 0 1p\nRTOP output feedback 1k\nRBOTTOM feedback 0 1k\n";
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "gin", "gout", "near_in", "near_out" }) |net| {
        for ([_]bool{ false, true }) |reversed| {
            const ends = if (reversed) [2][]const u8{ "0", net } else [2][]const u8{ net, "0" };
            const text = try std.fmt.allocPrint(a, "{s}CEXTRA {s} {s} 1p\n", .{ fixture, ends[0], ends[1] });
            try expectLoop(text, false, null);
            // The input bus already requires a gate-only MIN control,
            // even for hidden devices. Preserve that older contract.
            if (!std.mem.eql(u8, net, "gin")) try expectLoop(text, true, "cextra");
        }
        if (!std.mem.eql(u8, net, "gin")) {
            const floating = try std.fmt.allocPrint(a, "{s}CEXTRA {s} other 1p\n", .{ fixture, net });
            try expectLoop(floating, true, null);
        }
    }
}
