//! Stage 3 of issue #8: where each drawn device stands, as a cell of a
//! lattice. In: the netlist, its roles and its structure. Out, per device:
//! drawn or not; its form (vertical: current enters at its top and leaves
//! at its bottom; horizontal: a bridge between columns); which side its
//! gate faces; its x and y. Device columns stand two apart and device rows
//! two apart, so a channel lies between any two: taps, bridges and wires go
//! there.
//!
//! - A device is vertical when it is a transistor, sits on a rail, or is in
//!   series (alone with one other channel element on each of its nets);
//!   a capacitor only on a rail. Anything else bridges.
//! - Columns are the chains current flows down: one device's lower end and
//!   the next one's upper end on a net. Where several meet, one link is
//!   kept (a transistor, a chain that reaches a rail, the same type, then
//!   rank), mirrored by the symmetry; nothing links across a pair's tail, so
//!   a tail stands in a column of its own.
//! - Mates: the symmetry's, else each differential, cross-coupled or
//!   two-member mirror pair's, carried up and down their columns.
//! - Rows by longest path down the chains, mates and blocks held level where
//!   that closes no cycle; transistors on ground drop to their type's lowest
//!   such row.
//! - Columns ordered by `columns.zig`; a bridge in the channel among the
//!   columns of its nets, at its first net's tap row, or mirroring its mate.
//! - Gates: a differential pair's face out, a mirror's or a cross-coupled
//!   pair's face each other, any other transistor's faces the rest of its
//!   gate net.
//!
//! Contents:
//! - `pub const Form = enum(u8) { vertical, horizontal }`
//! - `pub const Skeleton = struct`
//! - `pub fn place(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure) Allocator.Error!Skeleton`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const symmetry = @import("symmetry.zig");
const columns = @import("columns.zig");
const levels = @import("levels.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Structure = structure.Structure;
const none = structure.none;

pub const Form = enum(u8) { vertical, horizontal };

/// One entry per device, in card order. A device that is not drawn (a
/// driver, a card with no pins) has `drawn` false and the rest unspecified.
pub const Skeleton = struct {
    drawn: []const bool,
    form: []const Form,
    /// A vertical device's upper and lower ends' nets; `none` otherwise.
    upper: []const u32,
    lower: []const u32,
    /// Its gate (side pins) faces right.
    gate_right: []const bool,
    /// Its cell: even for vertical devices, the smallest of each axis 0.
    x: []const i32,
    y: []const i32,
};

/// Each device's neighbours in its column, or `none`.
const Chain = struct {
    above: []u32,
    below: []u32,
};

/// Asserts that `roles` has one entry per net and `st` comes from `nl`.
pub fn place(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure) Allocator.Error!Skeleton {
    const c = &nl.graph;
    const n = c.edgeCount();
    assert(roles.len == c.vertexCount());
    assert(st.device_rank.len == n);
    const drawn = try arena.alloc(bool, n);
    const form = try arena.alloc(Form, n);
    const upper = try arena.alloc(u32, n);
    const lower = try arena.alloc(u32, n);
    const gate_right = try arena.alloc(bool, n);
    const x = try arena.alloc(i32, n);
    const y = try arena.alloc(i32, n);
    @memset(x, 0);
    @memset(y, 0);
    @memset(gate_right, false);

    try classify(gpa, nl, roles, drawn, form);
    try ends(gpa, nl, roles, drawn, form, upper, lower);
    const net_rank = try structure.rankByName(gpa, gpa, c.vertices.items(.name));
    defer gpa.free(net_rank);
    var chain: Chain = .{ .above = try gpa.alloc(u32, n), .below = try gpa.alloc(u32, n) };
    defer gpa.free(chain.above);
    defer gpa.free(chain.below);
    try link(gpa, nl, roles, st, net_rank, drawn, form, upper, lower, &chain);

    // Columns: chains from their top devices, in rank order.
    const column_of = try gpa.alloc(u32, n);
    defer gpa.free(column_of);
    @memset(column_of, none);
    var start: std.ArrayList(u32) = .empty;
    defer start.deinit(gpa);
    var members: std.ArrayList(u32) = .empty;
    defer members.deinit(gpa);
    try start.append(gpa, 0);
    const devices_by_rank = try byRank(gpa, st.device_rank);
    defer gpa.free(devices_by_rank);
    for (devices_by_rank) |d| {
        if (!drawn[d] or form[d] != .vertical or chain.above[d] != none) continue;
        var at = d;
        while (at != none) : (at = chain.below[at]) {
            assert(members.items.len < n);
            column_of[at] = @intCast(start.items.len - 1);
            try members.append(gpa, at);
        }
        try start.append(gpa, @intCast(members.items.len));
    }

    const mate = try mates(gpa, nl, st, drawn, form, column_of, chain);
    defer gpa.free(mate);
    const rank = try levels.rows(gpa, nl, roles, st, mate, drawn, form, upper, lower);
    defer gpa.free(rank);
    const cols: columns.Columns = .{ .start = start.items, .devices = members.items };
    const partners = try gpa.alloc(u32, n);
    defer gpa.free(partners);
    for (partners, 0..) |*p, d| p.* = blockPartner(st, @intCast(d));
    const col_x = try columns.order(gpa, nl, roles, cols, column_of, mate, partners, st.device_rank);
    defer gpa.free(col_x);
    for (0..n) |d| {
        if (!drawn[d] or form[d] != .vertical) continue;
        x[d] = col_x[column_of[d]];
        y[d] = 2 * @as(i32, @intCast(rank[d]));
    }
    try bridges(gpa, nl, roles, st, drawn, form, upper, lower, rank, x, y);
    gates(nl, roles, st, drawn, form, x, gate_right);
    normalize(drawn, x, y);
    try expectDistinctCells(gpa, drawn, x, y);
    return .{ .drawn = drawn, .form = form, .upper = upper, .lower = lower, .gate_right = gate_right, .x = x, .y = y };
}

// ---- private ----

fn isTransistor(kind: DeviceKind) bool {
    return switch (kind) {
        .mosfet, .bjt, .jfet, .mesfet => true,
        else => false,
    };
}

/// A two-pin device the current passes through: its first two pins.
fn isTwoPin(kind: DeviceKind) bool {
    return switch (kind) {
        .resistor, .capacitor, .inductor, .vsource, .isource, .diode, .vswitch, .cswitch => true,
        else => false,
    };
}

fn isRail(r: Role) bool {
    return r == .supply or r == .sink;
}

/// Drawn: not a driver and with pins. Vertical: a transistor, a two-pin
/// device on a rail, or one in series (each of its nets holds one other
/// channel element); capacitors only on a rail.
fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []bool, form: []Form) !void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    assert(drawn.len == c.edgeCount());
    for (drawn, 0..) |*dr, d| {
        dr.* = c.members(EdgeId.from(d)).len > 0 and !sch.isDriver(c, roles, @intCast(d));
    }
    // Channel elements on each net: transistor channel ends, two-pin pins.
    const count = try gpa.alloc(u32, c.vertexCount());
    defer gpa.free(count);
    @memset(count, 0);
    for (0..c.edgeCount()) |d| {
        if (!drawn[d]) continue;
        const pins = c.members(EdgeId.from(d));
        if (isTransistor(kinds[d]) and pins.len >= 3) {
            count[pins[0].index()] += 1;
            count[pins[2].index()] += 1;
        } else if (isTwoPin(kinds[d]) and kinds[d] != .capacitor and pins.len >= 2) {
            count[pins[0].index()] += 1;
            count[pins[1].index()] += 1;
        }
    }
    for (form, 0..) |*f, d| {
        const pins = c.members(EdgeId.from(d));
        f.* = .horizontal;
        if (!drawn[d]) continue;
        if (isTransistor(kinds[d]) and pins.len >= 3) {
            f.* = .vertical;
        } else if (isTwoPin(kinds[d]) and pins.len >= 2) {
            const a = pins[0].index();
            const b = pins[1].index();
            const on_rail = isRail(roles[a]) or isRail(roles[b]);
            const series = kinds[d] != .capacitor and count[a] == 2 and count[b] == 2;
            if (on_rail or series) f.* = .vertical;
        }
    }
}

/// A transistor's ends from its type (an n-type's drain is its upper end);
/// a two-pin device's from the rails, else the pin nearer the supply
/// through channel elements.
fn ends(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32) !void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    @memset(upper, none);
    @memset(lower, none);
    const dist = try supplyDistance(gpa, nl, roles, drawn);
    defer gpa.free(dist);
    for (0..c.edgeCount()) |d| {
        if (!drawn[d] or form[d] != .vertical) continue;
        const e = EdgeId.from(d);
        const pins = c.members(e);
        if (isTransistor(kinds[d])) {
            const p = symmetry.polarity(nl.modelType(e)) == .p;
            upper[d] = if (p) pins[2].index() else pins[0].index();
            lower[d] = if (p) pins[0].index() else pins[2].index();
        } else {
            const a = pins[0].index();
            const b = pins[1].index();
            const a_up = roles[a] == .supply or roles[b] == .sink or
                (roles[b] != .supply and roles[a] != .sink and dist[a] <= dist[b]);
            upper[d] = if (a_up) a else b;
            lower[d] = if (a_up) b else a;
        }
        assert(upper[d] != none);
        assert(lower[d] != none);
    }
}

/// Hops from a supply net through channel elements (transistor channels,
/// two-pin devices but capacitors).
fn supplyDistance(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool) ![]u32 {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    const dist = try gpa.alloc(u32, c.vertexCount());
    errdefer gpa.free(dist);
    @memset(dist, none);
    var queue: std.ArrayList(u32) = .empty;
    defer queue.deinit(gpa);
    for (roles, 0..) |r, net| if (r == .supply) {
        dist[net] = 0;
        try queue.append(gpa, @intCast(net));
    };
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        assert(queue.items.len <= dist.len);
        const v = queue.items[head];
        for (c.incident(VertexId.from(v))) |e| {
            const d = e.index();
            if (!drawn[d] or kinds[d] == .capacitor) continue;
            const pins = c.members(e);
            var chan: [2]VertexId = undefined;
            if (isTransistor(kinds[d]) and pins.len >= 3) {
                chan = .{ pins[0], pins[2] };
            } else if (isTwoPin(kinds[d]) and pins.len >= 2) {
                chan = .{ pins[0], pins[1] };
            } else continue;
            for (chan) |w| if (dist[w.index()] == none) {
                dist[w.index()] = dist[v] + 1;
                try queue.append(gpa, w.index());
            };
        }
    }
    return dist;
}

fn byRank(gpa: Allocator, rank: []const u32) ![]u32 {
    const order = try gpa.alloc(u32, rank.len);
    for (rank, 0..) |r, d| {
        assert(r < rank.len);
        order[r] = @intCast(d);
    }
    for (order, 0..) |d, r| assert(rank[d] == r);
    return order;
}

/// The other member of `d`'s differential or cross-coupled pair, or `none`.
fn blockPartner(st: *const Structure, d: u32) u32 {
    for (st.block_kind, 0..) |k, b| {
        if (k != .pair and k != .cross) continue;
        const ms = st.members(b);
        if (ms[0] == d) return ms[1];
        if (ms[1] == d) return ms[0];
    }
    return none;
}

/// One link per net: from a device whose lower end is on it to one whose
/// upper end is, none across a pair (a tail stands alone). The symmetry's
/// mate net gets the mirrored link.
fn link(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, net_rank: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, chain: *Chain) !void {
    assert(net_rank.len == roles.len);
    assert(chain.above.len == drawn.len);
    @memset(chain.above, none);
    @memset(chain.below, none);
    var ups: std.ArrayList(u32) = .empty;
    defer ups.deinit(gpa);
    var downs: std.ArrayList(u32) = .empty;
    defer downs.deinit(gpa);
    const nets = try byRank(gpa, net_rank);
    defer gpa.free(nets);
    for (nets) |net| {
        if (isRail(roles[net])) continue;
        const m = st.net_mate[net];
        if (m != none and m != net and net_rank[m] < net_rank[net]) continue;
        try endsOn(gpa, nl, drawn, form, upper, lower, net, &ups, &downs);
        const u, const l = choose(nl, st, upper, lower, roles, chain, ups.items, downs.items) orelse continue;
        chain.below[u] = l;
        chain.above[l] = u;
        if (m == none or m == net) continue;
        const mu = st.device_mate[u];
        const ml = st.device_mate[l];
        if (mu == none or ml == none or chain.below[mu] != none or chain.above[ml] != none) continue;
        if (lower[mu] != m or upper[ml] != m) continue;
        chain.below[mu] = ml;
        chain.above[ml] = mu;
    }
    for (chain.below, 0..) |b, d| if (b != none) assert(chain.above[b] == d);
}

/// The drawn vertical devices with their lower end (`ups`) and upper end
/// (`downs`) on `net`, each once.
fn endsOn(gpa: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, net: u32, ups: *std.ArrayList(u32), downs: *std.ArrayList(u32)) !void {
    ups.clearRetainingCapacity();
    downs.clearRetainingCapacity();
    for (nl.graph.incident(VertexId.from(net))) |e| {
        const d = e.index();
        if (!drawn[d] or form[d] != .vertical) continue;
        if (lower[d] == net and std.mem.indexOfScalar(u32, ups.items, d) == null) try ups.append(gpa, d);
        if (upper[d] == net and std.mem.indexOfScalar(u32, downs.items, d) == null) try downs.append(gpa, d);
    }
}

/// The link to keep among `ups` over `downs`, or null: none when either
/// side is a pair (its tail stands alone), else the best free device on
/// each side.
fn choose(nl: *const Netlist, st: *const Structure, upper: []const u32, lower: []const u32, roles: []const Role, chain: *const Chain, ups: []const u32, downs: []const u32) ?struct { u32, u32 } {
    if (ups.len == 0 or downs.len == 0) return null;
    if (isPair(st, ups) or isPair(st, downs)) return null;
    const kinds = nl.graph.edges.items(.kind);
    var u: u32 = none;
    var u_score: i64 = std.math.minInt(i64);
    for (ups) |d| {
        if (chain.below[d] != none) continue;
        const s = @as(i64, @intFromBool(isTransistor(kinds[d]))) * 4 + @as(i64, @intFromBool(reachesRail(roles, upper, lower, chain, d, .up))) * 2;
        const score = s * 1_000_000 - st.device_rank[d];
        if (score > u_score) {
            u_score = score;
            u = d;
        }
    }
    if (u == none) return null;
    const pol_u = symmetry.polarity(nl.modelType(EdgeId.from(u)));
    var l: u32 = none;
    var l_score: i64 = std.math.minInt(i64);
    for (downs) |d| {
        if (chain.above[d] != none or d == u) continue;
        const same = isTransistor(kinds[d]) and symmetry.polarity(nl.modelType(EdgeId.from(d))) == pol_u;
        const s = @as(i64, @intFromBool(same)) * 8 + @as(i64, @intFromBool(isTransistor(kinds[d]))) * 4 +
            @as(i64, @intFromBool(reachesRail(roles, upper, lower, chain, d, .down))) * 2;
        const score = s * 1_000_000 - st.device_rank[d];
        if (score > l_score) {
            l_score = score;
            l = d;
        }
    }
    if (l == none) return null;
    assert(u != l);
    assert(chain.below[u] == none and chain.above[l] == none);
    return .{ u, l };
}

/// Exactly two devices that are a differential or cross-coupled pair, or
/// each other's mates.
fn isPair(st: *const Structure, ds: []const u32) bool {
    if (ds.len != 2) return false;
    if (st.device_mate[ds[0]] == ds[1]) return true;
    return blockPartner(st, ds[0]) == ds[1];
}

/// Whether following `d`'s end up (or down) through single devices reaches
/// a rail.
fn reachesRail(roles: []const Role, upper: []const u32, lower: []const u32, chain: *const Chain, d0: u32, dir: enum { up, down }) bool {
    var d = d0;
    var steps: usize = 0;
    while (steps <= upper.len) : (steps += 1) {
        const net = if (dir == .up) upper[d] else lower[d];
        if (isRail(roles[net])) return true;
        const next = if (dir == .up) chain.above[d] else chain.below[d];
        if (next == none) return false;
        d = next;
    }
    return false;
}

/// The symmetry's mates where it has one; else each pair's and two-member
/// mirror's or bank's, carried up and down their two columns while the
/// devices there are of one kind.
fn mates(gpa: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, column_of: []const u32, chain: Chain) ![]u32 {
    const n = column_of.len;
    const mate = try gpa.alloc(u32, n);
    errdefer gpa.free(mate);
    @memset(mate, none);
    var exact = false;
    for (st.device_mate, 0..) |m, d| if (m != none and drawn[d]) {
        mate[d] = m;
        exact = true;
    };
    if (exact) return mate;
    defer for (mate, 0..) |m, d| if (m != none) assert(mate[m] == d);
    const kinds = nl.graph.edges.items(.kind);
    for (st.block_kind, 0..) |k, b| {
        const ms = st.members(b);
        // A bank's two need not mirror each other: a tail and a second
        // stage's source share a bias line.
        if (k == .stack or k == .bank or ms.len != 2) continue;
        var a = ms[0];
        var z = ms[1];
        if (form[a] != .vertical or form[z] != .vertical or column_of[a] == column_of[z]) continue;
        if (mate[a] != none or mate[z] != none) continue;
        // Up the two columns, then down.
        for ([_]bool{ true, false }) |up| {
            a = ms[0];
            z = ms[1];
            var steps: usize = 0;
            while (a != none and z != none and kinds[a] == kinds[z] and steps <= n) : (steps += 1) {
                if (mate[a] != none and mate[a] != z) break;
                mate[a] = z;
                mate[z] = a;
                a = if (up) chain.above[a] else chain.below[a];
                z = if (up) chain.above[z] else chain.below[z];
                if (a != none and z != none and (mate[a] != none or mate[z] != none)) break;
            }
        }
    }
    return mate;
}

/// Bridges in canonical order: a bridge whose mate stands already takes
/// the mirror image of its cell; any other its first net's tap row
/// (between the devices above and below it there), in the channel nearest
/// the middle of its nets' columns. A taken cell moves it away from the
/// axis (rightward with none) until one is free.
fn bridges(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, x: []i32, y: []i32) !void {
    const c = &nl.graph;
    const n = c.edgeCount();
    assert(x.len == n);
    assert(y.len == n);
    // Twice the axis: the sum of any mirrored pair of vertical devices.
    var axis2: ?i32 = null;
    for (st.device_mate, 0..) |m, a| if (m != none and m != a and drawn[a] and form[a] == .vertical) {
        axis2 = x[a] + x[m];
        break;
    };
    var taken: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer taken.deinit(gpa);
    for (0..n) |d| if (drawn[d] and form[d] == .vertical) try taken.put(gpa, .{ x[d], y[d] }, {});
    const order = try byRank(gpa, st.device_rank);
    defer gpa.free(order);
    const placed = try gpa.alloc(bool, n);
    defer gpa.free(placed);
    @memset(placed, false);
    for (order) |d| {
        if (!drawn[d] or form[d] != .horizontal) continue;
        const m = st.device_mate[d];
        var at: [2]i32 = undefined;
        if (axis2 != null and m != none and m != d and placed[m]) {
            at = .{ axis2.? - x[m], y[m] };
        } else {
            var row: ?i32 = null;
            var sum: i64 = 0;
            var count: i64 = 0;
            for (c.members(EdgeId.from(d))) |net| {
                if (isRail(roles[net.index()])) continue;
                if (row == null) row = tapRow(nl, drawn, form, upper, lower, rank, net.index());
                for (c.incident(net)) |e| {
                    const v = e.index();
                    if (!drawn[v] or form[v] != .vertical) continue;
                    sum += x[v];
                    count += 1;
                }
            }
            at = .{ if (count > 0) @intCast(@divFloor(sum + @divFloor(count, 2), count)) else 0, row orelse -1 };
        }
        const step: i32 = if (axis2 != null and 2 * at[0] < axis2.?) -1 else 1;
        var steps: usize = 0;
        while (taken.contains(at)) : (steps += 1) {
            assert(steps <= n);
            at[0] += step;
        }
        try taken.put(gpa, at, {});
        x[d] = at[0];
        y[d] = at[1];
        placed[d] = true;
    }
}

/// The odd row just below a net's lowest device above it, else just above
/// its highest device below it; null for a net no vertical device ends on.
fn tapRow(nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, net: u32) ?i32 {
    assert(net < nl.graph.vertexCount());
    assert(rank.len == drawn.len);
    var above: ?u32 = null;
    var below: ?u32 = null;
    for (nl.graph.incident(VertexId.from(net))) |e| {
        const d = e.index();
        if (!drawn[d] or form[d] != .vertical) continue;
        if (lower[d] == net) above = @max(above orelse 0, rank[d]);
        if (upper[d] == net) below = @min(below orelse std.math.maxInt(u32), rank[d]);
    }
    if (above) |r| return 2 * @as(i32, @intCast(r)) + 1;
    if (below) |r| return 2 * @as(i32, @intCast(r)) - 1;
    return null;
}

/// Every transistor's gate faces the rest of its gate net, or away from the
/// middle when that is a rail or it has none; then a differential pair's
/// face out, the two of a mirror, bank or cross-coupled pair face each
/// other, and a larger mirror's or bank's all face left, as along one gate
/// line.
fn gates(nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []const bool, form: []const Form, x: []const i32, gate_right: []bool) void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    assert(gate_right.len == c.edgeCount());
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    for (0..c.edgeCount()) |d| if (drawn[d]) {
        lo = @min(lo, x[d]);
        hi = @max(hi, x[d]);
    };
    for (0..c.edgeCount()) |d| {
        if (!drawn[d] or form[d] != .vertical or !isTransistor(kinds[d])) continue;
        const pins = c.members(EdgeId.from(d));
        var sum: i64 = 0;
        var count: i64 = 0;
        if (!isRail(roles[pins[1].index()])) for (c.incident(pins[1])) |e| {
            const v = e.index();
            if (v == d or !drawn[v]) continue;
            sum += x[v];
            count += 1;
        };
        // Twice the coordinates, so a middle between columns is exact.
        const own: i64 = 2 * @as(i64, x[d]);
        gate_right[d] = if (count > 0) @divFloor(2 * sum, count) > own else own > @as(i64, lo) + hi;
    }
    for (st.block_kind, 0..) |k, b| {
        const ms = st.members(b);
        if (k == .stack) continue;
        if (ms.len > 2) {
            for (ms) |d| gate_right[d] = false;
            continue;
        }
        const a, const z = if (x[ms[0]] <= x[ms[1]]) .{ ms[0], ms[1] } else .{ ms[1], ms[0] };
        if (x[a] == x[z]) continue;
        gate_right[a] = k != .pair;
        gate_right[z] = k == .pair;
    }
}

/// Two devices on one cell is a bug of the placement above.
fn expectDistinctCells(gpa: Allocator, drawn: []const bool, x: []const i32, y: []const i32) !void {
    var seen: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer seen.deinit(gpa);
    for (drawn, x, y) |dr, px, py| if (dr) {
        const gop = try seen.getOrPut(gpa, .{ px, py });
        assert(!gop.found_existing);
    };
}

fn normalize(drawn: []const bool, x: []i32, y: []i32) void {
    var mx: i32 = std.math.maxInt(i32);
    var my: i32 = std.math.maxInt(i32);
    for (drawn, x, y) |dr, px, py| if (dr) {
        mx = @min(mx, px);
        my = @min(my, py);
    };
    if (mx == std.math.maxInt(i32)) return;
    for (x, y) |*px, *py| {
        px.* -= mx;
        py.* -= my;
    }
    for (drawn, x, y) |dr, px, py| if (dr) {
        assert(px >= 0);
        assert(py >= 0);
    };
}
