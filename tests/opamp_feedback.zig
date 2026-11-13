//! Feedback cells → local capacitor/switch axes around an amplifier.
//! Oracle: AnalogGenie ag-800/801/803 source terminal coordinates. AG799's
//! longer feedback path is a separate case. No generated layout is a golden.
//!
//! Contents: private geometry checks, then public source regressions.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const testing = std.testing;

const prefix = "Feedback cell\n.model nch nmos\n" ++
    ".subckt opamp VDD VSS VIP VIN VOUT\n.ends\n";
const ag800 = prefix ++ "C1 net2 net0 1p\nC2 net0 net1 1p\n" ++
    "M1 net2 phi1 vin VSS nch\nM2 net2 phi2 VSS VSS nch\n" ++
    "M3 vout phi2 net0 VSS nch\nM4 VSS phi2 net1 VSS nch\n" ++
    "M5 net1 phi1 vout VSS nch\nX1 0 VSS VSS net0 vout opamp\n";
const ag801 = prefix ++ "C1 net1 net3 1p\nC2 net3 net2 1p\nC3 net0 vout 1p\n" ++
    "M1 net1 phi1 vin VSS nch\nM2 net1 phi2 VSS VSS nch\n" ++
    "M3 net0 phi2 net3 VSS nch\nM4 net0 phi1 VSS VSS nch\n" ++
    "M5 VSS phi2 net2 VSS nch\nM6 net2 phi1 vout VSS nch\n" ++
    "X1 0 VSS VSS net3 vout opamp\n";
const ag803 = prefix ++ "C1 net3 net1 1p\nC2 net1 net6 1p\nC3 net5 net4 1p\n" ++
    "C4 net4 net0 1p\nC5 net1 net2 1p\nM1 vin phi1 net3 VSS nch\n" ++
    "M10 net0 phi1 VG VSS nch\nM11 net0 phi2 net2 VSS nch\n" ++
    "M2 net3 phi2 VSS VSS nch\nM3 net1 phi2 net4 VSS nch\n" ++
    "M4 net6 phi1 net2 VSS nch\nM5 net6 phi2 VSS VSS nch\n" ++
    "M6 net2 phi1 vout VSS nch\nM7 vin phi2 net5 VSS nch\n" ++
    "M8 net5 phi1 VG VSS nch\nM9 net4 phi1 VG VSS nch\n" ++
    "X1 VDD VSS VSS net1 net2 opamp\n";
const ag799 = prefix ++ "C1 net2 vout 1p\nC2 net3 net1 1p\nC3 vin net2 1p\nC4 net0 net3 1p\n" ++
    "M1 net0 phi1 vin VSS nch\nM2 net0 phi2 VSS VSS nch\nM3 net3 phi2 VSS VSS nch\n" ++
    "M4 net2 phi1 net3 VSS nch\nM5 net1 phi2 VSS VSS nch\nM6 vout phi1 net1 VSS nch\n" ++
    "X1 0 VSS VSS net2 vout opamp\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, k: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.pinRange(d)[0] + k];
}

fn axis(p: *const np.Placed, name: []const u8, last: u32, horizontal: bool) !void {
    const a = pin(p, name, 0);
    const b = pin(p, name, last);
    try testing.expectEqual(horizontal, a.y == b.y);
    try testing.expectEqual(!horizontal, a.x == b.x);
}

fn rectangle(p: *const np.Placed, cap: []const u8, signal: []const u8, shunt: []const u8, at_input: bool) !void {
    try axis(p, cap, 1, true);
    try axis(p, signal, 2, false);
    try axis(p, shunt, 2, true);
    const c = pin(p, cap, 0);
    const d = pin(p, signal, 0);
    const gate = pin(p, signal, 1);
    const s = pin(p, signal, 2);
    const z = pin(p, shunt, 0);
    const amp = pin(p, "x1", if (at_input) 4 else 3);
    try testing.expectEqual(c.y, z.y);
    try testing.expect(if (at_input) d.x > amp.x else d.x < amp.x);
    try testing.expect(if (at_input) gate.x > d.x else gate.x < d.x);
    try testing.expect(c.y <= @min(d.y, s.y) and @max(d.y, s.y) <= amp.y);
}

test "feedback cells: a capacitor and reset shunt share a row beside a vertical signal switch" {
    // Oracle: AG800 C2/M4 share a row above M3; M5 returns down to the
    // output. AG801 mirrors two such cells around shared capacitor columns.
    // All seven source rectangles put the vertical return's gate outside.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{ag800}, null);
        defer p.deinit();
        try rectangle(&p, "c2", "m5", "m4", true);
        try testing.expect(pin(&p, "c2", 0).y < pin(&p, "m3", 0).y);
        try testing.expect(pin(&p, "m3", 0).y < pin(&p, "x1", 3).y);
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
        var q = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{ag801}, null);
        defer q.deinit();
        try rectangle(&q, "c2", "m6", "m5", true);
        try rectangle(&q, "c3", "m3", "m4", false);
        try testing.expectEqual(pin(&q, "c2", 0).x + pin(&q, "c2", 1).x, pin(&q, "c3", 0).x + pin(&q, "c3", 1).x);
        try testing.expect(pin(&q, "c3", 0).y < pin(&q, "c2", 0).y);
        try support.expectConnected(&q, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &q, true));
    }
}

test "feedback cells: a direct feedback capacitor takes the outer row above a straight switched branch" {
    // Oracle: AG803 C5 is above the C2/M4 row; its ground shunt M5 stands
    // upright. A direct capacitor changes the cell's local axis and order.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{ag803}, null);
    defer p.deinit();
    try axis(&p, "c2", 1, true);
    try axis(&p, "m4", 2, true);
    try axis(&p, "m5", 2, false);
    try testing.expectEqual(pin(&p, "c2", 0).y, pin(&p, "m4", 0).y);
    try testing.expect(pin(&p, "c5", 0).y < pin(&p, "c2", 0).y);
    try testing.expect(pin(&p, "c2", 0).y < pin(&p, "x1", 3).y);
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
}

test "feedback cells: longer paths and explicit upright hints keep their own axes" {
    // Oracle: AG799's three-part feedback path has horizontal signal MOS
    // and vertical ground shunts. An explicit user hint overrides the cell.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{ag799}, null);
    defer p.deinit();
    for ([_][]const u8{ "m1", "m4", "m6" }) |name| try axis(&p, name, 2, true);
    for ([_][]const u8{ "m2", "m3", "m5" }) |name| try axis(&p, name, 2, false);
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    var q = try np.place(testing.allocator, &.default, lib, &.{ag800 ++ "*@ upright m4\n"}, null);
    defer q.deinit();
    try axis(&q, "m4", 2, false);
    try support.expectConnected(&q, lib);
}

test "feedback cells: reversing source card order preserves every named pin position" {
    // Oracle: netlist card order carries no drawing instruction. The
    // reversed spelling has identical models, ports and connectivity.
    const reversed = prefix ++ "X1 0 VSS VSS net0 vout opamp\n" ++
        "M5 net1 phi1 vout VSS nch\nM4 VSS phi2 net1 VSS nch\n" ++
        "M3 vout phi2 net0 VSS nch\nM2 net2 phi2 VSS VSS nch\n" ++
        "M1 net2 phi1 vin VSS nch\nC2 net0 net1 1p\nC1 net2 net0 1p\n";
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var a = try np.place(testing.allocator, &.default, lib, &.{ag800}, null);
    defer a.deinit();
    var b = try np.place(testing.allocator, &.default, lib, &.{reversed}, null);
    defer b.deinit();
    for ([_][]const u8{ "c1", "c2", "m1", "m2", "m3", "m4", "m5", "x1" }) |name| {
        const d = np.checks.deviceIn(&a, name).?;
        const lo, const hi = a.pinRange(d);
        for (0..hi - lo) |k| try testing.expectEqual(pin(&a, name, @intCast(k)), pin(&b, name, @intCast(k)));
    }
}

test "feedback cells: reversing return terminals preserves the outward gate and connected endpoints" {
    // Oracle: gate side belongs to the local feedback rectangle, not the
    // D/S spelling. Swapping those terminals swaps their geometric roles.
    const reversed = try std.mem.replaceOwned(u8, testing.allocator, ag800, "M5 net1 phi1 vout", "M5 vout phi1 net1");
    defer testing.allocator.free(reversed);
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var a = try np.place(testing.allocator, &.default, lib, &.{ag800}, null);
    defer a.deinit();
    var b = try np.place(testing.allocator, &.default, lib, &.{reversed}, null);
    defer b.deinit();
    try rectangle(&a, "c2", "m5", "m4", true);
    try rectangle(&b, "c2", "m5", "m4", true);
    try testing.expectEqual(pin(&a, "m5", 0), pin(&b, "m5", 2));
    try testing.expectEqual(pin(&a, "m5", 2), pin(&b, "m5", 0));
    try support.expectConnected(&b, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &b, true));
}
