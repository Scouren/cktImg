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
pub const place = @import("place.zig");
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
    /// Where the host puts the files (the manifest header's `place` and the `lib` rows), which decides
    /// how cells refer to each other; empty: all beside each other, `./cell` throughout.
    /// Set before the first `step`.
    place: place.Place = .{},
    out: Conversion = .{},

    /// Parses and recognizes `text`, read from project-relative `source` (which seeds the
    /// ids and names the bench); no cell is drawn yet. `text` must outlive `a`'s use.
    pub fn init(gpa: Allocator, a: Allocator, source: []const u8, text: []const u8) Allocator.Error!Converter {
        return initLibs(gpa, a, source, text, &.{});
    }

    /// `init` with the project's library cells an `X` of an undefined subckt may call
    /// (`calls` lists the names to look up); `libs` must outlive `a`'s use.
    pub fn initLibs(gpa: Allocator, a: Allocator, source: []const u8, text: []const u8, libs: []const recognize.LibCell) Allocator.Error!Converter {
        const deck = try spice.parse(a, text);
        var rec = try recognize.recognize(a, &deck, libs);
        var out: Conversion = .{};
        try out.warnings.appendSlice(a, deck.warnings);
        try hints.check(a, &deck, &out.warnings);
        try out.warnings.appendSlice(a, rec.warnings.items);
        const lib = try layout.library(gpa, a, &rec, &out.warnings);
        const file = source[if (mem.lastIndexOfScalar(u8, source, '/')) |i| i + 1 else 0..];
        const base = title(&deck) orelse file[0 .. mem.lastIndexOfScalar(u8, file, '.') orelse file.len];
        // A bench named like a cell it tests (`rcdiv.sp` holding `.subckt rcdiv`) reads
        // `tb_<name>` rather than `<name>_2`.
        const named = if (recognize.nameTaken(rec.taken.items, base)) try a.print("tb_{s}", .{base}) else base;
        const bench = try recognize.uniqueStem(a, named, &rec.taken);
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
        try c.out.files.append(a, try emit.cellFile(a, c.source, &c.deck, &c.rec, cell, stem, &drawn, &c.place, &c.out.warnings));
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

/// The top level's `.title` text, which names the bench when there is one.
fn title(deck: *const spice.Deck) ?[]const u8 {
    for (deck.code, deck.code_cell) |text, cc| {
        if (cc != 0 or text.len < 7 or !std.ascii.eqlIgnoreCase(text[0..6], ".title")) continue;
        const line = text[6 .. mem.indexOfScalar(u8, text, '\n') orelse text.len];
        if (!std.ascii.isWhitespace(text[6])) continue;
        const t = mem.trim(u8, line, spice.ws);
        if (t.len > 0) return t;
    }
    return null;
}

/// The subckt names `X` cards of `text` call that it does not define, each once (first
/// spelling), in card order: the cells `Converter.initLibs` may find in the project's
/// libraries.
pub fn calls(a: Allocator, text: []const u8) Allocator.Error![]const []const u8 {
    const deck = try spice.parse(a, text);
    var out: ArrayList([]const u8) = .empty;
    for (deck.dev_sub) |sub| {
        if (sub.len == 0 or deck.findCell(sub) != null) continue;
        for (out.items) |x| {
            if (std.ascii.eqlIgnoreCase(x, sub)) break;
        } else try out.append(a, sub);
    }
    return out.items;
}

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
    _ = place;
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

test "a bench placed apart from its subckt refers to it through the library" {
    // Oracle: Schemify's resolution (netlist spec §1): `./cell` beside the file, `lib:cell`
    // at a library's top. AMTemplate's rows put the bench in test/, the cell in schematics/.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const deck = "* rcdiv\n.subckt rcdiv in out gnd\nR1 in out 1k\nR2 out gnd 1k\nC1 out gnd 1p\n.ends\nV1 in 0 DC 1\nX1 in out 0 rcdiv\n.op\n";
    const run = struct {
        fn bench(a_: Allocator, text: []const u8, rows: []const u8) Allocator.Error!Conversion {
            var c: Converter = try .init(testing.allocator, a_, "rcdiv.sp", text);
            defer c.deinit();
            c.place = try .parse(a_, rows);
            while (c.cellsLeft() > 0) try c.step();
            return c.finish();
        }
    }.bench;
    const rows = "schemify 1 project\n  root ../..\n  place *.shbench test\n  place *.shcomp schematics\n\nlib blk path schematics\n";
    const placed = try run(a, deck, rows);
    const tb = for (placed.files.items) |f| {
        if (mem.endsWith(u8, f.name, ".shbench")) break f.bytes;
    } else unreachable;
    try testing.expect(mem.indexOf(u8, tb, " blk:rcdiv\n") != null);
    try testing.expect(mem.indexOf(u8, tb, "./rcdiv") == null);
    // Without a library at schematics/ the cell is unreachable: `./` and a note naming it.
    const unlisted = try run(a, deck, "schemify 1 project\n  place *.shbench test\n");
    var noted = false;
    for (unlisted.warnings.items) |w| noted = noted or mem.indexOf(u8, w, "no `lib … path` names it") != null;
    try testing.expect(noted);
    // No rows: everything beside the netlist, as before.
    const flat = try run(a, deck, "");
    for (flat.files.items) |f| if (mem.endsWith(u8, f.name, ".shbench"))
        try testing.expect(mem.indexOf(u8, f.bytes, " ./rcdiv\n") != null);
}

test "an X of a library cell instantiates it, its parameters flowing in by name" {
    // Oracle: the vendor-kit import (miniproj2): `Xm0 … vnfet w=w l=l` in a subckt with
    // parameters, `lib vkit` holding `vnfet` (pins d g s b, string params). The netlist
    // spec renders `{w}` as the specialized value in every dialect, so no `.param` shim and
    // no generated verbatim leaf may appear.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const deck = ".title tb_nmos_switch\n.lib /k/design_wrapper.lib tt\n.param wn=80n\n" ++
        ".subckt nmos_switch a b g bulk PARAMS: w=80n l=20n\nXm0 a g b bulk vnfet w=w l=l\n.ends nmos_switch\n" ++
        "X1 x y gn vdd nmos_switch w=wn l=20n\nVx x 0 0.4\nVg gn 0 0.8\nVb vdd 0 0.8\nVy y 0 0\n.dc Vx 0 1 0.1\n";
    try testing.expectEqualStrings("vnfet", (try calls(a, deck))[0]);
    const cell = "schemify 1 shprim\n\npin d inout 40 0\npin g inout 40 20\npin s inout 40 40\npin b inout 40 60\n\n" ++
        "param w \"\"\n  kind string\nparam l \"\"\n  kind string\n\nrect -20 -10 20 70\n";
    const lib = (try place.libCell(a, "vkit", "vnfet", cell)).?;
    try testing.expectEqual(recognize.Body{ -20, -10, 40, 70 }, lib.body);
    var c: Converter = try .initLibs(testing.allocator, a, "nmos_switch.spice", deck, &.{lib});
    defer c.deinit();
    while (c.cellsLeft() > 0) try c.step();
    const out = try c.finish();
    var names: ArrayList(u8) = .empty;
    for (out.files.items) |f| try names.print(a, "{s} ", .{f.name});
    try testing.expectEqualStrings("nmos_switch.shcomp tb_nmos_switch.shbench ", names.items);
    const sub = out.files.items[0].bytes;
    try testing.expect(mem.indexOf(u8, sub, " vkit:vnfet\n") != null);
    try testing.expect(mem.indexOf(u8, sub, "\n  name m0\n  w {w}\n  l {l}\n") != null);
    try testing.expect(mem.indexOf(u8, sub, ".param") == null);
    // `w=wn` names a bench `.param`, so `w` passes SPICE text (a string); `l` is a number.
    try testing.expect(mem.indexOf(u8, sub, "param w 80n\n  kind string\nparam l 20n\n\n") != null);
    // An expression over number parameters is one hole Schemify evaluates (miniproj2's
    // tg_switch: `w=w*2` imported as `{{({w})}}*2`, which renders ngspice braces).
    const tg = ".subckt tg a b gn gp bn bp PARAMS: w=80n l=20n\nXmn a gn b bn vnfet w=w l=l\n" ++
        "Xmp b gp a bp vnfet w=w*2 l='l+w/2' nf=2\n.ends\nX1 x y n p 0 vdd tg w=8e-08 l={2*10n}\n";
    var t: Converter = try .initLibs(testing.allocator, a, "tg.sp", tg, &.{lib});
    defer t.deinit();
    while (t.cellsLeft() > 0) try t.step();
    const tg_out = try t.finish();
    const cellt = tg_out.files.items[0].bytes;
    try testing.expect(mem.indexOf(u8, cellt, "param w 80n\nparam l 20n\n\n") != null);
    try testing.expect(mem.indexOf(u8, cellt, "  w {w*2}\n  l {l+w/2}\n") != null);
    try testing.expect(mem.indexOf(u8, tg_out.files.items[1].bytes, "  w 8e-08\n  l 2*10n\n") != null);
    // Card text that names a parameter still gets the shim, in bare form.
    const verbatim = ".subckt r2 a b PARAMS: k=2\nR1 a b {k*1k}\n.ends\nX1 x 0 r2\n";
    const v = try convert(testing.allocator, a, "r2.sp", verbatim);
    try testing.expect(mem.indexOf(u8, v.files.items[0].bytes, "text \".param k={k}\"") != null);
}

test "a bench named like its subckt is tb_<name>" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    // AMTemplate's report: `rcdiv.sp` holding `.subckt rcdiv` wrote `rcdiv_2.shbench`.
    const deck = "* rcdiv\n.subckt rcdiv in out gnd\nR1 in out 1k\nR2 out gnd 1k\nC1 out gnd 1p\n.ends\nV1 in 0 DC 1\nX1 in out 0 rcdiv\n.op\n";
    const out = try convert(testing.allocator, arena.allocator(), "rcdiv.sp", deck);
    var names: [2][]const u8 = undefined;
    for (out.files.items[0..2], &names) |f, *n| n.* = f.name;
    try testing.expectEqualStrings("rcdiv.shcomp", names[0]);
    try testing.expectEqualStrings("tb_rcdiv.shbench", names[1]);
    // No clash: the file's name, as before.
    const rc = try convert(testing.allocator, arena.allocator(), "rc.sp", "* rc\nV1 in 0 1\nR1 in out 1k\nC1 out 0 1n\n.op\n");
    try testing.expectEqualStrings("rc.shbench", rc.files.items[0].name);
}

test "a driver island's net is joined by name on purpose, not counted unwired" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    // AMTemplate's report: the rcdiv import logged "1/2 nets fully wired". The bench's `in`
    // (V1 to X1) is a driver island (engine rule R3: the source apart, joined by name); the
    // cell's `out` (R1, R2, C1) is wired.
    const deck = "* rcdiv\n.subckt rcdiv in out gnd\nR1 in out 1k\nR2 out gnd 1k\nC1 out gnd 1p\n.ends\nV1 in 0 DC 1\nX1 in out 0 rcdiv\n.op\n";
    const out = try convert(testing.allocator, arena.allocator(), "rcdiv.sp", deck);
    try testing.expectEqual(1, out.stats.nets_multi);
    try testing.expectEqual(1, out.stats.nets_wired);
}
