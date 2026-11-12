//! Steering (docs/research/steering.md): the 30 lines of
//! docs/research/figures.md make each golden figure score in full.
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const golden = @import("golden.zig");
const support = @import("support.zig");

const Lines = struct { deck: []const u8, lines: []const u8 };

/// Each deck's lines (figures.md), rung 2 where the vocabulary has it.
const figures = [_]Lines{
    .{ .deck = "folded_cascode", .lines = "*@ above M9 Iss\n*@ above Iss M7\n*@ above M7 M1\n*@ above M1 M3\n*@ face M3 g left\n*@ face M5 g left\n*@ face M7 g left\n*@ face M9 g left\n" },
    .{ .deck = "strongarm", .lines = "*@ above M3 S3\n*@ above S3 M5\n" },
    .{ .deck = "gilbert", .lines = "*@ symmetry off\n*@ order RD1 M1 M5 M2 Iss M3 M6 M4 RD2\n*@ above RD1 RD2\n*@ face M2 g left\n*@ face M4 g left\n" },
    .{ .deck = "bandgap_ptat", .lines = "*@ face Q3 b left\n" },
    .{ .deck = "wide_swing", .lines = "*@ above Iin Ibias\n*@ above Ibias M4\n*@ above M4 M5\n*@ above M5 M3\n*@ face M5 g right\n" },
    .{ .deck = "beta_multiplier", .lines = "*@ face M5 g left\n" },
    .{ .deck = "two_stage_pmos", .lines = "*@ row M1 Rc Cc\n" },
    .{ .deck = "cmfb_two_stage", .lines = "*@ order M7 R3 M1\n" },
};

// ---- private ----

/// `spice` with `lines` after its title.
fn withLines(arena: std.mem.Allocator, spice: []const u8, lines: []const u8) ![]const u8 {
    const at = std.mem.indexOfScalar(u8, spice, '\n').? + 1;
    return std.mem.concat(arena, u8, &.{ spice[0..at], lines, spice[at..] });
}

/// Every relation the score counts holds as the figure has it.
fn full(s: golden.Score) bool {
    return s.x_order.agree == s.x_order.of and s.y_order.agree == s.y_order.of and
        s.rows.drawing_only == 0 and s.rows.figure_only == 0 and
        s.columns.drawing_only == 0 and s.columns.figure_only == 0 and
        s.symmetric.agree == s.symmetric.of and s.gates.agree == s.gates.of;
}

fn deckNamed(name: []const u8) golden.Deck {
    return for (golden.decks) |g| {
        if (std.mem.eql(u8, g.name, name)) break g;
    } else unreachable;
}

test "steering: each golden figure's lines draw it in full, every line honoured, every guarantee kept" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var bad: usize = 0;
    for (figures) |f| {
        const spice = try withLines(arena, deckNamed(f.deck).spice, f.lines);
        const s = try golden.score(arena, lib, spice);
        if (!full(s)) {
            std.debug.print("{s}\n", .{try golden.formatScore(arena, f.deck, s)});
            bad += 1;
        }
        var nl = try np.netlist.parse(arena, &.{spice}, null);
        const roles = try np.guessRoles(arena, &nl);
        const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
        const sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{});
        for (nl.hints, st.verdicts, sk.verdicts) |h, a, b| {
            const v = a orelse b orelse {
                std.debug.print("{s}: no stage took `{s}`\n", .{ f.deck, h.text });
                bad += 1;
                continue;
            };
            if (v.state == .honoured) continue;
            std.debug.print("{s}: `{s}` {t} {t}\n", .{ f.deck, h.text, v.state, v.code });
            bad += 1;
        }
        const sch = try np.layout(arena, &nl, roles, lib, .{});
        const p = try np.Placed.init(arena, &sch, &nl);
        support.expectConnected(&p, lib) catch {
            std.debug.print("{s}: a net in pieces\n", .{f.deck});
            bad += 1;
        };
        bad += try support.shorts(gpa, &p, true);
        bad += try support.dots(gpa, &p, true);
    }
    try std.testing.expectEqual(0, bad);
}

test "steering: no figure's line is redundant: without any one, the score falls" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var redundant: usize = 0;
    for (figures) |f| {
        var it = std.mem.splitScalar(u8, f.lines, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            const rest = try std.mem.replaceOwned(u8, arena, f.lines, try std.mem.concat(arena, u8, &.{ line, "\n" }), "");
            const s = try golden.score(arena, lib, try withLines(arena, deckNamed(f.deck).spice, rest));
            if (!full(s)) continue;
            std.debug.print("{s}: `{s}` changes nothing the score sees\n", .{ f.deck, line });
            redundant += 1;
        }
    }
    try std.testing.expectEqual(0, redundant);
}
