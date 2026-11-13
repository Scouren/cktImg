//! Horizontal trunk-row contact regressions through public trunk.draw.
//! Oracle: the literal interval between facing pins crosses foreign ink
//! properly, even where a synthetic half-unit approach would end on it.
//! A foreign endpoint or overlap still forbids that interval; reversed
//! pin departures must route around their actual bodies.
//!
//! Contents: private scene helper, then literal contact tests.

const std = @import("std");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const trunk = @import("trunk.zig");

const Pt = library.Pt;
const Side = library.Side;
const Scene = enum { clear, proper, endpoint, overlap, away };

// ---- private ----

fn reflected(p: Pt, mirror: bool) Pt {
    return .{ .x = if (mirror) -p.x else p.x, .y = p.y };
}

fn scene(gpa: std.mem.Allocator, which: Scene, mirror: bool, order: [2]u32) !void {
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "signal", "other" }, .device_pin_count = &.{}, .roles = &.{ .internal, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    const terminals = [_]Pt{ .{ .x = 20, .y = 100 }, .{ .x = 90, .y = 100 } };
    const sides: [2]Side = if (which == .away) .{ .left, .right } else .{ .right, .left };
    for (terminals, sides) |at, side| {
        const node = try s.addNode(.{ .kind = .terminal, .ref = 0, .group = sch.none });
        try xy.append(s.arena.allocator(), reflected(at, mirror).toF());
        _ = try s.addPin(.{ .home = node, .side = if (mirror) side.opposite() else side, .net = 0, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    // Each terminal is on its body's outward boundary in both scenes.
    var boxes = [_]library.Rect{
        .{ .min = .{ .x = if (which == .away) 20 else -20, .y = 80 }, .max = .{ .x = if (which == .away) 40 else 20, .y = 120 } },
        .{ .min = .{ .x = if (which == .away) 70 else 90, .y = 80 }, .max = .{ .x = if (which == .away) 90 else 130, .y = 120 } },
    };
    if (mirror) for (&boxes) |*box| {
        box.* = .fromCorners(reflected(box.min, true), reflected(box.max, true));
    };
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &boxes, &.{});
    defer c.deinit();
    const foreign: ?[2]Pt = switch (which) {
        .proper => .{ .{ .x = 40, .y = 40 }, .{ .x = 40, .y = 200 } },
        .endpoint => .{ .{ .x = 40, .y = 100 }, .{ .x = 40, .y = 200 } },
        .overlap => .{ .{ .x = 30, .y = 100 }, .{ .x = 70, .y = 100 } },
        else => null,
    };
    if (foreign) |ends| try std.testing.expect(try c.commit(1, &.{ reflected(ends[0], mirror), reflected(ends[1], mirror) }));
    const before = c.save();
    const drawn = try trunk.draw(&c, 0, &order, .name);
    if (which == .endpoint or which == .overlap) {
        try std.testing.expect(!drawn);
        try std.testing.expectEqual(before, c.save());
        return;
    }
    try std.testing.expect(drawn);
    if (which == .clear) {
        // Original legal candidate, including its name stub, retained
        // exactly: a new unsplit row must not replace it at a lower cost.
        const expected = [_][2]Pt{
            .{ terminals[order[0]], .{ .x = if (order[0] == 0) 40 else 70, .y = 100 } },
            .{ terminals[order[1]], .{ .x = if (order[1] == 0) 40 else 70, .y = 100 } },
            .{ .{ .x = 40, .y = 100 }, .{ .x = 70, .y = 100 } },
            .{ .{ .x = if (mirror) 90 else 20, .y = 100 }, .{ .x = if (mirror) 70 else 40, .y = 100 } },
        };
        try std.testing.expectEqual(expected.len, c.segs.items.len);
        for (expected, c.segs.items) |want, actual| {
            const a = reflected(want[0], mirror);
            const b = reflected(want[1], mirror);
            try std.testing.expect((actual.a.eql(a) and actual.b.eql(b)) or (actual.a.eql(b) and actual.b.eql(a)));
        }
        try std.testing.expectEqual(@as(usize, 3), s.nodes.len);
        try std.testing.expectEqual(sch.NodeKind.label, s.nodes.items(.kind)[2]);
    }
    if (which == .away) {
        // The middle is clear, but reaching it directly would enter both
        // symbol bodies against the pins' outward directions.
        try std.testing.expect(!c.onNet(0, reflected(.{ .x = 55, .y = 100 }, mirror)));
    } else {
        // Labels and other-net ink cannot fill any part of this interval.
        for (20..91) |x| try std.testing.expect(c.onNet(0, reflected(.{ .x = @intCast(x), .y = 100 }, mirror)));
    }
    for (terminals, sides) |at, side| {
        const point = reflected(at, mirror);
        const facing = if (mirror) side.opposite() else side;
        var leaves = false;
        for (c.segs.items) |segment| if (segment.net == 0) {
            const other = if (segment.a.eql(point)) segment.b else if (segment.b.eql(point)) segment.a else continue;
            if (other.eql(point)) continue;
            leaves = true;
            try std.testing.expectEqual(facing.unit(), (Pt{ .x = std.math.sign(other.x - point.x), .y = std.math.sign(other.y - point.y) }));
        };
        try std.testing.expect(leaves);
    }
    if (which == .proper) {
        const crossing = reflected(.{ .x = 40, .y = 100 }, mirror);
        try std.testing.expect(c.onNet(1, crossing));
        for (c.segs.items) |segment| if (segment.net == 0) {
            try std.testing.expect(!c.onNet(1, segment.a));
            try std.testing.expect(!c.onNet(1, segment.b));
        };
    }
}

test "trunk row: a proper crossing at the half-unit approach keeps the whole facing interval" {
    for ([_]bool{ false, true }) |mirror| for ([_][2]u32{ .{ 0, 1 }, .{ 1, 0 } }) |order| {
        try scene(std.testing.allocator, .clear, mirror, order);
        try scene(std.testing.allocator, .proper, mirror, order);
    };
}

test "trunk row: foreign endpoint and overlap contacts leave the canvas unchanged" {
    for ([_]bool{ false, true }) |mirror| for ([_]Scene{ .endpoint, .overlap }) |which| {
        try scene(std.testing.allocator, which, mirror, .{ 0, 1 });
    };
}

test "trunk row: outward pins keep their departures and route around their bodies" {
    for ([_]bool{ false, true }) |mirror| for ([_][2]u32{ .{ 0, 1 }, .{ 1, 0 } }) |order| {
        try scene(std.testing.allocator, .away, mirror, order);
    };
}
