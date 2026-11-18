//! Select the signed frame where the original cell and every use are known.
//!
//! Contents: `select`.

const std = @import("std");
const engine = @import("NetlistParser");
const rec = @import("recognize.zig");
const Deck = @import("spice.zig").Deck;

/// A generated Schemify cell has one symbol. Choose positive-above only if
/// every use across the imported hierarchy independently requests it.
pub fn select(a: std.mem.Allocator, deck: *const Deck, recognized: *rec.Recognized) std.mem.Allocator.Error!void {
    const syms = &recognized.syms;
    const uses = try a.alloc(u32, syms.len());
    @memset(uses, 0);
    for (recognized.parts.sym.items) |s| uses[s] += 1;
    const wanted = try a.alloc(u32, syms.len());
    @memset(wanted, 0);
    for (1..deck.cells()) |ci| {
        const cell: u32 = @intCast(ci);
        const range = deck.devs(cell);
        const actual = recognized.parts.sym.items[range.lo..range.hi];
        if (range.len() < 4 or !(for (actual) |s| {
            if (capable(syms, s)) break true;
        } else false)) continue;
        const cards = try a.alloc(engine.regulator.Card, actual.len);
        const counts = try a.alloc(u8, deck.netCount(cell));
        @memset(counts, 0);
        for (cards, actual, range.lo..) |*card, s, d| {
            const nets = deck.netsOf(@intCast(d));
            for (nets) |net| counts[net] +|= 1;
            card.* = .{ .nets = nets, .kind = switch (std.ascii.toLower(deck.dev_name[d][0])) {
                'x' => if (capable(syms, s)) .amplifier else .other,
                'r' => .resistor,
                'c' => .capacitor,
                'm' => kind: {
                    if (syms.family.items[s] != .nmos) break :kind .other;
                    var words = std.mem.tokenizeAny(u8, deck.dev_rest[d], " \t");
                    const model = words.next() orelse break :kind .other;
                    break :kind if (std.ascii.eqlIgnoreCase(deck.modelKind(model) orelse model, "nmos")) .nmos else .other;
                },
                else => .other,
            } };
        }
        var holds: ?[]const bool = null;
        for (cards, actual, 0..) |card, s, d| {
            if (card.kind != .amplifier) continue;
            var words: [9][]const u8 = undefined;
            const ports = portNames(syms, s, &words);
            const external = deck.ports(cell);
            if (cards.len == 6 and engine.regulator.positiveAbove(cards[0..6].*, ports, external)) {
                if (std.mem.indexOfScalar(u16, deck.directive_cell, @intCast(cell)) == null and
                    std.mem.indexOfScalar(u16, deck.code_cell, @intCast(cell)) == null) wanted[s] += 1;
                continue;
            }
            if (cards.len != 4 and uses[s] < 2) continue;
            const own = engine.regulator.localOwner(cards, d, ports, external, counts) orelse continue;
            const members = [_]u32{ @intCast(d), own[0], own[1], own[2] };
            if (holds == null) holds = try held(a, deck, recognized, cell);
            const owned = holds.?;
            if (owned.len != 0 and (for (members) |m| {
                if (owned[m]) break true;
            } else false)) continue;
            wanted[s] += 1;
        }
    }
    for (wanted, uses, 0..) |accepted, total, i| {
        if (accepted == 0 or accepted != total) continue;
        const s: u32 = @intCast(i);
        var words: [9][]const u8 = undefined;
        const glyph = try engine.block_symbols.draw(a, .regulator_amplifier, portNames(syms, s, &words), 20);
        const pins = syms.pin.items[syms.pin_start.items[s]..syms.pin_start.items[s + 1]];
        for (pins, glyph.terminals) |*p, term| {
            p.x = term.at.x;
            p.y = term.at.y;
        }
        syms.shape.items[s] = .regulator_amplifier;
    }
}

// ---- private ----

fn capable(syms: *const rec.Symbols, s: u32) bool {
    return syms.origin.items[s] == .sub and switch (syms.shape.items[s]) {
        .amplifier, .four_bias_amplifier => true,
        else => false,
    };
}

fn portNames(syms: *const rec.Symbols, s: u32, buf: *[9][]const u8) []const []const u8 {
    const pins = syms.pins(s);
    std.debug.assert(pins.len <= buf.len);
    for (pins, buf[0..pins.len]) |pin, *name| name.* = pin.name;
    return buf[0..pins.len];
}

fn held(a: std.mem.Allocator, deck: *const Deck, recognized: *const rec.Recognized, cell: u32) std.mem.Allocator.Error![]const bool {
    for (deck.directive, deck.directive_cell) |line, c| {
        if (c != cell) continue;
        const h = engine.hints.read(line) orelse continue;
        switch (h.verb) {
            .at, .cell, .face, .class => break,
            else => {},
        }
    } else return &.{};
    const layout = @import("layout.zig");
    const owned = try a.alloc(bool, deck.devs(cell).len());
    @memset(owned, true);
    if (owned.len > layout.cell_devices_max) return owned;
    var local = std.heap.ArenaAllocator.init(a);
    defer local.deinit();
    const scratch = local.allocator();
    var warnings: std.ArrayList([]const u8) = .empty;
    var symbols = try layout.library(scratch, scratch, recognized, &warnings);
    defer symbols.deinit();
    const names = try layout.netNames(scratch, deck, cell);
    const text = try layout.cellDeck(scratch, deck, recognized, cell, names);
    var nl = engine.netlist.parse(scratch, &.{text}, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return owned,
    };
    defer nl.deinit(scratch);
    const active = engine.regulator.held(scratch, &nl, &symbols, &.default) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return owned,
    };
    if (active.len == 0) return &.{};
    for (try @import("names.zig").deviceNames(scratch, deck, recognized, cell), owned) |name, *flag| {
        const e = nl.device(name) orelse continue;
        flag.* = active[e.index()];
    }
    return owned;
}
