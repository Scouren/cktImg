//! Concrete complete-owner wiring regressions, source148 and rollback/OOM.
//! Oracle/provenance: docs/research/figures/ct_four_wires_tests.json.
//! Frozen RED7 assertions and fixture values; no production topology oracle.
//!
//! Contents: .

const std = @import("std");
const testing = std.testing;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const netlist = @import("netlist.zig");
const netlines = @import("netlines.zig");
const hints = @import("hints.zig");
const canvas = @import("canvas.zig");
const trunk = @import("trunk.zig");
const maze = @import("maze.zig");
const owner = @import("ct_four_sides.zig");
const routing = @import("ct_four_wires.zig");
const requests = @import("wire_requests.zig");
const literal = @import("ct_four_wire_data.zig");
const Pt = library.Pt;
const fixture = @import("ct_four_wire_fixture.zig");
const oracle = @import("ct_four_wire_oracle.zig");
const run = fixture.run;
const group = fixture.group;
const Change = fixture.Change;
const joined = oracle.joined;

// ---- private ----

fn qualify(extra: []const u8, expected: usize, admitted: bool) !void {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const deck = try std.fmt.allocPrint(a, "{s}\n{s}\n", .{ literal.deck, extra });
    var nl = try netlist.parse(a, &.{deck}, null);
    const roles = try sch.guessRoles(a, &nl);
    const verdicts = try a.alloc(?hints.Verdict, nl.hints.len);
    @memset(verdicts, null);
    const lines = try netlines.read(a, &nl, roles, 40, verdicts);
    if (extra.len > 0) {
        try testing.expect(nl.hints.len > 0);
        const v = verdicts[verdicts.len - 1] orelse return error.RequestWasNotParsed;
        try testing.expectEqual(admitted, v.state == .honoured or v.state == .relaxed);
    }
    const groups = [_]owner.Group{group(&nl)};
    try testing.expectEqual(expected, routing.qualify(&nl, &groups, verdicts, &lines).len);
}

fn oomParts(gpa: std.mem.Allocator) !void {
    try run(gpa, true, .none, false, false);
}

fn oomRail(gpa: std.mem.Allocator) !void {
    try run(gpa, true, .none, false, true);
}

fn contact(second: [2]Pt, foreign: bool, expected: bool) !void {
    var lib: library.Library = .init(testing.allocator);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(testing.allocator), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "one", "other" }, .device_pin_count = &.{}, .roles = &.{ .internal, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    const points = [_]Pt{ .{ .x = -20, .y = 0 }, .{ .x = 20, .y = 0 }, second[0], second[1] };
    for (points, 0..) |p, i| {
        const n: u32 = if (foreign and i >= 2) 1 else 0;
        const node = try s.addNode(.{ .kind = .terminal, .ref = n, .group = sch.none });
        try xy.append(s.arena.allocator(), p.toF());
        _ = try s.addPin(.{ .home = node, .side = .left, .net = n, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    var c = try canvas.Canvas.init(testing.allocator, &s, &xy, .of(.{}, 40), &.{}, &.{});
    defer c.deinit();
    try testing.expect(try c.commit(0, points[0..2]));
    try testing.expect(try c.commit(if (foreign) 1 else 0, &second));
    try testing.expectEqual(expected, try joined(&c, 0, 2));
}

// ---- tests ----

test "whole26 consumer: exact source148 components and one shared supply in both frames" {
    try run(testing.allocator, false, .none, true, false);
    try run(testing.allocator, true, .none, true, false);
    try run(testing.allocator, true, .permuted, true, false);
    try run(testing.allocator, true, .cut, false, false);
}
test "whole26 consumer: real pin mapping and original deferred requests abstain atomically" {
    for ([_]Change{ .missing, .duplicate, .wrong_index, .wrong_net, .projected, .hidden, .extra, .existing_same_net, .first, .port, .route, .via, .at, .routed, .drawn, .no_owner, .label, .wire, .trunk, .ladder, .route_style }) |change| try run(testing.allocator, true, change, false, false);
}
test "whole26 consumer: late second-component failure restores first tree and generated label" {
    try run(testing.allocator, true, .late_blocker, false, false);
}
test "whole26 consumer: opposed supply exact mapping and original request boundaries" {
    for ([_]Change{ .missing, .duplicate, .wrong_index, .wrong_net, .projected, .hidden, .extra, .first, .route, .via, .at, .routed, .drawn, .no_owner }) |change| try run(testing.allocator, true, change, false, true);
}
test "whole26 consumer: normalized rail choices use admitted verdicts, never raw text" {
    for ([_][]const u8{ "bar", "each", "plain" }) |mode| {
        const line = try std.fmt.allocPrint(testing.allocator, "*@ rail vdd {s}", .{mode});
        defer testing.allocator.free(line);
        try qualify(line, 0, true);
    }
    try qualify("*@ first hb", 0, true);
}
test "whole26 consumer: default, invalid and unrelated rail requests retain automatic owner" {
    try qualify("", 1, false);
    try qualify("*@ rail vdd invalid", 1, false);
    try qualify("*@ rail absent bar", 1, false);
    try qualify("*@ rail vss bar", 1, true);
}
test "whole26 consumer: complete net rollback through every allocation failure" {
    var backing = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(backing.allocator(), oomParts, .{});
    try testing.checkAllAllocationFailures(backing.allocator(), oomRail, .{});
}
test "whole26 consumer: source separation oracle rejects endpoint T overlap and proper X mutations" {
    // Canvas accepts every same-net contact; the partition oracle must
    // reject it. A normal foreign-net interior crossing is still legal.
    try contact(.{ .{ .x = -20, .y = 20 }, .{ .x = 20, .y = 20 } }, false, false);
    for ([_][2]Pt{
        .{ .{ .x = 20, .y = 0 }, .{ .x = 20, .y = 20 } },
        .{ .{ .x = 0, .y = 0 }, .{ .x = 0, .y = 20 } },
        .{ .{ .x = 0, .y = 0 }, .{ .x = 30, .y = 0 } },
        .{ .{ .x = 0, .y = -20 }, .{ .x = 0, .y = 20 } },
    }) |line| try contact(line, false, true);
    try contact(.{ .{ .x = 0, .y = -20 }, .{ .x = 0, .y = 20 } }, true, false);
}
