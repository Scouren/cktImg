//! One successful linked-load owner -> its observed two named 2+1 outputs.
//!
//! Human Rules:
//! - resistor_downstream.1 (bounded observation) Two correlated branches in
//!   complete AG1052 keep the owned resistor/drain pair physically separate
//!   from a remote input gate. Each remote drain also has the complete raw
//!   resistor/NMOS-follower/PMOS-gate interface, with every supply/body bound.
//!   The source census admits exactly these two nets in 2,936 drawings.
//!   No name, value, distance or crossing budget selects. `branch`
//! - resistor_downstream.2 (boundary) Exactly one successful linked Pair and
//!   both complete interfaces qualify together before routing deferral.
//!   Multiple owners, raw competitors, unknown models, aliases and admitted
//!   interface geometry/net requests retain ordinary routing. `qualify`
//! - resistor_downstream.3 (choice) Each qualified net uses ordinary trunk
//!   and names for its local pair and remote gate, atomically. Current cut
//!   rounds may retain the two pieces; label rounds use ordinary labels.
//!   All actual leads, names, contacts and thinning remain authoritative.
//!
//! Data: one borrowed 48-byte Pair or empty; two temporary six-handle Branch
//! arrays (24 bytes each). No allocation, retained graph or widened request
//! view. The caller owns all inputs; wire_parts owns cold append rollback.
//! Raw CSR counts precede filtering. No hot-path or speed claim.
//!
//! Contents: qualify, parts; private topology, intent and actual-pin checks.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const canvas = @import("canvas.zig");
const loads = @import("resistor_loads.zig");
const hints = @import("hints.zig");
const netlines = @import("netlines.zig");
const wire_parts = @import("wire_parts.zig");
const Requests = @import("wire_requests.zig").Requests;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Pair = loads.Pair;
const Canvas = canvas.Canvas;
const Pt = library.Pt;
const Branch = [6]EdgeId; // Owned R/D, external input device, R, N, P.

comptime {
    assert(@sizeOf(Branch) == 24);
}

/// Returns the same sole successful Pair slice or empty. Both complete
/// interfaces and original admitted requests are checked without allocation.
/// The three verdict slices and NetLines belong to the caller's draw phase.
pub fn qualify(nl: *const Netlist, roles: []const sch.Role, pairs: []const Pair, sk: []const ?hints.Verdict, st: []const ?hints.Verdict, verdicts: []const ?hints.Verdict, lines: *const netlines.NetLines) []const Pair {
    assert(roles.len == nl.graph.vertexCount() and lines.style.len == roles.len);
    assert(sk.len == nl.hints.len and st.len == nl.hints.len and verdicts.len == nl.hints.len);
    if (pairs.len != 1 or lines.first.len != 0) return &.{};
    for (0..2) |i| {
        const members = branch(nl, roles, pairs[0], i) orelse return &.{};
        for (members) |edge| {
            for (nl.graph.members(edge)) |net| {
                if (lines.style[net.index()] != .auto or lines.port[net.index()] != null) return &.{};
                for (lines.routes) |route| if (route.net == net.index()) return &.{};
            }
            for (nl.hints, sk, st, verdicts) |hint, sv, tv, dv| {
                const verdict = dv orelse sv orelse tv orelse continue;
                if (verdict.state != .honoured and verdict.state != .relaxed) continue;
                switch (hint.verb) {
                    .off, .symmetry_off, .axis => return &.{},
                    .pair, .mirror, .bank, .stack, .cross, .nogroup, .symmetric, .row, .above, .order, .cell, .face, .upright, .bridge, .at => {},
                    else => continue,
                }
                for (hint.args) |name| if ((nl.device(name) orelse continue) == edge) return &.{};
            }
        }
    }
    return pairs;
}

/// Consumes only qualify's borrowed result, before mirror replication.
/// Each net commits independently; decline/OOM restores its appended ink and
/// generated symbols. Earlier successful nets and every caller table remain.
pub fn parts(c: *Canvas, nl: *const Netlist, pairs: []const Pair, lines: *const netlines.NetLines, requests: Requests, pins_of: []const std.ArrayList(u32), routed: []const bool, drawn: []bool) Allocator.Error!void {
    assert(pairs.len <= 1 and requests.ats.len == nl.graph.edgeCount());
    assert(pins_of.len == c.s.net_name.len and routed.len == pins_of.len and drawn.len == pins_of.len);
    if (pairs.len == 0 or lines.first.len != 0) return;
    for (0..2) |i| {
        const members = branch(nl, c.s.roles, pairs[0], i) orelse continue;
        const net = nl.graph.members(members[1])[0].index();
        if (routed[net] or drawn[net] or c.s.roles[net] != .internal or lines.port[net] != null) continue;
        if (lines.style[net] != .auto and lines.style[net] != .cut) continue;
        const blocked = blk: {
            for (members) |edge| if (requests.ats[edge.index()] != null) break :blk true;
            for (requests.routes) |route| if (route.net == net) break :blk true;
            for (lines.routes) |route| if (route.net == net) break :blk true;
            for (c.segs.items) |segment| if (segment.net == net) break :blk true;
            break :blk false;
        };
        if (blocked) continue;
        const pins = map(c, nl, members, net, pins_of[net].items) orelse continue;
        if (try wire_parts.draw(c, net, pins[0..2], pins[2..3], .name)) {
            drawn[net] = true;
            c.s.labeled[net] = true;
        }
    }
}

// ---- private ----

fn branch(nl: *const Netlist, roles: []const sch.Role, pair: Pair, i: usize) ?Branch {
    assert(i < 2 and roles.len == nl.graph.vertexCount());
    const c = &nl.graph;
    const r = pair[1][1 + i];
    const d = pair[1][3 + i];
    const net = c.members(d)[0];
    const local = c.members(r);
    if (local.len != 2 or local[0] == local[1] or (local[0] != net and local[1] != net)) return null;
    const incident = c.incident(net);
    if (incident.len != 3 or roles[net.index()].isRail()) return null;
    var have_r = false;
    var have_d = false;
    var remote: ?EdgeId = null;
    for (incident) |edge| {
        if (edge == r) {
            if (have_r) return null;
            have_r = true;
        } else if (edge == d) {
            if (have_d) return null;
            have_d = true;
        } else {
            if (remote != null) return null;
            remote = edge;
        }
    }
    if (!have_r or !have_d) return null;
    const gate = remote orelse return null;
    const supply = c.members(pair[1][0])[2];
    const ground = c.members(pair[1][5])[2];
    if (!known(nl, gate, "nmos")) return null;
    const g = c.members(gate);
    if (g[1] != net or g[3] != ground or inside(pair, gate)) return null;
    const output = c.incident(g[0]);
    if (output.len != 4 or roles[g[0].index()].isRail()) return null;
    var out: Branch = .{ r, d, gate, .from(sch.none), .from(sch.none), .from(sch.none) };
    var drain = false;
    for (output) |edge| {
        const ports = c.members(edge);
        if (edge == gate) {
            if (drain) return null;
            drain = true;
            continue;
        }
        if (inside(pair, edge)) return null;
        if (c.edges.items(.kind)[edge.index()] == .resistor) {
            if (out[3].index() != sch.none or ports.len != 2 or ports[0] == ports[1]) return null;
            if (!((ports[0] == supply and ports[1] == g[0]) or (ports[1] == supply and ports[0] == g[0]))) return null;
            out[3] = edge;
        } else if (known(nl, edge, "nmos")) {
            if (out[4].index() != sch.none or ports[1] != g[0] or ports[0] != supply or ports[3] != ground) return null;
            out[4] = edge;
        } else if (known(nl, edge, "pmos")) {
            if (out[5].index() != sch.none or ports[1] != g[0] or ports[2] != supply or ports[3] != supply) return null;
            out[5] = edge;
        } else return null;
    }
    if (!drain) return null;
    for (out) |edge| if (edge.index() == sch.none) return null;
    for (out, 0..) |edge, j| for (out[j + 1 ..]) |other| if (edge == other) return null;
    return out;
}
fn known(nl: *const Netlist, edge: EdgeId, model: []const u8) bool {
    if (nl.graph.edges.items(.kind)[edge.index()] != .mosfet) return false;
    const p = nl.graph.members(edge);
    return p.len == 4 and p[0] != p[1] and p[0] != p[2] and p[1] != p[2] and std.mem.eql(u8, nl.modelType(edge) orelse return false, model);
}
fn inside(pair: Pair, edge: EdgeId) bool {
    for (pair) |group| for (group) |member| if (member == edge) return true;
    return false;
}
fn map(c: *const Canvas, nl: *const Netlist, members: Branch, net: u32, pins: []const u32) ?[3]u32 {
    if (pins.len != 3) return null;
    var out: [3]u32 = @splat(sch.none);
    const indices = [3]usize{ @intFromBool(nl.graph.members(members[0])[0].index() != net), 0, 1 };
    for (pins) |p| {
        const pin = c.s.pins.get(p);
        const slot = for (members[0..3], indices, 0..) |edge, index, j| {
            if (pin.device == edge.index() and pin.index == index) break j;
        } else return null;
        if (pin.net != net or out[slot] != sch.none) return null;
        const bound = nl.graph.members(members[slot]);
        if (pin.index >= bound.len or bound[pin.index].index() != net) return null;
        const row = c.s.devices.get(pin.device);
        const class = c.s.lib.at(row.class);
        if (!row.kept or !class.shows(pin.index) or sch.referencePin(c.s, pin.device, pin.index, net)) return null;
        if (class.side(pin.index, row.orient) != pin.side) return null;
        const node = c.s.deviceNode(pin.device) orelse return null;
        const origin = Pt.round(c.s.xy[node]);
        const offset = row.orient.apply(class.terminals[pin.index].at);
        const point = canvas.pinAt(c.s, p);
        if (@as(i64, origin.x) - row.grid.x + offset.x != point.x or @as(i64, origin.y) - row.grid.y + offset.y != point.y) return null;
        out[slot] = p;
    }
    for (out) |pin| if (pin == sch.none) return null;
    return out;
}

test {
    _ = @import("resistor_downstream_test.zig");
}
