//! Turning, mirroring and sizing blocks: `face <block> <port> <side>`,
//! `symmetric` on two blocks, a recognized glyph under a child's side
//! lines, and a generated box's title clear of its ports' names.
//! Oracles: the finished `Placed` read back (a port's pin against its
//! block's origin, two blocks' pins against one mirror axis), the report's
//! verdict, the class's own strokes (a title text, the side each terminal
//! faces), and `text_overlaps.find`.
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");

/// AG1168 (fable2's reproducer): two centre-tap coils, mirrored by their
/// MOS pairs, each a block with ports `n1 n2 n3`.
const ag1168 =
    \\AG1168 cross-coupled oscillator
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt ct_inductor n1 n2 n3
    \\L1 n1 n3 1n
    \\L2 n3 n2 1n
    \\.ends ct_inductor
    \\C1 VGBP VDAP 1p
    \\C10 0 VGAP 1p
    \\C11 VGBN 0 1p
    \\C12 VGAN 0 1p
    \\C2 VDAP 0 1p
    \\C3 VGAP VDBP 1p
    \\C4 VDBP 0 1p
    \\C5 VDAN VGBN 1p
    \\C6 0 VDAN 1p
    \\C7 VDBN VGAN 1p
    \\C8 0 VDBN 1p
    \\C9 0 VGBP 1p
    \\L1 VGBP VDAP 1n
    \\L2 VGAP VDBP 1n
    \\L3 VDAN VGBN 1n
    \\L4 VDBN VGAN 1n
    \\M1n VDBN VGBN 0 0 nch
    \\M1p VDBP VGBP VDD VDD pch
    \\M2n VDAN VGAN 0 0 nch
    \\M2p VDAP VGAP VDD VDD pch
    \\RS net1 net0 1k
    \\X1 VDAN VDAP net0 ct_inductor
    \\X2 VDBN VDBP net1 ct_inductor
    \\VDD VDD 0 1.8
    \\
;

/// AR3201's differential amplifier (fable5): its card asks the
/// non-inverting input above the inverting one on the left, the outputs
/// on the right.
const ar3201 =
    \\AR3201 differential amplifier block
    \\.subckt opamp_differential VDD VSS VIP VIN VOP VON
    \\*@ left vip vin
    \\*@ right von vop
    \\E1 VOP VON VIP VIN 1e6
    \\.ends opamp_differential
    \\X1 vdd 0 inp inn outp outn opamp_differential
    \\R1 inp outn 1k
    \\R2 inn outp 1k
    \\V1 vdd 0 1.8
    \\
;

/// A centre-tap coil whose card stands it upright, tap on the right
/// (fable2, ag-1168.h.r3).
const ct_upright =
    \\Upright centre tap
    \\.subckt ct_inductor n1 n2 n3
    \\*@ top n2
    \\*@ bottom n1
    \\*@ right n3
    \\L1 n1 n3 1n
    \\L2 n3 n2 1n
    \\.ends ct_inductor
    \\X1 a b t ct_inductor
    \\R1 a 0 1k
    \\R2 b 0 1k
    \\R3 t 0 1k
    \\
;

/// AG1289's EA1 (fable3): three ports right, one left, so a port's name
/// shares the title's row on both sides.
const ea1 =
    \\AG1289 error amplifier block
    \\.subckt EA1 VDD VSS VFP1 VREF VX3 VCTRL
    \\*@ right vfp1 vref vx3
    \\*@ left vctrl
    \\E1 VX3 0 VFP1 VREF 1e3
    \\R1 VCTRL VX3 1k
    \\.ends EA1
    \\X1 vdd 0 fb ref out ctl EA1
    \\R1 fb 0 1k
    \\R2 ref 0 1k
    \\R3 out 0 1k
    \\R4 ctl 0 1k
    \\V1 vdd 0 1.8
    \\
;

const Run = struct {
    nl: np.netlist.Netlist,
    p: np.Placed,
    v: []const np.hints.Verdict,

    fn verdict(r: *const Run, text: []const u8) np.hints.Verdict {
        for (r.nl.hints, r.v) |h, v| if (std.mem.eql(u8, h.text, text)) return v;
        unreachable;
    }

    fn device(r: *const Run, name: []const u8) usize {
        return np.checks.deviceIn(&r.p, name).?;
    }

    fn pin(r: *const Run, name: []const u8, k: u32) np.Pt {
        return r.p.pin_xy[r.p.pinRange(r.device(name))[0] + k];
    }
};

// ---- private ----

/// `spice` with `lines` after its title, laid out and reported on; the
/// drawing's guarantees checked.
fn run(arena: std.mem.Allocator, lib: *np.Library, spice: []const u8, lines: []const u8) !Run {
    const cut = std.mem.indexOfScalar(u8, spice, '\n').? + 1;
    const deck = try std.mem.concat(arena, u8, &.{ spice[0..cut], lines, spice[cut..] });
    var nl = try np.netlist.parse(arena, &.{deck}, null);
    const roles = try np.guessRoles(arena, &nl);
    const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
    const sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{});
    const s = try np.layout(arena, &nl, roles, lib, .{});
    const p = try np.Placed.init(arena, &s, &nl);
    try support.expectConnected(&p, lib);
    try std.testing.expectEqual(0, try support.shorts(std.testing.allocator, &p, true));
    const v = try np.report.verdicts(arena, &nl, roles, &st, &sk, &p, lib);
    return .{ .nl = nl, .p = p, .v = v };
}

fn expectState(v: np.hints.Verdict, state: np.hints.State, code: np.hints.Code) !void {
    errdefer std.debug.print("got {t} {t}\n", .{ v.state, v.code });
    try std.testing.expectEqual(state, v.state);
    try std.testing.expectEqual(code, v.code);
}

/// A recognized glyph, not the generated box: the box writes its
/// definition's name as a title, a glyph does not.
fn expectGlyph(class: np.Class, name: []const u8) !void {
    try std.testing.expect(std.mem.startsWith(u8, class.name, "block:"));
    for (class.draw) |op| if (op == .text) try std.testing.expect(!std.ascii.eqlIgnoreCase(op.text.s, name));
}

test "face: a block's port takes the side its line names" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const r = try run(arena, lib, ag1168, "*@ face x2 n1 right\n*@ face x1 n3 up\n*@ face x1 n9 left\n");
    try expectState(r.verdict("*@ face x2 n1 right"), .honoured, .ok);
    try expectState(r.verdict("*@ face x1 n3 up"), .honoured, .ok);
    try expectState(r.verdict("*@ face x1 n9 left"), .rejected, .unknown_name);
    try std.testing.expect(r.pin("x2", 0).x > r.p.dev_pos[r.device("x2")].x);
    try std.testing.expect(r.pin("x1", 2).y < r.p.dev_pos[r.device("x1")].y);
}

test "symmetric: the mate of a block is drawn as its mirror image" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const r = try run(arena, lib, ag1168, "*@ symmetric x1 x2\n*@ symmetric m2p m1p\n*@ symmetric m2n m1n\n");
    try expectState(r.verdict("*@ symmetric x1 x2"), .honoured, .ok);
    // Each port and its image: one row, one axis.
    const axis = r.pin("x1", 0).x + r.pin("x2", 0).x;
    for (0..3) |k| {
        const a = r.pin("x1", @intCast(k));
        const b = r.pin("x2", @intCast(k));
        try std.testing.expectEqual(a.y, b.y);
        try std.testing.expectEqual(axis, a.x + b.x);
    }
}

test "glyph: a child's side lines turn the amplifier, not box it" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const r = try run(arena, lib, ar3201, "");
    const x1 = r.device("x1");
    try expectGlyph(lib.at(r.p.dev_class[x1]), "opamp_differential");
    // vip above vin on the left, von above vop on the right.
    const o = r.p.dev_pos[x1];
    const vip, const vin, const vop, const von = .{ r.pin("x1", 2), r.pin("x1", 3), r.pin("x1", 4), r.pin("x1", 5) };
    try std.testing.expect(vip.x < o.x and vin.x < o.x and vop.x > o.x and von.x > o.x);
    try std.testing.expect(vip.y < vin.y and von.y < vop.y);
}

test "glyph: a centre tap stands upright as its card's side lines ask" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const r = try run(arena, lib, ct_upright, "");
    const x1 = r.device("x1");
    try expectGlyph(lib.at(r.p.dev_class[x1]), "ct_inductor");
    const o = r.p.dev_pos[x1];
    try std.testing.expect(r.pin("x1", 1).y < o.y and r.pin("x1", 0).y > o.y and r.pin("x1", 2).x > o.x);
}

test "box: a block's title clears its ports' names" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    const r = try run(arena, lib, ea1, "");
    var found: std.ArrayList(np.text_overlaps.Overlap) = .empty;
    try np.text_overlaps.find(arena, &found, &r.p, lib);
    for (found.items) |f| {
        errdefer std.debug.print("{t} {s} over {t} {s}\n", .{ f.of, f.text, f.over, f.other });
        try std.testing.expect(f.of != .symbol);
    }
}

test "text gate: two texts of one symbol on each other are found" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = try support.library(std.testing.allocator);
    defer support.freeLibrary(std.testing.allocator, lib);
    _ = try lib.register(.{ .name = "twotext", .terminals = &.{ .{ .name = "a", .at = .{ .x = -20, .y = 0 } }, .{ .name = "b", .at = .{ .x = 20, .y = 0 } } }, .draw = &.{
        .{ .text = .{ .at = .zero, .s = "title", .size = 7 } },
        .{ .text = .{ .at = .{ .x = 4, .y = 0 }, .s = "port", .size = 5 } },
    } });
    const r = try run(arena, lib, "Two texts\n.subckt twotext a b\nR1 a b 1k\n.ends twotext\nX1 p 0 twotext\nR1 p 0 1k\n", "");
    var found: std.ArrayList(np.text_overlaps.Overlap) = .empty;
    try np.text_overlaps.find(arena, &found, &r.p, lib);
    const hit = for (found.items) |f| {
        if (f.of == .symbol and std.mem.eql(u8, f.text, "title") and std.mem.eql(u8, f.other, "port")) break true;
    } else false;
    try std.testing.expect(hit);
}
