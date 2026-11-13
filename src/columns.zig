//! Column order (issue #8, stage 3): where each column of devices stands.
//! In: the columns (devices top to bottom), each device's mate, the
//! netlist and roles. Out: each column's x, device columns at least two
//! apart so a channel lies between neighbours.
//!
//! Human Rules:
//! - columns.1 (unmeasured) Rails, biases and inputs pull no columns
//!   together: they are drawn as symbols or labels, so only internal nets
//!   and outputs count as wired. `wiredNets`
//! - columns.2 (unmeasured) Mated columns are the core: one of each pair
//!   on the left, its mate its mirror image on the right. `order`
//! - columns.3 (choice) Of two mated columns, the one nearer, along current
//!   paths, the lowest-ranked mated device stands in one half and its mate
//!   in the other: one reference keeps each half whole. Which half stands
//!   left is the row's to say (columns.13). `assignSides`
//! - columns.4 (unmeasured) A column whose devices the symmetry maps to
//!   themselves stands on the axis, as does a column wired to both halves
//!   (a start-up device between them). `assignSides`
//! - columns.5 (habit) Of two columns that would share the axis on one
//!   row, a pair's tail keeps it. People: 91.9% of 347 such devices in
//!   5,263 hand-drawn schematics stand between the pair's two. `order`
//! - columns.6 (invariant) At most one column stands on the axis at any
//!   row; the others, by rank, go free. `order`
//! - columns.7, .8, .9, .11: retired; columns.13 is the rule they were
//!   cases of (a free column on the side of the half it shares more nets
//!   with: people 1,172 of 1,716; one on an output right, 577 of 760, any
//!   other left, 1,403 of 2,618; a circuit with no core in one row).
//! - columns.10 (invariant) No free column stands between the core's mated
//!   columns: the core is one item of the row. People: 6,003 of 6,781 free
//!   columns stand clear of the core (5,198 beside it, 805 over or under
//!   it) in 5,263 hand-drawn schematics. `lay`
//! - columns.12 (choice) Each half of the core, then the row, tries every
//!   order up to `exhaustive_max` (6) columns, else moves one column at a
//!   time up to `move_reach` (12) places for `move_rounds` (16) passes; of
//!   equal orders the one nearer rank order stands: a bound on the work.
//!   `best`
//! - columns.13 (order: signal) The columns stand in one row, the core as
//!   one of them, in the order span.2 then span.1 give: the fewest pins
//!   left of what drives them, then the narrowest wired nets. A second
//!   stage stands right of the pair that drives it, a bias generator left
//!   of what it biases, and of the core and its mirror image the one with
//!   fewer such pins stands. People: 1,036 of the 1,200 hand drawings with
//!   a core that differ from their mirror image in those pins face the way
//!   with fewer; a free column the core drives stands right of it in 599
//!   of 843, one that drives the core left in 303 of 418; two free columns
//!   a wired net joins stand on one side in 5,238 of 6,102. `order`
//!
//! Contents:
//! - `pub const Columns = struct { start: []const u32, devices: []const u32 }`, `Columns.count(c: Columns) u32`, `Columns.of(c: Columns, k: usize) []const u32`
//! - `pub const Ctx = struct`
//! - `pub fn order(gpa: Allocator, nl: *const Netlist, roles: []const Role, cols: Columns, column_of: []const u32, mate: []const u32, partner: []const u32, rank: []const u32, row: []const u32) Allocator.Error![]i32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const order_cost = @import("span.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;

/// Column c holds `devices[start[c]..start[c + 1]]`, top to bottom.
pub const Columns = struct {
    start: []const u32,
    devices: []const u32,

    /// How many columns.
    pub fn count(c: Columns) u32 {
        assert(c.start.len >= 1);
        return @intCast(c.start.len - 1);
    }
    /// Column `k`'s devices, top to bottom.
    pub fn of(c: Columns, k: usize) []const u32 {
        assert(k + 1 < c.start.len);
        assert(c.start[k] < c.start[k + 1]);
        return c.devices[c.start[k]..c.start[k + 1]];
    }
};

/// What an order of the columns is judged against (`span.zig` reads it).
pub const Ctx = struct {
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
    /// Columns with an x so far: the core's, then the whole row's.
    placed: []bool,
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

/// The mirrored core as one item of the row: its columns `in`, each at
/// `about` from the axis (so within `reach` of it), standing where the
/// column `anchor` is listed; `sign` -1 lays its mirror image. `anchor` is
/// `none` when no column is in the core.
const Core = struct {
    about: []const i32,
    in: []const bool,
    reach: i32 = 0,
    anchor: u32 = none,
    sign: i32 = 1,
};

/// How an order of columns is laid: leftward from minus the given x, each
/// column's mate its mirror image about x = 0 (a half of the core); or left
/// to right from 0, a channel between neighbours, the core among them.
const Lay = union(enum) { mirrored: i32, row: Core };

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
    // The row: every column with no place in the core, and the core as one.
    var row_list: std.ArrayList(u32) = .empty;
    defer row_list.deinit(gpa);
    for (side, 0..) |s, k| switch (s) {
        .left => try left.append(gpa, @intCast(k)),
        .axis => try axis.append(gpa, @intCast(k)),
        .right => {},
        .free => try row_list.append(gpa, @intCast(k)),
    };
    sortByRank(ctx, left.items);
    sortByRank(ctx, axis.items);
    // A pair's tail first: of two columns that would share the axis on one
    // row, the one between the pair's two keeps it (people: 91.9% of 347
    // such devices in 5,263 hand-drawn schematics stand between the two).
    var tails: usize = 0;
    for (0..axis.items.len) |i| {
        if (!isTail(ctx, mate, axis.items[i])) continue;
        const k = axis.items[i];
        std.mem.copyBackwards(u32, axis.items[tails + 1 .. i + 1], axis.items[tails..i]);
        axis.items[tails] = k;
        tails += 1;
    }
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
        } else try row_list.append(gpa, k);
    }
    axis.shrinkRetainingCapacity(kept);

    @memset(x, 0);
    for (axis.items) |k| placed[k] = true;
    // Axis columns share x = 0; the halves start one channel out, or two
    // when an axis column stands between them.
    _ = try best(ctx, left.items, .{ .mirrored = if (axis.items.len > 0) 2 else 1 }, x, col_mate);
    // The core, as laid about x = 0, is one item of the row: it stands in
    // it where its lowest-ranked column would.
    const about = try gpa.dupe(i32, x);
    defer gpa.free(about);
    const in_core = try gpa.dupe(bool, placed);
    defer gpa.free(in_core);
    var core: Core = .{ .about = about, .in = in_core };
    for (in_core, 0..) |in, k| {
        if (!in) continue;
        core.reach = @max(core.reach, @as(i32, @intCast(@abs(about[k]))));
        if (core.anchor == none or rank[cols.of(k)[0]] < rank[cols.of(core.anchor)[0]]) core.anchor = @intCast(k);
    }
    if (core.anchor != none) try row_list.append(gpa, core.anchor);
    sortByRank(ctx, row_list.items);
    // One row, in the order that costs least (`span.zig`): the fewest pins
    // left of what drives them, then the narrowest wired nets. The core's
    // mirror image is as symmetric as the core, so it is tried both ways
    // round (people: 1,036 of the 1,200 drawings with a core that differ
    // from their mirror image in pins left of their drivers face the way
    // with fewer, in 5,263 hand-drawn schematics).
    const turned = try gpa.dupe(u32, row_list.items);
    defer gpa.free(turned);
    const cost = try best(ctx, row_list.items, .{ .row = core }, x, col_mate);
    if (core.anchor != none) {
        core.sign = -1;
        if (try best(ctx, turned, .{ .row = core }, x, col_mate) >= cost) {
            core.sign = 1;
            lay(.{ .row = core }, x, col_mate, row_list.items);
        }
        // The axis back at x = 0.
        const axis_x = x[core.anchor] - core.sign * about[core.anchor];
        for (x) |*v| v.* -= axis_x;
    }
    // Read left to right: the whole row turned end for end otherwise.
    if (!order_cost.flowsRight(ctx, x)) for (x) |*v| {
        v.* = -v.*;
    };
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

/// Mated columns: the one nearer the reference device in the half called
/// left, its mate in the right one (the row may stand the core either way
/// round). Unmated columns whose devices are their own mates, or wired to
/// both halves, on the axis. Everything else is free.
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
                if (!order_cost.isChannelPin(ctx, v, i) or dist[w] != none or ctx.roles[net.index()].isRail()) continue;
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

/// Whether column `k` holds a pair's tail: a device with a channel end on a
/// net two mated devices end on too.
fn isTail(ctx: Ctx, mate: []const u32, k: u32) bool {
    const c = &ctx.nl.graph;
    for (ctx.cols.of(k)) |d| for (c.members(EdgeId.from(d)), 0..) |net, pin| {
        if (!order_cost.isChannelPin(ctx, d, pin) or !ctx.wired[net.index()]) continue;
        for (c.incident(net)) |e| {
            const a = e.index();
            const m = mate[a];
            if (a == d or m == none or m == a or m == d) continue;
            // Both of the pair end on the net.
            const ends = for ([_]u32{ a, m }) |v| {
                const on = for (c.members(EdgeId.from(v)), 0..) |n2, p2| {
                    if (n2.index() == net.index() and order_cost.isChannelPin(ctx, v, p2)) break true;
                } else false;
                if (!on) break false;
            } else true;
            if (ends) return true;
        }
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

/// Gives `list`'s columns their x in `xs`, as `how` lays an order.
fn lay(how: Lay, xs: []i32, cm: []const u32, list: []const u32) void {
    switch (how) {
        .mirrored => |first| for (list, 0..) |k, i| {
            const at = -(first + 2 * @as(i32, @intCast(i)));
            xs[k] = at;
            xs[cm[k]] = -at;
        },
        .row => |core| {
            var at: i32 = 0;
            for (list) |k| {
                if (k != core.anchor) {
                    xs[k] = at;
                    at += 2;
                    continue;
                }
                for (core.about, core.in, 0..) |about, in, c| {
                    if (in) xs[c] = at + core.reach + core.sign * about;
                }
                at += 2 * core.reach + 2;
            }
        },
    }
}

/// Tries the orders of `list` (all of them up to `exhaustive_max` columns,
/// else one column moved at a time, up to `move_reach` places, while that
/// helps), laying each as `how` says, keeps the one that costs least
/// (`span.zig`) and returns its cost. Of equal orders the one nearer rank
/// order stands.
fn best(ctx: Ctx, list: []u32, how: Lay, x: []i32, col_mate: []const u32) !i64 {
    if (list.len == 0) return 0;
    for (list) |k| {
        ctx.placed[k] = true;
        if (col_mate[k] != none) ctx.placed[col_mate[k]] = true;
    }
    const work = try ctx.gpa.dupe(u32, list);
    defer ctx.gpa.free(work);
    // The order by rank, which an equal order is held against.
    const ranked = try ctx.gpa.dupe(u32, list);
    defer ctx.gpa.free(ranked);
    lay(how, x, col_mate, list);
    var best_cost = try order_cost.span(ctx, x);
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
                lay(how, x, col_mate, work);
                const cost = try order_cost.span(ctx, x);
                if (cost < best_cost or (cost == best_cost and earlier(ranked, work, list))) {
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
                    lay(how, x, col_mate, work);
                    const cost = try order_cost.span(ctx, x);
                    if (cost >= best_cost) continue;
                    best_cost = cost;
                    improved = true;
                    @memcpy(list, work);
                }
            }
        }
    }
    lay(how, x, col_mate, list);
    return best_cost;
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
