//! Complete four-MOS reflected parents whose two internal outputs each drive one external gate.
//!
//! Contents:
//! - `pub const Pair`, `pub fn eligible(arena: std.mem.Allocator, ctx: context.Context) ![]const Pair`
//! - `pub fn collect(arena:std.mem.Allocator,ctx:context.Context,p:local.Parents) std.mem.Allocator.Error![]const parts.Pair`

const std = @import("std");
const context = @import("parent_context.zig");
const local = @import("local_parents.zig");
const netlist = @import("netlist.zig");
const parts = @import("parent_parts.zig");

/// Each output identifies its two local drains and the outside gate by exact graph handle.
pub const Pair = parts.Pair;

/// Filters the raw collector's cyclic contrary before any routing requests are published.
pub fn eligible(arena: std.mem.Allocator, ctx: context.Context) ![]const Pair {
    const parents = try local.collect(arena, ctx, .{});
    if (parents.disposition != .raw_multigroup_candidate) return &.{};
    return collect(arena, ctx, parents);
}

/// Returns complete raw tuples, including cyclic contraries. Each net has
/// exactly P.D, N.D and a single external G in the complete raw graph.
pub fn collect(arena: std.mem.Allocator, ctx: context.Context, p: local.Parents) std.mem.Allocator.Error![]const parts.Pair {
    if (p.group_count < 2 or p.search == null or p.search.?.state != .complete_unique) return &.{};
    const m = p.search.?.first.?;
    const graph = &ctx.nl.graph;
    var found: std.ArrayList(parts.Pair) = .empty;
    for (0..p.group_count) |owner| {
        var members: [4]u32 = undefined;
        var n: usize = 0;
        for (p.groups, 0..) |group, d| if (group == owner) {
            if (n < 4) members[n] = @intCast(d);
            n += 1;
        };
        if (n != 4) continue;
        var pair: parts.Pair = undefined;
        var count: usize = 0;
        for (members) |d| {
            if (p.groups[m.devices[d]] != owner) break;
            const pins = graph.members(netlist.EdgeId.from(d));
            if (pins[2] != pins[3] or (ctx.kind[pins[2].index()] != .sink and ctx.kind[pins[2].index()] != .supply)) break;
            if (ctx.kind[pins[2].index()] != .supply) continue;
            if (count == 2) break;
            pair[count] = output(ctx, p, owner, d) orelse break;
            count += 1;
        } else {
            if (count != 2) continue;
            const a = pair[0];
            const b = pair[1];
            if (a.net == b.net or m.nets[a.net] != b.net or m.devices[a.pmos] != b.pmos or m.devices[a.nmos] != b.nmos or m.devices[a.gate] != b.gate or p.groups[a.gate] != p.groups[b.gate]) continue;
            if (std.mem.lessThan(u8, graph.vertices.items(.name)[b.net], graph.vertices.items(.name)[a.net])) std.mem.swap(parts.Output, &pair[0], &pair[1]);
            try found.append(arena, pair);
        }
    }
    return found.items;
}

// ---- private ----
fn output(ctx: context.Context, p: local.Parents, owner: usize, pmos: u32) ?parts.Output {
    const graph = &ctx.nl.graph;
    const net = graph.members(netlist.EdgeId.from(pmos))[0];
    if (ctx.kind[net.index()] != .internal or graph.incident(net).len != 3) return null;
    var nmos: ?u32 = null;
    var gate: ?u32 = null;
    for (graph.incident(net)) |e| {
        const d = e.index();
        if (d == pmos) continue;
        const pins = graph.members(e);
        if (p.groups[d] == owner and pins[0] == net and ctx.kind[pins[3].index()] == .sink and pins[2] == pins[3]) nmos = d else if (p.groups[d] != owner and pins[1] == net) gate = d else return null;
    }
    return .{ .net = net.index(), .pmos = pmos, .nmos = nmos orelse return null, .gate = gate orelse return null };
}
