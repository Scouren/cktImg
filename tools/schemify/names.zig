//! The names a cell's devices have in the deck it hands the engine, and the card each is
//! written as: the designer's own names wherever the engine can read them, so nothing the
//! engine decides depends on the order of the cell's instances, and the cell's `*@` lines
//! map onto them.
//!
//! Contents:
//! - `pub fn deviceNames(a: Allocator, deck: *const Deck, rec: *const Recognized, c: u32) Allocator.Error![]const []const u8`
//! - `pub fn cardOf(a: Allocator, deck: *const Deck, rec: *const Recognized, d: u32) Allocator.Error!struct { card: u8, tail: []const u8 }`

const std = @import("std");
const Allocator = std.mem.Allocator;
const ascii = std.ascii;
const mem = std.mem;
const spice = @import("spice.zig");
const recognize = @import("recognize.zig");
const Deck = spice.Deck;
const Recognized = recognize.Recognized;

/// Per device of cell `c`, the name its engine card has: the designer's, lower case, when
/// it starts with the card's letter and is a plain word; else that letter before it; else
/// `<letter><row>`. Each is unique (a clash takes trailing `_`); empty for a node-less
/// device.
pub fn deviceNames(a: Allocator, deck: *const Deck, rec: *const Recognized, c: u32) Allocator.Error![]const []const u8 {
    const devs = deck.devs(c);
    const out = try a.alloc([]const u8, devs.len());
    var taken: std.StringHashMapUnmanaged(void) = .empty;
    for (devs.lo..devs.hi, 0..) |d, i| {
        out[i] = "";
        if (deck.netsOf(@intCast(d)).len == 0) continue;
        const card = (try cardOf(a, deck, rec, @intCast(d))).card;
        const own = try ascii.allocLowerString(a, deck.dev_name[d]);
        var plain = own.len > 0;
        for (own) |ch| plain = plain and (ascii.isAlphanumeric(ch) or ch == '_');
        var name: []const u8 = if (!plain) try a.print("{c}{d}", .{ card, i }) else if (own[0] == card) own else try a.print("{c}{s}", .{ card, own });
        while ((try taken.getOrPut(a, name)).found_existing) name = try a.print("{s}_", .{name});
        out[i] = name;
    }
    return out;
}

/// The card letter device `d` is written with, and what follows its nets.
pub fn cardOf(a: Allocator, deck: *const Deck, rec: *const Recognized, d: u32) Allocator.Error!struct { card: u8, tail: []const u8 } {
    const syms = &rec.syms;
    const s = rec.parts.sym.items[d];
    const letter = ascii.toLower(deck.dev_name[d][0]);
    const card: u8, const tail: []const u8 = switch (syms.family.items[s]) {
        .two => switch (letter) {
            'r', 'c', 'l', 'd' => .{ letter, "" },
            'v', 'i' => .{ letter, try plainWords(a, deck.dev_rest[d]) },
            else => .{ 'b', "v=0" },
        },
        .nmos => .{ 'm', "nmos" },
        .pmos => .{ 'm', "pmos" },
        .npn => .{ 'q', "npn" },
        .pnp => .{ 'q', "pnp" },
        .vcxs => .{ if (letter == 'g') 'g' else 'e', "1" },
        .vsw => .{ 's', "sw" },
        .tline => .{ 't', "z0=50 td=1n" },
        .box => .{ 'x', try a.print("b{d}", .{s}) },
    };
    return .{ .card = card, .tail = tail };
}

// ---- private ----

/// `text` with every byte the engine's tokenizer would treat specially turned into a
/// space: the words of a source specification (`dc 0 ac 1 pulse 0 1 …`) survive, so the
/// engine can tell a signal source from a supply.
fn plainWords(a: Allocator, text: []const u8) Allocator.Error![]const u8 {
    const out = try a.dupe(u8, text);
    for (out) |*ch| if (!ascii.isAlphanumeric(ch.*) and mem.indexOfScalar(u8, "._+-", ch.*) == null) {
        ch.* = ' ';
    };
    return out;
}
