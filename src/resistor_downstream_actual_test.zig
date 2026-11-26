//! Real linked-interface devices -> exact actual-pin partitions and rollback.
//! Oracle: literal R/D physical pair, isolated gate, one bound name on each,
//! full unchanged-prefix comparison on every rejection and allocation error.
//!
//! Contents: real device fixture, pin/symbol oracle, then tests.

const std = @import("std");
const testing = std.testing;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const canvas = @import("canvas.zig");
const netlines = @import("netlines.zig");
const pinned = @import("pinned.zig");
const loads = @import("resistor_loads.zig");
const routing = @import("resistor_downstream.zig");
const oracle = @import("ct_four_wire_oracle.zig");
const Pt = library.Pt;
const cards = "Linked\n.model nn nmos\n.model pp pmos\n" ++
    "ML top top vdd vdd pp\nR1 top a 1k\nR2 top b 1k\nM1 a in1 tail 0 nn\nM2 b in2 tail 0 nn\nMT tail vb2 0 0 nn\n" ++
    "MN top2 top2 vdd vdd pp\nR3 top2 c 1k\nR4 top2 d 1k\nM3 c a tail2 0 nn\nM4 d b tail2 0 nn\nMU tail2 vb2 0 0 nn\n" ++
    "MI out c common 0 nn\nRI vdd out 1k\nMF vdd out nf 0 nn\nMP np out vdd vdd pp\n" ++
    "MJ out2 d common 0 nn\nRJ vdd out2 1k\nMG vdd out2 ng 0 nn\nMQ nq out2 vdd vdd pp\n";
const names = [_][]const u8{ "ml", "r1", "r2", "m1", "m2", "mt", "mn", "r3", "r4", "m3", "m4", "mu", "mi", "ri", "mf", "mp", "mj", "rj", "mg", "mq" };
const targets = [_]Pt{ .{ .x = 500, .y = 0 }, .{ .x = 500, .y = 40 }, .{ .x = 580, .y = 250 } };
const Change = enum { none, permutation, cut, hidden, projected, wrong_index, wrong_net, extra, missing, existing, label, wire, port, first, route, at, output, routed, drawn, no_owner };

// ---- private ----

fn run(gpa: std.mem.Allocator, change: Change) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{cards}, null);
    const roles = try sch.guessRoles(a, &nl);
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    for ([_][]const u8{ "nmos", "pmos" }) |name| _ = try lib.register(.{ .name = name, .terminals = &.{
        .{ .name = "d", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "g", .at = .{ .x = -20, .y = 0 }, .side = .left, .hidden = change == .hidden },
        .{ .name = "s", .at = .{ .x = 0, .y = 20 }, .side = .down },
        .{ .name = "b", .at = .zero, .hidden = true },
    }, .draw = &.{
        .{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .{ .x = 0, .y = 20 } } },
        .{ .line = .{ .a = .zero, .b = .{ .x = -20, .y = 0 } } },
    } });
    _ = try lib.register(.{ .name = "res", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "b", .at = .{ .x = 0, .y = 20 }, .side = .down },
    }, .draw = &.{.{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .{ .x = 0, .y = 20 } } }} });
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    const sa = s.arena.allocator();
    var pair: loads.Pair = undefined;
    for (names[0..12], 0..) |name, i| pair[i/6][i%6] = nl.device(name).?;
    var xy: std.ArrayList([2]f32) = .empty;
    var boxes: [20]library.Rect = undefined;
    for (0..s.devices.len) |d| {
        const member = for (names, 0..) |name, i| { if (nl.device(name).?.index() == d) break i; } else unreachable;
        var at: Pt = .{ .x = -1500 + @as(i32, @intCast(member)) * 80, .y = 500 };
        at = switch (member) {
            6 => .{ .x = 450, .y = -200 }, 7 => .{ .x = 400, .y = -20 }, 8 => .{ .x = 500, .y = -20 },
            9 => .{ .x = 400, .y = 60 }, 10 => .{ .x = 500, .y = 60 }, 11 => .{ .x = 450, .y = 120 },
            12 => .{ .x = 200, .y = 250 }, 16 => .{ .x = 600, .y = 250 }, else => at,
        };
        const class = lib.at(s.devices.items(.class)[d]);
        s.devices.set(d, .{ .kept = true, .driver = false, .orientation = .horizontal, .flip_x = false, .flip_y = false, .class = s.devices.items(.class)[d], .orient = .{}, .grid = .zero, .reach = @splat(20) });
        try testing.expectEqual(d, try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = sch.none }));
        try xy.append(sa, at.toF());
        boxes[d] = class.box(.{}, at);
    }
    const pins_of = try a.alloc(std.ArrayList(u32), roles.len);
    @memset(pins_of, .empty);
    for (0..s.devices.len) |d| {
        const class = lib.at(s.devices.items(.class)[d]);
        for (nl.graph.members(.from(@intCast(d))), 0..) |net, i| {
            if (i == 3) continue; // Body remains a raw binding, never a fabricated visible lead.
            const side = class.terminals[i].side.?;
            const pin = try s.addPin(.{ .home = @intCast(d), .side = side, .net = net.index(), .device = @intCast(d), .index = @intCast(i) });
            try pins_of[net.index()].append(a, pin);
        }
    }
    s.xy = xy.items;
    const net = nl.net("d").?.index();
    const other = nl.net("c").?.index();
    const foreign = nl.net("in1").?.index();
    var ids: [3]u32 = undefined;
    for ([_][]const u8{ "r4", "m4", "mj" }, [_]usize{ 1, 0, 1 }, &ids, targets) |name, index, *id, target| {
        id.* = for (pins_of[net].items) |pin| {
            if (s.pins.items(.device)[pin] == nl.device(name).?.index() and s.pins.items(.index)[pin] == index) break pin;
        } else unreachable;
        try testing.expectEqualDeep(target, canvas.pinAt(&s, id.*));
    }
    if (change == .projected) {
        const d = nl.device("mj").?.index();
        const node = try s.addNode(.{ .kind = .device, .ref = d, .group = d });
        try xy.append(sa, .{ 600, 260 });
        s.pins.items(.home)[ids[2]] = node;
        s.xy = xy.items;
        try testing.expectEqualDeep(Pt{ .x = 580, .y = 260 }, canvas.pinAt(&s, ids[2]));
        try testing.expect(!canvas.pinAt(&s, ids[2]).eql(targets[2]));
    }
    if (change == .wrong_index) s.pins.items(.index)[ids[2]] = 2;
    if (change == .wrong_net) s.pins.items(.net)[ids[2]] = foreign;
    if (change == .missing) pins_of[net].items = pins_of[net].items[0..2];
    if (change == .extra) {
        const node = try s.addNode(.{ .kind = .terminal, .ref = net, .group = sch.none });
        try xy.append(sa, .{ 900, 900 });
        const pin = try s.addPin(.{ .home = node, .side = .left, .net = net, .device = sch.none, .index = 0 });
        try pins_of[net].append(a, pin);
    }
    if (change == .permutation) std.mem.reverse(u32, pins_of[net].items);
    s.xy = xy.items;
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &boxes, &.{});
    defer c.deinit();
    try testing.expect(try c.commit(foreign, &.{ .{ .x = -2000, .y = -500 }, .{ .x = -1960, .y = -500 } }));
    c.wall();
    if (change == .existing) try testing.expect(try c.commit(net, &.{ .{ .x = 1000, .y = 1000 }, .{ .x = 1040, .y = 1000 } }));
    const styles = try a.alloc(netlines.Style, roles.len); @memset(styles, .auto);
    const ports = try a.alloc(?library.Side, roles.len); @memset(ports, null);
    const rails = try a.alloc(netlines.Rail, roles.len); @memset(rails, .auto);
    var lines: netlines.NetLines = .{ .style = styles, .port = ports, .rail = rails, .first = &.{}, .routes = &.{} };
    const owners = [_]loads.Pair{pair};
    const qualified = routing.qualify(&nl, roles, &owners, &.{}, &.{}, &.{}, &lines);
    try testing.expectEqual(@as(usize, 1), qualified.len);
    styles[net] = switch (change) { .cut => .cut, .label => .label, .wire => .wire, else => .auto };
    if (change == .port) ports[net] = .left;
    if (change == .first) lines.first = &.{net};
    if (change == .output) {
        roles[net] = .output;
        s.roles = roles; // initDevices copied the original roles before this mutation.
        try testing.expectEqual(sch.Role.output, c.s.roles[net]);
    }
    const ats = try a.alloc(?pinned.At, s.devices.len); @memset(ats, null);
    if (change == .at) ats[nl.device("mg").?.index()] = .{ .origin = .{ .x = 100, .y = 100 }, .orient = null, .line = 0 };
    const routes = [_]netlines.Route{.{ .net = net, .pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 40, .y = 0 } }, .via = false, .line = 0 }};
    const routed = try a.alloc(bool, roles.len); @memset(routed, false);
    const drawn = try a.alloc(bool, roles.len); @memset(drawn, false);
    drawn[other] = true; // An earlier independent net is already consumed.
    if (change == .routed) routed[net] = true;
    if (change == .drawn) drawn[net] = true;
    const before = try oracle.Before.take(&c, drawn);
    defer before.deinit();
    routing.parts(&c, &nl, if (change == .no_owner) &.{} else qualified, &lines, .{ .routes = if (change == .route) &routes else &.{}, .ats = ats }, pins_of, routed, drawn) catch |err| {
        try before.matches(&c, drawn);
        return err;
    };
    const success = change == .none or change == .permutation or change == .cut;
    if (!success) { try before.matches(&c, drawn); return; }
    try testing.expect(drawn[net]);
    try testing.expect(try oracle.joined(&c, ids[0], ids[1]));
    try testing.expect(!try oracle.joined(&c, ids[0], ids[2]));
    try testing.expect(!try oracle.joined(&c, ids[1], ids[2]));
    try testing.expectEqual(before.pins.len + 2, s.pins.len);
    for ([_]u32{ ids[0], ids[2] }) |representative| {
        var count: usize = 0;
        for (before.pins.len..s.pins.len) |pin| {
            const row = s.pins.get(pin);
            try testing.expectEqual(net, row.net);
            try testing.expectEqual(sch.none, row.device);
            try testing.expectEqual(sch.NodeKind.label, s.nodes.items(.kind)[row.home]);
            try testing.expectEqual(net, s.nodes.items(.ref)[row.home]);
            if (try oracle.joined(&c, representative, @intCast(pin))) count += 1;
        }
        try testing.expectEqual(@as(usize, 1), count);
    }
}

fn oom(gpa: std.mem.Allocator) !void { try run(gpa, .none); }

test "resistor downstream actual: real local ink remote name and current cut retain two components" {
    for ([_]Change{ .none, .permutation, .cut }) |change| try run(testing.allocator, change);
}

test "resistor downstream actual: malformed projected hidden and requested cases preserve every row" {
    for ([_]Change{ .hidden, .projected, .wrong_index, .wrong_net, .extra, .missing, .existing, .label, .wire, .port, .first, .route, .at, .output, .routed, .drawn, .no_owner }) |change| {
        errdefer std.debug.print("downstream actual change={t}\n", .{change});
        try run(testing.allocator, change);
    }
}

test "resistor downstream actual: both component allocations roll back on every failure" {
    var backing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(backing.allocator(), oom, .{});
}
