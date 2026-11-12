//! The trunk pattern (issue #8, stage 4): one net with no symbol of its own
//! as a trunk along a row with each pin brought to it, or a column's pins
//! joined in order. In: the canvas, the net and its pins, placed. Out: the
//! net's wires on the canvas (an output's or an input's port too), or nothing drawn when
//! no track fits.
//!
//! Contents:
//! - `pub fn draw(c: *Canvas, net: u32, pins: []const u32) Allocator.Error!bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");

const Pt = library.Pt;
const Schematic = sch.Schematic;
const Canvas = canvas.Canvas;
const Line = canvas.Line;
const linesFit = canvas.linesFit;
const pinAt = canvas.pinAt;
const stepPt = canvas.stepPt;

/// The rows tried for a trunk before the tap row.
const level_max = 4;

/// A net with no symbol of its own: one column's pins joined in order, or
/// each pin brought to a trunk along the net's tap row. An output also
/// gets a port at the trunk's outer end. False, with nothing drawn, when
/// the lines would touch another net's point or run through a device.
pub fn draw(c: *Canvas, net: u32, pins: []const u32) Allocator.Error!bool {
    const s = c.s;
    assert(pins.len >= 1);
    for (pins) |p| assert(s.pins.items(.net)[p] == net);
    // A lone pin has nothing to join: an output's gets its port.
    if (pins.len == 1) {
        if (s.roles[net] == .output) try c.port(net, pinAt(s, pins[0]), s.pins.items(.side)[pins[0]]);
        return true;
    }
    var lines: std.ArrayList(Line) = .empty;
    defer lines.deinit(c.gpa);
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    const column = sameX(s, pins);
    // A trunk takes the first of a few tracks that no other net's wire or
    // point is on: the tap row, a quarter gap either side, then half; then
    // a half gap past its pins' devices, away from the drawing's middle
    // first (a gate line over the top row's gates, under the bottom's).
    const tap = tapY(s, pins, c.len.tap);
    const q = @divFloor(c.len.unit, 4);
    const past = pastDevices(c, pins);
    var y_t = tap;
    // Facing gates joined by a gate line first (a mirror's, as the book
    // draws it), then every pin on its own way to the trunk.
    // First of all the row of a pin that faces sideways level with the
    // junction: the trunk along it joins that pin straight.
    var tracks: [level_max + 7]i32 = undefined;
    const level = levelRows(s, pins, tap, tracks[0..level_max]);
    @memcpy(tracks[level..][0..7], &[_]i32{ tap, tap - q, tap + q, tap - 2 * q, tap + 2 * q, past[0], past[1] });
    const fit = fit: for ([_]bool{ true, false }) |rungs| {
        for (tracks[0 .. level + 7]) |track| {
            y_t = track;
            lines.clearRetainingCapacity();
            lo = std.math.maxInt(i32);
            hi = std.math.minInt(i32);
            const drawn = try trunkLines(c.gpa, s, pins, y_t, c.len.unit, column, rungs, &lines, &lo, &hi);
            if (rungs and !drawn) break;
            if (linesFit(c, net, lines.items)) break :fit true;
            if (column) break;
        }
    } else false;
    if (!fit) return false;
    const role = s.roles[net];
    // The output's port: out from the outer end of the trunk, or of the
    // column at its tap, on the drawing's nearer side. An input's: from
    // the left end, where the signal enters, or the right, an end no pin
    // of the net stands beyond (the stub would run back along the wire);
    // with room at neither, nothing is drawn, and each pin gets a port.
    var right = 2 * hi >= c.middle2();
    if (role == .input) {
        right = for ([_]bool{ false, true }) |r| {
            const from: Pt = .{ .x = if (r) hi else lo, .y = y_t };
            const beyond = for (pins) |p| {
                if (if (r) pinAt(s, p).x > hi else pinAt(s, p).x < lo) break true;
            } else false;
            if (!beyond and c.fits(net, from, stepPt(from, if (r) .right else .left, c.len.terminal))) break r;
        } else return false;
    }
    for (lines.items) |*l| assert(try c.commit(net, l.slice()));
    if (role != .output and role != .input) return true;
    try c.port(net, .{ .x = if (right) hi else lo, .y = y_t }, if (right) .right else .left);
    return true;
}

// ---- private ----

/// The lines of one trunk at `y_t`: a column's pins joined in order, or each
/// pin brought to the trunk and the trunk across them; `lo`, `hi` its ends.
/// With `rungs`, two pins facing each other along a row off the trunk are
/// joined straight (a gate line) and the line's middle is brought to the
/// trunk; whether any such line was drawn.
fn trunkLines(gpa: Allocator, s: *const Schematic, pins: []const u32, y_t: i32, gap: i32, column: bool, rungs: bool, lines: *std.ArrayList(Line), lo: *i32, hi: *i32) !bool {
    if (column) {
        const sorted = try gpa.dupe(u32, pins);
        defer gpa.free(sorted);
        std.mem.sort(u32, sorted, s, struct {
            fn lt(sc: *const Schematic, x: u32, y: u32) bool {
                return pinAt(sc, x).y < pinAt(sc, y).y;
            }
        }.lt);
        for (sorted[0 .. sorted.len - 1], sorted[1..]) |p, q| {
            if (!pinAt(s, p).eql(pinAt(s, q))) try lines.append(gpa, .of(&.{ pinAt(s, p), pinAt(s, q) }));
        }
        lo.* = pinAt(s, sorted[0]).x;
        hi.* = lo.*;
        return false;
    }
    var ends: std.ArrayList(i32) = .empty;
    defer ends.deinit(gpa);
    const paired = try gpa.alloc(bool, pins.len);
    defer gpa.free(paired);
    @memset(paired, false);
    const sides = s.pins.items(.side);
    const q = @max(1, @divFloor(gap, 4));
    if (rungs) for (pins, 0..) |p, i| {
        const a = pinAt(s, p);
        if (sides[p] != .right or a.y == y_t) continue;
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
        try lines.append(gpa, .of(&.{ mid, .{ .x = mid.x, .y = y_t } }));
        try ends.append(gpa, mid.x);
        lo.* = @min(lo.*, mid.x);
        hi.* = @max(hi.*, mid.x);
    };
    for (pins, paired) |p, done| {
        if (done) continue;
        const line = reachTrunk(s, p, y_t, gap);
        // A pin on the trunk already needs no line of its own.
        if (line.len >= 2) try lines.append(gpa, line);
        const end = line.pts[line.len - 1];
        try ends.append(gpa, end.x);
        lo.* = @min(lo.*, end.x);
        hi.* = @max(hi.*, end.x);
    }
    // The trunk in pieces between the ends, so every joint is a wire's end.
    std.mem.sort(i32, ends.items, {}, std.sort.asc(i32));
    for (ends.items[0 .. ends.items.len - 1], ends.items[1..]) |a, b| {
        if (a != b) try lines.append(gpa, .of(&.{ .{ .x = a, .y = y_t }, .{ .x = b, .y = y_t } }));
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

/// A pin's way to the trunk at `y_t`: straight when it faces it, out a
/// half gap and down or up when it faces sideways, round its own device
/// through the channel on its right when it faces away.
fn reachTrunk(s: *const Schematic, p: u32, y_t: i32, gap: i32) Line {
    const at = pinAt(s, p);
    const side = s.pins.items(.side)[p];
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
