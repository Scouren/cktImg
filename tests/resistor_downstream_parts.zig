//! Complete AG1052 source -> two downstream named 2+1 ink partitions.
//! Oracle: resistor-downstream-parts-proof.py verifies all raw incidences,
//! actual SVG leads and complete source pieces across 2,936 source drawings.
//! Exactly vm2 and vp2 qualify; two branches in one figure are not a universal
//! gate-distance rule. All declared supplies and bodies stay in the oracle.
//! Prospective, unimported: ROOT records RED before a routing request exists.
//!
//! Contents: full source DUT, literal binding/physical oracles, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1052 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\* Ideal inverter: switches at V(VDD,VSS)/2; vt sets the step width, td the delay
    \\.subckt inverter VDD VSS A Y params: vt=10m td=10p
    \\BhA hA 0 V={0.5*(1+tanh((V(A,VSS)-0.5*V(VDD,VSS))/vt))}
    \\Bf nfn VSS V={V(VDD,VSS)*(1-V(hA))}
    \\Rd nfn ndl 1k
    \\Cd ndl VSS {td/1000}
    \\BY Y VSS V={V(ndl,VSS)}
    \\.ends inverter
    \\
    \\M1 net1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M10 net15 net11 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net2 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net4 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M13 vM2 net9 net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 vP2 net15 net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 net3 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 VOP vM2 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M17 VON vP2 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\M18 net5 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 VDD VON net6 VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net11 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M20 net6 net6 net13 VSS nch l=0.15 w=1 nf=1 m=1
    \\M21 net13 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M22 net10 VON VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M23 net10 net13 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M24 VDD VOP net12 VSS nch l=0.15 w=1 nf=1 m=1
    \\M25 net12 net12 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\M26 net0 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M27 net14 VOP VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M28 net14 net0 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net1 vX net8 VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net11 VCM net8 VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net8 VCMFB VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 net11 net11 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 net1 net1 net11 VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 net7 net7 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M9 net9 net1 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\R1 net7 net9 1k
    \\R2 net7 net15 1k
    \\R3 net4 vM2 1k
    \\R4 net4 vP2 1k
    \\R5 VDD VOP 1k
    \\R6 VDD VON 1k
    \\X1 VDD VSS net14 Q inverter td=10p vt=10m
    \\X2 VDD VSS net10 Q_bar inverter td=10p vt=10m
    \\*@ weak role vx input
    \\*@ weak role vcm input
    \\*@ weak role vcmfb input
    \\*@ weak role q output
    \\*@ weak role q_bar output
;

const Binding = struct { name: []const u8, nets: []const []const u8 };
const bindings = [_]Binding{
    .{ .name = "m8", .nets = &.{ "net7", "net7", "vdd", "vdd" } },
    .{ .name = "r1", .nets = &.{ "net7", "net9" } },
    .{ .name = "r2", .nets = &.{ "net7", "net15" } },
    .{ .name = "m9", .nets = &.{ "net9", "net1", "net2", "vss" } },
    .{ .name = "m10", .nets = &.{ "net15", "net11", "net2", "vss" } },
    .{ .name = "m11", .nets = &.{ "net2", "vb2", "vss", "vss" } },
    .{ .name = "m12", .nets = &.{ "net4", "net4", "vdd", "vdd" } },
    .{ .name = "r3", .nets = &.{ "net4", "vm2" } },
    .{ .name = "r4", .nets = &.{ "net4", "vp2" } },
    .{ .name = "m13", .nets = &.{ "vm2", "net9", "net3", "vss" } },
    .{ .name = "m14", .nets = &.{ "vp2", "net15", "net3", "vss" } },
    .{ .name = "m15", .nets = &.{ "net3", "vb2", "vss", "vss" } },
    .{ .name = "m16", .nets = &.{ "vop", "vm2", "net5", "vss" } },
    .{ .name = "r5", .nets = &.{ "vdd", "vop" } },
    .{ .name = "m24", .nets = &.{ "vdd", "vop", "net12", "vss" } },
    .{ .name = "m27", .nets = &.{ "net14", "vop", "vdd", "vdd" } },
    .{ .name = "m17", .nets = &.{ "von", "vp2", "net5", "vss" } },
    .{ .name = "r6", .nets = &.{ "vdd", "von" } },
    .{ .name = "m19", .nets = &.{ "vdd", "von", "net6", "vss" } },
    .{ .name = "m22", .nets = &.{ "net10", "von", "vdd", "vdd" } },
};
const branches = [_]struct { net: []const u8, devices: [3][]const u8 }{
    .{ .net = "vm2", .devices = .{ "r3", "m13", "m16" } },
    .{ .net = "vp2", .devices = .{ "r4", "m14", "m17" } },
};

// ---- private ----

fn checkBindings(p: *const np.Placed) !void {
    for (bindings) |binding| {
        const device = np.checks.deviceIn(p, binding.name) orelse return error.MissingDevice;
        const lo, const hi = p.pinRange(device);
        try testing.expectEqual(binding.nets.len, hi - lo);
        for (binding.nets, 0..) |net, i| {
            var index = i;
            if (binding.nets.len == 2 and !std.mem.eql(u8, net, p.net_name[p.pin_net[lo + i]])) index = 1 - i;
            // MOS body slots are checked even when their glyph hides them.
            try testing.expectEqualStrings(net, p.net_name[p.pin_net[lo + index]]);
        }
    }
}

fn actualPins(p: *const np.Placed, lib: *const np.Library, branch: usize) ![3]usize {
    const want = branches[branch];
    var result: [3]usize = undefined;
    for (want.devices, &result, 0..) |name, *pin, i| {
        const device = np.checks.deviceIn(p, name) orelse return error.MissingDevice;
        const lo, const hi = p.pinRange(device);
        var index: usize = if (i == 2) 1 else 0;
        if (i == 0 and !std.mem.eql(u8, want.net, p.net_name[p.pin_net[lo]])) index = 1;
        try testing.expect(lo + index < hi);
        pin.* = lo + index;
        try testing.expectEqualStrings(want.net, p.net_name[p.pin_net[pin.*]]);
        const class = lib.at(p.dev_class[device]);
        try testing.expect(class.shows(index));
        if (i > 0) try testing.expect(std.ascii.eqlIgnoreCase(if (i == 1) "d" else "g", class.terminals[index].name));
        try testing.expectEqualDeep(p.dev_pos[device].add(p.dev_orient[device].apply(class.terminals[index].at)), p.pin_xy[pin.*]);
    }
    var count: usize = 0;
    for (p.dev_name, 0..) |name, device| {
        if (name.len == 0) continue; // Placed's generated terminal symbols.
        const lo, const hi = p.pinRange(device);
        for (lo..hi) |pin| if (p.pin_net[pin] == p.pin_net[result[0]]) {
            try testing.expect(std.mem.indexOfScalar(usize, &result, pin) != null);
            count += 1;
        };
    }
    try testing.expectEqual(@as(usize, 3), count);
    return result;
}

fn partition(p: *const np.Placed, ids: [3]usize) !bool {
    return try ink.connected(testing.allocator, p, ids[0..2]) and
        !try ink.connected(testing.allocator, p, &.{ ids[0], ids[2] }) and
        !try ink.connected(testing.allocator, p, &.{ ids[1], ids[2] });
}

fn checkSource(deck: []const u8) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        try checkBindings(&p);
        // Correct names alone must never substitute for source physical ink.
        try support.expectConnected(&p, lib);
        try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, &p, true));
        for (branches, 0..) |branch, i| {
            const ids = try actualPins(&p, lib, i);
            errdefer std.debug.print("downstream {s}, compact={}, pins={any}\n", .{ branch.net, compact, .{ p.pin_xy[ids[0]], p.pin_xy[ids[1]], p.pin_xy[ids[2]] } });
            try testing.expect(try partition(&p, ids));
        }
    }
}

test "resistor downstream parts: complete source local pairs and remote gates stay separate" {
    try checkSource(ag1052);
}

test "resistor downstream parts: card permutation and resistor end reversal keep the source answer" {
    const gpa = testing.allocator;
    var deck = try gpa.dupe(u8, ag1052);
    defer gpa.free(deck);
    for (deck) |*c| c.* = std.ascii.toLower(c.*);
    for ([_][2][]const u8{ .{ "r3 net4 vm2", "r3 vm2 net4" }, .{ "r4 net4 vp2", "r4 vp2 net4" } }) |change| {
        const changed = try std.mem.replaceOwned(u8, gpa, deck, change[0], change[1]);
        gpa.free(deck);
        deck = changed;
    }
    // Move complete DUT cards only; the inverter declaration stays intact.
    const a = "m13 vm2 net9 net3 vss nch l=0.15 w=1 nf=1 m=1\n";
    const b = "m14 vp2 net15 net3 vss nch l=0.15 w=1 nf=1 m=1\n";
    try testing.expect(std.mem.indexOf(u8, deck, a ++ b) != null);
    const reordered = try std.mem.replaceOwned(u8, gpa, deck, a ++ b, b ++ a);
    defer gpa.free(reordered);
    try checkSource(reordered);
}

test "resistor downstream parts: literal partition rejects wrong ink and missing component names" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const class = try lib.register(.{ .name = "literal_pair", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -10, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 10, .y = 0 }, .side = .right },
    } });
    const ids: [3]usize = .{ 0, 2, 4 };
    const p: np.Placed = .{
        .arena = undefined,
        .dev_name = &.{ "r", "d", "g" },
        .dev_class = &.{ class, class, class },
        .dev_value = &.{ "", "", "" },
        .dev_pos = &.{ .zero, .zero, .zero },
        .dev_orient = &.{ .{}, .{}, .{} },
        .dev_pin0 = &.{ 0, 2, 4, 6 },
        .pin_net = &.{ 0, np.placed.no_net, 0, np.placed.no_net, 0, np.placed.no_net },
        .pin_xy = &.{ .{ .x = 0, .y = 0 }, .zero, .{ .x = 40, .y = 0 }, .zero, .{ .x = 20, .y = 30 }, .zero },
        .net_name = &.{ "vm", "foreign" },
        .net_seg = &.{ 0, 2, 2 },
        .seg_pt = &.{ 0, 2, 4 },
        .wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 40, .y = 0 }, .{ .x = 20, .y = 30 }, .{ .x = 20, .y = 20 } },
        .junctions = &.{},
        .labels = &.{ .{ .net = 0, .at = .{ .x = 0, .y = 0 }, .side = .left }, .{ .net = 0, .at = .{ .x = 20, .y = 30 }, .side = .right } },
        .no_connects = &.{},
    };
    try testing.expect(try partition(&p, ids));
    try support.expectConnected(&p, lib);
    var missing_name = p;
    missing_name.labels = p.labels[0..1];
    var findings: std.ArrayList(np.checks.Finding) = .empty;
    defer findings.deinit(gpa);
    try np.checks.connected(gpa, &findings, &missing_name, lib);
    try testing.expectEqual(@as(usize, 1), findings.items.len);
    try testing.expectEqual(@as(u32, 0), findings.items[0].net);
    try testing.expect(try partition(&missing_name, ids));

    var changed = p;
    changed.net_seg = &.{ 0, 1, 1 };
    changed.seg_pt = &.{ 0, 2 };
    changed.wire_pts = p.wire_pts[2..];
    try testing.expect(!try partition(&changed, ids));
    // The same geometric local bridge on a different net cannot repair it.
    changed.net_seg = &.{ 0, 1, 2 };
    changed.seg_pt = &.{ 0, 2, 4 };
    changed.wire_pts = &.{ .{ .x = 20, .y = 30 }, .{ .x = 20, .y = 20 }, .{ .x = 0, .y = 0 }, .{ .x = 40, .y = 0 } };
    try testing.expect(!try partition(&changed, ids));
    for ([_][]const np.Pt{
        &.{ .{ .x = 20, .y = 30 }, .{ .x = 40, .y = 30 }, .{ .x = 40, .y = 0 } }, // endpoint
        &.{ .{ .x = 20, .y = 30 }, .{ .x = 20, .y = 0 } }, // T contact
        &.{ .{ .x = 20, .y = 30 }, .{ .x = 20, .y = 0 }, .{ .x = 20, .y = -10 } }, // proper X, split at its dot
    }) |bridge| {
        var points: [5]np.Pt = undefined;
        @memcpy(points[0..2], p.wire_pts[0..2]);
        @memcpy(points[2 .. 2 + bridge.len], bridge);
        const cuts = [_]u32{ 0, 2, @intCast(2 + bridge.len) };
        changed = p;
        changed.seg_pt = &cuts;
        changed.wire_pts = points[0 .. 2 + bridge.len];
        try testing.expect(!try partition(&changed, ids));
    }
}

test "resistor downstream parts: explicit names override the source local wire request" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1052 ++ "\n*@ label vm2\n*@ label vp2\n"}, null);
        defer p.deinit();
        try checkBindings(&p);
        for (0..branches.len) |i| {
            const ids = try actualPins(&p, lib, i);
            try testing.expect(!try ink.connected(testing.allocator, &p, ids[0..2]));
        }
        try support.expectConnected(&p, lib);
        try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, &p, true));
    }
}
