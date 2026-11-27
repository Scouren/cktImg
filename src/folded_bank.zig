//! Source-bound composition of a capacitively coupled transconductor and folded switching bank.
//!
//! Contents:
//! - `pub const Request`, `pub fn collect`, `pub fn arrange`
const std = @import("std");
const nlmod = @import("netlist.zig");
const regions = @import("source_regions.zig");
const lib = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const hints = @import("hints.zig");
const intent = @import("parent_intent.zig");
const Edge = nlmod.EdgeId;
const Net = nlmod.VertexId;

/// Two complementary input branches, four switches, the paired input and output
/// capacitors, both output loads and the three independently bound bias networks.
pub const Request = struct { devices: [19]u32 };

const empty = std.math.maxInt(u32);

/// Selects the full cell including both external output loads and the capacitor
/// across the two outputs. The source gate/drain roles choose the facing rows.
pub fn collect(a: std.mem.Allocator, raw: []const u8, nl: *const nlmod.Netlist) !?Request {
    const graph = &nl.graph;
    if (graph.edgeCount() != 19 or std.mem.count(nlmod.DeviceKind, graph.edges.items(.kind), &.{.mosfet}) != 8) return null;
    const inventory = try regions.collect(a, raw, nl);
    if (inventory.regions.len != 2) return null;
    var owner = Request{ .devices = @splat(empty) };
    var nodes: [2]Net = undefined;
    var upper: Net = undefined;
    var lower: Net = undefined;
    for (inventory.regions, 0..) |region, i| {
        if (region.disposition != .direct_source or region.members.len != 2) return null;
        const pins = graph.members(region.members[0]);
        nodes[i] = pins[2];
        if (formal(nl, nodes[i]) != null or graph.incident(nodes[i]).len != 4) return null;
        for (graph.incident(nodes[i])) |d| {
            const ps = graph.members(d);
            if (graph.edges.items(.kind)[d.index()] != .mosfet or ps.len != 4) return null;
            if (ps[2] == nodes[i]) continue;
            if (ps[0] != nodes[i] or ps[2] != ps[3] or formal(nl, ps[3]) == null) return null;
            const rail = lib.named(graph.vertices.items(.name)[ps[3].index()], .net);
            const model = nl.modelType(d) orelse return null;
            const p = std.mem.eql(u8, model, "pmos");
            if (!p and !std.mem.eql(u8, model, "nmos")) return null;
            if (rail != @as(@TypeOf(rail), if (p) .supply else .ground)) return null;
            const slot = i + @as(usize, @intFromBool(p)) * 2;
            if (owner.devices[slot] != empty) return null;
            owner.devices[slot] = d.index();
        }
        if (owner.devices[i] == empty or owner.devices[i + 2] == empty) return null;
    }
    const input0 = graph.members(Edge.from(owner.devices[0]));
    const input1 = graph.members(Edge.from(owner.devices[1]));
    const ord0 = formal(nl, input0[1]) orelse return null;
    const ord1 = formal(nl, input1[1]) orelse return null;
    if (ord0 == ord1) return null;
    if (ord0 > ord1) {
        std.mem.swap(Net, &nodes[0], &nodes[1]);
        std.mem.swap(u32, &owner.devices[0], &owner.devices[1]);
        std.mem.swap(u32, &owner.devices[2], &owner.devices[3]);
    }
    lower = graph.members(Edge.from(owner.devices[0]))[3];
    upper = graph.members(Edge.from(owner.devices[2]))[3];
    if (graph.members(Edge.from(owner.devices[1]))[3] != lower or graph.members(Edge.from(owner.devices[3]))[3] != upper) return null;
    if (!equal(nl, owner.devices[0], owner.devices[1]) or !equal(nl, owner.devices[2], owner.devices[3])) return null;
    var outs: [2]Net = undefined;
    var control: [2]Net = undefined;
    for (nodes, 0..) |node, i| {
        var switches: [2]u32 = undefined;
        var count: usize = 0;
        for (graph.incident(node)) |d| {
            const pins = graph.members(d);
            if (pins[2] != node) continue;
            if (count == 2 or pins[3] != lower or !std.mem.eql(u8, nl.modelType(d) orelse return null, "nmos") or formal(nl, pins[0]) == null or formal(nl, pins[1]) == null) return null;
            switches[count] = d.index();
            count += 1;
        }
        if (count != 2) return null;
        const x = graph.members(Edge.from(switches[0]));
        const y = graph.members(Edge.from(switches[1]));
        if (x[0] == y[0] or x[1] == y[1]) return null;
        const swap = formal(nl, x[0]).? > formal(nl, y[0]).?;
        const top = switches[@intFromBool(swap)];
        const bottom = switches[@intFromBool(!swap)];
        const ts = graph.members(Edge.from(top));
        const bs = graph.members(Edge.from(bottom));
        if (i == 0) {
            outs = .{ ts[0], bs[0] };
            control = .{ ts[1], bs[1] };
        } else if (outs[0] != ts[0] or outs[1] != bs[0] or control[0] != bs[1] or control[1] != ts[1]) return null;
        owner.devices[5 - i] = top;
        owner.devices[7 - i] = bottom;
    }
    for (owner.devices[4..8]) |d| if (!equal(nl, d, owner.devices[4])) return null;
    // Input capacitors join each PMOS gate to its branch's NMOS gate.
    // Each of the three matching gate pairs has its own resistor-fed bias formal.
    var bias: [3][2]Net = undefined;
    for (0..2) |side| {
        const ng = graph.members(Edge.from(owner.devices[side]))[1];
        const pg = graph.members(Edge.from(owner.devices[side + 2]))[1];
        if (formal(nl, pg) != null or graph.incident(ng).len != 3 or graph.incident(pg).len != 3 or graph.incident(control[side]).len != 3) return null;
        owner.devices[8 + side] = between(nl, .capacitor, ng, pg) orelse return null;
        for ([_]Net{ pg, ng, control[side] }, 0..) |gate, j| {
            const r = single(nl, gate, .resistor) orelse return null;
            const ps = graph.members(Edge.from(r));
            bias[j][side] = ps[@intFromBool(ps[0] == gate)];
            if (formal(nl, bias[j][side]) == null or graph.incident(bias[j][side]).len != 2) return null;
            owner.devices[13 + 2 * j + side] = r;
        }
        if (graph.incident(outs[side]).len != 4) return null;
        owner.devices[11 + side] = between(nl, .resistor, outs[side], upper) orelse return null;
    }
    owner.devices[10] = between(nl, .capacitor, outs[0], outs[1]) orelse return null;
    for (bias) |b| if (b[0] != b[1]) return null;
    if (bias[0][0] == bias[1][0] or bias[0][0] == bias[2][0] or bias[1][0] == bias[2][0]) return null;
    for ([_]usize{ 8, 11, 13, 15, 17 }) |d| if (!equal(nl, owner.devices[d], owner.devices[d + 1])) return null;
    for (owner.devices, 0..) |d, i| {
        if (d == empty or std.mem.indexOfScalar(u32, owner.devices[0..i], d) != null) return null;
        if (i >= 8 and (nl.params(Edge.from(d)).len != 1 or !(graph.edges.items(.value)[d] > 0) or !std.math.isFinite(graph.edges.items(.value)[d]))) return null;
    }
    return owner;
}

/// Sets the two output-facing rows and keeps the separate transconductor on
/// their left with its complementary inputs in two aligned columns.
pub fn arrange(nl: *const nlmod.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, at: [][2]f32, r: Request, verdicts: []const hints.Verdict) bool {
    const unit = s.lib.unit;
    if (at.len != 19 or (unit != 40 and unit != 60)) return false;
    for (r.devices, 0..) |d, i| {
        if (d >= at.len or !sk.drawn[d] or std.mem.indexOfScalar(u32, r.devices[0..i], d) != null) return false;
        const kind: nlmod.DeviceKind = if (i < 8) .mosfet else if (i < 11) .capacitor else .resistor;
        if (nl.graph.edges.items(.kind)[d] != kind or s.lib.at(s.devices.items(.class)[d]).terminals.len < (if (i < 8) @as(usize, 3) else 2)) return false;
    }
    for (nl.hints, verdicts) |h, v| if (intent.touches(nl, h, v, &r.devices, &.{})) return false;
    const sites = [19][2]i32{ .{ 3, 6 }, .{ 7, 6 }, .{ 3, 3 }, .{ 7, 3 }, .{ 14, 3 }, .{ 18, 3 }, .{ 14, 7 }, .{ 18, 7 }, .{ 1, 5 }, .{ 9, 5 }, .{ 22, 5 }, .{ 16, 0 }, .{ 16, 10 }, .{ 3, 0 }, .{ 7, 0 }, .{ 3, 10 }, .{ 7, 10 }, .{ 14, 12 }, .{ 18, 12 } };
    for (r.devices, sites, 0..) |d, site, i| {
        const class = s.lib.at(s.devices.items(.class)[d]);
        const other: usize = if (i < 8) 2 else 1;
        if (i == 10) {
            s.devices.items(.orientation)[d] = .vertical;
            sch.settleDevice(s, &nl.graph, d);
        }
        var relative = s.devices.items(.orient)[d].apply(class.terminals[other].at.sub(class.terminals[0].at));
        if (i < 13) {
            if (relative.x != 0 or @abs(relative.y) != unit) return false;
        } else if (relative.y != 0 or @abs(relative.x) != unit) return false;
        if (i < 8) {
            if ((relative.y < 0) != (i == 2 or i == 3 or i == 6 or i == 7)) {
                s.devices.items(.flip_y)[d] = !s.devices.items(.flip_y)[d];
                sch.settleDevice(s, &nl.graph, d);
            }
            relative = s.devices.items(.orient)[d].apply(class.terminals[1].at.sub(class.terminals[0].at));
            if ((relative.x < 0) != (i % 2 == 0)) {
                s.devices.items(.flip_x)[d] = !s.devices.items(.flip_x)[d];
                sch.settleDevice(s, &nl.graph, d);
            }
        }
        const info = s.devices.get(d);
        const sum = info.orient.apply(class.terminals[0].at.add(class.terminals[other].at));
        at[d] = (lib.Pt{ .x = site[0] * unit - @divFloor(sum.x, 2), .y = site[1] * unit - @divFloor(sum.y, 2) }).add(info.grid).toF();
    }
    for (r.devices, 0..) |d, i| {
        const box = s.boxAt(d, lib.Pt.round(at[d])).grow(2);
        for (r.devices[0..i]) |prev| if (box.intersects(s.boxAt(prev, lib.Pt.round(at[prev])))) return false;
    }
    return true;
}

// ---- private ----

fn formal(nl: *const nlmod.Netlist, n: Net) ?usize {
    const name = nl.graph.vertices.items(.name)[n.index()];
    return for (nl.defs[0].ports, 0..) |p, i| {
        if (std.mem.eql(u8, p, name)) break i;
    } else null;
}

fn single(nl: *const nlmod.Netlist, node: Net, kind: nlmod.DeviceKind) ?u32 {
    var found: ?u32 = null;
    for (nl.graph.incident(node)) |d| if (nl.graph.edges.items(.kind)[d.index()] == kind) {
        if (found != null) return null;
        found = d.index();
    };
    return found;
}

fn between(nl: *const nlmod.Netlist, kind: nlmod.DeviceKind, n: Net, m: Net) ?u32 {
    const d = single(nl, n, kind) orelse return null;
    const ps = nl.graph.members(Edge.from(d));
    return if ((ps[0] == n and ps[1] == m) or (ps[0] == m and ps[1] == n)) d else null;
}

fn equal(nl: *const nlmod.Netlist, a: u32, b: u32) bool {
    const x = nl.params(Edge.from(a));
    const y = nl.params(Edge.from(b));
    if (x.len != y.len) return false;
    for (x, y) |k, v| if (!std.mem.eql(u8, k, v)) return false;
    return true;
}
