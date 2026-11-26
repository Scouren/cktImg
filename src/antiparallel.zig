//! Unique antiparallel diode-connected MOS/BJT channels.
//!
//! Human Rules:
//! - antiparallel.1 (habit, bounded) Same-kind, same-known-polarity channels
//!   on reversed distinct nonrail ends, each control tied to its own first
//!   end, form a local pair only when no third same-kind channel spans those
//!   ends. All eight selected source devices in AG739/1048/1052/1149 lie
//!   flat, on separate rows, controls outward, with matched spatial net
//!   order. AG1149 staggers their columns; one common column is a placement
//!   choice, not a universal source relation. `find`
//! - antiparallel.2 (invariant) An existing valid gate/base face left/right
//!   request retains upright classification, so this inferred habit cannot
//!   invalidate a formerly honoured caller request. The relations owner
//!   still admits and applies it; malformed requests give no exemption.
//!   Other caller constraints retain their ordinary owners. `directed`, `held`
//!
//! Data: existing CSR, model/role rows and hints in; one optional typed
//! device handle or a cold precedence predicate out. No arrays, allocation,
//! retained state or new hot structure. A query reads at most one endpoint's
//! incidence slice; callers use their existing canonical device passes and
//! joint chain/slot scratch. Placement remains serial because slots collide.
//!
//! Contents: `find`, `directed`, `held`, `frame`, `placedMate`, then tests.

const std = @import("std");
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const sch = @import("schematic.zig");
const hints = @import("hints.zig");
const relations = @import("relations.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const library = @import("library.zig");
const Side = library.Side;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const assert = std.debug.assert;

/// Finds the sole reversed same-kind channel with its own control tied to
/// its first end and the same known polarity. Counts all same-kind parallel
/// competitors before testing control or polarity. Form/visibility filtering
/// cannot hide an ambiguous third channel. `d` and roles belong to nl.
pub fn find(nl: *const Netlist, roles: []const sch.Role, d: EdgeId) ?EdgeId {
    const c = &nl.graph;
    assert(d.index() < c.edgeCount());
    assert(roles.len == c.vertexCount());
    const kind = c.edges.items(.kind)[d.index()];
    if (kind != .mosfet and kind != .bjt) return null;
    const p = c.members(d);
    assert(p.len >= 3);
    if (p[0] == p[2] or p[0] != p[1] or roles[p[0].index()].isRail() or roles[p[2].index()].isRail()) return null;
    const polarity = device.polarity(nl.modelType(d));
    if (polarity == .other) return null;
    var other: ?EdgeId = null;
    var previous: ?EdgeId = null;
    for (c.incident(p[0])) |e| {
        if (previous == e) continue;
        previous = e;
        if (e == d or c.edges.items(.kind)[e.index()] != kind) continue;
        const q = c.members(e);
        if (!((p[0] == q[0] and p[2] == q[2]) or (p[0] == q[2] and p[2] == q[0]))) continue;
        if (other != null) return null;
        other = e;
    }
    const m = other orelse return null;
    const q = c.members(m);
    return if (q[0] == p[2] and q[2] == p[0] and q[0] == q[1] and
        device.polarity(nl.modelType(m)) == polarity) m else null;
}

/// Whether a pair contains an existing valid upright-control face request.
/// Mirrors relations.faces' admission prerequisites, not merely its verb:
/// unknown pins, malformed arguments and unsupported sides have no effect.
pub fn directed(nl: *const Netlist, a: EdgeId, b: EdgeId) bool {
    for (nl.hints) |hint| {
        if (hint.verb != .face or hint.args.len != 3) continue;
        const side = hint.verb.side(Side, hint.args[2]);
        if (side != .left and side != .right) continue;
        const d = nl.device(hint.args[0]) orelse continue;
        if (d != a and d != b) continue;
        if (relations.pinIndex(nl, d.index(), hint.args[1]) == 1) return true;
    }
    return false;
}

/// Already honoured caller placement/group constraints on either member.
/// Unhandled, dropped and invalid lines cannot suppress the automatic pair.
pub fn held(nl: *const Netlist, verdicts: []const ?hints.Verdict, a: EdgeId, b: EdgeId) bool {
    assert(verdicts.len == nl.hints.len);
    for (nl.hints, verdicts) |hint, verdict| {
        if ((verdict orelse continue).state != .honoured) continue;
        switch (hint.verb) {
            .pair, .mirror, .bank, .stack, .cross, .nogroup, .symmetric, .axis,
            .row, .above, .order, .cell, .face, .upright, .bridge, .at => {},
            .off => return true,
            else => continue,
        }
        for (hint.args) |name| {
            const d = nl.device(name) orelse continue;
            if (d == a or d == b) return true;
        }
    }
    return false;
}

/// Whether the caller's actual canonical frame supports a flat channel
/// with an outward control. No endpoint, declared side or class is rewritten.
pub fn frame(class: library.Class) bool {
    if (class.terminals.len < 3) return false;
    const a, const g, const b = .{ class.terminals[0], class.terminals[1], class.terminals[2] };
    for (class.terminals[0..3]) |t| if (t.hidden or t.ground_ref) return false;
    if (a.at.y != b.at.y or a.at.x == b.at.x or g.at.y == a.at.y) return false;
    const first: Side = if (a.at.x < b.at.x) .left else .right;
    const control: Side = if (g.at.y < a.at.y) .up else .down;
    return class.side(0, .r0) == first and class.side(2, .r0) == first.opposite() and
        class.side(1, .r0) == control;
}

/// The mate eligible for coupled turning in this existing skeleton. Both
/// actual caller frames must support the two rows; final admitted relations
/// and either fixed/stay candidate defeat the inferred orientation together.
pub fn placedMate(s: *const sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, d: EdgeId) ?EdgeId {
    const other = find(nl, s.roles, d) orelse return null;
    const a, const b = .{ d.index(), other.index() };
    assert(ats.len == sk.drawn.len);
    if (!sk.drawn[b] or sk.form[b] != .horizontal or sk.x[a] != sk.x[b] or sk.y[a] == sk.y[b] or sk.shelf[a] != sk.shelf[b]) return null;
    if (ats[a] != null or ats[b] != null or sk.left_end[a] != .auto or sk.left_end[b] != .auto) return null;
    if (held(nl, sk.verdicts, d, other)) return null;
    for ([_]u32{ a, b }) |v| if (!frame(s.lib.at(s.devices.items(.class)[v]))) return null;
    return other;
}

// ---- tests ----

test "antiparallel topology: unique own-control reversed channels and exact boundaries" {
    // Oracle: literal endpoint/control equalities, independent of placement.
    const gpa = std.testing.allocator;
    const prefix = "Clamps\n.model aa nmos\n.model pp pmos\n.model nn npn\n";
    const rows = [_]struct { []const u8, []const u8, bool }{
        .{ "M1 a a b b aa\nM2 b b a 0 aa\n", "m1", true },
        .{ "M2 b b a 0 aa\nM1 a a b b aa\n", "m1", true },
        .{ "Q1 a a b 0 nn\nQ2 b b a 0 nn\n", "q1", true },
        .{ "M1 a a b 0 aa\nM2 b b a vdd pp\n", "m1", false },
        .{ "M1 a a b 0 aa\nM2 b g a 0 aa\n", "m1", false },
        .{ "M1 a a b 0 aa\nM2 a a b 0 aa\n", "m1", false },
        .{ "M1 a a a 0 aa\nM2 a a a 0 aa\n", "m1", false },
        .{ "M1 a a b 0 aa\nM2 b b a 0 aa\nM3 a g b 0 unknown\n", "m1", false },
        .{ "M1 vdd vdd b 0 aa\nM2 b b vdd 0 aa\n", "m1", false },
        .{ "M1 a a b 0 unknown\nM2 b b a 0 unknown\n", "m1", false },
        .{ "M1 a a b 0 aa\nQ2 b b a 0 nn\n", "m1", false },
    };
    for (rows) |row| {
        const text = try std.mem.concat(gpa, u8, &.{ prefix, row[0] });
        defer gpa.free(text);
        var nl = try netlist.parse(gpa, &.{text}, null);
        defer nl.deinit(gpa);
        const roles = try sch.guessRoles(gpa, &nl);
        defer gpa.free(roles);
        const d = nl.device(row[1]).?;
        const mate = find(&nl, roles, d);
        try std.testing.expectEqual(row[2], mate != null);
        if (mate) |m| try std.testing.expectEqual(d, find(&nl, roles, m).?);
    }
}

test "antiparallel topology: incompatible caller frames are not projected into a pair" {
    // Oracle: actual lead coordinates and declared sides, not bbox centers.
    var terminals = [_]library.Terminal{
        .{ .name = "d", .at = .{ .x = -20, .y = 0 } },
        .{ .name = "g", .at = .{ .x = 0, .y = -20 } },
        .{ .name = "s", .at = .{ .x = 20, .y = 0 } },
    };
    const class: library.Class = .{ .name = "custom", .terminals = &terminals, .draw = &.{} };
    try std.testing.expect(frame(class));
    terminals[2].at.y = 10;
    try std.testing.expect(!frame(class));
    terminals[2].at.y = 0;
    terminals[1].side = .left;
    try std.testing.expect(!frame(class));
    terminals[1].side = null;
    terminals[1].hidden = true;
    try std.testing.expect(!frame(class));
}
