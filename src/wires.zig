//! Wires (issue #8, stage 4): every net of a placed drawing, as terminal
//! symbols, wires and labels, by the book's patterns. In: a `Schematic`
//! whose devices are placed and pinned, the devices' boxes, and the
//! drawing's mirror if it has one. Out: its routes, terminal and label
//! nodes, and the nets drawn as labels.
//!
//! - Rails: a ground symbol under each pin on ground; the supply a bar over
//!   its pins with one symbol. Inputs: a port at each pin. Outputs: a port
//!   at the outer end of the net's wire.
//! - A bias net: a gate line between the two facing gates of one row,
//!   named; else a label at each pin.
//! - Any other net: pins facing each other in pairs on two rows or more as
//!   a ladder (a rung between each pair, one upright through them all, as a
//!   CMFB midpoint meets its gate line); else down its column when its pins
//!   stand in one; else a trunk along its tap row (or a free track beside
//!   it) with each pin brought to it. A net none of these fits is routed by
//!   `routes.zig` after every pattern.
//!
//! Nets go rails and nets driven from outside first, then by name, so the
//! drawing does not depend on card order.
//!
//! Contents:
//! - `pub fn wire(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const canvas = @import("canvas.zig");
const routes = @import("routes.zig");
const maze = @import("maze.zig");

const Side = library.Side;
const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const Role = sch.Role;
const Canvas = canvas.Canvas;
const Lengths = canvas.Lengths;
const pinAt = canvas.pinAt;
const stepPt = canvas.stepPt;

/// One wire to draw: a polyline of at most six points, as a `Route` holds.
const Line = struct {
    pts: [6]Pt = undefined,
    len: u8 = 0,

    fn of(pts: []const Pt) Line {
        var l: Line = .{};
        for (pts) |p| l.push(p);
        return l;
    }
    fn push(l: *Line, p: Pt) void {
        assert(l.len < l.pts.len);
        l.pts[l.len] = p;
        l.len += 1;
    }
    fn slice(l: *const Line) []const Pt {
        assert(l.len >= 1);
        return l.pts[0..l.len];
    }
};

/// Draws every net of `s`; `xy` holds the nodes' points (`s.xy` is kept
/// in step with it), `gap` the room beside a device, `hidden` the points of
/// pins drawn on their symbol with no wire.
pub fn wire(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror) Allocator.Error!void {
    var c = try Canvas.init(gpa, s, xy, len, boxes, hidden);
    defer c.deinit();
    const n_nets = s.net_name.len;
    const pins_of = try gpa.alloc(std.ArrayList(u32), n_nets);
    defer {
        for (pins_of) |*l| l.deinit(gpa);
        gpa.free(pins_of);
    }
    @memset(pins_of, .empty);
    for (s.pins.items(.net), 0..) |net, p| try pins_of[net].append(gpa, @intCast(p));
    const order = try gpa.alloc(u32, n_nets);
    defer gpa.free(order);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    std.mem.sort(u32, order, s, struct {
        fn first(r: Role) u8 {
            return switch (r) {
                .supply, .sink => 0,
                .input, .bias => 1,
                .internal, .output => 2,
            };
        }
        fn lt(sc: *Schematic, x: u32, y: u32) bool {
            const fx = first(sc.roles[x]);
            const fy = first(sc.roles[y]);
            if (fx != fy) return fx < fy;
            return structure.nameLess(sc.net_name[x], sc.net_name[y]);
        }
    }.lt);
    var waiting: std.ArrayList(u32) = .empty;
    defer waiting.deinit(gpa);
    for (order) |net| {
        const pins = pins_of[net].items;
        if (pins.len == 0) continue;
        const axis2: ?i32 = if (mirror) |m| (if (m.net_mate[net] == net) m.axis2 else null) else null;
        switch (s.roles[net]) {
            .sink, .input => for (pins) |p| try terminal(&c, p),
            .supply => try supply(&c, pins),
            .bias => try bias(&c, net, pins),
            .internal, .output => if (!try ladder(&c, net, pins, axis2) and !try trunk(&c, net, pins)) try waiting.append(gpa, net),
        }
    }
    try routes.draw(&c, waiting.items, pins_of, mirror);
    assert(xy.items.len == s.nodes.len);
}

// ---- private ----

/// A rail's, input's or output's symbol one gap out from the pin, on a
/// stub; a label there if the stub would touch something.
fn terminal(c: *Canvas, p: u32) !void {
    const at = pinAt(c.s, p);
    const side = c.s.pins.items(.side)[p];
    const net = c.s.pins.items(.net)[p];
    const end = stepPt(at, side, if (c.rails[net]) c.len.rail else c.len.terminal);
    if (try c.commit(net, &.{ at, end })) {
        try c.leaf(.terminal, net, end, side.opposite());
    } else {
        try c.leaf(.label, net, at, side.opposite());
        c.s.labeled[net] = true;
    }
}

/// Supply pins facing up: stubs to a bar a gap above the highest, one
/// symbol on each unbroken run of the bar at its middle stub. Any other
/// supply pin: a symbol of its own.
fn supply(c: *Canvas, pins: []const u32) !void {
    const s = c.s;
    const gpa = c.gpa;
    var ups: std.ArrayList(u32) = .empty;
    defer ups.deinit(gpa);
    var top: i32 = std.math.maxInt(i32);
    for (pins) |p| {
        if (s.pins.items(.side)[p] != .up) continue;
        try ups.append(gpa, p);
        top = @min(top, pinAt(s, p).y);
    }
    for (pins) |p| if (s.pins.items(.side)[p] != .up or ups.items.len < 2) try terminal(c, p);
    if (ups.items.len < 2) return;
    assert(top != std.math.maxInt(i32));
    const net = s.pins.items(.net)[ups.items[0]];
    const bar = top - c.len.rail;
    std.mem.sort(u32, ups.items, s, struct {
        fn lt(sc: *Schematic, x: u32, y: u32) bool {
            return pinAt(sc, x).x < pinAt(sc, y).x;
        }
    }.lt);
    // A pin whose stub would touch something gets a symbol of its own.
    var on_bar: std.ArrayList(u32) = .empty;
    defer on_bar.deinit(gpa);
    for (ups.items) |p| {
        const at = pinAt(s, p);
        if (try c.commit(net, &.{ at, .{ .x = at.x, .y = bar } })) {
            try on_bar.append(gpa, p);
        } else {
            try terminal(c, p);
        }
    }
    if (on_bar.items.len == 0) return;
    // The bar in pieces between stubs, so every joint is a wire's end; a
    // piece that does not fit ends a run, and each run gets a symbol at its
    // middle stub.
    var run: usize = 0;
    for (on_bar.items, 0..) |q, i| {
        const last = i + 1 == on_bar.items.len;
        const joined = !last and blk: {
            const x0 = pinAt(s, q).x;
            const x1 = pinAt(s, on_bar.items[i + 1]).x;
            break :blk x0 == x1 or try c.commit(net, &.{ .{ .x = x0, .y = bar }, .{ .x = x1, .y = bar } });
        };
        if (joined) continue;
        const mid = pinAt(s, on_bar.items[(run + i) / 2]);
        try c.leaf(.terminal, net, .{ .x = mid.x, .y = bar }, .down);
        run = i + 1;
    }
}

/// Two gates of one row facing each other: a gate line between them, named
/// at its middle. Else a label at each pin.
fn bias(c: *Canvas, net: u32, pins: []const u32) !void {
    const s = c.s;
    assert(pins.len >= 1);
    assert(s.roles[net] == .bias);
    if (pins.len == 2) {
        const a = pinAt(s, pins[0]);
        const b = pinAt(s, pins[1]);
        const sa = s.pins.items(.side)[pins[0]];
        const sb = s.pins.items(.side)[pins[1]];
        const facing = a.y == b.y and ((a.x < b.x and sa == .right and sb == .left) or (b.x < a.x and sb == .right and sa == .left));
        if (facing and try c.commit(net, &.{ a, b })) {
            // Named at its middle, unless another net's wire crosses there.
            const mid: Pt = .{ .x = @divFloor(a.x + b.x, 2), .y = a.y };
            if (c.fits(net, mid, mid)) try c.leaf(.label, net, mid, .down) else try c.labelAt(pins[0]);
            return;
        }
    }
    for (pins) |p| try c.labelAt(p);
    s.labeled[net] = true;
}

/// An internal net whose pins all face each other in pairs along rows, one
/// pair a row on two rows or more, the pairs' spans sharing an x: a rung
/// between each pair and an upright at that x (the axis when `axis2` is
/// set and inside, else the middle) through them all. False, with nothing
/// drawn, when a piece does not fit.
fn ladder(c: *Canvas, net: u32, pins: []const u32, axis2: ?i32) !bool {
    const s = c.s;
    if (s.roles[net] != .internal or pins.len < 4 or pins.len % 2 != 0) return false;
    const sides = s.pins.items(.side);
    var rungs: std.ArrayList([3]i32) = .empty;
    defer rungs.deinit(c.gpa);
    var lo: i32 = std.math.minInt(i32);
    var hi: i32 = std.math.maxInt(i32);
    for (pins) |p| {
        if (sides[p] != .right) continue;
        const a = pinAt(s, p);
        // The nearest pin facing back from the right on its row.
        var end: ?i32 = null;
        for (pins) |q| {
            const b = pinAt(s, q);
            if (sides[q] == .left and b.y == a.y and b.x > a.x and (end == null or b.x < end.?)) end = b.x;
        }
        try rungs.append(c.gpa, .{ a.y, a.x, end orelse return false });
        lo = @max(lo, a.x);
        hi = @min(hi, end.?);
    }
    if (2 * rungs.items.len != pins.len or hi - lo < 2) return false;
    std.mem.sort([3]i32, rungs.items, {}, struct {
        fn lt(_: void, a: [3]i32, b: [3]i32) bool {
            return a[0] < b[0];
        }
    }.lt);
    for (rungs.items[0 .. rungs.items.len - 1], rungs.items[1..]) |a, b| if (a[0] == b[0]) return false;
    const mid = @divFloor(lo + hi, 2);
    const x: i32 = if (axis2) |a2| (if (@mod(a2, 2) == 0 and a2 > 2 * lo and a2 < 2 * hi) @divExact(a2, 2) else mid) else mid;
    var lines: std.ArrayList(Line) = .empty;
    defer lines.deinit(c.gpa);
    for (rungs.items) |r| {
        try lines.append(c.gpa, .of(&.{ .{ .x = r[1], .y = r[0] }, .{ .x = x, .y = r[0] } }));
        try lines.append(c.gpa, .of(&.{ .{ .x = x, .y = r[0] }, .{ .x = r[2], .y = r[0] } }));
    }
    for (rungs.items[0 .. rungs.items.len - 1], rungs.items[1..]) |a, b| {
        try lines.append(c.gpa, .of(&.{ .{ .x = x, .y = a[0] }, .{ .x = x, .y = b[0] } }));
    }
    if (!linesFit(c, net, lines.items)) return false;
    for (lines.items) |*l| assert(try c.commit(net, l.slice()));
    return true;
}

/// A net with no symbol of its own: one column's pins joined in order, or
/// each pin brought to a trunk along the net's tap row. An output also
/// gets a port at the trunk's outer end. False, with nothing drawn, when
/// the lines would touch another net's point or run through a device.
fn trunk(c: *Canvas, net: u32, pins: []const u32) !bool {
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
    for ([_]i32{ tap, tap - q, tap + q, tap - 2 * q, tap + 2 * q, past[0], past[1] }) |track| {
        y_t = track;
        lines.clearRetainingCapacity();
        lo = std.math.maxInt(i32);
        hi = std.math.minInt(i32);
        try trunkLines(c.gpa, s, pins, y_t, c.len.unit, column, &lines, &lo, &hi);
        if (linesFit(c, net, lines.items)) break;
        if (column) break;
    }
    if (!linesFit(c, net, lines.items)) return false;
    for (lines.items) |*l| assert(try c.commit(net, l.slice()));
    if (s.roles[net] != .output) return true;
    // The output's port: out from the outer end of the trunk, or of the
    // column at its tap, on the drawing's nearer side.
    const right = 2 * hi >= c.middle2();
    try c.port(net, .{ .x = if (right) hi else lo, .y = y_t }, if (right) .right else .left);
    return true;
}

/// The lines of one trunk at `y_t`: a column's pins joined in order, or each
/// pin brought to the trunk and the trunk across them; `lo`, `hi` its ends.
fn trunkLines(gpa: Allocator, s: *const Schematic, pins: []const u32, y_t: i32, gap: i32, column: bool, lines: *std.ArrayList(Line), lo: *i32, hi: *i32) !void {
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
        return;
    }
    var ends: std.ArrayList(i32) = .empty;
    defer ends.deinit(gpa);
    for (pins) |p| {
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

/// Whether every line fits for `net` (`Canvas.fits`).
fn linesFit(c: *const Canvas, net: u32, lines: []const Line) bool {
    for (lines) |*l| {
        const pts = l.slice();
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| if (!c.fits(net, a, b)) return false;
    }
    return true;
}
