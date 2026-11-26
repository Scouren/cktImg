//! Actual paired block input frame -> one five-passive proposal and orders.
//!
//! Human Rules:
//! - block_input_place.1 (bounded observation) Source X2/X3 capacitors
//!   align with their own INP/INN tips; transverse bias resistors share
//!   two rows beyond that input span. R(INP) lies farther outward than
//!   R(INN), both between input and cap planes. The actual block never
//!   turns; its named input frame defines both axes. Its unique bias choke
//!   sits outward of R(INP), beyond the R-bias row, parallel to the input
//!   leads; the far tip points outward. docs/research/block-input-chokes.md.
//!   `propose`
//! - block_input_place.2 (choice) One nearest full-body-spaced candidate,
//!   using the observed semantic INN side. All five actual passive frames
//!   must support it; no larger search or routing exception. Caller owns
//!   all geometry changes and restores rows on rejection. `propose`
//! - block_input_place.3 (invariant) Reanchored passive tracks preserve
//!   actual input rows and paired bias rows through compaction. Ten
//!   strict coordinate pairs per group retain the source order. `orders`
//!
//! Data: borrowed cold groups and actual classes in; fixed five-point
//! proposal or immediate order slices out. No allocation or retained state.
//! Coordinates use i64 intermediates and checked i32 narrowing. This is
//! cold scalar geometry, with no speed or hot-loop abstraction claim.
//!
//! Contents: rooms, propose, orders; private actual-frame helpers.

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const input = @import("block_input_rc.zig");
const actual_lead = @import("actual_lead.zig");
const actual_anchor = @import("actual_anchor.zig");
const Room = @import("lattice_geometry.zig").Room;
const Lengths = @import("canvas.zig").Lengths;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Pt = library.Pt;
const Side = library.Side;
const Group = input.Group;

/// Prepares one full five-passive envelope relative to each read-only
/// block grid, retaining supported groups. Every temporary row is restored.
pub fn rooms(s: *sch.Schematic, nl: *const Netlist, len: Lengths, batch: *input.Batch) []const Room {
    assert(batch.room.len >= batch.groups.items.len);
    assert(s.devices.len == nl.graph.edgeCount());
    var kept: usize = 0;
    for (batch.groups.items) |group| {
        const edges = input.members(group);
        var before: [5]sch.DeviceInfo = undefined;
        for (edges, &before) |edge, *row| row.* = s.devices.get(edge.index());
        defer for (edges, before) |edge, row| s.devices.set(edge.index(), row);
        const points = propose(s, nl, len, group) orelse continue;
        var bounds = s.boxAt(edges[0].index(), points[0]);
        for (edges[1..], points[1..]) |edge, point| bounds = bounds.merge(s.boxAt(edge.index(), point));
        batch.room[kept] = .{ .anchor = group.block, .bounds = bounds.grow(len.clearance) };
        batch.groups.items[kept] = group;
        kept += 1;
    }
    batch.groups.items = batch.groups.items[0..kept];
    return batch.room[0..kept];
}

/// Settles only the five passive rows and returns their nearest positions
/// relative to the unchanged block grid. The caller must restore full rows
/// on null or scene collision; no coordinate or allocation writes occur.
pub fn propose(s: *sch.Schematic, nl: *const Netlist, len: Lengths, group: Group) ?[5]Pt {
    assert(s.devices.len == nl.graph.edgeCount());
    assert(group.block.index() < s.devices.len);
    const u = actual_lead.leadSide(s, group.block.index(), group.pins[0]) orelse return null;
    if (actual_lead.leadSide(s, group.block.index(), group.pins[1]) != u) return null;
    const a, const b = .{ tip(s, group.block, group.pins[0]), tip(s, group.block, group.pins[1]) };
    if (project(a, u) != project(b, u) or a.eql(b)) return null;
    const w = Side.of(b.sub(a)) orelse return null;
    if (!u.perpendicular(w)) return null;
    const edges = input.members(group);
    for (edges, 0..) |edge, i| {
        const first = input.nearPin(nl, group, i);
        const offset = if (i < 2) along(w, project(if (i == 0) a else b, w)) orelse return null else Pt.zero;
        if (!turn(s, nl, edge, first, if (i < 2 or i == 4) u else w, offset)) return null;
    }
    // Shared planes are actual lead constraints, including custom lengths.
    if (project(tip(s, edges[0], 1-input.nearPin(nl, group, 0)), u) != project(tip(s, edges[1], 1-input.nearPin(nl, group, 1)), u)) return null;
    if (project(tip(s, edges[2], 1-input.nearPin(nl, group, 2)), w) != project(tip(s, edges[3], 1-input.nearPin(nl, group, 3)), w)) return null;
    var boxes: [5]library.Rect = undefined;
    for (edges, &boxes) |edge, *box| box.* = s.boxAt(edge.index(), .zero);
    const gap: i64 = @max(len.stack, len.clearance + 1);
    const inner = project(a, u) + gap - low(boxes[3], u);
    const outer = inner + high(boxes[3], u) + gap - low(boxes[2], u);
    const caps = outer + high(boxes[2], u) + gap - @min(low(boxes[0], u), low(boxes[1], u));
    const branch = @max(high(boxes[0], w), high(boxes[1], w)) + gap - @min(low(boxes[2], w), low(boxes[3], w));
    const choke_out = outer + high(boxes[2], u) + gap - low(boxes[4], u);
    const choke_row = branch + @max(high(boxes[2], w), high(boxes[3], w)) + gap - low(boxes[4], w);
    return .{
        along(u, caps) orelse return null,
        along(u, caps) orelse return null,
        combine(u, outer, w, branch) orelse return null,
        combine(u, inner, w, branch) orelse return null,
        combine(u, choke_out, w, choke_row) orelse return null,
    };
}

/// Ten strict source-coordinate relations per successful group. All
/// shared actual rows/planes already use equal grid tracks. Storage is
/// twenty pairs per group, split into two bounded axis slices.
pub fn orders(s: *const sch.Schematic, nl: *const Netlist, batch: *input.Batch) [2][]const [2]i32 {
    assert(s.xy.len == s.nodes.len);
    const capacity = input.order_pair_capacity * batch.groups.items.len;
    assert(batch.coordinates.len >= 2 * capacity);
    const storage = [2][][2]i32{ batch.coordinates[0..capacity], batch.coordinates[capacity..] };
    var counts: [2]usize = .{ 0, 0 };
    for (batch.groups.items) |group| {
        var points: [12]Pt = undefined;
        points[0] = current(s, group.block, group.pins[0]);
        points[1] = current(s, group.block, group.pins[1]);
        for (input.members(group), 0..) |edge, i| {
            const first = input.nearPin(nl, group, i);
            points[2+2*i] = current(s, edge, first);
            points[3+2*i] = current(s, edge, 1-first);
        }
        const u = actual_lead.leadSide(s, group.block.index(), group.pins[0]).?;
        const w = Side.of(points[1].sub(points[0])).?;
        for ([_][2]usize{ .{0,8}, .{8,6}, .{6,2}, .{2,3}, .{6,10}, .{10,11} }) |ij| keep(storage, &counts, u, points[ij[0]], points[ij[1]]);
        for ([_][2]usize{ .{0,1}, .{1,6}, .{6,7}, .{7,10} }) |ij| keep(storage, &counts, w, points[ij[0]], points[ij[1]]);
    }
    return .{ storage[0][0..counts[0]], storage[1][0..counts[1]] };
}

// ---- private ----

fn turn(s: *sch.Schematic, nl: *const Netlist, edge: EdgeId, first: u1, forward: Side, offset: Pt) bool {
    const class = s.lib.at(s.devices.items(.class)[edge.index()]);
    if (class.terminals.len != 2) return false;
    for (class.terminals) |terminal| if (terminal.hidden or terminal.ground_ref) return false;
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{false,false}, .{true,false}, .{false,true}, .{true,true} }) |flips| {
        s.devices.items(.orientation)[edge.index()] = form;
        s.devices.items(.flip_x)[edge.index()] = flips[0];
        s.devices.items(.flip_y)[edge.index()] = flips[1];
        sch.settleDevice(s, &nl.graph, edge.index());
        const a, const b = .{ tip(s, edge, first), tip(s, edge, 1-first) };
        if ((a.x != b.x and a.y != b.y) or Side.of(b.sub(a)) != forward or s.pinSide(edge.index(), first) != forward.opposite() or s.pinSide(edge.index(), 1-first) != forward) continue;
        actual_anchor.move(s, nl, edge.index(), a.sub(offset));
        return actual_anchor.representable(s, nl, edge.index());
    };
    return false;
}

fn tip(s: *const sch.Schematic, edge: EdgeId, pin: usize) Pt {
    const row = s.devices.get(edge.index());
    return row.orient.apply(s.lib.at(row.class).terminals[pin].at).sub(row.grid);
}
fn current(s: *const sch.Schematic, edge: EdgeId, pin: usize) Pt { return Pt.round(s.xy[s.deviceNode(edge.index()).?]).add(tip(s, edge, pin)); }
fn project(p: Pt, side: Side) i64 { const v = side.unit(); return @as(i64,p.x)*v.x + @as(i64,p.y)*v.y; }
fn low(r: library.Rect, side: Side) i64 { return @min(project(r.min, side), project(r.max, side)); }
fn high(r: library.Rect, side: Side) i64 { return @max(project(r.min, side), project(r.max, side)); }
fn along(side: Side, distance: i64) ?Pt { return combine(side, distance, if (side.isHorizontal()) .up else .left, 0); }
fn combine(u: Side, a: i64, w: Side, b: i64) ?Pt {
    const v, const t = .{ u.unit(), w.unit() };
    const x, const y = .{ v.x*a+t.x*b, v.y*a+t.y*b };
    if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or y < std.math.minInt(i32) or y > std.math.maxInt(i32)) return null;
    return .{ .x = @intCast(x), .y = @intCast(y) };
}
fn keep(storage: [2][][2]i32, count: *[2]usize, side: Side, a: Pt, b: Pt) void {
    assert(project(a, side) < project(b, side));
    const axis: usize = @intFromBool(!side.isHorizontal());
    assert(count[axis] < storage[axis].len);
    storage[axis][count[axis]] = if (axis == 0) .{ @min(a.x,b.x), @max(a.x,b.x) } else .{ @min(a.y,b.y), @max(a.y,b.y) };
    count[axis] += 1;
}
