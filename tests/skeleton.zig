//! Stage 3 (issue #8): each golden figure against the cells the skeleton
//! gives its devices, before any wire; the cells do not depend on the order
//! of the cards; a symmetric circuit's cells are an exact mirror image.
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const structure = np.schematic.structure;
const skeleton = np.schematic.skeleton;
const golden = @import("golden.zig");
const textbook = @import("textbook.zig");

/// One line per golden deck, as `golden.formatScore` writes it, for the
/// skeleton's cells (labels are not scored here). A change either way fails
/// until the line is updated.
const recorded = [golden.decks.len][]const u8{
    "ota_5t x 8/8 y 8/8 rows 2+0-0 cols 2+0-0 sym 3/3 gates 5/5 labels +[] -[]",
    "two_stage_pmos x 33/33 y 26/26 rows 6+0-4 cols 3+0-0 sym 3/3 gates 7/7 labels +[] -[]",
    "fd_two_stage x 32/32 y 24/24 rows 12+0-0 cols 4+0-0 sym 5/5 gates 8/8 labels +[] -[]",
    "telescopic_fd x 24/24 y 32/32 rows 4+0-0 cols 12+0-0 sym 5/5 gates 8/8 labels +[] -[]",
    "folded_cascode x 43/43 y 44/50 rows 5+6-0 cols 12+0-0 sym 6/6 gates 2/10 labels +[] -[]",
    "strongarm x 49/49 y 38/46 rows 9+8-0 cols 6+0-0 sym 6/6 gates 7/7 labels +[] -[]",
    "gilbert x 34/36 y 28/29 rows 7+1-0 cols 0+2-0 sym 0/0 gates 4/6 labels +[] -[]",
    "cmfb_two_stage x 70/74 y 64/64 rows 14+0-0 cols 4+0-0 sym 7/7 gates 8/8 labels +[] -[]",
    "bandgap_ptat x 29/29 y 29/29 rows 7+0-0 cols 7+0-0 sym 0/0 gates 5/6 labels +[] -[]",
    "cascode_mirror x 6/6 y 8/8 rows 2+0-0 cols 4+0-0 sym 2/2 gates 4/4 labels +[] -[]",
    "wide_swing x 16/16 y 16/19 rows 2+3-0 cols 5+0-0 sym 0/0 gates 4/5 labels +[] -[]",
    "beta_multiplier x 11/11 y 13/13 rows 2+0-0 cols 4+0-0 sym 2/2 gates 4/5 labels +[] -[]",
    "diff_pair_resistive x 8/8 y 8/8 rows 2+0-0 cols 2+0-0 sym 3/3 gates 2/2 labels +[] -[]",
    "telescopic_se x 0/0 y 6/6 rows 0+0-0 cols 6+0-0 sym 0/0 gates 4/4 labels +[] -[]",
};

const Laid = struct { nl: np.netlist.Netlist, st: structure.Structure, sk: skeleton.Skeleton };

// ---- private ----

fn lay(arena: std.mem.Allocator, spice: []const u8) !Laid {
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    const st = try structure.analyze(arena, arena, &nl, roles);
    const sk = try skeleton.place(arena, arena, &nl, roles, &st);
    return .{ .nl = nl, .st = st, .sk = sk };
}

/// Each drawn device by name: form, cell and gate side.
fn cells(arena: std.mem.Allocator, l: *const Laid) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    const names = l.nl.graph.edges.items(.name);
    var order: std.ArrayList(u32) = .empty;
    for (0..names.len) |d| if (l.sk.drawn[d]) try order.append(arena, @intCast(d));
    std.mem.sort(u32, order.items, names, struct {
        fn lt(ns: []const []const u8, a: u32, b: u32) bool {
            return structure.nameLess(ns[a], ns[b]);
        }
    }.lt);
    for (order.items) |d| try out.print(arena, "{s} {t} {d},{d} {} ", .{ names[d], l.sk.form[d], l.sk.x[d], l.sk.y[d], l.sk.gate_right[d] });
    return out.items;
}

test "skeleton: each golden figure's cells score what is recorded" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var changed: usize = 0;
    for (golden.decks, recorded) |d, want| {
        const l = try lay(arena, d.spice);
        const s = try golden.scoreCells(arena, d.spice, &l.nl, l.sk.x, l.sk.y, l.sk.gate_right);
        const got = try golden.formatScore(arena, d.name, s);
        if (std.mem.eql(u8, got, want)) continue;
        changed += 1;
        std.debug.print("skeleton {s}:\n  recorded \"{s}\"\n  now      \"{s}\",\n", .{ d.name, want, got });
    }
    try std.testing.expectEqual(0, changed);
}

test "skeleton: the order of the cards changes no cell" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var decks: std.ArrayList([]const u8) = .empty;
    for (golden.decks) |d| try decks.append(arena, d.spice);
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, c.spice);
    for (decks.items) |spice| {
        const base = try lay(arena, spice);
        const want = try cells(arena, &base);
        for ([_]golden.Shuffle{ .reversed, .rotated }) |how| {
            const other = try lay(arena, try golden.shuffled(arena, spice, how));
            try std.testing.expectEqualStrings(want, try cells(arena, &other));
        }
    }
}

test "skeleton: a symmetric circuit stands as its exact mirror image" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var symmetric: usize = 0;
    for (golden.decks) |d| {
        const l = try lay(arena, d.spice);
        var axis: ?i32 = null;
        for (l.st.device_mate, 0..) |m, a| {
            if (m == structure.none or !l.sk.drawn[a] or l.sk.form[a] != .vertical) continue;
            const sum = l.sk.x[a] + l.sk.x[m];
            if (axis == null) axis = sum;
            std.testing.expectEqual(axis.?, sum) catch |err| {
                std.debug.print("{s}: {s} and its mate are not mirrored about one axis\n", .{ d.name, l.nl.graph.edges.items(.name)[a] });
                return err;
            };
            try std.testing.expectEqual(l.sk.y[a], l.sk.y[m]);
            if (m != a and l.nl.graph.edges.items(.kind)[a] == .mosfet) try std.testing.expect(l.sk.gate_right[a] != l.sk.gate_right[m]);
        }
        symmetric += @intFromBool(axis != null);
    }
    // fd_two_stage, telescopic_fd, folded_cascode, strongarm, gilbert,
    // cmfb_two_stage, diff_pair_resistive (tests/structure.zig).
    try std.testing.expectEqual(7, symmetric);
}

test "skeleton: a stack hint picks the link its column keeps" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // m1 over one of two below it (r1 keeps them from being mirror images,
    // which would stand m1 alone on the axis): rank picks m2; the hint,
    // written bottom first, m3.
    const deck = "stack hint\n.model nch nmos level=1\nM1 vdd g1 n 0 nch\nM2 n g2 0 0 nch\nM3 n g3 0 0 nch\nR1 vdd g3 1k\n";
    for ([_]struct { hint: []const u8, under: []const u8, apart: []const u8 }{
        .{ .hint = "", .under = "m2", .apart = "m3" },
        .{ .hint = "*@ group stack m3 m1\n", .under = "m3", .apart = "m2" },
    }) |case| {
        const l = try lay(arena, try std.mem.concat(arena, u8, &.{ deck, case.hint }));
        errdefer std.debug.print("{s}=> {s}\n", .{ case.hint, cells(arena, &l) catch "" });
        const top = l.nl.device("m1").?.index();
        const under = l.nl.device(case.under).?.index();
        const apart = l.nl.device(case.apart).?.index();
        try std.testing.expectEqual(l.sk.x[top], l.sk.x[under]);
        try std.testing.expect(l.sk.y[top] < l.sk.y[under]);
        try std.testing.expect(l.sk.x[top] != l.sk.x[apart]);
    }
}
