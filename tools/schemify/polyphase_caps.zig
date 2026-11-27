//! Select a complete four-phase passive RC cell from actual host bindings.
//!
//! Contents:
//! - `pub const strokes`
//! - `pub fn match`, `pub fn requested`

const std = @import("std");
const engine = @import("NetlistParser");
const rec = @import("recognize.zig");
const spice = @import("spice.zig");

/// Schemify xschem-unit ink with actual contacts at (−21,−21) and (+21,+21).
pub const strokes = [_]engine.library.DrawOp{
    .ln(-21, -21, -3, -3), .ln(21, 21, 3, 3), .ln(-12, 6, 6, -12), .ln(-6, 12, 12, -6),
};

/// Returns the ordered poses only when every device binds the core passive
/// it represents. Any explicit cell directive or pin direction retains the
/// editor's original symbol and layout choice.
pub fn match(deck: *const spice.Deck, r: *const rec.Recognized, c: u32) ?engine.polyphase_caps.Layout {
    const ds = deck.devs(c);
    if (ds.len() != 16 or deck.ports(c).len != 8) return null;
    if (std.mem.indexOfScalar(u16, deck.directive_cell, @intCast(c)) != null or std.mem.indexOfScalar(u16, deck.code_cell, @intCast(c)) != null) return null;
    var ports: [8]engine.polyphase_caps.Port = undefined;
    for (&ports, deck.ports(c)) |*p, n| {
        const name = deck.netKey(c, n);
        if (deck.pinInfo(name) != null) return null;
        p.* = .{ .net = n, .name = name };
    }
    var parts: [16]engine.polyphase_caps.Part = undefined;
    for (&parts, ds.lo..ds.hi) |*p, d| {
        const id = r.parts.sym.items[d];
        const nets = deck.netsOf(@intCast(d));
        if (r.syms.origin.items[id] != .core or nets.len != 2) return null;
        const name = r.syms.stem.items[id];
        const cap = std.mem.eql(u8, name, "cap");
        if (!cap and !std.mem.eql(u8, name, "res")) return null;
        p.* = .{ .cap = cap, .nets = nets[0..2].* };
    }
    return engine.polyphase_caps.match(&parts, &ports);
}

/// Highest-priority native or oblique capacitor class explicitly requested for
/// this real core capacitor; later lines win among equally strong directives.
pub fn requested(deck: *const spice.Deck, c: u32, name: []const u8) bool {
    var chosen = false;
    var strong = false;
    for (deck.directive, deck.directive_cell) |line, cell| {
        if (cell != c) continue;
        var hint = engine.hints.read(line) orelse continue;
        if (hint.verb != .class or (strong and hint.weak)) continue;
        const owner = hint.names.next() orelse continue;
        const class = hint.names.next() orelse continue;
        if (hint.names.next() != null or !std.ascii.eqlIgnoreCase(owner, name)) continue;
        if (std.ascii.eqlIgnoreCase(class, "cap_oblique")) chosen = true else if (std.ascii.eqlIgnoreCase(class, "cap")) chosen = false else continue;
        strong = !hint.weak;
    }
    return chosen;
}
