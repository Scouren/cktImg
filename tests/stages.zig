//! The stage lines (docs/research/vocabulary.md, src/units.zig): `stage`
//! names a unit, `row`, `order` and `repeat` move units whole. The case is
//! ag-1067 of the Analog Canvas corpus, four identical pass-XNOR cells in
//! series, which the engine draws as a staircase (the Fable round's
//! reproducer). Oracles: the finished `Placed` read back (each unit's top
//! row, its extent along x, its members' rows), the skeleton's cells of the
//! devices no line names compared with the drawing without the lines, and
//! the guarantees every drawing keeps.
//!
//! Contents: tests only.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

/// ag-1067 as the corpus has it, its top cell `dut` flattened to the top
/// level (its ports are its nets).
const deck =
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
    \\M1 net15 A0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M10 VX net13 net19 VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net12 net22 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 VX B1 net12 VSS nch l=0.15 w=1 nf=1 m=1
    \\M13 net18 net22 net16 VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 net16 net13 VX VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 net18 A1 net27 VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 net27 B1 VX VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 net5 A2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 net1 net8 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 net24 net17 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net18 net6 net15 VSS nch l=0.15 w=1 nf=1 m=1
    \\M20 net1 B2 net24 VSS nch l=0.15 w=1 nf=1 m=1
    \\M21 VX net17 net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M22 net3 net8 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M23 VX A2 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M24 net0 B2 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M25 net26 A3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M26 net2 net21 net26 VSS nch l=0.15 w=1 nf=1 m=1
    \\M27 net4 net20 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M28 net2 B3 net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M29 net1 net20 net23 VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net10 net11 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M30 net23 net21 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M31 net1 A3 net14 VSS nch l=0.15 w=1 nf=1 m=1
    \\M32 net14 B3 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M33 net2 net7 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 net18 B0 net10 VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 VDD net11 net9 VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 net9 net6 net18 VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 VDD A0 net25 VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 net25 B0 net18 VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 net19 A1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\X1 VDD VSS A0 net11 inverter td=10p vt=10m
    \\X10 VDD VSS net7 EQ inverter td=10p vt=10m
    \\X2 VDD VSS B0 net6 inverter td=10p vt=10m
    \\X3 VDD VSS A1 net22 inverter td=10p vt=10m
    \\X4 VDD VSS B1 net13 inverter td=10p vt=10m
    \\X5 VDD VSS A2 net17 inverter td=10p vt=10m
    \\X6 VDD VSS B2 net8 inverter td=10p vt=10m
    \\X7 VDD VSS A3 net20 inverter td=10p vt=10m
    \\X8 VDD VSS B3 net21 inverter td=10p vt=10m
    \\X9 VDD VSS net2 net7 inverter td=10p vt=10m
    \\*@ shelf off
    \\
;

/// The four cells, each member k the same part of its cell.
const cells =
    \\*@ stage b0 x1 x2 m1 m2 m3 m4 m5 m6 m7 m8
    \\*@ stage b1 x3 x4 m9 m10 m11 m12 m13 m14 m15 m16
    \\*@ stage b2 x5 x6 m17 m18 m19 m20 m21 m22 m23 m24
    \\*@ stage b3 x7 x8 m25 m26 m27 m28 m29 m30 m31 m32
    \\
;

const names = [4][]const []const u8{
    &.{ "x1", "x2", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8" },
    &.{ "x3", "x4", "m9", "m10", "m11", "m12", "m13", "m14", "m15", "m16" },
    &.{ "x5", "x6", "m17", "m18", "m19", "m20", "m21", "m22", "m23", "m24" },
    &.{ "x7", "x8", "m25", "m26", "m27", "m28", "m29", "m30", "m31", "m32" },
};

const Drawn = struct {
    arena: std.heap.ArenaAllocator,
    p: np.Placed,
    nl: np.netlist.Netlist,
    v: []const np.hints.Verdict,

    fn init(src: []const u8, lib: *np.Library) !Drawn {
        var d: Drawn = .{ .arena = .init(testing.allocator), .p = undefined, .nl = undefined, .v = undefined };
        errdefer d.arena.deinit();
        const a = d.arena.allocator();
        d.p = try np.place(testing.allocator, &.{}, lib, &.{src}, null);
        errdefer d.p.deinit();
        d.nl = try np.netlist.parse(a, &.{src}, null);
        const roles = try np.guessRoles(a, &d.nl);
        const st = try np.schematic.structure.analyze(a, a, &d.nl, roles);
        const sk = try np.schematic.skeleton.place(a, a, &d.nl, roles, &st, .{});
        d.v = try np.report.verdicts(a, &d.nl, roles, &st, &sk, &d.p, lib);
        return d;
    }

    fn deinit(d: *Drawn) void {
        d.p.deinit();
        d.arena.deinit();
    }

    fn at(d: *const Drawn, name: []const u8) np.Pt {
        return d.p.dev_pos[np.checks.deviceIn(&d.p, name).?];
    }

    /// A unit's top y, leftmost x and rightmost x.
    fn box(d: *const Drawn, unit: []const []const u8) [3]i32 {
        var b: [3]i32 = .{ std.math.maxInt(i32), std.math.maxInt(i32), std.math.minInt(i32) };
        for (unit) |m| b = .{ @min(b[0], d.at(m).y), @min(b[1], d.at(m).x), @max(b[2], d.at(m).x) };
        return b;
    }

    fn expectHonoured(d: *const Drawn) !void {
        for (d.nl.hints, d.v) |h, v| {
            errdefer std.debug.print("{s}: {t} {t}\n", .{ h.text, v.state, v.code });
            try testing.expectEqual(np.hints.State.honoured, v.state);
        }
    }
};

/// The skeleton's cells in its own frame, per device.
fn frameCells(a: std.mem.Allocator, src: []const u8) !struct { nl: np.netlist.Netlist, x: []i32, y: []i32 } {
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const x = try a.dupe(i32, sk.x);
    const y = try a.dupe(i32, sk.y);
    for (x, y) |*cx, *cy| {
        cx.* += sk.origin[0];
        cy.* += sk.origin[1];
    }
    return .{ .nl = nl, .x = x, .y = y };
}

test "stages: four repeated cells stand level, alike, left to right, the output stage after them" {
    // Oracle: the drawing. Unhinted, each cell hangs a row pair below the
    // one before (a staircase over 10 rows); the Fable agent's 54 lines
    // still drew one. Seven lines: each cell's top on one y, each wholly
    // right of the one before, each member as far below its cell's top as
    // the first cell's member, and the output stage right of the last.
    const src = deck ++ cells ++ "*@ repeat b0 b1 b2 b3\n*@ stage out x9 x10 m33\n*@ order b3 out\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var d: Drawn = try .init(src, lib);
    defer d.deinit();
    try d.expectHonoured();
    const first = d.box(names[0]);
    var prev = first;
    for (names[1..]) |unit| {
        const b = d.box(unit);
        try testing.expectEqual(first[0], b[0]);
        try testing.expect(b[1] > prev[2]);
        for (unit, names[0]) |m, model| try testing.expectEqual(d.at(model).y - first[0], d.at(m).y - b[0]);
        prev = b;
    }
    try testing.expect(d.box(&.{ "x9", "x10", "m33" })[1] > prev[2]);
    try support.expectConnected(&d.p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &d.p, true));
}

test "stages: a row of stages levels them; a stage line moves no device it does not name" {
    // Oracle: the skeleton's cells without the lines. `row b0 b1` levels
    // the two cells' tops; every device of neither cell keeps its cell,
    // but those the moved cell landed on.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const src = deck ++ cells ++ "*@ row b0 b1\n";
    var d: Drawn = try .init(src, lib);
    defer d.deinit();
    try d.expectHonoured();
    try testing.expectEqual(d.box(names[0])[0], d.box(names[1])[0]);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try frameCells(a, deck);
    // The stage lines alone: each cell its own ground row (levels.11), the
    // rest as before; then the row moves b1 alone.
    const staged = try frameCells(a, deck ++ cells);
    const after = try frameCells(a, src);
    const member = try a.alloc(bool, before.x.len);
    @memset(member, false);
    for (names) |unit| for (unit) |m| {
        member[before.nl.device(m).?.index()] = true;
    };
    for (0..before.x.len) |e| {
        if (member[e]) continue;
        try testing.expectEqual(before.x[e], staged.x[e]);
        try testing.expectEqual(before.y[e], staged.y[e]);
        try testing.expectEqual(staged.x[e], after.x[e]);
        try testing.expectEqual(staged.y[e], after.y[e]);
    }
}

test "stages: the verdicts of malformed stage lines" {
    // Oracle: the verdict contract (hints.1): a stage line naming a device,
    // a stage of a stage's device, an unknown member, and a repeat of two
    // sizes each say why.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const src = deck ++ cells ++
        \\*@ stage m1 m2
        \\*@ stage dup m5 m33
        \\*@ stage odd m99
        \\*@ stage out x9 x10 m33
        \\*@ repeat b0 out
        \\*@ order b0 nothing
        \\
    ;
    var d: Drawn = try .init(src, lib);
    defer d.deinit();
    const want = [_]struct { []const u8, np.hints.State, np.hints.Code }{
        .{ "*@ stage m1 m2", .rejected, .bad_args },
        .{ "*@ stage dup m5 m33", .dropped, .taken },
        .{ "*@ stage odd m99", .rejected, .unknown_name },
        .{ "*@ stage out x9 x10 m33", .honoured, .ok },
        .{ "*@ repeat b0 out", .rejected, .bad_args },
        .{ "*@ order b0 nothing", .rejected, .unknown_name },
    };
    for (want) |w| {
        const v = for (d.nl.hints, d.v) |h, v| {
            if (std.mem.eql(u8, h.text, w[0])) break v;
        } else unreachable;
        errdefer std.debug.print("{s}: {t} {t}\n", .{ w[0], v.state, v.code });
        try testing.expectEqual(w[1], v.state);
        try testing.expectEqual(w[2], v.code);
    }
}
