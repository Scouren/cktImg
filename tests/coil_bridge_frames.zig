//! Four-switch caller-frame and whole-owner precedence regressions.
//! Oracle: actual source path rows/columns and rigid caller transforms;
//! source switch controls have no measured source position. All four
//! electrical bindings remain present. No label establishes physical ink.
//!
//! Contents: complete AG1180 deck, actual-lead helpers, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

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

const names = [_][]const u8{ "se1", "se2", "so1", "so2" };
const bound = [_][4][]const u8{
    .{ "net4", "net2", "se", "vss" }, .{ "net5", "net7", "se", "vss" },
    .{ "net4", "net7", "so", "vss" }, .{ "net2", "net5", "so", "vss" },
};
const terms = [_]np.library.Terminal{
    .{ .name = "a", .at = .{ .x = -10, .y = 20 }, .side = .left },
    .{ .name = "b", .at = .{ .x = 30, .y = 20 }, .side = .right },
    .{ .name = "c+", .at = .{ .x = 4, .y = -20 }, .side = .up },
    .{ .name = "c-", .at = .{ .x = 16, .y = -20 }, .side = .up },
};
const frame_hints = "*@ class se1 bridge_switch\n*@ class se2 bridge_switch\n*@ class so1 bridge_switch\n*@ class so2 bridge_switch\n";
const disabled = "*@ nogroup se1 se2 so1 so2\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, net: []const u8) !np.Pt {
    const lo, const hi = p.pinRange(np.checks.deviceIn(p, name).?);
    var found: ?np.Pt = null;
    for (lo..hi) |i| if (std.mem.eql(u8, net, p.net_name[p.pin_net[i]])) {
        try testing.expect(found == null);
        found = p.pin_xy[i];
    };
    return found orelse error.MissingBinding;
}

fn geometry(p: *const np.Placed) !void {
    const a = try pin(p, "xle1", "net4");
    const b = try pin(p, "xle2", "net2");
    const bottom = try pin(p, "xle1", "net5");
    const upper = try pin(p, "m1", "net4");
    const lower = try pin(p, "m2", "net5");
    const axis2 = @as(i64, a.x) + b.x;
    var cross: [2][2]np.Pt = undefined;
    for (names, bound, 0..) |name, nets, i| {
        const d = np.checks.deviceIn(p, name).?;
        const lo, const hi = p.pinRange(d);
        try testing.expectEqual(@as(usize, 4), hi - lo);
        for (nets, lo..hi) |net, j| try testing.expectEqualStrings(net, p.net_name[p.pin_net[j]]);
        const first = try pin(p, name, nets[0]);
        const last = try pin(p, name, nets[1]);
        for ([_]np.Pt{ first, last }) |q| try testing.expect(q.x > @min(a.x, b.x) and q.x < @max(a.x, b.x));
        if (i < 2) {
            const y = if (i == 0) upper.y else lower.y;
            try testing.expectEqual(y, first.y);
            try testing.expectEqual(y, last.y);
            try testing.expectEqual(axis2, @as(i64, first.x) + last.x);
        } else {
            cross[i - 2] = .{ first, last };
            try testing.expectEqual(first.x, last.x);
            try testing.expectEqual(upper.y, first.y);
            try testing.expect(first.y < last.y and 2 * @as(i64, last.y) < @as(i64, a.y) + bottom.y);
        }
    }
    try testing.expect(cross[0][0].x != cross[1][0].x);
    for (0..2) |i| {
        try testing.expectEqual(cross[0][i].y, cross[1][i].y);
        try testing.expectEqual(axis2, @as(i64, cross[0][i].x) + cross[1][i].x);
    }
}

fn custom(lib: *np.Library) !np.ClassId {
    return lib.register(.{ .name = "bridge_switch", .terminals = &terms, .draw = &.{
        .{ .line = .{ .a = terms[0].at, .b = .{ .x = 0, .y = 20 } } },
        .{ .line = .{ .a = .{ .x = 0, .y = 20 }, .b = .{ .x = 20, .y = 10 } } },
        .{ .line = .{ .a = .{ .x = 20, .y = 20 }, .b = terms[1].at } },
        .{ .line = .{ .a = terms[2].at, .b = .{ .x = 4, .y = 0 } } },
        .{ .line = .{ .a = terms[3].at, .b = .{ .x = 16, .y = 0 } } },
    } });
}

fn same(p: *const np.Placed, q: *const np.Placed) !void {
    for (names) |name| {
        const a = np.checks.deviceIn(p, name).?;
        const b = np.checks.deviceIn(q, name).?;
        try testing.expectEqualDeep(p.dev_pos[a], q.dev_pos[b]);
        try testing.expectEqualDeep(p.dev_orient[a], q.dev_orient[b]);
        const lo, const hi = p.pinRange(a);
        const qlo, const qhi = q.pinRange(b);
        try testing.expectEqualDeep(p.pin_xy[lo..hi], q.pin_xy[qlo..qhi]);
    }
}

fn requests(text: []const u8, p: *const np.Placed, lib: *const np.Library, last: np.hints.State) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{text}, null);
    const rs = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, rs);
    const sk = try np.schematic.skeleton.place(a, a, &nl, rs, &st, .{ .shelf = 8 });
    const verdicts = try np.report.verdicts(a, &nl, rs, &st, &sk, p, lib);
    for (verdicts, 0..) |v, i| try testing.expectEqual(if (i + 1 == verdicts.len) last else np.hints.State.honoured, v.state);
    if (last == .rejected) try testing.expectEqual(np.hints.Code.not_placeable, verdicts[verdicts.len - 1].code);
}

// ---- tests ----

test "coil bridge frames: shifted complete glyphs keep actual paths and visible controls" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const id = try custom(lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{full ++ frame_hints}, null);
        defer p.deinit();
        try geometry(&p);
        for (names) |name| {
            const d = np.checks.deviceIn(&p, name).?;
            const lo, const hi = p.pinRange(d);
            for (terms, lo..hi) |terminal, i| {
                try testing.expect(!terminal.hidden);
                try testing.expectEqualDeep(p.dev_pos[d].add(p.dev_orient[d].apply(terminal.at)), p.pin_xy[i]);
            }
        }
        try testing.expectEqualDeep(@as([]const np.library.Terminal, &terms), lib.at(id).terminals);
        try support.expectConnected(&p, lib);
        try testing.expectEqual(@as(u32, 0), try support.shorts(a, &p, true));
    }
}

test "coil bridge frames: one caller request or topology competitor holds all four members" {
    const a = testing.allocator;
    for ([_][]const u8{
        "*@ at se1 -20 -20\n", "*@ cell so1 -5 -5\n", "*@ upright so1\n*@ face so1 a down\n",
        "*@ upright se1\n", "*@ grouping off\n", "*@ label net4\n",
        "SX net4 net2 se vss ideal_switch\n", "REXTRA net6 vss 10k\n",
    }) |extra| {
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        const text = try std.mem.concat(a, u8, &.{ full, extra });
        defer a.free(text);
        const control = try std.mem.concat(a, u8, &.{ text, disabled });
        defer a.free(control);
        for ([_]bool{ false, true }) |compact| {
            var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
            defer p.deinit();
            var q = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{control}, null);
            defer q.deinit();
            errdefer std.debug.print("bridge held request={s} compact={}\n", .{ extra, compact });
            try requests(text, &p, lib, .honoured);
            try same(&p, &q);
            try support.expectConnected(&p, lib);
            try testing.expectEqual(@as(u32, 0), try support.shorts(a, &p, true));
        }
    }
}


test "coil bridge frames: a rejected horizontal four-pin face does not hold automatic placement" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    // "a" is a valid switch endpoint, but the existing horizontal face
    // request accepts two-card-pin parts only. Preserve that rejection;
    // the valid upright + downward face is covered separately above.
    const text = full ++ "*@ face so1 a right\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        var q = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{full}, null);
        defer q.deinit();
        try requests(text, &p, lib, .rejected);
        try geometry(&p);
        try same(&p, &q);
        try support.expectConnected(&p, lib);
        try testing.expectEqual(@as(u32, 0), try support.shorts(a, &p, true));
    }
}
