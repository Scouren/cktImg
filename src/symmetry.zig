//! The left-right symmetry of a circuit (issue #8, stage 2a): an
//! involution on devices and nets that maps the circuit onto itself. In:
//! the netlist, its nets' roles and the canonical order. Out: each device's
//! and net's mate (itself on the axis), or `none` everywhere.
//!
//! Devices and nets are the vertices of one graph, a pin an edge labelled
//! with its terminal. Colour refinement (1-dimensional Weisfeiler-Leman)
//! with individualization: two copies are refined, a vertex individualized
//! in one and a candidate image in the other, depth first, until both
//! colourings are discrete; the map is then read off the colours.
//!
//! Cites: B. McKay, A. Piperno, "Practical graph isomorphism, II", J.
//! Symbolic Computation 60, 2014.
//!
//! Human Rules:
//! - symmetry.1 (unmeasured) A circuit that maps onto itself by swapping
//!   devices and nets in pairs is drawn as a mirror image about one axis,
//!   each device opposite one of its own kind, polarity and pin count, each
//!   net opposite one of its own role; what maps to itself stands on the
//!   axis. `find`
//! - symmetry.2 (unmeasured) An input and a bias net count as one role: a
//!   pair driven with `ac` on one input and dc only on the other is still
//!   drawn mirrored. `initialColours`
//! - symmetry.3 (unmeasured) A device's mirror image keeps its terminals:
//!   gate opposite gate, drain opposite drain; a path's two ends may trade
//!   places only where the part does not tell them apart (a resistor's or
//!   a switch's may, a diode's may not). `preservesPins`
//!   Narrowing: each family keeps the label numbers it had, which order
//!   the colours and so which of equal symmetries is met first
//!   (`pinLabel`).
//! - symmetry.4 (unmeasured) A swap that moves no net but a rail (two
//!   parallel devices traded) is not drawn as a mirror. `movesSignal`
//! - symmetry.5 (book) Of the symmetries, the drawing shows the one that
//!   moves the most devices that are not sources: the Gilbert cell has
//!   three, and the book draws that one (no book named). `consider`
//!   Narrowing: only voltage sources are left out of the count; the device
//!   table's sources also take I, E, G, F and H (`movedDevices`).
//! - symmetry.6 (choice) Of symmetries that move as many devices, the
//!   first met in the canonical order is drawn: something must break the
//!   tie, and the order of the cards may not. `consider`
//! - symmetry.7 (choice) The search stops after `refines_max` (64)
//!   refinements or `candidates_max` (16) complete maps: a circuit of many
//!   identical cells has many symmetries, and the first few are as good as
//!   any. `complete`
//!
//! Contents:
//! - `pub const none: u32`
//! - `pub const Polarity = device.Polarity`
//! - `pub const Pin = struct`
//! - `pub fn find(gpa: Allocator, nl: *const Netlist, roles: []const Role, device_rank: []const u32, net_rank: []const u32, pins: []const Pin, device_mate: []u32, net_mate: []u32) Allocator.Error!bool`
//! - `pub const polarity = device.polarity`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const sch = @import("schematic.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const Role = sch.Role;

/// No mate: the circuit has no symmetry.
pub const none: u32 = std.math.maxInt(u32);

/// A transistor's type, and the reader of it from a model: the device
/// model's, under the names the stages before `device.zig` call them by.
pub const Polarity = device.Polarity;
pub const polarity = device.polarity;

/// Two devices (or nets) the symmetry must swap; one on the axis when
/// `a == b` (`*@ symmetric`, `*@ axis`).
pub const Pin = struct { net: bool, a: u32, b: u32 };

/// Refinements one symmetry search may run, and complete maps it may weigh:
/// a circuit of many identical cells has many symmetries, and the first
/// few of the search are as good as any. The golden and textbook decks need
/// 14 and 4 at most; a bus of 8 slices would spend 512 refinements, 5 ms.
const refines_max = 64;
const candidates_max = 16;

/// Devices then nets as one vertex set; an edge per pin, labelled with the
/// pin's terminal (pins a device has no order between share a label).
const Graph = struct {
    devices: u32,
    off: []u32,
    to: []u32,
    label: []u8,

    fn vertices(g: Graph) u32 {
        assert(g.off.len >= 1);
        return @intCast(g.off.len - 1);
    }
    fn deinit(g: Graph, gpa: Allocator) void {
        gpa.free(g.off);
        gpa.free(g.to);
        gpa.free(g.label);
    }
};

const Search = struct {
    gpa: Allocator,
    g: Graph,
    nl: *const Netlist,
    roles: []const Role,
    /// Vertices in canonical order: devices by rank, then nets by rank.
    canon: []const u32,
    refines: u32 = 0,
    candidates: u32 = 0,
    best: ?[]u32 = null,
    best_moved: u32 = 0,
    /// Vertex pairs every map kept must swap.
    pinned: []const [2]u32 = &.{},
};

const SigOrder = struct {
    g: Graph,
    colour: []const u32,
    sig: []const u64,

    fn lessThan(o: SigOrder, x: u32, y: u32) bool {
        if (o.colour[x] != o.colour[y]) return o.colour[x] < o.colour[y];
        const sx = o.sig[o.g.off[x]..o.g.off[x + 1]];
        const sy = o.sig[o.g.off[y]..o.g.off[y + 1]];
        return std.mem.order(u64, sx, sy) == .lt;
    }
};

/// Fills both mate tables (one entry per device and per net, in card
/// order; the ranks are the canonical order) with the involution that maps
/// the circuit onto itself, swaps every pair of `pins`, and moves the most
/// devices that are not sources; or with `none`, returning false when there
/// is none.
pub fn find(gpa: Allocator, nl: *const Netlist, roles: []const Role, device_rank: []const u32, net_rank: []const u32, pins: []const Pin, device_mate: []u32, net_mate: []u32) Allocator.Error!bool {
    assert(device_mate.len == device_rank.len);
    assert(net_mate.len == net_rank.len);
    @memset(device_mate, none);
    @memset(net_mate, none);
    const g = try buildGraph(gpa, nl, roles);
    defer g.deinit(gpa);
    const canon = try gpa.alloc(u32, g.vertices());
    defer gpa.free(canon);
    for (device_rank, 0..) |r, d| canon[r] = @intCast(d);
    for (net_rank, 0..) |r, n| canon[g.devices + r] = @intCast(g.devices + n);

    const colour = try initialColours(gpa, nl, roles, g);
    defer gpa.free(colour);
    // Each pinned pair a colour of its own, so the search maps it onto
    // itself; `consider` keeps only the maps that swap it.
    const pinned = try gpa.alloc([2]u32, pins.len);
    defer gpa.free(pinned);
    for (pins, pinned) |p, *v| {
        const base: u32 = if (p.net) g.devices else 0;
        assert(base + @max(p.a, p.b) < g.vertices());
        v.* = .{ base + p.a, base + p.b };
    }
    if (pins.len > 0) try seed(gpa, colour, pinned);
    var search: Search = .{ .gpa = gpa, .g = g, .nl = nl, .roles = roles, .canon = canon, .pinned = pinned };
    defer if (search.best) |b| gpa.free(b);
    try complete(&search, colour, colour, 0);
    const sigma = search.best orelse return false;
    assert(isInvolution(sigma));
    for (device_mate, sigma[0..g.devices]) |*m, s| m.* = s;
    for (net_mate, sigma[g.devices..]) |*m, s| m.* = s - g.devices;
    for (device_mate, 0..) |m, d| assert(device_mate[m] == d);
    for (pinned) |v| assert(sigma[v[0]] == v[1]);
    return true;
}

// ---- private ----

fn buildGraph(gpa: Allocator, nl: *const Netlist, roles: []const Role) !Graph {
    const c = &nl.graph;
    const devices = c.edgeCount();
    const n = devices + c.vertexCount();
    assert(roles.len == c.vertexCount());
    const off = try gpa.alloc(u32, n + 1);
    errdefer gpa.free(off);
    @memset(off, 0);
    for (0..devices) |d| for (c.members(EdgeId.from(d))) |net| {
        off[d + 1] += 1;
        off[devices + net.index() + 1] += 1;
    };
    for (1..off.len) |i| off[i] += off[i - 1];
    assert(off[n] % 2 == 0); // every pin counted at its device and its net
    const to = try gpa.alloc(u32, off[n]);
    errdefer gpa.free(to);
    const label = try gpa.alloc(u8, off[n]);
    errdefer gpa.free(label);
    const fill = try gpa.dupe(u32, off[0..n]);
    defer gpa.free(fill);
    const kinds = c.edges.items(.kind);
    for (0..devices) |d| for (c.members(EdgeId.from(d)), 0..) |net, i| {
        const v = devices + net.index();
        const l = pinLabel(kinds[d], i);
        to[fill[d]] = v;
        label[fill[d]] = l;
        fill[d] += 1;
        to[fill[v]] = @intCast(d);
        label[fill[v]] = l;
        fill[v] += 1;
    };
    for (0..n) |v| assert(fill[v] == off[v + 1]);
    return .{ .devices = devices, .off = off, .to = to, .label = label };
}

/// A pin's label, from the device table: its place among the pins its kind
/// tells apart. A path's two ends share one unless told apart (a resistor's
/// and a switch's share, a diode's do not); a pin past the last told apart
/// (a control pair's second, a transistor's body, else the path's second
/// end) shares that one's; a box's ports each have their own.
///
/// Narrowing: each family keeps the numbers it had (`first`), F and H a
/// box's (the general form: a source's 11 and 12). The place alone refines
/// the same classes, kinds starting in colours of their own; but the
/// numbers order the colours, and so which of equal symmetries is met first.
fn pinLabel(kind: DeviceKind, pin: usize) u8 {
    const p: u8 = @intCast(@min(pin, 200));
    const k = device.of(kind);
    const path = k.path orelse return 32 + p;
    if (kind == .cccs or kind == .ccvs) return 32 + p;
    const pair = k.control == .pair;
    const first: u8 = if (k.gate != null) (if (kind == .bjt) 4 else 0) else if (!k.polar) 8 else if (!pair) 11 else 13;
    const last = if (pair) path[1] + 2 else k.body orelse path[1];
    return first + (@min(p, last) -| @intFromBool(!k.polar));
}

/// Devices by kind, polarity and pin count; nets by role. Colours are the
/// ranks of the distinct keys, so they do not depend on numbering.
fn initialColours(gpa: Allocator, nl: *const Netlist, roles: []const Role, g: Graph) ![]u32 {
    const c = &nl.graph;
    assert(roles.len + g.devices == g.vertices());
    const key = try gpa.alloc(u64, g.vertices());
    defer gpa.free(key);
    for (0..g.devices) |d| {
        const e = EdgeId.from(d);
        const kind: u64 = @backingInt(c.edges.items(.kind)[d]);
        const pol: u64 = @backingInt(polarity(nl.modelType(e)));
        key[d] = kind << 24 | pol << 16 | @min(c.members(e).len, 0xffff);
    }
    // A net driven from outside is an input or a bias by its stimulus: a
    // testbench that drives one input of a pair with `ac` and the other
    // with dc only still has a symmetric circuit.
    for (roles, 0..) |r, n| {
        const class: u64 = switch (r) {
            .supply => 0,
            .sink => 1,
            .input, .bias => 2,
            .output => 3,
            .internal => 4,
        };
        key[g.devices + n] = @as(u64, 1) << 40 | class;
    }
    // The distinct keys, sorted; a vertex's colour is its key's place.
    const distinct = try gpa.dupe(u64, key);
    defer gpa.free(distinct);
    std.mem.sort(u64, distinct, {}, std.sort.asc(u64));
    var m: usize = 0;
    for (distinct, 0..) |k, i| {
        if (i > 0 and k == distinct[m - 1]) continue;
        distinct[m] = k;
        m += 1;
    }
    assert(m >= 1);
    const colour = try gpa.alloc(u32, g.vertices());
    for (key, colour) |k, *col| {
        col.* = @intCast(std.mem.indexOfScalar(u64, distinct[0..m], k).?);
    }
    for (colour) |col| assert(col < m);
    return colour;
}

/// Depth-first over individualizations: `a` and `b` are colourings that
/// a symmetry maps onto each other so far. Refines both; when they are
/// discrete, the map is `v ↦ the vertex of b with a[v]`'s colour.
fn complete(s: *Search, a0: []const u32, b0: []const u32, depth: u32) Allocator.Error!void {
    assert(depth <= s.g.vertices());
    assert(a0.len == s.g.vertices());
    assert(b0.len == a0.len);
    if (s.refines + 2 > refines_max or s.candidates >= candidates_max) return;
    const a = try s.gpa.dupe(u32, a0);
    defer s.gpa.free(a);
    const b = try s.gpa.dupe(u32, b0);
    defer s.gpa.free(b);
    try refine(s.gpa, s.g, a);
    try refine(s.gpa, s.g, b);
    s.refines += 2;
    if (!try sameClasses(s.gpa, a, b)) return;

    // The first class of more than one vertex, and its first member in
    // canonical order; with none, the map is complete.
    const n = s.g.vertices();
    const size = try s.gpa.alloc(u32, n);
    defer s.gpa.free(size);
    @memset(size, 0);
    for (a) |c| size[c] += 1;
    const split = for (0..n) |c| {
        if (size[c] > 1) break c;
    } else return consider(s, a, b);
    const u = for (s.canon) |v| {
        if (a[v] == split) break v;
    } else unreachable;
    const fresh: u32 = n;
    for (s.canon) |w| {
        if (b[w] != split) continue;
        const a2 = try s.gpa.dupe(u32, a);
        defer s.gpa.free(a2);
        const b2 = try s.gpa.dupe(u32, b);
        defer s.gpa.free(b2);
        a2[u] = fresh;
        b2[w] = fresh;
        try complete(s, a2, b2, depth + 1);
    }
}

/// Colour refinement to a stable colouring: a vertex's new colour is the
/// rank of its colour with the sorted (label, colour) list of its
/// neighbours. Ranks, not hashes, so equal structure gives equal colours.
fn refine(gpa: Allocator, g: Graph, colour: []u32) !void {
    const n = g.vertices();
    assert(colour.len == n);
    const sig = try gpa.alloc(u64, g.to.len);
    defer gpa.free(sig);
    const order = try gpa.alloc(u32, n);
    defer gpa.free(order);
    const next = try gpa.alloc(u32, n);
    defer gpa.free(next);
    var classes = countClasses(colour);
    var round: u32 = 0;
    while (round <= n) : (round += 1) {
        for (0..n) |v| {
            const r = sig[g.off[v]..g.off[v + 1]];
            for (r, g.off[v]..) |*x, k| x.* = @as(u64, g.label[k]) << 32 | colour[g.to[k]];
            std.mem.sort(u64, r, {}, std.sort.asc(u64));
        }
        for (order, 0..) |*o, v| o.* = @intCast(v);
        const ctx: SigOrder = .{ .g = g, .colour = colour, .sig = sig };
        std.mem.sort(u32, order, ctx, SigOrder.lessThan);
        var c: u32 = 0;
        for (order, 0..) |v, i| {
            if (i > 0 and ctx.lessThan(order[i - 1], v)) c += 1;
            next[v] = c;
        }
        @memcpy(colour, next);
        const now = c + 1;
        if (now == classes) break;
        classes = now;
    }
    assert(round <= n);
    for (colour) |c| assert(c < n);
}

fn countClasses(colour: []const u32) u32 {
    assert(colour.len > 0);
    var max: u32 = 0;
    for (colour) |c| max = @max(max, c);
    return max + 1;
}

/// Each colour on as many vertices in `a` as in `b`.
fn sameClasses(gpa: Allocator, a: []const u32, b: []const u32) !bool {
    assert(a.len == b.len);
    assert(a.len > 0);
    const count = try gpa.alloc(i32, a.len + 1);
    defer gpa.free(count);
    @memset(count, 0);
    for (a, b) |x, y| {
        if (x > a.len or y > a.len) return false;
        count[x] += 1;
        count[y] -= 1;
    }
    for (count) |k| if (k != 0) return false;
    return true;
}

/// A complete map: kept when it is an involution, maps every device's pins
/// onto its image's, moves a net that is not a rail, and moves more devices
/// that are not sources than the best so far.
fn consider(s: *Search, a: []const u32, b: []const u32) !void {
    s.candidates += 1;
    assert(s.candidates <= candidates_max);
    const g = s.g;
    const n = g.vertices();
    const at = try s.gpa.alloc(u32, n);
    defer s.gpa.free(at);
    // Both colourings are discrete: a colour names one vertex.
    @memset(at, none);
    for (b, 0..) |c, v| {
        assert(at[c] == none);
        at[c] = @intCast(v);
    }
    const sigma = try s.gpa.alloc(u32, n);
    errdefer s.gpa.free(sigma);
    for (a, sigma) |c, *m| m.* = at[c];
    const swaps = for (s.pinned) |v| {
        if (sigma[v[0]] != v[1]) break false;
    } else true;
    const keep = swaps and isInvolution(sigma) and try preservesPins(s.gpa, g, sigma) and movesSignal(s, sigma);
    const moved = movedDevices(s, sigma);
    if (!keep or moved <= s.best_moved) {
        s.gpa.free(sigma);
        return;
    }
    if (s.best) |old| s.gpa.free(old);
    s.best = sigma;
    s.best_moved = moved;
}

/// Gives each pinned pair a colour no other vertex has, then renumbers the
/// colours densely (refinement keeps them below the vertex count).
fn seed(gpa: Allocator, colour: []u32, pinned: []const [2]u32) !void {
    var next = countClasses(colour);
    for (pinned) |v| {
        colour[v[0]] = next;
        colour[v[1]] = next;
        next += 1;
    }
    const used = try gpa.alloc(u32, next);
    defer gpa.free(used);
    @memset(used, none);
    var k: u32 = 0;
    for (0..next) |c| {
        if (std.mem.indexOfScalar(u32, colour, @intCast(c)) == null) continue;
        used[c] = k;
        k += 1;
    }
    for (colour) |*c| c.* = used[c.*];
    assert(k <= colour.len);
}

fn isInvolution(sigma: []const u32) bool {
    assert(sigma.len > 0);
    for (sigma) |m| assert(m < sigma.len);
    for (sigma, 0..) |m, v| if (sigma[m] != v) return false;
    return true;
}

fn preservesPins(gpa: Allocator, g: Graph, sigma: []const u32) !bool {
    assert(sigma.len == g.vertices());
    var mine: std.ArrayList(u64) = .empty;
    defer mine.deinit(gpa);
    var theirs: std.ArrayList(u64) = .empty;
    defer theirs.deinit(gpa);
    for (0..g.devices) |d| {
        const e = sigma[d];
        if (e >= g.devices) return false;
        mine.clearRetainingCapacity();
        theirs.clearRetainingCapacity();
        for (g.off[d]..g.off[d + 1]) |k| try mine.append(gpa, @as(u64, g.label[k]) << 32 | sigma[g.to[k]]);
        for (g.off[e]..g.off[e + 1]) |k| try theirs.append(gpa, @as(u64, g.label[k]) << 32 | g.to[k]);
        std.mem.sort(u64, mine.items, {}, std.sort.asc(u64));
        std.mem.sort(u64, theirs.items, {}, std.sort.asc(u64));
        if (!std.mem.eql(u64, mine.items, theirs.items)) return false;
    }
    return true;
}

/// Swapping two parallel devices fixes every net: not a symmetry worth
/// drawing.
fn movesSignal(s: *const Search, sigma: []const u32) bool {
    assert(sigma.len == s.g.vertices());
    assert(s.roles.len + s.g.devices == sigma.len);
    for (s.roles, 0..) |r, n| {
        const v = s.g.devices + n;
        if (sigma[v] != v and !r.isRail()) return true;
    }
    return false;
}

/// The devices `sigma` moves that are not sources. Narrowing: voltage
/// sources only; the device table's sources (`device.of(kind).source`) are
/// also I, E, G, F and H, which count here.
fn movedDevices(s: *const Search, sigma: []const u32) u32 {
    assert(sigma.len == s.g.vertices());
    const kinds = s.nl.graph.edges.items(.kind);
    var k: u32 = 0;
    for (0..s.g.devices) |d| k += @intFromBool(sigma[d] != d and kinds[d] != .vsource);
    return k;
}
