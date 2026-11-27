//! The decision report (`src/report.zig`). Oracles: a fixed point (a deck
//! plus its exported decisions, recognition off, draws the same bytes, so the
//! export states every decision it claims to) and `checks` on the drawing
//! (no finding, the gates every drawing already passes).
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const golden = @import("golden.zig");
const support = @import("support.zig");
const textbook = @import("textbook.zig");

// ---- private ----

/// `spice` drawn, as `cktimg-json` writes it.
fn drawn(arena: std.mem.Allocator, lib: *np.Library, spice: []const u8) ![]const u8 {
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    const s = try np.layout(arena, &nl, roles, lib, .{});
    const p = try np.Placed.init(arena, &s, &nl);
    var aw: std.Io.Writer.Allocating = .init(arena);
    try np.json.write(&p, lib, &aw.writer);
    return aw.written();
}

test "report: a deck plus its exported decisions, rungs 1 to 4, recognition off, draws the same picture" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var decks: std.ArrayList(struct { []const u8, []const u8 }) = .empty;
    for (golden.decks) |d| try decks.append(arena, .{ d.name, d.spice });
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, .{ c.name, c.spice });
    // A drawing wrapped into shelves: its cells give its shelves back.
    try decks.append(arena, .{ "wide_chain", support.wide_chain });
    // A drawing placed along its signal: its places are its decisions.
    try decks.append(arena, .{ "inverting_amp", support.inverting_amp });
    var bad: usize = 0;
    for (decks.items) |d| {
        const nl = try np.netlist.parse(arena, &.{d[1]}, null);
        const roles = try np.guessRoles(arena, &nl);
        const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
        const sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{});
        try std.testing.expectEqual(st.block_kind.len, (try np.report.decisions(arena, &nl, &st, &sk, null, lib.unit, 1)).len);
        const s0 = try np.layout(arena, &nl, roles, lib, .{});
        const p0 = try np.Placed.init(arena, &s0, &nl);
        for ([_]u8{ 1, 2, 3, 4 }) |rung| {
            const lines = try np.report.decisions(arena, &nl, &st, &sk, &p0, lib.unit, rung);
            // After the title line, so no `.end` hides them.
            const title_end = std.mem.indexOfScalar(u8, d[1], '\n').? + 1;
            var deck: std.ArrayList(u8) = .empty;
            try deck.appendSlice(arena, d[1][0..title_end]);
            for (lines) |l| try deck.print(arena, "{s}\n", .{l});
            try deck.appendSlice(arena, "*@ grouping off\n");
            try deck.appendSlice(arena, d[1][title_end..]);
            const same = std.mem.eql(u8, try drawn(arena, lib, d[1]), try drawn(arena, lib, deck.items));
            // Every exported line honoured, and shown.
            var nl2 = try np.netlist.parse(arena, &.{deck.items}, null);
            const roles2 = try np.guessRoles(arena, &nl2);
            const st2 = try np.schematic.structure.analyze(arena, arena, &nl2, roles2);
            const sk2 = try np.schematic.skeleton.place(arena, arena, &nl2, roles2, &st2, .{});
            const s2 = try np.layout(arena, &nl2, roles2, lib, .{});
            const p2 = try np.Placed.init(arena, &s2, &nl2);
            var refused: usize = 0;
            for (nl2.hints, try np.report.verdicts(arena, &nl2, roles2, &st2, &sk2, &p2, lib)) |h, v| if (v.state != .honoured) {
                std.debug.print("{s} rung {d}: `{s}` {t} {t}\n", .{ d[0], rung, h.text, v.state, v.code });
                refused += 1;
            };
            if (same and refused == 0) continue;
            if (!same) std.debug.print("{s}: its rung {d} decisions draw another picture\n", .{ d[0], rung });
            bad += 1;
        }
    }
    try std.testing.expectEqual(0, bad);
}

test "report: the five-transistor OTA's report has no finding, its four blocks, and every device in a row" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const spice =
        \\five-transistor OTA
        \\M1 x inp tail 0 nmos
        \\M2 out inn tail 0 nmos
        \\M3 x x vdd vdd pmos
        \\M4 out x vdd vdd pmos
        \\M5 tail bias 0 0 nmos
        \\V1 vdd 0 1.8
        \\.end
    ;
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    const s = try np.layout(arena, &nl, roles, lib, .{});
    const p = try np.Placed.init(arena, &s, &nl);
    var aw: std.Io.Writer.Allocating = .init(arena);
    try np.report.write(gpa, &aw.writer, &p, lib, &nl, roles, .{});
    const Doc = struct {
        gates: []const struct { rule: []const u8 },
        text_overlaps: []const struct { text: []const u8 },
        metrics: struct { crossings: u32, bends: u32, labelled: []const []const u8 },
        requests: []const struct { line: u32 },
        decisions: []const []const u8,
        grid: []const []const u8,
    };
    const doc = try std.json.parseFromSliceLeaky(Doc, arena, aw.written(), .{});
    try std.testing.expectEqual(0, doc.gates.len);
    try std.testing.expectEqual(0, doc.text_overlaps.len);
    var have: std.ArrayList(u8) = .empty;
    for (doc.decisions) |l| if (std.mem.startsWith(u8, l, "*@ group")) try have.print(arena, "{s}\n", .{l});
    // Names as the parser keeps them (lower case); stacks top to bottom.
    try std.testing.expectEqualStrings(
        \\*@ group pair m1 m2
        \\*@ group mirror m3 m4
        \\*@ group stack m3 m1
        \\*@ group stack m4 m2
        \\
    , have.items);
    // Each drawn device once across the rows.
    for ([_][]const u8{ "m1@", "m2@", "m3@", "m4@", "m5@" }) |name| {
        var seen: usize = 0;
        for (doc.grid) |row| seen += std.mem.count(u8, row, name);
        try std.testing.expectEqual(1, seen);
    }
}

test "report: bends counts every corner a reader sees, a trunk drawn in pieces too" {
    // Oracle: a reference count written as the corpus scorer counts corners
    // (the ways a net's wire leaves each of its points, as a set): a point
    // with no pin on it that the wire leaves exactly two ways, not straight
    // on. The report counted the turns inside one polyline only, so a
    // trunk's corners, each where two pieces end, read as none (an agent
    // hinting hand drawings read 0 bends where the scorer counted 4).
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var total: u32 = 0;
    for (golden.decks) |deck| {
        var arena_state: std.heap.ArenaAllocator = .init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var nl = try np.netlist.parse(arena, &.{deck.spice}, null);
        const roles = try np.guessRoles(arena, &nl);
        const s = try np.layout(arena, &nl, roles, lib, .{});
        const p = try np.Placed.init(arena, &s, &nl);
        var want: u32 = 0;
        for (0..p.netCount()) |n| {
            // Each point of the net's wire with the ways out of it: bit 0
            // left, 1 right, 2 up, 3 down.
            var ways: std.AutoArrayHashMapUnmanaged([2]i32, u4) = .empty;
            var it = p.segments(n);
            while (it.next()) |poly| for (poly) |at| try ways.put(arena, .{ at.x, at.y }, 0);
            for (ways.keys(), ways.values()) |at, *w| {
                var jt = p.segments(n);
                while (jt.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                    if (at[0] < @min(a.x, b.x) or at[0] > @max(a.x, b.x) or at[1] < @min(a.y, b.y) or at[1] > @max(a.y, b.y)) continue;
                    if (@min(a.x, b.x) < at[0]) w.* |= 1;
                    if (@max(a.x, b.x) > at[0]) w.* |= 2;
                    if (@min(a.y, b.y) < at[1]) w.* |= 4;
                    if (@max(a.y, b.y) > at[1]) w.* |= 8;
                };
                const pinned = for (p.pin_xy, p.pin_net) |q, net| {
                    if (net == n and q.x == at[0] and q.y == at[1]) break true;
                } else false;
                want += @intFromBool(!pinned and (w.* == 5 or w.* == 6 or w.* == 9 or w.* == 10));
            }
        }
        var aw: std.Io.Writer.Allocating = .init(arena);
        try np.report.write(gpa, &aw.writer, &p, lib, &nl, roles, .{});
        const Doc = struct { metrics: struct { bends: u32 } };
        const doc = try std.json.parseFromSliceLeaky(Doc, arena, aw.written(), .{ .ignore_unknown_fields = true });
        try std.testing.expectEqual(want, doc.metrics.bends);
        total += want;
    }
    // The figures have corners: the count is not vacuous.
    try std.testing.expect(total > 0);
}

test "report: a displaced gate and a locally translated mirror pair fail on the final common axis" {
    // Independent mutations. No abstract mate, origin or hint changes when
    // a single gate moves. Translating both complete frames retains a local
    // mirror, while the load pair and the common tail still share the old axis.
    const spice =
        \\caller geometry
        \\.model nch nmos level=1
        \\R1 VDD OUTN 1k
        \\R2 VDD OUTP 1k
        \\M1 OUTN INP tail VSS nch w=2u l=1u
        \\M2 OUTP INN tail VSS nch w=2u l=1u
        \\M5 tail VB VSS VSS nch w=4u l=1u
        \\*@ symmetric M1 M2
        \\*@ symmetric R1 R2
        \\*@ axis M5
    ;
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var p = try np.place(gpa, &.{}, lib, &.{spice}, null);
    defer p.deinit();
    const nl = try np.netlist.parse(a, &.{spice}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const left = np.checks.deviceIn(&p, "m1").?;
    const right = np.checks.deviceIn(&p, "m2").?;
    const xy = try a.dupe(np.Pt, p.pin_xy);
    const origins = try a.dupe(np.Pt, p.dev_pos);
    p.pin_xy = xy;
    p.dev_pos = origins;
    xy[p.dev_pin0[right] + 1].y += 10;
    for (0..2) |i| {
        const got = try np.report.verdicts(a, &nl, roles, &st, &sk, &p, lib);
        try std.testing.expectEqual(np.hints.State.relaxed, got[0].state);
        try std.testing.expectEqual(np.hints.Code.not_drawn, got[0].code);
        try std.testing.expectEqual(np.hints.State.honoured, got[1].state);
        try std.testing.expectEqual(np.hints.State.honoured, got[2].state);
        if (i == 0) {
            xy[p.dev_pin0[right] + 1].y -= 10;
            for ([_]usize{ left, right }) |d| {
                origins[d].x += 40;
                for (xy[p.dev_pin0[d]..p.dev_pin0[d + 1]]) |*pin| pin.x += 40;
            }
        }
    }
    // Neither of the two complete pair axes meets a subsequently displaced
    // tail. Its new position alone cannot certify a common plane.
    origins[np.checks.deviceIn(&p, "m5").?].x += 15;
    const split = try np.report.verdicts(a, &nl, roles, &st, &sk, &p, lib);
    for (split) |v| try std.testing.expectEqual(np.hints.Code.not_drawn, v.code);
}

test "report: two admitted quad tails occupy distinct rows on the common final axis" {
    // The complete resistor pair determines the physical axis independent
    // of the current-source positions. A held exact pose must win even
    // when its hint occurs before the symmetry requests it breaks.
    const quad =
        \\caller geometry
        \\.model nch nmos level=1
        \\R1 VDD OUTP 1k
        \\R2 VDD OUTN 1k
        \\M1 OUTP INP s1 VSS nch w=2u l=1u
        \\M2 OUTN INN s1 VSS nch w=2u l=1u
        \\M3 OUTP INN s2 VSS nch w=2u l=1u
        \\M4 OUTN INP s2 VSS nch w=2u l=1u
        \\I1 s1 VSS 1m
        \\I2 s2 VSS 1m
        \\*@ at M3 -20 -20 r0
        \\*@ symmetric M3 M4
        \\*@ symmetric R1 R2
        \\*@ axis I1
        \\*@ axis I2
    ;
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var p = try np.place(gpa, &.{}, lib, &.{quad}, null);
    defer p.deinit();
    const nl = try np.netlist.parse(a, &.{quad}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const axis = p.dev_pos[np.checks.deviceIn(&p, "r1").?].x + p.dev_pos[np.checks.deviceIn(&p, "r2").?].x;
    const tail1 = p.dev_pos[np.checks.deviceIn(&p, "i1").?];
    const tail2 = p.dev_pos[np.checks.deviceIn(&p, "i2").?];
    try std.testing.expectEqual(axis, 2 * tail1.x);
    try std.testing.expectEqual(axis, 2 * tail2.x);
    try std.testing.expect(tail1.y != tail2.y);
    const m3 = p.dev_pos[np.checks.deviceIn(&p, "m3").?];
    try std.testing.expectEqual(-20 * lib.unit, m3.x);
    try std.testing.expectEqual(-20 * lib.unit, m3.y);
    const v = try np.report.verdicts(a, &nl, roles, &st, &sk, &p, lib);
    try std.testing.expectEqual(np.hints.State.honoured, v[0].state);
    try std.testing.expectEqual(np.hints.State.dropped, v[1].state);
    try std.testing.expectEqual(np.hints.Code.conflict, v[1].code);
    try std.testing.expectEqualSlices(u32, &.{0}, v[1].blocked_by);
    for (v[2..]) |rest| try std.testing.expectEqual(np.hints.State.honoured, rest.state);
}

test "report: the written stack follows the final shared channel, including both pin coordinates" {
    // The tail net is independently the source of M1 and drain of M5. The
    // physical MOS path puts M1 above M5, even if the caller names M5 first.
    const base =
        \\caller stack
        \\.model nch nmos level=1
        \\R1 vdd outn 1k
        \\R2 vdd outp 1k
        \\M1 outn inp tail vss nch w=2u l=1u
        \\M2 outp inn tail vss nch w=2u l=1u
        \\M5 tail vb vss vss nch w=4u l=1u
        \\
    ;
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_]bool{ false, true }) |reverse| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const src = try std.mem.concat(a, u8, &.{ base, if (reverse) "*@ group stack m5 m1\n" else "*@ group stack m1 m5\n" });
        var p = try np.place(gpa, &.{}, lib, &.{src}, null);
        defer p.deinit();
        const nl = try np.netlist.parse(a, &.{src}, null);
        const roles = try np.guessRoles(a, &nl);
        const st = try np.schematic.structure.analyze(a, a, &nl, roles);
        const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
        const u = np.checks.deviceIn(&p, "m1").?;
        const l = np.checks.deviceIn(&p, "m5").?;
        try std.testing.expect(p.dev_pos[u].y < p.dev_pos[l].y);
        try std.testing.expectEqual(p.pin_xy[p.dev_pin0[u] + 2].x, p.pin_xy[p.dev_pin0[l]].x);
        const got = try np.report.verdicts(a, &nl, roles, &st, &sk, &p, lib);
        try std.testing.expectEqual(if (reverse) np.hints.Code.not_drawn else .ok, got[0].code);
        try std.testing.expectEqual(!reverse, support.generatedStack(&p, nl.hints[0].args[0], nl.hints[0].args[1]));
        const decisions = try np.report.decisions(a, &nl, &st, &sk, &p, lib.unit, 1);
        try std.testing.expect(for (decisions) |line| {
            if (std.mem.eql(u8, line, "*@ group stack m1 m5")) break true;
        } else false);
        if (!reverse) {
            const pins = try a.dupe(np.Pt, p.pin_xy);
            p.pin_xy = pins;
            pins[p.dev_pin0[l]].x += 10;
            try std.testing.expect(!support.generatedStack(&p, "m1", "m5"));
            try std.testing.expectEqual(false, np.checks.drawnAs(&p, &nl, nl.hints[0], lib.unit).?);
        }
    }
}

test "report: two controlled sources anchored to the same rail refuse both stack orders" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const deck = "controlled sources\nE3 vdd 0 in b 1\nE5 b vdd c vdd 1\n";
    for ([_][]const u8{ "*@ group stack e5 e3\n", "*@ group stack e3 e5\n" }) |request| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const src = try std.mem.concat(a, u8, &.{ deck, request });
        var p = try np.place(gpa, &.{}, lib, &.{src}, null);
        defer p.deinit();
        const e3 = np.checks.deviceIn(&p, "e3").?;
        const e5 = np.checks.deviceIn(&p, "e5").?;
        try std.testing.expectEqual(p.dev_pos[e3].y, p.dev_pos[e5].y);
        try std.testing.expectEqual(p.pin_xy[p.dev_pin0[e3]].y, p.pin_xy[p.dev_pin0[e5] + 1].y);
        const nl = try np.netlist.parse(a, &.{src}, null);
        const roles = try np.guessRoles(a, &nl);
        const st = try np.schematic.structure.analyze(a, a, &nl, roles);
        const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
        const v = (try np.report.verdicts(a, &nl, roles, &st, &sk, &p, lib))[0];
        try std.testing.expectEqual(np.hints.State.relaxed, v.state);
        try std.testing.expectEqual(np.hints.Code.not_drawn, v.code);
        try std.testing.expect(!support.generatedStack(&p, nl.hints[0].args[0], nl.hints[0].args[1]));
        for (try np.report.decisions(a, &nl, &st, &sk, &p, lib.unit, 1)) |line|
            try std.testing.expect(!std.mem.startsWith(u8, line, "*@ group stack"));
    }
}
