//! Complete A1/EA1/AEA declarations -> source-backed glyph and pin checks.
//! Cites docs/research/remaining-amplifiers.md and its exact SVG inventory.
//! tests/schemify.zig supplies both NetlistParser and cktimg for caller
//! metadata checks.
//!
//! Contents: private ink checks, then source, permutation and caller tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const cktimg = @import("cktimg");

const Case = struct {
    source: []const u8,
    family: []const u8 = "a1",
    ports: []const u8,
    sides: []const u8,
    positive: []const u8 = "inp",
    negative: []const u8 = "inn",
};

// ---- private ----

fn triangle(c: np.Class) bool {
    var outlines: usize = 0;
    for (c.draw) |op| if (op == .polyline) {
        const p = op.polyline;
        if (p.len != 4 or !p[0].eql(p[3])) continue;
        const area = (@as(i64, p[1].x) - p[0].x) * (@as(i64, p[2].y) - p[0].y) -
            (@as(i64, p[1].y) - p[0].y) * (@as(i64, p[2].x) - p[0].x);
        outlines += @intFromBool(area != 0);
    };
    return outlines == 1;
}

fn box(c: np.Class) bool {
    var outlines: usize = 0;
    for (c.draw) |op| if (op == .polyline) {
        const p = op.polyline;
        if (p.len != 5 or !p[0].eql(p[4])) continue;
        const rectangular = for (p[0..4], p[1..5]) |a, b| {
            if (a.eql(b) or (a.x != b.x and a.y != b.y)) break false;
        } else true;
        outlines += @intFromBool(rectangular);
    };
    return outlines == 1 and !triangle(c);
}

fn sign(c: np.Class, name: []const u8, mark: []const u8) !void {
    var count: usize = 0;
    for (c.draw) |op| if (op == .text and std.mem.eql(u8, op.text.s, mark)) {
        count += 1;
        const at = for (c.terminals) |p| {
            if (std.ascii.eqlIgnoreCase(p.name, name)) break p.at;
        } else return error.UnexpectedPolarityMark;
        // The sign belongs to the named input, rather than merely existing
        // somewhere in the triangle. No exact font size or x offset is fixed.
        try testing.expectEqual(at.y, op.text.at.y);
        try testing.expect(op.text.at.x > at.x);
    };
    try testing.expectEqual(@as(usize, @intFromBool(name.len != 0)), count);
}

fn sourceCase(row: Case) !void {
    errdefer std.debug.print("remaining amplifier contract: {s}\n", .{row.source});
    const text = try std.fmt.allocPrint(testing.allocator, "source glyph\n.subckt {s} {s}\n.ends\n", .{ row.family, row.ports });
    defer testing.allocator.free(text);
    var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
    defer nl.deinit(testing.allocator);
    var lib = np.Library.init(testing.allocator);
    defer lib.deinit();
    const def = &nl.defs[0];
    const c = lib.at(try lib.blockFor(def));
    try testing.expect(triangle(c));
    try testing.expectEqual(def.ports.len, c.terminals.len);
    try testing.expectEqual(row.sides.len, c.terminals.len);
    for (def.ports, c.terminals, row.sides, 0..) |name, terminal, side, i| {
        const expected: np.Side = switch (side) {
            'U' => .up,
            'D' => .down,
            'L' => .left,
            'R' => .right,
            else => unreachable,
        };
        try testing.expectEqualStrings(name, terminal.name);
        try testing.expectEqual(expected, c.side(i, .r0).?);
        // Source omits VSS ink; the electrical declaration remains complete.
        try testing.expect(!terminal.hidden and !terminal.ground_ref);
        for (c.terminals[i + 1 ..]) |other| try testing.expect(!terminal.at.eql(other.at));
    }
    try sign(c, row.positive, "+");
    try sign(c, row.negative, "-");
}

test "remaining amplifiers: all 39 source contracts retain triangles and named polarity" {
    // Oracle: independent outlines, apex/base leads and sign strokes in the
    // exact source inventory. Literal side strings express the existing
    // canonical API contract, not each source's world facing or bias order.
    // AG1708 reverses the source input order; AG1233 points left. Neither
    // observation changes named polarity or removes the declared VSS pin.
    const cases = [_]Case{
        .{ .source = "ag-1233:x1", .ports = "vdd vss inp inn out", .sides = "UDLLR", .family = "ea1" },
        .{ .source = "ag-1464:x1", .ports = "vdd vss vb1 vb3 vb2 inn inp out", .sides = "UDDDDLLR" },
        .{ .source = "ag-1486:x1", .ports = "vdd vss vb1 vb2 inn inp out", .sides = "UDDDLLR" },
        .{ .source = "ag-1504:x1", .ports = "vdd vss inp inn out vb1 vb2", .sides = "UDLLRDD" },
        .{ .source = "ag-1505:x1", .ports = "vdd vss vb1 inn inp out vb2", .sides = "UDDLLRD" },
        .{ .source = "ag-1551:x1", .ports = "vss inn inp out", .sides = "DLLR" },
        .{ .source = "ag-1557:x1", .ports = "vss inn inp out", .sides = "DLLR" },
        .{ .source = "ag-1565:x1", .ports = "vdd vss inn inp vb2 vb1 out", .sides = "UDLLDDR" },
        .{ .source = "ag-1570:x1", .ports = "vdd vss inn inp out vb1 vb2", .sides = "UDLLRDD" },
        .{ .source = "ag-1574:x1", .ports = "vdd vss inn inp out vb1 vb2", .sides = "UDLLRDD" },
        .{ .source = "ag-1579:x1", .ports = "vss inn inp out", .sides = "DLLR" },
        .{ .source = "ag-1586:x1", .ports = "vss inn inp out", .sides = "DLLR" },
        .{ .source = "ag-1591:x1", .ports = "vdd vss vb3 vb2 vb1 inp inn out", .sides = "UDDDDLLR" },
        .{ .source = "ag-1593:x1", .ports = "vdd vss inp inn out", .sides = "UDLLR" },
        .{ .source = "ag-1597:x1", .ports = "vdd vss inp inn out", .sides = "UDLLR" },
        .{ .source = "ag-1600:x1", .ports = "vdd vss vb1 vb3 vb2 inp inn out", .sides = "UDDDDLLR" },
        .{ .source = "ag-1609:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1610:x1", .ports = "vss inn inp out", .sides = "DLLR" },
        .{ .source = "ag-1614:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1617:x1", .ports = "vss inn inp out", .sides = "DLLR" },
        .{ .source = "ag-1626:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1629:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1630:x1", .ports = "vss in- in+ out", .sides = "DLLR", .positive = "in+", .negative = "in-" },
        .{ .source = "ag-1631:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1634:x1", .ports = "vdd vss inn inp out vb", .sides = "UDLLRD" },
        .{ .source = "ag-1636:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1637:x1", .ports = "vss inn inp out", .sides = "DLLR" },
        .{ .source = "ag-1675:x1", .ports = "vss inn inp out", .sides = "DLLR" },
        .{ .source = "ag-1704:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1705:x1", .ports = "vdd vss out inp inn", .sides = "UDRLL" },
        .{ .source = "ag-1708:x1", .ports = "vdd vss inp inn out", .sides = "UDLLR" },
        .{ .source = "ag-1711:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1713:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1715:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1722:x1", .ports = "vdd vss inn inp out vb2 vb1", .sides = "UDLLRDD" },
        .{ .source = "ag-1724:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1726:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-1727:x1", .ports = "vdd vss inn inp out", .sides = "UDLLR" },
        .{ .source = "ag-2423:x1", .ports = "vdd vss inn out vb", .sides = "UDLRD", .family = "aea", .positive = "" },
    };
    for (cases) |row| try sourceCase(row);
}

test "remaining amplifiers: case and declaration permutations retain named port roles" {
    // Oracle: permutation invariance of named electrical ports. These are
    // deliberate permutations of the eight-, five- and five-port sources.
    try testing.expectEqual(.amplifier, np.block_symbols.identify("A1", &.{ "OUT", "INP", "VSS", "INN", "VDD" }));
    try testing.expectEqual(.amplifier, np.block_symbols.identify("Ea1", &.{ "OUT", "INN", "VDD", "INP", "VSS" }));
    try testing.expectEqual(.amplifier, np.block_symbols.identify("aEa", &.{ "VB", "OUT", "VDD", "INN", "VSS" }));
    try sourceCase(.{ .source = "permuted ag-1464", .family = "A1", .ports = "OUT VB2 INP VSS VB1 VDD INN VB3", .sides = "RDLDDULD" });
    try sourceCase(.{ .source = "permuted ag-1233", .family = "Ea1", .ports = "OUT INN VDD INP VSS", .sides = "RLULD" });
    try sourceCase(.{ .source = "permuted ag-2423", .family = "aEa", .ports = "VB OUT VDD INN VSS", .sides = "DRULD", .positive = "" });
}

test "remaining amplifiers: exact names and complete contracts keep source exceptions boxed" {
    // Oracle: AG1752 is an actual box with these six A1 ports, despite
    // AG1510 drawing the identical declaration as a triangle. The unknown
    // Z role remains outside this complete-contract extension. AG1289's
    // unsigned EA1 is a box; AG1316's additional unsigned controls need
    // their own contract and must not acquire fabricated plus/minus marks.
    const cases = [_]struct { []const u8, []const u8 }{
        .{ "A1", "VDD VSS INP INN OUT Z" },
        .{ "A1", "VDD VSS INN INP OUT VB1 VB2 VZ" },
        .{ "EA1", "VDD VSS VFP1 VREF VX3 VCTRL" },
        .{ "EA1", "VDD VSS VFP1 VREF VX2 VB1 VISR VX1" },
        .{ "A10", "VDD VSS INP INN OUT" },
        .{ "my_a1", "VDD VSS INP INN OUT" },
        .{ "EA1_extra", "VDD VSS INP INN OUT" },
        .{ "AEA2", "VDD VSS INN OUT VB" },
        .{ "A1", "VDD VSS INP INN OUT VB VB1" },
        .{ "EA1", "VDD VSS INP INN" },
        .{ "A1", "VDD INP INN IN OUT" },
        .{ "AEA", "VDD VSS INN OUT VB ENABLE" },
        .{ "OTA", "VDD VSS INP INN OUT" },
    };
    for (cases) |row| {
        const text = try std.fmt.allocPrint(testing.allocator, "bounded glyph\n.subckt {s} {s}\n.ends\n", .{ row[0], row[1] });
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib = np.Library.init(testing.allocator);
        defer lib.deinit();
        const c = lib.at(try lib.blockFor(&nl.defs[0]));
        try testing.expect(box(c));
        try testing.expectEqual(nl.defs[0].ports.len, c.terminals.len);
        for (nl.defs[0].ports, c.terminals) |name, terminal| {
            try testing.expectEqualStrings(name, terminal.name);
            try testing.expect(!terminal.hidden);
        }
    }
}

test "remaining amplifiers: explicit port sides and caller classes retain precedence" {
    // Oracle: the public Library contract, independent of source glyphs.
    for ([_]struct { []const u8, []const u8 }{
        .{ "A1", "VDD VSS INP INN OUT" },
        .{ "EA1", "VDD VSS INP INN OUT" },
        .{ "AEA", "VDD VSS INN OUT VB" },
    }) |row| {
        const text = try std.fmt.allocPrint(testing.allocator, "caller\n.subckt {s} {s}\n*@ right INN\n.ends\n", .{ row[0], row[1] });
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib = np.Library.init(testing.allocator);
        defer lib.deinit();
        const def = &nl.defs[0];
        const c = lib.at(try lib.blockFor(def));
        try testing.expect(box(c));
        for (c.terminals, 0..) |p, i| if (std.mem.eql(u8, p.name, "inn")) {
            try testing.expectEqual(np.Side.right, c.side(i, .r0).?);
        };
        const terms = try testing.allocator.dupe(np.library.Terminal, c.terminals);
        defer testing.allocator.free(terms);
        terms[0].at = .{ .x = 17, .y = -91 };
        terms[0].side = .up;
        var own = np.Library.init(testing.allocator);
        defer own.deinit();
        const custom = try own.register(.{ .name = def.name, .terminals = terms, .draw = &.{np.library.DrawOp.ln(-9, -7, 13, 11)} });
        try testing.expectEqual(custom, try own.blockFor(def));
        const retained = own.at(custom);
        try testing.expectEqual(@as(usize, 1), retained.draw.len);
        try testing.expectEqual(terms.len, retained.terminals.len);
        for (terms, retained.terminals) |expected, actual| try testing.expectEqualDeep(expected, actual);
    }
}

test "remaining amplifiers: Schemify PININFO and side hints preserve declared ports" {
    // Oracles: AG1464's eight named ports, AG1233's signed pair and
    // AG2423's single negative input; public I/O/B and side metadata take
    // precedence over inferred glyph geometry. Matching PININFO must not
    // suppress recognition, while conflicts retain their explicit values.
    const cases = [_]struct {
        family: []const u8,
        ports: []const u8,
        info: []const u8,
        normal_dirs: []const u8,
        conflict_dirs: []const u8,
        positive: []const u8,
    }{
        .{ .family = "A1", .ports = "VDD VSS VB1 VB3 VB2 INN INP OUT", .info = "VDD:B VSS:B VB1:B VB3:B VB2:B INN:I INP:I OUT:O", .normal_dirs = "BBBBBIIO", .conflict_dirs = "BBBBBOII", .positive = "inp" },
        .{ .family = "EA1", .ports = "VDD VSS INP INN OUT", .info = "VDD:B VSS:B INP:I INN:I OUT:O", .normal_dirs = "BBIIO", .conflict_dirs = "BBIOI", .positive = "inp" },
        .{ .family = "AEA", .ports = "VDD VSS INN OUT VB", .info = "VDD:B VSS:B INN:I OUT:O VB:B", .normal_dirs = "BBIOB", .conflict_dirs = "BBOIB", .positive = "" },
    };
    for (cases) |row| {
        // The first two modes admit the same source glyph, independently
        // of whether the caller explicitly repeated its pin directions.
        for (0..4) |mode| {
            var arena = std.heap.ArenaAllocator.init(testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            const extra: []const u8 = switch (mode) {
                0 => "",
                1 => try std.fmt.allocPrint(a, "*.PININFO {s}\n", .{row.info}),
                2 => "*.PININFO INN:O OUT:I\n",
                3 => "*@ right INN\n",
                else => unreachable,
            };
            const text = try std.fmt.allocPrint(a, "* source alias metadata\n.subckt {s} {s}\n{s}R1 VDD VSS 1meg\n.ends\nX1 {s} {s}\n", .{ row.family, row.ports, extra, row.ports, row.family });
            var c = try cktimg.Converter.init(testing.allocator, a, "remaining.sp", text);
            defer c.deinit();
            const sym = cktimg.recognize.subSymbol(c.deck.findCell(row.family).?);
            const pins = c.rec.syms.pins(sym);
            const dirs = if (mode == 2) row.conflict_dirs else row.normal_dirs;
            try testing.expectEqual(dirs.len, pins.len);
            var names = std.mem.tokenizeScalar(u8, row.ports, ' ');
            for (pins, dirs) |pin, dir| {
                const name = names.next() orelse return error.ExtraDeclaredPort;
                try testing.expectEqualStrings(name, pin.name);
                const expected: cktimg.spice.Dir = switch (dir) {
                    'I' => .in,
                    'O' => .out,
                    'B' => .inout,
                    else => unreachable,
                };
                try testing.expectEqual(expected, pin.dir);
                if (mode == 3 and std.mem.eql(u8, name, "INN")) try testing.expect(pin.x > 0);
            }
            try testing.expect(names.next() == null);
            const class_name = try std.fmt.allocPrint(a, "b{d}", .{sym});
            const glyph = c.lib.at(c.lib.find(class_name).?);
            if (mode < 2) {
                try testing.expect(triangle(glyph));
                try sign(glyph, row.positive, "+");
                try sign(glyph, "inn", "-");
            } else try testing.expect(box(glyph));
            while (c.cellsLeft() > 0) try c.step();
            const out = try c.finish();
            const file = for (out.files.items) |f| {
                if (std.mem.endsWith(u8, f.name, ".shcomp")) break f.bytes;
            } else return error.MissingGeneratedComponent;
            try testing.expect(std.mem.indexOf(u8, file, "prefix X\n") != null);
            try testing.expect(std.mem.indexOf(u8, file, "impl schematic schematic\n") != null);
            try testing.expectEqual(mode >= 2, std.mem.indexOf(u8, file, "rect ") != null);
            var previous: usize = 0;
            for (pins) |pin| {
                const needle = try std.fmt.allocPrint(a, "pin {s} {s} ", .{ pin.name, @tagName(pin.dir) });
                const at = std.mem.indexOf(u8, file, needle) orelse return error.MissingExportedPort;
                try testing.expect(at >= previous);
                previous = at;
            }
        }
    }
}

test "remaining amplifiers: project library cells keep their supplied pins and origin" {
    // Oracle: a caller-provided project cell is an external library
    // reference, not a generated glyph. Deliberately reversed signal
    // coordinates and directions cannot be replaced by alias defaults.
    const cases = [_]struct { family: []const u8, names: []const []const u8 }{
        .{ .family = "A1", .names = &.{ "VDD", "VSS", "INP", "INN", "OUT" } },
        .{ .family = "EA1", .names = &.{ "VDD", "VSS", "INP", "INN", "OUT" } },
        .{ .family = "AEA", .names = &.{ "VDD", "VSS", "INN", "OUT", "VB" } },
    };
    for (cases) |row| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const pins = [_]cktimg.recognize.Pin{
            .{ .name = row.names[0], .x = 0, .y = -90, .dir = .inout },
            .{ .name = row.names[1], .x = 0, .y = 90, .dir = .inout },
            .{ .name = row.names[2], .x = 80, .y = -20, .dir = .out },
            .{ .name = row.names[3], .x = 80, .y = 20, .dir = .in },
            .{ .name = row.names[4], .x = -80, .y = 0, .dir = .inout },
        };
        const cells = [_]cktimg.recognize.LibCell{.{ .lib = "caller", .name = row.family, .pins = &pins, .body = .{ -80, -90, 80, 90 }, .params = &.{} }};
        const text = try std.fmt.allocPrint(a, "* external alias\nX1 supply ground p2 p3 p4 {s}\n", .{row.family});
        var c = try cktimg.Converter.initLibs(testing.allocator, a, "project.sp", text, &cells);
        defer c.deinit();
        const sym = c.rec.parts.sym.items[0];
        try testing.expectEqual(cktimg.recognize.Origin.lib, c.rec.syms.origin.items[sym]);
        try testing.expectEqual(@as(usize, pins.len), c.rec.syms.pins(sym).len);
        for (pins, c.rec.syms.pins(sym)) |expected, actual| try testing.expectEqualDeep(expected, actual);
        while (c.cellsLeft() > 0) try c.step();
        const out = try c.finish();
        const reference = try std.fmt.allocPrint(a, "caller:{s}", .{row.family});
        const found = for (out.files.items) |file| {
            try testing.expect(!std.mem.endsWith(u8, file.name, ".shcomp"));
            if (std.mem.indexOf(u8, file.bytes, reference) != null) break true;
        } else false;
        try testing.expect(found);
    }
}
