//! The trunk pattern (issue #8, stage 4): one net with no symbol of its own
//! as a trunk along a row, or down a column, with each pin brought to it,
//! or a column's pins joined in order. Of the tracks that fit it takes the
//! cheapest as the router counts a path: the wire's length and `bend_cost`
//! a corner (people draw a net at the fewest corners its pins allow in
//! 93.8% of the nets of 5,263 hand-drawn schematics). In: the canvas, the
//! net and its pins, placed. Out: the net's wires on the canvas (an
//! output's or an input's port too), or nothing drawn when no track fits.
//!
//! Contents:
//! - `pub const End = enum { port, name }`
//! - `pub fn draw(c: *Canvas, net: u32, pins: []const u32, end: End) Allocator.Error!bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const routes = @import("routes.zig");

const Pt = library.Pt;
const Side = library.Side;
const Schematic = sch.Schematic;
const Canvas = canvas.Canvas;
const Line = canvas.Line;
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

/// The rows tried for a trunk before the tap row.
const level_max = 4;
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
};

/// A net with no symbol of its own: one column's pins joined in order, or
/// each pin brought to a trunk, the cheapest track that fits. An output also
/// gets a port at the trunk's outer end; with `end` `.name` (two pins or
/// more) the wire carries the net's name on a stub from a free end. False,
/// with nothing drawn, when the lines would touch another net's point or
/// run through a device.
pub fn draw(c: *Canvas, net: u32, pins: []const u32, end: End) Allocator.Error!bool {
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
    // the row of a pin facing sideways level with the junction, the tap
    // row, a quarter gap either side, then half; a half gap past its pins'
    // devices, away from the drawing's middle first (a gate line over the
    // top row's gates, under the bottom's); then each pin's own row.
    const tap = tapY(s, pins, c.len.tap);
    const q = @divFloor(c.len.unit, 4);
    const past = pastDevices(c, pins);
    const tracks = try c.gpa.alloc(i32, level_max + 7 + pins.len);
    defer c.gpa.free(tracks);
    const level = levelRows(s, pins, tap, tracks[0..level_max]);
    @memcpy(tracks[level..][0..7], &[_]i32{ tap, tap - q, tap + q, tap - 2 * q, tap + 2 * q, past[0], past[1] });
    for (pins, tracks[level + 7 ..][0..pins.len]) |p, *t| t.* = pinAt(s, p).y;
    // From the top down, so the order of the cards chooses nothing.
    std.mem.sort(i32, tracks[level + 7 ..][0..pins.len], {}, std.sort.asc(i32));
    // An upright trunk's columns: of a pin facing up or down (the link
    // between two devices of a column, a gate a straight stub to it), midway
    // between two pins, a half gap either side of a pin, then of a pin
    // facing sideways.
    // ponytail: only for a net with no port or name on its wire; the stub's
    // place on an upright trunk when outputs should have one too.
    var columns: [5 * upright_pins_max]i32 = undefined;
    const uprights: []const i32 = if (!column and !ended and role != .output and pins.len <= upright_pins_max) uprightColumns(s, pins, @divFloor(c.len.unit, 2), c.middle2(), &columns) else &.{};
    var lo: i32 = 0;
    var hi: i32 = 0;
    var y_t = tap;
    var free: ?Side = null;
    var fewest: i64 = std.math.maxInt(i64);
    // A column has one way to be drawn. Else facing gates joined by a gate
    // line first (a mirror's, as the book draws it), then every pin on its
    // own way to the trunk; then an upright trunk, where it costs less
    // still.
    const lays: []const Lay = if (column) &.{.column} else &.{ .rungs, .level, .upright };
    for (lays) |lay| {
        const among = switch (lay) {
            .column => tracks[level..][0..1],
            .rungs, .level => tracks[0 .. level + 7 + pins.len],
            .upright => uprights,
        };
        for (among) |track| {
            tried.clearRetainingCapacity();
            var t_lo: i32 = std.math.maxInt(i32);
            var t_hi: i32 = std.math.minInt(i32);
            const drawn = try trunkLines(c.gpa, s, pins, track, c.len.unit, lay, &tried, &t_lo, &t_hi);
            if (lay == .rungs and !drawn) break;
            const count = cost(c, pins, tried.items, fewest);
            if (count >= fewest or !linesFit(c, net, tried.items)) continue;
            // An upright trunk has no end to mark: its ends are not read.
            const t_free = if (ended) freeEnd(c, net, pins, t_lo, t_hi, track, reach) else null;
            if (needs_end and t_free == null) continue;
            std.mem.swap(std.ArrayList(Line), &lines, &tried);
            lo = t_lo;
            hi = t_hi;
            y_t = track;
            free = t_free;
            fewest = count;
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
    const side: Side = free orelse if (end == .name) return nameOnPin(c, pins) else if (2 * hi >= c.middle2()) .right else .left;
    const from: Pt = .{ .x = if (side == .right) hi else lo, .y = y_t };
    if (end == .port) {
        try c.port(net, from, side);
        return true;
    }
    const to = stepPt(from, side, reach);
    if (!try c.commit(net, &.{ from, to })) return nameOnPin(c, pins);
    // A bias net's name is a port, as people draw it.
    try c.leaf(if (role == .bias) .terminal else .label, net, to, side.opposite());
    return true;
}

// ---- private ----

/// The part's name at its top-left pin, by place, so card order changes
/// nothing: the wire has no free end to carry it.
fn nameOnPin(c: *Canvas, pins: []const u32) !bool {
    try c.labelAt(pins[routes.topLeft(c.s, pins)]);
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

/// What a net's lines cost, as the router counts a path: their length and
/// `bend_cost` a corner; more than any track costs when a line ends on
/// nothing (`corners`). `under` is the cost to beat: at that length or
/// more the length alone is returned.
fn cost(c: *const Canvas, pins: []const u32, lines: []const Line, under: i64) i64 {
    var length: i64 = 0;
    for (lines) |*l| {
        const pts = l.slice();
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| length += @abs(a.x - b.x) + @abs(a.y - b.y);
    }
    // No cheaper than the track in hand: its corners are not counted.
    if (length >= under) return length;
    return length + @as(i64, c.len.bend_cost) * (corners(c.s, pins, lines) orelse return std.math.maxInt(i64));
}

/// The corners of a net's lines as a reader counts them: the points its
/// wire leaves exactly two ways at a right angle, a pin's device one of
/// the ways. A T, a crossing of its own and a straight joint are none.
/// Null when a line ends on nothing: two pins' ways to the trunk run
/// together past where they meet, a spur no wire should have.
fn corners(s: *const Schematic, pins: []const u32, lines: []const Line) ?u32 {
    var count: u32 = 0;
    for (lines, 0..) |*l, li| for (l.slice(), 0..) |p, pi| {
        // Each point once, where it first stands.
        const seen = seen: for (lines[0 .. li + 1], 0..) |*m, mi| {
            const pts = m.slice();
            for (pts[0..if (mi == li) pi else pts.len]) |o| if (o.eql(p)) break :seen true;
        } else false;
        if (seen) continue;
        // The ways out: left, right, up, down. A pin's device is one, back
        // from the side it faces.
        var arms: u4 = 0;
        for (pins) |pin| if (pinAt(s, pin).eql(p)) {
            arms |= switch (s.pins.items(.side)[pin]) {
                .right => 1,
                .left => 2,
                .down => 4,
                .up => 8,
            };
        };
        for (lines) |*m| {
            const pts = m.slice();
            for (pts[0 .. pts.len - 1], pts[1..]) |a, b| {
                if (p.x < @min(a.x, b.x) or p.x > @max(a.x, b.x) or p.y < @min(a.y, b.y) or p.y > @max(a.y, b.y)) continue;
                for ([_]Pt{ a, b }) |e| {
                    if (e.x < p.x) arms |= 1;
                    if (e.x > p.x) arms |= 2;
                    if (e.y < p.y) arms |= 4;
                    if (e.y > p.y) arms |= 8;
                }
            }
        }
        if (@popCount(arms) < 2) return null;
        count += @intFromBool(@popCount(arms) == 2 and arms & 3 != 0 and arms & 12 != 0);
    };
    return count;
}

/// The columns tried for an upright trunk, into `out`, in the order tried:
/// each pin's facing up or down, midway between each two neighbours, `half`
/// either side of each pin, each pin's facing sideways. Within each kind
/// the column nearest the middle of the pins first, then the one nearer the
/// drawing's middle (twice it, `middle2`), so neither the order of the
/// cards nor a mirror image chooses another.
fn uprightColumns(s: *const Schematic, pins: []const u32, half: i32, middle2: i32, out: []i32) []const i32 {
    assert(pins.len >= 2 and out.len >= 5 * pins.len);
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    for (pins) |p| {
        lo = @min(lo, pinAt(s, p).x);
        hi = @max(hi, pinAt(s, p).x);
    }
    const order: Nearest = .{ .box2 = lo + hi, .middle2 = middle2 };
    const sides = s.pins.items(.side);
    var n: usize = 0;
    for (0..4) |kind| {
        const from = n;
        for (pins) |p| {
            const x = pinAt(s, p).x;
            switch (kind) {
                // On a pin: first one facing up or down, last one sideways.
                0, 3 => if (sides[p].isHorizontal() == (kind == 3)) {
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
/// (`rungs` only).
fn trunkLines(gpa: Allocator, s: *const Schematic, pins: []const u32, t: i32, gap: i32, lay: Lay, lines: *std.ArrayList(Line), lo: *i32, hi: *i32) !bool {
    assert(lines.items.len == 0);
    var ends: std.ArrayList(i32) = .empty;
    defer ends.deinit(gpa);
    const paired = try gpa.alloc(bool, pins.len);
    defer gpa.free(paired);
    @memset(paired, false);
    const sides = s.pins.items(.side);
    if (lay == .rungs) {
        const q = @max(1, @divFloor(gap, 4));
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
            const mid: Pt = .{ .x = a.x + @divFloor(@divFloor(b.x - a.x, 2), q) * q, .y = a.y };
            if (mid.x == a.x) continue;
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
            .column => .of(&.{.{ .x = at.y, .y = at.x }}),
            .upright => wayTo(.{ .x = at.y, .y = at.x }, switch (sides[p]) {
                .left => .up,
                .up => .left,
                .right => .down,
                .down => .right,
            }, t, gap),
            .rungs, .level => wayTo(at, sides[p], t, gap),
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
    std.mem.sort(i32, ends.items, {}, std.sort.asc(i32));
    for (ends.items[0 .. ends.items.len - 1], ends.items[1..]) |a, b| {
        if (a != b) try lines.append(gpa, .of(&.{ .{ .x = a, .y = y }, .{ .x = b, .y = y } }));
    }
    if (upright) for (lines.items) |*l| for (l.pts[0..l.len]) |*pt| std.mem.swap(i32, &pt.x, &pt.y);
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

/// The rows of the pins facing sideways that every pin facing down stands
/// over and every pin facing up under (the junction between two devices
/// of a column; the row a lone drain comes down to), nearest `tap` first,
/// into `out`; how many. A trunk along such a row joins that pin straight
/// and bends no other: people's wires run pin to pin or pin to T.
fn levelRows(s: *const Schematic, pins: []const u32, tap: i32, out: []i32) usize {
    var down: i32 = std.math.minInt(i32);
    var up: i32 = std.math.maxInt(i32);
    for (pins) |p| switch (s.pins.items(.side)[p]) {
        .down => down = @max(down, pinAt(s, p).y),
        .up => up = @min(up, pinAt(s, p).y),
        else => {},
    };
    if (down == std.math.minInt(i32) and up == std.math.maxInt(i32)) return 0;
    var n: usize = 0;
    for (pins) |p| {
        const y = pinAt(s, p).y;
        if (!s.pins.items(.side)[p].isHorizontal() or y <= down or y >= up) continue;
        if (std.mem.indexOfScalar(i32, out[0..n], y) != null or n == out.len) continue;
        out[n] = y;
        n += 1;
    }
    std.sort.insertion(i32, out[0..n], tap, struct {
        fn lt(t: i32, a: i32, b: i32) bool {
            return @abs(a - t) < @abs(b - t);
        }
    }.lt);
    return n;
}

/// Between the lowest pin facing down and the highest facing up; a gap
/// past the pins when only one way faces; else the topmost pin's row.
fn tapY(s: *const Schematic, pins: []const u32, gap: i32) i32 {
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
    if (down != null and up != null) return @divFloor(down.? + up.?, 2);
    if (down) |d| return d + gap;
    if (up) |u| return u - gap;
    return top;
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
/// away.
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
