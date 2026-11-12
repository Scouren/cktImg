//! Mates (issue #8, stage 3): which column devices mirror each other. In:
//! the structure, each device's column and its neighbours in it. Out: each
//! column device's mate (itself on the axis), or `none`.
//!
//! The symmetry's mates where it has one (none under `*@ symmetry off`);
//! else each pair's and two-member mirror's, carried up and down their
//! columns. Kept only where each column's mates stand in one column, since
//! columns mirror whole; and, of pairs the circuit does not wire half to
//! half, only those about one axis: a drawing has one.
//!
//! Contents:
//! - `pub fn find(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []const bool, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, n_columns: usize) Allocator.Error![]u32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");
const sch = @import("schematic.zig");

const Netlist = netlist.Netlist;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Structure = structure.Structure;
const Form = skeleton.Form;
const none = structure.none;

/// The symmetry's mates where it has one; else each pair's and two-member
/// mirror's or bank's, carried up and down their two columns while the
/// devices there are of one kind. Vertical devices only, and only where
/// each column's mates stand in one column (`mirrorable`); block mates
/// about one axis only (`oneAxis`).
pub fn find(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []const bool, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, n_columns: usize) Allocator.Error![]u32 {
    const mate = try gpa.alloc(u32, column_of.len);
    errdefer gpa.free(mate);
    @memset(mate, none);
    if (st.symmetry_off) return mate;
    var exact = false;
    for (st.device_mate, 0..) |m, d| if (m != none and drawn[d] and form[d] == .vertical and form[m] == .vertical) {
        mate[d] = m;
        exact = true;
    };
    if (!exact) pairMates(nl, st, form, column_of, above, below, mate);
    try mirrorable(gpa, column_of, n_columns, mate);
    if (!exact) try oneAxis(gpa, nl, roles, st, column_of, n_columns, mate);
    for (mate, 0..) |m, d| if (m != none) assert(mate[m] == d);
    return mate;
}

// ---- private ----

/// Each pair's and two-member mirror's mates, carried up and down their two
/// columns while the devices there are of one kind. Differential and
/// cross-coupled pairs first: a pair's load is its own before it is some
/// mirror's other half.
fn pairMates(nl: *const Netlist, st: *const Structure, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, mate: []u32) void {
    const n = column_of.len;
    const kinds = nl.graph.edges.items(.kind);
    for ([_]bool{ true, false }) |pairs| for (st.block_kind, 0..) |k, b| {
        const ms = st.members(b);
        // A bank's two need not mirror each other: a tail and a second
        // stage's source share a bias line.
        if (k == .stack or k == .bank or ms.len != 2 or (k == .pair or k == .cross) != pairs) continue;
        var a = ms[0];
        var z = ms[1];
        if (form[a] != .vertical or form[z] != .vertical or column_of[a] == column_of[z]) continue;
        if (mate[a] != none or mate[z] != none) continue;
        // Up the two columns, then down.
        for ([_][]const u32{ above, below }) |next| {
            a = ms[0];
            z = ms[1];
            var steps: usize = 0;
            while (a != none and z != none and kinds[a] == kinds[z] and steps <= n) : (steps += 1) {
                if (mate[a] != none and mate[a] != z) break;
                mate[a] = z;
                mate[z] = a;
                a = next[a];
                z = next[z];
                if (a != none and z != none and (mate[a] != none or mate[z] != none)) break;
            }
        }
    };
}

/// One axis a drawing. Mated column pairs are one cluster when the circuit
/// wires them half to half: a net (no rail, no bias) joins a column of one
/// pair to a column of the other, and another net joins their two mates (a
/// pair and its folded branches, two pairs on the same inputs). One net on
/// all four says nothing of the halves: a supply under another name. Unjoined clusters would
/// nest about one axis, each pair's two columns far apart: where there are
/// several, the largest holding a differential or cross-coupled pair keeps
/// its mates (the lowest rank on a tie) and the others lose theirs, so
/// their columns stand free, side by side; none keeps them when none holds
/// such a pair (mirrors along a chain of stages).
// ponytail: one axis; a second symmetric cluster is drawn as free columns.
// An axis per cluster needs the skeleton, the wires and the closing up to
// carry several.
fn oneAxis(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, column_of: []const u32, n_columns: usize, mate: []u32) !void {
    const g = &nl.graph;
    assert(roles.len == g.vertexCount());
    assert(mate.len == column_of.len);
    const image = try gpa.alloc(u32, 2 * n_columns);
    defer gpa.free(image);
    const root = image[n_columns..];
    @memset(image[0..n_columns], none);
    for (mate, 0..) |m, d| if (m != none and m != d) {
        image[column_of[d]] = column_of[m];
    };
    // Per two mated columns: the first net joining them, and whether a
    // second does.
    // ponytail: nets only. Pairs joined half to half through bridges (a
    // coil each side) are not one cluster: tried on 5,263 reference
    // circuits, it drew 3 with fewer crossings and 10 with more.
    const joined = try gpa.alloc(u32, n_columns * n_columns);
    defer gpa.free(joined);
    const twice = try gpa.alloc(bool, n_columns * n_columns);
    defer gpa.free(twice);
    @memset(joined, none);
    @memset(twice, false);
    for (roles, 0..) |r, net| {
        if (r == .supply or r == .sink or r == .bias) continue;
        const on = g.incident(VertexId.from(@intCast(net)));
        for (on) |e| for (on) |f| {
            const u = column_of[e.index()];
            const v = column_of[f.index()];
            if (u == none or v == none or image[u] == none or image[v] == none) continue;
            const at = u * n_columns + v;
            if (joined[at] == none) joined[at] = @intCast(net) else if (joined[at] != net) twice[at] = true;
        };
    }
    for (root, 0..) |*r, c| r.* = @intCast(c);
    for (0..n_columns) |u| {
        if (image[u] == none) continue;
        unite(root, @intCast(u), image[u]);
        for (0..u) |v| {
            if (image[v] == none) continue;
            const here = u * n_columns + v;
            const there = image[u] * n_columns + image[v];
            if (joined[here] == none or joined[there] == none) continue;
            if (joined[here] != joined[there] or twice[here] or twice[there]) unite(root, @intCast(u), @intCast(v));
        }
    }
    // Per cluster (at its root column): its mated devices, the least rank
    // among them, and whether a pair's two are mates in it.
    const Cluster = struct { devices: u32 = 0, rank: u32 = none, paired: bool = false };
    const clusters = try gpa.alloc(Cluster, n_columns);
    defer gpa.free(clusters);
    @memset(clusters, .{});
    for (mate, 0..) |m, d| if (m != none and m != d) {
        const c = &clusters[top(root, column_of[d])];
        c.devices += 1;
        c.rank = @min(c.rank, st.device_rank[d]);
    };
    for (st.block_kind, 0..) |k, b| {
        const ms = st.members(b);
        if ((k == .pair or k == .cross) and mate[ms[0]] == ms[1]) clusters[top(root, column_of[ms[0]])].paired = true;
    }
    var count: usize = 0;
    var keep: u32 = none;
    for (clusters, 0..) |c, at| {
        if (c.devices == 0) continue;
        count += 1;
        const k = if (keep == none) c else clusters[keep];
        const better = keep == none or (c.paired and !k.paired) or
            (c.paired == k.paired and (c.devices > k.devices or (c.devices == k.devices and c.rank < k.rank)));
        if (better) keep = @intCast(at);
    }
    if (count <= 1) return;
    if (!clusters[keep].paired) keep = none;
    for (mate, 0..) |*m, d| {
        if (m.* != none and m.* != d and top(root, column_of[d]) != keep) m.* = none;
    }
}

fn top(root: []const u32, c: u32) u32 {
    var at = c;
    var steps: usize = 0;
    while (root[at] != at) : (steps += 1) {
        assert(steps < root.len);
        at = root[at];
    }
    return at;
}

fn unite(root: []u32, a: u32, b: u32) void {
    const ra = top(root, a);
    const rb = top(root, b);
    root[@max(ra, rb)] = @min(ra, rb);
}

/// Drops the mates of every column whose members' mates do not all stand in
/// one column that maps back to it (and the mates' own): the columns'
/// order mirrors column onto column, so such a column has no image. A
/// keeper's two devices in two columns, mated to one inverter's, lose them.
fn mirrorable(gpa: Allocator, column_of: []const u32, n_columns: usize, mate: []u32) !void {
    const conflict = none - 1;
    const image = try gpa.alloc(u32, n_columns);
    defer gpa.free(image);
    var rounds: usize = 0;
    while (true) : (rounds += 1) {
        assert(rounds <= mate.len);
        @memset(image, none);
        for (mate, 0..) |m, d| if (m != none) {
            const c = column_of[d];
            image[c] = if (image[c] == none or image[c] == column_of[m]) column_of[m] else conflict;
        };
        var changed = false;
        for (mate, 0..) |m, d| if (m != none) {
            const c = column_of[d];
            const ok = image[c] != conflict and image[image[c]] == c;
            if (ok) continue;
            mate[d] = none;
            mate[m] = none;
            changed = true;
        };
        if (!changed) break;
    }
}
