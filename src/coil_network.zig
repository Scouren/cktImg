//! Cold contracts for the paired center-tapped resonator network.
//!
//! Human Rules:
//! - coil_network.1 (habit, bounded) AG1180 has two reciprocal NMOS tanks,
//!   each with two parallel CT windings and one capacitor; two private
//!   C-S-C chains and four direct/cross switches join them. Count every
//!   candidate before choosing. This is one source figure, not a general
//!   LC network rule. docs/research/center-tap-chains.md; `findBank`, `chains`
//! - coil_network.2 (choice) When exactly one complete two-bank context
//!   exists, request its whole-network reflection before the generic
//!   maximum-moved-device choice. The graph search must prove all original
//!   pin bindings and admitted caller constraints; failed requests fall
//!   back to ordinary search. No terminal-equivalence rule changes.
//!   `preferred`; structure.mates
//!
//! Data: netlist incidence/contracts, roles and canonical ranks in; cold
//! immediate typed-handle certificates out. Existing bank/chain/bridge
//! placement and structure analysis share these pure bounded scans. Twelve
//! device-pair requests cover twenty distinct members in 96 stack bytes.
//! There is no allocation, class geometry, retained state or hot dispatch.
//! Multiple complete bank contexts abstain from this preference; source
//! selection does not license moving a held member downstream.
//!
//! Contents:
//! - `pub const Bank`, `Pair`, `Chain`, `Bridges`, `Reflection`
//! - `pub fn ports(nl: *const Netlist, edge: EdgeId) ?[3]u2`
//! - `pub fn findBank(nl: *const Netlist, roles: []const sch.Role, rank: []const u32, coil: EdgeId) ?Bank`
//! - `pub fn chains(nl: *const Netlist, roles: []const sch.Role, pair: Pair) ?Chain`
//! - `pub fn bridges(nl: *const Netlist, roles: []const sch.Role, pair: Pair) ?Bridges`
//! - `pub fn preferred(nl: *const Netlist, roles: []const sch.Role, rank: []const u32) ?Reflection`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const block_symbols = @import("block_symbols.zig");
const device = @import("device.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;

/// Canonical two windings, capacitor, N1-drain and N2-drain MOS handles;
/// semantic CT port maps and capacitor first end use that first winding.
pub const Bank = struct { devices: [5]EdgeId, pins: [2][3]u2, first: u1 };
/// Disjoint banks; each placement consumer verifies its exact mate image.
pub const Pair = [2]Bank;
/// Parent key, then upper/lower C-S-C paths in first-to-second direction.
pub const Chain = struct { parent: EdgeId, devices: [6]EdgeId, first: [6]u1 };
/// Parent key, then corresponding-upper/lower and crossed switch paths.
pub const Bridges = struct { parent: EdgeId, devices: [4]EdgeId, first: [4]u1 };
/// Twelve device-pair requests, including four self-mated axis devices.
pub const Reflection = [12][2]EdgeId;

comptime {
    assert(@sizeOf(Bank) == 28 and @sizeOf(Pair) == 56);
    assert(@sizeOf(Chain) == 36 and @sizeOf(Bridges) == 24);
    assert(@sizeOf(Reflection) == 96);
}

/// Returns the three declared semantic ports of a complete CT contract.
pub fn ports(nl: *const Netlist, edge: EdgeId) ?[3]u2 {
    const def = nl.defOf(edge) orelse return null;
    if (block_symbols.identify(def.name, def.ports) != .center_tap or nl.graph.members(edge).len != 3) return null;
    var result: [3]u2 = undefined;
    for (def.ports, 0..) |name, i| for ([_][]const u8{ "n1", "n2", "n3" }, 0..) |want, k| {
        if (std.ascii.eqlIgnoreCase(name, want)) result[k] = @intCast(i);
    };
    return result;
}

/// Returns a unique bank, before visibility, hints, frames or mates.
pub fn findBank(nl: *const Netlist, roles: []const sch.Role, rank: []const u32, coil: EdgeId) ?Bank {
    const c = &nl.graph;
    const ps = ports(nl, coil) orelse return null;
    const p = c.members(coil);
    const a, const b, const tap = .{ p[ps[0]], p[ps[1]], p[ps[2]] };
    if (a == b or tap == a or tap == b or roles[a.index()].isRail() or roles[b.index()].isRail() or roles[tap.index()] != .supply) return null;
    var result: Bank = undefined;
    var coils: usize = 0;
    var caps: usize = 0;
    var mos: [2]usize = .{ 0, 0 };
    var ground: ?netlist.VertexId = null;
    for (c.edges.items(.kind), 0..) |kind, d| {
        const edge = EdgeId.from(d);
        const ends = c.members(edge);
        if (kind == .subckt) {
            var pins = ports(nl, edge) orelse continue;
            if (!((ends[pins[0]] == a and ends[pins[1]] == b) or (ends[pins[0]] == b and ends[pins[1]] == a))) continue;
            if (coils == 2 or ends[pins[2]] != tap) return null;
            if (ends[pins[0]] != a) std.mem.swap(u2, &pins[0], &pins[1]);
            result.devices[coils] = edge;
            result.pins[coils] = pins;
            coils += 1;
        } else if (kind == .capacitor and ends.len == 2) {
            if (!((ends[0] == a and ends[1] == b) or (ends[1] == a and ends[0] == b))) continue;
            caps += 1;
            result.devices[2] = edge;
            result.first = @intFromBool(ends[0] != a);
        } else if (kind == .mosfet and ends.len == 4) {
            const which: usize = if (ends[0] == a and ends[1] == b) 0 else if (ends[0] == b and ends[1] == a) 1 else continue;
            // A competing reciprocal MOS is ambiguity even if its model,
            // source or body would make that alternative ineligible.
            mos[which] += 1;
            if (device.polarity(nl.modelType(edge) orelse "") != .n or ends[2] != ends[3] or roles[ends[2].index()] != .sink) return null;
            if (ground != null and ground.? != ends[2]) return null;
            ground = ends[2];
            result.devices[3 + which] = edge;
        }
    }
    if (coils != 2 or caps != 1 or mos[0] != 1 or mos[1] != 1) return null;
    if (rank[result.devices[0].index()] > rank[result.devices[1].index()]) {
        std.mem.swap(EdgeId, &result.devices[0], &result.devices[1]);
        std.mem.swap([3]u2, &result.pins[0], &result.pins[1]);
    }
    // The first coil's literal N1 fixes semantic order, independently of
    // card order or a reversed second winding declaration.
    if (c.members(result.devices[0])[ports(nl, result.devices[0]).?[0]] != a) return null;
    return result;
}

/// Returns both unique private chains and checks all four bridge paths.
pub fn chains(nl: *const Netlist, roles: []const sch.Role, pair: Pair) ?Chain {
    const c = &nl.graph;
    var ends: [2][2]VertexId = undefined;
    for (pair, &ends) |bank, *out| for (bank.pins[0][0..2], out) |pin, *net| {
        net.* = c.members(bank.devices[0])[pin];
    };
    for (ends[0]) |a| for (ends[1]) |b| {
        var count: usize = 0;
        for (c.edges.items(.kind), 0..) |kind, d| {
            if (kind != .vswitch) continue;
            const ps = c.members(EdgeId.from(d));
            if (ps.len == 4 and ((ps[0] == a and ps[1] == b) or (ps[0] == b and ps[1] == a))) count += 1;
        }
        if (count != 1) return null;
    };
    var out: Chain = .{ .parent = pair[0].devices[0], .devices = undefined, .first = undefined };
    for (0..2) |i| {
        const a, const b = .{ ends[0][i], ends[1][i] };
        var count: usize = 0;
        for (c.edges.items(.kind), 0..) |kind, d| {
            if (kind != .capacitor) continue;
            const cap = EdgeId.from(d);
            const ps = c.members(cap);
            if (ps.len != 2 or (ps[0] == a) == (ps[1] == a)) continue;
            const first: u1 = @intFromBool(ps[0] != a);
            const u = ps[1 - first];
            if (!private(roles, ends, u) or c.incident(u).len != 2) continue;
            const sw = otherIncident(c.incident(u), cap) orelse continue;
            if (c.edges.items(.kind)[sw.index()] != .vswitch) continue;
            const path = c.members(sw);
            if (path.len != 4 or (path[0] == u) == (path[1] == u)) continue;
            const sf: u1 = @intFromBool(path[0] != u);
            const v = path[1 - sf];
            if (v == u or !private(roles, ends, v) or c.incident(v).len != 2) continue;
            const last = otherIncident(c.incident(v), sw) orelse continue;
            const qs = c.members(last);
            if (last == cap or c.edges.items(.kind)[last.index()] != .capacitor or qs.len != 2) continue;
            if (!((qs[0] == v and qs[1] == b) or (qs[0] == b and qs[1] == v))) continue;
            count += 1;
            out.devices[i * 3 ..][0..3].* = .{ cap, sw, last };
            out.first[i * 3 ..][0..3].* = .{ first, sf, @intFromBool(qs[0] != v) };
        }
        if (count != 1) return null;
    }
    for (out.devices, 0..) |d, i| {
        for (out.devices[0..i]) |other_d| if (d == other_d) return null;
        for (pair) |bank| for (bank.devices) |member| {
            if (d == member) return null;
        };
    }
    return out;
}

/// Returns the unique direct/cross switches of a complete chain context.
pub fn bridges(nl: *const Netlist, roles: []const sch.Role, pair: Pair) ?Bridges {
    _ = chains(nl, roles, pair) orelse return null;
    var ends: [2][2]netlist.VertexId = undefined;
    for (pair, &ends) |bank, *out| for (bank.pins[0][0..2], out) |pin, *net| {
        net.* = nl.graph.members(bank.devices[0])[pin];
    };
    var out: Bridges = .{ .parent = pair[0].devices[0], .devices = undefined, .first = undefined };
    for ([_][4]usize{ .{ 0, 0, 1, 0 }, .{ 0, 1, 1, 1 }, .{ 0, 0, 1, 1 }, .{ 1, 0, 0, 1 } }, 0..) |ij, i| {
        const a, const b = .{ ends[ij[0]][ij[1]], ends[ij[2]][ij[3]] };
        var count: usize = 0;
        for (nl.graph.edges.items(.kind), 0..) |kind, d| {
            if (kind != .vswitch) continue;
            const ps = nl.graph.members(EdgeId.from(d));
            if (ps.len != 4 or !((ps[0] == a and ps[1] == b) or (ps[0] == b and ps[1] == a))) continue;
            count += 1;
            out.devices[i] = EdgeId.from(d);
            out.first[i] = @intFromBool(ps[0] != a);
        }
        if (count != 1) return null;
    }
    for (out.devices, 0..) |d, i| for (out.devices[0..i]) |other| {
        if (d == other) return null;
    };
    return out;
}

/// Nominates one complete twenty-device context, independent of the
/// currently chosen symmetry. A third bank or ambiguous path abstains.
/// The caller combines these requests with admitted hints and validates
/// the complete graph; this function never writes a mate table.
pub fn preferred(nl: *const Netlist, roles: []const sch.Role, rank: []const u32) ?Reflection {
    const c = &nl.graph;
    assert(roles.len == c.vertexCount());
    assert(rank.len == c.edgeCount());
    var pair: Pair = undefined;
    var count: usize = 0;
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt) continue;
        const group = findBank(nl, roles, rank, EdgeId.from(d)) orelse continue;
        if (group.devices[0].index() != d) continue;
        if (count == pair.len) return null;
        pair[count] = group;
        count += 1;
    }
    if (count != pair.len) return null;
    if (rank[pair[0].devices[0].index()] > rank[pair[1].devices[0].index()]) std.mem.swap(Bank, &pair[0], &pair[1]);
    for (pair[0].devices) |a| for (pair[1].devices) |b| {
        if (a == b) return null;
    };
    const left_ends = c.members(pair[0].devices[0]);
    const right_ends = c.members(pair[1].devices[0]);
    for (pair[0].pins[0][0..2]) |x| for (pair[1].pins[0][0..2]) |y| {
        if (left_ends[x] == right_ends[y]) return null;
    };
    const cs = chains(nl, roles, pair) orelse return null;
    const bs = bridges(nl, roles, pair) orelse return null;
    var out: Reflection = undefined;
    for (pair[0].devices, pair[1].devices, out[0..5]) |a, b, *p| p.* = .{ a, b };
    for (0..2) |i| {
        out[5 + 2 * i] = .{ cs.devices[3 * i], cs.devices[3 * i + 2] };
        out[6 + 2 * i] = .{ cs.devices[3 * i + 1], cs.devices[3 * i + 1] };
        out[9 + i] = .{ bs.devices[i], bs.devices[i] };
    }
    out[11] = .{ bs.devices[2], bs.devices[3] };
    for (out, 0..) |ends, i| for (out[0..i]) |old| {
        for (ends) |a| for (old) |b| {
            if (a == b) return null;
        };
    };
    return out;
}

// ---- private ----

fn private(roles: []const sch.Role, ends: [2][2]VertexId, net: VertexId) bool {
    if (roles[net.index()].isRail()) return false;
    for (ends) |pair| for (pair) |other_net| {
        if (net == other_net) return false;
    };
    return true;
}

fn otherIncident(incident: []const EdgeId, selected: EdgeId) ?EdgeId {
    assert(incident.len == 2);
    if (incident[0] == selected and incident[1] != selected) return incident[1];
    if (incident[1] == selected and incident[0] != selected) return incident[0];
    return null;
}
