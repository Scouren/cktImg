//! Stage 3 of issue #8: where each drawn device stands, as a cell of a
//! lattice. In: the netlist, its roles and its structure. Out, per device:
//! drawn or not; its form (vertical: current enters at its top and leaves
//! at its bottom; horizontal: a bridge between columns); which side its
//! gate faces; its x and y. Neighbouring device columns stand eight
//! lattice columns apart and device rows two apart, so a channel lies
//! between any two: taps, bridges and wires go there.
//!
//! - A device is vertical when it is a transistor, sits on a rail, or is in
//!   series (alone with one other channel element on each of its nets);
//!   a capacitor only on a rail. Anything else bridges, as does a two-pin
//!   device between two nets the symmetry swaps (it straddles the axis).
//! - Columns are the chains current flows down: one device's lower end and
//!   the next one's upper end on a net. Where several meet, one link is
//!   kept (a stack block's, hinted or recognized; else a transistor, a
//!   chain that reaches a rail, the same type, then rank), mirrored by the
//!   symmetry; nothing else links across a pair's tail, so a tail stands in
//!   a column of its own.
//! - Mates: the symmetry's, else each differential, cross-coupled or
//!   two-member mirror pair's, carried up and down their columns; kept only
//!   where each column's mates stand in one column, since columns mirror
//!   whole.
//! - Rows by longest path down the chains, mates and blocks held level where
//!   that closes no cycle; transistors on ground drop to their type's lowest
//!   such row.
//! - Columns ordered by `columns.zig`, bridges set in the channels between
//!   them by `bridges.zig`.
//! - Gates: a differential pair's face out, a mirror's or a cross-coupled
//!   pair's face each other, any other transistor's faces the rest of its
//!   gate net.
//!
//! Contents:
//! - `pub const Form = enum(u8) { vertical, horizontal }`
//! - `pub const Skeleton = struct`
//! - `pub fn place(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure) Allocator.Error!Skeleton`
//! - `pub const Invalid = error{...}`, `pub fn validate(sk: *const Skeleton, nl: *const Netlist) Invalid!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const symmetry = @import("symmetry.zig");
const columns = @import("columns.zig");
const levels = @import("levels.zig");
const bridges = @import("bridges.zig");
const relations = @import("relations.zig");
const sequence = @import("sequence.zig");
const mates = @import("mates.zig");
const cells = @import("cells.zig");
const hints = @import("hints.zig");

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
    /// Its cell; the smallest of each axis is 0.
    x: []const i32,
    y: []const i32,
    /// Twice the x of the axis mated devices mirror about, if any.
    axis2: ?i32,
    /// Where cell (0, 0) is in the frame `cell` lines use (before the cells
    /// shift to start at 0): add it to a cell to get that frame's.
    origin: [2]i32,
    /// Per deck hint: what became of it, for the lines this stage owns
    /// (`upright`, `bridge`, `face`, `row`, `above`); null for the rest.
    verdicts: []const ?hints.Verdict,
};

/// What a skeleton edited by a caller can get wrong for the drawing.
pub const Invalid = error{
    /// A slice is not one entry per device.
    WrongLength,
    /// A drawn device's cell is negative.
    OffLattice,
    /// Two drawn devices share a cell.
    CellTaken,
    /// A vertical device's ends are not two of its nets.
    BadEnds,
};

/// Lattice columns between neighbouring device columns, per step of
/// `columns.order`: the slots between hold bridges.
const spread = 4;

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

    const verdicts = try arena.alloc(?hints.Verdict, nl.hints.len);
    @memset(verdicts, null);
    try classify(gpa, nl, roles, st, drawn, form, verdicts);
    try relations.forms(arena, nl, drawn, form, verdicts);
    try ends(gpa, nl, roles, drawn, form, upper, lower);
    try relations.ends(arena, nl, drawn, form, upper, lower, verdicts);
    const rel = try relations.rows(gpa, arena, nl, st, drawn, form, verdicts);
    const seq = try sequence.read(gpa, arena, nl, st, drawn, form, verdicts);
    const net_rank = st.net_rank;
    var chain: Chain = .{ .above = try gpa.alloc(u32, n), .below = try gpa.alloc(u32, n) };
    defer gpa.free(chain.above);
    defer gpa.free(chain.below);
    try link(gpa, nl, roles, st, net_rank, &rel, &seq, drawn, form, upper, lower, &chain);

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

    const mate = try mates.find(gpa, nl, st, drawn, form, column_of, chain.above, chain.below, start.items.len - 1);
    defer gpa.free(mate);
    const rank = try levels.rows(gpa, nl, roles, st, &rel, mate, chain.below, drawn, form, upper, lower);
    defer gpa.free(rank);
    const cols: columns.Columns = .{ .start = start.items, .devices = members.items };
    const partners = try gpa.alloc(u32, n);
    defer gpa.free(partners);
    for (partners, 0..) |*p, d| p.* = blockPartner(st, @intCast(d));
    const col_x = try columns.order(gpa, nl, roles, cols, column_of, mate, partners, st.device_rank, rank);
    defer gpa.free(col_x);
    try sequence.columns(gpa, &seq, column_of, col_x);
    for (0..n) |d| {
        if (!drawn[d] or form[d] != .vertical) continue;
        x[d] = spread * col_x[column_of[d]];
        y[d] = 2 * @as(i32, @intCast(rank[d]));
    }
    // The core stands about x = 0 until the cells shift to start at 0; a
    // device its own mate whose column went free keeps none.
    var mated = false;
    for (mate, 0..) |*m, d| {
        // An order line that moved one of a pair ends the pair.
        if (m.* != none and m.* != d and x[d] + x[m.*] != 0) {
            mate[m.*] = none;
            m.* = none;
        }
        if (m.* == d and x[d] != 0) m.* = none;
        mated = mated or (m.* != none and drawn[d] and form[d] == .vertical);
    }
    try bridges.place(gpa, nl, roles, st, devices_by_rank, drawn, form, upper, lower, rank, if (mated) 0 else null, x, y);
    try sequence.bridges(gpa, &seq, rel.bridge_row, devices_by_rank, drawn, form, x, y, verdicts);
    try cells.apply(gpa, arena, nl, drawn, mate, x, y, verdicts);
    mated = false;
    for (mate, 0..) |m, d| mated = mated or (m != none and drawn[d] and form[d] == .vertical);
    gates(nl, roles, st, drawn, form, x, gate_right);
    // A gate a line turns against its mate's ends the mirror.
    const mirrored = try relations.faces(arena, nl, drawn, form, mate, gate_right, verdicts);
    const origin = normalize(drawn, x, y);
    try expectDistinctCells(gpa, drawn, x, y);
    const axis2: ?i32 = if (mated and mirrored) -2 * origin[0] else null;
    if (axis2) |a2| for (mate, 0..) |m, d| if (m != none and drawn[d] and form[d] == .vertical) assert(x[d] + x[m] == a2);
    return .{ .drawn = drawn, .form = form, .upper = upper, .lower = lower, .gate_right = gate_right, .x = x, .y = y, .axis2 = axis2, .origin = origin, .verdicts = verdicts };
}

/// Checks what `sketch.draw` relies on in `sk`, as a caller may have edited
/// it: one entry per device, drawn devices on distinct cells of the lattice
/// (x and y at least 0), and each vertical device's upper and lower ends two
/// distinct nets it touches. `place`'s own skeletons always pass.
pub fn validate(sk: *const Skeleton, nl: *const Netlist) Invalid!void {
    const c = &nl.graph;
    const n = c.edgeCount();
    for ([_]usize{ sk.drawn.len, sk.form.len, sk.upper.len, sk.lower.len, sk.gate_right.len, sk.x.len, sk.y.len }) |len| {
        if (len != n) return error.WrongLength;
    }
    for (0..n) |d| {
        if (!sk.drawn[d]) continue;
        if (sk.x[d] < 0 or sk.y[d] < 0) return error.OffLattice;
        for (d + 1..n) |e| {
            if (sk.drawn[e] and sk.x[e] == sk.x[d] and sk.y[e] == sk.y[d]) return error.CellTaken;
        }
        if (sk.form[d] != .vertical) continue;
        const up = sk.upper[d];
        const low = sk.lower[d];
        if (up == low or up >= c.vertexCount() or low >= c.vertexCount()) return error.BadEnds;
        var has_up = false;
        var has_low = false;
        for (c.members(EdgeId.from(d))) |net| {
            has_up = has_up or net.index() == up;
            has_low = has_low or net.index() == low;
        }
        if (!has_up or !has_low) return error.BadEnds;
    }
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

/// Drawn: not a driver (unless a `driver` line says) and with pins. Vertical: a transistor, a two-pin
/// device on a rail, or one in series (each of its nets holds one other
/// channel element); capacitors only on a rail; never a two-pin device
/// between two nets the symmetry swaps, which straddles the axis, nor a
/// device whose current path is shorted (a MOS dummy: no current flows).
fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []bool, form: []Form, verdicts: []?hints.Verdict) !void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    assert(drawn.len == c.edgeCount());
    for (drawn, 0..) |*dr, d| {
        dr.* = c.members(EdgeId.from(d)).len > 0 and !sch.isDriver(c, roles, @intCast(d));
    }
    try relations.drivers(gpa, nl, drawn, verdicts);
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
            if (pins[0].index() != pins[2].index()) f.* = .vertical;
        } else if (isTwoPin(kinds[d]) and pins.len >= 2 and pins[0].index() != pins[1].index()) {
            const a = pins[0].index();
            const b = pins[1].index();
            const on_rail = isRail(roles[a]) or isRail(roles[b]);
            const series = kinds[d] != .capacitor and count[a] == 2 and count[b] == 2;
            const straddles = a != b and st.net_mate[a] == b;
            if ((on_rail or series) and !straddles) f.* = .vertical;
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
        assert(upper[d] != none and lower[d] != none);
        assert(upper[d] != lower[d]);
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
fn link(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, net_rank: []const u32, rel: *const relations.Relations, seq: *const sequence.Sequence, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, chain: *Chain) !void {
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
    // Each device's next one down its stack block, hinted or recognized.
    const stacked = try gpa.alloc(u32, drawn.len);
    defer gpa.free(stacked);
    @memset(stacked, none);
    for (st.block_kind, 0..) |k, b| if (k == .stack) {
        const ms = st.members(b);
        for (ms[0 .. ms.len - 1], ms[1..]) |u, l| stacked[u] = l;
    };
    for (nets) |net| {
        if (isRail(roles[net])) continue;
        const m = st.net_mate[net];
        if (m != none and m != net and net_rank[m] < net_rank[net]) continue;
        try endsOn(gpa, nl, drawn, form, upper, lower, net, &ups, &downs);
        const u, const l = choose(nl, st, upper, lower, roles, chain, stacked, ups.items, downs.items) orelse continue;
        if (closesLoop(chain, u, l) or try rel.refuses(gpa, chain.below, u, l) or try seq.refuses(gpa, chain.above, u, l)) continue;
        chain.below[u] = l;
        chain.above[l] = u;
        if (m == none or m == net) continue;
        const mu = st.device_mate[u];
        const ml = st.device_mate[l];
        if (mu == none or ml == none or chain.below[mu] != none or chain.above[ml] != none) continue;
        if (lower[mu] != m or upper[ml] != m or closesLoop(chain, mu, ml) or try rel.refuses(gpa, chain.below, mu, ml) or try seq.refuses(gpa, chain.above, mu, ml)) continue;
        chain.below[mu] = ml;
        chain.above[ml] = mu;
    }
    for (chain.below, 0..) |b, d| if (b != none) assert(chain.above[b] == d);
}

/// Whether `u` over `l` closes a loop: `u` stands below `l` already (two
/// devices joined by both their ends, each over the other on one net).
fn closesLoop(chain: *const Chain, u: u32, l: u32) bool {
    var d = l;
    var steps: usize = 0;
    while (d != none) : (steps += 1) {
        assert(steps <= chain.below.len);
        if (d == u) return true;
        d = chain.below[d];
    }
    return false;
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

/// The link to keep among `ups` over `downs`, or null: a stack block's
/// (`stacked`, either way round: a hint lists its devices in any order),
/// the first by rank; else none when either side is a pair (its tail
/// stands alone), else the best free device on each side.
fn choose(nl: *const Netlist, st: *const Structure, upper: []const u32, lower: []const u32, roles: []const Role, chain: *const Chain, stacked: []const u32, ups: []const u32, downs: []const u32) ?struct { u32, u32 } {
    if (ups.len == 0 or downs.len == 0) return null;
    const rank = st.device_rank;
    var block: ?struct { u32, u32 } = null;
    for (ups) |u| for (downs) |l| {
        if (u == l or chain.below[u] != none or chain.above[l] != none) continue;
        if (stacked[u] != l and stacked[l] != u) continue;
        const bu, const bl = block orelse .{ u, l };
        if (block == null or rank[u] < rank[bu] or (u == bu and rank[l] < rank[bl])) block = .{ u, l };
    };
    if (block) |b| return b;
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

/// Shifts every cell so the smallest x and y are 0; returns the shift.
fn normalize(drawn: []const bool, x: []i32, y: []i32) [2]i32 {
    var mx: i32 = std.math.maxInt(i32);
    var my: i32 = std.math.maxInt(i32);
    for (drawn, x, y) |dr, px, py| if (dr) {
        mx = @min(mx, px);
        my = @min(my, py);
    };
    if (mx == std.math.maxInt(i32)) return .{ 0, 0 };
    for (x, y) |*px, *py| {
        px.* -= mx;
        py.* -= my;
    }
    for (drawn, x, y) |dr, px, py| if (dr) {
        assert(px >= 0);
        assert(py >= 0);
    };
    return .{ mx, my };
}
