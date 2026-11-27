//! Whole-network reflection preferences preserve source bank ownership.
//! Oracle: the complete AG1180 source pairs its two banks and private
//! paths across one axis. The literal pairs below include every device;
//! the alternative within-bank involution moves more devices but breaks
//! that source arrangement. Graph validation retains every original pin.
//!
//! Contents: complete source, independent mate checks, then regressions.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

const setup =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.model ideal_switch SW(RON=1 ROFF=1e12 VT=0.5 VH=0)
    \\
;

const cards =
    \\C1 net6 net4 1p
    \\C2 net2 net3 1p
    \\C3 net0 net5 1p
    \\C4 net7 net1 1p
    \\CT1 net4 net5 1p
    \\CT2 net2 net7 1p
    \\M1 net4 net5 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net5 net4 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net2 net7 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M4 net7 net2 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\S1 net6 net3 S1 VSS ideal_switch
    \\S2 net0 net1 S2 VSS ideal_switch
    \\SE1 net4 net2 SE VSS ideal_switch
    \\SE2 net5 net7 SE VSS ideal_switch
    \\SO1 net4 net7 SO VSS ideal_switch
    \\SO2 net2 net5 SO VSS ideal_switch
    \\XLE1 net4 net5 VDD ct_inductor l1=1n l2=1n k=0
    \\XLE2 net2 net7 VDD ct_inductor l1=1n l2=1n k=0
    \\XLO1 net4 net5 VDD ct_inductor l1=1n l2=1n k=0
    \\XLO2 net2 net7 VDD ct_inductor l1=1n l2=1n k=0
    \\
;

const roles =
    \\*@ weak role s1 output
    \\*@ weak role s2 output
    \\*@ weak role se output
    \\*@ weak role so output
    \\
;

const full = setup ++ cards ++ roles;

const pairs = [_][2][]const u8{
    .{ "xle1", "xle2" }, .{ "xlo1", "xlo2" }, .{ "ct1", "ct2" },
    .{ "m1", "m3" },     .{ "m2", "m4" },     .{ "c1", "c2" },
    .{ "s1", "s1" },     .{ "c3", "c4" },     .{ "s2", "s2" },
    .{ "se1", "se1" },   .{ "se2", "se2" },   .{ "so1", "so2" },
};

// ---- private ----

fn reversed(a: std.mem.Allocator) ![]u8 {
    const one = try std.mem.replaceOwned(u8, a, full, "XLO1 net4 net5 VDD", "XLO1 net5 net4 VDD");
    defer a.free(one);
    return std.mem.replaceOwned(u8, a, one, "XLO2 net2 net7 VDD", "XLO2 net7 net2 VDD");
}

fn reflection(a: std.mem.Allocator, text: []const u8) !struct { nl: np.netlist.Netlist, st: np.schematic.structure.Structure } {
    var nl = try np.netlist.parse(a, &.{text}, null);
    const roles_in = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles_in);
    return .{ .nl = nl, .st = st };
}

fn paired(nl: *const np.netlist.Netlist, st: *const np.schematic.structure.Structure, names: [2][]const u8) !void {
    const a = nl.device(names[0]).?.index();
    const b = nl.device(names[1]).?.index();
    try testing.expectEqual(b, st.device_mate[a]);
    try testing.expectEqual(a, st.device_mate[b]);
}

fn sameMates(a: std.mem.Allocator, text: []const u8) !void {
    const plain = try reflection(a, text);
    const disabled = try reflection(a, try std.mem.concat(a, u8, &.{ text, "\n*@ grouping off\n" }));
    try testing.expectEqualDeep(disabled.st.device_mate, plain.st.device_mate);
    try testing.expectEqualDeep(disabled.st.net_mate, plain.st.net_mate);
}

fn allocationFailure(gpa: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try reversed(a);
    var nl = try np.netlist.parse(a, &.{text}, null);
    const rs = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(gpa, a, &nl, rs);
    for (pairs) |pair| try paired(&nl, &st, pair);
}

// ---- tests ----

test "coil reflection: complete source context chooses the same whole-network reflection after winding reversal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ full, try reversed(a) }) |text| {
        const got = try reflection(a, text);
        for (pairs) |pair| try paired(&got.nl, &got.st, pair);
    }
}

test "coil reflection: caller symmetry and global off requests outrank the automatic source choice" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try reversed(a);
    for ([_][]const u8{ "*@ symmetric xle1 xlo1\n", "*@ axis ct1\n", "*@ grouping off\n", "*@ symmetry off\n" }, 0..) |request, i| {
        const got = try reflection(a, try std.mem.concat(a, u8, &.{ base, "\n", request }));
        const verdict = got.st.verdicts[got.st.verdicts.len - 1].?;
        try testing.expectEqual(np.hints.State.honoured, verdict.state);
        if (i == 3) {
            for (got.st.device_mate) |mate| try testing.expectEqual(np.schematic.structure.none, mate);
        } else {
            try paired(&got.nl, &got.st, .{ "xle1", "xlo1" });
            try paired(&got.nl, &got.st, .{ "ct1", "ct1" });
        }
    }
}

test "coil reflection: incomplete or competing paths retain the ordinary symmetry search" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try reversed(a);
    for ([_][2][]const u8{
        .{ "SE1 net4 net2 SE VSS ideal_switch", "" },
        .{ "C1 net6 net4 1p", "" },
        .{ "CT1 net4 net5 1p", "" },
    }) |change| try sameMates(a, try std.mem.replaceOwned(u8, a, base, change[0], change[1]));
    for ([_][]const u8{
        "SE3 net4 net2 SE VSS ideal_switch\n",
        "C5 net6 net4 1p\n",
        "CT3 net4 net5 1p\n",
        "XLC1 net4 net5 VDD ct_inductor\n",
    }) |extra| try sameMates(a, try std.mem.concat(a, u8, &.{ base, "\n", extra }));
}

test "coil reflection: compatible caller symmetry remains honoured by the complete source preference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try reversed(a);
    for ([_][]const u8{ "*@ symmetric xle1 xle2\n", "*@ axis s1\n", "*@ symmetric so1 so2\n" }) |request| {
        const got = try reflection(a, try std.mem.concat(a, u8, &.{ base, "\n", request }));
        try testing.expectEqual(np.hints.State.honoured, got.st.verdicts[got.st.verdicts.len - 1].?.state);
        for (pairs) |pair| try paired(&got.nl, &got.st, pair);
    }
}

test "coil reflection: a second complete context retains the ordinary search" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A complete independent copy shares only rails and control inputs.
    // Every card is literal, so a missing bridge cannot fake this boundary.
    const second =
        \\C5 peer6 peer4 1p
        \\C6 peer2 peer3 1p
        \\C7 peer0 peer5 1p
        \\C8 peer7 peer1 1p
        \\CT3 peer4 peer5 1p
        \\CT4 peer2 peer7 1p
        \\M5 peer4 peer5 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M6 peer5 peer4 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M7 peer2 peer7 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\M8 peer7 peer2 VSS VSS nch l=0.15 w=1 nf=1 m=1
        \\S3 peer6 peer3 S1 VSS ideal_switch
        \\S4 peer0 peer1 S2 VSS ideal_switch
        \\SE3 peer4 peer2 SE VSS ideal_switch
        \\SE4 peer5 peer7 SE VSS ideal_switch
        \\SO3 peer4 peer7 SO VSS ideal_switch
        \\SO4 peer2 peer5 SO VSS ideal_switch
        \\XLE3 peer4 peer5 VDD ct_inductor l1=1n l2=1n k=0
        \\XLE4 peer2 peer7 VDD ct_inductor l1=1n l2=1n k=0
        \\XLO3 peer5 peer4 VDD ct_inductor l1=1n l2=1n k=0
        \\XLO4 peer7 peer2 VDD ct_inductor l1=1n l2=1n k=0
        \\
    ;
    const text = try std.mem.concat(a, u8, &.{ try reversed(a), "\n", second });
    const parsed = try reflection(a, text);
    try testing.expectEqual(@as(usize, 40), parsed.nl.graph.edgeCount());
    try sameMates(a, text);
}

test "coil reflection: reversed windings retain admitted pose and group requests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try reversed(a);
    for ([_][]const u8{ "*@ at xle1 -12 -8 r0\n", "*@ cell xle1 -12 -8\n", "*@ group cross m1 m2\n" }, 0..) |request, i| {
        const text = try std.mem.concat(a, u8, &.{ base, "\n", request });
        const lib = try support.library(testing.allocator);
        defer support.freeLibrary(testing.allocator, lib);
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = false, .shelf = 0 } }, lib, &.{text}, null);
        defer p.deinit();
        const got = try reflection(a, text);
        const rs = try np.guessRoles(a, &got.nl);
        const sk = try np.schematic.skeleton.place(a, a, &got.nl, rs, &got.st, .{});
        for (try np.report.verdicts(a, &got.nl, rs, &got.st, &sk, &p, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
        if (i == 0) try testing.expectEqualDeep(np.Pt{ .x = -480, .y = -320 }, p.dev_pos[np.checks.deviceIn(&p, "xle1").?]);
        // The automatic graph preference may still change unheld members;
        // this oracle checks the admitted request, not an opaque fallback.
        try support.expectConnected(&p, lib);
        try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, &p, true));
    }
}

test "coil reflection: allocation failure releases trial requests and graph search scratch" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationFailure, .{});
}
