//! Actual terminal axes and conductor paths from the source ladder and bridged-T figures.
//! The source diagrams order parts by the tapped path between ports.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");
const testing = std.testing;

const ladder = "ladder\nR1 vin x 1k\nR2 x y 1k\nR3 y vout 1k\nC1 x 0 1p\nC2 y 0 1p\nC3 vout 0 1p\n";
const bridged = "bridged T\nR1 x b 1k\nC3 a b 1p\nC4 x 0 1p\nR2 a x 1k\n*@ weak role a output\n*@ weak role b output\n";

// ---- private ----

fn ends(p: *const np.Placed, name: []const u8) [2]np.Pt {
    const start = p.dev_pin0[np.checks.deviceIn(p, name).?];
    return .{ p.pin_xy[start], p.pin_xy[start + 1] };
}

fn through(p: *const np.Placed, name: []const u8) ![2]np.Pt {
    const pts = ends(p, name);
    try testing.expectEqual(pts[0].y, pts[1].y);
    try testing.expect(pts[0].x != pts[1].x);
    return if (pts[0].x < pts[1].x) pts else .{ pts[1], pts[0] };
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
    for (p.net_name, 0..) |name, net| {
        if (std.mem.eql(u8, name, "0")) continue;
        var pins: std.ArrayList(usize) = .empty;
        defer pins.deinit(testing.allocator);
        for (p.pin_net, 0..) |n, i| if (n == net) try pins.append(testing.allocator, i);
        if (pins.items.len > 1) try testing.expect(try ink.connected(testing.allocator, p, pins.items));
    }
}

test "passive filters: three tapped arms keep their order and physically connected ports" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    // AR6308. Reverse the order of cards and pins in a second deck.
    const reverse = "ladder\nC3 0 vout 1p\nC2 0 y 1p\nC1 0 x 1p\nR3 vout y 1k\nR2 y x 1k\nR1 x vin 1k\n";
    for ([_][]const u8{ ladder, reverse }) |deck| for ([_]bool{ true, false }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{deck}, null);
        defer p.deinit();
        const a = try through(&p, "r1");
        const b = try through(&p, "r2");
        const c = try through(&p, "r3");
        try testing.expectEqual(a[0].y, b[0].y);
        try testing.expectEqual(a[0].y, c[0].y);
        for ([_][2]np.Pt{ a, b, c }, [_][]const u8{ "c1", "c2", "c3" }, 0..) |span, shunt, i| {
            const pts = ends(&p, shunt);
            try testing.expectEqual(pts[0].x, pts[1].x);
            try testing.expect(@min(pts[0].y, pts[1].y) >= a[0].y);
            try testing.expect(span[1].x <= pts[0].x);
            if (i < 2) try testing.expect(pts[0].x <= ([_][2]np.Pt{ b, c })[i][0].x);
        }
        try electrical(&p, lib);
    };
}

test "passive filters: tapped two-element path remains on the port row with its bridge above" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ true, false }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{bridged}, null);
        defer p.deinit();
        const a = try through(&p, "r2");
        const b = try through(&p, "r1");
        const bridge = try through(&p, "c3");
        const leg = ends(&p, "c4");
        try testing.expectEqual(a[0].y, b[0].y);
        try testing.expect(bridge[0].y < a[0].y);
        try testing.expect(leg[0].y >= a[0].y and leg[1].y > leg[0].y);
        try testing.expectEqual(leg[0].x, leg[1].x);
        try testing.expect(a[1].x <= leg[0].x and leg[0].x <= b[0].x);
        var port_count: usize = 0;
        for (p.dev_class, 0..) |class, d| {
            if (class != lib.findRole(.output_port).? or p.dev_name[d].len != 0) continue;
            const pin = p.dev_pin0[d];
            try testing.expectEqual(a[0].y, p.pin_xy[pin].y);
            const is_left = std.mem.eql(u8, p.net_name[p.pin_net[pin]], "a");
            try testing.expect(if (is_left) p.pin_xy[pin].x < a[0].x else p.pin_xy[pin].x > b[1].x);
            port_count += 1;
        }
        try testing.expectEqual(2, port_count);
        try electrical(&p, lib);
    }
}
