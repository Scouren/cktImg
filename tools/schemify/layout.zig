//! Layout transform: one deck cell → the engine → a `Drawn` cell (instance origins and
//! orientations, wires, labels/ports, no-connects), in xschem units.
//!
//! The engine is told what every Schemify symbol looks like (`library`): one class per
//! symbol family, terminals at the symbol's pin positions turned into the engine's
//! canonical frame (principal terminals on the x axis) by `toCanonical`, one pin-to-pin
//! unit being `unit`, so the engine's integer grid is xschem units and every wire it draws
//! ends exactly on a Schemify pin. Each cell becomes a small SPICE deck of its own
//! (`cellDeck`): one card per device, written so the engine picks the class with the
//! device's geometry, with the cell's own net names where the engine can read them, so its
//! supply/ground/input/output heuristics see the names the designer wrote.
//!
//! Translating back: devices keep the engine's position; the Schemify orientation is the
//! engine's composed with the family's turn, and every pin is asserted to land where the
//! engine put it. Wires are its polylines split into segments; its labels, rail and port
//! symbols and hidden pins (a MOS bulk) become `label` records (the first on a subckt
//! port's net becomes the `port`); its no-connect crosses become `noconn`; junction dots
//! are dropped (Schemify derives them). A net nothing names but the cell needs by name (a
//! port, a `.global`, a net its code text mentions) gets a label on its first pin.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const mem = std.mem;
const ascii = std.ascii;
const engine = @import("NetlistParser");
const spice = @import("spice.zig");
const recognize = @import("recognize.zig");
const hints = @import("hints.zig");
const names_ = @import("names.zig");
const Deck = spice.Deck;
const Range = spice.Range;
const Recognized = recognize.Recognized;
const Family = recognize.Family;
const Pt = engine.Pt;

/// Devices the engine draws per conversion (cells in file order, each wholly drawn by the
/// engine or wholly labelled). With `cell_devices_max` it bounds a conversion's time and
/// memory.
// ponytail: guards from measurements; cells past them are drawn on a grid with every pin
// labelled, which stays correct.
pub const drawn_devices_max = 400;

/// Devices of one cell the engine draws; a bigger cell is labelled. The engine's time
/// grows steeply with a cell's size on irregular circuits (a random 100-MOSFET mesh takes
/// 3.9 s natively and 20 MB, a 200-MOSFET one 71 s and 90 MB), while the largest regular
/// cells of the fixtures and corpus (117 devices) take 0.9 s and 26 MB.
pub const cell_devices_max = 120;

/// One pin-to-pin length of a two-pin core symbol (`res`: `p` at y = -30, `n` at y = 30).
pub const unit = 60;

/// Orientation words indexed by `quarter_turns + 4 * mirrored` (format spec §3).
pub const orient_words = [8][]const u8{ "R0", "R90", "R180", "R270", "MR0", "MR90", "MR180", "MR270" };

pub const P = [2]i32;
/// An axis-aligned segment `[x1, y1, x2, y2]`.
pub const Seg = [4]i32;

/// Maps a symbol-local point through orientation `o` (mirror x, then clockwise quarter
/// turns, y down): format spec §3, and the engine's `Orient.apply`.
pub fn xform(o: u8, x: i32, y: i32) P {
    assert(o < 8);
    const q = (engine.Orient{ .rot = @intCast(o & 3), .mirror = o >= 4 }).apply(.{ .x = x, .y = y });
    return .{ q.x, q.y };
}

/// The orientation that applies `b`, then `a`.
pub fn compose(a: u8, b: u8) u8 {
    const probes = [_]P{ .{ 1, 0 }, .{ 0, 1 } };
    for (0..8) |o| {
        for (probes) |p| {
            const q = xform(b, p[0], p[1]);
            if (!mem.eql(i32, &xform(@intCast(o), p[0], p[1]), &xform(a, q[0], q[1]))) break;
        } else return @intCast(o);
    }
    unreachable; // the eight orientations are closed under composition
}

/// The label orientation whose text runs away from a symbol placed with orientation `o`,
/// at its pin `(px, py)` (symbol-local): along the pin's dominant axis, outwards.
pub fn facing(o: u8, px: i32, py: i32) u8 {
    var d: P = if (@abs(px) >= @abs(py)) .{ std.math.sign(px), 0 } else .{ 0, std.math.sign(py) };
    if (d[0] == 0 and d[1] == 0) d = .{ 1, 0 };
    const want = xform(o, d[0], d[1]);
    for (0..4) |k| if (mem.eql(i32, &xform(@intCast(k), 1, 0), &want)) return @intCast(k);
    unreachable; // a quarter turn
}

/// Turn from a family's Schemify symbol frame (vertical, like xschem's devices) into the
/// engine's canonical frame: R90 for the core families, none for the transmission line
/// (already horizontal) and generated boxes.
pub fn toCanonical(fam: Family) u8 {
    return switch (fam) {
        .tline, .box => 0,
        else => 1,
    };
}

/// Whether pin `k` of a `fam` symbol gets no wire: a MOSFET's bulk, drawn on the symbol
/// and joined by name.
fn hiddenPin(fam: Family, k: usize) bool {
    return (fam == .nmos or fam == .pmos) and k == 3;
}

/// Engine class names a family registers (all with the family's geometry): the device
/// vocabulary names of the cards `cellDeck` writes for it. Boxes register `b<symbol>`.
fn classNames(fam: Family) []const []const u8 {
    return switch (fam) {
        .two => &.{ "res", "cap", "ind", "vsource", "isource", "diode", "bsource" },
        .nmos => &.{"nmos"},
        .pmos => &.{"pmos"},
        .npn => &.{"npn"},
        .pnp => &.{"pnp"},
        .vcxs => &.{ "cvsource", "cisource" },
        .vsw => &.{"switch"},
        .tline => &.{"tline"},
        .box => &.{},
    };
}

/// Builds the engine's class library for the symbols of `rec`: each family's geometry
/// under its vocabulary names, one `b<s>` class per generated box symbol, and the rail
/// and port symbols the engine adds (one terminal each, at their origin). A class the
/// engine refuses is left out and named in `refused`: a cell using it then fails placement
/// and is drawn with labels, so a hostile netlist never panics the import.
pub fn library(gpa: Allocator, a: Allocator, rec: *const Recognized, refused: *ArrayList([]const u8)) Allocator.Error!engine.Library {
    var lib: engine.Library = .init(gpa);
    errdefer lib.deinit();
    lib.unit = unit;
    const syms = &rec.syms;
    for (0..syms.len()) |i| {
        const s: u32 = @intCast(i);
        const pins = syms.pins(s);
        if (pins.len == 0) continue; // a subckt with no ports: only node-less calls
        const fam = syms.family.items[s];
        const t = toCanonical(fam);
        const terms = try a.alloc(engine.library.Terminal, pins.len);
        for (pins, terms, 0..) |p, *term, k| {
            const q = xform(t, p.x, p.y);
            term.* = .{ .name = p.name, .at = .{ .x = q[0], .y = q[1] }, .hidden = hiddenPin(fam, k) };
        }
        // The body outline, for the engine's spacing: pins sit on it.
        const b = syms.body.items[s];
        const corners = [5]P{ .{ b[0], b[1] }, .{ b[2], b[1] }, .{ b[2], b[3] }, .{ b[0], b[3] }, .{ b[0], b[1] } };
        var outline: [5]Pt = undefined;
        for (corners, &outline) |c, *o| {
            const q = xform(t, c[0], c[1]);
            o.* = .{ .x = q[0], .y = q[1] };
        }
        const box_ops = [_]engine.library.DrawOp{.{ .polyline = &outline }};
        const ops = if (syms.shape.items[s] == .box) &box_ops else glyph: {
            const port_names = try a.alloc([]const u8, pins.len);
            for (pins, port_names) |p, *name| name.* = p.name;
            const glyph = try engine.block_symbols.draw(a, syms.shape.items[s], port_names, 20);
            break :glyph glyph.ops;
        };
        const block = try a.print("b{d}", .{s});
        const names: []const []const u8 = if (fam == .box) &.{block} else classNames(fam);
        for (names) |name| {
            _ = lib.register(.{ .name = name, .terminals = terms, .draw = ops }) catch |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                else => try refused.append(a, try a.print("the engine refused class {s} ({s}: {t}); its cells are drawn with labels", .{ name, syms.stem.items[s], e })),
            };
        }
    }
    const rails = [_]struct { []const u8, engine.library.Role }{
        .{ "vdd", .power_rail }, .{ "gnd", .ground_rail }, .{ "ipin", .input_port }, .{ "opin", .output_port },
    };
    const term = [_]engine.library.Terminal{.{ .name = "p", .at = .zero }};
    const line = [_]engine.library.DrawOp{.ln(-10, 0, 10, 0)};
    for (rails) |r| _ = lib.register(.{ .name = r[0], .role = r[1], .terminals = &term, .draw = &line }) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable, // one terminal, a fresh name
    };
    return lib;
}

/// A name marker: a `label`, or a `port` when `port`.
pub const Mark = struct { at: P, net: u32, orient: u8, port: bool = false };

/// One drawn cell: instance rows parallel to `deck.devs(c)`, wire segments, name markers
/// and no-connect marks, xschem units.
pub const Drawn = struct {
    x: ArrayList(i32) = .empty,
    y: ArrayList(i32) = .empty,
    /// Instance orientation, an index into `orient_words`.
    orient: ArrayList(u8) = .empty,
    /// Axis-aligned, non-zero length, `(x1, y1) < (x2, y2)`.
    wire: ArrayList(Seg) = .empty,
    mark: ArrayList(Mark) = .empty,
    noconn: ArrayList(P) = .empty,
    /// Bounding box of everything drawn (all zero when empty).
    bounds: [4]i32 = .{ 0, 0, 0, 0 },
    /// Nets with ≥ 2 device pins that the engine did not draw as a rail or join by name on
    /// purpose (two or more of its terminal symbols: a driver island's, rule R3).
    nets_multi: u32 = 0,
    /// Of those, nets whose pins one tree of wires connects (no label needed).
    nets_wired: u32 = 0,
    /// Why the engine was not used for this cell (then every pin is labelled), if it was not.
    fallback: ?[]const u8 = null,
    /// Pins the engine left with neither a wire nor a name (an engine bug); each got a label.
    strays: u32 = 0,
    /// One line per `*@` line of the cell the engine did not honour: its verdict.
    notes: ArrayList([]const u8) = .empty,

    fn addMark(out: *Drawn, a: Allocator, at: P, net: u32, orient: u8) Allocator.Error!void {
        try out.mark.append(a, .{ .at = at, .net = net, .orient = orient });
    }

    fn hasMark(out: *const Drawn, net: u32) bool {
        for (out.mark.items) |m| if (m.net == net) return true;
        return false;
    }

    fn namedAt(out: *const Drawn, net: u32, p: P) bool {
        for (out.mark.items) |m| if (m.net == net and eqlP(m.at, p)) return true;
        return false;
    }

    fn markedAt(out: *const Drawn, p: P) bool {
        for (out.mark.items) |m| if (eqlP(m.at, p)) return true;
        return false;
    }

    fn place(out: *Drawn, a: Allocator, x: i32, y: i32, o: u8) Allocator.Error!void {
        try out.x.append(a, x);
        try out.y.append(a, y);
        try out.orient.append(a, o);
    }
};

fn eqlP(p: P, q: P) bool {
    return p[0] == q[0] and p[1] == q[1];
}

/// Label orientation per engine text side (left, right, up, down): the editor writes a
/// label's text along its orientation's +x. A port draws its arrow and text the other way,
/// so a marker that becomes a port turns by R180.
const label_orient = [4]u8{ 2, 0, 3, 1 };

/// The engine's name for each local net of cell `c` (lowercase): the deck's own name where
/// the engine's tokenizer reads it as one field, `0` for ground (`gnd` too when the cell
/// has no `0`), else a fresh `n2s_<n>`.
pub fn netNames(a: Allocator, deck: *const Deck, c: u32) Allocator.Error![]const []const u8 {
    const n = deck.netCount(c);
    var has_zero = false;
    for (0..n) |k| has_zero = has_zero or mem.eql(u8, deck.netKey(c, @intCast(k)), "0");
    var taken: std.StringHashMapUnmanaged(void) = .empty;
    const out = try a.alloc([]const u8, n);
    for (out, 0..) |*o, k| {
        const key = deck.netKey(c, @intCast(k));
        var safe = key.len > 0 and key[0] != '$' and mem.indexOf(u8, key, "//") == null;
        for (key) |ch| safe = safe and ascii.isPrint(ch) and ch != ' ' and mem.indexOfScalar(u8, ",(){}='\";", ch) == null;
        var name: []const u8 = if (mem.eql(u8, key, "gnd"))
            (if (has_zero) try a.print("n2s_{d}", .{k}) else "0")
        else if (safe) key else try a.print("n2s_{d}", .{k});
        while ((try taken.getOrPut(a, name)).found_existing) name = try a.print("{s}_", .{name});
        o.* = name;
    }
    return out;
}

/// The SPICE deck the engine places for cell `c`: a title, a `.subckt b<s>` stub per box
/// symbol the cell uses, then one card per device in deck order, each under the name
/// `names.deviceNames` gives it (the designer's, so nothing depends on the order of the
/// instances), then the cell's `*@` lines with their names mapped likewise. Node-less
/// devices have nothing to lay out and are left out (`draw` places them).
pub fn cellDeck(a: Allocator, deck: *const Deck, rec: *const Recognized, c: u32, names: []const []const u8) Allocator.Error![]const u8 {
    const syms = &rec.syms;
    var text: ArrayList(u8) = .empty;
    try text.print(a, "* {s}\n", .{if (c == 0) "top" else deck.cell_name[c]});
    const devs = deck.devs(c);
    var boxes: ArrayList(u32) = .empty;
    for (devs.lo..devs.hi) |d| {
        const s = rec.parts.sym.items[d];
        if (deck.netsOf(@intCast(d)).len > 0 and syms.family.items[s] == .box and mem.indexOfScalar(u32, boxes.items, s) == null)
            try boxes.append(a, s);
    }
    mem.sort(u32, boxes.items, {}, std.sort.asc(u32));
    for (boxes.items) |s| {
        try text.print(a, ".subckt b{d}", .{s});
        for (syms.pins(s), 1..) |pin, k| {
            if (syms.shape.items[s] != .box) try text.print(a, " {s}", .{pin.name}) else try text.print(a, " p{d}", .{k});
        }
        try text.appendSlice(a, "\n.ends\n");
    }
    const dev_names = try names_.deviceNames(a, deck, rec, c);
    for (devs.lo..devs.hi, 0..) |d, i| {
        const nets = deck.netsOf(@intCast(d));
        if (nets.len == 0) continue;
        const card = try names_.cardOf(a, deck, rec, @intCast(d));
        try text.appendSlice(a, dev_names[i]);
        for (nets) |n| try text.print(a, " {s}", .{names[n]});
        try text.print(a, " {s}\n", .{card.tail});
    }
    try hints.write(a, &text, deck, c, dev_names, names);
    return text.items;
}

/// Draws cell `c` with the engine (or, when it refuses the deck, the cell has more than
/// `cell_devices_max` devices or `budget` of devices is spent, with every pin labelled).
/// `budget` drops by the cell's device count when the engine draws it. `gpa` backs the
/// engine's own work, freed before this returns; the result lives in `a`.
///
/// Asserts that the engine's result agrees with the deck it was given (device and pin
/// counts, every pin on its symbol's position), which would otherwise mean a wrong class
/// library.
pub fn draw(gpa: Allocator, a: Allocator, lib: *engine.Library, deck: *const Deck, rec: *const Recognized, c: u32, budget: *u32) Allocator.Error!Drawn {
    const devs = deck.devs(c);
    const names = try netNames(a, deck, c);
    var out: Drawn = .{};
    var wired_devs: u32 = 0;
    for (devs.lo..devs.hi) |d| wired_devs += @intFromBool(deck.netsOf(@intCast(d)).len > 0);
    if (wired_devs == 0) {
        // Node-less devices (an `X` on globals only) are placed below the drawing.
        for (devs.lo..devs.hi) |_| try out.place(a, 0, 0, 0);
        try nameNets(a, &out, deck, rec, c, &.{});
        growBounds(&out);
        try placeFree(a, &out, deck, rec, c);
        return out;
    }
    if (wired_devs > budget.* or wired_devs > cell_devices_max) {
        out.fallback = try a.print("over the {d} devices the engine draws per cell, or the {d} per import", .{ cell_devices_max, drawn_devices_max });
        try labelled(a, &out, deck, rec, c);
        return out;
    }
    const text = try cellDeck(a, deck, rec, c, names);
    var diag: engine.netlist.Diagnostic = .{};
    var placed = engine.place(gpa, &engine.Config.default, lib, &.{text}, &diag) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            out.fallback = try a.print("the engine refused the cell: line {d}: {t} near '{s}'", .{ diag.line, e, diag.token() });
            try labelled(a, &out, deck, rec, c);
            return out;
        },
    };
    defer placed.deinit();
    budget.* -= wired_devs;
    try hints.notes(gpa, a, &out.notes, deck, c, text, &placed, lib);
    try translate(a, &out, &placed, lib, deck, rec, c, names);
    try placeFree(a, &out, deck, rec, c);
    assert(out.x.items.len == devs.len());
    return out;
}

/// Places the node-less devices of cell `c` (nothing to wire, so the engine never sees
/// them) in a row below everything drawn, each pin no-connected: a 0-port subckt's call has
/// none, a stub's one pin is a placeholder its template never prints.
fn placeFree(a: Allocator, out: *Drawn, deck: *const Deck, rec: *const Recognized, c: u32) Allocator.Error!void {
    const syms = &rec.syms;
    const devs = deck.devs(c);
    assert(out.x.items.len == devs.len());
    var x = @divFloor(out.bounds[0], 10) * 10;
    const y = @divFloor(out.bounds[3], 10) * 10 + 2 * unit;
    for (devs.lo..devs.hi, 0..) |d, i| {
        if (deck.netsOf(@intCast(d)).len > 0) continue;
        const s = rec.parts.sym.items[d];
        const b = syms.body.items[s];
        // The body's top-left corner at the cursor.
        const ox = x - b[0];
        const oy = y - b[1];
        out.x.items[i] = ox;
        out.y.items[i] = oy;
        out.orient.items[i] = 0;
        for (syms.pins(s)) |p| try out.noconn.append(a, .{ ox + p.x, oy + p.y });
        x += b[2] - b[0] + unit;
    }
    growBounds(out);
    assert(out.bounds[1] <= out.bounds[3]);
}

const Hidden = struct { at: P, net: u32, face: u8 };
const Face = struct { at: P, face: u8 };
const First = ?Face;

fn faceAt(faces: []const Face, p: P) u8 {
    for (faces) |f| if (eqlP(f.at, p)) return f.face;
    return 0;
}

fn onAny(wires: []const Seg, p: P) bool {
    for (wires) |w| if (onSeg(p, w)) return true;
    return false;
}

/// Fills `out` from the engine's placement `placed` of cell `c`.
fn translate(a: Allocator, out: *Drawn, placed: *const engine.Placed, lib: *const engine.Library, deck: *const Deck, rec: *const Recognized, c: u32, names: []const []const u8) Allocator.Error!void {
    const syms = &rec.syms;
    const devs = deck.devs(c);
    const n = devs.len();
    const none = std.math.maxInt(u32);
    var ids: std.StringHashMapUnmanaged(u32) = .empty;
    for (names, 0..) |name, k| try ids.putNoClobber(a, name, @intCast(k));
    // The engine reports only the nets it was given, plus its ground `0` when the cell has none.
    const Local = struct {
        ids: *const std.StringHashMapUnmanaged(u32),
        p: *const engine.Placed,
        fn of(l: @This(), net: u32) ?u32 {
            return if (net == engine.placed.no_net) null else l.ids.get(l.p.net_name[net]);
        }
    };
    const local: Local = .{ .ids = &ids, .p = placed };
    // The engine lists a driver island's source after the symbols it added, so devices are
    // matched by name (`names.deviceNames`), the added symbols unnamed.
    var rows: std.StringHashMapUnmanaged(u32) = .empty;
    for (try names_.deviceNames(a, deck, rec, c), 0..) |name, r| if (name.len > 0) try rows.putNoClobber(a, name, @intCast(r));
    const at_row = try a.alloc(u32, n);
    @memset(at_row, none);
    var added: ArrayList(u32) = .empty;
    for (0..placed.deviceCount()) |i| {
        if (rows.get(placed.dev_name[i])) |r| {
            assert(r < n and at_row[r] == none);
            at_row[r] = @intCast(i);
        } else try added.append(a, @intCast(i));
    }
    // Pins per local net, in device order (for naming, wiredness and no-connects).
    const pin_pts = try a.alloc(ArrayList(P), names.len);
    @memset(pin_pts, .empty);
    var hidden: ArrayList(Hidden) = .empty;
    // Every pin point with the orientation a label there reads best in.
    var faces: ArrayList(Face) = .empty;
    for (devs.lo..devs.hi, 0..) |d, row| {
        const nets = deck.netsOf(@intCast(d));
        assert((at_row[row] != none) == (nets.len > 0)); // the engine dropped no device
        if (nets.len == 0) {
            try out.place(a, 0, 0, 0);
            continue;
        }
        const i = at_row[row];
        const s = rec.parts.sym.items[d];
        const pos = placed.dev_pos[i];
        const ori = placed.dev_orient[i];
        const o = compose(@as(u8, ori.rot) + 4 * @as(u8, @intFromBool(ori.mirror)), toCanonical(syms.family.items[s]));
        try out.place(a, pos.x, pos.y, o);
        const lo, const hi = placed.pinRange(i);
        const pins = syms.pins(s);
        assert(hi - lo == pins.len);
        for (pins, 0..) |p, k| {
            const dd = xform(o, p.x, p.y);
            const at: P = .{ pos.x + dd[0], pos.y + dd[1] };
            assert(placed.pin_xy[lo + k].eql(.{ .x = at[0], .y = at[1] }));
            const net = nets[k];
            assert(local.of(placed.pin_net[lo + k]) == net);
            const face = facing(o, p.x, p.y);
            try faces.append(a, .{ .at = at, .face = face });
            if (hiddenPin(syms.family.items[s], k))
                try hidden.append(a, .{ .at = at, .net = net, .face = face })
            else
                try pin_pts[net].append(a, at);
        }
    }
    const rails = try a.alloc(bool, names.len);
    @memset(rails, false);
    // Terminal symbols per net: the engine splits a driver island's net (R3: the source
    // apart, left of the circuit) and puts one on each piece, so two mean by name on purpose.
    const terms = try a.alloc(u32, names.len);
    @memset(terms, 0);
    for (added.items) |i| {
        const lo, _ = placed.pinRange(i);
        const net = local.of(placed.pin_net[lo]).?; // a terminal symbol sits on a net of the cell
        const orient: u8, const rail: bool = switch (lib.at(placed.dev_class[i]).role) {
            .power_rail => .{ 3, true },
            .ground_rail => .{ 1, true },
            .input_port => .{ 2, false },
            .output_port => .{ 0, false },
            .none => unreachable, // the engine adds only terminal symbols
        };
        rails[net] = rails[net] or rail;
        terms[net] += @intFromBool(!rail);
        const at = placed.pin_xy[lo];
        try out.addMark(a, .{ at.x, at.y }, net, orient);
    }
    for (placed.labels) |l| {
        const net = ids.get(placed.net_name[l.net]).?; // a label names a net of the cell
        try out.addMark(a, .{ l.at.x, l.at.y }, net, label_orient[@backingInt(l.side)]);
    }
    // A hidden pin (MOS bulk) gets no wire, so it is joined by name; a net the engine wired
    // whole and left unnamed then needs its name on the wired piece too.
    for (hidden.items) |h| {
        if (!out.hasMark(h.net) and pin_pts[h.net].items.len > 0) {
            const p = pin_pts[h.net].items[0];
            try out.addMark(a, p, h.net, faceAt(faces.items, p));
        }
        try out.addMark(a, h.at, h.net, h.face);
    }
    const polys = try a.alloc(ArrayList([]const Pt), names.len);
    @memset(polys, .empty);
    const wire_of = try a.alloc(Range, names.len);
    @memset(wire_of, .{ .lo = 0, .hi = 0 });
    for (0..placed.netCount()) |w| {
        var segs = placed.segments(w);
        const net = ids.get(placed.net_name[w]) orelse {
            assert(segs.next() == null); // no wires on a net the cell does not have
            continue;
        };
        var net_wires: ArrayList(Seg) = .empty;
        while (segs.next()) |poly| {
            for (poly[0 .. poly.len - 1], poly[1..]) |p, q| {
                assert(p.x == q.x or p.y == q.y); // Manhattan
                try net_wires.append(a, .{ p.x, p.y, q.x, q.y });
            }
            try polys[net].append(a, poly);
        }
        const start: u32 = @intCast(out.wire.items.len);
        try out.wire.appendSlice(a, try merged(a, net_wires.items));
        wire_of[net] = .{ .lo = start, .hi = @intCast(out.wire.items.len) };
    }
    for (pin_pts, 0..) |pins, net| if (pins.items.len >= 2 and !rails[net] and terms[net] < 2) {
        out.nets_multi += 1;
        out.nets_wired += @intFromBool(try wired(a, pins.items, polys[net].items));
    };
    // The engine should leave no pin of a net without a wire or a name. Such a net is
    // joined by name instead: a label on every pin.
    for (pin_pts, 0..) |pins, ni| {
        const net: u32 = @intCast(ni);
        if (pins.items.len < 2) continue;
        const mine = out.wire.items[wire_of[net].lo..wire_of[net].hi];
        var strays: u32 = 0;
        for (pins.items) |p| strays += @intFromBool(!onAny(mine, p) and !out.namedAt(net, p));
        if (strays == 0) continue;
        out.strays += strays;
        for (pins.items) |p| if (!out.namedAt(net, p)) try out.addMark(a, p, net, faceAt(faces.items, p));
    }
    // Every net of two or more pins carries its name (cards and code may name it, and the
    // designer wrote it): one label where it reads as a net name, else on its first pin.
    for (pin_pts, 0..) |pins, ni| {
        const net: u32 = @intCast(ni);
        if (pins.items.len < 2 or out.hasMark(net)) continue;
        if (try spot(a, out.wire.items, wire_of[net])) |p|
            try out.addMark(a, p, net, 0)
        else
            try out.addMark(a, pins.items[0], net, faceAt(faces.items, pins.items[0]));
    }
    out.bounds = if (placed.bounds(lib)) |r| .{ r.min.x, r.min.y, r.max.x, r.max.y } else .{ 0, 0, 0, 0 };
    const first = try a.alloc(First, names.len);
    for (first, pin_pts) |*f, pins| f.* = if (pins.items.len > 0) .{ .at = pins.items[0], .face = faceAt(faces.items, pins.items[0]) } else null;
    try nameNets(a, out, deck, rec, c, first);
    // The engine's crosses, plus one on any other lone pin it missed and nothing names.
    for (placed.no_connects) |q| {
        const p: P = .{ q.x, q.y };
        if (!out.markedAt(p)) try out.noconn.append(a, p);
    }
    for (pin_pts, 0..) |pins, net| {
        if (pins.items.len != 1) continue;
        const p = pins.items[0];
        if (out.markedAt(p) or onAny(out.wire.items[wire_of[net].lo..wire_of[net].hi], p)) continue;
        if (for (out.noconn.items) |q| {
            if (eqlP(p, q)) break true;
        } else false) continue;
        out.strays += 1;
        try out.noconn.append(a, p);
    }
    growBounds(out);
}

const Line = struct { vertical: bool, at: i32, lo: i32, hi: i32 };

fn lineLess(_: void, x: Line, y: Line) bool {
    if (x.vertical != y.vertical) return !x.vertical;
    if (x.at != y.at) return x.at < y.at;
    if (x.lo != y.lo) return x.lo < y.lo;
    return x.hi < y.hi;
}

/// One net's axis-aligned segments without overlaps: each normalized so `(x1, y1) <
/// (x2, y2)` (the format's wire order), zero-length ones dropped, and collinear ones that
/// overlap cut at every original endpoint into disjoint pieces. Every original endpoint
/// stays an endpoint, so connectivity is unchanged (netlist spec §3: joining two pieces
/// through a junction would turn it into an interior crossing, which does not connect).
fn merged(a: Allocator, segs: []const Seg) Allocator.Error![]const Seg {
    var lines: ArrayList(Line) = .empty;
    for (segs) |s0| {
        const swap = s0[2] < s0[0] or (s0[2] == s0[0] and s0[3] < s0[1]);
        const s: Seg = if (swap) .{ s0[2], s0[3], s0[0], s0[1] } else s0;
        if (s[0] == s[2] and s[1] == s[3]) continue;
        try lines.append(a, if (s[1] == s[3])
            .{ .vertical = false, .at = s[1], .lo = s[0], .hi = s[2] }
        else
            .{ .vertical = true, .at = s[0], .lo = s[1], .hi = s[3] });
    }
    const ls = lines.items;
    mem.sort(Line, ls, {}, lineLess);
    var out: ArrayList(Seg) = try .initCapacity(a, ls.len);
    var cuts: ArrayList(i32) = .empty;
    var k: usize = 0;
    while (k < ls.len) {
        const vertical = ls[k].vertical;
        const at = ls[k].at;
        var end = k;
        while (end < ls.len and ls[end].vertical == vertical and ls[end].at == at) end += 1;
        cuts.clearRetainingCapacity();
        for (ls[k..end]) |l| try cuts.appendSlice(a, &.{ l.lo, l.hi });
        std.sort.heap(i32, cuts.items, {}, std.sort.asc(i32));
        // Sweep the union of the intervals; emit the pieces between consecutive cuts.
        var lo = ls[k].lo;
        var hi = ls[k].hi;
        for (k + 1..end + 1) |j| {
            const sentinel = j == end;
            if (!sentinel and ls[j].lo <= hi) {
                hi = @max(hi, ls[j].hi);
                continue;
            }
            var prev: ?i32 = null;
            for (cuts.items) |cut| {
                if (cut < lo or cut > hi or (prev != null and prev.? == cut)) continue;
                if (prev) |p| try out.append(a, if (vertical) .{ at, p, at, cut } else .{ p, at, cut, at });
                prev = cut;
            }
            if (!sentinel) {
                lo = ls[j].lo;
                hi = ls[j].hi;
            }
        }
        k = end;
    }
    for (out.items) |s| assert((s[0] < s[2] or (s[0] == s[2] and s[1] < s[3])) and (s[0] == s[2] or s[1] == s[3]));
    return out.items;
}

/// Whether point `p` lies on segment `w` (normalized, as `merged` leaves it), ends included.
fn onSeg(p: P, w: Seg) bool {
    return w[0] <= p[0] and p[0] <= w[2] and w[1] <= p[1] and p[1] <= w[3];
}

/// Where to write a net's name on its wires `wires[mine]`: the middle of one of its four
/// longest segments that no other net's wire passes through (a name there would join that
/// wire too). Null when every candidate tried is crossed.
fn spot(a: Allocator, wires: []const Seg, mine: Range) Allocator.Error!?P {
    const order = try a.alloc(u32, mine.len());
    for (order, mine.lo..) |*o, i| o.* = @intCast(i);
    mem.sort(u32, order, wires, struct {
        fn lt(ws: []const Seg, x: u32, y: u32) bool {
            const lx = (ws[x][2] - ws[x][0]) + (ws[x][3] - ws[x][1]);
            const ly = (ws[y][2] - ws[y][0]) + (ws[y][3] - ws[y][1]);
            return lx > ly or (lx == ly and x < y);
        }
    }.lt);
    for (order[0..@min(order.len, 4)]) |i| {
        const w = wires[i];
        const m: P = .{ @divFloor(w[0] + w[2], 2), @divFloor(w[1] + w[3], 2) };
        const clear = for (wires, 0..) |o, j| {
            if ((j < mine.lo or j >= mine.hi) and onSeg(m, o)) break false;
        } else true;
        if (clear) return m;
    }
    return null;
}

fn onPoly(p: Pt, poly: []const Pt) bool {
    for (poly[0 .. poly.len - 1], poly[1..]) |s, t| {
        if (@min(s.x, t.x) <= p.x and p.x <= @max(s.x, t.x) and @min(s.y, t.y) <= p.y and p.y <= @max(s.y, t.y)) return true;
    }
    return false;
}

fn root(parent: []u32, start: u32) u32 {
    var i = start;
    while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
    }
    return i;
}

/// Whether one tree of `polys` connects every point of `pins` (union-find over the pins
/// and polylines; a pin or a polyline end on another polyline joins it).
fn wired(a: Allocator, pins: []const P, polys: []const []const Pt) Allocator.Error!bool {
    const np: u32 = @intCast(pins.len);
    const parent = try a.alloc(u32, pins.len + polys.len);
    for (parent, 0..) |*p, i| p.* = @intCast(i);
    for (polys, 0..) |poly, j| {
        const pj = np + @as(u32, @intCast(j));
        for (pins, 0..) |p, i| if (onPoly(.{ .x = p[0], .y = p[1] }, poly)) {
            parent[root(parent, @intCast(i))] = root(parent, pj);
        };
        for (polys[j + 1 ..], j + 1..) |other, k| {
            const touch = onPoly(poly[0], other) or onPoly(poly[poly.len - 1], other) or
                onPoly(other[0], poly) or onPoly(other[other.len - 1], poly);
            if (touch) parent[root(parent, pj)] = root(parent, np + @as(u32, @intCast(k)));
        }
    }
    const r0 = root(parent, 0);
    for (1..pins.len) |i| if (root(parent, @intCast(i)) != r0) return false;
    return true;
}

/// Gives every net the cell needs by name a marker (a label on its first pin, `first[n]`,
/// for a net nothing named yet; a port off the drawing for a port net with no pin), then
/// turns the first marker of each port net into its `port`. A net is needed by name when
/// it is a port, a global (`.global`, `…!`, `0`), on a pin of a generated leaf (which
/// re-emits its card's node names as text) or a word of the cell's card or code text
/// (`v(a1)` in a `B` expression, `.save v(out)`); any other lone pin keeps its cross.
fn nameNets(a: Allocator, out: *Drawn, deck: *const Deck, rec: *const Recognized, c: u32, first: []const First) Allocator.Error!void {
    const words = try textWords(a, deck, c);
    const ports = deck.ports(c);
    const on_leaf = try a.alloc(bool, deck.netCount(c));
    @memset(on_leaf, false);
    const devs = deck.devs(c);
    for (devs.lo..devs.hi) |d| {
        if (rec.syms.origin.items[rec.parts.sym.items[d]] != .leaf) continue;
        for (deck.netsOf(@intCast(d))) |n| on_leaf[n] = true;
    }
    for (first, 0..) |f, ni| {
        const n: u32 = @intCast(ni);
        const face = f orelse continue;
        if (out.hasMark(n)) continue;
        const key = deck.netKey(c, n);
        const needs = (c > 0 and mem.indexOfScalar(u32, ports, n) != null) or mem.eql(u8, key, "0") or
            mem.endsWith(u8, key, "!") or deck.isGlobal(key) or on_leaf[n] or words.contains(key);
        if (needs) try out.addMark(a, face.at, n, face.face);
    }
    if (c == 0) return;
    var free_y = out.bounds[1];
    for (ports) |n| {
        for (out.mark.items) |*m| {
            if (m.net != n) continue;
            m.port = true;
            m.orient = (m.orient + 2) % 4;
            break;
        } else {
            // No device on the net: a port left of the drawing, clear of every wire.
            try out.mark.append(a, .{ .at = .{ out.bounds[0] - 2 * unit, free_y }, .net = n, .orient = 2, .port = true });
            free_y += unit;
        }
    }
}

/// Lowercase words of cell `c`'s code text and card text after the nodes (the net names
/// they may mention, e.g. `v(out)`).
fn textWords(a: Allocator, deck: *const Deck, c: u32) Allocator.Error!std.StringHashMapUnmanaged(void) {
    var words: std.StringHashMapUnmanaged(void) = .empty;
    const seps = spice.ws ++ "(),='\"{}";
    for (deck.code, deck.code_cell) |t, cc| if (cc == c) {
        var it = mem.tokenizeAny(u8, t, seps);
        while (it.next()) |w| try words.put(a, try ascii.allocLowerString(a, w), {});
    };
    const devs = deck.devs(c);
    for (deck.dev_rest[devs.lo..devs.hi]) |t| {
        var it = mem.tokenizeAny(u8, t, seps);
        while (it.next()) |w| try words.put(a, try ascii.allocLowerString(a, w), {});
    }
    return words;
}

/// The fallback drawing: devices in rows in deck order, unrotated, each symbol's body clear
/// of the others' (so no two pins share a point), every pin labelled with its net (labels
/// with equal names connect, so this is always correct; a node-less stub's placeholder pin
/// is no-connected).
fn labelled(a: Allocator, out: *Drawn, deck: *const Deck, rec: *const Recognized, c: u32) Allocator.Error!void {
    const syms = &rec.syms;
    const row_width = 24 * unit;
    var x: i32 = 0;
    var y: i32 = 0;
    var row_height: i32 = 0;
    const devs = deck.devs(c);
    for (devs.lo..devs.hi) |d| {
        const s = rec.parts.sym.items[d];
        const b = syms.body.items[s];
        assert(b[0] <= b[2] and b[1] <= b[3]);
        if (x > 0 and x + (b[2] - b[0]) > row_width) {
            y += row_height + unit;
            x = 0;
            row_height = 0;
        }
        // The body's top-left corner at the cursor.
        const ox = x - b[0];
        const oy = y - b[1];
        try out.place(a, ox, oy, 0);
        const nets = deck.netsOf(@intCast(d));
        for (syms.pins(s), 0..) |p, k| {
            const at: P = .{ ox + p.x, oy + p.y };
            if (k < nets.len)
                try out.addMark(a, at, nets[k], facing(0, p.x, p.y))
            else
                try out.noconn.append(a, at); // a node-less stub's placeholder pin
        }
        x += b[2] - b[0] + unit;
        row_height = @max(row_height, b[3] - b[1]);
    }
    // Nets of two or more pins, all joined by name here (the layout report's denominator).
    const pins = try a.alloc(u32, deck.netCount(c));
    @memset(pins, 0);
    for (deck.dev_net[deck.dev_net_start[devs.lo]..deck.dev_net_start[devs.hi]]) |n| pins[n] += 1;
    for (pins) |k| out.nets_multi += @intFromBool(k >= 2);
    growBounds(out);
    const first = try a.alloc(First, deck.netCount(c));
    @memset(first, null);
    try nameNets(a, out, deck, rec, c, first);
    growBounds(out);
    assert(out.x.items.len == devs.len());
}

/// Grows `out.bounds` over every instance origin, wire end and marker.
fn growBounds(out: *Drawn) void {
    var b = out.bounds;
    var empty = b[0] == 0 and b[1] == 0 and b[2] == 0 and b[3] == 0;
    const Grow = struct {
        fn f(bb: *[4]i32, e: *bool, p: P) void {
            if (e.*) {
                bb.* = .{ p[0], p[1], p[0], p[1] };
                e.* = false;
            }
            bb.* = .{ @min(bb[0], p[0]), @min(bb[1], p[1]), @max(bb[2], p[0]), @max(bb[3], p[1]) };
        }
    };
    for (out.x.items, out.y.items) |x, y| Grow.f(&b, &empty, .{ x, y });
    for (out.wire.items) |w| {
        Grow.f(&b, &empty, .{ w[0], w[1] });
        Grow.f(&b, &empty, .{ w[2], w[3] });
    }
    for (out.mark.items) |m| Grow.f(&b, &empty, m.at);
    for (out.noconn.items) |p| Grow.f(&b, &empty, p);
    assert(b[0] <= b[2] and b[1] <= b[3]);
    out.bounds = b;
}

const testing = std.testing;

test "compose applies the right operand first" {
    for (0..8) |ai| for (0..8) |bi| {
        const a: u8 = @intCast(ai);
        const b: u8 = @intCast(bi);
        const o = compose(a, b);
        for ([_]P{ .{ 1, 0 }, .{ 0, 1 }, .{ 3, -7 } }) |p| {
            const q = xform(b, p[0], p[1]);
            try testing.expectEqual(xform(a, q[0], q[1]), xform(o, p[0], p[1]));
        }
    };
    // R90 then MR0 is MR270 (a reflection across the diagonal); R0 is neutral.
    try testing.expectEqual(7, compose(4, 1));
    for (0..8) |o| try testing.expectEqual(o, compose(@intCast(o), 0));
}

test "labels face away from their symbol" {
    // nmos4 bulk (20, 0): text to the right at R0, to the left when mirrored, down at R90.
    try testing.expectEqual(0, facing(0, 20, 0));
    try testing.expectEqual(2, facing(4, 20, 0));
    try testing.expectEqual(1, facing(1, 20, 0));
    // res p (0, -30): text up at R0 (orientation R270 runs +x upwards).
    try testing.expectEqual(3, facing(0, 0, -30));
    try testing.expectEqual(0, facing(0, 0, 0)); // a pin at the origin reads left to right
}

test "the canonical turn puts core two-pins on the x axis" {
    // res p (0,-30) → (30,0), n (0,30) → (-30,0): one unit apart on the x axis.
    try testing.expectEqual(P{ 30, 0 }, xform(toCanonical(.two), 0, -30));
    try testing.expectEqual(P{ -30, 0 }, xform(toCanonical(.two), 0, 30));
    // nmos4: drain right, gate up, source left (the engine's MOS frame), bulk below.
    const t = toCanonical(.nmos);
    try testing.expectEqual(P{ 30, 20 }, xform(t, 20, -30));
    try testing.expectEqual(P{ 0, -20 }, xform(t, -20, 0));
    try testing.expectEqual(P{ -30, 20 }, xform(t, 20, 30));
    try testing.expectEqual(P{ 0, 20 }, xform(t, 20, 0));
}

test "merged cuts overlaps at every endpoint" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const w = try merged(arena.allocator(), &.{
        .{ 30, 0, 0, 0 }, // reversed
        .{ 10, 0, 60, 0 }, // overlaps it
        .{ 60, 0, 90, 0 }, // touches it: stays a separate piece
        .{ 10, 0, 60, 0 }, // a duplicate
        .{ 0, 10, 0, -20 }, // vertical through the start
        .{ 5, 5, 5, 5 }, // zero length
        .{ 0, 40, 0, 50 }, // a gap on the same vertical line
    });
    try testing.expectEqualSlices(Seg, &.{
        .{ 0, 0, 10, 0 }, .{ 10, 0, 30, 0 }, .{ 30, 0, 60, 0 }, .{ 60, 0, 90, 0 }, .{ 0, -20, 0, 10 }, .{ 0, 40, 0, 50 },
    }, w);
    try testing.expectEqual(0, (try merged(arena.allocator(), &.{})).len);
}

test "net names keep readable names and fold ground" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const d = try spice.parse(a, "R1 a gnd 1\nR2 a(1) b 1\nR3 b 0 1\n");
    const names = try netNames(a, &d, 0);
    const by = struct {
        fn f(dk: *const Deck, ns: []const []const u8, k: []const u8) []const u8 {
            for (0..dk.netCount(0)) |n| if (mem.eql(u8, dk.netKey(0, @intCast(n)), k)) return ns[n];
            unreachable;
        }
    }.f;
    try testing.expectEqualStrings("a", by(&d, names, "a"));
    try testing.expectEqualStrings("0", by(&d, names, "0"));
    try testing.expect(mem.startsWith(u8, by(&d, names, "gnd"), "n2s_")); // gnd must not merge with 0 here
    try testing.expect(mem.startsWith(u8, by(&d, names, "a(1)"), "n2s_"));
    const lone = try spice.parse(a, "R1 a gnd 1\n");
    const ln = try netNames(a, &lone, 0);
    try testing.expect(for (ln) |n| {
        if (mem.eql(u8, n, "0")) break true;
    } else false); // a lone gnd is ground
}
