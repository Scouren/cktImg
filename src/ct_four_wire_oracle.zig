//! Independent physical components and complete pre-transaction row snapshots.
//! Oracle/provenance: docs/research/figures/ct_four_wires_tests.json.
//! Frozen RED7 assertions and fixture values; no production topology oracle.
//!
//! Contents: Before, take, deinit, matches, joined, expectPairs, componentSymbols.

const std = @import("std");
const testing = std.testing;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const netlist = @import("netlist.zig");
const canvas = @import("canvas.zig");
const maze = @import("maze.zig");
const literal = @import("ct_four_wire_data.zig");

/// Owned exact-prefix snapshot; the test allocator owns every duplicate.
pub const Before = struct {
    nodes: []sch.Node,
    pins: []sch.Pin,
    xy: [][2]f32,
    routes: []sch.Route,
    segs: []maze.Wire,
    points: []maze.Mark,
    devices: []sch.DeviceInfo,
    labels: []bool,
    drawn: []bool,
    /// Frozen full-prefix take oracle.
    pub fn take(c: *const canvas.Canvas, drawn: []const bool) !Before {
        const a = testing.allocator;
        const nodes = try a.alloc(sch.Node, c.s.nodes.len);
        errdefer a.free(nodes);
        for (nodes, 0..) |*row, i| row.* = c.s.nodes.get(i);
        const pins = try a.alloc(sch.Pin, c.s.pins.len);
        errdefer a.free(pins);
        for (pins, 0..) |*row, i| row.* = c.s.pins.get(i);
        const devices = try a.alloc(sch.DeviceInfo, c.s.devices.len);
        errdefer a.free(devices);
        for (devices, 0..) |*row, i| row.* = c.s.devices.get(i);
        const xy = try a.dupe([2]f32, c.xy.items);
        errdefer a.free(xy);
        const routes = try a.dupe(sch.Route, c.s.routes.items);
        errdefer a.free(routes);
        const segs = try a.dupe(maze.Wire, c.segs.items);
        errdefer a.free(segs);
        const points = try a.dupe(maze.Mark, c.points.items);
        errdefer a.free(points);
        const labels = try a.dupe(bool, c.s.labeled);
        errdefer a.free(labels);
        return .{ .nodes = nodes, .pins = pins, .xy = xy, .routes = routes, .segs = segs, .points = points, .devices = devices, .labels = labels, .drawn = try a.dupe(bool, drawn) };
    }
    /// Frozen full-prefix deinit oracle.
    pub fn deinit(b: Before) void {
        const a = testing.allocator;
        a.free(b.nodes);
        a.free(b.pins);
        a.free(b.xy);
        a.free(b.routes);
        a.free(b.segs);
        a.free(b.points);
        a.free(b.devices);
        a.free(b.labels);
        a.free(b.drawn);
    }
    /// Frozen full-prefix matches oracle.
    pub fn matches(b: Before, c: *const canvas.Canvas, drawn: []const bool) !void {
        try testing.expectEqual(b.nodes.len, c.s.nodes.len);
        for (b.nodes, 0..) |row, i| try testing.expectEqualDeep(row, c.s.nodes.get(i));
        try testing.expectEqual(b.pins.len, c.s.pins.len);
        for (b.pins, 0..) |row, i| try testing.expectEqualDeep(row, c.s.pins.get(i));
        try testing.expectEqual(b.devices.len, c.s.devices.len);
        for (b.devices, 0..) |row, i| try testing.expectEqualDeep(row, c.s.devices.get(i));
        try testing.expectEqualDeep(b.xy, c.xy.items);
        try testing.expectEqual(c.xy.items.ptr, c.s.xy.ptr);
        try testing.expectEqualDeep(b.xy, c.s.xy);
        try testing.expectEqualDeep(b.routes, c.s.routes.items);
        try testing.expectEqualDeep(b.segs, c.segs.items);
        try testing.expectEqualDeep(b.points, c.points.items);
        try testing.expectEqualDeep(b.labels, c.s.labeled);
        try testing.expectEqualDeep(b.drawn, drawn);
        try testing.expectEqual(@as(usize, 0), c.s.no_connects.items.len);
    }
};

/// Frozen joined certificate over actual emitted ink/rows.
pub fn joined(c: *const canvas.Canvas, a: u32, b: u32) !bool {
    const net = c.s.pins.items(.net)[a];
    const n = c.segs.items.len;
    const parent = try testing.allocator.alloc(usize, n + 2);
    defer testing.allocator.free(parent);
    for (parent, 0..) |*p, i| p.* = i;
    for (0..n + 2) |i| {
        if (i < n and c.segs.items[i].net != net) continue;
        const ri = if (i < n) library.Rect.fromCorners(c.segs.items[i].a, c.segs.items[i].b) else library.Rect.point(canvas.pinAt(c.s, if (i == n) a else b));
        for (i + 1..n + 2) |j| {
            if (j < n and c.segs.items[j].net != net) continue;
            const rj = if (j < n) library.Rect.fromCorners(c.segs.items[j].a, c.segs.items[j].b) else library.Rect.point(canvas.pinAt(c.s, if (j == n) a else b));
            if (ri.intersects(rj)) {
                const x = root(parent, i);
                const y = root(parent, j);
                parent[@max(x, y)] = @min(x, y);
            }
        }
    }
    return root(parent, n) == root(parent, n + 1);
}

/// Frozen expectPairs certificate over actual emitted ink/rows.
pub fn expectPairs(c: *const canvas.Canvas, only: ?u32) !void {
    for (literal.pairs) |pair| {
        if (only) |target| if (c.s.pins.items(.net)[pair.a] != target) continue;
        const actual = try joined(c, pair.a, pair.b);
        errdefer std.debug.print("partition {s}.{d}--{s}.{d}: expected {}, observed {}\n", .{ literal.pins_on[pair.a].name, literal.pins_on[pair.a].index, literal.pins_on[pair.b].name, literal.pins_on[pair.b].index, pair.yes, actual });
        try testing.expectEqual(pair.yes, actual);
    }
}

/// Frozen componentSymbols certificate over actual emitted ink/rows.
pub fn componentSymbols(c: *const canvas.Canvas, nl: *const netlist.Netlist, first: usize, only: ?u32) !bool {
    for (literal.parts) |part| {
        const target = nl.net(literal.nets[part.net]).?.index();
        if (only) |n| if (n != target) continue;
        var count: usize = 0;
        for (first..c.s.pins.len) |raw| {
            const p = c.s.pins.get(raw);
            if (p.net != target or !try joined(c, part.pins[0], @intCast(raw))) continue;
            const row = c.s.nodes.get(p.home);
            if (p.device != sch.none or row.ref != target or row.kind == .device) return false;
            if (!part.output and row.kind != .label) return false;
            count += 1;
        }
        if (count != 1) return false;
    }
    return true;
}

// ---- private ----

fn root(parent: []usize, i: usize) usize {
    var k = i;
    for (0..parent.len) |_| {
        if (parent[k] == k) return k;
        k = parent[k];
    }
    unreachable;
}
