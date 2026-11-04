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
        const base = try placesByName(arena, &try draw(arena, lib, &.{d[1]}, .{}));
        const p = try draw(arena, lib, &.{d[1]}, long);
        const wide = try placesByName(arena, &p);
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
    var span_at_1: i32 = 0;
    for ([_]f32{ 1, 2.5 }) |k| {
        const p = try draw(arena, lib, &.{deck}, .{ .stack = k, .rail = k });
        const len: i32 = @intFromFloat(@ceil(k * @as(f32, @floatFromInt(lib.unit))));
        // Rd's pin on `out` above M1's drain: the rows' room plus `stack`
        // twice, a channel row standing between two device rows.
        const span = pinOf(&p, "m1", 0).y - pinOf(&p, "rd", 1).y;
        if (k == 1) span_at_1 = span else try std.testing.expectEqual(span_at_1 + 2 * (len - lib.unit), span);
        // M1's source, `rail` above the ground symbol under it.
        const src = pinOf(&p, "m1", 2);
        const ground = for (p.dev_name, 0..) |n, d| {
            const at = p.pin_xy[p.pinRange(d)[0]];
            if (n.len == 0 and at.x == src.x and at.y > src.y) break at;
        } else return error.NoGroundSymbol;
        try std.testing.expectEqual(len, ground.y - src.y);
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
