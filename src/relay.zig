//! A drawing relaid (stage 4): the previous drawing's places (the deck's
//! `*@ weak at` stays) set against the lattice the engine reads from the
//! deck as it is now. In: the skeleton's cells, the lattice's own
//! coordinates, the stays. Out: every drawn device's point, and no second
//! wiring: the drawing is not closed up again.
//!
//! Human Rules:
//! - relay.1 (invariant) A column or row of the lattice keeps the place
//!   its devices' stays agree on: what the deck did not change stands
//!   where it stood. `axis`
//! - relay.2 (choice) Where the stays' places disagree with the
//!   skeleton's order of the lines, the heaviest set of lines by devices
//!   keeps them (a longest increasing subsequence), each line at the place
//!   most of its stays agree on, the lesser on a tie: the fewest devices
//!   move. `axis`
//! - relay.3 (invariant) Every other device is inside the radius of change
//!   and is laid again: one new to the deck, one the structure now puts on
//!   another line (a pair it mirrors, a row it joins); one it only turns
//!   is turned where it stands. `place`
//! - relay.4 (choice) A line with no place of its own stands the lattice's
//!   pitch after the line before it (before the first kept line, the pitch
//!   before it), and where that leaves no room the lines after it move
//!   along as one, so what stood mirrored stays mirrored. `axis`
//! - relay.5 (invariant) A relaid drawing has no symbol on another: where
//!   two would overlap, the stays are let go and the deck is laid afresh.
//!   `place`
//! - relay.6 (invariant) A strong `at` anchors its device's column and
//!   row as a stay does, and still fixes the device: a strong `at` on the
//!   place a device already holds changes nothing (ag-1350, a hinting
//!   trial: one stay made strong moved four other devices and the report
//!   called their stays `dropped guarantee`). `place`
//!
//! Contents:
//! - `pub fn place(gpa: Allocator, s: *const Schematic, sk: *const Skeleton, xs: []const i32, ys: []const i32, ats: []?pinned.At, at: [][2]f32) Allocator.Error!bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");

const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const Skeleton = skeleton.Skeleton;

/// Sets `at[d]`, each drawn device's point, from the lattice (`xs` per
/// column, `ys` per row, as `sk` cells index them) anchored on the stays in
/// `ats` (a strong `at` anchors too), and takes the `weak` stays out of
/// `ats`: the lines they anchor carry them. A device's turn is the skeleton's
/// (`s.devices` orient and grid, settled), whatever its stay says: one the
/// structure turns is turned where it stands. False, and `at` untouched,
/// when two symbols would overlap: the caller lays the deck afresh. `gpa`
/// backs the work.
pub fn place(gpa: Allocator, s: *const Schematic, sk: *const Skeleton, xs: []const i32, ys: []const i32, ats: []?pinned.At, at: [][2]f32) Allocator.Error!bool {
    const n = sk.drawn.len;
    assert(at.len == n and ats.len == n);
    assert(s.devices.len == n);
    const info = s.devices.slice();
    const old = try gpa.alloc(?i32, 2 * n);
    defer gpa.free(old);
    for (0..n) |d| {
        old[d] = null;
        old[n + d] = null;
        const a = ats[d] orelse continue;
        // A strong `at` keeps its line too: the device stands there anyway
        // (relay.6), so the line it is on stays put with it.
        if (a.weak) ats[d] = null;
        if (!sk.drawn[d]) continue;
        const p = a.origin.add(info.items(.grid)[d]);
        old[d] = p.x;
        old[n + d] = p.y;
    }
    const out = try gpa.alloc(i32, xs.len + ys.len);
    defer gpa.free(out);
    try axis(gpa, sk.x, sk.drawn, xs, old[0..n], out[0..xs.len]);
    try axis(gpa, sk.y, sk.drawn, ys, old[n..], out[xs.len..]);
    // No symbol on another, or the lattice lays the deck afresh.
    const boxes = try gpa.alloc(Rect, n);
    defer gpa.free(boxes);
    for (boxes, 0..) |*b, d| {
        if (!sk.drawn[d]) continue;
        const p: Pt = .{ .x = out[@intCast(sk.x[d])], .y = out[xs.len + @as(usize, @intCast(sk.y[d]))] };
        b.* = s.boxAt(d, p);
        for (boxes[0..d], 0..) |other, e| if (sk.drawn[e] and b.intersects(other)) return false;
    }
    for (at, 0..) |*p, d| if (sk.drawn[d]) {
        p.* = .{ @floatFromInt(out[@intCast(sk.x[d])]), @floatFromInt(out[xs.len + @as(usize, @intCast(sk.y[d]))]) };
    };
    return true;
}

// ---- private ----

/// One axis: `out[l]`, the coordinate of each lattice line. `cell[d]` is
/// the line of drawn device `d`, `fresh[l]` the lattice's own coordinate of
/// line `l` (ascending), `old[d]` where `d`'s stay has it, if any.
fn axis(gpa: Allocator, cell: []const i32, drawn: []const bool, fresh: []const i32, old: []const ?i32, out: []i32) Allocator.Error!void {
    const lines = fresh.len;
    assert(out.len == lines);
    assert(cell.len == drawn.len and old.len == drawn.len);
    // Per line: where its stays have it (the place most agree on, the
    // lesser on a tie), how many do, and whether a device stands on it.
    const anchor = try gpa.alloc(?i32, lines);
    defer gpa.free(anchor);
    const weight = try gpa.alloc(u32, 3 * lines);
    defer gpa.free(weight);
    const used = try gpa.alloc(bool, lines);
    defer gpa.free(used);
    @memset(anchor, null);
    @memset(weight, 0);
    @memset(used, false);
    for (old, cell, drawn) |stay, l, is_drawn| {
        if (!is_drawn) continue;
        const li: usize = @intCast(l);
        used[li] = true;
        const v = stay orelse continue;
        var count: u32 = 0;
        for (old, cell, drawn) |other, m, other_drawn| count += @intFromBool(other_drawn and m == l and other != null and other.? == v);
        if (count > weight[li] or (count == weight[li] and v < anchor[li].?)) {
            anchor[li] = v;
            weight[li] = count;
        }
    }
    // The heaviest set of lines whose places ascend as the lines do keeps
    // them; the others are laid again.
    const best = weight[lines .. 2 * lines];
    const before = weight[2 * lines ..];
    var end: ?usize = null;
    for (0..lines) |l| {
        const a = anchor[l] orelse continue;
        best[l] = weight[l];
        before[l] = std.math.maxInt(u32);
        for (0..l) |k| {
            const b = anchor[k] orelse continue;
            if (b >= a or best[k] + weight[l] <= best[l]) continue;
            best[l] = best[k] + weight[l];
            before[l] = @intCast(k);
        }
        if (end == null or best[l] > best[end.?]) end = l;
    }
    const kept = try gpa.alloc(bool, lines);
    defer gpa.free(kept);
    @memset(kept, false);
    var walk = end;
    while (walk) |l| {
        kept[l] = true;
        walk = if (before[l] == std.math.maxInt(u32)) null else before[l];
    }
    for (anchor, kept) |*a, k| {
        if (!k) a.* = null;
    }

    // The sweep: a kept line where it was, moved along by what was pushed
    // before it; a line laid again, the lattice's pitch after the last.
    const first = for (anchor, used, 0..) |a, u, l| {
        if (u and a != null) break l;
    } else {
        @memcpy(out, fresh);
        return;
    };
    var shift: i32 = 0;
    var prev = first;
    out[first] = anchor[first].?;
    for (first + 1..lines) |l| {
        if (!used[l]) {
            out[l] = out[prev];
            continue;
        }
        const need = out[prev] + (fresh[l] - fresh[prev]);
        if (anchor[l]) |a| {
            // Between two kept lines the room is the drawing's own.
            if (anchor[prev] == null and a + shift < need) shift = need - a;
            out[l] = a + shift;
        } else {
            out[l] = need;
        }
        assert(out[l] >= out[prev]);
        prev = l;
    }
    // The lines before the first kept one, the lattice's pitch before it.
    for (0..first) |l| out[l] = out[first] - (fresh[first] - fresh[l]);
}

test "axis: kept lines stay, a new line between two pushes what follows, a line out of order is laid again" {
    // Oracle: worked by hand. Lattice lines every 100; devices 0..4 on
    // lines 0..4.
    const gpa = std.testing.allocator;
    const cell = [_]i32{ 0, 1, 2, 3, 4 };
    const drawn: [5]bool = @splat(true);
    const fresh = [_]i32{ 0, 100, 200, 300, 400 };
    var out: [5]i32 = undefined;
    // Every line stayed, closer together than the lattice: as it was.
    try axis(gpa, &cell, &drawn, &fresh, &.{ 10, 50, 90, 130, 170 }, &out);
    try std.testing.expectEqualSlices(i32, &.{ 10, 50, 90, 130, 170 }, &out);
    // Line 2 is new: it takes the lattice's pitch, and 3 and 4 move along
    // as one, keeping the room between them.
    try axis(gpa, &cell, &drawn, &fresh, &.{ 10, 50, null, 90, 130 }, &out);
    try std.testing.expectEqualSlices(i32, &.{ 10, 50, 150, 250, 290 }, &out);
    // Line 1's stay is right of line 2's: one of the two is laid again,
    // the rest keep their places; new lines before the first kept one
    // stand the lattice's pitch before it.
    try axis(gpa, &cell, &drawn, &fresh, &.{ null, 300, 90, 130, 170 }, &out);
    try std.testing.expectEqualSlices(i32, &.{ -110, -10, 90, 130, 170 }, &out);
    // No stay at all: the lattice's own.
    try axis(gpa, &cell, &drawn, &fresh, &.{ null, null, null, null, null }, &out);
    try std.testing.expectEqualSlices(i32, &fresh, &out);
}
