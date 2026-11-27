//! Op-amp circuits (issue #8, stage 3): where the devices of a circuit of
//! amplifier blocks and two-pin parts stand, as people draw one. In: the
//! netlist, its roles, each device's class. Out: a place and a turn for
//! every drawn device, or nothing when the circuit is of another kind. The
//! steps of the procedure are `opamp_grow.zig`'s. Lengths are hundredths
//! of a unit on a quarter-unit grid, y down.
//!
//! Human Rules:
//! - opamp.1 (invariant) A deck with an admitted line that places or turns a device
//!   (`upright`, `bridge`, `row`, `above`, `order`, `face`, `cell`, a
//!   strong `at`) is laid by its lines, not along the signal; a stay
//!   (`weak at`) is no such line. `steered`
//! - opamp.2 (habit) A circuit whose every drawn device is a two-pin part
//!   or an amplifier block (one or two inputs and one output by their port
//!   names, the rest rails), with at least one block, is drawn along its
//!   signal, not on the lattice: its blocks and parts all bridge. People:
//!   199 of 5,263 hand-drawn schematics are of this kind; laid so, 170
//!   such circuits cross 14 wires where the lattice crossed 306 and their
//!   hand drawings 6. `applies`, `place`
//!   Narrowing: a block whose symbol has an input right of its output, or
//!   a pin count other than its class's, leaves the circuit on the
//!   lattice (`place`).
//! - opamp.3 (unmeasured) The groups the procedure begins stand one under
//!   the other in the order begun, 1.5 units apart; a group a part joins to
//!   a node of an earlier one stands with that part's end at the node's x.
//!   `place`
//! - opamp.4 (habit, bounded) A capacitor circuit of amplifier blocks,
//!   resistors, voltage sources and externally controlled MOS switches
//!   follows the signal too: AG759/762/799. A control net may touch only
//!   MOS gates and a voltage source to a rail; a channel cannot touch a
//!   supply. Driven stages (AG807/2209), diode/current steering (AG1042)
//!   and complementary parallel pairs (AG751) stay on the lattice.
//!   These are admission limits, not a universal definition of a switch.
//!   Only D/S enter the path; flat gates face up. Local return loops may
//!   turn a channel upright (AG800/801). `applies`, `externalGate`, `place`
//!   A MOS class must have a flat, one-unit channel and its gate above it;
//!   its whole symbol must fit the reserved switch frame. Other caller
//!   frames retain lattice placement (`place`, `channelFits`).
//!
//! Data: reads the netlist's existing pin rows and roles. `place` owns one
//! optional channel midpoint per device until export (library coordinates,
//! `Pt` is two i32s); null means no MOS. D/S alone append path incidences.
//! The phase arena owns the table; no electrical pins or classes change.
//!
//! Contents:
//! - `pub fn applies(nl: *const Netlist, roles: []const Role, drawn: []const bool) bool`
//! - `pub fn steered`
//! - `pub fn place`
//! - for `opamp_grow.zig`: `pub const none`, `unit`, `quarter`, `tries`; `pub const P`, `R`, `Kind`, `Link`, `Pin`, `Block`, `Two`, `Canvas`, `Put`
//! - `pub const Placer = struct`, `Placer.canvas`, `Placer.free`, `Placer.wire`, `Placer.add`, `Placer.anchor`, `Placer.aOn`, `Placer.put`
//! - `pub fn partRect(kind: Kind, cx: i32, cy: i32, tall: bool) R`, `pub fn ceilQuarter(v: i32) i32`, `pub fn roundEven(num: i64, den: i64) i32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const pinned = @import("pinned.zig");
const relations = @import("relations.zig");
const structure = @import("structure.zig");
const transmission = @import("transmission.zig");
const grow_mod = @import("opamp_grow.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Role = sch.Role;
const Library = library.Library;
const ClassId = library.ClassId;
const Orient = library.Orient;
const At = pinned.At;

pub const none: u32 = std.math.maxInt(u32);
/// A unit, and the grid's quarter.
pub const unit = 100;
pub const quarter = 25;
/// The most parts a rail of tries moves a body before it stands where it is.
pub const tries = 40;

pub const P = struct { x: i32, y: i32 };
pub const R = struct { x0: i32, y0: i32, x1: i32, y1: i32 };
/// How a two-pin part lies: flat along the signal, or upright with room
/// for its rail's symbol under it or over it.
pub const Kind = enum(u8) { flat, down, up };
pub const Link = struct { part: u32, other: u32 };
pub const Pin = struct { net: u32, off: P, role: library.PortRole };

/// An amplifier: its pins, which of them are its inputs (upper first as
/// drawn) and which its output.
pub const Block = struct { pins: []Pin, ins: [2]u8, n_ins: u8, out: u8 };

/// A path's canonical ends and frame; capacitor identity orders feedback cells.
/// The two booleans share the existing padding: this row remains 12 bytes.
pub const Two = struct { a: u32, b: u32, tall: bool, capacitor: bool };

/// One group of placed bodies and the wire runs kept clear, in its own
/// frame until the groups are stacked.
pub const Canvas = struct {
    rects: std.ArrayList(R) = .empty,
    wires: std.ArrayList(R) = .empty,
    devs: std.ArrayList(u32) = .empty,
    /// Where a part of it joins a node of an earlier group: its end's x
    /// here, and that node's net.
    link: ?struct { x: i32, net: u32 } = null,
};

pub const Put = struct { x: i32, y: i32, turn: Orient, canvas: u32 };

comptime {
    assert(@sizeOf(Two) == 12);
    assert(@sizeOf(library.Pt) == 8);
}

/// The placement's working tables, one entry per device or per net.
pub const Placer = struct {
    arena: Allocator,
    /// Canonical device rank and its inverse, using `structure.nameLess`.
    rank: []const u32,
    order: []u32,
    two: []?Two,
    /// Per device: a MOS channel midpoint in library coordinates, or null.
    /// Placement centers the channel, then subtracts this offset at export.
    mos_mid: []?library.Pt,
    blocks: []?Block,
    /// Per net: its paths and each one's other net, in canonical name order.
    on: []std.ArrayList(Link),
    /// Per net: the first block it is the output of.
    out_of: []u32,
    rail: []bool,
    rail_up: []bool,
    port: []bool,
    /// Per device: an independent source.
    source: []bool,
    anch: []?P,
    anch_cv: []u32,
    placed: []bool,
    pending: []bool,
    flat_shunt: []bool,
    at: []?Put,
    canvases: std.ArrayList(Canvas) = .empty,
    cv: u32 = 0,

    pub fn canvas(p: *Placer) *Canvas {
        return &p.canvases.items[p.cv];
    }

    /// Whether `r` keeps `gap` clear of every body and `wgap` of every run.
    pub fn free(p: *Placer, r: R, gap: i32, wgap: i32) bool {
        const c = p.canvas();
        for (c.rects.items) |b| {
            if (r.x0 < b.x1 + gap and b.x0 < r.x1 + gap and r.y0 < b.y1 + gap and b.y0 < r.y1 + gap) return false;
        }
        for (c.wires.items) |b| {
            if (r.x0 < b.x1 + wgap and b.x0 < r.x1 + wgap and r.y0 < b.y1 + wgap and b.y0 < r.y1 + wgap) return false;
        }
        return true;
    }

    pub fn wire(p: *Placer, a: P, b: P) Allocator.Error!void {
        try p.canvas().wires.append(p.arena, .{ .x0 = @min(a.x, b.x), .y0 = @min(a.y, b.y), .x1 = @max(a.x, b.x), .y1 = @max(a.y, b.y) });
    }

    pub fn add(p: *Placer, d: u32, x: i32, y: i32, turn: Orient, r: R) Allocator.Error!void {
        assert(p.at[d] == null);
        p.at[d] = .{ .x = x, .y = y, .turn = turn, .canvas = p.cv };
        try p.canvas().rects.append(p.arena, r);
        try p.canvas().devs.append(p.arena, d);
        p.placed[d] = true;
    }

    pub fn anchor(p: *Placer, net: u32, at: P) void {
        p.anch[net] = at;
        p.anch_cv[net] = p.cv;
    }

    pub fn aOn(p: *const Placer, d: u32, net: u32) bool {
        return p.two[d].?.a == net;
    }

    /// One two-pin part, flat or upright at (cx, cy), moved by `step` until
    /// free; `node_first`: its pin on the node's net is the left one (flat)
    /// or the top one (upright). Where it came to stand.
    pub fn put(p: *Placer, d: u32, kind: Kind, cx0: i32, cy0: i32, step: P, node_first: bool, gap: i32) Allocator.Error!P {
        var cx = cx0;
        var cy = cy0;
        var r = partRect(kind, cx, cy, p.two[d].?.tall);
        for (0..tries) |_| {
            r = partRect(kind, cx, cy, p.two[d].?.tall);
            if (p.free(r, gap, 20)) break;
            cx += step.x;
            cy += step.y;
        }
        const quarters: u2 = if (kind == .flat) (if (node_first) 0 else 2) else (if (node_first) 1 else 3);
        const turn: Orient = if (p.mos_mid[d] != null and kind == .flat) .{ .mirror = !node_first } else .{ .rot = quarters };
        try p.add(d, cx, cy, turn, r);
        return .{ .x = cx, .y = cy };
    }
};

/// Whether the op-amp placement is this circuit's: every drawn device a
/// two-pin part or an amplifier block (one or two inputs and one output by
/// its port names, the rest rails), and at least one block. Also admits
/// capacitor circuits whose other parts are R/C/V and MOS channels with
/// external gate-only controls, no supply endpoint or complementary pair.
/// `roles` is the existing `guessRoles` result, one entry per net.
pub fn applies(nl: *const Netlist, roles: []const Role, drawn: []const bool) bool {
    const c = &nl.graph;
    assert(drawn.len == c.edgeCount());
    assert(roles.len == c.vertexCount());
    var blocks: usize = 0;
    var switches: usize = 0;
    var cap = false;
    var rc = true;
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (!drawn[d]) continue;
        if (relations.twoPin(kind)) {
            cap = cap or kind == .capacitor;
            rc = rc and (kind == .resistor or kind == .capacitor or kind == .vsource);
            continue;
        }
        if (kind == .mosfet) {
            const pins = c.members(EdgeId.from(d));
            if (pins[0] == pins[2] or pins[1] == pins[0] or pins[1] == pins[2]) return false;
            if (roles[pins[0].index()] == .supply or roles[pins[2].index()] == .supply) return false;
            if (!externalGate(nl, roles, pins[1]) or transmission.mate(nl, @intCast(d)) != null) return false;
            switches += 1;
            continue;
        }
        const def = nl.defOf(EdgeId.from(d)) orelse return false;
        if (kind != .subckt or def.ports.len != c.members(EdgeId.from(d)).len or amplifier(def.ports) == null) return false;
        blocks += 1;
    }
    return blocks > 0 and (switches == 0 or (cap and rc));
}

/// Whether an admitted structural or precise placement request selects the
/// lattice. Uses the same pre-drawing verdicts as the public report. Weak
/// relay stays do not constrain the amplifier's signal placement.
pub fn steered(arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const structure.Structure, sk: *const @import("skeleton.zig").Skeleton) Allocator.Error!bool {
    for (nl.hints) |h| {
        if (positional(h)) break;
    } else return false;
    const verdicts = try @import("report.zig").verdicts(arena, nl, roles, st, sk, null, null);
    for (nl.hints, verdicts) |h, v| if (v.state == .honoured and positional(h)) return true;
    return false;
}

/// A place and a turn for every drawn device of an op-amp circuit, in
/// drawing units, or null when the deck is `steered`, `applies` says no, or
/// a block's symbol has an input right of its output. `classes` is each device's class in `lib`.
pub fn place(arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const structure.Structure, sk: *const @import("skeleton.zig").Skeleton, lib: *const Library, classes: []const ClassId) Allocator.Error!?[]?At {
    const drawn = sk.drawn;
    if (!applies(nl, roles, drawn) or try steered(arena, nl, roles, st, sk)) return null;
    const c = &nl.graph;
    const n = c.edgeCount();
    const nets = c.vertexCount();
    assert(classes.len == n);
    var p: Placer = .{
        .arena = arena,
        .rank = try structure.rankByName(arena, arena, c.edges.items(.name)),
        .order = try arena.alloc(u32, n),
        .two = try arena.alloc(?Two, n),
        .mos_mid = try arena.alloc(?library.Pt, n),
        .blocks = try arena.alloc(?Block, n),
        .on = try arena.alloc(std.ArrayList(Link), nets),
        .out_of = try arena.alloc(u32, nets),
        .rail = try arena.alloc(bool, nets),
        .rail_up = try arena.alloc(bool, nets),
        .port = try arena.alloc(bool, nets),
        .source = try arena.alloc(bool, n),
        .anch = try arena.alloc(?P, nets),
        .anch_cv = try arena.alloc(u32, nets),
        .placed = try arena.alloc(bool, n),
        .pending = try arena.alloc(bool, nets),
        .flat_shunt = try arena.alloc(bool, nets),
        .at = try arena.alloc(?Put, n),
    };
    for (p.rank, 0..) |rank, d| p.order[rank] = @intCast(d);
    @memset(p.two, null);
    @memset(p.mos_mid, null);
    @memset(p.blocks, null);
    for (p.on) |*l| l.* = .empty;
    @memset(p.out_of, none);
    @memset(p.anch, null);
    @memset(p.anch_cv, none);
    @memset(p.placed, false);
    @memset(p.pending, false);
    @memset(p.flat_shunt, false);
    @memset(p.at, null);
    for (roles, 0..) |role, v| {
        p.rail[v] = role.isRail();
        p.rail_up[v] = role == .supply;
        p.port[v] = role.isPort();
    }
    for (c.edges.items(.kind), p.source) |kind, *s| s.* = device.of(kind).source == .independent;
    for (p.order) |d| {
        if (!drawn[d]) continue;
        const kind = c.edges.items(.kind)[d];
        const pins = c.members(EdgeId.from(d));
        if (relations.twoPin(kind) or kind == .mosfet) {
            // Its path's ends: the reader gives every part both. The
            // switch's symbol is the taller one.
            const a, const b = nl.path(EdgeId.from(d)).?;
            var t: Two = .{ .a = a, .b = b, .tall = kind == .vswitch or kind == .cswitch or kind == .mosfet, .capacitor = kind == .capacitor };
            if (kind == .mosfet) {
                const terms = lib.at(classes[d]).terminals;
                if (terms.len < 3) return null;
                const drain = terms[0].at;
                const gate = terms[1].at;
                const source = terms[2].at;
                // This procedure's paths span one unit. Other symbol frames
                // retain lattice placement; the library owns their geometry.
                if (drain.y != source.y or @abs(drain.x - source.x) != lib.unit or gate.y >= drain.y or @mod(drain.x + source.x, 2) != 0) return null;
                p.mos_mid[d] = .{ .x = @divExact(drain.x + source.x, 2), .y = drain.y };
                if (!channelFits(lib.at(classes[d]), p.mos_mid[d].?, lib.unit)) return null;
                if (drain.x > source.x) std.mem.swap(u32, &t.a, &t.b);
            }
            p.two[d] = t;
            if (t.a != t.b) {
                try p.on[t.a].append(arena, .{ .part = @intCast(d), .other = t.b });
                try p.on[t.b].append(arena, .{ .part = @intCast(d), .other = t.a });
            }
            continue;
        }
        const def = nl.defOf(EdgeId.from(d)).?;
        const terms = lib.at(classes[d]).terminals;
        if (terms.len != pins.len) return null;
        var b = amplifier(def.ports).?;
        b.pins = try arena.alloc(Pin, pins.len);
        for (b.pins, pins, def.ports, terms) |*bp, net, name, term| {
            bp.* = .{ .net = net.index(), .off = .{ .x = @divTrunc(term.at.x * unit, lib.unit), .y = @divTrunc(term.at.y * unit, lib.unit) }, .role = library.portRole(def.ports, name) };
        }
        for (b.ins[0..b.n_ins]) |i| if (b.pins[i].off.x >= b.pins[b.out].off.x) return null;
        // The upper input as drawn first.
        if (b.n_ins == 2 and b.pins[b.ins[1]].off.y < b.pins[b.ins[0]].off.y) std.mem.swap(u8, &b.ins[0], &b.ins[1]);
        p.blocks[d] = b;
        if (p.out_of[b.pins[b.out].net] == none) p.out_of[b.pins[b.out].net] = @intCast(d);
    }
    try grow_mod.run(&p);

    // The groups one under the other, in the order they were begun; one a
    // part joins to a node of an earlier group stands with that part's end
    // at the node's x.
    const out = try arena.alloc(?At, n);
    @memset(out, null);
    const shift = try arena.alloc(P, p.canvases.items.len);
    @memset(shift, .{ .x = 0, .y = 0 });
    var ybase: i32 = 0;
    for (p.canvases.items, 0..) |*cv, k| {
        if (cv.devs.items.len == 0) continue;
        var box: R = .{ .x0 = std.math.maxInt(i32), .y0 = std.math.maxInt(i32), .x1 = std.math.minInt(i32), .y1 = std.math.minInt(i32) };
        for ([_][]const R{ cv.rects.items, cv.wires.items }) |rs| for (rs) |r| {
            box = .{ .x0 = @min(box.x0, r.x0), .y0 = @min(box.y0, r.y0), .x1 = @max(box.x1, r.x1), .y1 = @max(box.y1, r.y1) };
        };
        var dx: i32 = 0;
        if (cv.link) |l| dx = p.anch[l.net].?.x + shift[p.anch_cv[l.net]].x - l.x;
        const dy = ceilQuarter(ybase - box.y0);
        shift[k] = .{ .x = dx, .y = dy };
        for (cv.devs.items) |d| {
            const at = p.at[d].?;
            const center: library.Pt = .{ .x = toDrawing(at.x + dx, lib.unit), .y = toDrawing(at.y + dy, lib.unit) };
            const offset = at.turn.apply(p.mos_mid[d] orelse .zero);
            out[d] = .{ .origin = center.sub(offset), .orient = at.turn, .line = none };
        }
        ybase = box.y1 + dy + 150;
    }
    for (0..n) |d| assert((out[d] != null) == drawn[d]);
    return out;
}

/// The room a two-pin part takes: flat, a unit long; upright, with its
/// rail symbol past its far end. Tall controls reserve three quarters of
/// a unit above a flat channel, or on either side when it stands upright.
pub fn partRect(kind: Kind, cx: i32, cy: i32, tall: bool) R {
    const side: i32 = if (tall) 75 else 20;
    return switch (kind) {
        .flat => .{ .x0 = cx - 50, .y0 = cy - side, .x1 = cx + 50, .y1 = cy + 20 },
        .down => .{ .x0 = cx - side, .y0 = cy - 50, .x1 = cx + side, .y1 = cy + 100 },
        .up => .{ .x0 = cx - side, .y0 = cy - 100, .x1 = cx + side, .y1 = cy + 50 },
    };
}

/// `v` up to the grid.
pub fn ceilQuarter(v: i32) i32 {
    return -@divFloor(-v, quarter) * quarter;
}

/// `num / den` to the nearest whole, a half to the even one.
pub fn roundEven(num: i64, den: i64) i32 {
    assert(den > 0);
    const q = @divFloor(num, den);
    const r = @mod(num, den);
    if (2 * r > den or (2 * r == den and @mod(q, 2) != 0)) return @intCast(q + 1);
    return @intCast(q);
}

// ---- private ----

fn positional(h: @import("hints.zig").Hint) bool {
    return switch (h.verb) {
        .upright, .bridge, .row, .above, .column, .order, .face, .cell => true,
        .at => !h.weak,
        else => false,
    };
}

/// A control net that touches only MOS gates and independent voltage
/// sources whose opposite terminal is a rail. Read every incidence, even
/// for sources drawn apart: hiding a driver does not change its function.
fn externalGate(nl: *const Netlist, roles: []const Role, gate: netlist.VertexId) bool {
    const c = &nl.graph;
    for (c.incident(gate)) |e| {
        const kind = c.edges.items(.kind)[e.index()];
        const pins = c.members(e);
        if (kind != .mosfet and kind != .vsource) return false;
        for (pins, 0..) |net, i| {
            if (net != gate) continue;
            if (kind == .mosfet and i != 1) return false;
            if (kind == .vsource and !roles[pins[1 - i].index()].isRail()) return false;
        }
    }
    return true;
}

/// Pins and strokes must fit the same reserved frame used while placing.
/// Cross multiplication keeps this edge check exact for any library unit.
fn channelFits(class: library.Class, mid: library.Pt, lib_unit: i32) bool {
    const box = class.bbox();
    const room = partRect(.flat, 0, 0, true);
    return (@as(i64, box.min.x) - mid.x) * unit >= @as(i64, room.x0) * lib_unit and
        (@as(i64, box.min.y) - mid.y) * unit >= @as(i64, room.y0) * lib_unit and
        (@as(i64, box.max.x) - mid.x) * unit <= @as(i64, room.x1) * lib_unit and
        (@as(i64, box.max.y) - mid.y) * unit <= @as(i64, room.y1) * lib_unit;
}

/// A block's inputs and its output among `ports`, by their names, its
/// `pins` still to fill; null when it is no amplifier: one or two inputs,
/// one output, the rest rails.
fn amplifier(ports: []const []const u8) ?Block {
    var b: Block = .{ .pins = &.{}, .ins = .{ 0, 0 }, .n_ins = 0, .out = 0 };
    var outs: usize = 0;
    for (ports, 0..) |name, i| switch (library.portRole(ports, name)) {
        .other => return null,
        .rail => {},
        .out => {
            b.out = @intCast(i);
            outs += 1;
        },
        .inp, .inn, .in => {
            if (b.n_ins == 2) return null;
            b.ins[b.n_ins] = @intCast(i);
            b.n_ins += 1;
        },
    };
    return if (outs == 1 and b.n_ins > 0) b else null;
}

fn toDrawing(v: i32, lib_unit: i32) i32 {
    return @divFloor(v * lib_unit + 50, unit);
}
