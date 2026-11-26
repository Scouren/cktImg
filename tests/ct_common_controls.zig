//! CT-linked common-base bias stage: one complete source figure, AG1114.
//! Oracle: actual source Q3.B (350,0) and Q4.B (250,0) share straight
//! conductor ink. Four-pin base, shared collector and both emitter/CT
//! trees are independently certified in iteration21-ct-control-stage.json.
//! Metamorphic negatives give recognized and opaque families IDENTICAL
//! caller glyphs, isolating admission from symbol size and lead positions.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const ag1114 =
    \\* official Analog Canvas netlist; PDK X cards rewritten by convert.py
    \\.model pch pmos
    \\.model qnpn npn
    \\
    \\.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
    \\L1 n1 n3 {l1}
    \\L2 n3 n2 {l2}
    \\K12 L1 L2 {k}
    \\.ends ct_inductor
    \\
    \\.model DIODE D(IS=1e-14 N=1)
    \\C1 net10 net9 1p
    \\C2 net10 VSS 1p
    \\Ccp1 net7 net1 1p
    \\Ccp2 net3 net0 1p
    \\Cvar1 Vcont net1 1p
    \\Cvar2 Vcont net0 1p
    \\D1 Vcc net4 DIODE
    \\D2 net10 net11 DIODE
    \\M1 net10 Vbias P Vcc pch l=0.15 w=1 nf=1 m=1
    \\Q1 net1 net3 net6 VSS qnpn m=1
    \\Q2 net0 net7 net6 VSS qnpn m=1
    \\Q3 P net5 net0 VSS qnpn m=1
    \\Q4 P net5 net1 VSS qnpn m=1
    \\Q5 net6 net9 net2 VSS qnpn m=1
    \\Q6 net11 net9 net8 VSS qnpn m=1
    \\Q7 Vcc net10 net9 VSS qnpn m=1
    \\R1 net3 Vref 1k
    \\R2 net7 Vref 1k
    \\R3 net8 VSS 1k
    \\R4 net2 VSS 1k
    \\Rb1 Vcc net5 1k
    \\Rb2 net5 net4 1k
    \\Rbias Vcc P 1k
    \\X1 net0 net1 net4 ct_inductor l1=1n l2=1n k=0
    \\*@ weak role vcont output
;

const Inputs = struct {
    extra: ?[]const u8 = null,
    verbs: []const np.hints.Verb = &.{},
};

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, index: usize) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + index;
}

fn expectBaseWire(p: *const np.Placed) !void {
    const a, const b = .{ pin(p, "q3", 1), pin(p, "q4", 1) };
    try testing.expectEqual(p.pin_net[a], p.pin_net[b]);
    try testing.expect(try ink.connected(testing.allocator, p, &.{ a, b }));
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
    try testing.expectEqual(1 + inputs.verbs.len, nl.hints.len);
    try testing.expectEqual(np.hints.Verb.role, nl.hints[0].verb);
    for (inputs.verbs, nl.hints[1..]) |verb, h| try testing.expectEqual(verb, h.verb);
    if (inputs.extra) |name| try testing.expect(nl.device(name) != null);
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
    if (inputs.extra) |name| {
        try testing.expect(np.checks.deviceIn(&ordinary, name) != null);
        try testing.expect(np.checks.deviceIn(&candidate, name) != null);
    }
    for ([_][]const u8{ "q3", "q4", "x1", "rb1", "rb2" }) |name| {
        const d = np.checks.deviceIn(&candidate, name).?;
        const e = np.checks.deviceIn(&ordinary, name).?;
        try testing.expectEqualDeep(ordinary.dev_pos[e], candidate.dev_pos[d]);
        try testing.expectEqualDeep(ordinary.dev_orient[e], candidate.dev_orient[d]);
        const start, const end = .{ candidate.dev_pin0[d], candidate.dev_pin0[d + 1] };
        try testing.expectEqualSlices(np.Pt, ordinary.pin_xy[ordinary.dev_pin0[e]..ordinary.dev_pin0[e + 1]], candidate.pin_xy[start..end]);
    }
    // The four stable literal source base incidences, not a count or a
    // net-name equality, define the physical-partition comparison.
    const names = [_][]const u8{ "q3", "q4", "rb1", "rb2" };
    const indices = [_]usize{ 1, 1, 1, 0 };
    for (0..4) |i| for (i + 1..4) |j| {
        const before = try ink.connected(a, &ordinary, &.{ pin(&ordinary, names[i], indices[i]), pin(&ordinary, names[j], indices[j]) });
        const after = try ink.connected(a, &candidate, &.{ pin(&candidate, names[i], indices[i]), pin(&candidate, names[j], indices[j]) });
        if (before != after) std.debug.print("CT boundary compact={} {s}:{d}/{s}:{d}, ordinary={} recognized={}\n", .{ compact, names[i], indices[i], names[j], indices[j], before, after });
        try testing.expectEqual(before, after);
    };
    if (custom) |spec| {
        const held = lib.at(class.?);
        try testing.expectEqualDeep(spec.terminals, held.terminals);
        try testing.expectEqualDeep(spec.draw, held.draw);
        try testing.expectEqual(class.?, candidate.dev_class[np.checks.deviceIn(&candidate, "q3").?]);
    }
}

// ---- tests ----

test "CT common controls: complete source stage keeps its two actual base leads connected" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = true, .shelf = 8 } }, lib, &.{ag1114}, null);
    defer p.deinit();
    try expectBaseWire(&p);
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
}

test "CT common controls: declared port order resistor ends and card order preserve source base ink" {
    const a = testing.allocator;
    const decl = try std.mem.replaceOwned(u8, a, ag1114, "ct_inductor n1 n2 n3 params:", "ct_inductor n3 n2 n1 params:");
    defer a.free(decl);
    const reordered = try std.mem.replaceOwned(u8, a, decl, "X1 net0 net1 net4", "X1 net4 net1 net0");
    defer a.free(reordered);
    const reverse = try std.mem.replaceOwned(u8, a, ag1114, "Rb2 net5 net4", "Rb2 net4 net5");
    defer a.free(reverse);
    const moved = try std.mem.replaceOwned(u8, a, ag1114, "Q3 P net5 net0 VSS qnpn m=1\nQ4 P net5 net1 VSS qnpn m=1", "Q4 P net5 net1 VSS qnpn m=1\nQ3 P net5 net0 VSS qnpn m=1");
    defer a.free(moved);
    for ([_][]const u8{ reordered, reverse, moved }) |text| {
        // Different port declarations get separate caller libraries.
        const lib = try support.library(a);
        defer support.freeLibrary(a, lib);
        var p = try np.place(a, &.{ .layout = .{ .compact = true, .shelf = 8 } }, lib, &.{text}, null);
        defer p.deinit();
        try expectBaseWire(&p);
        try support.expectConnected(&p, lib);
    }
}

test "CT common controls: extra incidence raw ambiguity and incomplete bias stages remain ordinary" {
    const a = testing.allocator;
    const changes = [_][2][]const u8{
        .{ "Q3 P net5 net0", "Q3 net5 net5 net0" },
        .{ "Q3 P net5 net0", "Q3 P net5 net4" },
        .{ "Q7 Vcc net10 net9 VSS", "Q7 Vcc net10 net9 net5" },
        .{ "Rb2 net5 net4", "Rb2 net5 other" },
        .{ "Rb1 Vcc net5", "Rb1 other net5" },
        .{ "Q4 P net5 net1 VSS qnpn", "Q4 P net5 net1 VSS qother" },
        .{ "Q4 P net5 net1 VSS qnpn", "Q4 P net5 net1 VSS pnp" },
    };
    for (changes) |change| {
        errdefer std.debug.print("CT boundary mutation: {s} -> {s}\n", .{ change[0], change[1] });
        const text = try std.mem.replaceOwned(u8, a, ag1114, change[0], change[1]);
        defer a.free(text);
        for ([_]bool{ false, true }) |compact| try compare(text, compact, null, .{});
    }
    const extras = [_][]const u8{
        "Rextra net5 remote 1k\n",
        "Qextra P net5 net0 VSS qnpn\n",
        "Qextra P net5 net0 VSS qother\n",
        "Xextra net0 net1 net4 ct_inductor\n",
        "Xextra net0 net1 net0 ct_inductor\n",
    };
    for (extras) |extra| {
        errdefer std.debug.print("CT boundary appended card: {s}", .{extra});
        const text = try std.fmt.allocPrint(a, "{s}\n{s}", .{ ag1114, extra });
        defer a.free(text);
        const name = switch (extra[0]) { 'R' => "rextra", 'Q' => "qextra", 'X' => "xextra", else => unreachable };
        for ([_]bool{ false, true }) |compact| try compare(text, compact, null, .{ .extra = name });
    }
}

test "CT common controls: caller net styles and nonopposing placed frames retain ordinary behavior" {
    const a = testing.allocator;
    const requests = [_]struct { text: []const u8, verbs: []const np.hints.Verb }{
        .{ .text = "*@ label net5\n", .verbs = &.{.label} },
        .{ .text = "*@ wire net5 trunk\n", .verbs = &.{.wire} },
        .{ .text = "*@ first net5\n", .verbs = &.{.first} },
        .{ .text = "*@ route net5 -12,-12 -10,-12\n", .verbs = &.{.route} },
        .{ .text = "*@ via net5 -12,-12\n", .verbs = &.{.via} },
        .{ .text = "*@ at q3 -10 -10 r0\n", .verbs = &.{.at} },
        .{ .text = "*@ cell q3 -8 -6\n", .verbs = &.{.cell} },
        .{ .text = "*@ face q3 b right\n*@ face q4 b right\n", .verbs = &.{ .face, .face } },
    };
    for (requests) |request| {
        errdefer std.debug.print("CT boundary caller request: {s}", .{request.text});
        const text = try std.fmt.allocPrint(a, "{s}\n{s}", .{ ag1114, request.text });
        defer a.free(text);
        for ([_]bool{ false, true }) |compact| try compare(text, compact, null, .{ .verbs = request.verbs });
    }
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    var p = try np.place(a, &.default, lib, &.{ag1114 ++ "\n*@ label net5\n"}, null);
    defer p.deinit();
    try testing.expect(!try ink.connected(a, &p, &.{ pin(&p, "q3", 1), pin(&p, "q4", 1) }));
}

test "CT common controls: hidden and skewed caller terminals cannot supply an actual-frame certificate" {
    const a = testing.allocator;
    const lib = try support.library(a);
    defer support.freeLibrary(a, lib);
    const original = lib.at(lib.find("npn").?);
    const terms = try a.dupe(np.library.Terminal, original.terminals);
    defer a.free(terms);
    const text = ag1114 ++ "\n*@ class q3 special_npn\n";
    for (0..2) |which| {
        errdefer std.debug.print("CT boundary custom frame variant: {d}\n", .{which});
        @memcpy(terms, original.terminals);
        if (which == 0) terms[1].hidden = true else terms[0].at.y += 7;
        const spec: np.library.Spec = .{ .name = "special_npn", .terminals = terms, .draw = original.draw };
        for ([_]bool{ false, true }) |compact| try compare(text, compact, spec, .{ .verbs = &.{.class} });
    }
}
