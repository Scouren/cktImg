//! The trunk pattern (issue #8, stage 4): one net with no symbol of its own
//! as a trunk along a row, or down a column, with each pin brought to it,
//! or a column's pins joined in order. In: the canvas, the net and its
//! pins, placed. Out: the net's wires on the canvas (an output's or an
//! input's port too), or nothing drawn when no track fits.
//!
//! Human Rules:
//! - trunk.1 (unmeasured) Pins all in one column, each facing up or down,
//!   are joined in order down that column. `draw`
//! - trunk.2 (habit) Of the tracks that fit, a net takes the one whose
//!   wire costs least, as the router counts a path (maze.2): its length,
//!   plus `bend_cost` a corner (a point the wire leaves exactly two ways
//!   at a right angle; a T, a crossing of its own and a straight joint
//!   are none), plus `cross_cost` each crossing of another net's wire
//!   drawn so far, a quarter of it for a rail's. People draw a net at the
//!   fewest corners its pins allow in 93.8% of the nets, and a net's wire
//!   crosses no other net's in 33,360 of 37,990 nets that are no rail
//!   (5,263 hand-drawn schematics). `cost`
//! - trunk.3 (invariant) No wire of a trunk has a spur: a track on which
//!   two pins' ways run on together past where they meet is never taken.
//!   `corners`
//! - trunk.4 (habit) The rows a trunk tries first, and keeps on a tie, are
//!   those of its pins facing sideways, nearest the tap row first: such a
//!   pin joins the trunk straight. People: a level wire runs along the
//!   row of a gate standing between a pin facing down and a pin facing up
//!   in 3,898 of 3,955 such nets (5,263 hand-drawn schematics).
//!   `levelRows`
//! - trunk.5 (habit) A level trunk stands `tap` (half a unit) out from the
//!   tips of the pins facing up or down that it joins: under the lowest
//!   facing down, over the highest facing up (midway where they stand two
//!   taps apart), and half a `tap` out only where neither row has room.
//!   People: a level wire past two pins or more facing one way stands
//!   half a unit out in 729 of 1,404 nets and a quarter in 76; between a
//!   pin facing down and one facing up it stands off both tips in 9,466
//!   of 11,252, midway in 5,134 (5,263 hand-drawn schematics). `tapRows`
//! - trunk.6 (choice) The rows tried after those, in order: `tap` under
//!   the pins facing down, `tap` over those facing up, half a `tap` each
//!   way; half a unit past the pins' devices, the side away from the
//!   drawing's middle first (a gate line over the top row's gates, under
//!   the bottom's); the first on a tie: a fixed order, so the cards'
//!   order chooses nothing. `draw`
//! - trunk.7 (book) Two pins facing each other along a row (a mirror's
//!   gates) are joined straight first, a gate line, and its middle
//!   brought to the trunk, as the book draws it. A track on the pins' own
//!   row needs no separate rung; that does not rule out a rung on the
//!   remaining bounded tracks. AMS401's source resistor/gate approach
//!   stays straight while a lower trunk reaches its feedback capacitor.
//!   Keep a midpoint that passes corner, obstacle and free-end checks;
//!   otherwise cost both adjacent quarter-unit taps, strictly inside the
//!   pair, through the same checks. AG981/984/986 have straight source
//!   gate lines whose native midpoint meets another wire. Alternatives
//!   keep the first on an exact cost tie; reflection is not universal.
//!   A displaced full-row tap leaves the original half rows available;
//!   only an accepted midpoint with any required free end rules them out.
//!   `trunkLines`, `draw`
//! - trunk.8 (unmeasured) A pin comes to its trunk straight when it faces
//!   it; out half a unit and along when it faces sideways; round its own
//!   device, through the channel on its right, when it faces away.
//!   Only when every original track fails for a named part, retry its
//!   sideways-pin rows without artificial half-unit approach vertices.
//!   AG2365 then keeps a proper foreign-wire crossing. Existing tracks,
//!   ports, departure checks and forbidden contacts retain precedence.
//!   `wayTo`
//! - trunk.9 (choice) A net of at most 12 pins may run its trunk upright,
//!   where that costs less: down the column of a pin facing up or down,
//!   midway between two neighbouring pins, or half a unit either side of
//!   a pin, each kind nearest the pins' middle first, then nearest the
//!   drawing's middle: the bound keeps the search small. `uprightColumns`
//!   Narrowing: only for a net with no port or name on its wire.
//! - trunk.10 (order: signal) A port or a name leaves a trunk from its
//!   free end, the left (where the signal enters) before the right; an
//!   end some pin of the net stands beyond is not free. `freeEnd`
//! - trunk.11 (choice) An input or a bias whose trunk has no free end for
//!   its port is not drawn as one trunk; a part of a net joined by name
//!   with none carries its name at its top-left pin, so card order
//!   chooses nothing. `draw`
//! - trunk.12 (unmeasured) An output's port leaves from the outer end of
//!   its trunk, or of its column at its tap, on the drawing's nearer
//!   side: the right when the trunk's right end reaches the drawing's
//!   middle; a lone pin's port leaves from the pin. `draw`
//! - trunk.13 (habit) A pin is an end of its wire, which leaves it the way
//!   the pin faces: no track runs through the tip of a pin facing across
//!   it or turns on one, and the wire branches off its pins. People:
//!   87,922 of 93,770 pins of wired nets that are no rail (5,263
//!   hand-drawn schematics). `corners`
//! - trunk.14 (habit) A bias's wire crosses no other net's (a rail's
//!   aside): a track that would is not taken, and a part no track fits
//!   ends in ports (wires.13). People: 3,926 of 4,080 wired bias nets
//!   (5,263 hand-drawn schematics). `cost`
//! - trunk.16 (invariant) A trunk's lines close no loop (wire_tree.1): a
//!   track on which one pin's way runs through another's, or through the
//!   trunk, and on to it is never taken. Before, 36 of the engine's
//!   drawings of the 5,274 corpus decks held a net in a loop, AMS385's
//!   input and AG2449's `vea` among them. `drawPreferred`
//!
//! - trunk.15 (choice, bounded) A complete complementary-mirror CT stage
//!   may nominate one actual opposing gate interval (ct_mirror_controls.1).
//!   Only an exact tie after full length, corner, crossing, obstacle and
//!   free-end checks prefers candidate ink covering that interval. Every
//!   cheaper legal candidate wins; null preserves the original tie order.
//!
//! Contents:
//! - `pub const End = enum { port, name }`
//! - `pub inline fn draw(c: *Canvas, net: u32, pins: []const u32, end: End) Allocator.Error!bool`
//! - `pub fn drawPreferred(c: *Canvas, net: u32, pins: []const u32, end: End, preferred: ?[2]Pt) Allocator.Error!bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const wire_tree = @import("wire_tree.zig");

const Pt = library.Pt;
const Side = library.Side;
const Schematic = sch.Schematic;
const Canvas = canvas.Canvas;
const Line = canvas.Line;
const crosses = canvas.crosses;
const linesFit = canvas.linesFit;
const pinAt = canvas.pinAt;
const stepPt = canvas.stepPt;

/// What the wire's free end carries.
pub const End = enum {
    /// By the net's role: an output's or an input's port, else nothing.
    port,
    /// The net's name: `pins` are one part of a net joined by name.
    name,
};

/// The most pins of a net an upright trunk is tried for: four columns a
/// pin, each a full set of lines, so the search stays small.
const upright_pins_max = 12;

/// Columns by how near they stand to the middle of a net's pins (twice it,
/// `box2`), then to the drawing's middle, then left first.
const Nearest = struct {
    box2: i32,
    middle2: i32,

    fn lt(o: Nearest, a: i32, b: i32) bool {
        if (@abs(2 * a - o.box2) != @abs(2 * b - o.box2)) return @abs(2 * a - o.box2) < @abs(2 * b - o.box2);
        if (@abs(2 * a - o.middle2) != @abs(2 * b - o.middle2)) return @abs(2 * a - o.middle2) < @abs(2 * b - o.middle2);
        return a < b;
    }
};

/// How a net's pins are brought to one line.
const Lay = enum {
    /// One column's pins joined in order: an upright trunk through them,
    /// each pin on it already.
    column,
    /// A level trunk, two pins facing each other along a row off it joined
    /// straight first (a gate line) and the line's middle brought to it.
    rungs,
    /// A level trunk, each pin on its own way to it.
    level,
    /// An upright trunk: `level` mirrored about the diagonal.
    upright,
    /// Last resort for a named part: sideways pins already on the row
    /// contribute their actual points, with no artificial approach split.
    row,
};

/// A net with no symbol of its own: one column's pins joined in order, or
/// each pin brought to a trunk, the cheapest track that fits. An output also
/// gets a port at the trunk's outer end; with `end` `.name` (two pins or
/// more) the wire carries the net's name on a stub from a free end. False,
/// with nothing drawn, when the lines would touch another net's point or
/// run through a device.
pub inline fn draw(c: *Canvas, net: u32, pins: []const u32, end: End) Allocator.Error!bool {
    return drawPreferred(c, net, pins, end, null);
}

/// Draws the least-cost legal trunk, preferring the nominated actual
/// horizontal interval only on an exact full-cost tie. Null keeps the
/// ordinary first-on-tie policy. The caller owns and validates the pair;
/// no candidate may bypass the normal obstacle or free-end checks.
pub fn drawPreferred(c: *Canvas, net: u32, pins: []const u32, end: End, preferred: ?[2]Pt) Allocator.Error!bool {
    const s = c.s;
    assert(pins.len >= 1);
    assert(end == .port or pins.len >= 2);
    for (pins) |p| assert(s.pins.items(.net)[p] == net);
    // A lone pin has nothing to join: an output's gets its port.
    if (pins.len == 1) {
        if (s.roles[net] == .output) try c.port(net, pinAt(s, pins[0]), s.pins.items(.side)[pins[0]]);
        return true;
    }
    var lines: std.ArrayList(Line) = .empty;
    defer lines.deinit(c.gpa);
    var tried: std.ArrayList(Line) = .empty;
    defer tried.deinit(c.gpa);
    const column = sameX(s, pins);
    const role = s.roles[net];
    // An input's port and a part's name go out from a free end of the wire.
    const reach = if (end == .name) c.len.label else c.len.terminal;
    const ended = end == .name or role == .input;
    const needs_end = role == .input and end == .port or role == .bias and end == .name;
    // A trunk takes, of the tracks no other net's wire or point is on, the
    // one whose lines cost the least (`cost`), the first of them on a tie:
    // the row of a pin facing sideways (it joins straight); a tap out from
    // the pins facing down, then from those facing up, and half a tap only
    // where neither has room; a half gap past its pins' devices, away from
    // the drawing's middle first (a gate line over the top row's gates,
    // under the bottom's). No row through the tip of a pin facing up or
    // down: a pin is an end of its wire (`corners`).
    const taps = tapRows(s, pins, c.len.tap);
    const tap = taps[0];
    const past = pastDevices(c, pins);
    const tracks = try c.gpa.alloc(i32, pins.len + 6);
    defer c.gpa.free(tracks);
    const level = levelRows(s, pins, tap, tracks[0..pins.len]);
    @memcpy(tracks[level..][0..6], &[_]i32{ taps[1], taps[2], taps[3], taps[4], past[0], past[1] });
    // An upright trunk's columns: of a pin facing up or down (the link
    // between two devices of a column, a gate a straight stub to it), midway
    // between two pins, a half gap either side of a pin.
    // ponytail: only for a net with no port or name on its wire; the stub's
    // place on an upright trunk when outputs should have one too.
    var columns: [4 * upright_pins_max]i32 = undefined;
    const uprights: []const i32 = if (!column and !ended and role != .output and pins.len <= upright_pins_max) uprightColumns(s, pins, @divFloor(c.len.unit, 2), c.middle2(), &columns) else &.{};
    var lo: i32 = 0;
    var hi: i32 = 0;
    var y_t = tap;
    var free: ?Side = null;
    var fewest: i64 = std.math.maxInt(i64);
    var best_straight = false;
    // A column has one way to be drawn. Else facing gates joined by a gate
    // line first (a mirror's, as the book draws it), then every pin on its
    // own way to the trunk; then an upright trunk, where it costs less
    // still.
    const lays: []const Lay = if (column) &.{.column} else &.{ .rungs, .level, .upright, .row };
    for (lays) |lay| {
        if (lay == .row and (end != .name or fewest != std.math.maxInt(i64))) continue;
        const among = switch (lay) {
            .column => taps[0..1],
            .rungs, .level => tracks[0 .. level + 6],
            .upright => uprights,
            .row => tracks[0..level],
        };
        const rows = lay == .rungs or lay == .level;
        // Whether a row a tap out from the pins has room.
        var tapped = false;
        for (among, 0..) |track, k| {
            const tap_row = rows and k >= level and k < level + 2;
            if (rows and k >= level + 2 and k < level + 4 and tapped) continue;
            const q: i32 = @max(1, @divFloor(c.len.unit, 4));
            const offsets = [_]i32{ 0, -q, q };
            for (offsets[0..if (lay == .rungs) 3 else 1]) |tap_dx| {
                tried.clearRetainingCapacity();
                var t_lo: i32 = std.math.maxInt(i32);
                var t_hi: i32 = std.math.minInt(i32);
                const drawn = try trunkLines(c.gpa, s, pins, track, c.len.unit, lay, tap_dx, &tried, &t_lo, &t_hi);
                if (lay == .rungs and !drawn) {
                    if (tap_dx == 0) break;
                    continue;
                }
                // Rungs need full corner checks even when too costly:
                // cost pruning alone must not replace a legal midpoint.
                const count = cost(c, net, pins, tried.items, if (tap_row or lay == .rungs) std.math.maxInt(i64) else if (preferred != null) fewest +| 1 else fewest);
                if (lay != .rungs and !tap_row and (if (preferred != null) count > fewest else count >= fewest)) continue;
                if (count == std.math.maxInt(i64) or !linesFit(c, net, tried.items)) continue;
                if (try loops(c.gpa, tried.items)) continue;
                // An upright trunk has no end to mark: its ends are not read.
                const t_free = if (ended) freeEnd(c, net, pins, t_lo, t_hi, track, reach) else null;
                if (needs_end and t_free == null) continue;
                tapped = tapped or (tap_row and tap_dx == 0);
                const straight = count <= fewest and (if (preferred) |pair| straightInterval(pair, tried.items) else false);
                if (count < fewest or (count == fewest and straight and !best_straight)) {
                    best_straight = straight;
                    std.mem.swap(std.ArrayList(Line), &lines, &tried);
                    lo = t_lo;
                    hi = t_hi;
                    y_t = track;
                    free = t_free;
                    fewest = count;
                }
                if (tap_dx == 0) break;
            }
        }
    }
    // No track fits; or an input or a bias has room at neither end of any,
    // and is not wired: each pin gets a port.
    if (fewest == std.math.maxInt(i64)) return false;
    for (lines.items) |*l| assert(try c.commit(net, l.slice()));
    if (end == .port and role != .output and role != .input) return true;
    // What the wire carries goes out from an end of it: a name or an
    // input's port from the free end found; an output's port from the outer
    // end of the trunk, or of the column at its tap, on the drawing's nearer
    // side. Nearer is narrower here than in `routes.port`, which sets the
    // wire's middle against the drawing's: a trunk whose right end reaches
    // the drawing's middle leaves right.
    // A `port` line asking left or right takes that end.
    const asked: ?Side = if (c.port_side.len > 0) c.port_side[net] else null;
    const side: Side = free orelse if (end == .name) return nameOnPin(c, pins) else if (asked != null and asked.?.isHorizontal()) asked.? else if (2 * hi >= c.middle2()) .right else .left;
    const from: Pt = .{ .x = if (side == .right) hi else lo, .y = y_t };
    if (end == .port) {
        try c.port(net, from, side);
        return true;
    }
    // A bias net's name is a port, as people draw it.
    return try c.stub(if (role == .bias) .terminal else .label, net, from, side, reach) or try nameOnPin(c, pins);
}

// ---- private ----

// Cover exactly the nominated interval by candidate ink, never labels.
fn straightInterval(pair: [2]Pt, lines: []const Line) bool {
    const a, const b = .{ pair[0], pair[1] };
    assert(a.y == b.y and a.x < b.x);
    var reached = a.x;
    for (0..lines.len * 5 + 1) |_| {
        const before = reached;
        for (lines) |*line| {
            const pts = line.slice();
            for (pts[0 .. pts.len - 1], pts[1..]) |u, v| {
                if (u.y != a.y or v.y != a.y) continue;
                if (@min(u.x, v.x) <= reached and @max(u.x, v.x) > reached)
                    reached = @max(u.x, v.x);
            }
        }
        if (reached >= b.x) return true;
        if (reached == before) break;
    }
    return false;
}

/// The part's name at its top-left pin, by place, so card order changes
/// nothing: the wire has no free end to carry it.
fn nameOnPin(c: *Canvas, pins: []const u32) !bool {
    try c.labelAt(pins[canvas.topLeft(c.s, pins)]);
    return true;
}

/// The free end of a level trunk a port or a name goes out from: the left,
/// where the signal enters, before the right; an end no pin of the net
/// stands beyond (the stub would run back along the wire). Null when
/// neither end has room.
fn freeEnd(c: *const Canvas, net: u32, pins: []const u32, lo: i32, hi: i32, y_t: i32, reach: i32) ?Side {
    assert(lo <= hi);
    for ([_]Side{ .left, .right }) |side| {
        const from: Pt = .{ .x = if (side == .right) hi else lo, .y = y_t };
        const beyond = for (pins) |p| {
            if (if (side == .right) pinAt(c.s, p).x > hi else pinAt(c.s, p).x < lo) break true;
        } else false;
        if (!beyond and c.fits(net, from, stepPt(from, side, reach))) return side;
    }
    return null;
}

/// What `net`'s lines cost, as the router counts a path (`maze.route`):
/// their length, `bend_cost` a corner, and `cross_cost` each crossing of
/// another net's wire drawn so far, a quarter of it for a rail's; more
/// than any track costs when a line ends on nothing or a pin is no end of
/// the wire (`corners`). `under` is the cost to beat: at that length or
/// more the length alone is returned. People: a net's wire crosses no
/// other net's in 33,360 of 37,990 nets that are no rail (5,263
/// hand-drawn schematics).
fn cost(c: *const Canvas, net: u32, pins: []const u32, lines: []const Line, under: i64) i64 {
    var total: i64 = 0;
    for (lines) |*l| {
        const pts = l.slice();
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| total += @abs(a.x - b.x) + @abs(a.y - b.y);
    }
    // No cheaper than the track in hand: corners and crossings only add.
    if (total >= under) return total;
    total += @as(i64, c.len.bend_cost) * (corners(c.s, pins, lines) orelse return std.math.maxInt(i64));
    // A bias ends in ports instead (trunk.14).
    const bias = c.s.roles[net] == .bias;
    for (lines) |*l| {
        const pts = l.slice();
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| for (c.segs.items) |g| {
            if (g.net == net or !crosses(a, b, g.a, g.b)) continue;
            if (bias and !c.rails[g.net]) return std.math.maxInt(i64);
            total += if (c.rails[g.net]) @divFloor(c.len.cross_cost, 4) else c.len.cross_cost;
        };
    }
    return total;
}

/// Whether `lines` close a loop (trunk.16).
fn loops(gpa: Allocator, lines: []const Line) Allocator.Error!bool {
    var segs: std.ArrayList([2]Pt) = .empty;
    defer segs.deinit(gpa);
    for (lines) |*l| {
        const pts = l.slice();
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| try segs.append(gpa, .{ a, b });
    }
    return wire_tree.cyclic(gpa, segs.items);
}

/// The corners of a net's lines as a reader counts them: the points its
/// wire leaves exactly two ways at a right angle, a pin's device one of
/// the ways. A T, a crossing of its own and a straight joint are none.
/// Null when a line ends on nothing (two pins' ways to the trunk run
/// together past where they meet, a spur no wire should have), or when a
/// pin is no end of the wire: the wire leaves a pin one way, the way the
/// pin faces, and branches off it. People: 87,922 of 93,770 pins of wired
/// nets that are no rail in 5,263 hand-drawn schematics.
fn corners(s: *const Schematic, pins: []const u32, lines: []const Line) ?u32 {
    for (pins) |p| {
        // Straight through the pin's point: its device one way, the wire on.
        const straight: u4 = if (s.pins.items(.side)[p].isHorizontal()) 0b0011 else 0b1100;
        if (canvas.ways(s, pins, lines, pinAt(s, p)) != straight) return null;
    }
    var count: u32 = 0;
    for (lines, 0..) |*l, li| for (l.slice(), 0..) |p, pi| {
        // Each point once, where it first stands.
        const seen = seen: for (lines[0 .. li + 1], 0..) |*m, mi| {
            const pts = m.slice();
            for (pts[0..if (mi == li) pi else pts.len]) |o| if (o.eql(p)) break :seen true;
        } else false;
        if (seen) continue;
        // The ways out: bits 0 and 1 along the row, 2 and 3 along the column.
        const arms = canvas.ways(s, pins, lines, p);
        if (@popCount(arms) < 2) return null;
        count += @intFromBool(@popCount(arms) == 2 and arms & 3 != 0 and arms & 12 != 0);
    };
    return count;
}

/// The columns tried for an upright trunk, into `out`, in the order tried:
/// each pin's facing up or down (it joins straight), midway between each
/// two neighbours, `half` either side of each pin. Within each kind the
/// column nearest the middle of the pins first, then the one nearer the
/// drawing's middle (twice it, `middle2`), so neither the order of the
/// cards nor a mirror image chooses another.
fn uprightColumns(s: *const Schematic, pins: []const u32, half: i32, middle2: i32, out: []i32) []const i32 {
    assert(pins.len >= 2 and out.len >= 4 * pins.len);
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    for (pins) |p| {
        lo = @min(lo, pinAt(s, p).x);
        hi = @max(hi, pinAt(s, p).x);
    }
    const order: Nearest = .{ .box2 = lo + hi, .middle2 = middle2 };
    const sides = s.pins.items(.side);
    var n: usize = 0;
    for (0..3) |kind| {
        const from = n;
        for (pins) |p| {
            const x = pinAt(s, p).x;
            switch (kind) {
                // On a pin facing up or down.
                0 => if (!sides[p].isHorizontal()) {
                    out[n] = x;
                    n += 1;
                },
                // Midway to its neighbour along x: the nearest pin on its right.
                1 => {
                    var next: ?i32 = null;
                    for (pins) |o| {
                        const ox = pinAt(s, o).x;
                        if (ox > x and (next == null or ox < next.?)) next = ox;
                    }
                    out[n] = @divFloor(x + (next orelse continue), 2);
                    n += 1;
                },
                else => {
                    out[n..][0..2].* = .{ x - half, x + half };
                    n += 2;
                },
            }
        }
        std.sort.insertion(i32, out[from..n], order, Nearest.lt);
    }
    return out[0..n];
}

/// The lines of one trunk on track `t` (a row; a column when `lay` is
/// `upright`), into the empty `lines`: each pin brought to the trunk and the
/// trunk across them; `lo`, `hi` its ends along it. A `column` stands at its
/// pins' x whatever `t`, `lo` and `hi` that x. Whether a gate line was drawn
/// (`rungs` only). `tap_dx` shifts each paired midpoint by at most one
/// quarter unit; false if any shifted tap would reach a pin or pass it.
fn trunkLines(gpa: Allocator, s: *const Schematic, pins: []const u32, t: i32, gap: i32, lay: Lay, tap_dx: i32, lines: *std.ArrayList(Line), lo: *i32, hi: *i32) !bool {
    assert(lines.items.len == 0);
    const q: i32 = @max(1, @divFloor(gap, 4));
    assert(tap_dx >= -q and tap_dx <= q);
    assert(lay == .rungs or tap_dx == 0);
    var ends: std.ArrayList(i32) = .empty;
    defer ends.deinit(gpa);
    const paired = try gpa.alloc(bool, pins.len);
    defer gpa.free(paired);
    @memset(paired, false);
    const sides = s.pins.items(.side);
    if (lay == .rungs) {
        // From the right, then the top: the pin nearest one facing back
        // takes it, whatever the order of the cards.
        const from_right = try gpa.alloc(usize, pins.len);
        defer gpa.free(from_right);
        for (from_right, 0..) |*o, i| o.* = i;
        const ByPlace = struct {
            s: *const Schematic,
            pins: []const u32,
            fn lt(ctx: @This(), x: usize, y: usize) bool {
                const a = pinAt(ctx.s, ctx.pins[x]);
                const b = pinAt(ctx.s, ctx.pins[y]);
                return a.x > b.x or (a.x == b.x and a.y < b.y);
            }
        };
        std.sort.insertion(usize, from_right, ByPlace{ .s = s, .pins = pins }, ByPlace.lt);
        for (from_right) |i| {
            const p = pins[i];
            const a = pinAt(s, p);
            if (sides[p] != .right or a.y == t) continue;
            // The nearest pin facing back along the row.
            var best: ?usize = null;
            for (pins, 0..) |o, j| {
                const b = pinAt(s, o);
                if (sides[o] != .left or paired[j] or b.y != a.y or b.x <= a.x) continue;
                if (best == null or b.x < pinAt(s, pins[best.?]).x) best = j;
            }
            const j = best orelse continue;
            const b = pinAt(s, pins[j]);
            // The middle, on the quarter-unit grid; a line too short has none.
            var mid: Pt = .{ .x = a.x + @divFloor(@divFloor(b.x - a.x, 2), q) * q, .y = a.y };
            if (mid.x == a.x) continue;
            mid.x += tap_dx;
            if (mid.x <= a.x or mid.x >= b.x) return false;
            paired[i] = true;
            paired[j] = true;
            try lines.append(gpa, .of(&.{ a, mid }));
            try lines.append(gpa, .of(&.{ mid, b }));
            try lines.append(gpa, .of(&.{ mid, .{ .x = mid.x, .y = t } }));
            try ends.append(gpa, mid.x);
            lo.* = @min(lo.*, mid.x);
            hi.* = @max(hi.*, mid.x);
        }
    }
    // The rest in the trunk's own frame, where it runs level: an upright
    // trunk's pins mirrored about the diagonal, and its lines back. A
    // column is an upright trunk through its pins, each on it already.
    const upright = lay == .upright or lay == .column;
    const y = if (lay == .column) pinAt(s, pins[0]).x else t;
    for (pins, paired) |p, done| {
        if (done) continue;
        const at = pinAt(s, p);
        const line: Line = switch (lay) {
            .column => .of(&.{at.transposed()}),
            .upright => wayTo(at.transposed(), sides[p].transposed(), t, gap),
            .rungs, .level => wayTo(at, sides[p], t, gap),
            .row => if (at.y == t and sides[p].isHorizontal()) .of(&.{at}) else wayTo(at, sides[p], t, gap),
        };
        // A pin on the trunk already needs no line of its own.
        if (line.len >= 2) try lines.append(gpa, line);
        const end = line.pts[line.len - 1];
        assert(end.y == y);
        try ends.append(gpa, end.x);
        lo.* = @min(lo.*, end.x);
        hi.* = @max(hi.*, end.x);
    }
    // The trunk in pieces between the ends, so every joint is a wire's end.
    std.sort.heap(i32, ends.items, {}, std.sort.asc(i32));
    for (ends.items[0 .. ends.items.len - 1], ends.items[1..]) |a, b| {
        if (a != b) try lines.append(gpa, .of(&.{ .{ .x = a, .y = y }, .{ .x = b, .y = y } }));
    }
    if (upright) for (lines.items) |*l| for (l.pts[0..l.len]) |*pt| {
        pt.* = pt.transposed();
    };
    // A column's port goes out sideways from it, at its tap.
    if (lay == .column) {
        lo.* = y;
        hi.* = y;
    }
    return std.mem.indexOfScalar(bool, paired, true) != null;
}

/// A half gap over the top of the pins' devices and under their bottom,
/// the one farther from the drawing's middle first.
fn pastDevices(c: *const Canvas, pins: []const u32) [2]i32 {
    var top: i32 = std.math.maxInt(i32);
    var bottom: i32 = std.math.minInt(i32);
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    for (c.boxes) |b| {
        lo = @min(lo, b.min.y);
        hi = @max(hi, b.max.y);
        for (pins) |p| if (b.contains(pinAt(c.s, p))) {
            top = @min(top, b.min.y);
            bottom = @max(bottom, b.max.y);
        };
    }
    if (top > bottom) return .{ pinAt(c.s, pins[0]).y, pinAt(c.s, pins[0]).y };
    const half = @divFloor(c.len.unit, 2);
    const over = top - half;
    const under = bottom + half;
    return if (top + bottom < lo + hi) .{ over, under } else .{ under, over };
}

/// The rows of the pins facing sideways, each once, nearest `tap` first
/// (the upper of two as near), into `out`; how many. A trunk along such a
/// row joins that pin straight: people run a level wire along the row of
/// a gate standing between a pin facing down and a pin facing up in 3,898
/// of 3,955 such nets (5,263 hand-drawn schematics).
fn levelRows(s: *const Schematic, pins: []const u32, tap: i32, out: []i32) usize {
    assert(out.len >= pins.len);
    var n: usize = 0;
    for (pins) |p| {
        const y = pinAt(s, p).y;
        if (!s.pins.items(.side)[p].isHorizontal() or std.mem.indexOfScalar(i32, out[0..n], y) != null) continue;
        out[n] = y;
        n += 1;
    }
    std.sort.insertion(i32, out[0..n], tap, struct {
        fn lt(t: i32, a: i32, b: i32) bool {
            return if (@abs(a - t) != @abs(b - t)) @abs(a - t) < @abs(b - t) else a < b;
        }
    }.lt);
    assert(n <= pins.len);
    return n;
}

/// Where a level trunk stands off the tips of the pins facing up or down.
/// First the net's tap row: between the lowest pin facing down and the
/// highest facing up, `gap` past the pins when they face one way, the
/// topmost pin's row when none faces up or down. Then the rows tried:
/// `gap` under the lowest pin facing down, `gap` over the highest facing
/// up, and half of `gap` each way (the tap row for a way no pin faces).
/// People: a level wire past two pins or more facing one way stands half a
/// unit out in 729 of 1,404 nets and a quarter in 76; between a pin facing
/// down and one facing up it stands off both tips in 9,466 of 11,252
/// (5,263 hand-drawn schematics).
fn tapRows(s: *const Schematic, pins: []const u32, gap: i32) [5]i32 {
    assert(pins.len >= 1);
    assert(gap > 0);
    var down: ?i32 = null;
    var up: ?i32 = null;
    var top: i32 = std.math.maxInt(i32);
    for (pins) |p| {
        const at = pinAt(s, p);
        top = @min(top, at.y);
        switch (s.pins.items(.side)[p]) {
            .down => down = @max(down orelse at.y, at.y),
            .up => up = @min(up orelse at.y, at.y),
            else => {},
        }
    }
    const tap = if (down != null and up != null) @divFloor(down.? + up.?, 2) else if (down) |d| d + gap else if (up) |u| u - gap else top;
    const half = @divFloor(gap, 2);
    return .{
        tap,
        if (down) |d| d + gap else tap,
        if (up) |u| u - gap else tap,
        if (down) |d| d + half else tap,
        if (up) |u| u - half else tap,
    };
}

fn sameX(s: *const Schematic, pins: []const u32) bool {
    assert(pins.len >= 1);
    const x = pinAt(s, pins[0]).x;
    for (pins) |p| {
        if (pinAt(s, p).x != x) return false;
        if (s.pins.items(.side)[p].isHorizontal()) return false;
    }
    return true;
}

/// The way from `at`, a pin facing `side`, to the trunk at `y_t`: straight
/// when it faces it, out a half gap and down or up when it faces sideways,
/// round its own device through the channel on its right when it faces
/// away. The named-part row fallback in trunkLines supplies its own
/// on-row endpoint; original candidates keep these half-gap approaches.
fn wayTo(at: Pt, side: Side, y_t: i32, gap: i32) Line {
    var line: Line = .of(&.{at});
    const half = @divFloor(gap, 2);
    switch (side) {
        .left, .right => {
            const out = stepPt(at, side, half);
            line.push(out);
            if (out.y != y_t) line.push(.{ .x = out.x, .y = y_t });
        },
        .up, .down => {
            const toward = if (side == .down) y_t >= at.y else y_t <= at.y;
            if (toward) {
                if (at.y != y_t) line.push(.{ .x = at.x, .y = y_t });
            } else {
                const out = stepPt(at, side, half);
                line.push(out);
                line.push(.{ .x = out.x + gap, .y = out.y });
                line.push(.{ .x = out.x + gap, .y = y_t });
            }
        },
    }
    assert(line.len >= 1);
    return line;
}

test {
    _ = @import("trunk_row_test.zig");
}

test "trunk: opposed pins keep their straight rung when the trunk needs a later row" {
    // Literal geometric oracle: two opposed pins on y=100 have a clear
    // horizontal approach, while the third pin faces down at (180,120).
    // The resistor body prevents extending the whole trunk through y=100;
    // a lower trunk can still meet the middle of the straight local rung.
    const gpa = std.testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{"signal"}, .device_pin_count = &.{}, .roles = &.{.output} };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    const terminals = [_]Pt{ .{ .x = 20, .y = 100 }, .{ .x = 80, .y = 100 }, .{ .x = 180, .y = 120 } };
    for (terminals, [_]Side{ .right, .left, .down }) |at, side| {
        const node = try s.addNode(.{ .kind = .terminal, .ref = 0, .group = sch.none });
        try xy.append(s.arena.allocator(), at.toF());
        _ = try s.addPin(.{ .home = node, .side = side, .net = 0, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    const boxes = [_]library.Rect{
        .{ .min = .{ .x = -20, .y = 80 }, .max = .{ .x = 20, .y = 120 } },
        .{ .min = .{ .x = 80, .y = 90 }, .max = .{ .x = 120, .y = 110 } },
        .{ .min = .{ .x = 170, .y = 80 }, .max = .{ .x = 190, .y = 120 } },
    };
    var c = try Canvas.init(gpa, &s, &xy, .of(.{}, 40), &boxes, &.{});
    defer c.deinit();
    try std.testing.expect(try draw(&c, 0, &.{ 0, 1, 2 }, .port));
    // Every integer point of this literal horizontal interval must be ink.
    // A continuous U detour through a lower trunk cannot satisfy it.
    for (20..81) |x| try std.testing.expect(c.onNet(0, .{ .x = @intCast(x), .y = 100 }));
    for (terminals) |at| try std.testing.expect(c.onNet(0, at));
}

test {
    _ = @import("trunk_taps_test.zig");
    _ = @import("trunk_tie_test.zig");
}
