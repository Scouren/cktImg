//! Stage 4 of issue #8: a drawing from the skeleton. In: the netlist, its
//! roles and a symbol library. Out: a laid-out `Schematic`, as
//! `Placed.init` reads one: every drawn device oriented and placed, its
//! pins, terminal symbols, wires, labels, dots and no-connect crosses.
//!
//! - Orientation: the flips that put a vertical device's upper end up and
//!   its gate on the skeleton's side, and a bridge's first pin toward its
//!   first net's devices.
//! - Coordinates: each lattice row and column as wide as the widest device
//!   in it, with room for a port or label on a side a gate faces, and the
//!   `config.Layout` lengths between neighbours; mirrored columns as wide as
//!   each other, so the drawing keeps the skeleton's symmetry.
//! - Wires, terminals and labels: `wires.zig`.
//!
//! Contents:
//! - `pub fn lay(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout) !Schematic`
//! - `pub fn draw(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton) !void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");
const wires = @import("wires.zig");
const netlines = @import("netlines.zig");
const pinned = @import("pinned.zig");
const hints = @import("hints.zig");
const routes = @import("routes.zig");
const maze = @import("maze.zig");
const canvas = @import("canvas.zig");
const compact = @import("compact.zig");
const thin = @import("thin.zig");
const relay = @import("relay.zig");
const config = @import("config.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Library = library.Library;
const Orient = library.Orient;
const Side = library.Side;
const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const Role = sch.Role;
const Skeleton = skeleton.Skeleton;
const Structure = structure.Structure;
const Lengths = canvas.Lengths;
const none = sch.none;

/// How often the drawing is wired again after naming the nets that cross
/// too many wires: a wire gone may free a path that crosses anew.
const thin_rounds = 3;

/// Lattice column and row → coordinate.
const Geo = struct {
    xs: []const i32,
    ys: []const i32,
};

/// The stages in one call: the structure (`structure.analyze`), the
/// skeleton (`skeleton.place`), then `draw`.
pub fn lay(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout) !Schematic {
    var s = try sch.initDevices(gpa, nl, roles, lib);
    errdefer s.arena.deinit();
    const a = s.arena.allocator();
    const st = try structure.analyze(gpa, a, nl, roles);
    const sk = try skeleton.place(gpa, a, nl, roles, &st, .{ .shelf = layout.shelf });
    // `place`'s skeletons always hold.
    skeleton.validate(&sk, nl) catch unreachable;
    try drawValid(gpa, &s, nl, layout, &st, &sk);
    return s;
}

/// The drawing of a skeleton: each device oriented and placed, its nets
/// wired, into `s` (from `schematic.initDevices`). `st` and `sk` are
/// `structure.analyze`'s and `skeleton.place`'s, a caller's edits between
/// the stages included: a skeleton the drawing cannot use is refused
/// (`skeleton.Invalid`) before anything is drawn.
pub fn draw(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton) !void {
    try skeleton.validate(sk, nl);
    try drawValid(gpa, s, nl, layout, st, sk);
}

// ---- private ----

fn drawValid(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton) !void {
    // The deck's drawing lines; their verdicts are the report's to give.
    const sa = s.arena.allocator();
    const scratch = try sa.alloc(?hints.Verdict, nl.hints.len);
    @memset(scratch, null);
    const ats = try pinned.read(sa, nl, s.lib.unit, sk.drawn, scratch);
    s.refdes = try pinned.sides(sa, nl, scratch);
    orientAll(s, nl, sk);
    const len = Lengths.of(layout, s.lib.unit);
    const lines = try netlines.read(sa, nl, s.roles, s.lib.unit, scratch);
    // Each drawn device's point: the lattice's.
    const n = nl.graph.edgeCount();
    const at = try gpa.alloc([2]f32, n);
    defer gpa.free(at);
    @memset(at, .{ 0, 0 });
    var placed_all = true;
    {
        const geo = try coordinates(gpa, s, nl, sk, len);
        defer gpa.free(geo.xs);
        defer gpa.free(geo.ys);
        for (at, 0..) |*p, d| if (sk.drawn[d]) {
            p.* = .{ @floatFromInt(geo.xs[@intCast(sk.x[d])]), @floatFromInt(geo.ys[@intCast(sk.y[d])]) };
            placed_all = placed_all and ats[d] != null;
        };
        // A drawing relaid: its stays anchor the lattice's lines, and only
        // what the deck's structure no longer puts there is laid again.
        const weak = try gpa.alloc(bool, nl.hints.len);
        defer gpa.free(weak);
        for (weak, nl.hints) |*w, h| w.* = h.weak and h.verb == .at;
        if (std.mem.indexOfScalar(bool, weak, true) != null) {
            placed_all = try relay.place(gpa, s, sk, weak, geo.xs, geo.ys, ats, at);
        }
    }
    var xy: std.ArrayList([2]f32) = .empty;
    // Closed up: the drawing as the engine alone makes it (the deck's `at`,
    // `route` and `via` lines are in the finished drawing's coordinates, so
    // they wait), squeezed; the devices' places there are the placement.
    // Its wires are scaffolding: the real ones are drawn below, on the
    // canvas, so every guarantee holds by construction.
    if (layout.compact and !placed_all) {
        const no_ats = try gpa.alloc(?pinned.At, n);
        defer gpa.free(no_ats);
        @memset(no_ats, null);
        var own = lines;
        own.routes = &.{};
        try wireUp(gpa, s, nl, sk, st, len, at, no_ats, &own, &xy);
        try compact.squeeze(gpa, s, len, try drawnAxis2(gpa, s, sk));
        const boxes = try deviceBoxes(gpa, s, nl, sk);
        defer gpa.free(boxes);
        const clear = clear: for (boxes, 0..) |a, i| {
            for (boxes[i + 1 ..]) |b| if (a.intersects(b)) break :clear false;
        } else true;
        // ponytail: an overlap after the squeeze keeps the lattice's places.
        if (clear) for (at, 0..) |*p, d| if (sk.drawn[d]) {
            p.* = s.xy[s.deviceNode(@intCast(d)).?];
        };
        wipe(s, &xy);
    }
    try keepAts(gpa, s, nl, sk, at, ats);
    // Wired; then a net crossing too many wires is named and the drawing
    // wired again without it, which may free a path for another.
    // ponytail: thinned on the finished places only, so a relaid drawing
    // thins alike; the closing up still leaves room for the named nets'
    // wires. Thin the scaffolding too if that room shows.
    const style = try gpa.dupe(netlines.Style, lines.style);
    defer gpa.free(style);
    var thinned = lines;
    thinned.style = style;
    // A net between two shelves is joined by name, each shelf's pins wired.
    for (style, s.roles, 0..) |*sty, role, net| {
        if (sty.* != .auto or role != .internal) continue;
        var first: ?u32 = null;
        for (nl.graph.incident(netlist.VertexId.from(@intCast(net)))) |e| {
            if (!sk.drawn[e.index()]) continue;
            if (first == null) first = sk.shelf[e.index()];
            if (sk.shelf[e.index()] != first.?) sty.* = .cut;
        }
    }
    for (0..thin_rounds + 1) |round| {
        try wireUp(gpa, s, nl, sk, st, len, at, ats, &thinned, &xy);
        const mirror = drawnMirror(s, sk, st);
        if (round == thin_rounds or !try thin.name(gpa, s.routes.items, s.roles, if (mirror) |m| m.net_mate else null, layout.cross_max, style)) break;
        wipe(s, &xy);
    }
    try noConnects(gpa, s);
    assert(s.xy.len == s.nodes.len);
}

/// The drawing's nodes, pins and wires taken off again, its devices too.
fn wipe(s: *Schematic, xy: *std.ArrayList([2]f32)) void {
    s.nodes.shrinkRetainingCapacity(0);
    s.pins.shrinkRetainingCapacity(0);
    s.routes.clearRetainingCapacity();
    xy.clearRetainingCapacity();
    s.xy = &.{};
    @memset(s.labeled, false);
}

/// The devices at `at` (an `at` line's place first), then every net wired.
fn wireUp(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, st: *const Structure, len: Lengths, at: []const [2]f32, ats: []const ?pinned.At, lines: *const netlines.NetLines, xy: *std.ArrayList([2]f32)) !void {
    try placeDevices(s, nl, sk, at, ats, xy);
    s.xy = xy.items;
    const boxes = try deviceBoxes(gpa, s, nl, sk);
    defer gpa.free(boxes);
    const hidden = try hiddenPins(gpa, s, nl, sk);
    defer gpa.free(hidden);
    try wires.wire(gpa, s, xy, len, boxes, hidden, drawnMirror(s, sk, st), st.net_rank, lines);
    s.xy = xy.items;
}

/// Keeps each `at` whose symbol, at its place and turn, overlaps no other
/// drawn device's (the preferred of two `at` devices stays), and turns the
/// kept ones; drops the rest (`ats[d] = null`). The report says which.
fn keepAts(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, at: []const [2]f32, ats: []?pinned.At) !void {
    const n = nl.graph.edgeCount();
    const info = s.devices.slice();
    const boxes = try gpa.alloc(Rect, n);
    defer gpa.free(boxes);
    const order = try hints.admitOrder(gpa, nl.hints);
    defer gpa.free(order);
    for (0..n) |d| {
        if (!sk.drawn[d]) continue;
        const bbox = s.lib.at(info.items(.class)[d]).bbox();
        boxes[d] = if (ats[d]) |a|
            (a.orient orelse info.items(.orient)[d]).applyRect(bbox).translate(a.origin)
        else
            info.items(.orient)[d].applyRect(bbox).translate(toPt(at[d]).sub(info.items(.grid)[d]));
    }
    // The least preferred `at` gives way first, and stands where the
    // lattice has it: another `at` may be on that place, and gives way in
    // turn, until none overlaps.
    var dropped = true;
    var passes: usize = 0;
    while (dropped) : (passes += 1) {
        assert(passes <= nl.hints.len);
        dropped = false;
        var k = order.len;
        while (k > 0) {
            k -= 1;
            if (nl.hints[order[k]].verb != .at) continue;
            const d = (nl.device(nl.hints[order[k]].args[0]) orelse continue).index();
            const a = ats[d] orelse continue;
            if (a.line != order[k]) continue;
            for (0..n) |e| {
                if (e == d or !sk.drawn[e] or !boxes[d].intersects(boxes[e])) continue;
                ats[d] = null;
                boxes[d] = info.items(.orient)[d].applyRect(s.lib.at(info.items(.class)[d]).bbox()).translate(toPt(at[d]).sub(info.items(.grid)[d]));
                dropped = true;
                break;
            }
        }
    }
    for (0..n) |d| {
        const o = (ats[d] orelse continue).orient orelse continue;
        for ([_]sch.Orientation{ .vertical, .horizontal }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |f| {
            if (!std.meta.eql(Orient.flipped(if (form == .vertical) .left else .r0, f[0], f[1]), o)) continue;
            info.items(.orientation)[d] = form;
            info.items(.flip_x)[d] = f[0];
            info.items(.flip_y)[d] = f[1];
        };
    }
    sch.settleDevices(s, &nl.graph);
}

fn isTransistor(kind: netlist.DeviceKind) bool {
    return switch (kind) {
        .mosfet, .bjt, .jfet, .mesfet => true,
        else => false,
    };
}

/// Kept and driver flags, then each drawn device's flips: the first of the
/// four that puts its upper end up and its gate on the skeleton's side (a
/// vertical device), or its first pin toward its first net's devices (a
/// bridge).
fn orientAll(s: *Schematic, nl: *const Netlist, sk: *const Skeleton) void {
    const c = &nl.graph;
    const info = s.devices.slice();
    assert(info.len == c.edgeCount());
    assert(sk.drawn.len == c.edgeCount());
    for (0..c.edgeCount()) |d| {
        info.items(.kept)[d] = sk.drawn[d];
        // A device with pins the skeleton leaves out is a driver (R3).
        info.items(.driver)[d] = c.members(EdgeId.from(d)).len > 0 and !sk.drawn[d];
        const vertical = sk.drawn[d] and sk.form[d] == .vertical;
        info.items(.orientation)[d] = if (vertical) .vertical else .horizontal;
        info.items(.flip_x)[d] = false;
        info.items(.flip_y)[d] = false;
        if (!sk.drawn[d]) continue;
        const class = s.lib.at(info.items(.class)[d]);
        const base: Orient = if (vertical) .left else .r0;
        for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |f| {
            if (!fits(nl, sk, class, @intCast(d), Orient.flipped(base, f[0], f[1]), vertical)) continue;
            info.items(.flip_x)[d] = f[0];
            info.items(.flip_y)[d] = f[1];
            break;
        }
    }
    sch.settleDevices(s, c);
}

fn fits(nl: *const Netlist, sk: *const Skeleton, class: library.Class, d: u32, o: Orient, vertical: bool) bool {
    assert(sk.drawn[d]);
    if (vertical) assert(sk.upper[d] != none);
    const pins = nl.graph.members(EdgeId.from(d));
    if (vertical) {
        var up = false;
        for (pins, 0..) |net, i| {
            const side = class.side(i, o) orelse continue;
            if (side == .up and net.index() == sk.upper[d]) up = true;
            if (side == .down and net.index() == sk.upper[d] and net.index() != sk.lower[d]) return false;
        }
        if (!up) return false;
        if (!isTransistor(nl.graph.edges.items(.kind)[d]) or pins.len < 2) return true;
        const g = class.side(1, o) orelse return true;
        return (g == .right) == sk.gate_right[d];
    }
    if (pins.len != 2) return true;
    const s0 = class.side(0, o) orelse return true;
    // A pin on a net it shares with one other flat part of its row faces
    // that part: two parts in series are one line, as people draw them
    // (52.7% of 1,397 such pairs in 5,263 hand-drawn schematics; the mean
    // of a far outer net turned one of them end for end in 201).
    for (pins, 0..) |net, i| {
        const other = seriesNeighbour(nl, sk, net.index(), d) orelse continue;
        if (sk.x[other] == sk.x[d]) continue;
        return ((i == 0) == (s0 == .left)) == (sk.x[other] < sk.x[d]);
    }
    // A pin alone on its net (a port's) has no column to face: the other
    // pin faces its net from where the part stands.
    for (pins, 0..) |net, i| {
        if (!alone(nl, sk, net.index(), d) or alone(nl, sk, pins[1 - i].index(), d)) continue;
        const there = meanX(nl, sk, pins[1 - i].index(), d);
        if (there == 2 * @as(i64, sk.x[d])) break;
        return ((i == 1) == (s0 == .left)) == (there < 2 * @as(i64, sk.x[d]));
    }
    return (s0 == .left) == (meanX(nl, sk, pins[0].index(), d) <= meanX(nl, sk, pins[1].index(), d));
}

/// Whether no drawn device but `d` is on `net`.
fn alone(nl: *const Netlist, sk: *const Skeleton, net: u32, d: u32) bool {
    for (nl.graph.incident(netlist.VertexId.from(net))) |e| {
        if (e.index() != d and sk.drawn[e.index()]) return false;
    }
    return true;
}

/// The one other drawn device on `net` when it is a flat two-pin part in
/// `d`'s row and the net joins just the two; else null.
fn seriesNeighbour(nl: *const Netlist, sk: *const Skeleton, net: u32, d: u32) ?u32 {
    var other: ?u32 = null;
    for (nl.graph.incident(netlist.VertexId.from(net))) |e| {
        const v = e.index();
        if (v == d or !sk.drawn[v]) continue;
        if (other != null) return null;
        other = v;
    }
    const o = other orelse return null;
    if (sk.form[o] != .horizontal or sk.y[o] != sk.y[d] or nl.graph.members(EdgeId.from(o)).len != 2) return null;
    return o;
}

/// The mean column of the drawn devices other than `skip` on `net`, twice.
fn meanX(nl: *const Netlist, sk: *const Skeleton, net: u32, skip: u32) i64 {
    assert(net < nl.graph.vertexCount());
    assert(skip < nl.graph.edgeCount());
    var sum: i64 = 0;
    var count: i64 = 0;
    for (nl.graph.incident(netlist.VertexId.from(net))) |e| {
        const v = e.index();
        if (v == skip or !sk.drawn[v]) continue;
        sum += sk.x[v];
        count += 1;
    }
    return if (count == 0) 0 else @divFloor(2 * sum, count);
}

/// Each lattice column as wide as its widest device's reach on each side,
/// plus room for a port, label or rail symbol (its stub and a unit) where a
/// side pin on a net driven from outside, an output or a rail faces that
/// side; rows as tall as their tallest device (its pins' reach, or its body
/// where that reaches more than `stack` past them), plus a port's or rail
/// symbol's stub where such a pin faces up or down (the supply's bar over
/// the top aside). `len.series` between neighbouring columns, `len.stack`
/// between rows.
fn coordinates(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths) !Geo {
    const c = &nl.graph;
    var w: usize = 1;
    var h: usize = 1;
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        w = @max(w, @as(usize, @intCast(sk.x[d])) + 1);
        h = @max(h, @as(usize, @intCast(sk.y[d])) + 1);
    };
    // Per column, room left and right; per row, up and down.
    const room = try gpa.alloc([2]i32, w + h);
    defer gpa.free(room);
    @memset(room, .{ 0, 0 });
    const cols = room[0..w];
    const rows = room[w..];
    const reach = s.devices.items(.reach);
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        const r = reach[d];
        const x: usize = @intCast(sk.x[d]);
        const y: usize = @intCast(sk.y[d]);
        var left = r[@backingInt(Side.left)];
        var right = r[@backingInt(Side.right)];
        // A body reaching farther than `stack` past its pins (a block with
        // pins on its sides only) takes its own room: two such in one
        // column touched, a pin of one on a pin of the other.
        const info = s.devices.slice();
        const body = info.items(.orient)[d].applyRect(s.lib.at(info.items(.class)[d]).bbox()).translate((Pt{ .x = 0, .y = 0 }).sub(info.items(.grid)[d]));
        var up = r[@backingInt(Side.up)];
        var down = r[@backingInt(Side.down)];
        if (-body.min.y > up + len.stack) up = -body.min.y;
        if (body.max.y > down + len.stack) down = body.max.y;
        for (c.members(EdgeId.from(d)), 0..) |net, i| {
            const side = s.pinSide(@intCast(d), i) orelse continue;
            switch (s.roles[net.index()]) {
                .input, .bias, .output => {
                    if (side == .left) left = r[@backingInt(Side.left)] + len.terminal + len.unit;
                    if (side == .right) right = r[@backingInt(Side.right)] + len.terminal + len.unit;
                    if (side == .up) up = r[@backingInt(Side.up)] + len.terminal;
                    if (side == .down) down = r[@backingInt(Side.down)] + len.terminal;
                },
                .sink, .supply => |role| {
                    if (side == .left) left = r[@backingInt(Side.left)] + len.rail + len.unit;
                    if (side == .right) right = r[@backingInt(Side.right)] + len.rail + len.unit;
                    if (side == .down) down = r[@backingInt(Side.down)] + len.rail;
                    if (side == .up and role == .sink) up = r[@backingInt(Side.up)] + len.rail;
                },
                .internal => {},
            }
        }
        cols[x] = .{ @max(cols[x][0], left), @max(cols[x][1], right) };
        rows[y] = .{ @max(rows[y][0], up), @max(rows[y][1], down) };
    };
    // Mirrored columns as wide as each other, so the drawing keeps the
    // skeleton's symmetry exactly.
    if (sk.axis2) |a2| for (0..w) |k| {
        const m = a2 - @as(i32, @intCast(k));
        if (m < 0 or m >= w) continue;
        const mk: usize = @intCast(m);
        const left = @max(cols[k][0], cols[mk][1]);
        const right = @max(cols[k][1], cols[mk][0]);
        cols[k] = .{ left, right };
        cols[mk] = .{ right, left };
    };
    const xs = try gpa.alloc(i32, w);
    errdefer gpa.free(xs);
    const ys = try gpa.alloc(i32, h);
    errdefer gpa.free(ys);
    // An empty lattice column takes no room: devices stand `series` apart.
    const used = try gpa.alloc(bool, w);
    defer gpa.free(used);
    @memset(used, false);
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        used[@intCast(sk.x[d])] = true;
    };
    var prev: ?usize = null;
    for (xs, cols, used, 0..) |*x, need, u, k| {
        x.* = if (prev) |p| xs[p] + (if (u) cols[p][1] + len.series + need[0] else 0) else need[0];
        if (u) prev = k;
    }
    for (ys, rows, 0..) |*y, need, k| y.* = if (k == 0) need[0] else ys[k - 1] + rows[k - 1][1] + len.stack + need[0];
    for (1..w) |k| assert(xs[k] >= xs[k - 1]);
    for (1..h) |k| assert(ys[k] > ys[k - 1]);
    return .{ .xs = xs, .ys = ys };
}

/// A node per drawn device at its cell, and a pin per drawn card pin. A pin
/// whose terminal is off its device's line for that side (an op-amp's
/// second input) gets a copy node on its own line, so no two pins of one
/// side meet at one point.
fn placeDevices(s: *Schematic, nl: *const Netlist, sk: *const Skeleton, places: []const [2]f32, ats: []const ?pinned.At, xy: *std.ArrayList([2]f32)) !void {
    const a = s.arena.allocator();
    const c = &nl.graph;
    const info = s.devices.slice();
    for (0..c.edgeCount()) |d| {
        if (!sk.drawn[d]) continue;
        // An `at` line's origin, else the layout's point.
        const at: [2]f32 = if (ats[d]) |p| toF(p.origin.add(info.items(.grid)[d])) else places[d];
        const node = try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = none });
        try xy.append(a, at);
        const class = s.lib.at(info.items(.class)[d]);
        const o = info.items(.orient)[d];
        const grid = info.items(.grid)[d];
        for (c.members(EdgeId.from(d)), 0..) |net, i| {
            if (i >= sch.max_pins or i >= class.terminals.len) continue;
            const side = s.pinSide(@intCast(d), i) orelse continue;
            if (sch.referencePin(s, @intCast(d), i, net.index())) continue;
            // The terminal, from the device's grid point.
            const t = o.apply(class.terminals[i].at).sub(grid);
            const across: f32 = @floatFromInt(if (side.isHorizontal()) t.y else t.x);
            var home = node;
            if (across != 0) {
                home = try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = node });
                try xy.append(a, if (side.isHorizontal()) .{ at[0], at[1] + across } else .{ at[0] + across, at[1] });
            }
            _ = try s.addPin(.{ .home = home, .side = side, .net = net.index(), .device = @intCast(d), .index = @intCast(i) });
        }
    }
    assert(xy.items.len == s.nodes.len);
    for (s.pins.items(.home)) |h| assert(h < s.nodes.len);
}

/// The drawing's mirror: twice the x its mated devices stand about, when
/// every mated pair agrees; null when none stands mirrored.
fn drawnMirror(s: *const Schematic, sk: *const Skeleton, st: *const structure.Structure) ?routes.Mirror {
    if (sk.axis2 == null) return null;
    var axis2: ?i32 = null;
    for (st.device_mate, 0..) |m, d| {
        if (m == none or m == d or !sk.drawn[d] or !sk.drawn[m]) continue;
        const a = toPt(s.xy[s.deviceNode(@intCast(d)).?]).x + toPt(s.xy[s.deviceNode(m).?]).x;
        if (axis2 != null and axis2.? != a) return null;
        axis2 = a;
    }
    return if (axis2) |a| .{ .axis2 = a, .net_mate = st.net_mate } else null;
}

/// Twice the x the skeleton's mirrored columns stand about in the drawing,
/// when every pair of them agrees (an `at` line may move one off it); else
/// null. The skeleton mirrors a pair's columns even where the circuit has
/// no symmetry of its own (a mirror load), which `drawnMirror` asks for.
fn drawnAxis2(gpa: Allocator, s: *const Schematic, sk: *const Skeleton) !?i32 {
    const a2 = sk.axis2 orelse return null;
    const x = try gpa.alloc(?i32, sk.drawn.len);
    defer gpa.free(x);
    for (x, 0..) |*v, d| v.* = if (sk.drawn[d]) toPt(s.xy[s.deviceNode(@intCast(d)).?]).x else null;
    var axis2: ?i32 = null;
    for (x, 0..) |xd, d| for (x[d..], d..) |xe, e| {
        if (xd == null or xe == null or sk.x[d] + sk.x[e] != a2) continue;
        if (axis2 != null and axis2.? != xd.? + xe.?) return null;
        axis2 = xd.? + xe.?;
    };
    return axis2;
}

/// The points of pins `Placed` draws on their symbol with no wire (a MOS
/// body, an op-amp's reference, a card pin its class lacks): no other net's
/// wire may touch them.
fn hiddenPins(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) ![]maze.Mark {
    var out: std.ArrayList(maze.Mark) = .empty;
    errdefer out.deinit(gpa);
    const info = s.devices.slice();
    assert(sk.drawn.len == nl.graph.edgeCount());
    for (0..nl.graph.edgeCount()) |d| {
        if (!sk.drawn[d]) continue;
        const origin = toPt(s.xy[s.deviceNode(@intCast(d)).?]).sub(info.items(.grid)[d]);
        const class = s.lib.at(info.items(.class)[d]);
        const o = info.items(.orient)[d];
        for (nl.graph.members(EdgeId.from(d)), 0..) |net, i| {
            const shown = i < sch.max_pins and i < class.terminals.len and s.pinSide(@intCast(d), i) != null and
                !sch.referencePin(s, @intCast(d), i, net.index());
            if (shown) continue;
            const at = if (i < class.terminals.len) origin.add(o.apply(class.terminals[i].at)) else origin;
            try out.append(gpa, .{ .at = at, .net = net.index() });
        }
    }
    for (out.items) |m| assert(m.net < nl.graph.vertexCount());
    return out.toOwnedSlice(gpa);
}

fn deviceBoxes(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) ![]Rect {
    var out: std.ArrayList(Rect) = .empty;
    errdefer out.deinit(gpa);
    const info = s.devices.slice();
    for (0..nl.graph.edgeCount()) |d| {
        if (!sk.drawn[d]) continue;
        const node = s.deviceNode(@intCast(d)).?;
        const origin = toPt(s.xy[node]).sub(info.items(.grid)[d]);
        const r = info.items(.orient)[d].applyRect(s.lib.at(info.items(.class)[d]).bbox()).translate(origin);
        assert(r.min.x <= r.max.x and r.min.y <= r.max.y);
        try out.append(gpa, r);
    }
    assert(out.items.len <= nl.graph.edgeCount());
    return out.toOwnedSlice(gpa);
}

fn toPt(p: [2]f32) Pt {
    return .{ .x = @intFromFloat(@round(p[0])), .y = @intFromFloat(@round(p[1])) };
}

fn toF(p: Pt) [2]f32 {
    return .{ @floatFromInt(p.x), @floatFromInt(p.y) };
}

/// A no-connect cross on each device pin with no other pin on its net.
fn noConnects(gpa: Allocator, s: *Schematic) !void {
    const count = try gpa.alloc(u32, s.net_name.len);
    defer gpa.free(count);
    @memset(count, 0);
    for (s.pins.items(.net)) |n| count[n] += 1;
    for (s.pins.items(.net)) |n| assert(count[n] >= 1);
    s.no_connects.clearRetainingCapacity();
    for (s.pins.items(.net), s.pins.items(.device), 0..) |n, d, p| {
        if (d != none and count[n] == 1) try s.no_connects.append(s.arena.allocator(), @intCast(p));
    }
}
