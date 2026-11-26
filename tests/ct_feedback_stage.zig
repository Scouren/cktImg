//! CT-linked NPN feedback stage: complete literal AG1149 source deck.
//! Oracle: 23 actual SVG lead positions, five complete physical wire trees
//! and world orientation in figures/ct_feedback_stage.py. One source figure.
//! Relative predicates have literal failure mutations; labels never connect.
//! Caller controls compare identical CT glyphs under an opaque family name.
//!
//! Contents: source fixture, independent actual-terminal oracle, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1149 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model qnpn npn
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\C1 net6 net10 1p
    \\C2 net8 net7 1p
    \\C3 net0 net4 1p
    \\C4 net11 net0 1p
    \\C5 net1 net9 1p
    \\C6 net2 net1 1p
    \\C7 VTune net11 1p
    \\C8 VTune net9 1p
    \\LB1A VB1 net7 1n
    \\LB1B net6 VB1 1n
    \\LB2A net11 VB2 1n
    \\LB2B net9 VB2 1n
    \\LS1 net4 net5 1n
    \\LS2 net3 net2 1n
    \\LT1 net5 VSS 1n
    \\LT2 net3 VSS 1n
    \\Q1 net10 net7 net5 VSS qnpn m=1
    \\Q2 net8 net6 net3 VSS qnpn m=1
    \\Q3 net8 net8 net10 VSS qnpn m=1
    \\Q4 net10 net10 net8 VSS qnpn m=1
    \\XLp net10 net8 Vcc ct_inductor l1=1n l2=1n k=0
    \\*@ weak role vtune output
;

const stage = [_][]const u8{ "xlp", "q1", "q2", "q3", "q4", "c1", "c2", "lb1a", "lb1b" };
const Frame = [23]np.Pt;
const Named = struct { device: []const u8, terminal: []const u8, net: []const u8 };
const named = [_]Named{
    .{ .device = "xlp", .terminal = "n1", .net = "net10" }, .{ .device = "xlp", .terminal = "n2", .net = "net8" }, .{ .device = "xlp", .terminal = "n3", .net = "vcc" },
    .{ .device = "q1", .terminal = "c", .net = "net10" },   .{ .device = "q1", .terminal = "b", .net = "net7" },   .{ .device = "q1", .terminal = "e", .net = "net5" },
    .{ .device = "q2", .terminal = "c", .net = "net8" },    .{ .device = "q2", .terminal = "b", .net = "net6" },   .{ .device = "q2", .terminal = "e", .net = "net3" },
    .{ .device = "q3", .terminal = "c", .net = "net8" },    .{ .device = "q3", .terminal = "b", .net = "net8" },   .{ .device = "q3", .terminal = "e", .net = "net10" },
    .{ .device = "q4", .terminal = "c", .net = "net10" },   .{ .device = "q4", .terminal = "b", .net = "net10" },  .{ .device = "q4", .terminal = "e", .net = "net8" },
    .{ .device = "c1", .terminal = "", .net = "net10" },    .{ .device = "c1", .terminal = "", .net = "net6" },    .{ .device = "c2", .terminal = "", .net = "net7" },
    .{ .device = "c2", .terminal = "", .net = "net8" },     .{ .device = "lb1a", .terminal = "", .net = "net7" },  .{ .device = "lb1a", .terminal = "", .net = "vb1" },
    .{ .device = "lb1b", .terminal = "", .net = "vb1" },    .{ .device = "lb1b", .terminal = "", .net = "net6" },
};
const trees = [_][]const usize{ &.{ 0, 3, 11, 12, 13, 15 }, &.{ 1, 6, 9, 10, 14, 18 }, &.{ 4, 17, 19 }, &.{ 7, 16, 22 }, &.{ 20, 21 } };
const source: Frame = .{
    .{ .x = 130, .y = 0 },   .{ .x = 230, .y = 0 },   .{ .x = 180, .y = -20 },
    .{ .x = -10, .y = 170 }, .{ .x = 20, .y = 190 },  .{ .x = -10, .y = 210 },
    .{ .x = 370, .y = 170 }, .{ .x = 340, .y = 190 }, .{ .x = 370, .y = 210 },
    .{ .x = 90, .y = 50 },   .{ .x = 70, .y = 20 },   .{ .x = 50, .y = 50 },
    .{ .x = 270, .y = 80 },  .{ .x = 290, .y = 110 }, .{ .x = 310, .y = 80 },
    .{ .x = 20, .y = 130 },  .{ .x = 60, .y = 130 },  .{ .x = 300, .y = 130 },
    .{ .x = 340, .y = 130 }, .{ .x = 80, .y = 240 },  .{ .x = 120, .y = 240 },
    .{ .x = 240, .y = 240 }, .{ .x = 280, .y = 240 },
};

// ---- private ----

fn pins(p: *const np.Placed, lib: *const np.Library) ![23]usize {
    var out: [23]usize = undefined;
    for (named, &out) |want, *result| {
        const d = np.checks.deviceIn(p, want.device) orelse return error.MissingDevice;
        const lo, const hi = p.pinRange(d);
        const class = lib.at(p.dev_class[d]);
        // Four-node BJT cards retain the substrate binding even when the
        // actual caller glyph has only the three visible C/B/E terminals.
        if (want.device[0] == 'q') {
            try testing.expectEqual(@as(u32, 4), hi - lo);
            try testing.expectEqualStrings("vss", p.net_name[p.pin_net[lo + 3]]);
        }
        var found: ?usize = null;
        for (lo..hi) |pin| {
            if (pin - lo >= class.terminals.len) continue;
            const selected = if (want.terminal.len == 0) std.ascii.eqlIgnoreCase(want.net, p.net_name[p.pin_net[pin]]) else std.ascii.eqlIgnoreCase(want.terminal, class.terminals[pin - lo].name);
            if (!selected) continue;
            try testing.expect(found == null);
            try testing.expect(!class.terminals[pin - lo].hidden);
            try testing.expectEqualStrings(want.net, p.net_name[p.pin_net[pin]]);
            try testing.expectEqualDeep(p.dev_pos[d].add(p.dev_orient[d].apply(class.terminals[pin - lo].at)), p.pin_xy[pin]);
            found = pin;
        }
        result.* = found orelse return error.MissingActualTerminal;
    }
    return out;
}

fn geometry(q: Frame) bool {
    const axis2 = @as(i64, q[0].x) + q[1].x;
    if (q[0].y != q[1].y or q[0].x >= q[1].x or 2 * @as(i64, q[2].x) != axis2 or q[2].y >= q[0].y) return false;
    for ([_]usize{ 3, 6 }) |i| {
        if (q[i].x != q[i + 2].x or q[i].y >= q[i + 1].y or q[i + 1].y >= q[i + 2].y) return false;
    }
    if (q[3].y != q[6].y or q[4].y != q[7].y or q[5].y != q[8].y) return false;
    if (!(q[3].x < q[4].x and 2 * @as(i64, q[4].x) < axis2 and axis2 < 2 * @as(i64, q[7].x) and q[7].x < q[6].x)) return false;
    if (q[3].x >= q[0].x or q[6].x <= q[1].x) return false;
    for (15..19) |i| if (q[i].y != q[15].y or q[i].y >= q[3].y) return false;
    if (!(q[15].x < q[16].x and 2 * @as(i64, q[16].x) < axis2 and axis2 < 2 * @as(i64, q[17].x) and q[17].x < q[18].x)) return false;
    for (19..23) |i| if (q[i].y != q[19].y or q[i].y <= q[4].y) return false;
    if (!(q[19].x < q[20].x and 2 * @as(i64, q[20].x) < axis2 and axis2 < 2 * @as(i64, q[21].x) and q[21].x < q[22].x)) return false;
    if (!(q[4].x < q[16].x and q[16].x < q[19].x and q[22].x < q[17].x and q[17].x < q[7].x)) return false;
    for (9..15) |i| if (q[i].y <= q[0].y or q[i].y >= q[15].y) return false;
    if (q[9].y != q[11].y or q[12].y != q[14].y or q[9].y >= q[12].y) return false;
    return q[11].x < q[10].x and q[10].x < q[9].x and q[10].y < q[9].y and q[12].x < q[13].x and q[13].x < q[14].x and q[13].y > q[12].y;
}

fn expectGeometry(p: *const np.Placed, lib: *const np.Library) !void {
    var actual: Frame = undefined;
    for (try pins(p, lib), &actual) |pin, *point| point.* = p.pin_xy[pin];
    errdefer std.debug.print("CT feedback actual frame: {any}\n", .{actual});
    try testing.expect(geometry(actual));
}

fn expectTrees(p: *const np.Placed, lib: *const np.Library) !void {
    const actual = try pins(p, lib);
    for (trees) |tree| {
        var targets: [6]usize = undefined;
        for (tree, targets[0..tree.len]) |index, *target| target.* = actual[index];
        const net = p.pin_net[targets[0]];
        // Placed adds unnamed rail/port symbols. Only named card ranges
        // are source incidences; retain their hidden pins in this census.
        try testing.expect(declaredPinsMatch(p.dev_name, p.dev_pin0, p.pin_net, net, targets[0..tree.len]));
        errdefer std.debug.print("CT feedback physical tree: {s}\n", .{p.net_name[net]});
        try testing.expect(try ink.connected(testing.allocator, p, targets[0..tree.len]));
    }
}

fn declaredPinsMatch(names: []const [:0]const u8, starts: []const u32, nets: []const u32, net: u32, targets: []const usize) bool {
    std.debug.assert(starts.len == names.len + 1);
    std.debug.assert(starts[starts.len - 1] == nets.len);
    var count: usize = 0;
    for (names, 0..) |name, d| {
        if (name.len == 0) continue;
        for (starts[d]..starts[d + 1]) |pin| if (nets[pin] == net) {
            if (std.mem.indexOfScalar(usize, targets, pin) == null) return false;
            count += 1;
        };
    }
    return count == targets.len;
}

fn disjoint(a: np.library.Rect, b: np.library.Rect) bool {
    return @max(a.min.x, b.min.x) >= @min(a.max.x, b.max.x) or @max(a.min.y, b.min.y) >= @min(a.max.y, b.max.y);
}

fn clear(p: *const np.Placed, lib: *const np.Library) !void {
    for (stage) |name| {
        const d = np.checks.deviceIn(p, name).?;
        const box = lib.at(p.dev_class[d]).box(p.dev_orient[d], p.dev_pos[d]);
        for (p.dev_pos, 0..) |at, other| {
            if (d == other) continue;
            const b = lib.at(p.dev_class[other]).box(p.dev_orient[other], at);
            try testing.expect(disjoint(box, b));
        }
    }
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

fn ordinary(text: []const u8, compact: bool, custom: ?np.library.Spec, verbs: []const np.hints.Verb, extra: ?[]const u8) !void {
    const a = testing.allocator;
    const opaque_deck = try std.mem.replaceOwned(u8, a, text, "ct_inductor", "opaque_coil");
    defer a.free(opaque_deck);
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const glyph = try np.block_symbols.draw(arena.allocator(), .center_tap, &.{ "n1", "n2", "n3" }, 20);
    for ([_][]const u8{ "ct_inductor", "opaque_coil" }) |name| _ = try lib.register(.{ .name = name, .terminals = glyph.terminals, .draw = glyph.ops });
    const id = if (custom) |spec| try lib.register(spec) else null;
    var nl = try np.netlist.parse(arena.allocator(), &.{text}, null);
    try testing.expectEqual(1 + verbs.len, nl.hints.len);
    for (verbs, nl.hints[1..]) |verb, hint| try testing.expectEqual(verb, hint.verb);
    if (extra) |name| try testing.expect(nl.device(name) != null);
    if (verbs.len != 0) {
        const roles = try np.guessRoles(arena.allocator(), &nl);
        const st = try np.schematic.structure.analyze(a, arena.allocator(), &nl, roles);
        const sk = try np.schematic.skeleton.place(a, arena.allocator(), &nl, roles, &st, .{});
        for (try np.report.verdicts(arena.allocator(), &nl, roles, &st, &sk, null, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
    }
    var before = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{opaque_deck}, null);
    defer before.deinit();
    var after = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
    defer after.deinit();
    if (extra) |name| try testing.expect(np.checks.deviceIn(&after, name) != null);
    for (stage) |name| {
        const d = np.checks.deviceIn(&after, name).?;
        const e = np.checks.deviceIn(&before, name).?;
        try testing.expectEqualDeep(before.dev_pos[e], after.dev_pos[d]);
        try testing.expectEqualDeep(before.dev_orient[e], after.dev_orient[d]);
        const lo, const hi = after.pinRange(d);
        const from, const to = before.pinRange(e);
        try testing.expectEqualSlices(np.Pt, before.pin_xy[from..to], after.pin_xy[lo..hi]);
    }
    if (custom) |spec| {
        try testing.expectEqualDeep(spec.terminals, lib.at(id.?).terminals);
        try testing.expectEqualDeep(spec.draw, lib.at(id.?).draw);
    }
}

// ---- tests ----

test "CT feedback stage: declared incidence excludes generated ports but retains every named card pin" {
    const starts = [_]u32{ 0, 2, 4, 5 };
    const nets = [_]u32{ 0, 1, 1, 2, 1 };
    const targets = [_]usize{ 1, 2 };
    try testing.expect(declaredPinsMatch(&.{ "lb1a", "lb1b", "" }, &starts, &nets, 1, &targets));
    try testing.expect(!declaredPinsMatch(&.{ "lb1a", "lb1b", "rextra" }, &starts, &nets, 1, &targets));
    // A third raw pin on a named card is still an incidence even if its
    // glyph would hide it. Empty names never exempt that card's pins.
    try testing.expect(!declaredPinsMatch(&.{ "lb1a", "lb1b" }, &.{ 0, 2, 5 }, &nets, 1, &targets));
    try testing.expect(!declaredPinsMatch(&.{ "lb1a", "lb1b", "" }, &starts, &nets, 1, &.{1}));
    try testing.expect(!declaredPinsMatch(&.{ "lb1a", "lb1b", "" }, &starts, &nets, 1, &.{ 1, 2, 4 }));
}

test "CT feedback stage: actual source world frame and literal mutations define the oracle" {
    try testing.expect(geometry(source));
    var translated = source;
    for (&translated) |*p| p.* = p.add(.{ .x = 73, .y = -81 });
    try testing.expect(geometry(translated));
    for ([_]usize{ 2, 4, 10, 13, 16, 19, 20 }) |index| {
        var bad = source;
        if (index == 2) bad[index].y = 20 else if (index == 19 or index == 20) bad[index].x = 200 else bad[index].y += 100;
        try testing.expect(!geometry(bad));
    }
    var upside_down = source;
    for (&upside_down) |*p| p.y = -p.y;
    try testing.expect(!geometry(upside_down));
    // These retain each old individual frame and outward endpoint order,
    // but lose the measured base -> feedback inner -> bias control order.
    for ([_][2]i32{ .{ 19, 40 }, .{ 22, 320 } }) |mutation| {
        var bad = source;
        bad[@intCast(mutation[0])].x = mutation[1];
        try testing.expect(!geometry(bad));
    }
    const a = np.library.Rect.fromCorners(.{ .x = 0, .y = 0 }, .{ .x = 20, .y = 20 });
    try testing.expect(disjoint(a, a.translate(.{ .x = 20, .y = 0 })));
    try testing.expect(!disjoint(a, a.translate(.{ .x = 19, .y = 0 })));
}

test "CT feedback stage: complete source has its measured world frame without body overlap" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1149}, null);
        defer p.deinit();
        try expectGeometry(&p, lib);
        try clear(&p, lib);
        try electrical(&p, lib);
    }
}

test "CT feedback stage: all five exact source terminal trees remain physical ink" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1149}, null);
        defer p.deinit();
        try expectTrees(&p, lib);
        try electrical(&p, lib);
    }
}

test "CT feedback stage: declaration card and passive pin order retain measured relations" {
    const a = testing.allocator;
    const decl = try std.mem.replaceOwned(u8, a, ag1149, "ct_inductor n1 n2 n3 params:", "ct_inductor n3 n2 n1 params:");
    defer a.free(decl);
    const reordered = try std.mem.replaceOwned(u8, a, decl, "XLp net10 net8 Vcc", "XLp Vcc net8 net10");
    defer a.free(reordered);
    const moved = try std.mem.replaceOwned(u8, a, ag1149, "Q1 net10 net7 net5 VSS qnpn m=1\nQ2 net8 net6 net3 VSS qnpn m=1", "Q2 net8 net6 net3 VSS qnpn m=1\nQ1 net10 net7 net5 VSS qnpn m=1");
    defer a.free(moved);
    const reversed = try std.mem.replaceOwned(u8, a, ag1149, "C1 net6 net10", "C1 net10 net6");
    defer a.free(reversed);
    const passive = try std.mem.replaceOwned(u8, a, reversed, "LB1A VB1 net7", "LB1A net7 VB1");
    defer a.free(passive);
    for ([_][]const u8{ reordered, moved, passive }) |text| {
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        for ([_]bool{ false, true }) |compact| {
            var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
            defer p.deinit();
            try expectGeometry(&p, lib);
            try expectTrees(&p, lib);
            try clear(&p, lib);
        }
    }
}

test "CT feedback stage: full incidence raw competitors and invalid models keep ordinary placement" {
    const a = testing.allocator;
    const changes = [_][2][]const u8{
        .{ "Q3 net8 net8 net10 VSS qnpn", "Q3 net8 net8 net10 VSS qother" },
        .{ "Q2 net8 net6 net3", "Q2 net8 net6 net5" },
        .{ "Q2 net8 net6 net3 VSS", "Q2 net8 net6 net3 other" },
        .{ "C1 net6 net10", "C1 net7 net10" },
        .{ "XLp net10 net8 Vcc", "XLp net10 net8 other" },
    };
    for (changes) |change| {
        const text = try std.mem.replaceOwned(u8, a, ag1149, change[0], change[1]);
        defer a.free(text);
        for ([_]bool{ false, true }) |compact| try ordinary(text, compact, null, &.{}, null);
    }
    const extras = [_][]const u8{ "Rextra net7 remote 1k\n", "Rextra net10 remote 1k\n", "Qextra net10 net10 net8 VSS qother\n", "Xextra net10 net8 net10 ct_inductor\n", "Cextra net6 net10 1p\n", "Rextra vb1 remote 1k\n" };
    for (extras) |extra| {
        const text = try std.fmt.allocPrint(a, "{s}\n{s}", .{ ag1149, extra });
        defer a.free(text);
        const name = switch (extra[0]) {
            'R' => "rextra",
            'Q' => "qextra",
            'X' => "xextra",
            'C' => "cextra",
            else => unreachable,
        };
        for ([_]bool{ false, true }) |compact| try ordinary(text, compact, null, &.{}, name);
    }
}

test "CT feedback stage: admitted member and net requests retain ordinary placement" {
    const a = testing.allocator;
    const requests = [_]struct { text: []const u8, verb: np.hints.Verb }{
        .{ .text = "*@ at q1 -10 -10 r0\n", .verb = .at },
        .{ .text = "*@ cell c1 -8 -6\n", .verb = .cell },
        .{ .text = "*@ face q1 b left\n", .verb = .face },
        .{ .text = "*@ row q1 q2\n", .verb = .row },
        .{ .text = "*@ group stack q1 q2\n", .verb = .stack },
        .{ .text = "*@ label net7\n", .verb = .label },
        .{ .text = "*@ route net10 -12,-12 -10,-12\n", .verb = .route },
        .{ .text = "*@ first net8\n", .verb = .first },
        .{ .text = "*@ first vcc\n", .verb = .first },
        .{ .text = "*@ label net5\n", .verb = .label },
        .{ .text = "*@ first vb1\n", .verb = .first },
    };
    for (requests) |request| {
        errdefer std.debug.print("CT feedback caller request: {s}", .{request.text});
        const text = try std.fmt.allocPrint(a, "{s}\n{s}", .{ ag1149, request.text });
        defer a.free(text);
        for ([_]bool{ false, true }) |compact| try ordinary(text, compact, null, &.{request.verb}, null);
    }
    // The supply tap cannot admit port/route. A touched emitter can be a
    // declared output; its actual admitted port must also take precedence.
    const output = ag1149 ++ "\n*@ role net5 output\n*@ port net5 left\n";
    for ([_]bool{ false, true }) |compact| try ordinary(output, compact, null, &.{ .role, .port }, null);
}

test "CT feedback stage: explicit plain tap rail changes rail rendering while preserving the stage" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const text = ag1149 ++ "\n*@ rail vcc plain\n";
    for ([_]bool{ false, true }) |compact| for ([_][]const u8{ ag1149, text }, 0..) |deck, variant| {
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        try expectGeometry(&p, lib);
        const net = p.pin_net[(try pins(&p, lib))[2]];
        var symbols: usize = 0;
        for (p.dev_class, 0..) |class, d| {
            const lo, const hi = p.pinRange(d);
            if (lib.at(class).role == .power_rail and hi > lo and p.pin_net[lo] == net) symbols += 1;
        }
        if (variant == 0) try testing.expect(symbols > 0) else {
            try testing.expectEqual(@as(usize, 0), symbols);
            var arena = std.heap.ArenaAllocator.init(a);
            defer arena.deinit();
            const scratch = arena.allocator();
            var nl = try np.netlist.parse(scratch, &.{deck}, null);
            try testing.expectEqual(np.hints.Verb.rail, nl.hints[1].verb);
            const roles = try np.guessRoles(scratch, &nl);
            const st = try np.schematic.structure.analyze(a, scratch, &nl, roles);
            const sk = try np.schematic.skeleton.place(a, scratch, &nl, roles, &st, .{});
            for (try np.report.verdicts(scratch, &nl, roles, &st, &sk, &p, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
        }
    };
}

test "CT feedback stage: literal shifted classes retain actual source relations and every binding" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const specs = [_]np.library.Spec{
        .{ .name = "offset_ct", .terminals = &.{
            .{ .name = "n1", .at = .{ .x = -43, .y = 11 }, .side = .left },
            .{ .name = "n2", .at = .{ .x = 57, .y = 11 }, .side = .right },
            .{ .name = "n3", .at = .{ .x = 7, .y = -9 }, .side = .up },
        }, .draw = &.{ .ln(-43, 11, 57, 11), .ln(7, 11, 7, -9) } },
        .{ .name = "offset_npn", .terminals = &.{
            .{ .name = "c", .at = .{ .x = 37, .y = 9 }, .side = .right },
            .{ .name = "b", .at = .{ .x = 7, .y = -21 }, .side = .up },
            .{ .name = "e", .at = .{ .x = -23, .y = 9 }, .side = .left },
        }, .draw = &.{ .ln(17, 9, 37, 9), .ln(-23, 9, -3, 9), .ln(7, -21, 7, 9) } },
        .{ .name = "offset_cap", .terminals = &.{
            .{ .name = "a", .at = .{ .x = -21, .y = -13 }, .side = .left },
            .{ .name = "b", .at = .{ .x = 39, .y = -13 }, .side = .right },
        }, .draw = &.{.ln(-21, -13, 39, -13)} },
        .{ .name = "offset_ind", .terminals = &.{
            .{ .name = "a", .at = .{ .x = -57, .y = 23 }, .side = .left },
            .{ .name = "b", .at = .{ .x = 23, .y = 23 }, .side = .right },
        }, .draw = &.{.ln(-57, 23, 23, 23)} },
    };
    var classes: [4]np.ClassId = undefined;
    for (specs, &classes) |spec, *class| class.* = try lib.register(spec);
    const text = ag1149 ++ "\n*@ class xlp offset_ct\n*@ class q1 offset_npn\n*@ class q2 offset_npn\n*@ class q3 offset_npn\n*@ class q4 offset_npn\n*@ class c1 offset_cap\n*@ class c2 offset_cap\n*@ class lb1a offset_ind\n*@ class lb1b offset_ind\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        try expectGeometry(&p, lib);
        try clear(&p, lib);
        try electrical(&p, lib);
        for (stage, [_]usize{ 0, 1, 1, 1, 1, 2, 2, 3, 3 }) |name, i| {
            try testing.expectEqual(classes[i], p.dev_class[np.checks.deviceIn(&p, name).?]);
            try testing.expectEqualDeep(specs[i].terminals, lib.at(classes[i]).terminals);
            try testing.expectEqualDeep(specs[i].draw, lib.at(classes[i]).draw);
        }
    }
}

test "CT feedback stage: hidden and noncollinear caller frames cannot own the stage" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const original = lib.at(lib.find("npn").?);
    const terms = try a.dupe(np.library.Terminal, original.terminals);
    defer a.free(terms);
    for (0..2) |which| {
        @memcpy(terms, original.terminals);
        if (which == 0) terms[1].hidden = true else terms[0].at.y += 7;
        const spec: np.library.Spec = .{ .name = "special_npn", .terminals = terms, .draw = original.draw };
        const text = ag1149 ++ "\n*@ class q1 special_npn\n";
        for ([_]bool{ false, true }) |compact| try ordinary(text, compact, spec, &.{.class}, null);
    }
}
