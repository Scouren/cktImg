//! Shared CT bank source regressions.
//! Oracle: actual AG1180 own leads and four eight-terminal conductor trees
//! in iteration21-shared-tanks.json. Two banks occur in one figure.
//! Both coil orders are allowed: their complete cards differ only by name.
//! Actual midpoint/column relations, MOS ground direction and local ink
//! are distinct from whole-circuit continuity and electrical equivalence.
//!
//! Contents: complete source, literal geometry oracle, then tests.

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

const Bank = struct { coils: [2][]const u8, cap: []const u8, mos: [2][]const u8 };
const banks = [_]Bank{
    .{ .coils = .{ "xle1", "xlo1" }, .cap = "ct1", .mos = .{ "m1", "m2" } },
    .{ .coils = .{ "xle2", "xlo2" }, .cap = "ct2", .mos = .{ "m3", "m4" } },
};

// ---- private ----

fn namedPin(p: *const np.Placed, lib: *const np.Library, device: []const u8, name: []const u8) !usize {
    const d = np.checks.deviceIn(p, device) orelse return error.MissingDevice;
    for (lib.at(p.dev_class[d]).terminals, 0..) |t, i| if (std.ascii.eqlIgnoreCase(t.name, name)) return p.dev_pin0[d] + i;
    return error.MissingTerminal;
}

fn bankPins(p: *const np.Placed, lib: *const np.Library, bank: Bank) ![14]usize {
    var result: [14]usize = undefined;
    for (bank.coils, 0..) |coil, i| for ([_][]const u8{ "n1", "n2", "n3" }, 0..) |term, j| {
        result[i * 3 + j] = try namedPin(p, lib, coil, term);
    };
    // Outer terminals match by electrical binding, not declaration order
    // or an arbitrary first winding end on the second coil.
    if (p.pin_net[result[3]] != p.pin_net[result[0]]) std.mem.swap(usize, &result[3], &result[4]);
    const cap = np.checks.deviceIn(p, bank.cap).?;
    const first = p.dev_pin0[cap];
    result[6] = if (p.pin_net[first] == p.pin_net[result[0]]) first else first + 1;
    result[7] = if (result[6] == first) first + 1 else first;
    for (bank.mos, 0..) |mos, i| for ([_][]const u8{ "d", "g", "s" }, 0..) |term, j| {
        result[8 + i * 3 + j] = try namedPin(p, lib, mos, term);
    };
    for ([_]usize{ 0, 3, 6, 8, 12 }) |i| try testing.expectEqual(p.pin_net[result[0]], p.pin_net[result[i]]);
    for ([_]usize{ 1, 4, 7, 9, 11 }) |i| try testing.expectEqual(p.pin_net[result[1]], p.pin_net[result[i]]);
    try testing.expect(p.pin_net[result[0]] != p.pin_net[result[1]]);
    return result;
}

fn relative(points: [14]np.Pt) bool {
    const horizontal = points[0].y == points[1].y and points[0].x != points[1].x;
    const vertical = points[0].x == points[1].x and points[0].y != points[1].y;
    if (!horizontal and !vertical) return false;
    var q: [14][2]i64 = undefined;
    for (points, &q) |p, *v| v.* = if (horizontal) .{ p.x, p.y } else .{ p.y, p.x };
    const axial_mid2 = q[0][0] + q[1][0];
    const dir: i64 = if (q[1][0] > q[0][0]) 1 else -1;
    if (q[6][1] != q[7][1] or q[6][0] + q[7][0] != axial_mid2) return false;
    if (dir * (q[7][0] - q[6][0]) <= 0) return false;
    for ([_]usize{ 0, 3 }) |i| {
        if (q[i][1] != q[i + 1][1] or q[i][0] + q[i + 1][0] != axial_mid2) return false;
        if (dir * (q[i + 1][0] - q[i][0]) <= 0 or 2 * q[i + 2][0] != axial_mid2) return false;
        if ((q[6][1] - q[i][1]) * (q[i + 2][1] - q[i][1]) >= 0) return false;
        // The drain rows sit beyond the actual winding ends.
        if (dir * (q[i][0] - q[8][0]) <= 0 or dir * (q[11][0] - q[i + 1][0]) <= 0) return false;
    }
    if (q[0][1] == q[3][1]) return false;
    if ((q[6][1] - q[0][1]) * (q[6][1] - q[3][1]) <= 0) return false;
    const toward: i64 = if (q[0][1] > q[6][1]) 1 else -1;
    if (q[8][1] != q[11][1] or toward * (q[6][1] - q[8][1]) <= 0) return false;
    for ([_]usize{ 8, 11 }) |i| {
        if (q[i][0] != q[i + 2][0] or toward * (q[i][1] - q[i + 2][1]) <= 0) return false;
        if (toward * (q[i + 1][1] - q[i + 2][1]) <= 0 or toward * (q[i][1] - q[i + 1][1]) <= 0) return false;
    }
    return dir * (q[9][0] - q[8][0]) > 0 and dir * (q[12][0] - q[9][0]) > 0 and dir * (q[11][0] - q[12][0]) > 0;
}

fn expectBank(p: *const np.Placed, lib: *const np.Library, bank: Bank) !void {
    const pins = try bankPins(p, lib, bank);
    var points: [14]np.Pt = undefined;
    for (pins, &points) |pin, *point| point.* = p.pin_xy[pin];
    errdefer std.debug.print("shared bank {s}: {any}\n", .{ bank.cap, points });
    try testing.expect(relative(points));
    try testing.expect(try ink.connected(testing.allocator, p, &.{ pins[0], pins[3], pins[6], pins[8], pins[12] }));
    try testing.expect(try ink.connected(testing.allocator, p, &.{ pins[1], pins[4], pins[7], pins[9], pins[11] }));
}

fn expectReflection(p: *const np.Placed, lib: *const np.Library) !void {
    const left = try bankPins(p, lib, banks[0]);
    const right = try bankPins(p, lib, banks[1]);
    const axis2 = @as(i64, p.pin_xy[left[0]].x) + p.pin_xy[right[0]].x;
    for (left, right) |a, b| {
        try testing.expectEqual(axis2, @as(i64, p.pin_xy[a].x) + p.pin_xy[b].x);
        try testing.expectEqual(p.pin_xy[a].y, p.pin_xy[b].y);
    }
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, p, true));
}

fn honoured(text: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{text}, null);
    const rs = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, rs);
    const sk = try np.schematic.skeleton.place(a, a, &nl, rs, &st, .{});
    for (try np.report.verdicts(a, &nl, rs, &st, &sk, p, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
}

fn reverseCards(a: std.mem.Allocator) ![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var it = std.mem.tokenizeScalar(u8, cards, '\n');
    while (it.next()) |line| try lines.append(a, line);
    std.mem.reverse([]const u8, lines.items);
    return std.mem.join(a, "\n", lines.items);
}

// ---- tests ----

test "shared coil banks: actual source geometry and reflected mutations define the oracle" {
    const original = [14]np.Pt{
        .{ .x = 180, .y = -50 }, .{ .x = 180, .y = 50 }, .{ .x = 200, .y = 0 },
        .{ .x = 110, .y = -50 }, .{ .x = 110, .y = 50 }, .{ .x = 130, .y = 0 },
        .{ .x = 60, .y = -20 }, .{ .x = 60, .y = 20 },
        .{ .x = 20, .y = -60 }, .{ .x = 0, .y = -30 }, .{ .x = -20, .y = -60 },
        .{ .x = 20, .y = 60 }, .{ .x = 0, .y = 30 }, .{ .x = -20, .y = 60 },
    };
    for ([_]bool{ false, true }) |swap| for ([_]bool{ false, true }) |mirror| {
        var points = original;
        errdefer std.debug.print("literal bank swap={} mirror={} points={any}\n", .{ swap, mirror, points });
        for (&points) |*p| {
            if (mirror) p.x = -p.x;
            if (swap) std.mem.swap(i32, &p.x, &p.y);
        }
        try testing.expect(relative(points));
    };
    var changed = original;
    changed[6].y += 10;
    changed[7].y += 10;
    try testing.expect(!relative(changed));
    changed = original;
    std.mem.swap(np.Pt, &changed[3], &changed[4]);
    try testing.expect(!relative(changed));
    changed = original;
    changed[2].x = 160;
    try testing.expect(!relative(changed));
    changed = original;
    changed[10].x = 40;
    try testing.expect(!relative(changed));
    changed = original;
    changed[9].y = -70;
    try testing.expect(!relative(changed));
    for ([_]usize{ 9, 12 }) |gate| {
        changed = original;
        changed[gate].x = 1000;
        try testing.expect(!relative(changed));
    }
}

test "shared coil banks: actual geometry and reflection are independent of physical wiring" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| for ([_]u32{ 0, 8 }) |shelf| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = shelf } }, lib, &.{full}, null);
        defer p.deinit();
        for (banks) |bank| {
            const pins = try bankPins(&p, lib, bank);
            var points: [14]np.Pt = undefined;
            for (pins, &points) |pin, *point| point.* = p.pin_xy[pin];
            const upper = try ink.connected(testing.allocator, &p, &.{ pins[0], pins[3], pins[6], pins[8], pins[12] });
            const lower = try ink.connected(testing.allocator, &p, &.{ pins[1], pins[4], pins[7], pins[9], pins[11] });
            std.debug.print("bank geometry {s} compact={} shelf={d}: relation={} upper_ink={} lower_ink={}\n", .{ bank.cap, compact, shelf, relative(points), upper, lower });
            try testing.expect(relative(points));
        }
        try expectReflection(&p, lib);
    };
}

test "shared coil banks: complete AG1180 groups both five-device banks through wrapping and compaction" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| for ([_]u32{ 0, 8 }) |shelf| {
        errdefer std.debug.print("AG1180 compact={} shelf={d}\n", .{ compact, shelf });
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = shelf } }, lib, &.{full}, null);
        defer p.deinit();
        for (banks) |bank| try expectBank(&p, lib, bank);
        try expectReflection(&p, lib);
        try electrical(&p, lib);
    };
}

test "shared coil banks: all eight actual endpoints of each source outer bus remain physically connected" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const buses = [_]struct { net: []const u8, pins: [8][2][]const u8 }{
        .{ .net = "net4", .pins = .{ .{ "c1", "b" }, .{ "ct1", "a" }, .{ "m1", "d" }, .{ "m2", "g" }, .{ "se1", "a" }, .{ "so1", "a" }, .{ "xle1", "n1" }, .{ "xlo1", "n1" } } },
        .{ .net = "net5", .pins = .{ .{ "c3", "b" }, .{ "ct1", "b" }, .{ "m1", "g" }, .{ "m2", "d" }, .{ "se2", "a" }, .{ "so2", "b" }, .{ "xle1", "n2" }, .{ "xlo1", "n2" } } },
        .{ .net = "net2", .pins = .{ .{ "c2", "a" }, .{ "ct2", "a" }, .{ "m3", "d" }, .{ "m4", "g" }, .{ "se1", "b" }, .{ "so2", "a" }, .{ "xle2", "n1" }, .{ "xlo2", "n1" } } },
        .{ .net = "net7", .pins = .{ .{ "c4", "a" }, .{ "ct2", "b" }, .{ "m3", "g" }, .{ "m4", "d" }, .{ "se2", "b" }, .{ "so1", "b" }, .{ "xle2", "n2" }, .{ "xlo2", "n2" } } },
    };
    // This is a source-equivalence goal, including pre-existing gaps: the
    // baseline20 already labelled parts of net2/net7/net5 separately.
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{full}, null);
        defer p.deinit();
        for (buses) |bus| {
            var terminals: [8]usize = undefined;
            for (bus.pins, &terminals) |named, *pin| {
                pin.* = try namedPin(&p, lib, named[0], named[1]);
                try testing.expectEqualStrings(bus.net, p.net_name[p.pin_net[pin.*]]);
            }
            var count: usize = 0;
            for (p.dev_name, 0..) |name, d| {
                if (name.len == 0 or name[0] == '_') continue;
                const lo, const hi = p.pinRange(@intCast(d));
                for (lo..hi) |pin| if (std.mem.eql(u8, p.net_name[p.pin_net[pin]], bus.net)) {
                    try testing.expect(count < terminals.len);
                    try testing.expect(std.mem.indexOfScalar(usize, &terminals, pin) != null);
                    count += 1;
                };
            }
            try testing.expectEqual(terminals.len, count);
            try testing.expect(try ink.connected(testing.allocator, &p, &terminals));
        }
        try electrical(&p, lib);
    }
}

test "shared coil banks: card ordering and capacitor reversal preserve semantic bank geometry" {
    const a = testing.allocator;
    const backwards = try reverseCards(a);
    defer a.free(backwards);
    const permuted = try std.mem.concat(a, u8, &.{ setup, backwards, "\n", roles });
    defer a.free(permuted);
    const one = try std.mem.replaceOwned(u8, a, full, "CT1 net4 net5", "CT1 net5 net4");
    defer a.free(one);
    const reversed = try std.mem.replaceOwned(u8, a, one, "CT2 net2 net7", "CT2 net7 net2");
    defer a.free(reversed);
    var reordered = try std.mem.replaceOwned(u8, a, full, "ct_inductor n1 n2 n3 params:", "ct_inductor n3 n1 n2 params:");
    defer a.free(reordered);
    for ([_][2][]const u8{
        .{ "XLE1 net4 net5 VDD ct_inductor", "XLE1 VDD net4 net5 ct_inductor" },
        .{ "XLO1 net4 net5 VDD ct_inductor", "XLO1 VDD net4 net5 ct_inductor" },
        .{ "XLE2 net2 net7 VDD ct_inductor", "XLE2 VDD net2 net7 ct_inductor" },
        .{ "XLO2 net2 net7 VDD ct_inductor", "XLO2 VDD net2 net7 ct_inductor" },
    }) |change| {
        const next = try std.mem.replaceOwned(u8, a, reordered, change[0], change[1]);
        a.free(reordered);
        reordered = next;
    }
    const coil_one = try std.mem.replaceOwned(u8, a, full, "XLO1 net4 net5 VDD", "XLO1 net5 net4 VDD");
    defer a.free(coil_one);
    const coil_reversed = try std.mem.replaceOwned(u8, a, coil_one, "XLO2 net2 net7 VDD", "XLO2 net7 net2 VDD");
    defer a.free(coil_reversed);
    const mutations = [_][]const u8{ "card order", "capacitor ends", "declaration order", "second winding ends" };
    for ([_][]const u8{ permuted, reversed, reordered, coil_reversed }, 0..) |text, which| {
        errdefer std.debug.print("shared bank mutation {s}\n", .{mutations[which]});
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        var p = try np.place(a, &.{}, lib, &.{text}, null);
        defer p.deinit();
        for (banks) |bank| try expectBank(&p, lib, bank);
        try expectReflection(&p, lib);
        if (which == 0) {
            const original_lib = try support.library(a);
            defer support.freeLibrary(a, original_lib);
            var original = try np.place(a, &.{}, original_lib, &.{full}, null);
            defer original.deinit();
            for (original.dev_name, 0..) |name, d| {
                if (name.len == 0 or name[0] == '_') continue;
                const other = np.checks.deviceIn(&p, name).?;
                try testing.expectEqualDeep(original.dev_pos[d], p.dev_pos[other]);
                try testing.expectEqualDeep(original.dev_orient[d], p.dev_orient[other]);
                const lo, const hi = original.pinRange(d);
                const ol, const oh = p.pinRange(other);
                try testing.expectEqualDeep(original.pin_xy[lo..hi], p.pin_xy[ol..oh]);
            }
        }
        try electrical(&p, lib);
    }
}

test "shared coil banks: explicit pose face and labels retain precedence" {
    const a = testing.allocator;
    const requests = [_][]const u8{
        "*@ at xle1 -12 -8 r0\n*@ at xlo1 -4 -8 r0\n*@ at ct1 -8 -4 r90\n",
        "*@ upright ct1\n*@ face m1 g right\n",
        "*@ label net4\n*@ label net5\n",
    };
    for (requests, 0..) |request, which| {
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        const text = try std.mem.concat(a, u8, &.{ full, request });
        defer a.free(text);
        var p = try np.place(a, &.{}, lib, &.{text}, null);
        defer p.deinit();
        if (which == 0) {
            try testing.expectEqualDeep(np.Pt{ .x = -480, .y = -320 }, p.dev_pos[np.checks.deviceIn(&p, "xle1").?]);
            try testing.expectEqualDeep(np.Pt{ .x = -160, .y = -320 }, p.dev_pos[np.checks.deviceIn(&p, "xlo1").?]);
            try testing.expectEqualDeep(np.Pt{ .x = -320, .y = -160 }, p.dev_pos[np.checks.deviceIn(&p, "ct1").?]);
        } else if (which == 1) {
            const pins = try bankPins(&p, lib, banks[0]);
            try testing.expectEqual(p.pin_xy[pins[6]].x, p.pin_xy[pins[7]].x);
            try testing.expect(p.pin_xy[pins[9]].x > p.pin_xy[pins[8]].x);
        } else {
            const pins = try bankPins(&p, lib, banks[0]);
            try testing.expect(!try ink.connected(a, &p, &.{ pins[0], pins[3], pins[6] }));
        }
        try honoured(text, &p, lib);
        try electrical(&p, lib);
    }
}

test "shared coil banks: shifted caller coil and capacitor frames use actual endpoints" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const terminals = [_]np.library.Terminal{
        .{ .name = "n1", .at = .{ .x = -70, .y = 20 }, .side = .left },
        .{ .name = "n2", .at = .{ .x = 90, .y = 20 }, .side = .right },
        .{ .name = "n3", .at = .{ .x = 10, .y = 50 }, .side = .down },
    };
    const coil = try lib.register(.{
        .name = "ct_inductor",
        .terminals = &terminals,
        .draw = &.{
            .{ .polyline = &.{ .{ .x = -70, .y = 20 }, .{ .x = -40, .y = 20 }, .{ .x = -30, .y = 0 }, .{ .x = -20, .y = 20 }, .{ .x = -10, .y = 0 }, .{ .x = 0, .y = 20 }, .{ .x = 20, .y = 20 }, .{ .x = 30, .y = 0 }, .{ .x = 40, .y = 20 }, .{ .x = 50, .y = 0 }, .{ .x = 60, .y = 20 }, .{ .x = 90, .y = 20 } } },
            .{ .line = .{ .a = .{ .x = 10, .y = 20 }, .b = .{ .x = 10, .y = 50 } } },
            .{ .filled_circle = .{ .c = .{ .x = 10, .y = 20 }, .r = 4 } },
        },
    });
    _ = try lib.register(.{
        .name = "bank_cap",
        .terminals = &.{ .{ .name = "a", .at = .{ .x = -30, .y = 10 }, .side = .left }, .{ .name = "b", .at = .{ .x = 50, .y = 10 }, .side = .right } },
        .draw = &.{
            .{ .line = .{ .a = .{ .x = -30, .y = 10 }, .b = .{ .x = 0, .y = 10 } } },
            .{ .line = .{ .a = .{ .x = 0, .y = -5 }, .b = .{ .x = 0, .y = 25 } } },
            .{ .line = .{ .a = .{ .x = 20, .y = -5 }, .b = .{ .x = 20, .y = 25 } } },
            .{ .line = .{ .a = .{ .x = 20, .y = 10 }, .b = .{ .x = 50, .y = 10 } } },
        },
    });
    const text = full ++ "*@ class ct1 bank_cap\n*@ class ct2 bank_cap\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        for (banks) |bank| try expectBank(&p, lib, bank);
        try expectReflection(&p, lib);
        try testing.expectEqualDeep(@as([]const np.library.Terminal, &terminals), lib.at(coil).terminals);
        try honoured(text, &p, lib);
        try electrical(&p, lib);
    }
}

test "shared coil banks: ambiguous or held linked banks do not choose a subset" {
    const a = testing.allocator;
    const mismatch1 = try std.mem.replaceOwned(u8, a, full, "XLE1 net4 net5 VDD", "XLE1 net4 net5 VCC");
    defer a.free(mismatch1);
    const mismatch = try std.mem.replaceOwned(u8, a, mismatch1, "XLE2 net2 net7 VDD", "XLE2 net2 net7 VCC");
    defer a.free(mismatch);
    const negatives = [_][]const u8{
        full ++ "CEXTRA1 net4 net5 2p\nCEXTRA2 net2 net7 2p\n",
        full ++ "XEXTRA1 net4 net5 VDD ct_inductor\nXEXTRA2 net2 net7 VDD ct_inductor\n",
        mismatch,
        full ++ "*@ at xle1 -12 -8 r0\n",
        full ++ "*@ cell xle1 -12 -8\n",
        full ++ "*@ group cross m1 m2\n",
        full ++ "*@ grouping off\n",
    };
    for (negatives) |text| {
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        const glyph = try np.block_symbols.draw(arena.allocator(), .center_tap, &.{ "n1", "n2", "n3" }, 20);
        for ([_][]const u8{ "ct_inductor", "unknown_coil" }) |name| _ = try lib.register(.{ .name = name, .terminals = glyph.terminals, .draw = glyph.ops });
        const control = try std.mem.replaceOwned(u8, a, text, "ct_inductor", "unknown_coil");
        defer a.free(control);
        var ordinary = try np.place(a, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{control}, null);
        defer ordinary.deinit();
        var p = try np.place(a, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{text}, null);
        defer p.deinit();
        for (banks) |bank| for ([_][]const u8{ bank.coils[0], bank.coils[1], bank.cap, bank.mos[0], bank.mos[1] }) |name| {
            const d = np.checks.deviceIn(&p, name).?;
            const other = np.checks.deviceIn(&ordinary, name).?;
            try testing.expectEqualDeep(ordinary.dev_pos[other], p.dev_pos[d]);
            try testing.expectEqualDeep(ordinary.dev_orient[other], p.dev_orient[d]);
        };
        try honoured(text, &p, lib);
        try electrical(&p, lib);
    }
}
