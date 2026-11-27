//! The column and partial-wiring lines (docs/research/vocabulary.md):
//! `column`, `label <net> at <dev>.<pin>`, `wire <net> at <pins>`, `wire`
//! on an input, where names stand (names clear of their own wire), and the
//! report's count of nets drawn as repeated ports. Oracles: the finished
//! `Placed` read back (a device's place, a pin on or off its net's wire,
//! the port symbols on a net), the verdicts' own contract (hints.3: a line
//! that cannot hold names the lines it gives way to), and the guarantees
//! every drawing keeps.
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");

/// The five-transistor OTA with a second tail device, M6, in parallel with
/// M5: two devices on the same two nets, which no chain links.
const ota =
    \\Five-transistor OTA, two tails
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
    \\M6 p vb 0 0 nch
    \\
;

/// One input on three gates far apart: by default a port at each. No
/// source drives it, so every port symbol on it is the circuit's.
const spread =
    \\Three gates on one input
    \\*@ role in input
    \\.model nch nmos level=1
    \\Vdd vdd 0 1.8
    \\M1 a in 0 0 nch
    \\R1 vdd a 1k
    \\M2 b a 0 0 nch
    \\R2 vdd b 1k
    \\M3 c b 0 0 nch
    \\R3 vdd c 1k
    \\M4 d in c 0 nch
    \\R4 vdd d 1k
    \\M5 e in 0 0 nch
    \\R5 d e 1k
    \\
;

/// A diode-connected load and a mirror: net `x` on M1's drain, M2's drain
/// and gate and M3's gate. The `label ... at` line names M3's gate; the
/// rest is one wire, named once (fable5 bug-ownwire).
const own_wire =
    \\Name on its own wire
    \\*@ label x at m3.g
    \\*@ role in input
    \\*@ role out output
    \\.model nch nmos
    \\.model pch pmos
    \\M1 x in vdd vdd pch
    \\M2 x x vss vss nch
    \\M3 out x vss vss nch
    \\M4 out in vdd vdd pch
    \\
;

/// Two gates facing each other on one row, `x` drawn as names (fable5
/// bug-facing): once two names on one point, each on the other's stub.
const facing =
    \\Facing gates as names
    \\*@ label x
    \\.model nch nmos
    \\.model pch pmos
    \\M1 a x vss vss nch
    \\M2 b x vss vss nch
    \\M3 x x vdd vdd pch
    \\R1 x vss 1k
    \\
;

/// An output `n` on M1's source and R1, its gate pin on M2 named apart
/// (fable3 ag-2323 IBUF): its port already writes the rest's name.
const ported_rest =
    \\Label at on a ported net
    \\*@ label n at m2.g
    \\*@ role n output
    \\.model nch nmos level=1
    \\Vdd vdd 0 1.8
    \\Vin a 0 1
    \\M1 vdd a n 0 nch
    \\R1 n 0 1k
    \\M2 b n 0 0 nch
    \\R2 vdd b 1k
    \\
;

const Run = struct {
    nl: np.netlist.Netlist,
    p: np.Placed,
    v: []const np.hints.Verdict,

    fn verdict(r: *const Run, text: []const u8) np.hints.Verdict {
        for (r.nl.hints, r.v) |h, v| if (std.mem.eql(u8, h.text, text)) return v;
        unreachable;
    }

    fn line(r: *const Run, text: []const u8) u32 {
        for (r.nl.hints, 0..) |h, i| if (std.mem.eql(u8, h.text, text)) return @intCast(i);
        unreachable;
    }

    fn at(r: *const Run, name: []const u8) np.Pt {
        return r.p.dev_pos[np.checks.deviceIn(&r.p, name).?];
    }

    fn pin(r: *const Run, name: []const u8, k: u32) np.Pt {
        return r.p.pin_xy[r.p.pinRange(np.checks.deviceIn(&r.p, name).?)[0] + k];
    }

    fn net(r: *const Run, name: []const u8) u32 {
        for (r.p.net_name, 0..) |n, k| if (std.mem.eql(u8, n, name)) return @intCast(k);
        unreachable;
    }

    /// The port symbols (unnamed one-pin devices) on net `name`.
    fn ports(r: *const Run, name: []const u8) usize {
        const n = r.net(name);
        var count: usize = 0;
        for (0..r.p.deviceCount()) |d| {
            const a, const b = r.p.pinRange(d);
            if (r.p.dev_name[d].len == 0 and b - a == 1 and r.p.pin_net[a] == n) count += 1;
        }
        return count;
    }

    /// Whether `a` and `b` lie on one connected piece of net `name`'s
    /// wires: polylines join where a point of one lies on a run of the
    /// other, as a netlister reads them.
    fn joined(r: *const Run, name: []const u8, a: np.Pt, b: np.Pt) bool {
        var polys: [64][]const np.Pt = undefined;
        var n: usize = 0;
        var it = r.p.segments(r.net(name));
        while (it.next()) |poly| : (n += 1) polys[n] = poly;
        var piece: [64]usize = undefined;
        for (0..n) |k| piece[k] = k;
        var changed = true;
        while (changed) {
            changed = false;
            for (0..n) |i| for (0..n) |j| {
                if (piece[i] == piece[j]) continue;
                const touch = for (polys[i]) |q| {
                    if (on(polys[j], q)) break true;
                } else false;
                if (!touch) continue;
                const lo = @min(piece[i], piece[j]);
                const hi = @max(piece[i], piece[j]);
                for (piece[0..n]) |*x| if (x.* == hi) {
                    x.* = lo;
                };
                changed = true;
            };
        }
        for (0..n) |i| for (0..n) |j| if (on(polys[i], a) and on(polys[j], b) and piece[i] == piece[j]) return true;
        return false;
    }

    /// The labels on net `name`.
    fn names(r: *const Run, name: []const u8) usize {
        const n = r.net(name);
        var count: usize = 0;
        for (r.p.labels) |l| count += @intFromBool(l.net == n);
        return count;
    }

    fn labelled(r: *const Run, name: []const u8) bool {
        const n = r.net(name);
        for (r.p.labels) |l| if (l.net == n) return true;
        return false;
    }
};

// ---- private ----

/// Whether `q` lies on a run of polyline `poly`.
fn on(poly: []const np.Pt, q: np.Pt) bool {
    if (poly.len == 1) return poly[0].eql(q);
    for (poly[0 .. poly.len - 1], poly[1..]) |u, v| {
        if (q.x >= @min(u.x, v.x) and q.x <= @max(u.x, v.x) and q.y >= @min(u.y, v.y) and q.y <= @max(u.y, v.y)) return true;
    }
    return false;
}

/// `spice` with `lines` after its title, laid out and reported on; the
/// drawing's guarantees checked.
fn run(arena: std.mem.Allocator, lib: *np.Library, spice: []const u8, lines: []const u8) !Run {
    const cut = std.mem.indexOfScalar(u8, spice, '\n').? + 1;
    const deck = try std.mem.concat(arena, u8, &.{ spice[0..cut], lines, spice[cut..] });
    var nl = try np.netlist.parse(arena, &.{deck}, null);
    const roles = try np.guessRoles(arena, &nl);
    const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
    const sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{});
    const s = try np.layout(arena, &nl, roles, lib, .{});
    const p = try np.Placed.init(arena, &s, &nl);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(std.testing.allocator, &p, true));
    const v = try np.report.verdicts(arena, &nl, roles, &st, &sk, &p, lib);
    return .{ .nl = nl, .p = p, .v = v };
}

/// No label's text starts on a wire of its own net (a point six units
/// into it, the way it runs), no two labels of a net share a point, and no
/// net draws one piece of wire twice, end for end: read off the drawing.
fn expectNamesClear(p: *const np.Placed) !void {
    for (p.labels, 0..) |l, i| {
        const into = l.at.add(.{ .x = 6 * l.side.unit().x, .y = 6 * l.side.unit().y });
        var it = p.segments(l.net);
        while (it.next()) |poly| try std.testing.expect(!on(poly, into));
        for (p.labels[i + 1 ..]) |m| try std.testing.expect(m.net != l.net or !m.at.eql(l.at));
    }
    for (0..p.netCount()) |n| {
        var pieces: std.ArrayList([2]np.Pt) = .empty;
        defer pieces.deinit(std.testing.allocator);
        var it = p.segments(n);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            for (pieces.items) |q| try std.testing.expect(!((q[0].eql(a) and q[1].eql(b)) or (q[0].eql(b) and q[1].eql(a))));
            try pieces.append(std.testing.allocator, .{ a, b });
        };
    }
}

fn expectState(v: np.hints.Verdict, state: np.hints.State, code: np.hints.Code) !void {
    if (v.state != state or v.code != code) std.debug.print("got {t} {t}\n", .{ v.state, v.code });
    try std.testing.expectEqual(state, v.state);
    try std.testing.expectEqual(code, v.code);
}

test "column: parallel devices stand in one column, top down, across a shelf cut too" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    // Parallel, so no chain joins them: by default side by side on a row.
    const r = try run(arena, lib, ota, "*@ column m6 m5\n");
    try expectState(r.verdict("*@ column m6 m5"), .honoured, .ok);
    try std.testing.expectEqual(r.at("m6").x, r.at("m5").x);
    try std.testing.expect(r.at("m6").y < r.at("m5").y);
    // The first and last stages of a chain that wraps onto two shelves.
    const w = try run(arena, lib, support.wide_chain, "*@ column r12 r1\n");
    try expectState(w.verdict("*@ column r12 r1"), .honoured, .ok);
    try std.testing.expectEqual(w.at("r12").x, w.at("r1").x);
    try std.testing.expect(w.at("r12").y < w.at("r1").y);
}

test "column: a line it cannot hold with gives way or wins by rank, naming the other" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    // Two columns of one device are no order of two columns.
    const o = try run(arena, lib, ota, "*@ order m5 m6\n*@ column m5 m6\n");
    try expectState(o.verdict("*@ column m5 m6"), .honoured, .ok);
    const order = o.verdict("*@ order m5 m6");
    try expectState(order, .dropped, .cycle);
    try std.testing.expectEqualSlices(u32, &.{o.line("*@ column m5 m6")}, order.blocked_by);
    // An `above` the other way: the later line stands.
    const a = try run(arena, lib, ota, "*@ column m5 m6\n*@ above m6 m5\n");
    try expectState(a.verdict("*@ above m6 m5"), .honoured, .ok);
    const up = a.verdict("*@ column m5 m6");
    try expectState(up, .dropped, .conflict);
    try std.testing.expectEqualSlices(u32, &.{a.line("*@ above m6 m5")}, up.blocked_by);
    // One device directly under two others.
    const t = try run(arena, lib, ota, "*@ column m5 m6\n*@ column m1 m6\n");
    try expectState(t.verdict("*@ column m1 m6"), .honoured, .ok);
    const two = t.verdict("*@ column m5 m6");
    try expectState(two, .dropped, .conflict);
    try std.testing.expectEqualSlices(u32, &.{t.line("*@ column m1 m6")}, two.blocked_by);
    // Malformed and unknown.
    const bad = try run(arena, lib, ota, "*@ column m5\n*@ column m5 m9\n*@ column m5 m5\n");
    try expectState(bad.verdict("*@ column m5"), .rejected, .bad_args);
    try expectState(bad.verdict("*@ column m5 m9"), .rejected, .unknown_name);
    try expectState(bad.verdict("*@ column m5 m5"), .rejected, .bad_args);
}

test "label at: the pins named carry the net's name, the rest stay one wire" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const base = try run(arena, lib, ota, "");
    try std.testing.expect(base.joined("f", base.pin("m4", 1), base.pin("m1", 0)));
    // M4's gate off the wire; M1's drain, M3's drain and gate on it.
    const r = try run(arena, lib, ota, "*@ label f at m4.g\n");
    try expectState(r.verdict("*@ label f at m4.g"), .honoured, .ok);
    try std.testing.expect(!r.joined("f", r.pin("m4", 1), r.pin("m1", 0)));
    for ([_]struct { []const u8, u32 }{ .{ "m3", 0 }, .{ "m3", 1 } }) |q|
        try std.testing.expect(r.joined("f", r.pin("m1", 0), r.pin(q[0], q[1])));
    try std.testing.expect(r.labelled("f"));
    const bad = try run(arena, lib, ota, "*@ label f at m9.g\n*@ label f at m5.g\n*@ label f m4.g\n*@ label f at m4\n");
    try expectState(bad.verdict("*@ label f at m9.g"), .rejected, .unknown_name);
    try expectState(bad.verdict("*@ label f at m5.g"), .rejected, .bad_args);
    try expectState(bad.verdict("*@ label f m4.g"), .rejected, .bad_args);
    try expectState(bad.verdict("*@ label f at m4"), .rejected, .bad_args);
}

test "wire on an input: one port, wired to every pin" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const base = try run(arena, lib, spread, "");
    try std.testing.expect(base.ports("in") >= 2);
    const r = try run(arena, lib, spread, "*@ wire in\n");
    try expectState(r.verdict("*@ wire in"), .honoured, .ok);
    try std.testing.expectEqual(1, r.ports("in"));
    for ([_][]const u8{ "m4", "m5" }) |m| try std.testing.expect(r.joined("in", r.pin("m1", 1), r.pin(m, 1)));
}

test "report: a net drawn as two ports or more is listed as ported" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var nl = try np.netlist.parse(arena, &.{spread}, null);
    const roles = try np.guessRoles(arena, &nl);
    const s = try np.layout(arena, &nl, roles, lib, .{});
    const p = try np.Placed.init(arena, &s, &nl);
    var aw: std.Io.Writer.Allocating = .init(arena);
    try np.report.write(gpa, &aw.writer, &p, lib, &nl, roles, .{});
    const Doc = struct { metrics: struct { ported: []const []const u8 } };
    const doc = try std.json.parseFromSliceLeaky(Doc, arena, aw.written(), .{ .ignore_unknown_fields = true });
    try std.testing.expectEqual(1, doc.metrics.ported.len);
    try std.testing.expectEqualStrings("in", doc.metrics.ported[0]);
}

test "names: a name's text never runs along its own wire, and no wire is drawn twice" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const r = try run(arena, lib, own_wire, "");
    try expectState(r.verdict("*@ label x at m3.g"), .honoured, .ok);
    try expectNamesClear(&r.p);
    // M3's gate named apart; the rest one wire with one name.
    try std.testing.expect(r.joined("x", r.pin("m1", 0), r.pin("m2", 1)));
    try std.testing.expectEqual(2, r.names("x"));
    const o = try run(arena, lib, ota, "*@ label f at m4.g\n");
    try expectNamesClear(&o.p);
}

test "label: facing pins each carry a name, never two names on one point" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const r = try run(arena, lib, facing, "");
    try expectState(r.verdict("*@ label x"), .honoured, .ok);
    try expectNamesClear(&r.p);
    // A `label` line's net has no wire between its pins (netlines.1).
    try std.testing.expect(!r.joined("x", r.pin("m1", 1), r.pin("m2", 1)));
}

test "wire at: the pins listed are one wire with one name, the rest drawn apart" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    // By default `f` is one wire: M1's drain on it with M4's gate.
    const r = try run(arena, lib, ota, "*@ wire f at m1.d m3.d\n");
    try expectState(r.verdict("*@ wire f at m1.d m3.d"), .honoured, .ok);
    try std.testing.expect(r.joined("f", r.pin("m1", 0), r.pin("m3", 0)));
    try std.testing.expect(r.joined("f", r.pin("m3", 1), r.pin("m4", 1)));
    try std.testing.expect(!r.joined("f", r.pin("m1", 0), r.pin("m4", 1)));
    // One name a piece.
    try std.testing.expectEqual(2, r.names("f"));
    try expectNamesClear(&r.p);
    const bad = try run(arena, lib, ota, "*@ wire f at m1.d\n*@ wire f at m1.d m1.d\n*@ wire f at m9.d m1.d\n*@ wire f at m1.d m5.d\n*@ wire f m1.d m3.d\n");
    try expectState(bad.verdict("*@ wire f at m1.d"), .rejected, .bad_args);
    try expectState(bad.verdict("*@ wire f at m1.d m1.d"), .rejected, .bad_args);
    try expectState(bad.verdict("*@ wire f at m9.d m1.d"), .rejected, .unknown_name);
    try expectState(bad.verdict("*@ wire f at m1.d m5.d"), .rejected, .bad_args);
    try expectState(bad.verdict("*@ wire f m1.d m3.d"), .rejected, .bad_args);
}

test "label at: a rest its port names carries no second name" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const r = try run(arena, lib, ported_rest, "");
    try expectState(r.verdict("*@ label n at m2.g"), .honoured, .ok);
    try std.testing.expectEqual(1, r.ports("n"));
    // The name at M2's gate only: the port names the rest.
    try std.testing.expectEqual(1, r.names("n"));
    try expectNamesClear(&r.p);
}
