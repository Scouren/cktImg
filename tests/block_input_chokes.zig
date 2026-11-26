//! Bias-choke source relations beside the paired input RC branches.
//! Oracle: AG1103 R3/R4 bias tips (50,370)/(70,370) join LBW5's actual
//! bias tip (30,380); its far tip is (-10,380). X3 is the reflected case.
//! The choke is beyond the paired bias row, not collinear with the R tips.
//! Only each local three-tip tree is required; the three remote V_bias
//! source pieces are separate. Future tests, intentionally not imported.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const source = @embedFile("block_input_rc_fixture.sp");
const Group = struct {
    block: []const u8,
    resistors: [2][]const u8,
    choke: []const u8,
    bias: []const u8,
};
const groups = [_]Group{
    .{ .block = "x2", .resistors = .{ "r3", "r4" }, .choke = "lbw5", .bias = "net15" },
    .{ .block = "x3", .resistors = .{ "r5", "r6" }, .choke = "lbw6", .bias = "net17" },
};

// ---- private ----

fn dot(p: np.Pt, axis: np.Pt) i64 {
    return @as(i64, p.x) * axis.x + @as(i64, p.y) * axis.y;
}

// INP, INN, the two resistor bias tips, choke bias tip, choke far tip.
fn relative(q: [6]np.Pt, outward: np.Side) bool {
    const w = (np.Side.of(q[1].sub(q[0])) orelse return false).unit();
    const u = outward.unit();
    if (dot(u, w) != 0 or dot(q[0], u) != dot(q[1], u)) return false;
    return dot(q[4], w) == dot(q[5], w) and
        dot(q[2], w) == dot(q[3], w) and dot(q[3], w) < dot(q[4], w) and
        dot(q[2], u) < dot(q[4], u) and dot(q[4], u) < dot(q[5], u);
}

fn named(p: *const np.Placed, lib: *const np.Library, name: []const u8, port: []const u8) !usize {
    const device = np.checks.deviceIn(p, name) orelse return error.MissingDevice;
    for (lib.at(p.dev_class[device]).terminals, 0..) |terminal, i| {
        if (std.ascii.eqlIgnoreCase(terminal.name, port)) return p.dev_pin0[device] + i;
    }
    return error.MissingTerminal;
}

fn onNet(p: *const np.Placed, name: []const u8, net: []const u8) !usize {
    const device = np.checks.deviceIn(p, name) orelse return error.MissingDevice;
    const lo, const hi = p.pinRange(device);
    var result: ?usize = null;
    for (lo..hi) |pin| if (std.mem.eql(u8, p.net_name[p.pin_net[pin]], net)) {
        try testing.expect(result == null);
        result = pin;
    };
    return result orelse error.MissingNet;
}

fn indices(p: *const np.Placed, lib: *const np.Library, group: Group) ![6]usize {
    return .{
        try named(p, lib, group.block, "inp"), try named(p, lib, group.block, "inn"),
        try onNet(p, group.resistors[0], group.bias), try onNet(p, group.resistors[1], group.bias),
        try onNet(p, group.choke, group.bias), try onNet(p, group.choke, "v_bias"),
    };
}

fn geometry(p: *const np.Placed, lib: *const np.Library, group: Group) !void {
    const pins = try indices(p, lib, group);
    const device = np.checks.deviceIn(p, group.block).?;
    const class = lib.at(p.dev_class[device]);
    const pose = p.dev_orient[device];
    const outward = class.side(pins[0] - p.dev_pin0[device], pose) orelse return error.MissingInputSide;
    try testing.expectEqual(outward, class.side(pins[1] - p.dev_pin0[device], pose).?);
    var tips: [6]np.Pt = undefined;
    const names = [_][]const u8{ group.block, group.block, group.resistors[0], group.resistors[1], group.choke, group.choke };
    for (pins, &tips, names) |pin, *tip, name| {
        tip.* = p.pin_xy[pin];
        const owner = np.checks.deviceIn(p, name).?;
        const local = lib.at(p.dev_class[owner]).terminals[pin - p.dev_pin0[owner]].at;
        try testing.expectEqualDeep(p.dev_pos[owner].add(p.dev_orient[owner].apply(local)), tip.*);
    }
    try testing.expect(relative(tips, outward));
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, p, true));
}

test "block input chokes: literal stepped source frame survives eight poses and detects row and polarity mutations" {
    const q = [6]np.Pt{
        .{ .x = 90, .y = 270 }, .{ .x = 90, .y = 310 },
        .{ .x = 50, .y = 370 }, .{ .x = 70, .y = 370 },
        .{ .x = 30, .y = 380 }, .{ .x = -10, .y = 380 },
    };
    try testing.expect(relative(q, .left));
    for (0..8) |i| {
        const pose: np.Orient = .{ .rot = @intCast(i & 3), .mirror = i >= 4 };
        var moved: [6]np.Pt = undefined;
        for (q, &moved) |v, *at| at.* = pose.apply(v).add(.{ .x = 137, .y = -49 });
        try testing.expect(relative(moved, np.Side.of(pose.apply(np.Side.left.unit())).?));
    }
    var wrong = q;
    std.mem.swap(np.Pt, &wrong[4], &wrong[5]);
    try testing.expect(!relative(wrong, .left));
    wrong = q;
    wrong[5].y += 1;
    try testing.expect(!relative(wrong, .left));
    wrong = q;
    wrong[4].y = 370;
    wrong[5].y = 370;
    try testing.expect(!relative(wrong, .left));
    wrong = q;
    wrong[4].x = 60;
    try testing.expect(!relative(wrong, .left));
}

test "block input chokes: AG1103 actual bias chokes sit beyond the RC bias row and outward of the first resistor" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{source}, null);
        defer p.deinit();
        try electrical(&p, lib);
        for (groups) |group| {
            errdefer std.debug.print("AG1103 choke frame {s} compact={}\n", .{ group.choke, compact });
            try geometry(&p, lib, group);
        }
    }
}

test "block input chokes: each local three-tip bias tree retains physical ink under reversed choke cards" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var changed: []const u8 = source;
    for ([_][2][]const u8{
        .{ "LBW5 V_bias net15", "Lfeed_left net15 V_bias" },
        .{ "LBW6 net17 V_bias", "Lfeed_right V_bias net17" },
    }) |edit| {
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, changed, edit[0]));
        changed = try std.mem.replaceOwned(u8, a, changed, edit[0], edit[1]);
    }
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{ source, changed }, 0..) |text, variant| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        try electrical(&p, lib);
        for (groups, 0..) |original, i| {
            var group = original;
            if (variant == 1) group.choke = if (i == 0) "lfeed_left" else "lfeed_right";
            errdefer std.debug.print("AG1103 choke ink {s} compact={} variant={}\n", .{ group.choke, compact, variant });
            const pins = try indices(&p, lib, group);
            try testing.expect(try ink.connected(testing.allocator, &p, pins[2..5]));
        }
    };
}

test "block input chokes: explicit choke position and upright form remain authoritative" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    for ([_][]const u8{ "*@ at lbw5 -10 -10 r0\n", "*@ upright lbw6\n" }, 0..) |request, which| {
        const text = try std.fmt.allocPrint(a, "{s}{s}", .{ source, request });
        defer a.free(text);
        for ([_]bool{ false, true }) |compact| {
            var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
            defer p.deinit();
            const device = np.checks.deviceIn(&p, if (which == 0) "lbw5" else "lbw6").?;
            if (which == 0) {
                try testing.expectEqualDeep(np.Pt{ .x = -400, .y = -400 }, p.dev_pos[device]);
                try testing.expectEqualDeep(np.Orient{}, p.dev_orient[device]);
            } else {
                const lo, const hi = p.pinRange(device);
                try testing.expectEqual(@as(usize, 2), hi - lo);
                try testing.expectEqual(p.pin_xy[lo].x, p.pin_xy[lo + 1].x);
            }
            try electrical(&p, lib);
        }
    }
}


test "block input chokes: the three same-label remote bias branches preserve source separation" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{source}, null);
        defer p.deinit();
        try electrical(&p, lib);
        const far = [_]usize{ try onNet(&p, "lbw3", "v_bias"), try onNet(&p, "lbw5", "v_bias"), try onNet(&p, "lbw6", "v_bias") };
        for (far, 0..) |a, i| for (far[i + 1 ..]) |b| {
            errdefer std.debug.print("AG1103 remote V_bias {}--{} compact={}\n", .{ a, b, compact });
            try testing.expect(!try ink.connected(testing.allocator, &p, &.{ a, b }));
        };
    }
}
