//! Source branch columns -> a default output order with caller precedence.
//! Cites: AG1191 SVG lead columns R1=460, CO=530, COP=590, and the
//! 114/145 preference in docs/research/converter-branches.md.
//! Human Rules:
//! - After a converter's main path, the common output-branch order is
//!   divider, floating cap, grounded cap. The 31 exceptions remain named;
//!   this test fixes the default on one observed source, not every circuit.
//! - Caller order and cell requests can choose another branch order.
//!   Actual local wires and electrical connectivity must survive the default.
//!
//! Contents: literal source DUT, terminal/continuity checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

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

fn terminal(p: *const np.Placed, name: []const u8, index: u32) usize {
    const d = np.checks.deviceIn(p, name).?;
    return p.dev_pin0[d] + index;
}

fn point(p: *const np.Placed, name: []const u8, index: u32) np.Pt {
    return p.pin_xy[terminal(p, name, index)];
}

fn expectLocalInk(p: *const np.Placed) !void {
    // Literal source nets and SPICE terminal indices. MOS body pins never
    // stand in for the selected source/drain, even on the same net.
    const Pin = struct { []const u8, u32 };
    const nets = [_][]const Pin{
        &.{ .{ "m1", 2 }, .{ "m2", 2 } },
        &.{ .{ "m1", 0 }, .{ "l1", 0 }, .{ "cfly", 0 } },
        &.{ .{ "l1", 1 }, .{ "m3", 0 } },
        &.{ .{ "m3", 2 }, .{ "co", 0 }, .{ "cop", 0 }, .{ "r1", 0 } },
        &.{ .{ "m2", 0 }, .{ "cfly", 1 }, .{ "d1", 1 } },
        &.{ .{ "co", 1 }, .{ "d1", 0 } },
        &.{ .{ "r1", 1 }, .{ "r2", 0 } },
    };
    for (nets) |net| {
        var pins: [4]usize = undefined;
        for (net, 0..) |pin, i| pins[i] = terminal(p, pin[0], pin[1]);
        try testing.expect(try ink.connected(testing.allocator, p, pins[0..net.len]));
    }
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
    for (try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib)) |verdict| {
        try testing.expectEqual(np.hints.State.honoured, verdict.state);
    }
}

test "converter branches: the default source order survives wrapping and compaction" {
    // Source R1 (460,370)-(460,410), R2 (460,430)-(460,470),
    // CO (530,420)-(530,460), COP (590,380)-(590,420).
    // Frozen wrap 12 has CO=420, COP=490, R1=550 instead.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1191}, null);
        defer p.deinit();
        const r1a, const r1b = .{ point(&p, "r1", 0), point(&p, "r1", 1) };
        const r2a, const r2b = .{ point(&p, "r2", 0), point(&p, "r2", 1) };
        const co, const cg = .{ point(&p, "co", 0), point(&p, "cop", 0) };
        try testing.expect(point(&p, "m3", 2).x < r1a.x);
        try testing.expect(r1a.x < co.x and co.x < cg.x);
        try testing.expect(r1a.x == r1b.x and r1b.x == r2a.x and r2a.x == r2b.x);
        try testing.expect(r1a.y < r1b.y and r1b.y <= r2a.y and r2a.y < r2b.y);
        try expectLocalInk(&p);
        try expectElectrical(&p, lib);
    }
}

test "converter branches: explicit order and cells can reverse the default" {
    // Pin every compared cell: one pinned branch alone does not fix its
    // relation to the inferred group. Opposing caller requests need not
    // retain the default group or its inferred physical wire template.
    const sources = [_][]const u8{
        ag1191 ++ "*@ order cop co r1\n",
        ag1191 ++ "*@ cell cop -8 -6\n*@ cell co -4 -6\n*@ cell r1 0 -6\n",
    };
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for (sources) |src| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{src}, null);
        defer p.deinit();
        try testing.expect(point(&p, "cop", 0).x < point(&p, "co", 0).x);
        try testing.expect(point(&p, "co", 0).x < point(&p, "r1", 0).x);
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    };
}
