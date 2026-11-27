//! One complementary-mirror CT oscillator stage supplies an actual interval.
//!
//! Human Rules:
//! - ct_mirror_controls.1 (bounded observation) AG1146's complete seven
//!   members have two straight actual mirror-gate intervals. Select the
//!   output mirror only: two opposite-polarity two-MOS diode mirrors,
//!   exact bridge/load incidences, two reciprocal load MOS and one CT.
//!   This is one figure; broad mirror or control preferences are unsafe.
//!   Source: docs/research/ct-mirror-controls.md.
//! - ct_mirror_controls.2 (choice) Nominate its complete actual opposing
//!   gate interval only for automatic internal-net routing. Explicit
//!   styles/ports/routes/first, hidden/projected or nonopposing frames
//!   abstain, including routes deferred until after compaction.
//!   This supplies a tie witness, never a cost credit or wire.
//!
//! Data: borrowed immutable netlist/current canvas in; optional two actual
//! points out. The cold stack Stage holds seven typed EdgeIds (28 bytes),
//! all read for visibility once outside candidate loops. No allocation,
//! retained flags, distance option or performance claim. Local CSR scans
//! count all incidences before polarity/frame filters; no source-ID rule.
//!
//! Contents:
//! - `pub fn interval(c: *const Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) ?[2]Pt`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const block_symbols = @import("block_symbols.zig");
const library = @import("library.zig");
const NetLines = @import("netlines.zig").NetLines;
const Requests = @import("wire_requests.zig").Requests;
const Pt = library.Pt;
const Side = library.Side;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Canvas = canvas.Canvas;
const no_edge: EdgeId = .from(sch.none);
const Mirror = struct { reference: EdgeId, output: EdgeId };
const Stage = struct { devices: [7]EdgeId };

comptime {
    assert(@sizeOf(Mirror) == 8);
    assert(@sizeOf(Stage) == 28);
}

/// Selects one actual output-mirror gate interval in ascending x order.
/// No mutation; the caller compares full legal-candidate costs first.
/// requests retains admitted paths and poses even during scaffolding.
pub fn interval(c: *const Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) ?[2]Pt {
    assert(nl.graph.edgeCount() == c.s.device_kind.len);
    assert(net < nl.graph.vertexCount());
    assert(requests.ats.len == nl.graph.edgeCount());
    if (c.s.roles[net] != .internal or lines.style[net] != .auto or lines.port[net] != null) return null;
    if (std.mem.indexOfScalar(u32, lines.first, net) != null) return null;
    for (requests.routes) |route| if (route.net == net) return null;
    const stage = find(nl, c.s.roles, .from(net)) orelse return null;
    for (stage.devices) |d| if (requests.ats[d.index()] != null or !c.s.devices.items(.kept)[d.index()] or c.s.deviceNode(d.index()) == null) return null;
    var selected: [2]u32 = @splat(sch.none);
    for (pins) |p| for (stage.devices[2..4], 0..) |d, i| {
        if (c.s.pins.items(.device)[p] != d.index() or c.s.pins.items(.index)[p] != 1) continue;
        if (selected[i] != sch.none) return null;
        selected[i] = p;
    };
    if (selected[0] == sch.none or selected[1] == sch.none) return null;
    var a = control(c, selected[0]) orelse return null;
    var b = control(c, selected[1]) orelse return null;
    if (a.y != b.y or a.x == b.x) return null;
    const sides = c.s.pins.items(.side);
    if (sides[selected[0]] != (if (a.x < b.x) Side.right else Side.left) or sides[selected[1]] != (if (a.x < b.x) Side.left else Side.right)) return null;
    for (pins) |p| {
        if (p == selected[0] or p == selected[1]) continue;
        const at = canvas.pinAt(c.s, p);
        if (at.y == a.y and at.x > @min(a.x, b.x) and at.x < @max(a.x, b.x)) return null;
    }
    if (!c.fits(net, a, b)) return null;
    if (a.x > b.x) std.mem.swap(Pt, &a, &b);
    return .{ a, b };
}

// ---- private ----

fn mirror(nl: *const Netlist, roles: []const sch.Role, gate: VertexId) ?Mirror {
    const g = &nl.graph;
    var gates: [2]EdgeId = undefined;
    var count: u2 = 0;
    // The same diode MOS occurs twice in CSR; count its gate once while
    // retaining every other raw MOS gate, including unknown model types.
    for (g.incident(gate)) |d| {
        if (g.edges.items(.kind)[d.index()] != .mosfet) continue;
        const pins = g.members(d);
        if (pins.len < 3 or pins[1] != gate) continue;
        if (std.mem.indexOfScalar(EdgeId, gates[0..count], d) != null) continue;
        if (count == 2) return null;
        gates[count] = d;
        count += 1;
    }
    if (count != 2) return null;
    const a, const b = .{ g.members(gates[0]), g.members(gates[1]) };
    if ((a[0] == gate) == (b[0] == gate)) return null;
    const reference, const output = if (a[0] == gate) .{ gates[0], gates[1] } else .{ gates[1], gates[0] };
    const p, const q = .{ g.members(reference), g.members(output) };
    if (p.len != 4 or q.len != 4 or p[2] != p[3] or p[2] != q[2] or p[3] != q[3]) return null;
    const kind = nl.modelType(reference) orelse return null;
    const source_role: sch.Role = if (std.mem.eql(u8, kind, "nmos")) .sink else if (std.mem.eql(u8, kind, "pmos")) .supply else return null;
    if (!std.mem.eql(u8, nl.modelType(output) orelse return null, kind) or roles[p[2].index()] != source_role) return null;
    if (gate == q[0] or gate == p[2] or q[0] == p[2] or roles[gate.index()].isRail() or roles[q[0].index()].isRail()) return null;
    return .{ .reference = reference, .output = output };
}

fn find(nl: *const Netlist, roles: []const sch.Role, gate: VertexId) ?Stage {
    const g = &nl.graph;
    assert(roles.len == g.vertexCount());
    const bridge = g.incident(gate);
    if (bridge.len != 4) return null;
    const out = mirror(nl, roles, gate) orelse return null;
    var previous = no_edge;
    var ref_count: u3 = 0;
    var out_count: u3 = 0;
    for (bridge) |d| {
        if (d == out.reference) {
            ref_count += 1;
            continue;
        }
        if (d == out.output) {
            out_count += 1;
            continue;
        }
        if (previous != no_edge) return null;
        previous = d;
    }
    if (ref_count != 2 or out_count != 1 or previous == no_edge or g.edges.items(.kind)[previous.index()] != .mosfet) return null;
    const before = g.members(previous);
    if (before.len != 4 or before[0] != gate) return null;
    const first = mirror(nl, roles, before[1]) orelse return null;
    if (first.output != previous or std.mem.eql(u8, nl.modelType(first.reference).?, nl.modelType(out.reference).?)) return null;
    const path = g.members(out.output);
    const load_net = path[0];
    const loads = g.incident(load_net);
    if (loads.len != 3) return null;
    var pair: [2]EdgeId = undefined;
    var count: u2 = 0;
    var driving: u2 = 0;
    for (loads) |d| {
        if (d == out.output) {
            driving += 1;
            continue;
        }
        const p = g.members(d);
        if (count == 2 or g.edges.items(.kind)[d.index()] != .mosfet or p.len != 4 or p[2] != load_net) return null;
        pair[count] = d;
        count += 1;
    }
    if (count != 2 or driving != 1 or pair[0] == pair[1]) return null;
    const a, const b = .{ g.members(pair[0]), g.members(pair[1]) };
    if (a[0] != b[1] or b[0] != a[1] or a[0] == b[0] or a[3] != path[2] or b[3] != path[2]) return null;
    for (pair) |d| if (!std.mem.eql(u8, nl.modelType(d) orelse return null, nl.modelType(out.output).?)) return null;
    var coil = no_edge;
    var tap: VertexId = undefined;
    for (g.incident(a[0])) |d| {
        if (g.edges.items(.kind)[d.index()] != .subckt) continue;
        const def = nl.defOf(d) orelse continue;
        if (block_symbols.identify(def.name, def.ports) != .center_tap) continue;
        const ps = g.members(d);
        if (ps.len != 3) return null;
        var named: [3]VertexId = undefined;
        for (def.ports, ps) |name, v| {
            const i: usize = if (std.mem.eql(u8, name, "n1")) 0 else if (std.mem.eql(u8, name, "n2")) 1 else 2;
            named[i] = v;
        }
        if (!((named[0] == a[0] and named[1] == b[0]) or (named[1] == a[0] and named[0] == b[0]))) continue;
        if (coil != no_edge and coil != d) return null;
        coil = d;
        tap = named[2];
    }
    if (coil == no_edge) return null;
    const nets = [_]VertexId{ before[1], gate, load_net, a[0], b[0], tap };
    for (nets, 0..) |v, i| {
        if (roles[v.index()].isRail()) return null;
        for (nets[i + 1 ..]) |other| if (v == other) return null;
    }
    const stage: Stage = .{ .devices = .{ first.reference, first.output, out.reference, out.output, pair[0], pair[1], coil } };
    for (stage.devices, 0..) |d, i| for (stage.devices[i + 1 ..]) |other| {
        if (d == other) return null;
    };
    return stage;
}

fn control(c: *const Canvas, p: u32) ?Pt {
    const s = c.s;
    const d = s.pins.items(.device)[p];
    assert(d != sch.none and s.pins.items(.index)[p] == 1);
    const info = s.devices.get(d);
    const class = s.lib.at(info.class);
    if (class.terminals.len < 3) return null;
    const node = s.deviceNode(d) orelse return null;
    const origin = Pt.round(s.xy[node]).sub(info.grid);
    var tips: [3]Pt = undefined;
    for (class.terminals[0..3], 0..) |terminal, i| {
        if (terminal.hidden or terminal.ground_ref) return null;
        tips[i] = origin.add(info.orient.apply(terminal.at));
    }
    const a, const gate, const b = .{ tips[0], tips[1], tips[2] };
    if (a.x != b.x or gate.x == a.x or gate.y <= @min(a.y, b.y) or gate.y >= @max(a.y, b.y)) return null;
    const side = class.side(1, info.orient) orelse return null;
    if (side != (if (gate.x < a.x) Side.left else Side.right) or s.pins.items(.side)[p] != side or !gate.eql(canvas.pinAt(s, p))) return null;
    return gate;
}

// Tests use literal source cards and independent membership expectations.

fn expectStage(text: []const u8, wanted: bool) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var nl = try netlist.parse(allocator, &.{text}, null);
    const roles = try sch.guessRoles(allocator, &nl);
    const found = find(&nl, roles, nl.net("net1").?);
    try std.testing.expectEqual(wanted, found != null);
    if (found) |stage| {
        try std.testing.expectEqual(nl.device("m3").?, stage.devices[2]);
        try std.testing.expectEqual(nl.device("m4").?, stage.devices[3]);
        for ([_][]const u8{ "m1", "m2", "m3", "m4", "m5", "m6", "x1" }) |name|
            try std.testing.expect(std.mem.indexOfScalar(EdgeId, &stage.devices, nl.device(name).?) != null);
        // The earlier mirror's gate is not the nominated output stage.
        try std.testing.expect(find(&nl, roles, nl.net("net3").?) == null);
    }
}

test "CT mirror: literal seven members and output-pair identities" {
    try expectStage(@embedFile("ct_mirror_controls_fixture.sp"), true);
}

test "CT mirror: full incidence ambiguity polarity and tap guards" {
    const source = @embedFile("ct_mirror_controls_fixture.sp");
    const replacements = [_][2][]const u8{
        .{ "M7 Von Vop VSS VSS", "M7 Von Vop VSS net1" },
        .{ "M7 Von Vop VSS VSS", "M7 Von net2 VSS VSS" },
        .{ "M4 net2 net1 VDD VDD pch", "M4 net2 net1 VDD VDD unknown" },
        .{ "M5 Von Vop net2 VDD pch", "M5 Von Vop net2 VDD unknown" },
        .{ "M5 Von Vop net2 VDD", "M5 Von elsewhere net2 VDD" },
        .{ "M3 net1 net1 VDD VDD", "M3 net1 net1 VDD elsewhere" },
        .{ "X1 Von Vop Vocm", "X1 Von Vop net1" },
    };
    for (replacements) |change| {
        const mutated = try std.mem.replaceOwned(u8, std.testing.allocator, source, change[0], change[1]);
        defer std.testing.allocator.free(mutated);
        try expectStage(mutated, false);
    }
    for ([_][]const u8{
        "Mextra unused net1 other VDD unknown\n",
        "Mextra unused g net2 VDD pch\n",
        "Xextra Von Vop Vocm ct_inductor\n",
        "Xextra Von Vop Von ct_inductor\n",
    }) |extra| {
        const mutated = try std.fmt.allocPrint(std.testing.allocator, "{s}\n{s}", .{ source, extra });
        defer std.testing.allocator.free(mutated);
        try expectStage(mutated, false);
    }
}
