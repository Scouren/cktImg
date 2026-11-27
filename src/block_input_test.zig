//! Independent RC envelope, caller-frame and shared-room transaction tests.
//! Oracle: literal line classes give five-passive envelope [-160,-30]..[-60,110].
//! Compared fallback is the actual pre-RC output-only transaction, including
//! every device row, coordinate, survivor and fallback pair. No routing used.
//! Contents: literal fixture, helpers and tests.

const std = @import("std");
const testing = std.testing;
const nlmod = @import("netlist.zig");
const sch = @import("schematic.zig");
const libmod = @import("library.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const input = @import("block_input_rc.zig");
const place = @import("block_input_place.zig");
const shared = @import("block_rooms.zig");
const tanks = @import("block_tanks.zig");
const coils = @import("coil_tanks.zig");
const Lengths = @import("canvas.zig").Lengths;
const Pt = libmod.Pt;

const deck = "Paired RC\n.subckt driver outp outn\n.ends\n.subckt stage inp inn out vss\n.ends\n" ++
    ".subckt ct_inductor n1 n2 n3\nL1 n1 n3 1n\nL2 n3 n2 1n\n.ends\n" ++
    "XD a b driver\nXL a b tap ct_inductor\nCT a b 1p\nX1 ip im out 0 stage\n" ++
    "C1 a ip 1p\nC2 b im 1p\nR1 ip bias 1k\nR2 im bias 1k\nLB bias ext 1n\nRREF other 0 1k\n";
const Frame = enum { normal, malformed, collision, malformed_choke, choke_collision };
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    lib: *libmod.Library,
    nl: nlmod.Netlist,
    s: sch.Schematic,
    st: structure.Structure,
    sk: skeleton.Skeleton,
    ats: []?pinned.At,
    lines: netlines.NetLines,

    fn init(frame: Frame) !Fixture {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        const lib = try a.create(libmod.Library);
        lib.* = libmod.Library.init(testing.allocator);
        errdefer lib.deinit();
        try classes(lib, frame);
        var nl = try nlmod.parse(a, &.{deck}, null);
        const roles = try sch.guessRoles(a, &nl);
        var s = try sch.initDevices(testing.allocator, &nl, roles, lib);
        errdefer s.deinit();
        for (0..s.devices.len) |d| s.devices.set(d, .{ .kept = true, .driver = false, .class = s.devices.items(.class)[d], .orientation = .horizontal, .flip_x = false, .flip_y = false, .orient = .r0, .grid = .zero, .reach = @splat(0) });
        if (frame == .collision or frame == .choke_collision) s.devices.items(.class)[nl.device("rref").?.index()] = lib.find("obstacle").?;
        sch.settleDevices(&s, &nl.graph);
        var st = try structure.analyze(a, a, &nl, roles);
        var sk = try skeleton.place(a, a, &nl, roles, &st, .{ .shelf = 0 });
        const mates = try a.alloc(u32, s.devices.len);
        @memset(mates, sch.none);
        st.device_mate = mates;
        st.block_devices = &.{};
        st.block_kind = &.{};
        st.block_start = &.{0};
        const visible = try a.alloc(bool, s.devices.len);
        @memset(visible, true);
        sk.drawn = visible;
        const shelves = try a.alloc(u32, s.devices.len);
        @memset(shelves, 0);
        sk.shelf = shelves;
        const x = try a.alloc(i32, s.devices.len);
        const y = try a.alloc(i32, s.devices.len);
        for (x, y, 0..) |*column, *row, d| {
            column.* = 4;
            row.* = @intCast(d + 1);
        }
        x[nl.device("xd").?.index()] = 0;
        y[nl.device("xd").?.index()] = 0;
        x[nl.device("x1").?.index()] = 1;
        y[nl.device("x1").?.index()] = 0;
        x[nl.device("rref").?.index()] = 2;
        y[nl.device("rref").?.index()] = 0;
        sk.x = x;
        sk.y = y;
        sk.axis2 = null;
        const ats = try a.alloc(?pinned.At, s.devices.len);
        @memset(ats, null);
        const verdicts = try a.alloc(?@import("hints.zig").Verdict, nl.hints.len);
        @memset(verdicts, null);
        const lines = try netlines.read(a, &nl, roles, 40, verdicts);
        return .{ .arena = arena, .lib = lib, .nl = nl, .s = s, .st = st, .sk = sk, .ats = ats, .lines = lines };
    }
    fn deinit(self: *Fixture) void {
        self.s.deinit();
        self.lib.deinit();
        self.arena.deinit();
    }
};

// ---- private ----

fn classes(lib: *libmod.Library, frame: Frame) !void {
    _ = try lib.register(.{ .name = "driver", .terminals = &.{
        .{ .name = "outp", .at = .{ .x = 50, .y = -20 }, .side = .right },
        .{ .name = "outn", .at = .{ .x = 50, .y = 20 }, .side = .right },
    }, .draw = &.{ .{ .polyline = &.{ .{ .x = -40, .y = -40 }, .{ .x = 40, .y = -40 }, .{ .x = 40, .y = 40 }, .{ .x = -40, .y = 40 }, .{ .x = -40, .y = -40 } } }, .ln(40, -20, 50, -20), .ln(40, 20, 50, 20) } });
    _ = try lib.register(.{ .name = "stage", .terminals = &.{
        .{ .name = "inp", .at = .{ .x = -50, .y = -20 }, .side = .left },
        .{ .name = "inn", .at = .{ .x = -50, .y = 20 }, .side = .left },
        .{ .name = "out", .at = .{ .x = 50, .y = 0 }, .side = .right },
        .{ .name = "vss", .at = .zero, .hidden = true },
    }, .draw = &.{ .{ .polyline = &.{ .{ .x = -40, .y = -40 }, .{ .x = 40, .y = -40 }, .{ .x = 40, .y = 40 }, .{ .x = -40, .y = 40 }, .{ .x = -40, .y = -40 } } }, .ln(-50, -20, if (frame == .malformed) -60 else -40, -20), .ln(-50, 20, -40, 20), .ln(40, 0, 50, 0) } });
    for ([_][]const u8{ "cap", "res", "ind" }) |name| _ = try lib.register(.{ .name = name, .terminals = &.{
        .{ .name = "a", .at = .{ .x = -20, .y = 0 }, .side = .left }, .{ .name = "b", .at = .{ .x = 20, .y = if (frame == .malformed_choke and std.mem.eql(u8, name, "ind")) 1 else 0 }, .side = .right },
    }, .draw = &.{.ln(-20, 0, 20, if (frame == .malformed_choke and std.mem.eql(u8, name, "ind")) 1 else 0)} });
    _ = try lib.register(.{ .name = "ct_inductor", .terminals = &.{
        .{ .name = "n1", .at = .{ .x = -50, .y = 0 }, .side = .left },
        .{ .name = "n2", .at = .{ .x = 50, .y = 0 }, .side = .right },
        .{ .name = "n3", .at = .{ .x = 0, .y = 20 }, .side = .down },
    }, .draw = &.{ .ln(-50, 0, 50, 0), .ln(0, 0, 0, 20) } });
    // Foreign bodies occupy y70..100 or the choke-only y100..130. Hidden terminals stay
    // inside that body and leave its grid at zero: visible y0 terminals
    // would enlarge the actual box into the old output-only tank too.
    _ = try lib.register(.{ .name = "obstacle", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -10, .y = if (frame == .choke_collision) 110 else 80 }, .hidden = true }, .{ .name = "b", .at = .{ .x = 10, .y = if (frame == .choke_collision) 110 else 80 }, .hidden = true },
    }, .draw = &.{.{ .polyline = &.{ .{ .x = -300, .y = if (frame == .choke_collision) 100 else 70 }, .{ .x = 300, .y = if (frame == .choke_collision) 100 else 70 }, .{ .x = 300, .y = if (frame == .choke_collision) 130 else 100 }, .{ .x = -300, .y = if (frame == .choke_collision) 130 else 100 }, .{ .x = -300, .y = if (frame == .choke_collision) 100 else 70 } } }} });
}

fn oldPath(f: *Fixture, at: [][2]f32) !void {
    var outputs = try tanks.collect(testing.allocator, &f.nl, &f.s, &f.sk, &f.st, f.ats, &f.lines);
    defer outputs.deinit(testing.allocator);
    var fallback = try coils.collect(testing.allocator, &f.nl, &f.s, &f.sk, &f.st, f.ats, &f.lines);
    defer fallback.deinit(testing.allocator);
    try testing.expect(try tanks.lattice(testing.allocator, &f.s, &f.nl, &f.sk, Lengths.of(.{}, 40), at, &outputs, &fallback.pairs));
    try testing.expectEqual(@as(usize, 1), outputs.groups.items.len);
    try testing.expectEqual(@as(usize, 0), fallback.pairs.items.len);
}

fn trial(gpa: std.mem.Allocator, f: *Fixture, expected: ?[]const [2]f32, old_rows: []const sch.DeviceInfo, empty: bool) !void {
    const before = try testing.allocator.alloc(sch.DeviceInfo, f.s.devices.len);
    defer testing.allocator.free(before);
    for (before, 0..) |*row, i| row.* = f.s.devices.get(i);
    defer for (before, 0..) |row, i| f.s.devices.set(i, row);
    var inputs = try input.collect(gpa, &f.nl, &f.s, &f.sk, &f.st, f.ats, &f.lines);
    defer inputs.deinit(gpa);
    try testing.expectEqual(@as(usize, 1), inputs.groups.items.len);
    if (empty) inputs.groups.items.len = 0;
    var outputs = try tanks.collect(gpa, &f.nl, &f.s, &f.sk, &f.st, f.ats, &f.lines);
    defer outputs.deinit(gpa);
    var fallback = try coils.collect(gpa, &f.nl, &f.s, &f.sk, &f.st, f.ats, &f.lines);
    defer fallback.deinit(gpa);
    const at = try testing.allocator.alloc([2]f32, f.s.devices.len);
    defer testing.allocator.free(at);
    @memset(at, .{ -777, -777 });
    _ = shared.lattice(gpa, &f.s, &f.nl, &f.sk, Lengths.of(.{}, 40), at, &outputs, &inputs, &fallback.pairs) catch |err| {
        for (at) |p| try testing.expectEqualDeep([2]f32{ -777, -777 }, p);
        for (before, 0..) |row, i| try testing.expectEqualDeep(row, f.s.devices.get(i));
        try testing.expectEqual(@as(usize, 1), fallback.pairs.items.len);
        return err;
    };
    try testing.expectEqual(@as(usize, 1), outputs.groups.items.len);
    try testing.expectEqual(@as(usize, 0), fallback.pairs.items.len);
    if (expected) |want| {
        try testing.expectEqualDeep(want, at);
        try testing.expectEqual(@as(usize, 0), inputs.groups.items.len);
        for (old_rows, 0..) |row, i| try testing.expectEqualDeep(row, f.s.devices.get(i));
    } else {
        try testing.expectEqual(@as(usize, 1), inputs.groups.items.len);
        const group = inputs.groups.items[0];
        const block = group.block.index();
        try testing.expectEqualDeep(before[block], f.s.devices.get(block));
        const row = f.s.devices.get(block);
        for (input.members(group)[0..2], group.pins) |edge, pin| {
            const r = f.s.devices.get(edge.index());
            const cp = input.nearPin(&f.nl, group, if (edge == group.caps[0]) 0 else 1);
            const actual = Pt.round(at[edge.index()]).add(r.orient.apply(f.lib.at(r.class).terminals[cp].at).sub(r.grid));
            const target = Pt.round(at[block]).add(row.orient.apply(f.lib.at(row.class).terminals[pin].at).sub(row.grid));
            try testing.expectEqual(target.y, actual.y);
            try testing.expect(actual.x < target.x);
        }
    }
}

test "block input rooms: literal five-passive envelope restores every temporary row" {
    var f = try Fixture.init(.normal);
    defer f.deinit();
    var batch = try input.collect(testing.allocator, &f.nl, &f.s, &f.sk, &f.st, f.ats, &f.lines);
    defer batch.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), batch.groups.items.len);
    var before: [10]sch.DeviceInfo = undefined;
    try testing.expectEqual(before.len, f.s.devices.len);
    for (&before, 0..) |*row, i| row.* = f.s.devices.get(i);
    const rooms = place.rooms(&f.s, &f.nl, Lengths.of(.{}, 40), &batch);
    try testing.expectEqual(@as(usize, 1), rooms.len);
    try testing.expectEqualDeep(libmod.Rect{ .min = .{ .x = -160, .y = -30 }, .max = .{ .x = -60, .y = 110 } }, rooms[0].bounds);
    for (before, 0..) |row, i| try testing.expectEqualDeep(row, f.s.devices.get(i));
}

test "block input rooms: combined future scene reserves both owners and survives allocation failures" {
    var f = try Fixture.init(.normal);
    defer f.deinit();
    try testing.checkAllAllocationFailures(testing.allocator, trial, .{ &f, null, @as([]const sch.DeviceInfo, &.{}), false });
}

test "block input rooms: empty unsupported and colliding RC restore the exact old output transaction" {
    for ([_]Frame{ .normal, .malformed, .collision, .malformed_choke, .choke_collision }) |frame| {
        errdefer std.debug.print("block input fallback frame={s}\n", .{@tagName(frame)});
        var f = try Fixture.init(frame);
        defer f.deinit();
        var before: [10]sch.DeviceInfo = undefined;
        for (&before, 0..) |*row, i| row.* = f.s.devices.get(i);
        var expected: [10][2]f32 = @splat(.{ -777, -777 });
        try oldPath(&f, &expected);
        var old_rows: [10]sch.DeviceInfo = undefined;
        for (&old_rows, 0..) |*row, i| row.* = f.s.devices.get(i);
        for (before, 0..) |row, i| f.s.devices.set(i, row);
        try testing.checkAllAllocationFailures(testing.allocator, trial, .{ &f, @as(?[]const [2]f32, &expected), @as([]const sch.DeviceInfo, &old_rows), frame == .normal });
    }
}

test "block input rooms: an admitted choke position rejects the whole input group" {
    var f = try Fixture.init(.normal);
    defer f.deinit();
    const choke = f.nl.device("lb").?.index();
    f.ats[choke] = .{ .origin = .{ .x = -400, .y = -400 }, .orient = .r0, .line = 0 };
    var before: [10]sch.DeviceInfo = undefined;
    for (&before, 0..) |*row, i| row.* = f.s.devices.get(i);
    var batch = try input.collect(testing.allocator, &f.nl, &f.s, &f.sk, &f.st, f.ats, &f.lines);
    defer batch.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 0), batch.groups.items.len);
    for (before, 0..) |row, i| try testing.expectEqualDeep(row, f.s.devices.get(i));
}
