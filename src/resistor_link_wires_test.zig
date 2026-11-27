//! Complete linked load outputs -> two physically separate actual ink trees.
//! Oracle: two three-terminal source trees, never labels; the literal paths
//! below independently prove that normal Canvas contact rules admit them.
//! The successful twelve-device placement request is borrowed, not inferred.
//!
//! Contents: literal frames and physical-ink oracle, fixture, then tests.

const std = @import("std");
const testing = std.testing;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const maze = @import("maze.zig");
const netlines = @import("netlines.zig");
const loads = @import("resistor_loads.zig");
const routing = @import("resistor_load_wires.zig");
const Pt = library.Pt;
const Side = library.Side;
const cards = "Linked\n.model nn nmos\n.model pp pmos\nML top top vdd vdd pp\nR1 top a 1k\nR2 top b 1k\nM1 a in1 tail 0 nn\nM2 b in2 tail 0 nn\nMT tail vb2 0 0 nn\nMN top2 top2 vdd vdd pp\nR3 top2 c 1k\nR4 top2 d 1k\nM3 c a tail2 0 nn\nM4 d b tail2 0 nn\nMU tail2 vb2 0 0 nn\n";
const names = [_][]const u8{ "ml", "r1", "r2", "m1", "m2", "mt", "mn", "r3", "r4", "m3", "m4", "mu" };
const positions = [_][2]f32{ .{ 100, -60 }, .{ 50, -20 }, .{ 150, -20 }, .{ 50, 80 }, .{ 150, 80 }, .{ 100, 160 }, .{ 400, -60 }, .{ 350, -20 }, .{ 450, -20 }, .{ 350, 80 }, .{ 450, 80 }, .{ 400, 160 } };
const endpoints = [_][3]Pt{
    .{ .{ .x = 50, .y = 0 }, .{ .x = 50, .y = 60 }, .{ .x = 330, .y = 80 } },
    .{ .{ .x = 150, .y = 0 }, .{ .x = 150, .y = 60 }, .{ .x = 470, .y = 80 } },
};
const source_paths = [_]canvas.Line{
    .of(&.{ .{ .x = 50, .y = 0 }, .{ .x = 50, .y = 60 } }),
    .of(&.{ .{ .x = 50, .y = 20 }, .{ .x = 310, .y = 20 }, .{ .x = 310, .y = 80 }, .{ .x = 330, .y = 80 } }),
    .of(&.{ .{ .x = 150, .y = 0 }, .{ .x = 150, .y = 60 } }),
    .of(&.{ .{ .x = 150, .y = 40 }, .{ .x = 250, .y = 40 }, .{ .x = 250, .y = 210 }, .{ .x = 490, .y = 210 }, .{ .x = 490, .y = 80 }, .{ .x = 470, .y = 80 } }),
};
// Measured native body gap40, with independent literal tracks for the two
// nets. This spacing is a fixture, not a claim about source distances.
const tight_endpoints = [_][3]Pt{
    .{ .{ .x = 50, .y = 0 }, .{ .x = 50, .y = 60 }, .{ .x = 210, .y = 80 } },
    .{ .{ .x = 150, .y = 0 }, .{ .x = 150, .y = 60 }, .{ .x = 350, .y = 80 } },
};
const tight_paths = [_]canvas.Line{
    .of(&.{ .{ .x = 50, .y = 0 }, .{ .x = 50, .y = 60 } }),
    .of(&.{ .{ .x = 50, .y = 20 }, .{ .x = 190, .y = 20 }, .{ .x = 190, .y = 80 }, .{ .x = 210, .y = 80 } }),
    .of(&.{ .{ .x = 150, .y = 0 }, .{ .x = 150, .y = 60 } }),
    .of(&.{ .{ .x = 150, .y = 40 }, .{ .x = 180, .y = 40 }, .{ .x = 180, .y = 210 }, .{ .x = 370, .y = 210 }, .{ .x = 370, .y = 80 }, .{ .x = 350, .y = 80 } }),
};
const tight_body_paths = [_]canvas.Line{
    .of(&.{ .{ .x = 50, .y = 0 }, .{ .x = 50, .y = 60 } }),
    .of(&.{ .{ .x = 50, .y = 20 }, .{ .x = 190, .y = 20 }, .{ .x = 190, .y = 80 }, .{ .x = 210, .y = 80 } }),
    .of(&.{ .{ .x = 150, .y = 0 }, .{ .x = 150, .y = 60 } }),
    .of(&.{ .{ .x = 150, .y = 40 }, .{ .x = 180, .y = 40 }, .{ .x = 180, .y = 250 }, .{ .x = 370, .y = 250 }, .{ .x = 370, .y = 80 }, .{ .x = 350, .y = 80 } }),
};
const tight_cascade_paths = [_]canvas.Line{
    .of(&.{ .{ .x = 50, .y = 0 }, .{ .x = 50, .y = 60 } }),
    .of(&.{ .{ .x = 50, .y = 20 }, .{ .x = 190, .y = 20 }, .{ .x = 190, .y = 80 }, .{ .x = 210, .y = 80 } }),
    .of(&.{ .{ .x = 150, .y = 0 }, .{ .x = 150, .y = 60 } }),
    .of(&.{ .{ .x = 150, .y = 40 }, .{ .x = 180, .y = 40 }, .{ .x = 180, .y = 290 }, .{ .x = 370, .y = 290 }, .{ .x = 370, .y = 80 }, .{ .x = 350, .y = 80 } }),
};
const contacts = [_]Pt{
    .{ .x = 50, .y = 30 },   .{ .x = 200, .y = 20 }, .{ .x = 310, .y = 50 },  .{ .x = 320, .y = 80 },
    .{ .x = 150, .y = 50 },  .{ .x = 200, .y = 40 }, .{ .x = 250, .y = 140 }, .{ .x = 400, .y = 210 },
    .{ .x = 490, .y = 140 }, .{ .x = 480, .y = 80 },
};
const Change = enum { none, tight, tight_body, tight_cascade, tight_blocked, tight_wire, permutation, projected, wrong_index, wrong_net, extra, hidden, absent, cut, label, explicit_wire, output, first, port, routed, drawn, no_owner };

// ---- private ----

fn on(w: maze.Wire, p: Pt) bool {
    return if (w.a.x == w.b.x) p.x == w.a.x and @min(w.a.y, w.b.y) <= p.y and p.y <= @max(w.a.y, w.b.y) else p.y == w.a.y and @min(w.a.x, w.b.x) <= p.x and p.x <= @max(w.a.x, w.b.x);
}
fn touches(a: maze.Wire, b: maze.Wire) bool {
    if (on(a, b.a) or on(a, b.b) or on(b, a.a) or on(b, a.b)) return true;
    if ((a.a.x == a.b.x) == (b.a.x == b.b.x)) return false;
    const point: Pt = if (a.a.x == a.b.x) .{ .x = a.a.x, .y = b.a.y } else .{ .x = b.a.x, .y = a.a.y };
    return on(a, point) and on(b, point);
}
// Foreign nets may cross strictly inside both segments. An endpoint on
// the other segment, including a collinear overlap, is a forbidden join.
fn foreignContact(a: maze.Wire, b: maze.Wire) bool {
    return on(a, b.a) or on(a, b.b) or on(b, a.a) or on(b, a.b);
}
fn connected(c: *const canvas.Canvas, net: u32, targets: [3]Pt) bool {
    std.debug.assert(c.segs.items.len <= 128);
    var seen: [128]bool = @splat(false);
    for (c.segs.items, 0..) |w, i| seen[i] = w.net == net and on(w, targets[0]);
    for (0..c.segs.items.len) |_| {
        var changed = false;
        for (c.segs.items, 0..) |a, i| {
            if (seen[i] or a.net != net) continue;
            for (c.segs.items, 0..) |b, j| if (seen[j] and touches(a, b)) {
                seen[i] = true;
                changed = true;
                break;
            };
        }
        if (!changed) break;
    }
    for (targets) |p| {
        const found = for (c.segs.items, 0..) |w, i| {
            if (seen[i] and on(w, p)) break true;
        } else false;
        if (!found) return false;
    }
    return true;
}
fn register(lib: *library.Library, hidden: bool) !void {
    for ([_]bool{ false, true }) |pmos| _ = try lib.register(.{ .name = if (pmos) "pmos" else "nmos", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 0, .y = if (pmos) 20 else -20 }, .side = if (pmos) .down else .up },
        .{ .name = "g", .at = .{ .x = if (pmos) 20 else -20, .y = 0 }, .side = if (pmos) .right else .left, .hidden = hidden and !pmos },
        .{ .name = "s", .at = .{ .x = 0, .y = if (pmos) -20 else 20 }, .side = if (pmos) .up else .down },
    }, .draw = &.{
        .{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .{ .x = 0, .y = 20 } } },
        .{ .line = .{ .a = .zero, .b = .{ .x = if (pmos) 20 else -20, .y = 0 } } },
    } });
    _ = try lib.register(.{ .name = "res", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "b", .at = .{ .x = 0, .y = 20 }, .side = .down },
    }, .draw = &.{.{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .{ .x = 0, .y = 20 } } }} });
}
fn run(gpa: std.mem.Allocator, change: Change, blocker: ?usize, crossing: bool, literal: bool) !void {
    const tight = switch (change) {
        .tight, .tight_body, .tight_cascade, .tight_blocked, .tight_wire => true,
        else => false,
    };
    const blocked = change == .tight_blocked or change == .tight_wire;
    const targets = if (tight) tight_endpoints else endpoints;
    var nl = try netlist.parse(gpa, &.{cards}, null);
    defer nl.deinit(gpa);
    const roles = try sch.guessRoles(gpa, &nl);
    defer gpa.free(roles);
    const nets = [2]u32{ nl.net("a").?.index(), nl.net("b").?.index() };
    const foreign = nl.net("in1").?.index();
    if (change == .output) roles[nets[1]] = .output;
    var lib = library.Library.init(gpa);
    defer lib.deinit();
    try register(&lib, change == .hidden);
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    const a = s.arena.allocator();
    var pair: loads.Pair = undefined;
    for (names, 0..) |name, i| pair[i / 6][i % 6] = nl.device(name).?;
    var xy: std.ArrayList([2]f32) = .empty;
    var boxes: [14]library.Rect = undefined;
    var box_count: usize = 12;
    for (0..s.devices.len) |d| {
        const member = for (names, 0..) |_, i| {
            if (pair[i / 6][i % 6].index() == d) break i;
        } else unreachable;
        const orient: library.Orient = .{ .mirror = member % 6 == 4 };
        s.devices.set(d, .{ .kept = true, .driver = false, .orientation = .horizontal, .flip_x = false, .flip_y = false, .class = s.devices.items(.class)[d], .orient = orient, .grid = .zero, .reach = @splat(20) });
        _ = try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = sch.none });
        var position = positions[member];
        if (tight and member >= 6) position[0] -= 120;
        try xy.append(a, position);
        boxes[d] = s.lib.at(s.devices.items(.class)[d]).box(orient, Pt.round(position));
    }
    // Foreign nominal bodies are literal Canvas obstacles, not extra
    // graph incidences. The first lift reveals the second body's row.
    if (change == .tight_body or change == .tight_cascade or change == .tight_wire) {
        boxes[12] = .{ .min = .{ .x = 320, .y = 200 }, .max = .{ .x = 340, .y = 240 } };
        box_count = 13;
    }
    if (change == .tight_cascade) {
        boxes[13] = .{ .min = .{ .x = 300, .y = 245 }, .max = .{ .x = 320, .y = 280 } };
        box_count = 14;
    }
    if (change == .tight_blocked) {
        boxes[12] = .{ .min = .{ .x = 171, .y = 90 }, .max = .{ .x = 189, .y = 120 } };
        box_count = 13;
    }
    const pins_of = try gpa.alloc(std.ArrayList(u32), roles.len);
    defer {
        for (pins_of) |*p| p.deinit(gpa);
        gpa.free(pins_of);
    }
    @memset(pins_of, .empty);
    for (0..s.devices.len) |d| {
        const row = s.devices.get(d);
        const class = lib.at(row.class);
        for (nl.graph.members(.from(@intCast(d))), 0..) |net, i| {
            if (i >= class.terminals.len) continue;
            // Keep the literal projected pin even in the hidden-class
            // admission control; Class.side intentionally hides that gate.
            const side = Side.of(row.orient.apply(class.terminals[i].side.?.unit())).?;
            const p = try s.addPin(.{ .home = @intCast(d), .side = side, .net = net.index(), .device = @intCast(d), .index = @intCast(i) });
            try pins_of[net.index()].append(gpa, p);
        }
    }
    s.xy = xy.items;
    for (nets, targets) |net, ps| for (ps) |point| {
        var found: usize = 0;
        for (pins_of[net].items) |p| if (canvas.pinAt(&s, p).eql(point)) {
            found += 1;
        };
        try testing.expectEqual(@as(usize, 1), found);
    };
    const gate = for (pins_of[nets[1]].items) |p| {
        if (s.pins.items(.device)[p] == pair[1][4].index()) break p;
    } else unreachable;
    if (change == .projected) {
        const node = try s.addNode(.{ .kind = .device, .ref = pair[1][4].index(), .group = pair[1][4].index() });
        // A right-facing pin takes x from its original group. Move the
        // copied node transversely so the routed point is actually wrong.
        try xy.append(a, .{ 460, 90 });
        s.pins.items(.home)[gate] = node;
        s.xy = xy.items;
        try testing.expectEqualDeep(Pt{ .x = 470, .y = 90 }, canvas.pinAt(&s, gate));
        try testing.expect(!canvas.pinAt(&s, gate).eql(endpoints[1][2]));
    }
    if (change == .wrong_index) s.pins.items(.index)[gate] = 0;
    if (change == .wrong_net) s.pins.items(.net)[gate] = foreign;
    if (change == .extra) {
        const node = try s.addNode(.{ .kind = .terminal, .ref = nets[1], .group = sch.none });
        try xy.append(a, .{ 600, 60 });
        const p = try s.addPin(.{ .home = node, .side = .left, .net = nets[1], .device = sch.none, .index = 0 });
        try pins_of[nets[1]].append(gpa, p);
    }
    if (change == .absent) {
        const unsupported = try lib.register(.{ .name = "missing_link_gate", .terminals = &.{.{ .name = "d", .at = .{ .x = 0, .y = -20 }, .side = .up }}, .draw = &.{} });
        s.devices.items(.class)[pair[1][4].index()] = unsupported;
    }
    if (change == .permutation) for (nets) |net| std.mem.reverse(u32, pins_of[net].items);
    s.xy = xy.items;
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), boxes[0..box_count], &.{});
    defer c.deinit();
    try testing.expect(try c.commit(foreign, &.{ .{ .x = 600, .y = 300 }, .{ .x = 640, .y = 300 } }));
    c.wall();
    if (change == .tight_wire) try testing.expect(try c.commit(foreign, &.{ .{ .x = 240, .y = 250 }, .{ .x = 260, .y = 250 } }));
    if (blocker) |i| {
        const vertical = i == 0 or i == 2 or i == 4 or i == 6 or i == 8;
        const delta: Pt = if (vertical) .{ .x = 5, .y = 0 } else .{ .x = 0, .y = 5 };
        try testing.expect(try c.commit(foreign, &.{ if (crossing) contacts[i].sub(delta) else contacts[i], contacts[i].add(delta) }));
    }
    if (literal) {
        const before = c.save();
        var success = true;
        const paths = switch (change) {
            .tight_body, .tight_wire => tight_body_paths,
            .tight_cascade => tight_cascade_paths,
            else => if (tight) tight_paths else source_paths,
        };
        for (paths, 0..) |path, i| {
            if (!try c.commit(nets[i / 2], path.slice())) {
                success = false;
                break;
            }
        }
        try testing.expectEqual(!blocked and (blocker == null or crossing), success);
        if (success) for (nets, targets) |net, ps| try testing.expect(connected(&c, net, ps));
        c.restore(before);
        return;
    }
    const styles = try gpa.alloc(netlines.Style, roles.len);
    defer gpa.free(styles);
    @memset(styles, .auto);
    styles[nets[1]] = switch (change) {
        .cut => .cut,
        .label => .label,
        .explicit_wire => .wire,
        else => .auto,
    };
    const ports = try gpa.alloc(?Side, roles.len);
    defer gpa.free(ports);
    @memset(ports, null);
    if (change == .port) ports[nets[1]] = .right;
    const rails = try gpa.alloc(netlines.Rail, roles.len);
    defer gpa.free(rails);
    @memset(rails, .auto);
    const lines: netlines.NetLines = .{ .style = styles, .port = ports, .rail = rails, .first = if (change == .first) &.{foreign} else &.{}, .routes = &.{} };
    const routed = try gpa.alloc(bool, roles.len);
    defer gpa.free(routed);
    @memset(routed, false);
    if (change == .routed) routed[nets[1]] = true;
    const drawn = try gpa.alloc(bool, roles.len);
    defer gpa.free(drawn);
    @memset(drawn, false);
    // The first load-bar consumer already succeeded; this transaction only
    // owns the two full interstage nets. Earlier ink must survive failure.
    drawn[nl.net("top").?.index()] = true;
    drawn[nl.net("top2").?.index()] = true;
    if (change == .drawn) drawn[nets[1]] = true;
    try c.segs.shrinkAndFreePrecise(gpa, c.segs.items.len);
    try c.segs.ensureTotalCapacityPrecise(gpa, c.segs.items.len + 1);
    try c.points.shrinkAndFreePrecise(gpa, c.points.items.len);
    try c.points.ensureTotalCapacityPrecise(gpa, c.points.items.len + 2);
    const before = c.save();
    const old_segments = try gpa.dupe(maze.Wire, c.segs.items);
    defer gpa.free(old_segments);
    const old_points = try gpa.dupe(maze.Mark, c.points.items);
    defer gpa.free(old_points);
    const old_routes = try gpa.dupe(sch.Route, s.routes.items);
    defer gpa.free(old_routes);
    routing.seed(&c, &nl, &.{}, if (change == .no_owner) &.{} else &.{pair}, &lines, pins_of, routed, drawn) catch |err| {
        try testing.expectEqualDeep(before, c.save());
        try testing.expectEqualDeep(old_segments, c.segs.items);
        try testing.expectEqualDeep(old_points, c.points.items);
        try testing.expectEqualDeep(old_routes, s.routes.items);
        try testing.expect(!drawn[nets[0]] and !drawn[nets[1]]);
        return err;
    };
    const expected = (change == .none or tight or change == .permutation) and !blocked and (blocker == null or crossing);
    errdefer std.debug.print("linked trees {s}, blocker {?}, crossing={} drawn={}/{}\n", .{ @tagName(change), blocker, crossing, drawn[nets[0]], drawn[nets[1]] });
    try testing.expectEqual(expected, drawn[nets[0]]);
    try testing.expectEqual(expected or change == .drawn, drawn[nets[1]]);
    if (expected) {
        for (nets, targets) |net, ps| try testing.expect(connected(&c, net, ps));
        for (c.segs.items) |x| if (x.net == nets[0]) {
            for (c.segs.items) |y| if (y.net == nets[1]) try testing.expect(!foreignContact(x, y));
        };
        if (change == .tight_cascade) {
            try testing.expect(c.onNet(nets[1], .{ .x = 180, .y = 290 }));
            try testing.expect(c.onNet(nets[1], .{ .x = 370, .y = 290 }));
            const saved_segments = try gpa.dupe(maze.Wire, c.segs.items);
            defer gpa.free(saved_segments);
            const saved_points = try gpa.dupe(maze.Mark, c.points.items);
            defer gpa.free(saved_points);
            const saved_routes = try gpa.dupe(sch.Route, s.routes.items);
            defer gpa.free(saved_routes);
            c.restore(before);
            for (nets) |net| drawn[net] = false;
            std.mem.swap(library.Rect, &boxes[12], &boxes[13]);
            try routing.seed(&c, &nl, &.{}, &.{pair}, &lines, pins_of, routed, drawn);
            try testing.expect(drawn[nets[0]] and drawn[nets[1]]);
            try testing.expectEqualDeep(saved_segments, c.segs.items);
            try testing.expectEqualDeep(saved_points, c.points.items);
            try testing.expectEqualDeep(saved_routes, s.routes.items);
        }
    } else {
        try testing.expectEqualDeep(before, c.save());
        try testing.expectEqualDeep(old_segments, c.segs.items);
        try testing.expectEqualDeep(old_points, c.points.items);
        try testing.expectEqualDeep(old_routes, s.routes.items);
    }
}

// ---- tests ----

test "linked load trees: source paths obey ordinary contact and proper-crossing rules" {
    try run(testing.allocator, .none, null, false, true);
    for (0..contacts.len) |i| {
        try run(testing.allocator, .none, i, false, true);
        try run(testing.allocator, .none, i, true, true);
    }
}

test "linked load trees: both complete actual three-pin trees commit independent of pin order" {
    try run(testing.allocator, .none, null, false, false);
    try run(testing.allocator, .permutation, null, false, false);
}

test "linked load trees: malformed ownership projections caller choices and either-net contacts abort both" {
    for ([_]Change{ .projected, .wrong_index, .wrong_net, .extra, .hidden, .absent, .cut, .label, .explicit_wire, .output, .first, .port, .routed, .drawn, .no_owner }) |change| try run(testing.allocator, change, null, false, false);
    for (0..contacts.len) |i| try run(testing.allocator, .none, i, false, false);
}

test "linked load trees: proper interior foreign crossings do not become endpoint contacts" {
    for (0..contacts.len) |i| try run(testing.allocator, .none, i, true, false);
}

test "linked load trees: every allocation failure restores both trees and earlier ink" {
    try testing.checkAllAllocationFailures(testing.allocator, run, .{ .none, @as(?usize, null), false, false });
}

test "linked load trees: forty-unit body gap needs distinct tracks for the two actual trees" {
    try run(testing.allocator, .tight, null, false, true);
    try run(testing.allocator, .tight, null, false, false);
}

test "linked load trees: lower corridor clears actual foreign bodies including a cascading row" {
    for ([_]Change{ .tight_body, .tight_cascade }) |change| {
        try run(testing.allocator, change, null, false, true);
        try run(testing.allocator, change, null, false, false);
    }
}

test "linked load trees: blocked vertical leg or lower foreign wire restores both trees" {
    for ([_]Change{ .tight_blocked, .tight_wire }) |change| {
        try run(testing.allocator, change, null, false, true);
        try run(testing.allocator, change, null, false, false);
    }
}

test "linked load trees: foreign-contact oracle permits strict crossings but rejects ends T and overlap" {
    const a: maze.Wire = .{ .a = .{ .x = 0, .y = 0 }, .b = .{ .x = 20, .y = 0 }, .net = 0 };
    const cross: maze.Wire = .{ .a = .{ .x = 10, .y = -10 }, .b = .{ .x = 10, .y = 10 }, .net = 1 };
    try testing.expect(!foreignContact(a, cross));
    try testing.expect(touches(a, cross)); // Same-net ink joins at a crossing.
    for ([_]maze.Wire{
        .{ .a = .{ .x = 10, .y = 0 }, .b = .{ .x = 10, .y = 10 }, .net = 1 },
        .{ .a = .{ .x = 20, .y = 0 }, .b = .{ .x = 30, .y = 0 }, .net = 1 },
        .{ .a = .{ .x = 5, .y = 0 }, .b = .{ .x = 15, .y = 0 }, .net = 1 },
    }) |b| {
        try testing.expect(foreignContact(a, b));
        try testing.expect(foreignContact(b, a));
    }
}
