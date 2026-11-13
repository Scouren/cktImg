//! Stage 2a (issue #8) against the book: each golden figure's symmetry and
//! blocks, read off the figure by hand, and that neither depends on the
//! order of the cards; the deck's grouping hints (#7) over recognition.
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const structure = np.schematic.structure;
const golden = @import("golden.zig");
const textbook = @import("textbook.zig");

/// Per golden deck: the pairs its figure draws mirrored about one axis and
/// the devices on the axis (sources aside), and the units it draws. Read off
/// the figures with the definitions of `BlockKind`, not from a run.
const expected = [_]struct { deck: []const u8, symmetry: []const u8, blocks: []const u8 }{
    .{ .deck = "ota_5t", .symmetry = "", .blocks = "mirror m3 m4; pair m1 m2; stack m3 m1; stack m4 m2" },
    .{ .deck = "two_stage_pmos", .symmetry = "", .blocks = "bank m5 m6; mirror m3 m4; pair m1 m2; stack m1 m3; stack m2 m4; stack m6 m7" },
    .{ .deck = "fd_two_stage", .symmetry = "iss m1:m2 m3:m4 m5:m6 m7:m8", .blocks = "bank m3 m4; bank m7 m8; pair m1 m2; stack m3 m1; stack m4 m2; stack m5 m7; stack m6 m8" },
    .{ .deck = "telescopic_fd", .symmetry = "iss m1:m2 m3:m4 m5:m6 m7:m8", .blocks = "bank m3 m4; bank m5 m6; bank m7 m8; pair m1 m2; stack m7 m5 m3 m1; stack m8 m6 m4 m2" },
    .{ .deck = "folded_cascode", .symmetry = "iss m1:m2 m3:m4 m5:m6 m7:m8 m9:m10", .blocks = "bank m3 m4; bank m5 m6; bank m7 m8; bank m9 m10; pair m1 m2; stack m10 m8 m4; stack m9 m7 m3" },
    .{ .deck = "strongarm", .symmetry = "m1:m2 m3:m4 m5:m6 mt s1:s2 s3:s4", .blocks = "cross m3 m4; cross m5 m6; pair m1 m2; stack m3 m5 m1; stack m4 m6 m2" },
    .{ .deck = "gilbert", .symmetry = "iss m1:m4 m2:m3 m5:m6 rd1:rd2", .blocks = "pair m1 m2; pair m3 m4; pair m5 m6" },
    .{ .deck = "cmfb_two_stage", .symmetry = "iss m1:m2 m3:m4 m5:m6 m7:m8 r1:r2 r3:r4", .blocks = "bank m3 m4; bank m7 m8; pair m1 m2; stack m3 m1; stack m4 m2; stack m5 m7; stack m6 m8" },
    .{ .deck = "bandgap_ptat", .symmetry = "", .blocks = "bank m3 m4 m5; stack m3 q1" },
    .{ .deck = "cascode_mirror", .symmetry = "", .blocks = "mirror m0 m3; mirror m1 m2; stack m0 m1; stack m3 m2" },
    .{ .deck = "wide_swing", .symmetry = "", .blocks = "bank m2 m3; mirror m1 m4 m5; stack m1 m2; stack m4 m3" },
    .{ .deck = "beta_multiplier", .symmetry = "", .blocks = "mirror m1 m2; mirror m3 m4" },
    .{ .deck = "diff_pair_resistive", .symmetry = "iss m1:m2 rd1:rd2", .blocks = "pair m1 m2" },
    .{ .deck = "telescopic_se", .symmetry = "", .blocks = "stack m4 m3 m2 m1" },
};

const Described = struct { symmetry: []const u8, blocks: []const u8 };

// ---- private ----

fn describe(arena: std.mem.Allocator, spice: []const u8) !Described {
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    const s = try structure.analyze(arena, arena, &nl, roles);
    const names = nl.graph.edges.items(.name);
    const kinds = nl.graph.edges.items(.kind);

    var sym: std.ArrayList([]const u8) = .empty;
    for (s.device_mate, 0..) |m, d| {
        if (m == structure.none or kinds[d] == .vsource) continue;
        if (m == d) {
            try sym.append(arena, names[d]);
        } else if (structure.nameLess(names[d], names[m])) {
            try sym.append(arena, try arena.print("{s}:{s}", .{ names[d], names[m] }));
        }
    }
    std.mem.sort([]const u8, sym.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return structure.nameLess(a, b);
        }
    }.lt);

    var blocks: std.ArrayList([]const u8) = .empty;
    for (s.block_kind, 0..) |k, b| {
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(arena, @tagName(k));
        for (s.members(b)) |d| try text.print(arena, " {s}", .{names[d]});
        try blocks.append(arena, text.items);
    }
    std.mem.sort([]const u8, blocks.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return .{ .symmetry = try std.mem.join(arena, " ", sym.items), .blocks = try std.mem.join(arena, "; ", blocks.items) };
}

/// The 5T OTA's blocks under `hints` (lines appended to its deck): what
/// recognition finds is "mirror m3 m4; pair m1 m2; stack m3 m1; stack m4 m2".
fn hinted(arena: std.mem.Allocator, hints: []const u8) ![]const u8 {
    const deck = for (golden.decks) |d| {
        if (std.mem.eql(u8, d.name, "ota_5t")) break d;
    } else return error.NoSuchDeck;
    return (try describe(arena, try std.mem.concat(arena, u8, &.{ deck.spice, "\n", hints, "\n" }))).blocks;
}

test "structure: names sort by their numbers" {
    try std.testing.expect(structure.nameLess("m2", "m10"));
    try std.testing.expect(!structure.nameLess("m10", "m2"));
    try std.testing.expect(structure.nameLess("m5:m6", "mt"));
    try std.testing.expect(structure.nameLess("m", "m1"));
    try std.testing.expect(!structure.nameLess("m1", "m1"));
    try std.testing.expect(structure.nameLess("r007", "r8"));
    // Equal as numbers, still ordered: nothing falls back to card order.
    try std.testing.expect(structure.nameLess("m01", "m1"));
    try std.testing.expect(!structure.nameLess("m1", "m01"));
}

test "structure: each golden figure's symmetry and blocks" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var wrong: usize = 0;
    for (expected) |e| {
        const deck = for (golden.decks) |d| {
            if (std.mem.eql(u8, d.name, e.deck)) break d;
        } else return error.NoSuchDeck;
        const got = try describe(arena, deck.spice);
        if (std.mem.eql(u8, got.symmetry, e.symmetry) and std.mem.eql(u8, got.blocks, e.blocks)) continue;
        wrong += 1;
        std.debug.print("{s}:\n  symmetry want \"{s}\"\n           got  \"{s}\"\n  blocks   want \"{s}\"\n           got  \"{s}\"\n", .{ e.deck, e.symmetry, got.symmetry, e.blocks, got.blocks });
    }
    try std.testing.expectEqual(0, wrong);
}

test "structure: one gate net's groups are listed in the device table's order of kinds" {
    // Oracle: the device table (src/device.zig, `DeviceKind`): a BJT comes
    // before a MOSFET there, and no other list of transistor kinds exists.
    // The blocks were listed MOSFETs first; either order draws the 5,263
    // reference circuits and the fixtures alike.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var nl = try np.netlist.parse(arena, &.{"Two kinds on one line\n.model nch nmos level=1\n.model qn npn\nVdd vdd 0 1.8\n" ++
        "M1 a g 0 0 nch\nM2 b g 0 0 nch\nQ1 c g 0 qn\nQ2 d g 0 qn\nR1 vdd a 1k\nR2 vdd b 1k\nR3 vdd c 1k\nR4 vdd d 1k\n"}, null);
    const s = try structure.analyze(arena, arena, &nl, try np.guessRoles(arena, &nl));
    const kinds = nl.graph.edges.items(.kind);
    try std.testing.expectEqual(2, s.block_kind.len);
    try std.testing.expectEqual(.bjt, kinds[s.members(0)[0]]);
    try std.testing.expectEqual(.mosfet, kinds[s.members(1)[0]]);
}

test "structure: the order of the cards changes nothing" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var decks: std.ArrayList([]const u8) = .empty;
    for (golden.decks) |d| try decks.append(arena, d.spice);
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, c.spice);
    for (decks.items) |spice| {
        const base = try describe(arena, spice);
        for ([_]golden.Shuffle{ .reversed, .rotated }) |how| {
            const other = try describe(arena, try golden.shuffled(arena, spice, how));
            try std.testing.expectEqualStrings(base.symmetry, other.symmetry);
            try std.testing.expectEqualStrings(base.blocks, other.blocks);
        }
    }
}

test "hints: a hinted group stands as written, over recognition" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // The loads hinted a pair: no longer a mirror; the inputs still a pair.
    try std.testing.expectEqualStrings("pair m1 m2; pair m3 m4; stack m3 m1; stack m4 m2", try hinted(arena, "*@ group pair m4 m3"));
    // A stack hint, top to bottom as written, holds its devices from
    // recognized stacks.
    try std.testing.expectEqualStrings("mirror m3 m4; pair m1 m2; stack m1 m3; stack m4 m2", try hinted(arena, "*@ group stack m1 m3"));
}

test "hints: nogroup keeps a device out of every group, grouping off out of recognized ones" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // m1 in no pair and no stack: m2 has no partner left.
    try std.testing.expectEqualStrings("mirror m3 m4; stack m4 m2", try hinted(arena, "*@ nogroup m1"));
    // Nothing recognized, the hinted group only; nogroup wins over a hint.
    try std.testing.expectEqualStrings("mirror m3 m4", try hinted(arena, "*@ grouping off\n*@ group mirror m3 m4\n*@ group pair m1 m2\n*@ nogroup m1"));
}

test "hints: a name the deck does not have is passed over, and the rest holds" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // A pair of one known device is no pair: recognition finds m1 m2.
    try std.testing.expectEqualStrings("mirror m3 m4; pair m1 m2; stack m3 m1; stack m4 m2", try hinted(arena, "*@ group pair m1 mx\n*@ nogroup my"));
    // Hints inside a `.subckt` are its own, not the deck's.
    try std.testing.expectEqualStrings("mirror m3 m4; pair m1 m2; stack m3 m1; stack m4 m2", try hinted(arena, ".subckt blk a b\n*@ grouping off\nr1 a b 1k\n.ends"));
}
