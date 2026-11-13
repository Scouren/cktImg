//! Switched-capacitor signal placement; source SVG coordinates are the oracle.
//! Contents: tests only.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

const prefix = "Switched amplifier\n.model nch nmos\n.model pch pmos\n" ++
    ".subckt opamp VDD VSS VIP VIN VOUT\n.ends\n";
const ag762 = prefix ++ "C1 net1 net2 1p\nC2 net0 vout 1p\n" ++
    "M1 net1 phase_a vin vss nch\nM2 vout phase_b net1 vss nch\n" ++
    "M3 net0 phase_b net2 vss nch\nM4 net2 phase_a vss vss nch\n" ++
    "X1 0 vss vss net0 vout opamp\n";
const ag799 = prefix ++ "C1 net2 vout 1p\nC2 net3 net1 1p\nC3 vin net2 1p\nC4 net0 net3 1p\n" ++
    "M1 net0 phase_a vin vss nch\nM2 net0 phase_b vss vss nch\nM3 net3 phase_b vss vss nch\n" ++
    "M4 net2 phase_a net3 vss nch\nM5 net1 phase_b vss vss nch\nM6 vout phase_a net1 vss nch\n" ++
    "X1 0 vss vss net2 vout opamp\n";
const ag759 = prefix ++ "C1 vout net1 1p\nC2 vout net0 1p\n" ++
    "M1 vout phase_a vin vss nch\nM2 net1 phase_a net0 vss nch\nX1 0 vss vss net1 net0 opamp\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, terminal: usize) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.dev_pin0[d] + terminal];
}

fn expectMode(src: []const u8, signal: bool) !void {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var p = try np.place(gpa, &.default, lib, &.{src}, null);
    defer p.deinit();
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const decisions = try np.report.decisions(a, &nl, &st, &sk, &p, lib.unit, 2);
    // The public report's signal-placement certificate is a strong position
    // for every device at rung 2, instead of lattice rows/forms.
    var positions: usize = 0;
    for (decisions) |line| positions += @intFromBool(std.mem.startsWith(u8, line, "*@ at "));
    try testing.expectEqual(signal, positions > 0);
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "switched opamp: external gate controls enter signal placement without clock-name guesses" {
    // Oracle: AG759/762/799 source drawings place switches on the amplifier's
    // signal/feedback paths, and each control net touches MOS gates only.
    for ([_][]const u8{ ag759, ag762, ag799 }) |src| try expectMode(src, true);
    try expectMode(ag762 ++ "Vphase phase_a 0 PULSE(0 1 0 1n 1n 5n 10n)\n", true);
    const renamed = try std.mem.replaceOwned(u8, testing.allocator, ag762, "phase_", "arbitrary_control_");
    defer testing.allocator.free(renamed);
    try expectMode(renamed, true);
}

test "switched opamp: signal channels lie flat and local ground shunts stand upright" {
    // Oracle: AG762 M1/M2/M3 horizontal and M4 upright; AG799 M1/M4/M6
    // horizontal and M2/M3/M5 upright. These are conditional examples:
    // AG800/801 use different local axes on their rectangular feedback loops.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_]struct { []const u8, []const []const u8, []const []const u8 }{
        .{ ag762, &.{ "m1", "m2", "m3" }, &.{"m4"} },
        .{ ag799, &.{ "m1", "m4", "m6" }, &.{ "m2", "m3", "m5" } },
    }) |row| {
        var p = try np.place(gpa, &.default, lib, &.{row[0]}, null);
        defer p.deinit();
        for (row[1]) |name| {
            const d = pin(&p, name, 0);
            const g = pin(&p, name, 1);
            const s = pin(&p, name, 2);
            try testing.expectEqual(d.y, s.y);
            try testing.expect(d.x != s.x);
            try testing.expect(g.y < d.y);
        }
        for (row[2]) |name| {
            const d = pin(&p, name, 0);
            const s = pin(&p, name, 2);
            try testing.expectEqual(d.x, s.x);
            try testing.expect(d.y < s.y);
        }
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(gpa, &p, true));
    }
}

test "switched opamp: driven stages, ambiguous controls and transmission gates retain the lattice" {
    // Oracle negatives: AG807 source follower, AG2209 LDO and AG826 active
    // cascode use the amplifier output as a MOS gate drive. AG1069's dynamic
    // CMOS logic has pure external gates but supply-connected channels;
    // adding an output capacitor must not turn it into a sampled amplifier.
    // AG1042 steers current through a diode bridge. AG751's complementary
    // pair needs its own coordinated row/gate placement.
    const negative = [_][]const u8{
        prefix ++ "CH vout vss 1p\nM2 vdd drive vout vss nch\nX1 vdd vss vin vout drive opamp\n",
        prefix ++ "CL vout vss 1p\nR1 vout fb 1k\nR2 fb vss 1k\nMNP vin drive vout vss nch\nX1 vdd vss ref fb drive opamp\n",
        prefix ++ "R1 vdd vo 1k\nM1 mid vi vss vss nch\nM2 vo drive mid vss nch\nX1 vdd vss ref mid drive opamp\n",
        ag762 ++ "Rcontrol phase_a vin 1k\n",
        ag762 ++ "Ccontrol phase_a vin 1p\n",
        prefix ++ "CH out vss 1p\nM1 vin ck out vss nch\nM2 out ck_bar vin vdd pch\nX1 vdd vss out vout vout opamp\n",
        prefix ++ "M1 vdd ck x vdd pch\nM2 y ck vss vss nch\nMN0 middle a y vss nch\nMP0 middle a x vdd pch\n" ++
            ".subckt inverter VDD VSS A Y\n.ends\nX1 vdd vss x vout inverter\n",
        prefix ++ "M1 vdd ck x vdd pch\nM2 y ck vss vss nch\nMN0 middle a y vss nch\nMP0 middle a x vdd pch\n" ++
            ".subckt inverter VDD VSS A Y\n.ends\nX1 vdd vss x vout inverter\nCload vout vss 1p\n",
        prefix ++ ".model diode d\nCH net1 0 1p\nD1 net3 vin diode\nD2 net3 net1 diode\nD3 vin net0 diode\nD4 net1 net0 diode\n" ++
            "D5 vout net3 diode\nD6 net0 vout diode\nI1 vdd net3 1m\nI2 vdd net0 1m\nI3 net2 vss 1m\n" ++
            "M1 net3 hold net2 vss nch\nM2 net0 sample net2 vss nch\nX1 vdd vss vout net1 vout opamp\n",
        ag762 ++ "*@ role vin supply\n",
        ag762 ++ "*@ upright M3\n",
    };
    for (negative) |src| try expectMode(src, false);
}

test "switched opamp: a translated MOS symbol preserves electrical pin positions" {
    // Oracle: translating a symbol's entire local frame cannot move its
    // placed electrical terminals. Schemify's MOS channel midpoint is
    // offset from its symbol origin; its PMOS also reverses D/S order.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var baseline: ?np.Placed = null;
    defer if (baseline) |*p| p.deinit();
    for ([_]np.Pt{ .zero, .{ .x = 7, .y = 20 } }, 0..) |offset, k| {
        const name = if (k == 0) "mos_centered" else "mos_translated";
        var terms = [_]np.library.Terminal{
            .{ .name = "d", .at = .{ .x = 20, .y = 0 }, .side = .right },
            .{ .name = "g", .at = .{ .x = 0, .y = -20 }, .side = .up },
            .{ .name = "s", .at = .{ .x = -20, .y = 0 }, .side = .left },
            .{ .name = "b", .at = .zero, .hidden = true },
        };
        for (&terms) |*t| t.at = t.at.add(offset);
        const line = [_]np.library.DrawOp{.ln(-10 + offset.x, -3 + offset.y, 10 + offset.x, -3 + offset.y)};
        _ = try lib.register(.{ .name = name, .terminals = &terms, .draw = &line });
        const src = try std.fmt.allocPrint(gpa, "{s}*@ class M1 {s}\n*@ class M2 {s}\n*@ class M3 {s}\n*@ class M4 {s}\n", .{ ag762, name, name, name, name });
        defer gpa.free(src);
        var p = try np.place(gpa, &.default, lib, &.{src}, null);
        if (k == 0) {
            baseline = p;
            continue;
        }
        defer p.deinit();
        for ([_][]const u8{ "m1", "m2", "m3", "m4" }) |mos| for (0..3) |terminal| {
            try testing.expectEqual(pin(&baseline.?, mos, terminal), pin(&p, mos, terminal));
        };
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(gpa, &p, true));
    }
}

test "switched opamp: card reversal preserves every named device pin and turn" {
    // Oracle: a SPICE card permutation preserves the circuit and must not
    // choose a different drawing. Compare named electrical pins, since the
    // output device/net table indices correctly follow their input order.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_][]const u8{ ag759, ag762, ag799 }) |src| {
        var cards: std.ArrayList([]const u8) = .empty;
        defer cards.deinit(gpa);
        var lines = std.mem.tokenizeScalar(u8, src[prefix.len..], '\n');
        while (lines.next()) |line| try cards.append(gpa, line);
        std.mem.reverse([]const u8, cards.items);
        var reversed: std.ArrayList(u8) = .empty;
        defer reversed.deinit(gpa);
        try reversed.appendSlice(gpa, prefix);
        for (cards.items) |line| {
            try reversed.appendSlice(gpa, line);
            try reversed.append(gpa, '\n');
        }
        var before = try np.place(gpa, &.default, lib, &.{src}, null);
        defer before.deinit();
        var after = try np.place(gpa, &.default, lib, &.{reversed.items}, null);
        defer after.deinit();
        for (before.dev_name, 0..) |name, d| {
            if (name.len == 0) continue;
            const other = np.checks.deviceIn(&after, name).?;
            try testing.expectEqual(before.dev_orient[d], after.dev_orient[other]);
            try testing.expectEqualSlices(np.Pt, before.pin_xy[before.dev_pin0[d]..before.dev_pin0[d + 1]], after.pin_xy[after.dev_pin0[other]..after.dev_pin0[other + 1]]);
        }
    }
}

test "switched opamp: a custom MOS outside the reserved frame retains lattice placement" {
    // Oracle: AG762 M3 is upright on the lattice and flat in the signal
    // procedure. A caller's long gate cannot fit that procedure's bounded
    // reservations, so the whole drawing must retain general placement.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    _ = try lib.register(.{ .name = "long_gate", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 0, .y = -80 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -20, .y = 0 }, .side = .left },
    }, .draw = &.{.ln(0, -80, 0, -3)} });
    var p = try np.place(gpa, &.default, lib, &.{ag762 ++ "*@ class M1 long_gate\n"}, null);
    defer p.deinit();
    try testing.expectEqual(pin(&p, "m3", 0).x, pin(&p, "m3", 2).x);
    try testing.expect(pin(&p, "m3", 0).y != pin(&p, "m3", 2).y);
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(gpa, &p, true));
}
