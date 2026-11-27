//! Real26-device Canvas fixture and original-request/failure variations.
//! Oracle/provenance: docs/research/figures/ct_four_wires_tests.json.
//! Frozen RED7 assertions and fixture values; no production topology oracle.
//!
//! Contents: Change, run, group.

const std = @import("std");
const testing = std.testing;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const netlist = @import("netlist.zig");
const netlines = @import("netlines.zig");
const hints = @import("hints.zig");
const canvas = @import("canvas.zig");
const trunk = @import("trunk.zig");
const maze = @import("maze.zig");
const owner = @import("ct_four_sides.zig");
const routing = @import("ct_four_wires.zig");
const requests = @import("wire_requests.zig");
const literal = @import("ct_four_wire_data.zig");
const Pt = library.Pt;
const oracle = @import("ct_four_wire_oracle.zig");
const Before = oracle.Before;
const joined = oracle.joined;
const expectPairs = oracle.expectPairs;
const componentSymbols = oracle.componentSymbols;

/// Each frozen variation changes one admission/transaction boundary.
pub const Change = enum { none, permuted, cut, label, wire, trunk, ladder, route_style, first, port, route, via, at, routed, drawn, no_owner, missing, duplicate, wrong_index, wrong_net, projected, hidden, extra, existing_same_net, late_blocker };

const members = [_][]const u8{ "xl1", "xl2", "ls1", "ls2", "ls3", "ls4", "c1", "c2", "m12", "m13", "m10", "m11", "m14", "m7", "m8", "m5", "m6", "m9", "m15", "m16", "m17", "m18", "m19", "m20", "m21", "m22" };
const selected_nets = [_][]const u8{ "p2", "m2", "p1", "m1", "p3", "m3" };

/// Runs the exact frozen real-device fixture, including every assertion.
pub fn run(gpa: std.mem.Allocator, comptime compact: bool, change: Change, whole: bool, rail_only: bool) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    try lib.loadZon(a, literal.symbols, null);
    var nl = try netlist.parse(a, &.{literal.deck}, null);
    const roles = try sch.guessRoles(a, &nl);
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    var raw_count: usize = 0;
    for (group(&nl)) |edge| raw_count += nl.graph.members(edge).len;
    try testing.expectEqual(@as(usize, 90), raw_count);
    try testing.expectEqual(@as(usize, 72), literal.pins_on.len);
    var xy: std.ArrayList([2]f32) = .empty;
    const poses = if (compact) literal.poses_on else literal.poses_off;
    const pins = if (compact) literal.pins_on else literal.pins_off;
    var bodies: [26]library.Rect = undefined;
    for (0..s.devices.len) |d| {
        const pose = for (poses) |p| {
            if (nl.device(p.name).?.index() == d) break p;
        } else unreachable;
        const class = lib.at(s.devices.items(.class)[d]);
        var reach: [4]i32 = @splat(0);
        for (class.terminals, 0..) |terminal, index| {
            if (!class.shows(index)) continue;
            const side = class.side(index, pose.orient).?;
            const v = pose.orient.apply(terminal.at);
            const u = side.unit();
            try testing.expect(if (side.isHorizontal()) v.y == 0 else v.x == 0);
            reach[@backingInt(side)] = v.x * u.x + v.y * u.y;
        }
        s.devices.set(d, .{ .kept = true, .driver = false, .orientation = .horizontal, .flip_x = false, .flip_y = false, .class = s.devices.items(.class)[d], .orient = pose.orient, .grid = .zero, .reach = reach });
        try testing.expectEqual(d, try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = sch.none }));
        try xy.append(s.arena.allocator(), pose.at.toF());
        bodies[d] = class.box(pose.orient, pose.at);
    }
    const pins_of = try a.alloc(std.ArrayList(u32), roles.len);
    @memset(pins_of, .empty);
    for (pins, 0..) |p, i| {
        const d = nl.device(p.name).?.index();
        const row = s.devices.get(d);
        const class = lib.at(row.class);
        const n = realNet(&nl, p.net);
        try testing.expectEqual(n, nl.graph.members(.from(d))[p.index].index());
        try testing.expect(class.shows(p.index));
        const actual = Pt.round(xy.items[d]).add(row.orient.apply(class.terminals[p.index].at));
        try testing.expectEqualDeep(p.xy, actual);
        const handle = try s.addPin(.{ .home = d, .side = class.side(p.index, row.orient).?, .net = n, .device = d, .index = p.index });
        try testing.expectEqual(i, handle);
        try pins_of[n].append(a, handle);
    }
    s.xy = xy.items;
    for (pins, 0..) |p, i| try testing.expectEqualDeep(p.xy, canvas.pinAt(&s, @intCast(i)));
    const target = nl.net(if (rail_only) "vdd" else "p3").?.index();
    const foreign = nl.net("hb").?.index();
    const touched = pin(if (rail_only) "xl1" else "ls3", if (rail_only) 2 else 0);
    switch (change) {
        .permuted => for (pins_of) |list| std.mem.reverse(u32, list.items),
        .missing => {
            pins_of[target].items.len -= 1;
        },
        .duplicate => {
            pins_of[target].items[1] = pins_of[target].items[0];
        },
        .wrong_index => {
            s.pins.items(.index)[touched] = 1;
        },
        .wrong_net => {
            s.pins.items(.net)[touched] = foreign;
        },
        .projected => {
            const d = s.pins.items(.device)[touched];
            const copy = try s.addNode(.{ .kind = .device, .ref = d, .group = d });
            try xy.append(s.arena.allocator(), .{ s.xy[d][0] + 10, s.xy[d][1] });
            s.pins.items(.home)[touched] = copy;
        },
        .hidden => {
            const d = s.pins.items(.device)[touched];
            const old = lib.at(s.devices.items(.class)[d]);
            const terms = try a.dupe(library.Terminal, old.terminals);
            terms[s.pins.items(.index)[touched]].hidden = true;
            s.devices.items(.class)[d] = try lib.register(.{ .name = "hidden_fixture", .terminals = terms, .draw = old.draw });
        },
        .extra => {
            const node = try s.addNode(.{ .kind = .terminal, .ref = target, .group = sch.none });
            try xy.append(s.arena.allocator(), .{ 1400, 800 });
            const p = try s.addPin(.{ .home = node, .side = .left, .net = target, .device = sch.none, .index = 0 });
            try pins_of[target].append(a, p);
        },
        else => {},
    }
    s.xy = xy.items;
    if (change == .projected) {
        const original = pins[touched].xy;
        try testing.expect(!canvas.pinAt(&s, touched).eql(original));
        const d = s.pins.items(.device)[touched];
        const row = s.devices.get(d);
        const class = lib.at(row.class);
        try testing.expectEqualDeep(original, Pt.round(s.xy[d]).add(row.orient.apply(class.terminals[s.pins.items(.index)[touched]].at)));
    }
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &bodies, &.{});
    defer c.deinit();
    for (if (compact) literal.wires_on else literal.wires_off) |wire| {
        const n = realNet(&nl, wire.net);
        try s.routes.append(s.arena.allocator(), .{ .net = n, .len = 2, .pts = .{ wire.a.toF(), wire.b.toF(), .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 }, .{ 0, 0 } } });
        try c.segs.append(gpa, .{ .a = wire.a, .b = wire.b, .net = n, .wall = wire.wall });
        try c.points.appendSlice(gpa, &.{ .{ .at = wire.a, .net = n }, .{ .at = wire.b, .net = n } });
    }
    if (change == .existing_same_net) try testing.expect(try c.commit(target, &.{ .{ .x = 1400, .y = 800 }, .{ .x = 1440, .y = 800 } }));
    if (change == .late_blocker) {
        // Preserve the independently GREEN feasibility order: the remote
        // three-pin part first, then the local CT/L pair. The blocker is
        // only on the second component's original LS3 pin.
        try c.points.append(gpa, .{ .at = canvas.pinAt(&s, pin("ls3", 0)), .net = foreign });
        const saved = c.save();
        const old_pins = s.pins.len;
        const old_xy = xy.items.len;
        try testing.expect(try trunk.draw(&c, target, &.{ pin("m15", 1), pin("m16", 0), pin("m18", 2) }, .name));
        try testing.expect(s.nodes.len > saved.nodes);
        try testing.expectEqual(old_pins + 1, s.pins.len);
        try testing.expectEqual(target, s.pins.items(.net)[old_pins]);
        try testing.expectEqual(target, s.nodes.items(.ref)[s.pins.items(.home)[old_pins]]);
        try testing.expect(try joined(&c, pin("m15", 1), @intCast(old_pins)));
        try testing.expect(!try joined(&c, pin("ls3", 0), @intCast(old_pins)));
        s.pins.shrinkRetainingCapacity(old_pins);
        s.nodes.shrinkRetainingCapacity(saved.nodes);
        xy.shrinkRetainingCapacity(old_xy);
        s.xy = xy.items;
        c.restore(saved);
    }
    const styles = try a.alloc(netlines.Style, roles.len);
    @memset(styles, if (whole) .auto else .label);
    styles[target] = .auto;
    styles[target] = switch (change) {
        .cut => .cut,
        .label => .label,
        .wire => .wire,
        .trunk => .trunk,
        .ladder => .ladder,
        .route_style => .route,
        else => styles[target],
    };
    const ports = try a.alloc(?library.Side, roles.len);
    @memset(ports, null);
    if (change == .port) ports[target] = .left;
    const rails = try a.alloc(netlines.Rail, roles.len);
    @memset(rails, .auto);
    rails[nl.net("vdd").?.index()] = .bar;
    const path = [_]Pt{ .{ .x = -200, .y = -200 }, .{ .x = -160, .y = -200 } };
    const explicit_routes = [_]netlines.Route{.{ .net = target, .pts = &path, .via = change == .via, .line = 0 }};
    const ats = try a.alloc(?@import("pinned.zig").At, s.devices.len);
    @memset(ats, null);
    if (change == .at) ats[nl.device("m15").?.index()] = .{ .origin = .{ .x = -200, .y = -200 }, .orient = .r0, .line = 0 };
    const intent: requests.Requests = .{ .routes = if (change == .route or change == .via) &explicit_routes else &.{}, .ats = ats };
    const first = [_]u32{foreign};
    const lines: netlines.NetLines = .{ .style = styles, .port = ports, .rail = rails, .first = if (change == .first) &first else &.{}, .routes = &.{} };
    const routed = try a.alloc(bool, roles.len);
    @memset(routed, false);
    routed[target] = change == .routed;
    const drawn = try a.alloc(bool, roles.len);
    @memset(drawn, false);
    drawn[target] = change == .drawn;
    const g = group(&nl);
    const groups: []const owner.Group = if (change == .no_owner) &.{} else &.{g};
    const before = try Before.take(&c, drawn);
    defer before.deinit();
    if (whole or rail_only) routing.rail(&c, &nl, groups, &lines, intent, pins_of, routed, drawn) catch |err| {
        try before.matches(&c, drawn);
        return err;
    };
    if (!rail_only) routing.parts(&c, &nl, groups, &lines, intent, pins_of, routed, drawn) catch |err| {
        // One target per allocation test; successful earlier unrelated nets
        // need not roll back. Whole-scene success is checked without OOM.
        if (!whole) try before.matches(&c, drawn);
        return err;
    };
    const success = change == .none or change == .permuted or change == .cut;
    errdefer std.debug.print("whole26 consumer compact={} mode={s} whole={} rail={}\n", .{ compact, @tagName(change), whole, rail_only });
    try testing.expectEqual(success or change == .drawn, drawn[target]);
    if (!success) {
        try before.matches(&c, drawn);
        return;
    }
    if (whole) {
        for (selected_nets) |name| try testing.expect(drawn[nl.net(name).?.index()]);
        try testing.expect(drawn[nl.net("vdd").?.index()]);
        try expectPairs(&c, null);
    } else try expectPairs(&c, target);
    if (!rail_only) try testing.expect(try componentSymbols(&c, &nl, before.pins.len, if (whole) null else target));
    if (rail_only or whole) {
        var count: usize = 0;
        for (before.nodes.len..s.nodes.len) |i| if (s.nodes.items(.kind)[i] == .terminal and s.nodes.items(.ref)[i] == nl.net("vdd").?.index()) {
            count += 1;
        };
        try testing.expectEqual(@as(usize, 1), count);
    } else {
        try testing.expectEqual(before.nodes.len + 2, s.nodes.len);
        // A missing second leaf leaves all original physical pair answers
        // unchanged. The independent named-component oracle must catch it.
        s.pins.shrinkRetainingCapacity(s.pins.len - 1);
        s.nodes.shrinkRetainingCapacity(s.nodes.len - 1);
        xy.shrinkRetainingCapacity(xy.items.len - 1);
        s.xy = xy.items;
        try expectPairs(&c, target);
        try testing.expect(!try componentSymbols(&c, &nl, before.pins.len, target));
    }
}

/// Resolves the named literal fixture members; never used by production.
pub fn group(nl: *const netlist.Netlist) owner.Group {
    var g: owner.Group = undefined;
    for (members, &g) |name, *edge| edge.* = nl.device(name).?;
    return g;
}

// ---- private ----

fn pin(name: []const u8, index: u8) u32 {
    for (literal.pins_on, 0..) |p, i| if (p.index == index and std.mem.eql(u8, p.name, name)) return @intCast(i);
    unreachable;
}

fn realNet(nl: *const netlist.Netlist, i: u32) u32 {
    return nl.net(literal.nets[i]).?.index();
}
