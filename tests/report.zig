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
        metrics: struct { crossings: u32, bends: u32, labelled: []const []const u8 },
        requests: []const struct { line: u32 },
        decisions: []const []const u8,
        grid: []const []const u8,
    };
    const doc = try std.json.parseFromSliceLeaky(Doc, arena, aw.written(), .{});
    try std.testing.expectEqual(0, doc.gates.len);
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
