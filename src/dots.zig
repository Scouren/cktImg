//! Junction dots: where a drawing marks that wires meet. In: a laid-out
//! `Schematic`'s routes and pins. Out: the points, each once, rounded to the
//! target's units.
//!
//! Human Rules:
//! - dots.1 (habit) A dot stands wherever one net's wires leave a point in
//!   three or more directions, a device's lead counting as one: a four-way
//!   meeting as much as a T; never where two nets' wires only cross.
//!   People: a dot at 41,668 of 43,009 points where three wires of a net
//!   meet and at all 1,330 where four meet (3% of their dots), in 5,263
//!   hand-drawn schematics. A pin two wires leave is not in that count:
//!   the drawings hold dots only between wires, and people run two wires
//!   from 3,194 of 127,232 pins. `find`
//! - dots.2 (choice) Where a net's level wire crosses one of its own upright
//!   wires, the two join there with a dot: an undotted crossing reads as two
//!   nets crossing. People draw six such crossings in 5,263 schematics.
//!   `find`
//!
//! Contents:
//! - `pub fn find(gpa: Allocator, out: Allocator, s: *const Schematic) Allocator.Error![]Pt`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");

const Pt = library.Pt;
const Schematic = sch.Schematic;
const Line = canvas.Line;
const none = sch.none;

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
    // Routes, on the target's units, and device pins by net.
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
    const lines = try al.alloc(Line, s.routes.items.len);
    const p_by_net = try al.alloc(u32, p_off[nets]);
    const rf = try al.dupe(u32, r_off[0..nets]);
    for (s.routes.items) |r| {
        const l = &lines[rf[r.net]];
        rf[r.net] += 1;
        l.* = .{};
        for (r.pts[0..r.len]) |p| l.push(.round(p));
    }
    const pf = try al.dupe(u32, p_off[0..nets]);
    for (pin_net, pin_dev, 0..) |n, d, p| if (d != none) {
        p_by_net[pf[n]] = @intCast(p);
        pf[n] += 1;
    };
    for (s.routes.items) |r| for (r.pts[0..r.len]) |c| {
        const at: Pt = .round(c);
        const arms = canvas.ways(s, p_by_net[p_off[r.net]..p_off[r.net + 1]], lines[r_off[r.net]..r_off[r.net + 1]], at);
        // People: a dot at 41,668 of 43,009 three-wire meetings and at all
        // 1,330 four-wire ones (5,263 hand-drawn schematics).
        if (@popCount(arms) >= 3) try mark(out, &found, at);
    };
    // A net's level piece crossing one of its own upright pieces, strictly
    // inside both: four ways out of a point that is no route's.
    for (s.routes.items) |r| for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |fa, fb| {
        const a: Pt = .round(fa);
        const b: Pt = .round(fb);
        if (a.y != b.y) continue;
        for (lines[r_off[r.net]..r_off[r.net + 1]]) |*l| {
            const pts = l.slice();
            for (pts[0 .. pts.len - 1], pts[1..]) |c, d| {
                if (c.x == d.x and between(c.x, a.x, b.x) and between(a.y, c.y, d.y)) try mark(out, &found, .{ .x = c.x, .y = a.y });
            }
        }
    };
    for (found.items, 0..) |p, i| for (found.items[i + 1 ..]) |q| assert(!p.eql(q));
    return found.items;
}

// ---- private ----

/// A dot at `at`, unless one is there.
fn mark(out: Allocator, found: *std.ArrayList(Pt), at: Pt) Allocator.Error!void {
    for (found.items) |j| {
        if (j.eql(at)) return;
    }
    try found.append(out, at);
}

/// Whether `v` lies strictly between `a` and `b`.
fn between(v: i32, a: i32, b: i32) bool {
    return v > @min(a, b) and v < @max(a, b);
}
