//! The column and partial-wiring lines (docs/research/vocabulary.md):
//! `column`, `label <net> at <dev>.<pin>`, `wire` on an input, and the
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
    try np.report.write(gpa, &aw.writer, &p, lib, &nl, roles, .{}, null);
    const Doc = struct { metrics: struct { ported: []const []const u8 } };
    const doc = try std.json.parseFromSliceLeaky(Doc, arena, aw.written(), .{ .ignore_unknown_fields = true });
    try std.testing.expectEqual(1, doc.metrics.ported.len);
    try std.testing.expectEqualStrings("in", doc.metrics.ported[0]);
}
