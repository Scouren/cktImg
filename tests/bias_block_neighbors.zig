//! Private amplifier bias blocks -> actual relative body/lead placement.
//! Oracle: seven actual source pairs and AG2440's extra-control negative in
//! docs/research/bias-block-neighbors.md. Source-up/down and other peer port
//! sides are deliberately outside this smallest relative contract.
//! Checkpoint20 tests: the source/caller cases went red before implementation.
//!
//! Contents: literal source decks, geometry certificates, then regressions.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");

const Case = struct { deck: []const u8, name: []const u8, amp: []const u8 = "x1", peer: []const u8 = "x2", amp_pin: u3 = 3, peer_pin: u3 };
const Frame = struct { terminal: np.Pt, attachment: np.Pt, body: [4]np.Pt, vertices: u3 };

// Full outer DUT cards and exact opaque declarations. Hidden subcircuit
// bodies are omitted: the proposed rule reads their external contracts.
// The CLI's weak VERR role is retained; all other public roles are named.

const ag2421 =
    \\ag-2421 private bias peer
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt bias vdd vss vb1 vbn
    \\.ends bias
    \\.subckt aea vdd vss vref vbn out
    \\.ends aea
    \\m1 net4 net5 vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net1 net1 net4 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net1 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net2 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net1 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net3 net3 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net3 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net3 net5 net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref net0 net5 aea
    \\x2 vdd vss vb1 net0 bias
    \\*@ weak role verr output
    \\
;

const ag2422 =
    \\ag-2422 private bias peer
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt error_amp vdd vss vref vbn out
    \\.ends error_amp
    \\.subckt bias vdd vss vbn vb1
    \\.ends bias
    \\m1 net0 vea vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net4 net4 net0 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net4 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net2 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net4 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net1 net1 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net1 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net1 vea net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref net3 vea error_amp
    \\x2 vdd vss net3 vb1 bias
    \\*@ weak role verr output
    \\
;

const ag2436 =
    \\ag-2436 private bias peer
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt bias vdd vss vb1 nb
    \\.ends bias
    \\.subckt error_amp vdd vss vref nb out
    \\.ends error_amp
    \\m1 net3 net4 vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net1 net1 net3 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net1 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net2 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net1 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net5 net5 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net5 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net5 net4 net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref net0 net4 error_amp
    \\x2 vdd vss vb1 net0 bias
    \\*@ weak role verr output
    \\
;

const ag2441 =
    \\ag-2441 private bias peer
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt aea vdd vss vref out vbn
    \\.ends aea
    \\.subckt bias vdd vss vb2 vb1 vbn
    \\.ends bias
    \\m1 net5 net2 vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net1 net1 net5 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net1 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net4 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net1 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net3 net3 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net3 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net3 net2 net4 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref net2 net0 aea
    \\x2 vdd vss vb2 vb1 net0 bias
    \\*@ weak role verr output
    \\
;

const ag2443 =
    \\ag-2443 private bias peer
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
    \\*@ weak role verr output
    \\
;

const ag2444 =
    \\ag-2444 private bias peer
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt aea vdd vss vref vbn out
    \\.ends aea
    \\.subckt bias_circuit vdd vss vbn
    \\.ends bias_circuit
    \\m1 net1 net2 vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net0 net0 net1 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net0 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net5 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net0 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net4 net4 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net4 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net4 net2 net5 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss net3 bias_circuit
    \\x2 vdd vss vref net3 net2 aea
    \\*@ weak role verr output
    \\
;

const ag2447 =
    \\ag-2447 private bias peer
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt aea vdd vss vref vbn out
    \\.ends aea
    \\.subckt bias vdd vss vb1 vbn vb2
    \\.ends bias
    \\m1 net2 net5 vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net0 net0 net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net0 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net4 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net0 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net1 net1 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net1 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net1 net5 net4 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref net3 net5 aea
    \\x2 vdd vss vb1 net3 vb2 bias
    \\*@ weak role verr output
    \\
;

const ag2440 =
    \\ag-2440 private bias peer
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt bias vdd vss vc vb2 vb1 vbn
    \\.ends bias
    \\.subckt aea vdd vss vref vbn out
    \\.ends aea
    \\m1 net1 net3 vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 vc vc net1 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 vc nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net2 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr vc vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net0 net0 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net0 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net0 net3 net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vc vb2 vb1 vbn bias
    \\x2 vdd vss vref vbn net3 aea
    \\*@ weak role verr output
    \\
;

const cases = [_]Case{
    .{ .deck = ag2421, .name = "ag-2421", .peer_pin = 3 },
    .{ .deck = ag2422, .name = "ag-2422", .peer_pin = 2 },
    .{ .deck = ag2436, .name = "ag-2436", .peer_pin = 3 },
    .{ .deck = ag2441, .name = "ag-2441", .amp_pin = 4, .peer_pin = 4 },
    .{ .deck = ag2443, .name = "ag-2443", .peer_pin = 4 },
    .{ .deck = ag2444, .name = "ag-2444", .amp = "x2", .peer = "x1", .peer_pin = 2 },
    .{ .deck = ag2447, .name = "ag-2447", .peer_pin = 3 },
};

// Shifted valid own bodies, with long leads and distinct supply/bias pins.
// Canonical port sides remain the caller's; whole-class turns are allowed.
const custom_amp: np.Class = .{
    .name = "offset_bias_amplifier",
    .terminals = &.{
        .{ .name = "vdd", .at = .{ .x = 80, .y = -40 }, .side = .up },
        .{ .name = "vss", .at = .{ .x = 70, .y = 100 }, .side = .down },
        .{ .name = "vref", .at = .{ .x = 10, .y = 30 }, .side = .left },
        .{ .name = "nb", .at = .{ .x = 90, .y = 95 }, .side = .down },
        .{ .name = "out", .at = .{ .x = 150, .y = 30 }, .side = .right },
    },
    .draw = &.{
        .{ .polyline = &.{ .{ .x = 40, .y = -10 }, .{ .x = 120, .y = 30 }, .{ .x = 40, .y = 70 }, .{ .x = 40, .y = -10 } } },
        .{ .line = .{ .a = .{ .x = 80, .y = -40 }, .b = .{ .x = 80, .y = 10 } } },
        .{ .line = .{ .a = .{ .x = 70, .y = 100 }, .b = .{ .x = 70, .y = 55 } } },
        .{ .line = .{ .a = .{ .x = 10, .y = 30 }, .b = .{ .x = 40, .y = 30 } } },
        .{ .line = .{ .a = .{ .x = 90, .y = 95 }, .b = .{ .x = 90, .y = 45 } } },
        .{ .line = .{ .a = .{ .x = 150, .y = 30 }, .b = .{ .x = 120, .y = 30 } } },
    },
};
const custom_peer: np.Class = .{
    .name = "offset_bias_peer",
    .terminals = &.{
        .{ .name = "vdd", .at = .{ .x = 90, .y = -80 }, .side = .up },
        .{ .name = "vss", .at = .{ .x = 100, .y = 100 }, .side = .down },
        .{ .name = "vb1", .at = .{ .x = 60, .y = 100 }, .side = .down },
        .{ .name = "nb", .at = .{ .x = -10, .y = 25 }, .side = .left },
    },
    .draw = &.{
        .{ .polyline = &.{ .{ .x = 30, .y = -40 }, .{ .x = 150, .y = -40 }, .{ .x = 150, .y = 60 }, .{ .x = 30, .y = 60 }, .{ .x = 30, .y = -40 } } },
        .{ .line = .{ .a = .{ .x = 90, .y = -80 }, .b = .{ .x = 90, .y = -40 } } },
        .{ .line = .{ .a = .{ .x = 100, .y = 100 }, .b = .{ .x = 100, .y = 60 } } },
        .{ .line = .{ .a = .{ .x = 60, .y = 100 }, .b = .{ .x = 60, .y = 60 } } },
        .{ .line = .{ .a = .{ .x = -10, .y = 25 }, .b = .{ .x = 30, .y = 25 } } },
    },
};

// ---- private ----

fn terminal(p: *const np.Placed, name: []const u8, index: u3) usize {
    return p.dev_pin0[np.checks.deviceIn(p, name).?] + index;
}

fn frame(c: np.Class, pin: u3) !Frame {
    var body: ?[]const np.Pt = null;
    for (c.draw) |op| if (op == .polyline) {
        const ps = op.polyline;
        if ((ps.len != 4 and ps.len != 5) or !ps[0].eql(ps[ps.len - 1])) continue;
        if (body != null) return error.AmbiguousBody;
        body = ps[0 .. ps.len - 1];
    };
    const outline = body orelse return error.MissingBody;
    const point = c.terminals[pin].at;
    var attachment: ?np.Pt = null;
    for (c.draw) |op| if (op == .line) {
        const a, const b = .{ op.line.a, op.line.b };
        const end = if (a.eql(point)) b else if (b.eql(point)) a else continue;
        if (attachment != null) return error.AmbiguousLead;
        var outward = false;
        for (outline, 0..) |u, i| {
            const v = outline[(i + 1) % outline.len];
            const cross = (@as(i64, v.x) - u.x) * (@as(i64, end.y) - u.y) - (@as(i64, v.y) - u.y) * (@as(i64, end.x) - u.x);
            if (cross != 0 or end.x < @min(u.x, v.x) or end.x > @max(u.x, v.x) or end.y < @min(u.y, v.y) or end.y > @max(u.y, v.y)) continue;
            const interior = outline[(i + 2) % outline.len];
            const inside = (@as(i64, v.x) - u.x) * (@as(i64, interior.y) - u.y) - (@as(i64, v.y) - u.y) * (@as(i64, interior.x) - u.x);
            const outside = (@as(i64, v.x) - u.x) * (@as(i64, point.y) - u.y) - (@as(i64, v.y) - u.y) * (@as(i64, point.x) - u.x);
            outward = outward or (inside > 0 and outside < 0) or (inside < 0 and outside > 0);
        }
        if (!outward or point.eql(end) or (point.x != end.x and point.y != end.y)) return error.InvalidLead;
        attachment = end;
    };
    var result: Frame = .{ .terminal = point, .attachment = attachment orelse return error.MissingLead, .body = @splat(.zero), .vertices = @intCast(outline.len) };
    @memcpy(result.body[0..outline.len], outline);
    return result;
}

fn placedFrame(p: *const np.Placed, lib: *const np.Library, name: []const u8, pin: u3) !Frame {
    const d = np.checks.deviceIn(p, name).?;
    var result = try frame(lib.at(p.dev_class[d]), pin);
    const origin, const orient = .{ p.dev_pos[d], p.dev_orient[d] };
    result.terminal = origin.add(orient.apply(result.terminal));
    result.attachment = origin.add(orient.apply(result.attachment));
    for (result.body[0..result.vertices]) |*point| point.* = origin.add(orient.apply(point.*));
    try testing.expectEqual(result.terminal, p.pin_xy[terminal(p, name, pin)]);
    return result;
}

fn relative(a: Frame, b: Frame) bool {
    const ax = std.math.sign(a.terminal.x - a.attachment.x);
    const ay = std.math.sign(a.terminal.y - a.attachment.y);
    const bx = std.math.sign(b.terminal.x - b.attachment.x);
    const by = std.math.sign(b.terminal.y - b.attachment.y);
    if (@abs(ax) + @abs(ay) != 1 or bx != -ax or by != -ay) return false;
    const dx = @as(i64, b.terminal.x) - a.terminal.x;
    const dy = @as(i64, b.terminal.y) - a.terminal.y;
    if (dx * ay != dy * ax or dx * ax + dy * ay < 0) return false;
    for (b.body[0..b.vertices]) |point| {
        if ((@as(i64, point.x) - a.terminal.x) * ax + (@as(i64, point.y) - a.terminal.y) * ay <= 0) return false;
    }
    return true;
}

fn expectPair(p: *const np.Placed, lib: *const np.Library, case: Case) !void {
    const a = try placedFrame(p, lib, case.amp, case.amp_pin);
    const b = try placedFrame(p, lib, case.peer, case.peer_pin);
    try testing.expect(relative(a, b));
    var body = np.library.Rect.point(b.body[0]);
    for (b.body[1..b.vertices]) |point| body = body.merge(.point(point));
    const peer = np.checks.deviceIn(p, case.peer).?;
    for (p.dev_name, 0..) |name, d| {
        if (d == peer or name.len == 0) continue;
        const other = lib.at(p.dev_class[d]).box(p.dev_orient[d], p.dev_pos[d]);
        try testing.expect(!body.intersects(other));
    }
    try testing.expect(try ink.connected(testing.allocator, p, &.{ terminal(p, case.amp, case.amp_pin), terminal(p, case.peer, case.peer_pin) }));
}

fn expectElectrical(src: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var nl = try np.netlist.parse(testing.allocator, &.{src}, null);
    defer nl.deinit(testing.allocator);
    var untouched = np.Library.init(testing.allocator);
    defer untouched.deinit();
    untouched.unit = lib.unit;
    for (p.dev_name, 0..) |name, d| {
        const edge = nl.device(name) orelse continue;
        const def = nl.defOf(edge) orelse continue;
        const pins = nl.graph.members(edge);
        const c = lib.at(p.dev_class[d]);
        // Fresh canonical generation is an independent no-mutation oracle
        // for cached classes. Caller classes have literal field snapshots.
        if (std.mem.indexOf(u8, src, "*@ class ") == null) {
            try testing.expectEqualDeep(untouched.at(try untouched.blockFor(def)), c);
        }
        try testing.expectEqual(def.ports.len, c.terminals.len);
        try testing.expectEqual(pins.len, p.dev_pin0[d + 1] - p.dev_pin0[d]);
        for (def.ports, pins, c.terminals, 0..) |port, net, t, i| {
            try testing.expectEqualStrings(port, t.name);
            try testing.expect(!t.hidden and !t.ground_ref);
            _ = try frame(c, @intCast(i));
            try testing.expectEqualStrings(nl.graph.vertices.items(.name)[net.index()], p.net_name[p.pin_net[p.dev_pin0[d] + i]]);
            try testing.expectEqual(p.dev_pos[d].add(p.dev_orient[d].apply(t.at)), p.pin_xy[p.dev_pin0[d] + i]);
        }
    }
    try support.expectConnected(p, lib);
    try testing.expectEqual(0, try support.shorts(testing.allocator, p, true));
}

fn expectHonoured(src: []const u8, p: *const np.Placed, lib: *const np.Library) !void {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try np.netlist.parse(a, &.{src}, null);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const verdicts = try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib);
    for (verdicts) |v| try testing.expectEqual(np.hints.State.honoured, v.state);
}

fn expectOrdinary(src: []const u8, peer: []const u8) !void {
    // Renaming an excluded peer's opaque family changes its printed text,
    // not the ordinary class geometry. It disables only the proposed name
    // contract, so its output is an independent abstention comparison.
    const gpa = testing.allocator;
    const renamed = try std.mem.replaceOwned(u8, gpa, src, " bias", " opaque");
    defer gpa.free(renamed);
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_]bool{ false, true }) |compact| {
        var a = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer a.deinit();
        var b = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{renamed}, null);
        defer b.deinit();
        const x = np.checks.deviceIn(&a, peer).?;
        const y = np.checks.deviceIn(&b, peer).?;
        // Frozen18 actual native replay: all nine excluded/hint decks in
        // both compact modes keep this ordinary whole-class orientation.
        // This independent value prevents both variants turning together
        // from hiding a missing topology or caller-precedence guard.
        try testing.expectEqual(np.Orient.r0, a.dev_orient[x]);
        try testing.expectEqual(a.dev_orient[x], b.dev_orient[y]);
        try testing.expectEqual(a.dev_pos[x], b.dev_pos[y]);
        try testing.expectEqualSlices(np.Pt, a.pin_xy[a.dev_pin0[x]..a.dev_pin0[x + 1]], b.pin_xy[b.dev_pin0[y]..b.dev_pin0[y + 1]]);
        try expectElectrical(src, &a, lib);
        try expectElectrical(renamed, &b, lib);
    }
}

fn allocatePair(gpa: std.mem.Allocator, lib: *np.Library) !void {
    const src = "Bias OOM\n.subckt error_amp vdd vss vref nb out\n.ends\n" ++
        ".subckt bias vdd vss vb1 nb\n.ends\nx1 vdd vss vref private out error_amp\nx2 vdd vss vb1 private bias\n";
    var p = try np.place(gpa, &.default, lib, &.{src}, null);
    defer p.deinit();
    try expectPair(&p, lib, .{ .deck = src, .name = "minimal OOM pair", .peer_pin = 3 });
}

test "bias neighbors: seven private source peers have opposing collinear leads and outward bodies" {
    const gpa = testing.allocator;
    for (cases) |case| for ([_]bool{ false, true }) |compact| {
        const lib = try support.library(gpa);
        defer support.freeLibrary(gpa, lib);
        errdefer std.debug.print("bias peer: {s}, compact={}\n", .{ case.name, compact });
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{case.deck}, null);
        defer p.deinit();
        try expectPair(&p, lib, case);
        try expectElectrical(case.deck, &p, lib);
    };
}

test "bias neighbors: valid shifted caller classes use actual terminals and preserve every class field" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const amp = try lib.register(.{ .name = custom_amp.name, .terminals = custom_amp.terminals, .draw = custom_amp.draw });
    const peer = try lib.register(.{ .name = custom_peer.name, .terminals = custom_peer.terminals, .draw = custom_peer.draw });
    const src = ag2436 ++ "*@ class x1 offset_bias_amplifier\n*@ class x2 offset_bias_peer\n";
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        try testing.expectEqual(amp, p.dev_class[np.checks.deviceIn(&p, "x1").?]);
        try testing.expectEqual(peer, p.dev_class[np.checks.deviceIn(&p, "x2").?]);
        try testing.expectEqualDeep(custom_amp, lib.at(amp));
        try testing.expectEqualDeep(custom_peer, lib.at(peer));
        try expectPair(&p, lib, cases[2]);
        try expectElectrical(src, &p, lib);
        try expectHonoured(src, &p, lib);
    }
}

test "bias neighbors: AG2440 extra controls and all-incidence mutations keep ordinary placement" {
    // AG2440's actual source bias pair is separated and its extra VC port
    // reaches local transistor controls. It supplies no seven-case rule.
    // This tests abstention, not an instruction to break electrical ink.
    try expectOrdinary(ag2440, "x1");
    const gpa = testing.allocator;
    const replacements = [_][2][]const u8{
        .{ "m1 net3 net4 vin vdd", "m1 net3 net4 vin net0" },
        .{ "m3 net1 nb vss vss", "m3 net1 net0 vss vss" },
        .{ "m3 net1 nb vss vss", "m3 net1 vb1 vss vss" },
        .{ "x2 vdd vss vb1 net0 bias", "x2 vdd vss net0 net0 bias" },
        .{ "x2 vdd vss vb1 net0 bias", "x2 vcc vss vb1 net0 bias" },
        .{ "x2 vdd vss vb1 net0 bias", "x2 vdd vss private_spare net0 bias" },
        .{ "error_amp", "unknown_amp" },
    };
    for (replacements) |change| {
        const src = try std.mem.replaceOwned(u8, gpa, ag2436, change[0], change[1]);
        defer gpa.free(src);
        try expectOrdinary(src, "x2");
    }
    try expectOrdinary(ag2436 ++ "x3 vdd vss vb2 net0 bias\n", "x2");
}

test "bias neighbors: fixed cells origins turns and an admitted gate face retain precedence" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    const requests = [_][]const u8{
        "*@ cell x1 -4 0\n*@ cell x2 4 0\n",
        "*@ at x1 -30 -30 r0\n",
        "*@ at x2 -30 -30 r90\n",
        "*@ face m1 g right\n",
    };
    for (requests, 0..) |request, i| for ([_]bool{ false, true }) |compact| {
        const src = try std.mem.concat(gpa, u8, &.{ ag2436, request });
        defer gpa.free(src);
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact, .shelf = 0 } }, lib, &.{src}, null);
        defer p.deinit();
        if (i == 0) {
            const a = np.checks.deviceIn(&p, "x1").?;
            const b = np.checks.deviceIn(&p, "x2").?;
            try testing.expect(p.dev_pos[a].x < p.dev_pos[b].x);
            try testing.expect(!relative(try placedFrame(&p, lib, "x1", 3), try placedFrame(&p, lib, "x2", 3)));
        } else if (i < 3) {
            const d = np.checks.deviceIn(&p, if (i == 1) "x1" else "x2").?;
            try testing.expectEqual(np.Pt{ .x = -1200, .y = -1200 }, p.dev_pos[d]);
            try testing.expectEqual(if (i == 1) np.Orient.r0 else (np.Orient{ .rot = 1 }), p.dev_orient[d]);
        } else {
            const d = np.checks.deviceIn(&p, "m1").?;
            try testing.expectEqual(np.Side.right, lib.at(p.dev_class[d]).side(1, p.dev_orient[d]).?);
        }
        try expectHonoured(src, &p, lib);
        try expectElectrical(src, &p, lib);
    };
}

test "bias neighbors: explicit peer definition side is not replaced by inferred facing" {
    const gpa = testing.allocator;
    const src = try std.mem.replaceOwned(u8, gpa, ag2436, ".ends bias", "*@ right nb\n.ends bias");
    defer gpa.free(src);
    try expectOrdinary(src, "x2");
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var p = try np.place(gpa, &.default, lib, &.{src}, null);
    defer p.deinit();
    const d = np.checks.deviceIn(&p, "x2").?;
    try testing.expectEqual(np.Side.right, lib.at(p.dev_class[d]).side(3, .r0).?);
    try expectHonoured(src, &p, lib);
}

test "bias neighbors: declaration order and X-card order do not substitute another bias pin" {
    const gpa = testing.allocator;
    const a = try std.mem.replaceOwned(u8, gpa, ag2436, ".subckt bias vdd vss vb1 nb", ".subckt bias nb vb1 vss vdd");
    defer gpa.free(a);
    const b = try std.mem.replaceOwned(u8, gpa, a, ".subckt error_amp vdd vss vref nb out", ".subckt error_amp out nb vref vss vdd");
    defer gpa.free(b);
    const src = try std.mem.replaceOwned(u8, gpa, b, "x1 vdd vss vref net0 net4 error_amp\nx2 vdd vss vb1 net0 bias", "x2 net0 vb1 vss vdd bias\nx1 net4 net0 vref vss vdd error_amp");
    defer gpa.free(src);
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_]bool{ false, true }) |compact| {
        var p = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer p.deinit();
        try expectPair(&p, lib, .{ .deck = src, .name = "permuted ag-2436", .amp_pin = 1, .peer_pin = 0 });
        try expectElectrical(src, &p, lib);
    }
}

test "bias neighbors: card permutation keeps exact named geometry" {
    const gpa = testing.allocator;
    const src = try std.mem.replaceOwned(u8, gpa, ag2436, "x1 vdd vss vref net0 net4 error_amp\nx2 vdd vss vb1 net0 bias", "x2 vdd vss vb1 net0 bias\nx1 vdd vss vref net0 net4 error_amp");
    defer gpa.free(src);
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_]bool{ false, true }) |compact| {
        var a = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{ag2436}, null);
        defer a.deinit();
        var b = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
        defer b.deinit();
        for (a.dev_name, 0..) |name, i| {
            if (name.len == 0) continue;
            const j = np.checks.deviceIn(&b, name).?;
            try testing.expectEqual(a.dev_pos[i], b.dev_pos[j]);
            try testing.expectEqual(a.dev_orient[i], b.dev_orient[j]);
            try testing.expectEqualSlices(np.Pt, a.pin_xy[a.dev_pin0[i]..a.dev_pin0[i + 1]], b.pin_xy[b.dev_pin0[j]..b.dev_pin0[j + 1]]);
        }
        try expectPair(&a, lib, cases[2]);
        try expectPair(&b, lib, cases[2]);
        try expectElectrical(src, &b, lib);
    }
}

test "bias neighbors: literal relative and own-lead oracles reject shifted columns inward bodies and missing leads" {
    const a: Frame = .{ .terminal = .zero, .attachment = .{ .x = 0, .y = -10 }, .body = .{ .{ .x = -10, .y = -30 }, .{ .x = 10, .y = -30 }, .{ .x = 0, .y = -10 }, .zero }, .vertices = 3 };
    const good: Frame = .{ .terminal = .zero, .attachment = .{ .x = 0, .y = 10 }, .body = .{ .{ .x = -10, .y = 10 }, .{ .x = 10, .y = 10 }, .{ .x = 10, .y = 30 }, .{ .x = -10, .y = 30 } }, .vertices = 4 };
    // Source AG2444: terminal points may coincide; bodies must stay beyond.
    try testing.expect(relative(a, good));
    var bad = good;
    bad.terminal.x = 1;
    bad.attachment.x = 1;
    try testing.expect(!relative(a, bad));
    bad = good;
    bad.attachment.y = -10;
    try testing.expect(!relative(a, bad));
    bad = good;
    bad.body[0].y = 0;
    try testing.expect(!relative(a, bad));
    bad = good;
    bad.terminal.y = -1;
    try testing.expect(!relative(a, bad));
    _ = try frame(custom_amp, 3);
    _ = try frame(custom_peer, 3);
    var broken = custom_peer;
    broken.draw = custom_peer.draw[0..4];
    try testing.expectError(error.MissingLead, frame(broken, 3));
    var terminals: [4]np.library.Terminal = undefined;
    @memcpy(&terminals, custom_peer.terminals);
    terminals[3].at.x += 1;
    broken = custom_peer;
    broken.terminals = &terminals;
    try testing.expectError(error.MissingLead, frame(broken, 3));
    const peer_body: np.library.Rect = .{ .min = .{ .x = -10, .y = 10 }, .max = .{ .x = 10, .y = 30 } };
    try testing.expect(!peer_body.intersects(.{ .min = .{ .x = -10, .y = -30 }, .max = .{ .x = 10, .y = -10 } }));
    try testing.expect(peer_body.intersects(.{ .min = .{ .x = 0, .y = 20 }, .max = .{ .x = 20, .y = 40 } }));
}

test "bias neighbors: a detached or far-edge caller lead keeps ordinary peer placement" {
    const gpa = testing.allocator;
    for ([_]i32{ 10, 150 }) |attachment_x| {
        const lib = try support.library(gpa);
        defer support.freeLibrary(gpa, lib);
        var ops: [custom_peer.draw.len]np.library.DrawOp = undefined;
        @memcpy(&ops, custom_peer.draw);
        // The tip stays at (-10,25). Either stop before the body at x=30,
        // or cross its interior to the far boundary at x=150.
        ops[4].line.b.x = attachment_x;
        const id = try lib.register(.{ .name = "orphan_bias_peer", .terminals = custom_peer.terminals, .draw = &ops });
        try testing.expectError(error.InvalidLead, frame(lib.at(id), 3));
        const src = ag2436 ++ "*@ class x2 orphan_bias_peer\n";
        const renamed = try std.mem.replaceOwned(u8, gpa, src, " bias", " opaque");
        defer gpa.free(renamed);
        for ([_]bool{ false, true }) |compact| {
            const cfg: np.Config = .{ .layout = .{ .compact = compact } };
            var a = try np.place(gpa, &cfg, lib, &.{src}, null);
            defer a.deinit();
            var b = try np.place(gpa, &cfg, lib, &.{renamed}, null);
            defer b.deinit();
            const x = np.checks.deviceIn(&a, "x2").?;
            const y = np.checks.deviceIn(&b, "x2").?;
            try testing.expectEqual(np.Orient.r0, a.dev_orient[x]);
            try testing.expectEqual(a.dev_orient[x], b.dev_orient[y]);
            try testing.expectEqual(a.dev_pos[x], b.dev_pos[y]);
            try testing.expectEqualDeep(@as([]const np.library.DrawOp, &ops), lib.at(id).draw);
        }
    }
}

test "bias neighbors: collected pairs and compaction orders release on allocation failure" {
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    // Warm library registration, which the caller owns independently.
    try allocatePair(testing.allocator, lib);
    // Force reallocations through alloc/free: a backing allocator's
    // opportunistic in-place growth otherwise changes the sweep length.
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocatePair, .{lib});
}

test "bias neighbors: caller body ink beyond the facing tip keeps ordinary placement" {
    const gpa = testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var ops: [custom_peer.draw.len + 1]np.library.DrawOp = undefined;
    @memcpy(ops[0..custom_peer.draw.len], custom_peer.draw);
    // The normal box/lead stay intact; this additional body lies wholly
    // beyond the left-facing NB tip. A whole turn cannot make it outward
    // from the peer's own facing terminal in the observed relative sense.
    ops[custom_peer.draw.len] = .{ .circle = .{ .c = .{ .x = -30, .y = 25 }, .r = 15 } };
    const circle = ops[custom_peer.draw.len].circle;
    try testing.expect(circle.c.x + circle.r < custom_peer.terminals[3].at.x);
    const id = try lib.register(.{ .name = "outside_bias_body", .terminals = custom_peer.terminals, .draw = &ops });
    const src = ag2436 ++ "*@ class x2 outside_bias_body\n";
    const renamed = try std.mem.replaceOwned(u8, gpa, src, " bias", " opaque");
    defer gpa.free(renamed);
    for ([_]bool{ false, true }) |compact| {
        const cfg: np.Config = .{ .layout = .{ .compact = compact } };
        var a = try np.place(gpa, &cfg, lib, &.{src}, null);
        defer a.deinit();
        var b = try np.place(gpa, &cfg, lib, &.{renamed}, null);
        defer b.deinit();
        const x = np.checks.deviceIn(&a, "x2").?;
        const y = np.checks.deviceIn(&b, "x2").?;
        try testing.expectEqual(np.Orient.r0, a.dev_orient[x]);
        try testing.expectEqual(a.dev_orient[x], b.dev_orient[y]);
        try testing.expectEqual(a.dev_pos[x], b.dev_pos[y]);
        try testing.expectEqualDeep(@as([]const np.library.DrawOp, &ops), lib.at(id).draw);
    }
}

test "bias neighbors: an honoured explicit group stack keeps its requested top member" {
    // Frozen19 actual drawing/report: this line is honoured, X2 is r0
    // above X1 in both modes. The inferred bias case must yield to it.
    const sources = [_][]const u8{
        ag2436 ++ "*@ group stack x2 x1\n",
        ag2436 ++ "*@ group stack x2 x1 absent\n",
    };
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    for (sources, 0..) |src, version| {
        try expectOrdinary(src, "x2");
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var nl = try np.netlist.parse(a, &.{src}, null);
        const roles = try np.guessRoles(a, &nl);
        const st = try np.schematic.structure.analyze(a, a, &nl, roles);
        try testing.expectEqual(if (version == 0) np.hints.State.honoured else .relaxed, st.verdicts[nl.hints.len - 1].?.state);
        for ([_]bool{ false, true }) |compact| {
            var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{src}, null);
            defer p.deinit();
            const amp = np.checks.deviceIn(&p, "x1").?;
            const b = np.checks.deviceIn(&p, "x2").?;
            try testing.expect(p.dev_pos[b].y < p.dev_pos[amp].y);
            if (version == 0) try expectHonoured(src, &p, lib);
        }
    }
}
