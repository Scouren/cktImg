//! Stage 1, the nets' roles (R1–R3 in docs/ALGORITHM.md), and what every
//! drawing keeps: hidden pins stay undrawn (O0), the same deck draws the
//! same picture, and random netlists end with every device on a cell of
//! its own and every net one piece. The suites of the later stages are
//! imported at the end. `zig build test`.
//!
//! Contents: tests only.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const netlist = np.netlist;
const sch = np.schematic;
const textbook = @import("textbook.zig");
const support = @import("support.zig");

/// A deck laid out, and everything that stays to look at.
const Built = struct {
    lib: *np.Library,
    nl: netlist.Netlist,
    roles: []sch.Role,
    s: sch.Schematic,

    fn init(src: []const u8) !Built {
        const gpa = testing.allocator;
        const lib = try support.library(gpa);
        errdefer support.freeLibrary(gpa, lib);
        var nl = try netlist.parse(gpa, &.{src}, null);
        errdefer nl.deinit(gpa);
        const roles = try sch.guessRoles(gpa, &nl);
        errdefer gpa.free(roles);
        const s = try np.layout(gpa, &nl, roles, lib, .{});
        return .{ .lib = lib, .nl = nl, .roles = roles, .s = s };
    }
    fn deinit(b: *Built) void {
        b.s.deinit();
        testing.allocator.free(b.roles);
        b.nl.deinit(testing.allocator);
        support.freeLibrary(testing.allocator, b.lib);
    }

    fn dev(b: *const Built, name: []const u8) u32 {
        return b.nl.device(name).?.index();
    }
    fn net(b: *const Built, name: []const u8) u32 {
        return b.nl.net(name).?.index();
    }
    fn info(b: *const Built, name: []const u8) sch.DeviceInfo {
        return b.s.devices.get(b.dev(name));
    }
    /// Whether device `name`'s card pin `index` is drawn.
    fn drawn(b: *const Built, name: []const u8, index: u8) bool {
        const d = b.dev(name);
        for (b.s.pins.items(.device), b.s.pins.items(.index)) |pd, i| if (pd == d and i == index) return true;
        return false;
    }
};

// ---- private ----

fn circuit(name: []const u8) []const u8 {
    for (textbook.all ++ textbook.beyond) |c| if (std.mem.eql(u8, c.name, name)) return c.spice;
    unreachable;
}

test "R1 roles by net name" {
    var b = try Built.init(
        \\roles by name
        \\R1 vdd vin 1k
        \\R2 vin out1 1k
        \\R3 out1 vb1 1k
        \\R4 vb1 x 1k
        \\R5 x gnd 1k
    );
    defer b.deinit();
    try testing.expectEqual(sch.Role.supply, b.roles[b.net("vdd")]);
    try testing.expectEqual(sch.Role.input, b.roles[b.net("vin")]);
    try testing.expectEqual(sch.Role.output, b.roles[b.net("out1")]);
    try testing.expectEqual(sch.Role.bias, b.roles[b.net("vb1")]);
    try testing.expectEqual(sch.Role.internal, b.roles[b.net("x")]);
    try testing.expectEqual(sch.Role.sink, b.roles[b.net("gnd")]);
}

test "R2 a net driven from ground: signal source -> input, otherwise bias" {
    var b = try Built.init(
        \\source-driven roles
        \\Vs a 0 ac 1
        \\Vb b 0 dc 0.5
        \\R1 a b 1k
    );
    defer b.deinit();
    try testing.expectEqual(sch.Role.input, b.roles[b.net("a")]);
    try testing.expectEqual(sch.Role.bias, b.roles[b.net("b")]);
}

test "R3 drivers of terminal nets are not drawn" {
    var b = try Built.init(
        \\drivers
        \\Vdd vdd 0 1.8
        \\Vin in 0 ac 1
        \\Vx p q 1
        \\R1 vdd p 1k
        \\R2 q in 1k
        \\I1 vdd q 1m
    );
    defer b.deinit();
    try testing.expect(!b.info("vdd").kept);
    try testing.expect(!b.info("vin").kept);
    try testing.expect(b.info("vx").kept);
    try testing.expect(b.info("i1").kept);
}

test "O0 hidden pins: MOS bulk and the op-amp reference on the sink" {
    var cs = try Built.init(circuit("cs_resistive"));
    defer cs.deinit();
    try testing.expect(cs.drawn("m1", 0) and !cs.drawn("m1", 3));
    var amp = try Built.init(circuit("noninverting_amp"));
    defer amp.deinit();
    try testing.expect(amp.drawn("e1", 0) and !amp.drawn("e1", 1));
}

test "textbook: the same deck draws the same picture" {
    for (textbook.all ++ textbook.beyond) |c| {
        var b1 = try Built.init(c.spice);
        defer b1.deinit();
        var b2 = try Built.init(c.spice);
        defer b2.deinit();
        try testing.expectEqualSlices([2]f32, b1.s.xy, b2.s.xy);
        try testing.expectEqual(b1.s.routes.items.len, b2.s.routes.items.len);
        for (b1.s.routes.items, b2.s.routes.items) |r1, r2| try testing.expectEqualDeep(r1, r2);
    }
}

test "random netlists: they end, each device on a cell of its own, every net one piece" {
    const gpa = testing.allocator;
    const nets = [_][]const u8{ "vdd", "0", "in", "out", "a", "b", "c" };
    var prng = std.Random.DefaultPrng.init(7);
    const r = prng.random();
    for (0..150) |_| {
        var buf: [1024]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        try w.writeAll("random\n.model nch nmos level=1\n.model pch pmos level=1\nVdd vdd 0 1.8\nVin in 0 ac 1\n");
        for (0..r.intRangeAtMost(u32, 2, 6)) |i| {
            const p = nets[r.intRangeLessThan(usize, 0, nets.len)];
            const q = nets[r.intRangeLessThan(usize, 0, nets.len)];
            const g = nets[r.intRangeLessThan(usize, 0, nets.len)];
            switch (r.intRangeAtMost(u32, 0, 3)) {
                0 => try w.print("R{d} {s} {s} 1k\n", .{ i, p, q }),
                1 => try w.print("C{d} {s} {s} 1p\n", .{ i, p, q }),
                2 => try w.print("M{d} {s} {s} {s} 0 nch\n", .{ i, p, g, q }),
                else => try w.print("M{d} {s} {s} {s} vdd pch\n", .{ i, p, g, q }),
            }
        }
        errdefer std.debug.print("{s}\n", .{w.buffered()});
        var b = try Built.init(w.buffered());
        defer b.deinit();
        // Each drawn device's node on a point of its own.
        const kinds = b.s.nodes.items(.kind);
        const groups = b.s.nodes.items(.group);
        for (b.s.xy, 0..) |p, i| for (b.s.xy[i + 1 ..], i + 1..) |q, j| {
            if (kinds[i] != .device or kinds[j] != .device or groups[i] != i or groups[j] != j) continue;
            try testing.expect(p[0] != q[0] or p[1] != q[1]);
        };
        var placed = try np.Placed.init(gpa, &b.s, &b.nl);
        defer placed.deinit();
        try support.expectConnected(&placed, b.lib);
        try testing.expectEqual(0, try support.shorts(gpa, &placed, true));
        try testing.expectEqual(0, try support.dots(gpa, &placed, true));
    }
}

test {
    _ = @import("golden.zig");
}

test {
    _ = @import("structure.zig");
}

test {
    _ = @import("skeleton.zig");
}

test {
    _ = @import("sketch.zig");
}

test {
    _ = @import("report.zig");
}
