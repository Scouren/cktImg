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
//! - `pub fn drawnAs(p: *const Placed, nl: *const Netlist, h: hints.Hint, unit: i32) ?bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const placed = @import("placed.zig");
const netlist = @import("netlist.zig");
const hints = @import("hints.zig");
const relations = @import("relations.zig");
const pinned = @import("pinned.zig");

const Pt = library.Pt;
const Rect = library.Rect;
const Library = library.Library;
const Placed = placed.Placed;
const Netlist = netlist.Netlist;

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

/// Whether `p` draws what line `h` of `nl`'s deck asks, read from the
/// drawing alone (y grows down): `row` one y, `above` y increasing, `order`
/// x increasing, `face` the pin on that side of its device or its other
/// end, `label` a name on the net and `wire` none, `port` a port symbol
/// past the net's pins on that side. Null for a line the drawing cannot
/// show (a group, the symmetry).
pub fn drawnAs(p: *const Placed, nl: *const Netlist, h: hints.Hint, unit: i32) ?bool {
    switch (h.verb) {
        .row, .above, .order => {
            var prev: ?Pt = null;
            for (h.args) |name| {
                const at = p.dev_pos[deviceIn(p, name) orelse return false];
                if (prev) |q| {
                    const ok = switch (h.verb) {
                        .row => at.y == q.y,
                        .above => at.y > q.y,
                        else => at.x > q.x,
                    };
                    if (!ok) return false;
                }
                prev = at;
            }
            return true;
        },
        .face => {
            if (h.args.len != 3) return null;
            const d = deviceIn(p, h.args[0]) orelse return false;
            const e = (nl.device(h.args[0]) orelse return false).index();
            const pin = relations.pinIndex(nl, e, h.args[1]) orelse return false;
            const lo, const hi = p.pinRange(d);
            if (lo + pin >= hi) return false;
            const at = p.pin_xy[lo + pin];
            const o = p.dev_pos[d];
            const dir = h.args[2];
            if (std.mem.eql(u8, dir, "left")) return at.x < o.x;
            if (std.mem.eql(u8, dir, "right")) return at.x > o.x;
            // An end: above or below the device's other end.
            const other: u32 = if (isFet(nl, e)) (if (pin == 0) 2 else 0) else (if (pin == 0) 1 else 0);
            if (lo + other >= hi) return false;
            const there = p.pin_xy[lo + other];
            return if (std.mem.eql(u8, dir, "up")) at.y < there.y else at.y > there.y;
        },
        .label => {
            // Named, or nothing in the circuit to name (an apart driver's).
            const net = netIn(p, h.args[0]) orelse return false;
            for (p.labels) |l| if (l.net == net) return true;
            var it = p.segments(net);
            return it.next() == null;
        },
        .wire => return wired(p, netIn(p, h.args[0]) orelse return false),
        .port => {
            if (h.args.len != 2) return null;
            const net = netIn(p, h.args[0]) orelse return false;
            // A port symbol (an unnamed one-pin device) on the net past
            // every pin of it the circuit's devices hold.
            var lo: Pt = .{ .x = std.math.maxInt(i32), .y = std.math.maxInt(i32) };
            var hi: Pt = .{ .x = std.math.minInt(i32), .y = std.math.minInt(i32) };
            for (0..p.deviceCount()) |d| {
                const a, const b = p.pinRange(d);
                if (p.dev_name[d].len == 0) continue;
                for (a..b) |pin| if (p.pin_net[pin] == net) {
                    lo = .{ .x = @min(lo.x, p.pin_xy[pin].x), .y = @min(lo.y, p.pin_xy[pin].y) };
                    hi = .{ .x = @max(hi.x, p.pin_xy[pin].x), .y = @max(hi.y, p.pin_xy[pin].y) };
                };
            }
            const side = h.args[1];
            for (0..p.deviceCount()) |d| {
                const a, const b = p.pinRange(d);
                if (p.dev_name[d].len != 0 or b - a != 1 or p.pin_net[a] != net) continue;
                const at = p.dev_pos[d];
                const past = if (std.mem.eql(u8, side, "left")) at.x < lo.x else if (std.mem.eql(u8, side, "right")) at.x > hi.x else if (std.mem.eql(u8, side, "top")) at.y < lo.y else at.y > hi.y;
                if (past) return true;
            }
            return false;
        },
        .at => {
            const d = deviceIn(p, h.args[0]) orelse return false;
            var buf: [1]Pt = undefined;
            const want = scaled(h.args[1..3], unit, &buf) orelse return false;
            if (!p.dev_pos[d].eql(want[0])) return false;
            if (h.args.len == 4) if (pinned.orientWord(h.args[3])) |o| return std.meta.eql(o, p.dev_orient[d]);
            return true;
        },
        .route, .via => {
            const net = netIn(p, h.args[0]) orelse return false;
            var buf: [64]Pt = undefined;
            const pts = scaled(h.args[1..], unit, &buf) orelse return false;
            for (pts, 0..) |at, k| {
                if (!onWire(p, net, at)) return false;
                if (h.verb == .via or k == 0) continue;
                // Every point of the segment from the last one on the net.
                const prev = pts[k - 1];
                const step: Pt = .{ .x = std.math.sign(at.x - prev.x), .y = std.math.sign(at.y - prev.y) };
                var q = prev;
                while (!q.eql(at)) : (q = q.add(step)) if (!onWire(p, net, q)) return false;
            }
            return true;
        },
        else => return null,
    }
}

// ---- private ----

/// `x y` pairs of symbol units, in drawing units, into `buf`; null for a
/// malformed or too long list.
fn scaled(words: []const []const u8, unit: i32, buf: []Pt) ?[]const Pt {
    const n = words.len / 2;
    if (n == 0 or n > buf.len) return null;
    const u: f64 = @floatFromInt(unit);
    for (buf[0..n], 0..) |*q, k| {
        const x = std.fmt.parseFloat(f64, words[2 * k]) catch return null;
        const y = std.fmt.parseFloat(f64, words[2 * k + 1]) catch return null;
        if (!std.math.isFinite(x) or !std.math.isFinite(y) or @abs(x) > 1e6 or @abs(y) > 1e6) return null;
        q.* = .{ .x = @intFromFloat(@round(x * u)), .y = @intFromFloat(@round(y * u)) };
    }
    return buf[0..n];
}

fn onWire(p: *const Placed, net: u32, at: Pt) bool {
    var it = p.segments(net);
    while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
        if (Rect.fromCorners(a, b).contains(at)) return true;
    };
    return false;
}

/// Whether the named devices' pins on `net` are one piece by its wires
/// alone (names aside). ponytail: a pin against every wire end, quadratic.
fn wired(p: *const Placed, net: u32) bool {
    var buf: [256]Pt = undefined;
    var group: [256]u16 = undefined;
    var n: usize = 0;
    var it = p.segments(net);
    while (it.next()) |poly| {
        // A polyline is one piece: its points share the first one's group.
        const g: u16 = @intCast(n);
        for (poly) |at| {
            if (n == buf.len) return true; // too big to judge here: no claim
            buf[n] = at;
            group[n] = g;
            n += 1;
        }
    }
    // Pieces meeting at a point (or a point on another's run) join.
    var changed = true;
    var rounds: usize = 0;
    while (changed and rounds <= n) : (rounds += 1) {
        changed = false;
        for (0..n) |i| for (0..n) |j| {
            if (group[i] == group[j] or !(buf[i].x == buf[j].x and buf[i].y == buf[j].y)) continue;
            const gi = group[i];
            const gj = group[j];
            const lo = @min(gi, gj);
            for (group[0..n]) |*x| if (x.* == gi or x.* == gj) {
                x.* = lo;
            };
            changed = true;
        };
    }
    // One pin, or none, is joined already.
    var count: usize = 0;
    for (0..p.deviceCount()) |d| {
        if (p.dev_name[d].len == 0) continue;
        const a, const b = p.pinRange(d);
        for (a..b) |pin| count += @intFromBool(p.pin_net[pin] == net);
    }
    if (count <= 1) return true;
    var piece: ?u16 = null;
    for (0..p.deviceCount()) |d| {
        if (p.dev_name[d].len == 0) continue;
        const a, const b = p.pinRange(d);
        for (a..b) |pin| {
            if (p.pin_net[pin] != net) continue;
            const g = for (0..n) |k| {
                if (buf[k].x == p.pin_xy[pin].x and buf[k].y == p.pin_xy[pin].y) break group[k];
            } else return false;
            if (piece != null and piece.? != g) return false;
            piece = g;
        }
    }
    return true;
}

fn netIn(p: *const Placed, name: []const u8) ?u32 {
    for (p.net_name, 0..) |n, k| if (std.mem.eql(u8, n, name)) return @intCast(k);
    return null;
}

fn deviceIn(p: *const Placed, name: []const u8) ?usize {
    for (p.dev_name, 0..) |n, d| if (std.mem.eql(u8, n, name)) return d;
    return null;
}

fn isFet(nl: *const Netlist, e: u32) bool {
    return switch (nl.graph.edges.items(.kind)[e]) {
        .mosfet, .bjt, .jfet, .mesfet => true,
        else => false,
    };
}
