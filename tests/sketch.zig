//! Stage 4 (issue #8): drawings from the skeleton. Every drawing (textbook,
//! golden, and every AnalogIOC cell) keeps each device once, every net one
//! piece as a netlister reads it, and no wire on another net's point. (Each
//! golden figure's score is `golden.zig`'s.)
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const golden = @import("golden.zig");
const support = @import("support.zig");
const textbook = @import("textbook.zig");
const fixtures = @import("fixtures.zig");

const Place = struct { name: []const u8, at: np.Pt };

// ---- private ----

/// The first source is the deck; the rest only lend it `.subckt`s.
fn draw(arena: std.mem.Allocator, lib: *np.Library, sources: []const []const u8, layout: np.config.Layout) !np.Placed {
    var nl = try np.netlist.parse(arena, sources, null);
    const roles = try np.guessRoles(arena, &nl);
    const s = try np.layout(arena, &nl, roles, lib, layout);
    return np.Placed.init(arena, &s, &nl);
}

/// The named devices' places, by name.
fn placesByName(arena: std.mem.Allocator, p: *const np.Placed) ![]const Place {
    var out: std.ArrayList(Place) = .empty;
    for (p.dev_name, p.dev_pos) |n, at| if (n.len > 0) try out.append(arena, .{ .name = n, .at = at });
    std.mem.sort(Place, out.items, {}, struct {
        fn lt(_: void, a: Place, b: Place) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    return out.items;
}

/// `placesByName` of `deck`'s drawing `p`, the drivers aside: a driver is
/// drawn apart from the circuit (R3) and shares no row or column with it,
/// so which of the two stands higher says nothing of the layout.
fn latticePlaces(arena: std.mem.Allocator, deck: []const u8, p: *const np.Placed) ![]const Place {
    var nl = try np.netlist.parse(arena, &.{deck}, null);
    const roles = try np.guessRoles(arena, &nl);
    var out: std.ArrayList(Place) = .empty;
    for (try placesByName(arena, p)) |place| {
        const driver = for (nl.graph.edges.items(.name), 0..) |name, d| {
            if (std.mem.eql(u8, name, place.name)) break np.schematic.isDriver(&nl.graph, roles, @intCast(d));
        } else false;
        if (!driver) try out.append(arena, place);
    }
    return out.items;
}

/// Points where a level wire of one net and an upright wire of another
/// cross inside both.
fn crossings(p: *const np.Placed) usize {
    var count: usize = 0;
    for (0..p.netCount()) |n| {
        var h = p.segments(n);
        while (h.next()) |hp| for (hp[0 .. hp.len - 1], hp[1..]) |a, b| {
            if (a.y != b.y) continue;
            for (0..p.netCount()) |m| {
                if (m == n) continue;
                var v = p.segments(m);
                while (v.next()) |vp| for (vp[0 .. vp.len - 1], vp[1..]) |c, d| {
                    if (c.x != d.x) continue;
                    count += @intFromBool(c.x > @min(a.x, b.x) and c.x < @max(a.x, b.x) and a.y > @min(c.y, d.y) and a.y < @max(c.y, d.y));
                };
            }
        };
    }
    return count;
}

/// Bends on net `n`'s wire: the points where one level piece and one
/// upright piece of it end, and nothing else of it touches.
fn bends(p: *const np.Placed, n: usize) usize {
    var seen: [64]np.Pt = undefined;
    var n_seen: usize = 0;
    var count: usize = 0;
    var it = p.segments(n);
    while (it.next()) |poly| for (poly) |at| {
        const known = for (seen[0..n_seen]) |q| {
            if (q.x == at.x and q.y == at.y) break true;
        } else false;
        if (known) continue;
        seen[n_seen] = at;
        n_seen += 1;
        // A piece ending at `at` counts once, one passing through twice.
        var level: usize = 0;
        var upright: usize = 0;
        var jt = p.segments(n);
        while (jt.next()) |q| for (q[0 .. q.len - 1], q[1..]) |a, b| {
            if (at.x < @min(a.x, b.x) or at.x > @max(a.x, b.x) or at.y < @min(a.y, b.y) or at.y > @max(a.y, b.y)) continue;
            const ends: usize = if ((at.x == a.x and at.y == a.y) or (at.x == b.x and at.y == b.y)) 1 else 2;
            if (a.y == b.y) level += ends else upright += ends;
        };
        count += @intFromBool(level == 1 and upright == 1);
    };
    return count;
}

/// Ends of net `n`'s wire on nothing: no pin, no name, and no other way
/// out along the wire.
fn looseEnds(p: *const np.Placed, n: usize) usize {
    var count: usize = 0;
    var it = p.segments(n);
    while (it.next()) |poly| for ([_]np.Pt{ poly[0], poly[poly.len - 1] }) |at| {
        var held = false;
        for (p.pin_xy, p.pin_net) |xy, net| held = held or (net == n and xy.x == at.x and xy.y == at.y);
        for (p.labels) |l| held = held or (l.net == n and l.at.x == at.x and l.at.y == at.y);
        count += @intFromBool(!held and @popCount(arms(p, n, at)) < 2);
    };
    return count;
}

/// The ways net `n`'s wire leaves `at`, a bit a `Side` in its order: left,
/// right, up, down.
fn arms(p: *const np.Placed, n: usize, at: np.Pt) u4 {
    var out: u4 = 0;
    var it = p.segments(n);
    while (it.next()) |q| for (q[0 .. q.len - 1], q[1..]) |a, b| {
        if (at.x < @min(a.x, b.x) or at.x > @max(a.x, b.x) or at.y < @min(a.y, b.y) or at.y > @max(a.y, b.y)) continue;
        for ([_]np.Pt{ a, b }) |e| {
            if (e.x < at.x) out |= 1;
            if (e.x > at.x) out |= 2;
            if (e.y < at.y) out |= 4;
            if (e.y > at.y) out |= 8;
        }
    };
    return out;
}

/// The device pins of net `n` that are no end of its wire leaving the way
/// the pin faces: a pin the wire runs through, turns on, or does not reach.
fn pinsOffEnd(p: *const np.Placed, lib: *const np.Library, n: usize) usize {
    var count: usize = 0;
    for (0..p.deviceCount()) |d| {
        // A rail's or a port's symbol stands on its stub's end.
        if (p.dev_name[d].len == 0) continue;
        const from, const to = p.pinRange(d);
        for (from..to) |k| {
            if (p.pin_net[k] != n) continue;
            const side = lib.at(p.dev_class[d]).side(k - from, p.dev_orient[d]) orelse continue;
            count += @intFromBool(arms(p, n, p.pin_xy[k]) != @as(u4, 1) << @backingInt(side));
        }
    }
    return count;
}

/// Device `name`'s pin `index` in `p`.
fn pinOf(p: *const np.Placed, name: []const u8, index: u32) np.Pt {
    for (p.dev_name, 0..) |n, d| if (std.mem.eql(u8, n, name)) return p.pin_xy[p.pinRange(d)[0] + index];
    unreachable;
}

/// `spice` through the stages one by one, ready to draw: the schematic, its
/// structure, and a skeleton the caller may edit.
fn staged(arena: std.mem.Allocator, lib: *np.Library, spice: []const u8) !struct { nl: np.netlist.Netlist, s: np.Schematic, st: np.schematic.structure.Structure, x: []i32, y: []i32, sk: np.schematic.skeleton.Skeleton } {
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    const s = try np.schematic.initDevices(arena, &nl, roles, lib);
    const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
    var sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{});
    const x = try arena.dupe(i32, sk.x);
    const y = try arena.dupe(i32, sk.y);
    sk.x = x;
    sk.y = y;
    return .{ .nl = nl, .s = s, .st = st, .x = x, .y = y, .sk = sk };
}

test "sketch: every drawing keeps its devices, is connected, and shorts nothing" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var decks: std.ArrayList(struct { []const u8, []const u8 }) = .empty;
    for (golden.decks) |d| try decks.append(arena, .{ d.name, d.spice });
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, .{ c.name, c.spice });
    var bad: usize = 0;
    for (decks.items) |d| {
        const p = try draw(arena, lib, &.{d[1]}, .{});
        support.expectConnected(&p, lib) catch {
            std.debug.print("sketch {s}: a net in pieces\n", .{d[0]});
            bad += 1;
        };
        const shorts = try support.shorts(gpa, &p, true);
        if (shorts > 0) {
            std.debug.print("sketch {s}: {d} nets touch another's point\n", .{ d[0], shorts });
            bad += 1;
        }
        const dotted = try support.dots(gpa, &p, true);
        if (dotted > 0) {
            std.debug.print("sketch {s}: {d} points whose dot is wrong\n", .{ d[0], dotted });
            bad += 1;
        }
    }
    try std.testing.expectEqual(0, bad);
}

test "sketch: every AnalogIOC cell keeps its devices, is connected, and shorts nothing" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var bad: usize = 0;
    // As cktimg-json reads a file of `.subckt`s: each one's body a deck of
    // its own, the file lending it the rest.
    for (fixtures.analogioc) |f| {
        const file = try std.fmt.allocPrint(arena, "{s}\n{s}", .{ f.name, f.spice });
        const nl = try np.netlist.parse(arena, &.{file}, null);
        try std.testing.expect(nl.defs.len >= 1);
        for (nl.defs) |d| {
            const cell = try std.fmt.allocPrint(arena, "{s}\n{s}", .{ d.name, d.body });
            const p = try draw(arena, lib, &.{ cell, file[f.name.len + 1 ..] }, .{});
            support.expectConnected(&p, lib) catch {
                std.debug.print("sketch {s} / {s}: a net in pieces\n", .{ f.name, d.name });
                bad += 1;
            };
            const shorts = try support.shorts(gpa, &p, true);
            if (shorts > 0) {
                std.debug.print("sketch {s} / {s}: {d} nets touch another's point\n", .{ f.name, d.name, shorts });
                bad += 1;
            }
            const dotted = try support.dots(gpa, &p, true);
            if (dotted > 0) {
                std.debug.print("sketch {s} / {s}: {d} points whose dot is wrong\n", .{ f.name, d.name, dotted });
                bad += 1;
            }
        }
    }
    try std.testing.expectEqual(0, bad);
}

test "sketch: a symbol set whose unit is under four still draws, connected and short-free" {
    // The C ABI and a symbol file accept any unit above 0; the router steps
    // a quarter of it.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var bad: usize = 0;
    for ([_]i32{ 1, 2, 3 }) |unit| {
        lib.unit = unit;
        for (textbook.all ++ textbook.beyond) |c| {
            const p = try draw(arena, lib, &.{c.spice}, .{});
            support.expectConnected(&p, lib) catch {
                std.debug.print("unit {d}, {s}: a net in pieces\n", .{ unit, c.name });
                bad += 1;
            };
            const shorts = try support.shorts(gpa, &p, true);
            if (shorts > 0) {
                std.debug.print("unit {d}, {s}: {d} nets touch another's point\n", .{ unit, c.name, shorts });
                bad += 1;
            }
        }
    }
    try std.testing.expectEqual(0, bad);
}

test "sketch: lengths space the drawing and move nothing to another row or column" {
    // Rows, columns and order are the skeleton's; `config.Layout` only
    // spaces them. Every two named devices keep their order along x and
    // along y, and the stretched drawing keeps every guarantee.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const long: np.config.Layout = .{ .stack = 2, .series = 3, .rail = 1.5, .terminal = 2, .label = 1, .tap = 1.5, .clearance = 0.5, .bend_cost = 3, .cross_cost = 0.5 };
    var decks: std.ArrayList(struct { []const u8, []const u8 }) = .empty;
    for (golden.decks) |d| try decks.append(arena, .{ d.name, d.spice });
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, .{ c.name, c.spice });
    var bad: usize = 0;
    for (decks.items) |d| {
        const base = try latticePlaces(arena, d[1], &try draw(arena, lib, &.{d[1]}, .{}));
        const p = try draw(arena, lib, &.{d[1]}, long);
        const wide = try latticePlaces(arena, d[1], &p);
        try std.testing.expectEqual(base.len, wide.len);
        for (base, wide, 0..) |a, b, i| {
            try std.testing.expectEqualStrings(a.name, b.name);
            for (base[i + 1 ..], wide[i + 1 ..]) |a2, b2| {
                if (std.math.order(a.at.x, a2.at.x) == std.math.order(b.at.x, b2.at.x) and
                    std.math.order(a.at.y, a2.at.y) == std.math.order(b.at.y, b2.at.y)) continue;
                std.debug.print("{s}: {s} and {s} change order\n", .{ d[0], a.name, a2.name });
                bad += 1;
            }
        }
        support.expectConnected(&p, lib) catch {
            std.debug.print("{s}: a net in pieces\n", .{d[0]});
            bad += 1;
        };
        const shorts = try support.shorts(gpa, &p, true);
        if (shorts > 0) {
            std.debug.print("{s}: {d} nets touch another's point\n", .{ d[0], shorts });
            bad += shorts;
        }
    }
    try std.testing.expectEqual(0, bad);
}

test "sketch: stages stand in the order the signal passes them, each load beside its stage" {
    // Oracles: CircuitThink #006 as its authors drew it (Analog Canvas
    // gallery ct-006, Apache-2.0): three common-source stages in a ring,
    // M1, M2, M3 in a row, each stage's load capacitor beside it before the
    // next; and the convention that a signal enters on the left and leaves
    // on the right (Razavi's figures; chip-arena's "Signal left → right").
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const ring = try draw(arena, lib, &.{
        \\Three-stage ring
        \\.model nch nmos
        \\Vdd vdd 0 1.8
        \\CL1 n1 0 1p
        \\CL2 n2 0 1p
        \\CL3 vout 0 1p
        \\M1 n1 vout 0 0 nch
        \\M2 n2 n1 0 0 nch
        \\M3 vout n2 0 0 nch
        \\RD1 vdd n1 1k
        \\RD2 vdd n2 1k
        \\RD3 vdd vout 1k
        \\
    }, .{});
    const chain = [_][]const u8{ "m1", "cl1", "m2", "cl2", "m3" };
    var rising: usize = 0;
    for (chain[0 .. chain.len - 1], chain[1..]) |a, b| rising += @intFromBool(pinOf(&ring, a, 0).x < pinOf(&ring, b, 0).x);
    // Left to right, or the whole row mirrored.
    try std.testing.expect(rising == chain.len - 1 or rising == 0);
    const amp = try draw(arena, lib, &.{
        \\Two-stage amplifier
        \\.model nch nmos
        \\Vdd vdd 0 1.8
        \\Vin vin 0 dc 0.7 ac 1
        \\CL vout 0 1p
        \\M2 vout n1 0 0 nch
        \\RD2 vdd vout 1k
        \\M1 n1 vin 0 0 nch
        \\RD1 vdd n1 1k
        \\
    }, .{});
    try std.testing.expect(pinOf(&amp, "m1", 0).x < pinOf(&amp, "m2", 0).x);
    try std.testing.expect(pinOf(&amp, "m2", 0).x < pinOf(&amp, "cl", 0).x);
}

test "sketch: a mirror the pair's halves are not wired to stands side by side, off the pair's axis" {
    // Oracle: AnalogRetriever's bias-cancelled input stage as drawn in the
    // Analog Canvas gallery (ar-6069, MIT): the mirror Q7, Q8 side by side
    // left of the pair, whose loads Q5, Q6 stand side by side over it; and
    // the book's convention that a mirror's two stand together (Razavi
    // Fig. 5.2). Nested about the pair's axis, Q5 and Q6 stood between them.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const stage = try draw(arena, lib, &.{
        \\Bias-cancelled input stage
        \\.model qnpn npn
        \\.model qpnp pnp
        \\Vcc vcc 0 5
        \\I1 net2 vee 1m
        \\Q1 net0 vi net2 qnpn
        \\Q2 net4 0 net2 qnpn
        \\Q3 net3 net1 net0 qnpn
        \\Q4 vo net0 net4 qnpn
        \\Q5 net3 net3 vcc qpnp
        \\Q6 vo net3 vcc qpnp
        \\Q7 net1 net1 vcc qpnp
        \\Q8 vi net1 vcc qpnp
        \\
    }, .{});
    const a = pinOf(&stage, "q7", 0).x;
    const b = pinOf(&stage, "q8", 0).x;
    try std.testing.expect(a != b);
    for ([_][]const u8{ "q1", "q2", "q3", "q4", "q5", "q6" }) |name| {
        const x = pinOf(&stage, name, 0).x;
        try std.testing.expect(x <= @min(a, b) or x >= @max(a, b));
    }
    // The pair's loads keep the pair's axis: the tail source under its middle.
    try std.testing.expectEqual(2 * pinOf(&stage, "i1", 0).x, pinOf(&stage, "q5", 0).x + pinOf(&stage, "q6", 0).x);
}

test "sketch: a ground by any name: transistors on `vss` stand as those on net 0 do" {
    // Oracle: a metamorphic relation. Renaming the ground net moves no
    // device; and the book's two-stage op-amp (Razavi Fig. 9.22), whose
    // second-stage current source stands level with the tail source.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const deck =
        \\Two-stage op-amp
        \\.model nch nmos
        \\.model pch pmos
        \\Vdd vdd 0 1.8
        \\M1 n1 inm tail 0 nch
        \\M2 n2 inp tail 0 nch
        \\M3 n1 n1 vdd vdd pch
        \\M4 n2 n1 vdd vdd pch
        \\M5 tail vb1 0 0 nch
        \\M6 vout n2 vdd vdd pch
        \\M7 vout vb2 0 0 nch
        \\
    ;
    const renamed = try std.mem.replaceOwned(u8, arena, deck, " 0", " vss");
    const zero = try draw(arena, lib, &.{deck}, .{});
    const vss = try draw(arena, lib, &.{renamed}, .{});
    for ([_][]const u8{ "m1", "m2", "m3", "m4", "m5", "m6", "m7" }) |name| {
        try std.testing.expectEqual(pinOf(&zero, name, 0), pinOf(&vss, name, 0));
    }
    try std.testing.expectEqual(pinOf(&vss, "m5", 0).y, pinOf(&vss, "m7", 0).y);
}

test "sketch: a lower crossing budget names more nets and draws no more crossings" {
    // Oracle: a metamorphic relation over every deck. Against no budget
    // (`cross_max` out of reach), a budget of none keeps every name, adds
    // only names, and crosses no more wires; and on some deck it crosses
    // fewer, so the key does something.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var fewer: usize = 0;
    var decks: std.ArrayList([]const u8) = .empty;
    for (golden.decks) |d| try decks.append(arena, d.spice);
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, c.spice);
    for (decks.items) |spice| {
        const free = try draw(arena, lib, &.{spice}, .{ .cross_max = 1000 });
        const none = try draw(arena, lib, &.{spice}, .{ .cross_max = 0 });
        try std.testing.expect(crossings(&none) <= crossings(&free));
        fewer += @intFromBool(crossings(&none) < crossings(&free));
        for (0..free.netCount()) |n| {
            var a = free.segments(n);
            var b = none.segments(n);
            if (a.next() == null) try std.testing.expect(b.next() == null);
        }
    }
    try std.testing.expect(fewer > 0);
}

test "sketch: a net over the crossing budget keeps its near pins wired, one name a part" {
    // Oracle: how people draw it. Of the nets people join by name in 5,274
    // hand-drawn schematics, 75% keep the pins standing near each other
    // wired and cut only the far connection. With no crossing budget one
    // node of the Sallen-Key filter (three pins) is cut: fewer names than
    // pins, a wire left, and the names still join the whole net. R2's left
    // end is the deck's word here: turned toward the amplifier beside it
    // (sketch.4) its pin stands near the node's other two, the node is one
    // part, and no connection of it is far.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = for (textbook.beyond) |c| {
        if (std.mem.eql(u8, c.name, "sallen_key")) break c.spice;
    } else unreachable;
    const told = try std.mem.concat(arena_state.allocator(), u8, &.{ deck, "\n*@ face r2 a left\n" });
    const p = try draw(arena_state.allocator(), lib, &.{told}, .{ .cross_max = 0 });
    // The cut net: the one that carries names.
    try std.testing.expect(p.labels.len > 0);
    const net = p.labels[0].net;
    var names: usize = 0;
    for (p.labels) |l| names += @intFromBool(l.net == net);
    var pins: usize = 0;
    for (p.dev_name, 0..) |name, d| if (name.len > 0) {
        const from, const to = p.pinRange(d);
        for (p.pin_net[from..to]) |n| pins += @intFromBool(n == net);
    };
    var wires = p.segments(net);
    try std.testing.expectEqual(2, names);
    try std.testing.expect(pins > names);
    try std.testing.expect(wires.next() != null);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: no wire crosses a rail symbol's stub or a supply bar, and no supply stub is longer than two units" {
    // Oracle: how people draw it. In 5,263 hand-drawn schematics 3 of the
    // 16,030 rail stubs of half a unit or less are crossed by a wire, and
    // about 12 wires cross a supply's level run; 97% of 9,149 upright
    // supply runs are no longer than two units: a pin farther from the bar
    // carries a symbol of its own.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var decks: std.ArrayList(struct { []const u8, []const u8 }) = .empty;
    for (golden.decks) |d| try decks.append(arena, .{ d.name, d.spice });
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, .{ c.name, c.spice });
    // A block under a mirror: its supply pin stands four units below the bar.
    try decks.append(arena, .{
        "low_supply_pin",
        \\Mirror over a block whose supply pin stands low
        \\.model nch nmos
        \\.model pch pmos
        \\.subckt amp inp inn out vdd vss
        \\M1 out inp vss vss nch
        \\M2 out inn vdd vdd pch
        \\.ends
        \\M1 a g vdd vdd pch
        \\M2 b g vdd vdd pch
        \\R1 a c 1k
        \\R2 b d 1k
        \\R3 c 0 1k
        \\R4 d 0 1k
        \\X1 c d g vdd 0 amp
        \\
    });
    // A collector node between two supply pins: its wire stays under the bar.
    try decks.append(arena, .{
        "node_under_supply_bar",
        \\Two-transistor amplifier
        \\.model qnpn npn
        \\QB n1 n0 vin 0 qnpn
        \\QD vout n1 0 0 qnpn
        \\RB vcc n0 1k
        \\RC vcc vout 1k
        \\
    });
    const rails = [_]?np.ClassId{ lib.findRole(.power_rail), lib.findRole(.ground_rail) };
    const stub: i32 = @intFromFloat(@ceil((np.config.Layout{}).rail * @as(f32, @floatFromInt(lib.unit))));
    var bad: usize = 0;
    for (decks.items) |d| {
        const p = try draw(arena, lib, &.{d[1]}, .{});
        for (p.dev_name, p.dev_class, 0..) |name, class, dev| {
            if (name.len != 0 or (class != rails[0] and class != rails[1])) continue;
            const net = p.pin_net[p.pinRange(dev)[0]];
            var it = p.segments(net);
            while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (a.x != b.x) {
                    // The supply's bar: crossed by no upright wire.
                    for (0..p.netCount()) |m| {
                        if (m == net or class != rails[0]) continue;
                        var other = p.segments(m);
                        while (other.next()) |q| for (q[0 .. q.len - 1], q[1..]) |u, v| {
                            if (u.x != v.x or u.x <= @min(a.x, b.x) or u.x >= @max(a.x, b.x) or a.y <= @min(u.y, v.y) or a.y >= @max(u.y, v.y)) continue;
                            std.debug.print("{s}: {s} crosses the bar of {s}\n", .{ d[0], p.net_name[m], p.net_name[net] });
                            bad += 1;
                        };
                    }
                    continue;
                }
                const len = @max(a.y, b.y) - @min(a.y, b.y);
                if (class == rails[0] and len > 2 * lib.unit) {
                    std.debug.print("{s}: {s} has a stub of {d}\n", .{ d[0], p.net_name[net], len });
                    bad += 1;
                }
                if (len > stub) continue;
                for (0..p.netCount()) |m| {
                    if (m == net) continue;
                    var other = p.segments(m);
                    while (other.next()) |q| for (q[0 .. q.len - 1], q[1..]) |u, v| {
                        if (u.y != v.y or u.y <= @min(a.y, b.y) or u.y >= @max(a.y, b.y) or a.x <= @min(u.x, v.x) or a.x >= @max(u.x, v.x)) continue;
                        std.debug.print("{s}: {s} crosses a stub of {s}\n", .{ d[0], p.net_name[m], p.net_name[net] });
                        bad += 1;
                    };
                }
            };
        }
    }
    try std.testing.expectEqual(0, bad);
}

test "sketch: a bias gate carries a port symbol, not a written name" {
    // Oracle: how people draw it. Of 4,378 nets named `vb*` or `bias*` in
    // 5,263 hand-drawn schematics, 3,228 carry port symbols and none a
    // written name. A cascode's `vb1` gate: one input port, no label.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Cascode stage
        \\.model nch nmos
        \\M1 x in 0 0 nch
        \\M2 out vb1 x 0 nch
        \\R1 vdd out 10k
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "vb1")) break i;
    } else unreachable;
    var ports: usize = 0;
    for (p.dev_name, p.dev_class, 0..) |n, class, d| {
        ports += @intFromBool(n.len == 0 and class == lib.findRole(.input_port).? and p.pin_net[p.pinRange(d)[0]] == net);
    }
    try std.testing.expectEqual(1, ports);
    for (p.labels) |l| try std.testing.expect(l.net != net);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a bias net's pins standing near each other share one wire and one port" {
    // Oracle: how people draw it. Of the 5,749 pins of bias nets that stand
    // near another pin of their net (wires.17's reach) in 5,263 hand-drawn
    // schematics, 5,400 are wired to it. A drain node a DC source holds (a
    // bias by R2) stays the wire between the transistor and its load.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Common source, its drain held by a source
        \\.model nch nmos
        \\M1 x vb 0 0 nch
        \\RD vdd x 1k
        \\VX x 0 dc 1
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "x")) break i;
    } else unreachable;
    // One port in the circuit; the source drawn apart carries its own.
    var ports: usize = 0;
    const drain = pinOf(&p, "m1", 0);
    for (p.dev_name, p.dev_class, 0..) |n, class, d| {
        if (n.len != 0 or class != lib.findRole(.input_port).? or p.pin_net[p.pinRange(d)[0]] != net) continue;
        ports += @intFromBool(@abs(p.dev_pos[d].x - drain.x) <= 2 * lib.unit);
    }
    try std.testing.expectEqual(1, ports);
    // The drain's wire reaches the resistor's end.
    const load = pinOf(&p, "rd", 1);
    var joined = false;
    var it = p.segments(net);
    while (it.next()) |poly| {
        var a = false;
        var b = false;
        for (poly) |pt| {
            a = a or std.meta.eql(pt, drain);
            b = b or std.meta.eql(pt, load);
        }
        joined = joined or (a and b);
    }
    try std.testing.expect(joined or drain.x == load.x);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: closing up reorders nothing, widens nothing, and narrows the five-transistor OTA" {
    // Oracle: the lattice drawing (`compact` off) of the same deck. Every
    // two named devices keep their order along x and along y, and the
    // devices span no more room either way.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var decks: std.ArrayList(struct { []const u8, []const u8 }) = .empty;
    for (golden.decks) |d| try decks.append(arena, .{ d.name, d.spice });
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, .{ c.name, c.spice });
    var bad: usize = 0;
    for (decks.items) |d| {
        const lattice = try latticePlaces(arena, d[1], &try draw(arena, lib, &.{d[1]}, .{ .compact = false }));
        const close = try latticePlaces(arena, d[1], &try draw(arena, lib, &.{d[1]}, .{ .compact = true }));
        try std.testing.expectEqual(lattice.len, close.len);
        var span: [2][2]u32 = @splat(@splat(0));
        for (lattice, close, 0..) |a, b, i| {
            try std.testing.expectEqualStrings(a.name, b.name);
            for (lattice[i + 1 ..], close[i + 1 ..]) |a2, b2| {
                span[0] = .{ @max(span[0][0], @abs(a.at.x - a2.at.x)), @max(span[0][1], @abs(a.at.y - a2.at.y)) };
                span[1] = .{ @max(span[1][0], @abs(b.at.x - b2.at.x)), @max(span[1][1], @abs(b.at.y - b2.at.y)) };
                if (std.math.order(a.at.x, a2.at.x) == std.math.order(b.at.x, b2.at.x) and
                    std.math.order(a.at.y, a2.at.y) == std.math.order(b.at.y, b2.at.y)) continue;
                std.debug.print("{s}: {s} and {s} change order\n", .{ d[0], a.name, a2.name });
                bad += 1;
            }
        }
        if (span[1][0] > span[0][0] or span[1][1] > span[0][1]) {
            std.debug.print("{s}: closed up {any}, lattice {any}\n", .{ d[0], span[1], span[0] });
            bad += 1;
        }
        if (std.mem.eql(u8, d[0], "ota_5t")) try std.testing.expect(span[1][0] < span[0][0] and span[1][1] < span[0][1]);
    }
    try std.testing.expectEqual(0, bad);
}

test "sketch: `stack` lengthens the wire between stacked devices, `rail` is a ground symbol's stub" {
    // The common-source stage: Rd over M1 on `out`, M1's source on ground.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const deck = for (textbook.all) |c| {
        if (std.mem.eql(u8, c.name, "cs_resistive")) break c.spice;
    } else unreachable;
    // Closed up, the wire from Rd to M1 is `stack` long. On the lattice
    // (`compact` off) a channel row stands between the two device rows, so
    // the wire grows by twice what `stack` does. Oracle: the keys' own
    // definitions (`config.Layout`), read off the drawing's pins.
    for ([_]bool{ true, false }) |compact| {
        var span_at_1: i32 = 0;
        for ([_]f32{ 1, 2.5 }) |k| {
            const p = try draw(arena, lib, &.{deck}, .{ .stack = k, .rail = k, .compact = compact });
            const len: i32 = @intFromFloat(@ceil(k * @as(f32, @floatFromInt(lib.unit))));
            const span = pinOf(&p, "m1", 0).y - pinOf(&p, "rd", 1).y;
            if (compact) try std.testing.expectEqual(len, span);
            if (k == 1) span_at_1 = span else if (!compact) try std.testing.expectEqual(span_at_1 + 2 * (len - lib.unit), span);
            // M1's source, `rail` above the ground symbol under it.
            const src = pinOf(&p, "m1", 2);
            const ground = for (p.dev_name, 0..) |n, d| {
                const at = p.pin_xy[p.pinRange(d)[0]];
                if (n.len == 0 and at.x == src.x and at.y > src.y) break at;
            } else return error.NoGroundSymbol;
            try std.testing.expectEqual(len, ground.y - src.y);
        }
    }
}

test "sketch: a net crossing its own wire is joined there, with a dot" {
    // Found by the fuzz: net c's trunk crossed one of its own pin's lines,
    // which read as two nets crossing.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const p = try draw(arena_state.allocator(), lib, &.{
        \\fuzz
        \\.model nch nmos level=1
        \\.model pch pmos level=1
        \\Vdd vdd 0 1.8
        \\Vin in 0 ac 1
        \\M0 c b in vdd pch
        \\M1 in out c 0 nch
        \\R2 a c 1k
        \\C3 out c 1p
        \\M4 in c in 0 nch
        \\M5 in vdd a 0 nch
    }, .{});
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.dots(gpa, &p, true));
}

test "sketch: a skeleton the drawing cannot use is refused, not drawn" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const deck = golden.decks[0].spice;
    // Two drawn devices on one cell (the deck's sources are drivers, not
    // drawn).
    var a = try staged(arena, lib, deck);
    var drawn: [2]usize = undefined;
    var k: usize = 0;
    for (a.sk.drawn, 0..) |dr, i| if (dr and k < 2) {
        drawn[k] = i;
        k += 1;
    };
    try std.testing.expectEqual(2, k);
    a.x[drawn[1]] = a.x[drawn[0]];
    a.y[drawn[1]] = a.y[drawn[0]];
    try std.testing.expectError(error.CellTaken, np.schematic.sketch.draw(arena, &a.s, &a.nl, .{}, &a.st, &a.sk));
    // A cell off the lattice.
    var b = try staged(arena, lib, deck);
    b.x[drawn[0]] = -1;
    try std.testing.expectError(error.OffLattice, np.schematic.sketch.draw(arena, &b.s, &b.nl, .{}, &b.st, &b.sk));
    // A vertical device whose ends are one net.
    var c = try staged(arena, lib, deck);
    const lower = try arena.dupe(u32, c.sk.lower);
    const d = for (c.sk.form, 0..) |f, i| {
        if (c.sk.drawn[i] and f == .vertical) break i;
    } else unreachable;
    lower[d] = c.sk.upper[d];
    c.sk.lower = lower;
    try std.testing.expectError(error.BadEnds, np.schematic.sketch.draw(arena, &c.s, &c.nl, .{}, &c.st, &c.sk));
}

test "sketch: devices dealt to any cells still draw connected, short-free and dotted" {
    // Full freedom over placement: the canvas keeps every guarantee
    // whatever cells the devices stand on.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var prng = std.Random.DefaultPrng.init(8);
    const r = prng.random();
    var decks: std.ArrayList(struct { []const u8, []const u8 }) = .empty;
    for (golden.decks) |dk| try decks.append(arena, .{ dk.name, dk.spice });
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, .{ c.name, c.spice });
    var bad: usize = 0;
    for (decks.items) |dk| for (0..3) |round| {
        var t = try staged(arena, lib, dk[1]);
        // Deal the drawn devices' cells among them at random.
        var drawn: std.ArrayList(usize) = .empty;
        for (t.sk.drawn, 0..) |dr, i| if (dr) try drawn.append(arena, i);
        const cells = try arena.alloc([2]i32, drawn.items.len);
        for (drawn.items, cells) |i, *cell| cell.* = .{ t.x[i], t.y[i] };
        r.shuffle([2]i32, cells);
        for (drawn.items, cells) |i, cell| {
            t.x[i] = cell[0];
            t.y[i] = cell[1];
        }
        try np.schematic.sketch.draw(arena, &t.s, &t.nl, .{}, &t.st, &t.sk);
        const p = try np.Placed.init(arena, &t.s, &t.nl);
        support.expectConnected(&p, lib) catch {
            std.debug.print("{s} round {d}: a net in pieces\n", .{ dk[0], round });
            bad += 1;
        };
        const shorts = try support.shorts(gpa, &p, true);
        const dotted = try support.dots(gpa, &p, true);
        if (shorts + dotted > 0) {
            std.debug.print("{s} round {d}: {d} shorts, {d} wrong dots\n", .{ dk[0], round, shorts, dotted });
            bad += 1;
        }
    };
    try std.testing.expectEqual(0, bad);
}

test "sketch: three pins are joined with the least wire that leaves each the way it faces" {
    // Oracle: a certificate, and the hand drawings. Three pins cannot be
    // joined with less wire than half the perimeter of the box around
    // them, and that tree branches at their median point: here the tip of
    // the transistor's source. A pin is an end of its wire, which leaves
    // it the way the pin faces (87,922 of 93,770 pins of wired nets that
    // are no rail in 5,263 hand-drawn schematics), so the branch stands
    // off that tip by a quarter unit at the least: that much more wire,
    // and no more.
    // The block is held right of the stack (`order`), its pin toward the
    // junction: facing away, no wire reaches that length.
    // The junction's net is on the block's lower input: its two inputs
    // stand half a unit either side of its middle (library.8), so the
    // upper one's row is the row of the follower's drain, a pin of another
    // net, and no pin on it is level with the junction.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Follower
        \\.model nch nmos
        \\.subckt amp vdd vss vip vin vout
        \\R1 vip vout 1k
        \\R2 vin vout 1k
        \\.ends
        \\CH x vss 1p
        \\M2 vdd net0 x vss nch
        \\X1 vdd vss x vin net0 amp
        \\*@ order m2 x1
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const pins = [_]np.Pt{ pinOf(&p, "ch", 0), pinOf(&p, "m2", 2), pinOf(&p, "x1", 2) };
    var lo = pins[0];
    var hi = pins[0];
    for (pins) |at| {
        lo = .{ .x = @min(lo.x, at.x), .y = @min(lo.y, at.y) };
        hi = .{ .x = @max(hi.x, at.x), .y = @max(hi.y, at.y) };
    }
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "x")) break i;
    } else unreachable;
    var wire: i32 = 0;
    var it = p.segments(net);
    while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
        wire += @intCast(@abs(b.x - a.x) + @abs(b.y - a.y));
    };
    try std.testing.expectEqual(hi.x - lo.x + hi.y - lo.y + @divExact(lib.unit, 4), wire);
    try std.testing.expectEqual(0, pinsOffEnd(&p, lib, net));
    try support.expectConnected(&p, lib);
}

test "sketch: a wire leaves each pin the way it faces and branches off the pins" {
    // Oracle: the hand drawings. A pin is an end of its wire, which leaves
    // it the way the pin faces, in 87,922 of 93,770 pins of wired nets that
    // are no rail (5,263 schematics); the engine drew 66,857 of 84,247 so.
    // An inverter's output joins two drains facing each other and a
    // resistor, its input two gates and two resistors: the output's trunk
    // ran through the lower drain's tip, the input's along the gates' tips.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Inverter
        \\.model nch nmos
        \\.model pch pmos
        \\M1 vout net0 vss vss nch
        \\M2 vout net0 vdd vdd pch
        \\R1 vin net0 1k
        \\R2 net0 vout 1k
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    for ([_][]const u8{ "vout", "net0" }) |name| {
        const net = for (p.net_name, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) break i;
        } else unreachable;
        try std.testing.expectEqual(0, pinsOffEnd(&p, lib, net));
    }
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a lone drain comes straight down to the row of the gate it drives" {
    // Oracle: a certificate. Two pins on neither one row nor one column
    // need a bend, and one is enough: down the drain's column, along the
    // gate's row. A trunk on a row of its own took three.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Stage
        \\.model nch nmos
        \\.model pch pmos
        \\M1 x in vdd vdd pch
        \\M2 out x 0 0 nch
        \\M3 out vb vdd vdd pch
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const drain = pinOf(&p, "m1", 0);
    const gate = pinOf(&p, "m2", 1);
    try std.testing.expect(drain.x != gate.x and drain.y != gate.y);
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "x")) break i;
    } else unreachable;
    try std.testing.expectEqual(1, bends(&p, net));
    try support.expectConnected(&p, lib);
}

test "sketch: an input's pins standing near each other share one wire and one port" {
    // Oracle: how people draw it. Of the 3,070 pins of input nets that
    // stand near another pin of their net (wires.17's reach) in 5,263
    // hand-drawn schematics, 2,689 are wired to it; the inverter's two
    // gates on `in` are the plainest case.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Inverter
        \\.model nch nmos
        \\.model pch pmos
        \\M1 out in vdd vdd pch
        \\M2 out in 0 0 nch
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "in")) break i;
    } else unreachable;
    var ports: usize = 0;
    for (p.dev_name, 0..) |n, d| ports += @intFromBool(n.len == 0 and p.pin_net[p.pinRange(d)[0]] == net);
    try std.testing.expectEqual(1, ports);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: an input's pins fall into parts: those standing near share a wire and a port, one far off has its own" {
    // Oracle: how people draw it. An input's pins fall into parts as a net
    // joined by name does (a pin within wires.17's reach of another joins
    // its part): 914 of 1,319 input nets and 1,818 of 2,208 bias nets of
    // two pins or more are drawn in exactly those parts in 5,263
    // hand-drawn schematics, and 8,089 of the 8,819 pins the rule wires
    // are wired. One cut on the box round all the pins gave every pin of
    // this net a port: people draw that in 254 of the 1,319.
    // The first stage's two gates stand in one column; the last stage's
    // gate on the same input stands four stages away.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Chain
        \\.model nch nmos
        \\.model pch pmos
        \\M1 a in vdd vdd pch
        \\M2 a in 0 0 nch
        \\M3 b a vdd vdd pch
        \\M4 b a 0 0 nch
        \\M5 c b vdd vdd pch
        \\M6 c b 0 0 nch
        \\M7 d c vdd vdd pch
        \\M8 d c 0 0 nch
        \\M9 out d x 0 nch
        \\M10 x in 0 0 nch
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "in")) break i;
    } else unreachable;
    // The places the count is made from: the two gates near, the third far.
    const g1 = pinOf(&p, "m1", 1);
    const g2 = pinOf(&p, "m2", 1);
    const g10 = pinOf(&p, "m10", 1);
    try std.testing.expect(@abs(g1.x - g2.x) + @abs(g1.y - g2.y) <= 3 * lib.unit);
    try std.testing.expect(@abs(g10.x - g1.x) > 3 * lib.unit and @abs(g10.x - g2.x) > 3 * lib.unit);
    var ports: usize = 0;
    for (p.dev_name, 0..) |n, d| ports += @intFromBool(n.len == 0 and p.pin_net[p.pinRange(d)[0]] == net);
    try std.testing.expectEqual(2, ports);
    // The near gates are on one wire: it leaves each, and no port stands
    // on either gate's own stub.
    try std.testing.expectEqual(0, pinsOffEnd(&p, lib, net));
    var wire: i32 = 0;
    var it = p.segments(net);
    while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
        wire += @intCast(@abs(b.x - a.x) + @abs(b.y - a.y));
    };
    try std.testing.expect(wire >= @abs(g1.y - g2.y));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a tall block stands beside the stack it joins, not between its rows" {
    // Oracle: the keys' own definitions (`config.Layout`). Closed up, the
    // wire from the junction on the block's pin row down to the load
    // capacitor is `tap` long, whatever the block's height: the block is
    // in another column (people stand blocks side by side in 82% of 5,274
    // hand-drawn schematics). A row of its own for the block put the
    // capacitor under the block's foot.
    // The block is held right of the stack (`order`), where its pin row
    // is the junction's: the amplifier's fed-back input is drawn under the
    // other (`left`), as a follower's is, where a generated box puts the
    // inverting input on top.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Follower
        \\.model nch nmos
        \\.subckt amp vdd vss vip vin vout
        \\*@ left vip vin
        \\R1 vip vout 1k
        \\R2 vin vout 1k
        \\.ends
        \\CH vout vss 1p
        \\M2 vdd net0 vout vss nch
        \\X1 vdd vss vin vout net0 amp
        \\*@ order m2 x1
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const tap: i32 = @intFromFloat(@ceil((np.config.Layout{}).tap * @as(f32, @floatFromInt(lib.unit))));
    try std.testing.expectEqual(tap, pinOf(&p, "ch", 0).y - pinOf(&p, "x1", 3).y);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a mirror's facing gates are joined by one straight gate line" {
    // Oracle: the book's figure (Razavi Fig. 5.26(b), the golden `ota_5t`):
    // the mirror's gate line runs straight from M3's gate to M4's, and the
    // diode connection taps it. Before, each gate dropped to the drain row.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = for (textbook.all) |c| {
        if (std.mem.eql(u8, c.name, "ota_5t")) break c.spice;
    } else unreachable;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const g3 = pinOf(&p, "m3", 1);
    const g4 = pinOf(&p, "m4", 1);
    try std.testing.expectEqual(g3.y, g4.y);
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "x")) break i;
    } else unreachable;
    // The wire of `x` along the gates' row, between the gates.
    var covered: i32 = 0;
    var it = p.segments(net);
    while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
        if (a.y != g3.y or b.y != g3.y) continue;
        covered += @max(0, @min(@max(a.x, b.x), @max(g3.x, g4.x)) - @max(@min(a.x, b.x), @min(g3.x, g4.x)));
    };
    try std.testing.expectEqual(@as(i32, @intCast(@abs(g4.x - g3.x))), covered);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a bias gate line carries a port hanging from its middle, not a written name" {
    // Oracle: the hand drawings. Of 264 bias nets of two facing gates in
    // the 5,263 reference drawings, 197 carry a port symbol; the engine
    // wrote the net's name at the middle of all 529 of its own.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const p = try draw(arena_state.allocator(), lib, &.{
        \\Two current sources on one bias
        \\.model pch pmos
        \\M1 a vb vdd vdd pch
        \\M2 b vb vdd vdd pch
        \\R1 a 0 1k
        \\R2 b 0 1k
        \\
    }, .{});
    const g1 = pinOf(&p, "m1", 1);
    const g2 = pinOf(&p, "m2", 1);
    try std.testing.expectEqual(g1.y, g2.y);
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "vb")) break i;
    } else unreachable;
    for (p.labels) |lb| try std.testing.expect(lb.net != net);
    var hanging: usize = 0;
    for (p.dev_name, p.dev_class, 0..) |n, class, d| {
        if (n.len != 0 or class != lib.findRole(.input_port).? or p.pin_net[p.pinRange(d)[0]] != net) continue;
        const at = p.pin_xy[p.pinRange(d)[0]];
        hanging += @intFromBool(at.x == @divFloor(g1.x + g2.x, 2) and at.y != g1.y);
    }
    try std.testing.expectEqual(1, hanging);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: two blocks stacked in one column stand clear, no pin of one on a pin of the other" {
    // Oracle: the geometry itself. A block with its pins on one side is
    // taller than its pins reach up or down (nothing): the lattice gave its
    // row no height, the two bodies touched, `xl1`'s last pin on `xl2`'s
    // first, and the router's path to the one ended on the other's net.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Two blocks in one column
        \\.subckt tank n1 n2 n3
        \\*@ left n1 n2 n3
        \\L1 n1 n2 1n
        \\L2 n2 n3 1n
        \\.ends
        \\.model nch nmos level=1
        \\VDD vdd 0 1.8
        \\XL1 p4 m4 vdd tank
        \\XL2 p3 m3 vdd tank
        \\M1 p4 g1 0 0 nch
        \\M2 p3 g2 0 0 nch
        \\M3 m4 g3 0 0 nch
        \\M4 m3 g4 0 0 nch
        \\*@ cell xl1 2 0
        \\*@ cell xl2 2 2
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    for (0..3) |i| for (0..3) |j| {
        const a = pinOf(&p, "xl1", @intCast(i));
        const b = pinOf(&p, "xl2", @intCast(j));
        try std.testing.expect(a.x != b.x or a.y != b.y);
    };
}

test "sketch: a net between two shelves is joined by name, a shelf's own nets by wire" {
    // Oracle: the wires themselves. Twelve stages in a chain wrap, at eight
    // columns a row, into two shelves of six: the one net that passes from
    // the sixth stage to the seventh carries names and no wire runs from
    // shelf to shelf; every other stage's net is a wire with no name;
    // nothing crosses.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const p = try draw(arena_state.allocator(), lib, &.{support.wide_chain}, .{ .shelf = 8 });
    var named: usize = 0;
    for (p.net_name, 0..) |name, net| {
        var names: usize = 0;
        for (p.labels) |l| names += @intFromBool(l.net == net);
        // A supply bar is a named rail (people 1,255 of 1,370): its name
        // joins nothing.
        if (names == 0 or std.mem.eql(u8, name, "vdd")) continue;
        named += 1;
        try std.testing.expectEqualStrings("n6", name);
    }
    try std.testing.expectEqual(1, named);
    try std.testing.expectEqual(0, crossings(&p));
    // The seventh stage stands under the first six.
    try std.testing.expect(pinOf(&p, "m7", 0).y > pinOf(&p, "m6", 2).y);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a trunk is the cheapest track that fits, not the first" {
    // Oracle: no wire over three pins is shorter than half the perimeter of
    // the box around them (the rectilinear Steiner tree of three points),
    // and the hand drawings: a wire branches off its pins (a pin is an end
    // of its wire in 87,922 of 93,770 pins of wired nets that are no rail,
    // 5,263 schematics). A stage's base net joins a coupling capacitor, a
    // feedback resistor and the base: the two parts' pins face each other
    // on one row, the base stands off it past the resistor, so that tree
    // branches on the resistor's pin. The wire branches at the middle of
    // the line between the two parts instead (a gate line, trunk.7), and
    // is longer by half that line and no more. The first track that fit
    // (the tap row under both parts) was longer still, with five corners.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\stage
        \\.model qnpn npn
        \\C1 vin b 1p
        \\C2 c vo 1p
        \\I1 vcc c 0.5m
        \\Q1 c b e 0 qnpn
        \\R1 c b 200k
        \\R2 e 0 200
        \\R3 vo 0 20k
        \\Vi vin 0 1
        \\*@ driver vi inline
        \\*@ bridge c1 r1 c2
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const net = for (p.net_name, 0..) |name, n| {
        if (std.mem.eql(u8, name, "b")) break n;
    } else unreachable;
    // The places the count is made from: the parts' pins level and facing,
    // the base off their row.
    const c1 = pinOf(&p, "c1", 1);
    const r1 = pinOf(&p, "r1", 1);
    try std.testing.expectEqual(c1.y, r1.y);
    try std.testing.expect(c1.x < r1.x and pinOf(&p, "c1", 0).x < c1.x and pinOf(&p, "r1", 0).x > r1.x);
    const base = pinOf(&p, "q1", 1);
    try std.testing.expect(base.y != c1.y and base.x > r1.x);
    var length: i64 = 0;
    var it = p.segments(net);
    while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
        length += @abs(a.x - b.x) + @abs(a.y - b.y);
    };
    try std.testing.expectEqual(@abs(base.x - c1.x) + @abs(base.y - c1.y) + @abs(@divExact(r1.x - c1.x, 2)), length);
    try std.testing.expectEqual(0, pinsOffEnd(&p, lib, net));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a net's wire takes the track that crosses no other net's" {
    // Oracle: the hand drawings. A net's wire crosses no other net's in
    // 33,360 of 37,990 wired nets that are no rail (5,263 schematics); the
    // person drew this follower (ag-46) with no crossing. The input's wire
    // was drawn before the output's, under it, and the output's trunk
    // crossed it; drawn after, with crossings in its cost, the input's
    // wire goes round.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\Follower
        \\.model nch nmos
        \\M1 vdd vin vout vss nch
        \\RF vin vout 1k
        \\RS vout vss 1k
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    try std.testing.expectEqual(0, crossings(&p));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a part to ground with nothing over it hangs under the gate it joins" {
    // Oracle: the hand-drawn figure. A gate's resistor to ground is drawn
    // under the gate's net, its upper pin below the gate (72% of 1,642 such
    // pins in the 5,263 reference drawings), so the wire comes down into
    // it. Longest path from the top alone stood it on the top row, its pin
    // over the gate, the wire four corners round.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\hang
        \\.model nch nmos level=1
        \\.model pch pmos level=1
        \\VDD vdd 0 1.8
        \\M2 out out vdd vdd pch
        \\M1 out g 0 0 nch
        \\R1 g 0 100k
        \\C1 in g 1p
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    try std.testing.expect(pinOf(&p, "r1", 0).y > pinOf(&p, "m1", 1).y);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a circuit of parts with no ground stands on its reference as on ground, the reference a plain wire" {
    // Oracle: the grounded drawing of the same circuit. A ladder drawn with
    // its shunts on net 0, and again with that net renamed `com` so the
    // deck has no ground, has every device in the same place: the engine
    // finds the net the ladder stands on. And `com` is drawn as people draw
    // a reference that is no ground (the bottom wire of 172 of 191 such
    // pieces in the 5,263 reference drawings): one wire, no rail symbol,
    // no name. `v-` and `v+` are rails by name.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const grounded = "ladder\nR1 a b 1k\nC1 b 0 1p\nR2 b c 1k\nC2 c 0 1p\nR3 c d 1k\nC3 d 0 1p\n";
    const floating = "ladder\nR1 a b 1k\nC1 b com 1p\nR2 b c 1k\nC2 c com 1p\nR3 c d 1k\nC3 d com 1p\n";
    const on_ground = try draw(arena, lib, &.{grounded}, .{});
    const p = try draw(arena, lib, &.{floating}, .{});
    const want = try placesByName(arena, &on_ground);
    const got = try placesByName(arena, &p);
    try std.testing.expectEqual(want.len, got.len);
    for (want, got) |w, g| {
        try std.testing.expectEqualStrings(w.name, g.name);
        try std.testing.expectEqual(w.at, g.at);
    }
    const com = for (p.net_name, 0..) |name, n| {
        if (std.mem.eql(u8, name, "com")) break n;
    } else unreachable;
    for (p.dev_name, 0..) |n, d| try std.testing.expect(n.len > 0 or p.pin_net[p.pinRange(d)[0]] != com);
    for (p.labels) |l| try std.testing.expect(l.net != com);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));

    var nl = try np.netlist.parse(arena, &.{"rails\nR1 v+ a 1k\nR2 a v- 1k\n"}, null);
    const roles = try np.guessRoles(arena, &nl);
    try std.testing.expectEqual(np.Role.supply, roles[nl.net("v+").?.index()]);
    try std.testing.expectEqual(np.Role.sink, roles[nl.net("v-").?.index()]);
}

test "sketch: no wire ends on nothing: two pins' ways to a trunk do not run on together past where they meet" {
    // Oracle: the wire itself. Every end of a net's wire is on a pin, on a
    // name, or on another piece of the wire. A gate and its resistor met at
    // one column and both ran on a quarter unit up to a trunk of no length:
    // a spur, which the trunk's cost took for a free T.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = "gate\n.model nch nmos\nM1 vout net0 vin 0 nch\nRD vdd vout 1k\nRG net0 vb 1k\n";
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    for (0..p.netCount()) |n| try std.testing.expectEqual(0, looseEnds(&p, n));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a block stands in the signal's order by its ports' names: beside the gate it drives, on its left; with none, right of what it reads" {
    // Oracle: the hand drawings. Of the 320 blocks whose output drives a
    // gate in the 5,263 reference drawings (ports named as an input and an
    // output), 266 stand left of every such gate; of the 590 that drive
    // none, 522 stand right of every upright device on their inputs' nets.
    // `x1` reads `b`, the third stage's drain, and drives `o`, the second
    // stage's gate; `x2` reads the last stage and drives a load. Each
    // stood between the nearest columns of its first and last net that is
    // no rail: `x1` right of the gate it drives, under another stage.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck =
        \\A block between two stages
        \\.model nch nmos level=1
        \\.subckt amp vdd vss inp inn out
        \\R1 inp out 1k
        \\.ends amp
        \\VDD vdd 0 1.8
        \\M1 a g1 0 0 nch
        \\R1 vdd a 1k
        \\M3 b g3 0 0 nch
        \\R3 vdd b 1k
        \\X1 vdd 0 b fb o amp
        \\M2 z o 0 0 nch
        \\R2 vdd z 1k
        \\M4 y z 0 0 nch
        \\R4 vdd y 1k
        \\X2 vdd 0 y fb2 q amp
        \\C9 q 0 1p
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    var x: [6]i32 = undefined;
    for ([_][]const u8{ "x1", "m2", "x2", "m4", "m1", "m3" }, &x) |name, *at| {
        at.* = for (p.dev_name, p.dev_pos) |n, pos| {
            if (std.mem.eql(u8, n, name)) break pos.x;
        } else unreachable;
    }
    // Left of the gate it drives, no stage between the two.
    try std.testing.expect(x[0] < x[1]);
    for ([_]i32{ x[3], x[4], x[5] }) |stage| try std.testing.expect(stage < x[0] or stage > x[1]);
    // Right of the stage it reads.
    try std.testing.expect(x[2] > x[3]);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: two flat parts in series face each other" {
    // Oracle: the places alone. A coupling capacitor and a gate resistor in
    // series through a net that joins just the two stand on one row; each
    // one's pin on that net lies between the two parts' centres, so one
    // straight wire joins them: each is the nearest device on the other's
    // net (people: the end on the nearest device's net faces it in 4,414
    // of 4,471 flat two-pin parts, 5,263 hand-drawn schematics). Turned by
    // the mean column of its far net, each faced away, and the wire went
    // round both with four corners.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = "Input chain\n.model nch nmos level=1\nVDD vdd 0 1.8\nM1 a g 0 0 nch\nR1 vdd a 10k\nM2 out a 0 0 nch\nR2 vdd out 10k\n" ++
        "C1 in x 1p\nR3 x g 1k\n";
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const c1 = pinOf(&p, "c1", 1);
    const r3 = pinOf(&p, "r3", 0);
    const c1_mid = @divFloor(pinOf(&p, "c1", 0).x + c1.x, 2);
    const r3_mid = @divFloor(pinOf(&p, "r3", 1).x + r3.x, 2);
    try std.testing.expectEqual(c1.y, r3.y);
    for ([_]i32{ c1.x, r3.x }) |x| try std.testing.expect(x > @min(c1_mid, r3_mid) and x < @max(c1_mid, r3_mid));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a flat part's end faces the nearest device on its net" {
    // Oracle: the places alone, and the hand drawings: of the devices on a
    // flat part's two nets that stand beside it, the nearest has its net's
    // end facing it (people: 4,414 of 4,471 flat two-pin parts, 98.7%, in
    // 5,263 hand-drawn schematics). The inductor's net b holds M5 and M2,
    // a column to its left, and M6, further to its right: its end on b
    // faces left and its output goes out on the right. Turned by the mean
    // column of b's devices, it faced M6 and its port stood inside.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = "Nearest\n.model nch nmos level=1\n.model pch pmos level=1\nVDD vdd 0 1.8\nM1 y y vdd vdd pch\nI1 y 0 10u\n" ++
        "M5 b y vdd vdd pch\nM2 b x 0 0 nch\nM6 b vb6 vdd vdd pch\nL2 b out 1n\n";
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const on_b = pinOf(&p, "l2", 0);
    const on_out = pinOf(&p, "l2", 1);
    const mid = @divFloor(on_b.x + on_out.x, 2);
    // The devices on b, by how far along x plus along y each stands.
    var nearest: ?np.Pt = null;
    var least: u32 = std.math.maxInt(u32);
    for ([_][]const u8{ "m5", "m2", "m6" }) |name| {
        const at = for (p.dev_name, p.dev_pos) |n, pos| {
            if (std.mem.eql(u8, n, name)) break pos;
        } else unreachable;
        const far = @abs(at.x - mid) + @abs(at.y - on_b.y);
        if (far < least) {
            least = far;
            nearest = at;
        }
    }
    try std.testing.expect(nearest.?.x != mid);
    try std.testing.expectEqual(nearest.?.x < mid, on_b.x < on_out.x);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a flat switch faces the nearest device on its path's nets, as a two-pin part does" {
    // Oracle: the places alone, and the hand drawings: a flat device with
    // a path that is no two-pin card (a pass transistor, a switch) has its
    // end on the nearest device's net facing that device in 1,684 of 1,719
    // (98.0%, 5,263 hand-drawn schematics), as a two-pin part has. S2's
    // second path pin is on x with C1 and S1, both to its left, and its
    // first on a port: x faces left. Lying as its class is drawn, its
    // first pin stood left and x's wire went round the switch.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = "Switched capacitor\n.model sw sw\nC1 x n0 1p\nS1 out x phi2 0 sw\nS2 cm x phi1 0 sw\n" ++
        "S3 n0 in phi2 0 sw\nS4 n0 bias phi1 0 sw\n";
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const on_cm = pinOf(&p, "s2", 0);
    const on_x = pinOf(&p, "s2", 1);
    try std.testing.expectEqual(on_cm.y, on_x.y);
    const mid = @divFloor(on_cm.x + on_x.x, 2);
    for ([_][]const u8{ "c1", "s1" }) |name| {
        const at = for (p.dev_name, p.dev_pos) |n, pos| {
            if (std.mem.eql(u8, n, name)) break pos;
        } else unreachable;
        try std.testing.expect(at.x < mid);
    }
    try std.testing.expect(on_x.x < on_cm.x);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: the layout's `shelf` key sets how many columns a row holds; a deck's line says otherwise" {
    // Oracle: the key's own definition (`config.Layout.shelf`). Twelve
    // stages in a chain stand in rows of at most `shelf` columns: three
    // rows of four at 4, one row at 0, and two rows of six where the deck
    // itself says `*@ shelf 6`. The key is read from a `lint.zon`. By
    // default the twelve stand in one row: of the 686 reference circuits
    // eight columns a row wrapped, people draw 504 in one band of rows
    // (5,263 hand-drawn schematics).
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cfg = try np.config.Config.parse(arena, ".{ .layout = .{ .shelf = 4 } }", null);
    try std.testing.expectEqual(4, cfg.layout.shelf);
    for ([_]struct { deck: []const u8, layout: np.config.Layout, rows: usize, widest: usize }{
        .{ .deck = support.wide_chain, .layout = cfg.layout, .rows = 3, .widest = 4 },
        .{ .deck = support.wide_chain, .layout = .{ .shelf = 0 }, .rows = 1, .widest = 12 },
        .{ .deck = support.wide_chain, .layout = .{}, .rows = 1, .widest = 12 },
        .{ .deck = support.wide_chain ++ "*@ shelf 6\n", .layout = cfg.layout, .rows = 2, .widest = 6 },
    }) |case| {
        const p = try draw(arena, lib, &.{case.deck}, case.layout);
        // The transistors' rows, and how many stand in each.
        var rows: std.AutoHashMapUnmanaged(i32, usize) = .empty;
        for (p.dev_name, p.dev_pos) |name, at| {
            if (name.len < 2 or name[0] != 'm') continue;
            const row = try rows.getOrPutValue(arena, at.y, 0);
            row.value_ptr.* += 1;
        }
        try std.testing.expectEqual(case.rows, rows.count());
        var it = rows.valueIterator();
        while (it.next()) |count| try std.testing.expect(count.* <= case.widest);
        try support.expectConnected(&p, lib);
    }
}

test "sketch: a gate alone on the junction of a column stands level with it; not beside its own kind on its own rail" {
    // Oracle: the pins' places alone, and the hand-drawn figure (69% of
    // 1,443 such gates in the 5,263 reference drawings). A transistor
    // whose gate hangs on a divider's midpoint stands in a row between the
    // two resistors: its gate pin lies between their pins on that net, and
    // the net's wire turns no corner. It stood beside the lower resistor,
    // the wire a Z of two corners. Two common-source stages on ground stay
    // level, as people keep them (65% of 184).
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const p = try draw(arena, lib, &.{"Divider\n.model nch nmos level=1\nVDD vdd 0 1.8\nR1 vdd mid 10k\nR2 mid 0 10k\nM1 out mid 0 0 nch\nR3 vdd out 10k\n"}, .{});
    const gate = pinOf(&p, "m1", 1);
    try std.testing.expect(gate.y > pinOf(&p, "r1", 1).y and gate.y < pinOf(&p, "r2", 0).y);
    const mid = for (p.net_name, 0..) |name, n| {
        if (std.mem.eql(u8, name, "mid")) break n;
    } else unreachable;
    try std.testing.expectEqual(0, bends(&p, mid));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
    const chain = try draw(arena, lib, &.{"Two stages\n.model nch nmos level=1\nVDD vdd 0 1.8\nM1 a in 0 0 nch\nR1 vdd a 10k\nM2 out a 0 0 nch\nR2 vdd out 10k\n"}, .{});
    try std.testing.expectEqual(pinOf(&chain, "m1", 2).y, pinOf(&chain, "m2", 2).y);
}

test "sketch: a shelf with rows of the whole left empty in it is still one shelf" {
    // Oracle: the wires themselves, as in the shelves' own test. Eight
    // stages wrap into two shelves of four; the first stage's load is three
    // resistors deep, so every stage's transistor stands three rows under
    // its load. In the second shelf the rows between are empty: its stages'
    // nets are still wires, and only `n4`, which passes from one shelf to
    // the other, carries names. The empty rows read as a shelf's end, and
    // `n5` to `n8` were cut.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = "Deep first stage\n*@ shelf 4\n.model nch nmos level=1\nVDD vdd 0 1.8\nM1 n1 in 0 0 nch\nRA vdd a 1k\nRB a b 1k\nRC b n1 1k\n" ++
        "M2 n2 n1 0 0 nch\nR2 vdd n2 1k\nM3 n3 n2 0 0 nch\nR3 vdd n3 1k\nM4 n4 n3 0 0 nch\nR4 vdd n4 1k\n" ++
        "M5 n5 n4 0 0 nch\nR5 vdd n5 1k\nM6 n6 n5 0 0 nch\nR6 vdd n6 1k\nM7 n7 n6 0 0 nch\nR7 vdd n7 1k\nM8 n8 n7 0 0 nch\nR8 vdd n8 1k\n";
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    // The supply's bar is a named rail (people 1,255 of 1,370): its name
    // joins nothing.
    for (p.labels) |l| if (!std.mem.eql(u8, p.net_name[l.net], "vdd")) try std.testing.expectEqualStrings("n4", p.net_name[l.net]);
    try std.testing.expect(p.labels.len > 0);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a chain of parts into a gate stands on the gate's row, the part on the gate's net next to the gate" {
    // Oracle: the pins' places alone. An input reaches a gate through a
    // capacitor and a resistor in series; no channel ends on the gate's
    // net, so the chain takes the gate's row, and the resistor, which is on
    // that net, stands next to the gate: its pin level with the gate and
    // between the gate and the capacitor, the wire straight. The chain
    // stood over the top row, and it started from the input's end
    // whichever end the column was on.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = "Input chain\n.model nch nmos level=1\nVDD vdd 0 1.8\nM1 a g 0 0 nch\nR1 vdd a 10k\nM2 out a 0 0 nch\nR2 vdd out 10k\n" ++
        "C1 in x 1p\nR3 x g 1k\n";
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const gate = pinOf(&p, "m1", 1);
    const r3 = pinOf(&p, "r3", 1);
    const c1 = pinOf(&p, "c1", 1);
    try std.testing.expectEqual(gate.y, r3.y);
    try std.testing.expect(@abs(gate.x - r3.x) < @abs(gate.x - c1.x));
    const g = for (p.net_name, 0..) |name, n| {
        if (std.mem.eql(u8, name, "g")) break n;
    } else unreachable;
    try std.testing.expectEqual(0, bends(&p, g));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a pair's halves close over the tail between them" {
    // Oracle: the hand drawings. Over an axis column on another row, the
    // two inner columns of a mirrored core stand 2.5 units apart at the
    // median of 246 such cores in the 5,263 reference drawings. The
    // five-transistor OTA's pair stands so over its tail; held `series`
    // from the tail's symbol on either side, it stood four units apart.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = for (textbook.all) |c| {
        if (std.mem.eql(u8, c.name, "ota_5t")) break c.spice;
    } else unreachable;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const m1 = pinOf(&p, "m1", 0);
    const m2 = pinOf(&p, "m2", 0);
    try std.testing.expectEqual(m1.y, m2.y);
    try std.testing.expect(2 * @abs(m2.x - m1.x) <= 5 * lib.unit);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a flat part that cannot be wired straight stands upright; a line of the deck keeps it flat" {
    // Oracle: the hand drawings and the pins' places. A stage's feedback
    // resistor joins the collector's node and the base: no row holds a pin
    // of both, so flat it is wired round corners; people stand such a part
    // upright (62% of those between a channel's node and a gate in the
    // 5,263 reference drawings). Upright, its two pins share a column, and
    // `*@ bridge r1` lays it flat again.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const deck = "Stage\n.model qnpn npn\nI1 vcc c 0.5m\nQ1 c b e 0 qnpn\nR1 c b 200k\nR2 e 0 200\n";
    const p = try draw(arena, lib, &.{deck}, .{});
    try std.testing.expectEqual(pinOf(&p, "r1", 0).x, pinOf(&p, "r1", 1).x);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
    const flat = try draw(arena, lib, &.{deck ++ "*@ bridge r1\n"}, .{});
    try std.testing.expectEqual(pinOf(&flat, "r1", 0).y, pinOf(&flat, "r1", 1).y);
}

test "sketch: an op-amp circuit is drawn along its signal: inverting input on top, feedback over the block, the input part level with its pin" {
    // Oracle: the hand drawings, as relations between pins. In the 199
    // op-amp circuits of the 5,263 reference drawings the inverting input
    // is on top (76%), a part from the output to an input stands straight
    // over or under its block (82%) on its pin's side (96%), the input's
    // series part lies level with its pin, and a load to ground stands
    // upright right of the block (100%). An inverting amplifier drawn so
    // crosses no wire. On the lattice the block and its parts shared a row
    // and the feedback went round.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const p = try draw(arena, lib, &.{support.inverting_amp}, .{});
    // The block's pins, in port order: vdd, vss, vip, vin, vout.
    const plus = pinOf(&p, "x1", 2);
    const minus = pinOf(&p, "x1", 3);
    const out = pinOf(&p, "x1", 4);
    try std.testing.expect(minus.y < plus.y);
    try std.testing.expect(minus.x < out.x);
    // The input resistor: level with the inverting pin, left of it.
    try std.testing.expectEqual(minus.y, pinOf(&p, "r1", 0).y);
    try std.testing.expectEqual(minus.y, pinOf(&p, "r1", 1).y);
    try std.testing.expect(pinOf(&p, "r1", 0).x < minus.x and pinOf(&p, "r1", 1).x < minus.x);
    // The feedback resistor: flat, over the block, between its pins.
    const rf = [2]np.Pt{ pinOf(&p, "rf", 0), pinOf(&p, "rf", 1) };
    try std.testing.expectEqual(rf[0].y, rf[1].y);
    try std.testing.expect(rf[0].y < minus.y);
    try std.testing.expect(@divFloor(rf[0].x + rf[1].x, 2) > minus.x and @divFloor(rf[0].x + rf[1].x, 2) < out.x);
    // The load: upright, right of the block, under the output.
    const rl = [2]np.Pt{ pinOf(&p, "rl", 0), pinOf(&p, "rl", 1) };
    try std.testing.expectEqual(rl[0].x, rl[1].x);
    try std.testing.expect(rl[0].x > out.x and @max(rl[0].y, rl[1].y) > out.y);
    try std.testing.expectEqual(0, crossings(&p));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
    // A line of the deck that places a device takes the placement back.
    const steered = try draw(arena, lib, &.{support.inverting_amp ++ "*@ bridge rl\n"}, .{});
    try std.testing.expectEqual(pinOf(&steered, "rl", 0).y, pinOf(&steered, "rl", 1).y);
}

test "sketch: a supply bar is a named rail running past its outer pins; rail_past = false, a bar with its symbol ending on them" {
    // Oracle: the hand drawings. Of 1,370 named supply bars (no symbol on
    // them) in the 5,263 reference drawings, 1,255 run past both outer
    // pins, the name at the right end in 1,252 of 1,256; of 1,140 bars
    // carrying the symbol, 1,083 end on their outer pins. No person draws
    // the symbol on a bar that runs past (0 of 730): the engine did.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const deck =
        \\Two dividers
        \\Vdd vdd 0 1
        \\R1 vdd a 1k
        \\R2 a 0 1k
        \\R3 vdd b 1k
        \\R4 b 0 1k
        \\
    ;
    const extent = struct {
        fn f(p: *const np.Placed, n: usize) [2]i32 {
            var lo: i32 = std.math.maxInt(i32);
            var hi: i32 = std.math.minInt(i32);
            // The bar: the net's level pieces (the source drawn apart has
            // a stub of its own, upright).
            var it = p.segments(n);
            while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (a.y != b.y) continue;
                lo = @min(lo, @min(a.x, b.x));
                hi = @max(hi, @max(a.x, b.x));
            };
            return .{ lo, hi };
        }
    }.f;
    const netOf = struct {
        fn f(p: *const np.Placed, name: []const u8) usize {
            for (p.net_name, 0..) |n, i| if (std.mem.eql(u8, n, name)) return i;
            unreachable;
        }
    }.f;
    const rail: i32 = @intFromFloat(@ceil((np.config.Layout{}).rail * @as(f32, @floatFromInt(lib.unit))));
    const p = try draw(arena, lib, &.{deck}, .{});
    const vdd = netOf(&p, "vdd");
    const x1 = pinOf(&p, "r1", 0).x;
    const x3 = pinOf(&p, "r3", 0).x;
    try std.testing.expectEqual([2]i32{ @min(x1, x3) - rail, @max(x1, x3) + rail }, extent(&p, vdd));
    try std.testing.expectEqual(0, bends(&p, vdd));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
    try std.testing.expectEqual(0, try support.dots(gpa, &p, true));
    const ended = try draw(arena, lib, &.{deck}, .{ .rail_past = false });
    const e1 = pinOf(&ended, "r1", 0).x;
    const e3 = pinOf(&ended, "r3", 0).x;
    try std.testing.expectEqual([2]i32{ @min(e1, e3), @max(e1, e3) }, extent(&ended, netOf(&ended, "vdd")));
    try std.testing.expectEqual(2, bends(&ended, netOf(&ended, "vdd")));
    // The symbols on the bar's line and the names at its right end.
    const marks = struct {
        fn f(q: *const np.Placed, l: *const np.Library, net: usize, y: i32, left: i32, right: i32) [2]usize {
            var n: [2]usize = .{ 0, 0 };
            for (q.dev_name, q.dev_class, q.dev_pos) |name, class, at| {
                n[0] += @intFromBool(name.len == 0 and class == l.findRole(.power_rail).? and at.y == y and at.x >= left and at.x <= right);
            }
            for (q.labels) |lb| n[1] += @intFromBool(lb.net == net and lb.at.y == y and lb.at.x == right);
            return n;
        }
    }.f;
    try std.testing.expectEqual([2]usize{ 0, 1 }, marks(&p, lib, vdd, pinOf(&p, "r1", 0).y - rail, @min(x1, x3) - rail, @max(x1, x3) + rail));
    try std.testing.expectEqual([2]usize{ 1, 0 }, marks(&ended, lib, netOf(&ended, "vdd"), pinOf(&ended, "r1", 0).y - rail, @min(e1, e3), @max(e1, e3)));
}

test "sketch: a rail symbol stands on a two-pin part's end, and a stub out from a transistor's" {
    // Oracle: the hand drawings. Of 8,367 rail symbols at a two-pin part's
    // end in the 5,263 reference drawings, 6,883 stand on the pin; of 8,921
    // at a transistor's path end, 3,612 (the rest on a stub).
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const p = try draw(arena, lib, &.{
        \\Common source, its gate on a divider
        \\.model nch nmos
        \\M1 d g 0 0 nch
        \\RD vdd d 1k
        \\R1 vdd g 1k
        \\R2 g 0 1k
        \\
    }, .{});
    const gnd = lib.findRole(.ground_rail).?;
    var on_r2 = false;
    var on_m1 = false;
    for (p.dev_name, p.dev_class, 0..) |n, class, d| {
        if (n.len != 0 or class != gnd) continue;
        const at = p.pin_xy[p.pinRange(d)[0]];
        on_r2 = on_r2 or at.eql(pinOf(&p, "r2", 1));
        on_m1 = on_m1 or at.eql(pinOf(&p, "m1", 2));
    }
    try std.testing.expect(on_r2);
    try std.testing.expect(!on_m1);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a block stands left of the transistor whose gate it drives" {
    // Oracle: the hand drawings. Of 487 blocks whose output net holds a
    // transistor's gate in the 5,263 reference drawings, 346 stand left of
    // that transistor (71%), 100 right. A regulator's error amplifier stood
    // right of its pass device, its output led back over the top.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const deck =
        \\A regulator
        \\.model nch nmos
        \\.subckt amp vdd vss vb1 vp vn vo
        \\R1 vp vo 1k
        \\R2 vn vo 1k
        \\R3 vb1 vo 1k
        \\.ends
        \\MNP vin net0 vout vout nch
        \\R1 vout fb 1k
        \\R2 fb vss 1k
        \\X1 vdd vss vb1 vref fb net0 amp
        \\
    ;
    const p = try draw(arena, lib, &.{deck}, .{});
    // The block's output pin (port order: vdd, vss, vb1, vp, vn, vo) and
    // the pass device's gate (d, g, s). The amplifier's first port that is
    // no rail is a bias line: its place came from that one's role.
    const out = pinOf(&p, "x1", 5);
    const gate = pinOf(&p, "mnp", 1);
    try std.testing.expect(out.x < gate.x);
    try std.testing.expect(gate.x < pinOf(&p, "mnp", 0).x);
    try std.testing.expectEqual(out.y, gate.y);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
}

test "sketch: a dependent source is an upright two-pin part, its control unwired; an ideal amplifier keeps its triangle" {
    // Oracle: the hand drawings. In the 5,263 reference drawings every one
    // of 414 voltage-controlled sources has two terminals, 398 of them one
    // over the other (361 of 377 `G`, 37 of 37 `E`); the control is read off
    // the element's value. Drawn with four wired pins, the 283 parts-only
    // circuits holding one crossed 198 wires where their people crossed 11.
    // An `E` with its low output on ground and a gain of a thousand or more
    // is the book's ideal amplifier, and keeps its triangle and its wired
    // inputs.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const model =
        \\A transistor's small-signal model
        \\Vi in 0 ac 1
        \\Rs in b 1k
        \\Rpi b 0 2.5k
        \\Gm c 0 b 0 40m
        \\Ro c 0 100k
        \\E1 x 0 c 0 1
        \\Rl x 0 5k
        \\
    ;
    const p = try draw(arena, lib, &.{model}, .{});
    for ([_][]const u8{ "gm", "e1" }) |name| {
        const d = for (p.dev_name, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) break i;
        } else unreachable;
        // Two terminals drawn, one over the other, the first on top.
        try std.testing.expectEqual(2, lib.at(p.dev_class[d]).terminals.len);
        try std.testing.expectEqual(pinOf(&p, name, 0).x, pinOf(&p, name, 1).x);
        try std.testing.expect(pinOf(&p, name, 0).y < pinOf(&p, name, 1).y);
        // No wire ends on a control pin: the card's third and fourth.
        const lo, const hi = p.pinRange(d);
        try std.testing.expectEqual(4, hi - lo);
    }
    try std.testing.expectEqual(0, crossings(&p));
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(gpa, &p, true));
    // The book's ideal amplifier: four terminals, its inputs wired.
    const amp =
        \\Non-inverting amplifier, ideal op-amp
        \\Vin in 0 ac 1
        \\E1 out 0 in fb 1e5
        \\Rf out fb 10k
        \\Rg fb 0 1k
        \\
    ;
    const q = try draw(arena, lib, &.{amp}, .{});
    const e = for (q.dev_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "e1")) break i;
    } else unreachable;
    try std.testing.expectEqual(4, lib.at(q.dev_class[e]).terminals.len);
}
