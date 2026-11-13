//! Mates (issue #8, stage 3): which column devices mirror each other. In:
//! the structure, each device's column and its neighbours in it. Out: each
//! column device's mate (itself on the axis), or `none`.
//!
//! Human Rules:
//! - mates.1 (unmeasured) In a circuit with a symmetry, each upright device
//!   stands opposite its image; a flat part is not mirrored. `find`
//! - mates.2 (habit) In a circuit with none, the two of each differential
//!   pair, cross-coupled pair and two-member mirror stand mirrored, with
//!   the devices of one type (kind, polarity and pin count, as a
//!   symmetry's two) above and below them in their two columns. People,
//!   drawn level: 946 of 1,057 differential pairs, 76 of 81 cross-coupled,
//!   2,637 of 3,006 mirrors of two; 1,433 of 1,644 pairs of one type up
//!   and down the two columns, and 17 of 170 of two types. `pairMates`
//! - mates.3 (unmeasured) A bank's two are not mirrored: a tail and a
//!   second stage's source share a bias line. `pairMates`
//! - mates.4 (unmeasured) A pair's loads mirror with the pair before they
//!   mirror as some mirror's other half. `pairMates`
//! - mates.5 (invariant) Columns mirror whole: a column's devices stand
//!   mirrored only when all their images stand in one column whose images
//!   stand in it. `mirrorable`
//! - mates.7 (habit) Two mated pairs of columns stand side by side, each
//!   about its own axis, whatever joins them. People: 1,768 of 2,407 twos
//!   of mated pairs of columns in circuits with no symmetry, 228 about one
//!   axis; of the 643 that nets join half to half (a pair and its folded
//!   branches, a chain of mirrors), 406 and 174. `oneAxis`
//!   Narrowing: one pair of columns keeps its mirror, the largest holding
//!   a differential or cross-coupled pair (the lowest rank on a tie; none
//!   when none holds such a pair); the rest stand free, level by their
//!   rows, not mirrored about axes of their own: the skeleton, the wires
//!   and the closing up carry one axis.
//!
//! Contents:
//! - `pub fn find(gpa: Allocator, nl: *const Netlist, _: []const Role, st: *const Structure, drawn: []const bool, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, n_columns: usize) Allocator.Error![]u32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const structure = @import("structure.zig");
const symmetry = @import("symmetry.zig");
const skeleton = @import("skeleton.zig");
const sch = @import("schematic.zig");

const Netlist = netlist.Netlist;
const Role = sch.Role;
const Structure = structure.Structure;
const Form = skeleton.Form;
const none = structure.none;

/// The symmetry's mates where it has one; else each pair's and two-member
/// mirror's, carried up and down their two columns while the devices
/// there are of one type. Vertical devices only, and only where
/// each column's mates stand in one column (`mirrorable`); block mates
/// about one axis only (`oneAxis`). The nets' roles are not read.
pub fn find(gpa: Allocator, nl: *const Netlist, _: []const Role, st: *const Structure, drawn: []const bool, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, n_columns: usize) Allocator.Error![]u32 {
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
    if (!exact) try oneAxis(gpa, st, column_of, n_columns, mate);
    for (mate, 0..) |m, d| if (m != none) assert(mate[m] == d);
    return mate;
}

// ---- private ----

/// Each pair's and two-member mirror's mates, carried up and down their two
/// columns while the devices there are of one type. Differential and
/// cross-coupled pairs first: a pair's load is its own before it is some
/// mirror's other half.
fn pairMates(nl: *const Netlist, st: *const Structure, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, mate: []u32) void {
    const n = column_of.len;
    for ([_]bool{ true, false }) |pairs| for (st.block_kind, 0..) |k, b| {
        const ms = st.members(b);
        // A bank's two need not mirror each other: a tail and a second
        // stage's source share a bias line.
        if (k == .stack or k == .bank or ms.len != 2 or k.ofTwo() != pairs) continue;
        var a = ms[0];
        var z = ms[1];
        if (form[a] != .vertical or form[z] != .vertical or column_of[a] == column_of[z]) continue;
        if (mate[a] != none or mate[z] != none) continue;
        // Up the two columns, then down.
        for ([_][]const u32{ above, below }) |next| {
            a = ms[0];
            z = ms[1];
            var steps: usize = 0;
            // Of one type, as a symmetry's two: people draw 1,433 of 1,644
            // such pairs level, and 17 of 170 of two types (a p-type load
            // over one of a pair, an n-type cascode over the other).
            while (a != none and z != none and symmetry.sameType(nl, a, z) and steps <= n) : (steps += 1) {
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

/// One axis a drawing. Each two mated columns are a cluster; where there
/// are several, the largest holding a differential or cross-coupled pair
/// keeps its mates (the lowest rank on a tie) and the others lose theirs,
/// so their columns stand free, side by side; none keeps them when none
/// holds such a pair (mirrors along a chain of stages).
// ponytail: one axis; a second mated pair of columns is drawn as free
// columns. An axis per pair needs the skeleton, the wires and the closing
// up to carry several.
fn oneAxis(gpa: Allocator, st: *const Structure, column_of: []const u32, n_columns: usize, mate: []u32) !void {
    assert(mate.len == column_of.len);
    // Per two mated columns (at the lesser): their mated devices, the least
    // rank among them, and whether a pair's two are mates in them. People:
    // of 2,407 twos of mated pairs of columns in 5,263 hand drawings, 1,768
    // stand each about its own axis and 228 share one, whatever joins them
    // (nets half to half: 406 and 174 of 643).
    const Cluster = struct { devices: u32 = 0, rank: u32 = none, paired: bool = false };
    const clusters = try gpa.alloc(Cluster, n_columns);
    defer gpa.free(clusters);
    @memset(clusters, .{});
    for (mate, 0..) |m, d| if (m != none and m != d) {
        const c = &clusters[@min(column_of[d], column_of[m])];
        c.devices += 1;
        c.rank = @min(c.rank, st.device_rank[d]);
    };
    for (st.block_kind, 0..) |k, b| {
        const ms = st.members(b);
        if (k.ofTwo() and mate[ms[0]] == ms[1]) clusters[@min(column_of[ms[0]], column_of[ms[1]])].paired = true;
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
        if (m.* != none and m.* != d and @min(column_of[d], column_of[m.*]) != keep) m.* = none;
    }
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
