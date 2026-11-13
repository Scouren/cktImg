//! Routes (issue #8, stage 4): the nets no pattern of `wires.zig` drew, by
//! the maze router (`maze.zig`). In: the canvas, the waiting nets and every
//! net's pins, and the drawing's mirror if it has one. Out: their wires,
//! ports and labels.
//!
//! - A net the symmetry maps to itself: its left pins joined to each other
//!   or to the axis, the axis between the points reached (and the net's
//!   pins on it) as a spine, and the left half's mirror image.
//! - A net and its mate: the net joined, then the mate as its mirror image.
//! - Else, or where those do not fit: from the topmost (then leftmost) pin,
//!   the unjoined pin nearest a joined one next, each by the cheapest path
//!   to the net's wires. A pin with no path gets a label, and so does the
//!   first. An output's port goes out from its wires' outermost point.
//!
//! Contents:
//! - `pub const Mirror = struct { axis2: i32, net_mate: []const u32 }`
//! - `pub fn draw(c: *Canvas, waiting: []const u32, pins_of: []const std.ArrayList(u32), mirror: ?Mirror) Allocator.Error!void`
//! - `pub fn attach(c: *Canvas, net: u32, pins: []const u32, anchor: u32) Allocator.Error!void`
//! - `pub fn port(c: *Canvas, net: u32) !void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const maze = @import("maze.zig");

const Side = library.Side;
const Pt = library.Pt;
const Schematic = sch.Schematic;
const Canvas = canvas.Canvas;
const pinAt = canvas.pinAt;
const topLeft = canvas.topLeft;
const none = sch.none;

/// The drawing's mirror: twice the x of its axis, and each net's image
/// (`none` for a net with none).
pub const Mirror = struct { axis2: i32, net_mate: []const u32 };

/// Draws the `waiting` nets, in order; a mate waiting too goes with its net.
pub fn draw(c: *Canvas, waiting: []const u32, pins_of: []const std.ArrayList(u32), mirror: ?Mirror) Allocator.Error!void {
    const gpa = c.gpa;
    const done = try gpa.alloc(bool, pins_of.len);
    defer gpa.free(done);
    @memset(done, true);
    for (waiting) |net| done[net] = false;
    var failed: std.ArrayList(u32) = .empty;
    defer failed.deinit(gpa);
    for (waiting) |net| {
        if (done[net]) continue;
        done[net] = true;
        const pins = pins_of[net].items;
        assert(pins.len >= 2);
        const mate = if (mirror) |m| m.net_mate[net] else none;
        if (mate == net and try halves(c, net, pins, mirror.?)) {
            try finish(c, net, pins[0], &.{});
            continue;
        }
        const from = c.segs.items.len;
        failed.clearRetainingCapacity();
        const first = try join(c, net, pins, null, false, &failed);
        if (mate != none and mate != net and !done[mate]) {
            done[mate] = true;
            const mine = pins_of[mate].items;
            if (failed.items.len == 0 and try mirrored(c, net, mate, pins, mine, from, mirror.?.axis2)) {
                try finish(c, mate, mine[0], &.{});
            } else {
                var lost: std.ArrayList(u32) = .empty;
                defer lost.deinit(gpa);
                const f = try join(c, mate, mine, null, false, &lost);
                try finish(c, mate, mine[f], lost.items);
            }
        }
        try finish(c, net, pins[first], failed.items);
    }
}

/// Joins each of `pins` to `net`'s wires drawn so far (a pinned route),
/// the nearest first; a pin no path reaches gets a name, as does `anchor`
/// (a pin on those wires) so the names join them; then an output's port.
pub fn attach(c: *Canvas, net: u32, pins: []const u32, anchor: u32) Allocator.Error!void {
    var failed: std.ArrayList(u32) = .empty;
    defer failed.deinit(c.gpa);
    if (pins.len > 0) _ = try join(c, net, pins, null, true, &failed);
    try finish(c, net, anchor, failed.items);
}

/// An output's port out from the topmost of its wires' outermost points,
/// on the drawing's nearer side; nothing for any other net.
pub fn port(c: *Canvas, net: u32) !void {
    if (c.s.roles[net] == .output) {
        var lo: i32 = std.math.maxInt(i32);
        var hi: i32 = std.math.minInt(i32);
        for (c.segs.items) |g| if (g.net == net) {
            lo = @min(lo, @min(g.a.x, g.b.x));
            hi = @max(hi, @max(g.a.x, g.b.x));
        };
        if (lo <= hi) {
            const right = lo + hi >= c.middle2();
            const edge = if (right) hi else lo;
            var from: ?Pt = null;
            for (c.segs.items) |g| if (g.net == net) for ([_]Pt{ g.a, g.b }) |e| {
                if (e.x == edge and (from == null or e.above(from.?))) from = e;
            };
            try c.port(net, from.?, if (right) .right else .left);
        }
    }
}

// ---- private ----

/// Joins `pins` by maze, the pin nearest a joined one next; returns the
/// first pin's index (`topLeft`) and appends the pins no path reached to
/// `failed`. With `half`, every pin is routed, to the net's wires or to the
/// axis at x = `half`, never right of it; with `onto`, to the net's wires
/// already drawn (none starts the tree).
fn join(c: *Canvas, net: u32, pins: []const u32, half: ?i32, onto: bool, failed: *std.ArrayList(u32)) !usize {
    const s = c.s;
    const gpa = c.gpa;
    assert(pins.len >= 1);
    for (pins) |p| assert(s.pins.items(.net)[p] == net);
    const joined = try gpa.alloc(bool, pins.len);
    defer gpa.free(joined);
    @memset(joined, false);
    const first = topLeft(s, pins);
    if (half == null and !onto) joined[first] = true;
    const sides = s.pins.items(.side);
    var wired = onto;
    for (0..pins.len - @intFromBool(half == null and !onto)) |_| {
        var pick: ?usize = null;
        var pick_d: u32 = std.math.maxInt(u32);
        for (pins, joined, 0..) |p, j, i| if (!j) {
            const at = pinAt(s, p);
            var d = nearest(s, pins, joined, at);
            if (half) |h| d = @min(d, @abs(h - at.x));
            if (pick == null or d < pick_d or (d == pick_d and at.above(pinAt(s, pins[pick.?])))) {
                pick = i;
                pick_d = d;
            }
        };
        const i = pick.?;
        joined[i] = true;
        const to: ?maze.Pin = if (wired or half != null) null else .{ .at = pinAt(s, pins[first]), .side = sides[pins[first]] };
        const path = try maze.route(gpa, .{
            .net = net,
            .from = .{ .at = pinAt(s, pins[i]), .side = sides[pins[i]] },
            .to = to,
            .half = half,
            .boxes = c.boxes,
            .wires = c.segs.items,
            .marks = c.points.items,
            .rails = c.rails,
            // A quarter unit, and never 0: a symbol set may have a unit
            // under four.
            .step = @max(1, @divFloor(c.len.unit, 4)),
            .clear = c.len.clearance,
            .bend = c.len.bend_cost,
            .cross = c.len.cross_cost,
        }) orelse {
            try failed.append(gpa, pins[i]);
            continue;
        };
        defer gpa.free(path);
        assert(try c.commit(net, path));
        wired = true;
    }
    return first;
}

/// A net the symmetry maps to itself, drawn as its left half and that
/// half's mirror image: the left pins joined to each other or to the axis,
/// and the axis between the points reached (and the net's pins on it) as
/// a spine. False, with nothing drawn, unless every pin has its mirror
/// image or stands on the axis facing the spine, and every piece fits.
fn halves(c: *Canvas, net: u32, pins: []const u32, m: Mirror) !bool {
    const s = c.s;
    const gpa = c.gpa;
    if (@mod(m.axis2, 2) != 0) return false;
    const axis = @divExact(m.axis2, 2);
    const sides = s.pins.items(.side);
    var left: std.ArrayList(u32) = .empty;
    defer left.deinit(gpa);
    var spine: std.ArrayList(i32) = .empty;
    defer spine.deinit(gpa);
    for (pins) |p| {
        const at = pinAt(s, p);
        if (at.x == axis) {
            if (sides[p].isHorizontal()) return false;
            try spine.append(gpa, at.y);
        } else if (image(s, pins, p, m.axis2) == null) {
            return false;
        } else if (at.x < axis) {
            try left.append(gpa, p);
        }
    }
    if (left.items.len == 0) return false;
    const cp = c.save();
    var failed: std.ArrayList(u32) = .empty;
    defer failed.deinit(gpa);
    _ = try join(c, net, left.items, axis, false, &failed);
    const ok = failed.items.len == 0 and try spineAndImage(c, net, pins, cp.segs, axis, &spine);
    if (!ok) c.restore(cp);
    return ok;
}

/// The spine through the rows in `spine` and where the left half meets the
/// axis, then the left half's image; false when the net's own pins on the
/// axis do not end it or a piece does not fit.
fn spineAndImage(c: *Canvas, net: u32, pins: []const u32, from: usize, axis: i32, spine: *std.ArrayList(i32)) !bool {
    const s = c.s;
    const half = try c.gpa.dupe(maze.Wire, c.segs.items[from..]);
    defer c.gpa.free(half);
    for (half) |g| for ([_]Pt{ g.a, g.b }) |e| if (e.x == axis) try spine.append(c.gpa, e.y);
    assert(spine.items.len >= 1);
    std.mem.sort(i32, spine.items, {}, std.sort.asc(i32));
    const top = spine.items[0];
    const bottom = spine.items[spine.items.len - 1];
    // A pin on the axis faces along the spine from its end.
    for (pins) |p| {
        const at = pinAt(s, p);
        if (at.x != axis) continue;
        const end = if (s.pins.items(.side)[p] == .up) bottom else top;
        if (at.y != end) return false;
    }
    for (spine.items[0 .. spine.items.len - 1], spine.items[1..]) |y0, y1| {
        if (y0 == y1) continue;
        if (!try c.commit(net, &.{ .{ .x = axis, .y = y0 }, .{ .x = axis, .y = y1 } })) return false;
    }
    for (half) |g| {
        if (g.a.x == axis and g.b.x == axis) continue;
        if (!try c.commit(net, &.{ flip(g.a, 2 * axis), flip(g.b, 2 * axis) })) return false;
    }
    return true;
}

/// The mate drawn as the mirror image of the net's wires from segment
/// `from` on. False, with nothing drawn, unless the mate's pins are the
/// net's pins' images and every piece fits.
fn mirrored(c: *Canvas, net: u32, mate: u32, pins: []const u32, mate_pins: []const u32, from: usize, axis2: i32) !bool {
    if (pins.len != mate_pins.len) return false;
    for (mate_pins) |q| if (image(c.s, pins, q, axis2) == null) return false;
    const segs = try c.gpa.dupe(maze.Wire, c.segs.items[from..]);
    defer c.gpa.free(segs);
    const cp = c.save();
    for (segs) |g| {
        assert(g.net == net);
        if (!try c.commit(mate, &.{ flip(g.a, axis2), flip(g.b, axis2) })) {
            c.restore(cp);
            return false;
        }
    }
    return true;
}

/// An output's port out from the topmost of its wires' outermost points,
/// on the drawing's nearer side; labels at the pins in `failed` and, when
/// any, at `first`.
fn finish(c: *Canvas, net: u32, first: u32, failed: []const u32) !void {
    try port(c, net);
    if (failed.len == 0) return;
    for (failed) |p| try c.labelAt(p);
    try c.labelAt(first);
    c.s.labeled[net] = true;
}

/// The pin among `among` at `p`'s mirror image, facing the mirrored way.
fn image(s: *const Schematic, among: []const u32, p: u32, axis2: i32) ?u32 {
    const at = flip(pinAt(s, p), axis2);
    const side = s.pins.items(.side)[p].flipX();
    for (among) |q| if (pinAt(s, q).eql(at) and s.pins.items(.side)[q] == side) return q;
    return null;
}

fn flip(p: Pt, axis2: i32) Pt {
    return .{ .x = axis2 - p.x, .y = p.y };
}

/// The distance from `at` to the nearest joined pin; the largest `u32`
/// when none is.
fn nearest(s: *const Schematic, pins: []const u32, joined: []const bool, at: Pt) u32 {
    assert(pins.len == joined.len);
    var best: u32 = std.math.maxInt(u32);
    for (pins, joined) |p, j| if (j) {
        const q = pinAt(s, p);
        best = @min(best, @abs(q.x - at.x) + @abs(q.y - at.y));
    };
    return best;
}
