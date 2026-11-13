//! Stage 2a of issue #8: the circuit's structure, from its connectivity
//! alone. In: the netlist and its nets' roles. Out, per device and net in
//! card order:
//!
//! - a canonical order of devices and of nets;
//! - blocks, the groups a designer draws as one unit;
//! - the left-right symmetry (`symmetry.zig`), under the deck's lines.
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
//! Human Rules:
//! - structure.1 (invariant) The drawing does not depend on the order of
//!   the cards: every tie is broken by the canonical order of device and
//!   net names. `rankByName`
//! - structure.2 (choice) The canonical order is natural: a run of digits
//!   reads as a number (`m2` before `m10`), the rest bytewise: a tie needs
//!   a breaker that the cards' order cannot be. `nameLess`
//! - structure.3 (invariant) A `symmetric a b` line draws a and b as each
//!   other's mirror image, an `axis x` line puts x on the mirror axis, and
//!   `symmetry off` draws no mirror at all, not even a block's. `mates`
//! - structure.4 (choice) Of `symmetric` and `axis` lines that no one
//!   symmetry satisfies together, the strongest stand and the rest are
//!   dropped; `symmetry off` drops them all: the deck's own ranking of
//!   its lines. `mates`
//! - structure.5 (invariant) A `group` line's devices are drawn as one
//!   block of the kind it names, as written (a stack top to bottom); a
//!   device a `nogroup` line names is in no block; `grouping off` leaves
//!   only the named groups. `groupLines`
//! - structure.6 (choice) Of `group` lines that name one device, the
//!   strongest takes it (a stack line and another kind may share it): the
//!   deck's own ranking of its lines. `groupLines`
//! - structure.7 (book) Two transistors of one type, each one's gate on the
//!   other's drain (neither net a rail), are drawn as one block, a
//!   cross-coupled pair. Massier, Graeb and Schlichtmann (Cites). `blocks`
//! - structure.8 (book) The only two transistor sources on a net that is no
//!   rail and holds no gate, of one type, with distinct gates and distinct
//!   drains, are drawn as one block, a differential pair. Massier, Graeb
//!   and Schlichtmann (Cites). `blocks`
//! - structure.9 (book) Two or more transistors of one kind and polarity
//!   on one gate net (no rail), one of them diode-connected, are drawn as
//!   one block, a current mirror. Massier, Graeb and Schlichtmann (Cites).
//!   `blocks`
//! - structure.10 (book) The same with none diode-connected (current
//!   sources on a bias line, cascodes) are drawn as one block, a bank.
//!   Massier, Graeb and Schlichtmann (Cites). `blocks`
//! - structure.11 (book) Transistors in series, each one's lower end alone
//!   with the next one's upper end on a net that is not a rail, are drawn
//!   as one block, a stack, top to bottom. Massier, Graeb and Schlichtmann
//!   (Cites). `blocks`
//! - structure.12 (habit) A transistor is in at most one of a
//!   cross-coupled pair, a differential pair and a mirror or bank, taken in
//!   that order; a stack may share it. People: of 93 twos that are both a
//!   cross-coupled and a differential pair (a latch on a tail), 88 turn
//!   their gates toward each other, as a cross-coupled pair's; of 190
//!   transistors of a pair that stand level with the pair's other or with
//!   another transistor on their gate net, not both, 153 stand with the
//!   pair's (5,263 hand drawings). `blocks`
//!
//! Contents:
//! - `pub const none: u32`
//! - `pub const BlockKind = enum(u8) { pair, cross, mirror, bank, stack }`, `BlockKind.ofTwo(k: BlockKind) bool`, `BlockKind.verb(k: BlockKind) hints.Verb`
//! - `pub const Structure = struct`, `Structure.members(s: *const Structure, b: usize) []const u32`
//! - `Pins.holds(p: Pins, lines: []const u32) Allocator.Error!bool`: the admission test `hints.conflict` calls
//! - `pub fn analyze(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role) Allocator.Error!Structure`
//! - `pub fn nameLess(a: []const u8, b: []const u8) bool`
//! - `pub fn rankByName(arena: Allocator, gpa: Allocator, names: []const []const u8) Allocator.Error![]u32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const sch = @import("schematic.zig");
const symmetry = @import("symmetry.zig");
const hints = @import("hints.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const isRail = Role.isRail;
const Polarity = symmetry.Polarity;
const Verdict = hints.Verdict;

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

    /// A differential or a cross-coupled pair: exactly two members, each
    /// the other's half.
    pub fn ofTwo(k: BlockKind) bool {
        return k == .pair or k == .cross;
    }

    /// The grouping verb that states a block of this kind: its namesake.
    pub fn verb(k: BlockKind) hints.Verb {
        return switch (k) {
            inline else => |t| @field(hints.Verb, @tagName(t)),
        };
    }
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
    /// `*@ symmetry off`: no mates, not even a block's.
    symmetry_off: bool,
    /// Per deck hint: what became of it, for the lines this stage owns
    /// (grouping, `symmetric`, `axis`, `symmetry off`); null for the rest.
    verdicts: []const ?Verdict,

    pub fn members(s: *const Structure, b: usize) []const u32 {
        assert(b + 1 < s.block_start.len);
        assert(s.block_start[b] < s.block_start[b + 1]);
        return s.block_devices[s.block_start[b]..s.block_start[b + 1]];
    }
};

/// The nets of a transistor's path (`drain` and `source`, its two ends in
/// card order) and of its gate.
const Fet = struct {
    drain: u32,
    gate: u32,
    source: u32,
    polarity: Polarity,
    kind: DeviceKind,

    /// The terminal current enters by (`device.sourceUp`).
    fn upper(f: Fet) u32 {
        return if (device.sourceUp(f.polarity)) f.source else f.drain;
    }
    fn lower(f: Fet) u32 {
        return if (device.sourceUp(f.polarity)) f.drain else f.source;
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

/// The admission test for `symmetric` and `axis` lines: a symmetry swaps
/// every pair they name. Each test leaves its result in the mate tables.
const Pins = struct {
    gpa: Allocator,
    nl: *const Netlist,
    roles: []const Role,
    device_rank: []const u32,
    net_rank: []const u32,
    /// By hint: the pair a line names.
    pin: []symmetry.Pin,
    device_mate: []u32,
    net_mate: []u32,

    pub fn holds(p: Pins, lines: []const u32) Allocator.Error!bool {
        var pins: std.ArrayList(symmetry.Pin) = .empty;
        defer pins.deinit(p.gpa);
        for (lines) |i| try pins.append(p.gpa, p.pin[i]);
        return symmetry.find(p.gpa, p.nl, p.roles, p.device_rank, p.net_rank, pins.items, p.device_mate, p.net_mate);
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
    const verdicts = try arena.alloc(?Verdict, nl.hints.len);
    @memset(verdicts, null);
    const off = try mates(gpa, arena, nl, roles, device_rank, net_rank, device_mate, net_mate, verdicts);
    var out: Structure = .{
        .device_rank = device_rank,
        .net_rank = net_rank,
        .device_mate = device_mate,
        .net_mate = net_mate,
        .block_kind = &.{},
        .block_start = &.{},
        .block_devices = &.{},
        .symmetry_off = off,
        .verdicts = verdicts,
    };
    for (device_rank) |r| assert(r < device_rank.len);
    try blocks(gpa, arena, nl, roles, device_rank, net_rank, verdicts, &out);
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
    // Index breaks every name tie: stability cannot change this total order.
    std.sort.heap(u32, order, names, struct {
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
fn blocks(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, device_rank: []const u32, net_rank: []const u32, verdicts: []?Verdict, out: *Structure) !void {
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
    const hinted = try groupLines(gpa, arena, nl, device_rank, taken, &list, verdicts);
    defer gpa.free(hinted.held);
    const recognize = !hinted.off;

    // Cross-coupled pairs: a's gate is b's drain and b's gate a's drain.
    // Before differential pairs: of 93 twos that are both, people turn 88
    // gate to gate. Both before gate groups: of 190 transistors of a pair
    // level with the pair's other or a gate-net neighbour, not both, 153
    // stand with the pair's.
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
        for ([_]Polarity{ .n, .p, .other }) |pol| for (std.enums.values(DeviceKind)) |kind| {
            if (!device.isTransistor(kind)) continue;
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

/// The deck's grouping lines: each group added to `list` (in file order)
/// with its known devices no stronger line took (a pair or a cross-coupled
/// pair of two exactly), its members `taken` (a stack's: `held` from
/// recognized stacks); a device `*@ nogroup` names `taken` and `held`.
/// Lines are admitted later first (`hints.admitOrder`). `off`: the deck
/// turns recognition off.
fn groupLines(gpa: Allocator, arena: Allocator, nl: *const Netlist, device_rank: []const u32, taken: []bool, list: *BlockList, verdicts: []?Verdict) !struct { off: bool, held: []bool } {
    const n = taken.len;
    assert(device_rank.len == n);
    assert(verdicts.len == nl.hints.len);
    const held = try gpa.alloc(bool, n);
    errdefer gpa.free(held);
    @memset(held, false);
    // Busy by side: a stack holds its devices (1), any other group takes
    // them (0), `nogroup` both; and the line that did, for `blocked_by`.
    const busy = [2][]bool{ taken, held };
    const by = try gpa.alloc([2]u32, n);
    defer gpa.free(by);
    @memset(by, .{ none, none });
    var off = false;
    for (nl.hints, 0..) |h, i| switch (h.verb) {
        .off => {
            off = true;
            verdicts[i] = .of(.ok);
        },
        .nogroup => {
            var known: usize = 0;
            for (h.args) |name| if (nl.device(name)) |e| {
                for (busy) |flags| flags[e.index()] = true;
                by[e.index()] = .{ @intCast(i), @intCast(i) };
                known += 1;
            };
            verdicts[i] = if (known == h.args.len and known > 0) .of(.ok) else if (known > 0) .{ .state = .relaxed, .code = .unknown_name } else .of(if (h.args.len == 0) .bad_args else .unknown_name);
        },
        else => {},
    };
    const got = try gpa.alloc(?[]const u32, nl.hints.len);
    defer gpa.free(got);
    @memset(got, null);
    var members: std.ArrayList(u32) = .empty;
    defer members.deinit(gpa);
    var blockers: std.ArrayList(u32) = .empty;
    defer blockers.deinit(gpa);
    for (try hints.admitOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        const kind = blockKind(h.verb) orelse continue;
        const side: usize = @intFromBool(kind == .stack);
        members.clearRetainingCapacity();
        blockers.clearRetainingCapacity();
        var unknown = false;
        for (h.args) |name| {
            const d = (nl.device(name) orelse {
                unknown = true;
                continue;
            }).index();
            if (busy[side][d]) {
                const b = by[d][side];
                if (std.mem.indexOfScalar(u32, blockers.items, b) == null) try blockers.append(gpa, b);
                continue;
            }
            if (std.mem.indexOfScalar(u32, members.items, d) == null) try members.append(gpa, d);
        }
        const two = kind.ofTwo();
        if (members.items.len < 2 or (two and members.items.len != 2)) {
            verdicts[i] = if (blockers.items.len > 0 and !(two and members.items.len > 2)) try .blocked(arena, .dropped, .taken, blockers.items) else .of(if (unknown) .unknown_name else .bad_args);
            continue;
        }
        // In rank order, as recognition lists them; a stack top to bottom as
        // written. ponytail: insertion sort, quadratic, for the handful of
        // names a hint gives; `std.mem.sort` costs the plugin 8 KB more.
        if (kind != .stack) std.sort.insertion(u32, members.items, device_rank, struct {
            fn lt(rank: []const u32, a: u32, b: u32) bool {
                return rank[a] < rank[b];
            }
        }.lt);
        for (members.items) |d| {
            busy[side][d] = true;
            by[d][side] = @intCast(i);
        }
        got[i] = try arena.dupe(u32, members.items);
        verdicts[i] = if (blockers.items.len > 0) try .blocked(arena, .relaxed, .taken, blockers.items) else if (unknown) .{ .state = .relaxed, .code = .unknown_name } else .of(.ok);
    }
    for (nl.hints, got) |h, ms| if (ms) |m| try list.add(arena, blockKind(h.verb).?, m);
    for (by, taken, held) |b, t, h| {
        assert(b[0] == none or t);
        assert(b[1] == none or h);
    }
    return .{ .off = off, .held = held };
}

fn blockKind(v: hints.Verb) ?BlockKind {
    for (std.enums.values(BlockKind)) |k| if (k.verb() == v) return k;
    return null;
}

/// The symmetry under the deck's `symmetric`, `axis` and `symmetry off`
/// lines, filling both mate tables and each such line's verdict. Lines are
/// admitted strongest first, each when a symmetry still swaps every pair
/// admitted with it; a line no symmetry takes is dropped, its preferred
/// conflict (Junker) in `blocked_by`. Returns whether `symmetry off` holds.
fn mates(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, device_rank: []const u32, net_rank: []const u32, device_mate: []u32, net_mate: []u32, verdicts: []?Verdict) !bool {
    const order = try hints.admitOrder(arena, nl.hints);
    var off: ?u32 = null;
    for (order) |i| if (nl.hints[i].verb == .symmetry_off) {
        off = off orelse i;
        verdicts[i] = .of(.ok);
    };
    const check: Pins = .{ .gpa = gpa, .nl = nl, .roles = roles, .device_rank = device_rank, .net_rank = net_rank, .pin = try arena.alloc(symmetry.Pin, nl.hints.len), .device_mate = device_mate, .net_mate = net_mate };
    var admitted: std.ArrayList(u32) = .empty;
    defer admitted.deinit(gpa);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .symmetric and h.verb != .axis) continue;
        check.pin[i] = pinOf(nl, h) catch |err| {
            verdicts[i] = .of(if (err == error.Unknown) .unknown_name else .bad_args);
            continue;
        };
        if (off) |o| {
            verdicts[i] = try .blocked(arena, .dropped, .conflict, &.{o});
            continue;
        }
        try admitted.append(gpa, i);
        if (try check.holds(admitted.items)) {
            verdicts[i] = .of(.ok);
            continue;
        }
        _ = admitted.pop();
        var v = try hints.conflict(gpa, arena, check, admitted.items, i, .conflict);
        if (v.blocked_by.len == 0) v.code = .asymmetric;
        verdicts[i] = v;
    }
    if (off != null) {
        @memset(device_mate, none);
        @memset(net_mate, none);
        return true;
    }
    const found = try check.holds(admitted.items);
    assert(found or admitted.items.len == 0);
    return false;
}

/// The pair a `symmetric a b` line swaps, or the one an `axis x` line fixes:
/// two devices or two nets.
fn pinOf(nl: *const Netlist, h: hints.Hint) error{ Unknown, Malformed }!symmetry.Pin {
    const want: usize = if (h.verb == .axis) 1 else 2;
    if (h.args.len != want) return error.Malformed;
    const a = h.args[0];
    const b = h.args[want - 1];
    if (nl.device(a)) |x| {
        const y = nl.device(b) orelse return if (nl.net(b) == null) error.Unknown else error.Malformed;
        return .{ .net = false, .a = x.index(), .b = y.index() };
    }
    if (nl.net(a)) |x| {
        const y = nl.net(b) orelse return if (nl.device(b) == null) error.Unknown else error.Malformed;
        return .{ .net = true, .a = x.index(), .b = y.index() };
    }
    return error.Unknown;
}

fn transistor(nl: *const Netlist, d: u32) ?Fet {
    assert(d < nl.graph.edgeCount());
    const e = EdgeId.from(d);
    const kind = nl.graph.edges.items(.kind)[d];
    const gate = device.of(kind).gate orelse return null;
    const path = device.of(kind).path.?;
    const pins = nl.graph.members(e);
    if (pins.len <= @max(gate, path[1])) return null;
    assert(pins[0].index() < nl.graph.vertexCount());
    return .{
        .drain = pins[path[0]].index(),
        .gate = pins[gate].index(),
        .source = pins[path[1]].index(),
        .polarity = symmetry.polarity(nl.modelType(e)),
        .kind = kind,
    };
}
