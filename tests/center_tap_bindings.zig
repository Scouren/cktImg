//! Center-tap public placement and Schemify binding regressions.
//! Literal source calls and caller contracts bound the supported symbol.
//!
//! Contents: literal source calls, then placed and emitted binding oracles.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const cktimg = @import("cktimg");
const support = @import("support.zig");

const Case = struct { source: []const u8, card: []const u8, nets: [3][]const u8 };
// Actual calls from center_tap_symbols_cases.json; the definition/body below
// is identical in all 13 source decks. These are reduced placement fixtures,
// not a claim that their surrounding DUT routing has been reproduced.
const cases = [_]Case{
    .{ .source = "ag-1103:xl1", .card = "xl1", .nets = .{ "net9", "net8", "net21" } },
    .{ .source = "ag-1114:x1", .card = "x1", .nets = .{ "net0", "net1", "net4" } },
    .{ .source = "ag-1131:x1", .card = "x1", .nets = .{ "net4", "net5", "vdd" } },
    .{ .source = "ag-1146:x1", .card = "x1", .nets = .{ "von", "vop", "vocm" } },
    .{ .source = "ag-1147:x1", .card = "x1", .nets = .{ "vop", "von", "vdd" } },
    .{ .source = "ag-1149:xlp", .card = "xlp", .nets = .{ "net10", "net8", "vcc" } },
    .{ .source = "ag-1151:xl", .card = "xl", .nets = .{ "net6", "net7", "net0" } },
    .{ .source = "ag-1152:xl1", .card = "xl1", .nets = .{ "net21", "net5", "net0" } },
    .{ .source = "ag-1152:xl2", .card = "xl2", .nets = .{ "net22", "net12", "net1" } },
    .{ .source = "ag-1153:xl1", .card = "xl1", .nets = .{ "p4", "m4", "vdd" } },
    .{ .source = "ag-1153:xl2", .card = "xl2", .nets = .{ "p3", "m3", "vdd" } },
    .{ .source = "ag-1168:x1", .card = "x1", .nets = .{ "vdan", "vdap", "net0" } },
    .{ .source = "ag-1168:x2", .card = "x2", .nets = .{ "vdbn", "vdbp", "net1" } },
    .{ .source = "ag-1180:xle1", .card = "xle1", .nets = .{ "net4", "net5", "vdd" } },
    .{ .source = "ag-1180:xle2", .card = "xle2", .nets = .{ "net2", "net7", "vdd" } },
    .{ .source = "ag-1180:xlo1", .card = "xlo1", .nets = .{ "net4", "net5", "vdd" } },
    .{ .source = "ag-1180:xlo2", .card = "xlo2", .nets = .{ "net2", "net7", "vdd" } },
    .{ .source = "ag-1187:xtb", .card = "xtb", .nets = .{ "net1", "net4", "vb" } },
    .{ .source = "ag-1190:x1", .card = "x1", .nets = .{ "net7", "net4", "vbuf" } },
};
const names = [_][]const u8{ "n1", "n2", "n3" };
const orders = [_][3]u2{ .{ 0, 1, 2 }, .{ 2, 0, 1 } };

// ---- private ----

fn deck(a: std.mem.Allocator, row: Case, order: [3]u2) ![]const u8 {
    // Saving the three literal nodes gives singleton pins observable names
    // without introducing PININFO. The second order permutes declaration
    // and call together; the literal named-terminal binding stays fixed.
    return std.fmt.allocPrint(a, "* actual center-tap call\n" ++
        ".subckt ct_inductor {s} {s} {s} params: l1=1n l2=1n k=0\n" ++
        "L1 n1 n3 {{l1}}\nL2 n3 n2 {{l2}}\nK12 L1 L2 {{k}}\n.ends ct_inductor\n" ++
        "{s} {s} {s} {s} ct_inductor l1=1n l2=1n k=0\n.save v({s}) v({s}) v({s})\n", .{ names[order[0]], names[order[1]], names[order[2]], row.card, row.nets[order[0]], row.nets[order[1]], row.nets[order[2]], row.nets[0], row.nets[1], row.nets[2] });
}

fn passiveGlyph(c: np.Class) !void {
    // Real geometric anchor identity; the three terminals of an arbitrary
    // fallback box do not satisfy the midpoint relation or disk operation.
    try testing.expectEqual(@as(usize, 3), c.terminals.len);
    var points: [3]np.Pt = undefined;
    for (names, &points) |name, *point| {
        const p = for (c.terminals) |p| {
            if (std.ascii.eqlIgnoreCase(name, p.name)) break p;
        } else return error.MissingTerminal;
        try testing.expect(!p.hidden and !p.ground_ref);
        point.* = p.at;
    }
    const a, const b, const tap = points;
    try testing.expectEqual(a.y, b.y);
    try testing.expect(a.x < tap.x and tap.x < b.x and tap.y > a.y);
    try testing.expectEqual(@as(i64, a.x) + b.x, 2 * @as(i64, tap.x));
    const filled = if (comptime @hasField(np.library.DrawOp, "filled_circle")) for (c.draw) |op| {
        if (op == .filled_circle and op.filled_circle.c.eql(.{ .x = tap.x, .y = a.y }) and op.filled_circle.r > 0) break true;
    } else false else false;
    try testing.expect(filled);
}

fn on(w: cktimg.layout.Seg, p: cktimg.layout.P) bool {
    return (w[0] == w[2] and p[0] == w[0] and p[1] >= @min(w[1], w[3]) and p[1] <= @max(w[1], w[3])) or
        (w[1] == w[3] and p[1] == w[1] and p[0] >= @min(w[0], w[2]) and p[0] <= @max(w[0], w[2]));
}

fn binding(a: std.mem.Allocator, parsed: *const cktimg.spice.Deck, drawn: cktimg.layout.Drawn, at: cktimg.layout.P, want: []const u8) !void {
    // Independent physical-component oracle, matching the established
    // reference-amplifier test: endpoint/T/overlap joins, no proximity or
    // same-name teleporting. Every reached marker must match the literal.
    const wires = drawn.wire.items;
    const seen = try a.alloc(bool, wires.len);
    for (wires, seen) |w, *v| v.* = on(w, at);
    for (0..wires.len) |_| {
        var changed = false;
        for (wires, 0..) |w, i| {
            if (!seen[i]) continue;
            for (wires, 0..) |v, j| {
                if (seen[j] or !(on(w, .{ v[0], v[1] }) or on(w, .{ v[2], v[3] }) or
                    on(v, .{ w[0], w[1] }) or on(v, .{ w[2], w[3] }))) continue;
                seen[j] = true;
                changed = true;
            }
        }
        if (!changed) break;
    }
    var named = false;
    for (drawn.mark.items) |mark| {
        const reached = std.mem.eql(i32, &at, &mark.at) or for (wires, seen) |w, visited| {
            if (visited and on(w, mark.at)) break true;
        } else false;
        if (!reached) continue;
        if (!std.mem.eql(u8, want, parsed.netKey(0, mark.net))) return error.WrongBinding;
        named = true;
    }
    if (!named) return error.UnnamedBinding;
}

test "center-tap bindings: all 57 source terminals retain actual placed net identity" {
    // Oracle: the independently source-audited literal X cards above, plus
    // the public transform contract. Neither class order nor net proximity
    // can redefine which source terminal is the midpoint tap.
    for (cases) |row| {
        for (orders) |order| {
            errdefer std.debug.print("placed center tap: {s}\n", .{row.source});
            const text = try deck(testing.allocator, row, order);
            defer testing.allocator.free(text);
            for ([_]bool{ false, true }) |compact| {
                const lib = try support.library(testing.allocator);
                defer support.freeLibrary(testing.allocator, lib);
                var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{text}, null);
                defer p.deinit();
                const d = for (p.dev_name, 0..) |name, i| {
                    if (std.mem.eql(u8, name, row.card)) break i;
                } else return error.MissingInstance;
                const glyph = lib.at(p.dev_class[d]);
                try passiveGlyph(glyph);
                const lo, const hi = p.pinRange(d);
                try testing.expectEqual(@as(u32, 3), hi - lo);
                for (glyph.terminals, order, lo..hi) |pin, named, index| {
                    const net = row.nets[named];
                    try testing.expectEqualStrings(names[named], pin.name);
                    try testing.expectEqualStrings(net, p.net_name[p.pin_net[index]]);
                    try testing.expectEqualDeep(np.geom.placePoint(p.dev_orient[d], p.dev_pos[d], pin.at), p.pin_xy[index]);
                }
                try support.expectConnected(&p, lib);
                try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, &p, false));
            }
        }
    }
}

test "center-tap bindings: no PININFO emits three bidirectional pins and 57 named connections" {
    // This observes generated component records and their placed calling
    // schematic, not just reparsed SPICE. Left/right passive geometry must
    // not silently become input/output metadata.
    for (cases) |row| {
        for (orders) |order| {
            errdefer std.debug.print("emitted center tap: {s}\n", .{row.source});
            var arena = std.heap.ArenaAllocator.init(testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var c = try cktimg.Converter.init(testing.allocator, a, "center-tap.sp", try deck(a, row, order));
            defer c.deinit();
            try testing.expectEqual(@as(usize, 0), c.deck.pininfo.len);
            const sym = cktimg.recognize.subSymbol(c.deck.findCell("ct_inductor").?);
            try c.step();
            const emitted = (try cktimg.place.libCell(a, "", "ct_inductor", c.out.files.items[0].bytes)).?;
            try testing.expectEqual(@as(usize, 3), emitted.pins.len);
            const glyph = c.lib.at(c.lib.find(try std.fmt.allocPrint(a, "b{d}", .{sym})).?);
            try passiveGlyph(glyph);
            const drawn = try cktimg.layout.draw(testing.allocator, a, &c.lib, &c.deck, &c.rec, 0, &c.budget);
            try testing.expect(drawn.fallback == null and drawn.strays == 0);
            try testing.expectEqual(@as(usize, 1), drawn.x.items.len);
            const ori = drawn.orient.items[0];
            const transform = np.Orient{ .rot = @intCast(ori & 3), .mirror = ori >= 4 };
            for (order, emitted.pins, glyph.terminals) |named, pin, terminal| {
                const name, const net = .{ names[named], row.nets[named] };
                try testing.expectEqualStrings(name, terminal.name);
                try testing.expectEqualStrings(name, pin.name);
                try testing.expectEqual(cktimg.spice.Dir.inout, pin.dir);
                try testing.expectEqualDeep(np.Pt{ .x = pin.x, .y = pin.y }, terminal.at);
                const offset = transform.apply(.{ .x = pin.x, .y = pin.y });
                const at = cktimg.layout.P{ drawn.x.items[0] + offset.x, drawn.y.items[0] + offset.y };
                errdefer std.debug.print("center-tap binding {s}.{s} expected {s} at {any}\n", .{ row.source, name, net, at });
                try binding(a, &c.deck, drawn, at, net);
            }
        }
    }
}

test "center-tap bindings: explicit PININFO retains I O B and project-library terminals" {
    // Caller metadata is the oracle even when it disagrees with the
    // passive default; no inferred role may rewrite an explicit direction.
    for ([_]struct { info: []const u8, dirs: [3]cktimg.spice.Dir }{
        .{ .info = "N1:B N2:B N3:B", .dirs = .{ .inout, .inout, .inout } },
        .{ .info = "N1:I N2:O N3:B", .dirs = .{ .in, .out, .inout } },
    }) |row| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.fmt.allocPrint(a, "* caller roles\n.subckt ct_inductor N1 N2 N3\n*.PININFO {s}\n.ends\nX1 a b tap ct_inductor\n", .{row.info});
        var c = try cktimg.Converter.init(testing.allocator, a, "roles.sp", text);
        defer c.deinit();
        const sym = cktimg.recognize.subSymbol(c.deck.findCell("ct_inductor").?);
        try c.step();
        const emitted = (try cktimg.place.libCell(a, "", "ct_inductor", c.out.files.items[0].bytes)).?;
        for ([_][]const u8{ "N1", "N2", "N3" }, row.dirs, emitted.pins) |name, dir, pin| {
            try testing.expectEqualStrings(name, pin.name);
            try testing.expectEqual(dir, pin.dir);
        }
        try passiveGlyph(c.lib.at(c.lib.find(try std.fmt.allocPrint(a, "b{d}", .{sym})).?));
    }
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pins = [_]cktimg.recognize.Pin{
        .{ .name = "N1", .x = 71, .y = -23, .dir = .out },
        .{ .name = "N2", .x = -51, .y = 19, .dir = .in },
        .{ .name = "N3", .x = 9, .y = -83, .dir = .inout },
    };
    const cells = [_]cktimg.recognize.LibCell{.{ .lib = "caller", .name = "ct_inductor", .pins = &pins, .body = .{ -40, -40, 40, 40 }, .params = &.{} }};
    var c = try cktimg.Converter.initLibs(testing.allocator, a, "own.sp", "* own symbol\nX1 a b tap ct_inductor\n", &cells);
    defer c.deinit();
    const sym = c.rec.parts.sym.items[0];
    try testing.expectEqual(cktimg.recognize.Origin.lib, c.rec.syms.origin.items[sym]);
    for (pins, c.rec.syms.pins(sym)) |expected, actual| try testing.expectEqualDeep(expected, actual);
}

test "center-tap bindings: Schemify side requests retain exported pins and actual bindings" {
    // A side request is an independent caller contract. It overrides the
    // canonical down-facing tap; explicit PININFO still owns direction.
    for ([_]bool{ false, true }) |explicit_dirs| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const info = if (explicit_dirs) "*.PININFO N1:I N2:O N3:B\n" else "";
        const text = try std.fmt.allocPrint(a, "* caller side\n.subckt ct_inductor n1 n2 n3\n*@ right n3\n{s}.ends\nX1 outer_a outer_b tap ct_inductor\n.save v(outer_a) v(outer_b) v(tap)\n", .{info});
        var c = try cktimg.Converter.init(testing.allocator, a, "side.sp", text);
        defer c.deinit();
        const sym = cktimg.recognize.subSymbol(c.deck.findCell("ct_inductor").?);
        try c.step();
        const emitted = (try cktimg.place.libCell(a, "", "ct_inductor", c.out.files.items[0].bytes)).?;
        const glyph = c.lib.at(c.lib.find(try std.fmt.allocPrint(a, "b{d}", .{sym})).?);
        try testing.expectEqual(np.Side.right, glyph.side(2, .r0).?);
        try testing.expectEqual(@as(usize, 3), emitted.pins.len);
        const dirs: [3]cktimg.spice.Dir = if (explicit_dirs) .{ .in, .out, .inout } else @splat(.inout);
        const nets = [_][]const u8{ "outer_a", "outer_b", "tap" };
        const drawn = try cktimg.layout.draw(testing.allocator, a, &c.lib, &c.deck, &c.rec, 0, &c.budget);
        try testing.expect(drawn.fallback == null and drawn.strays == 0);
        try testing.expectEqual(@as(usize, 1), drawn.x.items.len);
        const ori = drawn.orient.items[0];
        const transform = np.Orient{ .rot = @intCast(ori & 3), .mirror = ori >= 4 };
        for (names, nets, dirs, emitted.pins, glyph.terminals) |name, net, dir, pin, terminal| {
            try testing.expectEqualStrings(name, pin.name);
            try testing.expectEqualStrings(name, terminal.name);
            try testing.expectEqual(dir, pin.dir);
            try testing.expectEqualDeep(np.Pt{ .x = pin.x, .y = pin.y }, terminal.at);
            const offset = transform.apply(terminal.at);
            try binding(a, &c.deck, drawn, .{ drawn.x.items[0] + offset.x, drawn.y.items[0] + offset.y }, net);
        }
    }
}

test "center-tap bindings: a wrong marker or disconnected ink cannot pass the oracle" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try cktimg.spice.parse(a, "* literal names\nR1 outer tap 1k\n");
    try testing.expectEqualStrings("outer", parsed.netKey(0, 0));
    try testing.expectEqualStrings("tap", parsed.netKey(0, 1));
    var drawn: cktimg.layout.Drawn = .{};
    try drawn.wire.append(a, .{ 0, 0, 10, 0 });
    try drawn.mark.append(a, .{ .at = .{ 10, 0 }, .net = 0, .orient = 0 });
    try binding(a, &parsed, drawn, .{ 0, 0 }, "outer");
    try testing.expectError(error.WrongBinding, binding(a, &parsed, drawn, .{ 0, 0 }, "tap"));
    drawn.mark.items[0].net = 1;
    try testing.expectError(error.WrongBinding, binding(a, &parsed, drawn, .{ 0, 0 }, "outer"));
    drawn.mark.items[0].net = 0;
    drawn.wire.items[0][0] = 1;
    try testing.expectError(error.UnnamedBinding, binding(a, &parsed, drawn, .{ 0, 0 }, "outer"));
}
