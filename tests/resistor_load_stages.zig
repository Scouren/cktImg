//! Source resistor-loaded differential stages -> actual layout certificates.
//! Oracle: resistor_load_stages.py independently verifies three stages in
//! full AG1048/AG1052 SVGs: 13 relative predicates, no foreign glyph inside
//! their nominal group envelopes, 12 local trees and nine straight corridors.
//! Tail wiring may bend. Remote output gates and rails are not inferred to
//! join: complete source partitions remain in the research inventory.
//! This future suite is deliberately unimported until its RED is recorded.
//!
//! Contents: complete source decks, actual-pin and locality oracles, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1048 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\IB1 VB1 VSS DC 1m
    \\M1 VM1 vX net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M10 VDD VP1 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\M11 net0 VDD VCMM VSS nch l=0.15 w=1 nf=1 m=1
    \\M12 net2 VDD VCMP VSS nch l=0.15 w=1 nf=1 m=1
    \\M13 VCMM VCMM VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M14 VCMP VCMP VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M15 Vout1 VM1 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M16 Vout2 VP1 net1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M19 net3 net3 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VP1 VCM net4 VSS nch l=0.15 w=1 nf=1 m=1
    \\M20 net1 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 VM1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VP1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 VP1 VP1 VM1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M6 VM1 VM1 VP1 VSS nch l=0.15 w=1 nf=1 m=1
    \\M7 net4 VCMM VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 net4 VCMP VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M9 VDD VM1 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\MB1 VB1 VB1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 net3 Vout1 1k
    \\R2 net3 Vout2 1k
    \\*@ weak role vx input
    \\*@ weak role vcm input
;

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

const Frame = [16]np.Pt;
const Stage = struct {
    deck: []const u8,
    names: [6][]const u8,
    binding: [6][4][]const u8,
};
const stages = [_]Stage{
    .{ .deck = ag1048, .names = .{ "m19", "r1", "r2", "m15", "m16", "m20" }, .binding = .{
        .{ "net3", "net3", "vdd", "vdd" },  .{ "net3", "vout1", "", "" },       .{ "net3", "vout2", "", "" },
        .{ "vout1", "vm1", "net1", "vss" }, .{ "vout2", "vp1", "net1", "vss" }, .{ "net1", "vb2", "vss", "vss" },
    } },
    .{ .deck = ag1052, .names = .{ "m12", "r3", "r4", "m13", "m14", "m15" }, .binding = .{
        .{ "net4", "net4", "vdd", "vdd" }, .{ "net4", "vm2", "", "" },         .{ "net4", "vp2", "", "" },
        .{ "vm2", "net9", "net3", "vss" }, .{ "vp2", "net15", "net3", "vss" }, .{ "net3", "vb2", "vss", "vss" },
    } },
    .{ .deck = ag1052, .names = .{ "m8", "r1", "r2", "m9", "m10", "m11" }, .binding = .{
        .{ "net7", "net7", "vdd", "vdd" },  .{ "net7", "net9", "", "" },          .{ "net7", "net15", "", "" },
        .{ "net9", "net1", "net2", "vss" }, .{ "net15", "net11", "net2", "vss" }, .{ "net2", "vb2", "vss", "vss" },
    } },
};
const trees = [_][]const usize{ &.{ 0, 1, 3, 5 }, &.{ 4, 7 }, &.{ 6, 10 }, &.{ 9, 12, 13 } };
const corridors = [_][2]usize{ .{ 3, 5 }, .{ 4, 7 }, .{ 6, 10 } };
const source: Frame = .{
    .{ .x = 260, .y = 20 },  .{ .x = 290, .y = 0 },   .{ .x = 260, .y = -20 },
    .{ .x = 220, .y = 40 },  .{ .x = 220, .y = 80 },  .{ .x = 300, .y = 40 },
    .{ .x = 300, .y = 80 },  .{ .x = 220, .y = 120 }, .{ .x = 190, .y = 140 },
    .{ .x = 220, .y = 160 }, .{ .x = 300, .y = 120 }, .{ .x = 330, .y = 140 },
    .{ .x = 300, .y = 160 }, .{ .x = 260, .y = 200 }, .{ .x = 230, .y = 220 },
    .{ .x = 260, .y = 240 },
};

// ---- private ----

fn pins(p: *const np.Placed, lib: *const np.Library, stage: Stage) ![16]usize {
    var out: [16]usize = undefined;
    var count: usize = 0;
    for (stage.names, stage.binding, 0..) |name, binding, i| {
        const d = np.checks.deviceIn(p, name) orelse return error.MissingDevice;
        const lo, const hi = p.pinRange(d);
        const class = lib.at(p.dev_class[d]);
        const resistor = i == 1 or i == 2;
        const n: usize = if (resistor) 2 else 4;
        try testing.expectEqual(n, hi - lo);
        for (0..n) |j| {
            // Resistor reversal changes card order; semantic endpoints still
            // bind to the same named nets. All four MOS card slots stay fixed.
            var actual = lo + j;
            if (resistor and !std.mem.eql(u8, p.net_name[p.pin_net[actual]], binding[j])) actual = lo + 1 - j;
            try testing.expectEqualStrings(binding[j], p.net_name[p.pin_net[actual]]);
            if (!resistor and j == 3) continue;
            try testing.expect(class.shows(actual - lo));
            if (!resistor) try testing.expect(std.ascii.eqlIgnoreCase(([_][]const u8{ "d", "g", "s" })[j], class.terminals[j].name));
            try testing.expectEqualDeep(p.dev_pos[d].add(p.dev_orient[d].apply(class.terminals[actual - lo].at)), p.pin_xy[actual]);
            out[count] = actual;
            count += 1;
        }
    }
    try testing.expectEqual(out.len, count);
    return out;
}

fn geometry(input: Frame) bool {
    var q = input;
    if (q[7].x > q[10].x) {
        for (0..2) |i| std.mem.swap(np.Pt, &q[3 + i], &q[5 + i]);
        for (0..3) |i| std.mem.swap(np.Pt, &q[7 + i], &q[10 + i]);
    }
    if (q[0].x != q[2].x or !(q[2].y < q[1].y and q[1].y < q[0].y)) return false;
    for ([_]usize{ 3, 5 }) |i| if (q[i].x != q[i + 1].x or q[i].y >= q[i + 1].y) return false;
    if (q[3].y != q[5].y or q[4].y != q[6].y) return false;
    for ([_]usize{ 7, 10, 13 }) |i| if (q[i].x != q[i + 2].x or !(q[i].y < q[i + 1].y and q[i + 1].y < q[i + 2].y)) return false;
    for (0..3) |i| if (q[7 + i].y != q[10 + i].y) return false;
    if (!(q[8].x < q[7].x and q[7].x < q[10].x and q[10].x < q[11].x)) return false;
    if (q[4].x != q[7].x or q[6].x != q[10].x) return false;
    if (!(q[7].x < q[0].x and q[0].x < q[10].x) or q[0].y > q[3].y) return false;
    if (q[4].y >= q[7].y or q[6].y >= q[10].y) return false;
    return q[13].y > q[9].y and q[9].x < q[13].x and q[13].x < q[12].x;
}

fn disjoint(a: np.library.Rect, b: np.library.Rect) bool {
    return @max(a.min.x, b.min.x) >= @min(a.max.x, b.max.x) or @max(a.min.y, b.min.y) >= @min(a.max.y, b.max.y);
}

fn clear(p: *const np.Placed, lib: *const np.Library, stage: Stage) !void {
    var owner: [6]usize = undefined;
    var envelope: ?np.library.Rect = null;
    for (stage.names, &owner) |name, *d| {
        d.* = np.checks.deviceIn(p, name).?;
        const box = lib.at(p.dev_class[d.*]).box(p.dev_orient[d.*], p.dev_pos[d.*]);
        envelope = if (envelope) |old| old.merge(box) else box;
    }
    for (p.dev_name, 0..) |name, d| {
        // The source census contains device glyphs, not generated ports.
        if (name.len == 0 or std.mem.indexOfScalar(usize, &owner, d) != null) continue;
        const box = lib.at(p.dev_class[d]).box(p.dev_orient[d], p.dev_pos[d]);
        if (!disjoint(envelope.?, box)) std.debug.print("load {s} foreign glyph {s}: group={any}, body={any}\n", .{ stage.names[0], name, envelope.?, box });
        try testing.expect(disjoint(envelope.?, box));
    }
}

fn straight(p: *const np.Placed, from: usize, to: usize) bool {
    const a, const b = .{ p.pin_xy[from], p.pin_xy[to] };
    if (a.eql(b) or p.pin_net[from] != p.pin_net[to]) return false;
    const vertical = a.x == b.x;
    if (!vertical and a.y != b.y) return false;
    const fixed = if (vertical) a.x else a.y;
    const end = if (vertical) b.y else b.x;
    var lo = if (vertical) a.y else a.x;
    var hi = lo;
    for (0..p.seg_pt.len) |_| {
        var changed = false;
        var segments = p.segments(p.pin_net[from]);
        while (segments.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |c, d| {
            if ((if (vertical) c.x else c.y) != fixed or (if (vertical) d.x else d.y) != fixed) continue;
            const left = @min(if (vertical) c.y else c.x, if (vertical) d.y else d.x);
            const right = @max(if (vertical) c.y else c.x, if (vertical) d.y else d.x);
            if (left > hi or right < lo) continue;
            changed = changed or left < lo or right > hi;
            lo = @min(lo, left);
            hi = @max(hi, right);
        };
        if (lo <= end and end <= hi) return true;
        if (!changed) return false;
    }
    return false;
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

// ---- tests ----

test "resistor load stages: source relative frame and foreign-envelope oracle mutations" {
    try testing.expect(geometry(source));
    var reflected = source;
    for (&reflected) |*p| p.x = -p.x;
    try testing.expect(geometry(reflected));
    const mutations = [_]struct { index: usize, point: np.Pt }{
        .{ .index = 0, .point = .{ .x = 400, .y = 20 } },
        .{ .index = 3, .point = .{ .x = 219, .y = 40 } },
        .{ .index = 8, .point = .{ .x = 280, .y = 140 } },
        .{ .index = 13, .point = .{ .x = 260, .y = 100 } },
    };
    for (mutations) |change| {
        var bad = source;
        bad[change.index] = change.point;
        try testing.expect(!geometry(bad));
    }
    const group: np.library.Rect = .{ .min = .{ .x = 190, .y = -20 }, .max = .{ .x = 330, .y = 240 } };
    const outside: np.library.Rect = .{ .min = .{ .x = 340, .y = 0 }, .max = .{ .x = 380, .y = 40 } };
    const inserted: np.library.Rect = .{ .min = .{ .x = 250, .y = 90 }, .max = .{ .x = 270, .y = 110 } };
    try testing.expect(disjoint(group, outside));
    try testing.expect(!disjoint(group, inserted));
    try testing.expect(geometry(source)); // Body interleaving is a separate failure.
}

test "resistor load stages: all three complete DUT groups keep their relative frame and clear occupied envelope" {
    for (stages) |stage| for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("load stage {s}, compact={}\n", .{ stage.names[0], compact });
        const lib = try support.library(testing.allocator);
        defer support.freeLibrary(testing.allocator, lib);
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{stage.deck}, null);
        defer p.deinit();
        var q: Frame = undefined;
        for (try pins(&p, lib, stage), &q) |pin, *point| point.* = p.pin_xy[pin];
        try testing.expect(geometry(q));
        try clear(&p, lib, stage);
        try electrical(&p, lib);
    };
}

test "resistor load stages: all twelve literal local trees remain physically connected" {
    for (stages) |stage| for ([_]bool{ false, true }) |compact| {
        const lib = try support.library(testing.allocator);
        defer support.freeLibrary(testing.allocator, lib);
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{stage.deck}, null);
        defer p.deinit();
        const ids = try pins(&p, lib, stage);
        for (trees, 0..) |tree, index| {
            var targets: [4]usize = undefined;
            for (tree, targets[0..tree.len]) |i, *target| target.* = ids[i];
            // Load and tail trees contain every declared incidence. The two
            // output trees intentionally select only the local R/D pair.
            if (index == 0 or index == 3) {
                var count: usize = 0;
                for (p.pin_net, 0..) |net, pin| if (net == p.pin_net[targets[0]]) {
                    try testing.expect(std.mem.indexOfScalar(usize, targets[0..tree.len], pin) != null);
                    count += 1;
                };
                try testing.expectEqual(tree.len, count);
            }
            errdefer std.debug.print("load stage {s}, compact={}, local tree {s}\n", .{ stage.names[0], compact, p.net_name[p.pin_net[targets[0]]] });
            try testing.expect(try ink.connected(testing.allocator, &p, targets[0..tree.len]));
        }
        try electrical(&p, lib);
    };
}

test "resistor load stages: resistor top bar and each own-drain gap preserve source straight ink" {
    for (stages) |stage| for ([_]bool{ false, true }) |compact| {
        const lib = try support.library(testing.allocator);
        defer support.freeLibrary(testing.allocator, lib);
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{stage.deck}, null);
        defer p.deinit();
        const ids = try pins(&p, lib, stage);
        for (corridors) |pair| {
            errdefer std.debug.print("load stage {s}, compact={}, corridor {d}/{d}\n", .{ stage.names[0], compact, pair[0], pair[1] });
            try testing.expect(straight(&p, ids[pair[0]], ids[pair[1]]));
        }
    };
}

test "resistor load stages: straight-ink oracle rejects named gaps and accepts a bent tail only as connected" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const ports = [_]np.ClassId{ lib.findRole(.input_port).?, lib.findRole(.input_port).? };
    var p: np.Placed = .{
        .arena = undefined,
        .dev_name = &.{ "", "" },
        .dev_class = &ports,
        .dev_value = &.{ "", "" },
        .dev_pos = &.{ .{ .x = 0, .y = 0 }, .{ .x = 20, .y = 0 } },
        .dev_orient = &.{ .{}, .{} },
        .dev_pin0 = &.{ 0, 1, 2 },
        .pin_net = &.{ 0, 0 },
        .pin_xy = &.{ .{ .x = 0, .y = 0 }, .{ .x = 20, .y = 0 } },
        .net_name = &.{ "local", "other" },
        .net_seg = &.{ 0, 2, 2 },
        .seg_pt = &.{ 0, 2, 4 },
        .wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 20, .y = 0 } },
        .junctions = &.{},
        .labels = &.{ .{ .net = 0, .at = .{ .x = 0, .y = 0 }, .side = .left }, .{ .net = 0, .at = .{ .x = 20, .y = 0 }, .side = .right } },
        .no_connects = &.{},
    };
    // Borrowed literal storage; no arena or renderer can join these labels.
    try testing.expect(straight(&p, 0, 1));
    try testing.expect(straight(&p, 1, 0));
    p.wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 9, .y = 0 }, .{ .x = 11, .y = 0 }, .{ .x = 20, .y = 0 } };
    try testing.expect(!straight(&p, 0, 1));
    try testing.expect(!try ink.connected(testing.allocator, &p, &.{ 0, 1 }));
    p.net_seg = &.{ 0, 2, 3 };
    p.seg_pt = &.{ 0, 2, 4, 6 };
    p.wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 9, .y = 0 }, .{ .x = 11, .y = 0 }, .{ .x = 20, .y = 0 }, .{ .x = 9, .y = 0 }, .{ .x = 11, .y = 0 } };
    try testing.expect(!straight(&p, 0, 1));
    try testing.expect(!try ink.connected(testing.allocator, &p, &.{ 0, 1 }));
    p.net_seg = &.{ 0, 1, 1 };
    p.seg_pt = &.{ 0, 4 };
    p.wire_pts = &.{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 10 }, .{ .x = 20, .y = 10 }, .{ .x = 20, .y = 0 } };
    try testing.expect(try ink.connected(testing.allocator, &p, &.{ 0, 1 }));
    try testing.expect(!straight(&p, 0, 1));
}

test "resistor load stages: linked pair owns separate local axes and matching semantic rows" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1052}, null);
        defer p.deinit();
        const up = try pins(&p, lib, stages[2]);
        const down = try pins(&p, lib, stages[1]);
        const a = @as(i64, p.pin_xy[up[7]].x) + p.pin_xy[up[10]].x;
        const b = @as(i64, p.pin_xy[down[7]].x) + p.pin_xy[down[10]].x;
        try testing.expect(a < b);
        for (up, down) |u, d| try testing.expectEqual(p.pin_xy[u].y, p.pin_xy[d].y);
        for ([_][16]usize{ up, down }) |group| try testing.expect(p.pin_xy[group[14]].x < p.pin_xy[group[13]].x);
    }
}

test "resistor load stages: common tail bias stays two source-separated pieces" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1052}, null);
        defer p.deinit();
        const a = (try pins(&p, lib, stages[2]))[14];
        const b = (try pins(&p, lib, stages[1]))[14];
        try testing.expectEqualStrings("vb2", p.net_name[p.pin_net[a]]);
        try testing.expectEqual(p.pin_net[a], p.pin_net[b]);
        try testing.expect(!try ink.connected(testing.allocator, &p, &.{ a, b }));
        try electrical(&p, lib);
    }
}

test "resistor load stages: both complete interstage output trees preserve source ink" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1052}, null);
        defer p.deinit();
        const up = try pins(&p, lib, stages[2]);
        const down = try pins(&p, lib, stages[1]);
        const targets = [_][3]usize{ .{ up[4], up[7], down[8] }, .{ up[6], up[10], down[11] } };
        for (targets, [_][]const u8{ "net9", "net15" }) |tree, name| {
            errdefer std.debug.print("linked load output {s}, compact={}\n", .{ name, compact });
            const net = p.pin_net[tree[0]];
            try testing.expectEqualStrings(name, p.net_name[net]);
            var count: usize = 0;
            for (p.pin_net, 0..) |candidate, pin| if (candidate == net) {
                try testing.expect(std.mem.indexOfScalar(usize, &tree, pin) != null);
                count += 1;
            };
            try testing.expectEqual(tree.len, count);
            // Both source trees include their remote input gate. Their paths
            // bend on distinct rows; no straight interstage bar is implied.
            try testing.expect(try ink.connected(testing.allocator, &p, &tree));
        }
        try electrical(&p, lib);
    }
}

test "resistor load stages: reversed resistor cards keep the same source corridors" {
    const gpa = testing.allocator;
    for (stages) |stage| {
        var reversed = try gpa.dupe(u8, stage.deck);
        defer gpa.free(reversed);
        for (1..3) |i| {
            const before = try std.fmt.allocPrint(gpa, "{s} {s} {s}", .{ stage.names[i], stage.binding[i][0], stage.binding[i][1] });
            defer gpa.free(before);
            const after = try std.fmt.allocPrint(gpa, "{s} {s} {s}", .{ stage.names[i], stage.binding[i][1], stage.binding[i][0] });
            defer gpa.free(after);
            // Parse is case-insensitive; normalize the literal deck for this
            // transformation, preserving values and every other card.
            for (reversed) |*c| c.* = std.ascii.toLower(c.*);
            const next = try std.mem.replaceOwned(u8, gpa, reversed, before, after);
            gpa.free(reversed);
            reversed = next;
        }
        const lib = try support.library(gpa);
        defer support.freeLibrary(gpa, lib);
        for ([_]bool{ false, true }) |compact| {
            var p = try np.place(gpa, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{reversed}, null);
            defer p.deinit();
            const ids = try pins(&p, lib, stage);
            var frame: Frame = undefined;
            for (ids, &frame) |id, *point| point.* = p.pin_xy[id];
            try testing.expect(geometry(frame));
            try clear(&p, lib, stage);
            for (corridors) |pair| try testing.expect(straight(&p, ids[pair[0]], ids[pair[1]]));
            try electrical(&p, lib);
        }
    }
}

test "resistor load stages: shifted long caller frames preserve actual leads and class identity" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const r = try lib.register(.{ .name = "load_shift_r", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -50, .y = 15 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 30, .y = 15 }, .side = .right },
    }, .draw = &.{.{ .line = .{ .a = .{ .x = -50, .y = 15 }, .b = .{ .x = 30, .y = 15 } } }} });
    const m = try lib.register(.{ .name = "load_shift_m", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 50, .y = 15 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 10, .y = -15 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -30, .y = 15 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 10, .y = 15 }, .hidden = true },
    }, .draw = &.{
        .{ .line = .{ .a = .{ .x = -30, .y = 15 }, .b = .{ .x = 50, .y = 15 } } },
        .{ .line = .{ .a = .{ .x = 10, .y = -15 }, .b = .{ .x = 10, .y = 15 } } },
    } });
    const deck = ag1048 ++ "\n*@ class m19 load_shift_m\n*@ class m15 load_shift_m\n*@ class m16 load_shift_m\n*@ class m20 load_shift_m\n*@ class r1 load_shift_r\n*@ class r2 load_shift_r\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{deck}, null);
        defer p.deinit();
        const ids = try pins(&p, lib, stages[0]);
        var frame: Frame = undefined;
        for (ids, &frame) |id, *point| point.* = p.pin_xy[id];
        try testing.expect(geometry(frame));
        try clear(&p, lib, stages[0]);
        for (stages[0].names, 0..) |name, i| try testing.expectEqual(if (i == 1 or i == 2) r else m, p.dev_class[np.checks.deviceIn(&p, name).?]);
        for (corridors) |pair| try testing.expect(straight(&p, ids[pair[0]], ids[pair[1]]));
        try electrical(&p, lib);
    }
}
