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
//! - power_compact.4 (habit, bounded) A unique upright outer reservoir's
//!   signal stays beyond the main switch away from the coil, and at or
//!   below its channel. Preserve each initially true actual-terminal
//!   relation; equality already shares a track. All 359 source reservoirs
//!   agree, including two level signals. Shifted caller symbol frames
//!   require the transformed signal pin, not the device center.
//! - power_compact.5 (habit, bounded) A selected flying-capacitor loop
//!   retains its actual cap interval, downward drops, lower return and
//!   divider orders. All 145 source groups obey these inequalities.
//!   Preserve only initially true relations; explicit origins and turned
//!   or hidden channel leads abstain. When both diode ends already fit
//!   between the cap columns, retaining those orders also keeps its center
//!   inside. No exact lower-row equality or output-branch order is added.
//! - power_compact.6 (invariant) Other geometry owners may append initially
//!   true actual-coordinate orders to the same pass. Bias peers and coil
//!   tanks use this
//!   seam; this owner does not discover or place those groups. Empty
//!   extra slices preserve the converter-only requests.
//!
//! Data: existing netlist/CSR, skeleton and schematic rows in; temporary
//! x/y pairs of i32 coordinates out. Both pair fields are read together.
//! A group table has one slot per drawn coil; x has thirteen slots per group,
//! y twelve per group plus each coil-end/main-gate incident candidate. Each is
//! sized once, freed on return, and collected serially in graph order.
//! The compactor owns coordinate writes; this pass only submits orders.
//!
//! Contents:
//! - `pub fn deviceBoxes(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) Allocator.Error![]library.Rect`
//! - `pub fn clear(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) Allocator.Error!bool`
//! - `pub fn drawnAxis2(gpa: Allocator, s: *const Schematic, sk: *const Skeleton) !?i32`
//! - `pub fn squeeze(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, axis2: ?i32, extra: []const [2][]const [2]i32) Allocator.Error!void`

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
const power_loops = @import("power_loops.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Schematic = sch.Schematic;
const Skeleton = skeleton.Skeleton;
const Lengths = canvas.Lengths;
const Pt = library.Pt;

/// Tests every drawn device box after compaction. Allocation and overlap
/// order match the drawing's original check; caller decides whether to
/// retain the squeezed coordinates. Does not mutate the schematic.
pub fn clear(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) Allocator.Error!bool {
    const boxes = try deviceBoxes(gpa, s, nl, sk);
    defer gpa.free(boxes);
    return clear: for (boxes, 0..) |a, i| {
        for (boxes[i + 1 ..]) |b| if (a.intersects(b)) break :clear false;
    } else true;
}

/// Compacts a wired drawing while preserving its existing converter
/// terminal orders. Asserts the skeleton and `ats` cover every device and
/// `s` has its settled symbols and coordinates. `extra` borrows initially
/// strict actual-coordinate orders from other geometry owners. Temporary storage belongs
/// to this call; allocation failure may leave x compacted as in `compact`.
pub fn squeeze(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, axis2: ?i32, extra: []const [2][]const [2]i32) Allocator.Error!void {
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
    var extra_capacity: [2]usize = .{ 0, 0 };
    for (extra) |owner| for (owner, &extra_capacity) |orders, *capacity| {
        capacity.* += orders.len;
    };
    var y_capacity: usize = extra_capacity[1];
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .inductor) continue;
        const members = power_paths.series(nl, s.roles, sk.drawn, sk.form, @intCast(d)) orelse continue;
        if (ats[members[0]] != null or ats[members[1]] != null or ats[members[2]] != null) continue;
        groups[count] = members;
        count += 1;
        y_capacity += 12;
        for (controlNets(nl, members)) |net| y_capacity += c.incident(VertexId.from(net)).len;
    }
    assert(count <= coil_capacity);
    const x_capacity = 13 * count + extra_capacity[0];
    const xs = try gpa.alloc([2]i32, x_capacity);
    defer gpa.free(xs);
    const ys = try gpa.alloc([2]i32, y_capacity);
    defer gpa.free(ys);
    var nx: usize = 0;
    var ny: usize = 0;
    for (extra) |owner| {
        @memcpy(xs[nx..][0..owner[0].len], owner[0]);
        @memcpy(ys[ny..][0..owner[1].len], owner[1]);
        nx += owner[0].len;
        ny += owner[1].len;
    }
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
            const main_ends = nl.path(EdgeId.from(members[2 * side])).?;
            if (power_paths.reservoir(nl, s.roles, sk.drawn, sk.form, members[2 * side], net)) |cap| reservoir: {
                if (ats[cap] != null) break :reservoir;
                const ends = channel(s, nl, cap) orelse break :reservoir;
                const signal_end = @intFromBool(s.roles[nl.path(EdgeId.from(cap)).?[0]] == .sink);
                const signal = ends[signal_end];
                const ground = ends[1 - signal_end];
                if (signal.x != ground.x or signal.y >= ground.y) break :reservoir;
                if (row < signal.y) {
                    ys[ny] = .{ row, signal.y };
                    ny += 1;
                }
                const outer = main[@intFromBool(main_ends[0] == net)].x;
                if (signal.x < outer and outer < coil[side].x) {
                    xs[nx] = .{ signal.x, outer };
                    nx += 1;
                } else if (coil[side].x < outer and outer < signal.x) {
                    xs[nx] = .{ outer, signal.x };
                    nx += 1;
                }
            }
            const d = power_paths.groundShunt(nl, s.roles, sk.drawn, sk.form, net) orelse continue;
            if (ats[d] != null) continue;
            const shunt = channel(s, nl, d) orelse continue;
            if (shunt[0].x != shunt[1].x) continue;
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
        const loop = power_loops.find(nl, s.roles, sk.drawn, members[1]) orelse continue;
        const d = loop.devices;
        const nets = loop.nets;
        var ends: [10][2]Pt = undefined;
        const compatible = for (d, 0..) |part, i| {
            if (ats[part] != null) break false;
            ends[i] = channel(s, nl, part) orelse break false;
            const vertical = i == 4 or i >= 6;
            if (vertical and ends[i][0].x != ends[i][1].x) break false;
            if (!vertical and ends[i][0].y != ends[i][1].y) break false;
        } else true;
        if (!compatible) continue;
        const near = ends[0][@intFromBool(nl.path(EdgeId.from(d[0])).?[0] != nets[1])];
        const coil_in = ends[1][@intFromBool(nl.path(EdgeId.from(d[1])).?[0] != nets[1])];
        const outer = ends[2][@intFromBool(nl.path(EdgeId.from(d[2])).?[0] != nets[3])];
        const bottom = ends[3][@intFromBool(nl.path(EdgeId.from(d[3])).?[0] != nets[4])];
        const fly_up = @intFromBool(nl.path(EdgeId.from(d[4])).?[0] != nets[1]);
        const out_up = @intFromBool(nl.path(EdgeId.from(d[6])).?[0] != nets[3]);
        const upper_r = @intFromBool(nl.path(EdgeId.from(d[8])).?[0] != nets[3]);
        const lower_r = @intFromBool(nl.path(EdgeId.from(d[9])).?[0] != nets[6]);
        const fly = [2]Pt{ ends[4][fly_up], ends[4][1 - fly_up] };
        const out = [2]Pt{ ends[6][out_up], ends[6][1 - out_up] };
        const divider = [4]Pt{ ends[8][upper_r], ends[8][1 - upper_r], ends[9][lower_r], ends[9][1 - lower_r] };
        if (fly[0].y >= fly[1].y or out[0].y >= out[1].y or divider[0].y >= divider[1].y or divider[2].y >= divider[3].y) continue;
        const toward_right = outer.x > near.x;
        for ([_][2]i32{
            .{ near.x, fly[0].x },       .{ fly[0].x, coil_in.x },
            .{ bottom.x, fly[0].x },     .{ outer.x, out[0].x },
            .{ outer.x, divider[0].x },  .{ fly[0].x, ends[5][1].x },
            .{ ends[5][0].x, out[0].x },
        }) |pair| {
            const a = pair[@intFromBool(!toward_right)];
            const b = pair[@intFromBool(toward_right)];
            if (a >= b) continue;
            xs[nx] = .{ a, b };
            nx += 1;
        }
        for ([_][2]i32{
            .{ row, fly[0].y },              .{ fly[1].y, bottom.y },
            .{ row, out[0].y },              .{ out[1].y, ends[5][0].y },
            .{ fly[1].y, ends[5][0].y },     .{ divider[1].y, divider[2].y },
            .{ divider[3].y, ends[5][0].y }, .{ row, bottom.y },
            .{ row, ends[5][0].y },          .{ row, divider[0].y },
        }) |pair| {
            if (pair[0] >= pair[1]) continue;
            ys[ny] = pair;
            ny += 1;
        }
    }
    assert(nx <= x_capacity);
    assert(ny <= y_capacity);
    try compact.squeeze(gpa, s, len, axis2, .{ xs[0..nx], ys[0..ny] });
}

/// Twice the x the skeleton's mirrored columns stand about in the drawing,
/// when every pair of them agrees (an `at` line may move one off it); else
/// null. The skeleton mirrors a pair's columns even where the circuit has
/// no symmetry of its own (a mirror load), which sketch's `drawnMirror` asks for.
pub fn drawnAxis2(gpa: Allocator, s: *const Schematic, sk: *const Skeleton) !?i32 {
    assert(sk.drawn.len == s.devices.len and sk.x.len == sk.drawn.len);
    assert(s.xy.len == s.nodes.len);
    const a2 = sk.axis2 orelse return null;
    const x = try gpa.alloc(?i32, sk.drawn.len);
    defer gpa.free(x);
    for (x, 0..) |*v, d| v.* = if (sk.drawn[d]) Pt.round(s.xy[s.deviceNode(@intCast(d)).?]).x else null;
    var axis2: ?i32 = null;
    for (x, 0..) |xd, d| for (x[d..], d..) |xe, e| {
        if (xd == null or xe == null or sk.x[d] + sk.x[e] != a2) continue;
        if (axis2 != null and axis2.? != xd.? + xe.?) return null;
        axis2 = xd.? + xe.?;
    };
    return axis2;
}

/// Allocates the current drawn-device boxes in graph order. Both drawing
/// and post-compaction overlap checks consume this same geometry. The
/// caller frees the returned slice; allocation failure leaves input intact.
pub fn deviceBoxes(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) Allocator.Error![]library.Rect {
    var out: std.ArrayList(library.Rect) = .empty;
    errdefer out.deinit(gpa);
    for (0..nl.graph.edgeCount()) |d| {
        if (!sk.drawn[d]) continue;
        const r = s.boxAt(d, Pt.round(s.xy[s.deviceNode(@intCast(d)).?]));
        assert(r.min.x <= r.max.x and r.min.y <= r.max.y);
        try out.append(gpa, r);
    }
    assert(out.items.len <= nl.graph.edgeCount());
    return out.toOwnedSlice(gpa);
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
