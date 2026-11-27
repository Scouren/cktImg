//! Whether one net's wire closes a loop (issue #8, stage 4). In: the net's
//! segments. Out: whether, split at every point where they meet (an end, a
//! corner, a crossing on the lattice), the pieces join some two points two
//! ways. Shared by `trunk`, on a candidate's lines, and `wire_gates`, on a
//! finished drawing, so the check and the gate read one definition.
//!
//! Human Rules:
//! - wire_tree.1 (invariant) A net's wire is a tree: no two of its points
//!   are joined two ways. A loop draws a connection twice; the ring it
//!   leaves means nothing a reader can use, and it hides which pin feeds
//!   which. A piece drawn twice over the same points is one piece, no
//!   loop. `cyclic`
//!
//! Contents:
//! - `pub fn cyclic(gpa: Allocator, segs: []const [2]Pt) Allocator.Error!bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const wire_geometry = @import("wire_geometry.zig");

const Pt = library.Pt;

/// Whether `segs`, the segments of one net (each along a row, a column or a
/// diagonal), close a loop (wire_tree.1). Two segments meet where a point
/// of one lies on the other or where they cross on the lattice.
// ponytail: every point against every segment, quadratic; fine at one net.
pub fn cyclic(gpa: Allocator, segs: []const [2]Pt) Allocator.Error!bool {
    // No arena: one that retries a smaller block on failure makes the
    // allocation count depend on which allocation fails.
    const a = gpa;
    var pts: std.ArrayList(Pt) = .empty;
    defer pts.deinit(a);
    for (segs) |s| try pts.appendSlice(a, &s);
    for (segs, 0..) |s, i| for (segs[i + 1 ..]) |t| {
        const hit = wire_geometry.properCross(s[0], s[1], t[0], t[1]) orelse continue;
        try pts.append(a, hit.lattice() orelse continue);
    };
    std.sort.pdq(Pt, pts.items, {}, before);
    var n: usize = 0;
    for (pts.items) |p| {
        if (n > 0 and pts.items[n - 1].eql(p)) continue;
        pts.items[n] = p;
        n += 1;
    }
    const points = pts.items[0..n];
    // The pieces: consecutive points along each segment, each pair once.
    const Along = struct { key: i64, i: u32 };
    var along: std.ArrayList(Along) = .empty;
    defer along.deinit(a);
    var edges: std.ArrayList([2]u32) = .empty;
    defer edges.deinit(a);
    for (segs) |s| {
        along.clearRetainingCapacity();
        for (points, 0..) |p, i| if (wire_geometry.contains(s[0], s[1], p)) {
            try along.append(a, .{ .key = @as(i64, @abs(p.x - s[0].x)) + @abs(p.y - s[0].y), .i = @intCast(i) });
        };
        assert(along.items.len >= 1);
        std.sort.pdq(Along, along.items, {}, struct {
            fn lt(_: void, x: Along, y: Along) bool {
                return x.key < y.key;
            }
        }.lt);
        for (along.items[0 .. along.items.len - 1], along.items[1..]) |u, v| {
            try edges.append(a, .{ @min(u.i, v.i), @max(u.i, v.i) });
        }
    }
    std.sort.pdq([2]u32, edges.items, {}, struct {
        fn lt(_: void, x: [2]u32, y: [2]u32) bool {
            return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]);
        }
    }.lt);
    const parent = try a.alloc(u32, n);
    defer a.free(parent);
    for (parent, 0..) |*p, i| p.* = @intCast(i);
    for (edges.items, 0..) |e, k| {
        if (k > 0 and std.mem.eql(u32, &e, &edges.items[k - 1])) continue;
        const ra = root(parent, e[0]);
        const rb = root(parent, e[1]);
        if (ra == rb) return true;
        parent[ra] = rb;
    }
    return false;
}

// ---- private ----

fn before(_: void, x: Pt, y: Pt) bool {
    return x.y < y.y or (x.y == y.y and x.x < y.x);
}

fn root(parent: []const u32, x0: u32) u32 {
    var x = x0;
    var steps: usize = 0;
    while (parent[x] != x) : (steps += 1) {
        assert(steps < parent.len);
        x = parent[x];
    }
    return x;
}

test "wire tree: a ring is a loop; a tree, a T, a piece drawn twice and a cross are none" {
    const gpa = std.testing.allocator;
    const p = struct {
        fn f(x: i32, y: i32) Pt {
            return .{ .x = x, .y = y };
        }
    }.f;
    // By hand: a square drawn as two L's closes; an L and a T do not.
    try std.testing.expect(try cyclic(gpa, &.{ .{ p(0, 0), p(10, 0) }, .{ p(10, 0), p(10, 10) }, .{ p(0, 0), p(0, 10) }, .{ p(0, 10), p(10, 10) } }));
    try std.testing.expect(!try cyclic(gpa, &.{ .{ p(0, 0), p(10, 0) }, .{ p(10, 0), p(10, 10) } }));
    try std.testing.expect(!try cyclic(gpa, &.{ .{ p(0, 0), p(20, 0) }, .{ p(10, 0), p(10, 10) } }));
    // The same piece twice, and a piece lying along part of another.
    try std.testing.expect(!try cyclic(gpa, &.{ .{ p(0, 0), p(20, 0) }, .{ p(20, 0), p(0, 0) }, .{ p(5, 0), p(10, 0) } }));
    // A cross of two pieces joins them once.
    try std.testing.expect(!try cyclic(gpa, &.{ .{ p(0, 5), p(10, 5) }, .{ p(5, 0), p(5, 10) } }));
    // AMS385's input: a tap through its own trunk and on to the tap row.
    try std.testing.expect(try cyclic(gpa, &.{ .{ p(30, 120), p(30, 140) }, .{ p(30, 240), p(30, 140) }, .{ p(20, 180), p(40, 180) }, .{ p(40, 180), p(40, 140) }, .{ p(30, 140), p(60, 140) } }));
}
