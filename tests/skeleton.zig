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
    "wide_swing x 16/16 y 16/19 rows 2+3-0 cols 5+0-0 sym 0/0 gates 5/5 labels +[] -[]",
    "beta_multiplier x 11/11 y 13/13 rows 2+0-0 cols 4+0-0 sym 2/2 gates 4/5 labels +[] -[]",
    "diff_pair_resistive x 8/8 y 8/8 rows 2+0-0 cols 2+0-0 sym 3/3 gates 2/2 labels +[] -[]",
    "telescopic_se x 0/0 y 6/6 rows 0+0-0 cols 6+0-0 sym 0/0 gates 4/4 labels +[] -[]",
};

/// Twelve common-source stages in a chain, then a differential pair with
/// its loads and tail: a row of fifteen columns, a mirrored core among them.
const wide_deck = "wide\n.model nch nmos level=1\n.model pch pmos level=1\nVDD vdd 0 1.8\n" ++
    "M1 n1 in 0 0 nch\nR1 vdd n1 1k\nM2 n2 n1 0 0 nch\nR2 vdd n2 1k\nM3 n3 n2 0 0 nch\nR3 vdd n3 1k\n" ++
    "M4 n4 n3 0 0 nch\nR4 vdd n4 1k\nM5 n5 n4 0 0 nch\nR5 vdd n5 1k\nM6 n6 n5 0 0 nch\nR6 vdd n6 1k\n" ++
    "M7 n7 n6 0 0 nch\nR7 vdd n7 1k\nM8 n8 n7 0 0 nch\nR8 vdd n8 1k\nM9 n9 n8 0 0 nch\nR9 vdd n9 1k\n" ++
    "M10 n10 n9 0 0 nch\nR10 vdd n10 1k\nM11 n11 n10 0 0 nch\nR11 vdd n11 1k\nM12 n12 n11 0 0 nch\nR12 vdd n12 1k\n" ++
    "MA oa n12 t 0 nch\nMB ob ref t 0 nch\nRA vdd oa 1k\nRB vdd ob 1k\nMT t vb 0 0 nch\n";

const Laid = struct { nl: np.netlist.Netlist, st: structure.Structure, sk: skeleton.Skeleton };

// ---- private ----

fn lay(arena: std.mem.Allocator, spice: []const u8) !Laid {
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    const st = try structure.analyze(arena, arena, &nl, roles);
    const sk = try skeleton.place(arena, arena, &nl, roles, &st, .{});
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

test "skeleton: a column goes on through the part direct current passes, the capacitor beside it" {
    // Oracle: how people draw it. Where one device meets a capacitor and a
    // part direct current passes, the person's column goes on through the
    // latter on 749 of 778 such nets of the 5,263 hand-drawn schematics;
    // reference drawing ag-694 is the first deck (the degeneration resistor
    // under the source, its bypass capacitor beside). The capacitor took
    // the link once: it reaches ground too, and `cs` sorts before `rs`.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for ([_]struct { deck: []const u8, in: []const u8, beside: []const u8 }{
        .{ .deck = "bypassed degeneration\n.model nch nmos level=1\nVDD vdd 0 1.8\nM1 vo vi n0 0 nch\nRL vdd vo 1k\nCS n0 0 1p\nRS n0 0 1k\n", .in = "rs", .beside = "cs" },
        .{ .deck = "bypassed load\n.model nch nmos level=1\nVDD vdd 0 1.8\nM1 vo vi 0 0 nch\nCL vdd vo 1p\nRL vdd vo 1k\n", .in = "rl", .beside = "cl" },
    }) |case| {
        const l = try lay(arena, case.deck);
        errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
        const m1 = l.nl.device("m1").?.index();
        try std.testing.expectEqual(l.sk.x[m1], l.sk.x[l.nl.device(case.in).?.index()]);
        try std.testing.expect(l.sk.x[m1] != l.sk.x[l.nl.device(case.beside).?.index()]);
    }
}

test "skeleton: a mirror of three turns each gate to the rest of its gate line, not all of them left" {
    // Oracle: how people draw it. Of 1,103 mirrors of three or more in the
    // 5,263 hand-drawn schematics people turn every gate left in 12; in 567
    // every gate faces one point inside the block. Reference drawing
    // ar-6074 is the deck: the diode-connected reference on the left faces
    // the two it feeds, and they face it. All three faced left here once,
    // the reference away from its own gate line.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const l = try lay(arena, "Two stages on one reference\n.model nch nmos level=1\n.model pch pmos level=1\nVDD vdd 0 1.8\nIREF vdd nb 200u\n" ++
        "M1 n0 a n2 0 nch\nM2 n1 b n2 0 nch\nM3 n0 n0 vdd vdd pch\nM4 n1 n0 vdd vdd pch\nM5 n2 nb 0 0 nch\nM6 vo n1 vdd vdd pch\nM7 vo nb 0 0 nch\nM8 nb nb 0 0 nch\n");
    errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
    const x = l.sk.x;
    const ref = l.nl.device("m8").?.index();
    const fed = [2]u32{ l.nl.device("m5").?.index(), l.nl.device("m7").?.index() };
    // Three columns, the reference outside the two it feeds.
    try std.testing.expect(x[ref] != x[fed[0]] and x[ref] != x[fed[1]] and x[fed[0]] != x[fed[1]]);
    try std.testing.expect((x[ref] < x[fed[0]]) == (x[ref] < x[fed[1]]));
    for (fed) |d| try std.testing.expectEqual(x[ref] > x[d], l.sk.gate_right[d]);
    try std.testing.expectEqual(x[fed[0]] > x[ref], l.sk.gate_right[ref]);
}

test "skeleton: a gate with nothing in the drawing to face turns left; one with a mate, away from its mate" {
    // Oracle: how people draw it. A transistor alone on its gate net (a
    // bias, an input) or with its gate on a rail has nothing in the drawing
    // to face: people turn it left, the side a signal enters by, in 2,684
    // of 3,317 such transistors of the 5,263 hand-drawn schematics, and
    // away from the drawing's middle, the rule before, in 1,914 of 3,043.
    // Reference drawing ag-50 is the first deck: the flat resistor left of
    // the column put the middle on the gates' left, and both faced right.
    // One with a mate elsewhere faces away from it (283 of 367): the mirror
    // image, as the two followers of the second deck.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    {
        const l = try lay(arena, "Cascode\n.model nch nmos level=1\n.model pch pmos level=1\nVDD vdd 0 1.8\nM1 out vb1 n0 0 nch\nM2 out vb2 vdd vdd pch\nRS in n0 1k\n");
        errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
        for ([_][]const u8{ "m1", "m2" }) |name| try std.testing.expect(!l.sk.gate_right[l.nl.device(name).?.index()]);
    }
    {
        const l = try lay(arena, "Followers\n.model nch nmos level=1\nVDD vdd 0 1.8\nM1 vdd in1 o1 0 nch\nM2 vdd in2 o2 0 nch\nR1 o1 0 1k\nR2 o2 0 1k\n");
        errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
        const m1 = l.nl.device("m1").?.index();
        const m2 = l.nl.device("m2").?.index();
        try std.testing.expect(l.sk.x[m1] != l.sk.x[m2]);
        try std.testing.expectEqual(l.sk.x[m1] > l.sk.x[m2], l.sk.gate_right[m1]);
        try std.testing.expectEqual(l.sk.x[m2] > l.sk.x[m1], l.sk.gate_right[m2]);
    }
}

test "skeleton: a resistor on the way down stands upright under the emitter it leaves, a current source upright anywhere" {
    // Oracle: how people draw it. In 5,263 hand-drawn schematics 262 of the
    // 305 resistors with one net nearer the supply and the other nearer the
    // ground (and in no plain series) stand upright, and 76 of 83 current
    // sources off the rails; reference drawing ar-4843 is the first deck:
    // the degeneration resistor under the emitter, the feedback one across.
    // `q1`'s body on ground is no way to its emitter: the distance leaked
    // through it once and `re` lay across.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    {
        const l = try lay(arena, "emitter ladder\n.model qnpn npn\nVCC vcc 0 9\nQ1 c b e 0 qnpn\nR1 vcc b 10k\nR2 b 0 2.2k\n" ++
            "RC vcc c 3.6k\nRE e n7 180\nRE1 n7 0 820\nC4 n7 0 1u\nRF e n6 1k\nC6 c n6 1u\n");
        errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
        const q1 = l.nl.device("q1").?.index();
        const re = l.nl.device("re").?.index();
        const re1 = l.nl.device("re1").?.index();
        try std.testing.expectEqual(skeleton.Form.vertical, l.sk.form[re]);
        try std.testing.expectEqual(skeleton.Form.horizontal, l.sk.form[l.nl.device("rf").?.index()]);
        try std.testing.expectEqual(l.sk.x[q1], l.sk.x[re]);
        try std.testing.expect(l.sk.y[q1] < l.sk.y[re] and l.sk.y[re] < l.sk.y[re1]);
    }
    {
        const l = try lay(arena, "current source\n.model nch nmos level=1\nVDD vdd 0 1.8\nM1 d g 0 0 nch\nRD vdd d 1k\nRF d g 10k\n" ++
            "I1 g s 1u\nC1 s 0 1p\nC2 s d 1p\n");
        errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
        try std.testing.expectEqual(skeleton.Form.vertical, l.sk.form[l.nl.device("i1").?.index()]);
    }
}

test "skeleton: a column only a bridge joins to the rest stands beside the column the bridge leads to" {
    // Oracle: the bridge's own wire. `rl` hangs on the first stage's
    // collector through the coupling capacitor `c3` and on nothing else: a
    // column pitch (8) from a column on that collector's net, its wire
    // passes no other stage. It stood past the last stage once, the wire
    // crossing three.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const l = try lay(arena, "coupled load\n.model qnpn npn\nVCC vcc 0 9\nQ1 c1 b1 0 qnpn\nRC1 vcc c1 1k\nQ2 c2 c1 0 qnpn\nRC2 vcc c2 1k\n" ++
        "Q3 c3 c2 0 qnpn\nRC3 vcc c3 1k\nQ4 c4 c3 0 qnpn\nRC4 vcc c4 1k\nC3 c1 n9 1u\nRL n9 0 10k\n*@ bridge c3\n");
    errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
    const rl = l.sk.x[l.nl.device("rl").?.index()];
    const q1 = l.sk.x[l.nl.device("q1").?.index()];
    const q2 = l.sk.x[l.nl.device("q2").?.index()];
    try std.testing.expectEqual(skeleton.Form.horizontal, l.sk.form[l.nl.device("c3").?.index()]);
    try std.testing.expect(@min(@abs(rl - q1), @abs(rl - q2)) <= 8);
}

test "skeleton: a current-controlled source stands as a source does: upright on its rail" {
    // Oracle: the independent source beside it. An F card has two pins
    // like an I card (its control is a source's name), and people draw
    // every controlled source as a two-pin source (575 of 575 in the 5,263
    // reference drawings): on ground it stands upright, as `i1` does. It
    // was no two-pin part to the skeleton, and lay flat.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const l = try lay(arena, "Current gain\nVS in 0 1\nRS in a 1k\nVSENSE a 0 0\nF1 0 out VSENSE 10\nRL out 0 1k\nI1 0 out 1m\nH1 x 0 VSENSE 5\nRX x 0 1k\n");
    errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
    for ([_][]const u8{ "i1", "f1", "h1" }) |name| try std.testing.expectEqual(skeleton.Form.vertical, l.sk.form[l.nl.device(name).?.index()]);
}

test "skeleton: a pair's tail stands between the pair's two, not the mirror reference that shares its row" {
    // Oracle: the netlist alone. The one device on the net where the two
    // of a mated pair end stands strictly between them (people: 91.9% of
    // 347 such devices in the 5,263 reference drawings). The tail and the
    // diode-connected reference that feeds its gate both map to themselves
    // and stand on one row: the reference, first by rank, took the axis and
    // the tail stood outside the pair, its wire across a half.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const l = try lay(arena, "Pair over a mirrored tail\n.model nch nmos level=1\nVDD vdd 0 1.8\nIREF vdd b 10u\nMREF b b 0 0 nch\nMT p b 0 0 nch\n" ++
        "M1 a in1 p 0 nch\nM2 c in2 p 0 nch\nR1 vdd a 10k\nR2 vdd c 10k\n");
    errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
    const x = l.sk.x;
    const m1 = x[l.nl.device("m1").?.index()];
    const m2 = x[l.nl.device("m2").?.index()];
    const tail = x[l.nl.device("mt").?.index()];
    const ref = x[l.nl.device("mref").?.index()];
    try std.testing.expect(tail > @min(m1, m2) and tail < @max(m1, m2));
    try std.testing.expect(ref < @min(m1, m2) or ref > @max(m1, m2));
}

test "skeleton: two mirrors that nets join half to half stand side by side, not one inside the other" {
    // Oracle: the hand drawings. Of 643 twos of mated pairs of columns
    // that nets join half to half in the 5,263 reference drawings, people
    // draw 406 each about its own axis and 174 about one. m1 and m2 (with
    // m5, m6 over them) and m8 and m9 (m7 over m8) are such a two: m2's
    // column drives m3, m3's ends on m9's, and a's and c's columns hang on
    // one line. They stood nested about one axis, m9 m1 | m2 m8.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const l = try lay(arena, "Two mirrors in a chain\n.model nch nmos level=1\n.model pch pmos level=1\nVdd vdd 0 1.8\nIb r 0 10u\n" ++
        "M4 r r vdd vdd pch\nM5 a r vdd vdd pch\nM6 b r vdd vdd pch\nM7 c r vdd vdd pch\n" ++
        "M1 a a 0 0 nch\nM2 b a 0 0 nch\nM8 c c 0 0 nch\nM9 y c 0 0 nch\nM3 vdd b y 0 nch\n");
    errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
    const x = l.sk.x;
    const m1 = x[l.nl.device("m1").?.index()];
    const m2 = x[l.nl.device("m2").?.index()];
    const m8 = x[l.nl.device("m8").?.index()];
    const m9 = x[l.nl.device("m9").?.index()];
    try std.testing.expect(@max(m1, m2) < @min(m8, m9) or @max(m8, m9) < @min(m1, m2));
}

test "skeleton: a pair's mirror runs up its two columns through devices of one type only" {
    // Oracle: the hand drawings. Of the pairs up and down the two columns
    // of a block's two, people draw 1,433 of 1,644 of one type level, and
    // 17 of 170 of two types, in the 5,263 reference drawings. Over m1
    // stands a p-type load, over m2 an n-type cascode under its own load:
    // m3 stands with the other load under the supply. It stood level with
    // the cascode, as its mirror image.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const l = try lay(arena, "A pair with a load of each type\n.model nch nmos level=1\n.model pch pmos level=1\nVdd vdd 0 1.8\n" ++
        "M1 a in1 t 0 nch\nM2 b in2 t 0 nch\nM5 t vb 0 0 nch\nM3 a a vdd vdd pch\nM4 c vc b 0 nch\nM6 c c vdd vdd pch\n");
    errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
    const y = l.sk.y;
    try std.testing.expectEqual(y[l.nl.device("m1").?.index()], y[l.nl.device("m2").?.index()]);
    try std.testing.expect(y[l.nl.device("m3").?.index()] < y[l.nl.device("m4").?.index()]);
    try std.testing.expectEqual(y[l.nl.device("m3").?.index()], y[l.nl.device("m6").?.index()]);
}

test "skeleton: the axis is for a column whose current joins the halves: a reference that only drives their gates stands left of them" {
    // Oracle: the hand drawings. Of the devices the symmetry maps to
    // themselves, or that are wired to both halves, people stand one
    // between the two of a pair when its current path meets theirs (1,297
    // of 1,630 in the 5,263 reference drawings; 183 of 204 tails), and
    // elsewhere when it meets them through gates alone (148 of 180 stand
    // outside the pair) or not at all. The loads' reference `mb` drives
    // both loads' gates and nothing flows from it to either half: it stood
    // on the axis once, over the tail, because the symmetry maps it to
    // itself. Free, it is placed as any column: left of what it drives.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const l = try lay(arena, "Loads on a reference\n.model nch nmos level=1\n.model pch pmos level=1\nVDD vdd 0 1.8\n" ++
        "MT p vb 0 0 nch\nM1 a in1 p 0 nch\nM2 b in2 p 0 nch\nM3 a nb vdd vdd pch\nM4 b nb vdd vdd pch\nMB nb nb vdd vdd pch\nIB nb 0 10u\n");
    errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
    const x = l.sk.x;
    const m1 = x[l.nl.device("m1").?.index()];
    const m2 = x[l.nl.device("m2").?.index()];
    const tail = x[l.nl.device("mt").?.index()];
    const ref = x[l.nl.device("mb").?.index()];
    try std.testing.expectEqual(m1 + m2, 2 * tail);
    try std.testing.expect(ref < @min(x[l.nl.device("m3").?.index()], x[l.nl.device("m4").?.index()]));
}

test "skeleton: a bias net current paths end on pulls its columns together: the capacitor on it stands beside the transistor's column" {
    // Oracle: the hand drawings. Of the nets on exactly two columns in the
    // 5,263 reference drawings, people stand the two next to each other
    // for 1,719 of the 2,316 a current path ends on at both (74.2%), and
    // for 103 of the 137 of those that are a bias or an input; a net of
    // gates alone, 304 of 733 (a random order: 35%). `vb` is a bias the
    // capacitor c and the resistor r2 (under q1, in its column) end on: it
    // pulled nothing, being no internal net, and r1 stood between (deck
    // ar-6385 of the reference corpus, its coils made resistors: an
    // inductor off the rails lies flat, forms.19, and leaves the column).
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const l = try lay(arena, "Oscillator core\n.model qnpn npn\nC vin vb 1p\nR1 vin net0 1k\nR2 net0 vb 1k\nQ1 vin vb net0 0 qnpn\n");
    errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
    const x = l.sk.x;
    const q1 = x[l.nl.device("q1").?.index()];
    try std.testing.expectEqual(q1, x[l.nl.device("r2").?.index()]);
    const c = x[l.nl.device("c").?.index()];
    const l1 = x[l.nl.device("r1").?.index()];
    try std.testing.expect(@abs(c - q1) < @abs(l1 - q1));
}

test "skeleton: a circuit of parts stands with its source on the left, whatever the order of its cards" {
    // Oracle: the hand drawings, and a metamorphic relation. Of two parts
    // at different distances from a circuit's one source, people draw the
    // farther to the right in 90.1% of 1,676 pairs of the 5,263 reference
    // drawings: an RC ladder's source stands left of its first shunt, and
    // that left of the second, with the cards in either order. With no
    // stage to tell the signal's way the row was left as it fell, the
    // source on the right.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for ([_][]const u8{
        "Ladder\n*@ driver v1 inline\nV1 in 0 ac 1\nR1 in a 1k\nC1 a 0 1p\nR2 a b 1k\nC2 b 0 1p\n",
        "Ladder\n*@ driver v1 inline\nC2 b 0 1p\nR2 a b 1k\nC1 a 0 1p\nR1 in a 1k\nV1 in 0 ac 1\n",
    }) |deck| {
        const l = try lay(arena, deck);
        errdefer std.debug.print("=> {s}\n", .{cells(arena, &l) catch ""});
        const x = l.sk.x;
        try std.testing.expect(x[l.nl.device("v1").?.index()] < x[l.nl.device("c1").?.index()]);
        try std.testing.expect(x[l.nl.device("c1").?.index()] < x[l.nl.device("c2").?.index()]);
    }
}

test "skeleton: what drives a net stands left of what reads it, a mirrored core or none: the core faces that way and a second stage stands right of it" {
    // Oracle: the hand drawings, and a metamorphic relation. Of the 1,200
    // hand drawings with a mirrored core (of 5,263) that differ from their
    // mirror image in the pins standing left of every device that drives
    // their net, 1,036 face the way with fewer; a column outside the core
    // that the core drives stands right of it in 599 of 843. So a mirror's
    // copy stands right of its reference whichever of the pair's two the
    // reference loads, and a second stage right of the pair's device whose
    // node it reads, from either half. The core faced by the rank of its
    // devices once, and a stage read from the left half's node stood left
    // of the core, its gate before its driver.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const head = "second stage\n.model nch nmos level=1\n.model pch pmos level=1\nVdd vdd 0 1.8\nM1 a in1 p 0 nch\nM2 b in2 p 0 nch\n" ++
        "M5 p vb 0 0 nch\nR6 vdd x 1k\n";
    for ([_]struct { load: []const u8, reference: []const u8, copy: []const u8 }{
        .{ .load = "M3 a a vdd vdd pch\nM4 b a vdd vdd pch\n", .reference = "m3", .copy = "m4" },
        .{ .load = "M3 a b vdd vdd pch\nM4 b b vdd vdd pch\n", .reference = "m4", .copy = "m3" },
    }) |mirror| for ([_]struct { node: []const u8, driver: []const u8 }{
        .{ .node = "a", .driver = "m1" },
        .{ .node = "b", .driver = "m2" },
    }) |stage| {
        const l = try lay(arena, try std.mem.concat(arena, u8, &.{ head, mirror.load, "M6 x ", stage.node, " 0 0 nch\n" }));
        errdefer std.debug.print("{s}M6 on {s} => {s}\n", .{ mirror.load, stage.node, cells(arena, &l) catch "" });
        const x = l.sk.x;
        try std.testing.expect(x[l.nl.device(mirror.reference).?.index()] < x[l.nl.device(mirror.copy).?.index()]);
        try std.testing.expect(x[l.nl.device(stage.driver).?.index()] < x[l.nl.device("m6").?.index()]);
    };
}

test "skeleton: a row of more than eight columns wraps into shelves, a pair never parted; `*@ shelf` sets the width" {
    // Oracle: a page as people fill it (their drawings of over 30 devices
    // are 20 units wide at the median, the one row of columns was 37), and
    // the cut's own contract: every shelf at most the width asked where a
    // cut is allowed, each under the one before, the columns of a shelf in
    // the order they had, a device and its mirror image in one shelf about
    // one axis. `*@ shelf off` is the one row again.
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const flat = try lay(arena, wide_deck ++ "*@ shelf off\n");
    for (flat.sk.shelf) |s| try std.testing.expectEqual(0, s);
    try std.testing.expectEqual(.honoured, flat.sk.verdicts[0].?.state);
    const bad = try lay(arena, wide_deck ++ "*@ shelf wide\n");
    try std.testing.expectEqual(.rejected, bad.sk.verdicts[0].?.state);
    for ([_]struct { line: []const u8, cols: usize, shelves: u32 }{
        .{ .line = "", .cols = 8, .shelves = 2 },
        .{ .line = "*@ shelf 5\n", .cols = 5, .shelves = 3 },
    }) |case| {
        const l = try lay(arena, try std.mem.concat(arena, u8, &.{ wide_deck, case.line }));
        errdefer std.debug.print("{s}=> {s}\n", .{ case.line, cells(arena, &l) catch "" });
        const n = l.sk.x.len;
        var last: u32 = 0;
        for (0..n) |d| {
            if (l.sk.drawn[d]) last = @max(last, l.sk.shelf[d]);
        }
        try std.testing.expectEqual(case.shelves - 1, last);
        for (0..n) |a| {
            if (!l.sk.drawn[a] or l.sk.form[a] != .vertical) continue;
            // The shelf's width: the distinct columns left of or at `a`.
            var cols: std.AutoHashMapUnmanaged(i32, void) = .empty;
            for (0..n) |b| {
                if (!l.sk.drawn[b] or l.sk.form[b] != .vertical) continue;
                if (l.sk.shelf[b] == l.sk.shelf[a]) try cols.put(arena, l.sk.x[b], {});
                // A later shelf stands under an earlier one.
                if (l.sk.shelf[b] > l.sk.shelf[a]) try std.testing.expect(l.sk.y[b] > l.sk.y[a]);
                // Within a shelf the columns keep the order of the one row.
                if (l.sk.shelf[b] == l.sk.shelf[a] and flat.sk.x[a] < flat.sk.x[b]) try std.testing.expect(l.sk.x[a] < l.sk.x[b]);
            }
            try std.testing.expect(cols.count() <= case.cols);
            const m = l.st.device_mate[a];
            if (m == structure.none or !l.sk.drawn[m]) continue;
            try std.testing.expectEqual(l.sk.shelf[a], l.sk.shelf[m]);
            try std.testing.expectEqual(l.sk.axis2.?, l.sk.x[a] + l.sk.x[m]);
        }
    }
}
