//! Inductive converter paths, separate from their bias and control columns.
//!
//! Human Rules:
//! - power_paths.1 (habit, bounded) An inductor off the named rails with a
//!   grounded NMOS channel at either end identifies a switching node. A
//!   PMOS with distinct D/S/G and neither channel end on a rail lies flat
//!   between that node and a capacitor-to-ground reservoir: AG1363/1383.
//!   A gate/body does not make the grounded channel. `classify`
//! - power_paths.2 (habit, bounded) Independently controlled PMOS channels
//!   sharing an input bus lie flat when their other ends meet that inductor
//!   or a capacitor: AG1250's main/flying-capacitor branches. Every path
//!   incident on the bus must be such a PMOS; its control touches MOS gates
//!   only. A capacitor to its own gate/opposite end is no evidence. The
//!   auxiliary supply branch alone remains unresolved (AG1199:M1 and
//!   AG1202:M5 stand upright); an inductor's bias mirror stays upright too.
//! - power_paths.3 (habit) The selected path's inductor lies flat and is not
//!   stood up by forms.crooked. All 252 selected AnalogGenie inductors and
//!   649 selected PMOS lie flat in the source drawings. This is two related
//!   converter families, not 649 independent examples. The 734 AMSNet
//!   drawings select none. LC oscillators and inductive LNAs give counter-
//!   examples to using inductor adjacency alone: AG1109, AG1111, AG491.
//!   Explicit deck hints retain precedence. `classify`, `inductor`
//! - power_paths.4 (habit) The main path is the unique selected PMOS at
//!   each coil endpoint, even when shunts or bias columns tap it. The coil stands
//!   between the two selected main PMOS in all 252 source circuits; all
//!   three share a row in 243. The nine source offsets and the full named
//!   inventory are recorded by docs/research/figures/power_paths.py.
//!   More than one selected switch at an end, an ambiguous choice of coil,
//!   or an explicitly upright member gives no three-part group. `series`
//! - power_paths.5 (habit, bounded) The main path stands above its
//!   externally controlled grounded NMOS shunts and active MOS gate
//!   drivers. Both D/S pins lie below the path for all 365 such shunts
//!   and 92 such drivers in the selected source drawings. A bias channel
//!   merely touching the coil has no such order: 110 of 140 nonselected
//!   PMOS there stand level with or above the path. `controlBounds`
//! - power_paths.6 (habit, bounded) A main switch with gate-only external
//!   control faces down when both outer ends of its unique series path
//!   have capacitors to ground. All 107 such controls face down in the
//!   source drawings, including AG1363:MP3. The input-bus family has 159
//!   downward and 131 upward main gates, so one reservoir or an external
//!   gate alone does not decide. `externalReservoirGate`
//!
//! Data: reads existing netlist paths/CSR, model types, drawn and rail rows;
//! writes only the caller's forms. The placement queries read existing
//! coordinate slices and return scalar bounds, with no retained state.
//! Three boolean arrays, each vertexCount,
//! hold gate-only controls, switching-coil endpoints and shared input buses.
//! The allocator owns this scratch only for classify; no retained state,
//! new handles, device objects or per-incidence allocations. CSR bounds
//! every local scan. `inductor` rechecks only a coil's immediate neighbors
//! when forms.crooked needs the same certificate without retaining scratch.
//!
//! Contents:
//! - `pub fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []Form) Allocator.Error!void`
//! - `pub fn inductor(nl: *const Netlist, roles: []const Role, drawn: []const bool, d: u32) bool`
//! - `pub fn series(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, d: u32) ?[3]u32`
//! - `pub fn controlBounds(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, members: [3]u32, coordinates: []const i32) ?[2]i32`
//! - `pub fn externalReservoirGate(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, d: u32) bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = @import("schematic.zig").Role;
const Form = @import("skeleton.zig").Form;

/// Makes the selected PMOS channels and their switching inductors flat.
/// All input rows span their existing net/device table; other forms stay
/// as the caller chose them. Scratch is freed on success and allocation failure.
pub fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []Form) Allocator.Error!void {
    const c = &nl.graph;
    assert(roles.len == c.vertexCount());
    assert(drawn.len == c.edgeCount() and form.len == drawn.len);
    const has_coil = for (c.edges.items(.kind), drawn) |kind, dr| {
        if (dr and kind == .inductor) break true;
    } else false;
    if (!has_coil) return;
    const gates = try gpa.alloc(bool, c.vertexCount());
    defer gpa.free(gates);
    const coils = try gpa.alloc(bool, c.vertexCount());
    defer gpa.free(coils);
    const buses = try gpa.alloc(bool, c.vertexCount());
    defer gpa.free(buses);
    @memset(coils, false);
    @memset(buses, false);
    for (gates, 0..) |*gate, net| gate.* = gateOnly(nl, @intCast(net));
    for (0..c.edgeCount()) |d| {
        const e = EdgeId.from(d);
        if (!switchingCoil(nl, roles, drawn, e)) continue;
        const a, const b = nl.path(e).?;
        coils[a] = true;
        coils[b] = true;
    }
    for (buses, 0..) |*bus, net| {
        var reaches_coil = false;
        for (c.incident(VertexId.from(net))) |e| {
            if (!drawn[e.index()]) continue;
            const ends = nl.path(e) orelse continue;
            if (ends[0] != net and ends[1] != net) continue;
            if (!pmos(nl, roles, e) or !gates[c.members(e)[1].index()]) break;
            const other = ends[@intFromBool(ends[0] == net)];
            reaches_coil = reaches_coil or coils[other];
        } else bus.* = reaches_coil;
    }
    for (0..c.edgeCount()) |d| {
        const e = EdgeId.from(d);
        if (!drawn[d] or !pmos(nl, roles, e)) continue;
        const a, const b = nl.path(e).?;
        if (!selectedMos(nl, roles, drawn, e, .{ coils[a], coils[b] }, .{ buses[a], buses[b] })) continue;
        form[d] = .horizontal;
    }
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind == .inductor and inductor(nl, roles, drawn, @intCast(d))) form[d] = .horizontal;
    }
}

/// Whether this coil belongs to a selected PMOS power path. Used by the
/// later crooked-part pass to preserve that path's form, with no allocation.
/// `d` names an existing device; non-inductors return false.
pub fn inductor(nl: *const Netlist, roles: []const Role, drawn: []const bool, d: u32) bool {
    const c = &nl.graph;
    assert(d < c.edgeCount());
    assert(roles.len == c.vertexCount() and drawn.len == c.edgeCount());
    const e = EdgeId.from(d);
    if (!switchingCoil(nl, roles, drawn, e)) return false;
    for (nl.path(e).?) |net| for (c.incident(VertexId.from(net))) |p| {
        if (!drawn[p.index()] or !pmos(nl, roles, p)) continue;
        const ends = nl.path(p).?;
        if (ends[0] != net and ends[1] != net) continue;
        const other = ends[@intFromBool(ends[0] == net)];
        const gate = c.members(p)[1].index();
        if (capacitor(nl, roles, drawn, other, gate, net, true) or inputBus(nl, roles, drawn, other)) return true;
    };
    return false;
}

/// The unique flat PMOS, coil, PMOS main path containing `d`, ordered by
/// the coil's two terminal nets. Uses only channel endpoints; side-pin
/// incidences and their duplicates do not create additional switches.
/// Multiple qualifying coils or switches, and upright members, return null.
pub fn series(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, d: u32) ?[3]u32 {
    const c = &nl.graph;
    assert(d < c.edgeCount() and form.len == c.edgeCount());
    assert(roles.len == c.vertexCount() and drawn.len == c.edgeCount());
    if (!drawn[d] or form[d] != .horizontal) return null;
    const e = EdgeId.from(d);
    var group: ?[3]u32 = null;
    if (c.edges.items(.kind)[d] == .inductor) {
        group = pairAt(nl, roles, drawn, form, d);
    } else if (pmos(nl, roles, e)) {
        for (nl.path(e).?) |net| for (c.incident(VertexId.from(net))) |coil| {
            const candidate = pairAt(nl, roles, drawn, form, coil.index()) orelse continue;
            if (candidate[0] != d and candidate[2] != d) continue;
            if (group) |old| if (old[1] != candidate[1]) return null;
            group = candidate;
        };
    }
    const chosen = group orelse return null;
    // A coil-first visit must reject ambiguity just as a MOS-first one does.
    for ([_]u32{ chosen[0], chosen[2] }) |mos| for (nl.path(EdgeId.from(mos)).?) |net| {
        for (c.incident(VertexId.from(net))) |coil| {
            if (coil.index() == chosen[1]) continue;
            const other = pairAt(nl, roles, drawn, form, coil.index()) orelse continue;
            if (other[0] == mos or other[2] == mos) return null;
        }
    };
    return chosen;
}

/// The minimum and maximum of `coordinates` among upright grounded
/// external-gate shunts and MOS channels driving a main switch's gate.
/// `members` is a certified series group. The caller supplies existing
/// rows to place above those controls or columns to keep them on one shelf.
/// No bias-only connection counts; null means no selected upright control.
pub fn controlBounds(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, members: [3]u32, coordinates: []const i32) ?[2]i32 {
    const c = &nl.graph;
    assert(coordinates.len == c.edgeCount() and form.len == coordinates.len and drawn.len == coordinates.len);
    assert(c.edges.items(.kind)[members[1]] == .inductor and roles.len == c.vertexCount());
    var bounds: [2]i32 = .{ std.math.maxInt(i32), std.math.minInt(i32) };
    for (nl.path(EdgeId.from(members[1])).?) |net| for (c.incident(VertexId.from(net))) |e| {
        const d = e.index();
        if (!drawn[d] or form[d] != .vertical or !groundedMos(nl, roles, e, net)) continue;
        if (!gateOnly(nl, c.members(e)[1].index())) continue;
        bounds[0] = @min(bounds[0], coordinates[d]);
        bounds[1] = @max(bounds[1], coordinates[d]);
    };
    for ([_]u32{ members[0], members[2] }) |main| {
        const gate = c.members(EdgeId.from(main))[1].index();
        for (c.incident(VertexId.from(gate))) |e| {
            const d = e.index();
            if (!drawn[d] or form[d] != .vertical or c.edges.items(.kind)[d] != .mosfet) continue;
            const ends = nl.path(e).?;
            if (ends[0] != gate and ends[1] != gate) continue;
            bounds[0] = @min(bounds[0], coordinates[d]);
            bounds[1] = @max(bounds[1], coordinates[d]);
        }
    }
    return if (bounds[0] <= bounds[1]) bounds else null;
}

/// Whether `d` is a main switch whose external control faces down on a
/// unique flat path between two capacitors to ground. Gate-only controls
/// exclude active drivers; a single reservoir does not select this habit.
/// Reads existing paths and bounded CSR rows, with no allocation.
pub fn externalReservoirGate(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, d: u32) bool {
    const c = &nl.graph;
    assert(d < c.edgeCount() and form.len == c.edgeCount());
    assert(roles.len == c.vertexCount() and drawn.len == c.edgeCount());
    if (c.edges.items(.kind)[d] != .mosfet) return false;
    const gate = c.members(EdgeId.from(d))[1].index();
    if (roles[gate].isRail() or !gateOnly(nl, gate)) return false;
    const members = series(nl, roles, drawn, form, d) orelse return false;
    for ([_]u32{ members[0], members[2] }, nl.path(EdgeId.from(members[1])).?) |main, inner| {
        const e = EdgeId.from(main);
        const ends = nl.path(e).?;
        assert(ends[0] == inner or ends[1] == inner);
        const outer = ends[@intFromBool(ends[0] == inner)];
        if (!capacitor(nl, roles, drawn, outer, c.members(e)[1].index(), inner, true)) return false;
    }
    return true;
}

// ---- private ----

fn pairAt(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, d: u32) ?[3]u32 {
    const c = &nl.graph;
    if (form[d] != .horizontal or !inductor(nl, roles, drawn, d)) return null;
    var pair: [3]u32 = .{ 0, d, 0 };
    for (nl.path(EdgeId.from(d)).?, 0..) |net, side| {
        var found: ?u32 = null;
        for (c.incident(VertexId.from(net))) |e| {
            if (!drawn[e.index()] or !pmos(nl, roles, e)) continue;
            const a, const b = nl.path(e).?;
            if (a != net and b != net) continue;
            const coils: [2]bool = .{ coilEnd(nl, roles, drawn, a), coilEnd(nl, roles, drawn, b) };
            const buses: [2]bool = .{ busEnd(nl, roles, drawn, a), busEnd(nl, roles, drawn, b) };
            if (!selectedMos(nl, roles, drawn, e, coils, buses)) continue;
            if (found) |old| if (old != e.index()) return null;
            found = e.index();
        }
        const mos = found orelse return null;
        if (form[mos] != .horizontal) return null;
        pair[2 * side] = mos;
    }
    if (pair[0] == pair[2]) return null;
    return pair;
}

fn selectedMos(nl: *const Netlist, roles: []const Role, drawn: []const bool, e: EdgeId, coils: [2]bool, buses: [2]bool) bool {
    const ends = nl.path(e).?;
    const gate = nl.graph.members(e)[1].index();
    for (ends, 0..) |net, side| {
        const other = ends[1 - side];
        if (coils[side] and capacitor(nl, roles, drawn, other, gate, net, true)) return true;
        if (buses[side] and (coils[1 - side] or capacitor(nl, roles, drawn, other, gate, net, false))) return true;
    }
    return false;
}

fn coilEnd(nl: *const Netlist, roles: []const Role, drawn: []const bool, net: u32) bool {
    for (nl.graph.incident(VertexId.from(net))) |e| if (switchingCoil(nl, roles, drawn, e)) return true;
    return false;
}

fn busEnd(nl: *const Netlist, roles: []const Role, drawn: []const bool, net: u32) bool {
    if (!inputBus(nl, roles, drawn, net)) return false;
    for (nl.graph.incident(VertexId.from(net))) |e| {
        if (!drawn[e.index()]) continue;
        const ends = nl.path(e) orelse continue;
        if (ends[0] != net and ends[1] != net) continue;
        const other = ends[@intFromBool(ends[0] == net)];
        if (coilEnd(nl, roles, drawn, other)) return true;
    }
    return false;
}

fn pmos(nl: *const Netlist, roles: []const Role, e: EdgeId) bool {
    const c = &nl.graph;
    if (c.edges.items(.kind)[e.index()] != .mosfet or device.polarity(nl.modelType(e)) != .p) return false;
    const pins = c.members(e);
    assert(pins.len >= 4);
    return pins[0] != pins[2] and pins[1] != pins[0] and pins[1] != pins[2] and
        !roles[pins[0].index()].isRail() and !roles[pins[2].index()].isRail();
}

fn gateOnly(nl: *const Netlist, net: u32) bool {
    const c = &nl.graph;
    for (c.incident(VertexId.from(net))) |e| {
        if (c.edges.items(.kind)[e.index()] != .mosfet) return false;
        for (c.members(e), 0..) |pin, i| if (pin.index() == net and i != 1) return false;
    }
    return true;
}

fn shunt(nl: *const Netlist, roles: []const Role, drawn: []const bool, net: u32) bool {
    const c = &nl.graph;
    for (c.incident(VertexId.from(net))) |e| {
        if (drawn[e.index()] and groundedMos(nl, roles, e, net)) return true;
    }
    return false;
}

fn groundedMos(nl: *const Netlist, roles: []const Role, e: EdgeId, net: u32) bool {
    const c = &nl.graph;
    if (c.edges.items(.kind)[e.index()] != .mosfet or device.polarity(nl.modelType(e)) != .n) return false;
    const pins = c.members(e);
    if (pins[0] == pins[2] or pins[1] == pins[0] or pins[1] == pins[2]) return false;
    return (pins[0].index() == net and roles[pins[2].index()] == .sink) or
        (pins[2].index() == net and roles[pins[0].index()] == .sink);
}

fn switchingCoil(nl: *const Netlist, roles: []const Role, drawn: []const bool, e: EdgeId) bool {
    if (!drawn[e.index()] or nl.graph.edges.items(.kind)[e.index()] != .inductor) return false;
    const a, const b = nl.path(e).?;
    if (a == b or roles[a].isRail() or roles[b].isRail()) return false;
    return shunt(nl, roles, drawn, a) or shunt(nl, roles, drawn, b);
}

fn capacitor(nl: *const Netlist, roles: []const Role, drawn: []const bool, net: u32, gate: u32, opposite: u32, grounded: bool) bool {
    const c = &nl.graph;
    for (c.incident(VertexId.from(net))) |e| {
        if (!drawn[e.index()] or c.edges.items(.kind)[e.index()] != .capacitor) continue;
        const ends = nl.path(e).?;
        const other = ends[@intFromBool(ends[0] == net)];
        if (other == net or other == gate or other == opposite) continue;
        if (!grounded or roles[other] == .sink) return true;
    }
    return false;
}

fn inputBus(nl: *const Netlist, roles: []const Role, drawn: []const bool, net: u32) bool {
    const c = &nl.graph;
    for (c.incident(VertexId.from(net))) |e| {
        if (!drawn[e.index()]) continue;
        const ends = nl.path(e) orelse continue;
        if (ends[0] != net and ends[1] != net) continue;
        if (!pmos(nl, roles, e) or !gateOnly(nl, @intCast(c.members(e)[1].index()))) return false;
    }
    // The caller's PMOS is a path on this bus and reaches the tested coil.
    return true;
}

test "power paths: a series certificate rejects parallel choices, shared coils, and upright members" {
    // Oracle: the graph's unique three-part path, named independently of
    // traversal order. Body aliases repeat incidences but not devices.
    const gpa = std.testing.allocator;
    const prefix = "Power path\n.model nch nmos\n.model pch pmos\n";
    const body = "L1 a b 1n\nCA stored 0 1p\nCB out 0 1p\n" ++
        "MA a ca stored a pch\nMB b cb out b pch\nMN a cn 0 0 nch\n";
    const cases = [_]struct { []const u8, bool }{
        .{ "", true },
        .{ "MPAR a separate stored a pch\n", false },
        .{ "L2 a c 1n\nCC another 0 1p\nMC c cc another c pch\n", false },
    };
    for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.mem.concat(a, u8, &.{ prefix, body, case[0] });
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try @import("schematic.zig").guessRoles(a, &nl);
        const drawn = try a.alloc(bool, nl.graph.edgeCount());
        const form = try a.alloc(Form, drawn.len);
        @memset(drawn, true);
        @memset(form, .horizontal);
        const want: [3]u32 = .{ nl.device("ma").?.index(), nl.device("l1").?.index(), nl.device("mb").?.index() };
        for (want) |d| {
            const got = series(&nl, roles, drawn, form, d);
            try std.testing.expectEqual(case[1], got != null);
            if (got) |parts| try std.testing.expectEqualSlices(u32, &want, &parts);
        }
        form[want[0]] = .vertical;
        for (want) |d| try std.testing.expect(series(&nl, roles, drawn, form, d) == null);
    }
}
