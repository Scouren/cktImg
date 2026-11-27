//! Successful closed load stages -> checked actual four-terminal trees.
//!
//! Human Rules:
//! - resistor_load_wires.1 (bounded observation) All three certified source
//!   stages put the horizontal load bar through both resistor tips, with
//!   a drain branch and outward gate branch. This specific tip turn differs
//!   from generic trunk.13. Source: docs/research/resistor-load-stages.md.
//! - resistor_load_wires.2 (invariant) Consume successful six-device owners,
//!   never infer ownership from four points. Require every declared pin to
//!   equal its transformed actual lead; hidden, projected or extra pins
//!   abstain. Keep all ordinary Canvas body/contact/crossing rules.
//! - resistor_load_wires.3 (boundary) Explicit sequencing, styles and ports
//!   win. Only a current automatic internal net is seeded after rails.
//!   Later thinning remains ordinary: cut/label rounds do not seed it.
//!   Commit the entire tree or restore every earlier route/point/segment;
//!   mark drawn only after success. No terminal-list or mate-table edits.
//! - resistor_load_wires.4 (bounded observation) The linked twelve-member
//!   source has two complete three-terminal output trees. Keep each local
//!   resistor-to-drain interval whole; branch on distinct interior rows.
//!   Approach the inward gate directly and the outward gate below both
//!   complete bodies. Both trees commit together under normal Canvas rules.
//!   This one candidate requires the observed actual frame; no wire budget
//!   exemption or universal spacing claim follows from it.
//! - resistor_load_wires.5 (choice) Keep the outer branch's column strictly
//!   before the inward branch. Move its lower row past every actual body
//!   intersecting that row, scanning all bodies before each update so their
//!   enumeration order changes nothing. At most one increase per body is
//!   possible. Foreign wires, points and vertical obstructions still decline
//!   the whole pair; the ordinary crossing budget remains unchanged.
//!
//! Data: borrowed successful 24/48-byte owners and per-net tables, consumed
//! once per wiring pass. At most six u32 pin handles, six points, two owner
//! rectangles and four Lines are bounded stack scratch. Canvas owns all
//! output allocations; no retained graph,
//! new hot struct, per-net scan, allocation table or speed claim.
//!
//! Contents: seed; private exact-pin mapping and one candidate transaction.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const canvas = @import("canvas.zig");
const loads = @import("resistor_loads.zig");
const netlines = @import("netlines.zig");
const Pt = library.Pt;
const Group = loads.Group;
const Canvas = canvas.Canvas;

/// Seeds successful placement owners in their existing canonical order.
/// All per-net slices span the schematic. The caller owns every slice;
/// only drawn entries whose complete trees commit become true. An error
/// restores the current tree, retaining earlier successfully drawn nets.
/// These are placement-certified requests, not arbitrary handle tuples.
pub fn seed(c: *Canvas, nl: *const netlist.Netlist, singles: []const Group, pairs: []const loads.Pair, lines: *const netlines.NetLines, pins_of: []const std.ArrayList(u32), routed: []const bool, drawn: []bool) Allocator.Error!void {
    assert(pins_of.len == c.s.net_name.len and lines.style.len == pins_of.len);
    assert(routed.len == pins_of.len and drawn.len == pins_of.len);
    if (lines.first.len != 0) return;
    for (singles) |group| try one(c, nl, group, lines, pins_of, routed, drawn);
    for (pairs) |pair| {
        for (pair) |group| try one(c, nl, group, lines, pins_of, routed, drawn);
        try linked(c, nl, pair, lines, pins_of, routed, drawn);
    }
}

// ---- private ----

fn one(c: *Canvas, nl: *const netlist.Netlist, group: Group, lines: *const netlines.NetLines, pins_of: []const std.ArrayList(u32), routed: []const bool, drawn: []bool) Allocator.Error!void {
    const net = nl.graph.members(group[0])[0].index();
    if (drawn[net] or routed[net] or c.s.roles[net] != .internal or lines.style[net] != .auto or lines.port[net] != null) return;
    for (lines.routes) |route| if (route.net == net) return;
    const points = map(c, nl, group, net, pins_of[net].items) orelse return;
    if (try tree(c, net, points)) drawn[net] = true;
}

fn map(c: *const Canvas, nl: *const netlist.Netlist, group: Group, net: u32, pins: []const u32) ?[4]Pt {
    if (pins.len != 4) return null;
    const devices = [4]u32{ group[0].index(), group[0].index(), group[1].index(), group[2].index() };
    var indices = [4]usize{ 0, 1, 0, 0 };
    for (group[1..3], 2..) |edge, i| indices[i] = @intFromBool(nl.graph.members(edge)[0].index() != net);
    var handles: [4]u32 = @splat(sch.none);
    var result: [4]Pt = undefined;
    for (pins) |p| {
        const pin = c.s.pins.get(p);
        const slot = for (devices, indices, 0..) |d, index, i| {
            if (pin.device == d and pin.index == index) break i;
        } else return null;
        if (handles[slot] != sch.none or pin.net != net) return null;
        handles[slot] = p;
        result[slot] = actual(c, nl, p, net) orelse return null;
    }
    for (handles, [_]library.Side{ .down, .right, .up, .up }) |p, side| {
        if (p == sch.none or c.s.pins.items(.side)[p] != side) return null;
    }
    return result;
}

fn tree(c: *Canvas, net: u32, p: [4]Pt) Allocator.Error!bool {
    const d, const g = .{ p[0], p[1] };
    const a, const b = if (p[2].x < p[3].x) .{ p[2], p[3] } else .{ p[3], p[2] };
    if (a.y != b.y or !(a.x < d.x and d.x < g.x and g.x < b.x and g.y < d.y and d.y <= a.y)) return false;
    const lines: [3]canvas.Line = .{
        .of(&.{ a, b }),
        .of(&.{ g, .{ .x = b.x, .y = g.y }, b }),
        .of(&.{ d, .{ .x = d.x, .y = a.y } }),
    };
    const count: usize = if (d.y == a.y) 2 else 3;
    if (!canvas.linesFit(c, net, lines[0..count])) return false;
    const before = c.save();
    var committed = false;
    defer if (!committed) c.restore(before);
    for (lines[0..count]) |line| if (!try c.commit(net, line.slice())) return false;
    committed = true;
    return true;
}

fn actual(c: *const Canvas, nl: *const netlist.Netlist, p: u32, net: u32) ?Pt {
    const pin = c.s.pins.get(p);
    const d = pin.device;
    if (d == sch.none or d >= c.s.devices.len or pin.net != net) return null;
    const nets = nl.graph.members(.from(d));
    if (pin.index >= nets.len or nets[pin.index].index() != net) return null;
    const row = c.s.devices.get(d);
    const class = c.s.lib.at(row.class);
    if (!row.kept or !class.shows(pin.index) or sch.referencePin(c.s, d, pin.index, net)) return null;
    if (class.side(pin.index, row.orient) != pin.side) return null;
    const node = c.s.deviceNode(d) orelse return null;
    const origin = Pt.round(c.s.xy[node]);
    const offset = row.orient.apply(class.terminals[pin.index].at);
    const point = canvas.pinAt(c.s, p);
    if (@as(i64, origin.x) - row.grid.x + offset.x != point.x or @as(i64, origin.y) - row.grid.y + offset.y != point.y) return null;
    return point;
}

fn linked(c: *Canvas, nl: *const netlist.Netlist, pair: loads.Pair, lines: *const netlines.NetLines, pins_of: []const std.ArrayList(u32), routed: []const bool, drawn: []bool) Allocator.Error!void {
    var nets: [2]u32 = undefined;
    var points: [2][3]Pt = undefined;
    for (0..2) |i| {
        const resistor = pair[0][i + 1];
        const drain = pair[0][i + 3];
        const net = nl.graph.members(drain)[0].index();
        nets[i] = net;
        if (drawn[net] or routed[net] or c.s.roles[net] != .internal or lines.style[net] != .auto or lines.port[net] != null) return;
        for (lines.routes) |route| if (route.net == net) return;
        if (nl.graph.incident(.from(net)).len != 3 or pins_of[net].items.len != 3) return;
        var gate: ?netlist.EdgeId = null;
        for (pair[1][3..5]) |edge| if (nl.graph.members(edge)[1].index() == net) {
            if (gate != null) return;
            gate = edge;
        };
        const devices = [3]u32{ resistor.index(), drain.index(), (gate orelse return).index() };
        const resistor_nets = nl.graph.members(resistor);
        if (resistor_nets.len != 2) return;
        const first: usize = @intFromBool(resistor_nets[0].index() != net);
        const indices = [3]usize{ first, 0, 1 };
        const sides = [3]library.Side{ .down, .up, if (i == 0) .left else .right };
        var handles: [3]u32 = @splat(sch.none);
        for (pins_of[net].items) |p| {
            const pin = c.s.pins.get(p);
            const slot = for (devices, indices, 0..) |d, index, j| {
                if (pin.device == d and pin.index == index) break j;
            } else return;
            if (handles[slot] != sch.none or pin.side != sides[slot]) return;
            handles[slot] = p;
            points[i][slot] = actual(c, nl, p, net) orelse return;
        }
        for (handles) |p| if (p == sch.none) return;
    }
    if (nets[0] == nets[1]) return;
    const a, const b = .{ points[0], points[1] };
    if (a[0].x != a[1].x or b[0].x != b[1].x or a[0].x >= b[0].x) return;
    if (a[0].y != b[0].y or a[1].y != b[1].y or a[2].y != b[2].y) return;
    if (a[0].y >= a[1].y or a[1].y >= a[2].y or a[2].x >= b[2].x) return;
    const left = envelope(c, pair[0]) orelse return;
    const right = envelope(c, pair[1]) orelse return;
    if (left.max.x >= right.min.x) return;
    const tap: i64 = c.len.tap;
    const upper: i64 = @as(i64, a[0].y) + tap;
    const lower: i64 = @as(i64, b[1].y) - tap;
    if (!(a[0].y < upper and upper < lower and lower < a[1].y)) return;
    const inner: i64 = @as(i64, a[2].x) - tap;
    var middle = @divFloor(@as(i64, left.max.x) + right.min.x, 2);
    if (middle >= inner) middle = @divFloor(@as(i64, left.max.x) + inner, 2);
    var bottom = @as(i64, @max(left.max.y, right.max.y)) + tap + c.len.clearance;
    const outer = @as(i64, @max(right.max.x, b[2].x)) + tap;
    if (!(left.max.x < middle and middle < inner and inner < a[2].x)) return;
    // Match Canvas's horizontal body-interior check, including its edge
    // exclusions. Each scan sees one fixed row; no body can raise it twice.
    for (0..c.boxes.len + 1) |_| {
        var next = bottom;
        for (c.boxes) |box| {
            const x0, const x1 = .{ @as(i64, box.min.x) + 1, @as(i64, box.max.x) - 1 };
            const y0, const y1 = .{ @as(i64, box.min.y) + 1, @as(i64, box.max.y) - 1 };
            if (x0 > x1 or y0 > y1) continue;
            if (middle <= x1 and outer >= x0 and y0 < bottom and bottom < y1)
                next = @max(next, @as(i64, box.max.y) + c.len.clearance);
        }
        if (next == bottom) break;
        assert(next > bottom);
        bottom = next;
    } else unreachable;
    const paths: [4]canvas.Line = .{
        .of(&.{ a[0], a[1] }),
        .of(&.{ coordinate(a[0].x, upper) orelse return, coordinate(inner, upper) orelse return, coordinate(inner, a[2].y) orelse return, a[2] }),
        .of(&.{ b[0], b[1] }),
        .of(&.{ coordinate(b[0].x, lower) orelse return, coordinate(middle, lower) orelse return, coordinate(middle, bottom) orelse return, coordinate(outer, bottom) orelse return, coordinate(outer, b[2].y) orelse return, b[2] }),
    };
    for (nets, 0..) |net, i| if (!canvas.linesFit(c, net, paths[2 * i .. 2 * i + 2])) return;
    const before = c.save();
    var committed = false;
    defer if (!committed) c.restore(before);
    for (paths, 0..) |path, i| if (!try c.commit(nets[i / 2], path.slice())) return;
    committed = true;
    for (nets) |net| drawn[net] = true;
}

fn envelope(c: *const Canvas, group: Group) ?library.Rect {
    var result: ?library.Rect = null;
    for (group) |edge| {
        const d = edge.index();
        const row = c.s.devices.get(d);
        if (!row.kept) return null;
        const node = c.s.deviceNode(d) orelse return null;
        const origin = Pt.round(c.s.xy[node]);
        const local = c.s.lib.at(row.class).box(row.orient, .zero);
        const x = @as(i64, origin.x) - row.grid.x;
        const y = @as(i64, origin.y) - row.grid.y;
        const box: library.Rect = .{
            .min = coordinate(x + local.min.x, y + local.min.y) orelse return null,
            .max = coordinate(x + local.max.x, y + local.max.y) orelse return null,
        };
        result = if (result) |old| old.merge(box) else box;
    }
    return result;
}

fn coordinate(x: i64, y: i64) ?Pt {
    if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or y < std.math.minInt(i32) or y > std.math.maxInt(i32)) return null;
    return .{ .x = @intCast(x), .y = @intCast(y) };
}
