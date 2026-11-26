//! Complete ordered MOS involutions with explicit exhaustion and ambiguity certificates.
//!
//! Contents:
//! - `pub const Map`
//! - `pub const State`
//! - `pub const Result`
//! - `pub const Limits`
//! - `pub fn find(arena: Allocator, ctx: context.Context, order: []const u32, limits: Limits) !Result`

const std = @import("std");
const netlist = @import("netlist.zig");
const context = @import("parent_context.zig");
const Allocator = std.mem.Allocator;

/// Natural graph indices. An unused vertex (e.g. implicit ground) has no map.
pub const Map = struct { devices: []const u32, nets: []const u32 };
/// A completed uniqueness decision or an explicit bounded-search decline.
pub const State = enum { complete_none, complete_unique, ambiguous, exhausted };
/// Retains the first and second complete witnesses, when witnessed, and work consumed.
pub const Result = struct { state: State, first: ?Map = null, second: ?Map = null, states: usize = 0 };
/// State budget and recursion-depth ceiling are independent of witness storage.
pub const Limits = struct { states: usize = 100_000, devices: u32 = 128 };

const none = std.math.maxInt(u32);

const Pending = struct { keys: [8]u32 = undefined, len: usize = 0 };
const Search = struct {
    arena: Allocator,
    nl: *const netlist.Netlist,
    order: []const u32,
    compatible: []const bool,
    dmap: []u32,
    nmap: []u32,
    result: Result,
    limit: usize,
    fn undo(s: *Search, p: Pending) void {
        for (p.keys[0..p.len]) |i| s.nmap[i] = none;
    }
    fn put(s: *Search, p: *Pending, a: u32, b: u32) bool {
        if (s.nmap[a] != none) return s.nmap[a] == b;
        s.nmap[a] = b;
        p.keys[p.len] = a;
        p.len += 1;
        return true;
    }
    fn extend(s: *Search, d: u32, e: u32) ?Pending {
        if (s.dmap[e] != none or !s.compatible[@as(usize, d) * s.dmap.len + e]) return null;
        var p: Pending = .{};
        for (s.nl.graph.members(netlist.EdgeId.from(d)), s.nl.graph.members(netlist.EdgeId.from(e))) |a, b| {
            if (!s.put(&p, a.index(), b.index()) or !s.put(&p, b.index(), a.index())) {
                s.undo(p);
                return null;
            }
        }
        return p;
    }
    fn visit(s: *Search) Allocator.Error!void {
        if (s.result.states >= s.limit) {
            s.result.state = .exhausted;
            return;
        }
        s.result.states += 1;
        var chosen: u32 = none;
        var best: usize = s.dmap.len + 1;
        for (s.order) |d| {
            if (s.dmap[d] != none) continue;
            var possible: usize = 0;
            for (s.order) |e| if (s.extend(d, e)) |p| {
                s.undo(p);
                possible += 1;
                if (possible >= best) break;
            };
            if (possible == 0) return;
            if (possible < best) {
                chosen = d;
                best = possible;
            }
        }
        if (chosen == none) {
            const moves_net = for (s.nmap, 0..) |to, n| {
                if (to != none and to != n) break true;
            } else false;
            if (!moves_net) return;
            const m = Map{ .devices = try s.arena.dupe(u32, s.dmap), .nets = try s.arena.dupe(u32, s.nmap) };
            if (s.result.first == null) {
                s.result.first = m;
                s.result.state = .complete_unique;
            } else {
                s.result.second = m;
                s.result.state = .ambiguous;
            }
            return;
        }
        for (s.order) |e| if (s.extend(chosen, e)) |p| {
            s.dmap[chosen] = e;
            s.dmap[e] = chosen;
            try s.visit();
            s.dmap[chosen] = none;
            s.dmap[e] = none;
            s.undo(p);
            if (s.result.state == .ambiguous or s.result.state == .exhausted) return;
        };
    }
};

/// A unique result proves every other admitted complete device/net reflection
/// was excluded. Two distinct net-moving maps immediately certify ambiguity.
pub fn find(arena: Allocator, ctx: context.Context, order: []const u32, limits: Limits) !Result {
    const nl = ctx.nl;
    const n = nl.graph.edgeCount();
    const v = nl.graph.vertexCount();
    std.debug.assert(ctx.reasons.count() == 0 and order.len == n);
    if (n > @min(limits.devices, 128)) return .{ .state = .exhausted };
    const dmap = try arena.alloc(u32, n);
    const nmap = try arena.alloc(u32, v);
    @memset(dmap, none);
    @memset(nmap, none);
    const incidence = try arena.alloc([4]u32, v);
    @memset(incidence, .{ 0, 0, 0, 0 });
    for (order) |d| for (nl.graph.members(netlist.EdgeId.from(d)), 0..) |pin, t| {
        incidence[pin.index()][t] += 1;
    };
    const compatible = try arena.alloc(bool, @as(usize, n) * n);
    for (order) |d| for (order) |e| {
        const de = netlist.EdgeId.from(d);
        const ee = netlist.EdgeId.from(e);
        const ps = nl.params(de);
        const qs = nl.params(ee);
        var same = ps.len == qs.len;
        if (same) for (ps, qs) |a, b| {
            if (!std.mem.eql(u8, a, b)) {
                same = false;
                break;
            }
        };
        if (same) for (nl.graph.members(de), nl.graph.members(ee)) |a, b| {
            const x = a.index();
            const y = b.index();
            if (ctx.kind[x] != ctx.kind[y] or (isRail(ctx.kind[x]) and x != y) or !std.mem.eql(u32, &incidence[x], &incidence[y])) {
                same = false;
                break;
            }
        };
        compatible[@as(usize, d) * n + e] = same;
    };
    var work = Search{ .arena = arena, .nl = nl, .order = order, .compatible = compatible, .dmap = dmap, .nmap = nmap, .result = .{ .state = .complete_none }, .limit = limits.states };
    try work.visit();
    return work.result;
}

// ---- private ----
fn isRail(k: context.NetKind) bool {
    return k == .supply or k == .sink;
}
