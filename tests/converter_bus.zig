//! Source converter bus -> a continuous spine outside both switch terminals.
//! Cites: AG1191's actual source bus at x=40, with M1/M2 VIN pins at
//! (90,340)/(90,530), and the named 141/145 source preference in
//! docs/research/converter-loops.md. Four shared-column exceptions remain
//! recorded there; this test asserts the default choice on AG1191 only.
//! Human Rules:
//! - A converter's input bus usually has a short horizontal lead from
//!   each switch to one vertical spine strictly outside both pins.
//! - The source relation fixes neither the gap nor the control placement.
//!   A remote vertical spur cannot stand in for that complete local path.
//!
//! Contents: literal AG1191 DUT, geometric wire certificate, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1191 =
    \\AG1191 reservoir fixture
    \\.model nch nmos
    \\.model pch pmos
    \\.model DIODE D(IS=1e-14 N=1)
    \\CFLY VX1 VX2 1p
    \\CO VP VN 1p
    \\COP VP VSS 1p
    \\D1 VN VX2 DIODE
    \\L1 VX1 VX3 1n
    \\M1 VX1 VCONT2 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M2 VX2 VCONT3 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\M3 VX3 VCONT5 VP VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 VX3 VCONT4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M5 net9 VCONT1 VIN VDD pch l=0.15 w=1 nf=1 m=1
    \\MN1 net5 VFP1 net10 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN10 net1 VB4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN11 VB3 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN12 net0 VB3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN13 VBN VBN net3 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN14 net3 VBN VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN2 net4 VREF net10 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN3 net10 VB2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN4 VG VBN VX1 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN5 VX1 VG VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN6 VCTRL VBN net8 VSS nch l=0.15 w=1 nf=1 m=1
    \\MN7 net8 VG VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN8 net1 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MN9 net6 net1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\MP1 VFP1 net5 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP10 net6 net6 net9 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP11 VX1 net6 net9 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP12 VB3 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP13 net0 net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP14 VBN net0 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP2 net2 net5 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP3 VN net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP4 net7 net4 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\MP5 VG VB1 VFP1 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP6 net5 VB1 net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP7 net4 VB1 VN VDD pch l=0.15 w=1 nf=1 m=1
    \\MP8 VCTRL VB1 net7 VDD pch l=0.15 w=1 nf=1 m=1
    \\MP9 net1 VCTRL net9 VDD pch l=0.15 w=1 nf=1 m=1
    \\R1 VP VFP1 1k
    \\R2 VFP1 VSS 1k
    \\*@ weak role vcont1 input
    \\*@ weak role vcont2 input
    \\*@ weak role vcont3 input
    \\*@ weak role vcont4 input
    \\*@ weak role vcont5 input
    \\*@ weak role vp output
    \\
;

// ---- private ----

fn terminal(p: *const np.Placed, name: []const u8, index: u32) usize {
    const d = np.checks.deviceIn(p, name).?;
    return p.dev_pin0[d] + index;
}

// Union coverage on a single requested straight interval. Existing
// polylines may split that interval at T-junctions and remote branches.
fn covered(p: *const np.Placed, net: u32, a: np.Pt, b: np.Pt) bool {
    std.debug.assert(a.x == b.x or a.y == b.y);
    const vertical = a.x == b.x;
    const fixed = if (vertical) a.x else a.y;
    var at = @min(if (vertical) a.y else a.x, if (vertical) b.y else b.x);
    const end = @max(if (vertical) a.y else a.x, if (vertical) b.y else b.x);
    for (0..p.wire_pts.len) |_| {
        if (at == end) return true;
        var next = at;
        var it = p.segments(net);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |u, v| {
            if (if (vertical) u.x != fixed or v.x != fixed else u.y != fixed or v.y != fixed) continue;
            const lo = @min(if (vertical) u.y else u.x, if (vertical) v.y else v.x);
            const hi = @max(if (vertical) u.y else u.x, if (vertical) v.y else v.x);
            if (lo <= at and hi > next) next = hi;
        };
        if (next == at) return false;
        at = @min(next, end);
    }
    return at == end;
}

fn leftBus(p: *const np.Placed, upper: usize, lower: usize) ?i32 {
    const a = p.pin_xy[upper];
    const b = p.pin_xy[lower];
    const net = p.pin_net[upper];
    std.debug.assert(net == p.pin_net[lower]);
    if (a.y == b.y) return null;
    var it = p.segments(net);
    while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |u, v| {
        if (u.x != v.x or u.y == v.y or u.x >= @min(a.x, b.x)) continue;
        const top: np.Pt = .{ .x = u.x, .y = a.y };
        const bottom: np.Pt = .{ .x = u.x, .y = b.y };
        if (covered(p, net, a, top) and covered(p, net, top, bottom) and covered(p, net, bottom, b)) return u.x;
    };
    return null;
}

fn leftPort(p: *const np.Placed, lib: *const np.Library, upper: usize, bus: i32) !bool {
    const net = p.pin_net[upper];
    for (p.dev_class, 0..) |class, d| {
        if (p.dev_name[d].len != 0 or class != lib.findRole(.input_port).?) continue;
        const lo, const hi = p.pinRange(d);
        if (hi - lo != 1 or p.pin_net[lo] != net or p.pin_xy[lo].x >= bus) continue;
        if (try ink.connected(testing.allocator, p, &.{ upper, lo })) return true;
    }
    return false;
}

test "converter bus: the default spine stands strictly left of both source terminals" {
    // Source ink: (90,340)->(40,340)->(40,440)->(40,530)->(90,530).
    // Both horizontal shoulders and the whole vertical span must exist;
    // neither labels, a remote spur, nor a fixed 50-unit gap is the oracle.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1191}, null);
        defer p.deinit();
        const upper = terminal(&p, "m1", 2);
        const lower = terminal(&p, "m2", 2);
        try testing.expect(try ink.connected(testing.allocator, &p, &.{ upper, lower }));
        try testing.expect(leftBus(&p, upper, lower) != null);
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}

test "converter bus: a requested left input port stays outside the shifted spine" {
    // The local spine occupies the original anchor pin's left ray. The
    // requested port belongs at the tree boundary, where its stub is free.
    const src = ag1191 ++ "*@ port vin left\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{src}, null);
        defer p.deinit();
        const upper = terminal(&p, "m1", 2);
        const lower = terminal(&p, "m2", 2);
        try testing.expect(try ink.connected(testing.allocator, &p, &.{ upper, lower }));
        const bus = leftBus(&p, upper, lower);
        try testing.expect(bus != null);
        // M5's remote VIN branch may stand farther left and use its own
        // port. The requested local port must clear this connected tree.
        try testing.expect(try leftPort(&p, lib, upper, bus.?));
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}

test "converter bus: the wire oracle rejects remote spines and detached ports" {
    // Literal geometry: local terminals (20,0)/(20,40), remote port
    // (-30,20). A shared net name cannot supply either missing shoulder.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const ports = [_]np.ClassId{ lib.findRole(.input_port).?, lib.findRole(.input_port).?, lib.findRole(.input_port).? };
    var p: np.Placed = .{
        .arena = undefined,
        .dev_name = &.{ "upper", "lower", "" },
        .dev_class = &ports,
        .dev_value = &.{ "", "", "" },
        .dev_pos = &.{ .{ .x = 20, .y = 0 }, .{ .x = 20, .y = 40 }, .{ .x = -30, .y = 20 } },
        .dev_orient = &.{ .{}, .{}, .{} },
        .dev_pin0 = &.{ 0, 1, 2, 3 },
        .pin_net = &.{ 0, 0, 0 },
        .pin_xy = &.{ .{ .x = 20, .y = 0 }, .{ .x = 20, .y = 40 }, .{ .x = -30, .y = 20 } },
        .net_name = &.{ "vin", "other" },
        .net_seg = &.{ 0, 2, 2 },
        .seg_pt = &.{ 0, 2, 5 },
        .wire_pts = &.{ .{ .x = 20, .y = 0 }, .{ .x = 20, .y = 40 }, .{ .x = -30, .y = 20 }, .{ .x = 0, .y = 20 }, .{ .x = 0, .y = 40 } },
        .junctions = &.{},
        .labels = &.{},
        .no_connects = &.{},
    };
    // No deinit: every slice is borrowed literal data.
    try testing.expect(try ink.connected(testing.allocator, &p, &.{ 0, 1 }));
    try testing.expectEqual(@as(?i32, null), leftBus(&p, 0, 1));
    // The complete local bus exists, but the left port is still detached.
    p.seg_pt = &.{ 0, 4, 6 };
    p.wire_pts = &.{ .{ .x = 20, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 40 }, .{ .x = 20, .y = 40 }, .{ .x = -30, .y = 20 }, .{ .x = -10, .y = 20 } };
    try testing.expectEqual(@as(?i32, 0), leftBus(&p, 0, 1));
    try testing.expect(!try leftPort(&p, lib, 0, 0));
    // Split the spine at a T and join the port: coverage crosses both
    // pieces, while actual endpoint/T connectivity reaches the local pin.
    p.net_seg = &.{ 0, 3, 3 };
    p.seg_pt = &.{ 0, 3, 6, 8 };
    p.wire_pts = &.{ .{ .x = 20, .y = 0 }, .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 20 }, .{ .x = 0, .y = 20 }, .{ .x = 0, .y = 40 }, .{ .x = 20, .y = 40 }, .{ .x = -30, .y = 20 }, .{ .x = 0, .y = 20 } };
    try testing.expectEqual(@as(?i32, 0), leftBus(&p, 0, 1));
    try testing.expect(try leftPort(&p, lib, 0, 0));
    p.pin_net = &.{ 0, 0, 1 };
    try testing.expect(!try leftPort(&p, lib, 0, 0));
}
