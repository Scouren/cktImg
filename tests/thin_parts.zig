//! Source regressions for a cut net's physical-part budget.
//! Oracle: actual Analog-Genie SVG leads and conductor ink retained in
//! thin-parts.md. Each compacted M11.G–M12.G interval is straight in its
//! source; the previous whole-net cut budget erased the local wire.
//! Noncompacted layouts retain a separately recorded partition gap; these
//! tests require electrical identity there without blessing that gap.
//!
//! Contents: literal source decks, gate-line oracle, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

// Complete source models and DUT cards with only the wrapper removed.
// The CLI adds one weak role in each deck: IBUF is driven by M18.S.
// Other boundary names already determine their input, output or rail role.

const ag2309 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\CL VOUT net4 1p
    \\M10 EAO VB2 VY VDD pch l=0.15 w=1 nf=1 m=1
    \\M11 net6 VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 VY VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 net5 VB3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 VX EAO net5 VDD pch l=0.15 w=1 nf=1 m=1
    \\M15 VX VX VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 GATE VX VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 VDD net5 GATE VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 VY EAO IBUF VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 VY VY VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 net2 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 GATE VY VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M21 VSS IBUF GATE VDD pch l=0.15 w=1 nf=1 m=1
    \\M22 net0 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M23 VB4 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M24 VB4 VB4 VB5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M25 VB5 VB5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net1 VREF net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 net3 FB net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 net1 VB5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 net3 VB5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 VX VB4 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 EAO VB4 net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 VX VB2 net6 VDD pch l=0.15 w=1 nf=1 m=1
    \\MNP VIN GATE VOUT VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 FB VSS 1k
    \\R2 VOUT FB 1k
    \\R3 net0 VSS 1k
    \\R4 net4 VSS 1k
    \\RL VOUT VSS 1k
    \\*@ weak role ibuf output
    \\
;

const ag2318 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\CL VOUT net8 1p
    \\M10 EAO VB3 net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\M11 net5 VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 net0 VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 net4 VB4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 VX EAO net4 VDD pch l=0.15 w=1 nf=1 m=1
    \\M15 VX VX VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 GATE VX VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 VDD net4 GATE VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 net0 EAO IBUF VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 net0 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 net3 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 GATE net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M21 VSS IBUF GATE VDD pch l=0.15 w=1 nf=1 m=1
    \\M22 net2 net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M23 VB5 net2 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M24 VB5 VB5 net6 VSS nch l=0.15 w=1 nf=1 m=1
    \\M25 net6 VB5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net7 VREF net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 net1 FB net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 net7 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 net1 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 VX VB5 net7 VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 EAO VB5 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 VX VB3 net5 VDD pch l=0.15 w=1 nf=1 m=1
    \\MNP VIN GATE VOUT VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 FB VSS 1k
    \\R2 VOUT FB 1k
    \\R3 net2 VSS 1k
    \\R4 net8 VSS 1k
    \\RL VOUT VSS 1k
    \\*@ weak role ibuf output
    \\
;

const ag2319 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\CL VOUT net4 1p
    \\M10 EAO VB3 VY VDD pch l=0.15 w=1 nf=1 m=1
    \\M11 net6 VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 VY VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 net1 VB4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 VX EAO net1 VDD pch l=0.15 w=1 nf=1 m=1
    \\M15 VX VX VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 GATE VX VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 VDD net1 GATE VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 VY EAO IBUF VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 VY VY VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 net3 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 GATE VY VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M21 VSS IBUF GATE VDD pch l=0.15 w=1 nf=1 m=1
    \\M22 net0 net0 net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M23 VB5 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M24 VB5 VB5 net7 VSS nch l=0.15 w=1 nf=1 m=1
    \\M25 net7 VB5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net5 VREF net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VZ FB net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 net5 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 VZ VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 VX VB5 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 EAO VB5 VZ VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 VX VB3 net6 VDD pch l=0.15 w=1 nf=1 m=1
    \\MNP VIN GATE VOUT VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 FB VSS 1k
    \\R2 VOUT FB 1k
    \\R3 VDD net2 1k
    \\R4 net0 VSS 1k
    \\R5 net4 VSS 1k
    \\RL VOUT VSS 1k
    \\*@ weak role ibuf output
    \\
;

// ---- private ----

fn expectGateLine(deck: []const u8, name: []const u8) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("source {s} M11.G/M12.G, compact={}\n", .{ name, compact });
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
        if (!compact) continue;
        const a = p.dev_pin0[np.checks.deviceIn(&p, "m11").?] + 1;
        const b = p.dev_pin0[np.checks.deviceIn(&p, "m12").?] + 1;
        try testing.expectEqual(p.pin_net[a], p.pin_net[b]);
        try testing.expectEqual(p.pin_xy[a].y, p.pin_xy[b].y);
        const left = @min(p.pin_xy[a].x, p.pin_xy[b].x);
        const right = @max(p.pin_xy[a].x, p.pin_xy[b].x);
        try testing.expect(left < right and @as(i64, right) - left < 10000);
        // A label, other-net segment or U detour cannot fill this interval.
        var x = left;
        while (x <= right) : (x += 1) {
            var covered = false;
            var wires = p.segments(p.pin_net[a]);
            while (wires.next()) |poly| {
                for (poly[0 .. poly.len - 1], poly[1..]) |u, v| {
                    if (u.y == p.pin_xy[a].y and v.y == u.y and @min(u.x, v.x) <= x and x <= @max(u.x, v.x)) covered = true;
                }
            }
            try testing.expect(covered);
        }
        try testing.expect(try ink.connected(testing.allocator, &p, &.{ a, b }));
    }
}

test "thin parts: AG2309 keeps its compacted VX gate line" {
    // Source leads M11.G=(280,20), M12.G=(320,20).
    try expectGateLine(ag2309, "ag-2309");
}

test "thin parts: AG2318 keeps its compacted VX gate line" {
    // Source leads M11.G=(260,40), M12.G=(300,40).
    try expectGateLine(ag2318, "ag-2318");
}

test "thin parts: AG2319 keeps its compacted VX gate line" {
    // Source leads M11.G=(250,40), M12.G=(290,40).
    try expectGateLine(ag2319, "ag-2319");
}
