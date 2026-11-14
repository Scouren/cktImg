//! What is drawn so far (issue #8, stage 4): every net's wires and points
//! over the placed devices, and the one way to add to them. In: a
//! `Schematic` whose devices are placed and pinned, and the devices'
//! boxes. Out: its routes, and terminal and label nodes.
//!
//! Human Rules:
//! - canvas.1 (invariant) Every length is a whole number of target units,
//!   at least 1, rounded up from `config.Layout`: the drawing stays on
//!   integers and mirrors exactly. `Lengths.of`
//! - canvas.2 (invariant) A wire runs through no device's body, along no
//!   other net's wire, onto no other net's point (a pin from the start, a
//!   wire's end or bend, a symbol or a name), and ends on no other net's
//!   wire; it may cross one. `Canvas.fits`
//! - canvas.3 (habit) No other net's wire crosses the stub between a rail
//!   pin and its symbol: a person's symbol sits on its pin. People: 3 of
//!   16,030 such stubs in 5,263 hand-drawn schematics are crossed.
//!   `Canvas.wall`
//! - canvas.4 (unmeasured) A port, a rail symbol or a name stands at the
//!   end of a stub out from its pin, toward the first side asked whose stub
//!   fits (a name: the way its pin faces); where none fits, a name on the
//!   pin itself. `Canvas.markAt`
//! - canvas.5 (unmeasured) An input's or output's port goes out toward the
//!   side a `port` line asks, else the side given, else up, else down: the
//!   first whose stub neither runs along the net's own wire nor ends on it
//!   (the node between two parts in series has its port off the line).
//!   `Canvas.port`
//! - canvas.6 (invariant) A port whose stub does not fit is a name at its
//!   point, or at the net's top-left pin where another net's wire crosses
//!   that point: a name never joins two nets. `Canvas.port`
//! - canvas.7 (choice) A net's name, where it has no better place, goes on
//!   its topmost, then leftmost, pin: a place, so the order of the cards
//!   chooses nothing. `topLeft`
//! - canvas.8 (invariant) A polyline is committed whole: reserve its route,
//!   segment and point rows before changing any length. Allocation failure
//!   leaves the existing drawing intact. `Canvas.commit`
//!
//! Contents:
//! - `pub const Lengths = struct`, `Lengths.of(layout: config.Layout, unit: i32) Lengths`
//! - `pub const Canvas = struct`, `Canvas.Checkpoint`
//! - `Canvas.init(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark) Allocator.Error!Canvas`, `Canvas.deinit(c: *Canvas) void`
//! - `Canvas.commit(c: *Canvas, net: u32, pts: []const Pt) Allocator.Error!bool`, `Canvas.fits(c: *const Canvas, net: u32, a: Pt, b: Pt) bool`
//! - `Canvas.wall(c: *Canvas) void`
//! - `Canvas.leaf(c: *Canvas, kind: sch.NodeKind, net: u32, at: Pt, faces: Side) Allocator.Error!void`
//! - `Canvas.stub(c: *Canvas, kind: sch.NodeKind, net: u32, from: Pt, side: Side, d: i32) Allocator.Error!bool`, `Canvas.markAt(c: *Canvas, kind: sch.NodeKind, p: u32, toward: []const Side, d: i32) Allocator.Error!bool`
//! - `Canvas.labelAt(c: *Canvas, p: u32) Allocator.Error!void`, `Canvas.port(c: *Canvas, net: u32, from: Pt, side: Side) Allocator.Error!void`, `Canvas.onNet(c: *const Canvas, net: u32, at: Pt) bool`
//! - `Canvas.middle2(c: *const Canvas) i32`
//! - `Canvas.save(c: *const Canvas) Checkpoint`, `Canvas.restore(c: *Canvas, cp: Checkpoint) void`
//! - `pub const Line = struct`, `Line.of(pts: []const Pt) Line`, `Line.push(l: *Line, p: Pt) void`, `Line.slice(l: *const Line) []const Pt`
//! - `pub fn pinAt(s: *const Schematic, p: u32) Pt`, `pub fn topLeft(s: *const Schematic, pins: []const u32) usize`
//! - `pub fn stepPt(p: Pt, side: Side, d: i32) Pt`
//! - `pub fn linesFit(c: *const Canvas, net: u32, lines: []const Line) bool`
//! - `pub fn ways(s: *const Schematic, pins: []const u32, lines: []const Line, at: Pt) u4`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const maze = @import("maze.zig");
const config = @import("config.zig");

const Side = library.Side;
const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const none = sch.none;

/// The drawing's lengths in the target's units: `config.Layout` times the
/// symbols' unit, each rounded up to a whole unit and at least 1, so the
/// drawing stays on integers and mirrors exactly.
pub const Lengths = struct {
    /// The symbols' unit: the grain of trunk tracks and the router's lattice.
    unit: i32,
    stack: i32,
    series: i32,
    rail: i32,
    terminal: i32,
    label: i32,
    tap: i32,
    clearance: i32,
    bend_cost: i32,
    cross_cost: i32,
    /// How far a supply bar runs past its outer pins: `rail`, or 0 with
    /// `rail_past` off.
    past: i32,

    /// `layout`'s lengths for symbols of `unit`. Asserts a positive unit.
    pub fn of(layout: config.Layout, unit: i32) Lengths {
        assert(unit > 0);
        var out: Lengths = undefined;
        out.unit = unit;
        inline for (@typeInfo(config.Layout).@"struct".field_names, @typeInfo(config.Layout).@"struct".field_types) |f, T| {
            if (T != f32) continue; // a switch, not a length
            const v: f32 = @field(layout, f);
            assert(v >= 0);
            const scaled = @ceil(v * @as(f32, @floatFromInt(unit)));
            @field(out, f) = @max(1, @as(i32, @intFromFloat(@min(scaled, 1 << 20))));
        }
        out.past = if (layout.rail_past) out.rail else 0;
        assert(out.stack >= 1 and out.clearance >= 1);
        return out;
    }
};

/// One wire to draw: a polyline of at most six points, as a `Route` holds.
pub const Line = struct {
    pts: [6]Pt = undefined,
    len: u8 = 0,

    /// A line through `pts`.
    pub fn of(pts: []const Pt) Line {
        var l: Line = .{};
        for (pts) |p| l.push(p);
        return l;
    }
    /// Adds a point; asserts room.
    pub fn push(l: *Line, p: Pt) void {
        assert(l.len < l.pts.len);
        l.pts[l.len] = p;
        l.len += 1;
    }
    /// The points; asserts at least one.
    pub fn slice(l: *const Line) []const Pt {
        assert(l.len >= 1);
        return l.pts[0..l.len];
    }
};

/// One schematic's drawing in progress: `init`, draw, `deinit`.
pub const Canvas = struct {
    gpa: Allocator,
    s: *Schematic,
    /// The nodes' points; `s.xy` is kept in step with it.
    xy: *std.ArrayList([2]f32),
    len: Lengths,
    /// The devices' symbols.
    boxes: []const Rect,
    /// Per net: a rail (supply or ground).
    rails: []bool,
    /// Every net's wires and points: pins, wire ends and bends, labels,
    /// terminals.
    segs: std.ArrayList(maze.Wire) = .empty,
    points: std.ArrayList(maze.Mark) = .empty,
    /// Per net, the side a `*@ port` line puts its port on; empty for none.
    port_side: []const ?Side = &.{},

    /// How much was drawn, to go back to.
    pub const Checkpoint = struct { segs: usize, points: usize, routes: usize, nodes: usize };

    /// A canvas over `s` with every pin on it as a point of its net, and the
    /// `hidden` ones (a MOS body: drawn on its symbol, never wired).
    pub fn init(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark) Allocator.Error!Canvas {
        assert(xy.items.len == s.nodes.len);
        assert(len.unit > 0);
        const rails = try gpa.alloc(bool, s.roles.len);
        for (rails, s.roles) |*r, role| r.* = role.isRail();
        var c: Canvas = .{ .gpa = gpa, .s = s, .xy = xy, .len = len, .boxes = boxes, .rails = rails };
        errdefer c.deinit();
        for (s.pins.items(.net), 0..) |net, p| try c.points.append(gpa, .{ .at = pinAt(s, @intCast(p)), .net = net });
        try c.points.appendSlice(gpa, hidden);
        return c;
    }

    /// Frees what `init` took; the schematic keeps what was drawn.
    pub fn deinit(c: *Canvas) void {
        c.gpa.free(c.rails);
        c.segs.deinit(c.gpa);
        c.points.deinit(c.gpa);
    }

    /// Draws the polyline `pts` (two points or more) for `net` when every
    /// piece fits; returns whether it did, with nothing drawn when not. A
    /// `Route` holds six points: a longer polyline is drawn as several, each
    /// from the last one's end. Allocation failure leaves all drawn rows
    /// unchanged; their storage capacity may grow.
    pub fn commit(c: *Canvas, net: u32, pts: []const Pt) Allocator.Error!bool {
        assert(pts.len >= 2);
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| if (!c.fits(net, a, b)) return false;
        // Each six-point route owns at most five segments. Its first point
        // is retained too, including the shared tip between route chunks.
        const pieces = 1 + (pts.len - 2) / 5;
        try c.s.routes.ensureUnusedCapacity(c.s.arena.allocator(), pieces);
        try c.segs.ensureUnusedCapacity(c.gpa, pts.len - 1);
        try c.points.ensureUnusedCapacity(c.gpa, pts.len - 1 + pieces);
        const before = c.segs.items.len;
        defer assert(c.segs.items.len == before + pts.len - 1);
        var k: usize = 0;
        while (k + 1 < pts.len) : (k += 5) {
            const piece = pts[k..@min(k + 6, pts.len)];
            var route: sch.Route = .{ .pts = undefined, .len = @intCast(piece.len), .net = net };
            for (piece, 0..) |p, i| route.pts[i] = p.toF();
            c.s.routes.appendAssumeCapacity(route);
            for (piece[0 .. piece.len - 1], piece[1..]) |a, b| c.segs.appendAssumeCapacity(.{ .a = a, .b = b, .net = net });
            for (piece) |p| c.points.appendAssumeCapacity(.{ .at = p, .net = net });
        }
        return true;
    }

    /// Whether `net` may have the wire from `a` to `b`, along one row or
    /// column.
    pub fn fits(c: *const Canvas, net: u32, a: Pt, b: Pt) bool {
        assert(a.x == b.x or a.y == b.y);
        const r = Rect.fromCorners(a, b);
        for (c.points.items) |m| if (m.net != net and r.contains(m.at)) return false;
        for (c.segs.items) |g| {
            if (g.net == net) continue;
            const q = Rect.fromCorners(g.a, g.b);
            if (g.wall and r.intersects(q)) return false;
            // An end of ours on their wire, or one of theirs on ours.
            if (q.contains(a) or q.contains(b) or r.contains(g.a) or r.contains(g.b)) return false;
            // Overlap along one line.
            if ((a.y == b.y) == (g.a.y == g.b.y) and r.intersects(q)) return false;
        }
        for (c.boxes) |bx| {
            // Through a body: its interior, its pins' edge excluded.
            const inner = bx.grow(-1);
            if (inner.min.x > inner.max.x or inner.min.y > inner.max.y) continue;
            if (crossesInterior(inner, a, b)) return false;
        }
        return true;
    }

    /// A terminal or label node at `at`, its one pin facing `faces` (the
    /// wire it ends).
    pub fn leaf(c: *Canvas, kind: sch.NodeKind, net: u32, at: Pt, faces: Side) Allocator.Error!void {
        const s = c.s;
        const node = try s.addNode(.{ .kind = kind, .ref = net, .group = none });
        try c.xy.append(s.arena.allocator(), at.toF());
        // The list may have moved: pin points are read through `s.xy`.
        s.xy = c.xy.items;
        assert(s.xy.len == s.nodes.len);
        _ = try s.addPin(.{ .home = node, .side = faces, .net = net, .device = none, .index = 0 });
        try c.points.append(c.gpa, .{ .at = at, .net = net });
    }

    /// Makes the wire piece drawn last a wall, which no other net's wire
    /// crosses: the stub between a rail pin and its symbol (a person's
    /// symbol sits on its pin; 3 of 16,030 such stubs in 5,263 hand-drawn
    /// schematics are crossed). Asserts a piece was drawn.
    pub fn wall(c: *Canvas) void {
        assert(c.segs.items.len > 0);
        c.segs.items[c.segs.items.len - 1].wall = true;
    }

    /// A `kind` node at the end of a stub of `d` out from `from` toward
    /// `side`, which a port, a rail symbol and a name each are; false, with
    /// nothing drawn, when the stub does not fit.
    pub fn stub(c: *Canvas, kind: sch.NodeKind, net: u32, from: Pt, side: Side, d: i32) Allocator.Error!bool {
        const end = stepPt(from, side, d);
        if (!try c.commit(net, &.{ from, end })) return false;
        try c.leaf(kind, net, end, side.opposite());
        return true;
    }

    /// A `kind` node on a stub of `d` out from pin `p`, toward the first of
    /// `toward` whose stub fits. When none does, a label on the pin itself,
    /// and false.
    pub fn markAt(c: *Canvas, kind: sch.NodeKind, p: u32, toward: []const Side, d: i32) Allocator.Error!bool {
        const at = pinAt(c.s, p);
        const net = c.s.pins.items(.net)[p];
        for (toward) |side| if (try c.stub(kind, net, at, side, d)) return true;
        try c.leaf(.label, net, at, c.s.pins.items(.side)[p].opposite());
        return false;
    }

    /// A label on a stub from pin `p`, or on the pin when the stub does not
    /// fit.
    pub fn labelAt(c: *Canvas, p: u32) Allocator.Error!void {
        _ = try c.markAt(.label, p, &.{c.s.pins.items(.side)[p]}, c.len.label);
    }

    /// An output's or input's port on a stub out from `from`: toward the
    /// side a `port` line asks, else `side`, else up, else down, the first
    /// whose stub does not run back along the net's own wire (the node
    /// between two parts in series has its port off the line). When the
    /// stub does not fit, a label at `from`, or at the net's top-left pin
    /// when `from` is where another net's wire crosses (a label there would
    /// join the two).
    pub fn port(c: *Canvas, net: u32, from: Pt, side: Side) Allocator.Error!void {
        assert(c.s.roles[net] == .output or c.s.roles[net] == .input);
        const asked = if (c.port_side.len > 0) c.port_side[net] orelse side else side;
        // A stub over the net's own wire is no stub: the symbol would stand
        // on the wire, and a netlister reads the two as apart.
        const free: ?Side = for ([_]Side{ asked, side, .up, .down }) |t| {
            if (!c.along(net, from, t)) break t;
        } else null;
        if (free) |t| if (try c.stub(.terminal, net, from, t, c.len.terminal)) return;
        if (c.fits(net, from, from)) {
            try c.leaf(.label, net, from, (free orelse asked).opposite());
        } else {
            // Every pin of the net drawn so far, a symbol's or a name's too.
            var all: std.ArrayList(u32) = .empty;
            defer all.deinit(c.gpa);
            for (c.s.pins.items(.net), 0..) |n, p| if (n == net) try all.append(c.gpa, @intCast(p));
            try c.labelAt(all.items[topLeft(c.s, all.items)]);
        }
    }

    /// Whether a stub of `terminal` out from `from` toward `side` runs along
    /// a wire of `net`, or ends on one: its first step or its far end is on
    /// the net's wire.
    fn along(c: *const Canvas, net: u32, from: Pt, side: Side) bool {
        return c.onNet(net, stepPt(from, side, 1)) or c.onNet(net, stepPt(from, side, c.len.terminal));
    }

    /// Whether `at` is on a wire of `net` drawn so far.
    pub fn onNet(c: *const Canvas, net: u32, at: Pt) bool {
        for (c.segs.items) |g| if (g.net == net and Rect.fromCorners(g.a, g.b).contains(at)) return true;
        return false;
    }

    /// Twice the middle of the devices, along x.
    pub fn middle2(c: *const Canvas) i32 {
        var lo: i32 = std.math.maxInt(i32);
        var hi: i32 = std.math.minInt(i32);
        for (c.boxes) |b| {
            lo = @min(lo, b.min.x);
            hi = @max(hi, b.max.x);
        }
        return lo + hi;
    }

    /// How much is drawn now, for `restore`.
    pub fn save(c: *const Canvas) Checkpoint {
        return .{ .segs = c.segs.items.len, .points = c.points.items.len, .routes = c.s.routes.items.len, .nodes = c.s.nodes.len };
    }

    /// Takes back the wires drawn since `cp`; asserts no node came since.
    pub fn restore(c: *Canvas, cp: Checkpoint) void {
        assert(c.s.nodes.len == cp.nodes);
        assert(c.segs.items.len >= cp.segs and c.s.routes.items.len >= cp.routes);
        c.segs.shrinkRetainingCapacity(cp.segs);
        c.points.shrinkRetainingCapacity(cp.points);
        c.s.routes.shrinkRetainingCapacity(cp.routes);
    }
};

/// Where the layout routes a pin to: on its node's line, at its side's reach.
pub fn pinAt(s: *const Schematic, p: u32) Pt {
    assert(p < s.pins.len);
    assert(s.pins.items(.home)[p] < s.xy.len);
    return .round(s.pinPoint(p));
}

/// The index in `pins` of the topmost pin, then the leftmost: a net's first
/// pin by place, so the order of the cards chooses nothing. Asserts a pin.
pub fn topLeft(s: *const Schematic, pins: []const u32) usize {
    assert(pins.len >= 1);
    var first: usize = 0;
    for (pins, 0..) |p, i| if (pinAt(s, p).above(pinAt(s, pins[first]))) {
        first = i;
    };
    return first;
}

/// `d` from `p` toward `side`.
pub fn stepPt(p: Pt, side: Side, d: i32) Pt {
    assert(d >= 0);
    const u = side.unit();
    return .{ .x = p.x + d * u.x, .y = p.y + d * u.y };
}

/// Whether every line fits for `net` (`Canvas.fits`).
pub fn linesFit(c: *const Canvas, net: u32, lines: []const Line) bool {
    for (lines) |*l| {
        const pts = l.slice();
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| if (!c.fits(net, a, b)) return false;
    }
    return true;
}

/// The ways a net leaves `at`, bit `@backingInt(side)` for each `Side`:
/// along each of its `lines` (one ending there is one way, one through it
/// two) and, for each of its `pins` standing there, toward the pin's device,
/// back from the side the pin faces. Zero for a point off them all.
pub fn ways(s: *const Schematic, pins: []const u32, lines: []const Line, at: Pt) u4 {
    var out: u4 = 0;
    for (pins) |p| {
        if (pinAt(s, p).eql(at)) out |= @as(u4, 1) << @backingInt(s.pins.items(.side)[p].opposite());
    }
    for (lines) |*l| {
        const pts = l.slice();
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| {
            const r = Rect.fromCorners(a, b);
            if (!r.contains(at)) continue;
            out |= @as(u4, @intFromBool(r.min.x < at.x)) | @as(u4, @intFromBool(r.max.x > at.x)) << 1 |
                @as(u4, @intFromBool(r.min.y < at.y)) << 2 | @as(u4, @intFromBool(r.max.y > at.y)) << 3;
        }
    }
    return out;
}

// ---- private ----

/// An axis-aligned segment runs inside a rectangle somewhere.
fn crossesInterior(r: Rect, a: Pt, b: Pt) bool {
    assert(r.min.x <= r.max.x);
    assert(a.x == b.x or a.y == b.y);
    const s = Rect.fromCorners(a, b);
    return s.intersects(r) and !(s.min.x == s.max.x and (s.min.x == r.min.x or s.min.x == r.max.x)) and !(s.min.y == s.max.y and (s.min.y == r.min.y or s.min.y == r.max.y));
}

fn commitAllocation(gpa: Allocator) !void {
    const testing = std.testing;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{"a"}, .device_pin_count = &.{}, .roles = &.{.internal} };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    var c = try Canvas.init(gpa, &s, &xy, .of(.{}, 40), &.{}, &.{});
    defer c.deinit();
    try testing.expect(try c.commit(0, &.{ .{ .x = -20, .y = 0 }, .zero }));
    const before = c.save();
    const route = s.routes.items[0];
    const segment = c.segs.items[0];
    const points = [2]maze.Mark{ c.points.items[0], c.points.items[1] };
    // Independent count: 79 segments occupy sixteen routes; each route
    // records one more point than its segments, including shared tips.
    var stairs: [80]Pt = undefined;
    for (&stairs, 0..) |*p, i| p.* = .{ .x = @intCast(10 * ((i + 1) / 2)), .y = @intCast(10 * (i / 2)) };
    const drawn = c.commit(0, &stairs) catch |err| {
        try testing.expectEqualDeep(before, c.save());
        try testing.expectEqual(route.len, s.routes.items[0].len);
        try testing.expectEqualSlices([2]f32, route.pts[0..route.len], s.routes.items[0].pts[0..route.len]);
        try testing.expectEqualDeep(segment, c.segs.items[0]);
        try testing.expectEqualDeep(points, c.points.items[0..2].*);
        return err;
    };
    try testing.expect(drawn);
    try testing.expectEqual(17, s.routes.items.len);
    try testing.expectEqual(80, c.segs.items.len);
    try testing.expectEqual(97, c.points.items.len);
}

test "lengths: units scale to whole target units, at least 1" {
    const at40 = Lengths.of(.{ .stack = 1 }, 40);
    try std.testing.expectEqual(40, at40.stack);
    try std.testing.expectEqual(20, at40.label);
    try std.testing.expectEqual(10, at40.clearance);
    try std.testing.expectEqual(80, at40.cross_cost);
    // Rounded up, never to 0: a unit of 3 and a zero length.
    const at3 = Lengths.of(.{ .stack = 0 }, 3);
    try std.testing.expectEqual(2, at3.label);
    try std.testing.expectEqual(1, at3.clearance);
    try std.testing.expectEqual(1, at3.stack);
}

test "canvas: a polyline longer than a route holds is drawn as several, whole or not at all" {
    const gpa = std.testing.allocator;
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "a", "b" }, .device_pin_count = &.{}, .roles = &.{ .internal, .internal } };
    defer s.deinit();
    var xy: std.ArrayList([2]f32) = .empty;
    // Net b has a point at (60, 80).
    var c: Canvas = try .init(gpa, &s, &xy, .of(.{}, 40), &.{}, &.{.{ .at = .{ .x = 60, .y = 80 }, .net = 1 }});
    defer c.deinit();
    // The oracle, by hand: nine points of a staircase are a route of six
    // and one of four, the sixth point in both.
    var stairs: [9]Pt = undefined;
    for (&stairs, 0..) |*p, i| p.* = .{ .x = @intCast(10 * ((i + 1) / 2)), .y = @intCast(10 * (i / 2)) };
    try std.testing.expect(try c.commit(0, &stairs));
    try std.testing.expectEqual(2, s.routes.items.len);
    try std.testing.expectEqual(6, s.routes.items[0].len);
    try std.testing.expectEqual(4, s.routes.items[1].len);
    try std.testing.expectEqual(stairs[5].toF(), s.routes.items[1].pts[0]);
    try std.testing.expectEqual(stairs[8].toF(), s.routes.items[1].pts[3]);
    try std.testing.expectEqual(8, c.segs.items.len);
    // Seven points whose last piece runs through net b's point: the first
    // six fit, and nothing is drawn.
    const through = [_]Pt{ .{ .x = 0, .y = 50 }, .{ .x = 10, .y = 50 }, .{ .x = 10, .y = 60 }, .{ .x = 20, .y = 60 }, .{ .x = 20, .y = 80 }, .{ .x = 30, .y = 80 }, .{ .x = 90, .y = 80 } };
    try std.testing.expect(!try c.commit(0, &through));
    try std.testing.expectEqual(2, s.routes.items.len);
    try std.testing.expectEqual(8, c.segs.items.len);
    try std.testing.expect(try c.commit(0, through[0..6]));
}

test "canvas: allocation failure preserves existing routes segments and points" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, commitAllocation, .{});
}
