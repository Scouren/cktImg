//! Compaction (stage 4, after the wires): the empty room of a wired drawing
//! taken out, along x toward the mirror axis (the left edge when there is
//! none), then along y toward the top. In: a wired `Schematic`. Out: the
//! same drawing closer together: nothing reordered, nothing on one line
//! taken off it, every symbol rigid, every stub its length.
//!
//! One-dimensional constraint-graph compaction (Lengauer, "Combinatorial
//! Algorithms for Integrated Circuit Layout", 1990, ch. 10). Every
//! coordinate along the axis is a **track**, and everything on a track stays
//! on it. The tracks one symbol holds move as one. Two things that would
//! touch if they slid past each other keep their order, and the smaller of
//! the gap they have and the gap the style asks. Each track then goes as
//! near the anchor as that allows: a longest path, by relaxation. The
//! drawing as it stands satisfies every constraint, so there is always an
//! answer and nothing moves outward; a mirrored drawing is folded about its
//! axis, so its two halves get the same constraints and stay mirrored.
//!
//! Contents:
//! - `pub fn squeeze(gpa: Allocator, s: *Schematic, len: Lengths, axis2: ?i32) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const geom = @import("geom.zig");
const placed = @import("placed.zig");

const Pt = library.Pt;
const Rect = library.Rect;
const Side = library.Side;
const Schematic = sch.Schematic;
const Lengths = canvas.Lengths;
const pt = canvas.toPt;
const none = sch.none;

/// One thing drawn, as the room it takes: a symbol with its name, or one
/// piece of a wire.
const Feature = struct { r: Rect, wire: bool };

/// A port, rail symbol or name, and the side its wire comes to it from.
const Leaf = struct { at: Pt, faces: Side };

/// A device's point and symbol: columns and rows keep their order and
/// their spacing.
const Device = struct { at: Pt, box: Rect };

/// The drawing as compaction reads it, on both axes.
const Drawing = struct {
    feats: std.ArrayList(Feature) = .empty,
    /// Pairs of points that move as one.
    ties: std.ArrayList([2]Pt) = .empty,
    devices: std.ArrayList(Device) = .empty,
};

/// `u(to) - u(from) >= w`, in folded, doubled coordinates.
const Constraint = struct { from: u32, to: u32, w: i32 };

/// The tracks of one axis, folded about the anchor and doubled (so an axis
/// between two whole coordinates is whole). A track is a distance from the
/// anchor: the two coordinates that far on either side are one track, so
/// both halves of a mirrored drawing answer the same constraints and move
/// alike. Per track: what it moves as one with, and how near the anchor its
/// constraints let it come.
const Graph = struct {
    /// Each track's distance from the anchor, doubled, ascending.
    dist: []const i32,
    /// Twice the anchor's coordinate.
    anchor2: i32,
    /// Every move is a multiple of this (doubled): what was on the
    /// quarter-unit grid stays on it, and parity holds.
    quantum: i32,
    /// Per track: its cluster (the tracks that move as one), first a
    /// union-find parent, then its root (`settle`).
    cluster: []u32,
    /// Per track: tied to a point on the anchor or across it. Then per
    /// track, whether its cluster stays where it is (`settle`).
    fixed: []bool,
    /// Per cluster root: its least distance.
    base: []i32,
    /// Per cluster root: the least distance found so far (`solve`).
    pos: []i32,
    /// Per track: a least distance of its own (a pair across the anchor).
    floor: []i32,
    cons: std.ArrayList(Constraint) = .empty,

    fn init(arena: Allocator, dist: []const i32, anchor2: i32, quantum: i32) Allocator.Error!Graph {
        assert(dist.len > 0 and quantum > 0);
        const n = dist.len;
        const g: Graph = .{
            .dist = dist,
            .anchor2 = anchor2,
            .quantum = quantum,
            .cluster = try arena.alloc(u32, n),
            .fixed = try arena.alloc(bool, n),
            .base = try arena.alloc(i32, n),
            .pos = try arena.alloc(i32, n),
            .floor = try arena.alloc(i32, n),
        };
        for (g.cluster, 0..) |*c, t| c.* = @intCast(t);
        @memset(g.fixed, false);
        @memset(g.floor, 0);
        return g;
    }

    /// Which side of the anchor the coordinate `x` is on: -1, 0, 1.
    fn side(g: *const Graph, x: i32) i32 {
        return std.math.sign(2 * x - g.anchor2);
    }

    /// The track of the coordinate `x`, which is on one.
    fn track(g: *const Graph, x: i32) u32 {
        const d: i32 = @intCast(@abs(2 * x - g.anchor2));
        var lo: usize = 0;
        var hi: usize = g.dist.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (g.dist[mid] < d) lo = mid + 1 else hi = mid;
        }
        assert(lo < g.dist.len and g.dist[lo] == d);
        return @intCast(lo);
    }

    fn root(g: *Graph, t: u32) u32 {
        var r = t;
        while (g.cluster[r] != r) r = g.cluster[r];
        var c = t;
        while (g.cluster[c] != r) {
            const next = g.cluster[c];
            g.cluster[c] = r;
            c = next;
        }
        return r;
    }

    /// The coordinates `a` and `b` move as one. One thing on the anchor or
    /// across it cannot close up on itself: it stays.
    fn tie(g: *Graph, a: i32, b: i32) void {
        const ra = g.root(g.track(a));
        const rb = g.root(g.track(b));
        if (ra != rb) g.cluster[rb] = ra;
        if (a != b and g.side(a) * g.side(b) <= 0) g.fixed[ra] = true;
    }

    /// After every `tie`: each track's root, each cluster's least
    /// distance, and which stay where they are.
    fn settle(g: *Graph) void {
        const n = g.dist.len;
        for (0..n) |t| g.cluster[t] = g.root(@intCast(t));
        @memset(g.base, std.math.maxInt(i32));
        for (0..n) |t| {
            const r = g.cluster[t];
            g.base[r] = @min(g.base[r], g.dist[t]);
            if (g.fixed[t] or g.dist[t] == 0) g.fixed[r] = true;
        }
        for (0..n) |t| g.fixed[t] = g.fixed[g.cluster[t]];
    }

    /// The coordinates `a < b` keep their order and `min(b - a, room)`
    /// between them. `a == b` asks nothing.
    fn keep(g: *Graph, arena: Allocator, a: i32, b: i32, room: i32) Allocator.Error!void {
        if (a >= b) return;
        const ta = g.track(a);
        const tb = g.track(b);
        if (ta != tb and g.cluster[ta] == g.cluster[tb]) return;
        const w = 2 * @min(b - a, room);
        assert(w > 0);
        if (g.side(a) >= 0 and g.side(b) >= 0) {
            try g.cons.append(arena, .{ .from = ta, .to = tb, .w = w });
        } else if (g.side(a) <= 0 and g.side(b) <= 0) {
            try g.cons.append(arena, .{ .from = tb, .to = ta, .w = w });
        } else {
            // One each side of the anchor: each keeps its share of the room,
            // in proportion to where it stands, so a mirrored pair halves it.
            const sum: i64 = @as(i64, g.dist[ta]) + g.dist[tb];
            assert(sum >= w);
            g.floor[ta] = @max(g.floor[ta], @as(i32, @intCast(@divCeil(@as(i64, w) * g.dist[ta], sum))));
            g.floor[tb] = @max(g.floor[tb], @as(i32, @intCast(@divCeil(@as(i64, w) * g.dist[tb], sum))));
        }
    }

    /// Each cluster as near the anchor as the constraints allow: the least
    /// fixed point, reached from below. The drawing as it stands is a
    /// solution, so every bound is under where the cluster stands now and
    /// the relaxation ends.
    fn solve(g: *Graph) void {
        const n = g.dist.len;
        for (0..n) |r| {
            if (g.cluster[r] != r) continue;
            g.pos[r] = if (g.fixed[r]) g.base[r] else @mod(g.base[r], g.quantum);
        }
        for (0..n) |t| _ = g.raise(@intCast(t), g.floor[t]);
        var rounds: usize = 0;
        var changed = true;
        while (changed) : (rounds += 1) {
            assert(rounds <= n + 1);
            changed = false;
            for (g.cons.items) |c| {
                const from = g.cluster[c.from];
                const reach = g.pos[from] + (g.dist[c.from] - g.base[from]) + c.w;
                if (g.raise(c.to, reach)) changed = true;
            }
        }
    }

    /// Track `t` stands at least `d` from the anchor: its cluster out to the
    /// next whole step that allows it. Whether the cluster moved.
    fn raise(g: *Graph, t: u32, d: i32) bool {
        const r = g.cluster[t];
        if (g.fixed[r]) return false;
        const want = d - (g.dist[t] - g.base[r]);
        if (want <= g.pos[r]) return false;
        assert(want <= g.base[r]); // where it stands now satisfies everything
        g.pos[r] = g.base[r] - @divFloor(g.base[r] - want, g.quantum) * g.quantum;
        return true;
    }

    /// Where the coordinate `x` went.
    fn moved(g: *const Graph, x: i32) i32 {
        const t = g.track(x);
        const r = g.cluster[t];
        const d = g.pos[r] + (g.dist[t] - g.base[r]);
        assert(d >= 0 and d <= g.dist[t]);
        return @divExact(g.anchor2 + g.side(x) * d, 2);
    }
};

/// Closes `s` up in place: x toward `axis2` (twice the mirror axis; null
/// for the left edge), then y toward the top. `len.series` and `len.stack`
/// are the least room kept between device columns and between the rows of
/// one column (two symbols `len.series` apart along x pass each other
/// along y), `len.tap` the
/// least length of a wire between two symbols, bends or junctions, and
/// `len.clearance` the least room between any other two things; a gap
/// already smaller is kept as it is. `gpa` backs the work.
pub fn squeeze(gpa: Allocator, s: *Schematic, len: Lengths, axis2: ?i32) Allocator.Error!void {
    assert(s.xy.len == s.nodes.len);
    for ([_]u1{ 0, 1 }) |ax| {
        var arena_state: std.heap.ArenaAllocator = .init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        // Read again for y: the x pass moved everything.
        const d = try read(arena, s, len);
        try pass(arena, s, &d, len, ax, if (ax == 0) axis2 else null);
    }
}

// ---- private ----

/// The drawing's features and ties, from the schematic as it stands.
fn read(arena: Allocator, s: *const Schematic, len: Lengths) Allocator.Error!Drawing {
    var d: Drawing = .{};
    const info = s.devices.slice();
    const kinds = s.nodes.items(.kind);
    const refs = s.nodes.items(.ref);
    const groups = s.nodes.items(.group);
    // Which way each leaf's name runs: away from its wire.
    const runs = try arena.alloc(Side, s.nodes.len);
    @memset(runs, .left);
    for (s.pins.items(.home), s.pins.items(.side), s.pins.items(.device), 0..) |home, side, dev, p| {
        if (dev == none) {
            runs[home] = side.opposite();
        } else {
            // A pin with its device, where the wire meets it.
            try d.ties.append(arena, .{ pt(s.xy[groups[home]]), canvas.pinAt(s, @intCast(p)) });
        }
    }
    var leaves: std.ArrayList(Leaf) = .empty;
    for (kinds, refs, groups, 0..) |kind, ref, group, node| {
        const at = pt(s.xy[node]);
        var box: Rect = .point(at);
        switch (kind) {
            .device => {
                // A copy (a pin off its device's line) moves with it.
                try d.ties.append(arena, .{ pt(s.xy[group]), at });
                if (group != node) continue;
                const class = s.lib.at(info.items(.class)[ref]);
                const o = info.items(.orient)[ref];
                const origin = at.sub(info.items(.grid)[ref]);
                box = canvas.boxAt(s, ref, at);
                for (class.terminals[0..@min(class.terminals.len, s.device_pin_count[ref])]) |t| {
                    try d.ties.append(arena, .{ at, origin.add(o.apply(t.at)) });
                }
                try d.devices.append(arena, .{ .at = at, .box = box });
            },
            .terminal, .label => {
                try leaves.append(arena, .{ .at = at, .faces = runs[node].opposite() });
                if (kind == .terminal) if (placed.roleClass(s, ref)) |c| {
                    const class = s.lib.at(c);
                    box = class.bbox().translate(at.sub(class.terminals[0].at));
                };
                // A port's or a label's name is drawn beside it.
                if (kind == .label or s.roles[ref] == .input or s.roles[ref] == .output or s.roles[ref] == .bias) {
                    box = box.merge(nameBox(at, runs[node], s.net_name[ref]));
                }
            },
        }
        try d.feats.append(arena, .{ .r = box, .wire = false });
        try d.ties.append(arena, .{ at, box.min });
        try d.ties.append(arena, .{ at, box.max });
    }
    for (s.routes.items) |r| {
        for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |a, b| {
            try d.feats.append(arena, .{ .r = .fromCorners(pt(a), pt(b)), .wire = true });
        }
        if (r.len != 2) continue;
        // A stub keeps its length: a rail's to its bar or symbol, and any
        // wire that ends on a port, a symbol or a name. A rail's longer way
        // up to its bar, from a lower row, is a wire like any other: tied,
        // it would hold its row where the lattice put it.
        const a = pt(r.pts[0]);
        const b = pt(r.pts[1]);
        const rail = s.roles[r.net] == .supply or s.roles[r.net] == .sink;
        const stub = for (leaves.items) |l| {
            if ((l.at.eql(a) and toward(a, b) == l.faces) or (l.at.eql(b) and toward(b, a) == l.faces)) break true;
        } else false;
        if ((rail and a.x == b.x and @abs(b.y - a.y) <= len.rail) or stub) try d.ties.append(arena, .{ a, b });
    }
    return d;
}

/// One axis: `ax` 0 moves x toward `fold2` (twice the axis; null for the
/// least x), 1 moves y toward the least y.
fn pass(arena: Allocator, s: *Schematic, d: *const Drawing, len: Lengths, ax: u1, fold2: ?i32) Allocator.Error!void {
    // Tracks: every distance from the anchor along the axis, once, in order.
    var coords: std.ArrayList(i32) = .empty;
    for (d.feats.items) |f| try coords.appendSlice(arena, &.{ along(f.r.min, ax), along(f.r.max, ax) });
    for (d.ties.items) |t| try coords.appendSlice(arena, &.{ along(t[0], ax), along(t[1], ax) });
    for (s.xy) |p| try coords.append(arena, along(pt(p), ax));
    for (s.routes.items) |r| for (r.pts[0..r.len]) |p| try coords.append(arena, along(pt(p), ax));
    if (coords.items.len == 0) return;
    const anchor2 = fold2 orelse 2 * std.mem.min(i32, coords.items);
    for (coords.items) |*c| c.* = @intCast(@abs(2 * c.* - anchor2));
    std.mem.sort(i32, coords.items, {}, std.sort.asc(i32));
    var n: usize = 1;
    for (coords.items[1..]) |c| if (c != coords.items[n - 1]) {
        coords.items[n] = c;
        n += 1;
    };
    var g: Graph = try .init(arena, coords.items[0..n], anchor2, 2 * @max(1, @divFloor(len.unit, 4)));

    for (d.ties.items) |t| g.tie(along(t[0], ax), along(t[1], ax));
    g.settle();

    // Things that would touch sliding past each other keep their order.
    const feats = d.feats.items;
    for (feats, 0..) |fa, i| for (feats[i + 1 ..]) |fb| {
        const gap = @max(across(fb.r.min, ax) - across(fa.r.max, ax), across(fa.r.min, ax) - across(fb.r.max, ax));
        if (gap >= len.clearance) continue;
        for ([_]i32{ along(fa.r.min, ax), along(fa.r.max, ax) }) |ea| for ([_]i32{ along(fb.r.min, ax), along(fb.r.max, ax) }) |eb| {
            try g.keep(arena, @min(ea, eb), @max(ea, eb), len.clearance);
        };
    };
    // A wire between two symbols, bends or junctions keeps `tap`.
    for (feats) |f| if (f.wire) try g.keep(arena, along(f.r.min, ax), along(f.r.max, ax), len.tap);
    // Device columns (rows) keep their order, and `series` (`stack`)
    // between the symbols of two that stand clear of each other.
    const room = [2]i32{ len.series, len.stack };
    for (d.devices.items, 0..) |da, i| for (d.devices.items[i + 1 ..]) |db| {
        const a, const b = if (along(da.at, ax) <= along(db.at, ax)) .{ da, db } else .{ db, da };
        try g.keep(arena, along(a.at, ax), along(b.at, ax), @divExact(g.quantum, 2));
        // A row is its column's: two symbols a column apart may stand
        // beside each other (a tall block beside a stack), held only by
        // their order and by what would touch. And a column is its row's:
        // two symbols a row apart keep their order, not `series`, so a
        // pair's halves close over its tail as people draw them
        // (neighbouring columns 1.98 units apart at the mean in 5,263
        // hand-drawn schematics; with `series` between every two, 2.95).
        const beside = @max(across(b.box.min, ax) - across(a.box.max, ax), across(a.box.min, ax) - across(b.box.max, ax));
        if (beside >= room[1 - ax]) continue;
        try g.keep(arena, along(a.box.max, ax), along(b.box.min, ax), room[ax]);
    };

    g.solve();
    for (s.xy) |*p| p[ax] = @floatFromInt(g.moved(along(pt(p.*), ax)));
    for (s.routes.items) |*r| for (r.pts[0..r.len]) |*p| {
        p[ax] = @floatFromInt(g.moved(along(pt(p.*), ax)));
    };
}

/// The room a net's name takes written from `at` toward `side`.
fn nameBox(at: Pt, side: Side, name: []const u8) Rect {
    const w = geom.refdesWidth(name);
    const h = geom.text_h + geom.descent;
    const half = @divFloor(h + 1, 2);
    return switch (side) {
        .right => .{ .min = .{ .x = at.x, .y = at.y - half }, .max = .{ .x = at.x + w, .y = at.y + half } },
        .left => .{ .min = .{ .x = at.x - w, .y = at.y - half }, .max = .{ .x = at.x, .y = at.y + half } },
        .up => .{ .min = .{ .x = at.x - @divFloor(w, 2), .y = at.y - h }, .max = .{ .x = at.x + @divFloor(w + 1, 2), .y = at.y } },
        .down => .{ .min = .{ .x = at.x - @divFloor(w, 2), .y = at.y }, .max = .{ .x = at.x + @divFloor(w + 1, 2), .y = at.y + h } },
    };
}

/// The side of `from` that `to` lies on, the two on one row or column.
fn toward(from: Pt, to: Pt) Side {
    assert(from.x == to.x or from.y == to.y);
    return if (to.x > from.x) .right else if (to.x < from.x) .left else if (to.y > from.y) .down else .up;
}

fn along(p: Pt, ax: u1) i32 {
    return if (ax == 0) p.x else p.y;
}

fn across(p: Pt, ax: u1) i32 {
    return along(p, 1 - ax);
}
