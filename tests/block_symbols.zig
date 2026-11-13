//! Public symbol contracts, with AnalogGenie's source glyphs as the oracle.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");

// ---- private ----

fn diagonal(c: np.Class) bool {
    for (c.draw) |op| switch (op) {
        .polyline => |ps| for (ps[0 .. ps.len - 1], ps[1..]) |a, b| {
            if (a.x != b.x and a.y != b.y) return true;
        },
        else => {},
    };
    return false;
}

fn circles(c: np.Class) usize {
    var n: usize = 0;
    for (c.draw) |op| if (op == .circle) {
        n += 1;
    };
    return n;
}

fn kindsSigned(name: []const u8) bool {
    return std.mem.eql(u8, name, "icm_opamp_vdd_vss") or std.mem.eql(u8, name, "icm_ideal_comparator_vdd");
}

test "block glyphs: textbook amplifiers and gates retain every ordered SPICE port" {
    // Oracle: AG807/750/806/1044/438/1070/1076 source SVG symbols: triangles,
    // signed differential inputs, curved gates and output inversion bubbles.
    const cases = [_]struct { []const u8, []const u8, bool }{
        .{ "icm_opamp_vdd_vss", "VDD VSS VIP VIN VOUT", false },
        .{ "voltage_amplifier", "VDD VSS VIN VOUT", false },
        .{ "icm_ideal_comparator_vdd", "VDD VIP VIN VOUT", false },
        .{ "inverter", "VDD VSS A Y", true },
        .{ "buffer", "VDD VSS A Y", false },
        .{ "and_gate", "VDD VSS A B Y", false },
        .{ "nand_gate", "VDD VSS A B Y", true },
        .{ "or_gate", "VDD VSS A B Y", false },
        .{ "nor_gate", "VDD VSS A B Y", true },
        .{ "xor_gate", "VDD VSS A B Y", false },
        .{ "xnor_gate", "VDD VSS A B Y", true },
    };
    for (cases) |row| {
        const text = try std.fmt.allocPrint(testing.allocator, "glyph\n.subckt {s} {s}\n.ends\n", .{ row[0], row[1] });
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib: np.Library = .init(testing.allocator);
        defer lib.deinit();
        const def = &nl.defs[0];
        const c = lib.at(try lib.blockFor(def));
        try testing.expect(diagonal(c));
        try testing.expectEqual(@as(usize, @intFromBool(row[2])), circles(c));
        try testing.expectEqual(def.ports.len, c.terminals.len);
        for (def.ports, c.terminals) |name, pin| {
            try testing.expectEqualStrings(name, pin.name);
            try testing.expect(!pin.hidden);
        }
        try testing.expectEqual(np.Side.up, c.side(0, .r0).?);
        try testing.expectEqual(np.Side.right, c.side(c.terminals.len - 1, .r0).?);
        if (kindsSigned(row[0])) {
            var signs: usize = 0;
            for (c.draw) |op| if (op == .text) {
                signs += @intFromBool(std.mem.eql(u8, op.text.s, "+") or std.mem.eql(u8, op.text.s, "-"));
            };
            try testing.expectEqual(@as(usize, 2), signs);
        }
    }
}

test "block glyphs: side directives and caller symbols win; ambiguous contracts stay boxes" {
    // Oracle: explicit drawing instructions outrank name recognition; the extra
    // bias/control port of AG1677 and the custom blocks of AG1070 stay visible.
    const decks = [_][]const u8{
        "t\n.subckt opamp VDD VSS VIP VIN VOUT\n*@ right VIP\n.ends\n",
        "t\n.subckt opamp VDD VSS VIP VIN VOUT VB1\n.ends\n",
        "t\n.subckt inverter VDD VSS A B Y\n.ends\n",
        "t\n.subckt charge_pump VDD VSS VIP VIN VOUT\n.ends\n",
        "t\n.subckt opamp VDD VSS inp vip inn out\n.ends\n",
        "t\n.subckt opamp V+ V- VIP VIN VOUT\n.ends\n",
    };
    for (decks, 0..) |text, k| {
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib: np.Library = .init(testing.allocator);
        defer lib.deinit();
        const c = lib.at(try lib.blockFor(&nl.defs[0]));
        try testing.expect(!diagonal(c));
        try testing.expectEqual(nl.defs[0].ports.len, c.terminals.len);
        if (k == 0) try testing.expectEqual(np.Side.right, c.side(2, .r0).?);
        var own: np.Library = .init(testing.allocator);
        defer own.deinit();
        const custom = try own.register(.{ .name = nl.defs[0].name, .terminals = &.{.{ .name = "p", .at = .zero }} });
        try testing.expectEqual(custom, try own.blockFor(&nl.defs[0]));
    }
}
