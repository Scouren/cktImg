//! Complete source gate lines -> straight native wire intervals.
//! Oracle: actual Analog-Genie SVG leads and conductor ink, recorded in
//! figures/trunk_rungs_cases.json. AG981/984/986 each have a continuous
//! horizontal gate pair. A foreign wire at the native midpoint must not
//! force a detour when a nearby branch point leaves that gate line clear.
//!
//! Contents: tests only. Imported by tests/api.zig.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

// Complete source definitions and DUT cards, with only the DUT wrapper
// removed. Preserve the CLI's weak boundary roles: AG981 VNBias2 is an
// output, while AG984 net8 and AG986 VC3 remain internal nets.

const ag981 =
    \\ag-981 straight source gate line
    \\.model nch nmos
    \\.model pch pmos
    \\.model qpnp pnp
    \\
    \\.subckt icm_opamp_vdd_vss VDD VSS VIP VIN VOUT params: gain=1e6
    \\Blin nlin 0 V={gain*(V(VIP)-V(VIN))}
    \\Bcore VOUT 0 V={0.5*(V(VDD)+(0.5*(V(VSS)+V(nlin)+sqrt((V(nlin)-V(VSS))*(V(nlin)-V(VSS))+(1e-4*(V(VDD)-V(VSS)))*(1e-4*(V(VDD)-V(VSS)))+1e-12)))-sqrt((V(VDD)-(0.5*(V(VSS)+V(nlin)+sqrt((V(nlin)-V(VSS))*(V(nlin)-V(VSS))+(1e-4*(V(VDD)-V(VSS)))*(1e-4*(V(VDD)-V(VSS)))+1e-12))))*(V(VDD)-(0.5*(V(VSS)+V(nlin)+sqrt((V(nlin)-V(VSS))*(V(nlin)-V(VSS))+(1e-4*(V(VDD)-V(VSS)))*(1e-4*(V(VDD)-V(VSS)))+1e-12))))+(1e-4*(V(VDD)-V(VSS)))*(1e-4*(V(VDD)-V(VSS)))+1e-12))}
    \\.ends icm_opamp_vdd_vss
    \\
    \\M1 net18 net4 net17 VSS nch l=0.15 w=1 nf=1 m=1
    \\M10 VBG net11 net13 VDD pch l=0.15 w=1 nf=1 m=1
    \\M11 net15 VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 net10 VB3 net15 VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 net5 VX VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 VNBias2 VB3 net5 VDD pch l=0.15 w=1 nf=1 m=1
    \\M1A VNBias1 VNBias2 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net14 net4 net7 VSS nch l=0.15 w=1 nf=1 m=1
    \\M2A net2 VNBias1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net4 net8 net18 VSS nch l=0.15 w=1 nf=1 m=1
    \\M3A VPBias2 VNBias2 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net11 net8 net14 VSS nch l=0.15 w=1 nf=1 m=1
    \\M4A net0 VNBias1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net8 net11 net12 VDD pch l=0.15 w=1 nf=1 m=1
    \\M5A VPBias1 VPBias2 net9 VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 net6 net11 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M6A net9 VPBias1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 net12 net6 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 net3 net6 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 net13 net6 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\Q1 VSS VSS net17 qpnp m=1
    \\Q2 VSS VSS net16 qpnp m=1
    \\Q3 VSS VSS net1 qpnp m=1
    \\R1 net7 net16 1k
    \\R1A VNBias2 VNBias1 1k
    \\R2 VBG net1 1k
    \\R2A VPBias1 VPBias2 1k
    \\R3 net8 net4 1k
    \\R4 net6 net11 1k
    \\Rext net10 VSS 1k
    \\X1 VDD VSS net10 VBG VX icm_opamp_vdd_vss gain=1e6
    \\*@ weak role vx output
    \\*@ weak role vpbias1 output
    \\*@ weak role vpbias2 output
    \\*@ weak role vnbias2 output
    \\*@ weak role vnbias1 output
    \\
;

const ag984 =
    \\ag-984 straight source gate line
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\M1 net2 Vinp net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M10 net3 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net5 net2 net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net1 net4 net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M13 net5 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 net1 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M15 net8 net6 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M16 net8 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net4 Vinn net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net0 net5 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 vOUT net1 net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net0 net8 net7 VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 vOUT net8 net6 VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 net7 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M8 net6 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 net3 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\*@ weak role vnb1 input
    \\*@ weak role vpb1 input
    \\
;

const ag986 =
    \\ag-986 straight source gate line
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\M1 VS2 vINn net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\M10 net10 net6 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M11 VS3 net6 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M12 net1 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 VC1 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M14 net9 VS1 net1 VDD pch l=0.15 w=1 nf=1 m=1
    \\M15 VSS net7 net1 VDD pch l=0.15 w=1 nf=1 m=1
    \\M16 VC1 VNB2 net9 VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 net9 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 VDD VNB2 net7 VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 net7 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 VS1 vINp net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 net8 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M21 VC2 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M22 net4 VS2 net8 VDD pch l=0.15 w=1 nf=1 m=1
    \\M23 VSS net5 net8 VDD pch l=0.15 w=1 nf=1 m=1
    \\M24 VC2 VNB2 net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M25 net4 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M26 VDD VNB2 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M27 net5 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M28 net3 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M29 VC3 VPB2 net3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 net0 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M30 VC3 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M31 net3 VS3 net11 VSS nch l=0.15 w=1 nf=1 m=1
    \\M32 VDD net2 net11 VSS nch l=0.15 w=1 nf=1 m=1
    \\M33 net11 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M34 net2 VPB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M35 VSS VPB2 net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VS1 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 VS2 VNB1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 net6 VC1 VS1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 vOUT VC2 VS2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 net6 VC3 net10 VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 vOUT VC3 VS3 VDD pch l=0.15 w=1 nf=1 m=1
    \\*@ weak role vpb1 input
    \\*@ weak role vpb2 input
    \\*@ weak role vnb1 input
    \\*@ weak role vnb2 input
    \\
;

// ---- private ----

fn gate(p: *const np.Placed, name: []const u8) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + 1;
}

fn expectLine(deck: []const u8, first: []const u8, second: []const u8) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("source gate line {s}/{s}, compact={}\n", .{ first, second, compact });
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        const a, const b = .{ gate(&p, first), gate(&p, second) };
        try testing.expectEqual(p.pin_net[a], p.pin_net[b]);
        try testing.expectEqual(p.pin_xy[a].y, p.pin_xy[b].y);
        try testing.expect(p.pin_xy[a].x != p.pin_xy[b].x);
        const left = @min(p.pin_xy[a].x, p.pin_xy[b].x);
        const right = @max(p.pin_xy[a].x, p.pin_xy[b].x);
        // Every integer point in the literal gate interval needs horizontal
        // ink of this net. A U detour, label, or another net cannot fill it.
        try testing.expect(@as(i64, right) - left < 10000);
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
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}

test "trunk taps: AG981 retains its straight VNBias2 gate line" {
    // Source leads M1A.G=(490,380), M3A.G=(530,380).
    try expectLine(ag981, "m1a", "m3a");
}

test "trunk taps: AG984 retains its straight net8 gate line" {
    // Source leads M5.G=(-100,60), M6.G=(100,60).
    try expectLine(ag984, "m5", "m6");
}

test "trunk taps: AG986 retains its straight VC3 gate line" {
    // Source leads M8.G=(510,100), M9.G=(590,100).
    try expectLine(ag986, "m8", "m9");
}

test "bias feed: AG725 VB3 port joins both gates clear of the control crossing" {
    const deck =
        \\AG725 bias feed
        \\*@ weak role Iin1 output
        \\*@ weak role Iin2 output
        \\.model nch nmos
        \\.model pch pmos
        \\CL1 Voutp VSS 1p
        \\CL2 Voutn VSS 1p
        \\I1 VDD Iin2 DC 1m
        \\I2 VDD Iin1 DC 1m
        \\M10 Voutn VB3 net1 VSS nch l=0.15 w=1 nf=1 m=1
        \\M5 Voutp VB2 Iin2 VDD pch l=0.15 w=1 nf=1 m=1
        \\M6 Voutn VB2 Iin1 VDD pch l=0.15 w=1 nf=1 m=1
        \\M7 net0 Vcntrl VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M8 Voutp VB3 net0 VSS nch l=0.15 w=1 nf=1 m=1
        \\M9 net1 Vcntrl VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\RL1 Voutp Vcntrl 1k
        \\RL2 Vcntrl Voutn 1k
    ;
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.{}, lib, &.{deck}, null);
    defer p.deinit();

    const a = gate(&p, "m8");
    const b = gate(&p, "m10");
    const net = p.pin_net[a];
    try testing.expectEqualStrings("vb3", p.net_name[net]);
    try testing.expectEqual(net, p.pin_net[b]);
    var port: ?usize = null;
    for (0..p.deviceCount()) |d| {
        const start, const end = p.pinRange(d);
        if (p.dev_name[d].len != 0 or end - start != 1 or p.pin_net[start] != net) continue;
        try testing.expect(port == null);
        port = start;
    }
    // Fig. P6.57 gives this pair one visible bias feed on the gate line.
    try testing.expect(port != null);
    const tip = p.pin_xy[port.?];
    const left = @min(p.pin_xy[a].x, p.pin_xy[b].x);
    const right = @max(p.pin_xy[a].x, p.pin_xy[b].x);
    try testing.expect(tip.x > left and tip.x < right);
    try testing.expectEqual(p.pin_xy[a].y, p.pin_xy[b].y);
    try testing.expect(tip.y != p.pin_xy[a].y);
    try testing.expect(try ink.connected(testing.allocator, &p, &.{ a, b, port.? }));
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    try testing.expectEqual(0, try support.dots(testing.allocator, &p, true));
}

test "bias feed leaves adjacent AG1652 stage wiring and its existing bias ports intact" {
    // Before additional bias access was enabled, all four net0 pins shared
    // one conductor and seven drawn VB3 ports identified separate contacts.
    const deck =
        \\AG1652 bias ports
        \\.model nch nmos
        \\.model pch pmos
        \\.model qpnp pnp
        \\M1 net9 VB2 VDD VDD pch l=0.15 w=1 nf=1 m=1
        \\M10 Vout VB3 VQ VSS nch l=0.15 w=1 nf=1 m=1
        \\M11 VQ net7 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M12 net2 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
        \\M13 net0 VB1 net2 VDD pch l=0.15 w=1 nf=1 m=1
        \\M14 net0 VB3 net5 VSS nch l=0.15 w=1 nf=1 m=1
        \\M15 net5 VN1 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M16 net4 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
        \\M17 VB3 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
        \\M18 VB3 VB3 net6 VSS nch l=0.15 w=1 nf=1 m=1
        \\M19 net6 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M2 VN1 X net9 VDD pch l=0.15 w=1 nf=1 m=1
        \\M3 net7 Y net9 VDD pch l=0.15 w=1 nf=1 m=1
        \\M4 VN1 VB3 Y VSS nch l=0.15 w=1 nf=1 m=1
        \\M5 net7 VB3 net1 VSS nch l=0.15 w=1 nf=1 m=1
        \\M6 Y VN1 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M7 net1 net7 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M8 net8 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
        \\M9 Vout VB1 net8 VDD pch l=0.15 w=1 nf=1 m=1
        \\Q1 VSS VSS VQ qpnp m=1
        \\Q2 VQ VQ X qpnp m=1
        \\Q3 VSS VSS net10 qpnp m=1
        \\Q4 net10 net10 net3 qpnp m=1
        \\R1 Vout X 1k
        \\R2 Vout Y 1k
        \\R3 Y net3 1k
        \\R4 net4 VSS 1k
    ;
    const alloc = std.testing.allocator;
    const lib = try support.library(alloc);
    defer support.freeLibrary(alloc, lib);
    var p = try np.place(alloc, &.default, lib, &.{deck}, null);
    defer p.deinit();
    const refs = [_][]const u8{ "m12", "m13", "m14", "m8" };
    var pins: [4]usize = undefined;
    for (refs, [_]u32{ 1, 0, 0, 1 }, 0..) |name, term, i| {
        pins[i] = p.dev_pin0[np.checks.deviceIn(&p, name).?] + term;
    }
    try std.testing.expect(try ink.connected(alloc, &p, &pins));
    var ports: usize = 0;
    for (0..p.deviceCount()) |d| {
        const first, const end = p.pinRange(d);
        if (p.dev_name[d].len == 0 and end == first + 1 and std.mem.eql(u8, p.net_name[p.pin_net[first]], "vb3")) ports += 1;
    }
    try std.testing.expectEqual(7, ports);
}
