//! One whole26 source world frame -> atomic actual placement and orders.
//!
//! Human Rules:
//! - ct_four_place.1 (bounded observation) The one source scene has inward
//!   CT taps, upper sources up/lower sources down, and two upright outer
//!   reciprocal pairs with horizontal bypasses above. Center-tail controls
//!   both face left; electrical reflection is not full pin reflection.
//!   The immutable oracle is tests/ct_four_sides.zig, all72 visible leads.
//! - ct_four_place.2 (choice) One body-bounded proposal and eight actual
//!   rigid poses per member. Shared spans/offsets must agree; unsupported
//!   frames abstain. Keep the old upper midpoint x; translate once above
//!   foreign bodies. No search or routing change. All26 rows roll back;
//!   coordinates commit only after all325 pairs and foreign bodies clear.
//! - ct_four_place.3 (invariant) Midpoints and D/near anchors are actual
//!   existing tracks. Append only initially strict actual-pin inequalities
//!   from fixed semantic lists into the single compactor. No ghost tracks.
//!
//! Data: the cold104-byte group is borrowed. Fixed26-row/point/box scratch
//! lasts one attempt. Order capacity is the sum of adjacent pairs in the
//! two literal pin-list tables; caller allocates before any mutation.
//! No hot abstraction, cache mutation or runtime-residue claim.
//!
//! Contents: order_capacity, place, axis, orders; private.

const std = @import("std");
const assert = std.debug.assert;
const owner = @import("ct_four_sides.zig");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const actual_anchor = @import("actual_anchor.zig");
const Lengths = @import("canvas.zig").Lengths;
const Group = owner.Group;
const Pt = library.Pt;
const Rect = library.Rect;
const Side = library.Side;
/// Exact number of adjacent coordinate pairs in both semantic order lists.
pub const order_capacity = x_count + y_count;

const Pin = struct { member: u5, role: u2 };
const x_lists = [_][]const Pin{
    &.{ .{ .member = 2, .role = 0 }, .{ .member = 0, .role = 0 }, .{ .member = 6, .role = 0 }, .{ .member = 0, .role = 2 }, .{ .member = 6, .role = 1 }, .{ .member = 0, .role = 1 }, .{ .member = 3, .role = 0 } },
    &.{ .{ .member = 4, .role = 0 }, .{ .member = 1, .role = 0 }, .{ .member = 7, .role = 0 }, .{ .member = 1, .role = 2 }, .{ .member = 7, .role = 1 }, .{ .member = 1, .role = 1 }, .{ .member = 5, .role = 0 } },
    &.{ .{ .member = 10, .role = 1 }, .{ .member = 10, .role = 0 }, .{ .member = 8, .role = 0 }, .{ .member = 8, .role = 1 }, .{ .member = 0, .role = 2 }, .{ .member = 9, .role = 1 }, .{ .member = 9, .role = 0 }, .{ .member = 11, .role = 0 }, .{ .member = 11, .role = 1 } },
    &.{ .{ .member = 15, .role = 1 }, .{ .member = 15, .role = 0 }, .{ .member = 13, .role = 0 }, .{ .member = 13, .role = 1 }, .{ .member = 1, .role = 2 }, .{ .member = 14, .role = 1 }, .{ .member = 14, .role = 0 }, .{ .member = 16, .role = 0 }, .{ .member = 16, .role = 1 } },
    &.{ .{ .member = 19, .role = 0 }, .{ .member = 19, .role = 1 }, .{ .member = 20, .role = 0 }, .{ .member = 18, .role = 1 }, .{ .member = 18, .role = 0 }, .{ .member = 0, .role = 0 } },
    &.{ .{ .member = 0, .role = 1 }, .{ .member = 22, .role = 0 }, .{ .member = 22, .role = 1 }, .{ .member = 24, .role = 0 }, .{ .member = 23, .role = 1 }, .{ .member = 23, .role = 0 } },
    &.{ .{ .member = 12, .role = 1 }, .{ .member = 12, .role = 0 } },
    &.{ .{ .member = 17, .role = 1 }, .{ .member = 17, .role = 0 } },
    &.{ .{ .member = 20, .role = 1 }, .{ .member = 20, .role = 0 } },
    &.{ .{ .member = 24, .role = 0 }, .{ .member = 24, .role = 1 } },
};
const y_lists = [_][]const Pin{
    &.{ .{ .member = 12, .role = 2 }, .{ .member = 12, .role = 1 }, .{ .member = 12, .role = 0 }, .{ .member = 8, .role = 1 }, .{ .member = 8, .role = 0 }, .{ .member = 6, .role = 0 }, .{ .member = 2, .role = 1 }, .{ .member = 2, .role = 0 }, .{ .member = 0, .role = 0 }, .{ .member = 0, .role = 2 }, .{ .member = 1, .role = 2 }, .{ .member = 1, .role = 0 }, .{ .member = 4, .role = 0 }, .{ .member = 4, .role = 1 }, .{ .member = 7, .role = 0 }, .{ .member = 13, .role = 0 }, .{ .member = 13, .role = 1 }, .{ .member = 17, .role = 0 }, .{ .member = 17, .role = 1 }, .{ .member = 17, .role = 2 } },
    &.{ .{ .member = 21, .role = 1 }, .{ .member = 21, .role = 0 }, .{ .member = 0, .role = 0 }, .{ .member = 18, .role = 0 }, .{ .member = 18, .role = 1 }, .{ .member = 18, .role = 2 }, .{ .member = 1, .role = 0 } },
    &.{ .{ .member = 25, .role = 1 }, .{ .member = 25, .role = 0 }, .{ .member = 0, .role = 1 }, .{ .member = 22, .role = 0 }, .{ .member = 22, .role = 1 }, .{ .member = 22, .role = 2 }, .{ .member = 1, .role = 1 } },
    &.{ .{ .member = 20, .role = 0 }, .{ .member = 20, .role = 1 }, .{ .member = 20, .role = 2 } },
    &.{ .{ .member = 24, .role = 0 }, .{ .member = 24, .role = 1 }, .{ .member = 24, .role = 2 } },
};
const x_count = pairs(&x_lists);
const y_count = pairs(&y_lists);

/// Attempts one complete actual frame per group. Failure restores all26
/// rows and every coordinate; only successful groups remain for compaction.
pub fn place(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, groups: *std.ArrayList(Group)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (groups.items) |group| {
        if (!attempt(s, nl, sk, ats, len, at, group)) continue;
        groups.items[kept] = group;
        kept += 1;
    }
    groups.items = groups.items[0..kept];
}

/// Returns the successful actual CT midpoint axis, not the old skeleton
/// column coincidence. Empty requests leave existing axis policy unchanged.
pub fn axis(s: *const sch.Schematic, groups: []const Group) ?i32 {
    if (groups.len != 1) return null;
    return std.math.cast(i32, 2 * @as(i64, Pt.round(s.xy[s.deviceNode(groups[0][0].index()).?]).x));
}

/// Records only strict existing actual-pin relations. Shared anchors and
/// rigid equal spans retain equalities; storage spans order_capacity/group.
pub fn orders(s: *const sch.Schematic, nl: *const netlist.Netlist, groups: []const Group, storage: [][2]i32) [2][]const [2]i32 {
    assert(storage.len >= order_capacity * groups.len and s.xy.len == s.nodes.len);
    const split = x_count * groups.len;
    var count: [2]usize = .{ 0, 0 };
    for (groups) |group| for ([_][]const []const Pin{ &x_lists, &y_lists }, 0..) |lists, ax| {
        const buffer = if (ax == 0) storage[0..split] else storage[split..];
        for (lists) |list| for (list[0 .. list.len - 1], list[1..]) |a, b| {
            const first = world(s, nl, group, a);
            const last = world(s, nl, group, b);
            const lo = if (ax == 0) first.x else first.y;
            const hi = if (ax == 0) last.x else last.y;
            if (lo >= hi) continue;
            assert(count[ax] < buffer.len);
            buffer[count[ax]] = .{ lo, hi };
            count[ax] += 1;
        };
    };
    return .{ storage[0..count[0]], storage[split..][0..count[1]] };
}

// ---- private ----

fn pairs(lists: []const []const Pin) usize {
    var n: usize = 0;
    for (lists) |list| n += list.len - 1;
    return n;
}
fn tip(s: *const sch.Schematic, nl: *const netlist.Netlist, g: Group, m: usize, r: usize) Pt {
    const row = s.devices.get(g[m].index());
    const p = owner.binding(nl, g, m, r);
    return row.orient.apply(s.lib.at(row.class).terminals[p].at).sub(row.grid);
}
fn world(s: *const sch.Schematic, nl: *const netlist.Netlist, g: Group, p: Pin) Pt {
    return Pt.round(s.xy[s.deviceNode(g[p.member].index()).?]).add(tip(s, nl, g, p.member, p.role));
}
fn middle(a: Pt, b: Pt) ?Pt {
    const x, const y = .{ @as(i64, a.x) + b.x, @as(i64, a.y) + b.y };
    if (@mod(x, 2) != 0 or @mod(y, 2) != 0) return null;
    return .{ .x = @intCast(@divExact(x, 2)), .y = @intCast(@divExact(y, 2)) };
}
fn turn(s: *sch.Schematic, nl: *const netlist.Netlist, g: Group, m: usize) bool {
    const d = g[m].index();
    const class = s.lib.at(s.devices.items(.class)[d]);
    const count: usize = if (m >= 2 and m < 8) 2 else 3;
    if (class.terminals.len < count) return false;
    for (0..count) |i| if (!class.shows(i) or class.terminals[i].ground_ref) return false;
    for (count..class.terminals.len) |i| if (class.shows(i)) return false;
    const channel: Side = if (m < 2 or m == 6 or m == 7 or m == 25) .right else if (m < 4 or (m >= 8 and m < 13)) .up else if (m == 21) .left else .down;
    const lateral: Side = if (m == 0) .down else if (m == 1 or m == 21 or m == 25) .up else if (m == 8 or m == 11 or m == 13 or m == 16 or m == 19 or m == 22 or m == 24) .right else .left;
    const last: usize = if (m < 8) 1 else 2;
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
        s.devices.items(.orientation)[d] = form;
        s.devices.items(.flip_x)[d] = flips[0];
        s.devices.items(.flip_y)[d] = flips[1];
        sch.settleDevice(s, &nl.graph, d);
        const a, const b = .{ tip(s, nl, g, m, 0), tip(s, nl, g, m, last) };
        const u = channel.unit();
        const span = (@as(i64, b.x) - a.x) * u.x + (@as(i64, b.y) - a.y) * u.y;
        if (span <= 0 or (channel.isHorizontal() and a.y != b.y) or (!channel.isHorizontal() and a.x != b.x)) continue;
        if (s.pinSide(d, owner.binding(nl, g, m, 0)) != channel.opposite() or s.pinSide(d, owner.binding(nl, g, m, last)) != channel) continue;
        var anchor = a;
        if (m < 2 or m == 6 or m == 7 or m == 21 or m == 25) anchor = middle(a, b) orelse continue;
        if (count == 3) {
            const gate = tip(s, nl, g, m, if (m < 2) 2 else 1);
            const v = lateral.unit();
            const offset = (@as(i64, gate.x) - anchor.x) * v.x + (@as(i64, gate.y) - anchor.y) * v.y;
            if (offset <= 0 or s.pinSide(d, owner.binding(nl, g, m, if (m < 2) 2 else 1)) != lateral) continue;
            if (m < 2 or m == 21 or m == 25) {
                if (gate.x != anchor.x) continue;
            } else if (gate.y <= @min(a.y, b.y) or gate.y >= @max(a.y, b.y)) continue;
        }
        actual_anchor.move(s, nl, d, anchor);
        if (actual_anchor.representable(s, nl, d)) return true;
    };
    return false;
}
fn compatible(s: *const sch.Schematic, nl: *const netlist.Netlist, g: Group) bool {
    for ([_][2]usize{ .{ 8, 9 }, .{ 10, 11 }, .{ 13, 14 }, .{ 15, 16 }, .{ 18, 22 }, .{ 19, 23 }, .{ 20, 24 }, .{ 21, 25 } }) |ij| for (0..3) |r| {
        const a, const b = .{ tip(s, nl, g, ij[0], r), tip(s, nl, g, ij[1], r) };
        if (@as(i64, a.x) + b.x != 0 or a.y != b.y) return false;
    };
    for ([_][4]usize{ .{ 8, 9, 10, 11 }, .{ 13, 14, 15, 16 }, .{ 18, 19, 22, 23 } }) |row| for (row[1..]) |m| for ([_]usize{ 1, 2 }) |r| {
        if (tip(s, nl, g, row[0], r).y != tip(s, nl, g, m, r).y) return false;
    };
    for (0..2) |t| {
        const a, const b = .{ tip(s, nl, g, 2 + 2 * t, 1), tip(s, nl, g, 3 + 2 * t, 1) };
        if (a.y != b.y or a.x != 0 or b.x != 0) return false;
        const cap = tip(s, nl, g, 6 + t, 1);
        const coil = tip(s, nl, g, t, 1);
        if (cap.x <= 0 or cap.x >= coil.x) return false;
    }
    return true;
}
fn bounds(s: *const sch.Schematic, g: Group) [26]Rect {
    var out: [26]Rect = undefined;
    for (g, &out) |e, *b| b.* = s.boxAt(e.index(), .zero);
    return out;
}
fn layout(s: *const sch.Schematic, nl: *const netlist.Netlist, g: Group, len: Lengths, b: [26]Rect) [26][2]i64 {
    const gap: i64 = @max(len.stack, len.clearance + 1);
    var p: [26][2]i64 = @splat(.{ 0, 0 });
    var core: i64 = 0;
    for (0..2) |t| {
        const l = 2 + 2 * t;
        const r = l + 1;
        const c = 6 + t;
        const sign: i64 = if (t == 0) -1 else 1;
        const h = tip(s, nl, g, t, 1).x;
        const extent = @max(@as(i64, h) + gap, @max(@as(i64, b[l].max.x) - b[t].min.x + gap, @as(i64, b[t].max.x) - b[r].min.x + gap));
        const near = if (t == 0) @as(i64, b[t].min.y) - gap - @max(b[l].max.y, b[r].max.y) else @as(i64, b[t].max.y) + gap - @min(b[l].min.y, b[r].min.y);
        const far = near + tip(s, nl, g, l, 1).y;
        const cap = if (t == 0) @min(far - gap, near + @min(b[l].min.y, b[r].min.y) - gap - b[c].max.y) else @max(far + gap, near + @max(b[l].max.y, b[r].max.y) + gap - b[c].min.y);
        p[l] = .{ -extent, near };
        p[r] = .{ extent, near };
        p[c] = .{ 0, cap };
        core = @max(core, @max(extent - @as(i64, b[l].min.x), extent + b[r].max.x));
        assert(near * sign > 0 and (cap - far) * sign > 0);
    }
    // Side banks lie wholly outside the central passive envelope. Their
    // tail/bypass midpoint and two D columns are actual anchors.
    var half: i64 = gap;
    for ([_]usize{ 18, 19, 20, 21, 22, 23, 24, 25 }) |m| half = @max(half, @max(-@as(i64, b[m].min.x), b[m].max.x) + gap);
    // Each pair-to-tail gap includes both facing actual envelopes. An
    // individual maximum misses an inward pair gate beside the tail gate.
    for ([_][2]usize{ .{ 19, 20 }, .{ 20, 18 }, .{ 22, 24 }, .{ 24, 23 } }) |ij|
        half = @max(half, @as(i64, b[ij[0]].max.x) - b[ij[1]].min.x + gap);
    const inner = core + gap + @max(@as(i64, b[18].max.x), -@as(i64, b[22].min.x));
    const center = inner + half;
    const outer = center + half;
    const side_row = @as(i64, b[0].max.y) + gap - @min(@min(b[18].min.y, b[19].min.y), @min(b[22].min.y, b[23].min.y));
    const shared = side_row + tip(s, nl, g, 18, 2).y;
    const bypass = @min(-gap, @as(i64, b[0].min.y) - gap - @max(b[21].max.y, b[25].max.y));
    p[18] = .{ -inner, side_row };
    p[19] = .{ -outer, side_row };
    p[20] = .{ -center, shared };
    p[21] = .{ -center, bypass };
    p[22] = .{ inner, side_row };
    p[23] = .{ outer, side_row };
    p[24] = .{ center, shared };
    p[25] = .{ center, bypass };
    const lower = @max(shared + @max(b[20].max.y, b[24].max.y) + gap - b[1].min.y, @as(i64, tip(s, nl, g, 0, 2).y) - tip(s, nl, g, 1, 2).y + gap);
    p[1][1] = lower;
    for ([_]usize{ 4, 5, 7 }) |m| p[m][1] += lower;
    for (0..2) |t| {
        const first = 8 + 5 * t;
        const tail = first + 4;
        const cap = 6 + t;
        var extent: i64 = gap;
        for ([_]usize{ first, first + 1 }) |m| extent = @max(extent, @max(-@as(i64, b[m].min.x), b[m].max.x) + @max(-@as(i64, b[tail].min.x), b[tail].max.x) + gap);
        const outside = extent + @max(@as(i64, b[first + 2].max.x) - b[first].min.x, @as(i64, b[first + 1].max.x) - b[first + 3].min.x) + gap;
        var top: i64 = std.math.maxInt(i32);
        var bottom: i64 = std.math.minInt(i32);
        for (first..first + 4) |m| {
            top = @min(top, b[m].min.y);
            bottom = @max(bottom, b[m].max.y);
        }
        const row = if (t == 0) p[cap][1] + b[cap].min.y - gap - bottom else p[cap][1] + b[cap].max.y + gap - top;
        p[first] = .{ -extent, row };
        p[first + 1] = .{ extent, row };
        p[first + 2] = .{ -outside, row };
        p[first + 3] = .{ outside, row };
        p[tail] = .{ 0, row + tip(s, nl, g, first, 2).y };
    }
    return p;
}
fn attempt(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, g: Group) bool {
    const coil = s.lib.at(s.devices.items(.class)[g[0].index()]);
    if (coil.terminals.len != 3) return false;
    const row = s.devices.get(g[0].index());
    var old_tips: [2]Pt = undefined;
    for (&old_tips, 0..) |*point, r| {
        const raw = coil.terminals[owner.binding(nl, g, 0, r)].at;
        if (raw.x == std.math.minInt(i32) or raw.y == std.math.minInt(i32)) return false;
        const transformed = row.orient.apply(raw);
        point.* = .{ .x = std.math.cast(i32, @as(i64, transformed.x) - row.grid.x) orelse return false, .y = std.math.cast(i32, @as(i64, transformed.y) - row.grid.y) orelse return false };
    }
    const old_mid = middle(old_tips[0], old_tips[1]) orelse return false;
    var origin: Pt = undefined;
    inline for (.{ "x", "y" }, 0..) |field, ax| {
        const value = @round(@as(f64, at[g[0].index()][ax]));
        if (!std.math.isFinite(value) or value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return false;
        @field(origin, field) = std.math.cast(i32, @as(i64, @intFromFloat(value)) + @field(old_mid, field)) orelse return false;
    }
    var before: [26]sch.DeviceInfo = undefined;
    for (g, &before) |e, *r| r.* = s.devices.get(e.index());
    var committed = false;
    defer if (!committed) {
        for (g, before) |e, r| s.devices.set(e.index(), r);
    };
    for (0..26) |m| if (!turn(s, nl, g, m)) return false;
    if (!compatible(s, nl, g)) return false;
    const box = bounds(s, g);
    const relative = layout(s, nl, g, len, box);
    var bottom: i64 = std.math.minInt(i32);
    for (relative, box) |p, b| bottom = @max(bottom, p[1] + b.max.y);
    var foreign_top: ?i64 = null;
    for (at, sk.drawn, 0..) |xy, drawn, d| {
        if (!drawn or contains(g, d)) continue;
        const b = foreign(s, ats, @intCast(d), Pt.round(xy));
        foreign_top = if (foreign_top) |v| @min(v, b.min.y) else b.min.y;
    }
    const gap: i64 = @max(len.stack, len.clearance + 1);
    const dy = if (foreign_top) |v| v - gap - bottom else origin.y;
    var points: [26]Pt = undefined;
    for (relative, &points) |p, *point| point.* = .{ .x = std.math.cast(i32, @as(i64, origin.x) + p[0]) orelse return false, .y = std.math.cast(i32, dy + p[1]) orelse return false };
    for (g, points, 0..) |e, p, i| {
        const candidate = s.boxAt(e.index(), p).grow(len.clearance);
        for (g[i + 1 ..], points[i + 1 ..]) |other, q| if (candidate.intersects(s.boxAt(other.index(), q))) return false;
        for (at, sk.drawn, 0..) |xy, drawn, d| if (drawn and !contains(g, d) and candidate.intersects(foreign(s, ats, @intCast(d), Pt.round(xy)))) return false;
    }
    for (g, points) |e, p| at[e.index()] = p.toF();
    committed = true;
    return true;
}
fn contains(g: Group, d: usize) bool {
    for (g) |e| if (e.index() == d) return true;
    return false;
}
fn foreign(s: *const sch.Schematic, ats: []const ?pinned.At, d: u32, p: Pt) Rect {
    return if (ats[d]) |fixed| s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin) else s.boxAt(d, p);
}
