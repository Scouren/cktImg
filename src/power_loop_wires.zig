//! Certified flying-capacitor loops → local wire trees on actual pins.
//!
//! Human Rules:
//! - power_loop_wires.1 (habit, bounded) Keep the seven local connections
//!   of a certified loop continuous. All 145 selected AnalogGenie source
//!   drawings connect these terminals through actual Manhattan conductor
//!   ink, with no proper crossing between the seven local trees. Gates,
//!   bodies and remote controls do not belong to these trees. Provenance:
//!   docs/research/converter-loops.md and its exact source inventory.
//! - power_loop_wires.2 (choice) The main path is the top wire, the lower
//!   switch and diode the bottom wire, with vertical capacitor drops and
//!   a downward divider. Actual pins must support this ordering. Commit
//!   the whole group or leave it to the ordinary wire patterns; no partial
//!   loop survives a body, pin or prior-wire collision.
//!   A projected routing point must equal its transformed class terminal;
//!   off-line connectors added later cannot certify this local tree.
//! - power_loop_wires.3 (invariant) Explicit net styles, routes, vias and
//!   a requested first-net order take precedence. After a successful local
//!   tree, the ordinary wiring sees its outside pins plus one tree anchor:
//!   a remote connection may still be named, and an input still has a port.
//!   Automatic thinning never erases the local tree. Record the successful
//!   anchor so a later router attaches every outside pin to that tree.
//!   A later group sharing a seeded net keeps all its terminals for the
//!   ordinary patterns; one anchor never represents two disconnected trees.
//! - power_loop_wires.4 (choice) Retain an output's outermost selected pin
//!   toward its requested port side, so outside-pin wiring still sees the
//!   whole local output extent. A local output with no outside pins gets
//!   its port at the whole tree's boundary, toward the requested side or
//!   the loop's output direction. The retained anchor is a routing handle,
//!   not a new physical boundary inside the loop. `output`
//!
//! Data: existing netlist/roles/drawn rows select temporary 68-byte groups,
//! one capacity slot per drawn coil. Each wiring pass maps a group to 18
//! existing u32 pin handles in seven fixed rows, at most four per net.
//! No persistent state, new nodes, callbacks or per-pin allocation; the
//! canvas owns routes, and the caller owns/frees the group request slice.
//! A temporary u32 anchor per net is `none` until a tree is committed.
//!
//! Contents:
//! - `pub fn collect(gpa: Allocator, nl: *const Netlist, roles: []const sch.Role, drawn: []const bool, lines: *const NetLines) Allocator.Error![]Group`
//! - `pub fn seed(c: *Canvas, groups: []const Group, pins_of: []std.ArrayList(u32), mates: []u32, anchors: []u32) Allocator.Error!void`
//! - `pub fn output(c: *Canvas, net: u32, pins: []const u32, anchor: u32) Allocator.Error!bool`

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const loops = @import("power_loops.zig");
const netlines = @import("netlines.zig");
const Netlist = netlist.Netlist;
const Canvas = canvas.Canvas;
const NetLines = netlines.NetLines;
const Group = loops.Group;
const Member = loops.Member;
const Pt = @import("library.zig").Pt;

// Same order as loops.Net; the first selected terminal is the outside
// wiring's anchor, except an output retains its outermost selected pin.
// MOS entries select channel terminals only.
const members = [7][]const Member{
    &.{ .main_in, .lower },
    &.{ .main_in, .coil, .fly },
    &.{ .coil, .main_out },
    &.{ .main_out, .output_cap, .grounded_cap, .upper_r },
    &.{ .lower, .fly, .diode },
    &.{ .output_cap, .diode },
    &.{ .upper_r, .lower_r },
};

/// Selects topology-qualified requests before automatic thinning. The
/// caller frees the returned slice; explicit wiring instructions abstain.
pub fn collect(gpa: Allocator, nl: *const Netlist, roles: []const sch.Role, drawn: []const bool, lines: *const NetLines) Allocator.Error![]Group {
    assert(drawn.len == nl.graph.edgeCount());
    assert(lines.style.len == roles.len);
    var capacity: usize = 0;
    for (nl.graph.edges.items(.kind), drawn) |kind, keep| {
        capacity += @intFromBool(keep and kind == .inductor);
    }
    var groups: std.ArrayList(Group) = .empty;
    errdefer groups.deinit(gpa);
    if (lines.first.len != 0) return groups.toOwnedSlice(gpa);
    try groups.ensureTotalCapacity(gpa, capacity);
    next: for (nl.graph.edges.items(.kind), 0..) |kind, d| {
        if (kind != .inductor) continue;
        const group = loops.find(nl, roles, drawn, @intCast(d)) orelse continue;
        for (group.nets) |net| {
            if (lines.style[net] != .auto) continue :next;
            for (lines.routes) |route| if (route.net == net) continue :next;
        }
        groups.appendAssumeCapacity(group);
    }
    assert(groups.items.len <= capacity);
    return groups.toOwnedSlice(gpa);
}

/// Draws each compatible group atomically after rail wires. On success,
/// replaces its local terminals in `pins_of` with one existing anchor at
/// the end; outside pins remain before it. The caller initializes `anchors`
/// to `none`; only successful groups write their exact retained handles.
/// `mates` is empty or a caller-owned mirror table:
/// partial local trees cannot be mirrored as though they were whole nets.
pub fn seed(c: *Canvas, groups: []const Group, pins_of: []std.ArrayList(u32), mates: []u32, anchors: []u32) Allocator.Error!void {
    assert(pins_of.len == c.s.net_name.len);
    assert(mates.len == 0 or mates.len == pins_of.len);
    assert(anchors.len == pins_of.len);
    next: for (groups) |group| {
        for (group.nets) |net| if (anchors[net] != sch.none) continue :next;
        const pins = map(c, group, pins_of) orelse continue;
        const checkpoint = c.save();
        errdefer c.restore(checkpoint);
        if (!try tree(c, group.nets, pins)) {
            c.restore(checkpoint);
            continue;
        }
        // Walls prohibit crossings only between this group's local trees.
        // Prior rail walls retain their bits; later remote wires may cross.
        for (c.segs.items[checkpoint.segs..]) |*segment| segment.wall = false;
        for (group.nets, members, pins) |net, local, row| {
            var count: usize = 0;
            const list = &pins_of[net];
            for (list.items) |pin| {
                if (std.mem.indexOfScalar(u32, row[0..local.len], pin) != null) continue;
                list.items[count] = pin;
                count += 1;
            }
            assert(count < list.items.len);
            var anchor = row[0];
            if (net == group.nets[@backingInt(loops.Net.output)] and c.s.roles[net] == .output) {
                const direction = outputSide(c, net).unit();
                for (row[1..local.len]) |pin| {
                    const point = canvas.pinAt(c.s, pin);
                    const at = canvas.pinAt(c.s, anchor);
                    if (projection(point, direction) > projection(at, direction) or
                        (projection(point, direction) == projection(at, direction) and point.above(at))) anchor = pin;
                }
            }
            list.items[count] = anchor;
            list.shrinkRetainingCapacity(count + 1);
            assert(anchors[net] == sch.none);
            anchors[net] = anchor;
            if (mates.len != 0) {
                const mate = mates[net];
                if (mate != sch.none) mates[mate] = sch.none;
                mates[net] = sch.none;
            }
        }
    }
}

/// Finishes a successfully seeded output that retained only its anchor.
/// `anchor` is the handle recorded by `seed`, or `none` if it abstained.
/// Outputs with outside terminals or no successful seed return false.
pub fn output(c: *Canvas, net: u32, pins: []const u32, anchor: u32) Allocator.Error!bool {
    assert(c.s.roles[net] == .output);
    assert(pins.len >= 1);
    if (pins.len != 1 or anchor == sch.none) return false;
    assert(pins[0] == anchor);
    const side = outputSide(c, net);
    const direction = side.unit();
    var from = canvas.pinAt(c.s, anchor);
    var farthest = projection(from, direction);
    for (c.segs.items) |segment| {
        if (segment.net != net) continue;
        for ([_]Pt{ segment.a, segment.b }) |point| {
            const distance = projection(point, direction);
            if (distance > farthest or (distance == farthest and point.above(from))) {
                from = point;
                farthest = distance;
            }
        }
    }
    try c.port(net, from, side);
    return true;
}

// ---- private ----

fn outputSide(c: *const Canvas, net: u32) @import("library.zig").Side {
    return if (c.port_side.len != 0) c.port_side[net] orelse .right else .right;
}

fn projection(point: Pt, direction: Pt) i64 {
    return @as(i64, point.x) * direction.x + @as(i64, point.y) * direction.y;
}

fn map(c: *const Canvas, group: Group, pins_of: []const std.ArrayList(u32)) ?[7][4]u32 {
    var out: [7][4]u32 = @splat(@splat(sch.none));
    for (group.nets, members, 0..) |net, local, n| for (local, 0..) |member, i| {
        const d = group.devices[@backingInt(member)];
        const mos = member == .main_in or member == .main_out or member == .lower;
        var found: ?u32 = null;
        for (pins_of[net].items) |p| {
            const pin = c.s.pins.get(p);
            if (pin.device != d or (mos and pin.index != 0 and pin.index != 2)) continue;
            if (found != null) return null;
            const info = c.s.devices.slice();
            const class = c.s.lib.at(info.items(.class)[d]);
            const node = c.s.nodes.items(.group)[pin.home];
            const origin = Pt.round(c.s.xy[node]).sub(info.items(.grid)[d]);
            const actual = origin.add(info.items(.orient)[d].apply(class.terminals[pin.index].at));
            if (!actual.eql(canvas.pinAt(c.s, p))) return null;
            found = p;
        }
        out[n][i] = found orelse return null;
    };
    return out;
}

fn tree(c: *Canvas, nets: [7]u32, pins: [7][4]u32) Allocator.Error!bool {
    var p: [7][4]Pt = undefined;
    for (members, pins, 0..) |local, row, n| for (0..local.len) |i| {
        p[n][i] = canvas.pinAt(c.s, row[i]);
    };
    const row = p[1][0].y;
    // Actual terminal order, including shifted caller symbol frames.
    if (p[0][0].y != row or p[1][1].y != row or p[2][0].y != row or p[2][1].y != row or p[3][0].y != row) return false;
    if (!(p[0][0].x < p[1][0].x and p[1][0].x <= p[1][2].x and p[1][2].x <= p[1][1].x and p[1][1].x < p[2][0].x and p[2][0].x <= p[2][1].x and p[2][1].x < p[3][0].x)) return false;
    if (p[1][2].x != p[4][1].x or p[1][2].y < row or p[1][2].y >= p[4][1].y) return false;
    if (p[0][1].y != p[4][0].y or p[0][1].x >= p[4][0].x or p[4][0].y <= row) return false;
    if (p[4][0].x > p[4][1].x or p[4][1].x > p[4][2].x or p[4][1].y > p[4][0].y) return false;
    if (p[4][2].y != p[5][1].y or p[4][2].x >= p[5][1].x or p[4][2].y < p[4][0].y) return false;
    if (p[3][1].x != p[5][0].x or p[3][1].y >= p[5][0].y or p[5][0].y > p[5][1].y or p[5][1].x > p[5][0].x) return false;
    if (p[3][3].x != p[6][0].x or p[6][0].x != p[6][1].x or p[3][3].y >= p[6][0].y or p[6][0].y > p[6][1].y) return false;
    for (p[3][1..]) |point| if (point.x < p[3][0].x or point.y < row) return false;
    // Input bus left of both channel bodies.
    const bus_x = @min(p[0][0].x, p[0][1].x);
    if (!try path(c, nets[0], &.{ p[0][0], .{ .x = bus_x, .y = p[0][0].y }, .{ .x = bus_x, .y = p[0][1].y }, p[0][1] })) return false;
    if (!try path(c, nets[1], &.{ p[1][0], p[1][1] })) return false;
    if (!try path(c, nets[1], &.{ .{ .x = p[1][2].x, .y = row }, p[1][2] })) return false;
    if (!try path(c, nets[2], &.{ p[2][0], p[2][1] })) return false;
    var output_x = p[3][0].x;
    for (p[3][1..]) |point| output_x = @max(output_x, point.x);
    if (!try path(c, nets[3], &.{ p[3][0], .{ .x = output_x, .y = row } })) return false;
    for (p[3][1..]) |point| if (!try path(c, nets[3], &.{ .{ .x = point.x, .y = row }, point })) return false;
    const bottom_y = p[4][2].y;
    if (!try path(c, nets[4], &.{ p[4][0], .{ .x = p[4][0].x, .y = bottom_y }, p[4][2] })) return false;
    if (!try path(c, nets[4], &.{ p[4][1], .{ .x = p[4][1].x, .y = bottom_y } })) return false;
    if (!try path(c, nets[5], &.{ p[5][1], .{ .x = p[5][0].x, .y = p[5][1].y }, p[5][0] })) return false;
    return path(c, nets[6], &.{ p[6][0], p[6][1] });
}

fn path(c: *Canvas, net: u32, points: []const Pt) Allocator.Error!bool {
    assert(points.len >= 2 and points.len <= 4);
    for (points[0 .. points.len - 1], points[1..]) |a, b| {
        assert(a.x == b.x or a.y == b.y);
        if (a.eql(b)) continue;
        if (!try c.commit(net, &.{ a, b })) return false;
        c.wall();
    }
    return true;
}

test "power loop wires: hidden or projected terminals cannot certify a local tree" {
    // Oracle: literal physical geometry, not the selector or router.
    // All aligned pins form a clear loop. Changing only CFLY's glyph puts
    // its ends at (170,160)/(150,200), while routing still projects both
    // onto x=160. A seed must abstain before hiding those real terminals.
    const testing = std.testing;
    const library = @import("library.zig");
    const gpa = testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    const mos = try lib.register(.{ .name = "loop_test_mos", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -20, .y = 0 }, .side = .left },
    } });
    const coil = try lib.register(.{ .name = "loop_test_coil", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 20, .y = 0 }, .side = .right },
    } });
    const vertical = try lib.register(.{ .name = "loop_test_vertical", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "b", .at = .{ .x = 0, .y = 20 }, .side = .down },
    } });
    const skew = try lib.register(.{ .name = "loop_test_skew", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 10, .y = -20 }, .side = .up },
        .{ .name = "b", .at = .{ .x = -10, .y = 20 }, .side = .down },
    } });
    const hidden_top = try lib.register(.{ .name = "loop_test_hidden", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 0, .y = -20 }, .side = .up, .hidden = true },
        .{ .name = "b", .at = .{ .x = 0, .y = 20 }, .side = .down },
    } });
    const diode = try lib.register(.{ .name = "loop_test_diode", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "k", .at = .{ .x = -20, .y = 0 }, .side = .left },
    } });
    const coordinates = [_][2]f32{
        .{ 100, 100 }, .{ 240, 100 }, .{ 360, 100 }, .{ 100, 300 }, .{ 160, 180 },
        .{ 280, 300 }, .{ 440, 180 }, .{ 520, 180 }, .{ 600, 180 }, .{ 600, 260 },
    };
    const card_nets = [_][]const u32{
        &.{ 1, 8, 0 }, &.{ 1, 2 }, &.{ 3, 8, 2 }, &.{ 4, 8, 0 }, &.{ 1, 4 },
        &.{ 5, 4 },    &.{ 3, 5 }, &.{ 3, 7 },    &.{ 3, 6 },    &.{ 6, 7 },
    };
    const group: Group = .{ .devices = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, .nets = .{ 0, 1, 2, 3, 4, 5, 6 } };
    for (0..3) |frame| {
        const shifted = frame == 1;
        const hidden = frame == 2;
        const abstained = shifted or hidden;
        var s: sch.Schematic = .{
            .arena = .init(gpa),
            .lib = &lib,
            .device_kind = &.{ .mosfet, .inductor, .mosfet, .mosfet, .capacitor, .diode, .capacitor, .capacitor, .resistor, .resistor },
            .device_name = &.{ "m1", "l1", "m3", "m2", "cfly", "d1", "co", "cop", "r1", "r2" },
            .device_pin_count = &.{ 3, 2, 3, 3, 2, 2, 2, 2, 2, 2 },
            .net_name = &.{ "bus", "near_in", "near_out", "out", "bottom", "negative", "feedback", "gnd", "gate" },
            .roles = &.{ .input, .internal, .internal, .output, .internal, .internal, .internal, .sink, .input },
        };
        defer s.deinit();
        const a = s.arena.allocator();
        var xy: std.ArrayList([2]f32) = .empty;
        try xy.appendSlice(a, &coordinates);
        s.xy = xy.items;
        s.labeled = try a.alloc(bool, 9);
        @memset(s.labeled, false);
        const branch = if (hidden) hidden_top else vertical;
        const classes = [_]library.ClassId{ mos, coil, mos, mos, if (shifted) skew else vertical, diode, branch, branch, branch, vertical };
        var pins_of: [9]std.ArrayList(u32) = @splat(.empty);
        defer for (&pins_of) |*list| list.deinit(gpa);
        for (classes, card_nets, 0..) |class, nets, d| {
            try s.devices.append(a, .{
                .kept = true,
                .driver = false,
                .orientation = .horizontal,
                .flip_x = false,
                .flip_y = false,
                .class = class,
                .orient = .r0,
                .grid = .zero,
                .reach = @splat(20),
            });
            const node = try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = sch.none });
            for (nets, 0..) |net, index| {
                if (!lib.at(class).shows(index)) continue;
                const pin_id = try s.addPin(.{
                    .home = node,
                    .side = lib.at(class).side(index, .r0).?,
                    .net = net,
                    .device = @intCast(d),
                    .index = @intCast(index),
                });
                try pins_of[net].append(gpa, pin_id);
            }
        }
        var c = try Canvas.init(gpa, &s, &xy, .of(.{}, 40), &.{}, &.{});
        defer c.deinit();
        // An unrelated prior wall and its route/points must survive an
        // abstention byte-for-byte; no terminal list is consumed either.
        try testing.expect(try c.commit(8, &.{ .{ .x = 700, .y = 400 }, .{ .x = 740, .y = 400 } }));
        c.wall();
        const checkpoint = c.save();
        try testing.expectEqual(Pt{ .x = 160, .y = 160 }, canvas.pinAt(&s, 11));
        const actual = Pt{ .x = if (shifted) 170 else 160, .y = 160 };
        try testing.expectEqual(actual, Pt.round(s.xy[4]).add(lib.at(classes[4]).terminals[0].at));
        var anchors: [9]u32 = @splat(sch.none);
        try seed(&c, &.{group}, &pins_of, &.{}, &anchors);
        try testing.expect(c.segs.items[0].wall);
        try testing.expectEqual(checkpoint.nodes, s.nodes.len);
        if (abstained) {
            try testing.expectEqual(checkpoint.segs, c.segs.items.len);
            try testing.expectEqual(checkpoint.routes, s.routes.items.len);
            try testing.expectEqual(checkpoint.points, c.points.items.len);
        } else {
            try testing.expect(c.segs.items.len > checkpoint.segs);
        }
        for (group.nets, [_]usize{ 2, 3, 2, 4, 3, 2, 2 }) |net, before| {
            const count: usize = if (hidden and net == 3) 1 else if (abstained) before else 1;
            try testing.expectEqual(count, pins_of[net].items.len);
            try testing.expectEqual(if (abstained) sch.none else pins_of[net].items[0], anchors[net]);
        }
        if (hidden) {
            // Three caller classes hide their output terminal. The one
            // visible output pin is not evidence of a committed local tree.
            try testing.expect(!try output(&c, 3, pins_of[3].items, anchors[3]));
            try testing.expectEqual(checkpoint.nodes, s.nodes.len);
        }
    }
}

test "power loop wires: two groups sharing a bus retain one tree and the other terminals" {
    // Oracle: two translated, individually clear copies share only net 0.
    // Once the first copy owns that net's tree, the other copy must leave
    // its real terminals for ordinary routing. A second seed must neither
    // overwrite the existing anchor nor partially commit its other nets.
    const testing = std.testing;
    const library = @import("library.zig");
    const gpa = testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    const mos = try lib.register(.{ .name = "shared_loop_mos", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -20, .y = 0 }, .side = .left },
    } });
    const coil = try lib.register(.{ .name = "shared_loop_coil", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 20, .y = 0 }, .side = .right },
    } });
    const vertical = try lib.register(.{ .name = "shared_loop_vertical", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "b", .at = .{ .x = 0, .y = 20 }, .side = .down },
    } });
    const diode = try lib.register(.{ .name = "shared_loop_diode", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "k", .at = .{ .x = -20, .y = 0 }, .side = .left },
    } });
    const coordinates = [_][2]f32{
        .{ 100, 100 }, .{ 240, 100 }, .{ 360, 100 }, .{ 100, 300 }, .{ 160, 180 },
        .{ 280, 300 }, .{ 440, 180 }, .{ 520, 180 }, .{ 600, 180 }, .{ 600, 260 },
    };
    const card_nets = [_][]const u32{
        &.{ 1, 8, 0 }, &.{ 1, 2 }, &.{ 3, 8, 2 }, &.{ 4, 8, 0 }, &.{ 1, 4 },
        &.{ 5, 4 },    &.{ 3, 5 }, &.{ 3, 7 },    &.{ 3, 6 },    &.{ 6, 7 },
    };
    const groups = [_]Group{
        .{ .devices = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, .nets = .{ 0, 1, 2, 3, 4, 5, 6 } },
        .{ .devices = .{ 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }, .nets = .{ 0, 9, 10, 11, 12, 13, 14 } },
    };
    var s: sch.Schematic = .{
        .arena = .init(gpa),
        .lib = &lib,
        .device_kind = &.{
            .mosfet, .inductor, .mosfet, .mosfet, .capacitor, .diode, .capacitor, .capacitor, .resistor, .resistor,
            .mosfet, .inductor, .mosfet, .mosfet, .capacitor, .diode, .capacitor, .capacitor, .resistor, .resistor,
        },
        .device_name = &.{ "m1a", "l1a", "m3a", "m2a", "cfa", "d1a", "coa", "cpa", "r1a", "r2a", "m1b", "l1b", "m3b", "m2b", "cfb", "d1b", "cob", "cpb", "r1b", "r2b" },
        .device_pin_count = &.{ 3, 2, 3, 3, 2, 2, 2, 2, 2, 2, 3, 2, 3, 3, 2, 2, 2, 2, 2, 2 },
        .net_name = &.{ "bus", "in_a", "near_a", "out_a", "bot_a", "neg_a", "fb_a", "gnd", "gate", "in_b", "near_b", "out_b", "bot_b", "neg_b", "fb_b" },
        .roles = &.{ .input, .internal, .internal, .output, .internal, .internal, .internal, .sink, .input, .internal, .internal, .output, .internal, .internal, .internal },
    };
    defer s.deinit();
    const a = s.arena.allocator();
    var xy: std.ArrayList([2]f32) = .empty;
    for (0..2) |copy| for (coordinates) |point| {
        try xy.append(a, .{ point[0] + @as(f32, @floatFromInt(copy * 800)), point[1] });
    };
    s.xy = xy.items;
    s.labeled = try a.alloc(bool, 15);
    @memset(s.labeled, false);
    const classes = [_]library.ClassId{ mos, coil, mos, mos, vertical, diode, vertical, vertical, vertical, vertical };
    var pins_of: [15]std.ArrayList(u32) = @splat(.empty);
    defer for (&pins_of) |*list| list.deinit(gpa);
    for (groups, 0..) |group, copy| for (classes, card_nets, group.devices) |class, nets, d| {
        try s.devices.append(a, .{
            .kept = true,
            .driver = false,
            .orientation = .horizontal,
            .flip_x = false,
            .flip_y = false,
            .class = class,
            .orient = .r0,
            .grid = .zero,
            .reach = @splat(20),
        });
        const node = try s.addNode(.{ .kind = .device, .ref = d, .group = sch.none });
        for (nets, 0..) |original, index| {
            const net = if (original >= 1 and original <= 6 and copy == 1) original + 8 else original;
            const pin = try s.addPin(.{ .home = node, .side = lib.at(class).side(index, .r0).?, .net = net, .device = d, .index = @intCast(index) });
            try pins_of[net].append(gpa, pin);
        }
    };
    var c = try Canvas.init(gpa, &s, &xy, .of(.{}, 40), &.{}, &.{});
    defer c.deinit();
    var anchors: [15]u32 = @splat(sch.none);
    try seed(&c, groups[0..1], &pins_of, &.{}, &anchors);
    try testing.expectEqual(@as(u32, 2), anchors[0]);
    try testing.expectEqualSlices(u32, &.{ 25, 33, 2 }, pins_of[0].items);
    const checkpoint = c.save();
    var before: [15][]const u32 = undefined;
    for (&before, pins_of) |*row, list| row.* = try a.dupe(u32, list.items);
    const old_anchors = anchors;
    try seed(&c, groups[1..], &pins_of, &.{}, &anchors);
    try testing.expectEqual(checkpoint.segs, c.segs.items.len);
    try testing.expectEqual(checkpoint.routes, s.routes.items.len);
    try testing.expectEqual(checkpoint.points, c.points.items.len);
    try testing.expectEqual(checkpoint.nodes, s.nodes.len);
    try testing.expectEqualSlices(u32, &old_anchors, &anchors);
    for (before, pins_of) |row, list| try testing.expectEqualSlices(u32, row, list.items);
}
