//! Integer test for the four line directions shared by drawing checks and editor wires.
//!
//! Contents:
//! - `pub const Direction`, `Direction.offset`, `pub fn direction`, `pub fn contains`

const std = @import("std");
const library = @import("library.zig");
const Pt = library.Pt;

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
