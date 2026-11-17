//! The native cell reader has the literal outer interface and a fresh
//! drawing library. Register a generated signed frame before placement.
//!
//! Contents: `select`.

const std = @import("std");
const np = @import("NetlistParser");

/// Selects the complete regulator's frame for this one drawing. Existing
/// caller symbols, explicit side/pose directives and other cell topologies
/// retain ordinary block selection. Borrows `nl` and `ports`.
pub fn select(a: std.mem.Allocator, nl: *const np.netlist.Netlist, ports: []const []const u8, lib: *np.Library) !void {
    if (nl.graph.edgeCount() != 6 or nl.hints.len != 0) return;
    var cards: [6]np.regulator.Card = undefined;
    var amp: ?*const np.netlist.Subckt = null;
    for (nl.graph.edges.items(.kind), &cards, 0..) |kind, *card, d| {
        const e = np.netlist.EdgeId.from(d);
        const k: @FieldType(np.regulator.Card, "kind") = switch (kind) {
            .subckt => k: {
                const def = nl.defOf(e) orelse return;
                if (np.block_symbols.identify(def.name, def.ports) != .amplifier) return;
                for (def.sides) |side| if (side != null) return;
                if (std.mem.indexOf(u8, def.body, "*.pininfo") != null) return;
                amp = def;
                break :k .amplifier;
            },
            .resistor => .resistor,
            .capacitor => .capacitor,
            .mosfet => k: {
                if (!std.mem.eql(u8, nl.modelType(e) orelse return, "nmos")) return;
                break :k .nmos;
            },
            else => return,
        };
        card.* = .{ .kind = k, .nets = @ptrCast(nl.graph.members(e)) };
    }
    const def = amp orelse return;
    const boundary = try a.alloc(u32, ports.len);
    var n: usize = 0;
    for (ports) |p| if (nl.net(p)) |net| {
        boundary[n] = net.index();
        n += 1;
    };
    if (!np.regulator.positiveAbove(cards, def.ports, boundary[0..n])) return;
    const name = try std.fmt.allocPrint(a, "block:{s}", .{def.name});
    if (lib.find(def.name) != null or lib.find(name) != null) return;
    const glyph = try np.block_symbols.draw(a, .regulator_amplifier, def.ports, @min(1_000_000, @max(4, @divTrunc(lib.unit, 2))));
    _ = try lib.register(.{ .name = name, .terminals = glyph.terminals, .draw = glyph.ops });
}
