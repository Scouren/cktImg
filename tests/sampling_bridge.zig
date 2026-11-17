//! Upright sampling diodes in AnalogGenie 763 and 1042, including their hold input.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const sample = "Sampling head\n" ++
    ".model photodiode D(IS=1e-14 N=1)\n.model nch nmos\n.model qnpn npn\n" ++
    "Ch held 0 1p\nD1 a vin photodiode\nD2 a held photodiode\nD3 vin k photodiode\n" ++
    "D4 held k photodiode\nD5 vout a photodiode\nD6 k vout photodiode\n" ++
    "I1 vdd a 1m\nI2 vdd k 1m\nI3 tail 0 1m\n";

// ---- private ----

fn index(p: *const np.Placed, name: []const u8, terminal: usize) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + terminal;
}

test "sampling bridges retain diode polarity and both midpoint columns through final routing" {
    const alloc = std.testing.allocator;
    const lib = try support.library(alloc);
    defer support.freeLibrary(alloc, lib);
    const follower = ".subckt voltage_amplifier vdd vss vin vout\n.ends\n" ++
        "Q1 a hold tail 0 qnpn\nQ2 k track tail 0 qnpn\nX1 vdd 0 held vout voltage_amplifier\n";
    const amplifier = ".subckt icm_opamp_vdd_vss vdd vss vip vin vout\n.ends\n" ++
        "M1 a hold tail 0 nch\nM2 k track tail 0 nch\nX1 vdd 0 vout held vout icm_opamp_vdd_vss\n";
    for ([_][]const u8{ sample ++ follower, sample ++ amplifier }) |deck| {
        for ([_]np.Config{ .{}, .{ .layout = .{ .compact = false } }, .{ .layout = .{ .shelf = 2 } } }) |cfg| {
            var p = try np.place(alloc, &cfg, lib, &.{deck}, null);
            defer p.deinit();
            const d = [4]usize{ index(&p, "d1", 0), index(&p, "d2", 0), index(&p, "d3", 0), index(&p, "d4", 0) };
            for (d) |anode| {
                try std.testing.expectEqual(p.pin_xy[anode].x, p.pin_xy[anode + 1].x);
                try std.testing.expect(p.pin_xy[anode].y < p.pin_xy[anode + 1].y);
            }
            for (0..2) |col| {
                try std.testing.expectEqual(p.pin_xy[d[col]].x, p.pin_xy[d[col + 2]].x);
                try std.testing.expect(p.pin_xy[d[col] + 1].y <= p.pin_xy[d[col + 2]].y);
                try std.testing.expect(try ink.connected(alloc, &p, &.{ d[col] + 1, d[col + 2] }));
            }
            try std.testing.expect(p.pin_xy[d[0]].x < p.pin_xy[d[1]].x);
            try std.testing.expectEqual(p.pin_xy[d[0]].y, p.pin_xy[d[1]].y);
            try std.testing.expectEqual(p.pin_xy[d[2]].y, p.pin_xy[d[3]].y);
            try std.testing.expect(try ink.connected(alloc, &p, &.{ d[0], d[1] }));
            try std.testing.expect(try ink.connected(alloc, &p, &.{ d[2] + 1, d[3] + 1 }));
            const block = np.checks.deviceIn(&p, "x1").?;
            const first, const last = p.pinRange(block);
            const held = p.pin_net[d[1] + 1];
            const block_pin = for (first..last) |i| {
                if (p.pin_net[i] == held) break i;
            } else return error.MissingHoldPin;
            try std.testing.expect(try ink.connected(alloc, &p, &.{ d[1] + 1, d[3], block_pin, index(&p, "ch", 0) }));
            try support.expectConnected(&p, lib);
            try std.testing.expectEqual(0, try support.shorts(alloc, &p, true));
        }
    }
}

test "an explicit bridge form controls an input diode in a sampler" {
    const alloc = std.testing.allocator;
    const lib = try support.library(alloc);
    defer support.freeLibrary(alloc, lib);
    const deck = sample ++ ".subckt voltage_amplifier vdd vss vin vout\n.ends\n" ++
        "Q1 a hold tail 0 qnpn\nQ2 k track tail 0 qnpn\nX1 vdd 0 held vout voltage_amplifier\n" ++
        "*@ bridge d1\n";
    var p = try np.place(alloc, &.default, lib, &.{deck}, null);
    defer p.deinit();
    const pin = index(&p, "d1", 0);
    try std.testing.expectEqual(p.pin_xy[pin].y, p.pin_xy[pin + 1].y);
    try support.expectConnected(&p, lib);
}
