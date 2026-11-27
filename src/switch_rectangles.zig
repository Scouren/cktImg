//! Ordered four-MOS channel rectangles and their competing source/drain slots.
//!
//! Contents:
//! - `pub const Reason`, `pub const Rectangle`, `pub fn fromDevices`, `pub fn alone`
const std = @import("std");
const netlist = @import("netlist.zig");
const Edge = netlist.EdgeId;
const Net = netlist.VertexId;

/// All observed structural reasons for rejecting the exact four-MOS gate pattern.
pub const Reason = enum { competing_slot, model_or_parameters, body, gate_nets, uncrossed_gates };

/// Each slot retains every original MOS sharing its ordered source/drain pair.
/// The grid order is first source × both drains, then second source × both drains.
pub const Rectangle = struct {
    sources: [2]Net,
    drains: [2]Net,
    slots: [4][]const Edge,
    reasons: std.EnumSet(Reason),
};

/// Enumerates complete rectangles before any model, body, gate or caller
/// filter. The caller supplies distinct, original four-terminal MOS handles
/// in this graph and an arena for the returned rows and slot slices. Invalid
/// handles and inputs beyond the bounded 128-device scope produce no shapes.
pub fn fromDevices(a: std.mem.Allocator, nl: *const netlist.Netlist, mos: []const Edge) ![]const Rectangle {
    if (mos.len < 4 or mos.len > 128) return &.{};
    for (mos, 0..) |d, i| {
        if (d.index() >= nl.graph.edgeCount() or nl.graph.edges.items(.kind)[d.index()] != .mosfet or nl.graph.members(d).len != 4 or std.mem.indexOfScalar(Edge, mos[0..i], d) != null) return &.{};
    }
    var sources: std.ArrayList(Net) = .empty;
    var drains: std.ArrayList(Net) = .empty;
    for (mos) |d| {
        const pins = nl.graph.members(d);
        if (std.mem.indexOfScalar(Net, sources.items, pins[2]) == null) try sources.append(a, pins[2]);
        if (std.mem.indexOfScalar(Net, drains.items, pins[0]) == null) try drains.append(a, pins[0]);
    }
    const grid = try a.alloc(std.ArrayList(Edge), sources.items.len * drains.items.len);
    @memset(grid, .empty);
    for (mos) |d| {
        const pins = nl.graph.members(d);
        const s = std.mem.indexOfScalar(Net, sources.items, pins[2]).?;
        const t = std.mem.indexOfScalar(Net, drains.items, pins[0]).?;
        try grid[s * drains.items.len + t].append(a, d);
    }
    var rectangles: std.ArrayList(Rectangle) = .empty;
    var common: [128]usize = undefined;
    for (sources.items, 0..) |s, i| for (sources.items[0..i], 0..) |t, j| {
        var count: usize = 0;
        const x = grid[i * drains.items.len ..][0..drains.items.len];
        const y = grid[j * drains.items.len ..][0..drains.items.len];
        for (drains.items, 0..) |d, k| if (d != s and d != t and x[k].items.len > 0 and y[k].items.len > 0) {
            common[count] = k;
            count += 1;
        };
        for (common[0..count], 0..) |d, k| for (common[0..k]) |e| {
            const slots = [4][]const Edge{ x[d].items, x[e].items, y[d].items, y[e].items };
            const nodes = [4]Net{ s, t, drains.items[d], drains.items[e] };
            try rectangles.append(a, .{ .sources = nodes[0..2].*, .drains = nodes[2..4].*, .slots = slots, .reasons = screen(nl, slots, nodes) });
        };
    };
    return rectangles.items;
}

/// Exactly one raw rectangle can touch the proposed members. A competitor
/// still counts when its model, body, or control pattern would be ineligible.
pub fn alone(rows: []const Rectangle, members: []const u32) bool {
    if (members.len != 4) return false;
    var matched = false;
    for (rows) |row| {
        var touches = false;
        var same = true;
        for (row.slots) |slot| {
            var mine = false;
            for (slot) |d| if (std.mem.indexOfScalar(u32, members, d.index()) != null) {
                mine = true;
            };
            touches = touches or mine;
            same = same and mine and slot.len == 1;
        }
        if (!touches) continue;
        if (matched or !same or row.reasons.count() != 0) return false;
        matched = true;
    }
    return matched;
}

// ---- private ----

fn screen(nl: *const netlist.Netlist, slots: [4][]const Edge, nodes: [4]Net) std.EnumSet(Reason) {
    var reasons: std.EnumSet(Reason) = .empty;
    for (slots) |slot| if (slot.len != 1) {
        reasons.insert(.competing_slot);
        return reasons;
    };
    const first = slots[0][0];
    const body = nl.graph.members(first)[3];
    var gates: [4]Net = undefined;
    for (slots, &gates) |slot, *gate| {
        const d = slot[0];
        const pin = nl.graph.members(d);
        if (!equal(nl.params(d), nl.params(first))) reasons.insert(.model_or_parameters);
        if (pin[3] != body) reasons.insert(.body);
        gate.* = pin[1];
    }
    var distinct: usize = 0;
    for (gates, 0..) |g, i| {
        distinct += @intFromBool(std.mem.indexOfScalar(Net, gates[0..i], g) == null);
        if (std.mem.indexOfScalar(Net, &nodes, g) != null) reasons.insert(.gate_nets);
    }
    if (distinct != 2) reasons.insert(.gate_nets);
    if (!reasons.contains(.gate_nets) and (gates[0] != gates[3] or gates[1] != gates[2])) reasons.insert(.uncrossed_gates);
    return reasons;
}

fn equal(lhs: []const []const u8, rhs: []const []const u8) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |x, y| if (!std.mem.eql(u8, x, y)) return false;
    return true;
}
