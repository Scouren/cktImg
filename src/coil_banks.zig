//! Paired reciprocal-MOS tanks with two center-tapped windings per bank.
//!
//! Human Rules:
//! - coil_banks.1 (habit, bounded) AG1180 contains two mirrored banks, each
//!   with two parallel CT contracts, one capacitor and two reciprocal
//!   ground-return NMOS devices. This is one figure, not two independent
//!   samples. Count all candidates before visibility or frame filtering;
//!   third windings, extra capacitors and ambiguous active pairs abstain.
//!   coil_network.findBank; docs/research/center-tap-chains.md
//! - coil_banks.2 (invariant) Own both banks together only when their exact
//!   structural mates close over all ten members and corresponding nets.
//!   Contained automatic cross groups are compatible; admitted caller
//!   groups, global grouping off, poses, relations, sides and outer-net
//!   styles win for the whole owner. No private mate is cleared. `collect`
//!
//! Data: CSR/contracts, roles, structural mates and admitted requests in;
//! cold 56-byte paired certificates out. Five typed device handles, two
//! u2 port maps and one u1 end index make each 28-byte bank. All fields are
//! consumed together by once-per-draw placement, outside routing loops.
//! At most CT-count/4 owners; caller-owned buffers are reserved before any
//! geometry write and freed after drawing. Canonical ranks order collision
//! decisions. No retained flags or copied net table; no speed claim.
//!
//! Contents:
//! - `pub const Bank`, `Pair`, `Batch`, `Batch.deinit`
//! - `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const network = @import("coil_network.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;

/// Existing devices in order: inner winding, outer winding, capacitor,
/// N1-drain MOS, N2-drain MOS. Port maps follow the first winding's nets.
pub const Bank = network.Bank;

/// Complete disjoint banks, corresponding devices related by exact mates.
pub const Pair = network.Pair;

/// Temporary successful owners and their coordinate-order capacity.
pub const Batch = struct {
    pairs: std.ArrayList(Pair),
    coordinates: [][2]i32,

    /// Releases the two buffers using the collection allocator.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.pairs.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

comptime {
    assert(@sizeOf(Bank) == 28);
    assert(@sizeOf(Pair) == 56);
}

/// Collects complete paired owners before any geometry mutation. Every
/// per-device/per-net input spans the graph; the caller frees the result.
/// Forty orders per owner bound all initially strict terminal relations.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    const c = &nl.graph;
    assert(ats.len == c.edgeCount() and sk.drawn.len == c.edgeCount());
    assert(st.device_mate.len == c.edgeCount() and lines.style.len == c.vertexCount());
    var count: usize = 0;
    for (c.edges.items(.kind), 0..) |kind, d| if (kind == .subckt and network.ports(nl, EdgeId.from(d)) != null) {
        count += 1;
    };
    var out: std.ArrayList(Pair) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, count / 4);
    if (sk.axis2 != null and !st.symmetry_off) for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt) continue;
        const a = network.findBank(nl, s.roles, st.device_rank, EdgeId.from(d)) orelse continue;
        if (a.devices[0].index() != d) continue;
        const mate = st.device_mate[d];
        if (mate == sch.none or mate == d or st.device_rank[d] > st.device_rank[mate]) continue;
        var b = network.findBank(nl, s.roles, st.device_rank, EdgeId.from(mate)) orelse continue;
        if (!image(nl, st, a, &b)) continue;
        const pair: Pair = .{ a, b };
        const shelf = sk.shelf[d];
        const blocked = blocked: for (pair) |bank| {
            for (bank.devices) |edge| {
                const i = edge.index();
                if (!sk.drawn[i] or ats[i] != null or sk.shelf[i] != shelf or held(nl, sk, st, i)) break :blocked true;
                if (nl.defOf(edge)) |def| for (def.sides) |side| if (side != null) break :blocked true;
            }
        } else false;
        if (blocked) continue;
        const styled = styled: for (pair) |bank| {
            const p = c.members(bank.devices[0]);
            for (bank.pins[0][0..2]) |pin| {
                const net = p[pin].index();
                if (lines.style[net] != .auto or lines.port[net] != null) break :styled true;
                for (lines.routes) |route| if (route.net == net) break :styled true;
            }
        } else false;
        if (styled) continue;
        const grouped = grouped: for (st.block_kind, 0..) |kind_block, bi| {
            const members = st.members(bi);
            var hits: usize = 0;
            for (members) |member| hits += @intFromBool(contains(pair, member));
            if (hits == 0) continue;
            if (kind_block != .cross or members.len != 2 or hits != 2) break :grouped true;
            const same = for (pair) |bank| {
                const x, const y = .{ bank.devices[3].index(), bank.devices[4].index() };
                if ((members[0] == x and members[1] == y) or (members[0] == y and members[1] == x)) break true;
            } else false;
            if (!same) break :grouped true;
        } else false;
        if (!grouped) out.appendAssumeCapacity(pair);
    };
    std.sort.heap(Pair, out.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Pair, b: Pair) bool {
            return rank[a[0].devices[0].index()] < rank[b[0].devices[0].index()];
        }
    }.less);
    const coordinates = try gpa.alloc([2]i32, 40 * out.items.len);
    return .{ .pairs = out, .coordinates = coordinates };
}

// ---- private ----

fn image(nl: *const Netlist, st: *const structure.Structure, a: Bank, b: *Bank) bool {
    if (st.device_mate[a.devices[0].index()] == b.devices[1].index()) {
        std.mem.swap(EdgeId, &b.devices[0], &b.devices[1]);
        std.mem.swap([3]u2, &b.pins[0], &b.pins[1]);
    }
    if (st.device_mate[a.devices[3].index()] == b.devices[4].index()) {
        std.mem.swap(EdgeId, &b.devices[3], &b.devices[4]);
        for (&b.pins) |*p| std.mem.swap(u2, &p[0], &p[1]);
        b.first = 1 - b.first;
    }
    for (a.devices, b.devices) |x, y| {
        if (x == y or st.device_mate[x.index()] != y.index() or st.device_mate[y.index()] != x.index()) return false;
        for (a.devices) |other| if (y == other) return false;
    }
    const ap = nl.graph.members(a.devices[0]);
    const bp = nl.graph.members(b.devices[0]);
    for (a.pins[0], b.pins[0]) |x, y| {
        if (ap[x] != bp[y] and st.net_mate[ap[x].index()] != bp[y].index()) return false;
    }
    return true;
}

fn held(nl: *const Netlist, sk: *const skeleton.Skeleton, st: *const structure.Structure, d: u32) bool {
    for (nl.hints, sk.verdicts, st.verdicts) |hint, sv, tv| {
        const verdict = sv orelse tv orelse continue;
        if (verdict.state != .honoured and verdict.state != .relaxed) continue;
        switch (hint.verb) {
            .off => return true,
            .pair, .mirror, .bank, .stack, .cross, .nogroup, .row, .above, .order, .cell, .face, .upright, .bridge => {},
            else => continue,
        }
        for (hint.args) |name| if ((nl.device(name) orelse continue).index() == d) return true;
    }
    return false;
}

fn contains(pair: Pair, d: u32) bool {
    for (pair) |bank| for (bank.devices) |edge| if (edge.index() == d) return true;
    return false;
}
