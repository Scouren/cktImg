//! The Schemify import over every fixture, natively: each converts without a crash and
//! twice to the same bytes (determinism is a test). Every cell the engine is handed, drawn
//! by #8's stages, keeps its devices, is connected as a netlister reads it, and shorts
//! nothing. Connectivity of the import's own files is the round trip's job.

const std = @import("std");
const cktimg = @import("cktimg");
const np = @import("NetlistParser");
const support = @import("support.zig");

const fixtures = @import("fixtures.zig");

// ---- private ----

fn bytesOf(gpa: std.mem.Allocator, a: std.mem.Allocator, name: []const u8, text: []const u8) ![]const u8 {
    const out = try cktimg.convert(gpa, a, name, text);
    var all: std.ArrayList(u8) = .empty;
    for (out.files.items) |f| {
        try std.testing.expect(std.mem.startsWith(u8, f.bytes, "schemify 1 "));
        try all.print(a, "== {s}\n{s}", .{ f.name, f.bytes });
    }
    return all.items;
}

/// The 5T OTA as a subckt, with `hints` after its ports.
fn otaWith(a: std.mem.Allocator, hints: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{
        "* ota\n.model nch nmos level=1\n.model pch pmos level=1\n.subckt ota inp inn out vdd vss vb\n",
        hints,
        "M1 x inp tail vss nch\nM2 out inn tail vss nch\nM3 x x vdd vdd pch\nM4 out x vdd vdd pch\nM5 tail vb vss vss nch\n.ends\n",
    });
}

/// The kind of the block the engine finds holding devices `p` and `q` of the
/// deck the ota cell hands it.
fn blockOf(gpa: std.mem.Allocator, a: std.mem.Allocator, text: []const u8, p: []const u8, q: []const u8) !?np.schematic.structure.BlockKind {
    var conv = try cktimg.Converter.init(gpa, a, "ota.sp", text);
    defer conv.deinit();
    const cell = conv.deck.findCell("ota").?;
    const deck = try cktimg.layout.cellDeck(a, &conv.deck, &conv.rec, cell, try cktimg.layout.netNames(a, &conv.deck, cell));
    var nl = try np.netlist.parse(a, &.{deck}, null);
    const st = try np.schematic.structure.analyze(a, a, &nl, try np.guessRoles(a, &nl));
    const names = nl.graph.edges.items(.name);
    for (st.block_kind, 0..) |k, b| {
        var has: u2 = 0;
        for (st.members(b)) |d| has += @intFromBool(std.mem.eql(u8, names[d], p) or std.mem.eql(u8, names[d], q));
        if (has == 2) return k;
    }
    return null;
}

test {
    _ = @import("remaining_amplifiers.zig");
    _ = @import("reference_amplifiers.zig");
}

test "every fixture converts, deterministically" {
    for (fixtures.plugin) |f| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const name = f.name;
        const text = f.spice;
        const source = try std.fmt.allocPrint(a, "n2s/{s}", .{name});
        const first = try bytesOf(std.testing.allocator, a, source, text);
        const again = try bytesOf(std.testing.allocator, a, source, text);
        std.testing.expectEqualStrings(first, again) catch |e| {
            std.debug.print("{s}: output differs between two runs\n", .{name});
            return e;
        };
    }
}

test "every cell the engine is handed draws connected and short-free by #8's stages" {
    const gpa = std.testing.allocator;
    var bad: usize = 0;
    var cells: usize = 0;
    for (fixtures.plugin ++ fixtures.analogioc) |f| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var conv = try cktimg.Converter.init(gpa, a, f.name, f.spice);
        defer conv.deinit();
        for (conv.todo.items) |cell| {
            // The cells `layout.draw` hands the engine: some device has a net, at most
            // `cell_devices_max` do.
            const devs = conv.deck.devs(cell);
            var wired: u32 = 0;
            for (devs.lo..devs.hi) |d| wired += @intFromBool(conv.deck.netsOf(@intCast(d)).len > 0);
            if (wired == 0 or wired > cktimg.layout.cell_devices_max) continue;
            cells += 1;
            const names = try cktimg.layout.netNames(a, &conv.deck, cell);
            const text = try cktimg.layout.cellDeck(a, &conv.deck, &conv.rec, cell, names);
            var nl = try np.netlist.parse(a, &.{text}, null);
            const roles = try np.guessRoles(a, &nl);
            const s = try np.layout(a, &nl, roles, &conv.lib, .{});
            const p = try np.Placed.init(a, &s, &nl);
            support.expectConnected(&p, &conv.lib) catch {
                std.debug.print("{s} cell {d}: a net in pieces\n", .{ f.name, cell });
                bad += 1;
            };
            const shorts = try support.shorts(gpa, &p, true);
            if (shorts > 0) {
                std.debug.print("{s} cell {d}: {d} nets touch another's point\n", .{ f.name, cell, shorts });
                bad += 1;
            }
            const dotted = try support.dots(gpa, &p, true);
            if (dotted > 0) {
                std.debug.print("{s} cell {d}: {d} points whose dot is wrong\n", .{ f.name, cell, dotted });
                bad += 1;
            }
        }
    }
    try std.testing.expect(cells > fixtures.plugin.len);
    try std.testing.expectEqual(0, bad);
}

test "a subckt's grouping hints reach the engine under its device names" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The engine's deck keeps the designer's names: recognized a mirror,
    // hinted a pair.
    try std.testing.expectEqual(.mirror, try blockOf(std.testing.allocator, a, try otaWith(a, ""), "m3", "m4"));
    try std.testing.expectEqual(.pair, try blockOf(std.testing.allocator, a, try otaWith(a, "*@ group pair M4 M3\n"), "m3", "m4"));
    try std.testing.expectEqual(null, try blockOf(std.testing.allocator, a, try otaWith(a, "*@ grouping off\n"), "m3", "m4"));
}

test "every line reaches the engine, and one it does not honour is a log line citing the designer's lines" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try otaWith(a, "*@ above M5 M1\n*@ above M1 M5\n*@ label X\n");
    var conv = try cktimg.Converter.init(std.testing.allocator, a, "ota.sp", text);
    defer conv.deinit();
    const cell = conv.deck.findCell("ota").?;
    const deck = try cktimg.layout.cellDeck(a, &conv.deck, &conv.rec, cell, try cktimg.layout.netNames(a, &conv.deck, cell));
    try std.testing.expect(std.mem.indexOf(u8, deck, "*@ above m5 m1\n") != null);
    var nl = try np.netlist.parse(a, &.{deck}, null);
    try std.testing.expectEqual(3, nl.hints.len);
    try std.testing.expect(nl.device(nl.hints[0].args[0]) != null);
    try std.testing.expect(nl.net(nl.hints[2].args[0]) != null);
    const out = try cktimg.convert(std.testing.allocator, a, "ota.sp", text);
    // Lines 5 and 6 of the file: the earlier gives way to the later.
    var cited: usize = 0;
    for (out.warnings.items) |w| cited += @intFromBool(std.mem.indexOf(u8, w, "line 5: `*@ above m5 m1` dropped (cycle), blocked by line 6") != null);
    if (cited != 1) for (out.warnings.items) |w| std.debug.print("{s}\n", .{w});
    try std.testing.expectEqual(1, cited);
}

test "a cell draws the same with its instances in another order" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const body = "M1 x inp tail vss nch\nM2 out inn tail vss nch\nM3 x x vdd vdd pch\nM4 out x vdd vdd pch\nM5 tail vb vss vss nch\n";
    const reversed = "M5 tail vb vss vss nch\nM4 out x vdd vdd pch\nM3 x x vdd vdd pch\nM2 out inn tail vss nch\nM1 x inp tail vss nch\n";
    const head = "* ota\n.model nch nmos level=1\n.model pch pmos level=1\n.subckt ota inp inn out vdd vss vb\n";
    var placesOf: [2][]const u8 = undefined;
    for ([_][]const u8{ body, reversed }, 0..) |cards, k| {
        const text = try std.mem.concat(a, u8, &.{ head, cards, ".ends\n" });
        var conv = try cktimg.Converter.init(std.testing.allocator, a, "ota.sp", text);
        defer conv.deinit();
        const cell = conv.deck.findCell("ota").?;
        const deck = try cktimg.layout.cellDeck(a, &conv.deck, &conv.rec, cell, try cktimg.layout.netNames(a, &conv.deck, cell));
        var nl = try np.netlist.parse(a, &.{deck}, null);
        const s = try np.layout(a, &nl, try np.guessRoles(a, &nl), &conv.lib, .{});
        const p = try np.Placed.init(a, &s, &nl);
        var lines: std.ArrayList([]const u8) = .empty;
        for (p.dev_name, p.dev_pos) |n, at| if (n.len > 0) try lines.append(a, try std.fmt.allocPrint(a, "{s} {d} {d}", .{ n, at.x, at.y }));
        std.mem.sort([]const u8, lines.items, {}, struct {
            fn lt(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.lessThan(u8, x, y);
            }
        }.lt);
        placesOf[k] = try std.mem.join(a, "\n", lines.items);
    }
    try std.testing.expectEqualStrings(placesOf[0], placesOf[1]);
}

test "a hint naming a device the subckt lacks is a log line naming it, and the rest imports" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = try cktimg.convert(std.testing.allocator, a, "ota.sp", try otaWith(a, "*@ group pair M1 M2\n*@ nogroup M9\n"));
    var named: usize = 0;
    for (out.warnings.items) |w| named += @intFromBool(std.mem.indexOf(u8, w, "M9") != null);
    try std.testing.expectEqual(1, named);
    // One `.shcomp` per `.subckt`, with all five devices.
    var comps: usize = 0;
    for (out.files.items) |f| comps += @intFromBool(std.mem.endsWith(u8, f.name, ".shcomp"));
    try std.testing.expectEqual(1, comps);
    try std.testing.expectEqual(5, out.stats.devices);
}

test "steered oblique capacitor has two real tips; another cell cannot bind those tips to a resistor" {
    const t = std.testing;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const deck =
        \\separate target cells
        \\.subckt selected a b
        \\C1 a b 2.25p m=3
        \\C2 a b 8p
        \\*@ class C1 cap_oblique
        \\*@ weak class C1 cap
        \\.ends selected
        \\.subckt incompatible c d
        \\R1 c d 1k
        \\*@ class R1 cap_oblique
        \\.ends incompatible
    ;
    const out = try cktimg.convert(t.allocator, arena.allocator(), "probe.cir", deck);
    var seen: u8 = 0;
    for (out.files.items) |f| {
        if (std.mem.eql(u8, f.name, "polyphase_cap.shprim")) {
            for ([_][]const u8{ "pin p inout -21 -21", "pin n inout 21 21", "line -21 -21 -3 -3", "line 21 21 3 3", "{name} {p} {n} {value} m={m}" }) |s|
                try t.expect(std.mem.indexOf(u8, f.bytes, s) != null);
            seen |= 1;
        } else if (std.mem.eql(u8, f.name, "selected.shcomp")) {
            try t.expect(std.mem.indexOf(u8, f.bytes, "core:cap") != null);
            try t.expect(std.mem.indexOf(u8, f.bytes, "polyphase_cap") != null);
            seen |= 2;
        } else if (std.mem.eql(u8, f.name, "incompatible.shcomp")) {
            try t.expect(std.mem.indexOf(u8, f.bytes, "core:res") != null);
            seen |= 4;
        }
    }
    try t.expectEqual(@as(u8, 7), seen);
    for (out.warnings.items) |msg| {
        if (std.mem.indexOf(u8, msg, "different contact coordinates") != null) return;
    }
    return error.MissingCapabilityDiagnostic;
}

test "a closed switched-varactor control bus keeps four exact scalar names in one host contact" {
    // Oracle: the editable host expands this ordered comma expression to these four
    // literal names, independently netlisted from AG1146. A second scalar consumer
    // or a differently ordered call must retain the complete scalar representation.
    const text = "* bus\n.subckt Varactor_Switched_caps Von Vop B_3_ B_2_ B_1_ B_0_ Vcn Vcp\n.ends\n.subckt osc Von Vop Vcn Vcp B_3_ B_2_ B_1_ B_0_\nXbank Von Vop B_3_ B_2_ B_1_ B_0_ Vcn Vcp Varactor_Switched_caps\n";
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bus = "pin B_3_,B_2_,B_1_,B_0_ ";
    for ([_][]const u8{ ".ends\n", "Rextra B_1_ Vcn 1k\n.ends\n", ".ends\nXtop p n c d z y x w osc\n", "*@ label B_2_\n.ends\n", "*@ port B_2_ unknown-side\n.ends\n" }, 0..) |suffix, i| {
        const files = try bytesOf(std.testing.allocator, a, "bank.sp", try std.mem.concat(a, u8, &.{ text, suffix }));
        try std.testing.expectEqual(@as(usize, if (i == 0 or i == 4) 2 else 0), std.mem.count(u8, files, bus));
        if (i == 0 or i == 4) {
            try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, files, " B_3_,B_2_,B_1_,B_0_\n"));
            try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, files, " B<3:0>\n"));
        } else try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, files, "pin B_1_ "));
    }
    const reordered = try std.mem.replaceOwned(u8, a, text, "Xbank Von Vop B_3_ B_2_", "Xbank Von Vop B_2_ B_3_");
    const files = try bytesOf(std.testing.allocator, a, "bank.sp", try std.mem.concat(a, u8, &.{ reordered, ".ends\n" }));
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, files, bus));
}
