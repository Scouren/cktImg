//! Lattice rows/columns and actual symbol reaches → physical coordinates.
//!
//! Human Rules:
//! - lattice_geometry.1 (invariant) Each used row/column clears its actual
//!   body, pin reaches and existing rail/port stubs. Reflection mates use
//!   equal column widths. This is the original sketch coordinate pass,
//!   extracted unchanged so local owners do not exceed the file budget.
//! - lattice_geometry.2 (choice) Cold attached-group envelopes enlarge the
//!   existing cell's numeric room before symmetry equalization. Empty
//!   requests preserve the original coordinate loops. Callers validate the
//!   complete proposed scene and discard room after a rejected placement.
//!
//! Data: borrowed schematic/skeleton tables in; caller-owned x/y arrays
//! out. Temporary room is one pair per row/column, released before return.
//! Every fallible allocation precedes exposing the completed arrays.
//!
//! Contents:
//! - `pub const Geo`, `Room`
//! - `pub fn coordinates(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths, extra: []const Room) !Geo`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Schematic = sch.Schematic;
const Skeleton = skeleton.Skeleton;
const Side = library.Side;
const Lengths = @import("canvas.zig").Lengths;
const boxAt = Schematic.boxAt;

/// Lattice column/row coordinates. Caller frees both with the supplied
/// allocator. Every used column is nondecreasing; every row increases.
pub const Geo = struct { xs: []const i32, ys: []const i32 };

/// Actual composite bounds relative to one existing device's grid. Cold
/// callers own this immediate request slice; no cell or device row changes.
pub const Room = struct { anchor: EdgeId, bounds: library.Rect };

comptime {
    assert(@sizeOf(Room) == 20);
}

/// Each lattice column as wide as its widest device's reach on each side,
/// plus room for a port, label or rail symbol (its stub and a unit) where a
/// side pin on a net driven from outside, an output or a rail faces that
/// side; rows as tall as their tallest device (its pins' reach, or its body
/// where that reaches more than `stack` past them), plus a port's or rail
/// symbol's stub where such a pin faces up or down (the supply's bar over
/// the top aside). `len.series` between neighbouring columns, `len.stack`
/// between rows.
/// `extra` only enlarges numeric room at existing drawn anchors. The caller
/// must retain ordinary coordinates when its composite proposal is rejected.
pub fn coordinates(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths, extra: []const Room) !Geo {
    const c = &nl.graph;
    var w: usize = 1;
    var h: usize = 1;
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        w = @max(w, @as(usize, @intCast(sk.x[d])) + 1);
        h = @max(h, @as(usize, @intCast(sk.y[d])) + 1);
    };
    // Per column, room left and right; per row, up and down.
    const room = try gpa.alloc([2]i32, w + h);
    defer gpa.free(room);
    @memset(room, .{ 0, 0 });
    const cols = room[0..w];
    const rows = room[w..];
    const reach = s.devices.items(.reach);
    const up = @backingInt(Side.up);
    const down = @backingInt(Side.down);
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        const r = reach[d];
        const x: usize = @intCast(sk.x[d]);
        const y: usize = @intCast(sk.y[d]);
        // What it needs on each side.
        var need = r;
        // A body reaching farther than `stack` past its pins (a block with
        // pins on its sides only) takes its own room: two such in one
        // column touched, a pin of one on a pin of the other.
        const body = boxAt(s, d, .zero);
        if (-body.min.y > need[up] + len.stack) need[up] = -body.min.y;
        if (body.max.y > need[down] + len.stack) need[down] = body.max.y;
        for (c.members(EdgeId.from(d)), 0..) |net, i| {
            const side = s.pinSide(@intCast(d), i) orelse continue;
            const role = s.roles[net.index()];
            // A symbol's stub out from the pin (none for a rail's on a
            // two-pin part: `wires.terminal`), and a unit for a symbol
            // beside the device; the supply's bar over the top aside.
            const two = c.members(EdgeId.from(d)).len == 2;
            const stub = if (role.isPort()) len.terminal else if (role.isRail()) (if (two) 0 else len.rail) else continue;
            if (role == .supply and side == .up) continue;
            need[@backingInt(side)] = r[@backingInt(side)] + stub + if (side.isHorizontal()) len.unit else 0;
        }
        cols[x] = .{ @max(cols[x][0], need[@backingInt(Side.left)]), @max(cols[x][1], need[@backingInt(Side.right)]) };
        rows[y] = .{ @max(rows[y][0], need[up]), @max(rows[y][1], need[down]) };
    };
    for (extra) |request| {
        const d = request.anchor.index();
        assert(d < sk.drawn.len and sk.drawn[d]);
        const bounds = request.bounds;
        assert(bounds.min.x <= bounds.max.x and bounds.min.y <= bounds.max.y);
        const x: usize = @intCast(sk.x[d]);
        const y: usize = @intCast(sk.y[d]);
        cols[x] = .{ @max(cols[x][0], -bounds.min.x), @max(cols[x][1], bounds.max.x) };
        rows[y] = .{ @max(rows[y][0], -bounds.min.y), @max(rows[y][1], bounds.max.y) };
    }
    // Mirrored columns as wide as each other, so the drawing keeps the
    // skeleton's symmetry exactly.
    if (sk.axis2) |a2| for (0..w) |k| {
        const m = a2 - @as(i32, @intCast(k));
        if (m < 0 or m >= w) continue;
        const mk: usize = @intCast(m);
        const left = @max(cols[k][0], cols[mk][1]);
        const right = @max(cols[k][1], cols[mk][0]);
        cols[k] = .{ left, right };
        cols[mk] = .{ right, left };
    };
    const xs = try gpa.alloc(i32, w);
    errdefer gpa.free(xs);
    const ys = try gpa.alloc(i32, h);
    errdefer gpa.free(ys);
    // An empty lattice column takes no room: devices stand `series` apart.
    const used = try gpa.alloc(bool, w);
    defer gpa.free(used);
    @memset(used, false);
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        used[@intCast(sk.x[d])] = true;
    };
    var prev: ?usize = null;
    for (xs, cols, used, 0..) |*x, need, u, k| {
        x.* = if (prev) |p| xs[p] + (if (u) cols[p][1] + len.series + need[0] else 0) else need[0];
        if (u) prev = k;
    }
    for (ys, rows, 0..) |*y, need, k| y.* = if (k == 0) need[0] else ys[k - 1] + rows[k - 1][1] + len.stack + need[0];
    for (1..w) |k| assert(xs[k] >= xs[k - 1]);
    for (1..h) |k| assert(ys[k] > ys[k - 1]);
    return .{ .xs = xs, .ys = ys };
}
