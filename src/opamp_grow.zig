//! The op-amp placement's procedure (`opamp.zig` holds its tables and its
//! door): blocks in signal order, each with its feedback rows, its inputs'
//! trees grown leftward and its load rightward. In: a `Placer` with the
//! netlist's shape. Out: every device placed on a canvas. The shares below
//! are people's, in the hand drawings (5,263 schematics, 199 of this
//! kind).
//!
//! Human Rules:
//! - opamp_grow.1 (habit) The block farthest from the inputs is placed
//!   first, its output pin at the origin; a block that drives it is placed
//!   when its output net is reached, left of it. People: 85% of driven
//!   blocks stand right of their driver. `rootOrder`, `grow`
//! - opamp_grow.2 (habit) The inverting input is on top: the block's
//!   symbol is drawn so (`library.blockFor`), and its feedback then stands
//!   over the block. People: 76%. `block`
//! - opamp_grow.3 (habit) A part from the output to an input lies flat
//!   over the block for the upper pin, under it for the lower; two or three
//!   parts in series back to the output lie in one such row. People: 82%
//!   straight over or under, 96% on their pin's side. `block`, `fbPath`
//! - opamp_grow.4 (unmeasured) A part to a rail from a node of a feedback
//!   row hangs upright under that node, over the block as under it.
//!   `block`
//! - opamp_grow.5 (habit) From a pin's node leftward: parts to a rail
//!   stand upright beside it, the first series part lies level with the
//!   node, the rest stack away from the block; from the output rightward
//!   the same. People: 45% (the first series part level with the node).
//!   `grow`
//! - opamp_grow.6 (unmeasured) On the upper input's net, when the lower
//!   input carries a signal, a part to ground lies flat in the input's row
//!   instead of hanging upright. `grow`
//! - opamp_grow.7 (choice) Of a node's series parts, the one nearest a
//!   block still to be placed goes first, then the larger tree, then the
//!   earlier card: one order, whatever the circuit. `grow`
//! - opamp_grow.8 (unmeasured) A part between two nodes that both stand
//!   lies in the first row past every body between them, or upright beside
//!   them when one is over the other. `close`
//! - opamp_grow.9 (unmeasured) What no block's tree reaches is drawn in a
//!   group of its own, grown from its first net that is no rail; a part
//!   with both ends on rails, or both on one net, hangs upright. `run`
//! - opamp_grow.10 (choice) A body keeps 0.28 unit from every other (the
//!   first level part at a pin only clears a real overlap); a taken place
//!   moves by half a unit: the procedure's clearance and its step.
//!   `Placer.put`
//!
//! Contents:
//! - `pub fn run(p: *Placer) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const opamp = @import("opamp.zig");

const Placer = opamp.Placer;
const P = opamp.P;
const R = opamp.R;
const Link = opamp.Link;
const none = opamp.none;

/// Bodies keep this apart; the first level part at a pin only clears a
/// real overlap.
const gap = 28;
const gap_level = 5;
/// No block or net is this far: the distance of what nothing reaches.
const far = 99;

/// One step of a feedback path: a part, the net it is entered from, the
/// net it leads to.
const Step = struct { part: u32, near: u32, far: u32 };

/// How a part of a node's row is treated: one that leads on, one that
/// joins a node of an earlier group, a rail part lying flat.
const Tag = enum { deeper, link, flat };

/// Places every block and part: the blocks in signal order, each on a
/// group of its own unless an earlier one reached it, then whatever no
/// block's tree reached, each connected rest from its first part.
pub fn run(p: *Placer) Allocator.Error!void {
    for (try rootOrder(p)) |b| {
        if (p.placed[b]) continue;
        try newCanvas(p);
        try block(p, b, 0, 0, -1);
    }
    for (p.two, 0..) |two, d| {
        const t = two orelse continue;
        if (p.placed[d]) continue;
        try newCanvas(p);
        const first: u32 = if (!p.rail[t.a]) t.a else if (!p.rail[t.b]) t.b else none;
        if (first == none or t.a == t.b) {
            _ = try p.put(@intCast(d), .down, 0, 0, .{ .x = -100, .y = 0 }, !p.rail[t.a] or p.rail_up[t.a], gap);
            continue;
        }
        if (p.anch[first] == null) p.anchor(first, .{ .x = 0, .y = 0 });
        try grow(p, first, .{ .x = 0, .y = 0 }, 1, -1, none, false);
        if (!p.placed[d]) _ = try p.put(@intCast(d), .flat, 0, 300, .{ .x = 0, .y = 100 }, true, gap);
    }
    for (p.two, p.blocks, p.placed) |two, blk, placed| assert(placed or (two == null and blk == null));
}

// ---- private ----

fn newCanvas(p: *Placer) Allocator.Error!void {
    try p.canvases.append(p.arena, .{});
    p.cv = @intCast(p.canvases.items.len - 1);
}

/// The blocks, the one farthest from the inputs first; among equals one
/// that drives no other, then the later card.
fn rootOrder(p: *Placer) Allocator.Error![]u32 {
    var names: std.ArrayList(u32) = .empty;
    for (p.blocks, 0..) |b, d| if (b != null) try names.append(p.arena, @intCast(d));
    const dep = try depth(p);
    const drives = try p.arena.alloc(bool, p.blocks.len);
    for (drives, 0..) |*s, d| s.* = p.blocks[d] != null and try succ(p, @intCast(d));
    const Ctx = struct {
        dep: []const u32,
        drives: []const bool,
        fn key(c: @This(), d: u32) [3]i64 {
            return .{ if (c.dep[d] < far) -@as(i64, c.dep[d]) else 1, @intFromBool(c.drives[d]), -@as(i64, d) };
        }
        fn lt(c: @This(), a: u32, b: u32) bool {
            return std.mem.order(i64, &c.key(a), &c.key(b)) == .lt;
        }
    };
    std.sort.insertion(u32, names.items, Ctx{ .dep = dep, .drives = drives }, Ctx.lt);
    return names.items;
}

/// Per block: the parts (a block counts one, input to output) between the
/// circuit's inputs and its nearest input net. The inputs are the ports
/// that are no rail and no block's output, and the nets of the sources.
fn depth(p: *Placer) Allocator.Error![]u32 {
    const nets = p.rail.len;
    const dist = try p.arena.alloc(u32, nets);
    @memset(dist, far);
    var todo: std.ArrayList(u32) = .empty;
    for (0..nets) |x| {
        if (p.rail[x] or p.out_of[x] != none) continue;
        var src = p.port[x];
        for (p.on[x].items) |l| src = src or p.source[l.part];
        if (!src) continue;
        dist[x] = 0;
        try todo.append(p.arena, @intCast(x));
    }
    var head: usize = 0;
    while (head < todo.items.len) : (head += 1) {
        const x = todo.items[head];
        for (p.on[x].items) |l| if (!p.rail[l.other] and dist[l.other] == far) {
            dist[l.other] = dist[x] + 1;
            try todo.append(p.arena, l.other);
        };
        for (p.blocks) |blk| {
            const b = blk orelse continue;
            const reads = for (b.ins[0..b.n_ins]) |i| {
                if (b.pins[i].net == x) break true;
            } else false;
            const o = b.pins[b.out].net;
            if (!reads or dist[o] != far) continue;
            dist[o] = dist[x] + 1;
            try todo.append(p.arena, o);
        }
    }
    const out = try p.arena.alloc(u32, p.blocks.len);
    @memset(out, far);
    for (p.blocks, out) |blk, *o| {
        const b = blk orelse continue;
        for (b.ins[0..b.n_ins]) |i| if (!p.rail[b.pins[i].net]) {
            o.* = @min(o.*, dist[b.pins[i].net]);
        };
    }
    return out;
}

/// Whether block `a`'s output reaches another block's input directly or
/// through one series part.
fn succ(p: *Placer, a: u32) Allocator.Error!bool {
    const o = p.blocks[a].?.pins[p.blocks[a].?.out].net;
    for (p.blocks, 0..) |blk, d| {
        const b = blk orelse continue;
        if (d == a) continue;
        for (b.ins[0..b.n_ins]) |i| {
            const net = b.pins[i].net;
            if (net == o) return true;
            for (p.on[o].items) |l| if (!p.rail[l.other] and l.other == net) return true;
        }
    }
    return false;
}

/// Parts between `net` and the nearest output of a block still to be
/// placed, not through `stop`, a rail or a net that has its node; `far`
/// when there is none.
fn toDriver(p: *Placer, net: u32, stop: u32) Allocator.Error!u32 {
    const seen = try p.arena.alloc(bool, p.rail.len);
    @memset(seen, false);
    seen[stop] = true;
    seen[net] = true;
    var todo: std.ArrayList([2]u32) = .empty;
    try todo.append(p.arena, .{ net, 0 });
    var head: usize = 0;
    while (head < todo.items.len) : (head += 1) {
        const x, const k = todo.items[head];
        if (p.out_of[x] != none and !p.placed[p.out_of[x]]) return k;
        for (p.on[x].items) |l| {
            if (p.placed[l.part] or seen[l.other] or p.rail[l.other] or p.anch[l.other] != null) continue;
            seen[l.other] = true;
            try todo.append(p.arena, .{ l.other, k + 1 });
        }
    }
    return far;
}

/// Devices reached from `net` without passing `stop`, a rail or a net that
/// has its node; a driving block counts five.
fn size(p: *Placer, net: u32, stop: u32) Allocator.Error!u32 {
    const seen = try p.arena.alloc(bool, p.rail.len);
    @memset(seen, false);
    seen[stop] = true;
    seen[net] = true;
    var todo: std.ArrayList(u32) = .empty;
    try todo.append(p.arena, net);
    var count: u32 = 0;
    while (todo.pop()) |x| {
        if (p.out_of[x] != none and !p.placed[p.out_of[x]]) count += 5;
        for (p.on[x].items) |l| {
            if (p.placed[l.part]) continue;
            count += 1;
            if (seen[l.other] or p.rail[l.other] or p.anch[l.other] != null) continue;
            seen[l.other] = true;
            try todo.append(p.arena, l.other);
        }
    }
    return count;
}

/// Whether `net` leads, not through `stop` or a rail, to an input of a
/// block still to be placed.
fn leadsToBlock(p: *Placer, net: u32, stop: u32) Allocator.Error!bool {
    const seen = try p.arena.alloc(bool, p.rail.len);
    @memset(seen, false);
    seen[stop] = true;
    seen[net] = true;
    var todo: std.ArrayList(u32) = .empty;
    try todo.append(p.arena, net);
    while (todo.pop()) |x| {
        if (waits(p, x)) return true;
        for (p.on[x].items) |l| {
            if (seen[l.other] or p.rail[l.other] or p.placed[l.part]) continue;
            seen[l.other] = true;
            try todo.append(p.arena, l.other);
        }
    }
    return false;
}

/// Whether `net` is an input of a block still to be placed.
fn waits(p: *const Placer, net: u32) bool {
    for (p.blocks, p.placed) |blk, placed| {
        const b = blk orelse continue;
        if (placed) continue;
        for (b.ins[0..b.n_ins]) |i| if (b.pins[i].net == net) return true;
    }
    return false;
}

/// Block `d` with its output pin at (`x`, `y0`), then all that hangs on
/// it; a place that is taken moves `away` (up or down) by half units.
fn block(p: *Placer, d: u32, x: i32, y0: i32, away: i32) Allocator.Error!void {
    const b = p.blocks[d].?;
    const ins = b.ins[0..b.n_ins];
    const pin = try p.arena.alloc(P, b.pins.len);
    var y = y0;
    var top: i32 = 0;
    var bot: i32 = 0;
    var xin: i32 = 0;
    var origin: P = .{ .x = 0, .y = 0 };
    var room: R = undefined;
    for (0..opamp.tries) |_| {
        origin = .{ .x = x - b.pins[b.out].off.x, .y = y - b.pins[b.out].off.y };
        top = std.math.maxInt(i32);
        bot = std.math.minInt(i32);
        xin = std.math.maxInt(i32);
        for (b.pins, pin) |bp, *at| {
            at.* = .{ .x = origin.x + bp.off.x, .y = origin.y + bp.off.y };
            // A signal pin keeps half a unit, a wired rail pin its symbol.
            const reach: i32 = if (bp.role == .rail) 75 else 50;
            top = @min(top, at.y - reach);
            bot = @max(bot, at.y + reach);
        }
        for (ins) |i| xin = @min(xin, pin[i].x);
        room = .{ .x0 = xin + 25, .y0 = top, .x1 = x - 25, .y1 = bot };
        if (p.free(room, gap, 20)) break;
        y += away * 50;
    }
    try p.add(d, origin.x, origin.y, .r0, room);
    const onet = b.pins[b.out].net;
    if (p.anch[onet] == null) p.anchor(onet, .{ .x = x, .y = y });
    // The inputs, upper first (`opamp.place` has them so).
    var in_top: i32 = std.math.maxInt(i32);
    var in_bot: i32 = std.math.minInt(i32);
    for (ins) |i| {
        const net = b.pins[i].net;
        in_top = @min(in_top, pin[i].y);
        in_bot = @max(in_bot, pin[i].y);
        // An input on a rail, or alone on its net: its symbol's spot.
        const bare = p.on[net].items.len == 0 and p.out_of[net] == none;
        if (p.rail[net] or bare) try p.canvas().wires.append(p.arena, .{ .x0 = pin[i].x - 70, .y0 = pin[i].y - 20, .x1 = pin[i].x - 30, .y1 = pin[i].y + @as(i32, if (p.rail[net]) 75 else 20) });
    }
    if (ins.len == 2 and !p.rail[b.pins[ins[1]].net] and b.pins[ins[1]].net != onet) p.flat_shunt[b.pins[ins[0]].net] = true;
    // An input's tree: the upper pin's side is over the block (-1), the
    // lower pin's under it; `row` its next feedback row on that side.
    const Tree = struct { net: u32, at: P, side: i32, row: i32 };
    var trees: [2]Tree = undefined;
    var n_trees: usize = 0;
    for (ins, 0..) |i, k| {
        const net = b.pins[i].net;
        if (p.rail[net] or p.anch[net] != null) continue;
        p.anchor(net, pin[i]);
        trees[n_trees] = if (k == 0)
            .{ .net = net, .at = pin[i], .side = -1, .row = @min(top - 75, in_top - 125) }
        else
            .{ .net = net, .at = pin[i], .side = 1, .row = @max(bot + 75, in_bot + 125) };
        n_trees += 1;
        p.pending[net] = true;
    }
    const xc = xin + opamp.roundEven(@as(i64, x - xin) * 43, 2500) * opamp.quarter;
    for (trees[0..n_trees]) |*t| {
        for (p.on[t.net].items) |l| {
            if (l.other != onet or p.placed[l.part]) continue;
            const at = try p.put(l.part, .flat, xc, t.row, .{ .x = 0, .y = t.side * 50 }, p.aOn(l.part, t.net), gap);
            t.row = at.y + t.side * 100;
        }
    }
    for (trees[0..n_trees]) |*t| {
        for (p.on[t.net].items) |l| {
            var buf: [3]Step = undefined;
            const path = fbPath(p, l.part, t.net, l.other, onet, &buf) orelse continue;
            if (path.len == 2 and p.port[l.other]) {
                // The cell's output is past a series part: feedback from there.
                _ = try p.put(path[1].part, .flat, x + 100, y, .{ .x = 0, .y = 50 }, p.aOn(path[1].part, onet), gap);
                p.anchor(l.other, .{ .x = x + 150, .y = y });
                const at = try p.put(l.part, .flat, xc, t.row, .{ .x = 0, .y = t.side * 50 }, p.aOn(l.part, t.net), gap);
                t.row = at.y + t.side * 100;
                continue;
            }
            const k: i32 = @intCast(path.len);
            var hangs = false;
            for (path[0 .. path.len - 1]) |s| for (p.on[s.far].items) |h| {
                hangs = hangs or (p.rail[h.other] and !p.placed[h.part]);
            };
            // A shunt hangs under its row on either side of the block: over
            // it the row stands that much higher, under it the next row lower.
            var row = t.row - @as(i32, if (hangs and t.side < 0) 200 else 0);
            var xs: [3]i32 = undefined;
            for (0..path.len) |i| xs[i] = xc + (6 * @as(i32, @intCast(i)) - 3 * (k - 1)) * opamp.quarter;
            // The whole row moves as one.
            while (for (xs[0..path.len]) |cx| {
                if (!p.free(opamp.partRect(.flat, cx, row, false), gap, 20)) break true;
            } else false) row += t.side * 50;
            for (path, xs[0..path.len]) |s, cx| _ = try p.put(s.part, .flat, cx, row, .{ .x = 0, .y = t.side * 50 }, p.aOn(s.part, s.near), gap);
            for (path[0 .. path.len - 1], xs[0 .. path.len - 1]) |s, cx| {
                p.anchor(s.far, .{ .x = cx + 75, .y = row });
                for (p.on[s.far].items) |h| {
                    if (!p.rail[h.other] or p.placed[h.part]) continue;
                    _ = try p.put(h.part, .down, cx + 75, row + 100, .{ .x = 50, .y = 0 }, p.aOn(h.part, s.far), gap);
                }
            }
            t.row = row + t.side * @as(i32, if (t.side < 0 or !hangs) 100 else 250);
        }
    }
    // The lower pin's tree first: the upper one's shunts go round it.
    var k = n_trees;
    while (k > 0) {
        k -= 1;
        try grow(p, trees[k].net, trees[k].at, trees[k].side, -1, d, true);
    }
    try grow(p, onet, .{ .x = x, .y = y }, 1, 1, d, true);
}

/// Two or three parts in series from input net `net` (first `part`, to
/// `m`) to the block's output `onet`, through nets that hold nothing else
/// in series and no block's pin; null for anything else.
fn fbPath(p: *const Placer, part: u32, net: u32, m: u32, onet: u32, buf: *[3]Step) ?[]const Step {
    buf[0] = .{ .part = part, .near = net, .far = m };
    var len: usize = 1;
    var prev = part;
    var cur = m;
    while (len < 3) {
        if (p.placed[prev] or p.rail[cur] or p.anch[cur] != null or p.out_of[cur] != none or isInput(p, cur)) return null;
        var next: ?Link = null;
        for (p.on[cur].items) |l| {
            if (l.part == prev or p.placed[l.part] or p.rail[l.other]) continue;
            if (next != null) return null;
            next = l;
        }
        const l = next orelse return null;
        buf[len] = .{ .part = l.part, .near = cur, .far = l.other };
        len += 1;
        if (l.other == onet) return buf[0..len];
        prev = l.part;
        cur = l.other;
    }
    return null;
}

/// Whether `net` is an input of any block.
fn isInput(p: *const Placer, net: u32) bool {
    for (p.blocks) |blk| {
        const b = blk orelse continue;
        for (b.ins[0..b.n_ins]) |i| if (b.pins[i].net == net) return true;
    }
    return false;
}

/// Everything not yet placed on `net`, whose node is `at`: `d` -1 grows
/// leftward (an input), +1 rightward (a load); `side` -1 stacks upward,
/// +1 downward. `owner` is the block the node belongs to, `at_pin` whether
/// the node is that block's pin.
fn grow(p: *Placer, net: u32, at: P, side: i32, d: i32, owner: u32, at_pin: bool) Allocator.Error!void {
    const a = p.arena;
    const owner_out: u32 = if (owner != none) p.blocks[owner].?.pins[p.blocks[owner].?.out].net else none;
    var shunts: std.ArrayList(Link) = .empty;
    var flat: std.ArrayList(Link) = .empty;
    var closing: std.ArrayList(Link) = .empty;
    var links: std.ArrayList(Link) = .empty;
    var near: std.ArrayList(Link) = .empty;
    var series: std.ArrayList(Link) = .empty;
    p.pending[net] = false;
    for (p.on[net].items) |l| {
        if (p.placed[l.part]) continue;
        if (p.rail[l.other]) {
            // On the upper input's net, beside a lower input that carries a
            // signal, a part to ground lies flat.
            const lies = at_pin and d == -1 and p.flat_shunt[net] and !p.rail_up[l.other];
            try (if (lies) &flat else &shunts).append(a, l);
            continue;
        }
        if (p.pending[l.other]) continue;
        const there = p.anch[l.other] orelse {
            const keep = if (d == 1) !try leadsToBlock(p, l.other, net) else !waits(p, l.other) or try toDriver(p, l.other, net) < far;
            if (keep) try series.append(a, l);
            continue;
        };
        if (p.anch_cv[l.other] != p.cv) {
            try links.append(a, l);
        } else if (at_pin and d == -1 and there.x < at.x - 100 and l.other != owner_out) {
            try near.append(a, l);
        } else try closing.append(a, l);
    }
    try links.appendSlice(a, near.items);

    var last: ?i32 = null;
    var xs = at.x + d * 50;
    for (shunts.items) |l| {
        const kind: opamp.Kind = if (p.rail_up[l.other]) .up else .down;
        const cy = if (kind == .up) at.y - 100 else at.y + 100;
        const c = try p.put(l.part, kind, xs, cy, .{ .x = d * 50, .y = 0 }, p.aOn(l.part, net) == (kind == .down), gap);
        try p.wire(at, .{ .x = c.x, .y = at.y });
        try p.wire(.{ .x = c.x, .y = at.y }, .{ .x = c.x, .y = cy });
        last = c.x;
        xs = c.x + d * 100;
    }
    const edge = if (last) |lx| lx + d * @as(i32, if (at_pin) 75 else 25) else at.x + d * @as(i32, if (at_pin) 100 else 50);
    var j: i32 = 0;
    if (d == -1) for (p.blocks, 0..) |blk, bd| {
        const b = blk orelse continue;
        if (p.placed[bd] or b.pins[b.out].net != net) continue;
        try p.wire(at, .{ .x = edge - 50, .y = at.y });
        try block(p, @intCast(bd), edge - 50, at.y, side);
        j = 1;
        break;
    };
    // The series parts: nearest a block still to be placed first, then the
    // larger tree, then card order.
    const Keyed = struct { l: Link, to: u32, size: u32 };
    const keyed = try a.alloc(Keyed, series.items.len);
    for (keyed, series.items) |*k, l| k.* = .{ .l = l, .to = try toDriver(p, l.other, net), .size = try size(p, l.other, net) };
    std.sort.insertion(Keyed, keyed, {}, struct {
        fn lt(_: void, x: Keyed, y: Keyed) bool {
            if (x.to != y.to) return x.to < y.to;
            if (x.size != y.size) return x.size > y.size;
            return x.l.part < y.l.part;
        }
    }.lt);
    const Item = struct { l: Link, tag: Tag };
    var row: std.ArrayList(Item) = .empty;
    for (keyed) |k| try row.append(a, .{ .l = k.l, .tag = .deeper });
    for (links.items) |l| try row.append(a, .{ .l = l, .tag = .link });
    for (flat.items) |l| try row.append(a, .{ .l = l, .tag = .flat });
    for (row.items) |it| {
        const l = it.l;
        if (p.placed[l.part]) continue;
        if (it.tag == .deeper and p.anch[l.other] != null) {
            try closing.append(a, l);
            continue;
        }
        const c = try p.put(l.part, .flat, edge + d * 50, at.y + side * 100 * j, .{ .x = 0, .y = side * 50 }, p.aOn(l.part, net) == (d == 1), if (j == 0 and at_pin) gap_level else gap);
        if (c.y == at.y) try p.wire(at, .{ .x = edge, .y = at.y });
        j += 1;
        switch (it.tag) {
            // Its ground symbol's spot.
            .flat => try p.canvas().wires.append(a, .{ .x0 = c.x - 120, .y0 = c.y - 20, .x1 = c.x - 50, .y1 = c.y + 75 }),
            .link => if (p.anch_cv[l.other] != p.cv and p.canvas().link == null) {
                p.canvas().link = .{ .x = c.x + d * 50, .net = l.other };
            },
            .deeper => {
                const node: P = .{ .x = c.x + d * 50, .y = c.y };
                p.anchor(l.other, node);
                try grow(p, l.other, node, side, d, owner, false);
            },
        }
    }
    for (closing.items) |l| {
        if (!p.placed[l.part]) try close(p, l.part, net, l.other, side, owner_out);
    }
}

/// The first row past every body between two x, on `side` of row `y`.
fn beyond(p: *Placer, xa: i32, xb: i32, side: i32, y: i32) i32 {
    // Farther toward `side` is greater in `side * y`, over as under.
    var edge: ?i32 = null;
    for (p.canvas().rects.items) |r| {
        if (!(r.x0 < @max(xa, xb) + 50 and @min(xa, xb) - 50 < r.x1)) continue;
        edge = @max(edge orelse side * r.y0, side * r.y0, side * r.y1);
    }
    const e = edge orelse return y + side * 100;
    return side * opamp.ceilQuarter(e + 75);
}

/// Part `d` between nets `net` and `o`, which both have a node: flat in a
/// row past everything between the nodes (over for an upper pin's tree,
/// under for a lower one's); upright beside them when they stand one over
/// the other. `owner_out` is the owning block's output net, or `none`.
fn close(p: *Placer, d: u32, net: u32, o: u32, side: i32, owner_out: u32) Allocator.Error!void {
    const n1 = p.anch[net].?;
    const n2 = p.anch[o].?;
    const deep = owner_out != none and (owner_out == net or owner_out == o);
    if (@abs(n1.x - n2.x) >= 150 or deep) {
        const left = if (n1.x < n2.x) net else o;
        var cx = opamp.roundEven(n1.x + n2.x, 50) * opamp.quarter;
        if (deep) cx = @max(cx, @min(n1.x, n2.x) + 75);
        const y = beyond(p, n1.x, n2.x, side, side * @max(side * n1.y, side * n2.y));
        _ = try p.put(d, .flat, cx, y, .{ .x = 0, .y = side * 50 }, p.aOn(d, left), gap);
    } else {
        const top = if (n1.y <= n2.y) net else o;
        const cy = opamp.roundEven(n1.y + n2.y, 50) * opamp.quarter;
        _ = try p.put(d, .down, @min(n1.x, n2.x) - 50, cy, .{ .x = -50, .y = 0 }, p.aOn(d, top), gap);
    }
}
