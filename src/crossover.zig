//! Optional 45-degree feedback paths in a five-transistor differential pair with
//! reciprocal loads. The Manhattan router finishes first. Only these two complete
//! nets are replaced, using the integer pin tips, output ports and actual symbols.
//!
//! Contents:
//! - `pub const Pair`, `pub fn collect`, `pub fn apply`

const std = @import("std");
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const library = @import("library.zig");
const placed = @import("placed.zig");
const checks = @import("checks.zig");
const wire = @import("wire_geometry.zig");
const sch = @import("schematic.zig");
const Pt = library.Pt;
const Allocator = std.mem.Allocator;
const Edge = netlist.EdgeId;

/// Two load/input branches of one fully bound reciprocal stage in the original graph.
pub const Pair = struct {
    loads: [2]u32,
    inputs: [2]u32,
};
comptime {
    std.debug.assert(@sizeOf(Pair) == 16);
}

const Branch = struct {
    net: u32,
    gate_device: usize,
    load_device: usize,
    input_device: usize,
    port_device: usize,
    gate: Pt,
    input: Pt,
    drain: Pt,
    port: Pt,
    stub: Pt,
    foot: Pt,
};

/// Selects a complete five-MOS graph, including ordered body, gate, drain and
/// source roles, equal device contracts on each paired branch and no spare incidence.
pub fn collect(nl: *const netlist.Netlist, roles: []const sch.Role) ?Pair {
    const g = nl.graph;
    if (g.edgeCount() != 5) return null;
    var rq: Pair = undefined;
    var count: usize = 0;
    for (g.edges.items(.kind), 0..) |kind, i| {
        if (kind != .mosfet) return null;
        const p = g.members(Edge.from(i));
        if (p.len != 4 or device.polarity(nl.modelType(Edge.from(i))) == .other) return null;
        if (p[2] != p[3] or !roles[p[2].index()].isRail() or roles[p[0].index()] != .output or roles[p[1].index()] != .output) continue;
        if (count == 2) return null;
        rq.loads[count] = @intCast(i);
        count += 1;
    }
    if (count != 2 or !equalModel(nl, rq.loads)) return null;
    const left = g.members(Edge.from(rq.loads[0]));
    const right = g.members(Edge.from(rq.loads[1]));
    if (left[0] == left[1] or left[0] != right[1] or right[0] != left[1] or left[2] != right[2]) return null;
    var tail_source: ?netlist.VertexId = null;
    var input_gates: [2]netlist.VertexId = undefined;
    for (rq.loads, 0..) |load, k| {
        const drain = g.members(Edge.from(load))[0];
        if (g.incident(drain).len != 3) return null;
        const input = for (g.incident(drain)) |e| {
            if (e.index() != load and e.index() != rq.loads[1 - k]) break e;
        } else return null;
        const p = g.members(input);
        if (p[0] != drain or roles[p[1].index()] != .input or !roles[p[3].index()].isRail() or roles[p[2].index()] != .internal) return null;
        if (p[3] == left[2] or device.polarity(nl.modelType(input)) == device.polarity(nl.modelType(Edge.from(load)))) return null;
        if (tail_source) |n| if (n != p[2]) return null;
        tail_source = p[2];
        rq.inputs[k] = input.index();
        input_gates[k] = p[1];
    }
    if (input_gates[0] == input_gates[1] or !equalModel(nl, rq.inputs)) return null;
    const tail = for (0..5) |i| {
        if (std.mem.indexOfScalar(u32, &rq.loads, @intCast(i)) == null and std.mem.indexOfScalar(u32, &rq.inputs, @intCast(i)) == null) break Edge.from(i);
    } else return null;
    const tp = g.members(tail);
    const body = g.members(Edge.from(rq.inputs[0]))[3];
    if (tp[0] != tail_source.? or tp[2] != body or tp[3] != body or g.incident(tp[0]).len != 3 or
        device.polarity(nl.modelType(tail)) != device.polarity(nl.modelType(Edge.from(rq.inputs[0]))) or
        (roles[tp[1].index()] != .bias and roles[tp[1].index()] != .input) or g.incident(tp[1]).len != 1) return null;
    return rq;
}

/// Trials both new paths together. Every array installed in the result belongs
/// to its arena. A decline retains all old wires, terminal names and junctions.
pub fn apply(gpa: Allocator, lib: *const library.Library, p: *placed.Placed, nl: *const netlist.Netlist, pair: Pair) Allocator.Error!bool {
    // Existing steering governs routing/positioning; these small stages have a
    // complete ordinary candidate even when no angle can be drawn.
    var scratch = std.heap.ArenaAllocator.init(gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    const roles = try sch.guessRoles(a, nl);
    if (@import("parent_intent.zig").needsDrawing(nl)) {
        const st = try sch.structure.analyze(a, a, nl, roles);
        const sk = try sch.skeleton.place(a, a, nl, roles, &st, .{});
        const verdicts = try @import("report.zig").verdicts(a, nl, roles, &st, &sk, p, lib);
        const nets = [2]u32{ nl.graph.members(.from(pair.loads[0]))[0].index(), nl.graph.members(.from(pair.loads[1]))[0].index() };
        for (nl.hints, verdicts) |h, v| switch (h.verb) {
            .off, .symmetry_off, .wire, .label, .port, .via, .route, .first => if (@import("parent_intent.zig").touches(nl, h, v, &.{}, &nets)) return false,
            else => {},
        };
    }
    var branches: [2]Branch = undefined;
    for (pair.inputs, 0..) |idx, k| {
        const gate_dev = checks.deviceIn(p, nl.graph.edges.items(.name)[pair.loads[1 - k]]) orelse return false;
        const input_dev = checks.deviceIn(p, nl.graph.edges.items(.name)[idx]) orelse return false;
        const load_dev = checks.deviceIn(p, nl.graph.edges.items(.name)[pair.loads[k]]) orelse return false;
        if (!lib.at(p.dev_class[input_dev]).shows(0) or !lib.at(p.dev_class[load_dev]).shows(0)) return false;
        const gp = p.dev_pin0[gate_dev] + 1;
        const net = p.pin_net[gp];
        if (p.pin_net[p.dev_pin0[input_dev]] != net or p.pin_net[p.dev_pin0[load_dev]] != net) return false;
        const gate = p.pin_xy[gp];
        const drain = p.pin_xy[p.dev_pin0[load_dev]];
        const input = p.pin_xy[p.dev_pin0[input_dev]];
        if (drain.x != input.x or drain.x == gate.x) return false;
        var port: ?usize = null;
        for (p.dev_name, 0..) |name, d| {
            if (name.len != 0 or p.pin_net[p.dev_pin0[d]] != net) continue;
            if (lib.at(p.dev_class[d]).role != .output_port or port != null) return false;
            port = d;
        }
        const port_dev = port orelse return false;
        if (!lib.at(p.dev_class[port_dev]).shows(0)) return false;
        const term = p.pin_xy[p.dev_pin0[port_dev]];
        if (term.y <= @min(drain.y, input.y) or term.y >= @max(drain.y, input.y)) return false;
        const sign = std.math.sign(@as(i64, drain.x) - gate.x);
        const side = lib.at(p.dev_class[gate_dev]).side(1, p.dev_orient[gate_dev]) orelse return false;
        if (side != (if (sign > 0) library.Side.right else library.Side.left)) return false;
        const head = @as(i64, gate.x) + sign * @divFloor(lib.unit, 4);
        if (lib.unit < 4 or head <= @min(drain.x, gate.x) or head >= @max(drain.x, gate.x)) return false;
        branches[k] = .{ .net = net, .gate_device = gate_dev, .input_device = input_dev, .load_device = load_dev, .port_device = port_dev, .gate = gate, .drain = drain, .input = input, .port = term, .stub = .{ .x = @intCast(head), .y = gate.y }, .foot = undefined };
    }
    if (branches[0].gate.y != branches[1].gate.y or branches[0].drain.y != branches[1].drain.y or branches[0].input.y != branches[1].input.y) return false;
    const y = branches[0].gate.y;
    const sy = std.math.sign(@as(i64, branches[0].input.y) - y);
    const reach = @min(sy * (@as(i64, branches[0].port.y) - y), sy * (@as(i64, branches[1].port.y) - y)) - @divFloor(lib.unit, 4);
    const join_y = @as(i64, y) + sy * reach;
    if (reach < @divFloor(lib.unit, 2) or sy * (join_y - branches[0].drain.y) <= 0) return false;
    for (&branches) |*branch| {
        const sx = std.math.sign(@as(i64, branch.drain.x) - branch.gate.x);
        const end = @as(i64, branch.stub.x) + sx * reach;
        if (end <= @min(branch.drain.x, branch.gate.x) or end >= @max(branch.drain.x, branch.gate.x) or branch.port.x == branch.drain.x) return false;
        branch.foot = .{ .x = @intCast(end), .y = @intCast(join_y) };
    }
    const one, const two = branches;
    const crossing = wire.properCross(one.stub, one.foot, two.stub, two.foot) orelse return false;
    for (branches) |branch| {
        for (0..p.deviceCount()) |d| {
            const box = p.deviceRect(lib, d);
            if (wire.hitsRect(branch.stub, branch.foot, box) or wire.hitsRect(branch.foot, .{ .x = branch.drain.x, .y = branch.foot.y }, box)) return false;
            if (d != branch.gate_device and wire.hitsRect(branch.gate, branch.stub, box)) return false;
            if (d != branch.input_device and d != branch.load_device and wire.hitsRect(branch.drain, branch.input, box)) return false;
            if (d != branch.port_device and wire.hitsRect(.{ .x = branch.drain.x, .y = branch.port.y }, branch.port, box)) return false;
        }
        for (p.labels) |label| if (label.net == branch.net) return false;
    }
    var points: std.ArrayList(Pt) = .empty;
    var offsets: std.ArrayList(u32) = .empty;
    var ranges: std.ArrayList(u32) = .empty;
    var junctions: std.ArrayList(Pt) = .empty;
    try offsets.append(a, 0);
    for (p.junctions) |j| if (checks.wireRays(p, one.net, j) == 0 and checks.wireRays(p, two.net, j) == 0) try junctions.append(a, j);
    for (0..p.netCount()) |n| {
        try ranges.append(a, @intCast(offsets.items.len - 1));
        if (n != one.net and n != two.net) {
            var it = p.segments(n);
            while (it.next()) |poly| {
                for (poly[0 .. poly.len - 1], poly[1..]) |s, t| {
                    if (crossing.onSegment(s, t)) return false;
                }
                try append(a, &points, &offsets, poly);
            }
            continue;
        }
        const branch = if (n == one.net) one else two;
        const joint: Pt = .{ .x = branch.drain.x, .y = branch.foot.y };
        const port_joint: Pt = .{ .x = branch.drain.x, .y = branch.port.y };
        try append(a, &points, &offsets, &.{ branch.drain, joint });
        try append(a, &points, &offsets, &.{ joint, port_joint });
        try append(a, &points, &offsets, &.{ port_joint, branch.input });
        try append(a, &points, &offsets, &.{ branch.gate, branch.stub, branch.foot, joint });
        try append(a, &points, &offsets, &.{ port_joint, branch.port });
        try junctions.appendSlice(a, &.{ joint, port_joint });
    }
    try ranges.append(a, @intCast(offsets.items.len - 1));
    var trial = p.*;
    trial.net_seg = ranges.items;
    trial.seg_pt = offsets.items;
    trial.wire_pts = points.items;
    trial.junctions = junctions.items;
    var issues: std.ArrayList(checks.Finding) = .empty;
    try checks.find(a, &issues, &trial, lib);
    if (issues.items.len != 0) return false;
    const out = p.arena.allocator();
    const output_ranges = try out.dupe(u32, ranges.items);
    const output_offsets = try out.dupe(u32, offsets.items);
    const output_points = try out.dupe(Pt, points.items);
    const output_junctions = try out.dupe(Pt, junctions.items);
    p.net_seg = output_ranges;
    p.seg_pt = output_offsets;
    p.wire_pts = output_points;
    p.junctions = output_junctions;
    return true;
}

// ---- private ----

fn append(a: Allocator, points: *std.ArrayList(Pt), offsets: *std.ArrayList(u32), poly: []const Pt) !void {
    try points.appendSlice(a, poly);
    try offsets.append(a, @intCast(points.items.len));
}

fn equalModel(nl: *const netlist.Netlist, pair: [2]u32) bool {
    const a = nl.params(Edge.from(pair[0]));
    const b = nl.params(Edge.from(pair[1]));
    if (a.len != b.len or a.len == 0) return false;
    for (a, b) |x, y| if (!std.mem.eql(u8, x, y)) return false;
    return true;
}
