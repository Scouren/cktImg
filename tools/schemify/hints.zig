//! A cell's `*@` lines (steering, docs/research/vocabulary.md; the engine's `hints` reads
//! them): grouping lines checked against the cell's devices for the import log, every line
//! carried into the deck the cell hands the engine with its names mapped to that deck's,
//! and each line the engine did not honour logged with its verdict.
//!
//! Contents:
//! - `pub fn check(a: Allocator, deck: *const Deck, warnings: *ArrayList([]const u8)) Allocator.Error!void`
//! - `pub fn write(a: Allocator, text: *ArrayList(u8), deck: *const Deck, c: u32, dev_names: []const []const u8, net_names: []const []const u8) Allocator.Error!void`
//! - `pub fn notes(gpa: Allocator, a: Allocator, out: *ArrayList([]const u8), deck: *const Deck, c: u32, deck_text: []const u8, placed: *const engine.Placed, lib: *const engine.Library) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const engine = @import("NetlistParser");
const Deck = @import("spice.zig").Deck;

/// One import-log line per device a hint names that its cell does not have;
/// the hint holds for the rest.
pub fn check(a: Allocator, deck: *const Deck, warnings: *ArrayList([]const u8)) Allocator.Error!void {
    assert(deck.directive.len == deck.directive_cell.len and deck.directive.len == deck.directive_line.len);
    for (deck.directive, deck.directive_cell, deck.directive_line) |line, c, n| {
        var h = engine.hints.read(line) orelse continue;
        // Only a grouping line's words are all device names; the engine's
        // verdicts (`notes`) report the rest.
        if (!h.verb.grouping()) continue;
        while (h.names.next()) |name| {
            if (deviceNamed(deck, c, name) != null) continue;
            const cell = if (c == 0) "the top level" else deck.cell_name[c];
            try warnings.append(a, try a.print("line {d}: `{s}` names {s}, which {s} does not have; the hint holds for the rest", .{ n, h.head, name, cell }));
        }
    }
}

/// Appends cell `c`'s `*@` lines to `text`, its engine deck, each name mapped to the one
/// that deck uses: a device of the cell to `dev_names` (`layout.deviceNames`), a net to
/// `net_names` (`layout.netNames`); any other word as written.
pub fn write(a: Allocator, text: *ArrayList(u8), deck: *const Deck, c: u32, dev_names: []const []const u8, net_names: []const []const u8) Allocator.Error!void {
    const devs = deck.devs(c);
    assert(dev_names.len == devs.len());
    assert(net_names.len == deck.netCount(c));
    for (deck.directive, deck.directive_cell) |line, at| {
        if (at != c) continue;
        var h = engine.hints.read(line) orelse continue;
        try text.appendSlice(a, h.head);
        while (h.names.next()) |word| {
            const mapped = if (deviceNamed(deck, c, word)) |d|
                (if (dev_names[d - devs.lo].len > 0) dev_names[d - devs.lo] else word)
            else if (netNamed(deck, c, word)) |n| net_names[n] else word;
            try text.print(a, " {s}", .{mapped});
        }
        try text.append(a, '\n');
    }
    assert(text.items.len == 0 or text.items[text.items.len - 1] == '\n');
}

/// One import-log line per `*@` line of cell `c` the engine did not honour in `placed`,
/// laid out from `deck_text` (`layout.cellDeck`'s) with `lib`: the designer's line, its
/// verdict, and the lines that blocked it. A grouping line's unknown name is `check`'s.
pub fn notes(gpa: Allocator, a: Allocator, out: *ArrayList([]const u8), deck: *const Deck, c: u32, deck_text: []const u8, placed: *const engine.Placed, lib: *const engine.Library) Allocator.Error!void {
    // The designer's line of each line written, in the order `write` wrote them.
    var lines: ArrayList(u32) = .empty;
    for (deck.directive, deck.directive_cell, deck.directive_line) |line, at, n| {
        if (at == c and engine.hints.read(line) != null) try lines.append(a, n);
    }
    if (lines.items.len == 0) return;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const t = arena_state.allocator();
    var nl = engine.netlist.parse(t, &.{deck_text}, null) catch return;
    const roles = try engine.guessRoles(t, &nl);
    const st = try engine.schematic.structure.analyze(t, t, &nl, roles);
    const sk = try engine.schematic.skeleton.place(t, t, &nl, roles, &st, .{});
    const verdicts = try engine.report.verdicts(t, &nl, roles, &st, &sk, placed, lib);
    assert(verdicts.len == lines.items.len);
    for (nl.hints, verdicts, lines.items) |h, v, n| {
        if (v.state == .honoured) continue;
        if (h.verb.grouping() and v.code == .unknown_name) continue;
        var msg: ArrayList(u8) = .empty;
        try msg.print(a, "line {d}: `{s}` {t} ({t})", .{ n, h.text, v.state, v.code });
        for (v.blocked_by, 0..) |b, k| try msg.print(a, "{s}{d}", .{ if (k == 0) ", blocked by line " else ", ", lines.items[b] });
        try out.append(a, msg.items);
    }
}

// ---- private ----

/// The device of cell `c` named `name`, any case.
fn deviceNamed(deck: *const Deck, c: u32, name: []const u8) ?u32 {
    const devs = deck.devs(c);
    for (devs.lo..devs.hi) |d| if (std.ascii.eqlIgnoreCase(deck.dev_name[d], name)) return @intCast(d);
    return null;
}

/// The net of cell `c` named `name`, any case.
fn netNamed(deck: *const Deck, c: u32, name: []const u8) ?u32 {
    for (0..deck.netCount(c)) |n| if (std.ascii.eqlIgnoreCase(deck.netKey(c, @intCast(n)), name)) return @intCast(n);
    return null;
}
