//! Stage 2a of issue #8: the circuit's structure, from its connectivity
//! alone. In: the netlist and its nets' roles. Out, per device and net in
//! card order:
//!
//! - a canonical order: devices by name (a natural sort, `m2` before `m10`),
//!   so nothing that breaks a tie by it depends on the order of the cards;
//! - blocks, the groups a designer draws as one unit: differential pairs,
//!   cross-coupled pairs, transistors of one type on one gate (a mirror when
//!   one of them is diode-connected, else a bank), and series stacks;
//! - the left-right symmetry (`symmetry.zig`): an involution on devices and
//!   nets that maps the circuit onto itself and moves the most devices.
//!
//! Data: one row per device and per net (u32 handles, `none` = no mate);
//! blocks as kind + start offsets + members (each device in at most one row
//! block and one stack, so members ≤ 2 × devices). Everything is computed
//! once per schematic; temporaries are freed before `analyze` returns.
//!
//! Cites: T. Massier, H. Graeb, U. Schlichtmann, "The Sizing Rules Method
//! for CMOS and Bipolar Analog Integrated Circuit Synthesis", IEEE TCAD
//! 27(12), 2008 (blocks as groups of transistor pairs); symmetry.zig's.
//!
//! Contents:
//! - `pub const none: u32`
//! - `pub const BlockKind = enum(u8) { pair, cross, mirror, bank, stack }`
//! - `pub const Structure = struct`, `Structure.members(s: *const Structure, b: usize) []const u32`
//! - `pub fn analyze(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role) Allocator.Error!Structure`
//! - `pub fn nameLess(a: []const u8, b: []const u8) bool`
//! - `pub fn rankByName(arena: Allocator, gpa: Allocator, names: []const []const u8) Allocator.Error![]u32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const symmetry = @import("symmetry.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Polarity = symmetry.Polarity;

/// No mate: the circuit has no symmetry.
pub const none = symmetry.none;

pub const BlockKind = enum(u8) {
    /// Two transistors of one type alone on a source net that is not a
    /// rail and no gate is on, their gates and drains apart.
    pair,
    /// Two transistors of one type whose gates take each other's drains.
    cross,
    /// Transistors of one type on one gate net (not a rail), one of them
    /// diode-connected.
    mirror,
    /// The same, none diode-connected: current sources on a bias line,
    /// cascodes.
    bank,
    /// Transistors in series, top to bottom: each one's lower end is alone
    /// with the next one's upper end on a net that is not a rail.
    stack,
};

/// The result of `analyze`, in the arena it was given.
pub const Structure = struct {
    /// Per device: its place in the canonical order. A permutation.
    device_rank: []const u32,
    /// Per net: likewise. Every stage orders nets by it.
    net_rank: []const u32,
    /// Per device: the device the symmetry maps it to (itself on the
    /// axis), or `none`.
    device_mate: []const u32,
    /// Per net: likewise.
    net_mate: []const u32,
    block_kind: []const BlockKind,
    /// Block b's members are `block_devices[block_start[b]..block_start[b + 1]]`:
    /// a stack's top to bottom, any other's in canonical order.
    block_start: []const u32,
    block_devices: []const u32,

    pub fn members(s: *const Structure, b: usize) []const u32 {
        assert(b + 1 < s.block_start.len);
        assert(s.block_start[b] < s.block_start[b + 1]);
        return s.block_devices[s.block_start[b]..s.block_start[b + 1]];
    }
};

/// A transistor's three main terminals' nets.
const Fet = struct {
    drain: u32,
    gate: u32,
    source: u32,
    polarity: Polarity,
    kind: DeviceKind,

    /// The terminal current enters by: an n-type's drain, a p-type's source.
    fn upper(f: Fet) u32 {
        return if (f.polarity == .p) f.source else f.drain;
    }
    fn lower(f: Fet) u32 {
        return if (f.polarity == .p) f.drain else f.source;
    }
    fn sameType(f: Fet, o: Fet) bool {
        return f.kind == o.kind and f.polarity == o.polarity;
    }
};

const BlockList = struct {
    kind: std.ArrayList(BlockKind) = .empty,
    start: std.ArrayList(u32) = .empty,
    devices: std.ArrayList(u32) = .empty,

    fn add(l: *BlockList, arena: Allocator, kind: BlockKind, members: []const u32) !void {
        assert(members.len >= 2);
        if (l.start.items.len == 0) try l.start.append(arena, 0);
        try l.kind.append(arena, kind);
        try l.devices.appendSlice(arena, members);
        try l.start.append(arena, @intCast(l.devices.items.len));
        assert(l.start.items.len == l.kind.items.len + 1);
    }
};

/// Asserts that `roles` has one entry per net.
pub fn analyze(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role) Allocator.Error!Structure {
    const g = &nl.graph;
    assert(roles.len == g.vertexCount());
    const device_rank = try rankByName(arena, gpa, g.edges.items(.name));
    const net_rank = try rankByName(arena, gpa, g.vertices.items(.name));
    const device_mate = try arena.alloc(u32, g.edgeCount());
    const net_mate = try arena.alloc(u32, g.vertexCount());
    try symmetry.find(gpa, nl, roles, device_rank, net_rank, device_mate, net_mate);
    var out: Structure = .{
        .device_rank = device_rank,
        .net_rank = net_rank,
        .device_mate = device_mate,
        .net_mate = net_mate,
        .block_kind = &.{},
        .block_start = &.{},
        .block_devices = &.{},
    };
    for (device_rank) |r| assert(r < device_rank.len);
    try blocks(gpa, arena, nl, roles, device_rank, net_rank, &out);
    assert(out.block_start.len == out.block_kind.len + 1);
    assert(out.block_devices.len <= 2 * g.edgeCount());
    return out;
}

/// Natural order: runs of digits compare as numbers (`m2` < `m10`), the
/// rest bytewise; a prefix comes first. Names equal so (`m01`, `m1`) go
/// bytewise, so distinct names never tie and no order falls back to the
/// cards'.
pub fn nameLess(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        if (std.ascii.isDigit(a[i]) and std.ascii.isDigit(b[j])) {
            const ea = digitsEnd(a, i);
            const eb = digitsEnd(b, j);
            const na = std.mem.trimStart(u8, a[i..ea], "0");
            const nb = std.mem.trimStart(u8, b[j..eb], "0");
            if (na.len != nb.len) return na.len < nb.len;
            switch (std.mem.order(u8, na, nb)) {
                .lt => return true,
                .gt => return false,
                .eq => {},
            }
            i = ea;
            j = eb;
            continue;
        }
        if (a[i] != b[j]) return a[i] < b[j];
        i += 1;
        j += 1;
    }
    assert(i == a.len or j == b.len);
    assert(i <= a.len and j <= b.len);
    if (a.len - i != b.len - j) return a.len - i < b.len - j;
    return std.mem.lessThan(u8, a, b);
}

/// Each name's place in natural order (`nameLess`), a repeated name by
/// index: a permutation, in `arena`; `gpa` holds the sort.
pub fn rankByName(arena: Allocator, gpa: Allocator, names: []const []const u8) Allocator.Error![]u32 {
    const order = try gpa.alloc(u32, names.len);
    defer gpa.free(order);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    std.mem.sort(u32, order, names, struct {
        fn lt(ns: []const []const u8, x: u32, y: u32) bool {
            return nameLess(ns[x], ns[y]) or (!nameLess(ns[y], ns[x]) and x < y);
        }
    }.lt);
    const rank = try arena.alloc(u32, names.len);
    for (order, 0..) |d, r| rank[d] = @intCast(r);
    assert(rank.len == names.len);
    for (rank) |r| assert(r < names.len);
    return rank;
}

// ---- private ----

fn digitsEnd(s: []const u8, start: usize) usize {
    assert(start < s.len);
    assert(std.ascii.isDigit(s[start]));
    var e = start;
    while (e < s.len and std.ascii.isDigit(s[e])) e += 1;
    assert(e > start);
    return e;
}

/// Cross-coupled pairs first, then differential pairs, then gate groups
/// (a device joins one of these at most), then stacks; each kind in
/// canonical order of devices or nets, so the list does not depend on the
/// order of the cards.
fn blocks(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, device_rank: []const u32, net_rank: []const u32, out: *Structure) !void {
    const c = &nl.graph;
    const devices = c.edgeCount();
    assert(device_rank.len == devices);
    assert(net_rank.len == c.vertexCount());
    const by_rank = try gpa.alloc(u32, devices);
    defer gpa.free(by_rank);
    for (device_rank, 0..) |r, d| by_rank[r] = @intCast(d);
    const nets_by_rank = try gpa.alloc(u32, net_rank.len);
    defer gpa.free(nets_by_rank);
    for (net_rank, 0..) |r, n| nets_by_rank[r] = @intCast(n);
    const taken = try gpa.alloc(bool, devices);
    defer gpa.free(taken);
    @memset(taken, false);
    var list: BlockList = .{};
    // Hints first: a hinted group stands as written, a device kept out of
    // groups is in none, and `grouping off` leaves the hinted ones only.
    const hinted = try hints(gpa, arena, nl, device_rank, taken, &list);
    defer gpa.free(hinted.held);
    const recognize = !hinted.off;

    // Cross-coupled pairs: a's gate is b's drain and b's gate a's drain.
    if (recognize) for (by_rank) |a| {
        const fa = transistor(nl, a) orelse continue;
        if (taken[a] or isRail(roles[fa.drain]) or isRail(roles[fa.gate]) or fa.drain == fa.gate) continue;
        var best: ?u32 = null;
        for (c.incident(VertexId.from(fa.gate))) |e| {
            const b = e.index();
            const fb = transistor(nl, b) orelse continue;
            if (b == a or taken[b] or !fa.sameType(fb)) continue;
            if (fb.drain != fa.gate or fb.gate != fa.drain) continue;
            if (best == null or device_rank[b] < device_rank[best.?]) best = b;
        }
        const b = best orelse continue;
        taken[a] = true;
        taken[b] = true;
        try list.add(arena, .cross, &.{ a, b });
    };

    // Differential pairs: the only two transistor sources on a net.
    if (recognize) for (nets_by_rank) |n| {
        if (isRail(roles[n])) continue;
        var on: [2]u32 = undefined;
        var count: usize = 0;
        var gated = false;
        for (c.incident(VertexId.from(n))) |e| {
            const d = e.index();
            const f = transistor(nl, d) orelse continue;
            gated = gated or f.gate == n;
            if (f.source != n or (count > 0 and on[@min(count, on.len) - 1] == d)) continue;
            if (count < on.len) on[count] = d;
            count += 1;
        }
        if (count != 2 or gated or taken[on[0]] or taken[on[1]]) continue;
        assert(on[0] != on[1]);
        const fa = transistor(nl, on[0]).?;
        const fb = transistor(nl, on[1]).?;
        if (!fa.sameType(fb) or fa.gate == fb.gate or fa.drain == fb.drain) continue;
        const lo, const hi = if (device_rank[on[0]] < device_rank[on[1]]) .{ on[0], on[1] } else .{ on[1], on[0] };
        taken[lo] = true;
        taken[hi] = true;
        try list.add(arena, .pair, &.{ lo, hi });
    };

    // Gate groups: transistors of one type on a gate net, by rank.
    var group: std.ArrayList(u32) = .empty;
    defer group.deinit(gpa);
    if (recognize) for (nets_by_rank) |n| {
        if (isRail(roles[n])) continue;
        for ([_]Polarity{ .n, .p, .other }) |pol| for ([_]DeviceKind{ .mosfet, .bjt, .jfet, .mesfet }) |kind| {
            group.clearRetainingCapacity();
            var diode = false;
            for (by_rank) |d| {
                const f = transistor(nl, d) orelse continue;
                if (taken[d] or f.gate != n or f.polarity != pol or f.kind != kind) continue;
                try group.append(gpa, d);
                diode = diode or f.drain == n;
            }
            if (group.items.len < 2) continue;
            for (group.items) |d| taken[d] = true;
            try list.add(arena, if (diode) .mirror else .bank, group.items);
        };
    };

    // Stacks: links where a net holds just one transistor's lower end and
    // another's upper end.
    const below = try gpa.alloc(u32, devices);
    defer gpa.free(below);
    const above = try gpa.alloc(u32, devices);
    defer gpa.free(above);
    @memset(below, none);
    @memset(above, none);
    for (0..c.vertexCount()) |n| {
        if (!recognize) break;
        if (isRail(roles[n])) continue;
        var top: u32 = none;
        var bottom: u32 = none;
        var ends: usize = 0;
        for (c.incident(VertexId.from(n))) |e| {
            const d = e.index();
            // A diode-connected transistor is on the net by two pins.
            if (d == top or d == bottom) continue;
            const f = transistor(nl, d) orelse continue;
            if (f.lower() == n) {
                top = d;
                ends += 1;
            }
            if (f.upper() == n) {
                bottom = d;
                ends += 1;
            }
        }
        if (ends != 2 or top == none or bottom == none or top == bottom) continue;
        if (hinted.held[top] or hinted.held[bottom]) continue;
        assert(below[top] == none);
        assert(above[bottom] == none);
        below[top] = bottom;
        above[bottom] = top;
    }
    var chain: std.ArrayList(u32) = .empty;
    defer chain.deinit(gpa);
    for (by_rank) |d| {
        if (above[d] != none or below[d] == none) continue;
        chain.clearRetainingCapacity();
        var at = d;
        while (at != none) : (at = below[at]) {
            assert(chain.items.len < devices);
            try chain.append(gpa, at);
        }
        try list.add(arena, .stack, chain.items);
    }

    if (list.kind.items.len > 0) assert(list.start.items.len == list.kind.items.len + 1);
    out.block_kind = list.kind.items;
    out.block_start = if (list.start.items.len == 0) try arena.dupe(u32, &[_]u32{0}) else list.start.items;
    out.block_devices = list.devices.items;
}

/// The deck's grouping hints: each hinted group added to `list` with its
/// known devices no earlier hint took (a pair or a cross-coupled pair of two
/// exactly), its members `taken` (a stack's: `held` from recognized
/// stacks); a device `*@ nogroup` names `taken` and `held`. `off`: the deck
/// turns recognition off.
fn hints(gpa: Allocator, arena: Allocator, nl: *const Netlist, device_rank: []const u32, taken: []bool, list: *BlockList) !struct { off: bool, held: []bool } {
    const n = taken.len;
    assert(device_rank.len == n);
    const held = try gpa.alloc(bool, n);
    errdefer gpa.free(held);
    @memset(held, false);
    const nogroup = try gpa.alloc(bool, n);
    defer gpa.free(nogroup);
    @memset(nogroup, false);
    var off = false;
    for (nl.hints) |h| switch (h.verb) {
        .off => off = true,
        .nogroup => for (h.devices) |name| if (nl.device(name)) |e| {
            nogroup[e.index()] = true;
            held[e.index()] = true;
            taken[e.index()] = true;
        },
        .pair, .mirror, .bank, .stack, .cross => {},
    };
    var members: std.ArrayList(u32) = .empty;
    defer members.deinit(gpa);
    for (nl.hints) |h| {
        const kind: BlockKind = switch (h.verb) {
            .pair => .pair,
            .bank => .bank,
            .mirror => .mirror,
            .stack => .stack,
            .cross => .cross,
            .nogroup, .off => continue,
        };
        members.clearRetainingCapacity();
        for (h.devices) |name| {
            const d = (nl.device(name) orelse continue).index();
            const busy = if (kind == .stack) held[d] else taken[d];
            if (busy or nogroup[d] or std.mem.indexOfScalar(u32, members.items, d) != null) continue;
            try members.append(gpa, d);
        }
        if (members.items.len < 2 or ((kind == .pair or kind == .cross) and members.items.len != 2)) continue;
        // In rank order, as recognition lists them; a stack top to bottom as
        // written. ponytail: insertion sort, quadratic, for the handful of
        // names a hint gives; `std.mem.sort` costs the plugin 8 KB more.
        if (kind != .stack) std.sort.insertion(u32, members.items, device_rank, struct {
            fn lt(rank: []const u32, a: u32, b: u32) bool {
                return rank[a] < rank[b];
            }
        }.lt);
        for (members.items) |d| {
            if (kind == .stack) held[d] = true else taken[d] = true;
        }
        try list.add(arena, kind, members.items);
    }
    for (nogroup, taken) |g, t| assert(!g or t);
    return .{ .off = off, .held = held };
}

fn transistor(nl: *const Netlist, d: u32) ?Fet {
    assert(d < nl.graph.edgeCount());
    const e = EdgeId.from(d);
    const kind = nl.graph.edges.items(.kind)[d];
    switch (kind) {
        .mosfet, .jfet, .mesfet, .bjt => {},
        else => return null,
    }
    const pins = nl.graph.members(e);
    if (pins.len < 3) return null;
    assert(pins[0].index() < nl.graph.vertexCount());
    // BJT pins are c b e: the same places as d g s.
    return .{
        .drain = pins[0].index(),
        .gate = pins[1].index(),
        .source = pins[2].index(),
        .polarity = symmetry.polarity(nl.modelType(e)),
        .kind = kind,
    };
}

fn isRail(r: Role) bool {
    return r == .supply or r == .sink;
}
