//! Grounded input branches: existing graph, roles and drawn rows -> a
//! private voltage-source junction and the resistor's driven gate net.
//!
//! Human Rules:
//! - input_resistors.1 (habit, bounded) A resistor between a private
//!   grounded voltage source and a distinct MOS gate lies flat at one
//!   driven gate's row. The upright source stands outside it, ground
//!   below and signal at or below that row. All 22 selected AG/AMS source
//!   drawings agree; 160 actual SVG leads and both local conductor legs
//!   are verified in docs/research/input-resistors.md.
//! - input_resistors.2 (scope) Count every pin on the private junction,
//!   including hidden devices, gates and bodies. Only the resistor and
//!   one independent voltage source may meet there. Both resistor ends
//!   are distinct and nonrail. A driven MOS has distinct D/G/S and known
//!   polarity. A BJT base or MOS source alone supplies no certificate:
//!   AG637:R1 and AMS114:RS are upright source counterexamples.
//! - input_resistors.3 (scope) Other pins may meet the gate net, and more
//!   than one gate may qualify. AG1082 has a channel load; AG477 has three
//!   driven gates but only one same-row straight local anchor. Placement
//!   chooses one gate for every geometric condition; this query chooses
//!   none. Explicit driver, form, face and placement requests keep their
//!   existing owners and precedence.
//!
//! Data: at most one stack result per resistor; its three u32 handles are
//! existing graph indices consumed together. No new table or allocation.
//! Each query scans existing pin/incident rows; resistor queries share
//! read-only graph data, while callers own form and placement writes.
//!
//! Contents:
//! - `pub const Branch = struct`
//! - `pub fn find(nl: *const Netlist, roles: []const Role, drawn: []const bool, resistor: u32) ?Branch`
//! - `pub fn isGate(nl: *const Netlist, drawn: []const bool, net: u32, d: u32) bool`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = @import("schematic.zig").Role;

/// Electrical branch only. The resistor is the caller's input handle;
/// semantic R/V pin indices follow from `junction`. No gate is chosen.
pub const Branch = struct {
    /// Drawn independent voltage-source device, with its other pin ground.
    source: u32,
    /// Nonrail net whose only pin incidences belong to R and the source.
    junction: u32,
    /// Other resistor endpoint, driving at least one `isGate` MOS.
    gate_net: u32,
};

comptime {
    assert(@sizeOf(Branch) == 12);
}

/// Finds a private grounded-source branch at an existing resistor handle.
/// Roles/drawn span the graph; nondrawn members and nonresistors return
/// null. Hidden third-party pin incidences still invalidate privacy.
/// Caller geometry and forms do not enter this allocation-free query.
pub fn find(nl: *const Netlist, roles: []const Role, drawn: []const bool, resistor: u32) ?Branch {
    const c = &nl.graph;
    assert(resistor < c.edgeCount() and drawn.len == c.edgeCount());
    assert(roles.len == c.vertexCount());
    const kinds = c.edges.items(.kind);
    if (!drawn[resistor] or kinds[resistor] != .resistor) return null;
    const pins = c.members(EdgeId.from(resistor));
    if (pins.len != 2 or pins[0] == pins[1]) return null;
    if (roles[pins[0].index()].isRail() or roles[pins[1].index()].isRail()) return null;
    for (pins, 0..) |junction, side| {
        const incident = c.incident(junction);
        // With distinct R and V ends, each contributes exactly one pin.
        // Counting all incidences excludes a hidden C, gate or body too.
        if (incident.len != 2) continue;
        const source = incident[@intFromBool(incident[0].index() == resistor)];
        if (!drawn[source.index()] or kinds[source.index()] != .vsource) continue;
        const vp = c.members(source);
        if (vp.len != 2) continue;
        const ground = vp[@intFromBool(vp[0] == junction)];
        if (roles[ground.index()] != .sink) continue;
        const gate = pins[1 - side];
        for (c.incident(gate)) |e| {
            if (!isGate(nl, drawn, gate.index(), e.index())) continue;
            // The gate incidence prevents this endpoint from also being
            // a private R/V junction, so both directions cannot qualify.
            return .{ .source = source.index(), .junction = junction.index(), .gate_net = gate.index() };
        }
    }
    return null;
}

/// Whether an existing drawn device supplies a distinct-channel MOS gate
/// on `net`. The terminal index is always one. Other devices' incidences
/// on that net impose no restriction; placement selects a settled anchor.
pub fn isGate(nl: *const Netlist, drawn: []const bool, net: u32, d: u32) bool {
    const c = &nl.graph;
    assert(d < c.edgeCount() and drawn.len == c.edgeCount());
    assert(net < c.vertexCount());
    if (!drawn[d] or c.edges.items(.kind)[d] != .mosfet) return false;
    const pins = c.members(EdgeId.from(d));
    return pins[1].index() == net and pins[0] != pins[1] and
        pins[0] != pins[2] and pins[1] != pins[2] and
        device.polarity(nl.modelType(EdgeId.from(d))) != .other;
}

// ---- private ----

fn expectBranch(text: []const u8, expected: bool, hidden: ?[]const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{text}, null);
    const roles = try @import("schematic.zig").guessRoles(a, &nl);
    const drawn = try a.alloc(bool, nl.graph.edgeCount());
    @memset(drawn, true);
    if (hidden) |name| drawn[nl.device(name).?.index()] = false;
    const branch = find(&nl, roles, drawn, nl.device("rs").?.index());
    try std.testing.expectEqual(expected, branch != null);
    if (branch) |b| {
        try std.testing.expectEqual(nl.device("vin").?.index(), b.source);
        try std.testing.expectEqual(nl.net("private").?.index(), b.junction);
        try std.testing.expectEqual(nl.net("gate").?.index(), b.gate_net);
    }
}

test "input resistor certificate: semantic pin order, multiple gates and channel loads" {
    // Oracle: this literal graph has exactly R/V at private and a distinct
    // MOS gate at gate; pin order cannot change those named incidences.
    const fixture = "Input branch\n.model nch nmos\n.model pch pmos\n" ++
        "RS private gate 1k\nVin private 0 1\nM1 out gate 0 0 nch\n";
    try expectBranch(fixture, true, null);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]struct { old: []const u8, new: []const u8 }{
        .{ .old = "RS private gate", .new = "RS gate private" },
        .{ .old = "Vin private 0 1", .new = "Vin 0 private -1" },
        .{ .old = "M1 out gate 0 0 nch", .new = "M1 out gate vdd vdd pch" },
    }) |case| try expectBranch(try std.mem.replaceOwned(u8, a, fixture, case.old, case.new), true, null);
    const loaded = try std.mem.concat(a, u8, &.{ fixture, "M2 other gate vdd vdd pch\nM3 gate bias 0 0 nch\nC1 gate 0 1p\n" });
    try expectBranch(loaded, true, null);
    try expectBranch(loaded, true, "m1");
    try expectBranch(fixture, false, "m1");
    try expectBranch(fixture, false, "rs");
    try expectBranch(fixture, false, "vin");
}

test "input resistor certificate: every private-junction incidence counts" {
    // Oracle: each added third device has an explicit pin at private.
    // Hiding its symbol cannot make that electrical junction private.
    const fixture = "Input branch\n.model nch nmos\nRS private gate 1k\n" ++
        "Vin private 0 1\nM1 out gate 0 0 nch\n";
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]struct { text: []const u8, name: []const u8 }{
        .{ .text = "Cextra private 0 1p\n", .name = "cextra" },
        .{ .text = "Mextra drain private 0 0 nch\n", .name = "mextra" },
        .{ .text = "Mextra drain bias 0 private nch\n", .name = "mextra" },
        .{ .text = "Vextra private 0 1\n", .name = "vextra" },
    }) |case| {
        const text = try std.mem.concat(a, u8, &.{ fixture, case.text });
        try expectBranch(text, false, null);
        try expectBranch(text, false, case.name);
    }
}

test "input resistor certificate: BJT base, source drive and channel shorts do not qualify" {
    // Oracle: literal terminal identities, independent of native form.
    // The shorted-MOS case can already lie flat without this certificate.
    const fixture = "Input branch\n.model nch nmos\n.model qn npn\n" ++
        "RS private gate 1k\nVin private 0 1\nM1 out gate 0 0 nch\n";
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]struct { old: []const u8, new: []const u8 }{
        .{ .old = "M1 out gate 0 0 nch", .new = "Q1 out gate 0 qn" },
        .{ .old = "M1 out gate 0 0 nch", .new = "M1 out bias gate 0 nch" },
        .{ .old = "M1 out gate 0 0 nch", .new = "M1 gate gate 0 0 nch" },
        .{ .old = "M1 out gate 0 0 nch", .new = "M1 out gate gate 0 nch" },
        .{ .old = "M1 out gate 0 0 nch", .new = "M1 out gate out 0 nch" },
        .{ .old = "Vin private 0 1", .new = "Vin private floating 1" },
        .{ .old = "Vin private 0 1", .new = "Vin private vdd 1" },
        .{ .old = "RS private gate", .new = "RS private private" },
        .{ .old = "M1 out gate 0 0 nch", .new = "M1 out gate 0 0 unknown" },
    }) |case| try expectBranch(try std.mem.replaceOwned(u8, a, fixture, case.old, case.new), false, null);
}
