//! Independent linked-output qualification and actual-pin consumer controls.
//! Oracle: literal raw3/raw4 interfaces, all supply/body slots and original
//! admitted requests. The source proof supplies the named 2+1 choice; these
//! mutations prove that incomplete or requested variants are outside it.
//!
//! Contents: complete literal graph, qualification fixture, then tests.

const std = @import("std");
const testing = std.testing;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const hints = @import("hints.zig");
const netlines = @import("netlines.zig");
const loads = @import("resistor_loads.zig");
const routing = @import("resistor_downstream.zig");

const cards = "Linked\n.model nn nmos\n.model pp pmos\n" ++
    "ML top top vdd vdd pp\nR1 top a 1k\nR2 top b 1k\nM1 a in1 tail 0 nn\nM2 b in2 tail 0 nn\nMT tail vb2 0 0 nn\n" ++
    "MN top2 top2 vdd vdd pp\nR3 top2 c 1k\nR4 top2 d 1k\nM3 c a tail2 0 nn\nM4 d b tail2 0 nn\nMU tail2 vb2 0 0 nn\n" ++
    "MI out c common 0 nn\nRI vdd out 1k\nMF vdd out nf 0 nn\nMP np out vdd vdd pp\n" ++
    "MJ out2 d common 0 nn\nRJ vdd out2 1k\nMG vdd out2 ng 0 nn\nMQ nq out2 vdd vdd pp\n";
const names = [_][]const u8{ "ml", "r1", "r2", "m1", "m2", "mt", "mn", "r3", "r4", "m3", "m4", "mu" };
const Mutation = struct { from: []const u8, to: []const u8 };
const raw_changes = [_]Mutation{
    .{ .from = "MI out c common 0 nn", .to = "MI out c common 0 nn\nCX c spare 1p" },
    .{ .from = "MI out c common 0 nn", .to = "MI out c common 0 unknown" },
    .{ .from = "MI out c common 0 nn", .to = "MI out c common c nn" },
    .{ .from = "MI out c common 0 nn", .to = "MI out c common vdd nn" },
    .{ .from = "MI out c common 0 nn", .to = "MI c c common 0 nn" },
    .{ .from = "MI out c common 0 nn", .to = "MI out c out 0 nn" },
    .{ .from = "RI vdd out 1k", .to = "RI vdd out 1k\nCX out spare 1p" },
    .{ .from = "RI vdd out 1k", .to = "RI wrong out 1k" },
    .{ .from = "RI vdd out 1k", .to = "RI out out 1k" },
    .{ .from = "MF vdd out nf 0 nn", .to = "MF vdd out nf 0 unknown" },
    .{ .from = "MF vdd out nf 0 nn", .to = "MF vdd out nf 0 pp" },
    .{ .from = "MF vdd out nf 0 nn", .to = "MF wrong out nf 0 nn" },
    .{ .from = "MF vdd out nf 0 nn", .to = "MF vdd out nf vdd nn" },
    .{ .from = "MP np out vdd vdd pp", .to = "MP np out vdd 0 pp" },
    .{ .from = "MP np out vdd vdd pp", .to = "MP np out wrong vdd pp" },
    .{ .from = "MP np out vdd vdd pp", .to = "MP np out vdd vdd unknown" },
};

// ---- private ----

fn qualified(deck: []const u8, extra: []const u8, expected: usize, copies: usize, admitted: bool) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var combined: std.ArrayList(u8) = .empty;
    try combined.appendSlice(a, deck);
    if (copies == 2) {
        var lines = std.mem.splitScalar(u8, deck, '\n');
        while (lines.next()) |line| {
            var words = std.mem.tokenizeAny(u8, line, " \t");
            const name = words.next() orelse continue;
            if (name[0] != 'M' and name[0] != 'R') continue;
            try combined.appendSlice(a, try std.fmt.allocPrint(a, "{s}_b", .{name}));
            const count: usize = if (name[0] == 'M') 4 else 2;
            for (0..count) |_| {
                const net = words.next().?;
                const shared = std.mem.eql(u8, net, "0") or std.mem.eql(u8, net, "vdd");
                try combined.appendSlice(a, try std.fmt.allocPrint(a, " {s}{s}", .{ net, if (shared) "" else "_b" }));
            }
            try combined.appendSlice(a, try std.fmt.allocPrint(a, " {s}\n", .{words.rest()}));
        }
    }
    const input = try std.fmt.allocPrint(a, "{s}\n{s}\n", .{ combined.items, extra });
    var nl = try netlist.parse(a, &.{input}, null);
    const roles = try sch.guessRoles(a, &nl);
    const dv = try a.alloc(?hints.Verdict, nl.hints.len);
    const sv = try a.alloc(?hints.Verdict, nl.hints.len);
    const tv = try a.alloc(?hints.Verdict, nl.hints.len);
    @memset(dv, null);
    @memset(sv, null);
    @memset(tv, null);
    const lines = try netlines.read(a, &nl, roles, 40, dv);
    // The consumer receives already admitted geometry verdicts. Public
    // source tests separately exercise real parser/admission behavior.
    if (extra.len != 0) {
        try testing.expect(nl.hints.len != 0);
        if (dv[dv.len-1] == null) sv[sv.len-1] = if (admitted) .of(.ok) else .of(.unknown_name);
    }
    var pair: loads.Pair = undefined;
    for (names, 0..) |name, i| pair[i/6][i%6] = nl.device(name).?;
    var owners = [_]loads.Pair{ pair, pair };
    if (copies == 2) for (names, 0..) |name, i| {
        const second = try std.fmt.allocPrint(a, "{s}_b", .{name});
        owners[1][i/6][i%6] = nl.device(second).?;
        try testing.expect(owners[1][i/6][i%6] != owners[0][i/6][i%6]);
    };
    const result = routing.qualify(&nl, roles, owners[0..copies], sv, tv, dv, &lines);
    try testing.expectEqual(expected, result.len);
    if (expected != 0) try testing.expect(owners[0..copies].ptr == result.ptr);
}

test "resistor downstream: complete raw interfaces and spelling/order transformations qualify" {
    try qualified(cards, "", 1, 1, false);
    try qualified(cards, "", 0, 0, false);
    try qualified(cards, "", 0, 2, false);
    for ([_]Mutation{
        .{ .from = "R3 top2 c 1k", .to = "R3 c top2 1k" },
        .{ .from = "RI vdd out 1k", .to = "RI out vdd 1k" },
        .{ .from = "MF vdd out nf 0 nn\nMP np out vdd vdd pp", .to = "MP np out vdd vdd pp\nMF vdd out nf 0 nn" },
    }) |change| {
        const mutated = try std.mem.replaceOwned(u8, testing.allocator, cards, change.from, change.to);
        defer testing.allocator.free(mutated);
        try qualified(mutated, "", 1, 1, false);
    }
}

test "resistor downstream: raw extra pins aliases and every supply/body boundary decline" {
    for (raw_changes) |change| {
        errdefer std.debug.print("downstream raw mutation {s} -> {s}\n", .{ change.from, change.to });
        try testing.expect(std.mem.indexOf(u8, cards, change.from) != null);
        const mutated = try std.mem.replaceOwned(u8, testing.allocator, cards, change.from, change.to);
        defer testing.allocator.free(mutated);
        try qualified(mutated, "", 0, 1, false);
    }
}

test "resistor downstream: original net and every external member geometry request wins" {
    for ([_][]const u8{
        "*@ label c", "*@ wire c trunk", "*@ role c input\n*@ port c left", "*@ first c",
        "*@ face mi g right", "*@ face mf g right", "*@ face mp g right", "*@ upright ri",
        "*@ at mj 100 100", "*@ cell mg 2 2", "*@ group bank mq mp", "*@ order ri rj",
        "*@ grouping off", "*@ symmetry off",
    }) |line| try qualified(cards, line, 0, 1, true);
    try qualified(cards, "*@ face absent g left", 1, 1, false);
    try qualified(cards, "*@ face m1 g left", 1, 1, true); // Successful owner already owns this earlier qualification.
}
