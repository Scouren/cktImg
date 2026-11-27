//! Channel-bridge decks -> placed terminal axes and electrical connectivity.
//! Oracle: actual SVG lead strokes in AG387/440/550/987 (always-on
//! complementary channels) and AG739/1048/1052/1149 (antiparallel
//! diode-connected channels). See channel_bridges.py and its inventories.
//! No generated form table supplies the expected orientation.
//!
//! Contents: source-derived local decks, private checks, then placement tests.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const testing = std.testing;

const models = "Channel bridges\n.model nch nmos\n.model pch pmos\n" ++
    ".model qn npn\n.model qp pnp\n";
const loads = "R1 vdd left 1k\nR2 vdd right 1k\n";
const transmission = "M1 left vdd right vss nch\nM2 right vss left vdd pch\n";
const clamps = "M1 left left right vss nch\nM2 right right left vss nch\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, k: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.pinRange(d)[0] + k];
}

fn expectAxis(p: *const np.Placed, name: []const u8, horizontal: bool) !void {
    const a = pin(p, name, 0);
    const b = pin(p, name, 2);
    if (horizontal) {
        try testing.expectEqual(a.y, b.y);
        try testing.expect(a.x != b.x);
    } else {
        try testing.expectEqual(a.x, b.x);
        try testing.expect(a.y != b.y);
    }
}

fn expectConnected(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

test "channel bridges: always-on complementary channels lie horizontally" {
    // Oracle: all eight source channels in AG387/440/550/987 are
    // horizontal. D/S reversal and card order preserve the pair;
    // supply/sink control roles are unchanged.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const decks = [_][]const u8{
        models ++ transmission,
        models ++ "M2 left vss right vdd pch\nM1 left vdd right vss nch\n",
        models ++ "M2 right vss left vdd pch\nM1 right vdd left vss nch\n",
    };
    for (decks) |deck| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{deck}, null);
        defer p.deinit();
        try expectAxis(&p, "m1", true);
        try expectAxis(&p, "m2", true);
        try expectConnected(&p, lib);
    };
}

test "channel bridges: antiparallel diode-connected MOS and BJT channels lie horizontally" {
    // Oracle: AG739/1048/1052 have horizontal MOS clamps, AG1149 has
    // horizontal NPN clamps. Gate/base stays tied to its own drain/
    // collector. The surrounding load paths do not supply this axis.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const cases = [_]struct { []const u8, []const u8, []const u8 }{
        .{ models ++ loads ++ clamps, "m1", "m2" },
        .{ models ++ "M8 right right left vss nch\nM4 left left right vss nch\n" ++ loads, "m4", "m8" },
        .{ models ++ loads ++ "Q1 left left right vss qn\nQ2 right right left vss qn\n", "q1", "q2" },
        .{ models ++ "Q8 right right left vss qn\nQ4 left left right vss qn\n" ++ loads, "q4", "q8" },
    };
    for (cases) |case| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{case[0]}, null);
        defer p.deinit();
        try expectAxis(&p, case[1], true);
        try expectAxis(&p, case[2], true);
        try expectConnected(&p, lib);
    };
}

test "channel bridges: biased complementary stages and incomplete pairs remain upright" {
    // Negative source: AG175's complementary channels share off-rail
    // endpoints but have bias controls and are vertical. The other decks
    // remove one certificate at a time: polarity, correct control rail,
    // off-rail channels, unique partner or diode-connected direction.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const decks = [_][]const u8{
        models ++ "I1 vdd left 1m\nI2 right vss 1m\nRS input right 1k\n" ++
            "M1 left vb2 right vss nch\nM2 right vb1 left vdd pch\n",
        models ++ "M1 left vdd right vss nch\nM2 right vss left vss nch\n",
        models ++ "M1 left vss right vss nch\nM2 right vdd left vdd pch\n",
        models ++ "M1 left vdd right vss nch\nM2 right bias left vdd pch\n",
        models ++ "M1 vcc vdd right vss nch\nM2 right vss vcc vdd pch\n",
        models ++ transmission ++ "M3 left clock right vss nch\n",
        models ++ "M1 left left right vss nch\nM2 right right left vdd pch\n",
        models ++ "M1 left left right vss nch\nM2 left left right vss nch\n",
        models ++ "M1 left left right vss nch\nM2 right control left vss nch\n",
        models ++ clamps ++ "M3 left left right vss nch\n",
        models ++ "M1 vdd vdd right vss nch\nM2 right right vdd vss nch\n",
    };
    for (decks) |deck| {
        var p = try np.place(testing.allocator, &.default, lib, &.{deck}, null);
        defer p.deinit();
        try expectAxis(&p, "m1", false);
        try expectAxis(&p, "m2", false);
        try expectConnected(&p, lib);
    }
    var bipolar = try np.place(testing.allocator, &.default, lib, &.{models ++
        "Q1 left left right vss qn\nQ2 right right left vdd qp\n"}, null);
    defer bipolar.deinit();
    try expectAxis(&bipolar, "q1", false);
    try expectAxis(&bipolar, "q2", false);
    try expectConnected(&bipolar, lib);
}

test "channel bridges: explicit upright instructions override both bridge habits" {
    // Oracle: caller steering wins over a source habit, including a
    // single member; no bridge rule may rotate the instructed member.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const decks = [_][]const u8{
        models ++ transmission ++ "*@ upright m1 m2\n",
        models ++ loads ++ clamps ++ "*@ upright m1 m2\n",
        models ++ transmission ++ "*@ upright m1\n",
    };
    for (decks) |deck| {
        var p = try np.place(testing.allocator, &.default, lib, &.{deck}, null);
        defer p.deinit();
        try expectAxis(&p, "m1", false);
        try expectConnected(&p, lib);
    }
}
