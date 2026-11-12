//! Forms and ends (issue #8, stage 3): which devices are drawn, which stand
//! upright in a column and which lie flat between columns, and each upright
//! device's upper and lower end. In: the netlist, its roles and structure;
//! for `crooked`, a laid skeleton. Out: `drawn`, `form`, `upper`, `lower`;
//! the flat parts to stand upright after all.
//!
//! A device is upright when current passes it on the way down: a
//! transistor, a two-pin device on a rail, in series, or between a net
//! nearer the supply and one nearer the ground. A flat part the skeleton
//! could not set level with the pins it joins stands upright in a second
//! lay (`crooked`).
//!
//! Contents:
//! - `pub fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []bool, form: []Form, verdicts: []?hints.Verdict) !void`
//! - `pub fn ends(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32) !void`
//! - `pub fn crooked(nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, column: i32, stood: []bool) bool`
//! - `pub fn isTransistor(kind: DeviceKind) bool`, `pub fn isTwoPin(kind: DeviceKind) bool`, `pub fn isRail(r: Role) bool`
//! - `pub fn isDependent(nl: *const Netlist, roles: []const Role, d: u32) bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const symmetry = @import("symmetry.zig");
const relations = @import("relations.zig");
const hints = @import("hints.zig");
const skeleton = @import("skeleton.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Structure = structure.Structure;
const Form = skeleton.Form;
const Skeleton = skeleton.Skeleton;
const none = structure.none;

/// Drawn: not a driver (unless a `driver` line says) and with pins. Vertical: a transistor, a two-pin
/// device on a rail, one in series (each of its nets holds one other
/// channel element), one on the way down (one net nearer the supply, the
/// other nearer the ground), a current source; capacitors only on a rail;
/// never a two-pin device
/// between two nets the symmetry swaps, which straddles the axis, nor a
/// device whose current path is shorted (a MOS dummy: no current flows).
pub fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []bool, form: []Form, verdicts: []?hints.Verdict) !void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    assert(drawn.len == c.edgeCount());
    for (drawn, 0..) |*dr, d| {
        dr.* = c.members(EdgeId.from(d)).len > 0 and !sch.isDriver(c, roles, @intCast(d));
    }
    try relations.drivers(gpa, nl, drawn, verdicts);
    // Channel elements on each net: transistor channel ends, two-pin pins.
    const count = try gpa.alloc(u32, c.vertexCount());
    defer gpa.free(count);
    @memset(count, 0);
    for (0..c.edgeCount()) |d| {
        if (!drawn[d]) continue;
        const pins = c.members(EdgeId.from(d));
        if (isTransistor(kinds[d]) and pins.len >= 3) {
            count[pins[0].index()] += 1;
            count[pins[2].index()] += 1;
        } else if (passes(nl, roles, @intCast(d)) and kinds[d] != .capacitor and pins.len >= 2) {
            count[pins[0].index()] += 1;
            count[pins[1].index()] += 1;
        }
    }
    const from_supply = try railDistance(gpa, nl, roles, drawn, .supply);
    defer gpa.free(from_supply);
    const from_ground = try railDistance(gpa, nl, roles, drawn, .sink);
    defer gpa.free(from_ground);
    for (form, 0..) |*f, d| {
        const pins = c.members(EdgeId.from(d));
        f.* = .horizontal;
        if (!drawn[d]) continue;
        if (isTransistor(kinds[d]) and pins.len >= 3) {
            if (pins[0].index() != pins[2].index()) f.* = .vertical;
        } else if (passes(nl, roles, @intCast(d)) and pins.len >= 2 and pins[0].index() != pins[1].index()) {
            const a = pins[0].index();
            const b = pins[1].index();
            const on_rail = isRail(roles[a]) or isRail(roles[b]);
            const series = kinds[d] != .capacitor and count[a] == 2 and count[b] == 2;
            // On the way down: people stand 262 of 305 such resistors and 18
            // of 24 diodes upright in 5,263 hand-drawn schematics, and 76 of
            // 83 current sources wherever they are.
            const down = kinds[d] != .capacitor and
                (from_supply[a] < from_supply[b] and from_ground[a] > from_ground[b] or
                    from_supply[a] > from_supply[b] and from_ground[a] < from_ground[b]);
            const straddles = a != b and st.net_mate[a] == b;
            // A dependent source stands upright wherever it is, as a
            // current source does: 398 of 414 in those drawings.
            const source = kinds[d] == .isource or isDependent(nl, roles, @intCast(d));
            if ((on_rail or series or down or source) and !straddles) f.* = .vertical;
        }
    }
}

/// A transistor's ends from its type (an n-type's drain is its upper end);
/// a two-pin device's from the rails, else the pin nearer the supply
/// through channel elements.
pub fn ends(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32) !void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    @memset(upper, none);
    @memset(lower, none);
    const dist = try railDistance(gpa, nl, roles, drawn, .supply);
    defer gpa.free(dist);
    for (0..c.edgeCount()) |d| {
        if (!drawn[d] or form[d] != .vertical) continue;
        const e = EdgeId.from(d);
        const pins = c.members(e);
        if (isTransistor(kinds[d])) {
            const p = symmetry.polarity(nl.modelType(e)) == .p;
            upper[d] = if (p) pins[2].index() else pins[0].index();
            lower[d] = if (p) pins[0].index() else pins[2].index();
        } else {
            const a = pins[0].index();
            const b = pins[1].index();
            const a_up = roles[a] == .supply or roles[b] == .sink or
                (roles[b] != .supply and roles[a] != .sink and dist[a] <= dist[b]);
            upper[d] = if (a_up) a else b;
            lower[d] = if (a_up) b else a;
        }
        assert(upper[d] != none and lower[d] != none);
        assert(upper[d] != lower[d]);
    }
}

/// Marks in `stood` the flat two-pin parts of `sk` that cannot be wired
/// straight, and says whether there is one: a part between two nets that
/// both hold an upright device's pin, where not both have such a pin level
/// with the part within a device column. Flat, it would be wired round a
/// corner (the wire leaves both pins of a flat part straight for 44.9% of
/// 4,443 in 5,263 hand-drawn schematics, and for 12.6% of the 6,171 laid
/// flat here); upright, its column gives it a straight wire, and people
/// stand 55% to 62% of the parts between two such nets upright. A part
/// with a net no upright device is on (an input's, an output's, a block's)
/// stays flat, as people draw it. Not a part a line of the deck names
/// (`upright`, `bridge`), one on a rail, one between two nets the symmetry
/// swaps, one that meets its mate (a pair across the axis), or any part of
/// a circuit with no transistor and no block. `column` is a device column's width in lattice columns.
pub fn crooked(nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, column: i32, stood: []bool) bool {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    assert(stood.len == c.edgeCount());
    @memset(stood, false);
    // A circuit of parts only has no column of stages to stand a part in:
    // its series parts lie along its top wire.
    const parts_only = for (kinds) |kind| {
        if (isTransistor(kind) or kind == .subckt) break false;
    } else true;
    if (parts_only) return false;
    var any = false;
    for (0..c.edgeCount()) |d| {
        if (!sk.drawn[d] or sk.form[d] != .horizontal or !isTwoPin(kinds[d])) continue;
        const pins = c.members(EdgeId.from(d));
        if (pins.len != 2 or pins[0].index() == pins[1].index()) continue;
        const a = pins[0].index();
        const b = pins[1].index();
        if (isRail(roles[a]) or isRail(roles[b]) or st.net_mate[a] == b) continue;
        // Two mated parts that meet (a pair of sense resistors on the axis)
        // lie across it, as the book draws them.
        const m = st.device_mate[d];
        if (m != none and m != d and sk.drawn[m]) {
            const mp = c.members(EdgeId.from(m));
            const meet = for (mp) |net| {
                if (net.index() == a or net.index() == b) break true;
            } else false;
            if (meet) continue;
        }
        const told = for (nl.hints) |h| {
            if (h.verb != .upright and h.verb != .bridge) continue;
            const named = for (h.args) |name| {
                if ((nl.device(name) orelse continue).index() == d) break true;
            } else false;
            if (named) break true;
        } else false;
        if (told) continue;
        // Both its nets on upright devices, and one of them with no pin
        // level with the part.
        var level_ends: usize = 0;
        const between = for ([_]u32{ a, b }) |net| {
            var upright = false;
            var level = false;
            for (c.incident(VertexId.from(net))) |e| {
                const v = e.index();
                if (v == d or !sk.drawn[v] or sk.form[v] != .vertical) continue;
                upright = true;
                const row = if (sk.upper[v] == net) sk.y[v] - 1 else if (sk.lower[v] == net) sk.y[v] + 1 else sk.y[v];
                level = level or (row == sk.y[d] and @abs(sk.x[v] - sk.x[d]) <= column);
            }
            if (!upright) break false;
            level_ends += @intFromBool(level);
        } else true;
        stood[d] = between and level_ends < 2;
        any = any or stood[d];
    }
    return any;
}

pub fn isTransistor(kind: DeviceKind) bool {
    return switch (kind) {
        .mosfet, .bjt, .jfet, .mesfet => true,
        else => false,
    };
}

/// A two-pin device the current passes through: its first two pins.
pub fn isTwoPin(kind: DeviceKind) bool {
    return switch (kind) {
        .resistor, .capacitor, .inductor, .vsource, .isource, .cccs, .ccvs, .diode, .vswitch, .cswitch => true,
        else => false,
    };
}

/// A voltage-controlled source drawn as a dependent source: a two-pin part,
/// its control pins no part of where it stands. Every `G`, and an `E` that
/// is no ideal amplifier (its low output on a ground and a gain of a
/// thousand or more, `E1 out 0 inp inn 1e5`: the book's op-amp). People
/// draw each with two terminals (414 of 414 in 5,263 hand-drawn
/// schematics).
pub fn isDependent(nl: *const Netlist, roles: []const Role, d: u32) bool {
    const c = &nl.graph;
    const pins = c.members(EdgeId.from(d));
    if (pins.len < 2) return false;
    return switch (c.edges.items(.kind)[d]) {
        .vccs => true,
        // An unreadable gain (a parameter) is no number: not an amplifier.
        .vcvs => !(roles[pins[1].index()] == .sink and @abs(c.edges.items(.value)[d]) >= 1000),
        else => false,
    };
}

pub fn isRail(r: Role) bool {
    return r == .supply or r == .sink;
}

// ---- private ----

/// A part the current passes through by its first two pins.
fn passes(nl: *const Netlist, roles: []const Role, d: u32) bool {
    return isTwoPin(nl.graph.edges.items(.kind)[d]) or isDependent(nl, roles, d);
}

/// Hops from a net of role `from` (a rail) through channel elements
/// (transistor channels, two-pin devices but capacitors), never through
/// another rail; `none` where no such way leads.
fn railDistance(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, from: Role) ![]u32 {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    const dist = try gpa.alloc(u32, c.vertexCount());
    errdefer gpa.free(dist);
    @memset(dist, none);
    var queue: std.ArrayList(u32) = .empty;
    defer queue.deinit(gpa);
    for (roles, 0..) |r, net| if (r == from) {
        dist[net] = 0;
        try queue.append(gpa, @intCast(net));
    };
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        assert(queue.items.len <= dist.len);
        const v = queue.items[head];
        if (isRail(roles[v]) and roles[v] != from) continue;
        for (c.incident(VertexId.from(v))) |e| {
            const d = e.index();
            if (!drawn[d] or kinds[d] == .capacitor) continue;
            const pins = c.members(e);
            var chan: [2]VertexId = undefined;
            if (isTransistor(kinds[d]) and pins.len >= 3) {
                chan = .{ pins[0], pins[2] };
            } else if (passes(nl, roles, d) and pins.len >= 2) {
                chan = .{ pins[0], pins[1] };
            } else continue;
            // Through the channel only: a gate or a body on `v` is no way.
            if (chan[0].index() != v and chan[1].index() != v) continue;
            for (chan) |w| if (dist[w.index()] == none) {
                dist[w.index()] = dist[v] + 1;
                try queue.append(gpa, w.index());
            };
        }
    }
    return dist;
}
