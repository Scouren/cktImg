//! Parse transform: SPICE netlist text → `Deck` tables.
//!
//! Subset (the cards ngspice and xschem netlists use): `*` comments (`*.PININFO` and, in a
//! `.subckt`, cktImg's `*@ left|right|top|bottom <ports>` block-side directives read; its
//! other `*@` directives, the grouping hints among them, kept for the engine),
//! `;` and whitespace-delimited `$` inline comments, `+` continuations, `.control` …
//! `.endc` kept as one opaque text block, `.subckt`/`.ends` (nested definitions are
//! hoisted), `.global`, `.param` (inside a subckt: the cell's parameters), `.end`.
//! Element cards are split into nodes and the verbatim rest (`N`/`P`/`Y` like `X`: nodes,
//! then the model; XSPICE `A` by `xspice`; an `X` may have no nodes); everything else
//! (`.model`, `.include`, analyses, `K` couplings, unsupported element letters) is kept as
//! code text of the cell it appears in, in file order. Case is folded for matching only;
//! first spellings are kept. The first line is not a title (xschem and Schemify netlists
//! start with a comment).
//!
//! Memory: everything is allocated from the caller's arena and borrows `text`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const mem = std.mem;
const ascii = std.ascii;

/// Largest accepted input (the ABI's `fs_write` data cap).
pub const text_max: usize = 64 << 20;
/// Cells per deck (top level included).
pub const cells_max = 4096;
/// Element cards per deck.
pub const devices_max = 1 << 20;
/// Nets per cell.
pub const nets_max = std.math.maxInt(u16) - 1;
/// `Deck.port_rank` of a port no `*@` directive names.
pub const rank_none = std.math.maxInt(u16);

/// ASCII whitespace, what the parser splits on.
pub const ws = " \t\r\n\x0b\x0c";

/// Port direction (`*.PININFO` `I`/`O`/`B`, else guessed from the name). `@tagName` is
/// the format spec's pin `dir` word.
pub const Dir = enum(u8) { in, out, inout };

/// Side of a subckt's block symbol a port sits on: cktImg's `*@` directive, or `auto`.
pub const Side = enum(u8) { auto, left, right, top, bottom };

/// Rows `lo..hi` of a CSR table.
pub const Range = struct {
    lo: u32,
    hi: u32,

    pub fn len(r: Range) u32 {
        return r.hi - r.lo;
    }
};

pub const Model = struct { name: []const u8, kind: []const u8 };
pub const PinInfo = struct { key: []const u8, dir: Dir };
/// A subckt parameter: its name and default text, verbatim (`1u`, `{2*k}`, `'w/2'`).
pub const Param = struct { name: []const u8, value: []const u8 };

/// String → dense id, in first-intern order. The key is copied.
pub const Interner = struct {
    map: std.StringHashMapUnmanaged(u32) = .empty,

    pub fn get(self: *const Interner, key: []const u8) ?u32 {
        return self.map.get(key);
    }

    /// Id of `key`, interning it first if new; the flag tells whether it was new.
    pub fn intern(self: *Interner, a: Allocator, key: []const u8) Allocator.Error!struct { u32, bool } {
        const gop = try self.map.getOrPut(a, key);
        if (gop.found_existing) return .{ gop.value_ptr.*, false };
        gop.key_ptr.* = try a.dupe(u8, key);
        gop.value_ptr.* = self.map.count() - 1;
        return .{ gop.value_ptr.*, true };
    }
};

/// FNV-1a 64 offset basis: the state `fnv1a` starts from.
pub const fnv_offset: u64 = 0xcbf2_9ce4_8422_2325;

/// FNV-1a 64 of `bytes`, continuing from state `h` (`fnv_offset` for a fresh hash).
pub fn fnv1a(h: u64, bytes: []const u8) u64 {
    var s = h;
    for (bytes) |b| s = (s ^ b) *% 0x0000_0100_0000_01b3;
    return s;
}

/// Parsed netlist. Cell 0 is the top level; devices and nets are grouped by cell (CSR
/// `*_start`, `cells + 1` entries) and net ids in `dev_net`/`port_net` are cell-local.
pub const Deck = struct {
    /// Subckt names as written; `""` for the top level.
    cell_name: []const []const u8,
    port_start: []const u32,
    /// Port nets in `.subckt` order.
    port_net: []const u32,
    /// Per port: the block side a `*@` directive put it on.
    port_side: []const Side,
    /// Per port: its place among its definition's `*@` names, `rank_none` when unnamed.
    port_rank: []const u16,
    param_start: []const u32,
    /// Subckt parameters (`.subckt … k=v` and in-body `.param`).
    params_: []const Param,
    net_start: []const u32,
    /// Lowercase net names, grouped by cell.
    net_key: []const []const u8,
    dev_start: []const u32,
    /// Element names as written (`M1`, `Xdut`).
    dev_name: []const []const u8,
    /// 1-based source line of the card.
    dev_line: []const u32,
    dev_net_start: []const u32,
    /// Node nets in card order (cell-local ids).
    dev_net: []const u32,
    /// Subckt name of an `X` card, empty otherwise.
    dev_sub: []const []const u8,
    /// Text after the nodes (after the subckt name for `X`), verbatim; for an XSPICE `A`
    /// card everything after its name (`xspice` splits it).
    dev_rest: []const []const u8,
    /// Statements kept for the netlist, with their original line breaks, in file order.
    code: []const []const u8,
    /// Cell each `code` entry was written in.
    code_cell: []const u16,
    /// cktImg's `*@` directives other than block sides (the grouping hints the engine
    /// reads with `hints.read`), as written, in file order; with the cell and the 1-based
    /// line of each.
    directive: []const []const u8,
    directive_cell: []const u16,
    directive_line: []const u32,
    /// `.global` names, lowercase.
    globals: []const []const u8,
    models: []const Model,
    /// `*.PININFO` directions; the last entry wins.
    pininfo: []const PinInfo,
    /// Lowercase net names of the whole deck; `spelled[id]` is the first spelling.
    spelling: Interner,
    spelled: []const []const u8,
    /// Lines kept or dropped with a reason, for the import log.
    warnings: []const []const u8,

    pub fn cells(d: *const Deck) u32 {
        return @intCast(d.cell_name.len);
    }
    pub fn devs(d: *const Deck, c: u32) Range {
        return .{ .lo = d.dev_start[c], .hi = d.dev_start[c + 1] };
    }
    pub fn netCount(d: *const Deck, c: u32) u32 {
        return d.net_start[c + 1] - d.net_start[c];
    }
    pub fn netKey(d: *const Deck, c: u32, n: u32) []const u8 {
        return d.net_key[d.net_start[c] + n];
    }
    /// Display spelling of local net `n` of cell `c` (its first spelling in the deck).
    pub fn netName(d: *const Deck, c: u32, n: u32) []const u8 {
        const key = d.netKey(c, n);
        return if (d.spelling.get(key)) |id| d.spelled[id] else key;
    }
    pub fn pinInfo(d: *const Deck, key: []const u8) ?Dir {
        var i = d.pininfo.len;
        while (i > 0) {
            i -= 1;
            if (mem.eql(u8, d.pininfo[i].key, key)) return d.pininfo[i].dir;
        }
        return null;
    }
    pub fn netsOf(d: *const Deck, dev: u32) []const u32 {
        return d.dev_net[d.dev_net_start[dev]..d.dev_net_start[dev + 1]];
    }
    pub fn portRange(d: *const Deck, c: u32) Range {
        return .{ .lo = d.port_start[c], .hi = d.port_start[c + 1] };
    }
    pub fn ports(d: *const Deck, c: u32) []const u32 {
        return d.port_net[d.port_start[c]..d.port_start[c + 1]];
    }
    pub fn params(d: *const Deck, c: u32) []const Param {
        return d.params_[d.param_start[c]..d.param_start[c + 1]];
    }
    /// Lowercase type of `.model` `name` (case-insensitive; the first card of that name).
    pub fn modelKind(d: *const Deck, name: []const u8) ?[]const u8 {
        return modelIn(d.models, name);
    }
    /// Cell defined as subckt `name` (case-insensitive); never the top level.
    pub fn findCell(d: *const Deck, name: []const u8) ?u32 {
        return cellIn(d.cell_name, name);
    }
    pub fn isGlobal(d: *const Deck, key: []const u8) bool {
        for (d.globals) |g| if (mem.eql(u8, g, key)) return true;
        return false;
    }
};

fn modelIn(models: []const Model, name: []const u8) ?[]const u8 {
    for (models) |m| if (ascii.eqlIgnoreCase(m.name, name)) return m.kind;
    return null;
}

fn cellIn(names: []const []const u8, name: []const u8) ?u32 {
    for (names[1..], 1..) |n, c| if (ascii.eqlIgnoreCase(n, name)) return @intCast(c);
    return null;
}

/// Parses `text`. Never fails but on memory: an unusable card becomes a warning and code
/// text, so nothing is silently dropped. Cost: O(n) expected.
pub fn parse(a: Allocator, text: []const u8) Allocator.Error!Deck {
    assert(text.len <= text_max);
    var b: Builder = .{ .a = a };
    _ = try b.newCell("");
    const sts = try statements(&b, text);
    for (sts) |*st| if (!try b.statement(st)) break;
    if (b.stack.items.len > 1)
        try b.warnings.append(a, try a.print("{d} unterminated .subckt", .{b.stack.items.len - 1}));
    const deck = try b.finish();
    assert(deck.dev_start.len == deck.cells() + 1);
    assert(deck.net_start.len == deck.cells() + 1);
    return deck;
}

/// One logical statement: continuation lines joined with a space for parsing, the
/// original lines kept for code text.
const Stmt = struct { line: u32, text: ArrayList(u8), raw: ArrayList(u8) };

fn stmt(a: Allocator, line: u32, text: []const u8, raw: []const u8) Allocator.Error!Stmt {
    var st: Stmt = .{ .line = line, .text = .empty, .raw = .empty };
    try st.text.appendSlice(a, text);
    try st.raw.appendSlice(a, raw);
    return st;
}

/// Splits `text` into statements: comments dropped (`*.PININFO` recorded), inline
/// comments cut, `+` lines joined, a `.control` block as one statement.
fn statements(b: *Builder, text: []const u8) Allocator.Error![]Stmt {
    const a = b.a;
    var out: ArrayList(Stmt) = .empty;
    var control: ?Stmt = null;
    var lines = mem.splitScalar(u8, text, '\n');
    var line_no: u32 = 0;
    while (lines.next()) |full| {
        if (lines.index == null and full.len == 0) break;
        line_no +|= 1;
        const raw = mem.trimEnd(u8, full, ws);
        const line = mem.trim(u8, full, ws);
        if (control) |*block| {
            try block.raw.append(a, '\n');
            try block.raw.appendSlice(a, raw);
            if (ascii.eqlIgnoreCase(firstWord(line), ".endc")) {
                try out.append(a, block.*);
                control = null;
            }
            continue;
        }
        if (line.len == 0) continue;
        if (mem.startsWith(u8, line, "*@")) {
            // cktImg's block-side directive: a statement of its own, read in its cell.
            try out.append(a, try stmt(a, line_no, line, raw));
            continue;
        }
        if (line[0] == '*') {
            try pininfo(b, line[1..]);
            continue;
        }
        if (line[0] == '+') {
            // A comment between a card and its continuation is transparent, a directive too.
            var k = out.items.len;
            const prev: ?*Stmt = while (k > 0) {
                k -= 1;
                if (!mem.startsWith(u8, out.items[k].text.items, "*@")) break &out.items[k];
            } else null;
            if (prev != null and prev.?.text.items.len > 0) {
                try prev.?.text.append(a, ' ');
                try prev.?.text.appendSlice(a, mem.trimStart(u8, cutComment(line[1..]), ws));
                try prev.?.raw.append(a, '\n');
                try prev.?.raw.appendSlice(a, raw);
            } else try b.warn(line_no, "continuation without a card, dropped", .{});
            continue;
        }
        if (ascii.eqlIgnoreCase(firstWord(line), ".control")) {
            control = try stmt(a, line_no, "", raw);
            continue;
        }
        try out.append(a, try stmt(a, line_no, cutComment(line), raw));
    }
    if (control) |block| {
        try b.warn(block.line, "unterminated .control block", .{});
        try out.append(a, block);
    }
    return out.items;
}

/// Records `*.PININFO a:I b:O c:B` directions (`c` is the comment text after `*`).
fn pininfo(b: *Builder, c: []const u8) Allocator.Error!void {
    const lower = try ascii.allocLowerString(b.a, mem.trim(u8, c, ws));
    if (!mem.startsWith(u8, lower, ".pininfo")) return;
    var toks = mem.tokenizeAny(u8, lower[".pininfo".len..], ws);
    while (toks.next()) |tok| {
        const colon = mem.lastIndexOfScalar(u8, tok, ':') orelse continue;
        const d = tok[colon + 1 ..];
        const dir: Dir = if (mem.eql(u8, d, "i")) .in else if (mem.eql(u8, d, "o")) .out else if (mem.eql(u8, d, "b") or mem.eql(u8, d, "io")) .inout else continue;
        try b.pininfo.append(b.a, .{ .key = tok[0..colon], .dir = dir });
    }
}

fn firstWord(line: []const u8) []const u8 {
    var it = mem.tokenizeAny(u8, line, ws);
    return it.next() orelse "";
}

fn isSpace(c: u8) bool {
    return mem.indexOfScalar(u8, ws, c) != null;
}

/// Cuts an inline comment: `;`, or `$` with whitespace (or the line edge) on both sides,
/// outside quotes.
fn cutComment(s: []const u8) []const u8 {
    var quote: u8 = 0;
    for (s, 0..) |c, i| {
        if (quote != 0) {
            if (c == quote) quote = 0;
            continue;
        }
        switch (c) {
            '\'', '"' => quote = c,
            ';' => return mem.trimEnd(u8, s[0..i], ws),
            '$' => {
                const before = i == 0 or isSpace(s[i - 1]);
                const after = i + 1 == s.len or isSpace(s[i + 1]);
                if (before and after) return mem.trimEnd(u8, s[0..i], ws);
            },
            else => {},
        }
    }
    return mem.trimEnd(u8, s, ws);
}

/// One token: its text (`k = v` glued to `k=v`) and the byte offset where it starts.
pub const Tok = struct { text: []const u8, at: usize };

/// Splits on whitespace outside `'…'`, `"…"`, `{…}` and `(…)`, gluing `k = v`.
pub fn tokenize(a: Allocator, s: []const u8) Allocator.Error![]Tok {
    var raw: ArrayList(Tok) = .empty;
    var start: ?usize = null;
    var quote: u8 = 0;
    var brace: u32 = 0;
    var paren: u32 = 0;
    for (s, 0..) |c, i| {
        if (quote != 0) {
            if (c == quote) quote = 0;
            continue;
        }
        if (isSpace(c) and brace == 0 and paren == 0) {
            if (start) |at| try raw.append(a, .{ .text = s[at..i], .at = at });
            start = null;
            continue;
        }
        if (start == null) start = i;
        switch (c) {
            '\'', '"' => quote = c,
            '{' => brace += 1,
            '}' => brace -|= 1,
            '(' => paren += 1,
            ')' => paren -|= 1,
            else => {},
        }
    }
    if (start) |at| try raw.append(a, .{ .text = s[at..], .at = at });

    const r = raw.items;
    var out: ArrayList(Tok) = try .initCapacity(a, r.len);
    var i: usize = 0;
    while (i < r.len) {
        const t = r[i].text;
        const next: ?[]const u8 = if (i + 1 < r.len) r[i + 1].text else null;
        const last: ?*Tok = if (out.items.len > 0) &out.items[out.items.len - 1] else null;
        if (last != null and mem.eql(u8, t, "=")) {
            last.?.text = try mem.concat(a, u8, &.{ last.?.text, "=", next orelse "" });
            i += 2;
        } else if (last != null and t[0] == '=' and !mem.endsWith(u8, last.?.text, "=")) {
            last.?.text = try mem.concat(a, u8, &.{ last.?.text, t });
            i += 1;
        } else if (mem.endsWith(u8, t, "=") and next != null and keyOf(t) != null) {
            try out.append(a, .{ .text = try mem.concat(a, u8, &.{ t, next.? }), .at = r[i].at });
            i += 2;
        } else {
            try out.append(a, r[i]);
            i += 1;
        }
    }
    return out.items;
}

/// The `k` of a `k=v` token: non-empty, no quote, brace, paren or bracket.
pub fn keyOf(t: []const u8) ?[]const u8 {
    const eq = mem.indexOfScalar(u8, t, '=') orelse return null;
    const key = t[0..eq];
    if (key.len == 0 or mem.indexOfAny(u8, key, "'\"{()[") != null) return null;
    return key;
}

/// An XSPICE `A` card's text after its name, split by `xspice`.
pub const Xspice = struct {
    /// Byte ranges of the node words, in card order.
    nodes: []const Range,
    /// Byte offset of the model name; the model and everything after it is the tail.
    model: u32,
    /// The text before the model is only the nodes, space-separated, so `{pins}` re-emits it.
    plain: bool,
};

/// Splits XSPICE `A` card text after the name (`[a ~b] %vd(c d) null out model`). A word
/// is a run of anything but whitespace and `[ ] ( ) ~`; a `%…` word is a port modifier
/// (the word after `%vnam` names a source, not a node), `null` an unconnected port, a
/// `k=v` word a parameter; the model is the last other word outside brackets, and the
/// other words before it are the nodes. Null without a model or a node (kept as code).
pub fn xspice(a: Allocator, text: []const u8) Allocator.Error!?Xspice {
    const Word = struct { span: Range, plain: bool, depth: u32 };
    var words: ArrayList(Word) = .empty;
    var depth: u32 = 0;
    var start: ?usize = null;
    var names_source = false;
    for (0..text.len + 1) |i| {
        const ch: u8 = if (i < text.len) text[i] else ' ';
        if (!isSpace(ch) and mem.indexOfScalar(u8, "[]()~", ch) == null) {
            if (start == null) start = i;
            continue;
        }
        if (start) |s| {
            const w = text[s..i];
            const plain = !names_source and w[0] != '%' and !ascii.eqlIgnoreCase(w, "null") and mem.indexOfScalar(u8, w, '=') == null;
            names_source = ascii.eqlIgnoreCase(w, "%vnam");
            try words.append(a, .{ .span = .{ .lo = @intCast(s), .hi = @intCast(i) }, .plain = plain, .depth = depth });
            start = null;
        }
        switch (ch) {
            '[' => depth += 1,
            ']' => depth -|= 1,
            else => {},
        }
    }
    const ws_ = words.items;
    const m = for (0..ws_.len) |k| {
        const w = ws_[ws_.len - 1 - k];
        if (w.plain and w.depth == 0) break ws_.len - 1 - k;
    } else return null;
    var nodes: ArrayList(Range) = .empty;
    var plain = true;
    for (ws_[0..m]) |w| {
        if (w.plain) try nodes.append(a, w.span) else plain = false;
    }
    if (nodes.items.len == 0) return null;
    const model = ws_[m].span.lo;
    plain = plain and mem.indexOfAny(u8, text[0..model], "[]()~") == null;
    for (nodes.items) |r| assert(r.hi <= model);
    return .{ .nodes = nodes.items, .model = model, .plain = plain };
}

/// Words that make an `E`/`G` card a two-node behavioural source.
const behavioural = [_][]const u8{ "value", "vol", "cur", "table", "laplace", "poly", "freq", "and", "or", "nand", "nor" };

const SideOf = struct { net: u32, side: Side };

/// Parser state while statements stream in: the cell stack and global net ids
/// (`"<cell>/<lowercase name>"` → id), renumbered per cell by `finish`.
const Builder = struct {
    a: Allocator,
    cell_name: ArrayList([]const u8) = .empty,
    code: ArrayList([]const u8) = .empty,
    code_cell: ArrayList(u16) = .empty,
    directive_text: ArrayList([]const u8) = .empty,
    directive_cell: ArrayList(u16) = .empty,
    directive_line: ArrayList(u32) = .empty,
    globals: ArrayList([]const u8) = .empty,
    models: ArrayList(Model) = .empty,
    pininfo: ArrayList(PinInfo) = .empty,
    spelling: Interner = .{},
    spelled: ArrayList([]const u8) = .empty,
    warnings: ArrayList([]const u8) = .empty,
    // Device rows in file order before grouping by cell.
    row_cell: ArrayList(u16) = .empty,
    row_name: ArrayList([]const u8) = .empty,
    row_line: ArrayList(u32) = .empty,
    row_nets: ArrayList([]const u32) = .empty,
    row_sub: ArrayList([]const u8) = .empty,
    row_rest: ArrayList([]const u8) = .empty,
    net_ids: Interner = .{},
    net_cell: ArrayList(u16) = .empty,
    net_keys: ArrayList([]const u8) = .empty,
    ports: ArrayList(ArrayList(u32)) = .empty,
    /// Per cell, `*@` directive sides of its ports, in directive order, one per port.
    sides: ArrayList(ArrayList(SideOf)) = .empty,
    params: ArrayList(ArrayList(Param)) = .empty,
    stack: ArrayList(u16) = .empty,

    fn newCell(b: *Builder, name: []const u8) Allocator.Error!u16 {
        const c = b.cell_name.items.len;
        assert(c < cells_max);
        try b.cell_name.append(b.a, name);
        try b.ports.append(b.a, .empty);
        try b.sides.append(b.a, .empty);
        try b.params.append(b.a, .empty);
        try b.stack.append(b.a, @intCast(c));
        return @intCast(c);
    }

    fn cell(b: *const Builder) u16 {
        return b.stack.items[b.stack.items.len - 1];
    }

    fn warn(b: *Builder, line: u32, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
        const what = try b.a.print(fmt, args);
        try b.warnings.append(b.a, try b.a.print("line {d}: {s}", .{ line, what }));
    }

    /// Records `name`'s spelling unless the deck has one for it already.
    fn spell(b: *Builder, name: []const u8) Allocator.Error!void {
        _, const fresh = try b.spelling.intern(b.a, try ascii.allocLowerString(b.a, name));
        if (fresh) try b.spelled.append(b.a, name);
        assert(b.spelled.items.len == b.spelling.map.count());
    }

    fn net(b: *Builder, c: u16, name: []const u8) Allocator.Error!u32 {
        const key = try ascii.allocLowerString(b.a, name);
        const id, const fresh = try b.net_ids.intern(b.a, try b.a.print("{d}/{s}", .{ c, key }));
        if (fresh) {
            try b.spell(name);
            try b.net_cell.append(b.a, c);
            try b.net_keys.append(b.a, key);
        }
        assert(b.net_keys.items.len == b.net_ids.map.count());
        return id;
    }

    /// Sets parameter `k` of cell `c`; a repeated name (case-insensitive) takes the later
    /// value, as SPICE reads it, so the cell declares each parameter once.
    fn param(b: *Builder, line: u32, c: u16, k: []const u8, v: []const u8) Allocator.Error!void {
        const list = &b.params.items[c];
        for (list.items) |*p| if (ascii.eqlIgnoreCase(p.name, k)) {
            try b.warn(line, "parameter {s} set again; the later value is kept", .{k});
            p.value = v;
            return;
        };
        try list.append(b.a, .{ .name = k, .value = v });
    }

    /// Keeps `st` as code text of the current cell (netlisted where it was written).
    fn keep(b: *Builder, st: *const Stmt) Allocator.Error!void {
        try b.code.append(b.a, st.raw.items);
        try b.code_cell.append(b.a, b.cell());
    }

    /// A `*@ left|right|top|bottom <ports>` directive (cktImg's block shape): records the
    /// side of each named port of the current subckt, in directive order; a port named
    /// again takes its later side and place. Names that are no port and sides outside a
    /// subckt are ignored, as cktImg ignores them. Any other verb is kept for the engine.
    fn directive(b: *Builder, st: *const Stmt) Allocator.Error!void {
        const c = b.cell();
        var words = mem.tokenizeAny(u8, st.text.items[2..], ws ++ ",");
        const verb = words.next() orelse return;
        const side: Side = inline for (.{ Side.left, Side.right, Side.top, Side.bottom }) |s| {
            if (ascii.eqlIgnoreCase(verb, @tagName(s))) break s;
        } else {
            try b.directive_text.append(b.a, st.text.items);
            try b.directive_cell.append(b.a, c);
            try b.directive_line.append(b.a, st.line);
            return;
        };
        if (c == 0) return;
        while (words.next()) |w| {
            const key = try b.a.print("{d}/{s}", .{ c, try ascii.allocLowerString(b.a, w) });
            const id = b.net_ids.get(key) orelse continue;
            if (mem.indexOfScalar(u32, b.ports.items[c].items, id) == null) continue;
            const sides = &b.sides.items[c];
            var k: usize = 0;
            while (k < sides.items.len) {
                if (sides.items[k].net == id) _ = sides.orderedRemove(k) else k += 1;
            }
            try sides.append(b.a, .{ .net = id, .side = side });
        }
        assert(b.sides.items[c].items.len <= b.ports.items[c].items.len);
    }

    /// Consumes one statement; false stops parsing (`.end`).
    fn statement(b: *Builder, st: *const Stmt) Allocator.Error!bool {
        const text = st.text.items;
        if (mem.startsWith(u8, text, "*@")) {
            try b.directive(st);
            return true;
        }
        if (text.len == 0) {
            try b.keep(st); // a `.control` block (its text lives in `raw`)
            return true;
        }
        const toks = try tokenize(b.a, text);
        if (toks.len == 0) return true;
        const head = try ascii.allocLowerString(b.a, toks[0].text);
        if (head[0] == '.') return b.dotCard(st, head, toks);
        if (!ascii.isAlphabetic(head[0])) {
            try b.warn(st.line, "unrecognized card kept as code", .{});
            try b.keep(st);
            return true;
        }
        try b.element(st, head[0], toks);
        return true;
    }

    fn dotCard(b: *Builder, st: *const Stmt, head: []const u8, toks: []const Tok) Allocator.Error!bool {
        if (mem.eql(u8, head, ".end")) return false;
        if (mem.eql(u8, head, ".subckt")) {
            if (toks.len < 2) {
                try b.warn(st.line, ".subckt without a name, dropped", .{});
                return true;
            }
            const name = toks[1].text;
            if (cellIn(b.cell_name.items, name) != null)
                try b.warn(st.line, "duplicate .subckt name; calls use the first definition", .{});
            if (b.cell() != 0) try b.warn(st.line, "nested .subckt hoisted to the top level", .{});
            const c = try b.newCell(name);
            var in_params = false;
            for (toks[2..]) |t| {
                if (ascii.eqlIgnoreCase(t.text, "params:")) {
                    in_params = true;
                } else if (keyOf(t.text)) |k| {
                    in_params = true;
                    try b.param(st.line, c, k, t.text[k.len + 1 ..]);
                } else if (in_params) {
                    try b.warn(st.line, "stray token {s} in .subckt", .{t.text});
                } else {
                    const n = try b.net(c, t.text);
                    const ports = &b.ports.items[c];
                    if (mem.indexOfScalar(u32, ports.items, n) != null)
                        try b.warn(st.line, "duplicate port {s}", .{t.text})
                    else
                        try ports.append(b.a, n);
                }
            }
        } else if (mem.eql(u8, head, ".ends")) {
            if (b.stack.items.len > 1) _ = b.stack.pop() else try b.warn(st.line, ".ends without .subckt, dropped", .{});
        } else if (mem.eql(u8, head, ".global")) {
            for (toks[1..]) |t| {
                const key = try ascii.allocLowerString(b.a, t.text);
                try b.spell(t.text);
                for (b.globals.items) |g| {
                    if (mem.eql(u8, g, key)) break;
                } else try b.globals.append(b.a, key);
            }
        } else if ((mem.eql(u8, head, ".param") or mem.eql(u8, head, ".params")) and b.cell() != 0) {
            for (toks[1..]) |t| {
                if (keyOf(t.text)) |k|
                    try b.param(st.line, b.cell(), k, t.text[k.len + 1 ..])
                else
                    try b.warn(st.line, "stray token {s} in .param", .{t.text});
            }
        } else {
            if (mem.eql(u8, head, ".model") and toks.len >= 3) {
                const kind = toks[2].text[0 .. mem.indexOfScalar(u8, toks[2].text, '(') orelse toks[2].text.len];
                try b.models.append(b.a, .{
                    .name = try ascii.allocLowerString(b.a, toks[1].text),
                    .kind = try ascii.allocLowerString(b.a, kind),
                });
            }
            try b.keep(st);
        }
        return true;
    }

    /// Node count of an element card, or null for a card kept as code text.
    fn nodeCount(b: *const Builder, letter: u8, toks: []const Tok) ?usize {
        const models = b.models.items;
        const isModel = struct {
            fn f(ms: []const Model, ts: []const Tok, i: usize) bool {
                return i < ts.len and modelIn(ms, ts[i].text) != null;
            }
        }.f;
        return switch (letter) {
            'r', 'c', 'l', 'd', 'v', 'i', 'f', 'h', 'b', 'w' => 2,
            'e', 'g' => {
                if (toks.len <= 3) return 4;
                const w = toks[3].text;
                const word = w[0 .. mem.indexOfAny(u8, w, "(={") orelse w.len];
                for (behavioural) |x| if (ascii.eqlIgnoreCase(word, x)) return 2;
                return 4;
            },
            'm', 's', 't', 'o' => 4,
            'j', 'z', 'u' => 3,
            // `Q c b e [s] model`: four nodes when token 5 is the model, or when token 4 is
            // no known model and token 5 is a plain word.
            'q' => {
                const fifth_plain = toks.len > 5 and keyOf(toks[5].text) == null and mem.indexOfAny(u8, toks[5].text, "{'") == null;
                return if (!isModel(models, toks, 4) and (isModel(models, toks, 5) or fifth_plain)) 4 else 3;
            },
            // Nodes, then the subckt or model name, then `k=v` (`N1 d g s b osdi_mod w=1u`,
            // `P1 i1 i2 0 o1 o2 0 cpl len=1`, `Y1 a 0 b 0 txl len=1`). An `X` may have no
            // nodes (`X1 sub`: a subckt on globals only); the others need one.
            'x', 'n', 'p', 'y' => {
                const k = for (toks, 0..) |t, i| {
                    if (keyOf(t.text) != null or ascii.eqlIgnoreCase(t.text, "params:")) break i;
                } else toks.len;
                if (k < 2 or (k < 3 and letter != 'x')) return null;
                return k - 2;
            },
            else => null,
        };
    }

    fn element(b: *Builder, st: *const Stmt, letter: u8, toks: []const Tok) Allocator.Error!void {
        const a = b.a;
        const c = b.cell();
        var nets: ArrayList(u32) = .empty;
        var sub: []const u8 = "";
        var rest: []const u8 = "";
        if (letter == 'a') {
            // XSPICE: the nodes sit among port modifiers, so the rest keeps them all.
            const t = mem.trimStart(u8, st.text.items, ws);
            rest = if (mem.indexOfAny(u8, t, ws)) |sp| mem.trim(u8, t[sp..], ws) else "";
            const x = try xspice(a, rest) orelse {
                try b.warn(st.line, "XSPICE card without a node or a model kept as code (not drawn)", .{});
                return b.keep(st);
            };
            for (x.nodes) |r| try nets.append(a, try b.net(c, rest[r.lo..r.hi]));
        } else {
            const nodes = b.nodeCount(letter, toks) orelse {
                if (letter == 'k')
                    try b.warn(st.line, "coupling kept as top-level code", .{})
                else
                    try b.warn(st.line, "unsupported element kept as top-level code (not drawn)", .{});
                return b.keep(st);
            };
            const need = 1 + nodes + @intFromBool(letter == 'x');
            if (toks.len < need) {
                try b.warn(st.line, "too few nodes; card kept as code", .{});
                return b.keep(st);
            }
            for (toks[1 .. 1 + nodes]) |t| try nets.append(a, try b.net(c, t.text));
            if (letter == 'x') sub = toks[need - 1].text;
            if (toks.len > need) rest = mem.trim(u8, st.text.items[toks[need].at..], ws);
        }
        assert(b.row_name.items.len < devices_max);
        assert(letter == 'x' or nets.items.len > 0);
        try b.row_cell.append(a, c);
        try b.row_name.append(a, toks[0].text);
        try b.row_line.append(a, st.line);
        try b.row_nets.append(a, nets.items);
        try b.row_sub.append(a, sub);
        try b.row_rest.append(a, rest);
    }

    /// Groups devices and nets by cell (stable) and renumbers nets cell-locally.
    fn finish(b: *Builder) Allocator.Error!Deck {
        const a = b.a;
        const cells = b.cell_name.items.len;
        // Nets: stable counting sort by cell; `local[g]` is the cell-local id.
        const net_start = try a.alloc(u32, cells + 1);
        @memset(net_start, 0);
        for (b.net_cell.items) |c| net_start[c + 1] += 1;
        for (0..cells) |c| net_start[c + 1] += net_start[c];
        const next = try a.dupe(u32, net_start);
        const local = try a.alloc(u32, b.net_keys.items.len);
        const keys = try a.alloc([]const u8, b.net_keys.items.len);
        for (b.net_cell.items, 0..) |c, g| {
            const slot = next[c];
            next[c] += 1;
            local[g] = slot - net_start[c];
            keys[slot] = b.net_keys.items[g];
        }
        for (0..cells) |c| {
            const have = net_start[c + 1] - net_start[c];
            if (have > nets_max) try b.warnings.append(a, try a.print("cell {d}: {d} nets exceed {d}", .{ c, have, nets_max }));
        }
        // Devices: stable by cell.
        const n = b.row_cell.items.len;
        const dev_start = try a.alloc(u32, cells + 1);
        @memset(dev_start, 0);
        for (b.row_cell.items) |c| dev_start[c + 1] += 1;
        for (0..cells) |c| dev_start[c + 1] += dev_start[c];
        const fill = try a.dupe(u32, dev_start);
        const order = try a.alloc(usize, n);
        for (b.row_cell.items, 0..) |c, i| {
            order[fill[c]] = i;
            fill[c] += 1;
        }
        const dev_name = try a.alloc([]const u8, n);
        const dev_line = try a.alloc(u32, n);
        const dev_sub = try a.alloc([]const u8, n);
        const dev_rest = try a.alloc([]const u8, n);
        const dev_net_start = try a.alloc(u32, n + 1);
        var dev_net: ArrayList(u32) = .empty;
        dev_net_start[0] = 0;
        for (order, 0..) |i, d| {
            dev_name[d] = b.row_name.items[i];
            dev_line[d] = b.row_line.items[i];
            dev_sub[d] = b.row_sub.items[i];
            dev_rest[d] = b.row_rest.items[i];
            for (b.row_nets.items[i]) |g| try dev_net.append(a, local[g]);
            dev_net_start[d + 1] = @intCast(dev_net.items.len);
        }
        var port_start: ArrayList(u32) = .empty;
        var port_net: ArrayList(u32) = .empty;
        var port_side: ArrayList(Side) = .empty;
        var port_rank: ArrayList(u16) = .empty;
        var param_start: ArrayList(u32) = .empty;
        var params: ArrayList(Param) = .empty;
        try port_start.append(a, 0);
        try param_start.append(a, 0);
        for (0..cells) |c| {
            const sides = b.sides.items[c].items;
            for (b.ports.items[c].items) |g| {
                try port_net.append(a, local[g]);
                const at = for (sides, 0..) |s, k| {
                    if (s.net == g) break k;
                } else null;
                try port_side.append(a, if (at) |k| sides[k].side else .auto);
                try port_rank.append(a, if (at) |k| @intCast(k) else rank_none);
            }
            try port_start.append(a, @intCast(port_net.items.len));
            try params.appendSlice(a, b.params.items[c].items);
            try param_start.append(a, @intCast(params.items.len));
        }
        assert(dev_start[cells] == n);
        return .{
            .cell_name = b.cell_name.items,
            .port_start = port_start.items,
            .port_net = port_net.items,
            .port_side = port_side.items,
            .port_rank = port_rank.items,
            .param_start = param_start.items,
            .params_ = params.items,
            .net_start = net_start,
            .net_key = keys,
            .dev_start = dev_start,
            .dev_name = dev_name,
            .dev_line = dev_line,
            .dev_net_start = dev_net_start,
            .dev_net = dev_net.items,
            .dev_sub = dev_sub,
            .dev_rest = dev_rest,
            .code = b.code.items,
            .code_cell = b.code_cell.items,
            .directive = b.directive_text.items,
            .directive_cell = b.directive_cell.items,
            .directive_line = b.directive_line.items,
            .globals = b.globals.items,
            .models = b.models.items,
            .pininfo = b.pininfo.items,
            .spelling = b.spelling,
            .spelled = b.spelled.items,
            .warnings = b.warnings.items,
        };
    }
};

const testing = std.testing;

fn anyContains(list: []const []const u8, needle: []const u8) bool {
    for (list) |s| if (mem.indexOf(u8, s, needle) != null) return true;
    return false;
}

test "cards split into nodes, rest and code" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try parse(a, "* title\n.subckt inv in out vdd params: wn=1u\n*.PININFO in:I out:O\n" ++
        "M1 out in vdd vdd pmos w={2*wn}\n+ l=0.18u ; tail\nMn out in 0 0 nmos w=wn l=1u\n" ++
        ".param k=3\n.ends\nX1 a b VDD inv wn=2u\nV1 a 0 dc 0 ac 1\n.tran 1n 1u\n" ++
        ".control\nrun\n.endc\nK1 L1 L2 0.9\n.end\nR9 never here\n");
    try testing.expectEqual(2, d.cells());
    try testing.expectEqualStrings("inv", d.cell_name[1]);
    try testing.expectEqual(3, d.ports(1).len);
    try testing.expectEqual(2, d.params(1).len);
    try testing.expectEqualStrings("wn", d.params(1)[0].name);
    try testing.expectEqualStrings("k", d.params(1)[1].name);
    const r = try parse(a, ".subckt s a k=1\n.param K=2 j=3\n.param k=4\nR1 a 0 1\n.ends\n");
    try testing.expectEqual(2, r.params(1).len);
    try testing.expectEqualStrings("k", r.params(1)[0].name);
    try testing.expectEqualStrings("4", r.params(1)[0].value); // a repeat keeps the later value
    try testing.expectEqualStrings("j", r.params(1)[1].name);
    try testing.expectEqual(2, d.devs(0).len()); // X1 and V1 at top
    try testing.expectEqual(2, d.devs(1).len());
    const m1 = d.devs(1).lo;
    try testing.expectEqualStrings("pmos w={2*wn} l=0.18u", d.dev_rest[m1]);
    try testing.expectEqual(4, d.netsOf(m1).len);
    const x1 = d.devs(0).lo;
    try testing.expectEqualStrings("inv", d.dev_sub[x1]);
    try testing.expectEqualStrings("wn=2u", d.dev_rest[x1]);
    try testing.expectEqual(3, d.code.len);
    try testing.expectEqualSlices(u16, &.{ 0, 0, 0 }, d.code_cell);
    try testing.expect(mem.startsWith(u8, d.code[1], ".control") and mem.endsWith(u8, d.code[1], ".endc"));
    try testing.expectEqual(Dir.in, d.pinInfo("in").?);
    try testing.expect(anyContains(d.warnings, "coupling"));
    // Case folds for matching; the first spelling is kept for display.
    try testing.expectEqualStrings("vdd", d.netName(0, d.netsOf(x1)[2]));
}

test "qualified counts and bad cards" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const d = try parse(arena.allocator(), ".model qm npn\nQ1 c b e qm\nQ2 c b e s qm\nEb o 0 value={v(a)}\nR1 a\n");
    const r = d.devs(0);
    try testing.expectEqual(3, r.len()); // R1 has one node: kept as code
    try testing.expectEqual(3, d.netsOf(r.lo).len);
    try testing.expectEqual(4, d.netsOf(r.lo + 1).len);
    try testing.expectEqual(2, d.netsOf(r.lo + 2).len);
    try testing.expect(anyContains(d.code, "R1"));
    try testing.expect(anyContains(d.warnings, "too few"));
}

test "xspice, osdi, line and node-less cards are devices" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const d = try parse(arena.allocator(), ".subckt blk in out vdd vss\n*@ right out, in\n*@ top vdd\n*@ left IN\n*@ expand\n" ++
        "R1 in out 1\n.ends\n*@ left a\nA1 [a b] ~y nand1\nA2 %vd(a 0) %v o gain1\nA3 null\n" ++
        "N1 d g s b osdi w=1u\nP1 a b 0 c e 0 cpl\nY1 a 0 c 0 txl len=1\nX1 on_globals k=2\n" ++
        "X2\nP2 cpl\n");
    const top = d.devs(0);
    const names = [_][]const u8{ "A1", "A2", "N1", "P1", "Y1", "X1" };
    try testing.expectEqual(names.len, top.len());
    for (names, top.lo..) |n, i| try testing.expectEqualStrings(n, d.dev_name[i]);
    const keysOf = struct {
        fn f(dk: *const Deck, dev: u32, want: []const []const u8) !void {
            try testing.expectEqual(want.len, dk.netsOf(dev).len);
            for (dk.netsOf(dev), want) |n, w| try testing.expectEqualStrings(w, dk.netKey(0, n));
        }
    }.f;
    try keysOf(&d, top.lo, &.{ "a", "b", "y" });
    try keysOf(&d, top.lo + 1, &.{ "a", "0", "o" });
    try testing.expectEqual(4, d.netsOf(top.lo + 2).len);
    try testing.expectEqual(6, d.netsOf(top.lo + 3).len);
    try testing.expectEqual(4, d.netsOf(top.lo + 4).len);
    try testing.expectEqual(0, d.netsOf(top.lo + 5).len); // a node-less call
    try testing.expectEqualStrings("[a b] ~y nand1", d.dev_rest[top.lo]);
    try testing.expectEqualStrings("osdi w=1u", d.dev_rest[top.lo + 2]);
    try testing.expectEqualStrings("on_globals", d.dev_sub[top.lo + 5]);
    try testing.expectEqualStrings("k=2", d.dev_rest[top.lo + 5]);
    // No node (A3, P2) or no subckt name (X2): kept as code.
    try testing.expectEqual(3, d.code.len);
    // `in`, named twice, takes its later side and place; `vss` has none; the directive at
    // top level and `*@ expand` change nothing.
    const p = d.portRange(1);
    try testing.expectEqualSlices(Side, &.{ .left, .right, .top, .auto }, d.port_side[p.lo..p.hi]);
    try testing.expectEqualSlices(u16, &.{ 2, 0, 1, rank_none }, d.port_rank[p.lo..p.hi]);
}

test "xspice splits nodes from modifiers and the model" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x = (try xspice(a, "in out gain1")).?;
    try testing.expect(x.plain and x.model == 7);
    try testing.expectEqualSlices(Range, &.{ .{ .lo = 0, .hi = 2 }, .{ .lo = 3, .hi = 6 } }, x.nodes);
    const text = "[a ~b] %vd(c d) null out2 m";
    const y = (try xspice(a, text)).?;
    try testing.expect(!y.plain);
    const want = [_][]const u8{ "a", "b", "c", "d", "out2" };
    try testing.expectEqual(want.len, y.nodes.len);
    for (want, y.nodes) |w, r| try testing.expectEqualStrings(w, text[r.lo..r.hi]);
    try testing.expectEqualStrings("m", text[y.model..]);
    try testing.expectEqual(1, (try xspice(a, "%vnam vsrc o m")).?.nodes.len);
    try testing.expect(try xspice(a, "m") == null); // no node
    try testing.expect(try xspice(a, "[a b]") == null); // no model outside brackets
    try testing.expect(try xspice(a, "") == null);
}

test "tokenizer glues assignments and keeps groups" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const t = try tokenize(arena.allocator(), "V1 a b PULSE(0 1 0) w = {a + b} l= 2 'x y'");
    const want = [_][]const u8{ "V1", "a", "b", "PULSE(0 1 0)", "w={a + b}", "l=2", "'x y'" };
    try testing.expectEqual(want.len, t.len);
    for (want, t) |w, g| try testing.expectEqualStrings(w, g.text);
    try testing.expectEqualStrings("R1 a b 1k", cutComment("R1 a b 1k $ note"));
    try testing.expectEqualStrings("R1 a b '1$2'", cutComment("R1 a b '1$2' ; c"));
}
