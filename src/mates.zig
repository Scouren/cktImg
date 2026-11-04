//! Mates (issue #8, stage 3): which column devices mirror each other. In:
//! the structure, each device's column and its neighbours in it. Out: each
//! column device's mate (itself on the axis), or `none`.
//!
//! The symmetry's mates where it has one (none under `*@ symmetry off`);
//! else each pair's and two-member mirror's, carried up and down their
//! columns. Kept only where each column's mates stand in one column, since
//! columns mirror whole.
//!
//! Contents:
//! - `pub fn find(gpa: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, n_columns: usize) Allocator.Error![]u32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");

const Netlist = netlist.Netlist;
const Structure = structure.Structure;
const Form = skeleton.Form;
const none = structure.none;

/// The symmetry's mates where it has one; else each pair's and two-member
/// mirror's or bank's, carried up and down their two columns while the
/// devices there are of one kind. Vertical devices only, and only where
/// each column's mates stand in one column (`mirrorable`).
pub fn find(gpa: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, n_columns: usize) Allocator.Error![]u32 {
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
    for (mate, 0..) |m, d| if (m != none) assert(mate[m] == d);
    return mate;
}

// ---- private ----

/// Each pair's and two-member mirror's or bank's mates, carried up and down
/// their two columns while the devices there are of one kind.
fn pairMates(nl: *const Netlist, st: *const Structure, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, mate: []u32) void {
    const n = column_of.len;
    const kinds = nl.graph.edges.items(.kind);
    for (st.block_kind, 0..) |k, b| {
        const ms = st.members(b);
        // A bank's two need not mirror each other: a tail and a second
        // stage's source share a bias line.
        if (k == .stack or k == .bank or ms.len != 2) continue;
        var a = ms[0];
        var z = ms[1];
        if (form[a] != .vertical or form[z] != .vertical or column_of[a] == column_of[z]) continue;
        if (mate[a] != none or mate[z] != none) continue;
        // Up the two columns, then down.
        for ([_]bool{ true, false }) |up| {
            a = ms[0];
            z = ms[1];
            var steps: usize = 0;
            while (a != none and z != none and kinds[a] == kinds[z] and steps <= n) : (steps += 1) {
                if (mate[a] != none and mate[a] != z) break;
                mate[a] = z;
                mate[z] = a;
                a = if (up) above[a] else below[a];
                z = if (up) above[z] else below[z];
                if (a != none and z != none and (mate[a] != none or mate[z] != none)) break;
            }
        }
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
