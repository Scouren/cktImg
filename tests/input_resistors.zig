//! Grounded-source input branches -> actual resistor/source/gate geometry.
//! Oracle: the 22 source cases and 160 SVG leads in input-resistors.md.
//! Human Rules:
//! - A private grounded voltage-source junction feeding a MOS gate through
//!   one resistor forms a horizontal input branch at a driven gate's row.
//!   The upright source is outside the resistor, signal above ground and
//!   at/below the resistor row. All conditions use the same gate anchor.
//! - Actual source conductor ink connects both local legs in all 22 cases.
//!   The gate leg is horizontal. Labels cannot replace either local leg.
//! - Source adjacency alone gives no axis: AG637's BJT-base resistor and
//!   AMS114's MOS-source resistor are upright. Explicit geometry wins.
//!
//! Contents: complete source DUTs, physical-pin checks, then regressions.
//! Imported by tests/api.zig as a complete-branch regression gate.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

// Only DUT wrappers are removed. Models, values and every DUT card remain.
// cktimg-json adds the weak inline-driver request for each cell source;
// omitting it can test a detached driver island instead of the source DUT.

const ag161 =
    \\ag-161 grounded-source input fixture
    \\.model nch nmos
    \\CL Vout VSS 1p
    \\I1 Vout VSS DC 1m
    \\M1 VDD X Vout VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 X Vout VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\RS net0 X 1k
    \\Vin net0 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const ag265 =
    \\ag-265 grounded-source input fixture
    \\.model nch nmos
    \\M1 X net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 VDD X Vout VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 net1 net0 1k
    \\R2 net0 Vout 1k
    \\RD VDD X 1k
    \\RS Vout VSS 1k
    \\Vin net1 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const ag341 =
    \\ag-341 grounded-source input fixture
    \\.model pch pmos
    \\CC net1 Vout 1p
    \\CE VDD net1 1p
    \\CL Vout VSS 1p
    \\M9 Vout net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\RL Vout VSS 1k
    \\RS net0 net1 1k
    \\Vin net0 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const ag477 =
    \\ag-477 grounded-source input fixture
    \\.model nch nmos
    \\.model pch pmos
    \\C1 Y net1 1p
    \\C2 VSS net2 1p
    \\I1 VDD net2 DC 1m
    \\M1 Y X VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 Vout X VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 VDD net1 Vout VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 Y X net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\RB VDD net1 1k
    \\RF X Y 1k
    \\RS net0 X 1k
    \\Vin net0 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const ag1082 =
    \\ag-1082 grounded-source input fixture
    \\.model nch nmos
    \\I1 X VSS DC 1m
    \\M1 Voutp Vb X VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 Voutn X VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 VDD Voutp 1k
    \\R2 VDD Voutn 1k
    \\RS net0 X 1k
    \\VS net0 VSS DC 1 SIN(0 1 1k 0 0 0)
    \\*@ weak driver vs inline
    \\
;

const ams361 =
    \\amsnet-361 grounded-source input fixture
    \\.model nch nmos
    \\CDB Vout VSS 1p
    \\CGD Vout X 1p
    \\CGS X VSS 1p
    \\M1 Vout X VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\RD VDD Vout 1k
    \\RS X net0 1k
    \\Vin net0 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const ams585 =
    \\amsnet-585 grounded-source input fixture
    \\.model nch nmos
    \\M1 Vout net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\RD VDD Vout 1k
    \\RF Vout net1 1k
    \\RS net1 net0 1k
    \\Vin net0 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const ams401 =
    \\amsnet-401 grounded-source input fixture
    \\.model nch nmos
    \\CF B A 1p
    \\M1 B A VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\RD VDD B 1k
    \\RS A net0 1k
    \\V1 B VSS DC 1
    \\Vin net0 VSS DC 1
    \\*@ weak driver v1 inline
    \\*@ weak driver vin inline
    \\*@ weak role a output
    \\*@ weak role b output
    \\
;

const ams604 =
    \\amsnet-604 grounded-source input fixture
    \\.model nch nmos
    \\M1 X net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 VDD X Vout VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 net1 net0 1k
    \\R2 Vout net1 1k
    \\RD VDD X 1k
    \\RS Vout VSS 1k
    \\Vin net0 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const ag637 =
    \\ag-637 grounded-source input fixture
    \\.model qnpn npn
    \\.model qpnp pnp
    \\I1 VCC net11 DC 40uA
    \\I2 In+ VEE DC 20uA
    \\I3 In- VEE DC 20uA
    \\Igain net10 VEE DC 1m
    \\Q1 net0 In+ net10 VEE qnpn m=1
    \\Q10 net2 net5 net1 qpnp m=1
    \\Q11 net2 net2 net9 VEE qnpn m=1
    \\Q12 net9 net4 VEE VEE qnpn m=1
    \\Q13 Output net2 net4 VEE qnpn m=1
    \\Q14 net4 net4 VEE VEE qnpn m=1
    \\Q15 VCC net11 net8 VEE qnpn m=1
    \\Q16 net11 net8 In+ VEE qnpn m=1
    \\Q17 net11 net8 In- VEE qnpn m=1
    \\Q2 net5 In- net10 VEE qnpn m=1
    \\Q3 net6 net7 VCC qpnp m=1
    \\Q4 net0 net0 net6 qpnp m=1
    \\Q5 net7 net7 VCC qpnp m=1
    \\Q6 Output net0 net7 qpnp m=1
    \\Q7 net3 net1 VCC qpnp m=1
    \\Q8 net5 net5 net3 qpnp m=1
    \\Q9 net1 net1 VCC qpnp m=1
    \\R1 In+ net12 22kΩ
    \\R2 In- VSS 22kΩ
    \\Rload Output VSS 30kΩ
    \\Vin net12 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const ams114 =
    \\amsnet-114 grounded-source input fixture
    \\.model nch nmos
    \\M1 Vout Vb X VSS nch l=0.15 w=1 nf=1 m=1
    \\RD VDD Vout 1k
    \\rO Vout X 1k
    \\RS X net0 1k
    \\Vin net0 VSS DC 1
    \\*@ weak driver vin inline
    \\
;

const Case = struct {
    deck: []const u8,
    resistor: []const u8,
    source: []const u8 = "vin",
    gates: []const []const u8,
    r_junction: u1 = 0,
    v_signal: u1 = 0,
};

const cases = [_]Case{
    .{ .deck = ag161, .resistor = "rs", .gates = &.{"m1"} },
    .{ .deck = ag265, .resistor = "r1", .gates = &.{"m1"} },
    .{ .deck = ag341, .resistor = "rs", .gates = &.{"m9"} },
    .{ .deck = ag477, .resistor = "rs", .gates = &.{ "m1", "m2", "m4" } },
    .{ .deck = ag1082, .resistor = "rs", .source = "vs", .gates = &.{"m2"} },
    .{ .deck = ams361, .resistor = "rs", .gates = &.{"m1"}, .r_junction = 1 },
    .{ .deck = ams585, .resistor = "rs", .gates = &.{"m1"}, .r_junction = 1 },
    .{ .deck = ams401, .resistor = "rs", .gates = &.{"m1"}, .r_junction = 1 },
    .{ .deck = ams604, .resistor = "r1", .gates = &.{"m1"}, .r_junction = 1 },
};

// ---- private ----

fn terminal(p: *const np.Placed, name: []const u8, index: u32) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + index;
}

fn pin(p: *const np.Placed, name: []const u8, index: u32) np.Pt {
    return p.pin_xy[terminal(p, name, index)];
}

fn straightGate(p: *const np.Placed, from: usize, to: usize) bool {
    const a, const b = .{ p.pin_xy[from], p.pin_xy[to] };
    if (a.y != b.y or p.pin_net[from] != p.pin_net[to]) return false;
    var lo = a.x;
    var hi = a.x;
    // Merge only physical horizontal intervals touching the reached span.
    // A pass that changes it consumes another segment; labels add nothing.
    for (0..p.seg_pt.len) |_| {
        var changed = false;
        var segments = p.segments(p.pin_net[from]);
        while (segments.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |c, d| {
            if (c.y != a.y or d.y != a.y) continue;
            const left, const right = .{ @min(c.x, d.x), @max(c.x, d.x) };
            if (left > hi or right < lo) continue;
            changed = changed or left < lo or right > hi;
            lo = @min(lo, left);
            hi = @max(hi, right);
        };
        if (lo <= b.x and b.x <= hi) return true;
        if (!changed) return false;
    }
    return false;
}

fn expectBranch(p: *const np.Placed, case: Case) !void {
    const ri = terminal(p, case.resistor, case.r_junction);
    const rg = terminal(p, case.resistor, 1 - case.r_junction);
    const vi = terminal(p, case.source, case.v_signal);
    const vg = terminal(p, case.source, 1 - case.v_signal);
    const a, const b = .{ p.pin_xy[ri], p.pin_xy[rg] };
    const signal, const ground = .{ p.pin_xy[vi], p.pin_xy[vg] };
    try testing.expectEqual(a.y, b.y);
    try testing.expect(a.x != b.x);
    try testing.expectEqual(signal.x, ground.x);
    try testing.expect(signal.y < ground.y);
    try testing.expect(signal.y >= a.y);
    try testing.expect(try ink.connected(testing.allocator, p, &.{ ri, vi }));
    // AG477 has three driven gates and two source-row anchors. The same
    // candidate must supply row, interval and ink; independent existential
    // checks could incorrectly use three different gates.
    const anchored = for (case.gates) |name| {
        const gi = terminal(p, name, 1);
        const g = p.pin_xy[gi];
        if (g.y != a.y) continue;
        const middle2 = @as(i64, a.x) + b.x;
        if (middle2 <= 2 * @as(i64, @min(signal.x, g.x)) or middle2 >= 2 * @as(i64, @max(signal.x, g.x))) continue;
        if (straightGate(p, rg, gi) and try ink.connected(testing.allocator, p, &.{ rg, gi })) break true;
    } else false;
    if (!anchored) {
        std.debug.print("input branch pins: R={any}..{any}, V={any}..{any}\n", .{ a, b, signal, ground });
        for (case.gates) |name| {
            const gi = terminal(p, name, 1);
            std.debug.print("gate {s}={any}, straight={}, continuous={}\n", .{ name, p.pin_xy[gi], straightGate(p, rg, gi), try ink.connected(testing.allocator, p, &.{ rg, gi }) });
        }
        var segments = p.segments(p.pin_net[rg]);
        while (segments.next()) |poly| std.debug.print("gate wire {any}\n", .{poly});
        for (p.labels) |label| if (label.net == p.pin_net[rg]) std.debug.print("gate label {any}\n", .{label});
    }
    try testing.expect(anchored);
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
    for (try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib)) |v| {
        try testing.expectEqual(np.hints.State.honoured, v.state);
    }
}

test "input resistors: complete source legs align with a physically connected MOS gate" {
    // Source lead examples: AG161 RS(-120,0)..(-80,0), M1.G(-20,0),
    // Vin(+)=(-150,20), Vin(-)=(-150,60). AMS585's signal starts only 10
    // source units below R. The inequalities allow source-level equality.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for (cases) |case| for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("input branch: {s}, compact={}\n", .{ case.deck[0..std.mem.indexOfScalar(u8, case.deck, '\n').?], compact });
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{case.deck}, null);
        defer p.deinit();
        try expectBranch(&p, case);
        try expectElectrical(&p, lib);
    };
}

test "input resistors: resistor and source pin reversal retain semantic source and gate ends" {
    // Reversing V also negates its value, preserving the ideal source.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const r = try std.mem.replaceOwned(u8, gpa, ag161, "RS net0 X", "RS X net0");
    defer gpa.free(r);
    const v = try std.mem.replaceOwned(u8, gpa, ag161, "Vin net0 VSS DC 1", "Vin VSS net0 DC -1");
    defer gpa.free(v);
    const both = try std.mem.replaceOwned(u8, gpa, r, "Vin net0 VSS DC 1", "Vin VSS net0 DC -1");
    defer gpa.free(both);
    const reversed = [_]Case{
        .{ .deck = r, .resistor = "rs", .gates = &.{"m1"}, .r_junction = 1 },
        .{ .deck = v, .resistor = "rs", .gates = &.{"m1"}, .v_signal = 1 },
        .{ .deck = both, .resistor = "rs", .gates = &.{"m1"}, .r_junction = 1, .v_signal = 1 },
    };
    for (reversed) |case| for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("input reversal: r_junction={d}, v_signal={d}, compact={}\n", .{ case.r_junction, case.v_signal, compact });
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{case.deck}, null);
        defer p.deinit();
        try expectBranch(&p, case);
        try expectElectrical(&p, lib);
    };
}

test "input resistors: shifted caller frames align actual leads instead of device origins" {
    // The source branch inequalities still apply when each caller glyph
    // moves its leads off the origin and doubles its principal span.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const r = try lib.register(.{ .name = "input_offset_res", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -50, .y = 15 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 30, .y = 15 }, .side = .right },
    } });
    const v = try lib.register(.{ .name = "input_offset_source", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -40, .y = -10 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 40, .y = -10 }, .side = .right },
    } });
    const m = try lib.register(.{
        .name = "input_offset_mos",
        .terminals = &.{
            .{ .name = "d", .at = .{ .x = 50, .y = 15 }, .side = .right },
            .{ .name = "g", .at = .{ .x = 10, .y = -15 }, .side = .up },
            .{ .name = "s", .at = .{ .x = -30, .y = 15 }, .side = .left },
        },
        .draw = &.{
            // A caller frame needs a compatible body too. The automatic box
            // extends above this gate and buries it; these explicit strokes
            // leave the actual G terminal on its outward boundary.
            .{ .line = .{ .a = .{ .x = -30, .y = 15 }, .b = .{ .x = 50, .y = 15 } } },
            .{ .line = .{ .a = .{ .x = -10, .y = 0 }, .b = .{ .x = 30, .y = 0 } } },
            .{ .line = .{ .a = .{ .x = 10, .y = -15 }, .b = .{ .x = 10, .y = 0 } } },
        },
    });
    const src = ag161 ++ "*@ class rs input_offset_res\n*@ class vin input_offset_source\n*@ class m1 input_offset_mos\n";
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("input custom frames: compact={}\n", .{compact});
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        try expectBranch(&p, cases[0]);
        for ([_][]const u8{ "rs", "vin", "m1" }, [_]np.ClassId{ r, v, m }) |name, class| {
            const d = np.checks.deviceIn(&p, name).?;
            try testing.expectEqual(class, p.dev_class[d]);
        }
        const rd = np.checks.deviceIn(&p, "rs").?;
        const vd = np.checks.deviceIn(&p, "vin").?;
        try testing.expectEqual(@as(u32, 80), @abs(pin(&p, "rs", 0).x - pin(&p, "rs", 1).x));
        try testing.expectEqual(@as(u32, 80), @abs(pin(&p, "vin", 0).y - pin(&p, "vin", 1).y));
        try testing.expect(pin(&p, "rs", 0).y != p.dev_pos[rd].y);
        try testing.expect(pin(&p, "vin", 0).x != p.dev_pos[vd].x);
        try expectElectrical(&p, lib);
    }
}

test "input resistors: BJT-base and MOS-source counterexamples retain upright resistors" {
    // These are actual source axes, not the negation of the new selector.
    // AG637 R1 feeds Q1's base; AMS114 RS feeds M1's source.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const negative = [_]struct { []const u8, []const u8 }{ .{ ag637, "r1" }, .{ ams114, "rs" } };
    for (negative) |case| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{case[0]}, null);
        defer p.deinit();
        const a, const b = .{ pin(&p, case[1], 0), pin(&p, case[1], 1) };
        try testing.expectEqual(a.x, b.x);
        try testing.expect(a.y != b.y);
        try expectElectrical(&p, lib);
    };
}

test "input resistors: nonprivate junctions and nonground returns keep ordinary placement" {
    // Conservative admission oracle: these full-DUT mutations all have
    // upright RS in the frozen iteration12 native baseline. Gate and body
    // pins count against privacy even though they are not DC paths.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const floating = try std.mem.replaceOwned(u8, gpa, ag161, "Vin net0 VSS", "Vin net0 return");
    defer gpa.free(floating);
    const supply = try std.mem.replaceOwned(u8, gpa, ag161, "Vin net0 VSS", "Vin net0 VDD");
    defer gpa.free(supply);
    const body = try std.mem.replaceOwned(u8, gpa, ag161, "M1 VDD X Vout VSS", "M1 VDD X Vout net0");
    defer gpa.free(body);
    for ([_][]const u8{ floating, supply, body, ag161 ++ "CEXTRA net0 VSS 1p\n", ag161 ++ "MEXTRA spare net0 VSS VSS nch\n" }) |src| {
        var p = try np.place(gpa, &.default, lib, &.{src}, null);
        defer p.deinit();
        try testing.expectEqual(pin(&p, "rs", 0).x, pin(&p, "rs", 1).x);
        try expectElectrical(&p, lib);
    }
}

test "input resistors: explicit forms faces cells and origins retain precedence" {
    // The caller deliberately contradicts the inferred source branch.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const requests = [_][]const u8{
        "*@ upright rs\n",
        "*@ upright rs\n*@ face rs a down\n",
        "*@ bridge vin\n",
        "*@ cell rs -8 -6\n*@ cell vin -8 -2\n",
        "*@ at rs -10 -10 r90\n",
        "*@ at vin -10 -10 r0\n",
    };
    for (requests, 0..) |request, i| for ([_]bool{ false, true }) |compact| {
        const src = try std.fmt.allocPrint(gpa, "{s}{s}", .{ ag161, request });
        defer gpa.free(src);
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        switch (i) {
            0 => try testing.expectEqual(pin(&p, "rs", 0).x, pin(&p, "rs", 1).x),
            1 => try testing.expect(pin(&p, "rs", 0).y > pin(&p, "rs", 1).y),
            2 => try testing.expectEqual(pin(&p, "vin", 0).y, pin(&p, "vin", 1).y),
            3 => {
                const r = np.checks.deviceIn(&p, "rs").?;
                const v = np.checks.deviceIn(&p, "vin").?;
                try testing.expect(p.dev_pos[r].y < p.dev_pos[v].y);
            },
            4, 5 => {
                const d = np.checks.deviceIn(&p, if (i == 4) "rs" else "vin").?;
                try testing.expectEqual(np.Pt{ .x = -400, .y = -400 }, p.dev_pos[d]);
                if (i == 4) try testing.expectEqual(pin(&p, "rs", 0).x, pin(&p, "rs", 1).x) else try testing.expectEqual(pin(&p, "vin", 0).y, pin(&p, "vin", 1).y);
            },
            else => unreachable,
        }
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    };
}

test "input resistors: straight gate oracle rejects detours named gaps and other nets" {
    // Literal conductor geometry, independent of the placement algorithm.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const ports = [_]np.ClassId{ lib.findRole(.input_port).?, lib.findRole(.input_port).? };
    var p: np.Placed = .{
        .arena = undefined,
        .dev_name = &.{ "", "" },
        .dev_class = &ports,
        .dev_value = &.{ "", "" },
        .dev_pos = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 } },
        .dev_orient = &.{ .{}, .{} },
        .dev_pin0 = &.{ 0, 1, 2 },
        .pin_net = &.{ 0, 0 },
        .pin_xy = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 } },
        .net_name = &.{ "gate", "other" },
        .net_seg = &.{ 0, 2, 2 },
        .seg_pt = &.{ 0, 2, 4 },
        .wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 5, .y = 0 }, .{ .x = 5, .y = 0 }, .{ .x = 10, .y = 0 } },
        .junctions = &.{},
        .labels = &.{ .{ .net = 0, .at = .{ .x = 0, .y = 0 }, .side = .left }, .{ .net = 0, .at = .{ .x = 10, .y = 0 }, .side = .right } },
        .no_connects = &.{},
    };
    // Borrowed literal storage: there is no arena to deinit.
    try testing.expect(straightGate(&p, 0, 1));
    p.wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 0 }, .{ .x = 6, .y = 0 }, .{ .x = 10, .y = 0 } };
    try testing.expect(!straightGate(&p, 0, 1));
    p.net_seg = &.{ 0, 2, 3 };
    p.seg_pt = &.{ 0, 2, 4, 6 };
    p.wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 0 }, .{ .x = 6, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 4, .y = 0 }, .{ .x = 6, .y = 0 } };
    try testing.expect(!straightGate(&p, 0, 1));
    p.net_seg = &.{ 0, 3, 3 };
    p.seg_pt = &.{ 0, 2, 4, 8 };
    p.wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 0 }, .{ .x = 6, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 4, .y = 0 }, .{ .x = 4, .y = 5 }, .{ .x = 6, .y = 5 }, .{ .x = 6, .y = 0 } };
    try testing.expect(try ink.connected(testing.allocator, &p, &.{ 0, 1 }));
    try testing.expect(!straightGate(&p, 0, 1));
    p.pin_xy = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 1 } };
    try testing.expect(!straightGate(&p, 0, 1));
}
