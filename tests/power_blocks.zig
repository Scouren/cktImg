//! Converter control-block direction and electrical pin alignment.
//!
//! Contents: source fixtures, private geometry checks, then tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

const prefix = "Converter block\n.model nch nmos\n.model pch pmos\n";
const path = "CSTO stored 0 1p\nCL output 0 1p\nL1 left right 1n\n" ++
    "MP3 left phase1 stored stored pch\nMP2 right control output output pch\n" ++
    "MN1 left phase2 0 0 nch\nMN2 right phase3 0 0 nch\n";
const opaque_def = ".subckt comp VDD VSS INN OUT VX VB1 VB2\n.ends\n";
const opaque_card = "X1 vdd 0 right control left vb1 vb2 comp\n";
const signed = ".subckt comparator VDD VSS INN OUT VB1 VB2\n.ends\n";
const signed_card = "X1 vdd 0 right control vb1 vb2 comparator\n";
const base = prefix ++ opaque_def ++ path ++ opaque_card;

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, terminal: usize) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.dev_pin0[d] + terminal];
}

fn expectSide(p: *const np.Placed, lib: *const np.Library, side: np.Side) !void {
    const d = np.checks.deviceIn(p, "x1").?;
    try testing.expectEqual(side, lib.at(p.dev_class[d]).side(3, p.dev_orient[d]).?);
}

fn expectAligned(p: *const np.Placed, lib: *const np.Library) !void {
    const out = pin(p, "x1", 3);
    const gate = pin(p, "mp2", 1);
    const channel = pin(p, "mp2", 0);
    try expectSide(p, lib, .up);
    try testing.expectEqual(out.x, gate.x);
    try testing.expect(out.y > gate.y);
    try testing.expect(gate.y > channel.y);
    try testing.expect(out.y < pin(p, "x1", 2).y);
}

fn expectElectrical(p: *const np.Placed, lib: *const np.Library) !void {
    const d = np.checks.deviceIn(p, "x1").?;
    const pins = p.pin_net[p.dev_pin0[d]..p.dev_pin0[d + 1]];
    const names: []const []const u8 = if (pins.len == 7)
        &.{ "vdd", "0", "right", "control", "left", "vb1", "vb2" }
    else
        &.{ "vdd", "0", "right", "control", "vb1", "vb2" };
    try testing.expectEqual(names.len, pins.len);
    for (pins, names) |net, name| try testing.expectEqualStrings(name, p.net_name[net]);
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

fn expectHonoured(src: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const verdicts = try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib);
    for (verdicts) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
}

test "power blocks: opaque and signed controllers face up at the actual MOS gate" {
    // Oracle: 67/75 selected source SVG OUT leads face up on the main
    // gate's x line; AG1355 retains its opaque VX port. Eight source glyphs
    // face right despite 75/75 cached terminal pairs sharing x. This test
    // represents the upward habit, not those unresolved cases. A signed input
    // has nonzero y in the canonical glyph, so its settled grid is not
    // its origin. The electrical OUT/G relation must survive that offset.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_][]const u8{ base, prefix ++ signed ++ path ++ signed_card }, 0..) |src, k| {
        for ([_]bool{ false, true }) |compact| {
            var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
            defer p.deinit();
            if (k == 1) {
                const c = lib.at(p.dev_class[np.checks.deviceIn(&p, "x1").?]);
                try testing.expect(c.terminals[2].at.y != c.terminals[3].at.y);
            }
            try expectAligned(&p, lib);
            try expectElectrical(&p, lib);
        }
    }
}

test "power blocks: device card reversal preserves pins and an unrelated at preserves alignment" {
    // Oracles: circuit permutation leaves named pins unchanged; a retained
    // unrelated turn must not reset the controller's settled grid anchor.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(gpa);
    var it = std.mem.tokenizeScalar(u8, path ++ signed_card, '\n');
    while (it.next()) |line| try lines.append(gpa, line);
    std.mem.reverse([]const u8, lines.items);
    var reverse: std.ArrayList(u8) = .empty;
    defer reverse.deinit(gpa);
    try reverse.appendSlice(gpa, prefix ++ signed);
    for (lines.items) |line| {
        try reverse.appendSlice(gpa, line);
        try reverse.append(gpa, '\n');
    }
    var before = try np.place(gpa, &.default, lib, &.{prefix ++ signed ++ path ++ signed_card}, null);
    defer before.deinit();
    var after = try np.place(gpa, &.default, lib, &.{reverse.items}, null);
    defer after.deinit();
    for (before.dev_name, 0..) |name, d| {
        if (name.len == 0) continue;
        const other = np.checks.deviceIn(&after, name).?;
        try testing.expectEqual(before.dev_orient[d], after.dev_orient[other]);
        try testing.expectEqualSlices(np.Pt, before.pin_xy[before.dev_pin0[d]..before.dev_pin0[d + 1]], after.pin_xy[after.dev_pin0[other]..after.dev_pin0[other + 1]]);
    }
    try expectAligned(&after, lib);
    try expectElectrical(&after, lib);
    const fixed = prefix ++ signed ++ path ++ signed_card ++ "Rprobe probe 0 1k\n*@ at rprobe -20 20 r90\n";
    var p = try np.place(gpa, &.default, lib, &.{fixed}, null);
    defer p.deinit();
    try expectAligned(&p, lib);
    try expectElectrical(&p, lib);
    try expectHonoured(fixed, &p, lib);
}

test "power blocks: honoured cell and row relations can defeat inferred controller alignment" {
    // Oracle: caller geometry. These independent positions put OUT level
    // with or above the channel, so the source's below-path case is absent.
    // The two rows and their ordering explicitly imply the second relation.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_][]const u8{
        base ++ "*@ cell mp2 8 8\n*@ cell x1 2 8\n",
        base ++ "*@ above cl mn1\n*@ row x1 cl\n*@ row mp2 mn1\n",
    }, 0..) |src, k| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = false } }, lib, &.{src}, null);
        defer p.deinit();
        if (k == 0) {
            try testing.expectEqual(pin(&p, "x1", 3).y, pin(&p, "mp2", 0).y);
            try testing.expect(pin(&p, "x1", 3).x != pin(&p, "mp2", 1).x);
        } else try testing.expect(pin(&p, "x1", 3).y < pin(&p, "mp2", 0).y);
        try expectSide(&p, lib, .right);
        try expectElectrical(&p, lib);
        try expectHonoured(src, &p, lib);
    }
}

test "power blocks: exact origins with and without a turn retain caller geometry" {
    // Oracle: the at contract specifies class origins, not lattice points.
    // Either participant's fixed origin makes inferred alignment inapplicable.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_][]const u8{ "x1", "mp2" }) |name| for ([_][]const u8{ "", " r0" }) |turn| {
        const src = try std.fmt.allocPrint(gpa, "{s}*@ at {s} -20 20{s}\n", .{ base, name, turn });
        defer gpa.free(src);
        var p = try np.place(gpa, &.default, lib, &.{src}, null);
        defer p.deinit();
        const d = np.checks.deviceIn(&p, name).?;
        try testing.expectEqual(np.Pt{ .x = -20 * lib.unit, .y = 20 * lib.unit }, p.dev_pos[d]);
        if (turn.len != 0) try testing.expectEqual(np.Orient.r0, p.dev_orient[d]);
        try expectSide(&p, lib, .right);
        try expectElectrical(&p, lib);
        try expectHonoured(src, &p, lib);
    };
}

test "power blocks: definition sides win and an off-axis controller pin still aligns" {
    // Oracles: an explicit side is already a geometry decision; a caller's
    // OUT at y=15 must align by its electrical terminal, not by the class
    // origin. Rotation may move other terminals without reassigning them.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const directed = prefix ++ ".subckt comp VDD VSS INN OUT VX VB1 VB2\n*@ right OUT\n.ends\n" ++ path ++ opaque_card;
    var explicit = try np.place(gpa, &.default, lib, &.{directed}, null);
    defer explicit.deinit();
    try expectSide(&explicit, lib, .right);
    try expectElectrical(&explicit, lib);
    const own = try lib.register(.{ .name = "offset_controller", .terminals = &.{
        .{ .name = "vdd", .at = .{ .x = 0, .y = -60 }, .side = .up },
        .{ .name = "vss", .at = .{ .x = -40, .y = 60 }, .side = .down },
        .{ .name = "inn", .at = .{ .x = -60, .y = -20 }, .side = .left },
        .{ .name = "out", .at = .{ .x = 60, .y = 15 }, .side = .right },
        .{ .name = "vx", .at = .{ .x = -60, .y = 20 }, .side = .left },
        .{ .name = "vb1", .at = .{ .x = 0, .y = 60 }, .side = .down },
        .{ .name = "vb2", .at = .{ .x = 40, .y = 60 }, .side = .down },
    } });
    const custom = base ++ "*@ class x1 offset_controller\n";
    var p = try np.place(gpa, &.default, lib, &.{custom}, null);
    defer p.deinit();
    try testing.expectEqual(own, p.dev_class[np.checks.deviceIn(&p, "x1").?]);
    try expectAligned(&p, lib);
    try expectElectrical(&p, lib);
    try expectHonoured(custom, &p, lib);
}

test "power blocks: an off-grid main gate does not borrow a controller column" {
    // Oracle: this custom MOS's visible gate and body stand at x=+10/-10,
    // so its automatic grid has x=0 and its gate is not on that column.
    // Only the controller may be reanchored by this rule; an unsupported
    // main frame leaves its controller's established direction intact.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const own = try lib.register(.{ .name = "offset_gate", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 10, .y = -20 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = -10, .y = 20 }, .side = .down },
    } });
    const src = base ++ "*@ class mp2 offset_gate\n";
    var p = try np.place(gpa, &.default, lib, &.{src}, null);
    defer p.deinit();
    try testing.expectEqual(own, p.dev_class[np.checks.deviceIn(&p, "mp2").?]);
    try testing.expect(2 * pin(&p, "mp2", 1).x != pin(&p, "mp2", 0).x + pin(&p, "mp2", 2).x);
    try expectSide(&p, lib, .right);
    try expectElectrical(&p, lib);
    try expectHonoured(src, &p, lib);
}

test "power blocks: a distant output cannot move the grid past other facing pins" {
    // Oracle: after a quarter-left turn OUT.x=1000, beyond the right-facing
    // rail pins at x=60. Anchoring there would reverse those pins' required
    // reach. The ordinary horizontal class remains electrically connected.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    _ = try lib.register(.{ .name = "distant_controller", .terminals = &.{
        .{ .name = "vdd", .at = .{ .x = 0, .y = -60 }, .side = .up },
        .{ .name = "vss", .at = .{ .x = -40, .y = 60 }, .side = .down },
        .{ .name = "inn", .at = .{ .x = -60, .y = -20 }, .side = .left },
        .{ .name = "out", .at = .{ .x = 60, .y = 1000 }, .side = .right },
        .{ .name = "vx", .at = .{ .x = -60, .y = 20 }, .side = .left },
        .{ .name = "vb1", .at = .{ .x = 0, .y = 60 }, .side = .down },
        .{ .name = "vb2", .at = .{ .x = 40, .y = 60 }, .side = .down },
    } });
    const src = base ++ "*@ class x1 distant_controller\n";
    var p = try np.place(gpa, &.default, lib, &.{src}, null);
    defer p.deinit();
    try expectSide(&p, lib, .right);
    try expectElectrical(&p, lib);
    try expectHonoured(src, &p, lib);
}

test "power blocks: multiple output ports are ambiguous even on one gate net" {
    // Oracle: two different main targets give no unique column; two output
    // pins on the same target give no unique physical terminal to anchor.
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_][]const u8{ "phase1", "control" }) |net| {
        const src = try std.fmt.allocPrint(gpa, prefix ++ ".subckt comp VDD VSS INN OUT VOUT\n.ends\n" ++ path ++
            "X1 vdd 0 right control {s} comp\n", .{net});
        defer gpa.free(src);
        var p = try np.place(gpa, &.default, lib, &.{src}, null);
        defer p.deinit();
        try expectSide(&p, lib, .right);
        const d = np.checks.deviceIn(&p, "x1").?;
        try testing.expectEqual(5, p.dev_pin0[d + 1] - p.dev_pin0[d]);
        try testing.expectEqualStrings("control", p.net_name[p.pin_net[p.dev_pin0[d] + 3]]);
        try testing.expectEqualStrings(net, p.net_name[p.pin_net[p.dev_pin0[d] + 4]]);
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(gpa, &p, true));
    }
}
