//! The grouping hints of a deck (issue #7), in the `*@` style of the
//! block-side directives:
//!
//!     *@ group pair m1 m2        (also mirror, bank, stack, cross)
//!     *@ nogroup m9              out of every group
//!     *@ grouping off            no recognized groups, the hinted ones only
//!
//! `structure` applies them; the Schemify plugin reads them with `read` to
//! carry a subckt's hints into the deck it hands the engine.
//!
//! Contents:
//! - `Verb`, `Hint`, `Read`
//! - `pub fn read(line: []const u8) ?Read`
//! - `pub fn collect(arena: Allocator, text: []const u8) Allocator.Error![]const Hint`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const eql = std.ascii.eqlIgnoreCase;

pub const Verb = enum { pair, mirror, bank, stack, cross, nogroup, off };

pub const Hint = struct {
    verb: Verb,
    /// Device names as written.
    devices: []const []const u8,
    /// 1-based line in the text read.
    line: u32,
};

/// What a hint line states.
pub const Read = struct {
    verb: Verb,
    /// The line up to its device names (`*@ group pair`), as written.
    head: []const u8,
    /// Its device names, split at blanks and commas.
    names: std.mem.TokenIterator(u8, .any),
};

/// The hint `line` states (any case, blanks around it allowed); null for any
/// other line, a group of no known kind among them.
pub fn read(line: []const u8) ?Read {
    const t = std.mem.trim(u8, line, " \t\r");
    if (!std.mem.startsWith(u8, t, "*@")) return null;
    var it = std.mem.tokenizeAny(u8, t[2..], " \t\r,");
    const word = it.next() orelse return null;
    const verb: Verb = if (eql(word, "group")) kind: {
        const kind = it.next() orelse return null;
        inline for (.{ Verb.pair, .mirror, .bank, .stack, .cross }) |v| {
            if (eql(kind, @tagName(v))) break :kind v;
        }
        return null;
    } else if (eql(word, "nogroup"))
        .nogroup
    else if (eql(word, "grouping") and eql(it.next() orelse "", "off"))
        .off
    else
        return null;
    assert(it.index <= t.len - 2);
    return .{ .verb = verb, .head = t[0 .. 2 + it.index], .names = it };
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
        var devices: std.ArrayList([]const u8) = .empty;
        while (h.names.next()) |n| try devices.append(arena, n);
        try out.append(arena, .{ .verb = h.verb, .devices = devices.items, .line = line });
    }
    assert(depth <= line);
    var last: u32 = 1;
    for (out.items) |h| {
        assert(h.line > last and h.line <= line);
        last = h.line;
    }
    return out.items;
}

test "read: the three forms, and what is no hint" {
    var g = read("*@ group pair M1, M2").?;
    try std.testing.expectEqual(Verb.pair, g.verb);
    try std.testing.expectEqualStrings("*@ group pair", g.head);
    try std.testing.expectEqualStrings("M1", g.names.next().?);
    try std.testing.expectEqualStrings("M2", g.names.next().?);
    try std.testing.expectEqual(null, g.names.next());
    try std.testing.expectEqual(Verb.nogroup, read("  *@NoGroup m9").?.verb);
    try std.testing.expectEqual(Verb.off, read("*@ grouping off").?.verb);
    for ([_][]const u8{ "*@ group pairs m1 m2", "*@ group", "*@ grouping on", "*@ left a b", "* group pair m1 m2", "m1 a b c d nch" }) |l|
        try std.testing.expectEqual(null, read(l));
}
