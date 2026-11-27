//! Literal full-cost competition at the trunk drawing boundary.
//! Oracle: the four AG1146 scaffold pins admit a level detour and a
//! straight-interval upright tree, each length 1180 with three corners.
//! A foreign crossing adds 80 only to the straight tree; a collinear
//! foreign segment forbids it. The preference must not alter either cost
//! or clearance. The independent oracle samples every integer interval
//! point, rather than repeating the production interval-union algorithm.
//!
//! Contents: tests only.

const std = @import("std");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const trunk = @import("trunk.zig");
const Pt = library.Pt;
const Barrier = enum { none, crossing, collinear };

// ---- private ----

fn compete(preferred: bool, barrier: Barrier) !void {
    const gpa = std.testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "control", "other" }, .device_pin_count = &.{}, .roles = &.{ .internal, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    const terminals = [_]Pt{ .{ .x = 80, .y = 440 }, .{ .x = 80, .y = 40 }, .{ .x = 100, .y = 20 }, .{ .x = 760, .y = 20 } };
    for (terminals, [_]library.Side{ .up, .down, .right, .left }) |at, side| {
        const node = try s.addNode(.{ .kind = .terminal, .ref = 0, .group = sch.none });
        try xy.append(s.arena.allocator(), at.toF());
        _ = try s.addPin(.{ .home = node, .side = side, .net = 0, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    const boxes = [_]library.Rect{
        .{ .min = .{ .x = 70, .y = 440 }, .max = .{ .x = 90, .y = 480 } },
        .{ .min = .{ .x = 70, .y = 0 }, .max = .{ .x = 100, .y = 40 } },
        .{ .min = .{ .x = 760, .y = 0 }, .max = .{ .x = 790, .y = 40 } },
    };
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &boxes, &.{});
    defer c.deinit();
    switch (barrier) {
        .none => {},
        .crossing => try std.testing.expect(try c.commit(1, &.{ .{ .x = 500, .y = 0 }, .{ .x = 500, .y = 40 } })),
        .collinear => try std.testing.expect(try c.commit(1, &.{ .{ .x = 400, .y = 20 }, .{ .x = 600, .y = 20 } })),
    }
    const pair = [2]Pt{ terminals[2], terminals[3] };
    try std.testing.expect(try trunk.drawPreferred(&c, 0, &.{ 0, 1, 2, 3 }, .port, if (preferred) pair else null));
    var straight = true;
    for (100..761) |x| straight = straight and c.onNet(0, .{ .x = @intCast(x), .y = 20 });
    try std.testing.expectEqual(preferred and barrier == .none, straight);
    // Literal equal-cost trees both measure 1180. The dearer preferred
    // candidate must lose when its extra crossing contributes 80.
    var length: u32 = 0;
    for (c.segs.items) |segment| if (segment.net == 0) {
        length += @abs(segment.a.x - segment.b.x) + @abs(segment.a.y - segment.b.y);
        try std.testing.expect(!c.onNet(1, segment.a));
        try std.testing.expect(!c.onNet(1, segment.b));
    };
    try std.testing.expectEqual(1180, length);
    for (terminals) |at| try std.testing.expect(c.onNet(0, at));
}

test "trunk preference: equal full cost keeps interval only when nominated" {
    try compete(false, .none);
    try compete(true, .none);
}

test "trunk preference: added crossing cost and foreign collinear ink retain precedence" {
    for ([_]Barrier{ .crossing, .collinear }) |barrier| {
        try compete(false, barrier);
        try compete(true, barrier);
    }
}
