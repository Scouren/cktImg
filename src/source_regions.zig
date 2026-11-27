//! Source-connected MOS regions and terminal witnesses in a selected original cell.
//!
//! Contents:
//! - `pub const Disposition`, `pub const Occurrence`, `pub const Region`, `pub const Inventory`
//! - `pub fn collect(a: std.mem.Allocator, raw: []const u8, nl: *const netlist.Netlist) !Inventory`

const std = @import("std");
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const Edge = netlist.EdgeId;
const Net = netlist.VertexId;

/// A raw region can have any number of sources. Only the two exact resistor
/// shapes below attach extra devices. A direct-source relation remains raw.
pub const Disposition = enum { direct_source, other_source_count, unresolved, paired_rail_sources, equal_arms_tail };
/// The original card binding that actually touches the region.
pub const Occurrence = struct { device: Edge, terminal: u8, net: Net };
/// Source membership, complete local incidence, and any certified attachments.
/// All handles refer to the original graph used in this inventory.
pub const Region = struct {
    members: []const Edge,
    incidence: []const Occurrence,
    disposition: Disposition,
    owned: []const Edge,
};
/// A scope failure retains its reason and grants no source ownership.
pub const Inventory = struct {
    scope: enum { selected_cell, unsupported_grammar, source_graph_mismatch },
    regions: []const Region = &.{},
};

/// Binds a single original cell to the actual graph and collects every
/// off-rail source/resistor region with at least two source occurrences.
/// Only literal, ordered, supported card bindings enter the inventory.
pub fn collect(a: std.mem.Allocator, raw: []const u8, nl: *const netlist.Netlist) !Inventory {
    if (nl.defs.len != 1 or nl.graph.edgeCount() > 128) return .{ .scope = .unsupported_grammar };
    const text = std.ascii.lowerString(try a.alloc(u8, raw.len), raw);
    const title = !std.mem.startsWith(u8, std.mem.trimStart(u8, text, " \t\r\n"), ".subckt");
    var cards = netlist.OriginalCards.init(text, title);
    const seen = try a.alloc(bool, nl.graph.edgeCount());
    @memset(seen, false);
    var active = false;
    var opened = false;
    var models: std.StringHashMapUnmanaged(void) = .empty;
    while (try cards.next(a)) |f| {
        if (std.mem.eql(u8, f[0], ".model")) {
            if (f.len < 3 or (try models.getOrPut(a, f[1])).found_existing) return .{ .scope = .unsupported_grammar };
            continue;
        }
        if (std.mem.eql(u8, f[0], ".subckt")) {
            if (opened or f.len < 2 or !std.mem.eql(u8, f[1], nl.defs[0].name) or !tokensEq(f[2..], nl.defs[0].ports)) return .{ .scope = .source_graph_mismatch };
            active = true;
            opened = true;
            continue;
        }
        if (std.mem.eql(u8, f[0], ".ends")) {
            if (!active or f.len > 2 or (f.len == 2 and !std.mem.eql(u8, f[1], nl.defs[0].name))) return .{ .scope = .source_graph_mismatch };
            active = false;
            continue;
        }
        if (!active) return .{ .scope = .unsupported_grammar };
        const count: usize = switch (f[0][0]) {
            'm' => 4,
            'r', 'l', 'c', 'i', 'v', 'd' => 2,
            else => return .{ .scope = .unsupported_grammar },
        };
        const id = nl.device(f[0]) orelse return .{ .scope = .source_graph_mismatch };
        const pins = nl.graph.members(id);
        if (seen[id.index()] or f.len < 2 + count or count != pins.len or !tokensEq(nl.params(id), f[1 + count ..])) return .{ .scope = .source_graph_mismatch };
        seen[id.index()] = true;
        for (pins, f[1..][0..count]) |n, token| if (!std.mem.eql(u8, nl.graph.vertices.items(.name)[n.index()], token)) return .{ .scope = .source_graph_mismatch };
    }
    if (!opened or active or std.mem.indexOfScalar(bool, seen, false) != null) return .{ .scope = .source_graph_mismatch };

    const roots = try a.alloc(u32, nl.graph.vertexCount());
    const rail = try a.alloc(bool, roots.len);
    for (roots, rail, nl.graph.vertices.items(.name), 0..) |*parent, *is_rail, name, i| {
        parent.* = @intCast(i);
        const named = library.named(name, .net);
        is_rail.* = (named == .supply or named == .ground);
    }
    for (nl.graph.edges.items(.kind), 0..) |kind, i| {
        if (kind != .resistor) continue;
        const p = nl.graph.members(Edge.from(i));
        if (!rail[p[0].index()] and !rail[p[1].index()]) roots[root(roots, p[0].index())] = root(roots, p[1].index());
    }
    for (roots, 0..) |*p, i| p.* = root(roots, @intCast(i));
    const sources = try a.alloc(u32, roots.len);
    @memset(sources, 0);
    for (nl.graph.edges.items(.kind), 0..) |kind, i| if (kind == .mosfet) {
        const source = nl.graph.members(Edge.from(i))[2].index();
        if (!rail[source]) sources[roots[source]] += 1;
    };
    var regions: std.ArrayList(Region) = .empty;
    for (sources, 0..) |n, owner| {
        if (n < 2) continue;
        var members: std.ArrayList(Edge) = .empty;
        var incidence: std.ArrayList(Occurrence) = .empty;
        for (nl.graph.edges.items(.kind), 0..) |kind, i| {
            const e = Edge.from(i);
            for (nl.graph.members(e), 0..) |v, t| if (roots[v.index()] == owner) {
                if (kind == .mosfet and t == 2) try members.append(a, e);
                try incidence.append(a, .{ .device = e, .terminal = @intCast(t), .net = v });
            };
        }
        var row = Region{ .members = members.items, .incidence = incidence.items, .owned = &.{}, .disposition = .other_source_count };
        if (n == 2) row.disposition = try attach(a, nl, rail, &row);
        try regions.append(a, row);
    }
    return .{ .scope = .selected_cell, .regions = regions.items };
}

// ---- private ----

fn attach(a: std.mem.Allocator, nl: *const netlist.Netlist, rail: []const bool, row: *Region) !Disposition {
    const m = row.members;
    const pa = nl.graph.members(m[0]);
    const pb = nl.graph.members(m[1]);
    if (pa[2] == pb[2]) return .direct_source;
    const body = pa[3];
    const role = library.named(nl.graph.vertices.items(.name)[body.index()], .net);
    const model = nl.modelType(m[0]) orelse return .unresolved;
    if (pa[0] == pb[0] or pa[1] == pb[1] or body != pb[3] or !rail[body.index()] or !tokensEq(nl.params(m[0]), nl.params(m[1]))) return .unresolved;
    if (!std.mem.eql(u8, model, if (role == .supply) "pmos" else "nmos")) return .unresolved;
    var owned: std.ArrayList(Edge) = .empty;
    try owned.appendSlice(a, m);
    var currents: [2]?Edge = .{ null, null };
    var current_term: ?u8 = null;
    var anchors: [2]?Edge = .{ null, null };
    var center: ?Net = null;
    var bridge: ?Edge = null;
    var tail: ?Edge = null;
    for (row.incidence) |hit| {
        const e = hit.device;
        const ps = nl.graph.members(e);
        const net = hit.net;
        for (nl.defs[0].ports) |port| if (std.mem.eql(u8, port, nl.graph.vertices.items(.name)[net.index()])) return .unresolved;
        const branch: ?usize = if (net == pa[2]) 0 else if (net == pb[2]) 1 else null;
        if (e == m[0] or e == m[1]) {
            if (hit.terminal != 2) return .unresolved;
            continue;
        }
        switch (nl.graph.edges.items(.kind)[e.index()]) {
            .resistor => {
                const other = ps[1 - hit.terminal];
                if (rail[other.index()] or other == net or nl.params(e).len != 1 or !std.math.isFinite(nl.graph.edges.items(.value)[e.index()])) return .unresolved;
                // Process each resistor at a source end. A bridge has two such ends.
                const slot = branch orelse continue;
                if (anchors[slot] != null) return .unresolved;
                anchors[slot] = e;
                if (other == pa[2] or other == pb[2]) {
                    bridge = e;
                } else {
                    if (center != null and center != other) return .unresolved;
                    center = other;
                }
            },
            .isource => {
                const slot = branch orelse return .unresolved;
                if (currents[slot] != null or ps[1 - hit.terminal] != body or (current_term != null and current_term != hit.terminal)) return .unresolved;
                const value = nl.params(e);
                if (value.len != 2 or !std.mem.eql(u8, value[0], "dc")) return .unresolved;
                const current = netlist.parseValue(value[1]) catch return .unresolved;
                if (!(current > 0) or hit.terminal != @intFromBool(role == .supply)) return .unresolved;
                currents[slot] = e;
                current_term = hit.terminal;
            },
            .mosfet => {
                if (tail != null or hit.terminal != 0 or branch != null or ps[2] != body or ps[3] != body or !std.mem.eql(u8, nl.params(e)[0], nl.params(m[0])[0])) return .unresolved;
                tail = e;
            },
            else => return .unresolved,
        }
    }
    const arm0 = anchors[0] orelse return .unresolved;
    const arm1 = anchors[1] orelse return .unresolved;
    if (bridge) |r| {
        const current_a = currents[0] orelse return .unresolved;
        const current_b = currents[1] orelse return .unresolved;
        if (tail != null or center != null or arm0 != r or arm1 != r or row.incidence.len != 6 or !tokensEq(nl.params(current_a), nl.params(current_b))) return .unresolved;
        try owned.appendSlice(a, &.{ r, current_a, current_b });
        row.owned = owned.items;
        return .paired_rail_sources;
    }
    const t = tail orelse return .unresolved;
    if (currents[0] != null or currents[1] != null or center != nl.graph.members(t)[0] or row.incidence.len != 7 or !tokensEq(nl.params(arm0), nl.params(arm1))) return .unresolved;
    try owned.appendSlice(a, &.{ arm0, arm1, t });
    row.owned = owned.items;
    return .equal_arms_tail;
}

fn tokensEq(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (!std.mem.eql(u8, x, y)) return false;
    return true;
}

fn root(parents: []const u32, node: u32) u32 {
    var id = node;
    while (parents[id] != id) id = parents[id];
    return id;
}
