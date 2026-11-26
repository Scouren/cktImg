//! Unique center-tapped coil/capacitor tanks -> relative actual geometry.
//! Oracle: nine actual source pairs and eighteen physical conductor paths
//! in iteration21-tank-capacitors.json; five pairs have one coil owner.
//! AG1180 shares each capacitor between two coils and is outside this rule.
//! The coil keeps its existing world pose. The capacitor is parallel,
//! centered along the winding, opposite the tap, with matched net ends.
//!
//! Contents: complete source DUTs, actual-pin oracle, then regressions.
//! Future regression suite; root controls activation and meaningful RED.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

// Only the DUT wrapper is removed. Hidden definitions, every DUT card and
// the CLI's weak external-role requests remain; reduction changes shelves.

const ag1103 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.subckt PA VDD VSS VB inp inn outp outn src
    \\Cf1 outp net3 1p
    \\Cf2 outn net1 1p
    \\LBWa VDD outp 1n
    \\LBWb VDD outn 1n
    \\LBWc VB net5 1n
    \\LBWg src VSS 1n
    \\MP1A net0 inp src VSS nch l=0.15 w=1 nf=1 m=1
    \\MP1B net2 inn src VSS nch l=0.15 w=1 nf=1 m=1
    \\MP2A outp net4 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\MP2B outn net4 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\Rc net5 net4 1k
    \\Rf1 net3 inp 1k
    \\Rf2 net1 inn 1k
    \\.ends PA
    \\
    \\.subckt DA VSS VB inp inn outp outn src
    \\Cf1 outp net0 1p
    \\Cf2 outn net4 1p
    \\LBWc VB net1 1n
    \\LBWg src VSS 1n
    \\MD1A net2 inp src VSS nch l=0.15 w=1 nf=1 m=1
    \\MD1B net5 inn src VSS nch l=0.15 w=1 nf=1 m=1
    \\MD2A outp net3 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\MD2B outn net3 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\Rc net1 net3 1k
    \\Rf1 net0 inp 1k
    \\Rf2 net4 inn 1k
    \\.ends DA
    \\
    \\C1 net9 net8 1p
    \\Cblk1 net13 net10 1p
    \\Cblk2 net24 net22 1p
    \\Cblk3 net9 net14 1p
    \\Cblk4 net8 net19 1p
    \\Cblk5 net6 net9 1p
    \\Cblk6 net0 net8 1p
    \\Cbyp1 net11 net21 1p
    \\Cbyp2 net7 net18 1p
    \\CIN1 net16 net23 1p
    \\CIN2 net13 net24 1p
    \\Cout1a net20 net25 1p
    \\Cout1b net4 net2 1p
    \\Cout2 net3 net12 1p
    \\Lb1 net16 net5 1n
    \\Lb2 net5 net23 1n
    \\Lb3 net13 VSS 1n
    \\Lb4 VSS net24 1n
    \\LBW1 RFIN net16 1n
    \\LBW2 VSS net23 1n
    \\LBW3 net1 V_bias 1n
    \\LBW4 net21 VDD 1n
    \\LBW5 V_bias net15 1n
    \\LBW6 net17 V_bias 1n
    \\LBW7 net12 RFOUT 1n
    \\LBW8 net3 VSS 1n
    \\Lp1a net20 net18 1n
    \\Lp1b net18 net25 1n
    \\Lp2 net4 net2 1n
    \\Ls net12 net3 1n
    \\R1 net1 net10 1k
    \\R2 net1 net22 1k
    \\R3 net14 net15 1k
    \\R4 net19 net15 1k
    \\R5 net6 net17 1k
    \\R6 net0 net17 1k
    \\X1 VSS VB_DA net10 net22 net9 net8 net11 DA
    \\X2 VDD VSS VB_PA net14 net19 net20 net25 net7 PA
    \\X3 VDD VSS VB_PA2 net6 net0 net4 net2 NC0001 PA
    \\XL1 net9 net8 net21 ct_inductor l1=1n l2=1n k=0
    \\KTF1 Lb1 Lb3 1
    \\KTF2 Lb2 Lb4 1
    \\KTF3 Lp1a Ls 1
    \\KTF4 Lp1b Ls 1
    \\KTF5 Lp2 Ls 1
    \\*@ weak role rfin output
    \\*@ weak role rfout output
    \\*@ weak role v_bias output
    \\
;

const ag1147 =
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

const ag1151 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model qnpn npn
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.model DIODE D(IS=1e-14 N=1)
    \\C net7 net6 1p
    \\D1 VCC net0 DIODE
    \\I1 net5 VSS DC 1m
    \\I2 net8 VSS DC 1m
    \\I3 net3 VSS DC 1m
    \\I4 net4 VSS DC 1m
    \\Q1 VCC net6 net1 VSS qnpn m=1
    \\Q2 VCC net7 net2 VSS qnpn m=1
    \\Q3 VCC net1 net5 VSS qnpn m=1
    \\Q4 VCC net2 net4 VSS qnpn m=1
    \\Q5 net1 net4 net8 VSS qnpn m=1
    \\Q6 net2 net5 net3 VSS qnpn m=1
    \\XL net6 net7 net0 ct_inductor l1=1n l2=1n k=0
    \\
;

const ag1152 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model qnpn npn
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.model DIODE D(IS=1e-14 N=1)
    \\C1 net5 net21 1p
    \\C2 net12 net22 1p
    \\Cac1 net19 net6 1p
    \\Cac2 net7 net23 1p
    \\Cac3 net8 net10 1p
    \\Cac4 net25 net18 1p
    \\D1 VCC net0 DIODE
    \\D2 VCC net1 DIODE
    \\I1 net4 VSS DC 1m
    \\I2 net2 VSS DC 1m
    \\I3 net16 VSS DC 1m
    \\I4 net3 VSS DC 1m
    \\I5 net14 VSS DC 1m
    \\I6 net15 VSS DC 1m
    \\I7 net17 VSS DC 1m
    \\I8 net13 VSS DC 1m
    \\Q1 VCC net21 net24 VSS qnpn m=1
    \\Q10 VCC net12 net20 VSS qnpn m=1
    \\Q11 VCC net11 N3 VSS qnpn m=1
    \\Q12 VCC net20 N4 VSS qnpn m=1
    \\Q13 net11 N4 net15 VSS qnpn m=1
    \\Q14 net20 N3 net17 VSS qnpn m=1
    \\Q15 N3 N1 net14 VSS qnpn m=1
    \\Q16 N4 N2 net13 VSS qnpn m=1
    \\Q2 VCC net5 net9 VSS qnpn m=1
    \\Q3 VCC net24 N1 VSS qnpn m=1
    \\Q4 VCC net9 N2 VSS qnpn m=1
    \\Q5 net24 N2 net2 VSS qnpn m=1
    \\Q6 net9 N1 net16 VSS qnpn m=1
    \\Q7 N1 N4 net4 VSS qnpn m=1
    \\Q8 N2 N3 net3 VSS qnpn m=1
    \\Q9 VCC net22 net11 VSS qnpn m=1
    \\R1 net19 net4 1k
    \\R2 net7 net3 1k
    \\R3 net8 net14 1k
    \\R4 net25 net13 1k
    \\R5 net6 VSS 50Ω
    \\R6 net23 VSS 50Ω
    \\R7 net10 VSS 50Ω
    \\R8 net18 VSS 50Ω
    \\XL1 net21 net5 net0 ct_inductor l1=1n l2=1n k=0
    \\XL2 net22 net12 net1 ct_inductor l1=1n l2=1n k=0
    \\
;

const Case = struct { deck: []const u8, coil: []const u8, cap: []const u8, keeps_world_pose: bool = true };
const cases = [_]Case{
    .{ .deck = ag1103, .coil = "xl1", .cap = "c1", .keeps_world_pose = false },
    .{ .deck = ag1147, .coil = "x1", .cap = "c" },
    .{ .deck = ag1151, .coil = "xl", .cap = "c" },
    .{ .deck = ag1152, .coil = "xl1", .cap = "c1" },
    .{ .deck = ag1152, .coil = "xl2", .cap = "c2" },
};

// ---- private ----

fn namedPin(p: *const np.Placed, lib: *const np.Library, device: []const u8, name: []const u8) !usize {
    const d = np.checks.deviceIn(p, device) orelse return error.MissingDevice;
    const c = lib.at(p.dev_class[d]);
    for (c.terminals, 0..) |t, i| if (std.ascii.eqlIgnoreCase(t.name, name)) return p.dev_pin0[d] + i;
    return error.MissingTerminal;
}

fn matchedPins(p: *const np.Placed, lib: *const np.Library, case: Case) ![5]usize {
    const a = try namedPin(p, lib, case.coil, "n1");
    const b = try namedPin(p, lib, case.coil, "n2");
    const tap = try namedPin(p, lib, case.coil, "n3");
    const c = np.checks.deviceIn(p, case.cap) orelse return error.MissingDevice;
    const lo, const hi = p.pinRange(c);
    try testing.expectEqual(@as(u32, 2), hi - lo);
    try testing.expect(p.pin_net[a] != p.pin_net[b]);
    try testing.expect(p.pin_net[tap] != p.pin_net[a] and p.pin_net[tap] != p.pin_net[b]);
    const ca = if (p.pin_net[lo] == p.pin_net[a]) lo else lo + 1;
    const cb = if (ca == lo) lo + 1 else lo;
    try testing.expectEqual(p.pin_net[a], p.pin_net[ca]);
    try testing.expectEqual(p.pin_net[b], p.pin_net[cb]);
    return .{ a, b, tap, ca, cb };
}

fn relative(points: [5]np.Pt) bool {
    const a, const b, const t, const c, const d = points;
    const horizontal = a.y == b.y and a.x != b.x;
    const vertical = a.x == b.x and a.y != b.y;
    if (!horizontal and !vertical) return false;
    // Literal source relation expressed with doubled midpoint coordinates;
    // neither rounding nor class origins stand in for physical endpoints.
    if (horizontal) return c.y == d.y and c.x != d.x and
        @as(i64, a.x) + b.x == @as(i64, c.x) + d.x and
        2 * @as(i64, t.x) == @as(i64, a.x) + b.x and
        (@as(i64, b.x) - a.x) * (@as(i64, d.x) - c.x) > 0 and
        (@as(i64, c.y) - a.y) * (@as(i64, t.y) - a.y) < 0;
    return c.x == d.x and c.y != d.y and
        @as(i64, a.y) + b.y == @as(i64, c.y) + d.y and
        2 * @as(i64, t.y) == @as(i64, a.y) + b.y and
        (@as(i64, b.y) - a.y) * (@as(i64, d.y) - c.y) > 0 and
        (@as(i64, c.x) - a.x) * (@as(i64, t.x) - a.x) < 0;
}

fn expectTank(p: *const np.Placed, lib: *const np.Library, case: Case) !void {
    const pins = try matchedPins(p, lib, case);
    var points: [5]np.Pt = undefined;
    for (pins, &points) |i, *point| point.* = p.pin_xy[i];
    if (!relative(points)) std.debug.print("tank {s}/{s}: {any}\n", .{ case.coil, case.cap, points });
    try testing.expect(relative(points));
    for (0..2) |i| {
        const continuous = try ink.connected(testing.allocator, p, &.{ pins[i], pins[i + 3] });
        if (!continuous) std.debug.print("tank {s}/{s}: physical leg {d}, net {s}\n", .{ case.coil, case.cap, i, p.net_name[p.pin_net[pins[i]]] });
        try testing.expect(continuous);
    }
}

fn expectElectrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, p, true));
}

fn expectHonoured(text: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{text}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    for (try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
}

fn allocationFailure(gpa: std.mem.Allocator) !void {
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var p = try np.place(gpa, &.{ .layout = .{ .compact = false, .shelf = 8 } }, lib, &.{ag1152}, null);
    defer p.deinit();
    // Success proves that both the collected geometry and shelf grouping
    // path ran, rather than sweeping allocations in a rejected candidate.
    try expectTank(&p, lib, cases[3]);
    try expectTank(&p, lib, cases[4]);
}

test "center-tap tanks: allocation failures release pair order and cut-span scratch" {
    // A fixed backing resize policy makes every growth observable to the
    // standard allocation-failure sweep, as in the bias-neighbor owner.
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationFailure, .{});
}

test "center-tap tanks: five unique source pairs keep parallel centered capacitors opposite actual taps" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for (cases) |case| for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("tank {s}/{s}, compact={}\n", .{ case.coil, case.cap, compact });
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{case.deck}, null);
        defer p.deinit();
        // Four generic pairs retain their coil pose. AG1103's specific
        // paired-output owner now establishes its source-verified vertical
        // frame; every pair still owes the geometry and ink checks below.
        if (case.keeps_world_pose) try testing.expectEqualDeep(np.Orient.r0, p.dev_orient[np.checks.deviceIn(&p, case.coil).?]);
        try expectTank(&p, lib, case);
        if (std.mem.eql(u8, case.coil, "xl")) {
            // AG1151's ordinary I3 occupies the nearest target. A local
            // search must put the capacitor beyond its actual body, while
            // the broad fixed wall below still forces atomic abstention.
            const cap = np.checks.deviceIn(&p, case.cap).?;
            const current = np.checks.deviceIn(&p, "i3").?;
            const cb = lib.at(p.dev_class[cap]).box(p.dev_orient[cap], p.dev_pos[cap]);
            const ib = lib.at(p.dev_class[current]).box(p.dev_orient[current], p.dev_pos[current]);
            try testing.expect(cb.max.y < ib.min.y);
        }
        try expectElectrical(&p, lib);
    };
}

test "center-tap tanks: AG1152 retains both physical legs across the original shelf cut" {
    // Separate from the geometry assertion: this names the actual initial
    // regression C2.a/net12 -> XL2.N2 even if a future layout looks aligned.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1152}, null);
        defer p.deinit();
        for (cases[3..]) |case| {
            const pins = try matchedPins(&p, lib, case);
            for (0..2) |i| try testing.expect(try ink.connected(testing.allocator, &p, &.{ pins[i], pins[i + 3] }));
        }
        try expectElectrical(&p, lib);
    }
}

test "center-tap tanks: outer capacitor reversal and reordered tap declaration preserve named geometry" {
    const a = testing.allocator;
    const reversed = try std.mem.replaceOwned(u8, a, ag1151, "C net7 net6", "C net6 net7");
    defer a.free(reversed);
    const decl = try std.mem.replaceOwned(u8, a, ag1151, "ct_inductor n1 n2 n3 params:", "ct_inductor n3 n2 n1 params:");
    defer a.free(decl);
    const reordered = try std.mem.replaceOwned(u8, a, decl, "XL net6 net7 net0 ct_inductor", "XL net0 net7 net6 ct_inductor");
    defer a.free(reordered);
    for ([_][]const u8{ reversed, reordered }) |text| for ([_]bool{ false, true }) |compact| {
        // A Library retains registered classes by family name. A different
        // declaration is a different caller environment, not a request to
        // replace an already registered class in that same environment.
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        try expectTank(&p, lib, cases[2]);
        try expectElectrical(&p, lib);
    };
}

test "center-tap tanks: explicit capacitor form face cell and origin requests retain precedence" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const requests = [_][]const u8{
        "*@ upright c\n",
        "*@ bridge c\n*@ face c a right\n",
        "*@ cell c -8 -6\n*@ cell xl 0 0\n",
        "*@ at c -10 -10 r90\n",
    };
    for (requests, 0..) |request, which| for ([_]bool{ false, true }) |compact| {
        const text = try std.fmt.allocPrint(a, "{s}{s}", .{ ag1151, request });
        defer a.free(text);
        var p = try np.place(a, &.{ .layout = .{ .compact = compact } }, lib, &.{text}, null);
        defer p.deinit();
        const cap = np.checks.deviceIn(&p, "c").?;
        const first = p.pin_xy[p.dev_pin0[cap]];
        const second = p.pin_xy[p.dev_pin0[cap] + 1];
        switch (which) {
            0 => try testing.expectEqual(first.x, second.x),
            1 => try testing.expect(first.x > second.x and first.y == second.y),
            2 => {
                const coil = np.checks.deviceIn(&p, "xl").?;
                try testing.expect(p.dev_pos[cap].x < p.dev_pos[coil].x and p.dev_pos[cap].y < p.dev_pos[coil].y);
            },
            3 => try testing.expectEqualDeep(np.Pt{ .x = -400, .y = -400 }, p.dev_pos[cap]),
            else => unreachable,
        }
        try expectHonoured(text, &p, lib);
        try expectElectrical(&p, lib);
    };
}

test "center-tap tanks: explicit labels preserve deliberate physical separation" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const text = ag1151 ++ "*@ label net6\n*@ label net7\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{text}, null);
        defer p.deinit();
        const pins = try matchedPins(&p, lib, cases[2]);
        for (0..2) |i| try testing.expect(!try ink.connected(testing.allocator, &p, &.{ pins[i], pins[i + 3] }));
        try expectHonoured(text, &p, lib);
        try expectElectrical(&p, lib);
    }
}

test "center-tap tanks: shared coils duplicate caps and aliased ports retain ordinary placement" {
    // Conservative exclusion oracle: the known and opaque families use
    // identical caller-owned glyphs. Changing only the family must not
    // change the capacitor's placement in these inadmissible circuits.
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const glyph = try np.block_symbols.draw(arena.allocator(), .center_tap, &.{ "n1", "n2", "n3" }, 20);
    for ([_][]const u8{ "ct_inductor", "opaque_coil" }) |name| _ = try lib.register(.{ .name = name, .terminals = glyph.terminals, .draw = glyph.ops });
    const alias = try std.mem.replaceOwned(u8, a, ag1151, "XL net6 net7 net0", "XL net6 net7 net6");
    defer a.free(alias);
    const short = try std.mem.replaceOwned(u8, a, ag1151, "XL net6 net7 net0", "XL net6 net6 net0");
    defer a.free(short);
    const negative = [_][]const u8{
        ag1151 ++ "COTHER net6 net7 2p\n",
        ag1151 ++ "XOTHER net6 net7 net0 ct_inductor\n",
        alias,
        short,
    };
    for (negative) |text| for ([_]bool{ false, true }) |compact| {
        const control = try std.mem.replaceOwned(u8, a, text, "ct_inductor", "opaque_coil");
        defer a.free(control);
        var ordinary = try np.place(a, &.{ .layout = .{ .compact = compact } }, lib, &.{control}, null);
        defer ordinary.deinit();
        var candidate = try np.place(a, &.{ .layout = .{ .compact = compact } }, lib, &.{text}, null);
        defer candidate.deinit();
        const before = np.checks.deviceIn(&ordinary, "c").?;
        const after = np.checks.deviceIn(&candidate, "c").?;
        try testing.expectEqualDeep(ordinary.dev_pos[before], candidate.dev_pos[after]);
        try testing.expectEqualDeep(ordinary.dev_orient[before], candidate.dev_orient[after]);
        try expectElectrical(&candidate, lib);
    };
}

test "center-tap tanks: a fixed obstacle blocks the local capacitor target atomically" {
    // An opaque-family control has exactly the same glyph and topology.
    // Its actual coil frame locates the obstacle, independently of the new
    // owner's formula. The broad plate covers the opposite-tap local band
    // but stops before the coil. This test deliberately fixes the obstacle;
    // it does not claim that its caller-chosen overlaps are a valid layout.
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const glyph = try np.block_symbols.draw(arena.allocator(), .center_tap, &.{ "n1", "n2", "n3" }, 20);
    for ([_][]const u8{ "ct_inductor", "opaque_coil" }) |name| _ = try lib.register(.{ .name = name, .terminals = glyph.terminals, .draw = glyph.ops });
    _ = try lib.register(.{
        .name = "tank_obstacle",
        .terminals = &.{ .{ .name = "a", .at = .{ .x = -1000, .y = 0 }, .side = .left }, .{ .name = "b", .at = .{ .x = 1000, .y = 0 }, .side = .right } },
        .draw = &.{.{ .polyline = &.{ .{ .x = -1000, .y = -200 }, .{ .x = 1000, .y = -200 }, .{ .x = 1000, .y = 0 }, .{ .x = -1000, .y = 0 }, .{ .x = -1000, .y = -200 } } }},
    });
    const base = ag1151 ++ "RWALL barrier VSS 1k\n*@ class rwall tank_obstacle\n";
    const opaque_text = try std.mem.replaceOwned(u8, a, base, "ct_inductor", "opaque_coil");
    defer a.free(opaque_text);
    const probe_text = try std.mem.concat(a, u8, &.{ opaque_text, "*@ at rwall -100 -100 r0\n" });
    defer a.free(probe_text);
    var probe = try np.place(a, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{probe_text}, null);
    defer probe.deinit();
    const l = probe.pin_xy[try namedPin(&probe, lib, "xl", "n1")];
    const r = probe.pin_xy[try namedPin(&probe, lib, "xl", "n2")];
    try testing.expectEqual(l.y, r.y);
    const hint = try std.fmt.allocPrint(a, "*@ at rwall {d:.4} {d:.4} r0\n", .{ @as(f64, @floatFromInt(l.x + r.x)) / 80, @as(f64, @floatFromInt(l.y - 10)) / 40 });
    defer a.free(hint);
    const control = try std.mem.concat(a, u8, &.{ opaque_text, hint });
    defer a.free(control);
    const text = try std.mem.concat(a, u8, &.{ base, hint });
    defer a.free(text);
    var ordinary = try np.place(a, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{control}, null);
    defer ordinary.deinit();
    var candidate = try np.place(a, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{text}, null);
    defer candidate.deinit();
    const before = np.checks.deviceIn(&ordinary, "c").?;
    const after = np.checks.deviceIn(&candidate, "c").?;
    try testing.expectEqualDeep(ordinary.dev_pos[before], candidate.dev_pos[after]);
    try testing.expectEqualDeep(ordinary.dev_orient[before], candidate.dev_orient[after]);
    try expectHonoured(text, &candidate, lib);
}

test "center-tap tanks: literal relative oracle rejects same-side crossed-end off-center and skewed cases" {
    // Literal source-style frame, independent of current placement code.
    const good = [5]np.Pt{ .{ .x = -50, .y = 0 }, .{ .x = 50, .y = 0 }, .{ .x = 0, .y = 20 }, .{ .x = -20, .y = -40 }, .{ .x = 20, .y = -40 } };
    try testing.expect(relative(good));
    for (0..4) |i| {
        var bad = good;
        switch (i) {
            0 => {
                bad[3].y = 40;
                bad[4].y = 40;
            },
            1 => std.mem.swap(np.Pt, &bad[3], &bad[4]),
            2 => {
                bad[3].x += 10;
                bad[4].x += 10;
            },
            3 => bad[4].y += 10,
            else => unreachable,
        }
        try testing.expect(!relative(bad));
    }
    for (0..8) |i| {
        const pose: np.Orient = .{ .rot = @intCast(i & 3), .mirror = i >= 4 };
        var transformed: [5]np.Pt = undefined;
        for (good, &transformed) |point, *out| out.* = pose.apply(point).add(.{ .x = 30, .y = -70 });
        try testing.expect(relative(transformed));
    }
}
