//! Regressions for the router's guarantees (`wire_gates`): no wire on or
//! beside another net's rail symbol, no wire end that meets nothing, no net
//! in a loop. The gates on a drawing built by hand, the decks that broke
//! them, and the fixture decks known to break them still.
//!
//! Oracles: the gates on a hand-built drawing whose findings are counted
//! by hand; then the gates themselves, which read only the finished
//! `Placed` (pins, wires, labels), never the code that drew it; and
//! `checks.connected` that the nets stay one piece.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const fixtures = @import("fixtures.zig");

const Pt = np.Pt;
const Finding = np.checks.Finding;

/// The fixture decks known to break a router gate, with the rule: a known
/// failure of wire_gates.1 to .3. A deck that leaves this list fails the
/// test until its name is taken out.
const known = [_][]const u8{};

/// fable3's `x-under-min.sp`: `fb` wired under the drawing. Before, its
/// run stood past its one tap at both ends, and the riser to it ran a
/// unit beside r1's ground symbol.
const under =
    \\* minimal: wire under leaves a dangling stub
    \\*@ weak role vin input
    \\*@ weak role vout output
    \\*@ wire fb under
    \\M1 vout vin vdd vdd pch l=0.15 w=1
    \\M2 n1 fb vss vss nch l=0.15 w=1
    \\R0 vdd n1 1k
    \\R2 vout fb 1k
    \\R1 fb vss 1k
;

/// AMS385: before, the input's trunk took a track on which m1's gate ran
/// through the trunk and on to its tap row, a loop.
const ams385 =
    \\* AMS385
    \\*@ weak role vin1 input
    \\*@ weak role vout1 output
    \\.model nch nmos
    \\CDB Vout1 VSS 1p
    \\CGD Vout1 Vin1 1p
    \\CGS Vin1 VSS 1p
    \\M1 Vout1 Vin1 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\RD VDD Vout1 1k
;

fn find(p: *const np.Placed, lib: *const np.Library) !std.ArrayList(Finding) {
    var out: std.ArrayList(Finding) = .empty;
    errdefer out.deinit(testing.allocator);
    try np.wire_gates.find(testing.allocator, &out, p, lib);
    return out;
}

fn count(found: []const Finding, rule: np.checks.Rule) usize {
    var n: usize = 0;
    for (found) |f| n += @intFromBool(f.rule == rule);
    return n;
}

test "wire gates: by hand, a wire beside a ground bar, a run past its tap and a ring" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const gnd = lib.findRole(.ground_rail).?;
    // Net 0 (a): a run from (0,0) to (40,0), a riser at x = 20 from a
    // pin at (20,40) up to it, and a wire at x = 70 from (70,-10) to
    // (70,10), a unit right of the ground bar at x 51..69 (pin (60,0)).
    // Net 2 (b): a ring of two L's. The pin at (20,40) is a second ground
    // symbol's, a's own. By hand: one glyph touch, two dangling ends of the
    // run, one of the wire at x = 70 at each end, and b's ring has no end
    // but loops.
    const pts = [_]Pt{
        .{ .x = 0, .y = 0 },    .{ .x = 40, .y = 0 },
        .{ .x = 20, .y = 40 },  .{ .x = 20, .y = 0 },
        .{ .x = 70, .y = -10 }, .{ .x = 70, .y = 10 },
        .{ .x = 0, .y = 100 },  .{ .x = 20, .y = 100 },
        .{ .x = 20, .y = 120 }, .{ .x = 20, .y = 120 },
        .{ .x = 0, .y = 120 },  .{ .x = 0, .y = 100 },
    };
    var p: np.Placed = .{
        .arena = .init(gpa),
        .dev_name = &.{ "", "" },
        .dev_class = &.{ gnd, gnd },
        .dev_value = &.{ "", "" },
        .dev_pos = &.{ .{ .x = 60, .y = 0 }, .{ .x = 20, .y = 40 } },
        .dev_orient = &.{ .r0, .r0 },
        .dev_pin0 = &.{ 0, 1, 2 },
        .pin_net = &.{ 1, 0 },
        .pin_xy = &.{ .{ .x = 60, .y = 0 }, .{ .x = 20, .y = 40 } },
        .net_name = &.{ "a", "gnd", "b" },
        .net_seg = &.{ 0, 3, 3, 5 },
        .seg_pt = &.{ 0, 2, 4, 6, 9, 12 },
        .wire_pts = &pts,
        .junctions = &.{},
        .labels = &.{},
        .no_connects = &.{},
    };
    defer p.deinit();
    var found = try find(&p, lib);
    defer found.deinit(gpa);
    errdefer for (found.items) |f| std.debug.print("  {t} net {d} at ({d},{d})\n", .{ f.rule, f.net, f.at.x, f.at.y });
    try testing.expectEqual(1, count(found.items, .glyph_touch));
    try testing.expectEqual(4, count(found.items, .dangling_end));
    try testing.expectEqual(1, count(found.items, .net_loop));
    for (found.items) |f| if (f.rule == .net_loop) try testing.expectEqual(2, f.net);
}

test "wire gates: a run wired under ends on its taps, clear of the ground symbol" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{under}, null);
    defer p.deinit();
    var found = try find(&p, lib);
    defer found.deinit(testing.allocator);
    errdefer for (found.items) |f| std.debug.print("  {t} net {d} at ({d},{d})\n", .{ f.rule, f.net, f.at.x, f.at.y });
    try testing.expectEqual(0, found.items.len);
    try support.expectConnected(&p, lib);
}

test "wire gates: an input's trunk closes no loop (AMS385)" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{ams385}, null);
    defer p.deinit();
    var found = try find(&p, lib);
    defer found.deinit(testing.allocator);
    errdefer for (found.items) |f| std.debug.print("  {t} net {d} at ({d},{d})\n", .{ f.rule, f.net, f.at.x, f.at.y });
    try testing.expectEqual(0, count(found.items, .net_loop));
    try support.expectConnected(&p, lib);
}

test "wire gates: the fixture decks that break a router gate are the known ones" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var flagged: std.ArrayList([]const u8) = .empty;
    defer flagged.deinit(gpa);
    for (fixtures.plugin) |f| {
        var p = np.place(gpa, &.default, lib, &.{f.spice}, null) catch continue;
        defer p.deinit();
        var found = try find(&p, lib);
        defer found.deinit(gpa);
        if (found.items.len > 0) try flagged.append(gpa, f.name);
    }
    errdefer for (flagged.items) |n| std.debug.print("flagged: {s}\n", .{n});
    try testing.expectEqual(known.len, flagged.items.len);
    for (known, flagged.items) |want, got| try testing.expectEqualStrings(want, got);
}
