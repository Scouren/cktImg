//! Reservoir boundary cases → actual electrical pin relations.
//! Cites: Analog-Genie AG1191 and AG1374, with deliberate topology and
//! caller-frame mutations of the full DUTs in power_reservoirs.zig.
//!
//! Human Rules:
//! - The outer reservoir convention needs one grounded capacitor on a
//!   main switch's outer channel net. Gate and coil nets are different
//!   branches; multiple grounded capacitors leave the choice ambiguous.
//! - Electrical net identity determines the signal terminal. Caller
//!   orientation and symbol frames retain precedence over default art.
//!
//! Contents: source fixtures, private pin checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

// Keep the complete source DUT and inferred external roles: reducing the
// amplifier changes the placement that exposes the reservoir failures.
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

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, terminal: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.dev_pin0[d] + terminal];
}

fn pinOn(p: *const np.Placed, name: []const u8, net: []const u8) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    for (p.dev_pin0[d]..p.dev_pin0[d + 1]) |i| {
        if (std.mem.eql(u8, p.net_name[p.pin_net[i]], net)) return p.pin_xy[i];
    }
    unreachable;
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

test "power reservoirs: parallel outer capacitors do not select an arbitrary reservoir" {
    // Negative oracle: two grounded capacitors on VP invalidate the
    // single-reservoir case. Ordinary placement leaves both above M3;
    // silently choosing either would raise the power path above them.
    // Disabling shelves isolates this admission decision from wrapping.
    const src = ag1191 ++ "CEXTRA VP VSS 3p\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 0 } }, lib, &.{src}, null);
        defer p.deinit();
        for ([_][]const u8{ "cop", "cextra" }) |name| {
            try testing.expect(pinOn(&p, name, "vp").y < pin(&p, "m3", 2).y);
        }
        try testing.expectEqual(pinOn(&p, "cop", "vp").y, pinOn(&p, "cextra", "vp").y);
        try expectElectrical(&p, lib);
    }
}

test "power reservoirs: grounded gate and coil capacitors do not set the outer path height" {
    // Negative oracle: only COP attaches to the main's outer VP net.
    // The extra cap is above COP but touches either M3.G or its inner
    // VX3 net. The main path belongs above COP and below the extra cap;
    // a scan of every grounded cap would incorrectly raise it further.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{
        ag1191 ++ "CGATE VCONT5 VSS 1p\n",
        ag1191 ++ "CCOIL VX3 VSS 1p\n*@ above ccoil cop\n",
    }, [_][]const u8{ "cgate", "ccoil" }) |src, extra| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 0 } }, lib, &.{src}, null);
        defer p.deinit();
        try testing.expect(pin(&p, extra, 0).y < pin(&p, "m3", 2).y);
        try expectBranch(pin(&p, "cop", 0), pin(&p, "cop", 1), pin(&p, "m3", 2), pin(&p, "l1", 1));
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    };
}

test "power reservoirs: reversing capacitor terminals preserves electrical geometry" {
    // Metamorphic oracle: swapping an unpolarized capacitor's net cards
    // changes terminal indices, never the coordinates of its nets.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const first = try std.mem.replaceOwned(u8, gpa, ag1374, "CSTO VSTO VSS 1p", "CSTO VSS VSTO 1p");
    defer gpa.free(first);
    const reversed = try std.mem.replaceOwned(u8, gpa, first, "CL VOUT VSS 1p", "CL VSS VOUT 1p");
    defer gpa.free(reversed);
    for ([_]bool{ false, true }) |compact| {
        const cfg: np.Config = .{ .layout = .{ .compact = compact } };
        var before = try np.place(gpa, &cfg, lib, &.{ag1374}, null);
        defer before.deinit();
        var after = try np.place(gpa, &cfg, lib, &.{reversed}, null);
        defer after.deinit();
        for ([_][]const u8{ "csto", "cl" }, [_][]const u8{ "vsto", "vout" }, [_][]const u8{ "mp3", "mp2" }, 0..) |name, signal, main, end| {
            try testing.expectEqual(pinOn(&before, name, signal), pinOn(&after, name, signal));
            try testing.expectEqual(pinOn(&before, name, "vss"), pinOn(&after, name, "vss"));
            try expectBranch(pinOn(&after, name, signal), pinOn(&after, name, "vss"), pin(&after, main, 2), pin(&after, "lrx", @intCast(end)));
        }
        try expectElectrical(&before, lib);
        try expectElectrical(&after, lib);
    }
}

test "power reservoirs: an explicit downward signal terminal overrides the default face" {
    // Caller oracle: CSTO.a is the signal and faces down, so the ground
    // terminal is above it. The source convention cannot flip that face.
    const src = ag1374 ++ "*@ face csto a down\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        try testing.expectEqual(pin(&p, "csto", 0).x, pin(&p, "csto", 1).x);
        try testing.expect(pin(&p, "csto", 0).y > pin(&p, "csto", 1).y);
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    }
}

test "power reservoirs: a shifted tall capacitor keeps its actual signal below the path" {
    // Oracles: AG1374's outer-reservoir relation and the caller's frame.
    // The leads are 80 units apart and offset from the class origin, so
    // testing a device center in place of its signal terminal is unsound.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const own = try lib.register(.{ .name = "offset_tall_cap", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -50, .y = 15 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 30, .y = 15 }, .side = .right },
    } });
    const src = ag1374 ++ "*@ class csto offset_tall_cap\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        const d = np.checks.deviceIn(&p, "csto").?;
        const signal = pin(&p, "csto", 0);
        const ground = pin(&p, "csto", 1);
        try testing.expectEqual(own, p.dev_class[d]);
        try testing.expectEqual(@as(i32, 80), ground.y - signal.y);
        try testing.expect(p.dev_pos[d].y != signal.y);
        try expectBranch(signal, ground, pin(&p, "mp3", 2), pin(&p, "lrx", 0));
        try expectElectrical(&p, lib);
    }
}
