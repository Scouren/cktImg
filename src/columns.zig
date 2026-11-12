//! Column order (issue #8, stage 3): where each column of devices stands.
//! In: the columns (devices top to bottom), each device's mate, the
//! netlist and roles. Out: each column's x, device columns at least two
//! apart so a channel lies between neighbours.
//!
//! Mated columns are the core: one of each pair on the left, its mate
//! mirrored on the right; a column the mates map to itself, a pair's tail,
//! or a column wired to both halves stands on the axis, the first by rank
//! where several share a row (the rest go free). The left half's
//! order is the one whose wired nets span least (rails, biases and nets
//! driven from outside aside: they are symbols or labels; a bridge between
//! two wired nets counts the gap between their columns), tried
//! exhaustively up to `exhaustive_max` columns, else by moving one column
//! at a time while that helps. Columns with no mate go right of the core
//! when they reach an output, else left of it, each side ordered the same
//! way. With no core (no mated column, none on an axis) every column is
//! ordered at once, first so that as few gates as can be stand left of the
//! device that drives them (a chain of stages stands in the order the
//! signal passes them, a mirror's reference left of its copies, and a loop
//! is cut once), then by span; and the row is turned so that the signal
//! enters on the left: the columns an input reaches left of those that
//! drive an output.
//!
//! Contents:
//! - `pub const Columns = struct { start: []const u32, devices: []const u32 }`
//! - `pub fn order(gpa: Allocator, nl: *const Netlist, roles: []const Role, cols: Columns, column_of: []const u32, mate: []const u32, partner: []const u32, rank: []const u32, row: []const u32) Allocator.Error![]i32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;

/// Column c holds `devices[start[c]..start[c + 1]]`, top to bottom.
pub const Columns = struct {
    start: []const u32,
    devices: []const u32,

    fn count(c: Columns) u32 {
        assert(c.start.len >= 1);
        return @intCast(c.start.len - 1);
    }
    fn of(c: Columns, k: usize) []const u32 {
        assert(k + 1 < c.start.len);
        assert(c.start[k] < c.start[k + 1]);
        return c.devices[c.start[k]..c.start[k + 1]];
    }
};

const none: u32 = std.math.maxInt(u32);

/// Halves of more columns are ordered greedily (6! = 720 orders at most).
const exhaustive_max = 6;

/// How far one column is moved in a longer list, and how many passes over
/// the list: the work is bounded by `move_rounds * 2 * move_reach` orders
/// tried per column.
const move_reach = 12;
const move_rounds = 16;

const Side = enum(u8) { left, axis, right, free };

const Ctx = struct {
    gpa: Allocator,
    nl: *const Netlist,
    roles: []const Role,
    cols: Columns,
    column_of: []const u32,
    /// Each device's differential or cross-coupled partner, or `none`.
    partner: []const u32,
    rank: []const u32,
    /// Nets whose span counts, as their devices' columns.
    wired: []const bool,
    /// Columns with an x so far: the axis, then each side as it is ordered.
    placed: []bool,
    /// Whether an order is first judged by the signal's way (`against`).
    flow: bool = false,
};

/// Each column's x. `column_of`, `mate`, `partner`, `rank` and `row` have
/// one entry per device (`none` for a device in no column, or with no mate
/// or partner). Asserts that every column holds a device.
pub fn order(gpa: Allocator, nl: *const Netlist, roles: []const Role, cols: Columns, column_of: []const u32, mate: []const u32, partner: []const u32, rank: []const u32, row: []const u32) Allocator.Error![]i32 {
    const n = cols.count();
    assert(column_of.len == nl.graph.edgeCount());
    assert(mate.len == column_of.len and row.len == column_of.len);
    const x = try gpa.alloc(i32, n);
    errdefer gpa.free(x);
    if (n == 0) return x;
    const wired = try wiredNets(gpa, nl, roles);
    defer gpa.free(wired);
    const placed = try gpa.alloc(bool, n);
    defer gpa.free(placed);
    @memset(placed, false);
    const ctx: Ctx = .{ .gpa = gpa, .nl = nl, .roles = roles, .cols = cols, .column_of = column_of, .partner = partner, .rank = rank, .wired = wired, .placed = placed };

    // Each column's mate column, and its side.
    const col_mate = try gpa.alloc(u32, n);
    defer gpa.free(col_mate);
    const side = try gpa.alloc(Side, n);
    defer gpa.free(side);
    for (0..n) |k| col_mate[k] = columnMate(ctx, mate, k);
    try assignSides(ctx, mate, col_mate, side);

    // The core: the left half's order, mirrored; the axis between.
    var left: std.ArrayList(u32) = .empty;
    defer left.deinit(gpa);
    var axis: std.ArrayList(u32) = .empty;
    defer axis.deinit(gpa);
    var free_left: std.ArrayList(u32) = .empty;
    defer free_left.deinit(gpa);
    var free_right: std.ArrayList(u32) = .empty;
    defer free_right.deinit(gpa);
    const outward = try outputSide(ctx, side);
    defer gpa.free(outward);
    for (side, 0..) |s, k| switch (s) {
        .left => try left.append(gpa, @intCast(k)),
        .axis => try axis.append(gpa, @intCast(k)),
        .right => {},
        .free => if (outward[k]) try free_right.append(gpa, @intCast(k)) else try free_left.append(gpa, @intCast(k)),
    };
    sortByRank(ctx, left.items);
    sortByRank(ctx, axis.items);
    // One x for the axis: a column spanning a row of one before it there
    // goes free instead.
    var kept: usize = 0;
    for (axis.items) |k| {
        const clash = for (axis.items[0..kept]) |j| {
            if (shareRow(cols, row, j, k)) break true;
        } else false;
        if (!clash) {
            axis.items[kept] = k;
            kept += 1;
        } else if (outward[k]) {
            try free_right.append(gpa, k);
        } else {
            try free_left.append(gpa, k);
        }
    }
    axis.shrinkRetainingCapacity(kept);
    sortByRank(ctx, free_left.items);
    sortByRank(ctx, free_right.items);

    @memset(x, 0);
    if (left.items.len == 0 and axis.items.len == 0) {
        // No core: one row of columns, in one order, read left to right.
        try free_left.appendSlice(gpa, free_right.items);
        sortByRank(ctx, free_left.items);
        const place = struct {
            fn f(xs: []i32, _: []const u32, list: []const u32, first: i32) void {
                for (list, 0..) |k, i| xs[k] = first + 2 * @as(i32, @intCast(i));
            }
        }.f;
        var by_flow = ctx;
        by_flow.flow = true;
        try best(by_flow, free_left.items, place, x, col_mate, 0);
        if (!flowsRight(ctx, x)) {
            const last = 2 * @as(i32, @intCast(n - 1));
            for (x) |*v| v.* = last - v.*;
        }
        return x;
    }
    for (axis.items) |k| placed[k] = true;
    // Axis columns share x = 0; the halves start one channel out, or two
    // when an axis column stands between them.
    const inner: i32 = if (axis.items.len > 0) 2 else 1;
    try best(ctx, left.items, struct {
        fn place(xs: []i32, cm: []const u32, list: []const u32, first: i32) void {
            for (list, 0..) |k, i| {
                const at = -(first + 2 * @as(i32, @intCast(i)));
                xs[k] = at;
                xs[cm[k]] = -at;
            }
        }
    }.place, x, col_mate, inner);
    var lo: i32 = -inner + 2;
    var hi: i32 = inner - 2;
    for (left.items) |k| {
        lo = @min(lo, x[k]);
        hi = @max(hi, x[col_mate[k]]);
    }
    if (left.items.len == 0 and axis.items.len == 0) {
        lo = 0;
        hi = -2;
    }
    // Free columns outboard, each side in its order left to right: right
    // ones from the core's right edge, left ones ending at its left edge.
    try best(ctx, free_right.items, struct {
        fn place(xs: []i32, _: []const u32, list: []const u32, first: i32) void {
            for (list, 0..) |k, i| xs[k] = first + 2 * @as(i32, @intCast(i));
        }
    }.place, x, col_mate, hi + 2);
    try best(ctx, free_left.items, struct {
        fn place(xs: []i32, _: []const u32, list: []const u32, last: i32) void {
            const n_list: i32 = @intCast(list.len);
            for (list, 0..) |k, i| xs[k] = last - 2 * (n_list - 1 - @as(i32, @intCast(i)));
        }
    }.place, x, col_mate, lo - 2);
    for (side, 0..) |s, k| if (s == .right) assert(x[k] == -x[col_mate[k]]);
    return x;
}

// ---- private ----

/// Rails are symbols, and a net driven from outside (an input, a bias) is a
/// terminal or a label at each of its pins: neither is a wire to shorten.
fn wiredNets(gpa: Allocator, nl: *const Netlist, roles: []const Role) ![]bool {
    assert(roles.len == nl.graph.vertexCount());
    const wired = try gpa.alloc(bool, nl.graph.vertexCount());
    for (roles, wired) |r, *w| w.* = r == .internal or r == .output;
    return wired;
}

/// The column `k`'s devices' mates stand in, when they all stand in one
/// column other than `k`; else `none`.
fn columnMate(ctx: Ctx, mate: []const u32, k: usize) u32 {
    assert(k < ctx.cols.count());
    assert(mate.len == ctx.column_of.len);
    var found: u32 = none;
    for (ctx.cols.of(k)) |d| {
        const m = mate[d];
        if (m == none or m == d) continue;
        const c = ctx.column_of[m];
        if (c == none or c == k) return none;
        if (found != none and found != c) return none;
        found = c;
    }
    return found;
}

/// Mated columns: the one nearer the reference device on the left, its mate
/// on the right. Unmated columns whose devices are their own mates, or
/// wired to both halves, on the axis. Everything else is free.
fn assignSides(ctx: Ctx, mate: []const u32, col_mate: []u32, side: []Side) !void {
    const n = ctx.cols.count();
    @memset(side, .free);
    // Mates must be mutual.
    for (0..n) |k| {
        const m = col_mate[k];
        if (m != none and col_mate[m] != k) col_mate[k] = none;
    }
    // The reference: the lowest-ranked device with a mate elsewhere, on the
    // left; distances from it decide every other pair's sides.
    var ref: u32 = none;
    for (mate, 0..) |m, d| {
        if (m == none or m == d or ctx.column_of[d] == none or col_mate[ctx.column_of[d]] == none) continue;
        if (ref == none or ctx.rank[d] < ctx.rank[ref]) ref = @intCast(d);
    }
    if (ref != none) {
        const near = try distances(ctx, mate, ref);
        defer ctx.gpa.free(near);
        const far = try distances(ctx, mate, mate[ref]);
        defer ctx.gpa.free(far);
        for (0..n) |k| {
            const m = col_mate[k];
            if (m == none or side[k] != .free) continue;
            const dk = closest(ctx, near, k);
            const dm = closest(ctx, near, m);
            const left = if (dk != dm) dk < dm else closest(ctx, far, k) > closest(ctx, far, m);
            side[k] = if (left) .left else .right;
            side[m] = if (left) .right else .left;
        }
    }
    for (0..n) |k| {
        if (side[k] != .free) continue;
        var own = false;
        var others = false;
        for (ctx.cols.of(k)) |d| {
            if (mate[d] == d) own = true;
            if (mate[d] != none and mate[d] != d) others = true;
        }
        if ((own and !others) or (ref != none and wiredToBoth(ctx, side, k))) side[k] = .axis;
    }
    for (side, 0..) |s, k| if (s == .left) assert(side[col_mate[k]] == .right);
}

/// Hops from `from` along current paths (channel pins) and between the two
/// of a differential or cross-coupled pair, not through rails or what the
/// mates map to itself (the axis), so each half stays on its side: gate
/// wires (cross-couplings, inputs) reach both halves alike.
fn distances(ctx: Ctx, mate: []const u32, from: u32) ![]u32 {
    const c = &ctx.nl.graph;
    const devices = c.edgeCount();
    assert(from < devices);
    const dist = try ctx.gpa.alloc(u32, devices + c.vertexCount());
    @memset(dist, none);
    var queue: std.ArrayList(u32) = .empty;
    defer queue.deinit(ctx.gpa);
    dist[from] = 0;
    try queue.append(ctx.gpa, from);
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        assert(head < dist.len);
        const v = queue.items[head];
        if (v < devices) {
            for (c.members(EdgeId.from(v)), 0..) |net, i| {
                const w = devices + net.index();
                if (!isChannelPin(ctx, v, i) or dist[w] != none or ctx.roles[net.index()] == .supply or ctx.roles[net.index()] == .sink) continue;
                dist[w] = dist[v] + 1;
                try queue.append(ctx.gpa, w);
            }
            const p = ctx.partner[v];
            if (p != none and dist[p] == none and mate[p] != p) {
                dist[p] = dist[v] + 1;
                try queue.append(ctx.gpa, p);
            }
        } else {
            for (c.incident(VertexId.from(v - devices))) |e| {
                const d = e.index();
                if (dist[d] != none or mate[d] == d) continue;
                dist[d] = dist[v] + 1;
                try queue.append(ctx.gpa, d);
            }
        }
    }
    return dist;
}

/// A pin current flows through: a transistor's drain and source (collector
/// and emitter), a switch's or controlled source's first two, any pin of
/// anything else. A switch's control pins tie every switch on a clock.
fn isChannelPin(ctx: Ctx, d: u32, pin: usize) bool {
    assert(pin < ctx.nl.graph.members(EdgeId.from(d)).len);
    return switch (ctx.nl.graph.edges.items(.kind)[d]) {
        .mosfet, .bjt, .jfet, .mesfet => pin == 0 or pin == 2,
        .vswitch, .cswitch, .vcvs, .vccs => pin < 2,
        else => true,
    };
}

fn closest(ctx: Ctx, dist: []const u32, k: usize) u32 {
    var m: u32 = none;
    for (ctx.cols.of(k)) |d| m = @min(m, dist[d]);
    return m;
}

/// A free column on a wired net of a left column and one of a right column:
/// a start-up device between two mirrored halves.
fn wiredToBoth(ctx: Ctx, side: []const Side, k: usize) bool {
    assert(side.len == ctx.cols.count());
    var l = false;
    var r = false;
    for (ctx.cols.of(k)) |d| for (ctx.nl.graph.members(EdgeId.from(d))) |net| {
        if (!ctx.wired[net.index()]) continue;
        for (ctx.nl.graph.incident(net)) |e| {
            const c = ctx.column_of[e.index()];
            if (c == none or c == k) continue;
            l = l or side[c] == .left;
            r = r or side[c] == .right;
        }
    };
    return l and r;
}

/// Whether the signal passes the columns left to right: those with a pin
/// on an input stand, on average, no further right than those that drive
/// an output (a channel pin on it). True with no input or no output.
fn flowsRight(ctx: Ctx, x: []const i32) bool {
    assert(x.len == ctx.cols.count());
    var in: [2]i64 = .{ 0, 0 };
    var out: [2]i64 = .{ 0, 0 };
    for (0..ctx.cols.count()) |k| {
        var reads = false;
        var drives = false;
        for (ctx.cols.of(k)) |d| for (ctx.nl.graph.members(EdgeId.from(d)), 0..) |net, pin| {
            reads = reads or ctx.roles[net.index()] == .input;
            drives = drives or (ctx.roles[net.index()] == .output and isChannelPin(ctx, d, pin));
        };
        if (reads) in = .{ in[0] + x[k], in[1] + 1 };
        if (drives) out = .{ out[0] + x[k], out[1] + 1 };
    }
    if (in[1] == 0 or out[1] == 0) return true;
    return in[0] * out[1] <= out[0] * in[1];
}

/// Per column: whether, free, it goes right of the core. One on an output
/// does, and so does one a wired net joins to such a free column: a
/// mirror's two stand on one side.
fn outputSide(ctx: Ctx, side: []const Side) ![]bool {
    const c = &ctx.nl.graph;
    const n = ctx.cols.count();
    assert(side.len == n);
    const right = try ctx.gpa.alloc(bool, n);
    for (right, 0..) |*r, k| r.* = touchesOutput(ctx, k);
    var changed = true;
    var rounds: usize = 0;
    while (changed) : (rounds += 1) {
        assert(rounds <= n);
        changed = false;
        for (ctx.wired, 0..) |w, net| {
            if (!w) continue;
            const on = c.incident(VertexId.from(@intCast(net)));
            const any = for (on) |e| {
                const k = ctx.column_of[e.index()];
                if (k != none and side[k] == .free and right[k]) break true;
            } else false;
            if (!any) continue;
            for (on) |e| {
                const k = ctx.column_of[e.index()];
                if (k == none or side[k] != .free or right[k]) continue;
                right[k] = true;
                changed = true;
            }
        }
    }
    return right;
}

fn touchesOutput(ctx: Ctx, k: usize) bool {
    assert(k < ctx.cols.count());
    for (ctx.cols.of(k)) |d| for (ctx.nl.graph.members(EdgeId.from(d))) |net| {
        if (ctx.roles[net.index()] == .output) return true;
    };
    return false;
}

/// By the rank of each column's top device.
/// Columns `j` and `k` span a common row: one x would stack their devices
/// or run their wires together.
fn shareRow(cols: Columns, row: []const u32, j: u32, k: u32) bool {
    assert(j != k);
    const a = rowSpan(cols, row, j);
    const b = rowSpan(cols, row, k);
    return a[0] <= b[1] and b[0] <= a[1];
}

fn rowSpan(cols: Columns, row: []const u32, k: u32) [2]u32 {
    var out: [2]u32 = .{ std.math.maxInt(u32), 0 };
    for (cols.of(k)) |d| out = .{ @min(out[0], row[d]), @max(out[1], row[d]) };
    assert(out[0] <= out[1]);
    return out;
}

fn sortByRank(ctx: Ctx, list: []u32) void {
    std.mem.sort(u32, list, ctx, struct {
        fn lt(c: Ctx, a: u32, b: u32) bool {
            return c.rank[c.cols.of(a)[0]] < c.rank[c.cols.of(b)[0]];
        }
    }.lt);
}

/// Tries the orders of `list` (all of them up to `exhaustive_max` columns,
/// else one column moved at a time, up to `move_reach` places, while that
/// helps), placing each with `place`, and keeps the one whose wired nets
/// span least. Ties keep the earlier order, so by rank.
fn best(ctx: Ctx, list: []u32, comptime place: fn ([]i32, []const u32, []const u32, i32) void, x: []i32, col_mate: []const u32, first: i32) !void {
    if (list.len == 0) return;
    for (list) |k| {
        ctx.placed[k] = true;
        if (col_mate[k] != none) ctx.placed[col_mate[k]] = true;
    }
    const work = try ctx.gpa.dupe(u32, list);
    defer ctx.gpa.free(work);
    // The order by rank, which an equal order is held against.
    const ranked = try ctx.gpa.dupe(u32, list);
    defer ctx.gpa.free(ranked);
    place(x, col_mate, list, first);
    var best_cost = try span(ctx, x);
    if (list.len <= exhaustive_max) {
        // Heap's algorithm over `work`, iteratively.
        var c: [exhaustive_max]usize = @splat(0);
        var i: usize = 1;
        var steps: usize = 0;
        while (i < work.len) {
            assert(steps < 1000);
            if (c[i] < i) {
                const j = if (i % 2 == 0) 0 else c[i];
                std.mem.swap(u32, &work[j], &work[i]);
                place(x, col_mate, work, first);
                const cost = try span(ctx, x);
                if (cost < best_cost or (ctx.flow and cost == best_cost and earlier(ranked, work, list))) {
                    best_cost = cost;
                    @memcpy(list, work);
                }
                c[i] += 1;
                i = 1;
                steps += 1;
            } else {
                c[i] = 0;
                i += 1;
            }
        }
    } else {
        var improved = true;
        var rounds: usize = 0;
        while (improved and rounds < move_rounds) : (rounds += 1) {
            improved = false;
            for (0..list.len) |i| {
                const lo = i -| move_reach;
                const hi = @min(list.len - 1, i + move_reach);
                for (lo..hi + 1) |j| {
                    if (i == j) continue;
                    // `list[i]` moved to place `j`, the columns between
                    // closing up.
                    @memcpy(work, list);
                    if (i < j) {
                        std.mem.copyForwards(u32, work[i..j], list[i + 1 .. j + 1]);
                    } else {
                        std.mem.copyForwards(u32, work[j + 1 .. i + 1], list[j..i]);
                    }
                    work[j] = list[i];
                    place(x, col_mate, work, first);
                    const cost = try span(ctx, x);
                    if (cost >= best_cost) continue;
                    best_cost = cost;
                    improved = true;
                    @memcpy(list, work);
                }
            }
        }
    }
    place(x, col_mate, list, first);
}

/// Whether order `a` comes before order `b` of the same columns, read as
/// words over their places in `ranked`.
fn earlier(ranked: []const u32, a: []const u32, b: []const u32) bool {
    assert(a.len == b.len and a.len == ranked.len);
    for (a, b) |ka, kb| {
        if (ka == kb) continue;
        return std.mem.indexOfScalar(u32, ranked, ka).? < std.mem.indexOfScalar(u32, ranked, kb).?;
    }
    return false;
}

/// How many pins stand left of every device that drives their net (a
/// transistor's or controlled source's channel pin on it), over the wired
/// nets and the columns `placed` so far: a gate, a base or a controlled
/// source's input before its driver, a load before its stage. The signal
/// going right to left.
fn against(ctx: Ctx, x: []const i32) i64 {
    const c = &ctx.nl.graph;
    assert(x.len == ctx.cols.count());
    var count: i64 = 0;
    for (0..c.vertexCount()) |n| {
        if (!ctx.wired[n]) continue;
        var first: i32 = std.math.maxInt(i32);
        for ([_]bool{ true, false }) |drivers| for (c.incident(VertexId.from(n))) |e| {
            const d = e.index();
            const k = ctx.column_of[d];
            if (k == none or !ctx.placed[k]) continue;
            const is_controlled = controlled(c.edges.items(.kind)[d]);
            for (c.members(e), 0..) |net, pin| {
                if (net.index() != n or (is_controlled and isChannelPin(ctx, d, pin)) != drivers) continue;
                if (drivers) first = @min(first, x[k]) else count += @intFromBool(x[k] < first and first != std.math.maxInt(i32));
            }
        };
    }
    assert(count >= 0);
    return count;
}

/// A device with a control pin: what it drives follows what it reads.
fn controlled(kind: netlist.DeviceKind) bool {
    return switch (kind) {
        .mosfet, .bjt, .jfet, .mesfet, .vswitch, .cswitch, .vcvs, .vccs => true,
        else => false,
    };
}

/// The total width of the wired nets, each from its leftmost column to its
/// rightmost, and of the gaps the bridges cross, over the columns `placed`
/// so far; with `ctx.flow`, each pin
/// `against` the signal's way first, counted as more than any span.
fn span(ctx: Ctx, x: []const i32) !i64 {
    const c = &ctx.nl.graph;
    assert(x.len == ctx.cols.count());
    var total: i64 = if (ctx.flow) against(ctx, x) << 32 else 0;
    for (0..c.vertexCount()) |n| {
        if (!ctx.wired[n]) continue;
        var lo: i32 = std.math.maxInt(i32);
        var hi: i32 = std.math.minInt(i32);
        for (c.incident(VertexId.from(n))) |e| {
            const k = ctx.column_of[e.index()];
            if (k == none or !ctx.placed[k]) continue;
            lo = @min(lo, x[k]);
            hi = @max(hi, x[k]);
        }
        if (lo <= hi) total += hi - lo;
    }
    // A bridge joins two nets: the gap between their columns is its wire.
    for (0..c.edgeCount()) |d| {
        const pins = c.members(EdgeId.from(d));
        if (ctx.column_of[d] != none or pins.len != 2) continue;
        if (!ctx.wired[pins[0].index()] or !ctx.wired[pins[1].index()]) continue;
        const a = extent(ctx, x, pins[0]) orelse continue;
        const b = extent(ctx, x, pins[1]) orelse continue;
        total += @max(0, a[0] - b[1], b[0] - a[1]);
    }
    return total;
}

/// The leftmost and rightmost column placed so far with a device on `n`.
fn extent(ctx: Ctx, x: []const i32, n: VertexId) ?[2]i32 {
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    for (ctx.nl.graph.incident(n)) |e| {
        const k = ctx.column_of[e.index()];
        if (k == none or !ctx.placed[k]) continue;
        lo = @min(lo, x[k]);
        hi = @max(hi, x[k]);
    }
    return if (lo <= hi) .{ lo, hi } else null;
}
