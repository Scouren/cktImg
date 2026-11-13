//! Rung-tap regressions through the public trunk drawing boundary.
//! Oracle: literal Manhattan gate interval, foreign-wire endpoint exclusion,
//! unchanged canvas on failure, and reflected/permuted segment geometry.
//! AG981/984/986 retain straight source gate lines whose native midpoint
//! falls on an earlier net's vertical wire. A proper crossing elsewhere
//! on that gate line remains legal; a T junction on the foreign wire does not.
//!
//! Contents: tests only.

const std = @import("std");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const trunk = @import("trunk.zig");

const Pt = library.Pt;
const Side = library.Side;
const Barrier = enum { none, midpoint, all_taps, collinear };
const Segment = [5]i32;

// ---- private ----

fn reflected(p: Pt, mirror: bool) Pt {
    return .{ .x = if (mirror) -p.x else p.x, .y = p.y };
}

fn less(_: void, a: Segment, b: Segment) bool {
    for (a, b) |x, y| {
        if (x != y) return x < y;
    }
    return false;
}

/// Own the temporary canvas here; return the normalized physical tree.
/// Exclude its output stub: trunk.12's right-on-a-tie port side is a separate
/// policy. Undo the requested reflection before comparing the local tree.
fn draw(gpa: std.mem.Allocator, barrier: Barrier, mirror: bool, order: [3]u32) ![]Segment {
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "signal", "other" }, .device_pin_count = &.{}, .roles = &.{ .output, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    const terminals = [_]Pt{ .{ .x = 20, .y = 100 }, .{ .x = 80, .y = 100 }, .{ .x = 180, .y = 120 } };
    for (terminals, [_]Side{ .right, .left, .down }) |at, side| {
        const node = try s.addNode(.{ .kind = .terminal, .ref = 0, .group = sch.none });
        try xy.append(s.arena.allocator(), reflected(at, mirror).toF());
        _ = try s.addPin(.{ .home = node, .side = if (mirror and side.isHorizontal()) side.opposite() else side, .net = 0, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    var boxes = [_]library.Rect{
        .{ .min = .{ .x = -20, .y = 80 }, .max = .{ .x = 20, .y = 120 } },
        .{ .min = .{ .x = 80, .y = 90 }, .max = .{ .x = 120, .y = 110 } },
        .{ .min = .{ .x = 170, .y = 80 }, .max = .{ .x = 190, .y = 120 } },
    };
    if (mirror) for (&boxes) |*box| {
        box.* = .fromCorners(reflected(box.min, true), reflected(box.max, true));
    };
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &boxes, &.{});
    defer c.deinit();
    if (barrier == .midpoint or barrier == .all_taps) {
        const columns: []const i32 = if (barrier == .midpoint) &.{50} else &.{ 40, 50, 60 };
        for (columns) |x| try std.testing.expect(try c.commit(1, &.{
            reflected(.{ .x = x, .y = 40 }, mirror),
            reflected(.{ .x = x, .y = 200 }, mirror),
        }));
    } else if (barrier == .collinear) {
        try std.testing.expect(try c.commit(1, &.{
            reflected(.{ .x = 30, .y = 100 }, mirror),
            reflected(.{ .x = 70, .y = 100 }, mirror),
        }));
    }
    const before = c.save();
    const fits = try trunk.draw(&c, 0, &order, .port);
    const expected = barrier == .none or barrier == .midpoint;
    try std.testing.expectEqual(expected, fits);
    if (!expected) {
        try std.testing.expectEqual(before, c.save());
        try std.testing.expect(!c.onNet(0, reflected(.{ .x = 50, .y = 100 }, mirror)));
    } else {
        // Every point, including the crossing, must belong to signal ink.
        // Labels, the foreign wire, and a U detour cannot fill this interval.
        for (20..81) |x| try std.testing.expect(c.onNet(0, reflected(.{ .x = @intCast(x), .y = 100 }, mirror)));
        for (terminals) |at| try std.testing.expect(c.onNet(0, reflected(at, mirror)));
        if (barrier == .none) {
            // The right neighbor would shorten this tree, but a legal
            // midpoint keeps precedence over every alternative tap.
            const middle = reflected(.{ .x = 50, .y = 100 }, mirror);
            const kept = for (c.segs.items) |segment| {
                if (segment.net == 0 and segment.a.x == middle.x and segment.b.x == middle.x and
                    @min(segment.a.y, segment.b.y) == middle.y and @max(segment.a.y, segment.b.y) > middle.y) break true;
            } else false;
            try std.testing.expect(kept);
        }
        if (barrier == .midpoint) {
            try std.testing.expect(c.onNet(1, reflected(.{ .x = 50, .y = 100 }, mirror)));
            // Both wires may cross in their interiors. No signal endpoint
            // may turn that crossing into a junction with the foreign net.
            for (c.segs.items) |segment| if (segment.net == 0) {
                try std.testing.expect(!c.onNet(1, segment.a));
                try std.testing.expect(!c.onNet(1, segment.b));
            };
        }
    }
    const port_at: ?Pt = if (expected) port: {
        try std.testing.expectEqual(4, s.pins.len);
        try std.testing.expectEqual(sch.NodeKind.terminal, s.nodes.items(.kind)[s.nodes.len - 1]);
        break :port canvas.pinAt(&s, 3);
    } else null;
    const out = try gpa.alloc(Segment, c.segs.items.len - @intFromBool(port_at != null));
    errdefer gpa.free(out);
    var used: usize = 0;
    for (c.segs.items) |segment| {
        if (port_at) |at| if (segment.net == 0 and (segment.a.eql(at) or segment.b.eql(at))) continue;
        const a = reflected(segment.a, mirror);
        const b = reflected(segment.b, mirror);
        try std.testing.expect(used < out.len);
        out[used] = .{ @intCast(segment.net), @min(a.x, b.x), @min(a.y, b.y), @max(a.x, b.x), @max(a.y, b.y) };
        used += 1;
    }
    try std.testing.expectEqual(out.len, used);
    std.sort.heap(Segment, out, {}, less);
    return out;
}

test "trunk taps: a blocked midpoint keeps the full straight gate interval" {
    const gpa = std.testing.allocator;
    const segments = try draw(gpa, .midpoint, false, .{ 0, 1, 2 });
    defer gpa.free(segments);
}

test "trunk taps: blocked alternatives and foreign collinear ink keep the canvas unchanged" {
    const gpa = std.testing.allocator;
    for ([_]Barrier{ .none, .all_taps, .collinear }) |barrier| {
        const segments = try draw(gpa, barrier, false, .{ 0, 1, 2 });
        defer gpa.free(segments);
    }
}

test "trunk taps: pin permutation and reflection retain the same physical tree" {
    const gpa = std.testing.allocator;
    const baseline = try draw(gpa, .midpoint, false, .{ 0, 1, 2 });
    defer gpa.free(baseline);
    // The third terminal is to the right, so the nearer legal tap also
    // avoids a second crossing. Reflecting the whole scene must reflect
    // that choice; a fixed left-first fallback cannot claim symmetry.
    for ([_]bool{ false, true }) |mirror| for ([_][3]u32{
        .{ 0, 1, 2 }, .{ 2, 1, 0 }, .{ 1, 2, 0 },
    }) |order| {
        const changed = try draw(gpa, .midpoint, mirror, order);
        defer gpa.free(changed);
        try std.testing.expectEqualSlices(Segment, baseline, changed);
    };
}

test "trunk taps: an offset without a required input port keeps the half row available" {
    // Literal oracle: the full row y=140 cannot use midpoint x=50, and
    // either neighboring tap has no right port at x=200. The left end is
    // inside the gate interval, so its port would point back into the net.
    // The half row y=130 has a clear midpoint, trunk and right input port.
    const gpa = std.testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "signal", "other" }, .device_pin_count = &.{}, .roles = &.{ .input, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    const terminals = [_]Pt{ .{ .x = 20, .y = 100 }, .{ .x = 80, .y = 100 }, .{ .x = 180, .y = 120 } };
    for (terminals, [_]Side{ .right, .left, .down }) |at, side| {
        const node = try s.addNode(.{ .kind = .terminal, .ref = 0, .group = sch.none });
        try xy.append(s.arena.allocator(), at.toF());
        _ = try s.addPin(.{ .home = node, .side = side, .net = 0, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    const boxes = [_]library.Rect{
        .{ .min = .{ .x = -20, .y = 80 }, .max = .{ .x = 20, .y = 120 } },
        .{ .min = .{ .x = 80, .y = 90 }, .max = .{ .x = 120, .y = 110 } },
        .{ .min = .{ .x = 170, .y = 80 }, .max = .{ .x = 190, .y = 120 } },
    };
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &boxes, &.{});
    defer c.deinit();
    for ([_][2]Pt{
        .{ .{ .x = 50, .y = 134 }, .{ .x = 50, .y = 136 } },
        .{ .{ .x = 190, .y = 139 }, .{ .x = 190, .y = 141 } },
        .{ .{ .x = 0, .y = 60 }, .{ .x = 250, .y = 60 } },
    }) |barrier| try std.testing.expect(try c.commit(1, &barrier));
    try std.testing.expect(try trunk.draw(&c, 0, &.{ 0, 1, 2 }, .port));
    for (20..81) |x| try std.testing.expect(c.onNet(0, .{ .x = @intCast(x), .y = 100 }));
    for (100..131) |y| try std.testing.expect(c.onNet(0, .{ .x = 50, .y = @intCast(y) }));
    for (50..201) |x| try std.testing.expect(c.onNet(0, .{ .x = @intCast(x), .y = 130 }));
    for (terminals) |at| try std.testing.expect(c.onNet(0, at));
    try std.testing.expectEqual(4, s.pins.len);
    try std.testing.expectEqual(Pt{ .x = 200, .y = 130 }, canvas.pinAt(&s, 3));
    try std.testing.expectEqual(sch.NodeKind.terminal, s.nodes.items(.kind)[s.nodes.len - 1]);
    for (c.segs.items) |segment| if (segment.net == 0) {
        try std.testing.expect(!c.onNet(1, segment.a));
        try std.testing.expect(!c.onNet(1, segment.b));
    };
}
