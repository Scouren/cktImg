//! Private-chain transaction and allocation-failure oracles.
//! One literal reflected graph, a successful actual-frame proposal, then
//! a foreign body on that exact candidate. Failure restores every row.
//!
//! Contents: fixture and allocation oracle, then one transaction test.

const std = @import("std");
const testing = std.testing;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const banks = @import("coil_banks.zig");
const bank_place = @import("coil_bank_place.zig");
const chains = @import("coil_chains.zig");
const chain_place = @import("coil_chain_place.zig");
const Lengths = @import("canvas.zig").Lengths;

const text = "Banks\n.model nch nmos\n.model sw SW\n" ++
    ".subckt ct_inductor n1 n2 n3\nL1 n1 n3 1n\nL2 n3 n2 1n\n.ends\n" ++
    "XLE1 a b vdd ct_inductor\nXLO1 a b vdd ct_inductor\nCT1 a b 1p\nM1 a b 0 0 nch\nM2 b a 0 0 nch\n" ++
    "XLE2 c d vdd ct_inductor\nXLO2 c d vdd ct_inductor\nCT2 c d 1p\nM3 c d 0 0 nch\nM4 d c 0 0 nch\n" ++
    "C1 u a 1p\nC2 c v 1p\nS1 u v ctl1 0 sw\nC3 w b 1p\nC4 d z 1p\nS2 w z ctl2 0 sw\n" ++
    "SE1 a c ctl3 0 sw\nSE2 b d ctl3 0 sw\nSO1 a d ctl4 0 sw\nSO2 c b ctl4 0 sw\nRBLOCK block 0 1k\n";

// ---- private ----

fn allocation(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines, parents: []const banks.Pair) !void {
    var before: [21]sch.DeviceInfo = undefined;
    for (&before, 0..) |*row, d| row.* = s.devices.get(d);
    var batch = chains.collect(gpa, nl, s, sk, st, ats, lines, parents) catch |err| {
        for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
        return err;
    };
    defer batch.deinit(gpa);
    try testing.expectEqual(@as(usize, 1), batch.owners.items.len);
    for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
}

// ---- tests ----

test "coil chain transaction: one blocked candidate restores all six rows and OOM preserves geometry" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{text}, null);
    const roles = try sch.guessRoles(a, &nl);
    var lib = library.Library.init(gpa);
    defer lib.deinit();
    for ([_][]const u8{ "cap", "res" }) |name| _ = try lib.register(.{ .name = name, .terminals = &.{
        .{ .name = "a", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 20, .y = 0 }, .side = .right },
    }, .draw = &.{.{ .line = .{ .a = .{ .x = -20, .y = 0 }, .b = .{ .x = 20, .y = 0 } } }} });
    _ = try lib.register(.{ .name = "switch", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "c+", .at = .{ .x = -6, .y = -20 }, .side = .up },
        .{ .name = "c-", .at = .{ .x = 6, .y = -20 }, .side = .up },
    }, .draw = &.{
        .{ .line = .{ .a = .{ .x = -20, .y = 0 }, .b = .{ .x = 20, .y = 0 } } },
        .{ .line = .{ .a = .{ .x = -6, .y = -20 }, .b = .{ .x = -6, .y = -10 } } },
        .{ .line = .{ .a = .{ .x = 6, .y = -20 }, .b = .{ .x = 6, .y = -10 } } },
    } });
    _ = try lib.register(.{ .name = "nmos", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .zero, .hidden = true },
    }, .draw = &.{ .{ .line = .{ .a = .{ .x = -20, .y = 0 }, .b = .{ .x = 20, .y = 0 } } }, .{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .zero } } } });
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    try testing.expectEqual(@as(usize, 21), s.devices.len);
    for (0..s.devices.len) |d| s.devices.set(d, .{ .kept = true, .driver = false, .class = s.devices.items(.class)[d], .orientation = .horizontal, .flip_x = false, .flip_y = false, .orient = .r0, .grid = .zero, .reach = @splat(0) });
    sch.settleDevices(&s, &nl.graph);
    var st = try structure.analyze(gpa, a, &nl, roles);
    var sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
    const mates = try a.alloc(u32, s.devices.len);
    @memset(mates, sch.none);
    for ([_][2][]const u8{
        .{ "xle1", "xle2" }, .{ "xlo1", "xlo2" }, .{ "ct1", "ct2" }, .{ "m1", "m3" }, .{ "m2", "m4" },
        .{ "c1", "c2" }, .{ "c3", "c4" }, .{ "s1", "s1" }, .{ "s2", "s2" }, .{ "se1", "se1" }, .{ "se2", "se2" }, .{ "so1", "so2" },
    }) |names| {
        const x, const y = .{ nl.device(names[0]).?.index(), nl.device(names[1]).?.index() };
        mates[x] = y;
        mates[y] = x;
    }
    st.device_mate = mates;
    const drawn = try a.alloc(bool, s.devices.len);
    @memset(drawn, true);
    const obstacle = nl.device("rblock").?.index();
    drawn[obstacle] = false;
    sk.drawn = drawn;
    const shelf = try a.alloc(u32, s.devices.len);
    @memset(shelf, 0);
    sk.shelf = shelf;
    const ats: [21]?pinned.At = @splat(null);
    const lines = try netlines.read(a, &nl, roles, lib.unit, &.{});
    var pair: banks.Pair = undefined;
    for ([_][5][]const u8{ .{ "xle1", "xlo1", "ct1", "m1", "m2" }, .{ "xle2", "xlo2", "ct2", "m3", "m4" } }, &pair) |names, *bank| {
        for (names, &bank.devices) |name, *edge| edge.* = nl.device(name).?;
        bank.pins = .{ .{ 0, 1, 2 }, .{ 0, 1, 2 } };
        bank.first = 0;
    }
    try testing.checkAllAllocationFailures(gpa, allocation, .{ &nl, &s, &sk, &st, &ats, &lines, @as([]const banks.Pair, &.{pair}) });
    var batch = try chains.collect(gpa, &nl, &s, &sk, &st, &ats, &lines, &.{pair});
    defer batch.deinit(gpa);
    const owner = batch.owners.items[0];
    var positions: [21][2]f32 = @splat(.{ 0, 0 });
    positions[nl.device("se1").?.index()] = .{ -200, 0 };
    positions[nl.device("se2").?.index()] = .{ 200, 0 };
    positions[pair[0].devices[0].index()] = .{ -300, 0 };
    positions[pair[1].devices[0].index()] = .{ 300, 0 };
    var parent_rows = [_]banks.Pair{pair};
    var parents: std.ArrayList(banks.Pair) = .empty;
    parents.items = &parent_rows;
    parents.capacity = 1;
    const len = Lengths.of(.{}, lib.unit);
    bank_place.place(&s, &nl, &sk, &ats, len, &positions, &parents);
    try testing.expectEqual(@as(usize, 1), parents.items.len);
    var old: [21]sch.DeviceInfo = undefined;
    for (&old, 0..) |*row, d| row.* = s.devices.get(d);
    const old_positions = positions;
    chain_place.place(&s, &nl, &sk, &ats, len, &positions, parents.items, &batch.owners);
    try testing.expectEqual(@as(usize, 1), batch.owners.items.len);
    const blocked_position = positions[owner.devices[0].index()];
    try testing.expect(!std.meta.eql(old_positions[owner.devices[0].index()], blocked_position));
    for (old, 0..) |row, d| s.devices.set(d, row);
    positions = old_positions;
    positions[obstacle] = blocked_position;
    drawn[obstacle] = true;
    const before = positions;
    batch.owners.items.len = 1;
    batch.owners.items[0] = owner;
    chain_place.place(&s, &nl, &sk, &ats, len, &positions, parents.items, &batch.owners);
    try testing.expectEqual(@as(usize, 0), batch.owners.items.len);
    try testing.expectEqualDeep(before, positions);
    for (old, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
}
