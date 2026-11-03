//! What is drawn so far (issue #8, stage 4): every net's wires and points
//! over the placed devices, and the one way to add to them. In: a
//! `Schematic` whose devices are placed and pinned, and the devices'
//! boxes. Out: its routes, and terminal and label nodes.
//!
//! A wire is drawn only where it fits: through no device's body, along no
//! other net's wire, onto no other net's point, and with no end on another
//! net's wire; crossing one is allowed. Every pin is a point of its net
//! from the start, so no wire passes through another net's pin.
//!
//! Contents:
//! - `pub const Canvas = struct`, `Canvas.Checkpoint`
//! - `Canvas.init(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), gap: i32, boxes: []const Rect) Allocator.Error!Canvas`, `Canvas.deinit(c: *Canvas) void`
//! - `Canvas.commit(c: *Canvas, net: u32, pts: []const Pt) Allocator.Error!bool`, `Canvas.fits(c: *const Canvas, net: u32, a: Pt, b: Pt) bool`
//! - `Canvas.leaf(c: *Canvas, kind: sch.NodeKind, net: u32, at: Pt, faces: Side) Allocator.Error!void`
//! - `Canvas.labelAt(c: *Canvas, p: u32) Allocator.Error!void`, `Canvas.port(c: *Canvas, net: u32, from: Pt, side: Side) Allocator.Error!void`
//! - `Canvas.middle2(c: *const Canvas) i32`
//! - `Canvas.save(c: *const Canvas) Checkpoint`, `Canvas.restore(c: *Canvas, cp: Checkpoint) void`
//! - `pub fn pinAt(s: *const Schematic, p: u32) Pt`
//! - `pub fn stepPt(p: Pt, side: Side, d: i32) Pt`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const layout = @import("layout.zig");
const maze = @import("maze.zig");

const Side = library.Side;
const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const none = sch.none;

/// One schematic's drawing in progress: `init`, draw, `deinit`.
pub const Canvas = struct {
    gpa: Allocator,
    s: *Schematic,
    /// The nodes' points; `s.xy` is kept in step with it.
    xy: *std.ArrayList([2]f32),
    /// The room beside a device.
    gap: i32,
    /// The devices' symbols.
    boxes: []const Rect,
    /// Per net: a rail (supply or ground).
    rails: []bool,
    /// Every net's wires and points: pins, wire ends and bends, labels,
    /// terminals.
    segs: std.ArrayList(maze.Wire) = .empty,
    points: std.ArrayList(maze.Mark) = .empty,

    /// How much was drawn, to go back to.
    pub const Checkpoint = struct { segs: usize, points: usize, routes: usize, nodes: usize };

    /// A canvas over `s` with every pin on it as a point of its net.
    pub fn init(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), gap: i32, boxes: []const Rect) Allocator.Error!Canvas {
        assert(xy.items.len == s.nodes.len);
        assert(gap > 0);
        const rails = try gpa.alloc(bool, s.roles.len);
        for (rails, s.roles) |*r, role| r.* = role == .supply or role == .sink;
        var c: Canvas = .{ .gpa = gpa, .s = s, .xy = xy, .gap = gap, .boxes = boxes, .rails = rails };
        errdefer c.deinit();
        for (s.pins.items(.net), 0..) |net, p| try c.points.append(gpa, .{ .at = pinAt(s, @intCast(p)), .net = net });
        return c;
    }

    /// Frees what `init` took; the schematic keeps what was drawn.
    pub fn deinit(c: *Canvas) void {
        c.gpa.free(c.rails);
        c.segs.deinit(c.gpa);
        c.points.deinit(c.gpa);
    }

    /// Draws the polyline `pts` (two to six points) for `net` when every
    /// piece fits; returns whether it did.
    pub fn commit(c: *Canvas, net: u32, pts: []const Pt) Allocator.Error!bool {
        assert(pts.len >= 2 and pts.len <= 6);
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| if (!c.fits(net, a, b)) return false;
        const before = c.segs.items.len;
        defer assert(c.segs.items.len == before + pts.len - 1);
        var route: sch.Route = .{ .pts = undefined, .len = @intCast(pts.len), .net = net, .kind = .join, .id = none, .straight = true, .owners = .{ none, none, none } };
        for (pts, 0..) |p, i| route.pts[i] = toF(p);
        try c.s.routes.append(c.s.arena.allocator(), route);
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| try c.segs.append(c.gpa, .{ .a = a, .b = b, .net = net });
        for (pts) |p| try c.points.append(c.gpa, .{ .at = p, .net = net });
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
            // An end of ours on their wire, or one of theirs on ours.
            if (q.contains(a) or q.contains(b) or r.contains(g.a) or r.contains(g.b)) return false;
            // Overlap along one line.
            if ((a.y == b.y) == (g.a.y == g.b.y) and r.intersects(q)) return false;
        }
        for (c.boxes) |bx| {
            // Through a body: its interior, its pins' edge excluded.
            const inner: Rect = .{ .min = .{ .x = bx.min.x + 1, .y = bx.min.y + 1 }, .max = .{ .x = bx.max.x - 1, .y = bx.max.y - 1 } };
            if (inner.min.x > inner.max.x or inner.min.y > inner.max.y) continue;
            if (crossesInterior(inner, a, b)) return false;
        }
        return true;
    }

    /// A terminal or label node at `at`, its one pin facing `faces` (the
    /// wire it ends).
    pub fn leaf(c: *Canvas, kind: sch.NodeKind, net: u32, at: Pt, faces: Side) Allocator.Error!void {
        const s = c.s;
        const node = try s.addNode(.{ .kind = kind, .ref = net, .group = none, .x_key = 0, .y_key = 0 });
        try c.xy.append(s.arena.allocator(), toF(at));
        // The list may have moved: pin points are read through `s.xy`.
        s.xy = c.xy.items;
        assert(s.xy.len == s.nodes.len);
        _ = try s.addPin(.{ .home = node, .side = faces, .net = net, .device = none, .index = 0 });
        try c.points.append(c.gpa, .{ .at = at, .net = net });
    }

    /// A label on a half-gap stub from pin `p`, or on the pin when the stub
    /// does not fit.
    pub fn labelAt(c: *Canvas, p: u32) Allocator.Error!void {
        const at = pinAt(c.s, p);
        const side = c.s.pins.items(.side)[p];
        const net = c.s.pins.items(.net)[p];
        const end = stepPt(at, side, @divFloor(c.gap, 2));
        const stub = try c.commit(net, &.{ at, end });
        try c.leaf(.label, net, if (stub) end else at, side.opposite());
    }

    /// An output's port a gap out from `from` toward `side`, or a label at
    /// `from` when the stub does not fit.
    pub fn port(c: *Canvas, net: u32, from: Pt, side: Side) Allocator.Error!void {
        assert(c.s.roles[net] == .output);
        const end = stepPt(from, side, c.gap);
        if (try c.commit(net, &.{ from, end })) {
            try c.leaf(.terminal, net, end, side.opposite());
        } else {
            try c.leaf(.label, net, from, side.opposite());
        }
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
    return toPt(layout.pinPoint(s, p));
}

/// `d` from `p` toward `side`.
pub fn stepPt(p: Pt, side: Side, d: i32) Pt {
    assert(d >= 0);
    return switch (side) {
        .left => .{ .x = p.x - d, .y = p.y },
        .right => .{ .x = p.x + d, .y = p.y },
        .up => .{ .x = p.x, .y = p.y - d },
        .down => .{ .x = p.x, .y = p.y + d },
    };
}

// ---- private ----

/// An axis-aligned segment runs inside a rectangle somewhere.
fn crossesInterior(r: Rect, a: Pt, b: Pt) bool {
    assert(r.min.x <= r.max.x);
    assert(a.x == b.x or a.y == b.y);
    const s = Rect.fromCorners(a, b);
    return s.intersects(r) and !(s.min.x == s.max.x and (s.min.x == r.min.x or s.min.x == r.max.x)) and !(s.min.y == s.max.y and (s.min.y == r.min.y or s.min.y == r.max.y));
}

fn toPt(p: [2]f32) Pt {
    return .{ .x = @intFromFloat(@round(p[0])), .y = @intFromFloat(@round(p[1])) };
}

fn toF(p: Pt) [2]f32 {
    return .{ @floatFromInt(p.x), @floatFromInt(p.y) };
}
