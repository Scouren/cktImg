//! AG1147's actual source Vop tree includes M2.G and all five other pins.
//! The new coil removes a crossing, so Von remains wired instead of being
//! thinned. Its earlier route must leave M2.G a physical outward escape.
//! Oracle: actual source lead/ink certificates in the center-tap study,
//! full electrical identity, and no foreign-net contact in either layout.
//!
//! Contents: complete source DUT and physical-tree regression.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1147 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\C Vop Von 1p
    \\C1 Vop net3 1p
    \\C2 Von net1 1p
    \\Ct1 Vop Vtune 1p
    \\Ct2 Von Vtune 1p
    \\IB Vb VSS DC 1m
    \\M1 Vop Von net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 Von Vop net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 VSS net3 net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VSS net1 net4 VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 VDD VDD net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 Vb Vb net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 net3 Vb 1k
    \\R2 net1 Vb 1k
    \\X1 Vop Von VDD ct_inductor l1=1n l2=1n k=0
    \\*@ weak role vtune output
    \\
;

test "pin escape: AG1147 retains the complete physical Vop tree" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("AG1147 Vop compact={}\n", .{compact});
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1147}, null);
        defer p.deinit();
        var pins: [6]usize = undefined;
        for ([_][]const u8{ "c", "c1", "ct1", "m1", "m2", "x1" }, [_]u32{ 0, 0, 0, 0, 1, 0 }, &pins) |name, index, *pin| {
            pin.* = p.dev_pin0[np.checks.deviceIn(&p, name).?] + index;
        }
        for (pins[1..]) |pin| try std.testing.expectEqual(p.pin_net[pins[0]], p.pin_net[pin]);
        try support.expectConnected(&p, lib);
        try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
        try std.testing.expect(try ink.connected(gpa, &p, &pins));
    }
}
