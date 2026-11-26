//! Closed resistor-loaded differential stages -> cold placement owners.
//!
//! Human Rules:
//! - resistor_loads.1 (bounded observation) Three source stages have one
//!   diode PMOS, two resistors, one NMOS input pair and one grounded NMOS
//!   tail. Count complete load/tail incidence and raw drain competitors
//!   before model, visibility or caller-frame checks. No name/value test.
//!   Source: docs/research/resistor-load-stages.md; `find`.
//! - resistor_loads.2 (bounded priority) Two stages whose outputs drive
//!   the other's input gates and whose tails form one complete automatic
//!   bank own twelve devices together. Their separate local axes and left
//!   tail gates refine the generic bank/global-axis arrangement. Keep all
//!   mate identities; actual drawing symmetry validation remains in force.
//! - resistor_loads.3 (boundary) Admitted caller geometry, grouping and
//!   symmetry requests win for the whole owner. Only its own input pairs
//!   and, for a linked owner, its complete tail bank may touch it. External
//!   or incompatible mates and other crossing blocks abstain. `collect`
//!
//! Data: borrowed CSR/model/role/admission tables in; cold six-handle and
//! two-stage records out (24/48 bytes). At most PMOS-count raw candidates; disjoint survivors use six devices. Each
//! record is consumed together once per placement phase; no hot table or
//! ABI changes. Caller-owned lists/order storage live through one draw;
//! every allocation precedes geometry mutation. Canonical stage ordering
//! fixes sequential collision decisions. No hot-loop or speed claim.
//!
//! Contents: Group, Pair, Batch, Batch.deinit, collect; private topology/admission queries.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const device = @import("device.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;

/// Load, two resistors, corresponding input devices, grounded tail.
pub const Group = [6]EdgeId;
/// Upstream followed by downstream, each retaining its local mate pairs.
pub const Pair = [2]Group;
/// Separate existence lists avoid an unused second stage in single owners.
pub const Batch = struct {
    singles: std.ArrayList(Group),
    pairs: std.ArrayList(Pair),
    coordinates: [][2]i32,

    /// Frees all buffers with the allocator used by collect.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.singles.deinit(gpa);
        self.pairs.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

comptime {
    assert(@sizeOf(Group) == 24 and @sizeOf(Pair) == 48);
}

/// Collects whole unheld owners. All device/net slices span nl; allocation
/// failure leaves every borrowed table unchanged. Forty order slots per
/// stage cover both axes, including linked-stage separation.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    const c = &nl.graph;
    assert(ats.len == c.edgeCount() and sk.drawn.len == c.edgeCount());
    assert(st.device_mate.len == c.edgeCount() and lines.style.len == c.vertexCount());
    var raw: std.ArrayList(Group) = .empty;
    defer raw.deinit(gpa);
    var capacity: usize = 0;
    for (c.edges.items(.kind), 0..) |kind, d| if (kind == .mosfet and known(nl, .from(d), "pmos")) {
        capacity += 1;
    };
    try raw.ensureTotalCapacity(gpa, capacity);
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .mosfet) continue;
        if (find(nl, s.roles, st.device_rank, .from(d))) |group| {
            assert(raw.items.len < raw.capacity);
            raw.appendAssumeCapacity(group);
        }
    }
    std.sort.heap(Group, raw.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Group, b: Group) bool {
            return rank[a[0].index()] < rank[b[0].index()];
        }
    }.less);
    var singles: std.ArrayList(Group) = .empty;
    errdefer singles.deinit(gpa);
    var pairs: std.ArrayList(Pair) = .empty;
    errdefer pairs.deinit(gpa);
    try singles.ensureTotalCapacity(gpa, raw.items.len);
    try pairs.ensureTotalCapacity(gpa, raw.items.len / 2);
    if (!st.symmetry_off) for (raw.items) |a| {
        if (overlaps(raw.items, a)) continue;
        var linked: ?Group = null;
        var links: usize = 0;
        for (raw.items) |b| {
            if (a[0] == b[0]) continue;
            if (drives(nl, a, b) or drives(nl, b, a)) {
                links += 1;
                linked = b;
            }
        }
        if (links > 1) continue;
        if (linked) |b| {
            if (overlaps(raw.items, b)) continue;
            if (!drives(nl, a, b) or drives(nl, b, a)) continue;
            var reverse_links: usize = 0;
            for (raw.items) |other| if (other[0] != b[0] and (drives(nl, b, other) or drives(nl, other, b))) {
                reverse_links += 1;
            };
            if (reverse_links != 1) continue;
            const pair: Pair = .{ a, b };
            if (admitted(nl, sk, st, ats, lines, &pair)) pairs.appendAssumeCapacity(pair);
        } else if (admitted(nl, sk, st, ats, lines, &.{a})) singles.appendAssumeCapacity(a);
    };
    const coordinates = try gpa.alloc([2]i32, 40 * (singles.items.len + 2 * pairs.items.len));
    return .{ .singles = singles, .pairs = pairs, .coordinates = coordinates };
}

// ---- private ----

fn known(nl: *const Netlist, edge: EdgeId, model: []const u8) bool {
    return nl.graph.edges.items(.kind)[edge.index()] == .mosfet and
        nl.graph.members(edge).len == 4 and std.mem.eql(u8, nl.modelType(edge) orelse return false, model);
}

fn find(nl: *const Netlist, roles: []const sch.Role, rank: []const u32, load: EdgeId) ?Group {
    const c = &nl.graph;
    if (!known(nl, load, "pmos")) return null;
    const p = c.members(load);
    if (p[0] != p[1] or p[2] != p[3] or roles[p[2].index()] != .supply or roles[p[0].index()].isRail() or c.incident(p[0]).len != 4) return null;
    var group: Group = @splat(.from(sch.none));
    group[0] = load;
    var n: usize = 0;
    for (c.incident(p[0])) |edge| {
        if (edge == load) continue;
        if (n == 2 or c.edges.items(.kind)[edge.index()] != .resistor) return null;
        const q = c.members(edge);
        if (q.len != 2 or q[0] == q[1]) return null;
        group[1 + n] = edge;
        n += 1;
    }
    if (n != 2 or group[1] == group[2]) return null;
    if (rank[group[1].index()] > rank[group[2].index()]) std.mem.swap(EdgeId, &group[1], &group[2]);
    for (0..2) |i| {
        const r = c.members(group[1 + i]);
        const out = if (r[0] == p[0]) r[1] else r[0];
        if (roles[out.index()].isRail()) return null;
        var count: usize = 0;
        for (c.edges.items(.kind), 0..) |kind, d| {
            const edge: EdgeId = .from(d);
            const q = c.members(edge);
            if (!device.isTransistor(kind) or q.len < 3 or q[0] != out) continue;
            count += 1;
            group[3 + i] = edge;
        }
        if (count != 1 or !known(nl, group[3 + i], "nmos")) return null;
        const q = c.members(group[3 + i]);
        if (q[0] == q[1] or q[0] == q[2] or q[1] == q[2] or roles[q[3].index()] != .sink) return null;
    }
    const a, const b = .{ c.members(group[3]), c.members(group[4]) };
    if (a[0] == b[0] or a[2] != b[2] or a[3] != b[3] or a[1] == b[1] or roles[a[2].index()].isRail() or c.incident(a[2]).len != 3) return null;
    n = 0;
    for (c.incident(a[2])) |edge| {
        if (edge == group[3] or edge == group[4]) continue;
        n += 1;
        group[5] = edge;
    }
    if (n != 1 or !known(nl, group[5], "nmos")) return null;
    const tail = c.members(group[5]);
    if (tail[0] != a[2] or tail[2] != a[3] or tail[3] != a[3] or tail[0] == tail[1] or tail[1] == tail[2]) return null;
    for (group, 0..) |edge, i| for (group[0..i]) |previous| if (edge == previous) return null;
    return group;
}

fn overlaps(groups: []const Group, a: Group) bool {
    for (groups) |other| {
        if (other[0] == a[0]) continue;
        for (a) |edge| if (contains(other, edge.index())) return true;
    }
    return false;
}

fn drives(nl: *const Netlist, a: Group, b: Group) bool {
    const c = &nl.graph;
    const x, const y = .{ c.members(a[3])[0], c.members(a[4])[0] };
    const u, const v = .{ c.members(b[3])[1], c.members(b[4])[1] };
    return (x == u and y == v) or (x == v and y == u);
}

fn admitted(nl: *const Netlist, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines, groups: []const Group) bool {
    assert(groups.len == 1 or groups.len == 2);
    const image = [_]usize{ 0, 2, 1, 4, 3, 5 };
    for (groups, 0..) |group, gi| for (group, 0..) |edge, i| {
        const d = edge.index();
        if (!sk.drawn[d] or ats[d] != null or held(nl, sk, st, edge)) return false;
        const mate = st.device_mate[d];
        if (mate != sch.none and mate != group[image[i]].index()) return false;
        for (groups[0..gi]) |old| for (old) |e| if (edge == e) return false;
        if (nl.defOf(edge)) |def| for (def.sides) |side| if (side != null) return false;
        for (nl.graph.members(edge)) |net| {
            const k = net.index();
            if (lines.style[k] != .auto or lines.port[k] != null or std.mem.indexOfScalar(u32, lines.first, k) != null) return false;
            for (lines.routes) |route| if (route.net == k) return false;
        }
    };
    var bank = false;
    for (st.block_kind, 0..) |kind, bi| {
        const members = st.members(bi);
        var hits: usize = 0;
        for (members) |d| for (groups) |group| if (contains(group, d)) {
            hits += 1;
        };
        if (hits == 0) continue;
        if (members.len != 2 or hits != 2) return false;
        const pair = for (groups) |group| {
            if (same(members, group[3], group[4])) break true;
        } else false;
        if (kind == .pair and pair) continue;
        if (kind == .bank and groups.len == 2 and same(members, groups[0][5], groups[1][5]) and !bank) {
            bank = true;
            continue;
        }
        return false;
    }
    return (groups.len == 2) == bank;
}

fn same(members: []const u32, a: EdgeId, b: EdgeId) bool {
    return (members[0] == a.index() and members[1] == b.index()) or (members[0] == b.index() and members[1] == a.index());
}
fn contains(group: Group, d: u32) bool {
    for (group) |edge| if (edge.index() == d) return true;
    return false;
}
fn held(nl: *const Netlist, sk: *const skeleton.Skeleton, st: *const structure.Structure, edge: EdgeId) bool {
    for (nl.hints, sk.verdicts, st.verdicts) |hint, sv, tv| {
        const verdict = sv orelse tv orelse continue;
        if (verdict.state != .honoured and verdict.state != .relaxed) continue;
        switch (hint.verb) {
            .off, .symmetry_off, .axis => return true,
            .pair, .mirror, .bank, .stack, .cross, .nogroup, .symmetric, .row, .above, .order, .cell, .face, .upright, .bridge, .at => {},
            else => continue,
        }
        for (hint.args) |name| if ((nl.device(name) orelse continue) == edge) return true;
    }
    return false;
}
