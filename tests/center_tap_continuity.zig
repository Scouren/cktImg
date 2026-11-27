//! Center-tap expansion -> preserved source transistor-bank connection.
//! Oracle: AG1114 actual B leads Q3(350,0), Q4(250,0), joined by source
//! conductor ink through the actual junction at(280,0). The complete source
//! declarations and DUT cards are retained; only its wrapper is removed and
//! the CLI's weak VCONT output role is appended. Named labels never join ink.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1114 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model pch pmos
    \\.model qnpn npn
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.model DIODE D(IS=1e-14 N=1)
    \\C1 net10 net9 1p
    \\C2 net10 VSS 1p
    \\Ccp1 net7 net1 1p
    \\Ccp2 net3 net0 1p
    \\Cvar1 Vcont net1 1p
    \\Cvar2 Vcont net0 1p
    \\D1 Vcc net4 DIODE
    \\D2 net10 net11 DIODE
    \\M1 net10 Vbias P Vcc pch l=0.15 w=1 nf=1 m=1
    \\Q1 net1 net3 net6 VSS qnpn m=1
    \\Q2 net0 net7 net6 VSS qnpn m=1
    \\Q3 P net5 net0 VSS qnpn m=1
    \\Q4 P net5 net1 VSS qnpn m=1
    \\Q5 net6 net9 net2 VSS qnpn m=1
    \\Q6 net11 net9 net8 VSS qnpn m=1
    \\Q7 Vcc net10 net9 VSS qnpn m=1
    \\R1 net3 Vref 1k
    \\R2 net7 Vref 1k
    \\R3 net8 VSS 1k
    \\R4 net2 VSS 1k
    \\Rb1 Vcc net5 1k
    \\Rb2 net5 net4 1k
    \\Rbias Vcc P 1k
    \\X1 net0 net1 net4 ct_inductor l1=1n l2=1n k=0
    \\*@ weak role vcont output
;

// Source AG1146 M3.G=(-70,-130), M4.G=(-30,-130) share the complete
// straight interval. All cards and the CLI's weak port roles are literal.
const ag1146 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.subckt Varactor_Switched_caps Von Vop B_3_ B_2_ B_1_ B_0_ Vcn Vcp
    \\.ends Varactor_Switched_caps
    \\
    \\Iref VDD net3 DC 1m
    \\M1 net3 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net1 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net1 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 net2 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 Von Vop net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 Vop Von net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 Von Vop VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 Vop Von VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\X1 Von Vop Vocm ct_inductor l1=1n l2=1n k=0
    \\X2 Von Vop B_3_ B_2_ B_1_ B_0_ Vcn Vcp Varactor_Switched_caps
    \\*@ weak role vocm output
    \\*@ weak role von output
    \\*@ weak role vop output
    \\*@ weak role vcp output
    \\*@ weak role vcn output
    \\*@ weak role b_3_ output
    \\*@ weak role b_2_ output
    \\*@ weak role b_1_ output
    \\*@ weak role b_0_ output
;

// ---- tests ----

test "center tap continuity: AG1114 preserves the actual Q3-Q4 base wire" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("AG1114 Q3.B-Q4.B compact={}\n", .{compact});
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1114}, null);
        defer p.deinit();
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
        if (compact) {
            const q3 = np.checks.deviceIn(&p, "q3").?;
            const q4 = np.checks.deviceIn(&p, "q4").?;
            const pins = [_]usize{ p.dev_pin0[q3] + 1, p.dev_pin0[q4] + 1 };
            try testing.expectEqual(p.pin_net[pins[0]], p.pin_net[pins[1]]);
            try testing.expect(try ink.connected(testing.allocator, &p, &pins));
        }
    }
}

test "center tap continuity: AG1146 preserves its straight mirror gate interval" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("AG1146 M3.G-M4.G compact={}\n", .{compact});
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1146}, null);
        defer p.deinit();
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
        const a = p.dev_pin0[np.checks.deviceIn(&p, "m3").?] + 1;
        const b = p.dev_pin0[np.checks.deviceIn(&p, "m4").?] + 1;
        try testing.expectEqual(p.pin_net[a], p.pin_net[b]);
        try testing.expectEqual(p.pin_xy[a].y, p.pin_xy[b].y);
        const lo = @min(p.pin_xy[a].x, p.pin_xy[b].x);
        const hi = @max(p.pin_xy[a].x, p.pin_xy[b].x);
        // Every integer point on the literal terminal interval has own-net
        // ink. Labels, a detour and a foreign crossing cannot satisfy it.
        for (0..@as(usize, @intCast(hi - lo)) + 1) |dx| {
            const at: np.Pt = .{ .x = lo + @as(i32, @intCast(dx)), .y = p.pin_xy[a].y };
            var segments = p.segments(p.pin_net[a]);
            const reached = while (segments.next()) |poly| {
                if (ink.onPolyline(poly, at)) break true;
            } else false;
            try testing.expect(reached);
        }
    }
}
