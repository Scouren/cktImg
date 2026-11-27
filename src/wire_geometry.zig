//! Integer test for the four line directions shared by drawing checks and editor wires.
//!
//! Contents:
//! - `pub const Mode`, `Crossing.onSegment`
//! - `pub const Crossing`, `Crossing.lattice`, `pub fn properCross`, `pub fn rays`, `pub fn hitsRect`
//! - `pub const Direction`, `Direction.offset`, `pub fn direction`, `pub fn contains`

const std = @import("std");
const library = @import("library.zig");
const Pt = library.Pt;

/// Permission supplied by a consumer for its final wire records.
pub const Mode = enum(u8) { manhattan, allow_45 };

/// An undirected line in drawing coordinates, where y increases down the sheet.
pub const Direction = enum(u2) {
    horizontal,
    vertical,
    down_right,
    up_right,

    /// The constant for the line of this direction through p. Across the i32
    /// coordinate domain, the diagonal constants can require a signed 33rd bit.
    pub fn offset(d: Direction, p: Pt) i64 {
        return switch (d) {
            .horizontal => p.y,
            .vertical => p.x,
            .down_right => @as(i64, p.y) - p.x,
            .up_right => @as(i64, p.y) + p.x,
        };
    }
};

/// A proper crossing in half-grid coordinates. Multiplication by two keeps
/// the intersection exact even when the two diagonals meet between grid points.
pub const Crossing = struct {
    x2: i64,
    y2: i64,

    /// Whether the exact crossing touches a third closed wire, including its end.
    pub fn onSegment(c: Crossing, a: Pt, b: Pt) bool {
        if (c.x2 < 2 * @as(i64, @min(a.x, b.x)) or c.x2 > 2 * @as(i64, @max(a.x, b.x)) or
            c.y2 < 2 * @as(i64, @min(a.y, b.y)) or c.y2 > 2 * @as(i64, @max(a.y, b.y))) return false;
        const d = direction(a, b) orelse return a.eql(b);
        return switch (d) {
            .horizontal, .vertical => true,
            .down_right => c.y2 - c.x2 == 2 * d.offset(a),
            .up_right => c.y2 + c.x2 == 2 * d.offset(a),
        };
    }

    /// An integral contact can be a junction in the integer wire format.
    pub fn lattice(c: Crossing) ?Pt {
        if (@mod(c.x2, 2) != 0 or @mod(c.y2, 2) != 0) return null;
        return .{ .x = @intCast(@divExact(c.x2, 2)), .y = @intCast(@divExact(c.y2, 2)) };
    }
};

/// The direction of a nonempty supported segment. A point or another slope has none.
pub fn direction(a: Pt, b: Pt) ?Direction {
    if (a.x == b.x) return if (a.y == b.y) null else .vertical;
    if (a.y == b.y) return .horizontal;
    const dx = @as(i64, b.x) - a.x;
    const dy = @as(i64, b.y) - a.y;
    if (dx == dy) return .down_right;
    if (dx == -dy) return .up_right;
    return null;
}

/// Whether the closed segment contains p. A degenerate segment represents one point.
pub fn contains(a: Pt, b: Pt, p: Pt) bool {
    if (!library.Rect.fromCorners(a, b).contains(p)) return false;
    if (a.x == b.x or a.y == b.y) return true;
    const d = direction(a, b) orelse return false;
    return d.offset(a) == d.offset(p);
}

/// Intersects finite open segments. End touches and collinear pieces have
/// no proper crossing. Line constants and doubled coordinates fit in i64.
pub fn properCross(a: Pt, b: Pt, c: Pt, d: Pt) ?Crossing {
    const u = direction(a, b) orelse return null;
    const v = direction(c, d) orelse return null;
    if (u == v) return null;
    const x2: i64 = if (u == .vertical) 2 * @as(i64, a.x) else if (v == .vertical) 2 * @as(i64, c.x) else @divExact(2 * (v.offset(c) - u.offset(a)), slope(u) - slope(v));
    const y2 = if (u == .vertical) slope(v) * x2 + 2 * v.offset(c) else slope(u) * x2 + 2 * u.offset(a);
    if (!betweenOpen(a, b, x2, y2) or !betweenOpen(c, d, x2, y2)) return null;
    return .{ .x2 = x2, .y2 = y2 };
}

/// The eight wire rays leaving p. Low bits retain left, right, up, down.
/// Each successive pair of high bits represents the opposite rays of one diagonal.
pub fn rays(a: Pt, b: Pt, p: Pt) u8 {
    if (!contains(a, b, p)) return 0;
    const d = direction(a, b) orelse return 0;
    const shift: u3 = @as(u3, @backingInt(d)) * 2;
    const vertical = d == .vertical;
    const x = if (vertical) p.y else p.x;
    const lo = if (vertical) @min(a.y, b.y) else @min(a.x, b.x);
    const hi = if (vertical) @max(a.y, b.y) else @max(a.x, b.x);
    const both: u8 = @as(u8, @intFromBool(lo < x)) | (@as(u8, @intFromBool(hi > x)) << 1);
    return both << shift;
}

/// Closed segment intersection with a device rectangle, including its edge.
/// The two coordinate projections and the segment's normal are the separating axes.
pub fn hitsRect(a: Pt, b: Pt, box: library.Rect) bool {
    if (@max(a.x, b.x) < box.min.x or @min(a.x, b.x) > box.max.x or
        @max(a.y, b.y) < box.min.y or @min(a.y, b.y) > box.max.y) return false;
    const d = direction(a, b) orelse return box.contains(a);
    const k = d.offset(a);
    return switch (d) {
        .horizontal, .vertical => true,
        .down_right => k >= @as(i64, box.min.y) - box.max.x and k <= @as(i64, box.max.y) - box.min.x,
        .up_right => k >= d.offset(box.min) and k <= d.offset(box.max),
    };
}

// ---- private ----

fn slope(d: Direction) i64 {
    return switch (d) {
        .horizontal => 0,
        .vertical => unreachable,
        .down_right => 1,
        .up_right => -1,
    };
}

fn betweenOpen(a: Pt, b: Pt, x2: i64, y2: i64) bool {
    const v = a.x == b.x;
    const t = if (v) y2 else x2;
    const lo: i64 = if (v) @min(a.y, b.y) else @min(a.x, b.x);
    const hi: i64 = if (v) @max(a.y, b.y) else @max(a.x, b.x);
    return t > 2 * lo and t < 2 * hi;
}

test "proper crossings use half-grid coordinates and finite, ordered endpoints" {
    const min = std.math.minInt(i32);
    const max = std.math.maxInt(i32);
    const a: Pt = .{ .x = min, .y = min };
    const b: Pt = .{ .x = max, .y = max };
    const c: Pt = .{ .x = min, .y = max };
    const d: Pt = .{ .x = max, .y = min };
    try std.testing.expectEqual(Crossing{ .x2 = -1, .y2 = -1 }, properCross(b, a, c, d).?);
    try std.testing.expectEqual(@as(?Pt, null), properCross(d, c, a, b).?.lattice());
    const ten: Pt = .{ .x = 10, .y = 10 };
    const other: Pt = .{ .x = 0, .y = 10 };
    try std.testing.expectEqual(Pt{ .x = 5, .y = 5 }, properCross(.zero, ten, other, .{ .x = 10, .y = 0 }).?.lattice().?);
    try std.testing.expectEqual(@as(?Crossing, null), properCross(.zero, ten, other, .{ .x = 4, .y = 6 }));
    const half = properCross(a, b, c, d).?;
    try std.testing.expect(half.onSegment(.{ .x = -2, .y = -2 }, .zero));
    try std.testing.expect(!half.onSegment(.{ .x = -2, .y = -1 }, .zero));
    const entire: Crossing = .{ .x2 = 10, .y2 = 10 };
    try std.testing.expect(entire.onSegment(.{ .x = 5, .y = 5 }, .{ .x = 5, .y = 8 }));
    const box: library.Rect = .point(.{ .x = 2, .y = 8 });
    try std.testing.expect(!hitsRect(.zero, ten, box));
    try std.testing.expect(hitsRect(other, .{ .x = 10, .y = 0 }, box));
    const rays_at_origin = rays(.zero, .{ .x = -10, .y = -10 }, .zero) | rays(.zero, .{ .x = 10, .y = -10 }, .zero);
    try std.testing.expectEqual(@as(u8, 2), @popCount(rays_at_origin));
}

test "direction and point membership are exact over the entire signed coordinate range" {
    const min = std.math.minInt(i32);
    const max = std.math.maxInt(i32);
    const a: Pt = .{ .x = min, .y = max };
    const b: Pt = .{ .x = max, .y = min };
    try std.testing.expectEqual(Direction.up_right, direction(a, b).?);
    try std.testing.expect(contains(a, b, .{ .x = 0, .y = -1 }));
    try std.testing.expect(!contains(b, a, .{ .x = 0, .y = 0 }));
    try std.testing.expectEqual(@as(i64, 4294967294), Direction.up_right.offset(.{ .x = max, .y = max }));
    try std.testing.expectEqual(@as(?Direction, null), direction(a, a));
    try std.testing.expectEqual(@as(?Direction, null), direction(.zero, .{ .x = 9, .y = 10 }));
}
