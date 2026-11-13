//! Source auxiliary input-bus branch -> continuous ink through all three switches.
//! Cites: AG1316 SVG M5.S=(50,-70), M1.S=(50,60), M2.S=(50,240),
//! joined by x=0 conductor ink. This covers a branch outside the selected
//! ten-device loop; shared port labels cannot replace its actual wire.
//! Human Rules:
//! - A nearby auxiliary switch sharing the input bus keeps its physical
//!   connection when the selected converter receives a shifted bus spine.
//! - Explicit port side preserves that connection with compaction on or off.
//! - Proximity belongs to the existing wire tree: its lower branch can
//!   stand close to an auxiliary switch even when the retained pin is far.
//!
//! Contents: complete literal DUT, pin lookup, then public placement test.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1316 =
    \\AG1316 remote loop terminal fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt EA1 VDD VSS VFP1 VREF VX2 VB1 VISR VX1
    \\.ends
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 VS1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VX2 VS2 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 VP VS3 VX3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VS4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net0 VS5 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\X1 VDD VSS VFP1 VREF VX2 VB1 net0 VX1 EA1
    \\*@ weak role vs1 input
    \\*@ weak role vs2 input
    \\*@ weak role vs3 input
    \\*@ weak role vs4 input
    \\*@ weak role vs5 input
    \\*@ weak role vp output
    \\
;

const ag1249 =
    \\ag-1249 auxiliary bus regression
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt EA1 VDD VSS VCTRL VREF VFP1 VX3
    \\.ends
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
    \\M5 net3 VCONT1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MN6 net0 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN7 net2 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN8 net2 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP5 net0 net0 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP6 VX1 net0 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP7 net2 net1 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\X1 VDD VSS net1 VREF VFP1 VX3 EA1
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\*@ weak role vcont4 input
    \\*@ weak role vcont5 input
    \\*@ weak role vp output
    \\
;

const ag1263 =
    \\ag-1263 auxiliary bus regression
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt EA1 VDD VSS VCTRL VREF VFP1 VX3
    \\.ends
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 VS1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VX2 VS2 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 VP VS3 VX3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VS4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net1 VS5 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MN10 net2 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN11 net0 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN12 net2 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP7 net0 net0 net1 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP8 VX1 net0 net1 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP9 net2 net3 net1 VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\X1 VDD VSS net3 VREF VFP1 VX3 EA1
    \\*@ weak role vs1 input
    \\*@ weak role vs2 input
    \\*@ weak role vs3 input
    \\*@ weak role vs4 input
    \\*@ weak role vs5 input
    \\*@ weak role vp output
    \\
;

const ag1294 =
    \\ag-1294 auxiliary bus regression
    \\.model nch nmos
    \\.model pch pmos
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 VCONT2 VIN VIN pch l=0.15 w=1 nf=1 m=1
    \\M2 VX2 VCONT3 VIN VIN pch l=0.15 w=1 nf=1 m=1
    \\M3 VX3 VCONT5 VP VP pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VCONT4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 VSR VCONT1 VIN VIN pch l=0.15 w=1 nf=1 m=1
    \\MN1 net3 VX2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN10 VB3 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN11 net0 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN12 VA net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN2 VX2 VX2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN3 VA VA VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN4 VCTRL VA VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN6 VG net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN7 net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN8 net1 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN9 VB1 VB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP1 net3 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP10 VB3 VB3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP11 net0 VA VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP12 VA VA VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP2 net2 VB3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP3 VCTRL net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP4 VG VG VSR VSR pch l=0.15 w=1 nf=1 m=1
    \\MP5 VX1 VG VSR VSR pch l=0.15 w=1 nf=1 m=1
    \\MP6 net1 VCTRL VSR VSR pch l=0.15 w=1 nf=1 m=1
    \\MP7 VX2 VREF net2 net4 pch l=0.15 w=1 nf=1 m=1
    \\MP8 VA VFP1 net2 net4 pch l=0.15 w=1 nf=1 m=1
    \\MP9 VB1 VB3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\RBIAS VDD net0 1k
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\*@ weak role vcont4 input
    \\*@ weak role vcont5 input
    \\*@ weak role vp output
    \\
;

// ---- private ----

fn terminal(p: *const np.Placed, name: []const u8, index: u32) usize {
    const d = np.checks.deviceIn(p, name).?;
    return p.dev_pin0[d] + index;
}

fn expectBus(src: []const u8, compact: bool, continuous: bool) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{src}, null);
    defer p.deinit();
    const main = terminal(&p, "m1", 2);
    const lower = terminal(&p, "m2", 2);
    const auxiliary = terminal(&p, "m5", 2);
    try testing.expectEqual(p.pin_net[main], p.pin_net[lower]);
    try testing.expectEqual(p.pin_net[main], p.pin_net[auxiliary]);
    try testing.expectEqual(continuous, try ink.connected(testing.allocator, &p, &.{ main, lower, auxiliary }));
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
}

test "converter bus: the nearby auxiliary switch stays physically connected" {
    // Verified source ink joins these three source terminals. Both compact
    // variants joined in frozen12, then split when13 consumed the anchor.
    try expectBus(ag1316, true, true);
    try expectBus(ag1316 ++ "*@ port vin left\n", true, true);
}

test "converter bus: the uncompact auxiliary switch reaches the nearby tree" {
    // Source 144/145 buses join the auxiliary; this native gap predated13.
    // Frozen12 and13-near put M1.S=(180,40), M2.S=(180,320), and
    // M5.S=(80,440): the retained-pin box spans500 versus the240 limit.
    // The actual lower tree is only200 units away. Its named known-gap
    // assertion failed with an unexpected improvement after tree proximity;
    // both variants now carry the unchanged source continuity oracle.
    try expectBus(ag1316, false, true);
    try expectBus(ag1316 ++ "*@ port vin left\n", false, true);
}

test "converter bus: AG1249 joins a switch near the lower part of the tree" {
    try expectBus(ag1249, true, true);
}

test "converter bus: AG1263 joins a switch near the lower part of the tree" {
    try expectBus(ag1263, true, true);
}

test "converter bus: AG1294 joins the existing tree beyond its retained anchor" {
    try expectBus(ag1294, true, true);
}
