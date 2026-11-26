//! Literal load-tree routing boundary, independent of stage placement.
//! Oracle: the source bar contains every point between the two resistor
//! tips. Labels or a nearby parallel trunk cannot satisfy that interval.
//! The three literal paths fit normal Canvas rules, including rejection
//! of every foreign endpoint and permission for proper interior crossings.
//!
//! Contents: literal fixture helpers, then source-bar and contact tests.

const std = @import("std");
const testing = std.testing;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const trunk = @import("trunk.zig");
const netlist = @import("netlist.zig");
const netlines = @import("netlines.zig");
const loads = @import("resistor_loads.zig");
const routing = @import("resistor_load_wires.zig");
const Pt = library.Pt;
const Side = library.Side;

const terminals = [_]Pt{
    .{ .x = 60, .y = 40 }, // diode load drain
    .{ .x = 80, .y = 20 }, // diode load gate
    .{ .x = 0, .y = 60 }, // left resistor load end
    .{ .x = 120, .y = 60 }, // right resistor load end
};
const bodies = [_]library.Rect{
    .{ .min = .{ .x = 50, .y = 0 }, .max = .{ .x = 80, .y = 40 } },
    .{ .min = .{ .x = -6, .y = 60 }, .max = .{ .x = 6, .y = 100 } },
    .{ .min = .{ .x = 114, .y = 60 }, .max = .{ .x = 126, .y = 100 } },
};
const wanted = [_]canvas.Line{
    .of(&.{ .{ .x = 0, .y = 60 }, .{ .x = 120, .y = 60 } }),
    .of(&.{ .{ .x = 60, .y = 40 }, .{ .x = 60, .y = 60 } }),
    .of(&.{ .{ .x = 80, .y = 20 }, .{ .x = 120, .y = 20 }, .{ .x = 120, .y = 60 } }),
};

const Change = enum { none, reverse_card, permutation, projected, wrong_index, wrong_net, fifth, hidden, absent, cut, label, explicit_wire, output, first, port, routed, already_drawn, no_owner };
const cards = "Load\n.model nn nmos\n.model pp pmos\nML top top vdd vdd pp\nR1 top a 1k\nR2 top b 1k\nM1 a in1 tail 0 nn\nM2 b in2 tail 0 nn\nMT tail vb2 0 0 nn\n";


// ---- private ----

fn populate(s: *sch.Schematic, xy: *std.ArrayList([2]f32)) !void {
    for (terminals, [_]Side{ .down, .right, .up, .up }) |at, side| {
        const node = try s.addNode(.{ .kind = .terminal, .ref = 0, .group = sch.none });
        try xy.append(s.arena.allocator(), at.toF());
        _ = try s.addPin(.{ .home = node, .side = side, .net = 0, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
}

fn bar(c: *const canvas.Canvas) !void {
    for (0..121) |x| try testing.expect(c.onNet(0, .{ .x = @intCast(x), .y = 60 }));
}



fn consumer(gpa: std.mem.Allocator, change: Change, blocker: ?usize, crossing: bool) !void {
    const deck = if (change == .reverse_card) "Load\n.model nn nmos\n.model pp pmos\nML top top vdd vdd pp\nR1 a top 1k\nR2 top b 1k\nM1 a in1 tail 0 nn\nM2 b in2 tail 0 nn\nMT tail vb2 0 0 nn\n" else cards;
    var nl = try netlist.parse(gpa, &.{deck}, null);
    defer nl.deinit(gpa);
    const roles = try sch.guessRoles(gpa, &nl);
    defer gpa.free(roles);
    const net = nl.net("top").?.index();
    const foreign = nl.net("in1").?.index();
    if (change == .output) roles[net] = .output;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    _ = try lib.register(.{ .name = "pmos", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 0, .y = 20 }, .side = .down },
        .{ .name = "g", .at = .{ .x = 20, .y = 0 }, .side = .right, .hidden = change == .hidden },
        .{ .name = "s", .at = .{ .x = 0, .y = -20 }, .side = .up },
    }, .draw = &.{
        .{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .{ .x = 0, .y = 20 } } },
        .{ .line = .{ .a = .zero, .b = .{ .x = 20, .y = 0 } } },
    } });
    _ = try lib.register(.{ .name = "res", .terminals = &.{
        .{ .name = "a", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "b", .at = .{ .x = 0, .y = 20 }, .side = .down },
    }, .draw = &.{.{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .{ .x = 0, .y = 20 } } }} });
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    const a = s.arena.allocator();
    const group: loads.Group = .{ nl.device("ml").?, nl.device("r1").?, nl.device("r2").?, nl.device("m1").?, nl.device("m2").?, nl.device("mt").? };
    var xy: std.ArrayList([2]f32) = .empty;
    const positions = [_][2]f32{ .{60,20}, .{0,80}, .{120,80}, .{-100,180}, .{220,180}, .{60,260} };
    for (0..s.devices.len) |d| {
        const member = for(group,0..) |edge,i| { if(edge.index()==d) break i; } else unreachable;
        try xy.append(a,positions[member]);
        _ = try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = sch.none });
        s.devices.set(d,.{
            .kept=true,.driver=false,.orientation=.horizontal,.flip_x=false,.flip_y=false,
            .class=s.devices.items(.class)[d],
            .orient=if(change==.reverse_card and d==group[1].index()) .{.rot=2} else .r0,
            .grid=.zero,.reach=@splat(20),
        });
    }
    const pin_devices = [_]u32{ group[0].index(),group[0].index(),group[1].index(),group[2].index() };
    const pin_indices = [_]u8{ 0,1,if(change == .reverse_card) 1 else 0,0 };
    const pins_of = try gpa.alloc(std.ArrayList(u32),roles.len);
    defer { for (pins_of) |*list| list.deinit(gpa); gpa.free(pins_of); }
    @memset(pins_of,.empty);
    for (pin_devices,pin_indices,[_]Side{.down,.right,.up,.up}) |d,index,side| {
        const p = try s.addPin(.{ .home = d, .side = side, .net = net, .device = d, .index = index });
        try pins_of[net].append(gpa,p);
    }
    if (change == .projected) {
        const copy = try s.addNode(.{ .kind = .device, .ref = group[1].index(), .group = group[1].index() });
        try xy.append(a,.{10,80});
        s.pins.items(.home)[2] = copy;
    }
    if (change == .wrong_index) s.pins.items(.index)[1] = 2;
    if (change == .wrong_net) s.pins.items(.net)[1] = foreign;
    if (change == .fifth) {
        const node = try s.addNode(.{ .kind = .terminal, .ref = net, .group = sch.none });
        try xy.append(a,.{200,60});
        const p = try s.addPin(.{ .home=node, .side=.up, .net=net, .device=sch.none, .index=0 });
        try pins_of[net].append(gpa,p);
    }
    if (change == .absent) {
        const missing = try lib.register(.{.name="unsupported_load",.terminals=&.{.{.name="d",.at=.{.x=0,.y=20},.side=.down}},.draw=&.{}});
        s.devices.items(.class)[group[0].index()] = missing;
    }
    if (change == .permutation) std.mem.reverse(u32,pins_of[net].items);
    s.xy = xy.items;
    var c = try canvas.Canvas.init(gpa,&s,&xy,.of(.{},40),&bodies,&.{});
    defer c.deinit();
    try testing.expect(try c.commit(foreign,&.{.{.x=300,.y=300},.{.x=340,.y=300}}));
    c.wall();
    if (blocker) |i| {
        const contact = [_]Pt{.{.x=30,.y=60},.{.x=60,.y=50},.{.x=100,.y=20},.{.x=120,.y=40}};
        const delta: Pt = if(i==0 or i==2) .{.x=0,.y=5} else .{.x=5,.y=0};
        try testing.expect(try c.commit(foreign,&.{if(crossing) contact[i].sub(delta) else contact[i],contact[i].add(delta)}));
    }
    const styles = try gpa.alloc(netlines.Style,roles.len);
    defer gpa.free(styles);
    @memset(styles,.auto);
    styles[net] = switch(change) {.cut=>.cut,.label=>.label,.explicit_wire=>.wire,else=>.auto};
    const ports = try gpa.alloc(?Side,roles.len);
    defer gpa.free(ports);
    @memset(ports,null);
    if(change==.port) ports[net]=.left;
    const rails = try gpa.alloc(netlines.Rail,roles.len);
    defer gpa.free(rails);
    @memset(rails,.auto);
    const first = [_]u32{foreign};
    const lines: netlines.NetLines = .{.style=styles,.port=ports,.rail=rails,.first=if(change==.first) &first else &.{},.routes=&.{}};
    const routed = try gpa.alloc(bool,roles.len);
    defer gpa.free(routed);
    @memset(routed,false);
    routed[net]=change==.routed;
    const drawn = try gpa.alloc(bool,roles.len);
    defer gpa.free(drawn);
    @memset(drawn,false);
    drawn[net]=change==.already_drawn;
    // Exactly one path fits the current capacities. A later append must
    // allocate, so the failure sweep exercises rollback after partial ink.
    try c.segs.shrinkAndFreePrecise(gpa,c.segs.items.len);
    try c.segs.ensureTotalCapacityPrecise(gpa,c.segs.items.len+1);
    try c.points.shrinkAndFreePrecise(gpa,c.points.items.len);
    try c.points.ensureTotalCapacityPrecise(gpa,c.points.items.len+2);
    const before = c.save();
    const segments = try gpa.dupe(@import("maze.zig").Wire,c.segs.items);
    defer gpa.free(segments);
    const points = try gpa.dupe(@import("maze.zig").Mark,c.points.items);
    defer gpa.free(points);
    const routes = try gpa.dupe(sch.Route,s.routes.items);
    defer gpa.free(routes);
    routing.seed(&c,&nl,if(change==.no_owner) &.{} else &.{group},&.{},&lines,pins_of,routed,drawn) catch |err| {
        try testing.expectEqualDeep(before,c.save());
        try testing.expectEqualDeep(segments,c.segs.items);
        try testing.expectEqualDeep(points,c.points.items);
        try testing.expectEqualDeep(routes,s.routes.items);
        try testing.expect(!drawn[net]);
        return err;
    };
    const expected=(change==.none or change==.reverse_card or change==.permutation) and (blocker==null or crossing);
    errdefer {
        std.debug.print("load consumer {s}, blocker {?}, crossing {}: drawn {}\n",.{@tagName(change),blocker,crossing,drawn[net]});
        for(pins_of[net].items) |p| {
            const pin=s.pins.get(p);
            std.debug.print("  device {d} pin {d} net {d}, point {any}\n",.{pin.device,pin.index,pin.net,canvas.pinAt(&s,p)});
        }
    }
    try testing.expectEqual(expected or change==.already_drawn,drawn[net]);
    if(expected) {
        for(0..121) |x| try testing.expect(c.onNet(net,.{.x=@intCast(x),.y=60}));
        for(terminals) |p| try testing.expect(c.onNet(net,p));
        for(c.segs.items) |segment| if(segment.net==net) {
            try testing.expect(!c.onNet(foreign,segment.a));
            try testing.expect(!c.onNet(foreign,segment.b));
        };
    } else {
        try testing.expectEqualDeep(before,c.save());
        try testing.expectEqualDeep(segments,c.segs.items);
        try testing.expectEqualDeep(points,c.points.items);
        try testing.expectEqualDeep(routes,s.routes.items);
    }
}

// ---- tests ----

test "resistor load wire: literal source tree fits ordinary Canvas contact rules" {
    const gpa = testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "load", "other" }, .device_pin_count = &.{}, .roles = &.{ .internal, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    try populate(&s, &xy);
    var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &bodies, &.{});
    defer c.deinit();
    try testing.expect(canvas.linesFit(&c, 0, &wanted));
    const start = c.save();
    for (wanted) |line| try testing.expect(try c.commit(0, line.slice()));
    try bar(&c);
    c.restore(start);
    // Ordinary trunk remains available; the new owner consumer is tested
    // below against this same literal interval after its saved RED.
    try testing.expect(try trunk.draw(&c, 0, &.{ 0, 1, 2, 3 }, .port));
}

test "resistor load wire: every candidate branch rejects foreign tips but permits proper crossings" {
    const gpa = testing.allocator;
    const contacts = [_]Pt{ .{ .x = 30, .y = 60 }, .{ .x = 60, .y = 50 }, .{ .x = 100, .y = 20 }, .{ .x = 120, .y = 40 } };
    for (contacts, 0..) |contact, i| for ([_]bool{ false, true }) |crossing| {
        var lib: library.Library = .init(gpa);
        defer lib.deinit();
        var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "load", "other" }, .device_pin_count = &.{}, .roles = &.{ .internal, .internal } };
        defer s.deinit();
        var xy: std.ArrayList([2]f32) = .empty;
        try populate(&s, &xy);
        var c = try canvas.Canvas.init(gpa, &s, &xy, .of(.{}, 40), &bodies, &.{});
        defer c.deinit();
        const delta: Pt = if (i == 0 or i == 2) .{ .x = 0, .y = 5 } else .{ .x = 5, .y = 0 };
        try testing.expect(try c.commit(1, &.{ if (crossing) contact.sub(delta) else contact, contact.add(delta) }));
        const before = c.save();
        try testing.expectEqual(crossing, canvas.linesFit(&c, 0, &wanted));
        try testing.expectEqualDeep(before, c.save());
        if (crossing) {
            for (wanted) |line| try testing.expect(try c.commit(0, line.slice()));
            try bar(&c);
            for (c.segs.items) |segment| if (segment.net == 0) {
                try testing.expect(!c.onNet(1, segment.a));
                try testing.expect(!c.onNet(1, segment.b));
            };
        }
    };
}


test "resistor load wire: certified actual pins keep the source bar through card and pin permutation" {
    for([_]Change{.none,.reverse_card,.permutation}) |change| try consumer(testing.allocator,change,null,false);
}

test "resistor load wire: unsupported pins caller styles and absent ownership leave prior ink intact" {
    for([_]Change{.projected,.wrong_index,.wrong_net,.fifth,.hidden,.absent,.cut,.label,.explicit_wire,.output,.first,.port,.routed,.already_drawn,.no_owner}) |change| {
        errdefer std.debug.print("load wire boundary: {s}\n",.{@tagName(change)});
        try consumer(testing.allocator,change,null,false);
    }
}

test "resistor load wire: foreign endpoint on any branch rolls back while proper crossings stay legal" {
    for(0..4) |i| for([_]bool{false,true}) |crossing| try consumer(testing.allocator,.none,i,crossing);
}

test "resistor load wire: every allocation failure restores the complete previous Canvas" {
    try testing.checkAllAllocationFailures(testing.allocator,consumer,.{Change.none,@as(?usize,null),false});
}
