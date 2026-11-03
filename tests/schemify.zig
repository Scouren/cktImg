//! The Schemify import over every fixture, natively: each converts without a crash and
//! twice to the same bytes (determinism is a test). Every cell the engine is handed, drawn
//! by #8's stages, keeps its devices, is connected as a netlister reads it, and shorts
//! nothing. Connectivity of the import's own files is the round trip's job.

const std = @import("std");
const cktimg = @import("cktimg");
const np = @import("NetlistParser");
const support = @import("support.zig");

const fixtures = @import("fixtures.zig");

fn bytesOf(gpa: std.mem.Allocator, a: std.mem.Allocator, name: []const u8, text: []const u8) ![]const u8 {
    const out = try cktimg.convert(gpa, a, name, text);
    var all: std.ArrayList(u8) = .empty;
    for (out.files.items) |f| {
        try std.testing.expect(std.mem.startsWith(u8, f.bytes, "schemify 1 "));
        try all.print(a, "== {s}\n{s}", .{ f.name, f.bytes });
    }
    return all.items;
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
            const s = try np.schematic.sketch.lay(a, &nl, roles, &conv.lib);
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
        }
    }
    try std.testing.expect(cells > fixtures.plugin.len);
    try std.testing.expectEqual(0, bad);
}
