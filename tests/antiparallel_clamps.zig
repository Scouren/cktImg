//! Antiparallel diode-connected channel pairs -> source-derived local geometry.
//! Oracle: actual SVG D/G/S or C/B/E leads and conductor paths in all four
//! source circuits (eight devices), independently retained by the antiparallel
//! study. Both channels lie flat on separate rows, their controls face outward,
//! and the same net occupies the same channel end. AG1149 staggers their x
//! positions; neither a shared column nor an exact gap is required.
//!
//! The complete suite remains unimported while the named AG1149 physical
//! failures remain unresolved; its focused RED and partial GREEN are recorded.
//! Contents: complete literal source decks, actual-pin helpers, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag739 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\MD1 net5 net5 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\MD2 net2 net2 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN1 net5 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN10 net6 net4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN11 Qn net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN2 net2 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN3 net7 net8 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN4 net8 net7 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN5 net7 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN6 net8 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN7 net4 PHI1 net7 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN8 net3 PHI1 net8 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN9 net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP1 net5 Vn net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP10 Qn net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP2 net2 Vin net0 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP3 net4 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP4 net3 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP5 net4 PHI1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP6 net3 PHI1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP7 net1 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP8 net0 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP9 net6 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 Vn Vn-1 1k
    \\*@ weak role vn output
    \\*@ weak role vn-1 output
    \\*@ weak role phi1 input
    \\*@ weak role qn output
;

const ag1048 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\IB1 VB1 VSS DC 1m
    \\M1 VM1 vX net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M10 VDD VP1 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net0 VDD VCMM VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net2 VDD VCMP VSS nch l=0.15 w=1 nf=1 m=1
    \\M13 VCMM VCMM VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 VCMP VCMP VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 Vout1 VM1 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 Vout2 VP1 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 net3 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VP1 VCM net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M20 net1 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 VM1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VP1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 VP1 VP1 VM1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 VM1 VM1 VP1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 net4 VCMM VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 net4 VCMP VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 VDD VM1 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\MB1 VB1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 net3 Vout1 1k
    \\R2 net3 Vout2 1k
    \\*@ weak role vx input
    \\*@ weak role vcm input
;

const ag1052 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\* Ideal inverter: switches at V(VDD,VSS)/2; vt sets the step width, td the delay
    \\.subckt inverter VDD VSS A Y params: vt=10m td=10p
    \\BhA hA 0 V={0.5*(1+tanh((V(A,VSS)-0.5*V(VDD,VSS))/vt))}
    \\Bf nfn VSS V={V(VDD,VSS)*(1-V(hA))}
    \\Rd nfn ndl 1k
    \\Cd ndl VSS {td/1000}
    \\BY Y VSS V={V(ndl,VSS)}
    \\.ends inverter
    \\
    \\M1 net1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M10 net15 net11 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net2 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net4 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 vM2 net9 net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 vP2 net15 net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 net3 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 VOP vM2 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 VON vP2 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 net5 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 VDD VON net6 VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net11 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 net6 net6 net13 VSS nch l=0.15 w=1 nf=1 m=1
    \\M21 net13 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M22 net10 VON VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M23 net10 net13 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M24 VDD VOP net12 VSS nch l=0.15 w=1 nf=1 m=1
    \\M25 net12 net12 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M26 net0 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M27 net14 VOP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M28 net14 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net1 vX net8 VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net11 VCM net8 VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net8 VCMFB VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 net11 net11 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 net1 net1 net11 VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 net7 net7 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 net9 net1 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 net7 net9 1k
    \\R2 net7 net15 1k
    \\R3 net4 vM2 1k
    \\R4 net4 vP2 1k
    \\R5 VDD VOP 1k
    \\R6 VDD VON 1k
    \\X1 VDD VSS net14 Q inverter td=10p vt=10m
    \\X2 VDD VSS net10 Q_bar inverter td=10p vt=10m
    \\*@ weak role vx input
    \\*@ weak role vcm input
    \\*@ weak role vcmfb input
    \\*@ weak role q output
    \\*@ weak role q_bar output
;

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

const Case = struct { deck: []const u8, names: [2][]const u8 };
const cases = [_]Case{
    .{ .deck = ag739, .names = .{ "md1", "md2" } },
    .{ .deck = ag1048, .names = .{ "m5", "m6" } },
    .{ .deck = ag1052, .names = .{ "m6", "m7" } },
    .{ .deck = ag1149, .names = .{ "q3", "q4" } },
};

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, index: usize) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + index;
}

fn axis(p: *const np.Placed, name: []const u8, horizontal: bool) !void {
    const a, const b = .{ p.pin_xy[pin(p, name, 0)], p.pin_xy[pin(p, name, 2)] };
    try testing.expectEqual(horizontal, a.y == b.y);
    try testing.expectEqual(!horizontal, a.x == b.x);
}

fn connected(p: *const np.Placed, a: usize, b: usize) !void {
    try testing.expect(try ink.connected(testing.allocator, p, &.{ a, b }));
}

fn group(p: *const np.Placed, names: [2][]const u8) !void {
    for (names) |name| try axis(p, name, true);
    const a, const b = .{ pin(p, names[0], 0), pin(p, names[1], 0) };
    const top = if (p.pin_xy[a].y < p.pin_xy[b].y) a else b;
    const bottom = if (top == a) b else a;
    try testing.expect(p.pin_xy[top].y < p.pin_xy[bottom].y);
    try testing.expect(p.pin_xy[top + 1].y < p.pin_xy[top].y);
    try testing.expect(p.pin_xy[bottom + 1].y > p.pin_xy[bottom].y);
    // Reversed channel identities: top C/D and bottom E/S are one net.
    try testing.expectEqual(p.pin_net[a], p.pin_net[b + 2]);
    try testing.expectEqual(p.pin_net[a + 2], p.pin_net[b]);
    try testing.expectEqual(p.pin_xy[a].x < p.pin_xy[a + 2].x, p.pin_xy[b + 2].x < p.pin_xy[b].x);
    try connected(p, a, a + 1);
    try connected(p, b, b + 1);
    try connected(p, a, b + 2);
    try connected(p, a + 2, b);
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

fn honoured(text: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{text}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    for (try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
}

// ---- tests ----

test "antiparallel clamps: all eight actual source channels form an outward-facing local pair" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for (cases) |case| for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("antiparallel source {s}/{s}, compact={}\n", .{ case.names[0], case.names[1], compact });
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{case.deck}, null);
        defer p.deinit();
        try electrical(&p, lib);
        try group(&p, case.names);
    };
}

test "antiparallel clamps: AG1149 retains the base feed and clamp-to-coil source paths" {
    // Independent actual source endpoints: C2.2(300,130)->Q1.B(20,190)
    // and Q3.C(90,50)->XLp.N2(230,0). Native Manhattan detours are valid.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{ag1149}, null);
        defer p.deinit();
        try electrical(&p, lib);
        if (compact) {
            try connected(&p, pin(&p, "c2", 1), pin(&p, "q1", 1));
            try connected(&p, pin(&p, "q3", 0), pin(&p, "xlp", 1));
        }
    }
}

test "antiparallel clamps: node and device renaming and card permutation preserve the relation" {
    const models = ".model nch nmos\n.model qn npn\n";
    const local = [_]Case{
        .{ .deck = models ++ "R1 vdd left 1k\nR2 vdd right 1k\n" ++
            "M1 left left right vss nch\nM2 right right left vss nch\n", .names = .{ "m1", "m2" } },
        .{ .deck = models ++ "M8 alpha alpha beta vss nch\nM4 beta beta alpha vss nch\n" ++
            "R9 vdd beta 1k\nR7 vdd alpha 1k\n", .names = .{ "m4", "m8" } },
        .{ .deck = models ++ "Q8 alpha alpha beta vss qn\nQ4 beta beta alpha vss qn\n" ++
            "R9 vdd beta 1k\nR7 vdd alpha 1k\n", .names = .{ "q4", "q8" } },
    };
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for (local) |case| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{case.deck}, null);
        defer p.deinit();
        try electrical(&p, lib);
        try group(&p, case.names);
    };
}

test "antiparallel clamps: explicit upright and exact caller poses take precedence" {
    const base = ".model nch nmos\nR1 vdd left 1k\nR2 vdd right 1k\n" ++
        "M1 left left right vss nch\nM2 right right left vss nch\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{ "*@ upright m1 m2\n", "*@ upright m1\n", "*@ at m1 -2 -2 R90\n" }) |hint| {
        const deck = try std.mem.concat(testing.allocator, u8, &.{ base, hint });
        defer testing.allocator.free(deck);
        var p = try np.place(testing.allocator, &.default, lib, &.{deck}, null);
        defer p.deinit();
        try electrical(&p, lib);
        try axis(&p, "m1", false);
        if (std.mem.startsWith(u8, hint, "*@ at")) {
            const d = np.checks.deviceIn(&p, "m1").?;
            try testing.expectEqual(np.Pt{ .x = -80, .y = -80 }, p.dev_pos[d]);
            try testing.expectEqual(np.Orient{ .rot = 1 }, p.dev_orient[d]);
        }
    }
}

test "antiparallel clamps: standalone control faces retain their earlier caller contract" {
    // Oracle: actual left/right gate/base coordinates and honoured reports.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const fixtures = [_]struct { []const u8, []const u8, []const u8 }{
        .{ ".model nch nmos\nM1 a a b 0 nch\nM2 b b a 0 nch\n", "m1", "g" },
        .{ ".model np npn\nQ1 a a b 0 np\nQ2 b b a 0 np\n", "q1", "b" },
    };
    for (fixtures) |row| for ([_][]const u8{ "left", "right" }) |side| {
        const deck = try std.fmt.allocPrint(testing.allocator, "{s}*@ face {s} {s} {s}\n", .{ row[0], row[1], row[2], side });
        defer testing.allocator.free(deck);
        var p = try np.place(testing.allocator, &.default, lib, &.{deck}, null);
        defer p.deinit();
        try electrical(&p, lib);
        try axis(&p, row[1], false);
        const start = pin(&p, row[1], 0);
        try testing.expectEqual(std.mem.eql(u8, side, "left"), p.pin_xy[start + 1].x < p.pin_xy[start].x);
        try honoured(deck, &p, lib);
    };
}

test "antiparallel clamps: invalid faces cannot suppress the automatic pair" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const base = ".model nch nmos\nR1 vdd a 1k\nR2 vdd b 1k\nM1 a a b 0 nch\nM2 b b a 0 nch\n";
    for ([_][]const u8{ "*@ face m1 nope left\n", "*@ face m1 g north\n", "*@ face missing g left\n" }) |hint| {
        const deck = try std.mem.concat(testing.allocator, u8, &.{ base, hint });
        defer testing.allocator.free(deck);
        var p = try np.place(testing.allocator, &.default, lib, &.{deck}, null);
        defer p.deinit();
        try group(&p, .{ "m1", "m2" });
        try electrical(&p, lib);
    }
}

test "antiparallel clamps: source MOS pairs lie between their four channel-end anchors" {
    // Oracle: actual source D/S tips are strictly inside the four external
    // drain tips' rectangle. Source columns agree, but a common pair column
    // and any fixed gap are deliberately absent from this oracle. AG1149 has
    // one external transistor channel per end, so is outside this contract.
    const rows = [_]struct { Case, [2][]const u8, [2][]const u8 }{
        .{ cases[0], .{ "mp1", "mp2" }, .{ "mn1", "mn2" } },
        .{ cases[1], .{ "m3", "m4" }, .{ "m1", "m2" } },
        .{ cases[2], .{ "m1", "m2" }, .{ "m3", "m4" } },
    };
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for (rows) |row| for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("antiparallel channel anchors {s}/{s}, compact={}\n", .{ row[0].names[0], row[0].names[1], compact });
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{row[0].deck}, null);
        defer p.deinit();
        const upper = [2]np.Pt{ p.pin_xy[pin(&p, row[1][0], 0)], p.pin_xy[pin(&p, row[1][1], 0)] };
        const lower = [2]np.Pt{ p.pin_xy[pin(&p, row[2][0], 0)], p.pin_xy[pin(&p, row[2][1], 0)] };
        const left = @min(@min(upper[0].x, upper[1].x), @min(lower[0].x, lower[1].x));
        const right = @max(@max(upper[0].x, upper[1].x), @max(lower[0].x, lower[1].x));
        const top, const bottom = .{ @max(upper[0].y, upper[1].y), @min(lower[0].y, lower[1].y) };
        for (row[0].names) |name| for ([_]usize{ 0, 2 }) |index| {
            const at = p.pin_xy[pin(&p, name, index)];
            try testing.expect(top < at.y and at.y < bottom);
            try testing.expect(left < at.x and at.x < right);
        };
        try electrical(&p, lib);
    };
}
