//! Wires (issue #8, stage 4): every net of a placed drawing, as terminal
//! symbols, wires and labels, by the book's patterns. In: a `Schematic`
//! whose devices are placed and pinned, the devices' boxes, and the
//! drawing's mirror if it has one. Out: its routes, terminal and label
//! nodes, and the nets drawn as labels.
//!
//! Human Rules:
//! - wires.1 (choice) Rails are wired first, then the nets driven from
//!   outside (inputs, biases), then the rest, each group in the canonical
//!   net order: a net wired earlier claims its room first, and the order
//!   of the cards chooses nothing. `wire`
//! - wires.2 (choice) A `via` line's wire runs from the net's top-left pin
//!   to each point in turn by one L, along the row first, and skips a
//!   point neither L reaches: the line names points, not the path.
//!   `pinned`
//! - wires.3 (habit) A rail drawn as a bar takes each of its pins that
//!   faces the bar (up for a supply, down for ground) and stands no more
//!   than two units from it; a pin farther off has a symbol of its own.
//!   People: of 9,149 upright supply runs in 5,263 hand-drawn schematics,
//!   97% are no longer. `bar`
//! - wires.4 (unmeasured) A rail pin that does not face its bar, every
//!   pin when fewer than two reach the bar, and a pin whose stub to it
//!   does not fit, each have a rail symbol of their own. `bar`
//! - wires.5 (choice) A rail's bar stands one rail stub (`rail`) past the
//!   outermost of its pins facing it: the outermost pin meets it on the
//!   stub its symbol would have had. `bar`
//! - wires.6 (unmeasured) A rail's bar carries one symbol on each unbroken
//!   run of it, at the run's middle stub. `bar`
//! - wires.7 (habit) A supply bar's run of two stubs or more goes on
//!   `rail` past its outer pins, where that fits. People: 1,258 of 2,506
//!   supply bars (`config.Layout.rail_past`). `bar`
//!   Narrowing: a supply's bar only; a ground drawn as a bar ends on its
//!   outer pins.
//! - wires.8 (unmeasured) No other net's wire crosses a rail's bar or its
//!   run past its pins. `bar`
//! - wires.9 (unmeasured) A rail drawn as a plain bar brings every pin
//!   facing it to the bar however far; where the bar breaks or a pin does
//!   not reach it, each run and each pin off it carries the net's name,
//!   and a bar in one piece carries none. `bar`
//! - wires.10 (habit) A rail symbol on a two-pin part's end stands on the
//!   pin; on any other pin, and a port at a pin, one stub out from it,
//!   toward the side a `port` line asks, else the way the pin faces; a
//!   name on the pin where neither stub fits. People: on the pin 6,883 of
//!   8,367 rail symbols at a two-pin part's end in 5,263 hand-drawn
//!   schematics, 3,612 of 8,921 at a transistor's path end. `terminal`
//!   Narrowing: no name's stub is tried before the pin, as
//!   `Canvas.labelAt` would.
//! - wires.11 (unmeasured) A bias net of two gates facing each other on
//!   one row is one straight gate line between them, named at its middle
//!   (at its first pin when another net's wire crosses the middle).
//!   `ported`
//! - wires.12 (habit) An input's or a bias's pins standing near each other
//!   (the box round them no more than 6 units around half) are one wire
//!   with one port at a free end. People wire 87% of their inputs of two
//!   pins or more to one symbol and cut a connection past 5.5 to 7.5
//!   units (5,274 drawings). `near`
//!   Narrowing: one cut for every pin kind; per-edge cuts (gate to gate 3,
//!   gate to other 5.5, other 7.5) once the pitch is the human one.
//! - wires.13 (habit) An input or a bias whose pins stand farther apart, or
//!   whose wire has no free end for its port, has a port on a stub at each
//!   pin; a bias is never a written name. People: of 4,378 nets named
//!   `vb*` or `bias*` in 5,263 hand-drawn schematics, 3,228 carry port
//!   symbols and none a written name. `ported`
//! - wires.14 (choice) Any other net takes the first pattern that fits: a
//!   ladder, then a column or a trunk (`trunk.zig`); one no pattern fits
//!   is routed (`routes.zig`) after every pattern: a pattern is the shape
//!   a reader knows, the router what is left. `patterned`
//! - wires.15 (unmeasured) An internal net whose pins face each other in
//!   pairs along rows, one pair a row on two rows or more, is a ladder: a
//!   rung between each pair and one upright through them all at the
//!   mirror axis when it lies within every rung, else at the rungs' shared
//!   middle, as a CMFB midpoint meets its gate line. `ladder`
//! - wires.16 (choice) A bias a `wire` line wires, or a `route` or `via`
//!   line pins, carries its name once, at its top-left pin: the name
//!   joins it to its sources drawn apart, and card order chooses nothing.
//!   `wire`
//! - wires.17 (habit) A net joined by name falls into parts, each pin no
//!   farther from another of its part (along x plus along y) than 15, 11
//!   or 6 half units as neither, one or both of the two face sideways.
//!   People: fitted on the connections people wire and name in 5,274
//!   hand-drawn schematics (93.6% of nets right on those held out).
//!   `within`
//! - wires.18 (unmeasured) Each part of two pins or more of a net joined
//!   by name is one trunk with one name at a free end; a pin alone, or a
//!   part no trunk fits, carries the name at each pin. `parts`
//! - wires.19 (choice) A net joined by name that is all one part is named
//!   at every pin: it was cut because its one wire crossed too much.
//!   `parts`
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
const topLeft = canvas.topLeft;

/// The half perimeter, in units, of the box around an input's pins up to
/// which they are wired to one port; farther apart, each pin gets a port.
/// People wire 87% of their inputs of two pins or more to one symbol and
/// cut a connection past 5.5 to 7.5 units (5,274 drawings).
// ponytail: one cut for every pin kind; per-edge cuts (gate to gate 3,
// gate to other 5.5, other 7.5) once the pitch is the human one.
const input_reach = 6;

/// The longest stub from a rail pin to its bar, in units: a pin farther
/// from the bar carries a symbol of its own. Of 9,149 upright supply runs
/// in 5,263 hand-drawn schematics, 97% are no longer.
const rail_reach = 2;

/// The longest connection kept as wire in a net joined by name, in half
/// units, by how many of its two pins face sideways (a gate, a base):
/// neither, one, both. Fitted on the connections people wire and name in
/// 5,274 hand-drawn schematics (93.6% of nets right on those held out).
const cut = [3]u32{ 15, 11, 6 };

/// What a net is drawn as by its role, in the order the kinds are drawn.
const Drawn = enum(u8) {
    /// A supply or a ground: its symbols, or a bar.
    rail,
    /// An input or a bias, driven from outside: its port.
    port,
    /// An internal net or an output: a wire.
    wire,

    fn of(role: Role) Drawn {
        return switch (role) {
            .supply, .sink => .rail,
            .input, .bias => .port,
            .internal, .output => .wire,
        };
    }
};

/// Draws every net of `s`; `xy` holds the nodes' points (`s.xy` is kept
/// in step with it), `len` the drawing's lengths, `hidden` the points of
/// pins drawn on their symbol with no wire. Asserts `lines` is
/// `netlines.read`'s of these nets: an entry a net, every rail's bar or
/// symbols chosen, no input styled as a wire.
pub fn wire(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror, net_rank: []const u32, lines: *const NetLines) Allocator.Error!void {
    assert(net_rank.len == s.net_name.len);
    assert(lines.style.len == s.net_name.len);
    assert(lines.port.len == s.net_name.len and lines.rail.len == s.net_name.len);
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
        fn lt(o: Order, x: u32, y: u32) bool {
            const fx = @backingInt(Drawn.of(o.roles[x]));
            const fy = @backingInt(Drawn.of(o.roles[y]));
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
        if (style == .cut) {
            try parts(&c, net, pins);
            s.labeled[net] = true;
            continue;
        }
        switch (Drawn.of(s.roles[net])) {
            // A rail's pins face out along the rows, a supply's up and a
            // ground's down: a symbol at each, or one bar past them all.
            .rail => switch (lines.rail[net]) {
                .each => for (pins) |p| try terminal(&c, p),
                .bar, .plain => |r| try bar(&c, pins, if (s.roles[net] == .supply) .up else .down, r == .plain),
                .auto => unreachable,
            },
            // A bias a line wires (never an input) is a wire like any
            // other, named once.
            .port => if (style == .auto) try ported(&c, net, pins) else {
                assert(s.roles[net] == .bias);
                if (!try patterned(&c, net, pins, axis2, style)) try waiting.append(gpa, net);
                try named.append(gpa, net);
            },
            .wire => if (!try patterned(&c, net, pins, axis2, style)) try waiting.append(gpa, net),
        }
    }
    try routes.draw(&c, waiting.items, pins_of, mirror);
    try joinRouted(&c, routed, pins_of);
    // On its top-left pin, so card order changes nothing.
    for (named.items) |net| if (!s.labeled[net]) {
        const of = pins_of[net].items;
        try c.labelAt(of[topLeft(s, of)]);
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
        for (pins) |p| {
            const at = pinAt(c.s, p);
            if (at.eql(r.pts[0]) or at.eql(r.pts[r.pts.len - 1])) return commitThrough(c, r.net, pins, r.pts);
        }
        return false;
    }
    var from = pinAt(c.s, pins[topLeft(c.s, pins)]);
    var drew = false;
    for (r.pts) |to| {
        if (to.eql(from)) continue;
        const reached = for ([_]Pt{ .{ .x = to.x, .y = from.y }, .{ .x = from.x, .y = to.y } }) |corner| {
            const path: []const Pt = if (corner.eql(from) or corner.eql(to)) &.{ from, to } else &.{ from, corner, to };
            if (try commitThrough(c, r.net, pins, path)) break true;
        } else false;
        if (!reached) continue;
        from = to;
        drew = true;
    }
    return drew;
}

/// Commits polyline `pts` of `net`, each of its pins the polyline passes
/// made a point of it (a pin joins a wire only at a point). False, with
/// nothing drawn, when a piece does not fit.
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
    return c.commit(net, all.items);
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
            if (c.onNet(@intCast(net), pinAt(c.s, p))) {
                anchor = anchor orelse p;
            } else try off.append(gpa, p);
        }
        // A route ends on a pin and a via starts at one: some pin is on it.
        try routes.attach(c, @intCast(net), off.items, anchor.?);
    }
}

/// A net joined by name between its parts: the pins standing near each
/// other (each within `cut` of another of its part) on one trunk with one
/// name; a pin on its own, or a part no trunk fits, a name at each pin.
fn parts(c: *Canvas, net: u32, pins: []const u32) !void {
    assert(pins.len >= 1);
    const gpa = c.gpa;
    // Each pin's part: the least index of a pin in it.
    const part = try gpa.alloc(u32, pins.len);
    defer gpa.free(part);
    for (part, 0..) |*g, i| g.* = @intCast(i);
    var merged = true;
    var rounds: usize = 0;
    while (merged) : (rounds += 1) {
        assert(rounds <= pins.len); // every round but the last joins two parts
        merged = false;
        for (pins, 0..) |p, i| for (pins[i + 1 ..], i + 1..) |q, j| {
            if (part[i] == part[j] or !within(c, p, q)) continue;
            const keep = @min(part[i], part[j]);
            const drop = @max(part[i], part[j]);
            for (part) |*g| {
                if (g.* == drop) g.* = keep;
            }
            merged = true;
        };
    }
    // One part is the whole net, the wire that crossed too much: names.
    if (std.mem.allEqual(u32, part, 0)) {
        for (pins) |p| try c.labelAt(p);
        return;
    }
    var members: std.ArrayList(u32) = .empty;
    defer members.deinit(gpa);
    for (0..pins.len) |g| {
        members.clearRetainingCapacity();
        for (pins, part) |p, of| {
            if (of == g) try members.append(gpa, p);
        }
        if (members.items.len == 0) continue;
        if (members.items.len >= 2 and try trunk.draw(c, net, members.items, .name)) continue;
        for (members.items) |p| try c.labelAt(p);
    }
}

/// Whether two pins of a net stand near enough to stay wired when the net
/// is joined by name: the connections people keep (`cut`).
fn within(c: *const Canvas, p: u32, q: u32) bool {
    const a = pinAt(c.s, p);
    const b = pinAt(c.s, q);
    const sides = c.s.pins.items(.side);
    const sideways = @as(usize, @intFromBool(sides[p].isHorizontal())) + @intFromBool(sides[q].isHorizontal());
    return 2 * (@abs(a.x - b.x) + @abs(a.y - b.y)) <= cut[sideways] * @as(u32, @intCast(c.len.unit));
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
    return switch (if (pins.len < 2) .auto else style) {
        .auto, .wire => try ladder(c, net, pins, axis2) or try trunk.draw(c, net, pins, .port),
        .ladder => try ladder(c, net, pins, axis2),
        .trunk => try trunk.draw(c, net, pins, .port),
        .route => false,
        .label, .cut => unreachable,
    };
}

/// A rail's symbol or a port one gap out from pin `p`, on a stub: toward
/// the side a `port` line asks, then the way the pin faces, the first whose
/// stub fits; a label on the pin itself when neither does. Narrowing: no
/// name's stub is tried before the pin, as `Canvas.labelAt` would.
fn terminal(c: *Canvas, p: u32) !void {
    const side = c.s.pins.items(.side)[p];
    const net = c.s.pins.items(.net)[p];
    const rail = c.rails[net];
    const d = c.s.pins.items(.device)[p];
    // A rail symbol stands on a two-pin part's end, no stub: people 6,883
    // of 8,367; on a transistor's path end 3,612 of 8,921 (the stub stays).
    if (rail and d != sch.none and c.s.device_pin_count[d] == 2) {
        return c.leaf(.terminal, net, pinAt(c.s, p), (c.port_side[net] orelse side).opposite());
    }
    if (try c.markAt(.terminal, p, &.{ c.port_side[net] orelse side, side }, if (rail) c.len.rail else c.len.terminal)) {
        // A rail's stub is a wall.
        if (rail) c.wall();
    } else c.s.labeled[net] = true;
}

/// Rail pins facing `out` (up for a supply, down for ground): stubs to a
/// bar a gap past the outermost, one symbol on each unbroken run of the bar
/// at its middle stub; a supply's run of two or more stubs goes on
/// `len.past` beyond its outer ones where that fits. Any other pin: a symbol of its own. `plain`, the bar
/// is a wire and carries no symbol: where it is in pieces, each run and
/// each pin off it carries the net's name instead.
fn bar(c: *Canvas, pins: []const u32, out: Side, plain: bool) !void {
    const s = c.s;
    const gpa = c.gpa;
    assert(out == .up or out == .down);
    var ups: std.ArrayList(u32) = .empty;
    defer ups.deinit(gpa);
    var top: i32 = if (out == .up) std.math.maxInt(i32) else std.math.minInt(i32);
    for (pins) |p| {
        if (s.pins.items(.side)[p] != out) continue;
        top = if (out == .up) @min(top, pinAt(s, p).y) else @max(top, pinAt(s, p).y);
    }
    // A plain bar is the net's one wire: every pin facing it comes down to
    // it, however far.
    const reach = if (plain) std.math.maxInt(i32) else rail_reach * c.len.unit - c.len.rail;
    for (pins) |p| {
        if (s.pins.items(.side)[p] == out and @abs(pinAt(s, p).y - top) <= reach) try ups.append(gpa, p);
    }
    if (pins.len == 0) return;
    const net = s.pins.items(.net)[pins[0]];
    // Pieces of a plain bar: the pins off it and its runs.
    var pieces: usize = 0;
    for (pins) |p| if (ups.items.len < 2 or std.mem.indexOfScalar(u32, ups.items, p) == null) {
        if (plain) try c.labelAt(p) else try terminal(c, p);
        pieces += 1;
    };
    if (plain and pieces > 0) s.labeled[net] = true;
    if (ups.items.len < 2) return;
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
            if (@abs(at.y - y_bar) <= c.len.rail) c.wall();
            try on_bar.append(gpa, p);
        } else {
            if (plain) try c.labelAt(p) else try terminal(c, p);
            pieces += 1;
        }
    }
    if (on_bar.items.len == 0) return;
    var mids: std.ArrayList(Pt) = .empty;
    defer mids.deinit(gpa);
    // The bar in pieces between stubs, so every joint is a wire's end; a
    // piece that does not fit ends a run, and each run gets a symbol at its
    // middle stub.
    var run: usize = 0;
    for (on_bar.items, 0..) |q, i| {
        const last = i + 1 == on_bar.items.len;
        const joined = !last and blk: {
            const x0 = pinAt(s, q).x;
            const x1 = pinAt(s, on_bar.items[i + 1]).x;
            if (x0 == x1) break :blk true;
            if (!try c.commit(net, &.{ .{ .x = x0, .y = y_bar }, .{ .x = x1, .y = y_bar } })) break :blk false;
            c.wall();
            break :blk true;
        };
        if (joined) continue;
        // A supply's bar runs on past its outer pins, as a rail does.
        const x_lo = pinAt(s, on_bar.items[run]).x;
        if (out == .up and !plain and c.len.past > 0 and x_lo != pinAt(s, q).x) {
            for ([_][2]i32{ .{ x_lo, x_lo - c.len.past }, .{ pinAt(s, q).x, pinAt(s, q).x + c.len.past } }) |e| {
                if (try c.commit(net, &.{ .{ .x = e[0], .y = y_bar }, .{ .x = e[1], .y = y_bar } })) c.wall();
            }
        }
        const mid = pinAt(s, on_bar.items[(run + i) / 2]);
        if (plain) try mids.append(gpa, .{ .x = mid.x, .y = y_bar }) else try c.leaf(.terminal, net, .{ .x = mid.x, .y = y_bar }, out.opposite());
        run = i + 1;
    }
    // A plain bar in one piece is the whole net: a wire, nothing to name.
    if (pieces + mids.items.len < 2) return;
    for (mids.items) |at| try c.leaf(.label, net, at, out.opposite());
    s.labeled[net] = true;
}

/// A net driven from outside (an input, a bias). Pins standing near each
/// other: one trunk, one port out from a free end. Else a port on a stub at
/// each pin, as people draw a bias: of 4,378 nets named `vb*` or `bias*` in
/// 5,263 hand-drawn schematics, 3,228 carry port symbols and none a written
/// name. Before either, a bias of two gates of one row facing each other:
/// a gate line between them, named at its middle.
fn ported(c: *Canvas, net: u32, pins: []const u32) !void {
    const s = c.s;
    assert(pins.len >= 1);
    const bias = s.roles[net] == .bias;
    assert(bias or s.roles[net] == .input);
    if (bias and pins.len == 2) {
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
    // A bias's port stands where a name would, on a name's stub.
    if (pins.len >= 2 and near(c, pins) and try trunk.draw(c, net, pins, if (bias) .name else .port)) return;
    for (pins) |p| try terminal(c, p);
    // A bias's ports are its name written out: it is drawn with labels.
    if (bias) s.labeled[net] = true;
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
