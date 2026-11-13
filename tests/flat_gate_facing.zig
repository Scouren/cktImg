//! Flat MOS controls face their active drivers, with source pins as oracle.
//!
//! Contents: fixtures, private pin checks, then tests.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const testing = std.testing;

const models = "Flat gate\n.model nch nmos\n.model pch pmos\n";
const reservoir = models ++
    "CSTO stored 0 1p\nCL output 0 1p\nL1 left right 1n\n" ++
    "MP3 left phase1 stored vdd pch\nMP2 right control output vdd pch\n" ++
    "MN1 left phase2 0 0 nch\nMN2 right phase3 0 0 nch\n";
const drains = "M12 control vb1 vdd vdd pch\nM14 control vb3 0 0 nch\n";
const block = ".subckt comp VDD VSS INN OUT VX VB1 VB2\n.ends\n" ++
    "X1 vdd 0 right control left vb1 vb2 comp\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, k: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.pinRange(d)[0] + k];
}

fn expectGate(p: *const np.Placed, name: []const u8, down: bool) !void {
    const d = pin(p, name, 0);
    const s = pin(p, name, 2);
    const g = pin(p, name, 1);
    try testing.expectEqual(d.y, s.y);
    try testing.expect(d.x != s.x);
    try testing.expect(if (down) g.y > d.y else g.y < d.y);
}

fn expectConnected(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

test "flat gate: a comparator output below the power path attracts its control" {
    // Oracle: AG1354 MP2's gate and X1.OUT both lie below its channel.
    // Keep the source's opaque seven-port comparator contract. The cell
    // fixes its independent controller row, not the target's orientation.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = false } }, lib, &.{reservoir ++ block ++ "*@ cell x1 3 10\n"}, null);
    defer p.deinit();
    try testing.expect(pin(&p, "x1", 3).y > pin(&p, "mp2", 0).y);
    try expectGate(&p, "mp2", true);
    try expectConnected(&p, lib);
}

test "flat gate: two active drain drivers on the same side agree on the control" {
    // Oracle: AG1356 MP2 points down toward both M12.D and M14.D. One
    // output stage has two drivers; taking just the first is insufficient.
    // This reduced stage retains the same electrical driver terminals.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{reservoir ++ drains}, null);
        defer p.deinit();
        for ([_][]const u8{ "m12", "m14" }) |name| {
            try testing.expect(pin(&p, name, 0).y > pin(&p, "mp2", 0).y);
        }
        try expectGate(&p, "mp2", true);
        try expectConnected(&p, lib);
    }
}

test "flat gate: opposing active drivers and a level output do not choose a side" {
    // Oracle: the two literal driver coordinates straddle the channel;
    // neither side is unanimous. A level output supplies no vertical side.
    // Existing class orientation is retained in both ambiguous cases.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var opposed = try np.place(testing.allocator, &.{ .layout = .{ .compact = false } }, lib, &.{reservoir ++ drains ++ "*@ cell mp2 8 8\n*@ cell m12 2 2\n*@ cell m14 2 14\n"}, null);
    defer opposed.deinit();
    const channel = pin(&opposed, "mp2", 0).y;
    try testing.expect(pin(&opposed, "m12", 0).y < channel);
    try testing.expect(pin(&opposed, "m14", 0).y > channel);
    try expectGate(&opposed, "mp2", false);
    try expectConnected(&opposed, lib);
    var level = try np.place(testing.allocator, &.{ .layout = .{ .compact = false } }, lib, &.{reservoir ++ block ++ "*@ cell mp2 8 8\n*@ cell x1 2 8\n"}, null);
    defer level.deinit();
    try testing.expectEqual(pin(&level, "x1", 3).y, pin(&level, "mp2", 0).y);
    try expectGate(&level, "mp2", false);
    try expectConnected(&level, lib);
}

test "flat gate: source symbols passive loads gates and bodies do not vote" {
    // Oracle: none of these incidences is an active nongate driver. They
    // cannot justify changing a class's side, even when drawn below it.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const attachments = [_][]const u8{
        "VCONTROL control 0 1\n*@ driver vcontrol inline\n",
        "RCONTROL control 0 1k\n",
        "MG out2 control 0 0 nch\nMB out3 bias 0 control nch\n",
    };
    for (attachments) |extra| {
        const src = try std.mem.concat(testing.allocator, u8, &.{ reservoir, extra });
        defer testing.allocator.free(src);
        var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
        defer p.deinit();
        try expectGate(&p, "mp2", false);
        try expectConnected(&p, lib);
    }
}

test "flat gate: external converter controls do not imply all PMOS gates face down" {
    // Negative source: AG1191 M1/M3 face down, M2 up; all three controls
    // are external. Their polarity and horizontal form decide no gate side.
    // This reduced power path retains the external-control ambiguity.
    const src = models ++ "CFLY x1 x2 1p\nCO output bottom 1p\nCOP output 0 1p\n" ++
        "L1 x1 x3 1n\nM1 x1 phase2 input vdd pch\nM2 x2 phase3 input vdd pch\n" ++
        "M3 x3 phase5 output vdd pch\nM4 x3 phase4 0 0 nch\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
    defer p.deinit();
    for ([_][]const u8{ "m1", "m2", "m3" }) |name| try expectGate(&p, name, false);
    try expectConnected(&p, lib);
}

test "flat gate: transmission-pair outward controls take precedence over a driver" {
    // Oracle: AG386/751's complementary pair has outward controls. A
    // driver below its NMOS cannot turn the gate inward across the PMOS.
    const src = models ++ "CH out 0 1p\nM1 out ck in 0 nch\nM2 in cb out vdd pch\n" ++
        "MDRIVE ck bias 0 0 nch\nR1 vdd ck 1k\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = false } }, lib, &.{src}, null);
    defer p.deinit();
    try testing.expect(pin(&p, "mdrive", 0).y > pin(&p, "m1", 0).y);
    try testing.expectEqual(pin(&p, "m1", 0).x + pin(&p, "m1", 2).x, pin(&p, "m2", 0).x + pin(&p, "m2", 2).x);
    try testing.expect(pin(&p, "m1", 0).y < pin(&p, "m2", 0).y);
    try expectGate(&p, "m1", false);
    try expectGate(&p, "m2", true);
    try expectConnected(&p, lib);
}
