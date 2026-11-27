//! Nine-row feedback placement: literal shifted caller frames and rollback.
//! Oracle: actual named terminal rows/sides, unchanged foreign rows/classes,
//! two late failure cases and every allocation failing before mutation.
//!
//! Contents: literal fixture/classes, allocation oracle, then one test.

const std = @import("std");
const testing = std.testing;
const owner = @import("ct_feedback_stage.zig");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const Lengths = @import("canvas.zig").Lengths;
const Pt = library.Pt;

const deck = "Feedback transaction\n.model qnpn npn\n" ++
    ".subckt ct_inductor n1 n2 n3\nL1 n1 n3 1n\nL2 n3 n2 1n\n.ends\n" ++
    "C1 g2 a 1p\nC2 b g1 1p\nLB1A bias g1 1n\nLB1B g2 bias 1n\n" ++
    "Q1 a g1 e1 0 qnpn\nQ2 b g2 e2 0 qnpn\nQ3 b b a 0 qnpn\nQ4 a a b 0 qnpn\n" ++
    "XL a b vdd ct_inductor\nR1 remote 0 1k\n";

// ---- private ----

fn classes(lib: *library.Library) !library.ClassId {
    _ = try lib.register(.{ .name = "ct_inductor", .terminals = &.{
        .{ .name = "n1", .at = .{ .x = -43, .y = 11 }, .side = .left },
        .{ .name = "n2", .at = .{ .x = 57, .y = 11 }, .side = .right },
        .{ .name = "n3", .at = .{ .x = 7, .y = -9 }, .side = .up },
    }, .draw = &.{ .ln(-43, 11, 57, 11), .ln(7, 11, 7, -9) } });
    _ = try lib.register(.{ .name = "npn", .terminals = &.{
        .{ .name = "c", .at = .{ .x = 37, .y = 9 }, .side = .right },
        .{ .name = "b", .at = .{ .x = 7, .y = -21 }, .side = .up },
        .{ .name = "e", .at = .{ .x = -23, .y = 9 }, .side = .left },
    }, .draw = &.{ .ln(17, 9, 37, 9), .ln(-23, 9, -3, 9), .ln(7, -21, 7, 9) } });
    for ([_][]const u8{ "cap", "ind", "res" }) |name| _ = try lib.register(.{ .name = name, .terminals = &.{
        .{ .name = "a", .at = .{ .x = -37, .y = 19 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 23, .y = 19 }, .side = .right },
    }, .draw = &.{.ln(-37, 19, 23, 19)} });
    return try lib.register(.{ .name = "skewed_ind", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -37, .y = 24 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 23, .y = 19 }, .side = .right },
    }, .draw = &.{.ln(-37, 24, 23, 19)} });
}

fn point(s: *const sch.Schematic, nl: *const netlist.Netlist, at: []const [2]f32, name: []const u8, pin: usize) Pt {
    const d = nl.device(name).?.index();
    const row = s.devices.get(d);
    return Pt.round(at[d]).add(row.orient.apply(s.lib.at(row.class).terminals[pin].at).sub(row.grid));
}

fn expected(s: *const sch.Schematic, nl: *const netlist.Netlist, at: []const [2]f32) !void {
    const a, const b, const tap = .{ point(s, nl, at, "xl", 0), point(s, nl, at, "xl", 1), point(s, nl, at, "xl", 2) };
    try testing.expect(a.x < b.x and a.y == b.y and tap.y < a.y);
    try testing.expectEqual(@as(i64, a.x) + b.x, 2 * @as(i64, tap.x));
    const c1, const g1, const e1 = .{ point(s, nl, at, "q1", 0), point(s, nl, at, "q1", 1), point(s, nl, at, "q1", 2) };
    const c2, const g2, const e2 = .{ point(s, nl, at, "q2", 0), point(s, nl, at, "q2", 1), point(s, nl, at, "q2", 2) };
    try testing.expect(c1.y < g1.y and g1.y < e1.y and c1.x == e1.x);
    try testing.expect(c2.y < g2.y and g2.y < e2.y and c2.x == e2.x);
    try testing.expect(c1.y == c2.y and g1.y == g2.y and e1.y == e2.y);
    try testing.expect(c1.x < a.x and c2.x > b.x and g1.x > c1.x and g2.x < c2.x);
    for ([_][]const u8{ "q3", "q4" }, 0..) |name, i| {
        const c, const g, const e = .{ point(s, nl, at, name, 0), point(s, nl, at, name, 1), point(s, nl, at, name, 2) };
        try testing.expect(c.y == e.y and g.x > @min(c.x, e.x) and g.x < @max(c.x, e.x));
        try testing.expect((c.x > e.x) == (i == 0));
        try testing.expect((g.y < c.y) == (i == 0));
    }
    const ca, const cb, const la, const lb = .{ point(s, nl, at, "c1", 1), point(s, nl, at, "c2", 0), point(s, nl, at, "lb1a", 1), point(s, nl, at, "lb1b", 0) };
    try testing.expect(ca.y == cb.y and ca.y < c1.y and la.y == lb.y and la.y > g1.y);
    try testing.expect(ca.x < point(s, nl, at, "c1", 0).x and cb.x > point(s, nl, at, "c2", 1).x);
    try testing.expect(la.x < point(s, nl, at, "lb1a", 0).x and lb.x > point(s, nl, at, "lb1b", 1).x);
    try testing.expect(g1.x < point(s, nl, at, "c1", 0).x and point(s, nl, at, "c1", 0).x < la.x);
    try testing.expect(lb.x < point(s, nl, at, "c2", 1).x and point(s, nl, at, "c2", 1).x < g2.x);
    try testing.expect(point(s, nl, at, "lb1a", 0).x < tap.x and tap.x < point(s, nl, at, "lb1b", 1).x);
}

fn allocation(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) !void {
    var before: [10]sch.DeviceInfo = undefined;
    for (&before, 0..) |*row, d| row.* = s.devices.get(d);
    var batch = owner.collect(gpa, nl, s, sk, st, ats, lines) catch |err| {
        for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
        return err;
    };
    defer batch.deinit(gpa);
    try testing.expectEqual(@as(usize, 1), batch.groups.items.len);
    for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
}

// ---- tests ----

test "CT feedback transaction: shifted actual anchors, late full rollback and allocation failures" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{deck}, null);
    const roles = try sch.guessRoles(a, &nl);
    var lib = library.Library.init(gpa);
    defer lib.deinit();
    const bad = try classes(&lib);
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    try testing.expectEqual(@as(usize, 10), s.devices.len);
    for (0..s.devices.len) |d| s.devices.set(d, .{ .kept = true, .driver = false, .class = s.devices.items(.class)[d], .orientation = .horizontal, .flip_x = false, .flip_y = false, .orient = .r0, .grid = .zero, .reach = @splat(0) });
    sch.settleDevices(&s, &nl.graph);
    var st = try structure.analyze(gpa, a, &nl, roles);
    var sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
    // The public full-source probe separately proves this owner boundary;
    // this seam supplies it directly to isolate the transaction contract.
    const mates = try a.alloc(u32, s.devices.len);
    @memset(mates, sch.none);
    st.device_mate = mates;
    st.block_kind = &.{};
    st.block_devices = &.{};
    st.block_start = &.{0};
    const drawn = try a.alloc(bool, s.devices.len);
    @memset(drawn, true);
    sk.drawn = drawn;
    const shelf = try a.alloc(u32, s.devices.len);
    @memset(shelf, 0);
    sk.shelf = shelf;
    const ats: [10]?pinned.At = @splat(null);
    const lines = try netlines.read(a, &nl, roles, lib.unit, &.{});
    try testing.checkAllAllocationFailures(gpa, allocation, .{ &nl, &s, &sk, &st, &ats, &lines });
    var batch = try owner.collect(gpa, &nl, &s, &sk, &st, &ats, &lines);
    defer batch.deinit(gpa);
    const group = batch.groups.items[0];
    var positions: [10][2]f32 = @splat(.{ 700, 100 });
    const outside = nl.device("r1").?.index();
    positions[outside] = .{ 700, 1000 };
    const original_positions = positions;
    var original: [10]sch.DeviceInfo = undefined;
    for (&original, 0..) |*row, d| row.* = s.devices.get(d);
    owner.place(&s, &nl, &sk, &ats, Lengths.of(.{}, lib.unit), &positions, &batch.groups);
    try testing.expectEqual(@as(usize, 1), batch.groups.items.len);
    try expected(&s, &nl, &positions);
    try testing.expectEqualDeep(original_positions[outside], positions[outside]);
    try testing.expectEqualDeep(original[outside], s.devices.get(outside));
    try testing.expect(!std.meta.eql(original[nl.device("q1").?.index()], s.devices.get(nl.device("q1").?.index())));
    for (0..2) |failure| {
        for (original, 0..) |row, d| s.devices.set(d, row);
        positions = original_positions;
        if (failure == 0) {
            const last = nl.device("lb1b").?.index();
            s.devices.items(.class)[last] = bad;
            sch.settleDevice(&s, &nl.graph, last);
        } else positions[outside][1] = -2147483520;
        // A malformed last inductor fails after eight turns; an exact f32
        // near i32-min foreign row fails final translation after all nine.
        var before: [10]sch.DeviceInfo = undefined;
        for (&before, 0..) |*row, d| row.* = s.devices.get(d);
        const before_positions = positions;
        batch.groups.items.len = 1;
        batch.groups.items[0] = group;
        owner.place(&s, &nl, &sk, &ats, Lengths.of(.{}, lib.unit), &positions, &batch.groups);
        try testing.expectEqual(@as(usize, 0), batch.groups.items.len);
        try testing.expectEqualDeep(before_positions, positions);
        for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
    }
}
