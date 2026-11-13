//! Certified converter paths and their actual terminals → coordinate orders
//! supplied to the generic compactor. No circuit state survives this pass.
//!
//! Human Rules:
//! - power_compact.1 (habit, bounded) The whole channel of each upright
//!   grounded shunt or active gate driver stays below its flat main path.
//!   All 365 selected shunts and 92 drivers have both D/S below that path
//!   in the AnalogGenie source drawings (power_paths.5). Device centers
//!   alone let AG1356:M12.S rise to the main row. Preserve the actual upper
//!   D/S terminal's order, including caller-supplied shifted/tall symbols.
//! - power_compact.2 (habit, bounded) A unique grounded shunt's signal
//!   terminal stays between its connected main and coil terminals. All
//!   353 unique source channels lie in that inclusive interval; AG1418:MN2
//!   is level with the coil's terminal. Each initially strict half keeps
//!   its order; equality already shares one compaction track.
//! - power_compact.3 (invariant) Only relations true before compaction
//!   enter the graph. A turned/offset main path without one horizontal
//!   channel row, an explicit `at` participant, or an already external
//!   shunt does not acquire these orders. Caller geometry has precedence.
//!
//! Data: existing netlist/CSR, skeleton and schematic rows in; temporary
//! x/y pairs of i32 coordinates out. Both pair fields are read together.
//! A group table has one slot per drawn coil; x has four slots per group,
//! y one per incident candidate on the coil ends and main gates. Each is
//! sized once, freed on return, and collected serially in graph order.
//! The compactor owns coordinate writes; this pass only submits orders.
//!
//! Contents:
//! - `pub fn squeeze(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, axis2: ?i32) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const canvas = @import("canvas.zig");
const compact = @import("compact.zig");
const power_paths = @import("power_paths.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Schematic = sch.Schematic;
const Skeleton = skeleton.Skeleton;
const Lengths = canvas.Lengths;
const Pt = library.Pt;

/// Compacts a wired drawing while preserving its existing converter
/// terminal orders. Asserts the skeleton and `ats` cover every device and
/// `s` has its settled symbols and coordinates. Temporary storage belongs
/// to this call; allocation failure may leave x compacted as in `compact`.
pub fn squeeze(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, axis2: ?i32) Allocator.Error!void {
    const c = &nl.graph;
    assert(ats.len == c.edgeCount());
    assert(sk.drawn.len == c.edgeCount());
    assert(sk.form.len == c.edgeCount());
    var coil_capacity: usize = 0;
    for (c.edges.items(.kind), sk.drawn) |kind, drawn| {
        coil_capacity += @intFromBool(drawn and kind == .inductor);
    }
    const groups = try gpa.alloc([3]u32, coil_capacity);
    defer gpa.free(groups);
    var count: usize = 0;
    var y_capacity: usize = 0;
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .inductor) continue;
        const members = power_paths.series(nl, s.roles, sk.drawn, sk.form, @intCast(d)) orelse continue;
        if (ats[members[0]] != null or ats[members[1]] != null or ats[members[2]] != null) continue;
        groups[count] = members;
        count += 1;
        for (controlNets(nl, members)) |net| y_capacity += c.incident(VertexId.from(net)).len;
    }
    assert(count <= coil_capacity);
    const x_capacity = 4 * count;
    const xs = try gpa.alloc([2]i32, x_capacity);
    defer gpa.free(xs);
    const ys = try gpa.alloc([2]i32, y_capacity);
    defer gpa.free(ys);
    var nx: usize = 0;
    var ny: usize = 0;
    for (groups[0..count]) |members| {
        const coil = channel(s, nl, members[1]) orelse continue;
        const first = channel(s, nl, members[0]) orelse continue;
        const last = channel(s, nl, members[2]) orelse continue;
        const row = coil[0].y;
        if (coil[1].y != row or first[0].y != row or first[1].y != row or last[0].y != row or last[1].y != row) continue;
        for (controlNets(nl, members)) |net| for (c.incident(VertexId.from(net))) |e| {
            const d = e.index();
            if (ats[d] != null or !power_paths.control(nl, s.roles, sk.drawn, sk.form, members, d)) continue;
            const ends = channel(s, nl, d) orelse continue;
            if (ends[0].x != ends[1].x) continue;
            const upper = @min(ends[0].y, ends[1].y);
            if (upper <= row) continue;
            ys[ny] = .{ row, upper };
            ny += 1;
        };
        for (nl.path(EdgeId.from(members[1])).?, [_][2]Pt{ first, last }, 0..) |net, main, side| {
            const d = power_paths.groundShunt(nl, s.roles, sk.drawn, sk.form, net) orelse continue;
            if (ats[d] != null) continue;
            const shunt = channel(s, nl, d) orelse continue;
            if (shunt[0].x != shunt[1].x) continue;
            const main_ends = nl.path(EdgeId.from(members[2 * side])).?;
            const a = main[@intFromBool(main_ends[0] != net)].x;
            const b = coil[side].x;
            const x = shunt[0].x;
            const lo = @min(a, b);
            const hi = @max(a, b);
            if (x < lo or x > hi) continue;
            if (lo < x) {
                xs[nx] = .{ lo, x };
                nx += 1;
            }
            if (x < hi) {
                xs[nx] = .{ x, hi };
                nx += 1;
            }
        }
    }
    assert(nx <= x_capacity);
    assert(ny <= y_capacity);
    try compact.squeeze(gpa, s, len, axis2, .{ xs[0..nx], ys[0..ny] });
}

// ---- private ----

fn controlNets(nl: *const Netlist, members: [3]u32) [4]u32 {
    const ends = nl.path(EdgeId.from(members[1])).?;
    return .{ ends[0], ends[1], nl.graph.members(EdgeId.from(members[0]))[1].index(), nl.graph.members(EdgeId.from(members[2]))[1].index() };
}

fn channel(s: *const Schematic, nl: *const Netlist, d: u32) ?[2]Pt {
    assert(d < s.devices.len);
    assert(d < nl.graph.edgeCount());
    const path = device.of(nl.graph.edges.items(.kind)[d]).path.?;
    const info = s.devices.slice();
    const class = s.lib.at(info.items(.class)[d]);
    if (class.terminals.len <= path[1] or s.device_pin_count[d] <= path[1]) return null;
    if (class.terminals[path[0]].hidden or class.terminals[path[1]].hidden) return null;
    const node = s.deviceNode(d) orelse return null;
    const origin = Pt.round(s.xy[node]).sub(info.items(.grid)[d]);
    const orient = info.items(.orient)[d];
    return .{ origin.add(orient.apply(class.terminals[path[0]].at)), origin.add(orient.apply(class.terminals[path[1]].at)) };
}
