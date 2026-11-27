//! Regressions for the names a drawing writes and the wires a named net
//! keeps: the text gate (`text_overlaps.find`) over the fixture decks, the
//! corpus decks whose names it caught on a symbol, a name or a wire, a cut
//! net's adjacent pins, the supplies read by name, and a `port` line's side.
//! Each deck is the corpus file with its `.subckt dut` wrapper removed and
//! the `*@ weak role` lines `cktimg-json` adds for its ports written in.
//!
//! Oracles: the text gate (boxes from `geom.nameRect`/`refdesRect`, checked
//! after drawing, apart from the code that placed them); `wire_ink.connected`
//! for wires; hand-read roles for the names.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const fixtures = @import("fixtures.zig");
const ink = @import("wire_ink.zig");

/// The fixture decks known to draw a name on a symbol, a name or another
/// net's wire: a known failure of text_overlaps.1. A deck that leaves this
/// list fails the test until its name is taken out.
const known_overlaps = [_][]const u8{
    "bus/bus_8bit_dac.sp",
    "bus/bus_current_dac.sp",
    "bus/bus_decoder_2to4.sp",
    "bus/bus_parallel_adder.sp",
    "bus/bus_sram_cell_array.sp",
    "mixed_signal/phase_detector.sp",
    "testbench/tb_cmos_inverter_vtc.sp",
    // The `outn` port stands on the block's bottom edge in both (it did
    // before the box widened to clear its title, library.9); its name now
    // falls on the wider box.
    "testbench/tb_diff_pair_cmrr.sp",
    "testbench/tb_diff_pair_offset.sp",
};

/// AG1003: m8's name on the `vb1` port beside it ("m8vb1").
const ag1003 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\* top cell
    \\IBIAS Vb2 VSS DC 1m
    \\M1 net5 net4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M10 net2 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 vout net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 VDD net8 vout VSS nch l=0.15 w=1 nf=1 m=1
    \\M13 Vb1 Vb2 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 net3 Vb1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 net0 net4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net4 net1 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net8 net1 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net1 Vb2 net7 VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 net8 Vb2 net6 VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 net7 Vb1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 net6 Vb1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 net2 Vb1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 vin net1 1k
    \\R2 net1 net8 1k
    \\R3 net1 net4 1k
    \\R4 Vb1 Vb2 1k
;

/// AG1004: the `vo1` and `vo2` port names over the net5 and net2 wires.
const ag1004 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\* top cell
    \\*@ weak role vo1 output
    \\*@ weak role vo2 output
    \\*@ weak role vi1 input
    \\*@ weak role vi2 input
    \\C1 vo1 net4 1p
    \\C2 vo2 net3 1p
    \\M1 net5 vi1 net6 VSS nch l=0.15 w=1 nf=1 m=1
    \\M10 net0 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M13 net0 net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 net1 net5 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 net2 vi2 net6 VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net5 VBP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 net2 VBP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 net6 VBN VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 vo2 net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 vo1 net5 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 vo2 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 vo1 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 net4 net5 1k
    \\R2 net3 net2 1k
;

/// AG59: the `vout` label written up onto the `net0` wire.
const ag59 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\* top cell
    \\M1 Vout Vin net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 Vout net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\RS net0 VSS 1k
;

/// AR3201: `vx` named at m16's drain and at r3's top, one column apart.
const ar3201 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\.model qpnp pnp
    \\
    \\.subckt icm_opamp_vdd_vss VDD VSS VIP VIN VOUT params: gain=1e6
    \\Blin nlin 0 V={gain*(V(VIP)-V(VIN))}
    \\Bcore VOUT 0 V={0.5*(V(VDD)+(0.5*(V(VSS)+V(nlin)+sqrt((V(nlin)-V(VSS))*(V(nlin)-V(VSS))+(1e-4*(V(VDD)-V(VSS)))*(1e-4*(V(VDD)-V(VSS)))+1e-12)))-sqrt((V(VDD)-(0.5*(V(VSS)+V(nlin)+sqrt((V(nlin)-V(VSS))*(V(nlin)-V(VSS))+(1e-4*(V(VDD)-V(VSS)))*(1e-4*(V(VDD)-V(VSS)))+1e-12))))*(V(VDD)-(0.5*(V(VSS)+V(nlin)+sqrt((V(nlin)-V(VSS))*(V(nlin)-V(VSS))+(1e-4*(V(VDD)-V(VSS)))*(1e-4*(V(VDD)-V(VSS)))+1e-12))))+(1e-4*(V(VDD)-V(VSS)))*(1e-4*(V(VDD)-V(VSS)))+1e-12))}
    \\.ends icm_opamp_vdd_vss
    \\
    \\.subckt opamp_differential VDD VSS VIP VIN VOP VON params: gain=1e6 vocm=0
    \\VCM ncm 0 DC {vocm}
    \\EPLUS VOP ncm VIP VIN {gain/2}
    \\EMINUS VON ncm VIN VIP {gain/2}
    \\.ends opamp_differential
    \\
    \\* top cell
    \\M10 net19 net3 VDDL VDD pch l=0.15 w=1 nf=1 m=1
    \\M11 net6 net6 net11 VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net5 net3 VDDL VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 VR1 net9 net5 VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 net3 net9 net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M15 net14 net3 VDDL VDD pch l=0.15 w=1 nf=1 m=1
    \\M16 VX net9 net14 VDD pch l=0.15 w=1 nf=1 m=1
    \\M17 net17 net3 VDDL VDD pch l=0.15 w=1 nf=1 m=1
    \\M18 net6 net9 net17 VDD pch l=0.15 w=1 nf=1 m=1
    \\M19 E net9 net19 VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 net2 net3 VDDL VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 net9 VX net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M21 net0 net4 net16 VSS nch l=0.15 w=1 nf=1 m=1
    \\M22 net4 VX net7 VSS nch l=0.15 w=1 nf=1 m=1
    \\M23 net7 net4 net12 VSS nch l=0.15 w=1 nf=1 m=1
    \\M24 net8 net8 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M25 net8 VR1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M26 net1 net8 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M27 net1 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M28 VX net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 F net6 net10 VSS nch l=0.15 w=1 nf=1 m=1
    \\Q1 VSS net15 net13 qpnp m=1
    \\Q2 VSS net11 net12 qpnp m=1
    \\Q3 VSS VSS net15 qpnp m=1
    \\Q4 VSS VSS net11 qpnp m=1
    \\R1 net16 net13 1k
    \\R2 net3 net9 1k
    \\R3 VX net4 1k
    \\R4 F Voutp 1k
    \\R5 E Voutn 1k
    \\R6 net10 VSS 1k
    \\RM VR1 net15 1k
    \\Rr1 VDDL net18 1k
    \\Rr2 net18 VSS 1k
    \\X1 VDD VSS E F Voutp Voutn opamp_differential gain=1e6 vocm=0
    \\X2 VDD VSS VR1 net18 VDDL icm_opamp_vdd_vss gain=1e6
;

/// AG1108 as hinted in the trial's round 1: `port rfoutp left` drew the
/// port at the right end of the wire.
const ag1108 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\
    \\* top cell
    \\*@ weak role rfoutp output
    \\*@ weak role rfoutn output
    \\*@ role rfinp input
    \\*@ role rfinn input
    \\*@ role vg1 bias
    \\*@ role vg2 bias
    \\*@ role vg3 bias
    \\*@ face mp1 g right
    \\*@ face mp2 g right
    \\*@ face mp3 g right
    \\*@ face mp4 g left
    \\*@ face mp5 g left
    \\*@ face mp6 g left
    \\*@ port rfinp left
    \\*@ port rfinn right
    \\*@ port rfoutp left
    \\*@ port rfoutn right
    \\CF1 net1 RFinp 1p
    \\CF2 net0 RFinn 1p
    \\Cg2L G2p VSS 1p
    \\Cg2R G2n VSS 1p
    \\Cg3L G3p VSS 1p
    \\Cg3R G3n VSS 1p
    \\Cnp1L net2 RFinn 1p
    \\Cnp1R Vd1 RFinp 1p
    \\Cpn2L net3 G2n 1p
    \\Cpn2R Vd2 G2p 1p
    \\Cpn3L RFoutp G3n 1p
    \\Cpn3R RFoutn G3p 1p
    \\MP1 net2 RFinp VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP2 net3 G2p net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\MP3 RFoutp G3p net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\MP4 Vd1 RFinn VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP5 Vd2 G2n Vd1 VSS nch l=0.15 w=1 nf=1 m=1
    \\MP6 RFoutn G3n Vd2 VSS nch l=0.15 w=1 nf=1 m=1
    \\RcsL Vg1 RFinp 1k
    \\RcsR Vg1 RFinn 1k
    \\RF1 RFoutp net1 1k
    \\RF2 RFoutn net0 1k
    \\Rg2L Vg2 G2p 1k
    \\Rg2R Vg2 G2n 1k
    \\Rg3L Vg3 G3p 1k
    \\Rg3R Vg3 G3n 1k
;

fn place(lib: *np.Library, src: []const u8) !np.Placed {
    return np.place(testing.allocator, &.default, lib, &.{src}, null);
}

fn overlaps(p: *const np.Placed, lib: *const np.Library) !usize {
    var found: std.ArrayList(np.text_overlaps.Overlap) = .empty;
    defer found.deinit(testing.allocator);
    try np.text_overlaps.find(testing.allocator, &found, p, lib);
    for (found.items) |o| std.debug.print("  {t} {s} over {t} {s}\n", .{ o.of, o.text, o.over, o.other });
    return found.items.len;
}

test "text gate: the fixture decks that draw names on something are the known ones" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var flagged: std.ArrayList([]const u8) = .empty;
    defer flagged.deinit(gpa);
    for (fixtures.plugin) |f| {
        var p = np.place(gpa, &.default, lib, &.{f.spice}, null) catch continue;
        defer p.deinit();
        var found: std.ArrayList(np.text_overlaps.Overlap) = .empty;
        defer found.deinit(gpa);
        try np.text_overlaps.find(gpa, &found, &p, lib);
        if (found.items.len > 0) try flagged.append(gpa, f.name);
    }
    errdefer for (flagged.items) |n| std.debug.print("flagged: {s}\n", .{n});
    try testing.expectEqual(known_overlaps.len, flagged.items.len);
    for (known_overlaps, flagged.items) |want, got| try testing.expectEqualStrings(want, got);
}

test "text gate: a device's name, a port's and a label's clear on the decks that overlapped" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{ ag1003, ag1004, ag59 }) |deck| {
        var p = try place(lib, deck);
        defer p.deinit();
        try testing.expectEqual(@as(usize, 0), try overlaps(&p, lib));
    }
}

test "cut net: two near pins in one column stay wired when the part's trunk does not fit" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try place(lib, ar3201);
    defer p.deinit();
    const m16 = np.checks.deviceIn(&p, "m16").?;
    const r3 = np.checks.deviceIn(&p, "r3").?;
    const drain: usize = p.dev_pin0[m16];
    const top: usize = p.dev_pin0[r3];
    try testing.expectEqualStrings("vx", p.net_name[p.pin_net[drain]]);
    try testing.expectEqual(p.pin_net[drain], p.pin_net[top]);
    try testing.expectEqual(p.pin_xy[drain].x, p.pin_xy[top].x);
    try testing.expect(try ink.connected(testing.allocator, &p, &.{ drain, top }));
}

test "roles: `+<volts>v` is a supply; `vs` only on a p-type source with no other supply" {
    const gpa = testing.allocator;
    const Case = struct { deck: []const u8, net: []const u8, role: np.Role };
    const cases = [_]Case{
        .{ .deck = "plus\n.model qn npn\nQ1 +12v b out qn\nR1 out 0 1k\n", .net = "+12v", .role = .supply },
        .{ .deck = "plus\n.model qn npn\nQ1 +3.3v b out qn\nR1 out 0 1k\n", .net = "+3.3v", .role = .supply },
        // AR6228: pnp emitters and an npn collector on `vs`, no `vdd`.
        .{ .deck = "vs\n.model qp pnp\n.model qn npn\nQ10 a a vs qp\nQ7 vs a c qn\nR1 c 0 1k\n", .net = "vs", .role = .supply },
        // AR5873: a source node fed from `vdd` through RS.
        .{ .deck = "vs\n.model pch pmos\nM1 vd vg vs vdd pch\nRS vdd vs 1k\nR2 vd 0 1k\n", .net = "vs", .role = .internal },
        // A pmos drain on `vs`: a switched supply node, AG1208.
        .{ .deck = "vs\n.model pch pmos\nM1 vs g a a pch\nM2 b g vs vs pch\nR1 b 0 1k\n", .net = "vs", .role = .internal },
    };
    for (cases) |c| {
        var nl = try np.netlist.parse(gpa, &.{c.deck}, null);
        defer nl.deinit(gpa);
        const roles = try np.guessRoles(gpa, &nl);
        defer gpa.free(roles);
        try testing.expectEqual(c.role, roles[nl.net(c.net).?.index()]);
    }
}

test "port line: an output's port stands at the end of its wire the line asks" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try place(lib, ag1108);
    defer p.deinit();
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "rfoutp")) break i;
    } else return error.NoNet;
    var port: ?np.Pt = null;
    var lo: i32 = std.math.maxInt(i32);
    for (0..p.deviceCount()) |d| {
        const a, const b = p.pinRange(d);
        for (a..b) |pin| if (p.pin_net[pin] == net) {
            if (p.dev_name[d].len == 0) port = p.pin_xy[pin] else lo = @min(lo, p.pin_xy[pin].x);
        };
    }
    // No pin of the net stands left of it (level with rf1's end, at worst).
    try testing.expect(port.?.x <= lo);
}
