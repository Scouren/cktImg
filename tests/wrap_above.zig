//! Explicit vertical ordering → the same relation after shelf wrapping.
//! Cites: the public above-hint contract and the twelve-stage chain in
//! support.zig; this case contains no converter or inferred power group.
//!
//! Human Rules:
//! - A shelf cut must preserve an admitted caller relation. An invalid
//!   or unknown-device instruction changes neither placement nor cuts.
//!
//! Contents: private hint checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

// ---- private ----

fn expectHints(src: []const u8, p: *const np.Placed, lib: *const np.Library, wants: []const np.hints.Verdict) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const verdicts = try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib);
    try testing.expectEqual(wants.len, verdicts.len);
    for (verdicts, wants) |got, want| {
        try testing.expectEqual(want.code, got.code);
        try testing.expectEqual(want.state, got.state);
        try testing.expectEqualSlices(u32, want.blocked_by, got.blocked_by);
    }
}

test "shelves: an admitted above relation survives a cut between ordinary stages" {
    // Caller oracle: M10 must be above M1. With shelves disabled this
    // holds, but the old cut put M1 on the first shelf and M10 beneath it,
    // undoing the admitted relation. No converter inference is involved.
    const src = support.wide_chain ++ "*@ above m10 m1\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        for ([_]u32{ 0, 8 }) |shelf| {
            var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = shelf } }, lib, &.{src}, null);
            defer p.deinit();
            const upper = np.checks.deviceIn(&p, "m10").?;
            const lower = np.checks.deviceIn(&p, "m1").?;
            try testing.expect(p.dev_pos[upper].y < p.dev_pos[lower].y);
            if (shelf != 0) try expectHints(src, &p, lib, &.{.of(.ok)});
            try support.expectConnected(&p, lib);
            try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
        }
    }
}

test "shelves: an admitted forward above chain permits the existing shelf cut" {
    // Oracle: the twelve ordinary stages wrap after stage six. The
    // exported top-to-bottom chain crosses that cut from left to right;
    // it remains true on successive shelves and must not join them.
    const src = support.wide_chain ++ "*@ above r1 m1 r7 m7\n";
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    try testing.expect(sk.shelf[nl.device("m1").?.index()] < sk.shelf[nl.device("r7").?.index()]);
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        const chain = [_][]const u8{ "r1", "m1", "r7", "m7" };
        for (chain[0 .. chain.len - 1], chain[1..]) |upper, lower| {
            try testing.expect(p.dev_pos[np.checks.deviceIn(&p, upper).?].y < p.dev_pos[np.checks.deviceIn(&p, lower).?].y);
        }
        try expectHints(src, &p, lib, &.{.of(.ok)});
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}

test "shelves: rejected relation instructions leave ordinary wrapping unchanged" {
    // Metamorphic oracle: rejected hints promise no change. Unknown
    // devices, duplicate devices, undrawn drivers and missing arguments
    // must not protect a shelf interval. The malformed spanning lines
    // still name M1 and M10, so scanning their raw arguments would fail.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        const cfg: np.Config = .{ .layout = .{ .compact = compact } };
        var before = try np.place(testing.allocator, &cfg, lib, &.{support.wide_chain}, null);
        defer before.deinit();
        for ([_][]const u8{
            support.wide_chain ++ "*@ above m10 missing m1\n",
            support.wide_chain ++ "*@ above m10 m10 m1\n",
            support.wide_chain ++ "*@ above m10 vdd m1\n",
            support.wide_chain ++ "*@ above m10\n",
            support.wide_chain ++ "*@ row m10 missing m1\n",
            support.wide_chain ++ "*@ order m10 missing m1\n",
        }, [_]np.hints.Code{ .unknown_name, .bad_args, .not_placeable, .bad_args, .unknown_name, .unknown_name }) |src, code| {
            var after = try np.place(testing.allocator, &cfg, lib, &.{src}, null);
            defer after.deinit();
            try testing.expectEqualSlices(np.Pt, before.dev_pos, after.dev_pos);
            try testing.expectEqualSlices(np.Pt, before.pin_xy, after.pin_xy);
            try expectHints(src, &after, lib, &.{.of(code)});
            try support.expectConnected(&after, lib);
            try testing.expectEqual(0, try support.shorts(testing.allocator, &after, true));
        }
    }
}

test "shelves: a dropped conflicting above line cannot widen an admitted span" {
    // Metamorphic oracle: M2 above M1 is the only admitted relation. The
    // dropped line additionally names M10 across the ordinary shelf cut;
    // protecting its raw names would change an otherwise identical deck.
    // Both strength and last-line precedence must drop the whole cycle.
    const control = support.wide_chain ++ "*@ above m2 m1\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        const cfg: np.Config = .{ .layout = .{ .compact = compact } };
        var before = try np.place(testing.allocator, &cfg, lib, &.{control}, null);
        defer before.deinit();
        for ([_][]const u8{
            control ++ "*@ weak above m1 m2 m10\n",
            support.wide_chain ++ "*@ above m1 m2 m10\n*@ above m2 m1\n",
        }, 0..) |src, k| {
            var after = try np.place(testing.allocator, &cfg, lib, &.{src}, null);
            defer after.deinit();
            try testing.expectEqualSlices(np.Pt, before.dev_pos, after.dev_pos);
            try testing.expectEqualSlices(np.Pt, before.pin_xy, after.pin_xy);
            if (k == 0) {
                try expectHints(src, &after, lib, &.{
                    .of(.ok),
                    .{ .state = .dropped, .code = .cycle, .blocked_by = &.{0} },
                });
            } else {
                try expectHints(src, &after, lib, &.{
                    .{ .state = .dropped, .code = .cycle, .blocked_by = &.{1} },
                    .of(.ok),
                });
            }
            try support.expectConnected(&after, lib);
            try testing.expectEqual(0, try support.shorts(testing.allocator, &after, true));
        }
    }
}
