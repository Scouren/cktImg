//! The native cell reader has the literal outer interface and a fresh
//! drawing library. Register a generated signed frame before placement.
//!
//! Contents: `select`, `instances`.

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
                switch (np.block_symbols.identify(def.name, def.ports)) {
                    .amplifier, .four_bias_amplifier => {},
                    else => return,
                }
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

/// Borrows the selected cell's original formal bindings. Selects independent
/// local frames only for complete bare regulators or reused amplifier
/// definitions. Stronger caller classes and poses retain their geometry.
pub fn instances(a: std.mem.Allocator, nl: *const np.netlist.Netlist, ports: []const []const u8, lib: *np.Library, cfg: *const np.Config) ![]const np.netlist.Netlist.BlockFrame {
    const kinds = nl.graph.edges.items(.kind);
    if (kinds.len < 4) return &.{};
    const defs = nl.graph.edges.items(.def);
    const uses = try a.alloc(u32, nl.defs.len);
    @memset(uses, 0);
    var eligible = false;
    for (kinds, defs) |kind, def| if (kind == .subckt and def < uses.len) {
        uses[def] += 1;
        eligible = eligible or kinds.len == 4 or uses[def] > 1;
    };
    if (!eligible) return &.{};
    const cards = try a.alloc(np.regulator.Card, kinds.len);
    const counts = try a.alloc(u8, nl.graph.vertexCount());
    @memset(counts, 0);
    for (kinds, cards, 0..) |kind, *card, i| {
        const e = np.netlist.EdgeId.from(i);
        const nets: []const u32 = @ptrCast(nl.graph.members(e));
        for (nets) |n| counts[n] +|= 1;
        card.* = .{ .kind = switch (kind) {
            .subckt => .amplifier,
            .resistor => .resistor,
            .mosfet => if (std.mem.eql(u8, nl.modelType(e) orelse "", "nmos")) .nmos else .other,
            else => .other,
        }, .nets = nets };
    }
    var external: std.ArrayList(u32) = .empty;
    for (ports) |formal| if (nl.net(formal)) |n| try external.append(a, n.index());
    var frames: std.ArrayList(np.netlist.Netlist.BlockFrame) = .empty;
    var reserved: ?[]const bool = null;
    const initial_classes = lib.count();
    for (cards, 0..) |card, i| {
        if (card.kind != .amplifier or defs[i] >= uses.len or (kinds.len != 4 and uses[defs[i]] < 2)) continue;
        const e = np.netlist.EdgeId.from(i);
        const def = nl.defOf(e) orelse continue;
        const shape = np.block_symbols.identify(def.name, def.ports);
        if (shape != .amplifier and shape != .four_bias_amplifier) continue;
        if (std.mem.indexOf(u8, def.body, "*.pininfo") != null or lib.find(def.name) != null) continue;
        const family = try std.fmt.allocPrint(a, "block:{s}", .{def.name});
        if (lib.find(family)) |id| if (@backingInt(id) < initial_classes) continue;
        if (for (def.sides) |side| {
            if (side != null) break true;
        } else false) continue;
        const owner = np.regulator.localOwner(cards, i, def.ports, external.items, counts) orelse continue;
        const member = [4]u32{ @intCast(i), owner[0], owner[1], owner[2] };
        if (reserved == null) reserved = try np.regulator.held(a, nl, lib, cfg);
        const held_devices = reserved.?;
        if (held_devices.len != 0 and (for (member) |d| {
            if (held_devices[d]) break true;
        } else false)) continue;
        const name = try std.fmt.allocPrint(a, "{s}:reference-above", .{family});
        const glyph = try np.block_symbols.draw(a, .regulator_amplifier, def.ports, @min(1_000_000, @max(4, @divTrunc(lib.unit, 2))));
        const class = lib.register(.{ .name = name, .terminals = glyph.terminals, .draw = glyph.ops }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => continue,
        };
        try frames.append(a, .{ .device = e, .class = class });
    }
    return frames.items;
}
