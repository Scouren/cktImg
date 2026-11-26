//! Private capacitor-switch-capacitor paths between paired CT banks.
//!
//! Human Rules:
//! - coil_chains.1 (habit, bounded) AG1180 has two private C-S-C paths
//!   between corresponding outer ends of its two mirrored CT banks.
//!   Exactly one path per end and all four direct/cross switch contexts
//!   qualify. Count every private incidence, including hidden/control
//!   loads, before visibility. This is one figure, not a general switch
//!   rule. docs/research/center-tap-chains.md; `topology`
//! - coil_chains.2 (invariant) Own only six chain devices; the banks are
//!   read-only anchors. Exact capacitor mates and self-mated switches,
//!   whole-owner caller precedence and unique membership are required.
//!   A successful bank list may compact, so retain its typed first-coil
//!   handle rather than a transient list index. `collect`
//!
//! Data: complete netlist, existing bank certificates, exact mates and
//! admitted requests in; cold 36-byte six-device owners out. One per bank
//! pair bounds both allocations. Six u1 choices identify actual path ends;
//! no copied net table or active flags. All fields are read together once
//! per draw outside routing. Canonical parent order determines attempts.
//! Caller frees both buffers; all allocation precedes geometry mutation.
//!
//! Contents:
//! - `pub const Owner`, `Batch`, `Batch.deinit`
//! - `pub fn topology(nl: *const Netlist, roles: []const sch.Role, pair: banks.Pair) ?Owner`
//! - `pub fn held(nl: *const Netlist, sk: *const skeleton.Skeleton, st: *const structure.Structure, d: u32) bool`
//! - `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines, parents: []const banks.Pair) Allocator.Error!Batch`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const banks = @import("coil_banks.zig");
const network = @import("coil_network.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;

/// Existing parent key, then upper/lower cap-switch-cap handles in the
/// first-to-second bank direction; `first` names that directed path end.
pub const Owner = network.Chain;

/// Returns the complete raw two-chain topology, before caller or frame
/// filtering. Used by the separate chain and four-switch owners; the
/// existing paired-bank certificate supplies distinct outer nets.
pub const topology = network.chains;

/// Caller-owned immediate requests and two-axis order capacity.
pub const Batch = struct {
    owners: std.ArrayList(Owner),
    coordinates: [][2]i32,

    /// Releases both buffers using the collection allocator.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.owners.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

comptime { assert(@sizeOf(Owner) == 36); }

/// Collects unheld topology before any geometry writes. Parent keys remain
/// stable if the bank owner later removes unsuccessful placements. All
/// per-device and per-net inputs span the graph; caller deinitializes.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines, parents: []const banks.Pair) Allocator.Error!Batch {
    assert(ats.len == nl.graph.edgeCount() and sk.drawn.len == ats.len);
    assert(st.device_mate.len == ats.len and lines.style.len == s.roles.len);
    var owners: std.ArrayList(Owner) = .empty;
    errdefer owners.deinit(gpa);
    try owners.ensureTotalCapacity(gpa, parents.len);
    for (parents) |parent| {
        const owner = topology(nl, s.roles, parent) orelse continue;
        const shared = shared: for (parents) |other| {
            if (other[0].devices[0] == owner.parent) continue;
            const candidate = topology(nl, s.roles, other) orelse continue;
            for (owner.devices) |d| for (candidate.devices) |e| { if (d == e) break :shared true; };
        } else false;
        if (shared) continue;
        const blocked = blocked: for (owner.devices, 0..) |edge, i| {
            const d = edge.index();
            const mate = owner.devices[(i / 3) * 3 + 2 - i % 3].index();
            if (st.device_mate[d] != mate or !sk.drawn[d] or ats[d] != null or sk.shelf[d] != sk.shelf[owner.parent.index()] or held(nl, sk, st, d)) break :blocked true;
            for (st.block_devices) |member| if (member == d) break :blocked true;
            if (!s.lib.at(s.devices.items(.class)[d]).shows(0) or !s.lib.at(s.devices.items(.class)[d]).shows(1)) break :blocked true;
        } else false;
        if (blocked) continue;
        const styled = styled: for ([_]usize{ 0, 2, 3, 5 }) |i| {
            const pin: u1 = if (i % 3 == 0) 1 - owner.first[i] else owner.first[i];
            const net = nl.graph.members(owner.devices[i])[pin].index();
            if (lines.style[net] != .auto or lines.port[net] != null) break :styled true;
            for (lines.routes) |route| if (route.net == net) break :styled true;
        } else false;
        if (!styled) owners.appendAssumeCapacity(owner);
    }
    const coordinates = try gpa.alloc([2]i32, 24 * owners.items.len);
    return .{ .owners = owners, .coordinates = coordinates };
}

/// Whether an admitted caller request holds this device's automatic pose.
/// Global grouping off holds every member; dropped/rejected lines do not.
pub fn held(nl: *const Netlist, sk: *const skeleton.Skeleton, st: *const structure.Structure, d: u32) bool {
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

