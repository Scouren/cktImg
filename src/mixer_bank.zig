//! A degenerated input stage driving two interleaved switch-source pairs.
//!
//! Contents:
//! - `pub const Request`, `pub fn collect`, `pub fn arrange`
const std = @import("std");
const netlist = @import("netlist.zig");
const regions = @import("source_regions.zig");
const lib = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const hints = @import("hints.zig");
const intent = @import("parent_intent.zig");
const Edge = netlist.EdgeId;
const Net = netlist.VertexId;

/// Two inputs, their bias sources, the source bridge, four ordered switches,
/// two sinks, and one resistor/inductor pair for each distinct output.
pub const Request = struct { devices: [15]u32 };

/// Accepts one complete selected cell. Formal order only resolves the two
/// interchangeable sides after every source, gate and load has been bound.
pub fn collect(a: std.mem.Allocator, raw: []const u8, nl: *const netlist.Netlist) !?Request {
    const graph = &nl.graph;
    if (graph.edgeCount() != 15 or std.mem.count(netlist.DeviceKind, graph.edges.items(.kind), &.{.mosfet}) != 6) return null;
    const inventory = try regions.collect(a, raw, nl);
    if (inventory.regions.len != 3) return null;
    const input = for (inventory.regions) |r| {
        if (r.disposition == .paired_rail_sources) break r;
    } else return null;
    var rq: Request = .{ .devices = @splat(std.math.maxInt(u32)) };
    const u = graph.members(input.members[0]);
    const v = graph.members(input.members[1]);
    const supply = u[3];
    if (role(nl, supply) != .supply or formal(nl, supply) == null or !positive(nl, input.owned[2])) return null;
    // The first declared input controls the inner source pair. Either complete
    // mirror is electrically equivalent. Card ordering does not choose the side.
    const first = (formal(nl, u[1]) orelse return null) < (formal(nl, v[1]) orelse return null);
    rq.devices[4] = input.owned[2].index();
    var return_rail: ?Net = null;
    var gate0: ?Net = null;
    var gate1: ?Net = null;
    for (input.members, 0..) |m, index| {
        const i: usize = @intFromBool((index == 0) != first);
        const ps = graph.members(m);
        if (graph.incident(ps[1]).len != 1 or graph.incident(ps[0]).len != 4 or formal(nl, ps[0]) != null) return null;
        rq.devices[i] = m.index();
        rq.devices[2 + i] = input.owned[3 + index].index();
        var switches: [2]Edge = undefined;
        var found: usize = 0;
        for (graph.incident(ps[0])) |d| {
            const pins = graph.members(d);
            if (d == m) continue;
            switch (graph.edges.items(.kind)[d.index()]) {
                .mosfet => {
                    if (found == 2 or pins.len != 4 or pins[2] != ps[0] or role(nl, pins[3]) != .ground or formal(nl, pins[3]) == null or !std.mem.eql(u8, nl.modelType(d) orelse return null, "nmos")) return null;
                    if (return_rail != null and return_rail != pins[3]) return null;
                    return_rail = pins[3];
                    switches[found] = d;
                    found += 1;
                },
                .isource => {
                    if (rq.devices[9 + i] != std.math.maxInt(u32) or pins[0] != ps[0] or role(nl, pins[1]) != .ground or !equal(nl, d, input.owned[3])) return null;
                    rq.devices[9 + i] = d.index();
                },
                else => return null,
            }
        }
        if (found != 2 or rq.devices[9 + i] == std.math.maxInt(u32) or graph.members(Edge.from(rq.devices[9 + i]))[1] != return_rail.?) return null;
        const gx = graph.members(switches[0])[1];
        const gy = graph.members(switches[1])[1];
        if (gx == gy or graph.incident(gx).len != 2 or graph.incident(gy).len != 2) return null;
        const in_order = (formal(nl, gx) orelse return null) < (formal(nl, gy) orelse return null);
        const left = switches[@intFromBool(!in_order)];
        const right = switches[@intFromBool(in_order)];
        const gl = graph.members(left)[1];
        const gr = graph.members(right)[1];
        if (gate0 != null and (gate0 != gl or gate1 != gr)) return null;
        gate0 = gl;
        gate1 = gr;
        rq.devices[6 - i] = left.index();
        rq.devices[7 + i] = right.index();
    }
    const sw = rq.devices[5..9];
    for (sw) |id| if (!equal(nl, Edge.from(sw[0]), Edge.from(id))) return null;
    const out0 = graph.members(Edge.from(sw[0]))[0];
    const out1 = graph.members(Edge.from(sw[1]))[0];
    if (out0 == out1 or graph.members(Edge.from(sw[2]))[0] != out0 or graph.members(Edge.from(sw[3]))[0] != out1) return null;
    for ([_]Net{ out0, out1 }, 0..) |node, i| {
        if (formal(nl, node) == null or role(nl, node) == .ground or role(nl, node) == .supply or graph.incident(node).len != 4) return null;
        for (graph.incident(node)) |d| {
            const k = graph.edges.items(.kind)[d.index()];
            if (k == .mosfet) continue;
            if (k != .resistor and k != .inductor) return null;
            const pins = graph.members(d);
            if (pins[0] != supply or pins[1] != node or !positive(nl, d)) return null;
            const slot = 11 + 2 * i + @as(usize, @intFromBool(k == .inductor));
            if (rq.devices[slot] != std.math.maxInt(u32)) return null;
            rq.devices[slot] = d.index();
        }
    }
    if (std.mem.indexOfScalar(u32, &rq.devices, std.math.maxInt(u32)) != null) return null;
    for (11..13) |k| if (!equal(nl, Edge.from(rq.devices[k]), Edge.from(rq.devices[k + 2]))) return null;
    return rq;
}

/// Uses the selected physical terminal centers. Two inner switches have the
/// same source, while the complementary pair occupies the two outer columns.
pub fn arrange(nl: *const netlist.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, at: [][2]f32, rq: Request, verdicts: []const hints.Verdict) bool {
    const unit = s.lib.unit;
    if (at.len != 15 or (unit != 40 and unit != 60)) return false;
    for (rq.devices, 0..) |d, i| {
        if (d >= at.len or !sk.drawn[d] or std.mem.indexOfScalar(u32, rq.devices[0..i], d) != null) return false;
        const kind = nl.graph.edges.items(.kind)[d];
        const want: netlist.DeviceKind = switch (i) {
            0, 1, 5...8 => .mosfet,
            2, 3, 9, 10 => .isource,
            4, 11, 13 => .resistor,
            else => .inductor,
        };
        if (kind != want or s.lib.at(s.devices.items(.class)[d]).terminals.len < (if (want == .mosfet) @as(usize, 3) else 2)) return false;
    }
    for (nl.hints, verdicts) |h, v| if (intent.touches(nl, h, v, &rq.devices, &.{})) return false;
    // Centers in selected-symbol units. The two sources straddle the horizontal
    // input bridge. The two RL loads and sinks bracket the switching bank.
    const sites = [15][2]i32{
        .{ 1, 3 },  .{ 5, 3 },  .{ 1, 0 },  .{ 5, 0 },  .{ 3, 2 },
        .{ 10, 5 }, .{ 13, 5 }, .{ 17, 5 }, .{ 20, 5 }, .{ 13, 9 },
        .{ 20, 9 }, .{ 9, 0 },  .{ 11, 0 }, .{ 19, 0 }, .{ 21, 0 },
    };
    for (rq.devices, sites, 0..) |d, site, i| {
        const ic = s.lib.at(s.devices.items(.class)[d]);
        const mos = i < 2 or (i >= 5 and i <= 8);
        const other: usize = if (mos) 2 else 1;
        const delta = s.devices.items(.orient)[d].apply(ic.terminals[other].at.sub(ic.terminals[0].at));
        if (i == 4) {
            if (delta.y != 0 or @abs(delta.x) != unit) return false;
        } else if (delta.x != 0 or @abs(delta.y) != unit) return false;
        if (mos) {
            if ((i < 2) != (delta.y < 0)) return false;
            const left = i == 0 or i == 5 or i == 6;
            const gate = s.devices.items(.orient)[d].apply(ic.terminals[1].at.sub(ic.terminals[0].at));
            if ((gate.x < 0) != left) {
                s.devices.items(.flip_x)[d] = !s.devices.items(.flip_x)[d];
                sch.settleDevice(s, &nl.graph, d);
            }
        }
        const info = s.devices.get(d);
        const sum = info.orient.apply(ic.terminals[0].at.add(ic.terminals[other].at));
        at[d] = (lib.Pt{ .x = site[0] * unit - @divFloor(sum.x, 2), .y = site[1] * unit - @divFloor(sum.y, 2) }).add(info.grid).toF();
    }
    for (rq.devices, 0..) |d, i| {
        const box = s.boxAt(d, lib.Pt.round(at[d])).grow(2);
        for (rq.devices[0..i]) |other| if (box.intersects(s.boxAt(other, lib.Pt.round(at[other])))) return false;
    }
    return true;
}

// ---- private ----

fn formal(nl: *const netlist.Netlist, n: Net) ?usize {
    const name = nl.graph.vertices.items(.name)[n.index()];
    for (nl.defs[0].ports, 0..) |p, i| if (std.mem.eql(u8, p, name)) return i;
    return null;
}

fn role(nl: *const netlist.Netlist, n: Net) @TypeOf(lib.named("", .net)) {
    return lib.named(nl.graph.vertices.items(.name)[n.index()], .net);
}

fn equal(nl: *const netlist.Netlist, a: Edge, b: Edge) bool {
    const x = nl.params(a);
    const y = nl.params(b);
    if (x.len != y.len) return false;
    for (x, y) |k, v| if (!std.mem.eql(u8, k, v)) return false;
    return true;
}

fn positive(nl: *const netlist.Netlist, d: Edge) bool {
    const v = nl.graph.edges.items(.value)[d.index()];
    return nl.params(d).len == 1 and v > 0 and std.math.isFinite(v);
}
