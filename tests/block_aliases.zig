//! Named block contracts -> source-backed triangle, sign and step assertions.
//! Cites docs/research/block-aliases.md and figures/comparator_strokes.py.
//!
//! Contents: private glyph checks, then source and boundary tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");

// ---- private ----

fn signedTriangle(c: np.Class, positive: usize, negative: usize) !void {
    var diagonals: usize = 0;
    var plus: usize = 0;
    var minus: usize = 0;
    for (c.draw) |op| switch (op) {
        .polyline => |ps| for (ps[0 .. ps.len - 1], ps[1..]) |a, b| {
            diagonals += @intFromBool(a.x != b.x and a.y != b.y);
        },
        .text => |t| {
            plus += @intFromBool(std.mem.eql(u8, t.s, "+"));
            minus += @intFromBool(std.mem.eql(u8, t.s, "-"));
        },
        else => {},
    };
    try testing.expectEqual(@as(usize, 2), diagonals);
    try testing.expectEqual(positive, plus);
    try testing.expectEqual(negative, minus);
}

fn interiorStep(c: np.Class, expected_vertices: usize) !void {
    var outline: ?[]const np.Pt = null;
    for (c.draw) |op| if (op == .polyline) {
        const ps = op.polyline;
        if (ps.len == 4 and ps[0].eql(ps[3])) {
            try testing.expect(outline == null);
            outline = ps[0..3];
        }
    };
    try testing.expect(outline != null);
    var paths: usize = 0;
    for (c.draw) |op| switch (op) {
        .polyline => |ps| {
            const inside = for (ps) |p| {
                if (!insideTriangle(p, outline.?)) break false;
            } else true;
            if (!inside) continue;
            paths += 1;
            try testing.expectEqual(expected_vertices, ps.len);
            if (ps.len != 4) return error.UnexpectedInteriorStroke;
            // AG809's source step has exactly four vertices: right, up,
            // right in the symbol's untransformed frame. Its two outer
            // segments are parallel; signs are separate text operations.
            try testing.expect(ps[0].x < ps[1].x);
            try testing.expectEqual(ps[0].y, ps[1].y);
            try testing.expectEqual(ps[1].x, ps[2].x);
            try testing.expect(ps[1].y > ps[2].y);
            try testing.expect(ps[2].x < ps[3].x);
            try testing.expectEqual(ps[2].y, ps[3].y);
        },
        .line => |line| {
            try testing.expect(!(insideTriangle(line.a, outline.?) and insideTriangle(line.b, outline.?)));
        },
        else => {},
    };
    try testing.expectEqual(@as(usize, @intFromBool(expected_vertices != 0)), paths);
}

fn insideTriangle(p: np.Pt, triangle: []const np.Pt) bool {
    std.debug.assert(triangle.len == 3);
    var positive = true;
    var negative = true;
    for (triangle, 0..) |a, i| {
        const b = triangle[(i + 1) % 3];
        const cross = (@as(i64, b.x) - a.x) * (@as(i64, p.y) - a.y) - (@as(i64, b.y) - a.y) * (@as(i64, p.x) - a.x);
        positive = positive and cross > 0;
        negative = negative and cross < 0;
    }
    return positive or negative;
}

test "amplifier aliases: actual source triangles retain signed inputs and declared pin order" {
    // Oracle: AG2553 AMP, AG2550 AMP1, AG1367/1393 CMP and AG1237 EA
    // contain triangle bodies and the listed polarity marks in actual SVG
    // ink. Cached custom-terminal coordinates do not determine this oracle.
    const cases = [_]struct { []const u8, []const u8, usize }{
        .{ "AMP", "VDD VSS INN INP VB2 VB1 OUT", 1 },
        .{ "amp1", "VDD VSS INP INN OUT", 1 },
        .{ "CmP", "VDD VSS INP INN OUT", 1 },
        .{ "cmp", "VDD VSS VB1 VB2 INN OUT", 0 },
        .{ "EA", "VDD VSS INP INN OUT", 1 },
    };
    for (cases) |row| {
        const text = try std.fmt.allocPrint(testing.allocator, "source glyph\n.subckt {s} {s}\n.ends\n", .{ row[0], row[1] });
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib: np.Library = .init(testing.allocator);
        defer lib.deinit();
        const def = &nl.defs[0];
        const c = lib.at(try lib.blockFor(def));
        try signedTriangle(c, row[2], 1);
        try testing.expectEqual(def.ports.len, c.terminals.len);
        for (def.ports, c.terminals) |name, terminal| {
            try testing.expectEqualStrings(name, terminal.name);
            try testing.expect(!terminal.hidden);
        }
        try testing.expectEqual(np.Side.right, c.side(c.terminals.len - 1, .r0).?);
    }
}

test "amplifier aliases: whole family names and complete contracts bound recognition" {
    // Oracle: ZCD is an opaque block in AG1440/1457 despite the familiar
    // input/output names. AG1752's A1 with an extra Z is also a box. Controls
    // and duplicate roles cannot be removed to fit a triangle contract.
    const cases = [_]struct { []const u8, []const u8 }{
        .{ "zcd", "VDD VSS INN OUT" },
        .{ "a1", "VDD VSS INP INN OUT Z" },
        .{ "amp10", "VDD VSS INP INN OUT" },
        .{ "my_cmp", "VDD VSS INP INN OUT" },
        .{ "ea", "VDD VSS INP INN OUT ENABLE" },
        .{ "amp1", "VDD VSS INP INN OUT VB VB1" },
        .{ "cmp", "VDD VSS IN INN OUT" },
    };
    for (cases) |row| {
        const text = try std.fmt.allocPrint(testing.allocator, "bounded glyph\n.subckt {s} {s}\n.ends\n", .{ row[0], row[1] });
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib: np.Library = .init(testing.allocator);
        defer lib.deinit();
        const c = lib.at(try lib.blockFor(&nl.defs[0]));
        for (c.draw) |op| if (op == .polyline) {
            for (op.polyline[0 .. op.polyline.len - 1], op.polyline[1..]) |a, b| {
                try testing.expect(a.x == b.x or a.y == b.y);
            }
        };
        try testing.expectEqual(nl.defs[0].ports.len, c.terminals.len);
    }
}

test "comparator appearance: generic source triangles contain no interior step" {
    // Oracle: all 69 plain triangles in comparator_strokes_cases.json;
    // these complete contracts are AG1370/1364, AG1365/1394, AG1367/1393.
    // Each source has zero interior step paths, regardless of whether it
    // has a signed input pair or one negative input. This checks ink, not
    // an internal shape enum. AG1390's source box remains a named gap.
    const cases = [_]struct { []const u8, []const u8, usize }{
        .{ "comp", "VDD VSS VB2 INN INP VB1 OUT", 1 },
        .{ "comp", "VDD VSS INN OUT", 0 },
        .{ "comparator", "VDD VSS OUT VB1 VB2 INP INN", 1 },
        .{ "comparator", "VDD VSS INN VB1 VB2 OUT", 0 },
        .{ "CmP", "VDD VSS INP INN OUT", 1 },
        .{ "cmp", "VDD VSS VB1 VB2 INN OUT", 0 },
    };
    for (cases) |row| {
        const text = try std.fmt.allocPrint(testing.allocator, "plain comparator\n.subckt {s} {s}\n.ends\n", .{ row[0], row[1] });
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib: np.Library = .init(testing.allocator);
        defer lib.deinit();
        const c = lib.at(try lib.blockFor(&nl.defs[0]));
        try signedTriangle(c, row[2], 1);
        try interiorStep(c, 0);
    }
}

test "comparator appearance: explicit ICM source retains one four-vertex step" {
    // Oracle: actual SVG paths in AG806:x1 and AG809:x2. AG806 mirrors
    // the same source asset. One open interior path has four vertices and
    // three orthogonal segments; exact source/native dimensions differ.
    const text = "ICM comparator\n.subckt ICM_IDEAL_COMPARATOR_VDD VDD VIP VIN VOUT\n.ends\n";
    var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
    defer nl.deinit(testing.allocator);
    var lib: np.Library = .init(testing.allocator);
    defer lib.deinit();
    const c = lib.at(try lib.blockFor(&nl.defs[0]));
    try signedTriangle(c, 1, 1);
    try interiorStep(c, 4);
    try testing.expectEqual(@as(usize, 4), c.terminals.len);
    for (nl.defs[0].ports, c.terminals) |name, terminal| {
        try testing.expectEqualStrings(name, terminal.name);
    }
}
