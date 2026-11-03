//! Junction dots: where a net's wires leave a point in three or more
//! directions (a device lead counts as one). In: a laid-out `Schematic`'s
//! routes and pins. Out: the points, rounded to the target's units.
//!
//! Contents:
//! - `pub fn find(gpa: Allocator, out: Allocator, s: *const Schematic) Allocator.Error![]Pt`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");

const Pt = library.Pt;
const Side = library.Side;
const Schematic = sch.Schematic;
const none = sch.none;

const eps: f32 = 1e-4;

/// The junction dots of `s`, each once, in `out`; overlapping wires of one
/// net count once. `gpa` backs the work.
pub fn find(gpa: Allocator, out: Allocator, s: *const Schematic) Allocator.Error![]Pt {
    assert(s.xy.len == s.nodes.len);
    var found: std.ArrayList(Pt) = .empty;
    var scratch: std.heap.ArenaAllocator = .init(gpa);
    defer scratch.deinit();
    const al = scratch.allocator();
    const pin_net = s.pins.items(.net);
    const pin_dev = s.pins.items(.device);
    const pin_side = s.pins.items(.side);
    // Routes and device pins by net.
    const nets = s.net_name.len;
    const r_off = try al.alloc(u32, nets + 1);
    const p_off = try al.alloc(u32, nets + 1);
    @memset(r_off, 0);
    @memset(p_off, 0);
    for (s.routes.items) |r| r_off[r.net + 1] += 1;
    for (pin_net, pin_dev) |n, d| if (d != none) {
        p_off[n + 1] += 1;
    };
    for (1..nets + 1) |i| {
        r_off[i] += r_off[i - 1];
        p_off[i] += p_off[i - 1];
    }
    const r_by_net = try al.alloc(u32, s.routes.items.len);
    const p_by_net = try al.alloc(u32, p_off[nets]);
    const rf = try al.dupe(u32, r_off[0..nets]);
    for (s.routes.items, 0..) |r, i| {
        r_by_net[rf[r.net]] = @intCast(i);
        rf[r.net] += 1;
    }
    const pf = try al.dupe(u32, p_off[0..nets]);
    for (pin_net, pin_dev, 0..) |n, d, p| if (d != none) {
        p_by_net[pf[n]] = @intCast(p);
        pf[n] += 1;
    };
    for (s.routes.items) |cr| for (cr.pts[0..cr.len]) |c| {
        var dirs: [4]bool = @splat(false);
        for (r_by_net[r_off[cr.net]..r_off[cr.net + 1]]) |ri| {
            const r = s.routes.items[ri];
            for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |u, v| {
                if (near(u, v)) continue;
                if (inside(c, u, v)) {
                    const horiz = @abs(u[1] - v[1]) < eps;
                    dirs[@backingInt(if (horiz) Side.left else Side.up)] = true;
                    dirs[@backingInt(if (horiz) Side.right else Side.down)] = true;
                } else if (near(c, u)) {
                    dirs[@backingInt(toward(u, v))] = true;
                } else if (near(c, v)) {
                    dirs[@backingInt(toward(v, u))] = true;
                }
            }
        }
        for (p_by_net[p_off[cr.net]..p_off[cr.net + 1]]) |p| {
            if (near(s.pinPoint(p), c)) dirs[@backingInt(pin_side[p].opposite())] = true;
        }
        var count: u32 = 0;
        for (dirs) |x| count += @intFromBool(x);
        if (count < 3) continue;
        const at: Pt = .{ .x = @intFromFloat(@round(c[0])), .y = @intFromFloat(@round(c[1])) };
        for (found.items) |j| {
            if (j.eql(at)) break;
        } else try found.append(out, at);
    };
    for (found.items, 0..) |p, i| for (found.items[i + 1 ..]) |q| assert(!p.eql(q));
    return found.items;
}

// ---- private ----

fn near(p: [2]f32, q: [2]f32) bool {
    return @abs(p[0] - q[0]) < eps and @abs(p[1] - q[1]) < eps;
}

/// Whether `p` lies strictly inside the axis-aligned segment u–v.
fn inside(p: [2]f32, u: [2]f32, v: [2]f32) bool {
    if (@abs(u[1] - v[1]) < eps) {
        return @abs(p[1] - u[1]) < eps and p[0] > @min(u[0], v[0]) + eps and p[0] < @max(u[0], v[0]) - eps;
    }
    return @abs(p[0] - u[0]) < eps and p[1] > @min(u[1], v[1]) + eps and p[1] < @max(u[1], v[1]) - eps;
}

/// The way from `u` toward `v` along their segment.
fn toward(u: [2]f32, v: [2]f32) Side {
    if (@abs(u[1] - v[1]) < eps) return if (v[0] > u[0]) .right else .left;
    return if (v[1] > u[1]) .down else .up;
}
