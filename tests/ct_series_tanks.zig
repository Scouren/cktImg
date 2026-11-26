//! Complete AG1153 deck -> source-relative L-C-L tank geometry and ink.
//! Oracle: actual transformed SVG leads and eight conductor paths recorded
//! in docs/research/figures/ct_series_tanks_cases.json. The two correlated
//! groups have opposite world directions; only tap-relative order is fixed.
//! Distances and global placement are deliberately unconstrained.
//!
//! Contents: literal source frames, actual-terminal reader, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const deck = @embedFile("ct_series_tanks_fixture.sp");
const Frame = [9]np.Pt;
const groups = [2][4][]const u8{ .{ "xl1", "ls1", "ls2", "c1" }, .{ "xl2", "ls3", "ls4", "c2" } };
const nets = [2][5][]const u8{ .{ "p4", "m4", "vdd", "p2", "m2" }, .{ "p3", "m3", "vdd", "p1", "m1" } };
// Winding N1/N2/tap, first inductor near/far, second near/far, capacitor
// first/second far-net ends. These are literal source coordinates.
const source = [2]Frame{
    .{ .{ .x = 250, .y = 210 }, .{ .x = 350, .y = 210 }, .{ .x = 300, .y = 230 }, .{ .x = 230, .y = 200 }, .{ .x = 230, .y = 160 }, .{ .x = 370, .y = 200 }, .{ .x = 370, .y = 160 }, .{ .x = 280, .y = 150 }, .{ .x = 320, .y = 150 } },
    .{ .{ .x = 250, .y = 290 }, .{ .x = 350, .y = 290 }, .{ .x = 300, .y = 270 }, .{ .x = 230, .y = 300 }, .{ .x = 230, .y = 340 }, .{ .x = 370, .y = 300 }, .{ .x = 370, .y = 340 }, .{ .x = 280, .y = 350 }, .{ .x = 320, .y = 350 } },
};

// ---- private ----

fn geometry(points: Frame) bool {
    const horizontal = points[0].y == points[1].y and points[0].x != points[1].x;
    const vertical = points[0].x == points[1].x and points[0].y != points[1].y;
    if (!horizontal and !vertical) return false;
    var q: [9][2]i64 = undefined;
    for (points, &q) |p, *v| v.* = if (horizontal) .{ p.x, p.y } else .{ p.y, p.x };
    const center = q[0][0] + q[1][0];
    const row = q[0][1];
    if (2 * q[2][0] != center or q[2][1] == row) return false;
    const along: i64 = if (q[1][0] > q[0][0]) 1 else -1;
    const away: i64 = if (q[2][1] > row) -1 else 1;
    for (&q) |*v| v.* = .{ (2 * v[0] - center) * along, (v[1] - row) * away };
    if (q[3][0] != q[4][0] or q[5][0] != q[6][0]) return false;
    if (q[3][1] != q[5][1] or q[4][1] != q[6][1]) return false;
    if (q[7][1] != q[8][1] or q[7][0] + q[8][0] != 0) return false;
    if (!(q[3][0] < q[0][0] and q[0][0] < q[7][0] and q[7][0] < 0)) return false;
    if (!(0 < q[8][0] and q[8][0] < q[1][0] and q[1][0] < q[5][0])) return false;
    return 0 < q[3][1] and q[3][1] < q[4][1] and q[4][1] < q[7][1];
}

fn pins(p: *const np.Placed, lib: *const np.Library, group: usize) ![9]usize {
    const ds = groups[group];
    const ns = nets[group];
    const named = [9][2][]const u8{
        .{ ds[0], ns[0] }, .{ ds[0], ns[1] }, .{ ds[0], ns[2] },
        .{ ds[1], ns[0] }, .{ ds[1], ns[3] }, .{ ds[2], ns[1] }, .{ ds[2], ns[4] },
        .{ ds[3], ns[3] }, .{ ds[3], ns[4] },
    };
    var result: [9]usize = undefined;
    for (named, &result) |want, *out| {
        const d = np.checks.deviceIn(p, want[0]) orelse return error.MissingDevice;
        const lo, const hi = p.pinRange(d);
        const class = lib.at(p.dev_class[d]);
        var found: ?usize = null;
        for (lo..hi) |pin| {
            if (!std.mem.eql(u8, want[1], p.net_name[p.pin_net[pin]])) continue;
            try testing.expect(found == null);
            try testing.expect(pin - lo < class.terminals.len);
            try testing.expect(!class.terminals[pin - lo].hidden);
            try testing.expectEqualDeep(p.dev_pos[d].add(p.dev_orient[d].apply(class.terminals[pin - lo].at)), p.pin_xy[pin]);
            found = pin;
        }
        out.* = found orelse return error.MissingBinding;
    }
    return result;
}

test "CT series tanks: literal source frames and eight poses define relative order" {
    for (source) |original| {
        try testing.expect(geometry(original));
        for (0..8) |i| {
            const pose: np.library.Orient = .{ .rot = @intCast(i % 4), .mirror = i >= 4 };
            var transformed = original;
            for (&transformed) |*p| p.* = pose.apply(p.*).add(.{ .x = 37, .y = -91 });
            try testing.expect(geometry(transformed));
        }
    }
    for ([_]struct { index: usize, point: np.Pt }{
        .{ .index = 2, .point = .{ .x = 300, .y = 190 } },
        .{ .index = 4, .point = .{ .x = 240, .y = 160 } },
        .{ .index = 7, .point = .{ .x = 270, .y = 150 } },
        .{ .index = 3, .point = .{ .x = 230, .y = 190 } },
    }) |mutation| {
        var bad = source[0];
        bad[mutation.index] = mutation.point;
        try testing.expect(!geometry(bad));
    }
    var reversed = source[0];
    std.mem.swap(np.Pt, &reversed[7], &reversed[8]);
    try testing.expect(!geometry(reversed));
}

test "CT series tanks: complete source places both series branches opposite their taps" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        for (groups, 0..) |group, index| {
            errdefer std.debug.print("series source geometry {s}, compact={}\n", .{ group[0], compact });
            var actual: Frame = undefined;
            for (try pins(&p, lib, index), &actual) |pin, *point| point.* = p.pin_xy[pin];
            try testing.expect(geometry(actual));
        }
        try support.expectConnected(&p, lib);
        try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, &p, true));
    }
}

test "CT series tanks: all eight source paths use physical wire ink" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        for (groups, 0..) |group, index| {
            const actual = try pins(&p, lib, index);
            for ([_][2]usize{ .{ 0, 3 }, .{ 1, 5 }, .{ 4, 7 }, .{ 6, 8 } }) |pair| {
                errdefer std.debug.print("series source ink {s}, compact={}, pair={any}\n", .{ group[0], compact, pair });
                try testing.expect(try ink.connected(testing.allocator, &p, &.{ actual[pair[0]], actual[pair[1]] }));
            }
        }
    }
}

test "CT series tanks: reordered declaration and reversed passive cards preserve geometry and eight paths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var changed: []const u8 = deck;
    for ([_][2][]const u8{
        .{ "ct_inductor n1 n2 n3 params:", "ct_inductor n3 n2 n1 params:" },
        .{ "XL1 P4 M4 Vdd ct_inductor", "XL1 Vdd M4 P4 ct_inductor" },
        .{ "XL2 P3 M3 Vdd ct_inductor", "XL2 Vdd M3 P3 ct_inductor" },
        .{ "C1 M2 P2 1p", "C1 P2 M2 1p" }, .{ "C2 M1 P1 1p", "C2 P1 M1 1p" },
        .{ "LS1 P2 P4 1n\nLS2 M2 M4 1n", "LS2 M4 M2 1n\nLS1 P4 P2 1n" },
        .{ "LS3 P3 P1 1n\nLS4 M3 M1 1n", "LS4 M1 M3 1n\nLS3 P1 P3 1n" },
    }) |pair| {
        try testing.expect(std.mem.indexOf(u8, changed, pair[0]) != null);
        changed = try std.mem.replaceOwned(u8, a, changed, pair[0], pair[1]);
    }
    // The reordered declaration owns a fresh registered class contract.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{changed}, null);
        defer p.deinit();
        for (groups, 0..) |group, index| {
            errdefer std.debug.print("series reordered {s}, compact={}\n", .{group[0], compact});
            const actual = try pins(&p, lib, index);
            var points: Frame = undefined;
            for (actual, &points) |pin, *point| point.* = p.pin_xy[pin];
            try testing.expect(geometry(points));
            for ([_][2]usize{ .{0,3}, .{1,5}, .{4,7}, .{6,8} }) |pair| {
                try testing.expect(try ink.connected(testing.allocator, &p, &.{actual[pair[0]], actual[pair[1]]}));
            }
        }
    }
}

test "CT series tanks: explicit absolute passive pose remains honoured" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try a.print("{s}\n*@ at ls1 -100 -100 r0\n", .{deck});
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var nl = try np.netlist.parse(a, &.{text}, null);
    try testing.expectEqual(@as(usize, 7), nl.hints.len);
    try testing.expectEqual(np.hints.Verb.at, nl.hints[6].verb);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(testing.allocator, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(testing.allocator, a, &nl, roles, &st, .{});
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        const verdicts = try np.report.verdicts(a, &nl, roles, &st, &sk, &p, lib);
        try testing.expectEqual(np.hints.State.honoured, verdicts[6].state);
        const d = np.checks.deviceIn(&p, "ls1").?;
        try testing.expectEqualDeep(np.Pt{ .x=-100*lib.unit, .y=-100*lib.unit }, p.dev_pos[d]);
        try testing.expectEqualDeep(np.library.Orient.r0, p.dev_orient[d]);
    }
}
