//! A cell's grouping hints (`*@ group pair M1 M2`, issue #7; the engine's
//! `hints` reads them): checked against the cell's devices for the import
//! log, and carried into the deck the cell hands the engine under the names
//! that deck gives its devices.
//!
//! Contents:
//! - `pub fn check(a: Allocator, deck: *const Deck, warnings: *ArrayList([]const u8)) Allocator.Error!void`
//! - `pub fn write(a: Allocator, text: *ArrayList(u8), deck: *const Deck, c: u32, cards: []const u8) Allocator.Error!void`

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
        // ponytail: the grouping verbs only; the rest wait for the designer's
        // names in the engine deck (steering slice 7), which need no renaming.
        if (!h.verb.grouping()) continue;
        while (h.names.next()) |name| {
            if (deviceNamed(deck, c, name) != null) continue;
            const cell = if (c == 0) "the top level" else deck.cell_name[c];
            try warnings.append(a, try a.print("line {d}: `{s}` names {s}, which {s} does not have; the hint holds for the rest", .{ n, h.head, name, cell }));
        }
    }
}

/// Appends cell `c`'s hints to `text`, its engine deck, with each device by
/// the name that deck gives it: `<cards[i]><i>` for the cell's device `i`,
/// none when `cards[i]` is 0 (a device the deck leaves out). A name the cell
/// does not have is dropped (`check` logs it).
pub fn write(a: Allocator, text: *ArrayList(u8), deck: *const Deck, c: u32, cards: []const u8) Allocator.Error!void {
    const devs = deck.devs(c);
    assert(cards.len == devs.len());
    for (deck.directive, deck.directive_cell) |line, at| {
        if (at != c) continue;
        var h = engine.hints.read(line) orelse continue;
        if (!h.verb.grouping()) continue;
        try text.appendSlice(a, h.head);
        while (h.names.next()) |name| {
            const i = (deviceNamed(deck, c, name) orelse continue) - devs.lo;
            if (cards[i] != 0) try text.print(a, " {c}{d}", .{ cards[i], i });
        }
        try text.append(a, '\n');
    }
    assert(text.items.len == 0 or text.items[text.items.len - 1] == '\n');
}

// ---- private ----

/// The device of cell `c` named `name`, any case.
fn deviceNamed(deck: *const Deck, c: u32, name: []const u8) ?u32 {
    const devs = deck.devs(c);
    for (devs.lo..devs.hi) |d| if (std.ascii.eqlIgnoreCase(deck.dev_name[d], name)) return @intCast(d);
    return null;
}
