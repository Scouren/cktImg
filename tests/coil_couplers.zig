//! Paired CT coupling-bridge source regressions.
//! Oracle: actual AG1180 leads, twenty relative predicates and four private
//! conductor trees in iteration21-coil-couplers.json. One source figure.
//! Geometry, private ink and all-bank continuity are separate requirements.
//! No source coordinate is assigned to the switch control terminals.
//!
//! Contents: source deck, independent endpoint oracle, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const setup =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.model ideal_switch SW(RON=1 ROFF=1e12 VT=0.5 VH=0)
    \\
;

const cards =
    \\C1 net6 net4 1p
    \\C2 net2 net3 1p
    \\C3 net0 net5 1p
    \\C4 net7 net1 1p
    \\CT1 net4 net5 1p
    \\CT2 net2 net7 1p
    \\M1 net4 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net5 net4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net2 net7 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net7 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\S1 net6 net3 S1 VSS ideal_switch
    \\S2 net0 net1 S2 VSS ideal_switch
    \\SE1 net4 net2 SE VSS ideal_switch
    \\SE2 net5 net7 SE VSS ideal_switch
    \\SO1 net4 net7 SO VSS ideal_switch
    \\SO2 net2 net5 SO VSS ideal_switch
    \\XLE1 net4 net5 VDD ct_inductor l1=1n l2=1n k=0
    \\XLE2 net2 net7 VDD ct_inductor l1=1n l2=1n k=0
    \\XLO1 net4 net5 VDD ct_inductor l1=1n l2=1n k=0
    \\XLO2 net2 net7 VDD ct_inductor l1=1n l2=1n k=0
    \\
;

const roles =
    \\*@ weak role s1 output
    \\*@ weak role s2 output
    \\*@ weak role se output
    \\*@ weak role so output
    \\
;

const full = setup ++ cards ++ roles;

const names = [_][]const u8{ "c1", "s1", "c2", "c3", "s2", "c4" };
const Frame = [26]np.Pt;

// ---- private ----

fn pinOn(p: *const np.Placed, device: []const u8, net: []const u8) !usize {
    const d = np.checks.deviceIn(p, device) orelse return error.MissingDevice;
    const lo, const hi = p.pinRange(d);
    var result: ?usize = null;
    for (lo..hi) |pin| if (std.ascii.eqlIgnoreCase(p.net_name[p.pin_net[pin]], net)) {
        if (result != null) return error.AmbiguousDeviceNet;
        result = pin;
    };
    return result orelse error.MissingDeviceNet;
}

fn pins(p: *const np.Placed) ![26]usize {
    var out: [26]usize = undefined;
    const coils = [2][2][]const u8{ .{ "xle1", "xlo1" }, .{ "xle2", "xlo2" } };
    const ends = [2][2][]const u8{ .{ "net4", "net5" }, .{ "net2", "net7" } };
    const a = p.pin_xy[try pinOn(p, coils[0][0], ends[0][0])];
    const b = p.pin_xy[try pinOn(p, coils[1][0], ends[1][0])];
    const axis2 = @as(i64, a.x) + b.x;
    for (coils, ends, 0..) |pair, nets, i| {
        const x = try pinOn(p, pair[0], nets[0]);
        const y = try pinOn(p, pair[1], nets[0]);
        const inner = if (@abs(2 * @as(i64, p.pin_xy[x].x) - axis2) < @abs(2 * @as(i64, p.pin_xy[y].x) - axis2)) pair[0] else pair[1];
        out[2 * i] = try pinOn(p, inner, nets[0]);
        out[2 * i + 1] = try pinOn(p, inner, nets[1]);
    }
    const exact = [_][2][]const u8{
        .{ "m1", "net4" },  .{ "m2", "net5" },
        .{ "c1", "net4" },  .{ "c1", "net6" },
        .{ "s1", "net6" },  .{ "s1", "net3" },
        .{ "c2", "net3" },  .{ "c2", "net2" },
        .{ "c3", "net5" },  .{ "c3", "net0" },
        .{ "s2", "net0" },  .{ "s2", "net1" },
        .{ "c4", "net1" },  .{ "c4", "net7" },
        .{ "se1", "net4" }, .{ "se1", "net2" },
        .{ "se2", "net5" }, .{ "se2", "net7" },
        .{ "so1", "net4" }, .{ "so1", "net7" },
        .{ "so2", "net2" }, .{ "so2", "net5" },
    };
    for (exact, out[4..]) |named, *pin| pin.* = try pinOn(p, named[0], named[1]);
    return out;
}

fn frame(p: *const np.Placed) !Frame {
    var out: Frame = undefined;
    for (try pins(p), &out) |pin, *point| point.* = p.pin_xy[pin];
    return out;
}

fn normalized(points: Frame) ?[26][2]i64 {
    const vertical = points[0].x == points[1].x and points[0].y != points[1].y;
    const horizontal = points[0].y == points[1].y and points[0].x != points[1].x;
    if (!vertical and !horizontal) return null;
    var q: [26][2]i64 = undefined;
    for (points, &q) |p, *v| v.* = if (vertical) .{ p.y, p.x } else .{ p.x, p.y };
    const along: i64 = if (q[1][0] > q[0][0]) 1 else -1;
    const across: i64 = if (q[2][1] > q[0][1]) 1 else -1;
    for (&q) |*v| {
        v[0] *= along;
        v[1] *= across;
    }
    if (q[0][1] != q[1][1] or q[2][1] != q[3][1] or q[0][1] >= q[2][1]) return null;
    if (q[0][0] != q[2][0] or q[1][0] != q[3][0]) return null;
    if (q[4][0] >= q[0][0] or q[5][0] <= q[1][0]) return null;
    return q;
}

fn chains(points: Frame) bool {
    const q = normalized(points) orelse return false;
    for ([_]usize{ 6, 12 }, 0..) |first, i| {
        for (first + 1..first + 6) |j| {
            if (q[j][0] != q[first][0] or q[j - 1][1] >= q[j][1]) return false;
        }
        if (q[first][1] != q[0][1] or q[first + 5][1] != q[2][1]) return false;
        if (i == 0 and q[first][0] >= q[4][0]) return false;
        if (i == 1 and q[first][0] <= q[5][0]) return false;
    }
    return true;
}

fn bridges(points: Frame) bool {
    const q = normalized(points) orelse return false;
    for ([_]usize{ 18, 20 }, 0..) |first, i| for (first..first + 2) |j| {
        if (q[j][0] != q[4 + i][0] or q[j][1] <= q[0][1] or q[j][1] >= q[2][1]) return false;
    };
    for ([_]usize{ 22, 24 }) |first| {
        if (q[first][1] != q[first + 1][1] or q[first][1] <= q[0][1] or q[first][1] >= q[2][1]) return false;
        if (q[first][0] != q[4][0] or q[first + 1][0] <= q[first][0]) return false;
        if (2 * q[first + 1][0] >= q[0][0] + q[1][0]) return false;
    }
    return q[22][1] != q[24][1] and q[23][0] == q[25][0];
}

fn privateInk(p: *const np.Placed) !void {
    const ps = try pins(p);
    for ([_][2]usize{ .{ 7, 8 }, .{ 9, 10 }, .{ 13, 14 }, .{ 15, 16 } }) |pair| {
        try testing.expect(try ink.connected(testing.allocator, p, &.{ ps[pair[0]], ps[pair[1]] }));
    }
}

fn bindings(p: *const np.Placed, text: []const u8) !void {
    var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
    defer nl.deinit(testing.allocator);
    for ([_][]const u8{ "s1", "s2", "se1", "se2", "so1", "so2" }) |name| {
        const expected = nl.graph.members(nl.device(name).?);
        const lo, const hi = p.pinRange(np.checks.deviceIn(p, name).?);
        try testing.expectEqual(@as(usize, 4), expected.len);
        try testing.expectEqual(expected.len, hi - lo);
        for (expected, lo..hi) |net, pin| try testing.expectEqualStrings(nl.graph.vertices.items(.name)[net.index()], p.net_name[p.pin_net[pin]]);
    }
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, p, true));
}

fn sameMembers(a: *const np.Placed, b: *const np.Placed) !void {
    for (names) |name| {
        const x = np.checks.deviceIn(a, name).?;
        const y = np.checks.deviceIn(b, name).?;
        try testing.expectEqualDeep(a.dev_pos[x], b.dev_pos[y]);
        try testing.expectEqualDeep(a.dev_orient[x], b.dev_orient[y]);
        const al, const ah = a.pinRange(x);
        const bl, const bh = b.pinRange(y);
        try testing.expectEqualDeep(a.pin_xy[al..ah], b.pin_xy[bl..bh]);
    }
}

// ---- tests ----

test "coil couplers: literal source leads and rigid transforms define independent relations" {
    const original: Frame = .{
        .{ .x = 180, .y = -50 },  .{ .x = 180, .y = 50 },   .{ .x = 380, .y = -50 },  .{ .x = 380, .y = 50 },
        .{ .x = 20, .y = -60 },   .{ .x = 20, .y = 60 },    .{ .x = 180, .y = -100 }, .{ .x = 220, .y = -100 },
        .{ .x = 260, .y = -100 }, .{ .x = 300, .y = -100 }, .{ .x = 340, .y = -100 }, .{ .x = 380, .y = -100 },
        .{ .x = 180, .y = 100 },  .{ .x = 220, .y = 100 },  .{ .x = 260, .y = 100 },  .{ .x = 300, .y = 100 },
        .{ .x = 340, .y = 100 },  .{ .x = 380, .y = 100 },  .{ .x = 260, .y = -60 },  .{ .x = 300, .y = -60 },
        .{ .x = 260, .y = 60 },   .{ .x = 300, .y = 60 },   .{ .x = 240, .y = -60 },  .{ .x = 240, .y = -20 },
        .{ .x = 320, .y = -60 },  .{ .x = 320, .y = -20 },
    };
    for (0..4) |turns| for ([_]bool{ false, true }) |mirror| {
        var points = original;
        for (&points) |*p| {
            if (mirror) p.x = -p.x;
            for (0..turns) |_| {
                const old = p.*;
                p.* = .{ .x = -old.y, .y = old.x };
            }
            p.x += 137;
            p.y -= 49;
        }
        try testing.expect(chains(points));
        try testing.expect(bridges(points));
    };
    var changed = original;
    changed[7].y += 10;
    try testing.expect(!chains(changed));
    changed = original;
    for (changed[6..12]) |*p| p.y = 0;
    try testing.expect(!chains(changed));
    changed = original;
    changed[6].x -= 10;
    try testing.expect(!chains(changed));
    changed = original;
    std.mem.swap(np.Pt, &changed[8], &changed[9]);
    try testing.expect(!chains(changed));
    changed = original;
    changed[18].y += 10;
    try testing.expect(!bridges(changed));
    changed = original;
    changed[23].x += 10;
    try testing.expect(!bridges(changed));
    changed = original;
    changed[23].y = 0;
    changed[25].y = 0;
    try testing.expect(!bridges(changed));
}

test "coil couplers: both private chains keep actual source geometry through compaction and shelves" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| for ([_]u32{ 0, 8 }) |shelf| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = shelf } }, lib, &.{full}, null);
        defer p.deinit();
        const points = try frame(&p);
        errdefer std.debug.print("chain geometry compact={} shelf={d} points={any}\n", .{ compact, shelf, points });
        try testing.expect(chains(points));
        try privateInk(&p);
        try bindings(&p, full);
        try electrical(&p, lib);
    };
}

test "coil couplers: direct and crossed bridges follow distinct actual endpoint rows" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{full}, null);
        defer p.deinit();
        try testing.expect(bridges(try frame(&p)));
        try bindings(&p, full);
        try electrical(&p, lib);
    }
}

test "coil couplers: private source ink is independent of desired geometry" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{full}, null);
        defer p.deinit();
        try privateInk(&p);
        try bindings(&p, full);
        try electrical(&p, lib);
    }
}

test "coil couplers: reversed path cards retain electrically identified chain ends" {
    const a = testing.allocator;
    var text = try a.dupe(u8, full);
    defer a.free(text);
    for ([_][2][]const u8{
        .{ "C1 net6 net4", "C1 net4 net6" }, .{ "C2 net2 net3", "C2 net3 net2" },
        .{ "C3 net0 net5", "C3 net5 net0" }, .{ "C4 net7 net1", "C4 net1 net7" },
        .{ "S1 net6 net3", "S1 net3 net6" }, .{ "S2 net0 net1", "S2 net1 net0" },
    }) |change| {
        const next = try std.mem.replaceOwned(u8, a, text, change[0], change[1]);
        a.free(text);
        text = next;
    }
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        try testing.expect(chains(try frame(&p)));
        try privateInk(&p);
        try bindings(&p, text);
        try electrical(&p, lib);
    }
}

test "coil couplers: ambiguous private incidence and a held member abstain as one chain owner" {
    const a = testing.allocator;
    for ([_][]const u8{
        "CEXTRA net6 net4 1p\n", "REXTRA net6 VSS 1k\n",
        "*@ at c1 -12 -10 r0\n", "*@ cell s1 -4 -6\n",
        "*@ nogroup c1\n",       "*@ grouping off\n",
    }) |extra| {
        const text = try std.mem.concat(a, u8, &.{ full, extra });
        defer a.free(text);
        // The bank owner remains active in both variants. Holding all six
        // chain members is the ordinary-placement control; an opaque coil
        // would also disable the bank and move the shared anchors.
        const control = try std.mem.concat(a, u8, &.{ text, "*@ nogroup c1 s1 c2 c3 s2 c4\n" });
        defer a.free(control);
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        var p = try np.place(a, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{text}, null);
        defer p.deinit();
        var ordinary = try np.place(a, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{control}, null);
        defer ordinary.deinit();
        try sameMembers(&ordinary, &p);
        try bindings(&p, text);
        try electrical(&p, lib);
    }
}
