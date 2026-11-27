//! Pending device pins retain room to leave in their actual outward direction.
//! Oracle: literal two-net contact geometry, then two successive maze routes.
//! A foreign endpoint/parallel run cannot occupy the escape; an interior
//! perpendicular crossing remains legal, including at its far boundary.
//!
//! Contents: transformed literal scenes, then independent routing checks.

const std = @import("std");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const maze = @import("maze.zig");

const Pt = library.Pt;
const Side = library.Side;

// ---- private ----

fn transform(p: Pt, swap: bool, mirror: bool) Pt {
    const x = if (mirror) -p.x else p.x;
    return if (swap) .{ .x = p.y, .y = x } else .{ .x = x, .y = p.y };
}

fn side(swap: bool, mirror: bool) Side {
    return if (swap) (if (mirror) .down else .up) else (if (mirror) .right else .left);
}

fn contact(swap: bool, mirror: bool, physical: bool) !void {
    const gpa = std.testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    const class = try lib.register(.{ .name = "pending_pin", .terminals = &.{.{ .name = "p", .at = .{ .x = 0, .y = 0 }, .side = .left }} });
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{.resistor}, .device_name = &.{"pending"}, .net_name = &.{ "early", "pending" }, .device_pin_count = &.{1}, .roles = &.{ .internal, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    try s.devices.append(s.arena.allocator(), .{ .kept = true, .driver = false, .orientation = .horizontal, .flip_x = false, .flip_y = false, .class = class, .orient = .{}, .grid = .{ .x = 0, .y = 0 }, .reach = @splat(0) });
    const at = transform(.{ .x = 700, .y = 340 }, swap, mirror);
    const node = try s.addNode(.{ .kind = if (physical) .device else .label, .ref = 0, .group = 0 });
    try xy.append(s.arena.allocator(), at.toF());
    _ = try s.addPin(.{ .home = node, .side = side(swap, mirror), .net = 1, .device = if (physical) 0 else sch.none, .index = 0 });
    s.xy = xy.items;
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &.{}, &.{});
    defer c.deinit();
    const early = [_]Pt{ transform(.{ .x = 630, .y = 340 }, swap, mirror), transform(.{ .x = 690, .y = 340 }, swap, mirror) };
    const before = c.save();
    try std.testing.expectEqual(!physical, try c.commit(0, &early));
    if (!physical) return;
    try std.testing.expectEqual(before, c.save());
    // Its own wire may use the escape. A parallel foreign run behind the
    // pin is outside this reservation; device bodies are a separate check.
    try std.testing.expect(c.fits(1, early[0], early[1]));
    try std.testing.expect(c.fits(0, transform(.{ .x = 710, .y = 340 }, swap, mirror), transform(.{ .x = 750, .y = 340 }, swap, mirror)));
    for ([_]i32{ 690, 695 }) |x| {
        const top = transform(.{ .x = x, .y = 300 }, swap, mirror);
        const middle = transform(.{ .x = x, .y = 340 }, swap, mirror);
        const bottom = transform(.{ .x = x, .y = 380 }, swap, mirror);
        try std.testing.expect(c.fits(0, top, bottom));
        try std.testing.expect(!c.fits(0, top, middle));
        try std.testing.expect(!c.fits(0, middle, bottom));
    }
    try std.testing.expect(!c.fits(0, transform(.{ .x = 700, .y = 300 }, swap, mirror), transform(.{ .x = 700, .y = 380 }, swap, mirror)));
    // Even a short actual outward lead releases the reservation. Restore
    // derives it again from the restored ink; no mutable pending flag.
    const cp = c.save();
    const connected = [_]Pt{ at, transform(.{ .x = 695, .y = 340 }, swap, mirror), transform(.{ .x = 695, .y = 300 }, swap, mirror) };
    try std.testing.expect(try c.commit(1, &connected));
    try std.testing.expect(c.fits(0, early[0], early[1]));
    c.restore(cp);
    try std.testing.expect(!c.fits(0, early[0], early[1]));
}

test "pin escape: reserve only actual outward device leads and retain proper perpendicular crossings" {
    for ([_]bool{ false, true }) |swap| for ([_]bool{ false, true }) |mirror| {
        try contact(swap, mirror, true);
        try contact(swap, mirror, false);
    };
}

test "pin escape: an earlier maze route leaves the pending pin a physical route" {
    const gpa = std.testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    const class = try lib.register(.{ .name = "pending_pin", .terminals = &.{.{ .name = "p", .at = .{ .x = 0, .y = 0 }, .side = .left }} });
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{.resistor}, .device_name = &.{"pending"}, .net_name = &.{ "early", "pending" }, .device_pin_count = &.{1}, .roles = &.{ .internal, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    try s.devices.append(s.arena.allocator(), .{ .kept = true, .driver = false, .orientation = .horizontal, .flip_x = false, .flip_y = false, .class = class, .orient = .{}, .grid = .{ .x = 0, .y = 0 }, .reach = @splat(0) });
    const node = try s.addNode(.{ .kind = .device, .ref = 0, .group = 0 });
    try xy.append(s.arena.allocator(), .{ 700, 340 });
    _ = try s.addPin(.{ .home = node, .side = .left, .net = 1, .device = 0, .index = 0 });
    s.xy = xy.items;
    const boxes = [_]library.Rect{.{ .min = .{ .x = 700, .y = 320 }, .max = .{ .x = 740, .y = 360 } }};
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &boxes, &.{});
    defer c.deinit();
    const first = (try maze.route(gpa, .{ .net = 0, .from = .{ .at = .{ .x = 630, .y = 340 }, .side = .right }, .to = .{ .at = .{ .x = 720, .y = 320 }, .side = .up }, .boxes = &boxes, .wires = c.segs.items, .marks = c.points.items, .escapes = c.escapes.slice(), .step = 10, .clear = 10, .bend = 20, .cross = 80 })) orelse return error.MissingFirstRoute;
    defer gpa.free(first);
    try std.testing.expect(try c.commit(0, first));
    const second = (try maze.route(gpa, .{ .net = 1, .from = .{ .at = .{ .x = 700, .y = 340 }, .side = .left }, .to = .{ .at = .{ .x = 600, .y = 290 }, .side = .down }, .boxes = &boxes, .wires = c.segs.items, .marks = c.points.items, .escapes = c.escapes.slice(), .step = 10, .clear = 10, .bend = 20, .cross = 80 })) orelse return error.PendingPinStranded;
    defer gpa.free(second);
    try std.testing.expect(try c.commit(1, second));
    try std.testing.expect(second[1].x < 700 and second[1].y == 340);
    for (first[0 .. first.len - 1], first[1..]) |a, b| {
        // The early net cannot end a horizontal segment ten units in
        // front of the pending pin; that was the literal starvation.
        if (a.y == 340 and b.y == 340) try std.testing.expect(@max(a.x, b.x) <= 680);
    }
}
