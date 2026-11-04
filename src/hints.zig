//! A deck's `*@` lines (issue #7, docs/research/vocabulary.md): what the
//! circuit means and how it is drawn, stated by name, one line each:
//!
//!     *@ [weak] <verb> <arguments>
//!     *@ group pair m1 m2        (also mirror, bank, stack, cross)
//!     *@ above m9 iss m7         m9 above iss above m7
//!     *@ face m3 g left          m3's gate on its left
//!
//! A line is strong, or with `weak` a stay; either is honoured or reported
//! (`Verdict`), never dropped in silence. Each stage applies the lines it
//! owns and says what became of each; `report` gathers the verdicts.
//!
//! Contents:
//! - `Verb`, `Verb.grouping(v: Verb) bool`, `Verb.rung(v: Verb) u8`
//! - `Hint`, `Read`, `State`, `Code`, `Verdict`
//! - `pub fn read(line: []const u8) ?Read`
//! - `pub fn collect(arena: Allocator, text: []const u8) Allocator.Error![]const Hint`
//! - `pub fn admitOrder(arena: Allocator, list: []const Hint) Allocator.Error![]const u32`
//! - `pub fn applyOrder(gpa: Allocator, list: []const Hint) Allocator.Error![]const u32`
//! - `pub fn conflict(gpa: Allocator, arena: Allocator, check: anytype, admitted: []const u32, new: u32, code: Code) Allocator.Error!Verdict`
//! - `pub fn int(word: []const u8) ?i32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.ascii.eqlIgnoreCase;

/// Every verb, by rung (docs/research/vocabulary.md). The first seven are
/// the grouping hints: `group <kind>`, `nogroup`, `grouping off`.
pub const Verb = enum(u8) {
    pair,
    mirror,
    bank,
    stack,
    cross,
    nogroup,
    off,
    role,
    kind,
    class,
    symmetric,
    axis,
    symmetry_off,
    driver,
    expand,
    row,
    above,
    order,
    upright,
    bridge,
    face,
    label,
    wire,
    port,
    rail,
    first,
    cell,
    at,
    refdes,
    via,
    route,
    /// A `*@` line of no known verb: rejected.
    unknown,

    /// A grouping hint (rung 1), the lines the Schemify import carries.
    pub fn grouping(v: Verb) bool {
        return @backingInt(v) <= @backingInt(Verb.off);
    }

    /// The rung a verb stands on: 1 meaning, 2 relations, 3 cells, 4
    /// geometry, 5 wires; 0 for `unknown`.
    pub fn rung(v: Verb) u8 {
        if (v == .unknown) return 0;
        if (@backingInt(v) <= @backingInt(Verb.expand)) return 1;
        if (@backingInt(v) <= @backingInt(Verb.first)) return 2;
        return switch (v) {
            .cell => 3,
            .at, .refdes => 4,
            else => 5,
        };
    }
};

pub const Hint = struct {
    verb: Verb,
    /// Starts with `weak`: a stay, below every strong line.
    weak: bool,
    /// Its arguments as written, split at blanks and commas.
    args: []const []const u8,
    /// 1-based line in the text read.
    line: u32,
    /// The whole line, trimmed.
    text: []const u8,
};

/// What a hint line states.
pub const Read = struct {
    verb: Verb,
    weak: bool,
    /// The line up to its arguments (`*@ group pair`), as written.
    head: []const u8,
    /// Its arguments, split at blanks and commas.
    names: std.mem.TokenIterator(u8, .any),
};

/// What became of a line. Every line ends in exactly one.
pub const State = enum(u8) {
    /// Drawn as it says.
    honoured,
    /// Met in part (`Verdict.code` says how).
    relaxed,
    /// Valid, but it conflicts with stronger lines (`blocked_by`) or a
    /// guarantee.
    dropped,
    /// Malformed or naming what the deck does not have; nothing changed.
    rejected,
};

pub const Code = enum(u8) {
    ok,
    /// No such verb.
    unknown_verb,
    /// A device, net or pin the deck does not have.
    unknown_name,
    /// Too few or malformed arguments.
    bad_args,
    /// A device the verb cannot place: a driver, a card with no pins, a
    /// bridge where only a column device can stand.
    not_placeable,
    /// It would close a cycle with the lines in `blocked_by`.
    cycle,
    /// It cannot hold together with the lines in `blocked_by`.
    conflict,
    /// Its devices are in the stronger lines' groups (`blocked_by`).
    taken,
    /// No symmetry of the circuit swaps what it names.
    asymmetric,
    /// No free cell where it asks.
    no_room,
    /// The engine took it, but the finished drawing does not show it: a
    /// bug, caught by `checks.drawnAs`.
    not_drawn,
    /// A verb on a rung the engine does not take yet.
    not_built,
};

pub const Verdict = struct {
    state: State,
    code: Code,
    /// The stronger lines (indices into the deck's hints) that, with this
    /// one, cannot hold; no proper subset blocks it.
    blocked_by: []const u32 = &.{},
    /// Per `blocked_by` member: deleting it alone would admit this line.
    alone: []const bool = &.{},
};

/// The hint `line` states (any case, blanks around it allowed), its verb
/// `unknown` when no verb fits; null for a line that is no `*@` line.
pub fn read(line: []const u8) ?Read {
    const t = std.mem.trim(u8, line, " \t\r");
    if (!std.mem.startsWith(u8, t, "*@")) return null;
    var it = std.mem.tokenizeAny(u8, t[2..], " \t\r,");
    var word = it.next() orelse return .{ .verb = .unknown, .weak = false, .head = t, .names = it };
    const weak = eql(word, "weak");
    if (weak) word = it.next() orelse return .{ .verb = .unknown, .weak = true, .head = t, .names = it };
    const verb = verbOf(word, &it);
    assert(it.index <= t.len - 2);
    return .{ .verb = verb, .weak = weak, .head = t[0 .. 2 + it.index], .names = it };
}

/// The hints of `text`'s top level, in line order: the lines inside a
/// `.subckt` are its own hints, and the first line is the title. The result
/// borrows `text`.
pub fn collect(arena: Allocator, text: []const u8) Allocator.Error![]const Hint {
    var out: std.ArrayList(Hint) = .empty;
    var depth: u32 = 0;
    var line: u32 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        line += 1;
        if (line == 1) continue;
        var words = std.mem.tokenizeAny(u8, raw, " \t\r");
        const first = words.next() orelse continue;
        if (eql(first, ".subckt")) depth += 1;
        if (eql(first, ".ends")) depth -|= 1;
        if (depth > 0) continue;
        var h = read(raw) orelse continue;
        var args: std.ArrayList([]const u8) = .empty;
        while (h.names.next()) |n| try args.append(arena, n);
        try out.append(arena, .{ .verb = h.verb, .weak = h.weak, .args = args.items, .line = line, .text = std.mem.trim(u8, raw, " \t\r") });
    }
    assert(depth <= line);
    var last: u32 = 1;
    for (out.items) |h| {
        assert(h.line > last and h.line <= line);
        last = h.line;
    }
    return out.items;
}

/// The order lines are admitted in, as indices into `list`: strong before
/// weak, the later line first within a strength (a later line overrides an
/// earlier one).
pub fn admitOrder(arena: Allocator, list: []const Hint) Allocator.Error![]const u32 {
    const out = try arena.alloc(u32, list.len);
    var at: usize = 0;
    for ([_]bool{ false, true }) |weak| {
        var i = list.len;
        while (i > 0) {
            i -= 1;
            if (list[i].weak != weak) continue;
            out[at] = @intCast(i);
            at += 1;
        }
    }
    assert(at == list.len);
    return out;
}

/// The order lines that set one value are applied in, the least preferred
/// first, so the line `admitOrder` puts first is the one left standing.
/// The caller frees the result.
pub fn applyOrder(gpa: Allocator, list: []const Hint) Allocator.Error![]const u32 {
    const order = try admitOrder(gpa, list);
    const out = @constCast(order);
    std.mem.reverse(u32, out);
    return out;
}

/// The verdict of line `new`, which cannot join the `admitted` lines (hint
/// indices, most preferred first): dropped, `blocked_by` its preferred
/// conflict (Junker: from the least preferred line up, each line it still
/// conflicts without is left out), each member flagged `alone` when
/// deleting it by itself admits `new`. `check.holds(lines)` says whether a
/// set of lines holds together.
pub fn conflict(gpa: Allocator, arena: Allocator, check: anytype, admitted: []const u32, new: u32, code: Code) Allocator.Error!Verdict {
    var keep: std.ArrayList(u32) = .empty;
    defer keep.deinit(gpa);
    try keep.appendSlice(gpa, admitted);
    var trial: std.ArrayList(u32) = .empty;
    defer trial.deinit(gpa);
    var j = keep.items.len;
    while (j > 0) {
        j -= 1;
        trial.clearRetainingCapacity();
        for (keep.items, 0..) |k, at| if (at != j) try trial.append(gpa, k);
        try trial.append(gpa, new);
        if (!try check.holds(trial.items)) _ = keep.orderedRemove(j);
    }
    const solo = try arena.alloc(bool, keep.items.len);
    for (keep.items, solo) |b, *a| {
        trial.clearRetainingCapacity();
        for (admitted) |k| if (k != b) try trial.append(gpa, k);
        try trial.append(gpa, new);
        a.* = try check.holds(trial.items);
    }
    assert(keep.items.len <= admitted.len);
    return .{ .state = .dropped, .code = code, .blocked_by = try arena.dupe(u32, keep.items), .alone = solo };
}

/// A whole number, or null.
pub fn int(word: []const u8) ?i32 {
    return std.fmt.parseInt(i32, word, 10) catch null;
}

// ---- private ----

/// The verb `word` names, reading a second word where the verb has two
/// (`group pair`, `grouping off`, `symmetry off`).
fn verbOf(word: []const u8, it: *std.mem.TokenIterator(u8, .any)) Verb {
    if (eql(word, "group")) {
        const kind = it.next() orelse return .unknown;
        inline for (.{ Verb.pair, .mirror, .bank, .stack, .cross }) |v| {
            if (eql(kind, @tagName(v))) return v;
        }
        return .unknown;
    }
    if (eql(word, "grouping")) return if (eql(it.next() orelse "", "off")) .off else .unknown;
    if (eql(word, "symmetry")) return if (eql(it.next() orelse "", "off")) .symmetry_off else .unknown;
    var buf: [16]u8 = undefined;
    if (word.len > buf.len) return .unknown;
    const v = std.meta.stringToEnum(Verb, std.ascii.lowerString(&buf, word)) orelse return .unknown;
    // Two-word verbs are read above, never by their tag.
    return switch (v) {
        .pair, .mirror, .bank, .stack, .cross, .off, .symmetry_off => .unknown,
        else => v,
    };
}

test "read: the forms, weak, and what is no verb" {
    var g = read("*@ group pair M1, M2").?;
    try std.testing.expectEqual(Verb.pair, g.verb);
    try std.testing.expect(!g.weak);
    try std.testing.expectEqualStrings("*@ group pair", g.head);
    try std.testing.expectEqualStrings("M1", g.names.next().?);
    try std.testing.expectEqualStrings("M2", g.names.next().?);
    try std.testing.expectEqual(null, g.names.next());
    try std.testing.expectEqual(Verb.nogroup, read("  *@NoGroup m9").?.verb);
    try std.testing.expectEqual(Verb.off, read("*@ grouping off").?.verb);
    try std.testing.expectEqual(Verb.symmetry_off, read("*@ symmetry off").?.verb);
    try std.testing.expectEqual(Verb.above, read("*@ above m9 iss").?.verb);
    const w = read("*@ weak cell m5 2 4").?;
    try std.testing.expectEqual(Verb.cell, w.verb);
    try std.testing.expect(w.weak);
    for ([_][]const u8{ "*@ group pairs m1 m2", "*@ group", "*@ grouping on", "*@ left a b", "*@", "*@ weak" }) |l|
        try std.testing.expectEqual(Verb.unknown, read(l).?.verb);
    for ([_][]const u8{ "* group pair m1 m2", "m1 a b c d nch" }) |l| try std.testing.expectEqual(null, read(l));
    try std.testing.expectEqual(@as(u8, 1), Verb.symmetric.rung());
    try std.testing.expectEqual(@as(u8, 2), Verb.face.rung());
    try std.testing.expectEqual(@as(u8, 5), Verb.route.rung());
}

test "admitOrder: strong before weak, later first" {
    const h = [_]Hint{
        .{ .verb = .row, .weak = true, .args = &.{}, .line = 2, .text = "" },
        .{ .verb = .row, .weak = false, .args = &.{}, .line = 3, .text = "" },
        .{ .verb = .row, .weak = false, .args = &.{}, .line = 4, .text = "" },
        .{ .verb = .row, .weak = true, .args = &.{}, .line = 5, .text = "" },
    };
    const o = try admitOrder(std.testing.allocator, &h);
    defer std.testing.allocator.free(o);
    try std.testing.expectEqualSlices(u32, &.{ 2, 1, 3, 0 }, o);
}
