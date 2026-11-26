//! Relative geometry of an equal-arm source-degenerated input pair with mirrored resistive loads.
//!
//! Contents:
//! - `pub const Request`
//! - `pub fn fromSource(a: std.mem.Allocator, raw: []const u8, nl: *const netlist.Netlist) !?Request`
//! - `pub fn arrange(nl: *const netlist.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, at: [][2]f32, rq: Request, verdicts: []const hints.Verdict) bool`
//! - `pub fn intact(p: *const placed.Placed, nl: *const netlist.Netlist, rq: Request, unit: i32) bool`
const std = @import("std");
const checks = @import("checks.zig");
const placed = @import("placed.zig");
const netlist = @import("netlist.zig");
const regions = @import("source_regions.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const lib = @import("library.zig");
const hints = @import("hints.zig");
const intent = @import("parent_intent.zig");

/// Input A/B, their arms, shared tail, and their loads; all seven original devices.
pub const Request = struct { devices: [7]u32 };

/// Selects the complete two-branch circuit. Its independently certified
/// source owner supplies the equal resistors and private tail drain.
pub fn fromSource(a: std.mem.Allocator, raw: []const u8, nl: *const netlist.Netlist) !?Request {
    const graph = &nl.graph;
    if (graph.edgeCount() != 7 or std.mem.count(netlist.DeviceKind, graph.edges.items(.kind), &.{.resistor}) != 4) return null;
    const evidence = try regions.collect(a, raw, nl);
    if (evidence.regions.len != 1) return null;
    const row = evidence.regions[0];
    if (row.disposition != .equal_arms_tail) return null;
    const tail = row.owned[4];
    const tail_pins = graph.members(tail);
    if (graph.incident(tail_pins[1]).len != 1) return null;
    for (graph.edges.items(.kind), graph.edges.items(.value)) |kind, resistance| {
        if (kind == .resistor and (!(resistance > 0) or !std.math.isFinite(resistance))) return null;
    }
    var result: Request = .{ .devices = undefined };
    result.devices[4] = tail.index();
    var supply: ?netlist.VertexId = null;
    var load_value: ?[]const u8 = null;
    for (row.members, 0..) |input, i| {
        const pins = graph.members(input);
        if (graph.incident(pins[0]).len != 2 or graph.incident(pins[1]).len != 1 or pins[0] == pins[1] or pins[1] == tail_pins[1]) return null;
        // The complementary rail, each output, both input gates and tail
        // bias are actual selected-cell formals.
        for ([_]netlist.VertexId{ pins[0], pins[1], tail_pins[1], pins[3] }) |n| if (!isFormal(nl, n)) return null;
        const arm = row.owned[2 + i];
        result.devices[i] = input.index();
        result.devices[2 + i] = arm.index();
        const load = for (graph.incident(pins[0])) |other| {
            if (other != input) break other;
        } else return null;
        if (graph.edges.items(.kind)[load.index()] != .resistor or nl.params(load).len != 1) return null;
        const lp = graph.members(load);
        const far = lp[@intFromBool(lp[0] == pins[0])];
        const role = lib.named(graph.vertices.items(.name)[far.index()], .net);
        const body = lib.named(graph.vertices.items(.name)[pins[3].index()], .net);
        if ((body == .ground and role != .supply) or (body == .supply and role != .ground) or !isFormal(nl, far)) return null;
        if (supply != null and supply != far) return null;
        if (load_value) |v| if (!std.mem.eql(u8, v, nl.params(load)[0])) return null;
        supply = far;
        load_value = nl.params(load)[0];
        result.devices[5 + i] = load.index();
    }
    return result;
}

/// Draws two ordered resistor arms inward from the input branches to a
/// centered tail. Offsets leave room for the actual symbol's horizontal
/// outer lead; the resulting branches can turn once at each source.
pub fn arrange(nl: *const netlist.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, at: [][2]f32, rq: Request, verdicts: []const hints.Verdict) bool {
    const unit = s.lib.unit;
    if ((unit != 40 and unit != 60) or at.len != 7) return false;
    for (rq.devices, 0..) |id, slot| {
        if (id >= at.len or !sk.drawn[id] or std.mem.indexOfScalar(u32, rq.devices[0..slot], id) != null) return false;
        const kind = nl.graph.edges.items(.kind)[id];
        const count = s.lib.at(s.devices.items(.class)[id]).terminals.len;
        if (slot < 2 or slot == 4) {
            if (kind != .mosfet or count < 3) return false;
        } else if (kind != .resistor or count != 2) return false;
    }
    for (nl.hints, verdicts) |h, v| if (intent.touches(nl, h, v, &rq.devices, &.{})) return false;
    const tail = rq.devices[4];
    const tail_source = nl.graph.members(netlist.EdgeId.from(tail))[2];
    const nmos = lib.named(nl.graph.vertices.items(.name)[tail_source.index()], .net) == .ground;
    const sign: i32 = if (nmos) 1 else -1;
    const a = center(s, rq.devices[0], lib.Pt.round(at[rq.devices[0]]), 2);
    const b = center(s, rq.devices[1], lib.Pt.round(at[rq.devices[1]]), 2);
    if (a.y != b.y or a.x == b.x) return false;
    const x = @divFloor(a.x + b.x, 2);
    const half: i32 = @divExact(unit, 2);
    for (rq.devices[0..2], 0..) |input, i| {
        const direction: i32 = if ((i == 0) == (a.x < b.x)) -1 else 1;
        const arm = rq.devices[2 + i];
        const load = rq.devices[5 + i];
        const ic = s.lib.at(s.devices.items(.class)[input]);
        const tc = s.lib.at(s.devices.items(.class)[tail]);
        const rc = s.lib.at(s.devices.items(.class)[arm]);
        const lc = s.lib.at(s.devices.items(.class)[load]);
        if (ic.terminals.len < 3 or tc.terminals.len < 3 or rc.terminals.len != 2 or lc.terminals.len != 2) return false;
        for ([_]u32{ input, tail }) |d| {
            const info = s.devices.get(d);
            const cl = s.lib.at(info.class);
            const ds = info.orient.apply(cl.terminals[2].at.sub(cl.terminals[0].at));
            if (ds.x != 0 or ds.y != unit * sign) return false;
        }
        const left = center(s, load, lib.Pt.round(at[load]), 1);
        const li = s.devices.get(load);
        const lspan = li.orient.apply(lc.terminals[0].at.sub(lc.terminals[1].at));
        if (lspan.x != 0 or @abs(lspan.y) != unit or (a.y - left.y) * sign <= unit) return false;
        const arm_pins = nl.graph.members(netlist.EdgeId.from(arm));
        const source = nl.graph.members(netlist.EdgeId.from(input))[2];
        const outer: usize = @intFromBool(arm_pins[0] != source);
        if (arm_pins[outer] != source or arm_pins[1 - outer] != nl.graph.members(netlist.EdgeId.from(tail))[0]) return false;
        const dx = rc.terminals[outer].at.x - rc.terminals[1 - outer].at.x;
        if (@abs(dx) != unit or rc.terminals[0].at.y != rc.terminals[1].at.y) return false;
        s.devices.items(.orientation)[arm] = .horizontal;
        s.devices.items(.flip_x)[arm] = direction * dx < 0;
        s.devices.items(.flip_y)[arm] = false;
        sch.settleDevice(s, &nl.graph, arm);
        const col = x + direction * 2 * unit;
        at[input] = (lib.Pt{ .x = col, .y = a.y }).sub(center(s, input, .zero, 2)).toF();
        at[load] = (lib.Pt{ .x = col, .y = left.y }).sub(center(s, load, .zero, 1)).toF();
        at[arm] = (lib.Pt{ .x = x + direction * unit, .y = a.y + sign * (unit + half) }).sub(center(s, arm, .zero, 1)).toF();
    }
    at[tail] = (lib.Pt{ .x = x, .y = a.y + sign * (3 * unit + half) }).sub(center(s, tail, .zero, 2)).toF();
    for (rq.devices, 0..) |id, i| {
        const box = s.boxAt(id, lib.Pt.round(at[id])).grow(2);
        for (rq.devices[0..i]) |other| if (box.intersects(s.boxAt(other, lib.Pt.round(at[other])))) return false;
    }
    return true;
}

/// The direct source approaches and three-way tail connection must be visible
/// in the final route. Every unit edge below is on the correct actual net.
pub fn intact(p: *const placed.Placed, nl: *const netlist.Netlist, rq: Request, unit: i32) bool {
    if (unit != 40 and unit != 60) return false;
    var ids: [7]usize = undefined;
    for (rq.devices, &ids, 0..) |raw, *d, slot| {
        if (raw >= nl.graph.edgeCount()) return false;
        d.* = checks.deviceIn(p, nl.graph.edges.items(.name)[raw]) orelse return false;
        const lo, const hi = p.pinRange(d.*);
        if (hi - lo < (if (slot < 2 or slot == 4) @as(u32, 3) else @as(u32, 2))) return false;
    }
    const tail = p.dev_pin0[ids[4]];
    const center_net = p.pin_net[tail];
    const tail_pin = p.pin_xy[tail];
    for (ids[0..2], 0..) |input, i| {
        const source = p.dev_pin0[input] + 2;
        const arm = p.dev_pin0[ids[2 + i]];
        const from = p.pin_net[source];
        const swap = p.pin_net[arm] != from;
        const outer = arm + @as(u32, @intFromBool(swap));
        const inner = arm + @as(u32, @intFromBool(!swap));
        if (p.pin_net[outer] != from or p.pin_net[inner] != center_net) return false;
        const local = p.pin_xy[outer];
        const corner = lib.Pt{ .x = p.pin_xy[source].x, .y = local.y };
        const tee = lib.Pt{ .x = tail_pin.x, .y = local.y };
        if (!onWire(p, from, p.pin_xy[source], corner, unit) or !onWire(p, from, corner, local, unit)) return false;
        if (!onWire(p, center_net, p.pin_xy[inner], tee, unit) or !onWire(p, center_net, tee, tail_pin, unit)) return false;
        if (@popCount(checks.ways(p, center_net, tee)) != 3) return false;
    }
    return true;
}

// ---- private ----

fn onWire(p: *const placed.Placed, n: u32, a: lib.Pt, b: lib.Pt, unit: i32) bool {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    if ((dx != 0 and dy != 0) or (dx == 0 and dy == 0)) return false;
    const length = @max(@abs(dx), @abs(dy));
    if (length > 4 * @as(u32, @intCast(unit))) return false;
    const bit: u4 = if (dx < 0) 1 else if (dx > 0) 2 else if (dy < 0) 4 else 8;
    const step = lib.Pt{ .x = std.math.sign(dx), .y = std.math.sign(dy) };
    var cursor = a;
    for (0..length) |_| {
        if (checks.ways(p, n, cursor) & bit == 0) return false;
        cursor = cursor.add(step);
    }
    return true;
}

fn center(s: *const sch.Schematic, dev: u32, at: lib.Pt, other: usize) lib.Pt {
    const info = s.devices.get(dev);
    const cl = s.lib.at(info.class);
    const both = info.orient.apply(cl.terminals[0].at.add(cl.terminals[other].at));
    return at.sub(info.grid).add(.{ .x = @divFloor(both.x, 2), .y = @divFloor(both.y, 2) });
}

fn isFormal(nl: *const netlist.Netlist, n: netlist.VertexId) bool {
    const name = nl.graph.vertices.items(.name)[n.index()];
    for (nl.defs[0].ports) |p| if (std.mem.eql(u8, p, name)) return true;
    return false;
}
