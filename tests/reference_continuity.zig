//! Source reference-amplifier circuits -> retained physical wire connections.
//! Oracle: actual Analog-Genie SVG terminal leads and conductor ink, independently
//! certified in the iteration18 source pin-pair audit. Names and ports do not
//! connect physically separated pieces. Complete declarations and DUT cards are
//! retained; only the DUT wrapper is removed, with the CLI's weak port roles.
//!
//! Contents: tests only. Prospective, not imported until its routing case is owned.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag2415 =
    \\ag-2415 source physical connection
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\.subckt AEA VDD VSS VREF OUT
    \\M1 net2 net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M10 net1 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M11 net4 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 net0 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 net4 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 net0 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 OUT net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 OUT net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 net3 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 net2 VREF net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 OUT OUT VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 OUT OUT VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 net3 OUT net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 net5 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\.ends AEA
    \\
    \\M1 net3 net4 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 net0 net0 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 net0 nb VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MBIAS VERR nb VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MCHG net1 pb VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MCTRL VERR net0 VOUT VDD pch l=0.15 w=1 nf=1 m=1
    \\MGEN net2 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MINJ VERR net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MRES VOUT VERR VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MSEN net2 net4 net1 VDD pch l=0.15 w=1 nf=1 m=1
    \\X1 VDD VSS VREF net4 AEA
    \\*@ weak role verr output
;

const ag2428 =
    \\ag-2428 source physical connection
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\.subckt AEA VDD VSS VREF OUT VB1
    \\M11 net0 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 OUT net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 OUT net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 net3 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M15 OUT OUT VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 OUT OUT VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 net0 VREF net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 net3 OUT net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 net1 VBN VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M20 VBN VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M21 VB1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M22 VBN VBN VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M23 VB1 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M24 net2 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 VDD net2 1k
    \\.ends AEA
    \\
    \\M1 net2 VEAOUT VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M10 VERR nb VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net1 net1 net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 net1 nb VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net0 pb VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 net3 VEAOUT net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 net3 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 VERR net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 VOUT VERR VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 VERR net1 VOUT VDD pch l=0.15 w=1 nf=1 m=1
    \\X1 VDD VSS VREF VEAOUT VB1 AEA
    \\*@ weak role verr output
    \\*@ weak role pb input
    \\*@ weak role nb input
;

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
        if (compact) {
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
}

test "reference continuity: AG2415 keeps the source VIN branch wire" {
    // Actual source S terminals: M1(110,20), MCHG(230,20), MRES(390,20).
    // They join on the horizontal VIN conductor at y=0.
    try expectSourceConnection(ag2415, &.{ .{ .name = "m1", .index = 2 }, .{ .name = "mchg", .index = 2 }, .{ .name = "mres", .index = 2 } });
}

test "reference continuity: AG2428 keeps the source VIN branch wire" {
    // Source S terminals M1, M4 and M8 share the actual continuous VIN bus.
    try expectSourceConnection(ag2428, &.{ .{ .name = "m1", .index = 2 }, .{ .name = "m4", .index = 2 }, .{ .name = "m8", .index = 2 } });
}

test "reference continuity: AG2436 keeps the source amplifier output gate tree" {
    // Actual source X1.OUT(240,100), M1.G(270,40), MSEN.G(390,100) join
    // through (260,40)..(260,100). The native wire may take any legal path.
    try expectSourceConnection(ag2436, &.{ .{ .name = "m1", .index = 1 }, .{ .name = "msen", .index = 1 }, .{ .name = "x1", .index = 4 } });
}
