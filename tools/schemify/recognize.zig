//! Recognize transform: `Deck` devices → symbols (bundled `core` cells, generated subckt
//! cells, generated leaf cells) and per-instance parameter overrides.
//!
//! A card maps onto its `core` cell only when the core template re-emits it faithfully:
//! the core templates always print some parameters (`m=`, a diode's `area=`, a MOSFET's
//! `w=`/`l=`), so a card that omits them would change meaning. Every other card becomes an
//! instance of a generated *leaf* (`spice_<kind>.shprim`, template `{name} {pins} {args}`)
//! that re-emits the card text verbatim. `X` cards call the generated cell of a subckt in
//! the file, or a generated stub leaf named after an undefined subckt.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const mem = std.mem;
const ascii = std.ascii;
const spice = @import("spice.zig");
const Deck = spice.Deck;
const Dir = spice.Dir;
const Side = spice.Side;
const Tok = spice.Tok;
const Range = spice.Range;
const keyOf = spice.keyOf;
const Place = @import("place.zig").Place;

/// Symbols per conversion (core rows + generated cells).
pub const symbols_max = 8192;

/// Geometry family: pin layout and body of a symbol (local xschem units, y down).
pub const Family = enum {
    /// Two pins `p` (0,-30) / `n` (0,30).
    two,
    /// MOSFET `d g s b`, n-channel drawing.
    nmos,
    /// MOSFET `d g s b`, p-channel drawing (drain at the bottom).
    pmos,
    /// Three-terminal `c b e` (also JFET/MESFET `d g s`), npn drawing.
    npn,
    /// Three-terminal, pnp drawing (collector at the bottom).
    pnp,
    /// Controlled source `p n cp cn`.
    vcxs,
    /// Voltage switch `p n cp cn`.
    vsw,
    /// Four-port line `p1 n1 p2 n2`.
    tline,
    /// Generated box: pins on the sides `*@` directives name, else inputs left and the
    /// rest right (subckt cells, stubs, XSPICE and other leaves).
    box,
};

/// How a symbol is written out: a bundled `core` cell (nothing to write), the generated
/// `.shcomp` of a deck cell, a generated `.shprim` leaf re-emitting card text, or a cell of
/// a project library (nothing to write; `Symbols.lib` names it).
pub const Origin = enum { core, sub, leaf, lib };

/// A cell of a project library an `X` card may call by its subckt name (read by the
/// plugin from `<lib dir>/<name>.shprim|.shcomp`, `place.libCell`).
pub const LibCell = struct {
    /// Library name (the `lib` row), and the cell's.
    lib: []const u8,
    name: []const u8,
    /// Pins in file order, which is the card's node order.
    pins: []const Pin,
    body: Body,
    params: []const LibParam,
};

/// A library cell's parameter: string params take templates, the rest expressions.
pub const LibParam = struct { name: []const u8, string: bool };

pub const Pin = struct { name: []const u8, x: i32, y: i32, dir: Dir };
/// A closed rectangle `[x0, y0, x1, y1]`.
pub const Body = [4]i32;

/// Symbol table: one row per distinct cell instances refer to. Pins are CSR (`pin_start`,
/// rows + 1) in SPICE order.
pub const Symbols = struct {
    /// Cell stem (`res`, `inv`, `spice_d2`); unique among generated cells, case-insensitively.
    stem: ArrayList([]const u8) = .empty,
    origin: ArrayList(Origin) = .empty,
    family: ArrayList(Family) = .empty,
    /// Default of the leaf `args` parameter (stub leaves: the subckt name).
    args_default: ArrayList([]const u8) = .empty,
    /// A leaf's SPICE template when not the default `{name} {pins} {args}` (`""`).
    format: ArrayList([]const u8) = .empty,
    /// Local body rectangle, pins on its boundary.
    body: ArrayList(Body) = .empty,
    pin_start: ArrayList(u32) = .empty,
    /// Pins: offsets are multiples of 10; control pins are `in`.
    pin: ArrayList(Pin) = .empty,
    /// A `lib` symbol's library (`""` otherwise).
    lib: ArrayList([]const u8) = .empty,

    pub fn len(s: *const Symbols) u32 {
        return @intCast(s.stem.items.len);
    }

    pub fn pins(s: *const Symbols, i: u32) []const Pin {
        return s.pin.items[s.pin_start.items[i]..s.pin_start.items[i + 1]];
    }

    /// Cell reference written in `inst` records of file `from` (`top.shbench`), where `place`
    /// puts the files: `core:<stem>`, `./<stem>`, or `<lib>:<stem>` across directories;
    /// `null` when `place` puts the cell where `from` cannot reach it.
    pub fn cellref(s: *const Symbols, a: Allocator, i: u32, place: *const Place, from: []const u8) Allocator.Error!?[]const u8 {
        const stem = s.stem.items[i];
        const ext = switch (s.origin.items[i]) {
            .core => return try a.print("core:{s}", .{stem}),
            .lib => return try a.print("{s}:{s}", .{ s.lib.items[i], stem }),
            .sub => "shcomp",
            .leaf => "shprim",
        };
        return place.ref(a, from, try a.print("{s}.{s}", .{ stem, ext }), stem);
    }

    /// Appends a symbol; a `box` passes its body (from `boxLayout`), the other families'
    /// bodies follow from their pins.
    fn push(s: *Symbols, a: Allocator, stem: []const u8, origin: Origin, family: Family, pins_: []const Pin, box_body: ?Body) Allocator.Error!u32 {
        assert(s.stem.items.len < symbols_max);
        assert((family == .box) == (box_body != null));
        if (s.pin_start.items.len == 0) try s.pin_start.append(a, 0);
        var body: Body = .{ 0, 0, 0, 0 };
        for (pins_, 0..) |p, i| {
            assert(origin == .lib or (@rem(p.x, 10) == 0 and @rem(p.y, 10) == 0));
            if (i == 0) body = .{ p.x, p.y, p.x, p.y };
            body = .{ @min(body[0], p.x), @min(body[1], p.y), @max(body[2], p.x), @max(body[3], p.y) };
        }
        switch (family) {
            // The core two-pin bodies (circles, plates) reach x = ±20.
            .two => body = .{ -20, -30, 20, 30 },
            .vcxs, .vsw => body[2] = 20,
            .tline => body = .{ -80, -20, 80, 20 },
            .box => body = box_body.?,
            else => {},
        }
        try s.pin.appendSlice(a, pins_);
        try s.pin_start.append(a, @intCast(s.pin.items.len));
        try s.stem.append(a, stem);
        try s.origin.append(a, origin);
        try s.family.append(a, family);
        try s.args_default.append(a, "");
        try s.format.append(a, "");
        try s.lib.append(a, "");
        try s.body.append(a, body);
        return s.len() - 1;
    }
};

/// Per-device recognition result (rows parallel to the deck's devices).
pub const Parts = struct {
    sym: ArrayList(u32) = .empty,
    /// The instance's `name` attribute.
    inst_name: ArrayList([]const u8) = .empty,
    over_start: ArrayList(u32) = .empty,
    /// Overridden parameter names.
    over_key: ArrayList([]const u8) = .empty,
    /// Override values: expressions for number params, templates for string params.
    over_val: ArrayList([]const u8) = .empty,

    pub fn overrides(p: *const Parts, d: u32) Range {
        return .{ .lo = p.over_start.items[d], .hi = p.over_start.items[d + 1] };
    }
};

const Core = struct { name: []const u8, family: Family, pins: []const Pin };

fn pin(name: []const u8, x: i32, y: i32, dir: Dir) Pin {
    return .{ .name = name, .x = x, .y = y, .dir = dir };
}

const two_pins = [_]Pin{ pin("p", 0, -30, .inout), pin("n", 0, 30, .inout) };
const nmos_pins = [_]Pin{ pin("d", 20, -30, .inout), pin("g", -20, 0, .in), pin("s", 20, 30, .inout), pin("b", 20, 0, .in) };
const pmos_pins = [_]Pin{ pin("d", 20, 30, .inout), pin("g", -20, 0, .in), pin("s", 20, -30, .inout), pin("b", 20, 0, .in) };
const npn_pins = [_]Pin{ pin("c", 20, -30, .inout), pin("b", -20, 0, .in), pin("e", 20, 30, .inout) };
const pnp_pins = [_]Pin{ pin("c", 20, 30, .inout), pin("b", -20, 0, .in), pin("e", 20, -30, .inout) };
const vcxs_pins = [_]Pin{ pin("p", 0, -30, .inout), pin("n", 0, 30, .inout), pin("cp", -40, -20, .in), pin("cn", -40, 20, .in) };
const vsw_pins = [_]Pin{ pin("p", 0, -30, .inout), pin("n", 0, 30, .inout), pin("cp", -40, 0, .in), pin("cn", -40, 20, .in) };
const tline_pins = [_]Pin{ pin("p1", -80, -10, .inout), pin("n1", -80, 10, .inout), pin("p2", 80, -10, .inout), pin("n2", 80, 10, .inout) };

/// Core cells this importer places, with their SPICE-order pins (offsets from Schemify's
/// `devices/*.shprim`).
pub const core = [_]Core{
    .{ .name = "res", .family = .two, .pins = &two_pins },
    .{ .name = "cap", .family = .two, .pins = &two_pins },
    .{ .name = "ind", .family = .two, .pins = &two_pins },
    .{ .name = "diode", .family = .two, .pins = &two_pins },
    .{ .name = "vsource", .family = .two, .pins = &two_pins },
    .{ .name = "isource", .family = .two, .pins = &two_pins },
    .{ .name = "cccs", .family = .two, .pins = &two_pins },
    .{ .name = "ccvs", .family = .two, .pins = &two_pins },
    .{ .name = "switch", .family = .two, .pins = &two_pins },
    .{ .name = "nmos4", .family = .nmos, .pins = &nmos_pins },
    .{ .name = "pmos4", .family = .pmos, .pins = &pmos_pins },
    .{ .name = "npn", .family = .npn, .pins = &npn_pins },
    .{ .name = "pnp", .family = .pnp, .pins = &pnp_pins },
    .{ .name = "vcvs", .family = .vcxs, .pins = &vcxs_pins },
    .{ .name = "vccs", .family = .vcxs, .pins = &vcxs_pins },
    .{ .name = "vswitch", .family = .vsw, .pins = &vsw_pins },
    .{ .name = "tline", .family = .tline, .pins = &tline_pins },
};

fn coreSym(comptime name: []const u8) u32 {
    inline for (core, 0..) |c, i| if (comptime mem.eql(u8, c.name, name)) return i;
    @compileError("no core cell " ++ name);
}

/// Symbol row of the generated cell of deck subckt `c` (≥ 1).
pub fn subSymbol(c: u32) u32 {
    assert(c >= 1);
    return @as(u32, core.len) + c - 1;
}

/// Recognition output: the symbol table (core rows first, then subckt cells in deck
/// order, then leaves in first-use order) and one `Parts` row per deck device.
pub const Recognized = struct {
    syms: Symbols = .{},
    parts: Parts = .{},
    warnings: ArrayList([]const u8) = .empty,
    /// The `spice_code` leaf (one pin, template `{text}`) that carries a subckt's code
    /// text inside its definition; `none` when no subckt has code.
    code_sym: u32 = none,
    /// Generated stems taken so far (case-insensitive).
    taken: ArrayList([]const u8) = .empty,
    /// Per deck cell: its definition re-declares its parameters (`.param k={k}`), because
    /// card text kept verbatim in it names them.
    shim: []const bool = &.{},
    /// Per deck parameter (`Deck.params_` rows): a number parameter (`numeric`), else a
    /// string one.
    number: []const bool = &.{},

    /// Which of cell `c`'s parameters are numbers.
    pub fn numbers(r: *const Recognized, deck: *const Deck, c: u32) []const bool {
        return r.number[deck.param_start[c]..deck.param_start[c + 1]];
    }

    pub const none = std.math.maxInt(u32);
};

/// Recognizes every device of `deck`, an `X` of a subckt the deck does not define calling
/// the cell of that name in `libs` when there is one. Never fails but on memory: an
/// unmappable card becomes a leaf instance that re-emits it verbatim.
pub fn recognize(a: Allocator, deck: *const Deck, libs: []const LibCell) Allocator.Error!Recognized {
    var r: Recognized = .{};
    for (core) |c| _ = try r.syms.push(a, c.name, .core, c.family, c.pins, null);
    for (1..deck.cells()) |c| {
        const stem = try uniqueStem(a, deck.cell_name[c], &r.taken);
        const bp = try boxPins(a, deck, @intCast(c));
        _ = try r.syms.push(a, stem, .sub, .box, bp.pins, bp.body);
    }
    r.number = try numeric(a, deck);
    const shim = try a.alloc(bool, deck.cells());
    for (shim, 0..) |*x, c| x.* = c > 0 and try needsShim(a, deck, libs, @intCast(c));
    r.shim = shim;
    var has_code = mem.indexOfScalar(bool, shim, true) != null;
    for (deck.code_cell) |c| has_code = has_code or c != 0;
    if (has_code) {
        const stem = try uniqueStem(a, "spice_code", &r.taken);
        const bp = try boxAuto(a, &.{"p"}, &.{.inout});
        r.code_sym = try r.syms.push(a, stem, .leaf, .box, bp.pins, bp.body);
    }
    try r.parts.over_start.append(a, 0);
    for (0..deck.cells()) |ci| {
        const c: u32 = @intCast(ci);
        const first = r.parts.inst_name.items.len;
        const devs = deck.devs(c);
        for (devs.lo..devs.hi) |di| {
            const d: u32 = @intCast(di);
            try device(a, deck, d, c, libs, &r);
            try r.parts.over_start.append(a, @intCast(r.parts.over_key.items.len));
            // Instance names are unique per cell (E009): a repeated card name gets a suffix.
            const names = r.parts.inst_name.items;
            const last = names.len - 1;
            const name = names[last];
            if (nameTaken(names[first..last], name)) {
                var k: u32 = 2;
                while (nameTaken(names[first..last], try a.print("{s}_{d}", .{ name, k }))) k += 1;
                try r.warnings.append(a, try a.print("line {d}: duplicate name {s} renamed {s}_{d}", .{ deck.dev_line[d], name, name, k }));
                names[last] = try a.print("{s}_{d}", .{ name, k });
            }
        }
    }
    assert(r.parts.sym.items.len == deck.dev_name.len);
    assert(r.parts.over_start.items.len == deck.dev_name.len + 1);
    return r;
}

/// True when `n` equals one of `names`, case-insensitively (file stems on a case-folding disk).
pub fn nameTaken(names: []const []const u8, n: []const u8) bool {
    for (names) |x| if (ascii.eqlIgnoreCase(x, n)) return true;
    return false;
}

/// The cell of `libs` an `X` of undefined subckt `sub` with `nodes` nodes calls (first in
/// `libs` order, its pins in node order).
fn libCellOf(libs: []const LibCell, sub: []const u8, nodes: usize) ?*const LibCell {
    for (libs) |*l| if (ascii.eqlIgnoreCase(l.name, sub) and l.pins.len == nodes) return l;
    return null;
}

/// Whether text kept verbatim in subckt `c` names one of its parameters: a code entry, or
/// a card other than an `X` that `device` maps to a cell (whose overrides are holes).
fn needsShim(a: Allocator, deck: *const Deck, libs: []const LibCell, c: u32) Allocator.Error!bool {
    const params = deck.params(c);
    if (params.len == 0) return false;
    const names = struct {
        fn f(a_: Allocator, text: []const u8, ps: []const spice.Param) Allocator.Error!bool {
            return !mem.eql(u8, try template(a_, text, ps), try template(a_, text, &.{}));
        }
    }.f;
    for (deck.code, deck.code_cell) |text, cc| if (cc == c and try names(a, text, params)) return true;
    const devs = deck.devs(c);
    for (devs.lo..devs.hi) |d| {
        if (ascii.toLower(deck.dev_name[d][0]) == 'x') {
            const nodes = deck.netsOf(@intCast(d)).len;
            const sub = deck.dev_sub[d];
            const called = if (deck.findCell(sub)) |k| deck.ports(k).len == nodes else libCellOf(libs, sub, nodes) != null;
            if (called) continue;
        }
        if (try names(a, deck.dev_rest[d], params)) return true;
    }
    return false;
}

/// A symbol's pins and, for a box, its body.
const BoxPins = struct { pins: []const Pin, body: Body };

/// Generated box of subckt cell `c`: each port on the side its `*@` directive names, in
/// directive order, else inputs left and the rest right, in port order.
fn boxPins(a: Allocator, deck: *const Deck, c: u32) Allocator.Error!BoxPins {
    const ports = deck.ports(c);
    const dirs = try a.alloc(Dir, ports.len);
    const names = try a.alloc([]const u8, ports.len);
    for (ports, dirs, names) |n, *d, *nm| {
        d.* = portDir(deck, c, n);
        nm.* = try pinName(a, deck.netName(c, n));
    }
    const r = deck.portRange(c);
    return boxLayout(a, names, dirs, deck.port_side[r.lo..r.hi], deck.port_rank[r.lo..r.hi]);
}

/// `boxLayout` with every pin on its default side (inputs left, the rest right).
fn boxAuto(a: Allocator, names: []const []const u8, dirs: []const Dir) Allocator.Error!BoxPins {
    const sides = try a.alloc(Side, names.len);
    @memset(sides, .auto);
    const ranks = try a.alloc(u16, names.len);
    @memset(ranks, spice.rank_none);
    return boxLayout(a, names, dirs, sides, ranks);
}

/// Box geometry for pins `names` (directions `dirs`) on sides `sides` (`auto`: inputs left,
/// the rest right), ordered on each side by `ranks` then pin order (top to bottom, left to
/// right). Pins sit 20 apart, centred on the origin, side pins at x = ±xs and top/bottom
/// pins at y = ±ys; xs and ys put every pin on its own side by cktImg's rule (the larger
/// of |x| and |y| faces out) and clear of the other sides' pins. The body is
/// `[-xs, -ys, xs, ys]` (pins on its boundary, the drawn box 20 inside). Without
/// top/bottom pins and with at most six pins a side, the pins sit at x = ±60.
fn boxLayout(a: Allocator, names: []const []const u8, dirs: []const Dir, sides: []const Side, ranks: []const u16) Allocator.Error!BoxPins {
    const n = names.len;
    assert(dirs.len == n and sides.len == n and ranks.len == n);
    const side = try a.alloc(Side, n);
    for (side, sides, dirs) |*s, given, d| s.* = if (given != .auto) given else if (d == .in) .left else .right;
    // Slot of each pin along its side, and pins per side (indexed by `Side`).
    const slot = try a.alloc(i32, n);
    var count: [5]i32 = @splat(0);
    const on = try a.alloc(u32, n);
    for ([_]Side{ .left, .right, .top, .bottom }) |s| {
        var m: usize = 0;
        for (side, 0..) |x, k| if (x == s) {
            on[m] = @intCast(k);
            m += 1;
        };
        mem.sort(u32, on[0..m], ranks, struct {
            fn lt(rk: []const u16, x: u32, y: u32) bool {
                return rk[x] < rk[y] or (rk[x] == rk[y] and x < y);
            }
        }.lt);
        for (on[0..m], 0..) |k, j| slot[k] = @intCast(j);
        count[@backingInt(s)] = @intCast(m);
    }
    const half = struct {
        fn f(m: i32) i32 {
            return @max(m - 1, 0) * 10;
        }
    }.f;
    const lr = half(@max(count[@backingInt(Side.left)], count[@backingInt(Side.right)]));
    const tb = half(@max(count[@backingInt(Side.top)], count[@backingInt(Side.bottom)]));
    const xs: i32 = @max(60, lr + 10, tb + 30);
    const ys: i32 = @max(40, lr + 30, tb + 10);
    const pins_ = try a.alloc(Pin, n);
    for (pins_, 0..) |*p, k| {
        const along = slot[k] * 20 - half(count[@backingInt(side[k])]);
        const x: i32, const y: i32 = switch (side[k]) {
            .left => .{ -xs, along },
            .right => .{ xs, along },
            .top => .{ along, -ys },
            .bottom => .{ along, ys },
            .auto => unreachable, // resolved above
        };
        p.* = .{ .name = names[k], .x = x, .y = y, .dir = dirs[k] };
        assert((@abs(x) == xs and @abs(y) < xs) or (@abs(y) == ys and @abs(x) < ys));
    }
    return .{ .pins = pins_, .body = .{ -xs, -ys, xs, ys } };
}

/// Port direction: `*.PININFO`, else the net name (`in*`/`vin*` input, `out*`/`vout*`/
/// `vref*`/`vo` output), else inout.
fn portDir(deck: *const Deck, c: u32, n: u32) Dir {
    const key = deck.netKey(c, n);
    if (deck.pinInfo(key)) |d| return d;
    const starts = struct {
        fn f(k: []const u8, p: []const u8) bool {
            return mem.startsWith(u8, k, p);
        }
    }.f;
    if (starts(key, "in") or starts(key, "vin")) return .in;
    if (starts(key, "out") or starts(key, "vout") or starts(key, "vref") or mem.eql(u8, key, "vo")) return .out;
    return .inout;
}

/// A net or pin name as a Schemify net expression: `,` `*` `:` would read as bundle,
/// repeat or bus range, so they become `_`.
pub fn pinName(a: Allocator, name: []const u8) Allocator.Error![]const u8 {
    if (mem.indexOfAny(u8, name, ",*:") == null) return name;
    const out = try a.dupe(u8, name);
    for (out) |*ch| if (mem.indexOfScalar(u8, ",*:", ch.*) != null) {
        ch.* = '_';
    };
    return out;
}

/// A file stem from `name` (`[A-Za-z0-9_.-]`, others `_`), unique case-insensitively
/// against `taken` (suffix `_2`, `_3`, …), recorded in `taken`.
pub fn uniqueStem(a: Allocator, name: []const u8, taken: *ArrayList([]const u8)) Allocator.Error![]const u8 {
    var base = try a.dupe(u8, name);
    for (base) |*ch| if (!ascii.isAlphanumeric(ch.*) and mem.indexOfScalar(u8, "_.-", ch.*) == null) {
        ch.* = '_';
    };
    if (base.len == 0 or base[0] == '.') base = try a.print("c{s}", .{base});
    var stem: []const u8 = base;
    var k: u32 = 2;
    while (nameTaken(taken.items, stem)) : (k += 1) stem = try a.print("{s}_{d}", .{ base, k });
    try taken.append(a, stem);
    return stem;
}

/// True for a number the expression language reads exactly: `digits[.digits][e±digits]`
/// with an optional SI suffix and nothing after (`10u`, `1.8`, `2meg`; not `1.8V`).
pub fn isLiteral(text: []const u8) bool {
    const s = if (text.len > 0 and text[0] == '-') text[1..] else text;
    var i: usize = 0;
    const digits = struct {
        fn f(b: []const u8, at: *usize) bool {
            const start = at.*;
            while (at.* < b.len and ascii.isDigit(b[at.*])) at.* += 1;
            return at.* > start;
        }
    }.f;
    const int = digits(s, &i);
    if (i < s.len and s[i] == '.') {
        i += 1;
        if (!digits(s, &i)) return false;
    } else if (!int) return false;
    if (i + 1 < s.len and ascii.toLower(s[i]) == 'e' and (ascii.isDigit(s[i + 1]) or s[i + 1] == '+' or s[i + 1] == '-')) {
        i += 1;
        if (s[i] == '+' or s[i] == '-') i += 1;
        if (!digits(s, &i)) return false;
    }
    const suffix = s[i..];
    for ([_][]const u8{ "", "f", "p", "n", "u", "m", "k", "meg", "g", "t", "mil" }) |x|
        if (ascii.eqlIgnoreCase(suffix, x)) return true;
    return false;
}

/// SPICE text → template text (expr §6): literal braces doubled; an identifier naming a
/// parameter of `params` (case-insensitive, not a `k=` key, not a function name, not a
/// node inside `v(…)`/`i(…)`) becomes a hole, wrapped `({k})` inside an expression and
/// `{{({k})}}` (a SPICE expression) when bare.
pub fn template(a: Allocator, text: []const u8, params: []const spice.Param) Allocator.Error![]const u8 {
    return templateIn(a, text, params, 0, false);
}

/// `template` with every hole a bare `{k}`: the deck's text with each parameter's value
/// written in, in whatever syntax (quotes, braces) the deck used around it.
pub fn substitute(a: Allocator, text: []const u8, params: []const spice.Param) Allocator.Error![]const u8 {
    return templateIn(a, text, params, 0, true);
}

/// `template` for a parameter value: the whole text is one expression (its outer `{…}`/
/// `'…'` already stripped by `stripOuter`), so holes are `({k})` throughout.
pub fn templateExpr(a: Allocator, text: []const u8, params: []const spice.Param) Allocator.Error![]const u8 {
    return templateIn(a, text, params, 1, false);
}

fn isWordByte(ch: u8) bool {
    return ascii.isAlphanumeric(ch) or ch == '_';
}

fn templateIn(a: Allocator, text: []const u8, params: []const spice.Param, depth0: u32, plain: bool) Allocator.Error![]const u8 {
    var out: ArrayList(u8) = try .initCapacity(a, text.len + 8);
    var depth = depth0; // inside {…} or '…'
    var quote = false;
    var probe_depth: ?u32 = null; // paren depth of an open v(…)/i(…)
    var paren: u32 = 0;
    var k: usize = 0;
    while (k < text.len) {
        const ch = text[k];
        const ident_start = (ascii.isAlphabetic(ch) or ch == '_') and
            (k == 0 or !(isWordByte(text[k - 1]) or text[k - 1] == '.'));
        if (ident_start) {
            var e = k;
            while (e < text.len and isWordByte(text[e])) e += 1;
            const word = text[k..e];
            const after = mem.trimStart(u8, text[e..], spice.ws);
            const is_key = after.len > 0 and after[0] == '=' and !mem.startsWith(u8, after, "==");
            const is_call = after.len > 0 and after[0] == '(';
            const hit: ?[]const u8 = for (params) |p| {
                if (ascii.eqlIgnoreCase(p.name, word)) break p.name;
            } else null;
            if (hit != null and !is_key and !is_call and probe_depth == null) {
                if (plain)
                    try out.print(a, "{{{s}}}", .{hit.?})
                else if (depth > 0 or quote)
                    try out.print(a, "({{{s}}})", .{hit.?})
                else
                    try out.print(a, "{{{{({{{s}}})}}}}", .{hit.?});
            } else {
                try out.appendSlice(a, word);
                if (is_call and (ascii.eqlIgnoreCase(word, "v") or ascii.eqlIgnoreCase(word, "i"))) probe_depth = paren;
            }
            k = e;
            continue;
        }
        switch (ch) {
            '{' => {
                depth += 1;
                try out.appendSlice(a, "{{");
            },
            '}' => {
                depth -|= 1;
                try out.appendSlice(a, "}}");
            },
            '\'' => {
                quote = !quote;
                try out.append(a, ch);
            },
            '(' => {
                paren += 1;
                try out.append(a, ch);
            },
            ')' => {
                paren -|= 1;
                if (probe_depth == paren) probe_depth = null;
                try out.append(a, ch);
            },
            else => try out.append(a, ch),
        }
        k += 1;
    }
    return out.items;
}

/// Strips one outer `{…}` or `'…'` from a parameter value (`{2*k}` → `2*k`).
pub fn stripOuter(value: []const u8) []const u8 {
    const v = mem.trim(u8, value, spice.ws);
    if (v.len >= 2 and ((v[0] == '{' and v[v.len - 1] == '}') or (v[0] == '\'' and v[v.len - 1] == '\''))) return v[1 .. v.len - 1];
    return v;
}

/// Instance overrides being built for one device.
const Over = struct {
    a: Allocator,
    keys: ArrayList([]const u8) = .empty,
    vals: ArrayList([]const u8) = .empty,

    /// A string parameter holding card text, verbatim (braces escaped). Parameter names in
    /// it stay SPICE names: each generated component re-declares its parameters with a
    /// `.param` line inside its definition (empty values are the default, skipped).
    fn text(o: *Over, key: []const u8, v: []const u8) Allocator.Error!void {
        if (v.len == 0) return;
        try o.keys.append(o.a, key);
        try o.vals.append(o.a, try template(o.a, v, &.{}));
    }

    /// A number parameter with literal value `v`, stored only when it differs from the
    /// cell default (D40).
    fn number(o: *Over, key: []const u8, v: []const u8, default: []const u8) Allocator.Error!void {
        assert(isLiteral(v));
        if (ascii.eqlIgnoreCase(v, default)) return;
        try o.keys.append(o.a, key);
        try o.vals.append(o.a, v);
    }

    fn clear(o: *Over) void {
        o.keys.clearRetainingCapacity();
        o.vals.clearRetainingCapacity();
    }
};

const Kv = struct { key: []const u8, value: []const u8 };

/// `k=v` parameters of tokens (lowercase key, value), or null if any token is not `k=v`.
fn kv(a: Allocator, toks: []const Tok) Allocator.Error!?[]const Kv {
    const out = try a.alloc(Kv, toks.len);
    for (toks, out) |t, *o| {
        const k = keyOf(t.text) orelse return null;
        o.* = .{ .key = try ascii.allocLowerString(a, k), .value = t.text[k.len + 1 ..] };
    }
    return out;
}

/// Splits `model k=v…` into the model word and its parameters; null unless the rest is
/// exactly that.
fn modelAndParams(a: Allocator, toks: []const Tok) Allocator.Error!?struct { []const u8, []const Kv } {
    if (toks.len == 0) return null;
    const m = toks[0].text;
    if (keyOf(m) != null or mem.indexOfAny(u8, m, "{'(") != null) return null;
    const p = try kv(a, toks[1..]) orelse return null;
    return .{ m, p };
}

fn hasLiteral(p: []const Kv, k: []const u8) bool {
    for (p) |x| if (mem.eql(u8, x.key, k) and isLiteral(x.value)) return true;
    return false;
}

fn hasKey(p: []const Kv, k: []const u8) bool {
    for (p) |x| if (mem.eql(u8, x.key, k)) return true;
    return false;
}

/// P-channel by `.model` type, else by the model name (`p…`, `…pmos…`, `…pfet…`, `…pch…`).
fn isPmos(a: Allocator, model: []const u8, kind: ?[]const u8) Allocator.Error!bool {
    if (kind) |k| return k.len > 0 and k[0] == 'p';
    const m = try ascii.allocLowerString(a, model);
    return mem.startsWith(u8, m, "p") or mem.indexOf(u8, m, "pmos") != null or
        mem.indexOf(u8, m, "pfet") != null or mem.indexOf(u8, m, "pch") != null;
}

/// Recognizes device `d` (in a cell with parameters `params`) and appends its row.
fn device(a: Allocator, deck: *const Deck, d: u32, cell: u32, libs: []const LibCell, r: *Recognized) Allocator.Error!void {
    const params = deck.params(cell);
    const nums = r.numbers(deck, cell);
    const name = deck.dev_name[d];
    const letter = ascii.toLower(name[0]);
    const nodes = deck.netsOf(d).len;
    const rest = deck.dev_rest[d];
    const toks = try spice.tokenize(a, rest);
    var o: Over = .{ .a = a };
    var inst_name = name;
    const sym: ?u32 = switch (letter) {
        'r', 'c', 'l' => if (nodes != 2) null else blk: {
            var m: ?[]const u8 = null;
            var value: ArrayList(u8) = .empty;
            for (toks) |t| {
                const k = keyOf(t.text);
                if (k != null and ascii.eqlIgnoreCase(k.?, "m")) {
                    if (m == null) m = t.text[2..];
                    continue;
                }
                if (value.items.len > 0) try value.append(a, ' ');
                try value.appendSlice(a, t.text);
            }
            if ((m == null or isLiteral(m.?)) and value.items.len > 0) {
                try o.text("value", value.items);
                if (m) |v| try o.number("m", v, "1");
            }
            if (o.keys.items.len == 0) break :blk null;
            break :blk switch (letter) {
                'r' => coreSym("res"),
                'c' => coreSym("cap"),
                else => coreSym("ind"),
            };
        },
        'v', 'i' => if (nodes != 2 or rest.len == 0) null else blk: {
            try o.text("value", rest);
            break :blk if (letter == 'v') coreSym("vsource") else coreSym("isource");
        },
        'd' => if (nodes != 2) null else blk: {
            const mp = try modelAndParams(a, toks) orelse break :blk null;
            const p = mp[1];
            if (p.len != 1 or !mem.eql(u8, p[0].key, "area") or !isLiteral(p[0].value)) break :blk null;
            try o.text("model", mp[0]);
            try o.number("area", p[0].value, "1");
            break :blk coreSym("diode");
        },
        'q' => if (nodes != 3) null else blk: {
            const mp = try modelAndParams(a, toks) orelse break :blk null;
            const p = mp[1];
            if (!hasKey(p, "area")) break :blk null;
            for (p) |x| if (!(mem.eql(u8, x.key, "area") or mem.eql(u8, x.key, "m")) or !isLiteral(x.value)) break :blk null;
            try o.text("model", mp[0]);
            for (p) |x| try o.number(x.key, x.value, "1");
            const kind = deck.modelKind(mp[0]);
            break :blk if (kind != null and mem.eql(u8, kind.?, "pnp")) coreSym("pnp") else coreSym("npn");
        },
        'm' => if (nodes != 4) null else blk: {
            const mp = try modelAndParams(a, toks) orelse break :blk null;
            const p = mp[1];
            if (!hasLiteral(p, "w") or !hasLiteral(p, "l")) break :blk null;
            for (p) |x| if (mem.eql(u8, x.key, "m") and !isLiteral(x.value)) break :blk null;
            try o.text("model", mp[0]);
            var extra: ArrayList(u8) = .empty;
            for (p) |x| {
                if (mem.eql(u8, x.key, "w")) {
                    try o.number("w", x.value, "1u");
                } else if (mem.eql(u8, x.key, "l")) {
                    try o.number("l", x.value, "0.18u");
                } else if (mem.eql(u8, x.key, "m")) {
                    try o.number("m", x.value, "1");
                } else {
                    if (extra.items.len > 0) try extra.append(a, ' ');
                    try extra.print(a, "{s}={s}", .{ x.key, x.value });
                }
            }
            try o.text("extra", extra.items);
            break :blk if (try isPmos(a, mp[0], deck.modelKind(mp[0]))) coreSym("pmos4") else coreSym("nmos4");
        },
        'e', 'g' => if (nodes != 4 or toks.len != 1) null else blk: {
            try o.text("value", rest);
            break :blk if (letter == 'e') coreSym("vcvs") else coreSym("vccs");
        },
        'f', 'h' => if (nodes != 2 or toks.len != 2 or keyOf(toks[0].text) != null) null else blk: {
            try o.text("vnam", toks[0].text);
            try o.text("value", toks[1].text);
            break :blk if (letter == 'f') coreSym("cccs") else coreSym("ccvs");
        },
        'w' => if (nodes != 2 or toks.len != 2 or keyOf(toks[0].text) != null or keyOf(toks[1].text) != null) null else blk: {
            try o.text("vnam", toks[0].text);
            try o.text("model", toks[1].text);
            break :blk coreSym("switch");
        },
        's' => if (nodes != 4 or toks.len != 1 or keyOf(toks[0].text) != null) null else blk: {
            try o.text("model", toks[0].text);
            break :blk coreSym("vswitch");
        },
        't' => if (nodes != 4) null else blk: {
            const p = try kv(a, toks) orelse break :blk null;
            if (p.len != 2 or !hasLiteral(p, "z0") or !hasLiteral(p, "td")) break :blk null;
            for (p) |x| try o.number(x.key, x.value, if (mem.eql(u8, x.key, "z0")) "50" else "10n");
            break :blk coreSym("tline");
        },
        'a' => blk: {
            const x = (try spice.xspice(a, rest)).?; // the parser keeps only A cards it can split
            try o.text("args", rest[x.model..]);
            const format = if (x.plain) "" else try xspiceFormat(a, rest, x);
            break :blk try xspiceLeaf(a, @intCast(nodes), format, r);
        },
        'x' => blk: {
            if (deck.findCell(deck.dev_sub[d]) == null) if (libCellOf(libs, deck.dev_sub[d], nodes)) |l| {
                for (toks) |t| {
                    if (ascii.eqlIgnoreCase(t.text, "params:")) continue;
                    const k = keyOf(t.text);
                    const hit: ?LibParam = if (k) |kk| for (l.params) |p| {
                        if (ascii.eqlIgnoreCase(p.name, kk)) break p;
                    } else null else null;
                    const p = hit orelse {
                        try r.warnings.append(a, try a.print("line {d}: {s}: `{s}` is no parameter of {s}:{s}; dropped", .{ deck.dev_line[d], name, t.text, l.lib, l.name }));
                        continue;
                    };
                    try o.keys.append(a, p.name);
                    try o.vals.append(a, try overValue(a, t.text[k.?.len + 1 ..], !p.string, params, nums));
                }
                if (name.len > 1) inst_name = name[1..];
                break :blk try libSymbol(a, l, r);
            };
            const c = deck.findCell(deck.dev_sub[d]) orelse {
                const s = try stub(a, deck, d, r);
                if (rest.len > 0) try o.text("args", try a.print("{s} {s}", .{ deck.dev_sub[d], rest }));
                break :blk s;
            };
            if (deck.ports(c).len != nodes) {
                try r.warnings.append(a, try a.print("line {d}: {s}: node count differs from .subckt {s}; kept verbatim", .{ deck.dev_line[d], name, deck.dev_sub[d] }));
                break :blk null;
            }
            const callee = deck.params(c);
            const callee_nums = r.numbers(deck, c);
            for (toks) |t| {
                if (ascii.eqlIgnoreCase(t.text, "params:")) continue;
                const hit: ?usize = if (keyOf(t.text)) |k| for (callee, 0..) |p, j| {
                    if (ascii.eqlIgnoreCase(p.name, k)) break j;
                } else null else null;
                if (hit) |j| {
                    try o.keys.append(a, callee[j].name);
                    try o.vals.append(a, try overValue(a, t.text[keyOf(t.text).?.len + 1 ..], callee_nums[j], params, nums));
                } else try r.warnings.append(a, try a.print("line {d}: {s}: `{s}` is no parameter of {s}; dropped", .{ deck.dev_line[d], name, t.text, deck.dev_sub[d] }));
            }
            if (name.len > 1 and ascii.toLower(name[0]) == 'x') inst_name = name[1..];
            break :blk subSymbol(c);
        },
        else => null,
    };
    const s = sym orelse blk: {
        o.clear();
        const text = if (letter == 'x') try a.print("{s} {s}", .{ deck.dev_sub[d], rest }) else rest;
        try o.text("args", mem.trimEnd(u8, text, spice.ws));
        break :blk try leaf(a, letter, @intCast(nodes), toks, deck, r);
    };
    assert(o.keys.items.len == o.vals.items.len);
    try r.parts.over_key.appendSlice(a, o.keys.items);
    try r.parts.over_val.appendSlice(a, o.vals.items);
    try r.parts.sym.append(a, s);
    try r.parts.inst_name.append(a, inst_name);
}

/// An `X` card's override `k=v` of a number parameter (`number`), else a string one, in a
/// cell with parameters `params` (`nums`: which are numbers). A value Schemify can evaluate
/// there (a literal, or an expression over number parameters) is that expression, or for a
/// string the hole around it (`{w*2}`), so the netlist gets its value in every dialect's
/// syntax; other text is the deck's own spelling with parameter values written in.
fn overValue(a: Allocator, v: []const u8, number: bool, params: []const spice.Param, nums: []const bool) Allocator.Error![]const u8 {
    const e = stripOuter(v);
    if (number) return e; // `numeric` made it a number only if every call evaluates
    if (isLiteral(e)) return template(a, e, &.{});
    if (evaluates(e, params, nums)) return a.print("{{{s}}}", .{e});
    return substitute(a, v, params);
}

/// Whether Schemify evaluates SPICE expression `e` (outer braces or quotes stripped) in a
/// cell with parameters `params` (`nums`: which are numbers): a literal, or numbers,
/// operators and calls over number parameters only.
// ponytail: SPICE and Schemify share the arithmetic grammar; a deck operator Schemify lacks
// (`**`) fails the netlist with X-code instead of importing as text.
fn evaluates(e: []const u8, params: []const spice.Param, nums: []const bool) bool {
    if (isLiteral(e)) return true;
    if (e.len == 0 or mem.indexOfAny(u8, e, "{}'\"") != null) return false;
    var k: usize = 0;
    while (k < e.len) {
        const start = (ascii.isAlphabetic(e[k]) or e[k] == '_') and (k == 0 or !(isWordByte(e[k - 1]) or e[k - 1] == '.'));
        if (!start) {
            k += 1;
            continue;
        }
        var end = k;
        while (end < e.len and isWordByte(e[end])) end += 1;
        const word = e[k..end];
        const after = mem.trimStart(u8, e[end..], spice.ws);
        k = end;
        if (after.len > 0 and after[0] == '(') continue; // a function
        const known = for (params, nums) |p, n| {
            if (ascii.eqlIgnoreCase(p.name, word)) break n;
        } else false;
        if (!known) return false;
    }
    return true;
}

/// Per deck parameter: a number when its default is a literal and every `X` call's value
/// for it evaluates in the caller (`evaluates`); otherwise a string, which passes SPICE
/// text through (`X1 … w=wn` naming a `.param` of the bench). A fixed point: demoting a
/// parameter can demote the ones its cell passes it to.
fn numeric(a: Allocator, deck: *const Deck) Allocator.Error![]const bool {
    const num = try a.alloc(bool, deck.params_.len);
    for (num, deck.params_) |*n, p| n.* = isLiteral(stripOuter(p.value));
    var rounds: usize = 0;
    var changed = true;
    while (changed) : (rounds += 1) {
        assert(rounds <= deck.params_.len + 1); // each round demotes one at least
        changed = false;
        for (0..deck.cells()) |ci| {
            const c: u32 = @intCast(ci);
            const caller = deck.params(c);
            const caller_nums = num[deck.param_start[c]..deck.param_start[c + 1]];
            const devs = deck.devs(c);
            for (devs.lo..devs.hi) |d| {
                if (ascii.toLower(deck.dev_name[d][0]) != 'x') continue;
                const k = deck.findCell(deck.dev_sub[d]) orelse continue;
                const callee = deck.params(k);
                for (try spice.tokenize(a, deck.dev_rest[d])) |t| {
                    const key = keyOf(t.text) orelse continue;
                    for (callee, deck.param_start[k]..) |p, j| if (num[j] and ascii.eqlIgnoreCase(p.name, key) and
                        !evaluates(stripOuter(t.text[key.len + 1 ..]), caller, caller_nums))
                    {
                        num[j] = false;
                        changed = true;
                    };
                }
            }
        }
    }
    return num;
}

/// The symbol of library cell `l`, made on first use.
fn libSymbol(a: Allocator, l: *const LibCell, r: *Recognized) Allocator.Error!u32 {
    const s = &r.syms;
    for (0..s.len()) |i| {
        if (s.origin.items[i] == .lib and mem.eql(u8, s.stem.items[i], l.name) and mem.eql(u8, s.lib.items[i], l.lib)) return @intCast(i);
    }
    const i = try s.push(a, l.name, .lib, .box, l.pins, l.body);
    s.lib.items[i] = l.lib;
    return i;
}

/// The leaf symbol of origin `leaf` with stem `want` and template `format`, if made already.
fn findLeaf(r: *const Recognized, want: []const u8, format: []const u8) ?u32 {
    const s = &r.syms;
    for (0..s.len()) |i| {
        if (s.origin.items[i] == .leaf and mem.eql(u8, s.stem.items[i], want) and mem.eql(u8, s.format.items[i], format)) return @intCast(i);
    }
    return null;
}

/// The generated leaf for a card core cells cannot re-emit, keyed by drawing family and
/// pin count (`spice_nmos4`, `spice_diode`, `spice_e2`, …), created on first use.
fn leaf(a: Allocator, letter: u8, nodes: u32, toks: []const Tok, deck: *const Deck, r: *Recognized) Allocator.Error!u32 {
    const model = if (toks.len > 0) toks[0].text else "";
    const kind = deck.modelKind(model);
    const pnp = kind != null and mem.eql(u8, kind.?, "pnp");
    const key: []const u8, const fam: Family, const pins_: []const Pin = switch (letter) {
        'd' => if (nodes == 2) .{ "diode", .two, &two_pins } else try other(a, letter, nodes),
        'm' => if (nodes != 4) try other(a, letter, nodes) else if (try isPmos(a, model, kind)) .{ "pmos4", .pmos, &pmos_pins } else .{ "nmos4", .nmos, &nmos_pins },
        'q' => if (nodes != 3) try other(a, letter, nodes) else if (pnp) .{ "pnp", .pnp, &pnp_pins } else .{ "npn", .npn, &npn_pins },
        'j', 'z' => if (nodes == 3) .{ try a.print("{c}3", .{letter}), .npn, &npn_pins } else try other(a, letter, nodes),
        'e', 'g' => if (nodes == 4) .{ try a.print("{c}4", .{letter}), .vcxs, &vcxs_pins } else try other(a, letter, nodes),
        's' => if (nodes == 4) .{ "s4", .vsw, &vsw_pins } else try other(a, letter, nodes),
        't', 'o' => if (nodes == 4) .{ try a.print("{c}4", .{letter}), .tline, &tline_pins } else try other(a, letter, nodes),
        else => try other(a, letter, nodes),
    };
    const want = try a.print("spice_{s}", .{key});
    for (0..r.syms.len()) |i| {
        if (r.syms.origin.items[i] == .leaf and mem.eql(u8, r.syms.stem.items[i], want)) return @intCast(i);
    }
    const stem = try uniqueStem(a, want, &r.taken);
    if (fam != .box) return r.syms.push(a, stem, .leaf, fam, pins_, null);
    const lp = try leafPins(a, nodes);
    const dirs = try a.alloc(Dir, lp.names.len);
    @memset(dirs, .inout);
    const bp = try boxAuto(a, lp.names, dirs);
    const s = try r.syms.push(a, stem, .leaf, fam, bp.pins, bp.body);
    r.syms.format.items[s] = lp.format;
    return s;
}

/// Key and geometry of a leaf of no special family: two pins, or a box of `nodes` pins.
fn other(a: Allocator, letter: u8, nodes: u32) Allocator.Error!struct { []const u8, Family, []const Pin } {
    const key = try a.print("{c}{d}", .{ letter, nodes });
    return if (nodes == 2) .{ key, .two, &two_pins } else .{ key, .box, &.{} };
}

/// Pin names of a generated box leaf for a card of `nodes` nodes (`p1…pN`) and its
/// template when not the default. A node-less card gets one placeholder pin `p` (a
/// `.shprim` needs a pin; the layout no-connects it) that `{name} {args}` never prints.
fn leafPins(a: Allocator, nodes: u32) Allocator.Error!struct { names: []const []const u8, format: []const u8 } {
    if (nodes == 0) return .{ .names = &.{"p"}, .format = "{name} {args}" };
    const names = try a.alloc([]const u8, nodes);
    for (names, 1..) |*n, i| n.* = try a.print("p{d}", .{i});
    return .{ .names = names, .format = "" };
}

/// The leaf for XSPICE `A` cards of `nodes` nodes whose port shape needs template
/// `format` (`""`: plain nodes): a box with every node but the last an input. A shaped
/// leaf's stem carries a hash of its template (`spice_a3_1f2e3d4c`), since leaves are
/// shared by every import into a directory.
fn xspiceLeaf(a: Allocator, nodes: u32, format: []const u8, r: *Recognized) Allocator.Error!u32 {
    assert(nodes >= 1);
    const want = if (format.len == 0)
        try a.print("spice_a{d}", .{nodes})
    else
        try a.print("spice_a{d}_{x:0>8}", .{ nodes, @as(u32, @truncate(spice.fnv1a(spice.fnv_offset, format))) });
    if (findLeaf(r, want, format)) |s| return s;
    const stem = try uniqueStem(a, want, &r.taken);
    const lp = try leafPins(a, nodes);
    const dirs = try a.alloc(Dir, nodes);
    for (dirs, 1..) |*d, i| d.* = if (i < nodes) .in else .out;
    const bp = try boxAuto(a, lp.names, dirs);
    const s = try r.syms.push(a, stem, .leaf, .box, bp.pins, bp.body);
    r.syms.format.items[s] = format;
    return s;
}

/// The template of an XSPICE card `rest` (split as `x`) whose port shape `{pins}` cannot
/// print: the text before the model with each node a hole `{p<k>}` and literal braces
/// doubled, between `{name}` and `{args}` (the model on).
fn xspiceFormat(a: Allocator, rest: []const u8, x: spice.Xspice) Allocator.Error![]const u8 {
    assert(!x.plain and x.model <= rest.len);
    var f: ArrayList(u8) = .empty;
    try f.appendSlice(a, "{name} ");
    var at: u32 = 0;
    for (x.nodes, 1..) |r, k| {
        try f.appendSlice(a, try template(a, rest[at..r.lo], &.{}));
        try f.print(a, "{{p{d}}}", .{k});
        at = r.hi;
    }
    try f.appendSlice(a, try template(a, rest[at..x.model], &.{}));
    try f.appendSlice(a, "{args}");
    return f.items;
}

/// The stub leaf for `X` calls of undefined subckt `deck.dev_sub[d]` (one per name and node
/// count): pins `p1…pN` (a node-less call: see `leafPins`), `args` defaulting to the subckt
/// name.
fn stub(a: Allocator, deck: *const Deck, d: u32, r: *Recognized) Allocator.Error!u32 {
    const sub = deck.dev_sub[d];
    const lp = try leafPins(a, @intCast(deck.netsOf(d).len));
    const s_ = &r.syms;
    for (0..s_.len()) |i| {
        const s: u32 = @intCast(i);
        if (s_.origin.items[s] == .leaf and ascii.eqlIgnoreCase(s_.args_default.items[s], sub) and
            s_.pins(s).len == lp.names.len and mem.eql(u8, s_.format.items[s], lp.format)) return s;
    }
    const stem = try uniqueStem(a, sub, &r.taken);
    const dirs = try a.alloc(Dir, lp.names.len);
    @memset(dirs, .inout);
    const bp = try boxAuto(a, lp.names, dirs);
    const s = try r.syms.push(a, stem, .leaf, .box, bp.pins, bp.body);
    r.syms.args_default.items[s] = sub;
    r.syms.format.items[s] = lp.format;
    return s;
}

const testing = std.testing;

fn overOf(r: *const Recognized, d: u32, want: []const [2][]const u8) !void {
    const o = r.parts.overrides(d);
    try testing.expectEqual(want.len, o.len());
    for (want, o.lo..) |w, i| {
        try testing.expectEqualStrings(w[0], r.parts.over_key.items[i]);
        try testing.expectEqualStrings(w[1], r.parts.over_val.items[i]);
    }
}

test "box pins take their directive sides and face them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try spice.parse(a, ".subckt blk in out vdd vss b2\n*@ top vdd b2\n*@ bottom vss\nR1 in out 1\n.ends\n" ++
        "X1 a b c d e blk\nX2 n1 n2 n3 n4 n5 n6 n7 n8 eight\n");
    const r = try recognize(a, &d, &.{});
    const s = subSymbol(1);
    // Pins stay in port order: `in` (an input by name) left, `out` right, vdd then b2 on
    // top (directive order, left to right), vss below.
    const want = [_]Pin{ pin("in", -60, 0, .in), pin("out", 60, 0, .out), pin("vdd", -10, -40, .inout), pin("vss", 0, 40, .inout), pin("b2", 10, -40, .inout) };
    for (want, r.syms.pins(s)) |w, g| {
        try testing.expectEqualStrings(w.name, g.name);
        try testing.expectEqual(w.x, g.x);
        try testing.expectEqual(w.y, g.y);
    }
    try testing.expectEqual(Body{ -60, -40, 60, 40 }, r.syms.body.items[s]);
    // Eight pins on one side: the box widens so each still faces right (|x| > |y|).
    const eight = r.parts.sym.items[d.devs(0).lo + 1];
    for (r.syms.pins(eight)) |p| try testing.expect(p.x == 80 and @abs(p.y) < 80);
    try testing.expectEqual(-70, r.syms.pins(eight)[0].y);
}

test "xspice and node-less cards get their own templates" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try spice.parse(a, "A1 [a b] ~y nand1\nA2 a b y nand1\nA3 [c d] ~e nand2\nX1 g\nX2 h k=1\n");
    const r = try recognize(a, &d, &.{});
    const sym = struct {
        fn f(rr: *const Recognized, dk: *const Deck, i: u32) u32 {
            return rr.parts.sym.items[dk.devs(0).lo + i];
        }
    }.f;
    const s0 = sym(&r, &d, 0);
    try testing.expectEqualStrings("{name} [{p1} {p2}] ~{p3} {args}", r.syms.format.items[s0]);
    try testing.expect(mem.startsWith(u8, r.syms.stem.items[s0], "spice_a3_"));
    try overOf(&r, 0, &.{.{ "args", "nand1" }});
    try testing.expectEqualStrings("spice_a3", r.syms.stem.items[sym(&r, &d, 1)]);
    try testing.expectEqualStrings("", r.syms.format.items[sym(&r, &d, 1)]); // plain nodes print as {pins}
    try testing.expectEqual(s0, sym(&r, &d, 2)); // one leaf per port shape
    const ps = r.syms.pins(s0);
    try testing.expectEqual(3, ps.len);
    try testing.expect(ps[0].dir == .in and ps[1].dir == .in and ps[2].dir == .out);
    // Node-less calls of undefined subckts: one placeholder pin the template skips.
    const s3 = sym(&r, &d, 3);
    try testing.expectEqualStrings("{name} {args}", r.syms.format.items[s3]);
    try testing.expectEqual(1, r.syms.pins(s3).len);
    try overOf(&r, 3, &.{}); // args defaults to the subckt name
    try testing.expectEqualStrings("g", r.syms.args_default.items[s3]);
    try overOf(&r, 4, &.{.{ "args", "h k=1" }});
    try testing.expect(s3 != sym(&r, &d, 4));
}

test "literals follow the expression grammar" {
    for ([_][]const u8{ "1", "10u", "1.8", ".5", "2meg", "1e-6", "1E3k", "-3", "0.18U", "5mil" }) |ok|
        try testing.expect(isLiteral(ok));
    for ([_][]const u8{ "", "1.", "u", "1.8V", "10uF", "{w}", "'1u'", "1e", "w", "1k2" }) |bad|
        try testing.expect(!isLiteral(bad));
}

test "templates double braces and hole parameters" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const P = spice.Param;
    const p = struct {
        fn f(n: []const u8) P {
            return .{ .name = n, .value = "" };
        }
    }.f;
    try testing.expectEqualStrings("1k", try template(a, "1k", &.{}));
    try testing.expectEqualStrings("{{rval}}", try template(a, "{rval}", &.{}));
    try testing.expectEqualStrings("{{2*({w})}}", try template(a, "{2*W}", &.{p("w")}));
    try testing.expectEqualStrings("{{({wn})}}", try template(a, "wn", &.{p("wn")}));
    try testing.expectEqualStrings("w={{({wn})}} l={{({l})}}", try template(a, "w=wn l={l}", &.{ p("wn"), p("l") }));
    try testing.expectEqualStrings("v(k)*{{({k})}} + f({{({k})}})", try template(a, "v(k)*k + f(k)", &.{ p("k"), p("f") }));
    try testing.expectEqualStrings("10k", try template(a, "10k", &.{p("k")})); // a suffix is no identifier
    try testing.expectEqualStrings("2*k", stripOuter("{2*k}"));
    try testing.expectEqualStrings("a", stripOuter("'a'"));
}

test "faithful cards map to core, others to leaves" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try spice.parse(a, ".model dm d\nR1 a b 1k m=2\nD1 a 0 dm\nD2 a 0 dm area=2\nM1 d g 0 0 nch w=1u l=1u nf=2\n" ++
        "M2 d g 0 0 pch l=1u\nQ1 c b 0 qx\nX1 a b undefined_sub w=1\nE1 o 0 value={v(a)}\nJ1 d g s jm\n");
    const r = try recognize(a, &d, &.{});
    const want = [_][]const u8{ "res", "spice_diode", "diode", "nmos4", "spice_pmos4", "spice_npn", "undefined_sub", "spice_e2", "spice_j3" };
    try testing.expectEqual(want.len, d.dev_name.len);
    for (want, r.parts.sym.items) |w, s| try testing.expectEqualStrings(w, r.syms.stem.items[s]);
    try overOf(&r, 0, &.{ .{ "value", "1k" }, .{ "m", "2" } });
    try overOf(&r, 1, &.{.{ "args", "dm" }});
    const o3 = r.parts.overrides(3);
    try testing.expect(for (o3.lo..o3.hi) |i| {
        if (mem.eql(u8, r.parts.over_key.items[i], "extra") and mem.eql(u8, r.parts.over_val.items[i], "nf=2")) break true;
    } else false);
    try overOf(&r, 6, &.{.{ "args", "undefined_sub w=1" }});
    try testing.expectEqualStrings("undefined_sub", r.syms.args_default.items[r.parts.sym.items[6]]);
}
