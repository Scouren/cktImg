//! The router's guarantees, checked on a finished `Placed` alone, however
//! it was drawn. In: a `Placed` and its library. Out: `checks.Finding`s,
//! one per wire that comes too near another net's rail symbol, per wire end
//! that meets nothing, and per net whose wire closes a loop. The drawing
//! code never produces one, so a finding is a bug in it.
//!
//! Human Rules:
//! - wire_gates.1 (invariant) No wire touches another net's rail symbol or
//!   runs on a line beside its strokes, one target unit out (canvas.9).
//!   `glyphs`
//! - wire_gates.2 (invariant) Every end of a net's wire meets a pin of the
//!   net (a symbol's too), a name of it or another of its wires; a named
//!   bar's run past its outer pins (wires.7) ends free, its name on it.
//!   `ends`
//! - wire_gates.3 (invariant) Each net's wire is a tree (wire_tree.1).
//!   `loops`
//!
//! Contents:
//! - `pub fn find(gpa: Allocator, out: *std.ArrayList(checks.Finding), p: *const Placed, lib: *const Library) Allocator.Error!void`
//! - `pub fn glyphs(…)`, `pub fn ends(…)`, `pub fn loops(…)`: each rule alone

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const placed = @import("placed.zig");
const checks = @import("checks.zig");
const wire_geometry = @import("wire_geometry.zig");
const wire_tree = @import("wire_tree.zig");

const Pt = library.Pt;
const Library = library.Library;
const Placed = placed.Placed;
const Finding = checks.Finding;

/// Appends every finding on `p` to `out`: `glyphs`, then `ends`, then
/// `loops`, each in net order.
pub fn find(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed, lib: *const Library) Allocator.Error!void {
    const before = out.items.len;
    try glyphs(gpa, out, p, lib);
    try ends(gpa, out, p);
    try loops(gpa, out, p);
    assert(out.items.len >= before);
}

/// A wire of `net` within a unit of rail `other`'s symbol at `at`, its
/// pin (`glyph_touch`, wire_gates.1).
pub fn glyphs(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed, lib: *const Library) Allocator.Error!void {
    for (0..p.deviceCount()) |d| {
        const role = lib.at(p.dev_class[d]).role;
        if (role != .power_rail and role != .ground_rail) continue;
        const lo, const hi = p.pinRange(d);
        if (hi - lo != 1) continue;
        const rail = p.pin_net[lo];
        const box = p.deviceRect(lib, d).grow(1);
        for (0..p.netCount()) |n| {
            if (n == rail) continue;
            var it = p.segments(n);
            while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (!wire_geometry.hitsRect(a, b, box)) continue;
                try out.append(gpa, .{ .rule = .glyph_touch, .net = @intCast(n), .at = p.pin_xy[lo], .other = rail });
            };
        }
    }
}

/// An end of a wire of `net` at `at` that meets nothing of its net
/// (`dangling_end`, wire_gates.2).
pub fn ends(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed) Allocator.Error!void {
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        var k: u32 = 0;
        while (it.next()) |poly| : (k += 1) for ([_]Pt{ poly[0], poly[poly.len - 1] }) |e| {
            if (meets(p, n, p.net_seg[n] + k, e) or namedRun(p, n, e)) continue;
            try out.append(gpa, .{ .rule = .dangling_end, .net = @intCast(n), .at = e, .other = 0 });
        };
    }
}

/// A net whose wire closes a loop, at its first point (`net_loop`,
/// wire_gates.3).
pub fn loops(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed) Allocator.Error!void {
    var segs: std.ArrayList([2]Pt) = .empty;
    defer segs.deinit(gpa);
    for (0..p.netCount()) |n| {
        segs.clearRetainingCapacity();
        var it = p.segments(n);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| try segs.append(gpa, .{ a, b });
        if (segs.items.len < 2 or !try wire_tree.cyclic(gpa, segs.items)) continue;
        try out.append(gpa, .{ .rule = .net_loop, .net = @intCast(n), .at = segs.items[0][0], .other = 0 });
    }
}

// ---- private ----

/// Whether `e`, an end of polyline `self` of net `n`, lies on a pin, a
/// label or another polyline of the net.
fn meets(p: *const Placed, n: usize, self: u32, e: Pt) bool {
    for (p.pin_xy, p.pin_net) |at, pn| if (pn == n and at.eql(e)) return true;
    for (p.labels) |l| if (l.net == n and l.at.eql(e)) return true;
    var it = p.segments(n);
    var k = p.net_seg[n];
    while (it.next()) |poly| : (k += 1) {
        if (k == self) continue;
        for (poly[0 .. poly.len - 1], poly[1..]) |a, b| if (wire_geometry.contains(a, b, e)) return true;
    }
    return false;
}

/// Whether `e` ends a level run of net `n` that carries one of its names,
/// the run unbroken from `e` to the name: a bar run past its pins
/// (wires.7).
fn namedRun(p: *const Placed, n: usize, e: Pt) bool {
    for (p.labels) |l| {
        if (l.net != n or l.at.y != e.y) continue;
        // Walk from e to the name over the net's level pieces on this row.
        var x = @min(e.x, l.at.x);
        const end = @max(e.x, l.at.x);
        var steps: usize = 0;
        while (x < end) : (steps += 1) {
            assert(steps <= p.wire_pts.len);
            var reach = x;
            var it = p.segments(n);
            while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (a.y != e.y or b.y != e.y or @min(a.x, b.x) > x or @max(a.x, b.x) <= x) continue;
                reach = @max(reach, @max(a.x, b.x));
            };
            if (reach == x) break;
            x = reach;
        }
        if (x >= end) return true;
    }
    return false;
}
