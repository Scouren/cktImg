//! Unique center-tapped coils and their parallel tank capacitors.
//!
//! Human Rules:
//! - coil_tanks.1 (habit, bounded) A capacitor directly across N1/N2 is
//!   parallel to the winding, centered along it, opposite N3, with matched
//!   net ends. Nine actual source pairs have these relations and eighteen
//!   continuous conductor legs. Five have a unique coil owner; AG1180's
//!   two capacitors each serve two coils and remain outside this rule.
//!   See docs/research/center-tap-tanks.md. `find`
//! - coil_tanks.2 (choice) Keep the coil's world pose. Try one nearby
//!   capacitor position from actual class bounds and the existing spacing,
//!   then nearest-first quarter-unit steps through one additional symbol
//!   unit. This bounded room search is a placement choice, not a source
//!   distance rule. Failure restores every capacitor field. Only center-aligned,
//!   opposing two-ended frames qualify; no cached class is rewritten.
//!   Caller placement, groups, mates, sides and net styles win. `collect`,
//!   `place`
//! - coil_tanks.3 (habit, bounded) A unique semantic tank stays on one
//!   shelf, including when its custom frame declines geometric placement.
//!   Existing cell/strong-at and relation precedence is unchanged. This
//!   does not reserve a shelf's empty rows or exempt a wire from thinning.
//!   `spans`
//! - coil_tanks.4 (invariant) Actual midpoint anchors share one compaction
//!   track; an initially strict perpendicular order keeps the capacitor
//!   opposite the tap. Submit to the existing single compaction pass.
//!   `orders`
//!
//! Data: netlist/CSR, classes and admitted hints in; typed 12-byte pairs
//! and capacitor poses out. All pair fields are read together. At most one
//! per drawn block; indices are u2/u1, coordinates i32. Two caller-owned
//! buffers last through this drawing only. Canonical order serializes
//! collision decisions; recognition is a cold once-per-block collection,
//! outside cut-cost and routing loops. No performance claim is made.
//!
//! Contents:
//! - `pub const Pair`, `Batch`, `Batch.deinit`
//! - `pub fn find(nl: *const Netlist, coil: EdgeId) ?Pair`
//! - `pub fn spans(gpa: Allocator, nl: *const Netlist, drawn: []const bool, x: []const i32, previous: []const [2]i32) Allocator.Error!std.ArrayList([2]i32)`
//! - `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const Schematic, sk: *const Skeleton, st: *const Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch`
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
const netlines = @import("netlines.zig");
const block_symbols = @import("block_symbols.zig");
const Lengths = @import("canvas.zig").Lengths;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Schematic = sch.Schematic;
const Skeleton = skeleton.Skeleton;
const Structure = structure.Structure;
const Pt = library.Pt;
const Side = library.Side;

/// Two existing devices, declared N1/N2/N3 indices, and C's N1-bound end.
pub const Pair = struct { coil: EdgeId, cap: EdgeId, pins: [3]u2, first: u1 };

/// Immediate geometry requests and their bounded coordinate scratch.
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

/// Finds one capacitor across a complete CT contract's distinct outer
/// nets. Counts every matching capacitor and other CT before visibility,
/// form or tap-alias filtering; ambiguous ownership returns null.
pub fn find(nl: *const Netlist, coil: EdgeId) ?Pair {
    const c = &nl.graph;
    assert(coil.index() < c.edgeCount());
    const pins = ports(nl, coil) orelse return null;
    const members = c.members(coil);
    const a, const b = .{ members[pins[0]], members[pins[1]] };
    if (a == b) return null;
    var cap: ?EdgeId = null;
    var first: u1 = 0;
    for (c.incident(a)) |edge| {
        if (c.edges.items(.kind)[edge.index()] != .capacitor) continue;
        const p = c.members(edge);
        if (p.len != 2 or !((p[0] == a and p[1] == b) or (p[1] == a and p[0] == b))) continue;
        if (cap != null) return null;
        cap = edge;
        first = @intFromBool(p[0] != a);
    }
    const selected = cap orelse return null;
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt or d == coil.index()) continue;
        const other = EdgeId.from(d);
        const ends = ports(nl, other) orelse continue;
        const p = c.members(other);
        if ((p[ends[0]] == a and p[ends[1]] == b) or (p[ends[1]] == a and p[ends[0]] == b)) return null;
    }
    if (members[pins[2]] == a or members[pins[2]] == b) return null;
    return .{ .coil = coil, .cap = selected, .pins = pins, .first = first };
}

/// Returns an owned merged cut-only span list, or an empty list when no
/// tanks qualify. The caller then keeps `previous` borrowed. Recognition
/// occurs once per block, before cutCost; allocation precedes cell writes.
pub fn spans(gpa: Allocator, nl: *const Netlist, drawn: []const bool, x: []const i32, previous: []const [2]i32) Allocator.Error!std.ArrayList([2]i32) {
    assert(drawn.len == nl.graph.edgeCount() and x.len == drawn.len);
    var out: std.ArrayList([2]i32) = .empty;
    errdefer out.deinit(gpa);
    var capacity: usize = 0;
    for (nl.graph.edges.items(.kind), drawn) |kind, visible| capacity += @intFromBool(visible and kind == .subckt);
    for (nl.graph.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt or !drawn[d]) continue;
        const pair = find(nl, EdgeId.from(d)) orelse continue;
        if (!drawn[pair.cap.index()]) continue;
        if (out.capacity == 0) {
            try out.ensureTotalCapacity(gpa, previous.len + capacity);
            out.appendSliceAssumeCapacity(previous);
        }
        out.appendAssumeCapacity(.{ @min(x[d], x[pair.cap.index()]), @max(x[d], x[pair.cap.index()]) });
    }
    return out;
}

/// Collects unheld pairs before relay consumes weak stays. Allocation of
/// both buffers completes before any geometry mutation; caller deinitializes.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const Schematic, sk: *const Skeleton, st: *const Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    const n = nl.graph.edgeCount();
    assert(ats.len == n and sk.drawn.len == n and st.device_rank.len == n);
    assert(lines.style.len == nl.graph.vertexCount());
    var capacity: usize = 0;
    for (nl.graph.edges.items(.kind), sk.drawn) |kind, visible| capacity += @intFromBool(visible and kind == .subckt);
    var pairs: std.ArrayList(Pair) = .empty;
    errdefer pairs.deinit(gpa);
    try pairs.ensureTotalCapacity(gpa, capacity);
    for (nl.graph.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt or !sk.drawn[d]) continue;
        const pair = find(nl, EdgeId.from(d)) orelse continue;
        const cap = pair.cap.index();
        if (!sk.drawn[cap] or ats[d] != null or ats[cap] != null or sk.shelf[d] != sk.shelf[cap]) continue;
        if (st.device_mate[d] != sch.none or st.device_mate[cap] != sch.none or held(nl, sk, st, pair)) continue;
        const members = nl.graph.members(pair.coil);
        const styled = styled: for (pair.pins[0..2]) |p| {
            const net = members[p].index();
            if (lines.style[net] != .auto or lines.port[net] != null or s.roles[net].isRail()) break true;
            for (lines.routes) |route| if (route.net == net) break :styled true;
        } else false;
        if (!styled) pairs.appendAssumeCapacity(pair);
    }
    std.sort.heap(Pair, pairs.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Pair, b: Pair) bool {
            return rank[a.coil.index()] < rank[b.coil.index()];
        }
    }.less);
    const coordinates = try gpa.alloc([2]i32, 2 * pairs.items.len);
    return .{ .pairs = pairs, .coordinates = coordinates };
}

/// Tries bounded local positions opposite each actual tap. Keeps
/// the coil fixed and restores all cap fields on failure. Successful rows
/// compact the caller's list; no allocation or symbol-class mutation occurs.
pub fn place(s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pairs: *std.ArrayList(Pair)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (pairs.items) |pair| {
        const side = frame(s, pair) orelse continue;
        const cap = pair.cap.index();
        const before = s.devices.get(cap);
        if (!turn(s, nl, pair)) continue;
        const outward = side.opposite();
        const cb = s.boxAt(pair.coil.index(), .zero);
        const pb = s.boxAt(cap, .zero);
        const gap = @max(len.stack, len.clearance + 1);
        const distance = @max(project(cb.min, outward), project(cb.max, outward)) - @min(project(pb.min, outward), project(pb.max, outward)) + gap;
        const step = @max(1, @divTrunc(len.unit, 4));
        const offset = @divCeil(distance, step) * step;
        const v = outward.unit();
        const attempts: usize = @intCast(@divFloor(len.unit, step) + 1);
        assert(attempts <= 8); // quarter-unit grain, including small units
        const target: ?Pt = search: for (0..attempts) |i| {
            const reach = offset + @as(i32, @intCast(i)) * step;
            const point = Pt.round(at[pair.coil.index()]).add(.{ .x = v.x * reach, .y = v.y * reach });
            const candidate = s.boxAt(cap, point).grow(len.clearance);
            const blocked = for (at, sk.drawn, 0..) |other_at, visible, d| {
                if (!visible or d == cap) continue;
                const box = if (ats[d]) |fixed|
                    s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin)
                else
                    s.boxAt(d, Pt.round(other_at));
                if (candidate.intersects(box)) break true;
            } else false;
            if (!blocked) break :search point;
        } else null;
        const point = target orelse {
            s.devices.set(cap, before);
            continue;
        };
        at[cap] = point.toF();
        pairs.items[kept] = pair;
        kept += 1;
    }
    pairs.items = pairs.items[0..kept];
}

/// Records initially true actual midpoint orders from the current wired
/// scaffold. Longitudinal midpoint equality already shares a real device
/// track. Storage holds at least twice pairs.len and remains caller-owned.
pub fn orders(s: *const Schematic, pairs: []const Pair, storage: [][2]i32) [2][]const [2]i32 {
    assert(storage.len >= 2 * pairs.len);
    assert(s.xy.len == s.nodes.len);
    var count: [2]usize = .{ 0, 0 };
    for (pairs) |pair| {
        const side = frame(s, pair) orelse continue;
        if (!aligned(s, pair)) continue;
        const c = s.deviceNode(pair.coil.index()) orelse continue;
        const p = s.deviceNode(pair.cap.index()) orelse continue;
        const a, const b = .{ Pt.round(s.xy[c]), Pt.round(s.xy[p]) };
        if ((side.isHorizontal() and a.y != b.y) or (!side.isHorizontal() and a.x != b.x)) continue;
        if (project(b.sub(a), side) >= 0) continue;
        const axis: usize = @intFromBool(!side.isHorizontal());
        const from, const to = if (axis == 0) .{ a.x, b.x } else .{ a.y, b.y };
        storage[axis * pairs.len + count[axis]] = .{ @min(from, to), @max(from, to) };
        count[axis] += 1;
    }
    return .{ storage[0..count[0]], storage[pairs.len..][0..count[1]] };
}

// ---- private ----

fn ports(nl: *const Netlist, d: EdgeId) ?[3]u2 {
    const def = nl.defOf(d) orelse return null;
    if (block_symbols.identify(def.name, def.ports) != .center_tap or nl.graph.members(d).len != 3) return null;
    var out: [3]u2 = undefined;
    for (def.ports, 0..) |name, i| for ([_][]const u8{ "n1", "n2", "n3" }, 0..) |want, k| {
        if (std.ascii.eqlIgnoreCase(name, want)) out[k] = @intCast(i);
    };
    return out;
}

fn held(nl: *const Netlist, sk: *const Skeleton, st: *const Structure, pair: Pair) bool {
    const a, const b = .{ pair.coil.index(), pair.cap.index() };
    for (nl.defOf(pair.coil).?.sides) |side| if (side != null) return true;
    for (st.block_devices) |d| if (d == a or d == b) return true;
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

fn tip(s: *const Schematic, d: u32, pin: usize) Pt {
    const info = s.devices.get(d);
    return info.orient.apply(s.lib.at(info.class).terminals[pin].at).sub(info.grid);
}

fn frame(s: *const Schematic, pair: Pair) ?Side {
    const d = pair.coil.index();
    const c = s.lib.at(s.devices.items(.class)[d]);
    if (c.terminals.len != 3) return null;
    for (c.terminals) |p| if (p.hidden or p.ground_ref) return null;
    const a, const b, const t = .{ tip(s, d, pair.pins[0]), tip(s, d, pair.pins[1]), tip(s, d, pair.pins[2]) };
    if (!a.add(b).eql(.zero)) return null;
    if ((b.x != 0 and b.y != 0) or (t.x != 0 and t.y != 0)) return null;
    const end = Side.of(b) orelse return null;
    const side = Side.of(t) orelse return null;
    if (!end.perpendicular(side)) return null;
    if (s.pinSide(d, pair.pins[0]) != end.opposite() or s.pinSide(d, pair.pins[1]) != end or s.pinSide(d, pair.pins[2]) != side) return null;
    return side;
}

fn aligned(s: *const Schematic, pair: Pair) bool {
    const d = pair.cap.index();
    const c = s.lib.at(s.devices.items(.class)[d]);
    if (c.terminals.len != 2) return false;
    for (c.terminals) |p| if (p.hidden or p.ground_ref) return false;
    const a, const b = .{ tip(s, d, pair.first), tip(s, d, 1 - pair.first) };
    if (!a.add(b).eql(.zero)) return false;
    if (b.x != 0 and b.y != 0) return false;
    const side = Side.of(tip(s, pair.coil.index(), pair.pins[1])) orelse return false;
    return Side.of(b) == side and s.pinSide(d, pair.first) == side.opposite() and s.pinSide(d, 1 - pair.first) == side;
}

fn turn(s: *Schematic, nl: *const Netlist, pair: Pair) bool {
    const d = pair.cap.index();
    const before = s.devices.get(d);
    const info = s.devices.slice();
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_]bool{ false, true }) |flip| {
        info.items(.orientation)[d] = form;
        info.items(.flip_x)[d] = flip;
        info.items(.flip_y)[d] = flip;
        sch.settleDevice(s, &nl.graph, d);
        if (aligned(s, pair)) return true;
    };
    s.devices.set(d, before);
    return false;
}

fn project(p: Pt, side: Side) i32 {
    const v = side.unit();
    return p.x * v.x + p.y * v.y;
}
