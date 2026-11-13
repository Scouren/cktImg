//! A maze router for one connection (issue #8, stage 4): the cheapest
//! orthogonal path from a pin to its net's wires so far. In: the devices'
//! boxes, everything drawn so far, the pin and its side, the net. Out: the
//! path's corners, pin first, or null.
//!
//! Human Rules:
//! - maze.1 (choice) A routed wire runs on a lattice of `step` (a quarter
//!   unit, at least 1) or on a line a pin, a box edge or another wire
//!   already has, so it meets any of them exactly. `route`
//! - maze.2 (book) A routed wire is the cheapest orthogonal path: its
//!   length, plus `bend` a bend, plus `cross` each crossing of another
//!   net's wire. After M. Wybrow, K. Marriott and P. J. Stuckey,
//!   "Orthogonal Connector Routing", Graph Drawing 2009. `route`
//! - maze.3 (book) Crossing a rail's wire costs a quarter of `cross`: the
//!   book crosses supply stubs freely. `route`
//! - maze.4 (invariant) A routed wire never runs inside a device's box,
//!   along or within `clear` of another net's wire, within `clear` of
//!   another net's point, across a wall (a rail's short stub, its bar), or
//!   through a point of its own net that is not where it ends. `route`
//! - maze.5 (invariant) A routed wire crosses another net's wire straight,
//!   never bends on it and never ends on it. `route`
//! - maze.6 (invariant) A routed wire leaves its pin the way the pin faces,
//!   never turns straight back, and enters the pin it runs to from that
//!   pin's side. `route`
//! - maze.7 (choice) The cheapest path is sought round the pin and its
//!   nearest target first, then round the whole net, then over the whole
//!   drawing: most connections are local. `route`
//! - maze.8 (choice) A grid of more than 65,536 points is not searched,
//!   and the pin is named instead: it bounds the work. `route`
//!
//! Contents:
//! - `pub const Wire = struct`
//! - `pub const Mark = struct { at: Pt, net: u32 }`
//! - `pub const Pin = struct { at: Pt, side: Side }`
//! - `pub const Query = struct`
//! - `pub fn route(gpa: Allocator, q: Query) Allocator.Error!?[]Pt`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");

const Pt = library.Pt;
const Rect = library.Rect;
const Side = library.Side;

/// A straight wire of one net.
pub const Wire = struct {
    a: Pt,
    b: Pt,
    net: u32,
    /// No other net's path crosses it (a rail symbol's stub).
    wall: bool = false,
};
/// A point of one net: a pin, a wire's end or bend, a label, a terminal.
pub const Mark = struct { at: Pt, net: u32 };
/// A pin and the side its wire leaves by.
pub const Pin = struct { at: Pt, side: Side };

pub const Query = struct {
    net: u32,
    /// The pin to route from; the first step leaves by its side.
    from: Pin,
    /// The pin to reach, entered from its side, while the net has no wire;
    /// else null and any point of the net's wires is a target.
    to: ?Pin,
    /// Routes in x <= `half` only, a free point on x = `half` a target too
    /// (one half of a symmetric net, to be mirrored).
    half: ?i32 = null,
    /// Per net: a rail, whose wires cost a quarter of `cross` to cross (the
    /// book crosses supply stubs freely). Empty: none is.
    rails: []const bool = &.{},
    boxes: []const Rect,
    /// Everything drawn so far, every net.
    wires: []const Wire,
    marks: []const Mark,
    step: i32,
    /// At least 1: how near another net's wire or point a path may come.
    clear: i32,
    bend: i64,
    cross: i64,
};

/// Grids with more points are not searched: the caller labels instead.
const points_max = 1 << 16;

const none: u32 = std.math.maxInt(u32);

/// The four ways in `Side` order (left, right, up, down; y grows down).
const ways = [4][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };

/// Another net's wire through a point: none, a rail's, a signal's.
const Cross = enum(u8) { none, rail, signal };

const Grid = struct {
    xs: []i32,
    ys: []i32,
    /// Per point: no path passes (near another net's point, or a point of
    /// the net that is no target).
    closed: []bool,
    /// A point of the net's wires, or the pin to reach.
    target: []bool,
    /// Another net's horizontal or vertical wire passes the point.
    h_other: []Cross,
    v_other: []Cross,
    /// Per point and way: that step runs inside a box, or along or beside
    /// another net's wire.
    blocked: [][4]bool,

    fn width(g: Grid) usize {
        return g.xs.len;
    }
    fn at(g: Grid, i: usize) Pt {
        return .{ .x = g.xs[i % g.width()], .y = g.ys[i / g.width()] };
    }
    fn block(g: Grid, i: usize, horizontal: bool) void {
        // The step from point i right (or down) to the next, both ways.
        const j = if (horizontal) i + 1 else i + g.width();
        g.blocked[i][if (horizontal) 1 else 3] = true;
        g.blocked[j][if (horizontal) 0 else 2] = true;
    }
    fn deinit(g: Grid, gpa: Allocator) void {
        gpa.free(g.xs);
        gpa.free(g.ys);
        gpa.free(g.closed);
        gpa.free(g.target);
        gpa.free(g.h_other);
        gpa.free(g.v_other);
        gpa.free(g.blocked);
    }
};

const State = struct { f: i64, cost: i64, point: u32, way: u8 };

/// The open states, lowest estimate first (Dial's buckets: costs are
/// integers and the guess is consistent, so no estimate drops below the
/// one popped last); the last pushed first among equals.
const Buckets = struct {
    lists: std.ArrayList(std.ArrayList(State)) = .empty,
    base: i64,
    cur: usize = 0,

    fn push(b: *Buckets, a: Allocator, st: State) Allocator.Error!void {
        assert(st.f >= b.base);
        const i: usize = @intCast(st.f - b.base);
        assert(i >= b.cur);
        while (b.lists.items.len <= i) try b.lists.append(a, .empty);
        try b.lists.items[i].append(a, st);
    }
    fn pop(b: *Buckets) ?State {
        while (b.cur < b.lists.items.len) : (b.cur += 1) {
            if (b.lists.items[b.cur].pop()) |st| return st;
        }
        return null;
    }
};

/// The cheapest path from `q.from` to the net's wires (or to `q.to`), as
/// its corners from `q.from.at`; null when there is none or the grid is too
/// big. The caller owns the slice.
pub fn route(gpa: Allocator, q: Query) Allocator.Error!?[]Pt {
    assert(q.step > 0 and q.clear >= 1);
    assert(q.bend >= 0 and q.cross >= 0);
    // Most connections are local: a window round the pin and its nearest
    // target first, then round the whole net, then the whole drawing.
    if (try search(gpa, q, window(q, true))) |path| return path;
    if (try search(gpa, q, window(q, false))) |path| return path;
    return search(gpa, q, null);
}

// ---- private ----

/// The pin, the nearest point of the net's wires (all of them unless
/// `nearest_only`), the pin to reach and the axis it may end on, `8 * step`
/// round, grown over every box it cuts into, so no box's edge falls
/// outside.
fn window(q: Query, nearest_only: bool) Rect {
    const p = q.from.at;
    var r: Rect = .point(p);
    if (q.to) |t| r = r.merge(.point(t.at));
    if (q.half) |h| r = r.merge(.point(.{ .x = h, .y = p.y }));
    var nearest: ?Pt = null;
    var dist: i64 = std.math.maxInt(i64);
    for (q.wires) |w| if (w.net == q.net) {
        const b: Rect = .fromCorners(w.a, w.b);
        if (!nearest_only) r = r.merge(b);
        const c: Pt = .{ .x = std.math.clamp(p.x, b.min.x, b.max.x), .y = std.math.clamp(p.y, b.min.y, b.max.y) };
        const d = @as(i64, @abs(c.x - p.x)) + @abs(c.y - p.y);
        if (d < dist) {
            dist = d;
            nearest = c;
        }
    };
    if (nearest) |c| r = r.merge(.point(c));
    r = r.grow(8 * q.step);
    var rounds: usize = 0;
    while (true) : (rounds += 1) {
        assert(rounds <= q.boxes.len + 1);
        var grown = false;
        for (q.boxes) |b| if (b.intersects(r) and !(r.contains(b.min) and r.contains(b.max))) {
            r = r.merge(b);
            grown = true;
        };
        if (!grown) break;
    }
    return r;
}

/// `route` inside `win` (or everywhere): only what lies within `clear` of
/// it is an obstacle, and no step leaves it.
fn search(gpa: Allocator, q_all: Query, win: ?Rect) Allocator.Error!?[]Pt {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const scratch = arena.allocator();
    const q = try nearby(scratch, q_all, win);
    const g = (try buildGrid(gpa, q, win)) orelse return null;
    defer g.deinit(gpa);
    const n = g.xs.len * g.ys.len;
    const start = indexOf(g, q.from.at).?;
    const goal_point: u32 = if (q.to) |t| indexOf(g, t.at).? else none;
    const goal_way: u8 = if (q.to) |t| @backingInt(t.side.opposite()) else 0;

    // The targets' bounding box, for an admissible guess.
    var lo: Pt = .{ .x = std.math.maxInt(i32), .y = std.math.maxInt(i32) };
    var hi: Pt = .{ .x = std.math.minInt(i32), .y = std.math.minInt(i32) };
    for (g.target, 0..) |t, i| if (t) {
        const p = g.at(i);
        lo = .{ .x = @min(lo.x, p.x), .y = @min(lo.y, p.y) };
        hi = .{ .x = @max(hi.x, p.x), .y = @max(hi.y, p.y) };
    };
    if (lo.x > hi.x) return null;

    const best = try gpa.alloc(i64, n * 4);
    defer gpa.free(best);
    @memset(best, std.math.maxInt(i64));
    const parent = try gpa.alloc(u32, n * 4);
    defer gpa.free(parent);
    @memset(parent, none);
    const first: u8 = @backingInt(q.from.side);
    best[start * 4 + first] = 0;
    var open: Buckets = .{ .base = guess(q.from.at, lo, hi) };
    try open.push(scratch, .{ .f = open.base, .cost = 0, .point = start, .way = first });
    var popped: usize = 0;
    const found: u32 = while (open.pop()) |st| : (popped += 1) {
        assert(popped <= n * 16);
        const key = st.point * 4 + st.way;
        if (st.cost > best[key]) continue;
        const on_other = g.h_other[st.point] != .none or g.v_other[st.point] != .none;
        if (st.point != start and g.target[st.point] and !on_other) break key;
        for (0..4) |w| {
            const way: u8 = @intCast(w);
            // The pin's own side first, then never straight back.
            if (st.point == start and way != first) continue;
            if (way ^ 1 == st.way) continue;
            const turn = way != st.way;
            // A bend on another net's wire would join it.
            if (turn and on_other) continue;
            if (g.blocked[st.point][way]) continue;
            const next = neighbour(g, st.point, way) orelse continue;
            if (g.closed[next] and !g.target[next]) continue;
            if (next == goal_point and way != goal_way) continue;
            const a = g.at(st.point);
            const b = g.at(next);
            if (q.half) |h| if (b.x > h) continue;
            if (win) |box| if (!box.contains(b)) continue;
            var cost: i64 = st.cost + @abs(a.x - b.x) + @abs(a.y - b.y);
            if (turn) cost += q.bend;
            cost += switch (if (way < 2) g.v_other[next] else g.h_other[next]) {
                .none => 0,
                .rail => @divFloor(q.cross, 4),
                .signal => q.cross,
            };
            const nk = next * 4 + way;
            if (cost >= best[nk]) continue;
            best[nk] = cost;
            parent[nk] = key;
            try open.push(scratch, .{ .f = cost + guess(b, lo, hi), .cost = cost, .point = next, .way = way });
        }
    } else return null;
    return try corners(gpa, g, parent, found, start, q.from.at);
}

/// `q` with only the boxes, marks and wires within `clear` of `win`.
fn nearby(a: Allocator, q: Query, win: ?Rect) Allocator.Error!Query {
    const w = win orelse return q;
    const reach = w.grow(q.clear);
    var boxes: std.ArrayList(Rect) = .empty;
    for (q.boxes) |b| if (b.intersects(reach)) try boxes.append(a, b);
    var marks: std.ArrayList(Mark) = .empty;
    for (q.marks) |m| if (reach.contains(m.at)) try marks.append(a, m);
    var wires: std.ArrayList(Wire) = .empty;
    for (q.wires) |x| if (Rect.fromCorners(x.a, x.b).intersects(reach)) try wires.append(a, x);
    var out = q;
    out.boxes = boxes.items;
    out.marks = marks.items;
    out.wires = wires.items;
    return out;
}

fn guess(p: Pt, lo: Pt, hi: Pt) i64 {
    const dx: i64 = if (p.x < lo.x) lo.x - p.x else if (p.x > hi.x) p.x - hi.x else 0;
    const dy: i64 = if (p.y < lo.y) lo.y - p.y else if (p.y > hi.y) p.y - hi.y else 0;
    return dx + dy;
}

/// Back from `found` to the start, keeping the points where the way turns.
fn corners(gpa: Allocator, g: Grid, parent: []const u32, found: u32, start: u32, from: Pt) ![]Pt {
    var out: std.ArrayList(Pt) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, g.at(found / 4));
    var k = found;
    var walked: usize = 0;
    while (parent[k] != none) : (walked += 1) {
        assert(walked <= parent.len);
        const p = parent[k];
        if (p % 4 != k % 4 and p / 4 != start) try out.append(gpa, g.at(p / 4));
        k = p;
    }
    assert(k / 4 == start);
    try out.append(gpa, from);
    std.mem.reverse(Pt, out.items);
    assert(out.items.len >= 2);
    return out.toOwnedSlice(gpa);
}

fn neighbour(g: Grid, i: u32, way: u8) ?u32 {
    const x = @as(i64, @intCast(i % g.width())) + ways[way][0];
    const y = @as(i64, @intCast(i / g.width())) + ways[way][1];
    if (x < 0 or y < 0 or x >= g.xs.len or y >= g.ys.len) return null;
    return @intCast(@as(usize, @intCast(y)) * g.width() + @as(usize, @intCast(x)));
}

fn indexOf(g: Grid, p: Pt) ?u32 {
    const i = std.sort.binarySearch(i32, g.xs, p.x, order) orelse return null;
    const j = std.sort.binarySearch(i32, g.ys, p.y, order) orelse return null;
    return @intCast(j * g.width() + i);
}

fn order(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

/// The indices of the sorted `vs` from `lo` to `hi`, both included.
fn within(vs: []const i32, lo: i32, hi: i32) [2]usize {
    return .{ std.sort.lowerBound(i32, vs, lo, order), std.sort.upperBound(i32, vs, hi, order) };
}

/// Sets `flags` at every grid point in `r`; asserts there is one.
fn flag(g: Grid, flags: []bool, r: Rect) void {
    const cols = within(g.xs, r.min.x, r.max.x);
    const rows = within(g.ys, r.min.y, r.max.y);
    assert(rows[1] > rows[0] and cols[1] > cols[0]);
    for (rows[0]..rows[1]) |j| for (cols[0]..cols[1]) |i| {
        flags[j * g.width() + i] = true;
    };
}

/// The steps (from index i to i + 1) of the sorted `vs` that overlap the
/// open interval (lo, hi).
fn spanning(vs: []const i32, lo: i32, hi: i32) [2]usize {
    const first = std.sort.upperBound(i32, vs, lo, order) -| 1;
    const end = @min(std.sort.lowerBound(i32, vs, hi, order), vs.len - 1);
    return .{ first, @max(first, end) };
}

/// The grid lines, and what lies on them; the lattice over `win`, else
/// over everything with room to go round it.
fn buildGrid(gpa: Allocator, q: Query, win: ?Rect) Allocator.Error!?Grid {
    var xs: std.ArrayList(i32) = .empty;
    defer xs.deinit(gpa);
    var ys: std.ArrayList(i32) = .empty;
    defer ys.deinit(gpa);
    try xs.append(gpa, q.from.at.x);
    try ys.append(gpa, q.from.at.y);
    if (q.to) |t| {
        try xs.append(gpa, t.at.x);
        try ys.append(gpa, t.at.y);
    }
    if (q.half) |h| try xs.append(gpa, h);
    for (q.boxes) |b| {
        try xs.appendSlice(gpa, &.{ b.min.x, b.max.x });
        try ys.appendSlice(gpa, &.{ b.min.y, b.max.y });
    }
    for (q.marks) |m| {
        try xs.append(gpa, m.at.x);
        try ys.append(gpa, m.at.y);
    }
    for (q.wires) |w| {
        try xs.appendSlice(gpa, &.{ w.a.x, w.b.x });
        try ys.appendSlice(gpa, &.{ w.a.y, w.b.y });
    }
    const margin = 4 * q.step;
    const lo_x = if (win) |w| w.min.x else std.mem.min(i32, xs.items) - margin;
    const hi_x = if (win) |w| w.max.x else std.mem.max(i32, xs.items) + margin;
    const lo_y = if (win) |w| w.min.y else std.mem.min(i32, ys.items) - margin;
    const hi_y = if (win) |w| w.max.y else std.mem.max(i32, ys.items) + margin;
    if (@divFloor(hi_x - lo_x, q.step) * @divFloor(hi_y - lo_y, q.step) > points_max) return null;
    var v = @divFloor(lo_x, q.step) * q.step;
    while (v <= hi_x) : (v += q.step) try xs.append(gpa, v);
    v = @divFloor(lo_y, q.step) * q.step;
    while (v <= hi_y) : (v += q.step) try ys.append(gpa, v);
    const gx = try sortedUnique(gpa, xs.items);
    errdefer gpa.free(gx);
    const gy = try sortedUnique(gpa, ys.items);
    errdefer gpa.free(gy);
    const n = gx.len * gy.len;
    if (n > points_max) {
        gpa.free(gx);
        gpa.free(gy);
        return null;
    }
    const closed = try gpa.alloc(bool, n);
    errdefer gpa.free(closed);
    const target = try gpa.alloc(bool, n);
    errdefer gpa.free(target);
    const h_other = try gpa.alloc(Cross, n);
    errdefer gpa.free(h_other);
    const v_other = try gpa.alloc(Cross, n);
    errdefer gpa.free(v_other);
    const blocked = try gpa.alloc([4]bool, n);
    const g: Grid = .{ .xs = gx, .ys = gy, .closed = closed, .target = target, .h_other = h_other, .v_other = v_other, .blocked = blocked };
    @memset(g.closed, false);
    @memset(g.target, false);
    @memset(g.h_other, .none);
    @memset(g.v_other, .none);
    @memset(g.blocked, .{ false, false, false, false });
    for (q.boxes) |b| blockBox(g, b);
    for (q.wires) |w| {
        assert(w.a.x == w.b.x or w.a.y == w.b.y);
        const rail = w.net < q.rails.len and q.rails[w.net];
        // Every grid point along the net's own wire is a target, and along
        // another net's wall closed.
        if (w.net == q.net) flag(g, g.target, .fromCorners(w.a, w.b)) else otherWire(g, w, q.clear, if (rail) .rail else .signal);
        if (w.net != q.net and w.wall) flag(g, g.closed, .fromCorners(w.a, w.b));
    }
    for (q.marks) |m| {
        if (m.net != q.net) {
            // The grid points nearer than `clear` to another net's point.
            flag(g, g.closed, Rect.point(m.at).grow(q.clear - 1));
        } else {
            const i = indexOf(g, m.at).?;
            if (!g.target[i]) g.closed[i] = true;
        }
    }
    if (q.to) |t| g.target[indexOf(g, t.at).?] = true;
    if (q.half) |h| {
        const i = std.sort.binarySearch(i32, g.xs, h, order).?;
        for (0..g.ys.len) |j| {
            const k = j * g.width() + i;
            if (!g.closed[k] and g.h_other[k] == .none and g.v_other[k] == .none) g.target[k] = true;
        }
    }
    g.closed[indexOf(g, q.from.at).?] = false;
    return g;
}

/// Steps whose middle lies strictly inside the box (its edges are lines).
fn blockBox(g: Grid, b: Rect) void {
    const x0, const x1 = within(g.xs, b.min.x, b.max.x);
    const y0, const y1 = within(g.ys, b.min.y, b.max.y);
    assert(x1 > x0 and y1 > y0);
    // Rows and columns strictly inside, each step between the edges.
    for (y0 + 1..@max(y0 + 1, y1 - 1)) |j| for (x0..x1 - 1) |i| g.block(j * g.width() + i, true);
    for (x0 + 1..@max(x0 + 1, x1 - 1)) |i| for (y0..y1 - 1) |j| g.block(j * g.width() + i, false);
}

/// Another net's wire: its points are crossings of kind `kind`; steps
/// along it, or on a line nearer than `clear` (at least 1) beside it, are
/// blocked.
fn otherWire(g: Grid, w: Wire, clear: i32, kind: Cross) void {
    assert(w.a.x == w.b.x or w.a.y == w.b.y);
    const r = Rect.fromCorners(w.a, w.b);
    if (r.min.y == r.max.y) {
        const rows = within(g.ys, r.min.y - clear + 1, r.min.y + clear - 1);
        const along = spanning(g.xs, r.min.x - clear, r.max.x + clear);
        for (rows[0]..rows[1]) |j| for (along[0]..along[1]) |i| g.block(j * g.width() + i, true);
        const j = indexOf(g, r.min).? / g.width();
        for (0..g.xs.len) |i| {
            const k = j * g.width() + i;
            if (g.xs[i] >= r.min.x and g.xs[i] <= r.max.x) g.h_other[k] = @fromBackingInt(@intCast(@max(@backingInt(g.h_other[k]), @backingInt(kind))));
        }
    } else {
        const cols = within(g.xs, r.min.x - clear + 1, r.min.x + clear - 1);
        const along = spanning(g.ys, r.min.y - clear, r.max.y + clear);
        for (cols[0]..cols[1]) |i| for (along[0]..along[1]) |j| g.block(j * g.width() + i, false);
        const i = indexOf(g, r.min).? % g.width();
        for (0..g.ys.len) |j| {
            const k = j * g.width() + i;
            if (g.ys[j] >= r.min.y and g.ys[j] <= r.max.y) g.v_other[k] = @fromBackingInt(@intCast(@max(@backingInt(g.v_other[k]), @backingInt(kind))));
        }
    }
}

fn sortedUnique(gpa: Allocator, items: []i32) ![]i32 {
    std.mem.sort(i32, items, {}, std.sort.asc(i32));
    var k: usize = 0;
    for (items) |v| {
        if (k > 0 and v == items[k - 1]) continue;
        items[k] = v;
        k += 1;
    }
    assert(k >= 1);
    return gpa.dupe(i32, items[0..k]);
}

// ---- tests ----

fn query(from: Pin, to: ?Pin, boxes: []const Rect, wires: []const Wire, marks: []const Mark) Query {
    return .{ .net = 0, .from = from, .to = to, .boxes = boxes, .wires = wires, .marks = marks, .step = 10, .clear = 5, .bend = 10, .cross = 30 };
}

fn expectPath(want: []const Pt, got: ?[]Pt) !void {
    const path = got orelse return error.TestExpectedPath;
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualSlices(Pt, want, path);
}

test "maze: facing pins in one line are joined straight" {
    const a: Pin = .{ .at = .{ .x = 0, .y = 0 }, .side = .right };
    const b: Pin = .{ .at = .{ .x = 50, .y = 0 }, .side = .left };
    const marks = [_]Mark{ .{ .at = a.at, .net = 0 }, .{ .at = b.at, .net = 0 } };
    try expectPath(&.{ a.at, b.at }, try route(std.testing.allocator, query(a, b, &.{}, &.{}, &marks)));
}

test "maze: a pin is entered from its side, never through its box" {
    // b faces up from the top of its box, a sits level with the box's
    // middle: one bend over the box and down onto b.
    const a: Pin = .{ .at = .{ .x = 0, .y = 40 }, .side = .right };
    const b: Pin = .{ .at = .{ .x = 50, .y = 20 }, .side = .up };
    const box: Rect = .{ .min = .{ .x = 40, .y = 20 }, .max = .{ .x = 60, .y = 60 } };
    const marks = [_]Mark{ .{ .at = a.at, .net = 0 }, .{ .at = b.at, .net = 0 } };
    const path = (try route(std.testing.allocator, query(a, b, &.{box}, &.{}, &marks))).?;
    defer std.testing.allocator.free(path);
    try std.testing.expect(path[0].eql(a.at) and path[path.len - 1].eql(b.at));
    // The last leg comes down onto b; nothing runs inside the box.
    const last = path[path.len - 2];
    try std.testing.expect(last.x == b.at.x and last.y < b.at.y);
    for (path[0 .. path.len - 1], path[1..]) |p, q| {
        const s = Rect.fromCorners(p, q);
        try std.testing.expect(!(s.max.x > box.min.x and s.min.x < box.max.x and s.max.y > box.min.y and s.min.y < box.max.y));
    }
}

test "maze: another net's wire is crossed straight when going round costs more" {
    const a: Pin = .{ .at = .{ .x = 0, .y = 0 }, .side = .right };
    const b: Pin = .{ .at = .{ .x = 60, .y = 0 }, .side = .left };
    // A long wire of net 1 across the way, its ends far off.
    const wall = [_]Wire{.{ .a = .{ .x = 30, .y = -200 }, .b = .{ .x = 30, .y = 200 }, .net = 1 }};
    const marks = [_]Mark{ .{ .at = a.at, .net = 0 }, .{ .at = b.at, .net = 0 }, .{ .at = wall[0].a, .net = 1 }, .{ .at = wall[0].b, .net = 1 } };
    try expectPath(&.{ a.at, b.at }, try route(std.testing.allocator, query(a, b, &.{}, &wall, &marks)));
}

test "maze: a path ends on the net's wire and keeps clear of another net's point" {
    const a: Pin = .{ .at = .{ .x = 0, .y = 0 }, .side = .down };
    // The net's wire below; a point of net 1 straight in the way.
    const own = [_]Wire{.{ .a = .{ .x = -40, .y = 40 }, .b = .{ .x = 40, .y = 40 }, .net = 0 }};
    const other: Pt = .{ .x = 0, .y = 20 };
    const marks = [_]Mark{ .{ .at = a.at, .net = 0 }, .{ .at = own[0].a, .net = 0 }, .{ .at = own[0].b, .net = 0 }, .{ .at = other, .net = 1 } };
    const path = (try route(std.testing.allocator, query(a, null, &.{}, &own, &marks))).?;
    defer std.testing.allocator.free(path);
    try std.testing.expect(path[0].eql(a.at));
    try std.testing.expectEqual(@as(i32, 40), path[path.len - 1].y);
    for (path[0 .. path.len - 1], path[1..]) |p, q| try std.testing.expect(!Rect.fromCorners(p, q).contains(other));
}
