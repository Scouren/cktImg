//! Paired block outputs -> actual center-tapped tank frame.
//! Oracle: AG1103's own attached OUTP/OUTN leads (460,30)/(460,70),
//! C1 ends (480,30)/(480,70), XL1 N1/N2 (520,0)/(520,100), tap (540,50).
//! The three midpoint rows agree and output < cap < coil < tap. Actual
//! SVG ink proves both local paths and all five named remote-loss pairs.
//! See docs/research/block-tanks.md and its independently replayable proof.
//! This full source fixture retains the CLI weak external roles. No block
//! outline or hidden VSS position is inferred by the geometry oracle.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1103 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.subckt PA VDD VSS VB inp inn outp outn src
    \\Cf1 outp net3 1p
    \\Cf2 outn net1 1p
    \\LBWa VDD outp 1n
    \\LBWb VDD outn 1n
    \\LBWc VB net5 1n
    \\LBWg src VSS 1n
    \\MP1A net0 inp src VSS nch l=0.15 w=1 nf=1 m=1
    \\MP1B net2 inn src VSS nch l=0.15 w=1 nf=1 m=1
    \\MP2A outp net4 net0 VSS nch l=0.15 w=1 nf=1 m=1
    \\MP2B outn net4 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\Rc net5 net4 1k
    \\Rf1 net3 inp 1k
    \\Rf2 net1 inn 1k
    \\.ends PA
    \\
    \\.subckt DA VSS VB inp inn outp outn src
    \\Cf1 outp net0 1p
    \\Cf2 outn net4 1p
    \\LBWc VB net1 1n
    \\LBWg src VSS 1n
    \\MD1A net2 inp src VSS nch l=0.15 w=1 nf=1 m=1
    \\MD1B net5 inn src VSS nch l=0.15 w=1 nf=1 m=1
    \\MD2A outp net3 net2 VSS nch l=0.15 w=1 nf=1 m=1
    \\MD2B outn net3 net5 VSS nch l=0.15 w=1 nf=1 m=1
    \\Rc net1 net3 1k
    \\Rf1 net0 inp 1k
    \\Rf2 net4 inn 1k
    \\.ends DA
    \\
    \\C1 net9 net8 1p
    \\Cblk1 net13 net10 1p
    \\Cblk2 net24 net22 1p
    \\Cblk3 net9 net14 1p
    \\Cblk4 net8 net19 1p
    \\Cblk5 net6 net9 1p
    \\Cblk6 net0 net8 1p
    \\Cbyp1 net11 net21 1p
    \\Cbyp2 net7 net18 1p
    \\CIN1 net16 net23 1p
    \\CIN2 net13 net24 1p
    \\Cout1a net20 net25 1p
    \\Cout1b net4 net2 1p
    \\Cout2 net3 net12 1p
    \\Lb1 net16 net5 1n
    \\Lb2 net5 net23 1n
    \\Lb3 net13 VSS 1n
    \\Lb4 VSS net24 1n
    \\LBW1 RFIN net16 1n
    \\LBW2 VSS net23 1n
    \\LBW3 net1 V_bias 1n
    \\LBW4 net21 VDD 1n
    \\LBW5 V_bias net15 1n
    \\LBW6 net17 V_bias 1n
    \\LBW7 net12 RFOUT 1n
    \\LBW8 net3 VSS 1n
    \\Lp1a net20 net18 1n
    \\Lp1b net18 net25 1n
    \\Lp2 net4 net2 1n
    \\Ls net12 net3 1n
    \\R1 net1 net10 1k
    \\R2 net1 net22 1k
    \\R3 net14 net15 1k
    \\R4 net19 net15 1k
    \\R5 net6 net17 1k
    \\R6 net0 net17 1k
    \\X1 VSS VB_DA net10 net22 net9 net8 net11 DA
    \\X2 VDD VSS VB_PA net14 net19 net20 net25 net7 PA
    \\X3 VDD VSS VB_PA2 net6 net0 net4 net2 NC0001 PA
    \\XL1 net9 net8 net21 ct_inductor l1=1n l2=1n k=0
    \\KTF1 Lb1 Lb3 1
    \\KTF2 Lb2 Lb4 1
    \\KTF3 Lp1a Ls 1
    \\KTF4 Lp1b Ls 1
    \\KTF5 Lp2 Ls 1
    \\*@ weak role rfin output
    \\*@ weak role rfout output
    \\*@ weak role v_bias output
    \\
;

// ---- private ----

fn named(p: *const np.Placed, lib: *const np.Library, device: []const u8, port: []const u8) !usize {
    const d = np.checks.deviceIn(p, device) orelse return error.MissingDevice;
    for (lib.at(p.dev_class[d]).terminals, 0..) |terminal, i| {
        if (std.ascii.eqlIgnoreCase(terminal.name, port)) return p.dev_pin0[d] + i;
    }
    return error.MissingTerminal;
}

fn pins(p: *const np.Placed, lib: *const np.Library) ![7]usize {
    const out: [7]usize = .{
        try named(p, lib, "x1", "outp"), try named(p, lib, "x1", "outn"),
        try named(p, lib, "xl1", "n1"), try named(p, lib, "xl1", "n2"),
        try named(p, lib, "xl1", "n3"),
        p.dev_pin0[np.checks.deviceIn(p, "c1").?],
        p.dev_pin0[np.checks.deviceIn(p, "c1").?] + 1,
    };
    for ([_][3]usize{ .{ 0, 2, 5 }, .{ 1, 3, 6 } }, [_][]const u8{ "net9", "net8" }) |group, net| {
        for (group) |i| try testing.expectEqualStrings(net, p.net_name[p.pin_net[out[i]]]);
    }
    try testing.expectEqualStrings("net21", p.net_name[p.pin_net[out[4]]]);
    return out;
}

// Independent literal source relation. Only integral doubled midpoints are
// compared; neither class origins nor expected placement formulas appear.
fn relative(q: [7]np.Pt) bool {
    const a, const b, const c, const d, const t, const e, const f = q;
    return a.x == b.x and a.y < b.y and c.x == d.x and c.y < d.y and
        e.x == f.x and e.y < f.y and
        @as(i64, a.y) + b.y == @as(i64, c.y) + d.y and
        @as(i64, a.y) + b.y == @as(i64, e.y) + f.y and
        @as(i64, c.y) + d.y == 2 * @as(i64, t.y) and
        a.x < e.x and e.x < c.x and c.x < t.x;
}

fn electrical(p: *const np.Placed, lib: *const np.Library) !void {
    try support.expectConnected(p, lib);
    try testing.expectEqual(@as(u32, 0), try support.shorts(testing.allocator, p, true));
}

fn geometry(p: *const np.Placed, lib: *const np.Library) !void {
    const indices = try pins(p, lib);
    var points: [7]np.Pt = undefined;
    for (indices, &points) |pin, *point| point.* = p.pin_xy[pin];
    if (!relative(points)) std.debug.print("block tank actual tips: {any}\n", .{points});
    try testing.expect(relative(points));
    const block = np.checks.deviceIn(p, "x1").?;
    for (indices[0..2]) |pin| try testing.expectEqual(np.Side.right, lib.at(p.dev_class[block]).side(pin - p.dev_pin0[block], p.dev_orient[block]).?);
}

fn honoured(text: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{text}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    for (try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
}

test "block tanks: literal source geometry rejects skew wrong order and shifted midpoint" {
    const q = [7]np.Pt{
        .{ .x = 460, .y = 30 }, .{ .x = 460, .y = 70 },
        .{ .x = 520, .y = 0 }, .{ .x = 520, .y = 100 },
        .{ .x = 540, .y = 50 },
        .{ .x = 480, .y = 30 }, .{ .x = 480, .y = 70 },
    };
    try testing.expect(relative(q));
    for ([_]usize{ 2, 4, 5 }) |i| {
        var mutation = q;
        mutation[i].y += 1;
        try testing.expect(!relative(mutation));
    }
    var wrong = q;
    std.mem.swap(np.Pt, &wrong[2], &wrong[3]);
    try testing.expect(!relative(wrong));
    wrong = q;
    wrong[4].x = 500;
    try testing.expect(!relative(wrong));
}

test "block tanks: AG1103 actual outputs capacitor winding and tap share the source frame" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        errdefer std.debug.print("AG1103 actual tank frame compact={}\n", .{compact});
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1103}, null);
        defer p.deinit();
        try geometry(&p, lib);
        try electrical(&p, lib);
    }
}

test "block tanks: AG1103 preserves all named source-connected local and remote paths" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{ag1103}, null);
        defer p.deinit();
        try electrical(&p, lib);
        const indices = try pins(&p, lib);
        for ([_][3]usize{ .{ 0, 2, 5 }, .{ 1, 3, 6 } }) |group| {
            const path = [_]usize{ indices[group[0]], indices[group[1]], indices[group[2]] };
            if (!try ink.connected(testing.allocator, &p, &path)) std.debug.print("AG1103 local tank net {s}, compact={}\n", .{ p.net_name[p.pin_net[path[0]]], compact });
            try testing.expect(try ink.connected(testing.allocator, &p, &path));
        }
        // These five physical pairs were preserved in checkpoint20. They
        // remain separate from the new local-frame habit, even if a future
        // local placement succeeds while a remote route still regresses.
        if (compact) for ([_]struct { a: []const u8, ap: usize, b: []const u8, bp: usize }{
            .{ .a = "cblk4", .ap = 1, .b = "x2", .bp = 4 },
            .{ .a = "cblk5", .ap = 0, .b = "r5", .bp = 0 },
            .{ .a = "cblk5", .ap = 0, .b = "x3", .bp = 3 },
            .{ .a = "r5", .ap = 0, .b = "x3", .bp = 3 },
            .{ .a = "c1", .ap = 0, .b = "cblk3", .bp = 0 },
        }) |pair| {
            const path = [_]usize{
                p.dev_pin0[np.checks.deviceIn(&p, pair.a).?] + pair.ap,
                p.dev_pin0[np.checks.deviceIn(&p, pair.b).?] + pair.bp,
            };
            if (!try ink.connected(testing.allocator, &p, &path)) std.debug.print("AG1103 source path {s}.{d}--{s}.{d}\n", .{ pair.a, pair.ap, pair.b, pair.bp });
            try testing.expect(try ink.connected(testing.allocator, &p, &path));
        };
    }
}

test "block tanks: caller coil origin and capacitor form remain authoritative" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    for ([_][]const u8{ "*@ at xl1 -10 -10 r0\n", "*@ bridge c1\n" }, 0..) |request, which| for ([_]bool{ false, true }) |compact| {
        const text = try std.fmt.allocPrint(a, "{s}{s}", .{ ag1103, request });
        defer a.free(text);
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        const indices = try pins(&p, lib);
        if (which == 0) {
            const coil = np.checks.deviceIn(&p, "xl1").?;
            try testing.expectEqualDeep(np.Pt{ .x = -400, .y = -400 }, p.dev_pos[coil]);
            try testing.expectEqualDeep(np.Orient.r0, p.dev_orient[coil]);
        } else try testing.expectEqual(p.pin_xy[indices[5]].y, p.pin_xy[indices[6]].y);
        try honoured(text, &p, lib);
        try electrical(&p, lib);
    };
}
