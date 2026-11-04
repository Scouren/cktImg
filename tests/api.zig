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
