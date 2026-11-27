//! A deck's `*@` lines (issue #7, docs/research/vocabulary.md): what the
//! circuit means and how it is drawn, stated by name, one line each:
//!
//!     *@ [weak] <verb> <arguments>
//!     *@ group pair m1 m2        (also mirror, bank, stack, cross)
//!     *@ above m9 iss m7         m9 above iss above m7
//!     *@ face m3 g left          m3's gate on its left
//!     *@ hang c1 m3.g            c1 hung from m3's gate
//!
//! Each stage applies the lines it owns and says what became of each;
//! `report` gathers the verdicts. What each verb draws is the rule of the
//! stage that owns it.
//!
//! Human Rules:
//! - hints.1 (invariant) A `*@` line is drawn as it says, or the report
//!   says it was relaxed, dropped or rejected and why; none is dropped in
//!   silence. `Verdict`
//! - hints.2 (choice) A strong line outranks a stay (`weak`), and a later
//!   line an earlier one of the same strength: a deck is edited by adding
//!   a line. `admitOrder`, `applyOrder`
//! - hints.3 (invariant) Lines that set an order (one thing above or left
//!   of another) are drawn only while they close no cycle; the line that
//!   would is dropped, naming the stronger lines it conflicts with.
//!   `acyclic`, `conflict`
//!
//! Contents:
//! - `Verb`, `Verb.grouping(v: Verb) bool`, `Verb.rung(v: Verb) u8`, `Verb.head(v: Verb, strength: enum { strong, weak }) []const u8`, `Verb.side(v: Verb, comptime T: type, word: []const u8) ?T`
//! - `Hint`, `Read`, `State`, `Code`, `Verdict`, `Verdict.of(code: Code) Verdict`, `Verdict.blocked(arena: Allocator, state: State, code: Code, by: []const u32) Allocator.Error!Verdict`
//! - `pub fn read(line: []const u8) ?Read`
//! - `pub fn collect(arena: Allocator, text: []const u8) Allocator.Error![]const Hint`
//! - `pub fn nesting(depth: u32, head: []const u8, open: []const u8, close: []const u8) u32`
//! - `pub fn admitOrder(arena: Allocator, list: []const Hint) Allocator.Error![]const u32`
//! - `pub fn applyOrder(gpa: Allocator, list: []const Hint) Allocator.Error![]const u32`
//! - `pub fn conflict(gpa: Allocator, arena: Allocator, check: anytype, admitted: []const u32, new: u32, code: Code) Allocator.Error!Verdict`
//! - `pub fn acyclic(gpa: Allocator, n: usize, edges: []const [2]u32) Allocator.Error!bool`
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
    hang,
    label,
    wire,
    port,
    rail,
    shelf,
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
        // The last verb of each rung: the enum is in rung order.
        for ([_]Verb{ .expand, .first, .cell, .refdes, .route }, 1..) |last, r| {
            if (@backingInt(v) <= @backingInt(last)) return @intCast(r);
        }
        return 0;
    }

    /// The head of a line of this verb, the text `read` reads the verb back
    /// from: `*@ group pair`, `*@ row`, and a stay's, `*@ weak cell`.
    pub fn head(v: Verb, strength: enum { strong, weak }) []const u8 {
        return switch (v) {
            inline else => |k| if (strength == .weak) "*@ weak " ++ comptime spelling(k) else "*@ " ++ comptime spelling(k),
        };
    }

    /// The side `word` names in this verb's idiom, as the tag of `T`, any
    /// enum of the four sides in the order left, right, up, down: `face`
    /// says left right up down, `port` (and a definition's own port lines)
    /// left right top bottom, `refdes` left right above below. Null for any
    /// other word; the case is exact, as a deck is read lowercased. Asserts
    /// the verb is one of the three.
    pub fn side(v: Verb, comptime T: type, word: []const u8) ?T {
        comptime assert(std.enums.values(T).len == 4);
        const words: [4][]const u8 = switch (v) {
            .face => .{ "left", "right", "up", "down" },
            .port => .{ "left", "right", "top", "bottom" },
            .refdes => .{ "left", "right", "above", "below" },
            else => unreachable,
        };
        for (words, 0..) |w, i| if (std.mem.eql(u8, w, word)) return @as(T, @fromBackingInt(@intCast(i)));
        return null;
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
    /// It would break a guarantee (a symbol on another, a wire on another
    /// net's point, a route off its net's pins): refused.
    guarantee,
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

    /// The verdict of a line read with `code`: honoured when it is `ok`,
    /// else rejected.
    pub fn of(code: Code) Verdict {
        return .{ .state = if (code == .ok) .honoured else .rejected, .code = code };
    }

    /// The verdict of a line that gives way (`state`: dropped or relaxed) to
    /// the lines `by`, each alone blocking it. Copies `by` into `arena`.
    pub fn blocked(arena: Allocator, state: State, code: Code, by: []const u32) Allocator.Error!Verdict {
        const solo = try arena.alloc(bool, by.len);
        @memset(solo, true);
        return .{ .state = state, .code = code, .blocked_by = try arena.dupe(u32, by), .alone = solo };
    }
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
        depth = nesting(depth, words.next() orelse continue, ".subckt", ".ends");
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

/// The depth in nested blocks after a line whose first word is `head` (any
/// case): one deeper after `open`, one back after `close` and never above
/// the top level, else `depth`. The one count of `.subckt ... .ends`, for
/// the hints and the parser.
pub fn nesting(depth: u32, head: []const u8, open: []const u8, close: []const u8) u32 {
    if (eql(head, open)) return depth + 1;
    if (eql(head, close)) return depth -| 1;
    return depth;
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

/// Whether `edges` (`[a, b]`: a before b) hold together as an order: they
/// close no cycle (Kahn). The one test of both orders: `sequence`'s column
/// lines and, among the rows' classes, `relations`'. Asserts that the edges
/// name at most `n` nodes. Quadratic in the edges, a deck's handful.
pub fn acyclic(gpa: Allocator, n: usize, edges: []const [2]u32) Allocator.Error!bool {
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(gpa);
    for (edges) |e| for (e) |d| if (std.mem.indexOfScalar(u32, list.items, d) == null) try list.append(gpa, d);
    const nodes = list.items;
    assert(nodes.len <= n);
    const indeg = try gpa.alloc(u32, nodes.len);
    defer gpa.free(indeg);
    @memset(indeg, 0);
    for (edges) |e| indeg[std.mem.indexOfScalar(u32, nodes, e[1]).?] += 1;
    var queue: std.ArrayList(u32) = .empty;
    defer queue.deinit(gpa);
    for (indeg, 0..) |d, k| if (d == 0) try queue.append(gpa, @intCast(k));
    var done: usize = 0;
    while (queue.pop()) |k| {
        done += 1;
        for (edges) |e| if (e[0] == nodes[k]) {
            const t = std.mem.indexOfScalar(u32, nodes, e[1]).?;
            indeg[t] -= 1;
            if (indeg[t] == 0) try queue.append(gpa, @intCast(t));
        };
    }
    assert(done <= nodes.len);
    return done == nodes.len;
}

/// A whole number, or null.
pub fn int(word: []const u8) ?i32 {
    return std.fmt.parseInt(i32, word, 10) catch null;
}

// ---- private ----

/// The verb as written after `*@`: its tag, a group's kind after `group`,
/// the two `off` lines. The one table `Verb.head` writes and `verbOf` reads.
fn spelling(v: Verb) []const u8 {
    return switch (v) {
        inline .pair, .mirror, .bank, .stack, .cross => |k| "group " ++ @tagName(k),
        .off => "grouping off",
        .symmetry_off => "symmetry off",
        else => @tagName(v),
    };
}

/// The verb whose spelling starts with `word`, reading a second word where
/// the spelling has two (`group pair`, `grouping off`, `symmetry off`).
fn verbOf(word: []const u8, it: *std.mem.TokenIterator(u8, .any)) Verb {
    var second: ?[]const u8 = null;
    for (std.enums.values(Verb)) |v| {
        const s = spelling(v);
        const cut = std.mem.indexOfScalar(u8, s, ' ') orelse s.len;
        if (!eql(s[0..cut], word)) continue;
        if (cut == s.len) return v;
        second = second orelse it.next() orelse return .unknown;
        if (eql(s[cut + 1 ..], second.?)) return v;
    }
    return .unknown;
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

test "head: every verb's line reads back as written; side: the three idioms" {
    for (std.enums.values(Verb)) |v| {
        const r = read(v.head(.weak)).?;
        try std.testing.expect(r.verb == v and r.weak and read(v.head(.strong)).?.verb == v);
        try std.testing.expectEqualStrings(v.head(.weak), r.head);
    }
    const Side = enum { left, right, up, down };
    try std.testing.expectEqual(Side.up, Verb.face.side(Side, "up").?);
    try std.testing.expectEqual(Side.down, Verb.port.side(Side, "bottom").?);
    try std.testing.expectEqual(Side.down, Verb.refdes.side(Side, "below").?);
    try std.testing.expectEqual(null, Verb.face.side(Side, "above"));
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
