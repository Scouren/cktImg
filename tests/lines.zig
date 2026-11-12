//! Steering rungs 1 and 2 (docs/research/vocabulary.md): each verb's effect
//! on the drawing, read from the drawing, and each refusal's verdict, its
//! code and the lines that blocked it. Oracles: the finished `Placed` (a
//! device's place, a pin's side, a net's names and symbols), and the
//! guarantees every drawing keeps.
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");

const ota =
    \\Five-transistor OTA
    \\.model nch nmos level=1
    \\.model pch pmos level=1
    \\Vdd vdd 0 1.8
    \\Vin1 vin1 0 dc 0.9 ac 1
    \\Vin2 vin2 0 dc 0.9
    \\Vb vb 0 0.7
    \\M1 f vin1 p 0 nch
    \\M2 vout vin2 p 0 nch
    \\M3 f f vdd vdd pch
    \\M4 vout f vdd vdd pch
    \\M5 p vb 0 0 nch
    \\
;

const Run = struct {
    nl: np.netlist.Netlist,
    roles: []np.Role,
    st: np.schematic.structure.Structure,
    sk: np.schematic.skeleton.Skeleton,
    p: np.Placed,
    v: []const np.hints.Verdict,

    /// The verdict of the line whose text is `text`.
    fn verdict(r: *const Run, text: []const u8) np.hints.Verdict {
        for (r.nl.hints, r.v) |h, v| if (std.mem.eql(u8, h.text, text)) return v;
        unreachable;
    }

    /// The deck line number of the line whose text is `text`.
    fn line(r: *const Run, text: []const u8) u32 {
        for (r.nl.hints, 0..) |h, i| if (std.mem.eql(u8, h.text, text)) return @intCast(i);
        unreachable;
    }

    fn device(r: *const Run, name: []const u8) usize {
        for (r.p.dev_name, 0..) |n, d| if (std.mem.eql(u8, n, name)) return d;
        unreachable;
    }

    fn at(r: *const Run, name: []const u8) np.Pt {
        return r.p.dev_pos[r.device(name)];
    }

    /// Pin `k` of device `name`.
    fn pin(r: *const Run, name: []const u8, k: u32) np.Pt {
        return r.p.pin_xy[r.p.pinRange(r.device(name))[0] + k];
    }

    fn net(r: *const Run, name: []const u8) u32 {
        for (r.p.net_name, 0..) |n, k| if (std.mem.eql(u8, n, name)) return @intCast(k);
        unreachable;
    }

    /// The unnamed one-pin symbols (rails, ports) on net `name`.
    fn symbols(r: *const Run, name: []const u8) usize {
        const n = r.net(name);
        var count: usize = 0;
        for (0..r.p.deviceCount()) |d| {
            const a, const b = r.p.pinRange(d);
            if (r.p.dev_name[d].len == 0 and b - a == 1 and r.p.pin_net[a] == n) count += 1;
        }
        return count;
    }

    fn labelled(r: *const Run, name: []const u8) bool {
        const n = r.net(name);
        for (r.p.labels) |l| if (l.net == n) return true;
        return false;
    }
};

const Fixture = struct {
    arena_state: std.heap.ArenaAllocator,
    lib: *np.Library,

    fn init() !Fixture {
        return .{ .arena_state = .init(std.testing.allocator), .lib = try support.library(std.testing.allocator) };
    }
    fn deinit(f: *Fixture) void {
        support.freeLibrary(std.testing.allocator, f.lib);
        f.arena_state.deinit();
    }
    fn arena(f: *Fixture) std.mem.Allocator {
        return f.arena_state.allocator();
    }
};

// ---- private ----

/// `spice` with `lines` after its title, laid out and reported on; the
/// drawing's guarantees checked.
fn run(arena: std.mem.Allocator, lib: *np.Library, spice: []const u8, lines: []const u8) !Run {
    const at = std.mem.indexOfScalar(u8, spice, '\n').? + 1;
    const deck = try std.mem.concat(arena, u8, &.{ spice[0..at], lines, spice[at..] });
    var nl = try np.netlist.parse(arena, &.{deck}, null);
    const roles = try np.guessRoles(arena, &nl);
    const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
    const sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{});
    const s = try np.layout(arena, &nl, roles, lib, .{});
    const p = try np.Placed.init(arena, &s, &nl);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(std.testing.allocator, &p, true));
    try std.testing.expectEqual(0, try support.dots(std.testing.allocator, &p, true));
    const v = try np.report.verdicts(arena, &nl, roles, &st, &sk, &p, lib);
    return .{ .nl = nl, .roles = roles, .st = st, .sk = sk, .p = p, .v = v };
}

/// `v` drawing units in symbol units.
fn fu(v: i32, unit: i32) f64 {
    return @as(f64, @floatFromInt(v)) / @as(f64, @floatFromInt(unit));
}

fn expectState(v: np.hints.Verdict, state: np.hints.State, code: np.hints.Code) !void {
    if (v.state != state or v.code != code) std.debug.print("got {t} {t}\n", .{ v.state, v.code });
    try std.testing.expectEqual(state, v.state);
    try std.testing.expectEqual(code, v.code);
}

test "lines: above puts the tail above the pair; the later of two contradicting lines wins, the earlier blocked by it" {
    var f = try Fixture.init();
    defer f.deinit();
    const r = try run(f.arena(), f.lib, ota, "*@ above m1 m3\n*@ above m5 m1\n*@ above m3 m1\n");
    try std.testing.expect(r.at("m5").y < r.at("m1").y);
    try expectState(r.verdict("*@ above m5 m1"), .honoured, .ok);
    try expectState(r.verdict("*@ above m3 m1"), .honoured, .ok);
    const dropped = r.verdict("*@ above m1 m3");
    try expectState(dropped, .dropped, .cycle);
    try std.testing.expectEqualSlices(u32, &.{r.line("*@ above m3 m1")}, dropped.blocked_by);
    try std.testing.expectEqualSlices(bool, &.{true}, dropped.alone);
}

test "lines: a weak line gives way to a strong one" {
    var f = try Fixture.init();
    defer f.deinit();
    const r = try run(f.arena(), f.lib, ota, "*@ weak row m1 m3\n*@ above m3 m1\n");
    try expectState(r.verdict("*@ weak row m1 m3"), .dropped, .cycle);
    try std.testing.expect(r.at("m3").y < r.at("m1").y);
}

test "lines: row holds the pair and the tail level" {
    var f = try Fixture.init();
    defer f.deinit();
    const r = try run(f.arena(), f.lib, ota, "*@ row m3 m5\n");
    try expectState(r.verdict("*@ row m3 m5"), .honoured, .ok);
    try std.testing.expectEqual(r.at("m3").y, r.at("m5").y);
}

test "lines: face turns a gate, and its mate turns the mirror way" {
    var f = try Fixture.init();
    defer f.deinit();
    const base = try run(f.arena(), f.lib, ota, "");
    // The pair's gates face out: m1's toward the left of the two.
    const left = if (base.at("m1").x < base.at("m2").x) "m1" else "m2";
    const right = if (std.mem.eql(u8, left, "m1")) "m2" else "m1";
    const line = try std.fmt.allocPrint(f.arena(), "*@ face {s} g right\n", .{left});
    const r = try run(f.arena(), f.lib, ota, line);
    try expectState(r.verdict(line[0 .. line.len - 1]), .honoured, .ok);
    try std.testing.expect(r.pin(left, 1).x > r.at(left).x);
    try std.testing.expect(r.pin(right, 1).x < r.at(right).x);
}

test "lines: order splits a column the engine would make, and keeps the sides it asks" {
    var f = try Fixture.init();
    defer f.deinit();
    const base = try run(f.arena(), f.lib, ota, "");
    try std.testing.expectEqual(base.at("m3").x, base.at("m1").x);
    const r = try run(f.arena(), f.lib, ota, "*@ order m1 m3\n");
    try expectState(r.verdict("*@ order m1 m3"), .honoured, .ok);
    try std.testing.expect(r.at("m1").x < r.at("m3").x);
}

test "lines: order stands the bridges it names one after another in that order, and joins two lines on one bridge" {
    // Oracle: the line's own statement, read off the drawing: each device
    // named stands left of the next. A bridge was set between the nearest
    // columns its line names and no more, so two bridges named in a row
    // stood as the engine had them, and the line was reported `relaxed
    // not_drawn` (found hinting a hand-drawn circuit; `zig build fuzz` now
    // writes order lines of up to five names).
    var f = try Fixture.init();
    defer f.deinit();
    const deck =
        \\Two parts between two columns
        \\.model nch nmos level=1
        \\Vdd vdd 0 1.8
        \\R3 vdd a 1k
        \\R4 vdd b 1k
        \\M1 a in1 0 0 nch
        \\M2 b in2 0 0 nch
        \\R1 a b 1k
        \\C1 a b 1p
        \\
    ;
    for ([_][]const u8{ "*@ order m1 r1 c1 m2", "*@ order m1 c1 r1 m2", "*@ order c1 r1", "*@ order r1 c1" }) |text| {
        const r = try run(f.arena(), f.lib, deck, try std.mem.concat(f.arena(), u8, &.{ "*@ bridge r1 c1\n", text, "\n" }));
        try expectState(r.verdict(text), .honoured, .ok);
        var names = std.mem.tokenizeScalar(u8, text["*@ order ".len..], ' ');
        var last: ?i32 = null;
        while (names.next()) |name| {
            if (last) |x| try std.testing.expect(x < r.at(name).x);
            last = r.at(name).x;
        }
    }
    // Two lines on one bridge: the column the second names stands between
    // the columns the first does.
    const both = try run(f.arena(), f.lib, deck, "*@ bridge r1 c1\n*@ order m1 r1 c1 m2\n*@ order r1 r3 c1\n");
    try expectState(both.verdict("*@ order m1 r1 c1 m2"), .honoured, .ok);
    try expectState(both.verdict("*@ order r1 r3 c1"), .honoured, .ok);
    for ([_][2][]const u8{ .{ "m1", "r1" }, .{ "r1", "r3" }, .{ "r3", "c1" }, .{ "c1", "m2" } }) |pair| {
        try std.testing.expect(both.at(pair[0]).x < both.at(pair[1]).x);
    }
}

test "lines: symmetry off leaves no mates; symmetric refuses what no symmetry swaps; axis pins a device on it" {
    var f = try Fixture.init();
    defer f.deinit();
    const off = try run(f.arena(), f.lib, ota, "*@ symmetry off\n");
    try expectState(off.verdict("*@ symmetry off"), .honoured, .ok);
    for (off.st.device_mate) |m| try std.testing.expectEqual(np.schematic.structure.none, m);
    try std.testing.expectEqual(null, off.sk.axis2);
    // The 5T OTA has no exact symmetry (one load is diode-connected); a pair
    // with resistive loads has one, its tail on the axis.
    const pair =
        \\Resistive pair
        \\.model nch nmos level=1
        \\Vdd vdd 0 1.8
        \\Vin1 inp 0 dc 0.9 ac 1
        \\Vin2 inn 0 dc 0.9
        \\Vb vb 0 0.7
        \\R1 vdd outn 1k
        \\R2 vdd outp 1k
        \\M1 outn inp tail 0 nch
        \\M2 outp inn tail 0 nch
        \\M5 tail vb 0 0 nch
        \\
    ;
    const r = try run(f.arena(), f.lib, pair, "*@ symmetric m1 r1\n*@ axis m5\n*@ symmetric m1 m2\n");
    try expectState(r.verdict("*@ symmetric m1 r1"), .dropped, .asymmetric);
    try expectState(r.verdict("*@ axis m5"), .honoured, .ok);
    try expectState(r.verdict("*@ symmetric m1 m2"), .honoured, .ok);
    const m5 = r.nl.device("m5").?.index();
    try std.testing.expectEqual(m5, r.st.device_mate[m5]);
    try std.testing.expectEqual(r.nl.device("m2").?.index(), r.st.device_mate[r.nl.device("m1").?.index()]);
}

test "lines: role, driver, class" {
    var f = try Fixture.init();
    defer f.deinit();
    const r = try run(f.arena(), f.lib, ota, "*@ role vb input\n*@ driver vin1 inline\n*@ driver m1 apart\n*@ class m5 pmos\n");
    try expectState(r.verdict("*@ role vb input"), .honoured, .ok);
    try std.testing.expectEqual(np.Role.input, r.roles[r.nl.net("vb").?.index()]);
    try expectState(r.verdict("*@ driver vin1 inline"), .honoured, .ok);
    try std.testing.expect(r.sk.drawn[r.nl.device("vin1").?.index()]);
    try expectState(r.verdict("*@ driver m1 apart"), .rejected, .not_placeable);
    try expectState(r.verdict("*@ class m5 pmos"), .honoured, .ok);
    try std.testing.expectEqualStrings("pmos", f.lib.at(r.p.dev_class[r.device("m5")]).name);
}

test "lines: kind makes an unknown block a transistor; expand flattens one instance" {
    var f = try Fixture.init();
    defer f.deinit();
    const deck =
        \\blocks
        \\.subckt inv a y vdd
        \\M1 y a vdd vdd pmos
        \\M2 y a 0 0 nmos
        \\.ends
        \\Vdd vdd 0 1
        \\X1 in mid vdd inv
        \\X2 mid out vdd inv
        \\X3 out g 0 0 fet
        \\R1 vdd out 1k
        \\
    ;
    const r = try run(f.arena(), f.lib, deck, "*@ expand x1\n*@ expand x9\n*@ kind x3 nmos\n");
    try expectState(r.verdict("*@ expand x1"), .honoured, .ok);
    try expectState(r.verdict("*@ expand x9"), .rejected, .unknown_name);
    try std.testing.expectEqual(null, r.nl.device("x1"));
    try std.testing.expect(r.nl.device("x2") != null);
    try expectState(r.verdict("*@ kind x3 nmos"), .honoured, .ok);
    const x3 = r.nl.device("x3").?;
    try std.testing.expectEqual(np.netlist.DeviceKind.mosfet, r.nl.graph.edges.items(.kind)[x3.index()]);
}

test "lines: label names a net, wire wires one, port and rail set their symbols" {
    var f = try Fixture.init();
    defer f.deinit();
    const base = try run(f.arena(), f.lib, ota, "");
    try std.testing.expect(!base.labelled("f"));
    try std.testing.expect(base.labelled("vb") or base.symbols("vb") > 0);
    const r = try run(f.arena(), f.lib, ota, "*@ label f\n*@ port vout left\n*@ rail vdd each\n*@ first vout\n");
    try expectState(r.verdict("*@ label f"), .honoured, .ok);
    try std.testing.expect(r.labelled("f"));
    try expectState(r.verdict("*@ port vout left"), .honoured, .ok);
    try expectState(r.verdict("*@ rail vdd each"), .honoured, .ok);
    try std.testing.expect(r.symbols("vdd") > base.symbols("vdd"));
    try expectState(r.verdict("*@ first vout"), .honoured, .ok);
    // Two ground pins facing down share one bar.
    const dividers =
        \\Two dividers
        \\Vdd vdd 0 1
        \\R1 vdd a 1k
        \\R2 a 0 1k
        \\R3 vdd b 1k
        \\R4 b 0 1k
        \\
    ;
    const each = try run(f.arena(), f.lib, dividers, "");
    const one = try run(f.arena(), f.lib, dividers, "*@ rail 0 bar\n");
    try expectState(one.verdict("*@ rail 0 bar"), .honoured, .ok);
    try std.testing.expect(one.symbols("0") < each.symbols("0"));
}

test "lines: a port asked along its net's own wire is not drawn back over it" {
    // Oracle: the netlister's reading (`run` checks every net is one
    // piece). An input between two pins of one column is an upright wire;
    // `port in top` sent the port's stub back up that wire, which reads as
    // two pieces (found by `zig build fuzz`). The line has no room and
    // says so; the port goes out sideways.
    var f = try Fixture.init();
    defer f.deinit();
    const deck =
        \\An input down a column
        \\.model nch nmos level=1
        \\Vin in 0 ac 1
        \\M2 vdd b in 0 nch
        \\
    ;
    const r = try run(f.arena(), f.lib, deck, "*@ weak port in top\n*@ weak role 0 bias\n");
    try expectState(r.verdict("*@ weak port in top"), .relaxed, .no_room);
    // The node between two parts in series is all wire to its left and its
    // right: its port stands off the line, on no device's pin (in 238 of
    // 5,263 reference circuits the symbol stood on the next part's pin).
    const series =
        \\An output between two parts in series
        \\C1 vout c1_n 1p
        \\R1 vout vin 1k
        \\
    ;
    const s = try run(f.arena(), f.lib, series, "*@ role c1_n output\n");
    try std.testing.expectEqual(1, s.symbols("vout"));
    try std.testing.expect(!s.labelled("vout"));
    const net = s.net("vout");
    for (0..s.p.deviceCount()) |d| {
        const a, const b = s.p.pinRange(d);
        if (s.p.dev_name[d].len != 0 or b - a != 1 or s.p.pin_net[a] != net) continue;
        const at = s.p.pin_xy[a];
        try std.testing.expect(at.y != s.pin("r1", 0).y or at.y != s.pin("c1", 0).y);
        for ([_]np.Pt{ s.pin("r1", 0), s.pin("c1", 0) }) |q| try std.testing.expect(!(q.x == at.x and q.y == at.y));
    }
}

test "lines: a malformed line, an unknown name or verb are rejected" {
    var f = try Fixture.init();
    defer f.deinit();
    const r = try run(f.arena(), f.lib, ota, "*@ frobnicate m1\n*@ above m1 m99\n*@ face m1 g sideways\n*@ route f 1 2 3\n*@ rail vout bar\n*@ at m1 2 x\n");
    try expectState(r.verdict("*@ frobnicate m1"), .rejected, .unknown_verb);
    try expectState(r.verdict("*@ above m1 m99"), .rejected, .unknown_name);
    try expectState(r.verdict("*@ face m1 g sideways"), .rejected, .bad_args);
    try expectState(r.verdict("*@ route f 1 2 3"), .rejected, .bad_args);
    try expectState(r.verdict("*@ rail vout bar"), .rejected, .not_placeable);
    try expectState(r.verdict("*@ at m1 2 x"), .rejected, .bad_args);
}

test "lines: cell puts a device on its cell, the device there moves aside, and the later of two lines on one cell wins" {
    var f = try Fixture.init();
    defer f.deinit();
    const base = try run(f.arena(), f.lib, ota, "");
    // M5's cell and M3's, in the frame the lines use.
    const m3 = base.nl.device("m3").?.index();
    const m5 = base.nl.device("m5").?.index();
    const c3: [2]i32 = .{ base.sk.x[m3] + base.sk.origin[0], base.sk.y[m3] + base.sk.origin[1] };
    const line = try std.fmt.allocPrint(f.arena(), "*@ cell m5 {d} {d}\n", .{ c3[0], c3[1] });
    const r = try run(f.arena(), f.lib, ota, line);
    try expectState(r.verdict(line[0 .. line.len - 1]), .honoured, .ok);
    try std.testing.expectEqual(c3[0], r.sk.x[m5] + r.sk.origin[0]);
    try std.testing.expectEqual(c3[1], r.sk.y[m5] + r.sk.origin[1]);
    const two = try std.fmt.allocPrint(f.arena(), "*@ cell m1 {d} {d}\n*@ cell m2 {d} {d}\n", .{ c3[0], c3[1], c3[0], c3[1] });
    const t = try run(f.arena(), f.lib, ota, two);
    const first = try std.fmt.allocPrint(f.arena(), "*@ cell m1 {d} {d}", .{ c3[0], c3[1] });
    const second = try std.fmt.allocPrint(f.arena(), "*@ cell m2 {d} {d}", .{ c3[0], c3[1] });
    try expectState(t.verdict(second), .honoured, .ok);
    try expectState(t.verdict(first), .dropped, .conflict);
}

test "lines: at puts a symbol where it says and turns it; one on another symbol is refused; refdes moves a name" {
    var f = try Fixture.init();
    defer f.deinit();
    const r = try run(f.arena(), f.lib, ota, "*@ at m5 -10 20 r90\n*@ refdes m1 left\n");
    try expectState(r.verdict("*@ at m5 -10 20 r90"), .honoured, .ok);
    try std.testing.expect(r.at("m5").eql(.{ .x = -10 * f.lib.unit, .y = 20 * f.lib.unit }));
    try std.testing.expectEqual(np.Orient{ .rot = 1 }, r.p.dev_orient[r.device("m5")]);
    try expectState(r.verdict("*@ refdes m1 left"), .honoured, .ok);
    // M4 placed on M3's own spot.
    const base = try run(f.arena(), f.lib, ota, "");
    const m3 = base.at("m3");
    const on = try std.fmt.allocPrint(f.arena(), "*@ at m4 {d:.4} {d:.4}\n", .{ fu(m3.x, f.lib.unit), fu(m3.y, f.lib.unit) });
    const o = try run(f.arena(), f.lib, ota, on);
    try expectState(o.verdict(on[0 .. on.len - 1]), .dropped, .guarantee);
    try std.testing.expect(o.at("m4").eql(base.at("m4")));
}

test "lines: a row line and an above line on a loop of two devices are both held" {
    // Oracle: the lines themselves, read off the drawing. A transmission
    // gate's two transistors stand above each other both ways; `row` puts
    // one level with the capacitor, `above` orders the two. The engine
    // compared a device against its row's class and kept both ways of the
    // loop: no levels, an abort.
    var f = try Fixture.init();
    defer f.deinit();
    const gate = "Transmission gate\n.model nch nmos\n.model pch pmos\nC1 vout 0 1p\nM1 vout ck vin 0 nch\nM2 vout ckb vin vdd pch\n";
    const r = try run(f.arena(), f.lib, gate, "*@ row m2 c1\n*@ above m1 m2\n");
    try expectState(r.verdict("*@ row m2 c1"), .honoured, .ok);
    try expectState(r.verdict("*@ above m1 m2"), .honoured, .ok);
    try std.testing.expectEqual(r.at("m2").y, r.at("c1").y);
    try std.testing.expect(r.at("m1").y < r.at("m2").y);
}

test "lines: a line admitted after another line's mirror image stands, and the image goes" {
    // Oracle: the lines themselves, read off the drawing. `above m2 m0`
    // also states its image, `above m1 m3`; the rows `m2 m3` and `m0 m1`,
    // admitted after it, say the opposite of the image. Every line the
    // deck wrote is held. The image stayed, and the rows had no levels.
    var f = try Fixture.init();
    defer f.deinit();
    const mirrors = "Two mirrors over a pair\n.model nch nmos\n.model pch pmos\nM0 o1 a vdd vdd pch\nM1 a a vdd vdd pch\n" ++
        "M2 b b vdd vdd pch\nM3 o2 b vdd vdd pch\nM4 b in2 t 0 nch\nM5 a in1 t 0 nch\nI1 t 0 1m\nR1 o1 0 1k\nR2 o2 0 1k\n";
    const r = try run(f.arena(), f.lib, mirrors, "*@ row m2 m3\n*@ row m0 m1\n*@ above m2 m0\n");
    for ([_][]const u8{ "*@ row m2 m3", "*@ row m0 m1", "*@ above m2 m0" }) |line| try expectState(r.verdict(line), .honoured, .ok);
    try std.testing.expectEqual(r.at("m2").y, r.at("m3").y);
    try std.testing.expectEqual(r.at("m0").y, r.at("m1").y);
    try std.testing.expect(r.at("m2").y < r.at("m0").y);
}

test "lines: an order line admitted after another order line's mirror image stands, and the image goes" {
    // Oracle: the lines themselves, read off the drawing. `order m0 m1`
    // also states its image reversed, `order m2 m3`; `order m3 m2` says the
    // opposite of the image and of no line. Both lines are held, in either
    // order of the deck. The image stayed, the columns had no order, and
    // the engine aborted.
    var f = try Fixture.init();
    defer f.deinit();
    const mirrors = "Two mirrors over a pair\n.model nch nmos\n.model pch pmos\nM0 o1 a vdd vdd pch\nM1 a a vdd vdd pch\n" ++
        "M2 b b vdd vdd pch\nM3 o2 b vdd vdd pch\nM4 b in2 t 0 nch\nM5 a in1 t 0 nch\nI1 t 0 1m\nR1 o1 0 1k\nR2 o2 0 1k\n";
    for ([_][]const u8{ "*@ order m3 m2\n*@ order m0 m1\n", "*@ order m0 m1\n*@ order m3 m2\n" }) |lines| {
        const r = try run(f.arena(), f.lib, mirrors, lines);
        try expectState(r.verdict("*@ order m0 m1"), .honoured, .ok);
        try expectState(r.verdict("*@ order m3 m2"), .honoured, .ok);
        try std.testing.expect(r.at("m0").x < r.at("m1").x);
        try std.testing.expect(r.at("m3").x < r.at("m2").x);
    }
}

test "lines: an at that gives way stands on its lattice place, and an at on that place gives way too" {
    // Oracle: the guarantee (no symbol on another), checked by `run`, and
    // the drawing with no line. M4 is put on M3 and gives way; M1 is put
    // where M4 then stands, and must give way as well. It was checked
    // against the place M4 had left, kept, and drawn on M4.
    var f = try Fixture.init();
    defer f.deinit();
    const base = try run(f.arena(), f.lib, ota, "");
    const m3 = base.at("m3");
    const m4 = base.at("m4");
    const lines = try std.fmt.allocPrint(f.arena(), "*@ at m4 {d:.4} {d:.4}\n*@ at m1 {d:.4} {d:.4}\n", .{ fu(m3.x, f.lib.unit), fu(m3.y, f.lib.unit), fu(m4.x, f.lib.unit), fu(m4.y, f.lib.unit) });
    const r = try run(f.arena(), f.lib, ota, lines);
    for (r.nl.hints, r.v) |h, v| if (h.verb == .at) try expectState(v, .dropped, .guarantee);
    try std.testing.expect(r.at("m4").eql(m4));
    try std.testing.expect(r.at("m1").eql(base.at("m1")));
}

test "lines: a chain of two bridges, one mate turned upright, takes two cells" {
    // Oracle: the guarantees `run` checks (every device once, no symbol on
    // another). Two coupling capacitors in series through an input are a
    // chain; the mate of one is turned upright by a line, so the chain has
    // no whole mirror image to take. Member by member, both took the one
    // mirror cell.
    var f = try Fixture.init();
    defer f.deinit();
    const lna = "Two pairs\n.model nch nmos\nC1 g1 in1 1p\nC2 g2 in2 1p\nC5 g5 in1 1p\nC6 g6 in2 1p\nM1 x1 g1 0 0 nch\nM2 x2 g2 0 0 nch\n" ++
        "M5 x1 g5 0 0 nch\nM6 x2 g6 0 0 nch\nR3 vdd x1 1k\nR4 vdd x2 1k\n";
    const r = try run(f.arena(), f.lib, lna, "*@ upright c5\n*@ bridge c2\n*@ bridge c6\n");
    try expectState(r.verdict("*@ upright c5"), .honoured, .ok);
    try std.testing.expect(!r.at("c2").eql(r.at("c6")));
}

test "lines: route pins a net's wire from one of its pins; one off its pins is refused; via passes a point" {
    var f = try Fixture.init();
    defer f.deinit();
    const base = try run(f.arena(), f.lib, ota, "");
    const u = f.lib.unit;
    // The tail net: from M5's drain across to below M1's source, then up to it.
    const d5 = base.pin("m5", 0);
    const s1 = base.pin("m1", 2);
    const corner: np.Pt = .{ .x = s1.x, .y = d5.y };
    const text = try std.fmt.allocPrint(f.arena(), "*@ route p {d:.4},{d:.4} {d:.4},{d:.4} {d:.4},{d:.4}", .{
        fu(d5.x, u), fu(d5.y, u), fu(corner.x, u), fu(corner.y, u), fu(s1.x, u), fu(s1.y, u),
    });
    const r = try run(f.arena(), f.lib, ota, try std.mem.concat(f.arena(), u8, &.{ text, "\n" }));
    try expectState(r.verdict(text), .honoured, .ok);
    const off = "*@ route p 1000 1000 1000 1001";
    const o = try run(f.arena(), f.lib, ota, off ++ "\n");
    try expectState(o.verdict(off), .dropped, .guarantee);
    const via = try std.fmt.allocPrint(f.arena(), "*@ via vout {d:.4},{d:.4}", .{ fu(base.pin("m4", 0).x, u), fu(base.pin("m4", 0).y, u) });
    const w = try run(f.arena(), f.lib, ota, try std.mem.concat(f.arena(), u8, &.{ via, "\n" }));
    try expectState(w.verdict(via), .honoured, .ok);
}

const half =
    \\Half an OTA
    \\.model nch nmos level=1
    \\.model pch pmos level=1
    \\Vdd vdd 0 1.8
    \\Vin1 vin1 0 dc 0.9 ac 1
    \\Vb vb 0 0.7
    \\M1 f vin1 p 0 nch
    \\M3 f f vdd vdd pch
    \\M5 p vb 0 0 nch
    \\
;

/// The `weak at` stays of drawing `r`: where it has each device.
fn staysOf(arena: std.mem.Allocator, r: *const Run, unit: i32) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (try np.report.decisions(arena, &r.nl, &r.st, &r.sk, &r.p, unit, 4)) |line| {
        if (std.mem.startsWith(u8, line, "*@ weak at ")) try out.print(arena, "{s}\n", .{line});
    }
    return out.items;
}

test "lines: a deck relaid from its last drawing lays again only what its structure moved" {
    // Oracles: the deck laid afresh (every two devices stand in the same
    // order along x and y: the relaid drawing shows the same structure),
    // the last drawing (a device outside the radius of change is where it
    // was), and the circuit's own symmetry. `run` checks the guarantees.
    var f = try Fixture.init();
    defer f.deinit();
    const Case = struct { was: []const u8, now: []const u8, moved: usize };
    for ([_]Case{
        // Nothing changed: nothing moves.
        .{ .was = ota, .now = ota, .moved = 0 },
        // A load on the output stands beside the circuit: nothing moves.
        .{ .was = ota, .now = ota ++ "Cl vout 0 1p\n", .moved = 0 },
        // The other half makes the circuit symmetric: the tail moves onto
        // the axis, the first half stays.
        .{ .was = half, .now = ota, .moved = 1 },
        // A drawing wrapped into shelves wraps as it did: nothing moves.
        .{ .was = support.wide_chain, .now = support.wide_chain, .moved = 0 },
        .{ .was = support.inverting_amp, .now = support.inverting_amp, .moved = 0 },
    }) |c| {
        const was = try run(f.arena(), f.lib, c.was, "");
        const fresh = try run(f.arena(), f.lib, c.now, "");
        const r = try run(f.arena(), f.lib, c.now, try staysOf(f.arena(), &was, f.lib.unit));
        var moved: usize = 0;
        for (r.p.dev_name, 0..) |name, d| {
            if (name.len == 0) continue;
            const at = r.p.dev_pos[d];
            for (was.p.dev_name, was.p.dev_pos) |n, p| {
                if (std.mem.eql(u8, n, name) and was.sk.drawn[was.nl.device(n).?.index()]) moved += @intFromBool(!p.eql(at));
            }
            for (r.p.dev_name[d + 1 ..], d + 1..) |other, e| {
                if (other.len == 0) continue;
                const a = fresh.at(name);
                const b = fresh.at(other);
                try std.testing.expectEqual(std.math.order(a.x, b.x), std.math.order(at.x, r.p.dev_pos[e].x));
                try std.testing.expectEqual(std.math.order(a.y, b.y), std.math.order(at.y, r.p.dev_pos[e].y));
                try std.testing.expect(!r.p.deviceRect(f.lib, d).intersects(r.p.deviceRect(f.lib, e)));
            }
        }
        if (moved != c.moved) for (r.p.dev_name, r.p.dev_pos) |name, at| {
            if (name.len == 0) continue;
            std.debug.print("{s}: relaid {d},{d} fresh {d},{d}", .{ name, at.x, at.y, fresh.at(name).x, fresh.at(name).y });
            for (was.p.dev_name, was.p.dev_pos) |n, p| if (std.mem.eql(u8, n, name)) std.debug.print(" was {d},{d}", .{ p.x, p.y });
            std.debug.print("\n", .{});
        };
        try std.testing.expectEqual(c.moved, moved);
        if (c.was.ptr != half.ptr) continue;
        // The pair and the load level, both about the tail's drain.
        try std.testing.expectEqual(r.at("m1").y, r.at("m2").y);
        try std.testing.expectEqual(r.at("m3").y, r.at("m4").y);
        try std.testing.expectEqual(r.pin("m1", 0).x + r.pin("m2", 0).x, 2 * r.pin("m5", 0).x);
        try std.testing.expectEqual(r.pin("m3", 0).x + r.pin("m4", 0).x, 2 * r.pin("m5", 0).x);
        try std.testing.expect(r.at("m1").eql(was.at("m1")) and r.at("m3").eql(was.at("m3")));
    }
}
