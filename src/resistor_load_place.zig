//! Complete six/twelve-device load owners -> actual frames and strict orders.
//!
//! Human Rules:
//! - resistor_load_place.1 (bounded observation) A diode PMOS stands over
//!   two upright resistors, each aligned with its outward-gated input
//!   drain. The common grounded tail is below both sources. Three source
//!   groups certify these relations, nine straight corridors and clear
//!   nominal group envelopes. The tail tree may bend. `attempt`
//! - resistor_load_place.2 (bounded priority) The linked two-stage case
//!   has separate local axes, matching semantic rows and both tail gates
//!   left. This refines the automatic tail bank, retaining graph mates
//!   and caller classes. It never requests a wire between the bias gates.
//! - resistor_load_place.3 (choice) One body-spaced candidate per owner,
//!   centered at the old input-pair midpoint and above all foreign bodies.
//!   Eight rigid poses per member; unsupported frames/collisions restore
//!   all six/twelve rows before any position write. No source distances.
//! - resistor_load_place.4 (invariant) Actual lead anchors share tracks;
//!   preserve initially strict source orders and the foreign-body boundary
//!   through the existing one-pass compactor. No wire policy changes.
//! - resistor_load_place.5 (choice) Only the linked twelve-member owner
//!   leaves at least two tap lengths plus clearance between each resistor
//!   output and its input drain. The source has two distinct branch rows;
//!   this configured spacing is a bounded candidate, not a universal routing
//!   guarantee. Strict compact orders do not retain a numeric distance.
//!
//! Data: cold 24/48-byte owners, actual classes and coordinates in; at most
//! twelve poses/positions out. Fixed stack scratch, no allocation. Forty
//! caller-owned i32 pairs per stage bound requests (twenty per axis).
//! Placement is canonical/sequential because owners share collision room.
//! No routing-loop abstraction, retained state or speed claim.
//!
//! Contents: place, orders; private actual-frame transaction helpers.

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const loads = @import("resistor_loads.zig");
const actual_anchor = @import("actual_anchor.zig");
const Lengths = @import("canvas.zig").Lengths;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Pt = library.Pt;
const Rect = library.Rect;
const Side = library.Side;
const Group = loads.Group;

/// Attempts one complete owner at a time, retaining successful owners.
/// Every slice spans the existing device table. Failure restores all rows
/// and coordinates; the caller retains/frees Batch storage. No allocation.
pub fn place(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, batch: *loads.Batch) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var count: usize = 0;
    for (batch.singles.items) |group| {
        if (!attempt(s, nl, sk, ats, len, at, &.{group})) continue;
        batch.singles.items[count] = group;
        count += 1;
    }
    batch.singles.items = batch.singles.items[0..count];
    count = 0;
    for (batch.pairs.items) |pair| {
        if (!attempt(s, nl, sk, ats, len, at, &pair)) continue;
        batch.pairs.items[count] = pair;
        count += 1;
    }
    batch.pairs.items = batch.pairs.items[0..count];
}

/// Records source lead orders and the successful envelope's foreign-body
/// boundary from the wired scaffold. Requires forty storage slots per
/// successful stage; equal actual anchors already share compact tracks.
pub fn orders(s: *const sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, batch: *loads.Batch) [2][]const [2]i32 {
    const capacity = 20 * (batch.singles.items.len + 2 * batch.pairs.items.len);
    assert(batch.coordinates.len >= 2 * capacity);
    assert(s.xy.len == s.nodes.len);
    var count: [2]usize = .{ 0, 0 };
    const storage = [2][][2]i32{ batch.coordinates[0..capacity], batch.coordinates[capacity..] };
    for (batch.singles.items) |group| record(s, nl, sk, &.{group}, storage, &count);
    for (batch.pairs.items) |pair| record(s, nl, sk, &pair, storage, &count);
    return .{ storage[0][0..count[0]], storage[1][0..count[1]] };
}

// ---- private ----

fn first(nl: *const Netlist, group: Group, member: usize) usize {
    if (member != 1 and member != 2) return 0;
    return @intFromBool(nl.graph.members(group[member])[0] != nl.graph.members(group[0])[0]);
}
fn tip(s: *const sch.Schematic, edge: EdgeId, pin: usize) Pt {
    const row = s.devices.get(edge.index());
    return row.orient.apply(s.lib.at(row.class).terminals[pin].at).sub(row.grid);
}
fn turn(s: *sch.Schematic, nl: *const Netlist, group: Group, member: usize) bool {
    const edge = group[member];
    const class = s.lib.at(s.devices.items(.class)[edge.index()]);
    const resistor = member == 1 or member == 2;
    const n: usize = if (resistor) 2 else 3;
    if (class.terminals.len < n) return false;
    for (0..n) |j| if (!class.shows(j) or class.terminals[j].ground_ref) return false;
    const nets = nl.graph.members(edge);
    for (n..class.terminals.len) |j| if (j < nets.len and class.shows(j) and !sch.referencePin(s, edge.index(), j, nets[j].index())) return false;
    const a = first(nl, group, member);
    const b: usize = if (resistor) 1 - a else 2;
    const up: Side = if (member == 0) .down else .up;
    const gate: Side = if (member == 0 or member == 4) .right else .left;
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
        s.devices.items(.orientation)[edge.index()] = form;
        s.devices.items(.flip_x)[edge.index()] = flips[0];
        s.devices.items(.flip_y)[edge.index()] = flips[1];
        sch.settleDevice(s, &nl.graph, edge.index());
        const x, const y = .{ tip(s, edge, a), tip(s, edge, b) };
        if (x.x != y.x or (if (member == 0) x.y <= y.y else x.y >= y.y)) continue;
        if (s.pinSide(edge.index(), a) != up or s.pinSide(edge.index(), b) != up.opposite()) continue;
        if (!resistor) {
            const g = tip(s, edge, 1);
            if (g.y <= @min(x.y, y.y) or g.y >= @max(x.y, y.y) or (if (gate == .left) g.x >= x.x else g.x <= x.x)) continue;
            if (s.pinSide(edge.index(), 1) != gate) continue;
        }
        actual_anchor.move(s, nl, edge.index(), x);
        if (actual_anchor.representable(s, nl, edge.index())) return true;
    };
    return false;
}

fn attempt(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, groups: []const Group) bool {
    assert(groups.len == 1 or groups.len == 2);
    // Validate both old anchor frames before reading their first terminal.
    var anchors: [2][2]i64 = undefined;
    for (groups[0][3..5], 0..) |edge, i| {
        if (s.lib.at(s.devices.items(.class)[edge.index()]).terminals.len < 3) return false;
        const origin = Pt.round(at[edge.index()]);
        const offset = tip(s, edge, 0);
        anchors[i] = .{ @as(i64, origin.x) + offset.x, @as(i64, origin.y) + offset.y };
        for (anchors[i]) |value| if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return false;
    }
    const sum = anchors[0][0] + anchors[1][0];
    if (@mod(sum, 2) != 0) return false;
    const origin: i64 = @divExact(sum, 2);
    var before: [12]sch.DeviceInfo = undefined;
    for (groups, 0..) |group, gi| for (group, 0..) |edge, i| {
        before[6 * gi + i] = s.devices.get(edge.index());
    };
    var committed = false;
    defer if (!committed) {
        for (groups, 0..) |group, gi| for (group, 0..) |edge, i| {
            s.devices.set(edge.index(), before[6 * gi + i]);
        };
    };
    for (groups) |group| for (0..6) |i| if (!turn(s, nl, group, i)) return false;
    for (groups) |group| {
        if (tip(s, group[1], 1 - first(nl, group, 1)).y != tip(s, group[2], 1 - first(nl, group, 2)).y) return false;
        for ([_]usize{ 1, 2 }) |j| if (tip(s, group[3], j).y != tip(s, group[4], j).y) return false;
    }
    if (groups.len == 2) for (0..6) |i| {
        const n: usize = if (i == 1 or i == 2) 2 else 3;
        for (0..n) |j| {
            const ap = if (n == 2) (first(nl, groups[0], i) + j) % 2 else j;
            const bp = if (n == 2) (first(nl, groups[1], i) + j) % 2 else j;
            if (tip(s, groups[0][i], ap).y != tip(s, groups[1][i], bp).y) return false;
        }
    };
    var boxes: [12]Rect = undefined;
    for (groups, 0..) |group, gi| for (group, 0..) |edge, i| {
        boxes[6 * gi + i] = s.boxAt(edge.index(), .zero);
    };
    const gap: i64 = @max(@as(i64, len.stack), @as(i64, len.clearance) + 1);
    var extent: i64 = gap;
    var left: i64 = 0;
    var right: i64 = 0;
    for (groups, 0..) |_, gi| {
        var middle: i64 = 0;
        for ([_]usize{ 0, 5 }) |i| middle = @max(middle, @max(-@as(i64, boxes[6 * gi + i].min.x), boxes[6 * gi + i].max.x));
        for ([_]usize{ 1, 3 }) |i| extent = @max(extent, middle + boxes[6 * gi + i].max.x + gap);
        for ([_]usize{ 2, 4 }) |i| extent = @max(extent, middle - boxes[6 * gi + i].min.x + gap);
    }
    for (groups, 0..) |_, gi| for (0..6) |i| {
        const x: i64 = if (i == 1 or i == 3) -extent else if (i == 2 or i == 4) extent else 0;
        left = @min(left, x + boxes[6 * gi + i].min.x);
        right = @max(right, x + boxes[6 * gi + i].max.x);
    };
    const separation = right - left + @max(gap, len.series);
    var points: [12][2]i64 = undefined;
    for (groups, 0..) |_, gi| for (0..6) |i| {
        const x: i64 = if (i == 1 or i == 3) -extent else if (i == 2 or i == 4) extent else 0;
        points[6 * gi + i] = .{ origin + x + @as(i64, @intCast(gi)) * separation, 0 };
    };
    var bottom: i64 = std.math.minInt(i32);
    for (groups, 0..) |_, gi| bottom = @max(bottom, boxes[6 * gi].max.y);
    for ([_][]const usize{ &.{ 1, 2 }, &.{ 3, 4 }, &.{5} }) |band| {
        var upper: i64 = std.math.maxInt(i32);
        var lower: i64 = std.math.minInt(i32);
        for (groups, 0..) |_, gi| for (band) |i| {
            upper = @min(upper, boxes[6 * gi + i].min.y);
            lower = @max(lower, boxes[6 * gi + i].max.y);
        };
        var row = bottom + gap - upper;
        if (groups.len == 2 and band[0] == 3) {
            const room = 2 * @as(i64, len.tap) + len.clearance;
            for (groups, 0..) |group, gi| for ([_]usize{ 1, 2 }) |i| {
                const output = points[6 * gi + i][1] + tip(s, group[i], 1 - first(nl, group, i)).y;
                row = @max(row, output + room - tip(s, group[i + 2], 0).y);
            };
        }
        for (groups, 0..) |_, gi| for (band) |i| {
            points[6 * gi + i][1] = row;
        };
        bottom = row + lower;
    }
    var foreign_top: ?i64 = null;
    for (at, sk.drawn, 0..) |xy, visible, d| {
        if (!visible or contains(groups, d)) continue;
        const box = foreign(s, ats, @intCast(d), Pt.round(xy));
        foreign_top = if (foreign_top) |old| @min(old, box.min.y) else box.min.y;
    }
    const dy = if (foreign_top) |top| top - gap - bottom else @min(anchors[0][1], anchors[1][1]);
    var proposed: [12]Pt = undefined;
    for (points[0 .. 6 * groups.len], proposed[0 .. 6 * groups.len]) |point, *out| {
        const x = point[0];
        const y = point[1] + dy;
        if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or y < std.math.minInt(i32) or y > std.math.maxInt(i32)) return false;
        out.* = .{ .x = @intCast(x), .y = @intCast(y) };
    }
    for (groups, 0..) |group, gi| for (group, 0..) |edge, i| {
        const k = 6 * gi + i;
        const candidate = s.boxAt(edge.index(), proposed[k]).grow(len.clearance);
        for (groups, 0..) |other, oi| for (other, 0..) |e, j| if (6 * oi + j > k and candidate.intersects(s.boxAt(e.index(), proposed[6 * oi + j]))) return false;
        for (at, sk.drawn, 0..) |xy, visible, d| if (visible and !contains(groups, d) and candidate.intersects(foreign(s, ats, @intCast(d), Pt.round(xy)))) return false;
    };
    for (groups, 0..) |group, gi| for (group, 0..) |edge, i| {
        at[edge.index()] = proposed[6 * gi + i].toF();
    };
    committed = true;
    return true;
}

fn record(s: *const sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, groups: []const Group, storage: [2][][2]i32, count: *[2]usize) void {
    for (groups) |group| {
        var p: [16]Pt = undefined;
        var k: usize = 0;
        for (group, 0..) |edge, i| {
            const n: usize = if (i == 1 or i == 2) 2 else 3;
            for (0..n) |j| {
                const pin = if (n == 2) (first(nl, group, i) + j) % 2 else j;
                p[k] = Pt.round(s.xy[s.deviceNode(edge.index()).?]).add(tip(s, edge, pin));
                k += 1;
            }
        }
        for ([_][2]usize{ .{ 8, 7 }, .{ 7, 0 }, .{ 0, 10 }, .{ 10, 11 }, .{ 9, 13 }, .{ 13, 12 }, .{ 14, 13 } }) |ij| keep(storage[0], &count[0], p[ij[0]].x, p[ij[1]].x);
        for ([_][2]usize{ .{ 2, 1 }, .{ 1, 0 }, .{ 0, 3 }, .{ 3, 4 }, .{ 4, 7 }, .{ 7, 8 }, .{ 8, 9 }, .{ 9, 13 }, .{ 13, 14 }, .{ 14, 15 } }) |ij| keep(storage[1], &count[1], p[ij[0]].y, p[ij[1]].y);
    }
    if (groups.len == 2) {
        const a = groups[0][4];
        const b = groups[1][3];
        keep(storage[0], &count[0], Pt.round(s.xy[s.deviceNode(a.index()).?]).x + tip(s, a, 1).x, Pt.round(s.xy[s.deviceNode(b.index()).?]).x + tip(s, b, 1).x);
    }
    var bottom: i32 = std.math.minInt(i32);
    var top: i32 = std.math.maxInt(i32);
    for (sk.drawn, 0..) |visible, d| {
        if (!visible) continue;
        const box = s.boxAt(d, Pt.round(s.xy[s.deviceNode(@intCast(d)).?]));
        if (contains(groups, d)) bottom = @max(bottom, box.max.y) else top = @min(top, box.min.y);
    }
    if (top != std.math.maxInt(i32)) keep(storage[1], &count[1], bottom, top);
}
fn contains(groups: []const Group, d: usize) bool {
    for (groups) |group| for (group) |edge| if (edge.index() == d) return true;
    return false;
}
fn foreign(s: *const sch.Schematic, ats: []const ?pinned.At, d: u32, point: Pt) Rect {
    return if (ats[d]) |fixed| s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin) else s.boxAt(d, point);
}
fn keep(storage: [][2]i32, count: *usize, a: i32, b: i32) void {
    if (a >= b) return;
    assert(count.* < storage.len);
    storage[count.*] = .{ a, b };
    count.* += 1;
}
