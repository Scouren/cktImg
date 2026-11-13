//! The public surface, as a caller uses it: the tiers agree, the result is
//! well-formed plain data, and nothing is lost between netlist and drawing.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const fixtures = @import("fixtures.zig");
const support = @import("support.zig");
const textbook = @import("textbook.zig");

fn placeText(lib: *np.Library, src: []const u8) !np.Placed {
    return np.place(testing.allocator, &.default, lib, &.{src}, null);
}

/// Wires are Manhattan polylines; every pin with company on its net is on a
/// wire of that net, a label of it, or a symbol of it — nothing floats.
fn expectWellFormed(p: *const np.Placed, lib: *const np.Library) !void {
    try testing.expectEqual(p.netCount() + 1, p.net_seg.len);
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        while (it.next()) |poly| {
            try testing.expect(poly.len >= 2);
            for (poly[0 .. poly.len - 1], poly[1..]) |a, b| try testing.expect(a.x == b.x or a.y == b.y);
        }
    }
    var count: []u32 = try testing.allocator.alloc(u32, p.netCount());
    defer testing.allocator.free(count);
    @memset(count, 0);
    for (p.pin_net) |n| if (n != np.placed.no_net) {
        count[n] += 1;
    };
    for (0..p.deviceCount()) |d| {
        const class = lib.at(p.dev_class[d]);
        const lo, const hi = p.pinRange(d);
        for (lo..hi) |pin| {
            const n = p.pin_net[pin];
            const k = pin - lo;
            if (n == np.placed.no_net or k >= class.terminals.len or class.terminals[k].hidden) continue;
            if (count[n] < 2) continue;
            if (class.terminals[k].ground_ref) continue; // may be left unwired on ground
            if (hi - lo == 1) continue; // a port or rail symbol: a name, wired or not
            const at = p.pin_xy[pin];
            var found = false;
            var it = p.segments(n);
            while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (np.Rect.fromCorners(a, b).contains(at)) found = true;
            };
            for (p.labels) |l| found = found or (l.net == n and l.at.eql(at));
            // A lone terminal symbol on the pin itself names it.
            for (0..p.deviceCount()) |e| {
                if (e == d) continue;
                const elo, const ehi = p.pinRange(e);
                for (elo..ehi) |q| found = found or (p.pin_net[q] == n and p.pin_xy[q].eql(at));
            }
            if (!found) {
                std.debug.print("pin {d} of {s} ({s}) on net {s} at {any} touches nothing\n", .{ k, p.dev_name[d], class.name, p.net_name[n], at });
                return error.FloatingPin;
            }
        }
    }
}

/// The net of `p` named `name`, and how many ground symbols stand on it.
fn groundNet(p: *const np.Placed, lib: *const np.Library, name: []const u8) struct { u32, u32 } {
    const net: u32 = for (p.net_name, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) break @intCast(i);
    } else unreachable;
    var rails: u32 = 0;
    for (p.dev_class, p.dev_pin0[0..p.deviceCount()]) |c, pin| rails += @intFromBool(lib.at(c).role == .ground_rail and p.pin_net[pin] == net);
    return .{ net, rails };
}

/// The pin of `p`'s one supply symbol.
fn supplyPin(p: *const np.Placed, lib: *const np.Library) u32 {
    var found: ?u32 = null;
    for (p.dev_class, p.dev_pin0[0..p.deviceCount()]) |c, pin| {
        if (lib.at(c).role != .power_rail) continue;
        std.debug.assert(found == null);
        found = pin;
    }
    return found.?;
}

const expectConnected = support.expectConnected;

test "place: one call and the stages give the same drawing" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const src = textbook.all[2].spice;
    var one = try placeText(lib, src);
    defer one.deinit();

    var nl = try np.netlist.parse(gpa, &.{src}, null);
    defer nl.deinit(gpa);
    const roles = try np.guessRoles(gpa, &nl);
    defer gpa.free(roles);
    var s = try np.layout(gpa, &nl, roles, lib, .{});
    defer s.deinit();
    var staged = try np.Placed.init(gpa, &s, &nl);
    defer staged.deinit();

    try testing.expectEqualSlices(np.Pt, one.dev_pos, staged.dev_pos);
    try testing.expectEqualSlices(np.Pt, one.wire_pts, staged.wire_pts);
}

test "pipeline: borrowed results, pages kept across documents" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var p = np.Pipeline.init(gpa, &.default, lib);
    defer p.deinit();
    for (textbook.all) |c| {
        const got = try p.run(&.{c.spice}, null);
        var own = try placeText(lib, c.spice);
        defer own.deinit();
        try testing.expectEqualSlices(np.Pt, own.pin_xy, got.pin_xy);
    }
}

test "placed: every textbook drawing is well-formed and loses no device" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for (textbook.all ++ textbook.beyond) |c| {
        errdefer std.debug.print("circuit: {s}\n", .{c.name});
        var p = try placeText(lib, c.spice);
        defer p.deinit();
        try expectWellFormed(&p, lib);
        try expectConnected(&p, lib);
        // Every netlist device with a pin is drawn exactly once (drivers apart).
        var nl = try np.netlist.parse(gpa, &.{c.spice}, null);
        defer nl.deinit(gpa);
        for (nl.graph.edges.items(.name)) |name| {
            var seen: u32 = 0;
            for (p.dev_name) |dn| seen += @intFromBool(std.mem.eql(u8, dn, name));
            try testing.expectEqual(1, seen);
        }
    }
}

test "placed: a driver stands apart, between its terminal symbol and ground" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var p = try placeText(lib, textbook.all[1].spice); // cs_resistive: Vdd and Vin drive terminals
    defer p.deinit();
    const vdd = for (p.dev_name, 0..) |n, d| {
        if (std.mem.eql(u8, n, "vdd")) break d;
    } else unreachable;
    // Left of everything else that is not an island.
    const rd = for (p.dev_name, 0..) |n, d| {
        if (std.mem.eql(u8, n, "rd")) break d;
    } else unreachable;
    try testing.expect(p.dev_pos[vdd].x < p.dev_pos[rd].x);
    // Its + pin (on net vdd) is above its - pin, each wired to a symbol.
    const lo, _ = p.pinRange(vdd);
    try testing.expect(p.pin_xy[lo].y < p.pin_xy[lo + 1].y);
    var rails: u32 = 0;
    for (p.dev_class, p.dev_name) |c, n| rails += @intFromBool(n.len == 0 and lib.at(c).role == .power_rail);
    try testing.expectEqual(2, rails); // the circuit's rail and the island's
}

test "placed: a pin off the layout's line gets a lead onto it" {
    // The op-amp's inputs are 40 apart on the symbol, the second off its
    // input side's line: its own copy node, and the wires end on the pins.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var p = try np.place(gpa, &.default, lib, &.{textbook.all[13].spice}, null);
    defer p.deinit();
    try expectWellFormed(&p, lib);
}

test "placed: a device kind with no class is drawn as a generated box" {
    const gpa = testing.allocator;
    var lib = np.Library.init(gpa);
    defer lib.deinit();
    var p = try placeText(&lib, "t\nR1 a b 1k\nR2 b 0 1k\n");
    defer p.deinit();
    try testing.expect(lib.isGeneric(p.dev_class[0]));
}

const with_block =
    \\Non-inverting amplifier around an op-amp block
    \\.subckt opamp inp inn out vdd vss
    \\*@ left inp inn
    \\*@ right out
    \\E1 out 0 inp inn 1e5
    \\R1 vdd vss 1meg
    \\.ends
    \\Vdd vdd 0 1.8
    \\Vin in 0 ac 1
    \\X1 in fb out vdd 0 opamp
    \\Rf out fb 10k
    \\Rg fb 0 1k
;

test "blocks: a subcircuit is one block, its ports on the sides its directives say" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var p = try placeText(lib, with_block);
    defer p.deinit();
    try expectWellFormed(&p, lib);
    try expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(gpa, &p, true));

    const x = for (p.dev_name, 0..) |n, d| {
        if (std.mem.eql(u8, n, "x1")) break d;
    } else return error.NoBlock;
    try testing.expectEqualStrings("block:opamp", lib.at(p.dev_class[x]).name);
    // Nothing from inside is drawn.
    for (p.dev_name) |n| try testing.expect(std.mem.indexOf(u8, n, ".x1.") == null);
    // inp and inn on the left, inp above inn; out on the right.
    const lo, _ = p.pinRange(x);
    const at = p.dev_pos[x];
    try testing.expect(p.pin_xy[lo].x < at.x and p.pin_xy[lo + 1].x < at.x);
    try testing.expect(p.pin_xy[lo].y < p.pin_xy[lo + 1].y);
    try testing.expect(p.pin_xy[lo + 2].x > at.x);
}

test "blocks: *@ expand draws what is inside instead" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const src = try std.mem.replaceOwned(u8, gpa, with_block, "*@ right out", "*@ right out\n*@ expand");
    defer gpa.free(src);
    var p = try placeText(lib, src);
    defer p.deinit();
    try expectWellFormed(&p, lib);
    var inside: u32 = 0;
    for (p.dev_name, p.dev_class) |n, c| {
        try testing.expect(!std.mem.startsWith(u8, lib.at(c).name, "block:"));
        inside += @intFromBool(std.mem.eql(u8, n, "e.x1.e1") or std.mem.eql(u8, n, "r.x1.r1"));
    }
    try testing.expectEqual(2, inside);
}

test "placed: every net is one piece: example decks, a cross-coupled latch, a nine-port block" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for (@import("examples").all ++ [_][]const u8{ strongarm, nine_ports }) |src| {
        var p = try placeText(lib, src);
        defer p.deinit();
        try testing.expect(p.deviceCount() > 2);
        try expectWellFormed(&p, lib);
        try expectConnected(&p, lib);
    }
}

/// A block with more ports than a primitive has pins: every one is wired.
const nine_ports =
    \\nine ports
    \\.subckt nine a b c d e f g vdd vss
    \\R1 a b 1k
    \\.ends nine
    \\X1 n1 n2 n3 n4 n5 n6 n7 vdd 0 nine
    \\R1 n1 n2 1k
    \\R2 n3 n4 1k
    \\R3 n5 n6 1k
    \\R4 n7 0 1k
    \\R5 vdd n1 1k
;

/// A StrongARM latch: outp and outn each drive the other pair's gates.
/// The body of the subcircuit, as `cktimg-json` draws a deck of one.
const strongarm =
    \\strongarm
    \\Xtail tail clk vss vss sky130_fd_pr__nfet_01v8 W=0.42 L=0.15
    \\Xinp drn_p vinp tail vss sky130_fd_pr__nfet_01v8 W=21.8 L=0.6
    \\Xinn drn_n vinn tail vss sky130_fd_pr__nfet_01v8 W=21.8 L=0.6
    \\Xxnp outp outn drn_p vss sky130_fd_pr__nfet_01v8 W=2.3 L=0.15
    \\Xxnn outn outp drn_n vss sky130_fd_pr__nfet_01v8 W=2.3 L=0.15
    \\Xxpp outp outn vdd vdd sky130_fd_pr__pfet_01v8 W=10.33 L=0.15
    \\Xxpn outn outp vdd vdd sky130_fd_pr__pfet_01v8 W=10.33 L=0.15
    \\Xrstp outp clk vdd vdd sky130_fd_pr__pfet_01v8 W=2.3 L=0.15
    \\Xrstn outn clk vdd vdd sky130_fd_pr__pfet_01v8 W=2.3 L=0.15
;

test "placed: random netlists draw every net as one piece, no wire on another's point" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const nets = [_][]const u8{ "vdd", "0", "in", "out", "a", "b", "c" };
    var prng = std.Random.DefaultPrng.init(12345);
    const r = prng.random();
    for (0..1000) |_| {
        var buf: [1024]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        try w.writeAll("random\n.model nch nmos level=1\n.model pch pmos level=1\nVdd vdd 0 1.8\nVin in 0 ac 1\n");
        for (0..r.intRangeAtMost(u32, 2, 6)) |i| {
            const p = nets[r.intRangeLessThan(usize, 0, nets.len)];
            const q = nets[r.intRangeLessThan(usize, 0, nets.len)];
            const g = nets[r.intRangeLessThan(usize, 0, nets.len)];
            switch (r.intRangeAtMost(u32, 0, 3)) {
                0 => try w.print("R{d} {s} {s} 1k\n", .{ i, p, q }),
                1 => try w.print("C{d} {s} {s} 1p\n", .{ i, p, q }),
                2 => try w.print("M{d} {s} {s} {s} 0 nch\n", .{ i, p, g, q }),
                else => try w.print("M{d} {s} {s} {s} vdd pch\n", .{ i, p, g, q }),
            }
        }
        errdefer std.debug.print("{s}\n", .{w.buffered()});
        var pl = try placeText(lib, w.buffered());
        defer pl.deinit();
        try expectConnected(&pl, lib);
        try testing.expectEqual(0, try support.shorts(gpa, &pl, true));
    }
}

// The wire-first layout failed this, before its relayout and repair passes,
// on rstring_ladder (29 nets), gain_cell_array 24, write_dac 18,
// weight_tile 4 (`rowa0` across the `phi1`/`phi2` gates), the nine-port
// block 4 and blocks.spice 3; #8's canvas commits no such wire.
test "placed: no wire touches another net's pin, wire end or label" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var failed: u32 = 0;
    for (textbook.all ++ textbook.beyond) |c| {
        var p = try placeText(lib, c.spice);
        defer p.deinit();
        const k = try support.shorts(gpa, &p, true);
        if (k > 0) std.debug.print("textbook {s}: {d} nets\n", .{ c.name, k });
        failed += k;
    }
    for (@import("examples").all ++ [_][]const u8{ strongarm, nine_ports, with_block }) |src| {
        var p = try placeText(lib, src);
        defer p.deinit();
        const k = try support.shorts(gpa, &p, true);
        if (k > 0) std.debug.print("example {s}: {d} nets\n", .{ src[0..@min(src.len, 20)], k });
        failed += k;
    }
    // As AnalogIOC's converter runs it, a file of `.subckt`s titled as
    // cktimg-json titles it.
    for (fixtures.analogioc) |c| {
        // cktimg-json's top cell: the last `.subckt`'s body, the deck after it.
        const text = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ c.name, c.spice });
        defer gpa.free(text);
        var nl = try np.netlist.parse(gpa, &.{text}, null);
        defer nl.deinit(gpa);
        const top = try std.fmt.allocPrint(gpa, "{s}\n{s}", .{ c.name, nl.defs[nl.defs.len - 1].body });
        defer gpa.free(top);
        var p = try np.place(gpa, &.default, lib, &.{ top, text[c.name.len + 1 ..] }, null);
        defer p.deinit();
        try expectConnected(&p, lib);
        const k = try support.shorts(gpa, &p, true);
        if (k > 0) std.debug.print("analogioc {s}: {d} nets\n", .{ c.name, k });
        failed += k;
    }
    try testing.expectEqual(0, failed);
}

test "geom: a ground symbol carries no name; of two ground nets, the one that is not net 0 is named" {
    // Oracle: the hand drawings. 0 of 16,717 ground symbols in 5,263
    // hand-drawn schematics carry a name; of 436 drawings with two ground
    // nets, 433 keep one as plain symbols and name the other.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var one = try placeText(lib, "One ground\nR1 in out 1k\nR2 out vss 1k\nC1 out vss 1p\n");
    defer one.deinit();
    const vss, const rails = groundNet(&one, lib, "vss");
    try testing.expect(rails >= 1);
    try testing.expect(!np.geom.namesRail(&one, lib, vss));

    var two = try placeText(lib, "Two grounds\nR1 in out 1k\nR2 out vss 1k\nC1 out 0 1p\n");
    defer two.deinit();
    const vss2, const rails2 = groundNet(&two, lib, "vss");
    const zero, const rails0 = groundNet(&two, lib, "0");
    try testing.expect(rails2 >= 1 and rails0 >= 1);
    try testing.expect(np.geom.namesRail(&two, lib, vss2));
    try testing.expect(!np.geom.namesRail(&two, lib, zero));
}

test "placed: a negative supply named vee is drawn with the supply glyph, a ground with the ground's" {
    // Oracle: the hand drawings. 470 of 477 `vee` rail symbols in 5,263
    // hand-drawn schematics are the supply's glyph, below the pin
    // (placed.9); `vss` keeps the ground's.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try placeText(lib, "Negative supply\nR1 in out 1k\nR2 out vee 1k\nC1 out vss 1p\n");
    defer p.deinit();
    // Per net: supply glyphs, ground glyphs.
    var vee: [2]u32 = .{ 0, 0 };
    var vss: [2]u32 = .{ 0, 0 };
    for (p.dev_class, p.dev_pin0[0..p.deviceCount()]) |c, pin| {
        const k: usize = switch (lib.at(c).role) {
            .power_rail => 0,
            .ground_rail => 1,
            else => continue,
        };
        const name = p.net_name[p.pin_net[pin]];
        if (std.mem.eql(u8, name, "vee")) vee[k] += 1;
        if (std.mem.eql(u8, name, "vss")) vss[k] += 1;
    }
    try testing.expect(vee[0] >= 1);
    try testing.expectEqual(0, vee[1]);
    try testing.expect(vss[1] >= 1);
    try testing.expectEqual(0, vss[0]);
}

test "geom: a device's name stands on a side of its symbol no pin of it stands on" {
    // Oracle: the hand drawings. 40,958 of 45,982 named devices in 5,263
    // hand-drawn schematics carry the name on the first side no pin stands
    // on (right, left, above, below): 9,409 of 10,213 upright transistors
    // whose gate faces right carry it on the left, 3,265 of 4,256 two-pin
    // parts lying flat carry it above.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var stage = try placeText(lib, "Gate right\n.model nch nmos\nM1 out in 0 0 nch\nR1 vdd out 1k\n*@ face m1 g right\n");
    defer stage.deinit();
    const m1 = np.checks.deviceIn(&stage, "m1").?;
    // Its gate faces right, its drain and source up and down: only the left is free.
    try testing.expect(stage.pin_xy[stage.dev_pin0[m1] + 1].x > stage.dev_pos[m1].x);
    const at = try np.geom.refdesAnchors(gpa, &stage, lib);
    defer gpa.free(at);
    try testing.expect(np.geom.refdesRect(at[m1], "m1").max.x <= stage.deviceRect(lib, m1).min.x);

    var flat = try placeText(lib, "Flat part\nR1 in out 1k\nC1 out 0 1p\n*@ bridge r1\n");
    defer flat.deinit();
    const r1 = np.checks.deviceIn(&flat, "r1").?;
    // It lies flat, a pin left and a pin right: above is the first free side.
    try testing.expectEqual(flat.pin_xy[flat.dev_pin0[r1]].y, flat.pin_xy[flat.dev_pin0[r1] + 1].y);
    const over = try np.geom.refdesAnchors(gpa, &flat, lib);
    defer gpa.free(over);
    try testing.expect(np.geom.refdesRect(over[r1], "r1").max.y <= flat.deviceRect(lib, r1).min.y);
}

test "geom: a supply's name stands beside its bar, and above it where the wire runs on both ways" {
    // Oracle: the hand drawings. 4,531 of 6,169 supply names in 5,263
    // hand-drawn schematics stand beside the symbol's bar (2,957 of 4,576
    // supply symbols, 1,574 of 1,593 bars named at an end), 1,511 above it.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const bit = struct {
        fn of(s: np.Side) u4 {
            return @as(u4, 1) << @backingInt(s);
        }
    }.of;
    // One pin on the supply, a two-pin part's end: its symbol stands on the
    // pin (wires.10), so no wire leaves it.
    var one = try placeText(lib, "One supply pin\n.model nch nmos\nM1 out in 0 0 nch\nR1 vdd out 1k\n");
    defer one.deinit();
    const pin = supplyPin(&one, lib);
    try testing.expectEqual(@as(u4, 0), np.checks.ways(&one, one.pin_net[pin], one.pin_xy[pin]));
    try testing.expectEqual(np.Side.right, np.geom.railSide(&one, pin));
    // Three pins on one bar carrying its symbol (`rail_past` off; the
    // default bar is a named rail with none, wires.6): the symbol stands on
    // the bar's run.
    const symbol_bar: np.Config = .{ .layout = .{ .rail_past = false } };
    var bar = try np.place(testing.allocator, &symbol_bar, lib, &.{"Supply bar\n.model nch nmos\nM1 a in 0 0 nch\nR1 vdd a 1k\nM2 b a 0 0 nch\nR2 vdd b 1k\nM3 out b 0 0 nch\nR3 vdd out 1k\n"}, null);
    defer bar.deinit();
    const on = supplyPin(&bar, lib);
    const ways = np.checks.ways(&bar, bar.pin_net[on], bar.pin_xy[on]);
    try testing.expectEqual(bit(.left) | bit(.right), ways & (bit(.left) | bit(.right) | bit(.up)));
    try testing.expectEqual(np.Side.up, np.geom.railSide(&bar, on));
}

test "place: a coupling card remains electrical data and needs no drawable class" {
    // Oracle: SPICE K names inductors, not nodes; AnalogGenie ag-1101 and
    // ag-1157 draw the coils without a separate K symbol. Adding K must not
    // lose either coil or its connectivity, even with an empty symbol library.
    const gpa = testing.allocator;
    const cards = [_][]const u8{
        "Coupled coils\nL1 in mid 1n\nL2 mid 0 2n\nK1 L1 L2 0.9\n",
        "Coupled coils\nK1 L1 L2 0.9\nL2 mid 0 2n\nL1 in mid 1n\n*@ class k1 generic2\n",
    };
    for (cards) |src| {
        var lib = np.Library.init(gpa);
        defer lib.deinit();
        var nl = try np.netlist.parse(gpa, &.{src}, null);
        defer nl.deinit(gpa);
        const k = nl.device("k1").?;
        try testing.expectEqual(np.netlist.DeviceKind.coupling, nl.graph.edges.items(.kind)[k.index()]);
        try testing.expectEqual(0, nl.graph.members(k).len);
        var p = try placeText(&lib, src);
        defer p.deinit();
        try testing.expect(np.checks.deviceIn(&p, "k1") == null);
        for ([_][]const u8{ "l1", "l2" }) |name| {
            const d = np.checks.deviceIn(&p, name).?;
            const lo, const hi = p.pinRange(d);
            try testing.expectEqual(2, hi - lo);
        }
        try testing.expectEqual(2, p.deviceCount());
        try testing.expectEqual(1, lib.count()); // only the coils' generic2
        try expectWellFormed(&p, &lib);
        try expectConnected(&p, &lib);
        const roles = try np.guessRoles(gpa, &nl);
        defer gpa.free(roles);
        var s = try np.layout(gpa, &nl, roles, &lib, .{});
        defer s.deinit();
        try testing.expect(s.pinSide(@intCast(k.index()), 0) == null);
        try testing.expect(!np.schematic.referencePin(&s, @intCast(k.index()), 0, 0));
    }
}

test {
    _ = @import("block_symbols.zig");
}
