//! Rows (issue #8, stage 3): each vertical device's level, top 0. In: the
//! netlist, its structure, each device's mate, form and ends. Out: one level
//! per device (unspecified for a device not drawn or not vertical).
//!
//! A device stands above another when its lower end is the other's upper
//! end; levels are the longest path down those, after holding mates and
//! blocks level wherever that closes no cycle. Where devices stand above
//! each other in a loop (a transmission gate's two), only their column's
//! links count. Then each type's transistors
//! on ground drop to that type's lowest level among them, as the book draws
//! a second stage's current source beside the first stage's mirror.
//!
//! Contents:
//! - `pub fn rows(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, mate: []const u32, below: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32) ![]u32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const structure = @import("structure.zig");
const symmetry = @import("symmetry.zig");
const skeleton = @import("skeleton.zig");
const sch = @import("schematic.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Structure = structure.Structure;
const Form = skeleton.Form;
const Role = sch.Role;
const none = structure.none;

/// Each vertical device's level: longest path down from the top, after
/// merging mates and blocks (where that closes no cycle); then each type's
/// transistors on ground drop to that type's lowest level among them.
/// `below` is each device's next in its column, or `none`.
pub fn rows(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, mate: []const u32, below: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32) ![]u32 {
    const c = &nl.graph;
    const n = c.edgeCount();
    assert(mate.len == n and below.len == n);
    assert(roles.len == c.vertexCount());
    // Edges: u above l where u's lower end is l's upper end.
    var edges: std.ArrayList([2]u32) = .empty;
    defer edges.deinit(gpa);
    for (0..n) |u| {
        // A rail is a symbol per device: nothing stands on another through it.
        if (!drawn[u] or form[u] != .vertical or roles[lower[u]] == .supply or roles[lower[u]] == .sink) continue;
        for (c.incident(VertexId.from(lower[u]))) |e| {
            const l = e.index();
            if (l == u or !drawn[l] or form[l] != .vertical or upper[l] != lower[u]) continue;
            try edges.append(gpa, .{ @intCast(u), l });
        }
    }
    const class = try gpa.alloc(u32, n);
    defer gpa.free(class);
    for (class, 0..) |*k, d| k.* = @intCast(d);
    // On a loop only the column links stand: those never loop.
    const keep = try gpa.alloc(bool, edges.items.len);
    defer gpa.free(keep);
    for (edges.items, keep) |e, *k| k.* = below[e[0]] == e[1] or !try reaches(gpa, class, edges.items, e[1], e[0]);
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
    // a class only when every member stands on ground.
    const kinds = c.edges.items(.kind);
    for ([_]symmetry.Polarity{ .n, .p, .other }) |pol| {
        var low: u32 = 0;
        for (0..n) |d| if (onGround(nl, kinds, drawn, form, lower, d, pol)) {
            low = @max(low, rank[d]);
        };
        for (0..n) |d| {
            if (!onGround(nl, kinds, drawn, form, lower, d, pol)) continue;
            const k = find(class, @intCast(d));
            const all = for (0..n) |e| {
                if (find(class, @intCast(e)) == k and !onGround(nl, kinds, drawn, form, lower, e, pol)) break false;
            } else true;
            if (all) rank[d] = low;
        }
    }
    return rank;
}

// ---- private ----

fn onGround(nl: *const Netlist, kinds: []const DeviceKind, drawn: []const bool, form: []const Form, lower: []const u32, d: usize, pol: symmetry.Polarity) bool {
    if (!drawn[d] or form[d] != .vertical or !isTransistor(kinds[d])) return false;
    if (symmetry.polarity(nl.modelType(EdgeId.from(d))) != pol) return false;
    return lower[d] == netlist.ground.index();
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

fn reaches(gpa: Allocator, class: []u32, edges: []const [2]u32, from: u32, to: u32) !bool {
    assert(from < class.len);
    assert(to < class.len);
    var seen = try gpa.alloc(bool, class.len);
    defer gpa.free(seen);
    @memset(seen, false);
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, from);
    seen[from] = true;
    while (stack.pop()) |k| {
        if (k == to) return true;
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

fn isTransistor(kind: DeviceKind) bool {
    return switch (kind) {
        .mosfet, .bjt, .jfet, .mesfet => true,
        else => false,
    };
}
