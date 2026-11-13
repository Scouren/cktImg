//! Grounded converter shunts below their electrical connection interval.
//!
//! Contents: source fixtures, private checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

const prefix = "Converter shunts\n.model nch nmos\n.model pch pmos\n.model dio d\n";
const reservoir_cards = "CSTO stored 0 1p\nCL output 0 1p\nL1 left right 1n\n" ++
    "MP3 left phase1 stored stored pch\nMP2 right control output output pch\n" ++
    "MN1 left phase2 0 0 nch\nMN2 right phase3 0 0 nch\n";
const reservoir = prefix ++ reservoir_cards;
const flying = prefix ++ "CFLY x1 x2 1p\nCO output bottom 1p\nCOP output 0 1p\n" ++
    "D1 bottom x2 dio\nL1 x1 x3 1n\nM1 x1 phase1 input vdd pch\n" ++
    "M2 x2 phase2 input vdd pch\nM3 output phase3 x3 vdd pch\nM4 x3 phase4 0 0 nch\n";
// Full AG1191 DUT body with the CLI-inferred port roles; source values retained.
const flying_source = prefix ++
    ".model DIODE D(IS=1e-14 N=1)\n" ++
    "CFLY VX1 VX2 1p\n" ++
    "CO VP VN 1p\n" ++
    "COP VP VSS 1p\n" ++
    "D1 VN VX2 DIODE\n" ++
    "L1 VX1 VX3 1n\n" ++
    "M1 VX1 VCONT2 VIN VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "M2 VX2 VCONT3 VIN VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "M3 VX3 VCONT5 VP VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "M4 VX3 VCONT4 VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "M5 net9 VCONT1 VIN VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MN1 net5 VFP1 net10 VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN10 net1 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN11 VB3 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN12 net0 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN13 VBN VBN net3 VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN14 net3 VBN VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN2 net4 VREF net10 VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN3 net10 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN4 VG VBN VX1 VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN5 VX1 VG VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN6 VCTRL VBN net8 VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN7 net8 VG VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN8 net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MN9 net6 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1\n" ++
    "MP1 VFP1 net5 VDD VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP10 net6 net6 net9 VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP11 VX1 net6 net9 VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP12 VB3 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP13 net0 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP14 VBN net0 VDD VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP2 net2 net5 VDD VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP3 VN net4 VDD VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP4 net7 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP5 VG VB1 VFP1 VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP6 net5 VB1 net2 VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP7 net4 VB1 VN VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP8 VCTRL VB1 net7 VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "MP9 net1 VCTRL net9 VDD pch l=0.15 w=1 nf=1 m=1\n" ++
    "R1 VP VFP1 1k\n" ++
    "R2 VFP1 VSS 1k\n" ++
    "*@ weak role vcont1 input\n" ++
    "*@ weak role vcont2 input\n" ++
    "*@ weak role vcont3 input\n" ++
    "*@ weak role vcont4 input\n" ++
    "*@ weak role vcont5 input\n" ++
    "*@ weak role vp output\n";
// AG1383: M7 is an amplifier tail on the same endpoint as power shunt MN1.
const ambiguous = prefix ++
    "CL output 0 1p\nCSTO stored 0 1p\nL1 x1 x2 1n\n" ++
    "M1 n0 bias1 vdd vdd pch\nM10 n2 n4 0 0 nch\nM11 n3 n4 0 0 nch\n" ++
    "M12 n5 n5 vdd vdd pch\nM13 bias4 n5 vdd vdd pch\n" ++
    "M14 bias4 bias4 n1 0 nch\nM15 n1 bias4 0 0 nch\n" ++
    "M2 n6 bias1 vdd vdd pch\nM3 control bias3 n0 vdd pch\n" ++
    "M4 n4 bias3 n6 vdd pch\nM5 n0 control x1 0 nch\nM6 n6 x2 x1 0 nch\n" ++
    "M7 x1 bias2 0 0 nch\nM8 control bias4 n2 0 nch\nM9 n4 bias4 n3 0 nch\n" ++
    "MN1 x1 phase2 0 0 nch\nMN2 x2 phase3 0 0 nch\n" ++
    "MP2 x2 control output vdd pch\nMP3 x1 phase1 stored vdd pch\nR1 n5 0 1k\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, terminal: usize) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.dev_pin0[d] + terminal];
}

fn expectInterval(p: *const np.Placed, shunt: []const u8, main: []const u8, main_pin: usize, coil_pin: usize) !void {
    const coil = pin(p, "l1", coil_pin);
    const end = pin(p, main, main_pin);
    const drain = pin(p, shunt, 0);
    const source = pin(p, shunt, 2);
    try testing.expectEqual(drain.x, source.x);
    try testing.expect(drain.y < source.y);
    try testing.expect(drain.y > @max(coil.y, end.y));
    try testing.expect(drain.x >= @min(coil.x, end.x));
    try testing.expect(drain.x <= @max(coil.x, end.x));
}

fn expectElectrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

fn expectHonoured(src: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    for (try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib)) |v| {
        try testing.expectEqual(np.hints.State.honoured, v.state);
    }
}

test "power shunts: reservoir switches sit below their connected main and coil terminals" {
    // Oracle: AG1363/1401/1370/1432. The shunt's upper pin lies inside the
    // horizontal connection interval, not necessarily on the coil pin's x.
    // All 101 paired source cases place those upper pins on the same row.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{reservoir}, null);
        defer p.deinit();
        try expectInterval(&p, "mn1", "mp3", 0, 0);
        try expectInterval(&p, "mn2", "mp2", 0, 1);
        try testing.expectEqual(pin(&p, "mn1", 0).y, pin(&p, "mn2", 0).y);
        try expectElectrical(&p, lib);
    }
}

test "power shunts: a flying-capacitor converter keeps its unique output shunt in the interval" {
    // Oracle: AG1191 M4 lies under L1's output-side connection to M3.
    // The full source retains the amplifier/bias columns that provide
    // interior lattice room; its connected main terminal is M3.D.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{flying_source}, null);
        defer p.deinit();
        try expectInterval(&p, "m4", "m3", 0, 1);
        try expectElectrical(&p, lib);
    }
}

test "power shunts: adjacent main columns retain the ordinary placement" {
    // Boundary oracle: reducing AG1191 to its power devices removes the
    // interior lattice column. This pass reserves no new columns; a
    // future gap-insertion rule must replace this explicit limitation.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{flying}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const coil = nl.device("l1").?.index();
    const main = nl.device("m3").?.index();
    try testing.expectEqual(@as(u32, 1), @abs(sk.x[coil] - sk.x[main]));
    var p = try np.place(gpa, &.default, lib, &.{flying}, null);
    defer p.deinit();
    // This reduced card deliberately connects M3.S, rather than M3.D.
    try testing.expect(pin(&p, "m4", 0).x > @max(pin(&p, "l1", 1).x, pin(&p, "m3", 2).x));
    try expectElectrical(&p, lib);
}

test "power shunts: an ambiguous endpoint does not pull an amplifier tail into the power group" {
    // Negative source: AG1383 M7 and MN1 both connect VX1 to ground with
    // external controls. M7 belongs to the amplifier below its input pair;
    // its x is outside the power interval. Polarity alone cannot select it.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{ambiguous}, null);
    defer p.deinit();
    const a = pin(&p, "mp3", 0).x;
    const b = pin(&p, "l1", 0).x;
    const tail = pin(&p, "m7", 0);
    try testing.expect(tail.x < @min(a, b) or tail.x > @max(a, b));
    try testing.expectEqual(tail.x, pin(&p, "m7", 2).x);
    try expectElectrical(&p, lib);
}

test "power shunts: card reversal preserves named electrical pins and turns" {
    // Metamorphic oracle: card order changes no geometry or electrical pin.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var cards: std.ArrayList([]const u8) = .empty;
    defer cards.deinit(gpa);
    var it = std.mem.tokenizeScalar(u8, reservoir_cards, '\n');
    while (it.next()) |line| try cards.append(gpa, line);
    std.mem.reverse([]const u8, cards.items);
    var reverse: std.ArrayList(u8) = .empty;
    defer reverse.deinit(gpa);
    try reverse.appendSlice(gpa, prefix);
    for (cards.items) |line| {
        try reverse.appendSlice(gpa, line);
        try reverse.append(gpa, '\n');
    }
    var before = try np.place(gpa, &.default, lib, &.{reservoir}, null);
    defer before.deinit();
    var after = try np.place(gpa, &.default, lib, &.{reverse.items}, null);
    defer after.deinit();
    for (before.dev_name, 0..) |name, d| {
        if (name.len == 0) continue;
        const other = np.checks.deviceIn(&after, name).?;
        try testing.expectEqual(before.dev_orient[d], after.dev_orient[other]);
        try testing.expectEqualSlices(np.Pt, before.pin_xy[before.dev_pin0[d]..before.dev_pin0[d + 1]], after.pin_xy[after.dev_pin0[other]..after.dev_pin0[other + 1]]);
    }
    try expectInterval(&after, "mn1", "mp3", 0, 0);
    try expectInterval(&after, "mn2", "mp2", 0, 1);
    try expectElectrical(&after, lib);
}

test "power shunts: explicit cells and different row orders retain precedence" {
    // Oracle: the caller puts one shunt above the power path, or the two
    // shunts on different rows. Neither inferred interval nor pair row can
    // override those honoured instructions.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_][]const u8{
        reservoir ++ "*@ cell mn1 -8 -6\n",
        reservoir ++ "*@ above mn1 cl\n*@ row mn2 cl\n",
    }, 0..) |src, k| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = false } }, lib, &.{src}, null);
        defer p.deinit();
        if (k == 0) {
            try testing.expect(pin(&p, "mn1", 0).y < pin(&p, "l1", 0).y);
        } else try testing.expect(pin(&p, "mn1", 0).y < pin(&p, "mn2", 0).y);
        try expectElectrical(&p, lib);
        try expectHonoured(src, &p, lib);
    }
}

test "power shunts: an admitted upright order wins and an invalid order cannot disable the interval" {
    // Oracle: ordering CSTO before MN1 puts that shunt outside the main
    // interval. Upright orders run before bridges and must remain true.
    // A line naming an absent device has no admitted ordering constraint.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const ordered = reservoir ++ "*@ order csto mn1\n";
    var p = try np.place(gpa, &.default, lib, &.{ordered}, null);
    defer p.deinit();
    try testing.expect(pin(&p, "csto", 0).x < pin(&p, "mn1", 0).x);
    try testing.expect(pin(&p, "mn1", 0).x > @max(pin(&p, "mp3", 0).x, pin(&p, "l1", 0).x));
    try expectHonoured(ordered, &p, lib);
    try expectElectrical(&p, lib);
    var invalid = try np.place(gpa, &.default, lib, &.{reservoir ++ "*@ order absent mn1\n"}, null);
    defer invalid.deinit();
    try expectInterval(&invalid, "mn1", "mp3", 0, 0);
    try expectElectrical(&invalid, lib);
}

test "power shunts: an existing inferred mirror pair keeps its axis" {
    // Oracle: the caller's explicit pair creates layout mates even when
    // Structure has no exact graph symmetry. Moving either shunt into
    // the power interval would break that existing axis; its mirror wins.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const src = reservoir ++ "*@ group pair mn1 mn2\n";
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const first = nl.device("mn1").?.index();
    const second = nl.device("mn2").?.index();
    try testing.expectEqual(np.schematic.structure.none, st.device_mate[first]);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    try testing.expect(sk.axis2 != null);
    try testing.expectEqual(sk.axis2.?, sk.x[first] + sk.x[second]);
    try testing.expectEqual(sk.y[first], sk.y[second]);
    var p = try np.place(gpa, &.default, lib, &.{src}, null);
    defer p.deinit();
    try testing.expect(pin(&p, "mn1", 0).x > @max(pin(&p, "mp3", 0).x, pin(&p, "l1", 0).x));
    try testing.expectEqual(pin(&p, "mn1", 0).y, pin(&p, "mn2", 0).y);
    try expectHonoured(src, &p, lib);
    try expectElectrical(&p, lib);
}
