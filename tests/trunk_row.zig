//! AG2365's source-connected VEAOUT gates survive a foreign wire crossing.
//! Oracle: actual SVG M1.G=(280,80), MSEN.G=(470,150) join through
//! (260,80) and (260,150). Native16 connects both compaction modes;
//! native17 loses only compact=true when a retained VCTRL wire passes
//! through an artificial intermediate point on the straight gate interval.
//! Require physical continuity, electrical identity and no shorts. The
//! source is bent, so no universal source row or straightness is claimed.
//!
//! Contents: full source deck, then test.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

// Only the DUT wrapper is removed. All boundary roles follow their names;
// the CLI adds no weak port-role or driver requests to this source deck.
const ag2365 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\M1 net5 VEAOUT VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M10 net0 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net4 VCTRL VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 VY VB1 net4 VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 VY VZ net7 VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 net7 VY VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 net8 VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M16 VEAOUT VB1 net8 VDD pch l=0.15 w=1 nf=1 m=1
    \\M17 VEAOUT VZ net6 VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 net6 VY VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 VZ VW VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VCTRL VCTRL net5 VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 VZ VZ VEAOUT VSS nch l=0.15 w=1 nf=1 m=1
    \\M21 VEAOUT VZ VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M22 VW VW VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M23 VW VCTRL VB3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M24 VCTRL VW VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M25 VCTRL VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 VCTRL nb VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net9 VCTRL VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 VCTRL VB1 net9 VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 VCTRL VEAOUT net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 net3 VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 VX VB1 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 VX VREF net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\MBIAS VERR nb VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MCHG net2 pb VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MCTRL VERR VCTRL VOUT VDD pch l=0.15 w=1 nf=1 m=1
    \\MGEN net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MINJ VERR net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MRES VOUT VERR VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MSEN net1 VEAOUT net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VB3 VSS 1k
    \\
;

test "trunk row: AG2365 retains physical VEAOUT gate continuity across VCTRL" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("AG2365 M1.G/MSEN.G compact={}\n", .{compact});
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag2365}, null);
        defer p.deinit();
        const a = p.dev_pin0[np.checks.deviceIn(&p, "m1").?] + 1;
        const b = p.dev_pin0[np.checks.deviceIn(&p, "msen").?] + 1;
        try support.expectConnected(&p, lib);
        try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
        try std.testing.expectEqual(p.pin_net[a], p.pin_net[b]);
        try std.testing.expect(try ink.connected(gpa, &p, &.{ a, b }));
    }
}
