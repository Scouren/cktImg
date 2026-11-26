//! Complementary-mirror CT stage: one complete source figure, AG1146.
//! Oracle: actual source M3.G=(-70,-130), M4.G=(-30,-130) share straight
//! conductor ink. The seven-member certificate and two actual source gate
//! intervals are replayed by figures/ct_mirror_controls.py.
//! Metamorphic negatives give recognized and opaque families IDENTICAL
//! caller glyphs, isolating admission from symbol size and lead positions.
//!
//! Contents: tests only.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1146 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model nch nmos
    \\.model pch pmos
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.subckt Varactor_Switched_caps Von Vop B_3_ B_2_ B_1_ B_0_ Vcn Vcp
    \\.ends Varactor_Switched_caps
    \\
    \\Iref VDD net3 DC 1m
    \\M1 net3 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M2 net1 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M3 net1 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M4 net2 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1
    \\M5 Von Vop net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M6 Vop Von net2 VDD pch l=0.15 w=1 nf=1 m=1
    \\M7 Von Vop VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\M8 Vop Von VSS VSS nch l=0.15 w=1 nf=1 m=1
    \\X1 Von Vop Vocm ct_inductor l1=1n l2=1n k=0
    \\X2 Von Vop B_3_ B_2_ B_1_ B_0_ Vcn Vcp Varactor_Switched_caps
    \\*@ weak role vocm output
    \\*@ weak role von output
    \\*@ weak role vop output
    \\*@ weak role vcp output
    \\*@ weak role vcn output
    \\*@ weak role b_3_ output
    \\*@ weak role b_2_ output
    \\*@ weak role b_1_ output
    \\*@ weak role b_0_ output
;

const Inputs = struct {
    verbs: []const np.hints.Verb = &.{},
};

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, index: usize) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + index;
}

fn straight(p: *const np.Placed) bool {
    const a, const b = .{ pin(p, "m3", 1), pin(p, "m4", 1) };
    if (p.pin_net[a] != p.pin_net[b] or p.pin_xy[a].y != p.pin_xy[b].y or p.pin_xy[a].x == p.pin_xy[b].x) return false;
    const lo, const hi = .{ @min(p.pin_xy[a].x, p.pin_xy[b].x), @max(p.pin_xy[a].x, p.pin_xy[b].x) };
    for (0..@as(usize, @intCast(hi - lo)) + 1) |dx| {
        const at: np.Pt = .{ .x = lo + @as(i32, @intCast(dx)), .y = p.pin_xy[a].y };
        var wires = p.segments(p.pin_net[a]);
        const found = while (wires.next()) |poly| {
            if (ink.onPolyline(poly, at)) break true;
        } else false;
        if (!found) return false;
    }
    return true;
}

fn segmentLess(_: void, a: [4]i32, b: [4]i32) bool {
    for (a, b) |x, y| if (x != y) return x < y;
    return false;
}

fn segments(p: *const np.Placed) ![][4]i32 {
    var out: std.ArrayList([4]i32) = .empty;
    errdefer out.deinit(testing.allocator);
    var it = p.segments(p.pin_net[pin(p, "m3", 1)]);
    while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
        try out.append(testing.allocator, .{ @min(a.x, b.x), @min(a.y, b.y), @max(a.x, b.x), @max(a.y, b.y) });
    };
    std.sort.heap([4]i32, out.items, {}, segmentLess);
    return out.toOwnedSlice(testing.allocator);
}

fn compare(known: []const u8, compact: bool, custom: ?np.library.Spec, inputs: Inputs) !void {
    const a = testing.allocator;
    const opaque_deck = try std.mem.replaceOwned(u8, a, known, "ct_inductor", "opaque_coil");
    defer a.free(opaque_deck);
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const glyph = try np.block_symbols.draw(arena.allocator(), .center_tap, &.{ "n1", "n2", "n3" }, 20);
    for ([_][]const u8{ "ct_inductor", "opaque_coil" }) |name| _ = try lib.register(.{ .name = name, .terminals = glyph.terminals, .draw = glyph.ops });
    const class = if (custom) |spec| try lib.register(spec) else null;
    // A malformed append used to turn the whole requested line into the
    // preceding weak-role comment. Check independent parsed identities
    // and admission before trusting an opaque-family comparison.
    var nl = try np.netlist.parse(arena.allocator(), &.{known}, null);
    try testing.expectEqual(9 + inputs.verbs.len, nl.hints.len);
    try testing.expectEqual(np.hints.Verb.role, nl.hints[0].verb);
    for (inputs.verbs, nl.hints[9..]) |verb, h| try testing.expectEqual(verb, h.verb);
    if (inputs.verbs.len != 0) {
        const roles = try np.guessRoles(arena.allocator(), &nl);
        const st = try np.schematic.structure.analyze(a, arena.allocator(), &nl, roles);
        const sk = try np.schematic.skeleton.place(a, arena.allocator(), &nl, roles, &st, .{});
        // Admission is checked without finished wire geometry: an explicit
        // route may legitimately fall back when its requested path is blocked.
        for (try np.report.verdicts(arena.allocator(), &nl, roles, &st, &sk, null, lib)) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
    }
    var ordinary = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{opaque_deck}, null);
    defer ordinary.deinit();
    var candidate = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{known}, null);
    defer candidate.deinit();
    for ([_][]const u8{ "m1", "m2", "m3", "m4", "m5", "m6", "x1" }) |name| {
        const d = np.checks.deviceIn(&candidate, name).?;
        const e = np.checks.deviceIn(&ordinary, name).?;
        try testing.expectEqualDeep(ordinary.dev_pos[e], candidate.dev_pos[d]);
        try testing.expectEqualDeep(ordinary.dev_orient[e], candidate.dev_orient[d]);
        const start, const end = .{ candidate.dev_pin0[d], candidate.dev_pin0[d + 1] };
        try testing.expectEqualSlices(np.Pt, ordinary.pin_xy[ordinary.dev_pin0[e]..ordinary.dev_pin0[e + 1]], candidate.pin_xy[start..end]);
    }
    // The tie changes geometry without changing connectivity. Compare
    // every own-net segment, not merely the physical partition or labels.
    const before = try segments(&ordinary);
    defer a.free(before);
    const after = try segments(&candidate);
    defer a.free(after);
    try testing.expectEqualSlices([4]i32, before, after);
    if (custom) |spec| {
        const held = lib.at(class.?);
        try testing.expectEqualDeep(spec.terminals, held.terminals);
        try testing.expectEqualDeep(spec.draw, held.draw);
        try testing.expectEqual(class.?, candidate.dev_class[np.checks.deviceIn(&candidate, "m3").?]);
    }
}

// ---- tests ----

test "CT mirror controls: declared ports card order and net renaming keep source straight ink" {
    const a = testing.allocator;
    const decl = try std.mem.replaceOwned(u8, a, ag1146, "ct_inductor n1 n2 n3 params:", "ct_inductor n3 n2 n1 params:");
    defer a.free(decl);
    const reordered = try std.mem.replaceOwned(u8, a, decl, "X1 Von Vop Vocm", "X1 Vocm Vop Von");
    defer a.free(reordered);
    const renamed = try std.mem.replaceOwned(u8, a, ag1146, "net1", "control_renamed");
    defer a.free(renamed);
    const moved = try std.mem.replaceOwned(u8, a, ag1146, "M3 net1 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1\nM4 net2 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1", "M4 net2 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1\nM3 net1 net1 VDD VDD pch l=0.15 w=1 nf=1 m=1");
    defer a.free(moved);
    for ([_][]const u8{ ag1146, reordered, renamed, moved }) |text| {
        // Declaration variants get fresh caller libraries.
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        for ([_]bool{ false, true }) |compact| {
            var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
            defer p.deinit();
            try testing.expect(straight(&p));
            try support.expectConnected(&p, lib);
            try testing.expectEqual(0, try support.shorts(a, &p, true));
        }
    }
}

test "CT mirror controls: explicit routing choices keep ordinary geometry" {
    const a = testing.allocator;
    const requests = [_]struct { text: []const u8, verbs: []const np.hints.Verb }{
        .{ .text = "*@ label net1\n", .verbs = &.{.label} },
        .{ .text = "*@ wire net1 trunk\n", .verbs = &.{.wire} },
        .{ .text = "*@ wire net1\n", .verbs = &.{.wire} },
        .{ .text = "*@ first net1\n", .verbs = &.{.first} },
        .{ .text = "*@ route net1 -12,-12 -10,-12\n", .verbs = &.{.route} },
        .{ .text = "*@ via net1 -12,-12\n", .verbs = &.{.via} },
        .{ .text = "*@ at m3 -10 -10 r0\n", .verbs = &.{.at} },
        .{ .text = "*@ cell m3 -8 -6\n", .verbs = &.{.cell} },
        .{ .text = "*@ face m3 g right\n*@ face m4 g right\n", .verbs = &.{ .face, .face } },
    };
    for (requests) |request| {
        errdefer std.debug.print("CT mirror request: {s}", .{request.text});
        const text = try std.fmt.allocPrint(a, "{s}\n{s}", .{ ag1146, request.text });
        defer a.free(text);
        for ([_]bool{ false, true }) |compact| try compare(text, compact, null, .{ .verbs = request.verbs });
    }
}

test "CT mirror controls: hidden skewed and displaced actual caller gates cannot nominate" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const original = lib.at(lib.find("pmos").?);
    const terms = try a.dupe(np.library.Terminal, original.terminals);
    defer a.free(terms);
    const text = ag1146 ++ "\n*@ class m3 special_pmos\n";
    for (0..3) |which| {
        errdefer std.debug.print("CT mirror custom frame variant: {d}\n", .{which});
        @memcpy(terms, original.terminals);
        switch (which) {
            0 => terms[1].hidden = true,
            1 => terms[0].at.x += 7,
            2 => terms[1].at.y += 7,
            else => unreachable,
        }
        const spec: np.library.Spec = .{ .name = "special_pmos", .terminals = terms, .draw = original.draw };
        for ([_]bool{ false, true }) |compact| try compare(text, compact, spec, .{ .verbs = &.{.class} });
    }
}

test "CT mirror controls: an unrelated fixed block does not disable the stage" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const text = ag1146 ++ "\n*@ at x2 30 30 r0\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(a, &.{ .layout = .{ .compact = compact, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        const d = np.checks.deviceIn(&p, "x2").?;
        try testing.expectEqual(np.Pt{ .x = 30 * lib.unit, .y = 30 * lib.unit }, p.dev_pos[d]);
        try testing.expect(straight(&p));
    }
}
