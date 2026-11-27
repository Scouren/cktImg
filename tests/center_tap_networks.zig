//! Full source center-tap circuits -> retained physical conductor paths.
//! Oracle: actual source-owned capacitor/transistor/switch/coil terminals and
//! dot-aware conductor ink in center_tap_connectivity.py's frozen21 diagnostic.
//! Only DUT wrappers are removed; literal source declarations/cards and the
//! CLI's weak port roles remain. Tests do not require source global placement.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1149 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model qnpn npn
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\C1 net6 net10 1p
    \\C2 net8 net7 1p
    \\C3 net0 net4 1p
    \\C4 net11 net0 1p
    \\C5 net1 net9 1p
    \\C6 net2 net1 1p
    \\C7 VTune net11 1p
    \\C8 VTune net9 1p
    \\LB1A VB1 net7 1n
    \\LB1B net6 VB1 1n
    \\LB2A net11 VB2 1n
    \\LB2B net9 VB2 1n
    \\LS1 net4 net5 1n
    \\LS2 net3 net2 1n
    \\LT1 net5 VSS 1n
    \\LT2 net3 VSS 1n
    \\Q1 net10 net7 net5 VSS qnpn m=1
    \\Q2 net8 net6 net3 VSS qnpn m=1
    \\Q3 net8 net8 net10 VSS qnpn m=1
    \\Q4 net10 net10 net8 VSS qnpn m=1
    \\XLp net10 net8 Vcc ct_inductor l1=1n l2=1n k=0
    \\*@ weak role vtune output
;

const ag1180 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.model ideal_switch SW(RON=1 ROFF=1e12 VT=0.5 VH=0)
    \\C1 net6 net4 1p
    \\C2 net2 net3 1p
    \\C3 net0 net5 1p
    \\C4 net7 net1 1p
    \\CT1 net4 net5 1p
    \\CT2 net2 net7 1p
    \\M1 net4 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net5 net4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net2 net7 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net7 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\S1 net6 net3 S1 VSS ideal_switch
    \\S2 net0 net1 S2 VSS ideal_switch
    \\SE1 net4 net2 SE VSS ideal_switch
    \\SE2 net5 net7 SE VSS ideal_switch
    \\SO1 net4 net7 SO VSS ideal_switch
    \\SO2 net2 net5 SO VSS ideal_switch
    \\XLE1 net4 net5 VDD ct_inductor l1=1n l2=1n k=0
    \\XLE2 net2 net7 VDD ct_inductor l1=1n l2=1n k=0
    \\XLO1 net4 net5 VDD ct_inductor l1=1n l2=1n k=0
    \\XLO2 net2 net7 VDD ct_inductor l1=1n l2=1n k=0
    \\*@ weak role s1 output
    \\*@ weak role s2 output
    \\*@ weak role se output
    \\*@ weak role so output
;

const Terminal = struct { name: []const u8, index: u32 };
const Pair = struct { left: Terminal, right: Terminal };

// ---- private ----

fn retained(deck: []const u8, pairs: []const Pair) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
        if (compact) {
            for (pairs) |pair| {
                errdefer std.debug.print("center-tap source path {s}.{}--{s}.{}\n", .{ pair.left.name, pair.left.index, pair.right.name, pair.right.index });
                const a = np.checks.deviceIn(&p, pair.left.name).?;
                const b = np.checks.deviceIn(&p, pair.right.name).?;
                const pins = [_]usize{ p.dev_pin0[a] + pair.left.index, p.dev_pin0[b] + pair.right.index };
                try testing.expect(try ink.connected(testing.allocator, &p, &pins));
            }
        }
    }
}

// ---- tests ----

test "center tap network: AG1149 preserves the base feed and coil feedback" {
    // C2.2(300,130) -> Q1.B(20,190), including a source diagonal segment.
    // Q3.C(90,50) -> XLp.N2(230,0), through actual junctions (110,50)/(370,50).
    // The required behavior is continuity, with Manhattan native wires allowed.
    try retained(ag1149, &.{
        .{ .left = .{ .name = "c2", .index = 1 }, .right = .{ .name = "q1", .index = 1 } },
        .{ .left = .{ .name = "q3", .index = 0 }, .right = .{ .name = "xlp", .index = 1 } },
    });
}

test "center tap network: AG1180 preserves actual switch contacts and coil links" {
    // Visible switch contacts 1/2 map to SPICE nodes 1/2; hidden controls are
    // excluded. C3.1(220,100) -> S2.1(260,100) is a literal source segment.
    // C1.2(180,-100) -> SO1.1(240,-60) follows the dotted upper source bus.
    // CT2.1 -> XLO2.N1 is independently certified on the other tank's bus.
    try retained(ag1180, &.{
        .{ .left = .{ .name = "c3", .index = 0 }, .right = .{ .name = "s2", .index = 0 } },
        .{ .left = .{ .name = "c1", .index = 1 }, .right = .{ .name = "so1", .index = 0 } },
        .{ .left = .{ .name = "ct2", .index = 0 }, .right = .{ .name = "xlo2", .index = 0 } },
    });
}
