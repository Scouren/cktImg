//! Recognized amplifier outputs -> source-backed two-MOS bank facing.
//! Oracles: actual source leads in driven-banks.md, explicit caller requests,
//! card permutation, and physical wire components rather than equal net names.
//!
//! Contents: source fixtures, private checks, then source and boundary tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

// Full outer DUT cards and exact opaque declarations. Their internal bodies
// are omitted: this rule reads only the already-declared external contract.
const ag735 =
    \\ag-735 driven bank
    \\.model pch pmos
    \\.subckt icm_opamp_vdd_vss vdd vss vip vin vout
    \\.ends icm_opamp_vdd_vss
    \\m1 net0 net1 vdd vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 iout net1 vdd vdd pch l=0.15 w=1 nf=1 m=1
    \\r net0 vss 1k
    \\x1 vdd vss net0 vref net1 icm_opamp_vdd_vss gain=1e6
    \\*@ weak role iout output
;

const ag2427 =
    \\ag-2427 driven bank
    \\.model nch nmos
    \\.model pch pmos
    \\.global VDD
    \\.subckt error_amplifier vss vref vea
    \\.ends error_amplifier
    \\m1 net1 vea vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net2 net2 net1 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net2 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net3 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net2 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net0 net0 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net0 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net0 vea net3 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vss vref vea error_amplifier
    \\*@ weak role verr output
;

const ag2436 =
    \\ag-2436 driven bank
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt bias vdd vss vb1 nb
    \\.ends bias
    \\.subckt error_amp vdd vss vref nb out
    \\.ends error_amp
    \\m1 net3 net4 vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net1 net1 net3 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net1 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net2 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net1 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net5 net5 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net5 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net5 net4 net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref net0 net4 error_amp
    \\x2 vdd vss vb1 net0 bias
    \\*@ weak role verr output
;

const signed = ".subckt opamp vdd vss inp inn out\n.ends\n";
const channels = ".model pch pmos\nM1 a control vdd vdd pch\nM2 b control vdd vdd pch\n" ++
    "RA a 0 1k\nRB b 0 2k\n*@ symmetry off\n";
const base = "Driven bank\n" ++ signed ++ channels ++ "X1 vdd 0 a ref control opamp\n";

// ---- private ----

fn pinIndex(p: *const np.Placed, name: []const u8, terminal: usize) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + terminal;
}

fn pin(p: *const np.Placed, name: []const u8, terminal: usize) np.Pt {
    return p.pin_xy[pinIndex(p, name, terminal)];
}

fn gateLeft(p: *const np.Placed, name: []const u8) bool {
    const drain = pin(p, name, 0);
    const gate = pin(p, name, 1);
    const source = pin(p, name, 2);
    std.debug.assert(drain.x == source.x);
    return gate.x < drain.x;
}

fn expectFacing(p: *const np.Placed, names: [2][]const u8) !void {
    for (names) |name| try testing.expect(gateLeft(p, name));
}

fn expectInward(p: *const np.Placed) !void {
    const left: []const u8 = if (pin(p, "m1", 0).x < pin(p, "m2", 0).x) "m1" else "m2";
    const right: []const u8 = if (std.mem.eql(u8, left, "m1")) "m2" else "m1";
    try testing.expect(!gateLeft(p, left));
    try testing.expect(gateLeft(p, right));
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
    const verdicts = try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib);
    for (verdicts) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
}

test "driven banks: complete signed and reference source banks face their output" {
    // Actual SVG: AG735 M1/M2 and AG2436 M1/MSEN gates all face left,
    // and each source's named output connects both gates through wire ink.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{ ag735, ag2436 }, 0..) |src, i| {
        for ([_]bool{ false, true }) |compact| {
            errdefer std.debug.print("driven source: {s}, compact={}\n", .{ if (i == 0) "ag-735" else "ag-2436", compact });
            var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
            defer p.deinit();
            const other: []const u8 = if (i == 0) "m2" else "msen";
            try expectFacing(&p, .{ "m1", other });
            try testing.expect(pin(&p, "x1", 4).x < pin(&p, "m1", 1).x);
            try testing.expect(pin(&p, "x1", 4).x < pin(&p, other, 1).x);
            try testing.expect(try ink.connected(testing.allocator, &p, &.{ pinIndex(&p, "x1", 4), pinIndex(&p, "m1", 1), pinIndex(&p, other, 1) }));
            try expectElectrical(&p, lib);
        }
    }
}

test "driven banks: complete VEA contract places the actual output before both gates" {
    // AG2427's VEA is a reference-amplifier output, not a global name rule.
    // Before contextual passage, its actual pin lies inside the bank even
    // though the block origin is left of the first channel.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{ag2427}, null);
        defer p.deinit();
        const output = pin(&p, "x1", 2);
        try testing.expect(output.x < pin(&p, "m1", 0).x);
        try testing.expect(output.x < pin(&p, "msen", 0).x);
        try expectElectrical(&p, lib);
    }
}

test "driven banks: digital opaque and competing drivers keep the existing bank choice" {
    // Source negatives AG744 and AG1076 prevent a universal output rule.
    // Unknown controls and two independent output drivers give no unique
    // recognized analog certificate, even with an otherwise familiar name.
    const variants = [_][]const u8{
        "Digital\n.subckt inverter a y\n.ends\n" ++ channels ++ "X1 ref control inverter\n",
        "Opaque\n.subckt opamp vdd vss inp inn out vx\n.ends\n" ++ channels ++ "X1 vdd 0 a ref control extra opamp\n",
        base ++ "X2 vdd 0 b ref2 control opamp\n",
        base ++ "M3 control other vdd vdd pch\n",
    };
    for (variants) |src| {
        // Definitions differ between cases; generated block caches belong
        // to one definition set, just as in the permutation test below.
        const lib = try support.library(testing.allocator);
        defer support.freeLibrary(testing.allocator, lib);
        var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
        defer p.deinit();
        try expectInward(&p);
        try expectElectrical(&p, lib);
    }
}

test "driven banks: passive capacitor loads do not invent a second driver" {
    // AG994's certified gate net also holds two capacitor terminals.
    const src = base ++ "C1 control a 1p\nC2 control b 2p\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
    defer p.deinit();
    try expectFacing(&p, .{ "m1", "m2" });
    try expectElectrical(&p, lib);
}

test "driven banks: explicit gate faces and fixed cells retain caller precedence" {
    const src = base ++ "*@ face m1 g right\n*@ face m2 g right\n" ++
        "*@ cell x1 8 2\n*@ cell m1 0 2\n*@ cell m2 4 2\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{src}, null);
    defer p.deinit();
    try testing.expect(!gateLeft(&p, "m1"));
    try testing.expect(!gateLeft(&p, "m2"));
    try testing.expect(p.dev_pos[np.checks.deviceIn(&p, "x1").?].x > pin(&p, "m2", 0).x);
    try testing.expect(pin(&p, "m2", 0).x > pin(&p, "m1", 0).x);
    try expectHonoured(src, &p, lib);
    try expectElectrical(&p, lib);
}

test "driven banks: fixed driver cells select the actual side without face hints" {
    // Whole-bank direction follows an exterior driver; a driver between
    // the channels retains the ordinary inward pair. Actual output pins
    // certify the position rather than assuming an unshifted block frame.
    const placements = [_][]const u8{
        "*@ cell m1 0 2\n*@ cell m2 4 2\n*@ cell x1 10 2\n",
        "*@ cell m1 0 2\n*@ cell x1 4 2\n*@ cell m2 8 2\n",
    };
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for (placements, 0..) |placement, i| {
        const src = try std.mem.concat(testing.allocator, u8, &.{ base, placement });
        defer testing.allocator.free(src);
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{src}, null);
        defer p.deinit();
        const output = pin(&p, "x1", 4);
        if (i == 0) {
            try testing.expect(output.x > pin(&p, "m1", 1).x);
            try testing.expect(output.x > pin(&p, "m2", 1).x);
            try testing.expect(!gateLeft(&p, "m1"));
            try testing.expect(!gateLeft(&p, "m2"));
        } else {
            try testing.expect(output.x > pin(&p, "m1", 0).x);
            try testing.expect(output.x < pin(&p, "m2", 0).x);
            try expectInward(&p);
        }
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    }
}

test "driven banks: equivalent port and card permutations preserve named geometry" {
    const original = base;
    const permuted = "Permuted bank\n.model pch pmos\n" ++
        ".subckt opamp out inn vss inp vdd\n.ends\n" ++
        "RB b 0 2k\nX1 control ref 0 a vdd opamp\nM2 b control vdd vdd pch\n" ++
        "RA a 0 1k\nM1 a control vdd vdd pch\n*@ symmetry off\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var a = try np.place(testing.allocator, &.default, lib, &.{original}, null);
    defer a.deinit();
    // Generated block classes are cached by family name. Independent
    // definitions need independent libraries, so cached pin order cannot
    // contaminate the declaration-permutation oracle.
    const other_lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, other_lib);
    var b = try np.place(testing.allocator, &.default, other_lib, &.{permuted}, null);
    defer b.deinit();
    for (lib.at(a.dev_class[np.checks.deviceIn(&a, "x1").?]).terminals, [_][]const u8{ "vdd", "vss", "inp", "inn", "out" }) |terminal, name| try testing.expectEqualStrings(name, terminal.name);
    for (other_lib.at(b.dev_class[np.checks.deviceIn(&b, "x1").?]).terminals, [_][]const u8{ "out", "inn", "vss", "inp", "vdd" }) |terminal, name| try testing.expectEqualStrings(name, terminal.name);
    try expectFacing(&a, .{ "m1", "m2" });
    try expectFacing(&b, .{ "m1", "m2" });
    for ([_][]const u8{ "m1", "m2", "ra", "rb" }) |name| {
        const i = np.checks.deviceIn(&a, name).?;
        const j = np.checks.deviceIn(&b, name).?;
        try testing.expectEqual(a.dev_orient[i], b.dev_orient[j]);
        try testing.expectEqualSlices(np.Pt, a.pin_xy[a.dev_pin0[i]..a.dev_pin0[i + 1]], b.pin_xy[b.dev_pin0[j]..b.dev_pin0[j + 1]]);
    }
    try testing.expectEqual(pin(&a, "x1", 4), pin(&b, "x1", 0));
    try expectElectrical(&a, lib);
    try expectElectrical(&b, other_lib);
}

test "driven banks: exact symmetry mates keep their opposing gates" {
    // The literal circuit exchanges M1/RA with M2/RB and fixes the driver.
    // This is an existing whole-column mirror contract, not an inferred
    // bank-side preference. Confirm the symmetry witness before the oracle.
    const src = "Symmetric bank\n" ++ signed ++ ".model pch pmos\n" ++
        "M1 a control vdd vdd pch\nM2 b control vdd vdd pch\n" ++
        "RA a 0 1k\nRB b 0 1k\nX1 vdd 0 ref 0 control opamp\n";
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const m1 = nl.device("m1").?.index();
    const m2 = nl.device("m2").?.index();
    try testing.expectEqual(m2, st.device_mate[m1]);
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
    defer p.deinit();
    try expectInward(&p);
    try expectElectrical(&p, lib);
}

test "driven banks: shifted caller MOS terminals supply the physical facing oracle" {
    // A valid shifted frame keeps its gate outside the body. Measuring the
    // origin would give the wrong center; the actual D/S column defines it.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    _ = try lib.register(.{
        .name = "shifted_bank_pmos",
        .terminals = &.{
            .{ .name = "d", .at = .{ .x = 50, .y = 15 }, .side = .right },
            .{ .name = "g", .at = .{ .x = 10, .y = -15 }, .side = .up },
            .{ .name = "s", .at = .{ .x = -30, .y = 15 }, .side = .left },
        },
        .draw = &.{
            .{ .line = .{ .a = .{ .x = -30, .y = 15 }, .b = .{ .x = 50, .y = 15 } } },
            .{ .line = .{ .a = .{ .x = -10, .y = 0 }, .b = .{ .x = 30, .y = 0 } } },
            .{ .line = .{ .a = .{ .x = 10, .y = -15 }, .b = .{ .x = 10, .y = 0 } } },
        },
    });
    const src = base ++ "*@ class m1 shifted_bank_pmos\n*@ class m2 shifted_bank_pmos\n";
    var p = try np.place(gpa, &.default, lib, &.{src}, null);
    defer p.deinit();
    try expectFacing(&p, .{ "m1", "m2" });
    try expectElectrical(&p, lib);
}

test "driven banks: shifted caller amplifier frame retains its actual output" {
    // A conventional rightward triangle translated by (80, 30) inside its
    // class. This certifies a real shifted driver frame, not every possible
    // custom output direction or caller-imposed overlap.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const custom = try lib.register(.{
        .name = "shifted_bank_driver",
        .terminals = &.{
            .{ .name = "vdd", .at = .{ .x = 80, .y = -30 }, .side = .up },
            .{ .name = "vss", .at = .{ .x = 80, .y = 90 }, .side = .down },
            .{ .name = "inp", .at = .{ .x = 20, .y = 50 }, .side = .left },
            .{ .name = "inn", .at = .{ .x = 20, .y = 10 }, .side = .left },
            .{ .name = "out", .at = .{ .x = 140, .y = 30 }, .side = .right },
        },
        .draw = &.{
            .{ .polyline = &.{ .{ .x = 40, .y = -10 }, .{ .x = 120, .y = 30 }, .{ .x = 40, .y = 70 }, .{ .x = 40, .y = -10 } } },
            .{ .line = .{ .a = .{ .x = 80, .y = -30 }, .b = .{ .x = 80, .y = 10 } } },
            .{ .line = .{ .a = .{ .x = 80, .y = 90 }, .b = .{ .x = 80, .y = 50 } } },
            .{ .line = .{ .a = .{ .x = 20, .y = 50 }, .b = .{ .x = 40, .y = 50 } } },
            .{ .line = .{ .a = .{ .x = 20, .y = 10 }, .b = .{ .x = 40, .y = 10 } } },
            .{ .line = .{ .a = .{ .x = 140, .y = 30 }, .b = .{ .x = 120, .y = 30 } } },
        },
    });
    const src = base ++ "*@ class x1 shifted_bank_driver\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        const d = np.checks.deviceIn(&p, "x1").?;
        try testing.expectEqual(custom, p.dev_class[d]);
        try testing.expectEqual(p.dev_pos[d].add(p.dev_orient[d].apply(.{ .x = 140, .y = 30 })), pin(&p, "x1", 4));
        try testing.expect(pin(&p, "x1", 4).x < pin(&p, "m1", 1).x);
        try testing.expect(pin(&p, "x1", 4).x < pin(&p, "m2", 1).x);
        try expectFacing(&p, .{ "m1", "m2" });
        try expectElectrical(&p, lib);
    }
}
