//! Physical coordinates of the rows and columns in a resolved schematic lattice.
//!
//! Contents:
//! - `pub const Coordinates`
//! - `pub fn coordinates(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths) !Coordinates`
const std = @import("std");
const Schematic = @import("schematic.zig").Schematic;
const netlist = @import("netlist.zig");
const Skeleton = @import("skeleton.zig").Skeleton;
const Lengths = @import("canvas.zig").Lengths;
const Side = @import("library.zig").Side;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;

/// Device centers indexed by the lattice column and row. The caller frees both slices.
pub const Coordinates = struct {
    /// Horizontal coordinate for each lattice column.
    xs: []const i32,
    /// Vertical coordinate for each lattice row.
    ys: []const i32,
};

/// Each lattice column as wide as its widest device's reach on each side,
/// plus room for a port, label or rail symbol (its stub and a unit) where a
/// side pin on a net driven from outside, an output or a rail faces that
/// side; rows as tall as their tallest device (its pins' reach, or its body
/// where that reaches more than `stack` past them), plus a port's or rail
/// symbol's stub where such a pin faces up or down (the supply's bar over
/// the top aside). `len.series` between neighbouring columns, `len.stack`
/// between rows.
pub fn coordinates(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths) !Coordinates {
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
        const body = s.boxAt(d, .zero);
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
