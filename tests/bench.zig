//! Layout time over the fixture corpus (`zig build bench`, ReleaseFast):
//! every cell the Schemify import hands the engine, laid out from its deck
//! to `Placed`, the fastest of `runs` runs each. Prints a line per cell and
//! the total, and fails when a cell takes longer than `budget_ns`.
//!
//! When issue #8's stages replaced the wire-first layout, the 107 cells took
//! 205 ms against its 2245 ms; this is the number to cite and keep.
//!
//! Contents:
//! - `pub fn main(init: std.process.Init) !void`

const std = @import("std");
const cktimg = @import("cktimg");
const np = @import("NetlistParser");
const fixtures = @import("fixtures.zig");

const runs = 5;

/// The most one cell may take: well past the largest fixture cell (about
/// 120 ms), so only a layout whose work grows out of bounds trips it.
const budget_ns: u64 = 1_000_000_000;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var total: u64 = 0;
    var worst: u64 = 0;
    var cells: usize = 0;
    var over: usize = 0;
    for (fixtures.plugin ++ fixtures.analogioc) |f| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var conv = try cktimg.Converter.init(gpa, a, f.name, f.spice);
        defer conv.deinit();
        for (conv.todo.items) |cell| {
            // The cells `layout.draw` hands the engine.
            const devs = conv.deck.devs(cell);
            var wired: u32 = 0;
            for (devs.lo..devs.hi) |d| wired += @intFromBool(conv.deck.netsOf(@intCast(d)).len > 0);
            if (wired == 0 or wired > cktimg.layout.cell_devices_max) continue;
            const names = try cktimg.layout.netNames(a, &conv.deck, cell);
            const text = try cktimg.layout.cellDeck(a, &conv.deck, &conv.rec, cell, names);
            const ns = try fastest(gpa, io, &conv.lib, text);
            total += ns;
            worst = @max(worst, ns);
            cells += 1;
            over += @intFromBool(ns > budget_ns);
            std.debug.print("{s:<44} cell {d:>2} {d:>4} devices {d:>9} us\n", .{ f.name, cell, wired, ns / 1000 });
        }
    }
    std.debug.print("\n{d} cells: {d} ms in all, {d} ms the longest\n", .{ cells, total / 1_000_000, worst / 1_000_000 });
    if (over > 0) return error.OverBudget;
}

// ---- private ----

/// The fastest of `runs` layouts of `text`, in nanoseconds, deck to `Placed`.
fn fastest(gpa: std.mem.Allocator, io: std.Io, lib: *np.Library, text: []const u8) !u64 {
    var best: u64 = std.math.maxInt(u64);
    for (0..runs) |_| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const t0 = std.Io.Clock.awake.now(io);
        var nl = try np.netlist.parse(a, &.{text}, null);
        const roles = try np.guessRoles(a, &nl);
        const s = try np.layout(a, &nl, roles, lib, .{});
        _ = try np.Placed.init(a, &s, &nl);
        const t1 = std.Io.Clock.awake.now(io);
        best = @min(best, @as(u64, @intCast(t0.durationTo(t1).nanoseconds)));
    }
    return best;
}
