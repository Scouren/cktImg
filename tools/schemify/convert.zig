//! cktimg's Schemify import: a SPICE netlist → Schemify files, with the engine as the
//! layout. One `.shcomp` per `.subckt`, a `.shbench` for a top level (its dot cards and
//! `.control` blocks as a `code` block), and generated `.shprim` leaves for cards the
//! bundled `core` cells cannot re-emit faithfully.
//!
//! Spine (`Converter`), one transform per line:
//!
//! ```text
//! spice.parse(text)                      → deck    cells, devices, nets, code text
//! recognize.recognize(&deck)             → rec     symbols + per-device overrides
//! layout.library(&rec)                   → lib     engine classes = the symbols' pins
//! per cell: layout.draw(lib, deck, rec, c) → drawn the engine's placement as Schemify geometry
//!           emit.cellFile(…, &drawn)     → file
//! per generated leaf: emit.leafFile      → file
//! ```
//!
//! `Converter.step` draws one cell, so the wasm guest (`plugin.zig`) draws one per event.
//!
//! Memory: `a` (an arena the caller frees) holds the deck and every output; `gpa` backs
//! the engine's per-cell work, freed as each cell finishes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const mem = std.mem;
const engine = @import("NetlistParser");
pub const spice = @import("spice.zig");
pub const recognize = @import("recognize.zig");
pub const layout = @import("layout.zig");
pub const emit = @import("emit.zig");
const hints = @import("hints.zig");
pub const OutFile = emit.OutFile;

/// Counts for the import log.
pub const Stats = struct {
    /// Cell files written (components and the bench).
    cells: u32 = 0,
    devices: u32 = 0,
    wires: u32 = 0,
    /// Labels and ports drawn.
    markers: u32 = 0,
    /// Nets with ≥ 2 device pins that are not drawn as rails.
    nets_multi: u32 = 0,
    /// Of those, nets drawn as one wired tree.
    nets_wired: u32 = 0,
};

pub const Conversion = struct {
    /// Files to write next to the source netlist: cells first (subckts in file order, then
    /// the bench), then generated leaves.
    files: ArrayList(OutFile) = .empty,
    /// Lines kept as code, dropped parameters and other notes.
    warnings: ArrayList([]const u8) = .empty,
    stats: Stats = .{},
};

/// A conversion in progress: parsed and recognized, its cells drawn one `step` at a time.
/// Stepping to the end and `finish` give exactly what `convert` gives.
pub const Converter = struct {
    gpa: Allocator,
    a: Allocator,
    source: []const u8,
    deck: spice.Deck,
    rec: recognize.Recognized,
    lib: engine.Library,
    /// Cells still to draw, the next one last (file order: subckts, then the bench).
    todo: ArrayList(u32) = .empty,
    bench: []const u8,
    budget: u32 = layout.drawn_devices_max,
    out: Conversion = .{},

    /// Parses and recognizes `text`, read from project-relative `source` (which seeds the
    /// ids and names the bench); no cell is drawn yet. `text` must outlive `a`'s use.
    pub fn init(gpa: Allocator, a: Allocator, source: []const u8, text: []const u8) Allocator.Error!Converter {
        const deck = try spice.parse(a, text);
        var rec = try recognize.recognize(a, &deck);
        var out: Conversion = .{};
        try out.warnings.appendSlice(a, deck.warnings);
        try hints.check(a, &deck, &out.warnings);
        try out.warnings.appendSlice(a, rec.warnings.items);
        const lib = try layout.library(gpa, a, &rec, &out.warnings);
        const file = source[if (mem.lastIndexOfScalar(u8, source, '/')) |i| i + 1 else 0..];
        const base = file[0 .. mem.lastIndexOfScalar(u8, file, '.') orelse file.len];
        const bench = try recognize.uniqueStem(a, base, &rec.taken);
        var c: Converter = .{ .gpa = gpa, .a = a, .source = source, .deck = deck, .rec = rec, .lib = lib, .bench = bench, .out = out };
        var has_top = deck.devs(0).len() > 0;
        for (deck.code_cell) |cc| has_top = has_top or cc == 0;
        if (has_top) try c.todo.append(a, 0);
        var k = deck.cells();
        while (k > 1) : (k -= 1) try c.todo.append(a, k - 1);
        assert(c.todo.items.len <= deck.cells());
        return c;
    }

    pub fn deinit(c: *Converter) void {
        c.lib.deinit();
    }

    /// Cells still to draw (0: `finish` next).
    pub fn cellsLeft(c: *const Converter) usize {
        return c.todo.items.len;
    }

    /// Draws the next cell and writes its file. Asserts a cell is left.
    pub fn step(c: *Converter) Allocator.Error!void {
        const a = c.a;
        const cell = c.todo.pop().?;
        const stem = if (cell == 0) c.bench else c.rec.syms.stem.items[recognize.subSymbol(cell)];
        const drawn = try layout.draw(c.gpa, a, &c.lib, &c.deck, &c.rec, cell, &c.budget);
        if (drawn.fallback) |why| try c.out.warnings.append(a, try a.print("{s}: drawn with labels only ({s})", .{ stem, why }));
        if (drawn.strays > 0) try c.out.warnings.append(a, try a.print("{s}: the engine left {d} pins unconnected; labelled", .{ stem, drawn.strays }));
        for (drawn.notes.items) |note| try c.out.warnings.append(a, try a.print("{s}: {s}", .{ stem, note }));
        const s = &c.out.stats;
        s.cells += 1;
        s.devices += @intCast(drawn.x.items.len);
        s.wires += @intCast(drawn.wire.items.len);
        s.markers += @intCast(drawn.mark.items.len);
        s.nets_multi += drawn.nets_multi;
        s.nets_wired += drawn.nets_wired;
        try c.out.files.append(a, try emit.cellFile(a, c.source, &c.deck, &c.rec, cell, stem, &drawn));
        assert(s.nets_wired <= s.nets_multi);
    }

    /// The conversion: the cell files in drawing order, then the generated leaves. Asserts
    /// every cell is drawn.
    pub fn finish(c: *Converter) Allocator.Error!Conversion {
        assert(c.todo.items.len == 0);
        for (0..c.rec.syms.len()) |s| {
            if (c.rec.syms.origin.items[s] == .leaf) try c.out.files.append(c.a, try emit.leafFile(c.a, c.source, &c.rec, @intCast(s)));
        }
        return c.out;
    }
};

/// Converts SPICE netlist `text`, read from project-relative `source`. Deterministic: equal
/// arguments give equal bytes, natively and in the wasm guest.
pub fn convert(gpa: Allocator, a: Allocator, source: []const u8, text: []const u8) Allocator.Error!Conversion {
    var c: Converter = try .init(gpa, a, source, text);
    defer c.deinit();
    while (c.cellsLeft() > 0) try c.step();
    return c.finish();
}

test {
    _ = spice;
    _ = recognize;
    _ = layout;
    _ = emit;
}

const testing = std.testing;

test "an rc deck becomes one bench" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const out = try convert(testing.allocator, arena.allocator(), "rc.sp", "* rc\nV1 in 0 1\nR1 in out 1k\nC1 out 0 1n\n.tran 1u 1m\n");
    try testing.expectEqual(1, out.files.items.len);
    try testing.expectEqualStrings("rc.shbench", out.files.items[0].name);
    const text = out.files.items[0].bytes;
    try testing.expect(mem.indexOf(u8, text, "core:res") != null);
    try testing.expect(mem.indexOf(u8, text, "| .tran 1u 1m") != null);
}
