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
    return std.mem.eql(u8, name, "icm_opamp_vdd_vss") or std.mem.eql(u8, name, "icm_ideal_comparator_vdd") or std.mem.eql(u8, name, "opamp_differential");
}

test "block glyphs: textbook amplifiers and gates retain every ordered SPICE port" {
    // Oracle: AG807/750/806/1044/438/1070/1076 source SVG symbols: triangles,
    // signed differential inputs, curved gates and output inversion bubbles.
    const cases = [_]struct { []const u8, []const u8, bool }{
        .{ "icm_opamp_vdd_vss", "VDD VSS VIP VIN VOUT", false },
        .{ "opamp_differential", "VDD VSS VIP VIN VOP VON", false },
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
            try testing.expectEqual(@as(usize, if (std.mem.eql(u8, row[0], "opamp_differential")) 4 else 2), signs);
        }
    }
}

test "block glyphs: side directives and caller symbols win; ambiguous contracts stay boxes" {
    // Oracle: explicit drawing instructions outrank name recognition; the extra
    // extra control port of AG1677 and the custom blocks of AG1070 stay visible.
    const decks = [_][]const u8{
        "t\n.subckt opamp VDD VSS VIP VIN VOUT\n*@ right VIP\n.ends\n",
        "t\n.subckt opamp VDD VSS VIP VIN VOUT VA\n.ends\n",
        "t\n.subckt opamp VDD VSS VIP VIN VOUT VB VB1\n.ends\n",
        "t\n.subckt inverter VDD VSS A B Y\n.ends\n",
        "t\n.subckt charge_pump VDD VSS VIP VIN VOUT\n.ends\n",
        "t\n.subckt opamp VDD VSS inp vip inn out\n.ends\n",
        "t\n.subckt opamp V+ V- VIP VIN VOUT\n.ends\n",
        "t\n.subckt opamp_differential VDD VSS VIP VIN VOP VON VB\n.ends\n",
        "t\n.subckt opamp_differential VDD VIP VIN VOP OUTP\n.ends\n",
        "t\n.subckt opamp VDD VSS OUT\n.ends\n",
        "t\n.subckt opamp VDD VSS IN INN OUT\n.ends\n",
        "t\n.subckt comparator VDD INP OUT TAIL\n.ends\n",
        "t\n.subckt comparator VDD IN OUT VX\n.ends\n",
        "t\n.subckt opamp VDD INN OUT VB4\n.ends\n",
        "t\n.subckt opamp VDD INN OUT VB VB1\n.ends\n",
        "t\n.subckt opamp_differential VDD INN VOP VON\n.ends\n",
        "t\n.subckt voltage_amplifier VDD INN OUT\n.ends\n",
        "t\n.subckt arbitrary_amplifier VDD INN OUT\n.ends\n",
        "t\n.subckt opamp VDD VSS INN OUT\n*@ right INN\n.ends\n",
        "t\n.subckt comp VDD INN OUT VX\n.ends\n",
        "t\n.subckt comp VDD INN OUT TAIL\n.ends\n",
        "t\n.subckt comp VDD INN OUT VB4 VB5\n.ends\n",
        "t\n.subckt comp VDD INN OUT IB\n.ends\n",
        "t\n.subckt comp VDD INN OUT VBN\n.ends\n",
        "t\n.subckt comp VDD INN IN OUT\n.ends\n",
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
        if (std.mem.indexOf(u8, text, "*@ right INN") != null) try testing.expectEqual(np.Side.right, c.side(2, .r0).?);
        var own: np.Library = .init(testing.allocator);
        defer own.deinit();
        const custom = try own.register(.{ .name = nl.defs[0].name, .terminals = &.{.{ .name = "p", .at = .zero }} });
        try testing.expectEqual(custom, try own.blockFor(&nl.defs[0]));
    }
}

test "block glyphs: complete single-input amplifier contracts preserve their one input and polarity" {
    // Oracle: 47/47 selected source SVGs have triangles and matching signs:
    // AG1401 INN is minus, AG1432 INP is plus, AG1422 IN is unsigned.
    // Reordered ports retain identity; aliases retain the same contract.
    const cases = [_]struct { []const u8, []const u8, []const u8, []const u8 }{
        .{ "opamp", "VDD VSS VB1 OUT INN VB2 VB3", "inn", "-" },
        .{ "opamp", "VB3 INN OUT VB1 VDD VB2 VSS", "inn", "-" },
        .{ "comparator", "VDD VSS VB1 INP OUT", "inp", "+" },
        .{ "comparator", "VDD VSS IN OUT", "in", "" },
        .{ "opamp", "VIN OUT", "vin", "" },
        .{ "opamp", "INN OUT", "inn", "-" },
        .{ "icm_opamp_vdd_vss", "VSS OUT VDD INP", "inp", "+" },
        .{ "icm_ideal_comparator_vdd", "OUT IN VDD", "in", "" },
    };
    const gpa = testing.allocator;
    for (cases) |row| {
        const text = try std.fmt.allocPrint(gpa, "glyph\n.subckt {s} {s}\n.ends\n", .{ row[0], row[1] });
        defer gpa.free(text);
        var nl = try np.netlist.parse(gpa, &.{text}, null);
        defer nl.deinit(gpa);
        var lib = np.Library.init(gpa);
        defer lib.deinit();
        const def = &nl.defs[0];
        const c = lib.at(try lib.blockFor(def));
        try testing.expect(c.draw[0] == .polyline);
        try testing.expectEqual(4, c.draw[0].polyline.len);
        try testing.expect(diagonal(c));
        try testing.expectEqual(def.ports.len, c.terminals.len);
        var signs: usize = 0;
        for (c.draw) |op| if (op == .text and (std.mem.eql(u8, op.text.s, "+") or std.mem.eql(u8, op.text.s, "-"))) {
            signs += 1;
            try testing.expectEqualStrings(row[3], op.text.s);
        };
        try testing.expectEqual(@as(usize, @intFromBool(row[3].len != 0)), signs);
        for (def.ports, c.terminals, 0..) |name, terminal, i| {
            try testing.expectEqualStrings(name, terminal.name);
            try testing.expect(!terminal.hidden);
            if (std.mem.eql(u8, name, row[2])) try testing.expectEqual(np.Side.left, c.side(i, .r0).?);
            if (std.mem.eql(u8, name, "out")) try testing.expectEqual(np.Side.right, c.side(i, .r0).?);
            for (c.terminals[i + 1 ..]) |other| try testing.expect(!std.meta.eql(terminal.at, other.at));
        }
        var own = np.Library.init(gpa);
        defer own.deinit();
        const custom = try own.register(.{ .name = def.name, .terminals = &.{.{ .name = "p", .at = .zero }} });
        try testing.expectEqual(custom, try own.blockFor(def));
    }
}

test "block glyphs: the complete comp alias retains single and paired signed inputs" {
    // Oracle: AG1363/1446 use one signed/unsigned input; AG1370 has both
    // signs. All nine complete comp contracts have triangular source bodies.
    const gpa = testing.allocator;
    for ([_]struct { []const u8, usize }{
        .{ "VDD VSS VB1 VB2 INN OUT", 1 },
        .{ "OUT VB2 INN VSS VDD VB1", 1 },
        .{ "VDD VSS IN OUT", 0 },
        .{ "VDD VSS VB2 INN INP VB1 OUT", 2 },
    }) |row| {
        const text = try std.fmt.allocPrint(gpa, "glyph\n.subckt comp {s}\n.ends\n", .{row[0]});
        defer gpa.free(text);
        var nl = try np.netlist.parse(gpa, &.{text}, null);
        defer nl.deinit(gpa);
        var lib = np.Library.init(gpa);
        defer lib.deinit();
        const c = lib.at(try lib.blockFor(&nl.defs[0]));
        try testing.expect(diagonal(c));
        try testing.expectEqual(nl.defs[0].ports.len, c.terminals.len);
        var signs: usize = 0;
        for (c.draw) |op| if (op == .text) {
            signs += @intFromBool(std.mem.eql(u8, op.text.s, "+") or std.mem.eql(u8, op.text.s, "-"));
        };
        try testing.expectEqual(row[1], signs);
        for (nl.defs[0].ports, c.terminals) |name, pin| try testing.expectEqualStrings(name, pin.name);
    }
}

test "block glyphs: a fully differential amplifier keeps both signed outputs" {
    // Oracle: AG479/782 source triangles have two signal inputs and two
    // separate, signed outputs. The redraw omits power leads; the SPICE
    // contract retains them. AG782's crossed sign arrangement is the default.
    const gpa = testing.allocator;
    var nl = try np.netlist.parse(gpa, &.{"t\n.subckt opamp_differential VON VIN VSS VOP VIP VDD\n.ends\n"}, null);
    defer nl.deinit(gpa);
    var lib = np.Library.init(gpa);
    defer lib.deinit();
    const c = lib.at(try lib.blockFor(&nl.defs[0]));
    try testing.expect(diagonal(c));
    try testing.expectEqual(np.Side.right, c.side(0, .r0).?);
    try testing.expectEqual(np.Side.right, c.side(3, .r0).?);
    try testing.expectEqual(np.Side.left, c.side(1, .r0).?);
    try testing.expectEqual(np.Side.left, c.side(4, .r0).?);
    try testing.expectEqual(c.terminals[0].at.x, c.terminals[3].at.x);
    try testing.expect(c.terminals[3].at.y < c.terminals[0].at.y);
    try testing.expect(c.terminals[1].at.y < c.terminals[4].at.y);
    for (nl.defs[0].ports, c.terminals) |name, terminal| try testing.expectEqualStrings(name, terminal.name);
}

test "block glyphs: named amplifier bias pins retain a triangle and separate terminals" {
    // Oracle: 85 source instances with this complete signal/rail/bias contract
    // have triangular outlines, including AG1561/1661/1700/2223. A named
    // bias terminal changes the port count, not the amplifier's identity.
    const gpa = testing.allocator;
    for ([_][]const u8{
        "VDD VSS INP INN OUT VB1 VB2 VB3",
        "VB3 OUT INN VSS VB2 INP VB1 VDD",
        "VDD VSS INP INN OUT VB1",
    }) |ports| {
        const text = try std.fmt.allocPrint(gpa, "t\n.subckt opamp {s}\n.ends\n", .{ports});
        defer gpa.free(text);
        var nl = try np.netlist.parse(gpa, &.{text}, null);
        defer nl.deinit(gpa);
        var lib = np.Library.init(gpa);
        defer lib.deinit();
        const c = lib.at(try lib.blockFor(&nl.defs[0]));
        try testing.expect(diagonal(c));
        try testing.expectEqual(nl.defs[0].ports.len, c.terminals.len);
        for (nl.defs[0].ports, c.terminals, 0..) |name, terminal, i| {
            try testing.expectEqualStrings(name, terminal.name);
            try testing.expect(!terminal.hidden);
            if (std.mem.startsWith(u8, name, "vb")) try testing.expectEqual(np.Side.down, c.side(i, .r0).?);
            for (c.terminals[i + 1 ..]) |other| try testing.expect(!std.meta.eql(terminal.at, other.at));
        }
    }
}
