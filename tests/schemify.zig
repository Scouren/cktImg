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
    // M3 and M4 are written m2 and m3 for the engine: recognized a mirror,
    // hinted a pair.
    try std.testing.expectEqual(.mirror, try blockOf(std.testing.allocator, a, try otaWith(a, ""), "m2", "m3"));
    try std.testing.expectEqual(.pair, try blockOf(std.testing.allocator, a, try otaWith(a, "*@ group pair M4 M3\n"), "m2", "m3"));
    try std.testing.expectEqual(null, try blockOf(std.testing.allocator, a, try otaWith(a, "*@ grouping off\n"), "m2", "m3"));
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
