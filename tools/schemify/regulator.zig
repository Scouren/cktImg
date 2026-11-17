//! Select the signed frame while both original .subckt interfaces and the
//! generated symbol's electrical identity are known.
//!
//! Contents: `select`.

const std = @import("std");
const engine = @import("NetlistParser");
const rec = @import("recognize.zig");
const Deck = @import("spice.zig").Deck;

/// Assigns the positive-above frame to a generated amplifier only when
/// its sole instance is certified. A shared .shcomp has one symbol for all
/// uses and keeps its existing geometry. All allocations belong to `a`.
pub fn select(a: std.mem.Allocator, deck: *const Deck, recognized: *rec.Recognized) std.mem.Allocator.Error!void {
    const steered: u8 = 4;
    var usage: ?[]u8 = null;
    for (1..deck.cells()) |index| {
        const cell: u32 = @intCast(index);
        const range = deck.devs(cell);
        if (range.len() != 6) continue;
        var cards: [6]engine.regulator.Card = undefined;
        var symbol: ?u32 = null;
        for (&cards, range.lo..range.hi) |*card, d| {
            const s = recognized.parts.sym.items[d];
            const syms = &recognized.syms;
            const kind: @FieldType(engine.regulator.Card, "kind") = switch (std.ascii.toLower(deck.dev_name[d][0])) {
                'x' => kind: {
                    if (syms.origin.items[s] != .sub or syms.shape.items[s] != .amplifier) break;
                    symbol = s;
                    break :kind .amplifier;
                },
                'r' => .resistor,
                'c' => .capacitor,
                'm' => kind: {
                    if (syms.family.items[s] != .nmos) break;
                    var words = std.mem.tokenizeAny(u8, deck.dev_rest[d], " \t");
                    const model = words.next() orelse break;
                    if (!std.ascii.eqlIgnoreCase(deck.modelKind(model) orelse model, "nmos")) break;
                    break :kind .nmos;
                },
                else => break,
            };
            card.* = .{ .kind = kind, .nets = deck.netsOf(@intCast(d)) };
        } else {
            const s = symbol orelse continue;
            const syms = &recognized.syms;
            const pins = syms.pin.items[syms.pin_start.items[s]..syms.pin_start.items[s + 1]];
            if (pins.len > 8) continue;
            var ports: [8][]const u8 = undefined;
            for (ports[0..pins.len], pins) |*name, p| name.* = p.name;
            if (!engine.regulator.positiveAbove(cards, ports[0..pins.len], deck.ports(cell))) continue;
            if (usage == null) {
                // Once per import: zero, one or several uses, and one bit
                // for a cell containing directives or raw SPICE statements.
                const state = try a.alloc(u8, syms.len());
                @memset(state, 0);
                for (recognized.parts.sym.items) |id| state[id] = @min(2, state[id] + 1);
                for ([_][]const u16{ deck.directive_cell, deck.code_cell }) |cells| {
                    for (cells) |c| if (c != 0) {
                        state[rec.subSymbol(c)] |= steered;
                    };
                }
                usage = state;
            }
            const state = usage.?;
            if ((state[s] & ~steered) != 1 or (state[rec.subSymbol(cell)] & steered) != 0) continue;
            const shape: engine.block_symbols.Shape = .regulator_amplifier;
            const glyph = try engine.block_symbols.draw(a, shape, ports[0..pins.len], 20);
            for (pins, glyph.terminals) |*pin, term| {
                pin.x = term.at.x;
                pin.y = term.at.y;
            }
            syms.shape.items[s] = shape;
        }
    }
}
