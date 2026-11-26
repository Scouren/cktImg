//! Paired input RC source relations in the block's actual cardinal frame.
//! Oracle: AG1103 X2 inputs (90,270)/(90,310), cap-near (40,270)/(40,310),
//! R3 (50,330)->(50,370), R4 (70,330)->(70,370); X3 is the reflected case.
//! The actual block frame stays authoritative: INP/INN order is not forced
//! to match world-up/down in the source, and hidden VSS is never invented.
//! The independent ink oracle requires only the two input triples and the
//! resistor bias pair, not source-omitted remote connections. See the exact
//! source certificate in docs/research/block-input-rc.md. Not yet imported.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const source = @embedFile("block_input_rc_fixture.sp");
const Group = struct {
    block: []const u8,
    caps: [2][]const u8,
    resistors: [2][]const u8,
    inputs: [2][]const u8,
    remote: [2][]const u8,
    bias: []const u8,
};
const groups = [_]Group{
    .{ .block = "x2", .caps = .{ "cblk3", "cblk4" }, .resistors = .{ "r3", "r4" }, .inputs = .{ "net14", "net19" }, .remote = .{ "net9", "net8" }, .bias = "net15" },
    .{ .block = "x3", .caps = .{ "cblk5", "cblk6" }, .resistors = .{ "r5", "r6" }, .inputs = .{ "net6", "net0" }, .remote = .{ "net9", "net8" }, .bias = "net17" },
};

// ---- private ----

fn dot(a: np.Pt, b: np.Pt) i64 {
    return @as(i64, a.x) * b.x + @as(i64, a.y) * b.y;
}

// Ten actual tips: INP/INN, then cap-near/far for each branch, then
// resistor-input/bias for each branch. Absolute origins and distances are absent.
fn relative(q: [10]np.Pt, outward: np.Side) bool {
    const u = outward.unit();
    const delta = np.Pt{ .x = q[1].x - q[0].x, .y = q[1].y - q[0].y };
    const transverse = np.Side.of(delta) orelse return false;
    const w = transverse.unit();
    if (dot(u, w) != 0 or dot(q[0], u) != dot(q[1], u)) return false;
    for (0..2) |i| {
        const c, const r = .{ 2 + 2 * i, 6 + 2 * i };
        if (dot(q[c], w) != dot(q[c + 1], w) or dot(q[c], w) != dot(q[i], w)) return false;
        if (!(dot(q[i], u) < dot(q[c], u) and dot(q[c], u) < dot(q[c + 1], u))) return false;
        if (dot(q[r], u) != dot(q[r + 1], u) or dot(q[r], w) == dot(q[r + 1], w)) return false;
        if (!(dot(q[i], u) < dot(q[r], u) and dot(q[r], u) < dot(q[c], u))) return false;
    }
    if (dot(q[2], u) != dot(q[4], u) or dot(q[3], u) != dot(q[5], u)) return false;
    if (dot(q[6], w) != dot(q[8], w) or dot(q[7], w) != dot(q[9], w)) return false;
    const low, const high = .{ dot(q[0], w), dot(q[1], w) };
    const near, const far = .{ dot(q[6], w), dot(q[7], w) };
    return (high < near and near < far or far < near and near < low) and dot(q[6], u) > dot(q[8], u);
}

fn named(p: *const np.Placed, lib: *const np.Library, device: []const u8, port: []const u8) !usize {
    const d = np.checks.deviceIn(p, device) orelse return error.MissingDevice;
    for (lib.at(p.dev_class[d]).terminals, 0..) |terminal, i| {
        if (std.ascii.eqlIgnoreCase(terminal.name, port)) return p.dev_pin0[d] + i;
    }
    return error.MissingTerminal;
}

fn onNet(p: *const np.Placed, device: []const u8, net: []const u8) !usize {
    const d = np.checks.deviceIn(p, device) orelse return error.MissingDevice;
    const lo, const hi = p.pinRange(d);
    var found: ?usize = null;
    for (lo..hi) |pin| if (std.mem.eql(u8, net, p.net_name[p.pin_net[pin]])) {
        try testing.expect(found == null);
        found = pin;
    };
    return found orelse error.MissingNet;
}

fn indices(p: *const np.Placed, lib: *const np.Library, group: Group) ![10]usize {
    var result: [10]usize = undefined;
    for ([_][]const u8{ "inp", "inn" }, 0..) |port, i| {
        result[i] = try named(p, lib, group.block, port);
        result[2 + 2 * i] = try onNet(p, group.caps[i], group.inputs[i]);
        result[3 + 2 * i] = try onNet(p, group.caps[i], group.remote[i]);
        result[6 + 2 * i] = try onNet(p, group.resistors[i], group.inputs[i]);
        result[7 + 2 * i] = try onNet(p, group.resistors[i], group.bias);
        try testing.expectEqualStrings(group.inputs[i], p.net_name[p.pin_net[result[i]]]);
    }
    return result;
}

fn actualFrame(p: *const np.Placed, lib: *const np.Library, group: Group, pins: [10]usize) !np.Side {
    const d = np.checks.deviceIn(p, group.block).?;
    const class = lib.at(p.dev_class[d]);
    const pose = p.dev_orient[d];
    const outward = class.side(pins[0] - p.dev_pin0[d], pose) orelse return error.MissingInputSide;
    try testing.expectEqual(outward, class.side(pins[1] - p.dev_pin0[d], pose).?);
    // Every declared input uses its actual transformed class tip, not a
    // projected or rewritten canonical input coordinate. Hidden VSS is omitted.
    for (pins[0..2]) |pin| {
        const offset = pose.apply(class.terminals[pin - p.dev_pin0[d]].at);
        const expected = np.Pt{ .x = p.dev_pos[d].x + offset.x, .y = p.dev_pos[d].y + offset.y };
        try testing.expectEqualDeep(expected, p.pin_xy[pin]);
    }
    return outward;
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, p, true));
}

fn honoured(text: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{text}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    for (try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
}

test "block input RC: literal source frame survives eight poses and rejects shifted or reversed branches" {
    const q = [10]np.Pt{
        .{ .x = 90, .y = 270 }, .{ .x = 90, .y = 310 },
        .{ .x = 40, .y = 270 }, .{ .x = 0, .y = 270 },
        .{ .x = 40, .y = 310 }, .{ .x = 0, .y = 310 },
        .{ .x = 50, .y = 330 }, .{ .x = 50, .y = 370 },
        .{ .x = 70, .y = 330 }, .{ .x = 70, .y = 370 },
    };
    try testing.expect(relative(q, .left));
    for (0..8) |i| {
        const pose: np.Orient = .{ .rot = @intCast(i & 3), .mirror = i >= 4 };
        var moved: [10]np.Pt = undefined;
        for (q, &moved) |v, *at| {
            const changed = pose.apply(v);
            at.* = .{ .x = changed.x + 137, .y = changed.y - 49 };
        }
        try testing.expect(relative(moved, np.Side.of(pose.apply(np.Side.left.unit())).?));
    }
    for ([_]usize{ 2, 3, 6, 7 }) |i| {
        var wrong = q;
        wrong[i].y += 1;
        try testing.expect(!relative(wrong, .left));
    }
    var wrong = q;
    std.mem.swap(np.Pt, &wrong[2], &wrong[3]);
    try testing.expect(!relative(wrong, .left));
    wrong = q;
    wrong[6].x = 100;
    try testing.expect(!relative(wrong, .left));
    wrong = q;
    wrong[6].y = 300;
    wrong[8].y = 300;
    try testing.expect(!relative(wrong, .left));
    try testing.expect(!relative(q, .right));
}

test "block input RC: AG1103 downstream branches follow each actual input frame" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{source}, null);
        defer p.deinit();
        try electrical(&p, lib);
        for (groups) |group| {
            errdefer std.debug.print("AG1103 paired RC frame {s} compact={}\n", .{ group.block, compact });
            const pins = try indices(&p, lib, group);
            const outward = try actualFrame(&p, lib, group, pins);
            var tips: [10]np.Pt = undefined;
            for (pins, &tips) |pin, *at| at.* = p.pin_xy[pin];
            try testing.expect(relative(tips, outward));
        }
    }
}

test "block input RC: AG1103 local input triples and paired bias tips have physical ink" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{source}, null);
        defer p.deinit();
        try electrical(&p, lib);
        for (groups) |group| {
            const pins = try indices(&p, lib, group);
            for (0..2) |i| {
                errdefer std.debug.print("AG1103 local input {s} compact={}\n", .{ group.inputs[i], compact });
                const path = [_]usize{ pins[i], pins[2 + 2 * i], pins[6 + 2 * i] };
                try testing.expect(try ink.connected(testing.allocator, &p, &path));
            }
            const bias = [_]usize{ pins[7], pins[9] };
            errdefer std.debug.print("AG1103 local paired bias {s} compact={}\n", .{ group.bias, compact });
            try testing.expect(try ink.connected(testing.allocator, &p, &bias));
        }
    }
}

test "block input RC: caller passive pose form and block input frame remain authoritative" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const requests = [_][]const u8{
        "*@ at cblk3 -10 -10 r0\n",
        "*@ upright cblk4\n",
        "*@ at x2 -15 -15 r90\n",
    };
    for (requests, 0..) |request, which| for ([_]bool{ false, true }) |compact| {
        const text = try std.fmt.allocPrint(a, "{s}{s}", .{ source, request });
        defer a.free(text);
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        if (which == 1) {
            const d = np.checks.deviceIn(&p, "cblk4").?;
            const lo, const hi = p.pinRange(d);
            try testing.expectEqual(@as(usize, 2), hi - lo);
            try testing.expectEqual(p.pin_xy[lo].x, p.pin_xy[lo + 1].x);
        } else {
            const d = np.checks.deviceIn(&p, if (which == 0) "cblk3" else "x2").?;
            const at: i32 = if (which == 0) -400 else -600;
            const pose: np.Orient = .{ .rot = if (which == 0) 0 else 1 };
            try testing.expectEqualDeep(np.Pt{ .x = at, .y = at }, p.dev_pos[d]);
            try testing.expectEqualDeep(pose, p.dev_orient[d]);
        }
        try honoured(text, &p, lib);
        try electrical(&p, lib);
    };
}

test "block input RC: renamed drivers and permuted declarations retain actual named endpoint correspondence" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var text: []const u8 = source;
    const changes = [_][2][]const u8{
        .{ ".subckt PA VDD VSS VB inp inn outp outn src", ".subckt chain_stage src outn inn VSS inp outp VB VDD" },
        .{ ".ends PA", ".ends chain_stage" },
        .{ "X2 VDD VSS VB_PA net14 net19 net20 net25 net7 PA", "X2 net7 net25 net19 VSS net14 net20 VB_PA VDD chain_stage" },
        .{ "X3 VDD VSS VB_PA2 net6 net0 net4 net2 NC0001 PA", "X3 NC0001 net2 net0 VSS net6 net4 VB_PA2 VDD chain_stage" },
        .{ ".subckt DA VSS VB inp inn outp outn src", ".subckt chain_driver outn src inp VB outp VSS inn" },
        .{ ".ends DA", ".ends chain_driver" },
        .{ "X1 VSS VB_DA net10 net22 net9 net8 net11 DA", "XDRV net8 net11 net10 VB_DA net9 VSS net22 chain_driver" },
        .{ "Cblk3 net9 net14", "Cblk3 net14 net9" },
        .{ "Cblk4 net8 net19", "Cblk4 net19 net8" },
        .{ "Cblk5 net6 net9", "Cblk5 net9 net6" },
        .{ "Cblk6 net0 net8", "Cblk6 net8 net0" },
        .{ "R3 net14 net15", "R3 net15 net14" },
        .{ "R4 net19 net15", "R4 net15 net19" },
        .{ "R5 net6 net17", "R5 net17 net6" },
        .{ "R6 net0 net17", "R6 net17 net0" },
    };
    for (changes) |change| {
        try testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, change[0]));
        text = try std.mem.replaceOwned(u8, a, text, change[0], change[1]);
    }
    text = try std.mem.replaceOwned(u8, a, text, "net9", "drive_p");
    text = try std.mem.replaceOwned(u8, a, text, "net8", "drive_n");
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("permuted RC compact={}\n", .{compact});
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        try electrical(&p, lib);
        const driver = np.checks.deviceIn(&p, "xdrv").?;
        for ([_][]const u8{ "outp", "outn" }, [_][]const u8{ "drive_p", "drive_n" }) |port, net| {
            const pin = try named(&p, lib, "xdrv", port);
            try testing.expectEqualStrings(net, p.net_name[p.pin_net[pin]]);
            const terminal = lib.at(p.dev_class[driver]).terminals[pin - p.dev_pin0[driver]];
            const offset = p.dev_orient[driver].apply(terminal.at);
            try testing.expectEqualDeep(p.dev_pos[driver].add(offset), p.pin_xy[pin]);
        }
        for (groups) |original| {
            var group = original;
            group.remote = .{ "drive_p", "drive_n" };
            const pins = try indices(&p, lib, group);
            const outward = try actualFrame(&p, lib, group, pins);
            var tips: [10]np.Pt = undefined;
            for (pins, &tips) |pin, *point| point.* = p.pin_xy[pin];
            try testing.expect(relative(tips, outward));
            for (0..2) |i| try testing.expect(try ink.connected(testing.allocator, &p, &.{ pins[i], pins[2 + 2 * i], pins[6 + 2 * i] }));
            try testing.expect(try ink.connected(testing.allocator, &p, &.{ pins[7], pins[9] }));
        }
    }
}
