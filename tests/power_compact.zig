//! Compaction preserves source-derived converter channel order.
//!
//! Contents: the AG1356 source topology, private pin checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

// AG1356's DUT body, as selected by cktimg-json. Model dimensions do not
// affect this layout. Spell the CLI's inferred port roles for place(),
// which otherwise reads the source's top level rather than selecting DUT.
const ag1356 =
    \\AG1356 converter with discrete control amplifier
    \\.model nch nmos
    \\.model pch pmos
    \\CL VOUT VSS 1p
    \\CSTO VSTO VSS 1p
    \\LRX VX1 VX2 1n
    \\M10 net2 VB1 net7 VDD pch
    \\M11 VX1 VB1 net10 VDD pch
    \\M12 VC VB1 net3 VDD pch
    \\M13 VX1 VB3 net4 VSS nch
    \\M14 VC VB3 net1 VSS nch
    \\M15 net4 VX1 VSS VSS nch
    \\M16 net5 VB2 VSS VSS nch
    \\M17 net1 VX1 VSS VSS nch
    \\M18 net0 net0 VDD VDD pch
    \\M19 VB3 net0 VDD VDD pch
    \\M20 VB3 VB3 net9 VSS nch
    \\M21 net9 VB3 VSS VSS nch
    \\M3 net6 VX2 net5 VSS nch
    \\M4 net2 VC net5 VSS nch
    \\M5 net8 net6 VDD VDD pch
    \\M6 net7 net2 VDD VDD pch
    \\M7 net10 net6 VDD VDD pch
    \\M8 net3 net2 VDD VDD pch
    \\M9 net6 VB1 net8 VDD pch
    \\MN1 VX1 VCONT2 VSS VSS nch
    \\MN2 VX2 VCONT3 VSS VSS nch
    \\MP2 VX2 VC VOUT VDD pch
    \\MP3 VX1 VCONT1 VSTO VDD pch
    \\R1 net0 VSS 1k
    \\*@ weak role vsto output
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\
;

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, terminal: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.dev_pin0[d] + terminal];
}

fn expectElectrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

test "power compaction: AG1356's whole active channels stay below the main path" {
    // Oracle: ag-1356.human.json and the source SVG. LRX and MP2/MP3's
    // D/S pins have y=100; M12's S/D have y=480/520, and M14's D/S
    // have y=560/600. Both ground shunts are also wholly below the path.
    // Device-center order alone missed M12.S becoming level with LRX.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{ag1356}, null);
        defer p.deinit();
        const row = pin(&p, "lrx", 0).y;
        try testing.expectEqual(row, pin(&p, "lrx", 1).y);
        for ([_][]const u8{ "mp2", "mp3" }) |name| {
            try testing.expectEqual(row, pin(&p, name, 0).y);
            try testing.expectEqual(row, pin(&p, name, 2).y);
        }
        for ([_][]const u8{ "m12", "m14", "mn1", "mn2" }) |name| {
            try testing.expect(pin(&p, name, 0).y > row);
            try testing.expect(pin(&p, name, 2).y > row);
        }
        try expectElectrical(&p, lib);
    }
}

test "power compaction: AG1356's shunts stay between their connected main and coil terminals" {
    // Oracle: ag-1356.svg has MP3.D.x=220 < MN1.D.x=300 < LRX.1.x=370,
    // and LRX.2.x=430 < MN2.D.x=520 < MP2.D.x=580. Both relationships
    // are strict before compaction; the finished drawing must preserve
    // these electrical terminals' order across their different rows.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{ag1356}, null);
        defer p.deinit();
        for ([_][]const u8{ "mn1", "mn2" }, [_][]const u8{ "mp3", "mp2" }, 0..) |shunt, main, end| {
            const a = pin(&p, main, 0).x;
            const b = pin(&p, "lrx", @intCast(end)).x;
            const tap = pin(&p, shunt, 0);
            try testing.expect(tap.x > @min(a, b));
            try testing.expect(tap.x < @max(a, b));
            try testing.expect(tap.y > pin(&p, "lrx", @intCast(end)).y);
        }
        try expectElectrical(&p, lib);
    }
}

test "power compaction: an offset tall driver keeps its actual channel below the path" {
    // Oracles: the source's M12-below-path relation and this caller frame.
    // Its rotated D/S are 80 units apart; its origin and gate lie between
    // them, so preserving either of those points alone is insufficient.
    // In the original failure, M12.S reaches y=80 beside LRX.y=100 even
    // while the class origin remains below the power row at y=110.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const own = try lib.register(.{ .name = "offset_tall_driver", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 50, .y = 15 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 10, .y = -15 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -30, .y = 15 }, .side = .left },
    } });
    const src = ag1356 ++ "*@ class m12 offset_tall_driver\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        const d = np.checks.deviceIn(&p, "m12").?;
        const drain = pin(&p, "m12", 0);
        const source = pin(&p, "m12", 2);
        try testing.expectEqual(own, p.dev_class[d]);
        try testing.expectEqual(drain.x, source.x);
        try testing.expectEqual(@as(u32, 80), @abs(drain.y - source.y));
        try testing.expect(p.dev_pos[d].y != @min(drain.y, source.y));
        try testing.expect(@min(drain.y, source.y) > pin(&p, "lrx", 0).y);
        try expectElectrical(&p, lib);
    }
}

test "power compaction: explicit placement does not acquire an absent control-below relation" {
    // Oracle: the caller places the main path below the control rows.
    // Compaction may preserve an existing terminal order, not infer an
    // opposing one from the converter topology after explicit cells.
    const src = ag1356 ++ "*@ cell mp3 74 8\n*@ cell lrx 76 8\n*@ cell mp2 78 8\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        const row = pin(&p, "lrx", 0).y;
        try testing.expect(@min(pin(&p, "m12", 0).y, pin(&p, "m12", 2).y) <= row);
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var nl = try np.netlist.parse(a, &.{src}, null);
        const roles = try np.guessRoles(a, &nl);
        const st = try np.schematic.structure.analyze(a, a, &nl, roles);
        const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
        const verdicts = try np.report.verdicts(a, &nl, roles, &st, &sk, &p, lib);
        for (nl.hints, verdicts) |hint, verdict| if (hint.verb == .cell) {
            try testing.expectEqual(np.hints.State.honoured, verdict.state);
        };
        try expectElectrical(&p, lib);
    }
}
