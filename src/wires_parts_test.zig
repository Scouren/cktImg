//! Cut-part routing through the complete wires.wire entry point.
//! Oracle: literal facing row endpoints retain actual wire continuity when a
//! remote cluster keeps the net split. Direction, bodies, foreign points and
//! intervening own pins bound the new relation; names never join wire ink.
//!
//! Contents: private route flood-fill and scene helper, then literal tests.

const std = @import("std");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const wires = @import("wires.zig");
const netlines = @import("netlines.zig");

const Pt = library.Pt;
const Side = library.Side;
const Scene = enum { facing, away, same_face, body, foreign_point, own_middle, vertical, whole_net };

// ---- private ----

fn contact(a: [2]f32, b: [2]f32, c: [2]f32, d: [2]f32) bool {
    return @max(@min(a[0], b[0]), @min(c[0], d[0])) <= @min(@max(a[0], b[0]), @max(c[0], d[0])) and
        @max(@min(a[1], b[1]), @min(c[1], d[1])) <= @min(@max(a[1], b[1]), @max(c[1], d[1]));
}

fn contains(r: sch.Route, p: Pt) bool {
    for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |a, b| if (contact(a, b, p.toF(), p.toF())) return true;
    return false;
}

fn meet(a: sch.Route, b: sch.Route) bool {
    for (a.pts[0 .. a.len - 1], a.pts[1..a.len]) |p, q| for (b.pts[0 .. b.len - 1], b.pts[1..b.len]) |r, s| {
        if (contact(p, q, r, s)) return true;
    };
    return false;
}

fn joined(routes: []const sch.Route, net: u32, from: Pt, to: Pt) !bool {
    const reached = try std.testing.allocator.alloc(bool, routes.len);
    defer std.testing.allocator.free(reached);
    for (routes, reached) |r, *seen| seen.* = r.net == net and contains(r, from);
    for (0..routes.len) |_| {
        var changed = false;
        for (routes, reached) |r, seen| {
            if (!seen) continue;
            if (contains(r, to)) return true;
            for (routes, reached) |q, *other| {
                if (other.* or q.net != net or !meet(r, q)) continue;
                other.* = true;
                changed = true;
            }
        }
        if (!changed) break;
    }
    return false;
}

fn reflected(p: Pt, mirror: bool) Pt {
    return .{ .x = if (mirror) -p.x else p.x, .y = p.y };
}

fn scene(which: Scene, mirror: bool, reversed: bool) !void {
    const gpa = std.testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "signal", "foreign" }, .device_pin_count = &.{}, .roles = &.{ .internal, .internal } };
    defer s.deinit();
    const arena = s.arena.allocator();
    s.labeled = try arena.alloc(bool, 2);
    @memset(s.labeled, false);
    var xy: std.ArrayList([2]f32) = .empty;
    const right: i32 = if (which == .own_middle) 620 else 180;
    const main: [2]Pt = if (which == .vertical)
        .{ .{ .x = 20, .y = 100 }, .{ .x = 20, .y = 460 } }
    else
        .{ .{ .x = 20, .y = 100 }, .{ .x = right, .y = 100 } };
    const facing: [2]Side = switch (which) {
        .away => .{ .left, .right },
        .same_face => .{ .right, .right },
        .vertical => .{ .down, .up },
        else => .{ .right, .left },
    };
    const points = [_]Pt{ main[0], main[1], .{ .x = 1000, .y = 700 }, .{ .x = 1040, .y = 700 }, .{ .x = if (which == .own_middle) 320 else 100, .y = 100 } };
    const sides = [_]Side{ facing[0], facing[1], .right, .left, .up };
    const count: usize = if (which == .whole_net) 2 else if (which == .own_middle or which == .foreign_point) 5 else 4;
    for (0..count) |i| {
        const k = if (reversed) count - 1 - i else i;
        const node = try s.addNode(.{ .kind = .terminal, .ref = 0, .group = sch.none });
        try xy.append(arena, reflected(points[k], mirror).toF());
        _ = try s.addPin(.{ .home = node, .side = if (mirror) sides[k].flipX() else sides[k], .net = if (which == .foreign_point and k == 4) 1 else 0, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    var boxes: std.ArrayList(library.Rect) = .empty;
    if (which != .vertical) {
        try boxes.append(arena, .{ .min = .{ .x = if (which == .away) 20 else -20, .y = 80 }, .max = .{ .x = if (which == .away) 60 else 20, .y = 120 } });
        try boxes.append(arena, .{ .min = .{ .x = if (which == .away or which == .same_face) right - 40 else right, .y = 80 }, .max = .{ .x = if (which == .away or which == .same_face) right else right + 40, .y = 120 } });
    }
    if (which == .body) try boxes.append(arena, .{ .min = .{ .x = 80, .y = 80 }, .max = .{ .x = 120, .y = 120 } });
    if (mirror) for (boxes.items) |*b| {
        b.* = .fromCorners(reflected(b.min, true), reflected(b.max, true));
    };
    const lines: netlines.NetLines = .{ .style = &.{ .cut, .label }, .port = &.{ null, null }, .rail = &.{ .auto, .auto }, .first = &.{}, .routes = &.{} };
    try wires.wire(gpa, &s, &xy, .of(.{}, 40), boxes.items, &.{}, null, &.{ 0, 1 }, &lines, &.{});
    const a = reflected(main[0], mirror);
    const b = reflected(main[1], mirror);
    try std.testing.expectEqual(which == .facing, try joined(s.routes.items, 0, a, b));
    try std.testing.expect(s.labeled[0]);
    if (which != .whole_net) {
        const c = reflected(points[2], mirror);
        const d = reflected(points[3], mirror);
        try std.testing.expect(try joined(s.routes.items, 0, c, d));
        try std.testing.expect(!try joined(s.routes.items, 0, a, c));
    }
}

// ---- tests ----

test "wires cut parts: physical oracle rejects gaps and foreign ink" {
    var routes = [_]sch.Route{
        .{ .net = 0, .len = 2, .pts = .{ .{ 0, 0 }, .{ 10, 0 }, undefined, undefined, undefined, undefined } },
        .{ .net = 0, .len = 2, .pts = .{ .{ 10, 0 }, .{ 10, 10 }, undefined, undefined, undefined, undefined } },
    };
    const a: Pt = .{ .x = 0, .y = 0 };
    const b: Pt = .{ .x = 10, .y = 10 };
    try std.testing.expect(try joined(&routes, 0, a, b));
    routes[1].pts[0] = .{ 10, 1 };
    try std.testing.expect(!try joined(&routes, 0, a, b));
    routes[1].pts[0] = .{ 10, 0 };
    routes[1].net = 1;
    try std.testing.expect(!try joined(&routes, 0, a, b));
}

test "wires cut parts: consecutive facing row pins stay wired beyond the fitted distance" {
    // Unit40: two horizontal pins ordinarily split beyond120; this gap160
    // is clear. A remote40-unit cluster makes this a genuinely parted net.
    for ([_]bool{ false, true }) |mirror| for ([_]bool{ false, true }) |reversed| {
        try scene(.facing, mirror, reversed);
    };
}

test "wires cut parts: direction body foreign-point and intervening-pin boundaries abstain" {
    // The own-middle scene uses600 total/300 adjacent gaps so ordinary
    // distance grouping cannot disguise the forbidden nonconsecutive join.
    for ([_]Scene{ .away, .same_face, .body, .foreign_point, .own_middle, .vertical }) |which| {
        for ([_]bool{ false, true }) |mirror| for ([_]bool{ false, true }) |reversed| {
            try scene(which, mirror, reversed);
        };
    }
}

test "wires cut parts: a complete single part still uses names at its pins" {
    for ([_]bool{ false, true }) |mirror| try scene(.whole_net, mirror, false);
}
