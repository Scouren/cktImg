//! Source oracles for the reciprocal loads in AnalogGenie 215 and 1034.

const std = @import("std");
const np = @import("NetlistParser");
const ink = @import("wire_ink.zig");
const support = @import("support.zig");
const testing = std.testing;

const models = "Differential load\n.model nch nmos\n.model pch pmos\n";
const ag1034 = models ++
    "Ibias vdd bias 1m\nM1 vo1 vi1 tail vss nch\nM2 vo2 vi2 tail vss nch\n" ++
    "M3 vo1 vo1 vdd vdd pch\nM4 vo2 vo2 vdd vdd pch\nM5 tail bias vss vss nch\n" ++
    "M6 vo2 vo1 vdd vdd pch\nM7 vo1 vo2 vdd vdd pch\nM8 bias bias vss vss nch\n" ++
    "*@ weak role vo1 output\n*@ weak role vi1 input\n*@ weak role vo2 output\n*@ weak role vi2 input\n";
const ag215 = models ++
    "I1 tail vss 1m\nM1 vout1 vin1 tail vss nch\nM2 vout2 vin2 tail vss nch\n" ++
    "M3 vout1 vout2 vdd vdd pch\nM4 vout2 vout1 vdd vdd pch\n" ++
    "M5 vout1 vout1 vdd vdd pch\nM6 vout2 vout2 vdd vdd pch\n";

// ---- private ----

fn index(p: *const np.Placed, name: []const u8, terminal: usize) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + terminal;
}

fn pin(p: *const np.Placed, name: []const u8, terminal: usize) np.Pt {
    return p.pin_xy[index(p, name, terminal)];
}

fn between(x: i32, a: i32, b: i32) bool {
    return @min(a, b) < x and x < @max(a, b);
}

fn expectOuter(p: *const np.Placed, diode: [2][]const u8, crossed: [2][]const u8) !void {
    const a = pin(p, diode[0], 0);
    const b = pin(p, diode[1], 0);
    try testing.expectEqual(a.y, b.y);
    for (crossed) |name| {
        const d = pin(p, name, 0);
        try testing.expectEqual(a.y, d.y);
        try testing.expect(between(d.x, a.x, b.x));
    }
}

// Each array is ordered by output node, so the other crossed load provides
// that output's fifth terminal, its gate. Both sides must join by actual ink.
fn expectStage(p: *const np.Placed, refs: [2][]const u8, loads: [2][]const u8, inputs: [2][]const u8) !void {
    try expectOuter(p, refs, loads);
    for (0..2) |i| {
        try testing.expect(try ink.connected(testing.allocator, p, &.{
            index(p, refs[i], 0),      index(p, refs[i], 1),   index(p, loads[i], 0),
            index(p, loads[1 - i], 1), index(p, inputs[i], 0),
        }));
    }
}

test "source terminals and aligned branches of two reciprocal differential loads" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{ ag1034, ag215 }, 0..) |src, i| {
        var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
        defer p.deinit();
        const refs: [2][]const u8 = if (i == 0) .{ "m3", "m4" } else .{ "m5", "m6" };
        const loads: [2][]const u8 = if (i == 0) .{ "m7", "m6" } else .{ "m3", "m4" };
        const inputs: [2][]const u8 = .{ "m1", "m2" };
        try expectStage(&p, refs, loads, inputs);
        for (inputs, 0..) |name, j| {
            const ref = pin(&p, refs[j], 0).x;
            const gate = pin(&p, refs[j], 1).x;
            const cross = pin(&p, loads[j], 0).x;
            try testing.expectEqual(if (i == 0) ref else cross, pin(&p, name, 0).x);
            try testing.expectEqual(i == 0, between(gate, ref, cross));
            const partner = loads[1 - j];
            const partner_d = pin(&p, partner, 0).x;
            try testing.expect(between(pin(&p, partner, 1).x, ref, partner_d));
        }
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}

test "reversed cards and unrelated transistor names preserve the load roles" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const reversed = models ++
        "M6 vout2 vout2 vdd vdd pch\nM5 vout1 vout1 vdd vdd pch\n" ++
        "M4 vout2 vout1 vdd vdd pch\nM3 vout1 vout2 vdd vdd pch\n" ++
        "M2 vout2 vin2 tail vss nch\nM1 vout1 vin1 tail vss nch\nI1 tail vss 1m\n";
    var p = try np.place(testing.allocator, &.default, lib, &.{ag215}, null);
    defer p.deinit();
    var r = try np.place(testing.allocator, &.default, lib, &.{reversed}, null);
    defer r.deinit();
    for ([_][]const u8{ "m1", "m2", "m3", "m4", "m5", "m6" }) |name| {
        for (0..3) |t| try testing.expectEqual(pin(&p, name, t), pin(&r, name, t));
    }
    const renamed = models ++
        "Mbirch red red vdd vdd pch\nMtopaz blue blue vdd vdd pch\n" ++
        "Mivy red blue vdd vdd pch\nMcedar blue red vdd vdd pch\n" ++
        "Mquartz red vin2 node vss nch\nMamber blue vin1 node vss nch\nItest node vss 1m\n";
    var n = try np.place(testing.allocator, &.default, lib, &.{renamed}, null);
    defer n.deinit();
    try expectStage(&n, .{ "mtopaz", "mbirch" }, .{ "mcedar", "mivy" }, .{ "mamber", "mquartz" });
}

test "retained load order, explicit gate face and extra output pins" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const order = ag1034 ++ "*@ order m7 m3 m4 m6\n";
    const extra = ag1034 ++ "C1 vo1 0 2p\nC2 vo2 0 2p\n";
    for ([_][]const u8{ order, extra }) |src| {
        var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
        defer p.deinit();
        try expectOuter(&p, .{ "m7", "m6" }, .{ "m3", "m4" });
    }
    var f = try np.place(testing.allocator, &.default, lib, &.{ag1034 ++ "*@ face m6 g right\n"}, null);
    defer f.deinit();
    try testing.expect(pin(&f, "m6", 1).x > pin(&f, "m6", 0).x);
}
