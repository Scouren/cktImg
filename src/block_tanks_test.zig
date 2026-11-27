//! Block-tank actual frames, two-row rollback and allocation boundaries.
//! Oracle: literal shifted attached output leads and independently read
//! transformed terminals. A wide foreign plate blocks the entire bounded
//! search; every device row/coordinate and generic fallback must survive.
//!
//! Contents: literal fixture, private helpers, then tests.

const std = @import("std");
const testing = std.testing;
const owner = @import("block_tanks.zig");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const coil_tanks = @import("coil_tanks.zig");
const geometry = @import("lattice_geometry.zig");
const Lengths = @import("canvas.zig").Lengths;
const Pt = library.Pt;

const deck = "Block tank\n.subckt ct_inductor n1 n2 n3\nL1 n1 n3 1n\nL2 n3 n2 1n\n.ends\n" ++
    ".subckt stage inp outp outn\n.ends\n" ++
    "XL a b bias ct_inductor\nC1 a b 1p\nX1 input a b stage\nR1 remote 0 1k\n";

// The output midpoint lies nine units from the block grid. A ten-unit
// cap would put its up/left-facing end four units on the wrong side of
// that grid; the router's outward reach cannot represent that actual tip.
const Frame = enum { normal, malformed_lead, short_cap };

// ---- private ----

fn classes(lib: *library.Library, frame: Frame) !void {
    // Output midpoint y=7 differs from both raw origin and the settled
    // all-side grid because the unrelated input is at y=-30.
    _ = try lib.register(.{ .name = "stage", .terminals = &.{
        .{ .name = "inp", .at = .{ .x = -40, .y = -30 }, .side = .left },
        .{ .name = "outp", .at = .{ .x = 60, .y = -13 }, .side = .right },
        .{ .name = "outn", .at = .{ .x = 60, .y = 27 }, .side = .right },
    }, .draw = &.{
        .{ .polyline = &.{ .{ .x = -30, .y = -40 }, .{ .x = 50, .y = -40 }, .{ .x = 50, .y = 40 }, .{ .x = -30, .y = 40 }, .{ .x = -30, .y = -40 } } },
        .ln(-40, -30, -30, -30),
        .ln(50, -13, 60, -13),
        .ln(if (frame == .malformed_lead) 70 else 50, 27, 60, 27),
    } });
    _ = try lib.register(.{ .name = "ct_inductor", .terminals = &.{
        .{ .name = "n1", .at = .{ .x = -43, .y = 11 }, .side = .left },
        .{ .name = "n2", .at = .{ .x = 57, .y = 11 }, .side = .right },
        .{ .name = "n3", .at = .{ .x = 7, .y = 31 }, .side = .down },
    }, .draw = &.{ .ln(-43, 11, 57, 11), .ln(7, 11, 7, 31) } });
    _ = try lib.register(.{ .name = "cap", .terminals = &.{
        .{ .name = "a", .at = .{ .x = if (frame == .short_cap) 7 else -8, .y = 17 }, .side = .left },
        .{ .name = "b", .at = .{ .x = if (frame == .short_cap) 17 else 32, .y = 17 }, .side = .right },
    }, .draw = &.{.ln(if (frame == .short_cap) 7 else -8, 17, if (frame == .short_cap) 17 else 32, 17)} });
    _ = try lib.register(.{ .name = "res", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -200, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 200, .y = 0 }, .side = .right },
    }, .draw = &.{.{ .polyline = &.{ .{ .x = -200, .y = -200 }, .{ .x = 200, .y = -200 }, .{ .x = 200, .y = 200 }, .{ .x = -200, .y = 200 }, .{ .x = -200, .y = -200 } } }} });
}

fn point(s: *const sch.Schematic, at: []const [2]f32, d: netlist.EdgeId, pin: usize) Pt {
    const row = s.devices.get(d.index());
    return Pt.round(at[d.index()]).add(row.orient.apply(s.lib.at(row.class).terminals[pin].at).sub(row.grid));
}

fn expected(s: *const sch.Schematic, at: []const [2]f32, group: owner.Group) !void {
    const a, const b = .{ point(s, at, group.block, 1), point(s, at, group.block, 2) };
    const n1, const n2, const tap = .{ point(s, at, group.pair.coil, 0), point(s, at, group.pair.coil, 1), point(s, at, group.pair.coil, 2) };
    const ca, const cb = .{ point(s, at, group.pair.cap, 0), point(s, at, group.pair.cap, 1) };
    const side = s.pinSide(group.block.index(), 1).?;
    const v = side.unit();
    const w = library.Pt{ .x = -v.y, .y = v.x };
    const q = [_]Pt{ a, b, n1, n2, tap, ca, cb };
    var along: [7]i64 = undefined;
    var across: [7]i64 = undefined;
    for (q, &along, &across) |p, *x, *y| {
        x.* = @as(i64, p.x) * v.x + @as(i64, p.y) * v.y;
        y.* = @as(i64, p.x) * w.x + @as(i64, p.y) * w.y;
    }
    try testing.expect(along[0] == along[1] and along[2] == along[3] and along[5] == along[6]);
    try testing.expect(across[0] + across[1] == across[2] + across[3]);
    try testing.expect(across[0] + across[1] == across[5] + across[6]);
    try testing.expect(across[2] + across[3] == 2 * across[4]);
    try testing.expect((across[1] - across[0]) * (across[3] - across[2]) > 0);
    try testing.expect((across[1] - across[0]) * (across[6] - across[5]) > 0);
    try testing.expect(along[0] < along[5] and along[5] < along[2] and along[2] < along[4]);
}

fn allocation(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) !void {
    const before = [_]sch.DeviceInfo{ s.devices.get(0), s.devices.get(1), s.devices.get(2), s.devices.get(3) };
    var batch = owner.collect(gpa, nl, s, sk, st, ats, lines) catch |err| {
        for (before, 0..) |row, i| try testing.expectEqualDeep(row, s.devices.get(i));
        return err;
    };
    defer batch.deinit(gpa);
    try testing.expectEqual(@as(usize, 1), batch.groups.items.len);
    for (before, 0..) |row, i| try testing.expectEqualDeep(row, s.devices.get(i));
}

fn roomAllocation(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, group: owner.Group, ordinary: [4][2]f32, succeeds: bool) !void {
    const old = [_]sch.DeviceInfo{ s.devices.get(0), s.devices.get(1), s.devices.get(2), s.devices.get(3) };
    defer for (old, 0..) |row, i| s.devices.set(i, row);
    var groups = [_]owner.Group{group};
    var coordinates: [6][2]i32 = undefined;
    var room: [1]geometry.Room = undefined;
    var batch: owner.Batch = .{ .groups = .empty, .coordinates = &coordinates, .room = &room };
    batch.groups.items = &groups;
    batch.groups.capacity = 1;
    var pairs = [_]coil_tanks.Pair{group.pair};
    var fallback: std.ArrayList(coil_tanks.Pair) = .empty;
    fallback.items = &pairs;
    fallback.capacity = 1;
    var at: [4][2]f32 = @splat(.{ -777, -777 });
    const before = at;
    const applied = owner.lattice(gpa, s, nl, sk, Lengths.of(.{}, 40), &at, &batch, &fallback) catch |err| {
        try testing.expectEqualDeep(before, at);
        for (old, 0..) |row, i| try testing.expectEqualDeep(row, s.devices.get(i));
        try testing.expectEqual(@as(usize, 1), fallback.items.len);
        return err;
    };
    try testing.expectEqual(succeeds, applied);
    if (succeeds) {
        try testing.expectEqual(@as(usize, 0), fallback.items.len);
        try expected(s, &at, group);
    } else {
        try testing.expectEqualDeep(ordinary, at);
        try testing.expectEqual(@as(usize, 0), batch.groups.items.len);
        try testing.expectEqual(@as(usize, 1), fallback.items.len);
        for (old, 0..) |row, i| try testing.expectEqualDeep(row, s.devices.get(i));
    }
}

fn roomChecks(nl: *const netlist.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, lib: *library.Library, batch: *owner.Batch) !void {
    const group = batch.groups.items[0];
    const old = [_]sch.DeviceInfo{ s.devices.get(0), s.devices.get(1), s.devices.get(2), s.devices.get(3) };
    const requests = owner.rooms(s, nl, Lengths.of(.{}, 40), &batch.groups, batch.room);
    try testing.expectEqual(@as(usize, 1), requests.len);
    try testing.expectEqual(group.block, requests[0].anchor);
    // Literal shifted class arithmetic: output tips (60,-11)/(60,29),
    // cap x=80, winding x=100..120, span -41..59, clearance=10.
    try testing.expectEqualDeep(library.Rect{ .min = .{ .x = 70, .y = -51 }, .max = .{ .x = 130, .y = 69 } }, requests[0].bounds);
    for (old, 0..) |row, i| try testing.expectEqualDeep(row, s.devices.get(i));
    var x: [4]i32 = undefined;
    var y: [4]i32 = undefined;
    x[group.block.index()] = 0;
    y[group.block.index()] = 0;
    x[group.pair.coil.index()] = 2;
    y[group.pair.coil.index()] = 2;
    x[group.pair.cap.index()] = 2;
    y[group.pair.cap.index()] = 1;
    const obstruction = nl.device("r1").?.index();
    x[obstruction] = 1;
    y[obstruction] = 0;
    var cells = sk.*;
    cells.x = &x;
    cells.y = &y;
    cells.axis2 = null;
    for ([_]bool{ true, false }) |succeeds| {
        if (!succeeds) {
            // A caller body extending far beyond its two lead tips can
            // invalidate even reserved lattice spacing. Keep that body.
            const wide = try lib.register(.{ .name = "wide_room_obstacle", .terminals = &.{
                .{ .name = "a", .at = .{ .x = -10, .y = 0 }, .side = .left },
                .{ .name = "b", .at = .{ .x = 10, .y = 0 }, .side = .right },
            }, .draw = &.{.{ .polyline = &.{ .{ .x = -500, .y = -200 }, .{ .x = 500, .y = -200 }, .{ .x = 500, .y = 200 }, .{ .x = -500, .y = 200 }, .{ .x = -500, .y = -200 } } }} });
            s.devices.items(.class)[obstruction] = wide;
            sch.settleDevice(s, &nl.graph, @intCast(obstruction));
        }
        const baseline = try geometry.coordinates(testing.allocator, s, nl, &cells, Lengths.of(.{}, 40), &.{});
        defer testing.allocator.free(baseline.xs);
        defer testing.allocator.free(baseline.ys);
        var ordinary: [4][2]f32 = undefined;
        for (&ordinary, 0..) |*position, d| position.* = .{ @floatFromInt(baseline.xs[@intCast(x[d])]), @floatFromInt(baseline.ys[@intCast(y[d])]) };
        try testing.checkAllAllocationFailures(testing.allocator, roomAllocation, .{ nl, s, &cells, group, ordinary, succeeds });
    }
    for (old, 0..) |row, i| s.devices.set(i, row);
}

test "block tanks transaction: shifted eight poses, malformed or unrepresentable frame, collision and allocation preserve ownership" {
    const gpa = testing.allocator;
    for ([_]Frame{ .normal, .malformed_lead, .short_cap }) |frame| {
        const rejected = frame != .normal;
        errdefer std.debug.print("block tank private frame {s}\n", .{@tagName(frame)});
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var lib = library.Library.init(gpa);
        defer lib.deinit();
        try classes(&lib, frame);
        var nl = try netlist.parse(a, &.{deck}, null);
        try testing.expectEqual(@as(usize, 4), nl.graph.edgeCount());
        for ([_][]const u8{ "xl", "c1", "x1", "r1" }) |name| try testing.expect(nl.device(name) != null);
        const roles = try sch.guessRoles(a, &nl);
        // An independent ground prevents the no-reference heuristic from
        // legitimately assigning one of the two tank nets as the sink.
        for ([_][]const u8{ "a", "b" }) |name| try testing.expectEqual(sch.Role.internal, roles[nl.net(name).?.index()]);
        var s = try sch.initDevices(gpa, &nl, roles, &lib);
        defer s.deinit();
        for (0..s.devices.len) |d| s.devices.set(d, .{ .kept = true, .driver = false, .class = s.devices.items(.class)[d], .orientation = .horizontal, .flip_x = false, .flip_y = false, .orient = .r0, .grid = .zero, .reach = @splat(0) });
        sch.settleDevices(&s, &nl.graph);
        var st = try structure.analyze(gpa, a, &nl, roles);
        var sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
        const mates = try a.alloc(u32, s.devices.len);
        @memset(mates, sch.none);
        st.device_mate = mates;
        st.block_devices = &.{};
        st.block_kind = &.{};
        st.block_start = &.{0};
        const drawn = try a.alloc(bool, s.devices.len);
        @memset(drawn, true);
        sk.drawn = drawn;
        const shelves = try a.alloc(u32, s.devices.len);
        @memset(shelves, 0);
        sk.shelf = shelves;
        const ats: [4]?pinned.At = @splat(null);
        const verdicts = try a.alloc(?@import("hints.zig").Verdict, nl.hints.len);
        @memset(verdicts, null);
        const lines = try netlines.read(a, &nl, roles, 40, verdicts);
        try testing.checkAllAllocationFailures(gpa, allocation, .{ &nl, &s, &sk, &st, &ats, &lines });
        var batch = try owner.collect(gpa, &nl, &s, &sk, &st, &ats, &lines);
        defer batch.deinit(gpa);
        if (frame == .normal) try roomChecks(&nl, &s, &sk, &lib, &batch);
        const group = batch.groups.items[0];
        const block = group.block.index();
        const obstacle = nl.device("r1").?.index();
        for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
            s.devices.items(.orientation)[block] = form;
            s.devices.items(.flip_x)[block] = flips[0];
            s.devices.items(.flip_y)[block] = flips[1];
            sch.settleDevice(&s, &nl.graph, @intCast(block));
            var at: [4][2]f32 = @splat(.{ -500, -500 });
            at[block] = .{ 200, 300 };
            at[obstacle] = .{ 2000, 3000 };
            const old_at = at;
            const old_rows = [_]sch.DeviceInfo{ s.devices.get(0), s.devices.get(1), s.devices.get(2), s.devices.get(3) };
            batch.groups.items.len = 1;
            batch.groups.items[0] = group;
            var fallback_rows = [_]coil_tanks.Pair{group.pair};
            var fallback: std.ArrayList(coil_tanks.Pair) = .empty;
            fallback.items = &fallback_rows;
            fallback.capacity = 1;
            owner.place(&s, &nl, &sk, &ats, Lengths.of(.{}, 40), &at, &batch.groups, &fallback);
            try testing.expectEqual(@as(usize, @intFromBool(!rejected)), batch.groups.items.len);
            try testing.expectEqual(@as(usize, @intFromBool(rejected)), fallback.items.len);
            try testing.expectEqualDeep(old_rows[block], s.devices.get(block));
            if (rejected) {
                try testing.expectEqualDeep(old_at, at);
                for (old_rows, 0..) |row, i| try testing.expectEqualDeep(row, s.devices.get(i));
                continue;
            }
            try expected(&s, &at, group);
            const blocked_at = at[group.pair.coil.index()];
            for (old_rows, 0..) |row, i| s.devices.set(i, row);
            at = old_at;
            at[obstacle] = blocked_at;
            const before = at;
            batch.groups.items.len = 1;
            fallback.items.len = 1;
            owner.place(&s, &nl, &sk, &ats, Lengths.of(.{}, 40), &at, &batch.groups, &fallback);
            try testing.expectEqual(@as(usize, 0), batch.groups.items.len);
            try testing.expectEqual(@as(usize, 1), fallback.items.len);
            try testing.expectEqualDeep(before, at);
            for (old_rows, 0..) |row, i| try testing.expectEqualDeep(row, s.devices.get(i));
        };
    }
}

test "block tanks rooms: future peer envelopes replace stale passive boxes in either group order" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = library.Library.init(gpa);
    defer lib.deinit();
    try classes(&lib, .normal);
    var nl = try netlist.parse(a, &.{deck ++ "XL2 c d bias2 ct_inductor\nC2 c d 1p\nX2 input2 c d stage\n"}, null);
    try testing.expectEqual(@as(usize, 7), nl.graph.edgeCount());
    const roles = try sch.guessRoles(a, &nl);
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    for (0..s.devices.len) |d| s.devices.set(d, .{ .kept = true, .driver = false, .class = s.devices.items(.class)[d], .orientation = .horizontal, .flip_x = false, .flip_y = false, .orient = .r0, .grid = .zero, .reach = @splat(0) });
    sch.settleDevices(&s, &nl.graph);
    const st = try structure.analyze(gpa, a, &nl, roles);
    var sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
    const drawn: [7]bool = @splat(true);
    sk.drawn = &drawn;
    var groups: [2]owner.Group = undefined;
    for ([_][3][]const u8{ .{ "xl", "c1", "x1" }, .{ "xl2", "c2", "x2" } }, &groups) |names, *group| group.* = .{
        .pair = .{ .coil = nl.device(names[0]).?, .cap = nl.device(names[1]).?, .pins = .{ 0, 1, 2 }, .first = 0 },
        .block = nl.device(names[2]).?,
        .pins = .{ 1, 2 },
    };
    var before: [7]sch.DeviceInfo = undefined;
    for (&before, 0..) |*row, d| row.* = s.devices.get(d);
    var at: [7][2]f32 = @splat(.{ -500, -500 });
    at[groups[0].block.index()] = .{ 200, 300 };
    at[groups[1].block.index()] = .{ 800, 300 };
    at[nl.device("r1").?.index()] = .{ 2000, 3000 };
    // The old second coil occupies the first coil's future point. Both
    // are moving, so that old box must not veto the complete new scene.
    at[groups[1].pair.coil.index()] = .{ 300, 300 };
    const old_at = at;
    for ([_]bool{ false, true }) |reverse| {
        const ordered = if (reverse) [_]owner.Group{ groups[1], groups[0] } else groups;
        try testing.expect(owner.fits(&s, &nl, &sk, Lengths.of(.{}, 40), &at, &ordered));
        try testing.expectEqualDeep(old_at, at);
        // Old passives are still far apart, but both future pairs overlap.
        at[groups[1].block.index()] = at[groups[0].block.index()];
        try testing.expect(!owner.fits(&s, &nl, &sk, Lengths.of(.{}, 40), &at, &ordered));
        at = old_at;
        for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
    }
}
