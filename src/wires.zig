//! Wires (issue #8, stage 4): every net of a placed drawing, as terminal
//! symbols, wires and labels. In: a `Schematic` whose devices are placed
//! and pinned, and the devices' boxes. Out: its routes, terminal and label
//! nodes, and the nets drawn as labels.
//!
//! - Rails: a ground symbol under each pin on ground; the supply a bar over
//!   its pins with one symbol. Inputs: a port at each pin. Outputs: a port
//!   at the outer end of the net's wire.
//! - A bias net: a gate line between the two facing gates of one row,
//!   named; else a label at each pin.
//! - Any other net: down its column when its pins stand in one, else a
//!   trunk along its tap row (or a free track beside it) with each pin
//!   brought to it. A net whose wire would run through a device or touch
//!   another net's point is drawn as a label at each pin instead.
//!
//! Every pin is a point of its net from the start, so no wire passes
//! through another net's pin; nets go rails and nets driven from outside
//! first, then by name, so the drawing does not depend on card order.
//!
//! Contents:
//! - `pub const Box = struct { rect: Rect, device: u32 }`
//! - `pub fn wire(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), gap: i32, boxes: []const Box) !void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const layout = @import("layout.zig");
const structure = @import("structure.zig");

const Side = library.Side;
const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const Role = sch.Role;
const none = sch.none;

/// A device's symbol, placed: no wire may run through it.
pub const Box = struct { rect: Rect, device: u32 };

/// What is drawn so far: every net's segments and points (pins, ends,
/// bends, labels, terminals), for the checks a new wire must pass.
const Drawn = struct {
    segs: std.ArrayList(Seg) = .empty,
    points: std.ArrayList(Mark) = .empty,
    boxes: []const Box,
};

const Seg = struct { a: Pt, b: Pt, net: u32 };
const Mark = struct { at: Pt, net: u32 };

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
/// in step with it), `gap` the room beside a device.
pub fn wire(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), gap: i32, boxes: []const Box) !void {
    assert(xy.items.len == s.nodes.len);
    assert(gap > 0);
    var drawn: Drawn = .{ .boxes = boxes };
    defer drawn.segs.deinit(gpa);
    defer drawn.points.deinit(gpa);
    try wireNets(gpa, s, xy, gap, &drawn);
    assert(xy.items.len == s.nodes.len);
}

// ---- private ----

/// Every net with pins: rails and nets driven from outside first (stubs
/// to symbols and labels), then the rest by name. Every pin is a point of
/// its net from the start, so no wire passes through a pin of another.
fn wireNets(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), gap: i32, drawn: *Drawn) !void {
    const n_nets = s.net_name.len;
    const pins_of = try gpa.alloc(std.ArrayList(u32), n_nets);
    defer {
        for (pins_of) |*l| l.deinit(gpa);
        gpa.free(pins_of);
    }
    @memset(pins_of, .empty);
    for (s.pins.items(.net), 0..) |net, p| {
        try pins_of[net].append(gpa, @intCast(p));
        try drawn.points.append(gpa, .{ .at = pinAt(s, @intCast(p)), .net = net });
    }
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
    for (order) |net| {
        const pins = pins_of[net].items;
        if (pins.len == 0) continue;
        switch (s.roles[net]) {
            .sink => for (pins) |p| try terminal(gpa, s, xy, drawn, p, gap),
            .supply => try supply(gpa, s, xy, drawn, pins, gap),
            .input => for (pins) |p| try terminal(gpa, s, xy, drawn, p, gap),
            .bias => try bias(gpa, s, xy, drawn, net, pins, gap),
            .internal, .output => try trunk(gpa, s, xy, drawn, net, pins, gap),
        }
    }
}

/// Where the layout routes a pin to: on its node's line, at its side's reach.
fn pinAt(s: *const Schematic, p: u32) Pt {
    assert(p < s.pins.len);
    assert(s.pins.items(.home)[p] < s.xy.len);
    return toPt(layout.pinPoint(s, p));
}

/// A rail's, input's or output's symbol one gap out from the pin, on a
/// stub; a label there if the stub would touch something.
fn terminal(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), drawn: *Drawn, p: u32, gap: i32) !void {
    const at = pinAt(s, p);
    const side = s.pins.items(.side)[p];
    const net = s.pins.items(.net)[p];
    const end = stepPt(at, side, gap);
    if (try commit(gpa, s, drawn, net, &.{ at, end })) {
        try leaf(s, xy, drawn, gpa, .terminal, net, end, side.opposite());
    } else {
        try leaf(s, xy, drawn, gpa, .label, net, at, side.opposite());
        s.labeled[net] = true;
    }
}

/// A terminal or label node at `at` with one pin facing `faces` (toward
/// the wire it ends).
fn leaf(s: *Schematic, xy: *std.ArrayList([2]f32), drawn: *Drawn, gpa: Allocator, kind: sch.NodeKind, net: u32, at: Pt, faces: Side) !void {
    const node = try s.addNode(.{ .kind = kind, .ref = net, .group = none, .x_key = 0, .y_key = 0 });
    try xy.append(s.arena.allocator(), toF(at));
    // The list may have moved: pin points are read through `s.xy`.
    s.xy = xy.items;
    assert(s.xy.len == s.nodes.len);
    _ = try s.addPin(.{ .home = node, .side = faces, .net = net, .device = none, .index = 0 });
    try drawn.points.append(gpa, .{ .at = at, .net = net });
}

fn stepPt(p: Pt, side: Side, d: i32) Pt {
    assert(d >= 0);
    return switch (side) {
        .left => .{ .x = p.x - d, .y = p.y },
        .right => .{ .x = p.x + d, .y = p.y },
        .up => .{ .x = p.x, .y = p.y - d },
        .down => .{ .x = p.x, .y = p.y + d },
    };
}

/// Supply pins facing up: stubs to a bar a gap above the highest, one
/// symbol on the bar at the middle stub. Any other supply pin: a symbol of
/// its own.
fn supply(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), drawn: *Drawn, pins: []const u32, gap: i32) !void {
    var ups: std.ArrayList(u32) = .empty;
    defer ups.deinit(gpa);
    var top: i32 = std.math.maxInt(i32);
    for (pins) |p| {
        if (s.pins.items(.side)[p] != .up) continue;
        try ups.append(gpa, p);
        top = @min(top, pinAt(s, p).y);
    }
    for (pins) |p| if (s.pins.items(.side)[p] != .up or ups.items.len < 2) try terminal(gpa, s, xy, drawn, p, gap);
    if (ups.items.len < 2) return;
    assert(top != std.math.maxInt(i32));
    const net = s.pins.items(.net)[ups.items[0]];
    const bar = top - gap;
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
        if (try commit(gpa, s, drawn, net, &.{ at, .{ .x = at.x, .y = bar } })) {
            try on_bar.append(gpa, p);
        } else {
            try terminal(gpa, s, xy, drawn, p, gap);
        }
    }
    if (on_bar.items.len == 0) return;
    // The bar in pieces between stubs, so every joint is a wire's end.
    for (on_bar.items[0 .. on_bar.items.len - 1], on_bar.items[1..]) |p, q| {
        const x0 = pinAt(s, p).x;
        const x1 = pinAt(s, q).x;
        if (x0 != x1) _ = try commit(gpa, s, drawn, net, &.{ .{ .x = x0, .y = bar }, .{ .x = x1, .y = bar } });
    }
    const mid = pinAt(s, on_bar.items[(on_bar.items.len - 1) / 2]);
    try leaf(s, xy, drawn, gpa, .terminal, net, .{ .x = mid.x, .y = bar }, .down);
}

/// Two gates of one row facing each other: a gate line between them, named
/// at its middle. Else a label at each pin.
fn bias(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), drawn: *Drawn, net: u32, pins: []const u32, gap: i32) !void {
    assert(pins.len >= 1);
    assert(s.roles[net] == .bias);
    if (pins.len == 2) {
        const a = pinAt(s, pins[0]);
        const b = pinAt(s, pins[1]);
        const sa = s.pins.items(.side)[pins[0]];
        const sb = s.pins.items(.side)[pins[1]];
        const facing = a.y == b.y and ((a.x < b.x and sa == .right and sb == .left) or (b.x < a.x and sb == .right and sa == .left));
        if (facing and try commit(gpa, s, drawn, net, &.{ a, b })) {
            try leaf(s, xy, drawn, gpa, .label, net, .{ .x = @divFloor(a.x + b.x, 2), .y = a.y }, .down);
            return;
        }
    }
    for (pins) |p| try labelAt(gpa, s, xy, drawn, p, gap);
    s.labeled[net] = true;
}

/// A label on a stub from the pin, or on the pin when the stub would touch
/// something.
fn labelAt(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), drawn: *Drawn, p: u32, gap: i32) !void {
    const at = pinAt(s, p);
    const side = s.pins.items(.side)[p];
    const net = s.pins.items(.net)[p];
    const end = stepPt(at, side, @divFloor(gap, 2));
    const stub = try commit(gpa, s, drawn, net, &.{ at, end });
    try leaf(s, xy, drawn, gpa, .label, net, if (stub) end else at, side.opposite());
}

/// A net with no symbol of its own: one column's pins joined in order, or
/// each pin brought to a trunk along the net's tap row. An output also
/// gets a port at the trunk's outer end. Anything that would touch another
/// net's point or run through a device: labels.
fn trunk(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), drawn: *Drawn, net: u32, pins: []const u32, gap: i32) !void {
    assert(pins.len >= 1);
    for (pins) |p| assert(s.pins.items(.net)[p] == net);
    if (pins.len == 1 and s.roles[net] != .output) return;
    var lines: std.ArrayList(Line) = .empty;
    defer lines.deinit(gpa);
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    const column = sameX(s, pins);
    // A trunk takes the first of a few tracks in its channel that no other
    // net's wire or point is on: the tap row, then a quarter gap either
    // side, then half.
    const tap = tapY(s, pins, gap);
    const q = @divFloor(gap, 4);
    var y_t = tap;
    for ([_]i32{ 0, -q, q, -2 * q, 2 * q }) |off| {
        y_t = tap + off;
        lines.clearRetainingCapacity();
        lo = std.math.maxInt(i32);
        hi = std.math.minInt(i32);
        try trunkLines(gpa, s, pins, y_t, gap, column, &lines, &lo, &hi);
        if (linesFit(drawn, net, lines.items)) break;
        if (column) break;
    }
    const ok = linesFit(drawn, net, lines.items);
    if (!ok) {
        for (pins) |p| try labelAt(gpa, s, xy, drawn, p, gap);
        s.labeled[net] = true;
        return;
    }
    for (lines.items) |*l| assert(try commit(gpa, s, drawn, net, l.slice()));
    if (s.roles[net] != .output) return;
    // The output's port: beyond a lone pin, else out from the outer end of
    // the trunk, or of the column at its tap, on the drawing's nearer side.
    const from: Pt, const side: Side = if (pins.len == 1)
        .{ pinAt(s, pins[0]), s.pins.items(.side)[pins[0]] }
    else blk: {
        const right = 2 * hi >= drawingMiddle(drawn);
        break :blk .{ .{ .x = if (right) hi else lo, .y = y_t }, if (right) .right else .left };
    };
    const end = stepPt(from, side, gap);
    if (try commit(gpa, s, drawn, net, &.{ from, end })) {
        try leaf(s, xy, drawn, gpa, .terminal, net, end, side.opposite());
    } else {
        try leaf(s, xy, drawn, gpa, .label, net, from, side.opposite());
    }
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
    for (pins) |p| {
        const line = reachTrunk(s, p, y_t, gap);
        try lines.append(gpa, line);
        const end = line.pts[line.len - 1];
        lo.* = @min(lo.*, end.x);
        hi.* = @max(hi.*, end.x);
    }
    if (lo.* < hi.*) try lines.append(gpa, .of(&.{ .{ .x = lo.*, .y = y_t }, .{ .x = hi.*, .y = y_t } }));
}

/// Between the lowest pin facing down and the highest facing up; a gap
/// past the pins when only one way faces; else the first pin's row.
fn tapY(s: *const Schematic, pins: []const u32, gap: i32) i32 {
    assert(pins.len >= 1);
    assert(gap > 0);
    var down: ?i32 = null;
    var up: ?i32 = null;
    for (pins) |p| {
        const at = pinAt(s, p);
        switch (s.pins.items(.side)[p]) {
            .down => down = @max(down orelse at.y, at.y),
            .up => up = @min(up orelse at.y, at.y),
            else => {},
        }
    }
    if (down != null and up != null) return @divFloor(down.? + up.?, 2);
    if (down) |d| return d + gap;
    if (up) |u| return u - gap;
    return pinAt(s, pins[0]).y;
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

/// Twice the middle of what is drawn so far, along x.
fn drawingMiddle(drawn: *const Drawn) i32 {
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    for (drawn.boxes) |b| {
        lo = @min(lo, b.rect.min.x);
        hi = @max(hi, b.rect.max.x);
    }
    return lo + hi;
}

/// Whether every line can be drawn for `net`: none runs through a device,
/// overlaps another net's wire or touches another net's point, and no end
/// of it lies on another net's wire.
fn linesFit(drawn: *const Drawn, net: u32, lines: []const Line) bool {
    for (lines) |*l| {
        const pts = l.slice();
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| if (!segmentFree(drawn, net, a, b)) return false;
    }
    return true;
}

fn segmentFree(drawn: *const Drawn, net: u32, a: Pt, b: Pt) bool {
    // Wires are Manhattan.
    assert(a.x == b.x or a.y == b.y);
    const r = Rect.fromCorners(a, b);
    for (drawn.points.items) |m| if (m.net != net and r.contains(m.at)) return false;
    for (drawn.segs.items) |g| {
        if (g.net == net) continue;
        const q = Rect.fromCorners(g.a, g.b);
        // An end of ours on their wire, or one of theirs on ours.
        if (q.contains(a) or q.contains(b) or r.contains(g.a) or r.contains(g.b)) return false;
        // Overlap along one line.
        const ours_h = a.y == b.y;
        const theirs_h = g.a.y == g.b.y;
        if (ours_h == theirs_h and r.intersects(q)) return false;
    }
    for (drawn.boxes) |bx| {
        // Through a device's body: its interior, its pins' edge excluded.
        const inner: Rect = .{ .min = .{ .x = bx.rect.min.x + 1, .y = bx.rect.min.y + 1 }, .max = .{ .x = bx.rect.max.x - 1, .y = bx.rect.max.y - 1 } };
        if (inner.min.x > inner.max.x or inner.min.y > inner.max.y) continue;
        if (crossesInterior(inner, a, b)) return false;
    }
    return true;
}

/// An axis-aligned segment runs inside a rectangle somewhere.
fn crossesInterior(r: Rect, a: Pt, b: Pt) bool {
    assert(r.min.x <= r.max.x);
    assert(a.x == b.x or a.y == b.y);
    const s = Rect.fromCorners(a, b);
    return s.intersects(r) and !(s.min.x == s.max.x and (s.min.x == r.min.x or s.min.x == r.max.x)) and !(s.min.y == s.max.y and (s.min.y == r.min.y or s.min.y == r.max.y));
}

/// Draws the polyline `pts` for `net` when it fits; returns whether it did.
fn commit(gpa: Allocator, s: *Schematic, drawn: *Drawn, net: u32, pts: []const Pt) !bool {
    assert(pts.len >= 2);
    assert(pts.len <= 6);
    for (pts[0 .. pts.len - 1], pts[1..]) |a, b| if (!segmentFree(drawn, net, a, b)) return false;
    const before = drawn.segs.items.len;
    defer assert(drawn.segs.items.len == before + pts.len - 1);
    var route: sch.Route = .{ .pts = undefined, .len = @intCast(pts.len), .net = net, .kind = .join, .id = none, .straight = true, .owners = .{ none, none, none } };
    for (pts, 0..) |p, i| route.pts[i] = toF(p);
    try s.routes.append(s.arena.allocator(), route);
    for (pts[0 .. pts.len - 1], pts[1..]) |a, b| try drawn.segs.append(gpa, .{ .a = a, .b = b, .net = net });
    for (pts) |p| try drawn.points.append(gpa, .{ .at = p, .net = net });
    return true;
}

fn toPt(p: [2]f32) Pt {
    return .{ .x = @intFromFloat(@round(p[0])), .y = @intFromFloat(@round(p[1])) };
}

fn toF(p: Pt) [2]f32 {
    return .{ @floatFromInt(p.x), @floatFromInt(p.y) };
}
