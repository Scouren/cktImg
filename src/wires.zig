//! Wires (issue #8, stage 4): every net of a placed drawing, as terminal
//! symbols, wires and labels, by the book's patterns. In: a `Schematic`
//! whose devices are placed and pinned, the devices' boxes, and the
//! drawing's mirror if it has one. Out: its routes, terminal and label
//! nodes, and the nets drawn as labels.
//!
//! - Rails: a ground symbol under each pin on ground; the supply a bar over
//!   its pins with one symbol. Inputs: pins standing near each other on one
//!   wire with one port at its left end, else a port at each pin. Outputs:
//!   a port at the outer end of the net's wire.
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
//! drawing does not depend on card order. The deck's net lines
//! (`netlines.zig`) come first: `first` nets lead, `label` names a net,
//! `wire` wires it by the pattern named (names where none fits), `port`
//! sets a port's side and `rail` a rail's bar (ground too) or a symbol per
//! pin.
//!
//! Contents:
//! - `pub fn wire(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror, net_rank: []const u32, lines: *const NetLines) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const routes = @import("routes.zig");
const maze = @import("maze.zig");
const netlines = @import("netlines.zig");
const trunk = @import("trunk.zig");
const NetLines = netlines.NetLines;

const Side = library.Side;
const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const Role = sch.Role;
const Canvas = canvas.Canvas;
const Lengths = canvas.Lengths;
const Line = canvas.Line;

const linesFit = canvas.linesFit;
const pinAt = canvas.pinAt;
const stepPt = canvas.stepPt;

/// The half perimeter, in units, of the box around an input's pins up to
/// which they are wired to one port; farther apart, each pin gets a port.
/// People wire 87% of their inputs of two pins or more to one symbol and
/// cut a connection past 5.5 to 7.5 units (5,274 drawings).
// ponytail: one cut for every pin kind; per-edge cuts (gate to gate 3,
// gate to other 5.5, other 7.5) once the pitch is the human one.
const input_reach = 6;

/// Draws every net of `s`; `xy` holds the nodes' points (`s.xy` is kept
/// in step with it), `gap` the room beside a device, `hidden` the points of
/// pins drawn on their symbol with no wire.
pub fn wire(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror, net_rank: []const u32, lines: *const NetLines) Allocator.Error!void {
    assert(net_rank.len == s.net_name.len);
    assert(lines.style.len == s.net_name.len);
    var c = try Canvas.init(gpa, s, xy, len, boxes, hidden);
    defer c.deinit();
    c.port_side = lines.port;
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
    const Order = struct { roles: []const Role, rank: []const u32 };
    std.mem.sort(u32, order, Order{ .roles = s.roles, .rank = net_rank }, struct {
        fn first(r: Role) u8 {
            return switch (r) {
                .supply, .sink => 0,
                .input, .bias => 1,
                .internal, .output => 2,
            };
        }
        fn lt(o: Order, x: u32, y: u32) bool {
            const fx = first(o.roles[x]);
            const fy = first(o.roles[y]);
            if (fx != fy) return fx < fy;
            return o.rank[x] < o.rank[y];
        }
    }.lt);
    // Pinned routes and vias claim their room before anything else.
    const routed = try gpa.alloc(bool, n_nets);
    defer gpa.free(routed);
    @memset(routed, false);
    for (lines.routes) |r| {
        if (try pinned(&c, r, pins_of[r.net].items)) routed[r.net] = true;
    }
    // The `first` nets lead, in their order.
    var lead: usize = 0;
    for (lines.first) |net| {
        const at = std.mem.indexOfScalar(u32, order, net).?;
        std.mem.copyBackwards(u32, order[lead + 1 .. at + 1], order[lead..at]);
        order[lead] = net;
        lead += 1;
    }
    var waiting: std.ArrayList(u32) = .empty;
    defer waiting.deinit(gpa);
    // Bias nets a line wires: each named once, as a gate line is, so its
    // wire joins the source drawn apart under that name.
    var named: std.ArrayList(u32) = .empty;
    defer named.deinit(gpa);
    for (order) |net| {
        const pins = pins_of[net].items;
        if (pins.len == 0) continue;
        const axis2: ?i32 = if (mirror) |m| (if (m.net_mate[net] == net) m.axis2 else null) else null;
        const style = lines.style[net];
        if (routed[net]) {
            // The router joins its other pins to the pinned wire.
            if (s.roles[net] == .bias) try named.append(gpa, net);
            continue;
        }
        if (style == .label) {
            for (pins) |p| try c.labelAt(p);
            s.labeled[net] = true;
            continue;
        }
        switch (s.roles[net]) {
            .sink => if (lines.rail[net] == .bar) try bar(&c, pins, .down) else for (pins) |p| try terminal(&c, p, null),
            .input => if (pins.len < 2 or (style == .auto and !near(&c, pins)) or !try patterned(&c, net, pins, axis2, style)) {
                for (pins) |p| try terminal(&c, p, lines.port[net]);
            },
            .supply => if (lines.rail[net] == .each) {
                for (pins) |p| try terminal(&c, p, null);
            } else try bar(&c, pins, .up),
            .bias => if (style == .auto) try bias(&c, net, pins) else {
                if (!try patterned(&c, net, pins, axis2, style)) try waiting.append(gpa, net);
                try named.append(gpa, net);
            },
            .internal, .output => if (!try patterned(&c, net, pins, axis2, style)) try waiting.append(gpa, net),
        }
    }
    try routes.draw(&c, waiting.items, pins_of, mirror);
    try joinRouted(&c, routed, pins_of);
    // On its top-left pin, so card order changes nothing.
    for (named.items) |net| if (!s.labeled[net]) {
        var best = pins_of[net].items[0];
        for (pins_of[net].items) |p| {
            const a = pinAt(s, p);
            const b = pinAt(s, best);
            if (a.y < b.y or (a.y == b.y and a.x < b.x)) best = p;
        }
        try c.labelAt(best);
    };
    assert(xy.items.len == s.nodes.len);
}

// ---- private ----

/// Draws route or via `r` of a net with pins `pins`, whole or not at all: a
/// route must end on one of the pins; a via runs from the net's top-left pin
/// through each point in turn (an L each way), skipping one it cannot reach.
/// Whether anything was drawn.
fn pinned(c: *Canvas, r: netlines.Route, pins: []const u32) !bool {
    if (pins.len == 0) return false;
    if (!r.via) {
        const ends = for (pins) |p| {
            const at = pinAt(c.s, p);
            if (at.eql(r.pts[0]) or at.eql(r.pts[r.pts.len - 1])) break true;
        } else false;
        if (!ends) return false;
        const cp = c.save();
        if (!try commitThrough(c, r.net, pins, r.pts)) {
            c.restore(cp);
            return false;
        }
        return true;
    }
    var from = pinAt(c.s, pins[0]);
    for (pins) |p| {
        const at = pinAt(c.s, p);
        if (at.y < from.y or (at.y == from.y and at.x < from.x)) from = at;
    }
    var drew = false;
    for (r.pts) |to| {
        if (to.eql(from)) continue;
        const reached = for ([_]Pt{ .{ .x = to.x, .y = from.y }, .{ .x = from.x, .y = to.y } }) |corner| {
            const path: []const Pt = if (corner.eql(from) or corner.eql(to)) &.{ from, to } else &.{ from, corner, to };
            const cp = c.save();
            if (try commitThrough(c, r.net, pins, path)) break true;
            c.restore(cp);
        } else false;
        if (!reached) continue;
        from = to;
        drew = true;
    }
    return drew;
}

/// Commits polyline `pts` of `net`, each of its pins the polyline passes
/// made a point of it (a pin joins a wire only at a point), in pieces of six
/// points at most. False when a piece does not fit; the caller restores.
fn commitThrough(c: *Canvas, net: u32, pins: []const u32, pts: []const Pt) !bool {
    var all: std.ArrayList(Pt) = .empty;
    defer all.deinit(c.gpa);
    for (pts, 0..) |b, k| {
        if (k > 0) {
            const a = pts[k - 1];
            // The pins strictly inside a..b, in order along it.
            const step: Pt = .{ .x = std.math.sign(b.x - a.x), .y = std.math.sign(b.y - a.y) };
            var q = a.add(step);
            var guard: usize = 0;
            while (!q.eql(b)) : (q = q.add(step)) {
                guard += 1;
                assert(guard <= 1 << 24);
                for (pins) |p| if (pinAt(c.s, p).eql(q)) {
                    try all.append(c.gpa, q);
                    break;
                };
            }
        }
        try all.append(c.gpa, b);
    }
    var k: usize = 0;
    while (k + 1 < all.items.len) {
        const end = @min(k + 5, all.items.len - 1);
        if (!try c.commit(net, all.items[k .. end + 1])) return false;
        k = end;
    }
    return true;
}

/// Each net a route or via drew: its pins off that wire joined to it by
/// the router (`routes.attach`), its port if an output.
fn joinRouted(c: *Canvas, routed: []const bool, pins_of: []const std.ArrayList(u32)) !void {
    const gpa = c.gpa;
    var off: std.ArrayList(u32) = .empty;
    defer off.deinit(gpa);
    for (routed, 0..) |r, net| {
        if (!r) continue;
        off.clearRetainingCapacity();
        var anchor: ?u32 = null;
        for (pins_of[net].items) |p| {
            if (onNet(c, @intCast(net), pinAt(c.s, p))) {
                anchor = anchor orelse p;
            } else try off.append(gpa, p);
        }
        // A route ends on a pin and a via starts at one: some pin is on it.
        try routes.attach(c, @intCast(net), off.items, anchor.?);
    }
}

/// Whether `at` lies on one of `net`'s wires.
fn onNet(c: *const Canvas, net: u32, at: Pt) bool {
    for (c.segs.items) |g| if (g.net == net and Rect.fromCorners(g.a, g.b).contains(at)) return true;
    return false;
}

/// Whether an input's pins stand near enough to share one wire and one
/// port: the box around them no more than `input_reach` units around half.
fn near(c: *const Canvas, pins: []const u32) bool {
    assert(pins.len >= 1);
    var box: Rect = .point(pinAt(c.s, pins[0]));
    for (pins[1..]) |p| box = box.merge(.point(pinAt(c.s, p)));
    return box.max.x - box.min.x + box.max.y - box.min.y <= input_reach * c.len.unit;
}

/// A wire by the pattern `style` asks (`auto` and `wire`: a ladder, else a
/// trunk); false, with nothing drawn, when it does not fit (or for `route`):
/// the router takes the net.
fn patterned(c: *Canvas, net: u32, pins: []const u32, axis2: ?i32, style: netlines.Style) !bool {
    // One pin: nothing to route; its port, if any, as by default.
    if (pins.len < 2) return try ladder(c, net, pins, axis2) or try trunk.draw(c, net, pins);
    return switch (style) {
        .auto, .wire => try ladder(c, net, pins, axis2) or try trunk.draw(c, net, pins),
        .ladder => try ladder(c, net, pins, axis2),
        .trunk => try trunk.draw(c, net, pins),
        .route => false,
        .label => unreachable,
    };
}

/// A rail's, input's or output's symbol one gap out from the pin, on a
/// stub (toward `want` when a `port` line asks and the stub fits); a label
/// there if the stub would touch something.
fn terminal(c: *Canvas, p: u32, want: ?Side) !void {
    const at = pinAt(c.s, p);
    const side = c.s.pins.items(.side)[p];
    const net = c.s.pins.items(.net)[p];
    if (want) |w| if (w != side) {
        const out = stepPt(at, w, c.len.terminal);
        if (try c.commit(net, &.{ at, out })) return c.leaf(.terminal, net, out, w.opposite());
    };
    const end = stepPt(at, side, if (c.rails[net]) c.len.rail else c.len.terminal);
    if (try c.commit(net, &.{ at, end })) {
        try c.leaf(.terminal, net, end, side.opposite());
    } else {
        try c.leaf(.label, net, at, side.opposite());
        c.s.labeled[net] = true;
    }
}

/// Rail pins facing `out` (up for a supply, down for ground): stubs to a
/// bar a gap past the outermost, one symbol on each unbroken run of the bar
/// at its middle stub. Any other pin: a symbol of its own.
fn bar(c: *Canvas, pins: []const u32, out: Side) !void {
    const s = c.s;
    const gpa = c.gpa;
    assert(out == .up or out == .down);
    var ups: std.ArrayList(u32) = .empty;
    defer ups.deinit(gpa);
    var top: i32 = if (out == .up) std.math.maxInt(i32) else std.math.minInt(i32);
    for (pins) |p| {
        if (s.pins.items(.side)[p] != out) continue;
        try ups.append(gpa, p);
        top = if (out == .up) @min(top, pinAt(s, p).y) else @max(top, pinAt(s, p).y);
    }
    for (pins) |p| if (s.pins.items(.side)[p] != out or ups.items.len < 2) try terminal(c, p, null);
    if (ups.items.len < 2) return;
    const net = s.pins.items(.net)[ups.items[0]];
    const y_bar = if (out == .up) top - c.len.rail else top + c.len.rail;
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
        if (try c.commit(net, &.{ at, .{ .x = at.x, .y = y_bar } })) {
            try on_bar.append(gpa, p);
        } else {
            try terminal(c, p, null);
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
            break :blk x0 == x1 or try c.commit(net, &.{ .{ .x = x0, .y = y_bar }, .{ .x = x1, .y = y_bar } });
        };
        if (joined) continue;
        const mid = pinAt(s, on_bar.items[(run + i) / 2]);
        try c.leaf(.terminal, net, .{ .x = mid.x, .y = y_bar }, out.opposite());
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
