//! Source converter DUTs → capacitor placement checks on electrical pins.
//! Cites: Analog-Genie AG1191, AG1309, AG1329 and AG1374 SVGs; all 718
//! capacitor terminals independently verified by converter_terminals.py.
//!
//! Human Rules:
//! - One grounded capacitor on a certified main path's outer endpoint
//!   stands vertically beyond that main MOS, away from the inductor.
//!   Its signal pin is at or below the main channel, its ground pin below.
//! - The signal may be level with the channel: AG1309 and AG1329 are the
//!   two equality cases among 359 source capacitors. Caller instructions
//!   for rows, cells, exact origins and mates retain their own geometry.
//!
//! Contents: source fixtures, private pin checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

// Full DUT bodies and exact cktimg-json inferred roles. Empty EA/ISR
// declarations preserve AG1309's external ports; hidden bodies do not
// affect its block drawing. These four fixtures reproduce every named
// device pin in the frozen iteration7 CLI result, byte for byte.
const ag1374 =
    \\AG1374 reservoir fixture
    \\.model nch nmos
    \\.model pch pmos
    \\CL VOUT VSS 1p
    \\CSTO VSTO VSS 1p
    \\LRX VX1 VX2 1n
    \\M1 net0 VX2 VX1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M10 net4 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net6 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net3 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 VB3 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 VB3 VB3 VB4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 VB4 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net1 net2 VX1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 VX1 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net0 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 net1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 net5 VB2 net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 net2 VB2 net1 VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 net5 VB3 net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 net2 VB3 net6 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN1 VX1 VCONT2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN2 VX2 VCONT3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP2 VX2 net2 VOUT VDD pch l=0.15 w=1 nf=1 m=1
    \\MP3 VX1 VCONT1 VSTO VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 net3 VSS 1k
    \\*@ weak role vsto output
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\
;

const ag1191 =
    \\AG1191 reservoir fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 VCONT2 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VX2 VCONT3 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 VX3 VCONT5 VP VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VCONT4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net9 VCONT1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MN1 net5 VFP1 net10 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN10 net1 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN11 VB3 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN12 net0 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN13 VBN VBN net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN14 net3 VBN VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN2 net4 VREF net10 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN3 net10 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN4 VG VBN VX1 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN5 VX1 VG VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN6 VCTRL VBN net8 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN7 net8 VG VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN8 net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN9 net6 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP1 VFP1 net5 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP10 net6 net6 net9 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP11 VX1 net6 net9 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP12 VB3 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP13 net0 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP14 VBN net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP2 net2 net5 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP3 VN net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP4 net7 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP5 VG VB1 VFP1 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP6 net5 VB1 net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP7 net4 VB1 VN VDD pch l=0.15 w=1 nf=1 m=1
    \\MP8 VCTRL VB1 net7 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP9 net1 VCTRL net9 VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\*@ weak role vcont4 input
    \\*@ weak role vcont5 input
    \\*@ weak role vp output
    \\
;

const ag1309 =
    \\AG1309 reservoir fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt EA VDD VSS OUT INN INP VX2
    \\.ends
    \\.subckt ISR VDD VSS VS VCTRL VB2 IOUT
    \\.ends
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 VCONT2 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VX2 VCONT3 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 VP VCONT5 VX3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VCONT4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net0 VCONT1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\X1 VDD VSS net1 VFP1 VREF VX2 EA
    \\X2 VDD VSS net0 net1 VB2 VX1 ISR
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\*@ weak role vcont4 input
    \\*@ weak role vcont5 input
    \\*@ weak role vp output
    \\
;

const ag1329 =
    \\AG1329 reservoir fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 net2 net4 net4 pch l=0.15 w=1 nf=1 m=1
    \\M10 VX2 VX2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net3 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net8 VX2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M13 VCTRL net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 net8 net8 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M15 VCTRL net8 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M16 net7 net7 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M17 net0 net7 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M18 net0 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 VBP net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net2 net2 net4 net4 pch l=0.15 w=1 nf=1 m=1
    \\M20 VBP VBP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M21 VIN VS5 net4 VIN pch l=0.15 w=1 nf=1 m=1
    \\M22 VX1 VS1 VIN VIN pch l=0.15 w=1 nf=1 m=1
    \\M23 VX2 VS2 VIN VIN pch l=0.15 w=1 nf=1 m=1
    \\M24 VX3 VS4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M25 VP VS3 VX3 VP pch l=0.15 w=1 nf=1 m=1
    \\M3 net5 VCTRL net4 net4 pch l=0.15 w=1 nf=1 m=1
    \\M4 net5 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net2 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 net5 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 net6 VBP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 VX2 VREF net6 net1 pch l=0.15 w=1 nf=1 m=1
    \\M9 net3 VFP1 net6 net1 pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\RBIAS net7 VSS 1k
    \\*@ weak role vp output
    \\*@ weak role vs5 input
    \\*@ weak role vs1 input
    \\*@ weak role vs2 input
    \\*@ weak role vs4 input
    \\*@ weak role vs3 input
    \\
;

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, terminal: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.dev_pin0[d] + terminal];
}

fn expectBranch(signal: np.Pt, ground: np.Pt, main: np.Pt, coil: np.Pt) !void {
    try testing.expectEqual(signal.x, ground.x);
    try testing.expect(ground.y > signal.y);
    try testing.expect(signal.y >= main.y);
    try testing.expect(if (main.x < coil.x) signal.x < main.x else signal.x > main.x);
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

test "power reservoirs: shelving keeps AG1374's capacitors beyond their main switches" {
    // Source oracle: CSTO.1=(190,40), MP3.S=(240,0), LRX.1=(350,0);
    // LRX.2=(410,0), MP2.S=(550,0), CL.1=(610,40). Each ground is 40
    // units below its capacitor's signal pin. Shelving formerly moved
    // CSTO across the main path and left CL above the channel.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{ag1374}, null);
        defer p.deinit();
        try expectBranch(pin(&p, "csto", 0), pin(&p, "csto", 1), pin(&p, "mp3", 2), pin(&p, "lrx", 0));
        try expectBranch(pin(&p, "cl", 0), pin(&p, "cl", 1), pin(&p, "mp2", 2), pin(&p, "lrx", 1));
        try expectElectrical(&p, lib);
    }
}

test "power reservoirs: AG1191's output capacitor stays below the flying converter path" {
    // Source oracle: L1.2=(290,340), M3.S=(410,340), COP.1=(590,380),
    // COP.2=(590,420). CFLY and CO are not grounded reservoirs. Keeping
    // the full amplifier and original port roles reproduces the failure
    // that disappears when this DUT is reduced to only its power devices.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]u32{ 0, 8 }) |shelf| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = shelf } }, lib, &.{ag1191}, null);
        defer p.deinit();
        try expectBranch(pin(&p, "cop", 0), pin(&p, "cop", 1), pin(&p, "m3", 2), pin(&p, "l1", 1));
        try expectElectrical(&p, lib);
    };
}

test "power reservoirs: the two source equality cases permit a level signal pin" {
    // Source oracle: AG1309 COP.1 and M3.D have y=80; AG1329 COP.1 and
    // M25.D have y=290. The same outer reservoir relation permits equality.
    // Caller origins below create that exact relation at y=-80, with
    // COP's ground at -40; forcing strict separation would violate them.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{
        ag1309 ++ "*@ at l1 10 -2 r0\n*@ at m3 15 -2 r0\n*@ at cop 20 -1.5 r90\n",
        ag1329 ++ "*@ at l1 10 -2 r0\n*@ at m25 15 -2 r0\n*@ at cop 20 -1.5 r90\n",
    }, [_][]const u8{ "m3", "m25" }) |src, main| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        const signal = pin(&p, "cop", 0);
        const channel = pin(&p, main, 0);
        try testing.expectEqual(@as(i32, -80), signal.y);
        try testing.expectEqual(signal.y, channel.y);
        try expectBranch(signal, pin(&p, "cop", 1), channel, pin(&p, "l1", 1));
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    };
}

test "power reservoirs: caller cells and exact origins may place a capacitor above the path" {
    // Oracle: explicit caller placement overrides the inferred vertical
    // order. Neither moving the capacitor back nor raising the main path
    // after the caller's final placement is an acceptable substitution.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{
        ag1374 ++ "*@ cell csto -8 -6\n",
        ag1374 ++ "*@ at csto -2 -5 r90\n",
    }, 0..) |src, k| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        try testing.expect(pin(&p, "csto", 0).y < pin(&p, "mp3", 2).y);
        if (k == 1) {
            const d = np.checks.deviceIn(&p, "csto").?;
            try testing.expectEqual(np.Pt{ .x = -80, .y = -200 }, p.dev_pos[d]);
        }
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    };
}

test "power reservoirs: admitted rows, vertical order and mates retain their relationships" {
    // Oracle: the three independent caller relations. A mixed row can put
    // the capacitor's signal above its main MOS; an above relation must
    // survive shelf cuts; paired reservoirs retain their mirrored row.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{
        ag1374 ++ "*@ row csto mp3\n",
        ag1374 ++ "*@ above csto cl\n",
        ag1374 ++ "*@ group pair csto cl\n",
    }, 0..) |src, k| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        switch (k) {
            0 => {
                const capacitor = np.checks.deviceIn(&p, "csto").?;
                const main = np.checks.deviceIn(&p, "mp3").?;
                try testing.expectEqual(p.dev_pos[capacitor].y, p.dev_pos[main].y);
                try testing.expect(pin(&p, "csto", 0).y < pin(&p, "mp3", 2).y);
            },
            1 => try testing.expect(pin(&p, "csto", 0).y < pin(&p, "cl", 0).y),
            2 => {
                try testing.expectEqual(pin(&p, "csto", 0).y, pin(&p, "cl", 0).y);
                const center = np.checks.deviceIn(&p, "lrx").?;
                try testing.expectEqual(2 * p.dev_pos[center].x, pin(&p, "csto", 0).x + pin(&p, "cl", 0).x);
            },
            else => unreachable,
        }
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    };
}

test "power reservoirs: reversed source cards preserve named electrical geometry" {
    // Metamorphic oracle: source card order cannot change the circuit or
    // the coordinates and turns of its named electrical terminals.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var lines: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, ag1374, '\n');
    const title = it.next().?;
    while (it.next()) |line| try lines.append(a, line);
    std.mem.reverse([]const u8, lines.items);
    var reversed: std.ArrayList(u8) = .empty;
    try reversed.print(a, "{s}\n", .{title});
    for (lines.items) |line| try reversed.print(a, "{s}\n", .{line});
    var before = try np.place(gpa, &.default, lib, &.{ag1374}, null);
    defer before.deinit();
    var after = try np.place(gpa, &.default, lib, &.{reversed.items}, null);
    defer after.deinit();
    for (before.dev_name, 0..) |name, d| {
        if (name.len == 0) continue;
        const other = np.checks.deviceIn(&after, name).?;
        try testing.expectEqual(before.dev_orient[d], after.dev_orient[other]);
        try testing.expectEqualSlices(np.Pt, before.pin_xy[before.dev_pin0[d]..before.dev_pin0[d + 1]], after.pin_xy[after.dev_pin0[other]..after.dev_pin0[other + 1]]);
    }
    try expectBranch(pin(&after, "csto", 0), pin(&after, "csto", 1), pin(&after, "mp3", 2), pin(&after, "lrx", 0));
    try expectBranch(pin(&after, "cl", 0), pin(&after, "cl", 1), pin(&after, "mp2", 2), pin(&after, "lrx", 1));
    try expectElectrical(&after, lib);
}
