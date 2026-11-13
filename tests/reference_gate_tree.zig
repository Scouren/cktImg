//! Source amplifier output -> retained physical wire tree.
//! Oracle: actual AG2436 SVG output and gate leads and conductor ink.
//! This complete-DUT regression failed before the driven-bank rule and
//! passes without coordinate or facing hints in both layout modes.
//!
//! Contents: complete source fixture, private physical oracle, then test.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag2436 =
    \\ag-2436 source physical connection
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\.subckt bias VDD VSS VB1 NB
    \\M13 net0 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 net2 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 net0 net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M16 net1 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M17 net1 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 NB net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M19 NB NB VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M20 VB1 NB VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M21 VB1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VDD net0 1k
    \\R2 VDD net2 1k
    \\.ends bias
    \\
    \\.subckt error_amp VDD VSS VREF NB OUT
    \\M10 net2 VREF net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net1 OUT net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net0 NB VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net2 net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 OUT net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 OUT net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 net1 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 OUT OUT VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 OUT OUT VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\.ends error_amp
    \\
    \\M1 net3 net4 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 net1 net1 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 net1 nb VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MBIAS VERR nb VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MCHG net2 pb VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MCTRL VERR net1 VOUT VDD pch l=0.15 w=1 nf=1 m=1
    \\MGEN net5 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MINJ VERR net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MRES VOUT VERR VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MSEN net5 net4 net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\X1 VDD VSS VREF net0 net4 error_amp
    \\X2 VDD VSS VB1 net0 bias
    \\*@ weak role verr output
;

const Terminal = struct { name: []const u8, index: u32 };

// ---- private ----

fn expectSourceConnection(deck: []const u8, terminals: []const Terminal) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("reference source connection {s}, compact={}\n", .{ terminals[0].name, compact });
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
        var pins: [3]usize = undefined;
        try testing.expectEqual(pins.len, terminals.len);
        for (terminals, &pins) |terminal, *pin| {
            const device = np.checks.deviceIn(&p, terminal.name).?;
            pin.* = p.dev_pin0[device] + terminal.index;
        }
        // One physical component must reach all three exact source pins.
        // This also proves all three pairwise connections without labels.
        try testing.expect(try ink.connected(testing.allocator, &p, &pins));
    }
}

test "reference continuity: AG2436 keeps the source amplifier output gate tree" {
    // Actual source X1.OUT(240,100), M1.G(270,40), MSEN.G(390,100) join
    // through (260,40)..(260,100). The native wire may take any legal path.
    try expectSourceConnection(ag2436, &.{ .{ .name = "m1", .index = 1 }, .{ .name = "msen", .index = 1 }, .{ .name = "x1", .index = 4 } });
}
