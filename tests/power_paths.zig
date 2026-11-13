//! Inductive converter power paths, with human terminal coordinates as oracle.
//!
//! Contents: fixtures and private checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

const models = "Converter\n.model nch nmos\n.model pch pmos\n.model dio d\n";
const reservoirs = models ++
    "CSTO stored 0 1p\nCL output 0 1p\nL1 left right 1n\n" ++
    "MP3 left phase1 stored stored pch\nMP2 right control output output pch\n" ++
    "MN1 left phase2 0 0 nch\nMN2 right phase3 0 0 nch\n" ++
    "MCTRL control bias 0 0 nch\nRCTRL vdd control 1k\n";
const flying = models ++
    "CFLY x1 x2 1p\nCO output bottom 1p\nCOP output 0 1p\n" ++
    "D1 bottom x2 dio\nL1 x1 x3 1n\n" ++
    "M1 auxiliary phase5 input vdd pch\nM2 x1 phase1 input vdd pch\n" ++
    "M3 x2 phase2 input vdd pch\nM4 output phase3 x3 vdd pch\n" ++
    "M5 x3 phase4 0 0 nch\nMP10 x1 mirror auxiliary vdd pch\n" ++
    "MP9 mirror mirror auxiliary vdd pch\nMN10 mirror bias 0 0 nch\n";
const block_control = models ++
    ".subckt comp VDD VSS VB1 VB2 INN OUT\n.ends\n" ++
    "CSTO stored 0 1p\nCL output 0 1p\nL1 left right 1n\n" ++
    "MP3 left phase1 stored stored pch\nMP2 right control output output pch\n" ++
    "MN1 left phase2 0 0 nch\nMN2 right phase3 0 0 nch\n" ++
    "X1 vdd 0 bias1 bias2 right control comp\n";
// AG1383's discrete control amplifier; sizes do not affect the drawing.
const discrete_control = models ++
    "CL output 0 1p\nCSTO stored 0 1p\nL1 x1 x2 1n\n" ++
    "M1 n0 bias1 vdd vdd pch\nM10 n2 n4 0 0 nch\nM11 n3 n4 0 0 nch\n" ++
    "M12 n5 n5 vdd vdd pch\nM13 bias4 n5 vdd vdd pch\n" ++
    "M14 bias4 bias4 n1 0 nch\nM15 n1 bias4 0 0 nch\n" ++
    "M2 n6 bias1 vdd vdd pch\nM3 control bias3 n0 vdd pch\n" ++
    "M4 n4 bias3 n6 vdd pch\nM5 n0 control x1 0 nch\nM6 n6 x2 x1 0 nch\n" ++
    "M7 x1 bias2 0 0 nch\nM8 control bias4 n2 0 nch\nM9 n4 bias4 n3 0 nch\n" ++
    "MN1 x1 phase2 0 0 nch\nMN2 x2 phase3 0 0 nch\n" ++
    "MP2 x2 control output vdd pch\nMP3 x1 phase1 stored vdd pch\nR1 n5 0 1k\n";

// ---- private ----

fn reversed(a: std.mem.Allocator, src: []const u8) ![]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, src, '\n');
    const title = it.next().?;
    while (it.next()) |line| try lines.append(a, line);
    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "{s}\n", .{title});
    var i = lines.items.len;
    while (i > 0) {
        i -= 1;
        try out.print(a, "{s}\n", .{lines.items[i]});
    }
    return out.items;
}

fn expectForms(src: []const u8, flat: []const []const u8, upright: []const []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    // Card-order reversal is a metamorphic oracle for the same named forms.
    for ([_][]const u8{ src, try reversed(a, src) }) |deck| {
        var nl = try np.netlist.parse(a, &.{deck}, null);
        const roles = try np.guessRoles(a, &nl);
        const st = try np.schematic.structure.analyze(a, a, &nl, roles);
        const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
        for (flat) |name| try testing.expectEqual(np.schematic.skeleton.Form.horizontal, sk.form[nl.device(name).?.index()]);
        for (upright) |name| try testing.expectEqual(np.schematic.skeleton.Form.vertical, sk.form[nl.device(name).?.index()]);
        try np.schematic.skeleton.validate(&sk, &nl);
        for (nl.hints, sk.verdicts) |hint, verdict| if (hint.verb == .upright) {
            try testing.expect(verdict != null);
            try testing.expectEqual(np.hints.State.honoured, verdict.?.state);
        };
        var p = try np.place(testing.allocator, &.default, lib, &.{deck}, null);
        defer p.deinit();
        for ([_][]const []const u8{ flat, upright }, 0..) |names, form| for (names) |name| {
            const d = np.checks.deviceIn(&p, name).?;
            const pin0 = p.dev_pin0[d];
            // SPICE MOS order is D/G/S/B; a coil has just its two ends.
            // Neither the gate nor bulk substitutes for a channel end.
            const drain = p.pin_xy[pin0];
            const source = p.pin_xy[pin0 + @as(u32, if (name[0] == 'm') 2 else 1)];
            try testing.expectEqual(form == 0, drain.y == source.y);
            try testing.expectEqual(form == 1, drain.x == source.x);
        };
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}

fn expectSeries(src: []const u8, names: [3][]const u8) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
    defer p.deinit();
    var centers: [3]np.Pt = undefined;
    for (names, 0..) |name, i| {
        const d = np.checks.deviceIn(&p, name).?;
        const pin0 = p.dev_pin0[d];
        const first = p.pin_xy[pin0];
        const last = p.pin_xy[pin0 + @as(u32, if (i == 1) 1 else 2)];
        try testing.expectEqual(first.y, last.y);
        centers[i] = .{ .x = @divTrunc(first.x + last.x, 2), .y = first.y };
    }
    try testing.expectEqual(centers[0].y, centers[1].y);
    try testing.expectEqual(centers[1].y, centers[2].y);
    try testing.expect((centers[0].x < centers[1].x and centers[1].x < centers[2].x) or
        (centers[0].x > centers[1].x and centers[1].x > centers[2].x));
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
}

fn expectControlsBelow(src: []const u8, coil_name: []const u8, channels: []const []const u8, block: bool) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
    defer p.deinit();
    const coil = np.checks.deviceIn(&p, coil_name).?;
    const row = p.pin_xy[p.dev_pin0[coil]].y;
    for (channels) |name| {
        const d = np.checks.deviceIn(&p, name).?;
        const pin0 = p.dev_pin0[d];
        // Both channel terminals lie below the power row, independent of
        // symbol origins, mirroring and the location of its gate or body.
        try testing.expect(p.pin_xy[pin0].y > row);
        try testing.expect(p.pin_xy[pin0 + 2].y > row);
    }
    if (block) {
        const d = np.checks.deviceIn(&p, "x1").?;
        // The fixture's semantic OUT is port 5, not an all-terminal mean.
        try testing.expect(p.pin_xy[p.dev_pin0[d] + 5].y > row);
    }
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
}

fn expectGate(src: []const u8, name: []const u8, side: np.Side) !void {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
    defer p.deinit();
    const d = np.checks.deviceIn(&p, name).?;
    const pin0 = p.dev_pin0[d];
    const drain = p.pin_xy[pin0];
    const gate = p.pin_xy[pin0 + 1];
    const source = p.pin_xy[pin0 + 2];
    try testing.expectEqual(drain.y, source.y);
    try testing.expectEqual(side == .down, gate.y > drain.y);
    try testing.expectEqual(side, lib.at(p.dev_class[d]).side(1, p.dev_orient[d]).?);
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
}

test "power paths: reservoir switches lie along an inductor and ground shunts stand upright" {
    // Oracle: AG1363 MP3/LRX/MP2 form a horizontal power path between
    // CSTO and CL; MN1/MN2 stand upright below it. AG1383 keeps that
    // orientation when a transistor amplifier drives MP2's gate. The
    // reservoir and storage nets are not recognized supply-name aliases.
    try expectForms(reservoirs, &.{ "mp3", "l1", "mp2" }, &.{ "mn1", "mn2", "mctrl" });
    const renamed = try std.mem.replaceOwned(u8, testing.allocator, reservoirs, "stored", "n17");
    defer testing.allocator.free(renamed);
    try expectForms(renamed, &.{ "mp3", "l1", "mp2" }, &.{ "mn1", "mn2", "mctrl" });
}

test "power paths: flying-capacitor branches lie flat but nearby mirror and auxiliary supply stay upright" {
    // Oracle: AG1250 M2/M3/M4 lie flat on the main power path, while MP10
    // stands upright despite sharing L1's node. The auxiliary supply switch
    // is upright in AG1199:M1 and AG1202:M5; sharing the input bus alone
    // cannot justify rotating that capacitor/inductor-free branch.
    try expectForms(flying, &.{ "m2", "l1", "m3", "m4" }, &.{ "m1", "m5", "mp10", "mp9", "mn10" });
}

test "power paths: the reservoir switches and inductor stay in physical series order on one row" {
    // Oracle: AG1363's channel endpoints and LRX terminals share one y;
    // MP3, LRX, MP2 occur in order. A whole-drawing horizontal reflection
    // preserves this relation. Individual horizontal forms are insufficient.
    try expectSeries(reservoirs, .{ "mp3", "l1", "mp2" });
}

test "power paths: the main series row passes flying-capacitor and bias-column taps" {
    // Oracle: AG1250 M2/L1/M4 share a row in that order, even though CFLY
    // and upright MP10 also touch L1's input node. Neither tap ends the path.
    try expectSeries(flying, .{ "m2", "l1", "m4" });
}

test "power paths: a reservoir control block and externally driven shunts lie below the main channel" {
    // Oracle: AG1363 MP3/LRX/MP2 stand above MN1/MN2 and X1's OUT.
    // All 75 source blocks driving a certified path's main gate have
    // their output below the path; all 365 external-gate ground shunts
    // have both D/S terminals below it. The block remains an opaque cell.
    try expectControlsBelow(block_control, "l1", &.{ "mn1", "mn2" }, true);
}

test "power paths: active gate drivers stand below the channel without imposing an order on unrelated bias devices" {
    // Oracle: AG1383 M3/M8 drive MP2's gate from below the main path.
    // Both D/S terminals lie below it for all 92 selected direct drivers.
    // M1/M2 and the other bias devices have no asserted position here.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try expectControlsBelow(discrete_control, "l1", &.{ "m3", "m8", "mn1", "mn2" }, false);
    try expectControlsBelow(try reversed(arena.allocator(), discrete_control), "l1", &.{ "m3", "m8", "mn1", "mn2" }, false);
}

test "power paths: source ports and crossing bias columns do not push the main row below active controls" {
    // Oracle: actual AG1383 and AG1250 human D/S coordinates. Keeping the
    // original top-level ports matters: the old generic column fallback
    // put these main paths below their controls despite the reduced and
    // renamed equivalents passing. Model dimensions are irrelevant here.
    // Select DUT's body as cktimg-json does; spell its inferred port-role
    // hints explicitly so the public place() seam sees that same circuit.
    const ag1383 = models ++
        \\CL VOUT VSS 1p
        \\CSTO VSTO VSS 1p
        \\LRX VX1 VX2 1n
        \\M1 net0 VB1 VDD VDD pch
        \\M10 net2 net4 VSS VSS nch
        \\M11 net3 net4 VSS VSS nch
        \\M12 net5 net5 VDD VDD pch
        \\M13 VB4 net5 VDD VDD pch
        \\M14 VB4 VB4 net1 VSS nch
        \\M15 net1 VB4 VSS VSS nch
        \\M2 net6 VB1 VDD VDD pch
        \\M3 VC VB3 net0 VDD pch
        \\M4 net4 VB3 net6 VDD pch
        \\M5 net0 VC VX1 VSS nch
        \\M6 net6 VX2 VX1 VSS nch
        \\M7 VX1 VB2 VSS VSS nch
        \\M8 VC VB4 net2 VSS nch
        \\M9 net4 VB4 net3 VSS nch
        \\MN1 VX1 VCONT2 VSS VSS nch
        \\MN2 VX2 VCONT3 VSS VSS nch
        \\MP2 VX2 VC VOUT VDD pch
        \\MP3 VX1 VCONT1 VSTO VDD pch
        \\R1 net5 VSS 1k
        \\*@ weak role vsto output
        \\*@ weak role vcont1 input
        \\*@ weak role vcont2 input
        \\*@ weak role vcont3 input
    ;
    const ag1250 = models ++
        \\.model DIODE D
        \\CFLY VX1 VX2 1p
        \\CO VP VN 1p
        \\COP VP VSS 1p
        \\D1 VN VX2 DIODE
        \\L1 VX1 VX3 1n
        \\M1 VS VC5 VIN VDD pch
        \\M2 VX1 VC1 VIN VDD pch
        \\M3 VX2 VC2 VIN VDD pch
        \\M4 VP VC3 VX3 VDD pch
        \\M5 VX3 VC4 VSS VSS nch
        \\MN1 net3 VFP1 net4 VSS nch
        \\MN10 net0 net2 VSS VSS nch
        \\MN11 net2 VB2 VSS VSS nch
        \\MN2 VX3 VREF net4 VSS nch
        \\MN3 VB3 VB3 VSS VSS nch
        \\MN4 net4 VB3 VSS VSS nch
        \\MN5 net5 net5 VSS VSS nch
        \\MN6 VCTRL net5 VSS VSS nch
        \\MN7 VB1 VB1 VSS VSS nch
        \\MN8 net1 VB1 VX2 VSS nch
        \\MN9 net2 net2 VSS VSS nch
        \\MP1 net5 net3 VDD VDD pch
        \\MP10 VX1 net0 VS VDD pch
        \\MP2 net3 net3 VDD VDD pch
        \\MP3 VX3 VX3 VDD VDD pch
        \\MP4 VCTRL VX3 VDD VDD pch
        \\MP5 VB3 net1 VDD VDD pch
        \\MP6 net1 net1 VDD VDD pch
        \\MP7 VB1 net1 VDD VDD pch
        \\MP8 net2 VCTRL VS VDD pch
        \\MP9 net0 net0 VS VDD pch
        \\R1 VP VFP1 1k
        \\R2 VFP1 VSS 1k
        \\RBIAS VX2 VSS 1k
        \\*@ weak role vc5 input
        \\*@ weak role vc1 input
        \\*@ weak role vc2 input
        \\*@ weak role vc3 input
        \\*@ weak role vc4 input
        \\*@ weak role vp output
    ;
    try expectControlsBelow(ag1383, "lrx", &.{ "m3", "m8", "mn1", "mn2" }, false);
    try expectControlsBelow(ag1250, "l1", &.{"m5"}, false);
}

test "power paths: explicit row and cell instructions override control-block placement" {
    // Oracle: the caller's explicit relation/coordinates, applied after
    // inferred placement even when they put a controller above its path.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "*@ row x1 mn1\n", "*@ cell x1 0 -6\n" }, 0..) |hint, i| {
        const src = try std.mem.concat(a, u8, &.{ block_control, hint });
        var nl = try np.netlist.parse(a, &.{src}, null);
        const roles = try np.guessRoles(a, &nl);
        const st = try np.schematic.structure.analyze(a, a, &nl, roles);
        const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
        try np.schematic.skeleton.validate(&sk, &nl);
        const block = nl.device("x1").?.index();
        if (i == 0) {
            try testing.expectEqual(sk.y[nl.device("mn1").?.index()], sk.y[block]);
        } else {
            try testing.expectEqual(0, sk.x[block] + sk.origin[0]);
            try testing.expectEqual(-6, sk.y[block] + sk.origin[1]);
        }
        try testing.expectEqual(np.hints.State.honoured, sk.verdicts[0].?.state);
    }
}

test "power paths: LC oscillators and inductively loaded amplifiers do not establish a converter" {
    // Oracle: AG1109's cross-coupled PMOS LC oscillator and AG491's PMOS
    // common-gate LNA transistor remain upright. A capacitor and an
    // inductor alone do not establish the converter's grounded NMOS shunt.
    const oscillator = models ++
        "C1 tail 0 1p\nL1 a 0 1n\nL2 b 0 1n\n" ++
        "M1 a b tail vdd pch\nM2 b a tail vdd pch\nM3 tail bias vdd vdd pch\n";
    const amplifier = models ++
        "L1 vdd mid 1n\nL2 out 0 1n\nM1 mid in 0 0 nch\nM2 out bias mid vdd pch\n";
    const no_shunt = models ++ "L1 a b 1n\nR1 b 0 1k\nC1 stored 0 1p\nM1 a phase stored vdd pch\n";
    try expectForms(oscillator, &.{}, &.{ "m1", "m2", "m3" });
    try expectForms(amplifier, &.{}, &.{ "m1", "m2" });
    try expectForms(no_shunt, &.{}, &.{"m1"});
}

test "power paths: a caller's upright instruction overrides the converter habit" {
    // Oracle: the caller's explicit deck instruction takes precedence over
    // a human habit, even for AG1363's otherwise horizontal reservoir switch.
    try expectForms(reservoirs ++ "*@ upright mp2\n", &.{"mp3"}, &.{ "mp2", "mn1", "mn2", "mctrl" });
}

test "power paths: a two-reservoir path's external control faces down" {
    // Oracle: AG1363 MP3's gate is below its channel, as are all 107
    // external main controls where both outer channel ends have ground
    // capacitors. The other 107 main gates have active drivers below.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try expectGate(reservoirs, "mp3", .down);
    try expectGate(try reversed(arena.allocator(), reservoirs), "mp3", .down);
    // Swapping the channel's card order preserves its two outer reservoirs.
    const swapped = try std.mem.replaceOwned(u8, arena.allocator(), reservoirs, "MP3 left phase1 stored stored pch", "MP3 stored phase1 left stored pch");
    try expectGate(swapped, "mp3", .down);
}

test "power paths: the external-control direction does not extend to input-bus branches" {
    // Oracle: AG1250's M2/M3/M4 have gates above their channels. The
    // related 145 input-bus paths have 159 downward and 131 upward main
    // gates, so an external gate or one reservoir alone cannot decide.
    try expectGate(flying, "m2", .up);
    try expectGate(flying, "m3", .up);
    try expectGate(flying, "m4", .up);
}

test "power paths: an explicit turn overrides the two-reservoir gate habit" {
    // Oracle: r0 puts the library PMOS gate up, as requested by the caller.
    try expectGate(reservoirs ++ "*@ at mp3 -10 -10 r0\n", "mp3", .up);
}
