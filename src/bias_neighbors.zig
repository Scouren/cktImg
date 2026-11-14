//! Private amplifier bias peers, placed from their actual symbol frames.
//!
//! Human Rules:
//! - bias_neighbors.1 (habit, bounded) Seven source reference amplifiers
//!   place an isolated BIAS/BIAS_CIRCUIT peer beyond the bias lead, with
//!   opposing collinear leads and its whole body outward. AG2444 permits
//!   touching tips. AG2440's extra VC drives local controls and excludes
//!   it; a valid circuit need not follow this case. See
//!   docs/research/bias-block-neighbors.md. `find`
//! - bias_neighbors.2 (invariant) Count every declared pin incidence before
//!   drawn state or geometry. The peer has VDD/VSS, one NB/VBN, optional
//!   VB1/VB2, and no other ports. Rails match the amplifier. Other peer
//!   bias ports have one incidence and an external terminal role. Source
//!   evidence uses literal DUT ports; flattened engine decks retain only
//!   Role.isPort, so this is the explicit engine projection. `find`
//! - bias_neighbors.3 (choice) Keep the amplifier fixed; turn the whole
//!   peer and try outward positions beyond occupied symbol/terminal room.
//!   Actual class origins, tips and strokes determine the relation, never
//!   a guessed below-row or a rewritten library class. This does not copy
//!   source upward amplifier biases or every other peer port side. `place`
//! - bias_neighbors.4 (invariant) Admitted cells, relations, faces, fixed
//!   origins including weak stays, definition sides and mates take
//!   precedence, including admitted members of a relaxed caller group.
//!   Different shelves abstain. Failed frames/placements
//!   restore all peer fields. Existing cells remain untouched. `collect`
//! - bias_neighbors.5 (invariant) The single generic compaction pass keeps
//!   successful actual-tip order; equal tips already share a track. Each
//!   class remains rigid, so its outward body stays outward. `orders`
//!
//! Data: existing netlist/CSR, roles, hints and settled classes in; one
//! cold 12-byte certificate per possible amplifier out, then existing
//! peer orientation/grid-position writes. Handles are u32, port indices
//! u3 (complete contracts have at most eight ports). Collection reserves
//! once from the block count; the caller frees it. No per-device role
//! cache, callbacks or retained state. Attempts follow canonical rank.
//! This is bounded block-layout work, outside routing/cost inner loops;
//! no speed or no-residue claim is made.
//!
//! Contents:
//! - `pub const Pair = struct`, `Batch`, `Batch.deinit`
//! - `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const Schematic, sk: *const Skeleton, st: *const Structure, ats: []const ?pinned.At) Allocator.Error!Batch`
//! - `pub fn place(s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pairs: *std.ArrayList(Pair)) void`
//! - `pub fn orders(s: *const Schematic, pairs: []const Pair, storage: [][2]i32) [2][]const [2]i32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const block_symbols = @import("block_symbols.zig");
const Lengths = @import("canvas.zig").Lengths;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Schematic = sch.Schematic;
const Skeleton = skeleton.Skeleton;
const Structure = structure.Structure;
const Pt = library.Pt;
const Rect = library.Rect;
const Side = library.Side;

/// Cold immediate certificate: two existing devices and
/// their declared port indices. No class or electrical binding is changed.
pub const Pair = struct { amp: EdgeId, peer: EdgeId, pins: [2]u3 };

/// Caller-owned temporary certificates and coordinate-order capacity.
/// Both buffers die at the end of this drawing's geometry stage.
pub const Batch = struct {
    pairs: std.ArrayList(Pair),
    coordinates: [][2]i32,

    /// Releases both buffers with the allocator passed to collect.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.pairs.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

comptime {
    assert(@sizeOf(Pair) == 12);
}

/// Collects eligible pairs before relay consumes weak stays. All input
/// slices cover the graph. The caller owns/deinitializes the returned batch;
/// allocation failure occurs before any placement write.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const Schematic, sk: *const Skeleton, st: *const Structure, ats: []const ?pinned.At) Allocator.Error!Batch {
    const c = &nl.graph;
    assert(ats.len == c.edgeCount() and sk.drawn.len == c.edgeCount());
    assert(st.device_rank.len == c.edgeCount() and sk.verdicts.len == nl.hints.len);
    var capacity: usize = 0;
    for (c.edges.items(.kind)) |kind| capacity += @intFromBool(kind == .subckt);
    var out: std.ArrayList(Pair) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, capacity);
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt) continue;
        const pair = find(nl, s.roles, @intCast(d)) orelse continue;
        const a = pair.amp.index();
        const b = pair.peer.index();
        if (!sk.drawn[a] or !sk.drawn[b] or ats[a] != null or ats[b] != null) continue;
        if (st.device_mate[a] != sch.none or st.device_mate[b] != sch.none or sk.shelf[a] != sk.shelf[b]) continue;
        // These complete multiport blocks cannot enter automatic
        // transistor/path groups. Membership here is caller-admitted,
        // including the valid members of a relaxed partial request.
        const grouped = for (st.block_devices) |member| {
            if (member == a or member == b) break true;
        } else false;
        if (grouped) continue;
        // Skeleton's inferred mates are private to placement. Its public
        // mirror axis still promises every symmetric column pair; keep
        // any peer on such a column (including the axis itself) unmoved.
        const mirrored = if (sk.axis2) |axis| mirrored: {
            for (sk.x, sk.drawn) |x, drawn| if (drawn and x + sk.x[b] == axis) break :mirrored true;
            break :mirrored false;
        } else false;
        if (mirrored) continue;
        if (held(nl, sk, a, b)) continue;
        out.appendAssumeCapacity(pair);
    }
    std.sort.heap(Pair, out.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Pair, b: Pair) bool {
            return rank[a.amp.index()] < rank[b.amp.index()];
        }
    }.less);
    const coordinates = try gpa.alloc([2]i32, 2 * out.items.len);
    return .{ .pairs = out, .coordinates = coordinates };
}

/// Attempts each collected pair against actual occupied frames after
/// coordinates/relay. Only peer fields and its grid anchor may change.
/// Failed attempts restore the old device row. Compacts the caller's list
/// to successful pairs without allocation; all positions span the graph.
pub fn place(s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pairs: *std.ArrayList(Pair)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (pairs.items) |pair| {
        const side = leadSide(s, pair.amp.index(), pair.pins[0]) orelse continue;
        const a = tip(s, pair.amp.index(), pair.pins[0], Pt.round(at[pair.amp.index()]));
        const before = s.devices.get(pair.peer.index());
        if (!turn(s, nl, pair.peer.index(), pair.pins[1], side.opposite())) continue;
        const own = tip(s, pair.peer.index(), pair.pins[1], .zero);
        var gap = len.stack;
        var found: ?Pt = null;
        // Each collision advances beyond at least one fixed box; at most
        // n boxes can be crossed in this one-way sweep.
        for (0..at.len + 1) |_| {
            const p = step(a, side, gap).sub(own);
            const box = envelope(s, nl, pair.peer.index(), p, len);
            var advance: i32 = 0;
            for (at, sk.drawn, 0..) |other_at, drawn, d| {
                if (!drawn or d == pair.peer.index()) continue;
                const other = if (ats[d]) |fixed|
                    s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin).grow(@max(len.rail, len.terminal) + len.unit + len.clearance)
                else
                    envelope(s, nl, @intCast(d), Pt.round(other_at), len);
                if (!box.intersects(other)) continue;
                advance = @max(advance, far(other, side) - near(box, side) + len.clearance);
            }
            if (advance == 0) {
                found = p;
                break;
            }
            gap += advance;
        }
        if (found) |p| {
            at[pair.peer.index()] = p.toF();
            pairs.items[kept] = pair;
            kept += 1;
        } else s.devices.set(pair.peer.index(), before);
    }
    pairs.items = pairs.items[0..kept];
}

/// Writes current scaffold actual-tip orders into caller storage of at
/// least twice pairs.len. Both axes' slices borrow that storage. Equality
/// needs no edge; actual terminals are already tied to their rigid class
/// by compact.read. Refuses absent or no-longer-opposing/aligned pairs.
pub fn orders(s: *const Schematic, pairs: []const Pair, storage: [][2]i32) [2][]const [2]i32 {
    assert(storage.len >= 2 * pairs.len);
    assert(s.xy.len == s.nodes.len);
    var count: [2]usize = .{ 0, 0 };
    for (pairs) |pair| {
        const na = s.deviceNode(pair.amp.index()) orelse continue;
        const nb = s.deviceNode(pair.peer.index()) orelse continue;
        const side = leadSide(s, pair.amp.index(), pair.pins[0]) orelse continue;
        if (leadSide(s, pair.peer.index(), pair.pins[1]) != side.opposite()) continue;
        const a = tip(s, pair.amp.index(), pair.pins[0], Pt.round(s.xy[na]));
        const b = tip(s, pair.peer.index(), pair.pins[1], Pt.round(s.xy[nb]));
        if ((side.isHorizontal() and a.y != b.y) or (!side.isHorizontal() and a.x != b.x)) continue;
        if (project(b.sub(a), side) <= 0) continue;
        const axis: usize = @intFromBool(!side.isHorizontal());
        const x = if (axis == 0) a.x else a.y;
        const y = if (axis == 0) b.x else b.y;
        storage[axis * pairs.len + count[axis]] = .{ @min(x, y), @max(x, y) };
        count[axis] += 1;
    }
    return .{ storage[0..count[0]], storage[pairs.len..][0..count[1]] };
}

// ---- private ----

fn find(nl: *const Netlist, roles: []const sch.Role, amp: u32) ?Pair {
    const c = &nl.graph;
    const def = nl.defOf(EdgeId.from(amp)) orelse return null;
    const shape = block_symbols.identify(def.name, def.ports);
    if (shape != .amplifier and shape != .reference_amplifier) return null;
    const pins = c.members(EdgeId.from(amp));
    if (pins.len != def.ports.len) return null;
    const vdd = port(def.ports, "vdd") orelse return null;
    const vss = port(def.ports, "vss") orelse return null;
    if (pins[vdd] == pins[vss]) return null;
    var result: ?Pair = null;
    for (def.ports, pins, 0..) |name, net, i| {
        const bias = if (shape == .reference_amplifier) oneOf(name, "vb1 vbn nb") else oneOf(name, "vb vb1 vb2 vb3 bias");
        if (!bias or roles[net.index()] != .internal) continue;
        const incident = c.incident(net);
        if (incident.len != 2) continue;
        const e = incident[@intFromBool(incident[0].index() == amp)];
        if (e.index() == amp) continue;
        const peer = nl.defOf(e) orelse continue;
        if (!oneOf(peer.name, "bias bias_circuit") or peer.ports.len < 3 or peer.ports.len > 5) continue;
        const pp = c.members(e);
        if (pp.len != peer.ports.len) continue;
        var seen: [5]bool = @splat(false);
        var bias_pin: ?u3 = null;
        const valid = for (peer.ports, pp, 0..) |p, binding, j| {
            const role: usize = if (eq(p, "vdd")) 0 else if (eq(p, "vss")) 1 else if (oneOf(p, "nb vbn")) 2 else if (eq(p, "vb1")) 3 else if (eq(p, "vb2")) 4 else break false;
            if (seen[role]) break false;
            seen[role] = true;
            switch (role) {
                0 => if (binding != pins[vdd]) {
                    break false;
                },
                1 => if (binding != pins[vss]) {
                    break false;
                },
                2 => {
                    if (binding != net) break false;
                    bias_pin = @intCast(j);
                },
                else => if (!roles[binding.index()].isPort() or c.incident(binding).len != 1) {
                    break false;
                },
            }
        } else true;
        if (!valid or !seen[0] or !seen[1] or bias_pin == null) continue;
        if (result != null) return null;
        result = .{ .amp = EdgeId.from(amp), .peer = e, .pins = .{ @intCast(i), bias_pin.? } };
    }
    return result;
}

fn held(nl: *const Netlist, sk: *const Skeleton, a: u32, b: u32) bool {
    for ([_]u32{ a, b }) |d| for (nl.defOf(EdgeId.from(d)).?.sides) |side| {
        if (side != null) return true;
    };
    for (nl.hints, sk.verdicts) |hint, verdict| {
        if ((verdict orelse continue).state != .honoured) continue;
        switch (hint.verb) {
            .row, .above, .order, .cell, .face, .upright, .bridge => {},
            else => continue,
        }
        for (hint.args) |name| {
            const d = (nl.device(name) orelse continue).index();
            if (d == a or d == b) return true;
        }
    }
    return false;
}

fn turn(s: *Schematic, nl: *const Netlist, d: u32, pin: u3, want: Side) bool {
    const before = s.devices.get(d);
    const info = s.devices.slice();
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, true } }) |flips| {
        info.items(.orientation)[d] = form;
        info.items(.flip_x)[d] = flips[0];
        info.items(.flip_y)[d] = flips[1];
        sch.settleDevice(s, &nl.graph, d);
        if (leadSide(s, d, pin) == want and sch.alignPin(s, &nl.graph, d, pin)) return true;
    };
    s.devices.set(d, before);
    return false;
}

fn leadSide(s: *const Schematic, d: u32, pin: u3) ?Side {
    const info = s.devices.slice();
    const c = s.lib.at(info.items(.class)[d]);
    if (pin >= s.device_pin_count[d] or !c.shows(pin)) return null;
    const t = c.terminals[pin].at;
    var attachment: ?Pt = null;
    for (c.draw) |op| if (op == .line) {
        const line = op.line;
        const p = if (line.a.eql(t)) line.b else if (line.b.eql(t)) line.a else continue;
        if (attachment != null or p.eql(t) or (p.x != t.x and p.y != t.y)) return null;
        attachment = p;
    };
    const delta = t.sub(attachment orelse return null);
    const side = Side.of(delta).?;
    for (c.draw) |op| if (op == .circle) {
        if (project(op.circle.c.sub(t), side) + op.circle.r >= 0) return null;
    };
    var body = false;
    var attached = false;
    for (c.draw) |op| if (op == .polyline) {
        for (op.polyline) |p| if (project(p.sub(t), side) >= 0) return null;
        const ps = op.polyline;
        if (ps.len < 4 or !ps[0].eql(ps[ps.len - 1]) or body) return null;
        body = true;
        for (ps[0 .. ps.len - 1], ps[1..]) |a, b| {
            const p = attachment.?;
            const cross = @as(i64, p.x - a.x) * (b.y - a.y) - @as(i64, p.y - a.y) * (b.x - a.x);
            attached = attached or (cross == 0 and Rect.fromCorners(a, b).contains(p));
            // The attachment must be the first body boundary reached.
            // A diagonal may meet it; no edge may touch the open lead.
            const horizontal = side.isHorizontal();
            const transverse = if (horizontal) t.y else t.x;
            const ta = if (horizontal) a.y else a.x;
            const tb = if (horizontal) b.y else b.x;
            if (transverse < @min(ta, tb) or transverse > @max(ta, tb)) continue;
            const from_tip = @as(i64, t.x - a.x) * (b.y - a.y) - @as(i64, t.y - a.y) * (b.x - a.x);
            if ((cross < 0 and from_tip > 0) or (cross > 0 and from_tip < 0)) return null;
            if (cross == 0 and from_tip == 0) {
                const lo = if (horizontal) @min(t.x, p.x) else @min(t.y, p.y);
                const hi = if (horizontal) @max(t.x, p.x) else @max(t.y, p.y);
                const ea = if (horizontal) a.x else a.y;
                const eb = if (horizontal) b.x else b.y;
                if (@min(ea, eb) < hi and @max(ea, eb) > lo) return null;
            }
        }
    };
    const o = info.items(.orient)[d];
    const actual = Side.of(o.apply(delta)).?;
    return if (body and attached and c.side(pin, o) == actual) actual else null;
}

fn tip(s: *const Schematic, d: u32, pin: u3, at: Pt) Pt {
    const info = s.devices.slice();
    const c = s.lib.at(info.items(.class)[d]);
    return at.sub(info.items(.grid)[d]).add(info.items(.orient)[d].apply(c.terminals[pin].at));
}

fn envelope(s: *const Schematic, nl: *const Netlist, d: u32, at: Pt, len: Lengths) Rect {
    var box = s.boxAt(d, at);
    for (nl.graph.members(EdgeId.from(d)), 0..) |net, i| {
        const side = s.pinSide(d, i) orelse continue;
        const role = s.roles[net.index()];
        if (!role.isPort() and !role.isRail()) continue;
        const info = s.devices.slice();
        const c = s.lib.at(info.items(.class)[d]);
        const p = at.sub(info.items(.grid)[d]).add(info.items(.orient)[d].apply(c.terminals[i].at));
        const gap = (if (role.isRail()) len.rail else len.terminal) + if (side.isHorizontal()) len.unit else @as(i32, 0);
        box = box.merge(.point(step(p, side, gap)));
    }
    return box.grow(len.clearance);
}

fn project(p: Pt, side: Side) i32 {
    const v = side.unit();
    return p.x * v.x + p.y * v.y;
}

fn step(p: Pt, side: Side, distance: i32) Pt {
    const v = side.unit();
    return .{ .x = p.x + v.x * distance, .y = p.y + v.y * distance };
}

fn near(r: Rect, side: Side) i32 {
    return @min(project(r.min, side), project(r.max, side));
}

fn far(r: Rect, side: Side) i32 {
    return @max(project(r.min, side), project(r.max, side));
}

fn port(ports: []const []const u8, name: []const u8) ?usize {
    for (ports, 0..) |p, i| if (eq(p, name)) return i;
    return null;
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn oneOf(name: []const u8, names: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, names, ' ');
    while (it.next()) |word| if (eq(name, word)) return true;
    return false;
}
