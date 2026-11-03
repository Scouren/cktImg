//! What every test needs from outside the library: a symbol set, and the
//! checks every drawing must pass.
//!
//! Contents:
//! - `pub const symbols: *const [N:0]u8`
//! - `pub fn library(gpa: std.mem.Allocator) !*np.Library`
//! - `pub fn freeLibrary(gpa: std.mem.Allocator, lib: *np.Library) void`
//! - `pub fn shorts(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32`
//! - `pub fn dots(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32`
//! - `pub fn expectConnected(p: *const np.Placed, lib: *const np.Library) !void`

const std = @import("std");
const np = @import("NetlistParser");

pub const symbols = @embedFile("symbols.zon");

/// The standard symbol set (`symbols.zon`), on the heap so that schematics
/// can point at it while their owner moves.
pub fn library(gpa: std.mem.Allocator) !*np.Library {
    const lib = try gpa.create(np.Library);
    errdefer gpa.destroy(lib);
    lib.* = .init(gpa);
    errdefer lib.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var diags: std.ArrayList(np.library.ZonDiagnostic) = .empty;
    try lib.loadZon(arena.allocator(), symbols, &diags);
    for (diags.items) |d| std.debug.print("symbols.zon: {s}: {s}\n", .{ d.class, @errorName(d.err) });
    if (diags.items.len > 0) return error.BadSymbols;
    return lib;
}

pub fn freeLibrary(gpa: std.mem.Allocator, lib: *np.Library) void {
    lib.deinit();
    gpa.destroy(lib);
}

/// Contacts a netlister that joins by touch (xschem) reads as shorts: a wire
/// segment of one net through or onto a point of another — a pin, a wire
/// end or bend, a label. Two nets' segments overlapping along a line
/// are among them: one holds an end of the other. Returns how many nets have
/// a wire making one; prints the first of each when `print`.
// ponytail: every segment against every point, quadratic; fine at test sizes.
pub fn shorts(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32 {
    const Point = struct { at: np.Pt, net: u32, what: []const u8 };
    var pts: std.ArrayList(Point) = .empty;
    defer pts.deinit(gpa);
    // Every pin, a MOS body past the symbol's terminals too: a target whose
    // symbol has one (xschem's) draws it at the device's origin, its point.
    for (p.pin_xy, p.pin_net) |at, n| if (n != np.placed.no_net) {
        try pts.append(gpa, .{ .at = at, .net = n, .what = "pin" });
    };
    for (p.labels) |l| try pts.append(gpa, .{ .at = l.at, .net = l.net, .what = "label" });
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        while (it.next()) |poly| for (poly) |at| try pts.append(gpa, .{ .at = at, .net = @intCast(n), .what = "wire end" });
    }
    const bad = try gpa.alloc(bool, p.netCount());
    defer gpa.free(bad);
    @memset(bad, false);
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            const r = np.Rect.fromCorners(a, b);
            for (pts.items) |q| {
                if (q.net == n or !r.contains(q.at)) continue;
                if (print and !bad[n]) std.debug.print("net {s}: wire {any}-{any} touches a {s} of net {s} at {any}\n", .{ p.net_name[n], a, b, q.what, p.net_name[q.net], q.at });
                bad[n] = true;
            }
        };
    }
    var count: u32 = 0;
    for (bad) |b| count += @intFromBool(b);
    return count;
}

/// Dots where a net's wires meet, and nowhere else: a point where one net
/// leaves in three directions or more carries a dot, every dot is such a
/// point, and no net crosses itself where none is (a crossing without a dot
/// reads as two nets). At each of a net's wire points and pins, every wire
/// ending there is one direction, a wire running through it two, and a pin's
/// lead toward its device one. Returns how many points break this; prints
/// each when `print`. A four-way junction with its dot is fine: the book draws
/// them (an op-amp's output node).
// ponytail: every point against every segment of its net, quadratic; fine at test sizes.
pub fn dots(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32 {
    var bad: u32 = 0;
    var pts: std.ArrayList(np.Pt) = .empty;
    defer pts.deinit(gpa);
    var met: std.ArrayList(np.Pt) = .empty;
    defer met.deinit(gpa);
    for (0..p.netCount()) |n| {
        pts.clearRetainingCapacity();
        var it = p.segments(n);
        while (it.next()) |poly| try pts.appendSlice(gpa, poly);
        for (p.pin_xy, p.pin_net) |at, pn| if (pn == n) try pts.append(gpa, at);
        for (pts.items, 0..) |at, i| {
            // Each point once.
            const seen = for (pts.items[0..i]) |q| {
                if (q.x == at.x and q.y == at.y) break true;
            } else false;
            if (seen) continue;
            var dirs: [4]bool = @splat(false); // left, right, up, down
            var segs = p.segments(n);
            while (segs.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (!np.Rect.fromCorners(a, b).contains(at)) continue;
                const lo = if (a.x < b.x or a.y < b.y) a else b;
                const hi = if (lo.x == a.x and lo.y == a.y) b else a;
                if (!(at.x == lo.x and at.y == lo.y)) dirs[if (a.y == b.y) 0 else 2] = true;
                if (!(at.x == hi.x and at.y == hi.y)) dirs[if (a.y == b.y) 1 else 3] = true;
            };
            for (0..p.deviceCount()) |d| {
                const lo, const hi = p.pinRange(d);
                for (lo..hi) |pin| {
                    if (p.pin_net[pin] != n or !(p.pin_xy[pin].x == at.x and p.pin_xy[pin].y == at.y)) continue;
                    // The lead runs from the pin toward the device's origin,
                    // along the axis it is farther along; a pin at the origin
                    // (a MOS body drawn on its symbol) has none.
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
            if (print) std.debug.print("net {s}: {d} arms at {any}, {s}\n", .{ p.net_name[n], arms, at, if (dot) "a dot" else "no dot" });
            bad += 1;
        }
        // Crossings of the net with itself, away from its points.
        met.clearRetainingCapacity();
        var outer = p.segments(n);
        while (outer.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            if (a.y != b.y) continue;
            var inner = p.segments(n);
            while (inner.next()) |q| for (q[0 .. q.len - 1], q[1..]) |c, d| {
                if (c.x != d.x) continue;
                const x = c.x;
                const y = a.y;
                if (x <= @min(a.x, b.x) or x >= @max(a.x, b.x) or y <= @min(c.y, d.y) or y >= @max(c.y, d.y)) continue;
                if (print) std.debug.print("net {s}: crosses itself at {any}\n", .{ p.net_name[n], np.Pt{ .x = x, .y = y } });
                bad += 1;
            };
        };
    }
    for (p.junctions, 0..) |j, i| for (p.junctions[i + 1 ..]) |k| {
        if (j.x == k.x and j.y == k.y) bad += 1;
    };
    return bad;
}

/// Every net is one piece, read the way a netlister reads the JSON: wires
/// meet only at their ends (`Placed` splits a wire wherever another of its
/// net meets it), a pin joins the wire ending on it, a label the wire it
/// lies on, and the net's labels and one-pin symbols (ports, rails) are
/// joined by their name.
/// Stronger than `expectWellFormed`: a wire stub ending in the open, or two
/// unnamed pieces, fails here.
pub fn expectConnected(p: *const np.Placed, lib: *const np.Library) !void {
    // Its own scratch, so the fuzzer (no test runner) checks with it too.
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();
    var index: std.AutoHashMapUnmanaged([2]i32, u32) = .empty;
    defer index.deinit(gpa);
    var parent: std.ArrayList(u32) = .empty;
    defer parent.deinit(gpa);
    const uf = struct {
        fn find(par: []u32, x0: u32) u32 {
            var x = x0;
            while (par[x] != x) x = par[x];
            return x;
        }
        fn node(g: std.mem.Allocator, idx: *std.AutoHashMapUnmanaged([2]i32, u32), par: *std.ArrayList(u32), at: np.Pt) !u32 {
            const gop = try idx.getOrPut(g, .{ at.x, at.y });
            if (!gop.found_existing) {
                gop.value_ptr.* = @intCast(par.items.len);
                try par.append(g, gop.value_ptr.*);
            }
            return gop.value_ptr.*;
        }
        fn join(par: []u32, a: u32, b: u32) void {
            par[find(par, a)] = find(par, b);
        }
    };
    for (0..p.netCount()) |n| {
        index.clearRetainingCapacity();
        parent.clearRetainingCapacity();
        try parent.append(gpa, 0); // node 0: the net's name
        var it = p.segments(n);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            const ia = try uf.node(gpa, &index, &parent, a);
            const ib = try uf.node(gpa, &index, &parent, b);
            uf.join(parent.items, ia, ib);
        };
        for (p.labels) |l| if (l.net == n) {
            const at = try uf.node(gpa, &index, &parent, l.at);
            uf.join(parent.items, at, 0);
            // A name written on a wire (an annotation) names the wire.
            var on = p.segments(n);
            while (on.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
                if (np.Rect.fromCorners(a, b).contains(l.at)) uf.join(parent.items, at, index.get(.{ a.x, a.y }).?);
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
                const at = try uf.node(gpa, &index, &parent, p.pin_xy[pin]);
                // A port or rail symbol names its net; a ground_ref pin may
                // be left unwired on ground (O0), its symbol naming it.
                if (hi - lo == 1 or t.ground_ref) uf.join(parent.items, at, 0);
            }
        }
        if (pins < 2) continue;
        // Distinct pieces among the points (the name node counts only
        // through what it joins).
        var roots: u32 = 0;
        for (1..parent.items.len) |i| {
            const r = uf.find(parent.items, @intCast(i));
            const first = for (1..i) |j| {
                if (uf.find(parent.items, @intCast(j)) == r) break false;
            } else true;
            roots += @intFromBool(first);
        }
        if (roots != 1) {
            std.debug.print("net {s} is in {d} pieces\n", .{ p.net_name[n], roots });
            return error.SplitNet;
        }
    }
}
