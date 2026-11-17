//! Whole passive ladders and bridged-T networks drawn on the tapped signal path.
//!
//! Human Rules:
//! - passive_filters.1 (habit, bounded) Three series arms form one ordered
//!   signal row, with a shunt from each outgoing tap to the common return.
//!   AR1910/5431/5432/6308 follow this arrangement with R, L or C arms.
//! - passive_filters.2 (habit, bounded) Two series arms with a grounded
//!   tap stay on the port row when a fourth arm bridges the port nets.
//!   The bridge sits above and the shunt below in AR6363 and its R/C
//!   dual AR6364. A differential bridge or a parallel LC has other edges.
//! - passive_filters.3 (invariant) Every raw card and its two ordered pins
//!   must match. Existing geometry/group instructions retain precedence.
//!
//! Data: the complete four- or six-device graph, existing role/rank arrays
//! and shelf limit in, at most six temporary cell assignments out. No
//! allocation or retained per-device state. See docs/research/production-patterns/README.md.
//!
//! Contents: `Frame`, `apply`, `find`, and `port`.

const std = @import("std");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const canvas = @import("canvas.zig");

const Netlist = netlist.Netlist;
const VertexId = netlist.VertexId;
const EdgeId = netlist.EdgeId;
const none = sch.none;

/// A complete assignment indexed by netlist device, kept only through placement.
pub const Frame = struct {
    devices: [6]Cell,

    /// Writes the matched cells, keeping SPICE pin order in both orientations.
    pub fn apply(frame: *const Frame, nl: *const Netlist, form: []skeleton.Form, upper: []u32, lower: []u32, left_end: []skeleton.End, x: []i32, y: []i32) void {
        std.debug.assert(x.len == nl.graph.edgeCount() and y.len == x.len);
        std.debug.assert(x.len == 4 or x.len == 6);
        for (frame.devices[0..x.len], 0..) |cell, d| {
            x[d] = cell.x;
            y[d] = cell.y;
            form[d] = if (cell.vertical) .vertical else .horizontal;
            const pins = nl.graph.members(EdgeId.from(d));
            upper[d] = if (cell.vertical) pins[cell.first].index() else none;
            lower[d] = if (cell.vertical) pins[1 - cell.first].index() else none;
            left_end[d] = if (cell.vertical) .auto else if (cell.first == 0) .first else .second;
        }
    }
};

const Cell = struct { x: u8, y: u8, vertical: bool, first: u1 };
const Node = enum(u8) { left, right, ground, tap, second };
const Arm = struct { from: Node, to: Node, x: u8, y: u8 };

const ladder = [_]Arm{
    .{ .from = .left, .to = .tap, .x = 0, .y = 0 },
    .{ .from = .tap, .to = .second, .x = 2, .y = 0 },
    .{ .from = .second, .to = .right, .x = 4, .y = 0 },
    .{ .from = .tap, .to = .ground, .x = 1, .y = 1 },
    .{ .from = .second, .to = .ground, .x = 3, .y = 1 },
    .{ .from = .right, .to = .ground, .x = 5, .y = 1 },
};

const bridged = [_]Arm{
    .{ .from = .left, .to = .tap, .x = 0, .y = 1 },
    .{ .from = .tap, .to = .right, .x = 2, .y = 1 },
    .{ .from = .left, .to = .right, .x = 1, .y = 0 },
    .{ .from = .tap, .to = .ground, .x = 1, .y = 2 },
};

/// Admits the complete passive graph and two distinct signal interfaces.
/// Uses the input at the left when directed, otherwise canonical rank
/// chooses among equally valid bridged-T reflections.
pub fn find(nl: *const Netlist, roles: []const sch.Role, ranks: []const u32, shelf: u32) ?Frame {
    const g = &nl.graph;
    const count = g.edgeCount();
    if (count != 4 and count != 6) return null;
    const is_ladder = count == 6;
    const width: u8 = if (is_ladder) 6 else 3;
    if (shelf != 0 and shelf < width) return null;
    for (nl.hints) |hint| switch (hint.verb) {
        .role, .expand, .label, .wire, .port, .rail, .via, .route, .refdes => {},
        else => return null,
    };
    for (g.edges.items(.kind), 0..) |kind, d| {
        if (kind != .resistor and kind != .inductor and kind != .capacitor) return null;
        if (g.members(EdgeId.from(d)).len != 2) return null;
    }
    var nodes: [5]u32 = @splat(none);
    var ports: usize = 0;
    var taps: usize = 0;
    for (roles, 0..) |role, i| {
        if (g.incident(VertexId.from(i)).len == 0) continue;
        const v: u32 = @intCast(i);
        switch (role) {
            .input, .output => {
                if (ports == 2) return null;
                nodes[ports] = v;
                ports += 1;
            },
            .internal => {
                if (taps == 2) return null;
                nodes[3 + taps] = v;
                taps += 1;
            },
            .sink => {
                if (nodes[2] != none) return null;
                nodes[2] = v;
            },
            else => return null,
        }
    }
    if (ports != 2 or nodes[2] == none or taps != @as(usize, if (is_ladder) 2 else 1)) return null;
    const prefer_swap = if (roles[nodes[0]] == roles[nodes[1]]) ranks[nodes[1]] < ranks[nodes[0]] else roles[nodes[1]] == .input;
    if (prefer_swap) std.mem.swap(u32, &nodes[0], &nodes[1]);
    if (!is_ladder) return match(nl, &bridged, nodes, false);
    // Only the first through arm's outer net has degree one. Directed
    // ports may ask for the ladder to face the other way on the page.
    const reverse = g.incident(VertexId.from(nodes[1])).len == 1;
    if (reverse) std.mem.swap(u32, &nodes[0], &nodes[1]);
    const reflect = reverse and roles[nodes[0]] != roles[nodes[1]];
    if (match(nl, &ladder, nodes, reflect)) |frame| return frame;
    std.mem.swap(u32, &nodes[3], &nodes[4]);
    return match(nl, &ladder, nodes, reflect);
}

/// Connects a bridged T's two outward pins at a junction beside the tapped
/// path, with a port extending out on that row (AR6363/6364). Rechecks
/// terminal geometry because callers may edit a skeleton or symbol.
pub fn port(c: *canvas.Canvas, net: u32, pins: []const u32) std.mem.Allocator.Error!bool {
    if (pins.len != 2) return false;
    const side = c.s.pins.items(.side)[pins[0]];
    if (!side.isHorizontal() or side != c.s.pins.items(.side)[pins[1]]) return false;
    const upper = canvas.topLeft(c.s, pins);
    const top = canvas.pinAt(c.s, pins[upper]);
    const bottom = canvas.pinAt(c.s, pins[1 - upper]);
    if (top.y >= bottom.y or (if (side == .left) bottom.x >= top.x else bottom.x <= top.x)) return false;
    const junction = canvas.stepPt(bottom, side, c.len.tap);
    const corner: sch.Pt = .{ .x = junction.x, .y = top.y };
    const marker = canvas.stepPt(junction, side, c.len.terminal);
    if (!c.fits(net, junction, marker)) return false;
    if (!try c.commit(net, &.{ top, corner, junction, bottom })) return false;
    const drawn = try c.stub(.terminal, net, junction, side, c.len.terminal);
    std.debug.assert(drawn);
    return true;
}

// ---- private ----

fn match(nl: *const Netlist, arms: []const Arm, nodes: [5]u32, reflect: bool) ?Frame {
    std.debug.assert(nl.graph.edgeCount() == arms.len);
    var frame: Frame = undefined;
    // All expected endpoint pairs are distinct. Matching each expected
    // edge once accounts for every card, including duplicate/extra arms.
    for (arms) |arm| {
        const a = nodes[@backingInt(arm.from)];
        const b = nodes[@backingInt(arm.to)];
        const vertical = arm.to == .ground;
        const found = for (nl.graph.incident(VertexId.from(a))) |edge| {
            const pins = nl.graph.members(edge);
            const first: u1 = @intFromBool(pins[0].index() != a);
            if (pins[1 - first].index() != b) continue;
            frame.devices[edge.index()] = .{
                .x = if (reflect) 5 - arm.x else arm.x,
                .y = arm.y,
                .vertical = vertical,
                .first = if (reflect and !vertical) 1 - first else first,
            };
            break true;
        } else false;
        if (!found) return null;
    }
    return frame;
}

test "passive filters: reject different attachments, forced cells and external taps" {
    const body = "Filter\nR1 vin x 1k\nR2 x vout 1k\n";
    const valid = body ++ "C3 vin vout 1p\nC4 x 0 1p\n";
    // AR6364 beside an untapped path, a duplicate arm, an exported tap,
    // an extra load, an explicit placement and a shelf that must wrap.
    const cases = [_]struct { deck: []const u8, shelf: u32 = 8, admitted: bool = false }{
        .{ .deck = valid, .admitted = true },
        .{ .deck = body ++ "C3 vin vout 1p\nC4 vout 0 1p\n" },
        .{ .deck = body ++ "C3 vin x 1p\nC4 x 0 1p\n" },
        .{ .deck = valid ++ "*@ role x output\n" },
        .{ .deck = valid ++ "RL vout 0 1k\n" },
        .{ .deck = valid ++ "*@ cell c3 0 2\n" },
        .{ .deck = valid, .shelf = 1 },
    };
    for (cases) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const nl = try netlist.parse(a, &.{case.deck}, null);
        const roles = try sch.guessRoles(a, &nl);
        const st = try sch.structure.analyze(a, a, &nl, roles);
        try std.testing.expectEqual(case.admitted, find(&nl, roles, st.net_rank, case.shelf) != null);
    }
}
