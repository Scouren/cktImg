//! The drawing's guarantees, checked on a finished `Placed` alone, however it
//! was drawn (docs/research/steering.md §6): every net one piece as a
//! netlister reads it, no wire on another net's point, and dots exactly where
//! a net's wires meet. A finding names its rule, its net, a point, and what
//! else it involves; the drawing code never produces one, so a finding is a
//! bug in it, or in a caller's edit between the stages.
//!
//! Contents:
//! - `pub const Rule = enum`, `pub const Finding = struct`
//! - `pub fn find(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed, lib: *const Library) Allocator.Error!void`
//! - `pub fn connected(…)`, `pub fn shorts(…)`, `pub fn dots(…)`: each rule group alone

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const placed = @import("placed.zig");

const Pt = library.Pt;
const Rect = library.Rect;
const Library = library.Library;
const Placed = placed.Placed;

pub const Rule = enum {
    /// A net in more than one piece; `other` is how many.
    split_net,
    /// A wire of `net` through or onto a point of net `other` (a pin, a
    /// wire's end or bend, a label): xschem joins by touch.
    short,
    /// `net` leaves `at` in `other` (three or more) directions, no dot there.
    dot_missing,
    /// A dot at `at` where `net` has `other` (two or fewer) directions.
    dot_stray,
    /// `net` crosses itself at `at` with no dot: it reads as two nets crossing.
    self_crossing,
    /// Two dots at `at`.
    dot_twice,
};

pub const Finding = struct {
    rule: Rule,
    net: u32,
    at: Pt,
    /// The other net (`short`), or a count (see `Rule`).
    other: u32,
};

/// Appends every finding on `p` to `out`, in rule order, then net order.
/// `lib` is the library `p` was drawn with (which pins are hidden).
// ponytail: every point against every segment, quadratic; fine at cell sizes.
pub fn find(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed, lib: *const Library) Allocator.Error!void {
    const before = out.items.len;
    try connected(gpa, out, p, lib);
    try shorts(gpa, out, p);
    try dots(gpa, out, p);
    assert(out.items.len >= before);
}

/// Every net one piece (`split_net`). Union-find over a net's points:
/// wires join their ends, a label the wire it lies on and the net's name, a
/// port, rail or ground_ref pin the name.
pub fn connected(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed, lib: *const Library) Allocator.Error!void {
    var index: std.AutoHashMapUnmanaged([2]i32, u32) = .empty;
    defer index.deinit(gpa);
    var parent: std.ArrayList(u32) = .empty;
    defer parent.deinit(gpa);
    var where: std.ArrayList(Pt) = .empty;
    defer where.deinit(gpa);
    const uf = struct {
        fn root(par: []u32, x0: u32) u32 {
            var x = x0;
            while (par[x] != x) x = par[x];
            return x;
        }
        fn node(g: Allocator, idx: *std.AutoHashMapUnmanaged([2]i32, u32), par: *std.ArrayList(u32), at_: *std.ArrayList(Pt), at: Pt) !u32 {
            const gop = try idx.getOrPut(g, .{ at.x, at.y });
            if (!gop.found_existing) {
                gop.value_ptr.* = @intCast(par.items.len);
                try par.append(g, gop.value_ptr.*);
                try at_.append(g, at);
            }
            return gop.value_ptr.*;
        }
        fn join(par: []u32, a: u32, b: u32) void {
            par[root(par, a)] = root(par, b);
        }
    };
    for (0..p.netCount()) |n| {
        index.clearRetainingCapacity();
        parent.clearRetainingCapacity();
        where.clearRetainingCapacity();
        // Node 0: the net's name.
        try parent.append(gpa, 0);
        try where.append(gpa, .{ .x = 0, .y = 0 });
        var it = p.segments(n);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            const ia = try uf.node(gpa, &index, &parent, &where, a);
            const ib = try uf.node(gpa, &index, &parent, &where, b);
            uf.join(parent.items, ia, ib);
        };
        for (p.labels) |l| if (l.net == n) {
            const at = try uf.node(gpa, &index, &parent, &where, l.at);
            uf.join(parent.items, at, 0);
            // A name written on a wire names the wire.
            var on = p.segments(n);
            while (on.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (Rect.fromCorners(a, b).contains(l.at)) uf.join(parent.items, at, index.get(.{ a.x, a.y }).?);
            };
        };
        var pins: u32 = 0;
        for (0..p.deviceCount()) |d| {
            const class = lib.at(p.dev_class[d]);
            const lo, const hi = p.pinRange(d);
            for (lo..@min(hi, lo + class.terminals.len)) |pin| {
                const t = class.terminals[pin - lo];
                if (p.pin_net[pin] != n or t.hidden) continue;
                pins += 1;
                const at = try uf.node(gpa, &index, &parent, &where, p.pin_xy[pin]);
                if (hi - lo == 1 or t.ground_ref) uf.join(parent.items, at, 0);
            }
        }
        if (pins < 2) continue;
        var roots: u32 = 0;
        var second: ?Pt = null;
        for (1..parent.items.len) |i| {
            const r = uf.root(parent.items, @intCast(i));
            const first = for (1..i) |j| {
                if (uf.root(parent.items, @intCast(j)) == r) break false;
            } else true;
            if (first) {
                roots += 1;
                if (roots == 2) second = where.items[i];
            }
        }
        if (roots > 1) try out.append(gpa, .{ .rule = .split_net, .net = @intCast(n), .at = second.?, .other = roots });
    }
}

/// A wire of one net through or onto another's pin, label, wire end or bend
/// (`short`).
pub fn shorts(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed) Allocator.Error!void {
    const Point = struct { at: Pt, net: u32 };
    var pts: std.ArrayList(Point) = .empty;
    defer pts.deinit(gpa);
    for (p.pin_xy, p.pin_net) |at, n| if (n != placed.no_net) try pts.append(gpa, .{ .at = at, .net = n });
    for (p.labels) |l| try pts.append(gpa, .{ .at = l.at, .net = l.net });
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        while (it.next()) |poly| for (poly) |at| try pts.append(gpa, .{ .at = at, .net = @intCast(n) });
    }
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            const r = Rect.fromCorners(a, b);
            for (pts.items) |q| {
                if (q.net == n or !r.contains(q.at)) continue;
                try out.append(gpa, .{ .rule = .short, .net = @intCast(n), .at = q.at, .other = q.net });
            }
        };
    }
}

/// Dots exactly at the points where one net leaves in three or more
/// directions (a wire ending there is one, a wire through it two, a pin's
/// lead toward its device one), and no net crossing itself without one.
pub fn dots(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed) Allocator.Error!void {
    var pts: std.ArrayList(Pt) = .empty;
    defer pts.deinit(gpa);
    for (0..p.netCount()) |n| {
        pts.clearRetainingCapacity();
        var it = p.segments(n);
        while (it.next()) |poly| try pts.appendSlice(gpa, poly);
        for (p.pin_xy, p.pin_net) |at, pn| if (pn == n) try pts.append(gpa, at);
        for (pts.items, 0..) |at, i| {
            const seen = for (pts.items[0..i]) |q| {
                if (q.x == at.x and q.y == at.y) break true;
            } else false;
            if (seen) continue;
            var dirs: [4]bool = @splat(false); // left, right, up, down
            var segs = p.segments(n);
            while (segs.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (!Rect.fromCorners(a, b).contains(at)) continue;
                const lo = if (a.x < b.x or a.y < b.y) a else b;
                const hi = if (lo.x == a.x and lo.y == a.y) b else a;
                if (!(at.x == lo.x and at.y == lo.y)) dirs[if (a.y == b.y) 0 else 2] = true;
                if (!(at.x == hi.x and at.y == hi.y)) dirs[if (a.y == b.y) 1 else 3] = true;
            };
            for (0..p.deviceCount()) |d| {
                const lo, const hi = p.pinRange(d);
                for (lo..hi) |pin| {
                    if (p.pin_net[pin] != n or !(p.pin_xy[pin].x == at.x and p.pin_xy[pin].y == at.y)) continue;
                    const o = p.dev_pos[d];
                    const dx = o.x - at.x;
                    const dy = o.y - at.y;
                    if (dx == 0 and dy == 0) continue;
                    if (@abs(dx) >= @abs(dy)) dirs[if (dx < 0) 0 else 1] = true else dirs[if (dy < 0) 2 else 3] = true;
                }
            }
            var arms: u32 = 0;
            for (dirs) |x| arms += @intFromBool(x);
            const dot = for (p.junctions) |j| {
                if (j.x == at.x and j.y == at.y) break true;
            } else false;
            if ((arms >= 3) == dot) continue;
            try out.append(gpa, .{ .rule = if (dot) .dot_stray else .dot_missing, .net = @intCast(n), .at = at, .other = arms });
        }
        var outer = p.segments(n);
        while (outer.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            if (a.y != b.y) continue;
            var inner = p.segments(n);
            while (inner.next()) |q| for (q[0 .. q.len - 1], q[1..]) |c, d| {
                if (c.x != d.x) continue;
                if (c.x <= @min(a.x, b.x) or c.x >= @max(a.x, b.x) or a.y <= @min(c.y, d.y) or a.y >= @max(c.y, d.y)) continue;
                try out.append(gpa, .{ .rule = .self_crossing, .net = @intCast(n), .at = .{ .x = c.x, .y = a.y }, .other = 0 });
            };
        };
    }
    for (p.junctions, 0..) |j, i| for (p.junctions[i + 1 ..]) |k| {
        if (j.x == k.x and j.y == k.y) try out.append(gpa, .{ .rule = .dot_twice, .net = placed.no_net, .at = j, .other = 2 });
    };
}
