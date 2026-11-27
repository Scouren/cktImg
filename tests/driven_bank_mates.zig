//! Future driver-facing priority over inferred column mates.
//! Oracles: the three actual-source exceptions in driven-banks.md, exact
//! structural symmetry metadata, actual MOS terminal frames and electrical
//! identity. Unimported: no production mate-priority change is active.
//!
//! Contents: complete source decks, private checks, then future regressions.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

const ag2428 =
    \\ag-2428 guard probe
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt aea vdd vss vref out vb1
    \\.ends aea
    \\m1 net2 veaout vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m10 verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\m2 net1 net1 net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net1 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\m4 net0 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m5 net3 veaout net0 vdd pch l=0.15 w=1 nf=1 m=1
    \\m6 net3 net3 vss vss nch l=0.15 w=1 nf=1 m=1
    \\m7 verr net3 vss vss nch l=0.15 w=1 nf=1 m=1
    \\m8 vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m9 verr net1 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref veaout vb1 aea
    \\*@ weak role pb input
    \\*@ weak role nb input
    \\*@ weak role verr output
    \\
;

const ag2435 =
    \\ag-2435 guard probe
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt aea vdd vss vref out
    \\.ends aea
    \\m1 net1 veaout vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m10 verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\m2 vc vc net1 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 vc nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\m4 net2 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m5 net0 veaout net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\m6 net0 net0 vss vss nch l=0.15 w=1 nf=1 m=1
    \\m7 verr net0 vss vss nch l=0.15 w=1 nf=1 m=1
    \\m8 vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m9 verr vc vout vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref veaout aea
    \\*@ weak role pb input
    \\*@ weak role verr output
    \\
;

const ag2443 =
    \\ag-2443 guard probe
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt bias vdd vss vb1 vb2 nb
    \\.ends bias
    \\.subckt aea vdd vss vref nb out
    \\.ends aea
    \\m1 net2 vea vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m10 verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\m2 net1 net1 net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net1 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\m4 net3 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m5 net4 vea net3 vdd pch l=0.15 w=1 nf=1 m=1
    \\m6 net4 net4 vss vss nch l=0.15 w=1 nf=1 m=1
    \\m7 verr net4 vss vss nch l=0.15 w=1 nf=1 m=1
    \\m8 vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m9 verr net1 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref net0 vea aea
    \\x2 vdd vss vb1 vb2 net0 bias
    \\*@ weak role pb input
    \\*@ weak role nb input
    \\*@ weak role verr output
    \\
;

// ---- private ----

fn gateLeft(p: *const np.Placed, name: []const u8) bool {
    const d = np.checks.deviceIn(p, name).?;
    const first = p.dev_pin0[d];
    const drain, const gate, const source = .{ p.pin_xy[first], p.pin_xy[first + 1], p.pin_xy[first + 2] };
    std.debug.assert(drain.x == source.x);
    return gate.x < drain.x;
}

fn expectSource(src: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const m1 = nl.device("m1").?.index();
    const m5 = nl.device("m5").?.index();
    try testing.expectEqual(np.schematic.structure.none, st.device_mate[m1]);
    try testing.expectEqual(np.schematic.structure.none, st.device_mate[m5]);
    var bank = false;
    var mirror = false;
    for (st.block_kind, 0..) |kind, b| {
        const members = st.members(b);
        if (kind == .bank and members.len == 2) {
            bank = bank or (std.mem.indexOfScalar(u32, members, @intCast(m1)) != null and std.mem.indexOfScalar(u32, members, @intCast(m5)) != null);
        }
        mirror = mirror or kind == .mirror;
    }
    try testing.expect(bank and mirror);
    // The separately recorded private trace identifies inferred placement
    // mates: 2428/2443 M1→M8, 2435 M5→M9. They are not exact structural
    // symmetry. Their future priority is tested through the visible result,
    // without adding a public API or requiring a particular mate algorithm.
    for ([_]bool{ false, true }) |compact| {
        const lib = try support.library(testing.allocator);
        defer support.freeLibrary(testing.allocator, lib);
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        try testing.expect(gateLeft(&p, "m1"));
        try testing.expect(gateLeft(&p, "m5"));
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    }
}

test "driven bank mates: AG2428 source facing takes priority over an inferred column mate" {
    try expectSource(ag2428);
}

test "driven bank mates: AG2435 source facing takes priority over an inferred column mate" {
    // Source M5.G remains label-separated from X1.OUT. Facing is the
    // requested relation; this test does not invent a continuous wire.
    try expectSource(ag2435);
}

test "driven bank mates: AG2443 source facing takes priority over an inferred column mate" {
    try expectSource(ag2443);
}

test "driven bank mates: exact circuit symmetry retains the ordinary inward pair" {
    const src = "Exact symmetric bank\n.model pch pmos\n.subckt opamp vdd vss inp inn out\n.ends\n" ++
        "M1 a control vdd vdd pch\nM2 b control vdd vdd pch\nRA a 0 1k\nRB b 0 1k\nX1 vdd 0 ref 0 control opamp\n";
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    try testing.expectEqual(nl.device("m2").?.index(), st.device_mate[nl.device("m1").?.index()]);
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    var p = try np.place(testing.allocator, &.default, lib, &.{src}, null);
    defer p.deinit();
    const m1 = np.checks.deviceIn(&p, "m1").?;
    const m2 = np.checks.deviceIn(&p, "m2").?;
    const left: []const u8 = if (p.dev_pos[m1].x < p.dev_pos[m2].x) "m1" else "m2";
    const right: []const u8 = if (std.mem.eql(u8, left, "m1")) "m2" else "m1";
    try testing.expect(!gateLeft(&p, left));
    try testing.expect(gateLeft(&p, right));
    try support.expectConnected(&p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
}
