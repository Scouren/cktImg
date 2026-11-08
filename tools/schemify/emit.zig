//! Emit transform: drawn cells → Schemify files (format spec v1) in the writer's
//! canonical form (§2, §4): records in rank order, rank-3 kinds in writer order each
//! sorted by id, a blank line between records of different words, values quoted only when
//! not bare. Only the record kinds below are ever written, so this is a few lines rather
//! than Schemify's general writer.
//!
//! Ids follow the importer rule (format spec §4, `IdRng::for_import`): record `k` of a
//! file draws from FNV-1a 64 of `"<source>#<stem>"` then `k` (little-endian),
//! splitmix64, redrawn on collision.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const mem = std.mem;
const spice = @import("spice.zig");
const recognize = @import("recognize.zig");
const layout = @import("layout.zig");
const Deck = spice.Deck;
const Recognized = recognize.Recognized;
const Drawn = layout.Drawn;
const Place = @import("place.zig").Place;

/// One output file.
pub const OutFile = struct {
    /// File name (`inv.shcomp`), to be written next to the source netlist.
    name: []const u8,
    /// Canonical file bytes.
    bytes: []const u8,
    /// A generated leaf cell (`spice_*` or a stub): an existing file of that name is kept
    /// rather than replaced, since earlier imports into the directory share it.
    shared: bool,
};

/// Crockford base32 digits of ids, in value (and byte) order.
const id_alphabet = "0123456789abcdefghjkmnpqrstvwxyz";
/// Records per file: the sort key keeps 20 bits for the record index.
const records_max = 1 << 20;

/// Canonical position of a record word: rank 1, rank 2, the rank-3 kinds in writer order
/// (sorted by id within), rank 6.
const Slot = enum(u8) { rank1 = 1, rank2, inst, wire, label, port, noconn, code };

/// True when `v` can be written unquoted (format §2).
fn bare(v: []const u8) bool {
    if (v.len == 0 or v[0] == '#' or v[0] == '|') return false;
    for (v) |c| if (c <= 0x20 or c == 0x7f or c == '"' or c == '\\') return false;
    return true;
}

/// Appends one value: bare if legal, else quoted, with `"` `\` LF TAB escaped and other
/// control bytes as `\u{x}`.
pub fn pushValue(out: *ArrayList(u8), a: Allocator, v: []const u8) Allocator.Error!void {
    if (bare(v)) return out.appendSlice(a, v);
    try out.append(a, '"');
    for (v) |c| switch (c) {
        '"' => try out.appendSlice(a, "\\\""),
        '\\' => try out.appendSlice(a, "\\\\"),
        '\n' => try out.appendSlice(a, "\\n"),
        '\t' => try out.appendSlice(a, "\\t"),
        0...8, 0x0b...0x1f, 0x7f => try out.print(a, "\\u{{{x}}}", .{c}),
        else => try out.append(a, c),
    };
    try out.append(a, '"');
}

/// The 6-char id drawn from 64 random bits (low 30 bits, 5 per char, first char lowest).
fn idText(bits: u64) [6]u8 {
    var t: [6]u8 = undefined;
    for (&t, 0..) |*ch, i| ch.* = id_alphabet[@intCast((bits >> @intCast(5 * i)) & 31)];
    return t;
}

/// Bytewise sort value of an id drawn from `bits` (first char most significant).
fn idOrder(bits: u64) u64 {
    var acc: u64 = 0;
    for (0..6) |i| acc = (acc << 5) | ((bits >> @intCast(5 * i)) & 31);
    return acc;
}

/// `IdRng::for_import(key, ordinal)` + `fresh_id`, with the key's hash precomputed: the
/// first draw whose text `taken` does not hold yet (added there).
fn importId(a: Allocator, key: u64, ordinal: u32, taken: *std.StringHashMapUnmanaged(void)) Allocator.Error!u64 {
    var state = spice.fnv1a(key, &mem.toBytes(mem.nativeToLittle(u32, ordinal)));
    for (0..64) |_| {
        state +%= 0x9e37_79b9_7f4a_7c15;
        var z = state;
        z = (z ^ (z >> 30)) *% 0xbf58_476d_1ce4_e5b9;
        z = (z ^ (z >> 27)) *% 0x94d0_49bb_1331_11eb;
        const bits = z ^ (z >> 31);
        const text = idText(bits);
        const gop = try taken.getOrPut(a, &text);
        if (!gop.found_existing) {
            gop.key_ptr.* = try a.dupe(u8, &text);
            return bits;
        }
    }
    unreachable; // 64 taken draws in a 2^30 id space
}

const Rec = struct { key: u64, word: []const u8, text: ArrayList(u8) };

/// Builds one file.
const Writer = struct {
    a: Allocator,
    header: ArrayList(u8) = .empty,
    recs: ArrayList(Rec) = .empty,
    /// FNV-1a of `"<source>#<stem>"`.
    source_key: u64,
    ordinal: u32 = 0,
    taken: std.StringHashMapUnmanaged(void) = .empty,

    fn init(a: Allocator, kind: []const u8, source: []const u8, stem: []const u8) Allocator.Error!Writer {
        var w: Writer = .{ .a = a, .source_key = spice.fnv1a(spice.fnv1a(spice.fnv1a(spice.fnv_offset, source), "#"), stem) };
        try w.header.print(a, "schemify 1 {s}\n", .{kind});
        return w;
    }

    /// A header attribute (call in canonical order: doc, prefix, provenance).
    fn headerAttr(w: *Writer, key: []const u8, v: []const u8) Allocator.Error!void {
        assert(w.recs.items.len == 0);
        try w.header.print(w.a, "  {s} ", .{key});
        try pushValue(&w.header, w.a, v);
        try w.header.append(w.a, '\n');
    }

    fn current(w: *Writer) *ArrayList(u8) {
        return &w.recs.items[w.recs.items.len - 1].text;
    }

    /// Starts a record; rank-3 records draw an id (the first field). Fields follow with
    /// `fields`/`coords`, attribute lines with `attr`.
    fn record(w: *Writer, slot: Slot, word: []const u8, fields_: []const []const u8) Allocator.Error!void {
        assert(w.recs.items.len < records_max);
        var text: ArrayList(u8) = .empty;
        try text.appendSlice(w.a, word);
        var order: u64 = 0;
        if (@backingInt(slot) >= @backingInt(Slot.inst) and slot != .code) {
            const bits = try importId(w.a, w.source_key, w.ordinal, &w.taken);
            w.ordinal += 1;
            order = idOrder(bits);
            try text.print(w.a, " {s}", .{&idText(bits)});
        }
        try text.append(w.a, '\n');
        const key = @as(u64, @backingInt(slot)) << 56 | order << 20 | w.recs.items.len;
        try w.recs.append(w.a, .{ .key = key, .word = word, .text = text });
        try w.fields(fields_);
    }

    /// Integer coordinates (xschem units) as fields of the current record.
    fn coords(w: *Writer, xs: []const i32) Allocator.Error!void {
        const t = w.current();
        assert(t.pop() == '\n');
        for (xs) |v| try t.print(w.a, " {d}", .{v});
        try t.append(w.a, '\n');
    }

    /// Values on the current record's first line.
    fn fields(w: *Writer, values: []const []const u8) Allocator.Error!void {
        const t = w.current();
        assert(t.pop() == '\n');
        assert(mem.indexOfScalar(u8, t.items, '\n') == null); // fields go on the record line
        for (values) |v| {
            try t.append(w.a, ' ');
            try pushValue(t, w.a, v);
        }
        try t.append(w.a, '\n');
    }

    /// An attribute line of the current record.
    fn attr(w: *Writer, key: []const u8, values: []const []const u8) Allocator.Error!void {
        const t = w.current();
        try t.print(w.a, "  {s}", .{key});
        for (values) |v| {
            try t.append(w.a, ' ');
            try pushValue(t, w.a, v);
        }
        try t.append(w.a, '\n');
    }

    /// A verbatim line of the current record.
    fn verbatim(w: *Writer, line: []const u8) Allocator.Error!void {
        assert(mem.indexOfAny(u8, line, "\r\n") == null);
        const t = w.current();
        try t.appendSlice(w.a, if (line.len == 0) "  |" else "  | ");
        try t.appendSlice(w.a, line);
        try t.append(w.a, '\n');
    }

    fn finish(w: *Writer, name: []const u8, shared: bool) Allocator.Error!OutFile {
        const keys = try w.a.alloc(u64, w.recs.items.len);
        for (keys, w.recs.items) |*k, r| k.* = r.key;
        mem.sort(u64, keys, {}, std.sort.asc(u64));
        var out = w.header;
        var prev: []const u8 = "schemify";
        for (keys) |k| {
            const r = &w.recs.items[@intCast(k & (records_max - 1))];
            if (!mem.eql(u8, r.word, prev)) try out.append(w.a, '\n');
            try out.appendSlice(w.a, r.text.items);
            prev = r.word;
        }
        assert(mem.startsWith(u8, out.items, "schemify 1 ") and mem.endsWith(u8, out.items, "\n"));
        return .{ .name = name, .bytes = out.items, .shared = shared };
    }
};

/// Writes deck cell `c` (0: the bench, else a component) as file `stem`, its references
/// as `place` puts the files; a cell it cannot reach adds a note to `warnings`.
pub fn cellFile(a: Allocator, source: []const u8, deck: *const Deck, rec: *const Recognized, c: u32, stem: []const u8, drawn: *const Drawn, place: *const Place, warnings: *ArrayList([]const u8)) Allocator.Error!OutFile {
    const devs = deck.devs(c);
    assert(drawn.x.items.len == devs.len());
    const kind = if (c == 0) "shbench" else "shcomp";
    const file = try a.print("{s}.{s}", .{ stem, kind });
    const refs: Refs = .{ .a = a, .rec = rec, .place = place, .from = file, .warnings = warnings };
    var w: Writer = try .init(a, kind, source, stem);
    if (c > 0) try w.headerAttr("prefix", "X");
    try w.headerAttr("provenance", try a.print("netlist-import {s}", .{source}));
    const params = deck.params(c);
    if (c > 0) {
        const s = recognize.subSymbol(c);
        try symbol(&w, rec, s);
        for (params, rec.numbers(deck, c)) |p, number| {
            if (number) {
                try w.record(.rank1, "param", &.{ p.name, recognize.stripOuter(p.value) });
                continue;
            }
            try w.record(.rank1, "param", &.{ p.name, try recognize.templateExpr(a, recognize.stripOuter(p.value), params) });
            try w.attr("kind", &.{"string"});
        }
        try w.record(.rank1, "impl", &.{ "schematic", "schematic" });
        try graphics(&w, rec, s);
    }
    for (devs.lo..devs.hi, 0..) |d, i| {
        const s = rec.parts.sym.items[d];
        try w.record(.inst, "inst", &.{try refs.of(s)});
        try w.attr("at", &.{ try a.print("{d}", .{drawn.x.items[i]}), try a.print("{d}", .{drawn.y.items[i]}), layout.orient_words[drawn.orient.items[i]] });
        try w.attr("name", &.{try recognize.pinName(a, rec.parts.inst_name.items[d])});
        const o = rec.parts.overrides(@intCast(d));
        for (o.lo..o.hi) |k| try w.attr(rec.parts.over_key.items[k], &.{rec.parts.over_val.items[k]});
    }
    for (drawn.wire.items) |seg| {
        try w.record(.wire, "wire", &.{});
        try w.coords(&seg);
    }
    for (drawn.noconn.items) |p| {
        try w.record(.noconn, "noconn", &.{});
        try w.coords(&p);
    }
    for (drawn.mark.items) |m| {
        const name = try recognize.pinName(a, deck.netName(c, m.net));
        if (m.port) try w.record(.port, "port", &.{}) else try w.record(.label, "label", &.{});
        try w.coords(&m.at);
        try w.fields(&.{ layout.orient_words[m.orient], name });
        if (!m.port and deck.isGlobal(deck.netKey(c, m.net))) try w.attr("global", &.{"true"});
    }
    var has_code = false;
    for (deck.code_cell) |cc| has_code = has_code or cc == c;
    if (c == 0 and has_code) {
        try w.record(.code, "code", &.{ "netlist", "spice" });
        for (deck.code, deck.code_cell) |text, cc| if (cc == c) {
            var lines = mem.splitScalar(u8, text, '\n');
            // `${NAME}` expands in code text (netlist spec §7.1); `$$` is a literal `$`.
            while (lines.next()) |line| try w.verbatim(try mem.replaceOwned(u8, a, line, "$", "$$"));
        };
    } else if (c > 0 and (has_code or rec.shim[c])) {
        // Inside a subckt the text must stay in its definition: one `spice_code` instance
        // per entry, stacked below the drawing (clear of every wire), pin no-connected. When
        // card text kept verbatim names the cell's parameters, the first re-declares them:
        // `.param k={k}` renders each (specialized) value, bare, which every dialect reads.
        var texts: ArrayList([]const u8) = .empty;
        if (rec.shim[c]) {
            var line: ArrayList(u8) = .empty;
            try line.appendSlice(a, ".param");
            for (params) |p| try line.print(a, " {s}={{{s}}}", .{ p.name, p.name });
            try texts.append(a, line.items);
        }
        for (deck.code, deck.code_cell) |text, cc| if (cc == c) try texts.append(a, try recognize.template(a, text, &.{}));
        const s = rec.code_sym;
        const p0 = rec.syms.pins(s)[0];
        const b = drawn.bounds;
        assert(b[0] <= b[2] and b[1] <= b[3]);
        // Left-aligned, 300 units below the drawing, on the 10 grid.
        const x = @divFloor(b[0], 10) * 10;
        var y = @divFloor(b[3] + 300, 10) * 10 + 10;
        for (texts.items, 0..) |text, n| {
            try w.record(.inst, "inst", &.{try refs.of(s)});
            try w.attr("at", &.{ try a.print("{d}", .{x}), try a.print("{d}", .{y}), "R0" });
            try w.attr("name", &.{try a.print("code{d}", .{n})});
            try w.attr("text", &.{text});
            try w.record(.noconn, "noconn", &.{});
            try w.coords(&.{ x + p0.x, y + p0.y });
            y += 60;
        }
    }
    return w.finish(file, false);
}

/// One cell file's references ([`recognize.Symbols.cellref`]), with a note per cell it
/// cannot reach.
const Refs = struct {
    a: Allocator,
    rec: *const Recognized,
    place: *const Place,
    from: []const u8,
    warnings: *ArrayList([]const u8),

    fn of(r: *const Refs, s: u32) Allocator.Error![]const u8 {
        if (try r.rec.syms.cellref(r.a, s, r.place, r.from)) |ref| return ref;
        const stem = r.rec.syms.stem.items[s];
        const note = try r.a.print("{s}: `place` puts {s} in another directory and no `lib … path` names it; `./{s}` will not resolve (add a lib for that directory)", .{ r.from, stem, stem });
        for (r.warnings.items) |w| {
            if (mem.eql(u8, w, note)) break;
        } else try r.warnings.append(r.a, note);
        return r.a.print("./{s}", .{stem});
    }
};

/// Writes generated leaf symbol `s` (`.shprim`): its pins, one string parameter and a
/// SPICE impl that re-emits the card (`{name} {pins} {args}`, or the leaf's own template),
/// or for the code leaf the text itself (`{text}`).
pub fn leafFile(a: Allocator, source: []const u8, rec: *const Recognized, s: u32) Allocator.Error!OutFile {
    const stem = rec.syms.stem.items[s];
    const own = rec.syms.format.items[s];
    const code = s == rec.code_sym;
    const doc = if (code) "SPICE text kept inside a subckt definition (netlist import)" else "SPICE card re-emitted verbatim (netlist import)";
    const param = if (code) "text" else "args";
    const format = if (code) "{text}" else if (own.len == 0) "{name} {pins} {args}" else own;
    var w: Writer = try .init(a, "shprim", source, stem);
    try w.headerAttr("doc", doc);
    try w.headerAttr("provenance", try a.print("netlist-import {s}", .{source}));
    try symbol(&w, rec, s);
    try w.record(.rank1, "param", &.{ param, try recognize.template(a, rec.syms.args_default.items[s], &.{}) });
    try w.attr("kind", &.{"string"});
    try w.record(.rank1, "impl", &.{ "spice", "spice" });
    try w.attr("format", &.{ "spice", format });
    try graphics(&w, rec, s);
    return w.finish(try a.print("{s}.shprim", .{stem}), true);
}

/// Rank 1 pins of symbol `s`.
fn symbol(w: *Writer, rec: *const Recognized, s: u32) Allocator.Error!void {
    for (rec.syms.pins(s)) |p| {
        try w.record(.rank1, "pin", &.{ p.name, @tagName(p.dir) });
        try w.coords(&.{ p.x, p.y });
    }
}

fn lineRec(w: *Writer, v: [4]i32) Allocator.Error!void {
    try w.record(.rank2, "line", &.{});
    try w.coords(&v);
}

/// Rank 2 drawing of symbol `s`: the family's glyph, pin leads, name and cell text.
fn graphics(w: *Writer, rec: *const Recognized, s: u32) Allocator.Error!void {
    const b = rec.syms.body.items[s];
    switch (rec.syms.family.items[s]) {
        .two => {
            try lineRec(w, .{ 0, -30, 0, -20 });
            try lineRec(w, .{ 0, 20, 0, 30 });
            try w.record(.rank2, "rect", &.{});
            try w.coords(&.{ -10, -20, 10, 20 });
        },
        .box => {
            // The box 20 inside the body, a lead from each pin to its side.
            const r = [4]i32{ b[0] + 20, b[1] + 20, b[2] - 20, b[3] - 20 };
            assert(r[0] < r[2] and r[1] < r[3]); // a box body is at least 120 x 80
            try w.record(.rank2, "rect", &.{});
            try w.coords(&r);
            for (rec.syms.pins(s)) |p| {
                const edge: [2]i32 = if (p.x == b[0] or p.x == b[2])
                    .{ if (p.x == b[0]) r[0] else r[2], p.y }
                else
                    .{ p.x, if (p.y == b[1]) r[1] else r[3] };
                try lineRec(w, .{ p.x, p.y, edge[0], edge[1] });
            }
        },
        .vcxs, .vsw, .tline => {
            const inner = @max(b[2], -b[0]) - 20;
            const top = @min(b[1], -10) - 10;
            const bot = @max(b[3], 10) + 10;
            try w.record(.rank2, "rect", &.{});
            try w.coords(&.{ -inner, top, inner, bot });
            for (rec.syms.pins(s)) |p| {
                const edge: i32 = if (p.x < 0) -inner else if (p.x > 0) inner else 0;
                if (edge != p.x)
                    try lineRec(w, .{ p.x, p.y, edge, p.y })
                else if (p.y != 0 and (p.y < top or p.y > bot))
                    try lineRec(w, .{ p.x, p.y, p.x, if (p.y < 0) top else bot });
            }
        },
        .nmos, .pmos, .npn, .pnp => {
            for ([_][4]i32{
                .{ -20, 0, -10, 0 }, .{ -10, -20, -10, 20 }, .{ 0, -20, 0, 20 },  .{ 0, -20, 20, -20 },
                .{ 0, 20, 20, 20 },  .{ 20, -30, 20, -20 },  .{ 20, 20, 20, 30 },
            }) |v| try lineRec(w, v);
            if (rec.syms.pins(s).len == 4) try lineRec(w, .{ 0, 0, 20, 0 });
        },
    }
    for ([_]struct { i32, []const u8 }{ .{ b[1] - 20, "{name}" }, .{ b[3] + 10, "{cell}" } }) |t| {
        try w.record(.rank2, "stext", &.{});
        try w.coords(&.{ b[0], t[0] });
        try w.fields(&.{ "R0", t[1] });
    }
}

const testing = std.testing;

test "values quote only when needed" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_][2][]const u8{
        .{ "nfet_01v8", "nfet_01v8" },                                    .{ "{name}", "{name}" },
        .{ "", "\"\"" },                                                  .{ "#1", "\"#1\"" },
        .{ "a b", "\"a b\"" },                                            .{ "say \"hi\"\\", "\"say \\\"hi\\\"\\\\\"" },
        .{ "l1\nl2\tx\r\x00\x7f", "\"l1\\nl2\\tx\\u{d}\\u{0}\\u{7f}\"" },
    };
    for (cases) |c| {
        var out: ArrayList(u8) = .empty;
        try pushValue(&out, a, c[0]);
        try testing.expectEqualStrings(c[1], out.items);
    }
}

test "ids sort like their text" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var taken: std.StringHashMapUnmanaged(void) = .empty;
    const key = spice.fnv1a(spice.fnv_offset, "k");
    const x = try importId(a, key, 0, &taken);
    const y = try importId(a, key, 1, &taken);
    try testing.expect(!mem.eql(u8, &idText(x), &idText(y)));
    try testing.expectEqual(mem.lessThan(u8, &idText(x), &idText(y)), idOrder(x) < idOrder(y));
    const again = try importId(a, key, 0, &taken);
    try testing.expect(!mem.eql(u8, &idText(again), &idText(x))); // a taken id is redrawn
}
