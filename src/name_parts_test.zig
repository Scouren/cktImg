//! Naming at pins (`name_parts.atPins`) on a bare canvas. Oracle: the
//! canvas read back: which pins one wire joins, and where the names stand.
//! Two terminal pins face each other on one row, nothing between them.
//!
//! Contents: tests only.

const std = @import("std");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const name_parts = @import("name_parts.zig");

const Pt = library.Pt;
const Side = library.Side;

fn facingPins(join: bool) !void {
    const gpa = std.testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{"x"}, .device_pin_count = &.{}, .roles = &.{.internal} };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    const at = [_]Pt{ .{ .x = 20, .y = 100 }, .{ .x = 100, .y = 100 } };
    for (at, [_]Side{ .right, .left }) |p, side| {
        const node = try s.addNode(.{ .kind = .terminal, .ref = 0, .group = sch.none });
        try xy.append(s.arena.allocator(), p.toF());
        _ = try s.addPin(.{ .home = node, .side = side, .net = 0, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &.{}, &.{});
    defer c.deinit();
    try name_parts.atPins(&c, 0, &.{ 0, 1 }, join);
    var labels: std.ArrayList(Pt) = .empty;
    defer labels.deinit(gpa);
    for (s.nodes.items(.kind)[2..], 2..) |k, node| if (k == .label) try labels.append(gpa, .round(s.xy[node]));
    if (join) {
        // One wire between them, one name at its middle.
        for (20..101) |x| try std.testing.expect(c.onNet(0, .{ .x = @intCast(x), .y = 100 }));
        try std.testing.expectEqualSlices(Pt, &.{.{ .x = 60, .y = 100 }}, labels.items);
    } else {
        // A name at each, no wire between, never two on one point.
        try std.testing.expect(!c.onNet(0, .{ .x = 60, .y = 100 }));
        try std.testing.expectEqual(2, labels.items.len);
        try std.testing.expect(!labels.items[0].eql(labels.items[1]));
    }
}

test "atPins: facing pins joined by one straight wire, one name at its middle" {
    try facingPins(true);
}

test "atPins: a label line's facing pins each named, never two names on one point" {
    try facingPins(false);
}
