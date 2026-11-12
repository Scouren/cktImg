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
    var sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st);
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
    // wired and cut only the far connection. With no crossing budget the
    // Sallen-Key filter's node `a` (R1, R2, C1) is cut: fewer names than
    // pins, a wire left, and the names still join the whole net.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const deck = for (textbook.beyond) |c| {
        if (std.mem.eql(u8, c.name, "sallen_key")) break c.spice;
    } else unreachable;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{ .cross_max = 0 });
    const net = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, "a")) break i;
    } else unreachable;
    var names: usize = 0;
    for (p.labels) |l| names += @intFromBool(l.net == net);
    var wires = p.segments(net);
    try std.testing.expectEqual(2, names);
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
    // Oracle: how people draw it. Of 215 bias nets whose pins stand within
    // six units around half in 5,263 hand-drawn schematics, 187 are one
    // wire with one port. A drain node a DC source holds (a bias by R2)
    // stays the wire between the transistor and its load.
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

test "sketch: a pin level with a column's junction is joined along its own row" {
    // Oracle: a certificate. Three pins cannot be joined with less wire
    // than half the perimeter of the box around them; a trunk on the tap
    // row instead of the side pin's row spends a jog more.
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
        \\X1 vdd vss vin x net0 amp
        \\
    ;
    const p = try draw(arena_state.allocator(), lib, &.{deck}, .{});
    const pins = [_]np.Pt{ pinOf(&p, "ch", 0), pinOf(&p, "m2", 2), pinOf(&p, "x1", 3) };
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
    try std.testing.expectEqual(hi.x - lo.x + hi.y - lo.y, wire);
    try support.expectConnected(&p, lib);
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
    // Oracle: how people draw it. Of 3,400 input nets of two pins or more
    // in 5,274 hand-drawn schematics, 87% carry one port symbol with the
    // pins wired; the inverter's two gates on `in` are the plainest case.
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

test "sketch: a tall block stands beside the stack it joins, not between its rows" {
    // Oracle: the keys' own definitions (`config.Layout`). Closed up, the
    // wire from the junction on the block's pin row down to the load
    // capacitor is `tap` long, whatever the block's height: the block is
    // in another column (people stand blocks side by side in 82% of 5,274
    // hand-drawn schematics). A row of its own for the block put the
    // capacitor under the block's foot.
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
        \\CH vout vss 1p
        \\M2 vdd net0 vout vss nch
        \\X1 vdd vss vin vout net0 amp
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
    // Oracle: the wires themselves. Twelve stages in a chain wrap into two
    // shelves of six: the one net that passes from the sixth stage to the
    // seventh carries names and no wire runs from shelf to shelf; every
    // other stage's net is a wire with no name; nothing crosses.
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const p = try draw(arena_state.allocator(), lib, &.{support.wide_chain}, .{});
    var named: usize = 0;
    for (p.net_name, 0..) |name, net| {
        var names: usize = 0;
        for (p.labels) |l| names += @intFromBool(l.net == net);
        if (names == 0) continue;
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
