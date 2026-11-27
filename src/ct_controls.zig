//! A center-tapped common-base bias stage's local control connection.
//!
//! Human Rules:
//! - ct_controls.1 (habit, bounded) AG1114's two NPNs share C/B; their
//!   emitters meet one CT's outer ends. Exactly two resistors complete B's
//!   incidence, one to the tap and one to supply. Its actual B leads share
//!   straight ink. This is ONE figure: common-collector pairs alone have
//!   55 connected and 295 separated source examples. Count raw candidates
//!   and all incidences before visibility/polarity/frame eligibility. `find`
//! - ct_controls.2 (choice) Only for an automatic cut, keep this pair in
//!   one local part when their actual visible bases face along a clear row.
//!   A projected pin, intervening own pin, obstacle, or explicit net route
//!   or first request abstains. Ordinary partitioning, trunk competition,
//!   whole-part fallback and subsequent crossing cuts remain unchanged.
//!   Deferred routes/vias still exclude scaffold grouping.
//!   No device moves and no caller class or pose is rewritten. `adjacent`
//!
//! Data: immutable full CSR/contracts/roles and current Canvas in; zero or
//! one pair of indices into its existing net-pin slice out. A cold 20-byte
//! certificate holds all five member handles, read together.
//! It lives on the stack during one cut-net query, outside pair/DSU loops;
//! counts are bounded by four base incidences and one emitter's adjacency.
//! No new allocation, retained table, distance option or performance claim.
//! Source proof: docs/research/ct-common-controls.md.
//!
//! Contents:
//! - `pub fn adjacent(c: *const Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) ?[2]u32`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const block_symbols = @import("block_symbols.zig");
const NetLines = @import("netlines.zig").NetLines;
const Requests = @import("wire_requests.zig").Requests;
const Pt = @import("library.zig").Pt;
const Side = @import("library.zig").Side;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Canvas = canvas.Canvas;

const Stage = struct { devices: [5]EdgeId };
const no_edge: EdgeId = .from(sch.none);

comptime {
    assert(@sizeOf(Stage) == 20);
}

/// The two indices into `pins` that may share an automatic-cut part, or
/// null without mutation. Asserts graph/device/net table agreement. Actual
/// terminal frames and Canvas clearance are checked at this routing step.
/// requests retains admitted paths and poses even during scaffolding.
pub fn adjacent(c: *const Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) ?[2]u32 {
    assert(nl.graph.edgeCount() == c.s.device_kind.len);
    assert(net < nl.graph.vertexCount());
    assert(requests.ats.len == nl.graph.edgeCount());
    if (c.s.roles[net] != .internal) return null;
    if (std.mem.indexOfScalar(u32, lines.first, net) != null) return null;
    for (requests.routes) |r| if (r.net == net) return null;
    const stage = find(nl, c.s.roles, VertexId.from(net)) orelse return null;
    for (stage.devices) |d| {
        if (requests.ats[d.index()] != null or !c.s.devices.items(.kept)[d.index()] or c.s.deviceNode(d.index()) == null) return null;
    }
    var pair: [2]u32 = @splat(sch.none);
    for (pins, 0..) |p, i| for (stage.devices[0..2], 0..) |d, k| {
        if (c.s.pins.items(.device)[p] != d.index() or c.s.pins.items(.index)[p] != 1) continue;
        if (pair[k] != sch.none) return null;
        pair[k] = @intCast(i);
    };
    if (pair[0] == sch.none or pair[1] == sch.none) return null;
    const a = base(c, pins[pair[0]]) orelse return null;
    const b = base(c, pins[pair[1]]) orelse return null;
    if (a.y != b.y or a.x == b.x) return null;
    const sides = c.s.pins.items(.side);
    if (sides[pins[pair[0]]] != (if (a.x < b.x) Side.right else Side.left) or sides[pins[pair[1]]] != (if (a.x < b.x) Side.left else Side.right)) return null;
    for (pins) |p| {
        if (p == pins[pair[0]] or p == pins[pair[1]]) continue;
        const at = canvas.pinAt(c.s, p);
        if (at.y == a.y and at.x > @min(a.x, b.x) and at.x < @max(a.x, b.x)) return null;
    }
    if (!c.fits(net, a, b)) return null;
    if (pair[0] > pair[1]) std.mem.swap(u32, &pair[0], &pair[1]);
    assert(pair[0] < pair[1]);
    return pair;
}

// ---- private ----

fn find(nl: *const Netlist, roles: []const sch.Role, net: VertexId) ?Stage {
    const g = &nl.graph;
    assert(roles.len == g.vertexCount());
    const incident = g.incident(net);
    if (incident.len != 4) return null;
    var qs: [2]EdgeId = undefined;
    var rs: [2]EdgeId = undefined;
    var nq: u2 = 0;
    var nr: u2 = 0;
    for (incident) |d| {
        const p = g.members(d);
        switch (g.edges.items(.kind)[d.index()]) {
            .bjt => {
                if (nq == 2 or p.len < 3 or p[1] != net) return null;
                qs[nq] = d;
                nq += 1;
            },
            .resistor => {
                if (nr == 2 or p.len != 2 or p[0] == p[1]) return null;
                rs[nr] = d;
                nr += 1;
            },
            else => return null,
        }
    }
    if (nq != 2 or nr != 2 or qs[0] == qs[1] or rs[0] == rs[1]) return null;
    const a, const b = .{ g.members(qs[0]), g.members(qs[1]) };
    if (a[0] != b[0] or a[2] == b[2]) return null;
    var coil: EdgeId = no_edge;
    var tap: VertexId = undefined;
    // A duplicate CSR incidence is not a second coil, but a second
    // complete coil is ambiguous even if it will be hidden or ineligible.
    for (g.incident(a[2])) |d| {
        if (g.edges.items(.kind)[d.index()] != .subckt) continue;
        const def = nl.defOf(d) orelse continue;
        if (block_symbols.identify(def.name, def.ports) != .center_tap) continue;
        const members = g.members(d);
        if (members.len != 3) return null;
        var named: [3]VertexId = undefined;
        for (def.ports, members) |name, vertex| {
            const i: usize = if (std.mem.eql(u8, name, "n1")) 0 else if (std.mem.eql(u8, name, "n2")) 1 else 2;
            named[i] = vertex;
        }
        if (!((named[0] == a[2] and named[1] == b[2]) or (named[1] == a[2] and named[0] == b[2]))) continue;
        if (coil != no_edge and coil != d) return null;
        coil = d;
        tap = named[2];
    }
    if (coil == no_edge) return null;
    const nets = [_]VertexId{ a[0], net, a[2], b[2], tap };
    for (nets, 0..) |v, i| {
        if (roles[v.index()].isRail()) return null;
        for (nets[i + 1 ..]) |other| if (v == other) return null;
    }
    if (a.len != 4 or b.len != 4 or a[3] != b[3] or roles[a[3].index()] != .sink) return null;
    for (qs) |d| if (!std.mem.eql(u8, nl.modelType(d) orelse return null, "npn")) return null;
    var taps: u2 = 0;
    var supplies: u2 = 0;
    for (rs) |d| {
        const p = g.members(d);
        const other = p[@intFromBool(p[0] == net)];
        taps += @intFromBool(other == tap);
        supplies += @intFromBool(roles[other.index()] == .supply);
    }
    if (taps != 1 or supplies != 1) return null;
    assert(coil != qs[0]);
    assert(coil != qs[1]);
    return .{ .devices = .{ qs[0], qs[1], coil, rs[0], rs[1] } };
}

fn base(c: *const Canvas, p: u32) ?Pt {
    const s = c.s;
    const d = s.pins.items(.device)[p];
    assert(d != sch.none);
    assert(s.pins.items(.index)[p] == 1);
    const info = s.devices.get(d);
    const class = s.lib.at(info.class);
    if (class.terminals.len < 3) return null;
    const node = s.deviceNode(d) orelse return null;
    const origin = Pt.round(s.xy[node]).sub(info.grid);
    var tips: [3]Pt = undefined;
    for (class.terminals[0..3], 0..) |t, i| {
        if (t.hidden or t.ground_ref) return null;
        tips[i] = origin.add(info.orient.apply(t.at));
    }
    const a, const gate, const b = .{ tips[0], tips[1], tips[2] };
    if (a.x != b.x or gate.x == a.x or gate.y <= @min(a.y, b.y) or gate.y >= @max(a.y, b.y)) return null;
    const side = class.side(1, info.orient) orelse return null;
    if (side != (if (gate.x < a.x) Side.left else Side.right) or s.pins.items(.side)[p] != side) return null;
    if (!gate.eql(canvas.pinAt(s, p))) return null;
    return gate;
}
