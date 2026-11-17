//! Physical conductor and attached-name regression for reflected MOS outputs.
//! Literal SPICE cards in the gallery and the source-redraw partitions are
//! independent of selection; these tests exercise the staged routing caller.

const std = @import("std");
const np = @import("NetlistParser");
const src = @import("parent_examples");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");
const testing = std.testing;
const parts = np.schematic.sketch.parent_parts;

const Names = [4][]const u8; // net, P drain, N drain, outside gate
const rn79 = Names{ "rn", "m9", "m7", "m11" };
const rp79 = Names{ "rp", "m8", "m6", "m12" };
const rn80 = Names{ "rn", "m9", "m7", "m27" };
const rp80 = Names{ "rp", "m8", "m6", "m28" };
const fn80 = Names{ "fn1", "m16", "m18", "m29" };
const fp80 = Names{ "fp1", "m15", "m17", "m31" };

fn output(nl: *const np.Netlist, names: Names) parts.Output {
    return .{ .net = nl.net(names[0]).?.index(), .pmos = nl.device(names[1]).?.index(), .nmos = nl.device(names[2]).?.index(), .gate = nl.device(names[3]).?.index() };
}

fn check(d: []const u8, raw: []const [2]Names, policy: []const u8, expected: []const struct { Names, u8 }) !void {
    const gpa = testing.allocator;
    var scratch: std.heap.ArenaAllocator = .init(gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    var text: std.Io.Writer.Allocating = .init(a);
    var records = std.mem.tokenizeScalar(u8, d, '\n');
    while (records.next()) |line| {
        if (std.mem.startsWith(u8, line, ".subckt") or std.mem.startsWith(u8, line, ".ends")) continue;
        try text.writer.print("{s}\n", .{line});
    }
    // The selected-cell frontend labels formal gate-only inputs that the
    // primitive net vocabulary leaves internal.
    try text.writer.writeAll("*@ weak role clk input\n*@ weak role clkb input\n");
    if (std.mem.indexOf(u8, d, "CINN CINP") != null) {
        try text.writer.writeAll("*@ weak role cinn input\n*@ weak role cinp input\n");
    } else try text.writer.writeAll("*@ weak role vip input\n");
    try text.writer.writeAll(policy);
    const nl = try np.netlist.parse(a, &.{text.written()}, null);
    const roles = try np.guessRoles(a, &nl);
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const requests = try a.alloc(parts.Pair, raw.len);
    for (raw, requests) |names, *pair| pair.* = .{ output(&nl, names[0]), output(&nl, names[1]) };
    var s = try np.schematic.sketch.layWithParents(gpa, &nl, roles, lib, .{}, requests);
    defer s.deinit();
    var p = try np.Placed.init(gpa, &s, &nl);
    defer p.deinit();
    // The extra oracle point is a label under inspection; it never joins
    // two components merely because their exported strings agree.
    var query = p;
    const xy = try a.alloc(np.Pt, p.pin_xy.len + 1);
    const nets = try a.alloc(u32, xy.len);
    @memcpy(xy[0..p.pin_xy.len], p.pin_xy);
    @memcpy(nets[0..p.pin_net.len], p.pin_net);
    query.pin_xy = xy;
    query.pin_net = nets;
    const marker = xy.len - 1;
    for (expected) |row| {
        const o = output(&nl, row[0]);
        const dp = p.dev_pin0[o.pmos];
        const dn = p.dev_pin0[o.nmos];
        const gate = p.dev_pin0[o.gate] + 1;
        const n = row[1];
        try testing.expectEqual(n != 3, try ink.connected(gpa, &p, &.{ dp, dn }));
        try testing.expectEqual(n == 1, try ink.connected(gpa, &p, &.{ dp, gate }));
        try testing.expectEqual(n == 1, try ink.connected(gpa, &p, &.{ dn, gate }));
        var count: usize = 0;
        var reached: u3 = 0;
        for (p.labels) |l| {
            if (l.net != o.net) continue;
            xy[marker] = l.at;
            nets[marker] = l.net;
            var membership: u3 = 0;
            for ([_]u32{ dp, dn, gate }, 0..) |tip, i| {
                if (l.at.eql(xy[tip]) or try ink.connected(gpa, &query, &.{ tip, marker })) membership |= @as(u3, 1) << @intCast(i);
            }
            try testing.expect(membership != 0 and membership & reached == 0);
            reached |= membership;
            count += 1;
        }
        try testing.expectEqual(if (n == 1) @as(usize, 0) else n, count);
        if (n != 1) try testing.expectEqual(@as(u3, 7), reached);
    }
}

test "reflected parent outputs: the six acyclic outputs each have a named drain pair and a named separate gate" {
    try check(src.decks[1], &.{.{ rn79, rp79 }}, "", &.{ .{ rn79, 2 }, .{ rp79, 2 } });
    try check(src.decks[2], &.{ .{ fn80, fp80 }, .{ rn80, rp80 } }, "", &.{ .{ rn80, 2 }, .{ rp80, 2 }, .{ fn80, 2 }, .{ fp80, 2 } });
}

test "reflected parent outputs: caller wire or label keeps the sibling out, and cycle draws continuously" {
    try check(src.decks[2], &.{ .{ fn80, fp80 }, .{ rn80, rp80 } }, "*@ wire fn1\n", &.{ .{ fn80, 1 }, .{ fp80, 3 }, .{ rn80, 2 }, .{ rp80, 2 } });
    try check(src.decks[2], &.{ .{ fn80, fp80 }, .{ rn80, rp80 } }, "*@ label fn1\n", &.{ .{ fn80, 3 }, .{ fp80, 3 }, .{ rn80, 2 }, .{ rp80, 2 } });
    try check(src.decks[0], &.{}, "", &.{ .{ .{ "net1", "mp5", "mn5", "mp0" }, 1 }, .{ .{ "net3", "mp4", "mn4", "mp1" }, 1 } });
}

test "reflected outputs: ordinary thinning retains cut and withdraws both siblings on label" {
    const p: parts.Output = .{ .net = 0, .pmos = 0, .nmos = 1, .gate = 2 };
    var groups = [_]parts.Pair{ .{ p, p }, .{ p, p } };
    for (&groups, 0..) |*pair, i| for (pair, 0..) |*o, k| {
        o.net = @intCast(2 * i + k);
    };
    var states = [_]parts.State{ .drawn, .drawn };
    const trial: parts.Trial = .{ .pairs = &groups, .states = &states };
    try std.testing.expect(!trial.withdraw(&.{ .cut, .auto, .cut, .cut }));
    try std.testing.expect(trial.withdraw(&.{ .cut, .label, .cut, .cut }));
    try std.testing.expectEqualSlices(parts.State, &.{ .withdrawn, .drawn }, &states);
    try std.testing.expect(!trial.withdraw(&.{ .auto, .auto, .cut, .cut }));
}
