//! Actual-frame clamp-placement and allocation boundaries.
//! Oracle: a literal empty drain rectangle, independently named terminals,
//! exact unchanged rows on failure, and injected allocator failures.

const std = @import("std");
const testing = std.testing;
const owner = @import("clamp_anchors.zig");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const Lengths = @import("canvas.zig").Lengths;

const deck = ".model nn nmos\n.model pp pmos\n" ++
    "M0 a a b 0 nn\nM1 b b a 0 nn\nM2 a ga high 0 pp\nM3 b gb high 0 pp\n" ++
    "M4 a gc low 0 nn\nM5 b gd low 0 nn\nR1 outside farther 1k\n";

// ---- private ----

fn classes(lib: *library.Library, skew: bool) !void {
    // A shifted caller frame: raw origin differs from actual channel row
    // and center. Explicit sides keep those physical roles unambiguous.
    const terminals = [_]library.Terminal{
        .{ .name = "d", .at = .{ .x = 30, .y = 7 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 10, .y = -13 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -10, .y = if (skew) 12 else 7 }, .side = .left },
    };
    for ([_][]const u8{ "nmos", "pmos" }) |name| _ = try lib.register(.{
        .name = name,
        .terminals = &terminals,
        .draw = &.{.{ .line = .{ .a = .{ .x = -10, .y = 7 }, .b = .{ .x = 30, .y = 7 } } }},
    });
}

fn points(s: *const sch.Schematic, group: owner.Group, at: []const [2]f32) !void {
    // Literal anchors' inward D tips are x=0/200, y=20/120. Neither the
    // proposal arithmetic nor a projected side/reach computes this oracle.
    for (group[0..2], 0..) |e, i| {
        const info = s.devices.get(e.index());
        const c = s.lib.at(info.class);
        var ends: [2]library.Pt = undefined;
        for ([_]usize{ 0, 2 }, &ends) |pin, *p| {
            p.* = library.Pt.round(at[e.index()]).add(info.orient.apply(c.terminals[pin].at).sub(info.grid));
            try testing.expect(0 < p.x and p.x < 200);
            try testing.expect(20 < p.y and p.y < 120);
        }
        const gate = library.Pt.round(at[e.index()]).add(info.orient.apply(c.terminals[1].at).sub(info.grid));
        try testing.expectEqual(i == 0, gate.y < ends[0].y);
    }
}

fn allocation(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) !void {
    var batch = try owner.collect(gpa, nl, s, sk, st, ats, lines);
    defer batch.deinit(gpa);
    try testing.expectEqual(@as(usize, 1), batch.groups.items.len);
}

// ---- tests ----

test "clamp anchors: actual shifted frames fit, collisions and skew restore the whole pair" {
    const gpa = testing.allocator;
    for ([_]bool{ false, true }) |skew| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        var lib = library.Library.init(gpa);
        defer lib.deinit();
        try classes(&lib, skew);
        var nl = try netlist.parse(a, &.{deck}, null);
        const roles = try sch.guessRoles(a, &nl);
        var s = try sch.initDevices(gpa, &nl, roles, &lib);
        defer s.deinit();
        @memset(s.devices.items(.kept), true);
        @memset(s.devices.items(.driver), false);
        const st = try structure.analyze(gpa, a, &nl, roles);
        const sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
        var group: owner.Group = undefined;
        for (&group, [_][]const u8{ "m0", "m1", "m2", "m3", "m4", "m5" }, 0..) |*e, name, i| {
            e.* = nl.device(name).?;
            const d = e.index();
            s.devices.items(.orientation)[d] = if (i < 2) .horizontal else .vertical;
            s.devices.items(.flip_x)[d] = i == 0;
            s.devices.items(.flip_y)[d] = i == 1 or i == 2 or i == 3;
            sch.settleDevice(&s, &nl.graph, d);
        }
        const resistor = nl.device("r1").?.index();
        s.devices.items(.orientation)[resistor] = .horizontal;
        s.devices.items(.flip_x)[resistor] = false;
        s.devices.items(.flip_y)[resistor] = false;
        sch.settleDevice(&s, &nl.graph, resistor);
        const at = try a.alloc([2]f32, nl.graph.edgeCount());
        const ats = try a.alloc(?pinned.At, at.len);
        @memset(ats, null);
        for (group, [_][2]f32{ .{ 500, 300 }, .{ 500, 400 }, .{ 0, 0 }, .{ 200, 0 }, .{ 0, 140 }, .{ 200, 140 } }) |e, p| at[e.index()] = p;
        at[resistor] = .{ 500, 600 };
        const before = try a.dupe([2]f32, at);
        const infos = try a.alloc(sch.DeviceInfo, s.devices.len);
        for (infos, 0..) |*info, i| info.* = s.devices.get(i);
        var groups: std.ArrayList(owner.Group) = .empty;
        defer groups.deinit(gpa);
        try groups.append(gpa, group);
        owner.place(&s, &sk, ats, Lengths.of(.{}, 40), at, &groups);
        try testing.expectEqual(@as(usize, @intFromBool(!skew)), groups.items.len);
        if (skew) {
            try testing.expectEqualDeep(before, at);
        } else {
            try points(&s, group, at);
            for (group[2..]) |e| try testing.expectEqualDeep(before[e.index()], at[e.index()]);
            @memcpy(at, before);
            at[resistor] = .{ 100, 60 };
            const blocked = try a.dupe([2]f32, at);
            owner.place(&s, &sk, ats, Lengths.of(.{}, 40), at, &groups);
            try testing.expectEqual(@as(usize, 0), groups.items.len);
            try testing.expectEqualDeep(blocked, at);
        }
        for (infos, 0..) |info, i| try testing.expectEqualDeep(info, s.devices.get(i));
    }
}

test "clamp anchors: collection allocation failures publish no geometry" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = library.Library.init(gpa);
    defer lib.deinit();
    try classes(&lib, false);
    var nl = try netlist.parse(a, &.{deck}, null);
    const roles = try sch.guessRoles(a, &nl);
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    var st = try structure.analyze(gpa, a, &nl, roles);
    const sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
    // The fixture intentionally supplies an unowned context. Symmetry and
    // caller precedence have separate tests; this oracle exhausts allocations.
    const mates = try a.alloc(u32, nl.graph.edgeCount());
    @memset(mates, sch.none);
    st.device_mate = mates;
    st.block_kind = &.{};
    st.block_start = &.{0};
    st.block_devices = &.{};
    const ats = try a.alloc(?pinned.At, nl.graph.edgeCount());
    @memset(ats, null);
    const verdicts = try a.alloc(?@import("hints.zig").Verdict, nl.hints.len);
    @memset(verdicts, null);
    const lines = try netlines.read(a, &nl, roles, 40, verdicts);
    try testing.checkAllAllocationFailures(gpa, allocation, .{ &nl, &s, &sk, &st, ats, &lines });
}

test "clamp anchors: inferred diode mirror followers do not own caller placement" {
    // Oracle: the literal M0/M6 gate equality creates an inferred mirror,
    // but only the explicit grouping line gives the caller that placement.
    // Retain the real block table; the allocation fixture removes it.
    const gpa = testing.allocator;
    for ([_][]const u8{ "", "*@ group mirror m0 m6\n" }) |hint| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.mem.concat(a, u8, &.{ deck, "M6 elsewhere a farther 0 nn\n", hint });
        var lib = library.Library.init(gpa);
        defer lib.deinit();
        try classes(&lib, false);
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        var s = try sch.initDevices(gpa, &nl, roles, &lib);
        defer s.deinit();
        var st = try structure.analyze(gpa, a, &nl, roles);
        const m0 = nl.device("m0").?.index();
        const m6 = nl.device("m6").?.index();
        var mirror: ?usize = null;
        for (st.block_kind, 0..) |kind, b| {
            const members = st.members(b);
            if (kind == .mirror and std.mem.indexOfScalar(u32, members, m0) != null and
                std.mem.indexOfScalar(u32, members, m6) != null) mirror = b;
        }
        try testing.expect(mirror != null);
        // This test isolates block ownership, independently of exact symmetry.
        const mates = try a.alloc(u32, nl.graph.edgeCount());
        @memset(mates, sch.none);
        st.device_mate = mates;
        const sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
        const ats = try a.alloc(?pinned.At, nl.graph.edgeCount());
        @memset(ats, null);
        const verdicts = try a.alloc(?@import("hints.zig").Verdict, nl.hints.len);
        @memset(verdicts, null);
        const lines = try netlines.read(a, &nl, roles, 40, verdicts);
        var batch = try owner.collect(gpa, &nl, &s, &sk, &st, ats, &lines);
        defer batch.deinit(gpa);
        try testing.expectEqual(@as(usize, @intFromBool(hint.len == 0)), batch.groups.items.len);
        if (hint.len != 0) try testing.expectEqual(@import("hints.zig").State.honoured, st.verdicts[0].?.state);
        const kinds = try a.dupe(structure.BlockKind, st.block_kind);
        kinds[mirror.?] = .stack;
        st.block_kind = kinds;
        var held = try owner.collect(gpa, &nl, &s, &sk, &st, ats, &lines);
        defer held.deinit(gpa);
        try testing.expectEqual(@as(usize, 0), held.groups.items.len);
    }
}

test "clamp anchors: inferred reciprocal mates close locally but caller symmetry owns placement" {
    // Oracle: the literal circuit automorphism exchanges M0/M1 and their
    // two complementary anchor columns. The pair has no outside mate.
    // An explicitly admitted symmetry is a caller constraint, however.
    const gpa = testing.allocator;
    for ([_][]const u8{ "", "*@ symmetric m0 m1\n" }) |hint| {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.mem.concat(a, u8, &.{ deck, hint });
        var lib = library.Library.init(gpa);
        defer lib.deinit();
        try classes(&lib, false);
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        var s = try sch.initDevices(gpa, &nl, roles, &lib);
        defer s.deinit();
        var st = try structure.analyze(gpa, a, &nl, roles);
        const m0, const m1 = .{ nl.device("m0").?.index(), nl.device("m1").?.index() };
        try testing.expectEqual(m1, st.device_mate[m0]);
        try testing.expectEqual(m0, st.device_mate[m1]);
        if (hint.len != 0) try testing.expectEqual(@import("hints.zig").State.honoured, st.verdicts[0].?.state);
        const sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
        const ats = try a.alloc(?pinned.At, nl.graph.edgeCount());
        @memset(ats, null);
        const verdicts = try a.alloc(?@import("hints.zig").Verdict, nl.hints.len);
        @memset(verdicts, null);
        const lines = try netlines.read(a, &nl, roles, 40, verdicts);
        var batch = try owner.collect(gpa, &nl, &s, &sk, &st, ats, &lines);
        defer batch.deinit(gpa);
        try testing.expectEqual(@as(usize, @intFromBool(hint.len == 0)), batch.groups.items.len);
        if (hint.len != 0) continue;
        const mates = try a.dupe(u32, st.device_mate);
        st.device_mate = mates;
        const m2, const m3 = .{ nl.device("m2").?.index(), nl.device("m3").?.index() };
        for ([_][2]u32{ .{ m2, m3 }, .{ m0, m1 }, .{ m1, sch.none } }) |outside| {
            @memset(mates, sch.none);
            mates[m0] = outside[0];
            mates[m1] = outside[1];
            if (outside[0] == m2) {
                mates[m2] = m0;
                mates[m3] = m1;
            }
            var held = try owner.collect(gpa, &nl, &s, &sk, &st, ats, &lines);
            defer held.deinit(gpa);
            try testing.expectEqual(@as(usize, 0), held.groups.items.len);
        }
    }
}
