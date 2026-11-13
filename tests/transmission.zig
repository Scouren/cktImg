//! Transmission-gate geometry, with the source terminals as the oracle.
//!
//! Contents: private pin lookup, then tests.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const testing = std.testing;

const models = "Transmission gate\n.model nch nmos\n.model pch pmos\n";
const sampler = "CH out 0 1p\nM1 out ck in 0 nch\nM2 in cb out vdd pch\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, k: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.pinRange(d)[0] + k];
}

test "transmission: complementary parallel channels share a column with outward controls" {
    // Oracle: AG386 M1/M2 and AG751 M1/M2 have equal channel-midpoint x,
    // separate y, NMOS above PMOS, and clocks outside the pair. Swapping
    // D/S on a card, reversing cards, or renaming clocks preserves that rule.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const cards = [_][]const u8{
        models ++ sampler,
        models ++ "M2 in cb out vdd pch\nM1 out ck in 0 nch\nCH out 0 1p\n",
        models ++ "CH out 0 1p\nM1 out phase_a in 0 nch\nM2 out phase_b in vdd pch\n",
        models ++ "CH out 0 1p\nM1 out ck in bulk nch\nM2 in cb out vdd pch\nCB bulk 0 1p\n",
        models ++ ".subckt voltage_amplifier vdd vss vin vout\n.ends\nCH held 0 1p\nM1 in ck held 0 nch\nM2 in cb held vdd pch\nX1 vdd 0 held out voltage_amplifier\n",
    };
    for (cards) |deck| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{deck}, null);
        defer p.deinit();
        const nd = pin(&p, "m1", 0);
        const ns = pin(&p, "m1", 2);
        const pd = pin(&p, "m2", 0);
        const ps = pin(&p, "m2", 2);
        try testing.expectEqual(nd.y, ns.y);
        try testing.expectEqual(pd.y, ps.y);
        try testing.expectEqual(nd.x + ns.x, pd.x + ps.x);
        try testing.expectEqual(@min(nd.x, ns.x), @min(pd.x, ps.x));
        try testing.expect(nd.y < pd.y);
        try testing.expect(pin(&p, "m1", 1).y < nd.y);
        try testing.expect(pin(&p, "m2", 1).y > pd.y);
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    };
}

test "transmission: explicit row and upright instructions override the pair habit" {
    // Oracle: the caller's row/turn, which takes precedence over source habit.
    // A row of bridges needs the existing upright CH as its row anchor.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var row = try np.place(testing.allocator, &.default, lib, &.{models ++ sampler ++ "*@ row m1 m2 ch\n"}, null);
    defer row.deinit();
    try testing.expectEqual(pin(&row, "m1", 0).y, pin(&row, "m2", 0).y);
    try testing.expect(pin(&row, "m1", 0).x != pin(&row, "m2", 0).x);
    var upright = try np.place(testing.allocator, &.default, lib, &.{models ++ sampler ++ "*@ upright m2\n"}, null);
    defer upright.deinit();
    try testing.expectEqual(pin(&upright, "m2", 0).x, pin(&upright, "m2", 2).x);
    try testing.expect(pin(&upright, "m2", 0).y != pin(&upright, "m2", 2).y);
    try support.expectConnected(&row, lib);
    try support.expectConnected(&upright, lib);
}
