//! Rows (issue #8, stage 3): each vertical device's level, top 0. In: the
//! netlist, its structure, each device's mate, form and ends. Out: one level
//! per device (unspecified for a device not drawn or not vertical).
//!
//! Human Rules:
//! - levels.1 (order: potential) A device stands above another when its
//!   lower end is the other's upper end, and each device's row is the
//!   longest path down from the top; nothing stands on another through a
//!   rail. `rows`
//! - levels.2 (habit) A transistor whose gate is the only gate on the
//!   junction of two devices of one column takes a row between them, its
//!   gate level with the junction. People: 69% of 1,443 such gates in 5,263
//!   hand-drawn schematics. `rows`
//! - levels.3 (habit) Not when the lower device is a transistor of its type
//!   on the same rail: it keeps its row. People: 65% of 184. `rows`
//! - levels.4 (book) Nor when it is mated and the upper device is a
//!   transistor of its type on the same rail, as the book draws a fully
//!   differential second stage; the code names no figure. `rows`
//! - levels.5 (choice) A deck's `row` line holds devices level and its
//!   `above` line one over another, whatever else moves: the deck's word
//!   wins. `rows`
//! - levels.6 (choice) Where devices stand above each other in a loop (a
//!   transmission gate's two), only their column's links count: a loop has
//!   no longest path. `rows`
//! - levels.7 (unmeasured) Mates stand level, where that sets no device
//!   above itself. `rows`
//! - levels.8 (unmeasured) The upright members of a block other than a
//!   stack stand level, where that sets no device above itself. `rows`
//! - levels.9 (book) Each type's transistors on ground drop to that type's
//!   lowest row among them, as the book draws a second stage's current
//!   source beside the first stage's mirror; the code names no figure. A
//!   set held level drops only when every member stands on ground, and a
//!   drop that breaks a `row` or `above` line is undone. `rows`
//! - levels.10 (habit) A two-pin part on ground with nothing over it hangs
//!   under its net: a row below the lowest transistor whose gate the net
//!   drives, level with a device the net is the upper end of; mates hang
//!   level; a hang that breaks a line is undone. People: 72% of 1,642 such
//!   pins in 5,263 hand-drawn schematics are under the net; 27% here by
//!   longest path alone. `rows`
//!   Narrowing: a part with two pins on its card or a dependent source
//!   (`isFoot`); a switch and a three-pin diode keep their row.
//!
//! Contents:
//! - `pub fn rows(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, rel: *const Relations, mate: []const u32, below: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32) ![]u32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const structure = @import("structure.zig");
const symmetry = @import("symmetry.zig");
const skeleton = @import("skeleton.zig");
const forms = @import("forms.zig");
const relations = @import("relations.zig");
const sch = @import("schematic.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Structure = structure.Structure;
const Form = skeleton.Form;
const Role = sch.Role;
const Relations = relations.Relations;
const none = structure.none;
const isTransistor = device.isTransistor;
const isRail = Role.isRail;

/// Each vertical device's level: longest path down from the top, after
/// merging mates and blocks (where that closes no cycle); then each type's
/// transistors on ground drop to that type's lowest level among them, and
/// a part on ground with nothing over it hangs under the net it joins.
/// `below` is each device's next in its column, or `none`.
pub fn rows(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, rel: *const Relations, mate: []const u32, below: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32) ![]u32 {
    const c = &nl.graph;
    const n = c.edgeCount();
    assert(mate.len == n and below.len == n);
    assert(roles.len == c.vertexCount());
    const kinds = c.edges.items(.kind);
    // Edges: u above l where u's lower end is l's upper end.
    var edges: std.ArrayList([2]u32) = .empty;
    defer edges.deinit(gpa);
    for (0..n) |u| {
        // A rail is a symbol per device: nothing stands on another through it.
        if (!drawn[u] or form[u] != .vertical or isRail(roles[lower[u]])) continue;
        for (c.incident(VertexId.from(lower[u]))) |e| {
            const l = e.index();
            if (l == u or !drawn[l] or form[l] != .vertical or upper[l] != lower[u]) continue;
            try edges.append(gpa, .{ @intCast(u), l });
        }
    }
    // A transistor whose gate alone hangs on the junction of two devices of
    // one column stands in a row between them, its gate level with the
    // junction, as people draw it (69% of 1,443 such gates in 5,263
    // hand-drawn schematics): its gate's wire runs straight into the link,
    // where beside the lower device it was a Z of two corners. Not beside a
    // lower device of its own type on its own rail: people keep that row
    // (65% of 184); nor a mated one beside an upper device of its type on
    // its rail, as the book draws a fully differential second stage.
    for (0..n) |g| {
        if (!drawn[g] or form[g] != .vertical) continue;
        const gate = device.of(kinds[g]).gate orelse continue;
        const net = c.members(EdgeId.from(g))[gate].index();
        if (net == upper[g] or net == lower[g] or isRail(roles[net])) continue;
        var over: ?u32 = null;
        var under: ?u32 = null;
        var gates: usize = 0;
        var clear = true;
        for (c.incident(VertexId.from(net))) |e| {
            const d = e.index();
            if (!drawn[d]) continue;
            if (device.of(kinds[d]).gate) |pin| gates += @intFromBool(c.members(e)[pin].index() == net);
            if (form[d] != .vertical or d == g) continue;
            if (lower[d] == net) {
                clear = clear and (over == null or over.? == d);
                over = d;
            }
            if (upper[d] == net) {
                clear = clear and (under == null or under.? == d);
                under = d;
            }
        }
        const u = over orelse continue;
        const l = under orelse continue;
        if (!clear or gates != 1 or below[u] != l) continue;
        if (onRailWith(nl, roles, kinds, lower, g, l) or (mate[g] != none and mate[g] != g and onRailWith(nl, roles, kinds, upper, g, u))) continue;
        try edges.append(gpa, .{ u, @intCast(g) });
        try edges.append(gpa, .{ @intCast(g), l });
    }
    const class = try gpa.alloc(u32, n);
    defer gpa.free(class);
    for (class, 0..) |*k, d| k.* = rel.find(@intCast(d));
    const lines = edges.items.len;
    for (rel.edges) |e| try edges.append(gpa, e);
    // On a loop only the column links and the lines stand: those never
    // loop (the links were chosen around the lines).
    const keep = try gpa.alloc(bool, edges.items.len);
    defer gpa.free(keep);
    for (edges.items, keep, 0..) |e, *k, at| k.* = at >= lines or below[e[0]] == e[1] or
        (find(class, e[0]) != find(class, e[1]) and !try reaches(gpa, class, edges.items, e[1], e[0]));
    var kept: usize = 0;
    for (edges.items, keep) |e, k| if (k) {
        edges.items[kept] = e;
        kept += 1;
    };
    edges.shrinkRetainingCapacity(kept);
    // Equalities: mates first, then blocks, each kept if it closes no cycle.
    for (mate, 0..) |m, d| if (m != none and m != d) try level(gpa, class, edges.items, @intCast(d), m);
    for (st.block_kind, 0..) |k, b| {
        if (k == .stack) continue;
        const ms = st.members(b);
        for (ms[1..]) |d| if (drawn[d] and drawn[ms[0]] and form[d] == .vertical and form[ms[0]] == .vertical) try level(gpa, class, edges.items, ms[0], d);
    }

    // Longest path over the classes, now free of loops.
    const rank = try gpa.alloc(u32, n);
    errdefer gpa.free(rank);
    @memset(rank, 0);
    var changed = true;
    var rounds: usize = 0;
    while (changed and rounds <= n) : (rounds += 1) {
        changed = false;
        for (edges.items) |e| {
            const ru = rank[find(class, e[0])];
            const l = find(class, e[1]);
            if (find(class, e[0]) == l) continue;
            if (rank[l] < ru + 1) {
                rank[l] = ru + 1;
                changed = true;
            }
        }
    }
    assert(!changed);
    for (0..n) |d| rank[d] = rank[find(class, @intCast(d))];
    for (edges.items) |e| if (find(class, e[0]) != find(class, e[1])) assert(rank[e[1]] > rank[e[0]]);

    // Transistors on ground: each type's to its lowest level among them,
    // a class only when every member stands on ground; a drop that breaks a
    // line is undone.
    const before = try gpa.dupe(u32, rank);
    defer gpa.free(before);
    for ([_]symmetry.Polarity{ .n, .p, .other }) |pol| {
        var low: u32 = 0;
        for (0..n) |d| if (onGround(nl, roles, kinds, drawn, form, lower, d, pol)) {
            low = @max(low, rank[d]);
        };
        for (0..n) |d| {
            if (!onGround(nl, roles, kinds, drawn, form, lower, d, pol)) continue;
            const k = find(class, @intCast(d));
            const all = for (0..n) |e| {
                if (find(class, @intCast(e)) == k and !onGround(nl, roles, kinds, drawn, form, lower, e, pol)) break false;
            } else true;
            if (all) rank[d] = low;
        }
    }
    // A part on ground with nothing over it hangs under its net: a row
    // below the lowest transistor whose gate the net drives, level with a
    // device the net is the upper end of. Longest path alone left it on the
    // top row, its pin over the net it joins, where people have it under
    // (72% of 1,642 such pins in 5,263 hand-drawn schematics, 27% here).
    const hang = try gpa.dupe(u32, rank);
    defer gpa.free(hang);
    for (0..n) |d| {
        if (!isFoot(nl, roles, kinds, drawn, form, lower, d)) continue;
        const net = upper[d];
        if (isRail(roles[net])) continue;
        var under: u32 = 0;
        const over = for (c.incident(VertexId.from(net))) |e_id| {
            const e = e_id.index();
            if (e == d or !drawn[e] or form[e] != .vertical) continue;
            if (lower[e] == net) break true;
            under = @max(under, if (upper[e] == net) rank[e] else rank[e] + 1);
        } else false;
        if (!over) hang[d] = @max(rank[d], under);
    }
    for (0..n) |d| {
        if (hang[d] == rank[d]) continue;
        // Mates hang level: the class's lowest, when all of it hangs.
        const k = find(class, @intCast(d));
        var low = hang[d];
        const all = for (0..n) |e| {
            if (find(class, @intCast(e)) != k) continue;
            if (!isFoot(nl, roles, kinds, drawn, form, lower, e)) break false;
            low = @max(low, hang[e]);
        } else true;
        if (all) rank[d] = low;
    }
    var undone = true;
    var passes: usize = 0;
    while (undone) : (passes += 1) {
        assert(passes <= n);
        undone = false;
        for (rel.edges) |e| if (rank[e[0]] >= rank[e[1]]) {
            for ([_]u32{ e[0], e[1] }) |v| undone = undo(class, rank, before, v) or undone;
        };
        for (0..n) |d| if (rank[d] != rank[rel.find(@intCast(d))]) {
            for ([_]u32{ @intCast(d), rel.find(@intCast(d)) }) |v| undone = undo(class, rank, before, v) or undone;
        };
    }
    for (rel.edges) |e| assert(rank[e[0]] < rank[e[1]]);
    return rank;
}

// ---- private ----

/// Restores the level of `v`'s class from before the ground drop; whether
/// anything changed.
fn undo(class: []u32, rank: []u32, before: []const u32, v: u32) bool {
    const k = find(class, v);
    var changed = false;
    for (0..rank.len) |d| if (find(class, @intCast(d)) == k and rank[d] != before[d]) {
        rank[d] = before[d];
        changed = true;
    };
    return changed;
}

/// Whether `d` is a drawn transistor of type `pol` whose lower end is on a
/// ground: net 0 or one of that role (`vss`, `gnd`).
fn onGround(nl: *const Netlist, roles: []const Role, kinds: []const DeviceKind, drawn: []const bool, form: []const Form, lower: []const u32, d: usize, pol: symmetry.Polarity) bool {
    if (!drawn[d] or form[d] != .vertical or !isTransistor(kinds[d])) return false;
    if (symmetry.polarity(nl.modelType(EdgeId.from(d))) != pol) return false;
    return roles[lower[d]] == .sink;
}

/// Whether `g` and `d` are transistors of one type with the same rail on
/// their `end` (upper or lower).
fn onRailWith(nl: *const Netlist, roles: []const Role, kinds: []const DeviceKind, end: []const u32, g: usize, d: u32) bool {
    if (!isTransistor(kinds[d]) or end[g] != end[d] or !isRail(roles[end[g]])) return false;
    return symmetry.polarity(nl.modelType(EdgeId.from(g))) == symmetry.polarity(nl.modelType(EdgeId.from(d)));
}

/// Whether `d` is a drawn upright part drawn with two terminals (two pins
/// on its card, or a dependent source, its control pair undrawn) whose
/// lower end is on a ground. Narrower than "an upright part on ground": a
/// switch (its control pair is wired) and a three-pin diode keep their row.
fn isFoot(nl: *const Netlist, roles: []const Role, kinds: []const DeviceKind, drawn: []const bool, form: []const Form, lower: []const u32, d: usize) bool {
    if (!drawn[d] or form[d] != .vertical or isTransistor(kinds[d])) return false;
    return (nl.graph.members(EdgeId.from(d)).len == 2 or forms.isDependent(nl, roles, @intCast(d))) and roles[lower[d]] == .sink;
}

/// Merges the classes of `a` and `b` unless one is above the other.
fn level(gpa: Allocator, class: []u32, edges: []const [2]u32, a: u32, b: u32) !void {
    assert(a < class.len);
    assert(b < class.len);
    const ka = find(class, a);
    const kb = find(class, b);
    if (ka == kb) return;
    if (try reaches(gpa, class, edges, ka, kb) or try reaches(gpa, class, edges, kb, ka)) return;
    class[ka] = kb;
}

fn find(class: []u32, d: u32) u32 {
    var k = d;
    var steps: usize = 0;
    while (class[k] != k) : (steps += 1) {
        assert(steps < class.len);
        k = class[k];
    }
    return k;
}

/// Whether the class of `from` stands above the class of `to` through
/// `edges`: a path of them from one to the other.
fn reaches(gpa: Allocator, class: []u32, edges: []const [2]u32, from: u32, to: u32) !bool {
    assert(from < class.len);
    assert(to < class.len);
    var seen = try gpa.alloc(bool, class.len);
    defer gpa.free(seen);
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(gpa);
    // By class: a device a `row` line holds level is not its own class.
    const target = find(class, to);
    try stack.append(gpa, find(class, from));
    seen[find(class, from)] = true;
    while (stack.pop()) |k| {
        if (k == target) return true;
        for (edges) |e| {
            if (find(class, e[0]) != k) continue;
            const l = find(class, e[1]);
            if (seen[l]) continue;
            seen[l] = true;
            try stack.append(gpa, l);
        }
    }
    return false;
}
