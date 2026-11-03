//! Layout time over the fixture corpus (`zig build bench`, ReleaseFast):
//! every cell the Schemify import hands the engine, laid out by today's
//! engine and by issue #8's stages, each the fastest of `runs` runs from
//! the cell's deck to `Placed`. Prints a line per cell, the totals, and
//! the cells #8's stages lay out slower; fails when one is slower by more
//! than `slack_ns` (a tiny cell's maze costs more than today's whole
//! layout, unseen at that size) or the corpus takes longer in all.
//!
//! Contents:
//! - `pub fn main(init: std.process.Init) !void`

const std = @import("std");
const cktimg = @import("cktimg");
const np = @import("NetlistParser");
const fixtures = @import("fixtures.zig");

const runs = 5;

/// How much slower a cell may lay out: a fixed cost, below what a person
/// could see.
const slack_ns = 2 * std.time.ns_per_ms;

const Engine = enum { today, sketch };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var total: [2]u64 = .{ 0, 0 };
    var slower: std.ArrayList([]const u8) = .empty;
    defer {
        for (slower.items) |s| gpa.free(s);
        slower.deinit(gpa);
    }
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
            var ns: [2]u64 = undefined;
            for (std.enums.values(Engine), &ns) |e, *t| t.* = try fastest(gpa, io, &conv.lib, text, e);
            total[0] += ns[0];
            total[1] += ns[1];
            cells += 1;
            std.debug.print("{s:<44} cell {d:>2} {d:>4} devices  today {d:>9} us  #8 {d:>9} us  x{d:.2}\n", .{ f.name, cell, wired, ns[0] / 1000, ns[1] / 1000, ratio(ns) });
            if (ns[1] > ns[0]) try slower.append(gpa, try std.fmt.allocPrint(gpa, "{s} cell {d}: x{d:.2}, +{d} us", .{ f.name, cell, ratio(ns), (ns[1] - ns[0]) / 1000 }));
            over += @intFromBool(ns[1] > ns[0] + slack_ns);
        }
    }
    std.debug.print("\n{d} cells: today {d} ms, #8 {d} ms in all (x{d:.2})\n", .{ cells, total[0] / 1_000_000, total[1] / 1_000_000, ratio(total) });
    std.debug.print("{d} cells slower by #8's stages:\n", .{slower.items.len});
    for (slower.items) |s| std.debug.print("  {s}\n", .{s});
    if (over > 0 or total[1] > total[0]) return error.Slower;
}

// ---- private ----

/// The fastest of `runs` layouts of `text`, in nanoseconds, deck to `Placed`.
fn fastest(gpa: std.mem.Allocator, io: std.Io, lib: *np.Library, text: []const u8, e: Engine) !u64 {
    var best: u64 = std.math.maxInt(u64);
    for (0..runs) |_| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const t0 = std.Io.Clock.awake.now(io);
        var nl = try np.netlist.parse(a, &.{text}, null);
        const roles = try np.guessRoles(a, &nl);
        switch (e) {
            .today => {
                var s = try np.Schematic.build(a, &nl, roles, lib);
                try np.layout(a, &s, &.default);
                _ = try np.Placed.init(a, &s, &nl);
            },
            .sketch => {
                const s = try np.schematic.sketch.lay(a, &nl, roles, lib);
                _ = try np.Placed.init(a, &s, &nl);
            },
        }
        const t1 = std.Io.Clock.awake.now(io);
        best = @min(best, @as(u64, @intCast(t0.durationTo(t1).nanoseconds)));
    }
    return best;
}

fn ratio(ns: [2]u64) f64 {
    return @as(f64, @floatFromInt(ns[1])) / @as(f64, @floatFromInt(@max(ns[0], 1)));
}
