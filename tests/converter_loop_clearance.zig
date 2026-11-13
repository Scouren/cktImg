//! Full converter DUTs -> local loop ink clear of remote devices and rails.
//! Cites: AG1222/1349 source SVGs, the seven continuous local trees in
//! docs/research/converter-loops.md, and the iteration12 collision cases.
//! Human Rules:
//! - Reserve enough room for the complete loop's local wires, including
//!   a control device's physical body and its rail connections.
//! - The source varies the side occupied by control circuitry; require
//!   continuous local ink and electrical correctness, not a fixed side.
//!
//! Contents: literal source DUTs, exact terminal checks, then regressions.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

// The complete source subcircuits are retained. Only the DUT wrapper is
// removed, as the CLI does; its inferred external roles follow the DUT.
const ag1222 =
    \\AG-1222 loop clearance fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VS VCONT1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M10 net1 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 VCTRL VB3 net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 VX VB3 net5 VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 VCTRL VBC net6 VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 VX VBC net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 net6 VX VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 net3 VX VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 VBP VBP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M18 VX VBP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M19 VBC VBP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VX1 VCONT2 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 VBP VX net7 VSS nch l=0.15 w=1 nf=1 m=1
    \\M21 VX net7 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M22 VBC VBC net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M23 net4 VBC VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M24 net3 VCTRL VS VDD pch l=0.15 w=1 nf=1 m=1
    \\M25 net3 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M26 net3 VB5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M27 net2 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M28 net2 net2 VS VDD pch l=0.15 w=1 nf=1 m=1
    \\M29 VX1 net2 VS VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 VX2 VCONT3 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VCONT4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 VX3 VCONT5 VP VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 net0 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 net5 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 net0 VREF net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 net5 VFP1 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\RBIAS net7 VSS 1k
    \\*@ weak role vp output
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\*@ weak role vcont4 input
    \\*@ weak role vcont5 input
    \\
;

const ag1349 =
    \\AG-1349 loop clearance fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt EA VDD VSS INN INP OUT
    \\MN1 net3 INN net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN2 OUT INP net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN3 net2 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN4 net5 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN5 net0 net4 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN6 net4 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP1 net3 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP2 OUT net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP3 net2 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP4 net0 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP5 net4 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\RBIAS net1 VSS 1k
    \\.ends EA
    \\.subckt ISR VDD VSS TOP OUT CTRL VB3
    \\MN7 net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN8 net0 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN9 net1 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP6 net0 net0 TOP VDD pch l=0.15 w=1 nf=1 m=1
    \\MP7 OUT net0 TOP VDD pch l=0.15 w=1 nf=1 m=1
    \\MP8 net1 CTRL TOP VDD pch l=0.15 w=1 nf=1 m=1
    \\.ends ISR
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
    \\M5 net0 VCONT1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\X1 VDD VSS net0 VX1 net1 VB3 ISR
    \\X2 VDD VSS VFP1 VREF net1 EA
    \\*@ weak role vp output
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\*@ weak role vcont4 input
    \\*@ weak role vcont5 input
    \\
;

// ---- private ----

fn terminal(p: *const np.Placed, name: []const u8, index: u32) usize {
    const d = np.checks.deviceIn(p, name).?;
    return p.dev_pin0[d] + index;
}

fn expectLocal(p: *const np.Placed, case: []const u8, compact: bool, main_in: []const u8, main_out: []const u8, lower: []const u8) !void {
    // Literal source pin roles, independent of the production selector.
    // Both source main-output PMOS devices put VP on source terminal 2.
    const rows = [_][]const usize{
        &.{ terminal(p, main_in, 2), terminal(p, lower, 2) },
        &.{ terminal(p, main_in, 0), terminal(p, "l1", 0), terminal(p, "cfly", 0) },
        &.{ terminal(p, "l1", 1), terminal(p, main_out, 0) },
        &.{ terminal(p, main_out, 2), terminal(p, "co", 0), terminal(p, "cop", 0), terminal(p, "r1", 0) },
        &.{ terminal(p, lower, 0), terminal(p, "cfly", 1), terminal(p, "d1", 1) },
        &.{ terminal(p, "co", 1), terminal(p, "d1", 0) },
        &.{ terminal(p, "r1", 1), terminal(p, "r2", 0) },
    };
    const names = [_][]const u8{ "VIN", "VX1", "VX3", "VP", "VX2", "VN", "VFP1" };
    for (rows, names) |pins, name| {
        const connected = try ink.connected(testing.allocator, p, pins);
        if (!connected) std.debug.print("{s} compact={} local net {s} is disconnected\n", .{ case, compact, name });
        try testing.expect(connected);
    }
}

test "converter loop clearance: control rail stubs leave the lower return usable" {
    // AG1222's proposed return at y=460 touched M6's VDD stub at
    // (220,460), as well as the control rail. Atomic rollback left the
    // two selected VIN terminals connected only by separate input ports.
    // The source's seven local ink trees remain the independent oracle.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1222}, null);
        defer p.deinit();
        try expectLocal(&p, "AG1222", compact, "m2", "m5", "m3");
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}

test "converter loop clearance: a wide remote block leaves the input bus usable" {
    // AG1349's generated ISR frame extended beyond its cell onto VIN's
    // proposed x=170 bus. X1.VDD at (170,150) and its rail also blocked
    // the capacitor drops. Names on VIN cannot replace its local wire.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1349}, null);
        defer p.deinit();
        try expectLocal(&p, "AG1349", compact, "m1", "m3", "m2");
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}
