//! Caller-frame regressions for the private CT coupling chains.
//! Oracle: actual collinear and ordered source path leads, unchanged caller
//! classes and all four ordered switch bindings. Control pins are visible
//! in the positive custom class and are never hidden by inferred placement.
//!
//! Contents: complete AG1180 deck, private endpoint helpers, then tests.

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

const switches = [_]np.library.Terminal{
    .{ .name = "a", .at = .{ .x = -30, .y = 20 }, .side = .left },
    .{ .name = "b", .at = .{ .x = 50, .y = 20 }, .side = .right },
    .{ .name = "c+", .at = .{ .x = 10, .y = -20 }, .side = .up },
    .{ .name = "c-", .at = .{ .x = 10, .y = 60 }, .side = .down },
};
const cap = [_]np.library.Terminal{
    .{ .name = "a", .at = .{ .x = -30, .y = 20 }, .side = .left },
    .{ .name = "b", .at = .{ .x = 50, .y = 20 }, .side = .right },
};
const hints = "*@ class c1 chain_cap\n*@ class c2 chain_cap\n*@ class c3 chain_cap\n*@ class c4 chain_cap\n*@ class s1 chain_switch\n*@ class s2 chain_switch\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, net: []const u8) !usize {
    const lo, const hi = p.pinRange(np.checks.deviceIn(p, name).?);
    var found: ?usize = null;
    for (lo..hi) |i| if (std.mem.eql(u8, net, p.net_name[p.pin_net[i]])) {
        try testing.expect(found == null);
        found = i;
    };
    return found orelse error.MissingBinding;
}

fn custom(lib: *np.Library, terms: []const np.library.Terminal) ![2]np.ClassId {
    return .{
        try lib.register(.{ .name = "chain_cap", .terminals = &cap, .draw = &.{
            .{ .line = .{ .a = .{ .x = -30, .y = 20 }, .b = .{ .x = 0, .y = 20 } } },
            .{ .line = .{ .a = .{ .x = 0, .y = 5 }, .b = .{ .x = 0, .y = 35 } } },
            .{ .line = .{ .a = .{ .x = 20, .y = 5 }, .b = .{ .x = 20, .y = 35 } } },
            .{ .line = .{ .a = .{ .x = 20, .y = 20 }, .b = .{ .x = 50, .y = 20 } } },
        } }),
        try lib.register(.{ .name = "chain_switch", .terminals = terms, .draw = &.{
            .{ .line = .{ .a = .{ .x = -30, .y = 20 }, .b = .{ .x = 0, .y = 20 } } },
            .{ .line = .{ .a = .{ .x = 0, .y = 20 }, .b = .{ .x = 20, .y = 10 } } },
            .{ .line = .{ .a = .{ .x = 20, .y = 20 }, .b = .{ .x = 50, .y = 20 } } },
            .{ .line = .{ .a = terms[2].at, .b = .{ .x = 10, .y = 0 } } },
            .{ .line = .{ .a = terms[3].at, .b = .{ .x = 10, .y = 40 } } },
        } }),
    };
}

fn relation(p: *const np.Placed, row: usize) !void {
    const cards_here = [2][3][]const u8{ .{ "c1", "s1", "c2" }, .{ "c3", "s2", "c4" } };
    const nets = [2][4][]const u8{ .{ "net4", "net6", "net3", "net2" }, .{ "net5", "net0", "net1", "net7" } };
    var endpoints: [6]usize = undefined;
    for (cards_here[row], 0..) |name, j| {
        endpoints[2 * j] = try pin(p, name, nets[row][j]);
        endpoints[2 * j + 1] = try pin(p, name, nets[row][j + 1]);
    }
    const start = p.pin_xy[endpoints[0]];
    const finish = p.pin_xy[endpoints[5]];
    const dir: i64 = if (finish.x > start.x) 1 else -1;
    for (endpoints, 0..) |e, i| {
        try testing.expectEqual(start.y, p.pin_xy[e].y);
        if (i > 0) try testing.expect(dir * (@as(i64, p.pin_xy[e].x) - p.pin_xy[endpoints[i - 1]].x) > 0);
    }
    const drain = p.pin_xy[try pin(p, if (row == 0) "m1" else "m2", nets[row][0])];
    try testing.expect(if (row == 0) start.y < drain.y else start.y > drain.y);
    for ([_][2]usize{ .{ 1, 2 }, .{ 3, 4 } }) |pair| try testing.expect(try ink.connected(testing.allocator, p, &.{ endpoints[pair[0]], endpoints[pair[1]] }));
    const sw = np.checks.deviceIn(p, cards_here[row][1]).?;
    const lo, const hi = p.pinRange(sw);
    try testing.expectEqual(@as(usize, 4), hi - lo);
    try testing.expectEqualStrings(if (row == 0) "s1" else "s2", p.net_name[p.pin_net[lo + 2]]);
    try testing.expectEqualStrings("vss", p.net_name[p.pin_net[lo + 3]]);
    try testing.expectEqual(@as(i64, start.x) + finish.x, @as(i64, p.pin_xy[lo].x) + p.pin_xy[lo + 1].x);
}

// ---- tests ----

test "coil chain frames: shifted long paths and visible controls keep actual rows and card bindings" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const ids = try custom(lib, &switches);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{full ++ hints}, null);
        defer p.deinit();
        try relation(&p, 0);
        try relation(&p, 1);
        try testing.expectEqualDeep(@as([]const np.library.Terminal, &cap), lib.at(ids[0]).terminals);
        try testing.expectEqualDeep(@as([]const np.library.Terminal, &switches), lib.at(ids[1]).terminals);
        try support.expectConnected(&p, lib);
        try testing.expectEqual(@as(u32, 0), try support.shorts(a, &p, true));
    }
}

test "coil chain frames: off-axis controls retain their caller frame while path midpoints align" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    var changed = switches;
    changed[2].at.x += 15;
    const ids = try custom(lib, &changed);
    const text = full ++ hints;
    var p = try np.place(a, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{text}, null);
    defer p.deinit();
    // Source ink certifies only path contacts. A self-mated switch does
    // not imply that two different native control pins share its axis.
    try relation(&p, 0);
    try relation(&p, 1);
    for ([_][]const u8{ "s1", "s2" }) |name| {
        const d = np.checks.deviceIn(&p, name).?;
        const lo, const hi = p.pinRange(d);
        try testing.expectEqual(@as(usize, 4), hi - lo);
        for (changed[2..], lo + 2..hi) |terminal, i| {
            try testing.expect(!terminal.hidden);
            try testing.expectEqualDeep(p.dev_pos[d].add(p.dev_orient[d].apply(terminal.at)), p.pin_xy[i]);
        }
    }
    try testing.expectEqualDeep(@as([]const np.library.Terminal, &changed), lib.at(ids[1]).terminals);
    try support.expectConnected(&p, lib);
    try testing.expectEqual(@as(u32, 0), try support.shorts(a, &p, true));
}
