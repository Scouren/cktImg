//! Source converter DUTs -> terminal geometry and actual local wire continuity.
//! Cites: AG1191/1309 SVG leads and conductor ink, independently audited in
//! docs/research/converter-loops.md (145 groups, 3,335 actual lead endpoints).
//! Human Rules:
//! - The flying and floating output caps close a lower loop around the
//!   main path. Their electrical upper ends, lower MOS/diode placement,
//!   and continuous local wires must survive both compaction and shelving.
//! - Gate direction, exact lower-row equality, and CO/COP ordering vary
//!   in the source; no universal assertion below fixes those choices.
//! - Caller forms, faces, cells, origins, net labels and custom symbol
//!   frames retain precedence. No rejected topology implies a cap axis.
//! Selector boundary cases have independent source-audit checks and
//! private production tests in power_loops.zig, without a shipped API.
//!
//! Contents: full source fixtures, private wire/terminal checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

// Full DUT bodies and the CLI's inferred external roles, copied from the
// existing reservoir fixtures. Hidden EA/ISR contents do not affect their
// block drawing; their complete declared port lists remain intact.
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

const ag1309 =
    \\AG1309 reservoir fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt EA VDD VSS OUT INN INP VX2
    \\.ends
    \\.subckt ISR VDD VSS VS VCTRL VB2 IOUT
    \\.ends
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 VCONT2 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VX2 VCONT3 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 VP VCONT5 VX3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VCONT4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net0 VCONT1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\X1 VDD VSS net1 VFP1 VREF VX2 EA
    \\X2 VDD VSS net0 net1 VB2 VX1 ISR
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\*@ weak role vcont4 input
    \\*@ weak role vcont5 input
    \\*@ weak role vp output
    \\
;

// AG1316's complete DUT and the declared EA1 boundary. VX2 is terminal 4,
// separate from the selected M2/CFLY/D1 loop terminals. As with AG1309,
// hidden block internals do not change the block's drawing.
const ag1316 =
    \\AG1316 remote loop terminal fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt EA1 VDD VSS VFP1 VREF VX2 VB1 VISR VX1
    \\.ends
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 VS1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VX2 VS2 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 VP VS3 VX3 VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VS4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net0 VS5 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\X1 VDD VSS VFP1 VREF VX2 VB1 net0 VX1 EA1
    \\*@ weak role vs1 input
    \\*@ weak role vs2 input
    \\*@ weak role vs3 input
    \\*@ weak role vs4 input
    \\*@ weak role vs5 input
    \\*@ weak role vp output
    \\
;

const Ink = struct { a: np.Pt, b: np.Pt, net: u32 };

// ---- private ----

fn pinIndex(p: *const np.Placed, name: []const u8, terminal: u32) usize {
    const d = np.checks.deviceIn(p, name).?;
    return p.dev_pin0[d] + terminal;
}

fn pin(p: *const np.Placed, name: []const u8, terminal: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.dev_pin0[d] + terminal];
}

fn pointIndex(points: *std.ArrayList(np.Pt), a: std.mem.Allocator, point: np.Pt) !usize {
    for (points.items, 0..) |old, i| if (point.eql(old)) return i;
    try points.append(a, point);
    return points.items.len - 1;
}

// A shortest wire path from the first terminal to each other one. Only
// those paths enter the crossing certificate: remote control branches
// on the same electrical nets are deliberately outside this oracle.
fn localTree(p: *const np.Placed, terminals: []const usize, out: *std.ArrayList(Ink)) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const net = p.pin_net[terminals[0]];
    var points: std.ArrayList(np.Pt) = .empty;
    const targets = try a.alloc(usize, terminals.len);
    for (terminals, targets) |t, *target| target.* = try pointIndex(&points, a, p.pin_xy[t]);
    var edges: std.ArrayList(Ink) = .empty;
    var it = p.segments(net);
    while (it.next()) |poly| {
        for (poly) |point| _ = try pointIndex(&points, a, point);
        for (poly[0 .. poly.len - 1], poly[1..]) |start, end| try edges.append(a, .{ .a = start, .b = end, .net = net });
    }
    const absent = std.math.maxInt(usize);
    const previous = try a.alloc(usize, points.items.len);
    @memset(previous, absent);
    const queue = try a.alloc(usize, points.items.len);
    previous[0] = 0;
    queue[0] = 0;
    var head: usize = 0;
    var tail: usize = 1;
    for (0..points.items.len) |_| {
        if (head == tail) break;
        const current = queue[head];
        head += 1;
        for (points.items, 0..) |point, next| {
            if (previous[next] != absent) continue;
            const adjacent = for (edges.items) |edge| {
                if (ink.onPolyline(&.{ edge.a, edge.b }, point) and ink.onPolyline(&.{ edge.a, edge.b }, points.items[current])) break true;
            } else false;
            if (!adjacent) continue;
            previous[next] = current;
            queue[tail] = next;
            tail += 1;
        }
    }
    for (targets[1..]) |target| {
        var current = target;
        for (0..points.items.len) |_| {
            if (current == 0) break;
            try testing.expect(previous[current] != absent);
            const before = previous[current];
            try out.append(testing.allocator, .{ .a = points.items[current], .b = points.items[before], .net = net });
            current = before;
        }
        try testing.expectEqual(@as(usize, 0), current);
    }
}

fn crosses(a: Ink, b: Ink) bool {
    const h, const v = if (a.a.y == a.b.y) .{ a, b } else .{ b, a };
    return h.a.y == h.b.y and v.a.x == v.b.x and
        v.a.x > @min(h.a.x, h.b.x) and v.a.x < @max(h.a.x, h.b.x) and
        h.a.y > @min(v.a.y, v.b.y) and h.a.y < @max(v.a.y, v.b.y);
}

fn expectLoop(p: *const np.Placed, output_end: u32, upper_caps: [2]u32) !void {
    const first = pin(p, "m1", 0);
    const coil_a, const coil_b = .{ pin(p, "l1", 0), pin(p, "l1", 1) };
    const outer = pin(p, "m3", output_end);
    const direction: i64 = if (outer.x > first.x) 1 else -1;
    const fa, const fb = .{ pin(p, "cfly", upper_caps[0]), pin(p, "cfly", 1 - upper_caps[0]) };
    const oa, const ob = .{ pin(p, "co", upper_caps[1]), pin(p, "co", 1 - upper_caps[1]) };
    const low_d, const low_s = .{ pin(p, "m2", 0), pin(p, "m2", 2) };
    const da, const dk = .{ pin(p, "d1", 0), pin(p, "d1", 1) };
    const r1a, const r1b = .{ pin(p, "r1", 0), pin(p, "r1", 1) };
    const r2a, const r2b = .{ pin(p, "r2", 0), pin(p, "r2", 1) };
    // Both chosen sources have one main row. The nine source offset cases
    // are not a reason to change these two independent observed examples.
    for ([_]np.Pt{ first, pin(p, "m1", 2), coil_b, pin(p, "m3", 2 - output_end), outer }) |point| {
        try testing.expectEqual(coil_a.y, point.y);
    }
    try testing.expectEqual(fa.x, fb.x);
    try testing.expect(fa.y < fb.y and fa.y >= coil_a.y);
    try testing.expect(fa.x >= @min(first.x, coil_a.x) and fa.x <= @max(first.x, coil_a.x));
    try testing.expectEqual(low_d.y, low_s.y);
    try testing.expect(@min(low_d.y, low_s.y) > coil_a.y);
    try testing.expect(fb.y <= @min(low_d.y, low_s.y));
    try testing.expect((@as(i64, fa.x) - low_d.x) * direction >= 0);
    try testing.expectEqual(oa.x, ob.x);
    try testing.expect(oa.y < ob.y and oa.y >= coil_a.y);
    try testing.expect((@as(i64, oa.x) - outer.x) * direction >= 0);
    try testing.expectEqual(da.y, dk.y);
    try testing.expect(da.y > coil_a.y and da.y >= @max(fb.y, ob.y));
    const diode_x2 = @as(i64, da.x) + dk.x;
    try testing.expect(diode_x2 >= 2 * @as(i64, @min(fa.x, oa.x)) and diode_x2 <= 2 * @as(i64, @max(fa.x, oa.x)));
    try testing.expect((@as(i64, da.x) - dk.x) * direction > 0);
    for ([_]np.Pt{ r1b, r2a, r2b }) |point| try testing.expectEqual(r1a.x, point.x);
    try testing.expect(r1a.y < r1b.y and r1b.y <= r2a.y and r2a.y < r2b.y);
    try testing.expect(r2b.y <= da.y);
    try testing.expect((@as(i64, r1a.x) - outer.x) * direction >= 0);
}

fn expectLoopWires(p: *const np.Placed, output_end: u32, upper_caps: [2]u32) !void {
    // SPICE path indices are explicit; a shared MOS body net cannot be
    // mistaken for the actual output channel terminal (AG1329's case).
    const nets = [_][]const usize{
        &.{ pinIndex(p, "m1", 2), pinIndex(p, "m2", 2) },
        &.{ pinIndex(p, "m1", 0), pinIndex(p, "l1", 0), pinIndex(p, "cfly", upper_caps[0]) },
        &.{ pinIndex(p, "l1", 1), pinIndex(p, "m3", 2 - output_end) },
        &.{ pinIndex(p, "m3", output_end), pinIndex(p, "co", upper_caps[1]), pinIndex(p, "cop", 0), pinIndex(p, "r1", 0) },
        &.{ pinIndex(p, "m2", 0), pinIndex(p, "cfly", 1 - upper_caps[0]), pinIndex(p, "d1", 1) },
        &.{ pinIndex(p, "co", 1 - upper_caps[1]), pinIndex(p, "d1", 0) },
        &.{ pinIndex(p, "r1", 1), pinIndex(p, "r2", 0) },
    };
    var tree: std.ArrayList(Ink) = .empty;
    defer tree.deinit(testing.allocator);
    for (nets) |terminals| {
        try testing.expect(try ink.connected(testing.allocator, p, terminals));
        try localTree(p, terminals, &tree);
    }
    // All 145 audited sources have zero crossings between these seven
    // local spanning trees. Crossing a remote control wire is not tested.
    for (tree.items, 0..) |a, i| for (tree.items[i + 1 ..]) |b| {
        if (a.net != b.net) try testing.expect(!crosses(a, b));
    };
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

fn expectRightPort(p: *const np.Placed, lib: *const np.Library) !void {
    const net = p.pin_net[pinIndex(p, "m3", 0)];
    var right: i32 = std.math.minInt(i32);
    for (p.dev_name, 0..) |name, d| {
        if (name.len == 0) continue;
        for (p.dev_pin0[d]..p.dev_pin0[d + 1]) |t| {
            if (p.pin_net[t] == net) right = @max(right, p.pin_xy[t].x);
        }
    }
    const outside = for (p.dev_class, 0..) |class, d| {
        if (p.dev_name[d].len != 0 or class != lib.findRole(.output_port).?) continue;
        const lo, const hi = p.pinRange(d);
        if (hi - lo == 1 and p.pin_net[lo] == net and p.pin_xy[lo].x > right) break true;
    } else false;
    try testing.expect(outside);
}

test "converter loops: source geometry survives compaction and shelving" {
    // Actual AG1191 leads: main y=340; CFLY=(160,410)..(160,450);
    // M2 D/S y=530; D1 K/A=(420,530)/(460,530); CO=(530,420)..(530,460).
    // R1=(460,370)..(460,410), R2=(460,430)..(460,470).
    // Actual AG1309: main y=80; CFLY=(140,130)..(140,170); M2 y=220;
    // D1 K/A=(290,220)/(330,220); CO=(460,80)..(460,120).
    // Its output cap may start level with main. All seven local nets in
    // both SVGs have continuous Manhattan ink; net labels are no substitute.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{ ag1191, ag1309 }, [_]u32{ 2, 0 }) |src, output_end| {
        for ([_]u32{ 0, 8 }) |shelf| for ([_]bool{ false, true }) |compact| {
            var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = shelf } }, lib, &.{src}, null);
            defer p.deinit();
            try expectLoop(&p, output_end, .{ 0, 0 });
            try expectElectrical(&p, lib);
        };
    }
}

test "converter loops: source wire continuity and crossing certificate survive compaction and shelving" {
    // A separate oracle/run ensures the geometry's first failure cannot
    // hide absent local wiring. Both source ink trees have zero crossings.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{ ag1191, ag1309 }, [_]u32{ 2, 0 }) |src, output_end| {
        for ([_]u32{ 0, 8 }) |shelf| for ([_]bool{ false, true }) |compact| {
            var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = shelf } }, lib, &.{src}, null);
            defer p.deinit();
            try expectLoopWires(&p, output_end, .{ 0, 0 });
            try expectElectrical(&p, lib);
        };
    }
}

test "converter loops: capacitor pin order and MOS body aliases do not change electrical ends" {
    // Metamorphic oracle: swapping ideal capacitor card ends preserves
    // their circuit; MOS body on an existing channel net is not a path pin.
    // The body alias mirrors the real AG1329 output PMOS's VP body.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const reversed = try std.mem.replaceOwned(u8, gpa, ag1309, "CFLY VX1 VX2", "CFLY VX2 VX1");
    defer gpa.free(reversed);
    const both = try std.mem.replaceOwned(u8, gpa, reversed, "CO VP VN", "CO VN VP");
    defer gpa.free(both);
    const body = try std.mem.replaceOwned(u8, gpa, both, "M3 VP VCONT5 VX3 VDD", "M3 VP VCONT5 VX3 VP");
    defer gpa.free(body);
    var p = try np.place(gpa, &.{ .layout = .{ .compact = true, .shelf = 8 } }, lib, &.{body}, null);
    defer p.deinit();
    try expectLoop(&p, 0, .{ 1, 1 });
    try expectLoopWires(&p, 0, .{ 1, 1 });
    try expectElectrical(&p, lib);
}

test "converter loops: shifted tall capacitors preserve actual terminal bounds" {
    // Source inequalities use outer leads, not origins. In this caller
    // frame, both electrical pins are offset from the origin's column
    // after rotation, and their vertical span doubles from 40 to 80.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const custom = try lib.register(.{ .name = "loop_tall_cap", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -50, .y = 15 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 30, .y = 15 }, .side = .right },
    } });
    const src = ag1309 ++ "*@ class cfly loop_tall_cap\n*@ class co loop_tall_cap\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{src}, null);
        defer p.deinit();
        try expectLoop(&p, 0, .{ 0, 0 });
        try expectLoopWires(&p, 0, .{ 0, 0 });
        for ([_][]const u8{ "cfly", "co" }) |name| {
            const d = np.checks.deviceIn(&p, name).?;
            const a, const b = .{ pin(&p, name, 0), pin(&p, name, 1) };
            try testing.expectEqual(custom, p.dev_class[d]);
            try testing.expectEqual(@as(u32, 80), @abs(a.y - b.y));
            try testing.expect(a.x != p.dev_pos[d].x);
        }
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    }
}

test "converter loops: explicit form face cell and origin requests retain precedence" {
    // Caller oracles deliberately disagree with the inferred loop. These
    // are precedence tests, not experiments establishing a default layout.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const requests = [_][]const u8{
        "*@ upright m2\n",
        "*@ upright d1\n",
        "*@ upright cfly\n*@ face cfly a down\n",
        "*@ bridge co\n",
        "*@ cell co -8 -6\n*@ cell l1 -6 -2\n",
        "*@ at cfly -10 -10 r0\n",
    };
    for (requests, 0..) |request, i| for ([_]bool{ false, true }) |compact| {
        const src = try std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ ag1309, request });
        defer testing.allocator.free(src);
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        switch (i) {
            0 => try testing.expectEqual(pin(&p, "m2", 0).x, pin(&p, "m2", 2).x),
            1 => try testing.expectEqual(pin(&p, "d1", 0).x, pin(&p, "d1", 1).x),
            2 => try testing.expect(pin(&p, "cfly", 0).y > pin(&p, "cfly", 1).y),
            3 => try testing.expectEqual(pin(&p, "co", 0).y, pin(&p, "co", 1).y),
            4 => try testing.expect(p.dev_pos[np.checks.deviceIn(&p, "co").?].y < p.dev_pos[np.checks.deviceIn(&p, "l1").?].y),
            5 => {
                const d = np.checks.deviceIn(&p, "cfly").?;
                try testing.expectEqual(np.Pt{ .x = -400, .y = -400 }, p.dev_pos[d]);
                try testing.expectEqual(pin(&p, "cfly", 0).y, pin(&p, "cfly", 1).y);
            },
            else => unreachable,
        }
        try expectHonoured(src, &p, lib);
        try expectElectrical(&p, lib);
    };
}

test "converter loops: an output port stays beyond the whole seeded output bus" {
    // AG1309 already declares VP's output role. Its four selected output
    // pins must keep their local tree, while a requested right port stands
    // beyond every output pin, not at the internal M3 tree anchor.
    const src = ag1309 ++ "*@ port vp right\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{src}, null);
        defer p.deinit();
        try expectHonoured(src, &p, lib);
        try expectRightPort(&p, lib);
        try expectLoop(&p, 0, .{ 0, 0 });
        try expectLoopWires(&p, 0, .{ 0, 0 });
        try expectElectrical(&p, lib);
    }
}

test "converter loops: an outside output pin cannot hide the local output extent" {
    // A single output-to-ground load creates neither a second reservoir
    // nor a divider. Its explicit cell is outside the selected group, to
    // the left; the right port still belongs beyond CO/COP/R1's true pins.
    const src = ag1309 ++ "RLOAD VP VSS 10k\n*@ cell rload -8 -6\n*@ port vp right\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{src}, null);
        defer p.deinit();
        try testing.expect(pin(&p, "rload", 0).x < @min(pin(&p, "co", 0).x, pin(&p, "cop", 0).x));
        try expectRightPort(&p, lib);
        try expectHonoured(src, &p, lib);
        try expectLoop(&p, 0, .{ 0, 0 });
        try expectLoopWires(&p, 0, .{ 0, 0 });
        try expectElectrical(&p, lib);
    }
}

test "converter loops: a remote block terminal stays connected to the local loop" {
    // Oracle: the literal DUT connects X1 terminal 4 and M2 drain to VX2.
    // Iteration12 kept the three local VX2 terminals wired but left X1's
    // real pin (490,230) isolated: split_net(vx2, 2). A remote branch may
    // use labels; the netlister certificate must still join every pin.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1316}, null);
        defer p.deinit();
        try testing.expectEqual(p.pin_net[pinIndex(&p, "m2", 0)], p.pin_net[pinIndex(&p, "x1", 4)]);
        try expectLoopWires(&p, 0, .{ 0, 0 });
        try expectElectrical(&p, lib);
    }
}

test "converter loops: an explicit local net label wins over continuous loop wiring" {
    // An explicit label is allowed to break the human loop convention.
    // Labels may stand on short terminal stubs (Canvas.labelAt). Electrical
    // connectedness still passes; the complete ink-only loop must fail.
    const src = ag1309 ++ "*@ label vx2\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = true, .shelf = 8 } }, lib, &.{src}, null);
    defer p.deinit();
    const net = p.pin_net[pinIndex(&p, "m2", 0)];
    const named = for (p.labels) |label| {
        if (label.net == net) break true;
    } else false;
    try testing.expect(named);
    try testing.expect(!try ink.connected(testing.allocator, &p, &.{ pinIndex(&p, "m2", 0), pinIndex(&p, "cfly", 1), pinIndex(&p, "d1", 1) }));
    try expectHonoured(src, &p, lib);
    try expectElectrical(&p, lib);
}

test "converter loops: continuity oracle distinguishes a T junction from named gaps" {
    // Independent literal drawings: two disconnected input ports, each
    // labelled and wired to a stub, have electrical identity but no joining
    // ink. Filling the gap with another net must not connect this one.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const ports = [_]np.ClassId{ lib.findRole(.input_port).?, lib.findRole(.input_port).? };
    var p: np.Placed = .{
        .arena = undefined,
        .dev_name = &.{ "", "" },
        .dev_class = &ports,
        .dev_value = &.{ "", "" },
        .dev_pos = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 10 } },
        .dev_orient = &.{ .{}, .{} },
        .dev_pin0 = &.{ 0, 1, 2 },
        .pin_net = &.{ 0, 0 },
        .pin_xy = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 10 } },
        .net_name = &.{ "input", "other" },
        .net_seg = &.{ 0, 2, 3 },
        .seg_pt = &.{ 0, 2, 4, 6 },
        .wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 10, .y = 1 }, .{ .x = 10, .y = 10 }, .{ .x = 10, .y = 0 }, .{ .x = 10, .y = 1 } },
        .junctions = &.{},
        .labels = &.{ .{ .net = 0, .at = .{ .x = 0, .y = 0 }, .side = .left }, .{ .net = 0, .at = .{ .x = 10, .y = 10 }, .side = .right } },
        .no_connects = &.{},
    };
    try support.expectConnected(&p, lib);
    try testing.expect(!try ink.connected(testing.allocator, &p, &.{ 0, 1 }));
    // No deinit: every slice here is borrowed literal data, not an arena.
    // A genuine T touches the first wire's interior, not a nearest vertex.
    p.net_seg = &.{ 0, 2, 2 };
    p.seg_pt = &.{ 0, 2, 4 };
    p.wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 5, .y = 0 }, .{ .x = 5, .y = 10 } };
    p.pin_xy = &.{ .{ .x = 0, .y = 0 }, .{ .x = 5, .y = 10 } };
    p.dev_pos = p.pin_xy;
    p.labels = &.{};
    try testing.expect(try ink.connected(testing.allocator, &p, &.{ 0, 1 }));
    // A remote spur on this same net crosses another wire, but is not on
    // either terminal's connecting path and must not enter the local tree.
    p.net_seg = &.{ 0, 3, 3 };
    p.seg_pt = &.{ 0, 2, 4, 6 };
    p.wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 5, .y = 0 }, .{ .x = 5, .y = 10 }, .{ .x = 5, .y = 10 }, .{ .x = 5, .y = 30 } };
    const remote: Ink = .{ .a = .{ .x = 1, .y = 20 }, .b = .{ .x = 9, .y = 20 }, .net = 1 };
    try testing.expect(crosses(remote, .{ .a = .{ .x = 5, .y = 10 }, .b = .{ .x = 5, .y = 30 }, .net = 0 }));
    var tree: std.ArrayList(Ink) = .empty;
    defer tree.deinit(testing.allocator);
    try localTree(&p, &.{ 0, 1 }, &tree);
    for (tree.items) |edge| try testing.expect(!crosses(remote, edge));
    // Mutation: now both crossing strokes are actual terminal-to-terminal
    // paths on different nets. Neither tree may discard its crossing.
    p.net_seg = &.{ 0, 1, 2 };
    p.seg_pt = &.{ 0, 2, 4 };
    p.wire_pts = &.{ .{ .x = 0, .y = 5 }, .{ .x = 10, .y = 5 }, .{ .x = 5, .y = 0 }, .{ .x = 5, .y = 10 } };
    p.pin_xy = p.wire_pts[0..2];
    p.dev_pos = p.pin_xy;
    tree.clearRetainingCapacity();
    try localTree(&p, &.{ 0, 1 }, &tree);
    p.pin_net = &.{ 1, 1 };
    p.pin_xy = p.wire_pts[2..4];
    p.dev_pos = p.pin_xy;
    try localTree(&p, &.{ 0, 1 }, &tree);
    try testing.expectEqual(@as(usize, 2), tree.items.len);
    try testing.expect(crosses(tree.items[0], tree.items[1]));
    try testing.expect(crosses(tree.items[1], tree.items[0]));
    const reversed: Ink = .{ .a = tree.items[1].b, .b = tree.items[1].a, .net = 1 };
    try testing.expect(crosses(tree.items[0], reversed));
    const outside: Ink = .{ .a = .{ .x = 11, .y = 0 }, .b = .{ .x = 11, .y = 10 }, .net = 1 };
    try testing.expect(!crosses(tree.items[0], outside));
    // The identical strokes on one net, without a vertex at their proper
    // crossing, still do not supply an endpoint/T connection between them.
    p.net_seg = &.{ 0, 2, 2 };
    p.pin_net = &.{ 0, 0 };
    p.pin_xy = &.{ .{ .x = 0, .y = 5 }, .{ .x = 5, .y = 10 } };
    p.dev_pos = p.pin_xy;
    try testing.expect(!try ink.connected(testing.allocator, &p, &.{ 0, 1 }));
}
