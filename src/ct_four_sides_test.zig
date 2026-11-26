//! Whole26 transaction controls; the public test independently owns source geometry/ink.
//! Oracle: unchanged complete rows/coordinates on a late failed pose, all
//! allocations failing before mutation, and selected versus foreign holds.
//!
//! Contents: fixture/classes, allocation oracle, tests.

const std = @import("std");
const testing = std.testing;
const owner = @import("ct_four_sides.zig");
const placement = @import("ct_four_place.zig");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const Lengths = @import("canvas.zig").Lengths;
const Pt = library.Pt;

const deck =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\C1 M2 P2 1p
    \\C2 M1 P1 1p
    \\LS1 P2 P4 1n
    \\LS2 M2 M4 1n
    \\LS3 P3 P1 1n
    \\LS4 M3 M1 1n
    \\M10 P2 M2 VSS VSS nch l=0.06 w=14 nf=1 m=1
    \\M11 M2 P2 VSS VSS nch l=0.06 w=14 nf=1 m=1
    \\M12 P2 M2 net2 VSS nch l=0.06 w=8 nf=1 m=1
    \\M13 M2 P2 net2 VSS nch l=0.06 w=8 nf=1 m=1
    \\M14 net2 LB VSS VSS nch l=0.06 w=1 nf=1 m=1
    \\M15 P4 P3 net0 VSS nch l=0.06 w=14 nf=1 m=1
    \\M16 P3 P4 net0 VSS nch l=0.06 w=14 nf=1 m=1
    \\M17 net0 HB VSS VSS nch l=0.06 w=1 nf=1 m=1
    \\M18 P4 LB P3 VSS nch l=0.06 w=1 nf=1 m=1
    \\M19 M4 M3 net3 VSS nch l=0.06 w=14 nf=1 m=1
    \\M20 M3 M4 net3 VSS nch l=0.06 w=14 nf=1 m=1
    \\M21 net3 HB VSS VSS nch l=0.06 w=1 nf=1 m=1
    \\M22 M4 LB M3 VSS nch l=0.06 w=1 nf=1 m=1
    \\M5 P1 M1 VSS VSS nch l=0.06 w=14 nf=1 m=1
    \\M6 M1 P1 VSS VSS nch l=0.06 w=14 nf=1 m=1
    \\M7 P1 M1 net1 VSS nch l=0.06 w=8 nf=1 m=1
    \\M8 M1 P1 net1 VSS nch l=0.06 w=8 nf=1 m=1
    \\M9 net1 LB VSS VSS nch l=0.06 w=1 nf=1 m=1
    \\XL1 P4 M4 Vdd ct_inductor l1=1n l2=1n k=0
    \\XL2 P3 M3 Vdd ct_inductor l1=1n l2=1n k=0
    \\*@ weak role p1 output
    \\*@ weak role m1 output
    \\*@ weak role p2 output
    \\*@ weak role m2 output
    \\*@ weak role lb input
    \\*@ weak role hb input
    \\
    \\Rforeign remote 0 1k
;

// ---- private ----

fn classes(lib: *library.Library) ![2]library.ClassId {
    _ = try lib.register(.{ .name = "ct_inductor", .terminals = &.{
        .{ .name = "n1", .at = .{ .x = -43, .y = 11 }, .side = .left },
        .{ .name = "n2", .at = .{ .x = 57, .y = 11 }, .side = .right },
        .{ .name = "n3", .at = .{ .x = 7, .y = 31 }, .side = .down },
    }, .draw = &.{ .ln(-43, 11, 57, 11), .ln(7, 11, 7, 31) } });
    _ = try lib.register(.{ .name = "nmos", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 37, .y = 9 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 7, .y = -21 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -23, .y = 9 }, .side = .left },
    }, .draw = &.{ .ln(17, 9, 37, 9), .ln(-23, 9, -3, 9), .ln(7, -21, 7, 9) } });
    for ([_][]const u8{ "cap", "ind", "res" }) |name| _ = try lib.register(.{
        .name = name,
        .terminals = &.{
            .{ .name = "a", .at = .{ .x = -13, .y = 9 }, .side = .left },
            .{ .name = "b", .at = .{ .x = 27, .y = 9 }, .side = .right },
        },
        .draw = &.{.ln(-13, 9, 27, 9)},
    });
    const skew = try lib.register(.{ .name = "skew_nmos", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 37, .y = 12 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 7, .y = -21 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -23, .y = 9 }, .side = .left },
    }, .draw = &.{ .ln(37, 12, -23, 9), .ln(7, -21, 7, 9) } });
    const circle = try lib.register(.{ .name = "large_tail", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 37, .y = 9 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 7, .y = -21 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -23, .y = 9 }, .side = .left },
    }, .draw = &.{.{ .circle = .{ .c = .{ .x = 7, .y = 9 }, .r = 1000 } }} });
    return .{ skew, circle };
}
fn allocation(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) !void {
    var before: [27]sch.DeviceInfo = undefined;
    for (&before, 0..) |*row, d| row.* = s.devices.get(d);
    var batch = owner.collect(gpa, nl, s, sk, st, ats, lines) catch |err| {
        for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
        return err;
    };
    defer batch.deinit(gpa);
    try testing.expectEqual(@as(usize, 1), batch.groups.items.len);
    for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
}

// ---- tests ----

test "CT whole26 transaction: allocation, held boundaries, shifted frames and late full rollback" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{deck}, null);
    const roles = try sch.guessRoles(a, &nl);
    var lib = library.Library.init(gpa);
    defer lib.deinit();
    const bad = try classes(&lib);
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    try testing.expectEqual(@as(usize, 27), s.devices.len);
    for (0..s.devices.len) |d| s.devices.set(d, .{ .kept = true, .driver = false, .class = s.devices.items(.class)[d], .orientation = .horizontal, .flip_x = false, .flip_y = false, .orient = .r0, .grid = .zero, .reach = @splat(0) });
    sch.settleDevices(&s, &nl.graph);
    var st = try structure.analyze(gpa, a, &nl, roles);
    var sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
    // Public source probe separately checks the real table. At this owner
    // seam, retain contained automatic blocks and isolate all other holds.
    const mates = try a.alloc(u32, s.devices.len);
    @memset(mates, sch.none);
    st.device_mate = mates;
    const drawn = try a.alloc(bool, s.devices.len);
    @memset(drawn, true);
    sk.drawn = drawn;
    const shelf = try a.alloc(u32, s.devices.len);
    @memset(shelf, 0);
    sk.shelf = shelf;
    const ats: [27]?pinned.At = @splat(null);
    const lines = try netlines.read(a, &nl, roles, lib.unit, &.{});
    try testing.checkAllAllocationFailures(gpa, allocation, .{ &nl, &s, &sk, &st, &ats, &lines });
    var batch = try owner.collect(gpa, &nl, &s, &sk, &st, &ats, &lines);
    defer batch.deinit(gpa);
    try testing.expectEqual(@as(usize, 1), batch.groups.items.len);
    const group = batch.groups.items[0];
    const selected = nl.device("m22").?.index();
    const foreign = nl.device("rforeign").?.index();
    for ([_]bool{ false, true }) |unrelated| for (0..7) |guard| {
        const d = if (unrelated) foreign else selected;
        const net = nl.net(if (unrelated) "remote" else "hb").?.index();
        var own_st = st;
        var own_lines = lines;
        var own_ats = ats;
        const old_drawn = drawn[d];
        const old_mate = mates[d];
        defer {
            drawn[d] = old_drawn;
            mates[d] = old_mate;
        }
        const styles = try a.dupe(netlines.Style, lines.style);
        const sides = try a.dupe(?library.Side, lines.port);
        const route = [_]netlines.Route{.{ .net = @intCast(net), .pts = &.{ .{ .x = -90, .y = -90 }, .{ .x = -60, .y = -90 } }, .via = false, .line = 0 }};
        const block = [_]u32{ @intCast(selected), @intCast(foreign) };
        const start = [_]u32{ 0, 2 };
        switch (guard) {
            0 => drawn[d] = false,
            1 => mates[d] = @intCast(foreign),
            2 => own_ats[d] = .{ .origin = .{ .x = -90, .y = -90 }, .orient = .r0, .line = 0 },
            3 => {
                styles[net] = .label;
                own_lines.style = styles;
            },
            4 => {
                sides[net] = .left;
                own_lines.port = sides;
            },
            5 => own_lines.routes = &route,
            6 => if (!unrelated) {
                own_st.block_start = &start;
                own_st.block_devices = &block;
                own_st.block_kind = &.{.cross};
            },
            else => unreachable,
        }
        var held_batch = try owner.collect(gpa, &nl, &s, &sk, &own_st, &own_ats, &own_lines);
        defer held_batch.deinit(gpa);
        try testing.expectEqual(@as(usize, @intFromBool(unrelated)), held_batch.groups.items.len);
    };
    var before: [27]sch.DeviceInfo = undefined;
    for (&before, 0..) |*row, d| row.* = s.devices.get(d);
    var at: [27][2]f32 = @splat(.{ 400, 400 });
    at[foreign] = .{ 4000, 4000 };
    placement.place(&s, &nl, &sk, &ats, Lengths.of(.{}, lib.unit), &at, &batch.groups);
    try testing.expectEqual(@as(usize, 1), batch.groups.items.len);
    try testing.expectEqualDeep(before[foreign], s.devices.get(foreign));
    try testing.expectEqualDeep([2]f32{ 4000, 4000 }, at[foreign]);
    // The public source oracle checks all72 actual leads. Here independently
    // certify whole transaction success, pairwise body clearance and real pins.
    for (group, 0..) |edge, i| {
        const box = s.boxAt(edge.index(), Pt.round(at[edge.index()]));
        for (group[i + 1 ..]) |other| try testing.expect(!box.intersects(s.boxAt(other.index(), Pt.round(at[other.index()]))));
        try testing.expect(@import("actual_anchor.zig").representable(&s, &nl, edge.index()));
    }
    const original = before;
    for (0..2) |failure| {
        for (original, 0..) |row, d| s.devices.set(d, row);
        const changed = if (failure == 0) selected else nl.device("m14").?.index();
        s.devices.items(.class)[changed] = bad[failure];
        sch.settleDevice(&s, &nl.graph, changed);
        for (&before, 0..) |*row, d| row.* = s.devices.get(d);
        const old = at;
        batch.groups.items.len = 1;
        batch.groups.items[0] = group;
        placement.place(&s, &nl, &sk, &ats, Lengths.of(.{}, lib.unit), &at, &batch.groups);
        try testing.expectEqual(@as(usize, 0), batch.groups.items.len);
        try testing.expectEqualDeep(old, at);
        for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
    }
    const coil = nl.device("xl1").?.index();
    const unsupported = try lib.register(.{ .name = "one_coil", .terminals = &.{.{ .name = "n1", .at = .zero, .side = .left }}, .draw = &.{.ln(0, 0, 10, 0)} });
    for (0..4) |failure| {
        for (original, 0..) |row, d| s.devices.set(d, row);
        var points: [27][2]f32 = @splat(.{ 400, 400 });
        points[foreign] = .{ 4000, 4000 };
        if (failure == 0) {
            s.devices.items(.grid)[coil] = .{ .x = -200, .y = 0 };
            points[coil] = .{ 2147483520, 200 };
        }
        if (failure == 1) s.devices.items(.grid)[coil] = .{ .x = std.math.minInt(i32), .y = 0 };
        if (failure >= 2) s.devices.items(.class)[coil] = unsupported;
        if (failure == 3) lib.classes.items[@backingInt(unsupported)].terminals = &.{};
        for (&before, 0..) |*row, d| row.* = s.devices.get(d);
        const old = points;
        batch.groups.items.len = 1;
        batch.groups.items[0] = group;
        placement.place(&s, &nl, &sk, &ats, Lengths.of(.{}, lib.unit), &points, &batch.groups);
        try testing.expectEqual(@as(usize, 0), batch.groups.items.len);
        try testing.expectEqualDeep(old, points);
        for (before, 0..) |row, d| try testing.expectEqualDeep(row, s.devices.get(d));
    }
}

test "CT whole26 admission: extra raw, hidden and rail incidences precede eligibility" {
    const gpa = testing.allocator;
    for ([_][]const u8{
        "",                      "Mextra p4 p3 net0 vss unresolved\n", "Rextra p2 other 1k\n",
        "Rextra lb other 1k\n",  "Mextra aa bb cc vss unresolved\n",   "Xextra m4 p4 othertap ct_inductor\n",
        "Rextra vdd other 1k\n",
    }, 0..) |extra, i| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try a.print("{s}\n{s}", .{ deck, extra });
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        try testing.expectEqual(27 + @as(usize, @intFromBool(i != 0)), nl.graph.edgeCount());
        var lib = library.Library.init(gpa);
        defer lib.deinit();
        _ = try classes(&lib);
        var s = try sch.initDevices(gpa, &nl, roles, &lib);
        defer s.deinit();
        var st = try structure.analyze(gpa, a, &nl, roles);
        var sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
        const mates = try a.alloc(u32, s.devices.len);
        @memset(mates, sch.none);
        st.device_mate = mates;
        const drawn = try a.alloc(bool, s.devices.len);
        @memset(drawn, true);
        sk.drawn = drawn;
        const ats = try a.alloc(?pinned.At, s.devices.len);
        @memset(ats, null);
        const lines = try netlines.read(a, &nl, roles, lib.unit, &.{});
        var batch = try owner.collect(gpa, &nl, &s, &sk, &st, ats, &lines);
        defer batch.deinit(gpa);
        try testing.expectEqual(@as(usize, @intFromBool(i == 0)), batch.groups.items.len);
    }
}
