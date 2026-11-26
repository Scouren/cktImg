//! Unique CT / L-C-L paths -> three-passive relative placement requests.
//!
//! Human Rules:
//! - ct_series_tanks.1 (bounded observation) Two correlated AG1153 groups
//!   have perpendicular outer series inductors and a centered parallel C
//!   beyond them, opposite the actual tap. Count raw competitors and shared
//!   owners before eligibility. No source ID, value or world direction is
//!   selected. Source: docs/research/ct-series-tanks.md. `raw`, `find`
//! - ct_series_tanks.2 (choice) Keep the centered actual coil fixed. One
//!   complete-body-spaced proposal moves only L/L/C; all failed poses,
//!   signed reaches or collisions restore three full rows and coordinates.
//!   Caller requests/mates/groups win. No search or wire bypass. `place`
//! - ct_series_tanks.3 (bounded habit) Protect the complete four-member
//!   column span from a shelf cut, without reserving empty rows. Explicit
//!   wrap precedence wins. Semantic spans remain even when later actual
//!   frames abstain; only the three-row geometry transaction rolls back. `spans`
//! - ct_series_tanks.4 (invariant) Real midpoint/near-tip tracks retain
//!   equalities. Initially true actual-tip orders enter the existing single
//!   compaction pass; physical conductor paths remain independent. `orders`
//!
//! Data: borrowed CSR/roles/classes/admitted requests in; cold four-EdgeId
//! records (16 bytes) and three passive rows out. At most complete-CT count
//! records, all handles consumed together once per phase. Twelve i32 order
//! pairs per success cover either world axis. Caller owns both buffers for
//! one draw; allocation precedes mutation. Canonical order serializes body
//! collisions. Three old rows and candidate points are fixed stack scratch.
//! Recognition is outside cut-cost/routing loops; no speed claim is made.
//!
//! Contents: Group, Batch, Batch.deinit, spans, collect, place, orders; private.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const block_symbols = @import("block_symbols.zig");
const actual_anchor = @import("actual_anchor.zig");
const Lengths = @import("canvas.zig").Lengths;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Pt = library.Pt;
const Side = library.Side;

/// Center-tapped winding, N1-side L, N2-side L, far-net capacitor.
pub const Group = [4]EdgeId;

/// Caller-owned cold candidates/successes and bounded coordinate requests.
pub const Batch = struct {
    groups: std.ArrayList(Group),
    coordinates: [][2]i32,

    /// Releases both buffers with the allocator passed to collect.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.groups.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

const Frame = struct { along: Side, away: Side, half: i64 };
comptime {
    assert(@sizeOf(Group) == 16);
}

/// Merges complete semantic group spans for cutting only. An empty list
/// leaves previous borrowed. Collection occurs before cut-cost scans;
/// caller frees the result and retains its separate row-gap reservations.
pub fn spans(gpa: Allocator, nl: *const Netlist, roles: []const sch.Role, drawn: []const bool, x: []const i32, previous: []const [2]i32) Allocator.Error!std.ArrayList([2]i32) {
    assert(drawn.len == nl.graph.edgeCount() and x.len == drawn.len);
    assert(roles.len == nl.graph.vertexCount());
    var out: std.ArrayList([2]i32) = .empty;
    errdefer out.deinit(gpa);
    for (nl.graph.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt) continue;
        const group = find(nl, roles, .from(d)) orelse continue;
        if (for (group) |edge| {
            if (!drawn[edge.index()]) break true;
        } else false) continue;
        if (out.capacity == 0) {
            try out.ensureTotalCapacity(gpa, previous.len + capacity(nl));
            out.appendSliceAssumeCapacity(previous);
        }
        var lo = x[d];
        var hi = x[d];
        for (group[1..]) |edge| {
            lo = @min(lo, x[edge.index()]);
            hi = @max(hi, x[edge.index()]);
        }
        out.appendAssumeCapacity(.{ lo, hi });
    }
    return out;
}

/// Collects complete unheld groups while original admitted at/route intent
/// is available. All borrowed tables span nl; allocation changes no rows.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    assert(ats.len == nl.graph.edgeCount() and sk.drawn.len == ats.len);
    assert(lines.style.len == nl.graph.vertexCount() and st.device_mate.len == ats.len);
    var groups: std.ArrayList(Group) = .empty;
    errdefer groups.deinit(gpa);
    try groups.ensureTotalCapacity(gpa, capacity(nl));
    for (nl.graph.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt) continue;
        const group = find(nl, s.roles, .from(d)) orelse continue;
        const blocked = blocked: for (group) |edge| {
            const i = edge.index();
            if (!sk.drawn[i] or ats[i] != null or sk.shelf[i] != sk.shelf[d] or st.device_mate[i] != sch.none or held(nl, sk, st, edge)) break true;
            for (st.block_devices) |member| if (member == i) break :blocked true;
            if (nl.defOf(edge)) |def| for (def.sides) |side| if (side != null) break :blocked true;
            for (nl.graph.members(edge)) |net| {
                if (lines.style[net.index()] != .auto or lines.port[net.index()] != null) break :blocked true;
                for (lines.routes) |route| if (route.net == net.index()) break :blocked true;
            }
        } else false;
        if (!blocked) groups.appendAssumeCapacity(group);
    }
    std.sort.heap(Group, groups.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Group, b: Group) bool {
            return rank[a[0].index()] < rank[b[0].index()];
        }
    }.less);
    const coordinates = try gpa.alloc([2]i32, 12 * groups.items.len);
    return .{ .groups = groups, .coordinates = coordinates };
}

/// Attempts one actual-frame candidate per group. Only successful groups
/// remain; all failed attempts restore every passive row and coordinate.
pub fn place(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, groups: *std.ArrayList(Group)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (groups.items) |group| {
        if (!attempt(s, nl, sk, ats, len, at, group)) continue;
        groups.items[kept] = group;
        kept += 1;
    }
    groups.items = groups.items[0..kept];
}

/// Appends six longitudinal and three transverse strict actual-tip orders.
/// Real shared tracks retain equalities. Storage holds twelve pairs per
/// success, split equally by world axis; no second compaction pass occurs.
pub fn orders(s: *const sch.Schematic, nl: *const Netlist, groups: []const Group, storage: [][2]i32) [2][]const [2]i32 {
    const count = 6 * groups.len;
    assert(storage.len >= 2 * count);
    assert(s.xy.len == s.nodes.len);
    var used: [2]usize = .{ 0, 0 };
    for (groups) |group| {
        const f = frame(s, nl, group) orelse continue;
        var p: [9]Pt = undefined;
        for (&p, 0..) |*point, i| {
            const member, const pin = binding(nl, group, i);
            point.* = Pt.round(s.xy[s.deviceNode(group[member].index()).?]).add(tip(s, group[member], pin));
        }
        const center = Pt.round(s.xy[s.deviceNode(group[0].index()).?]);
        const along = [_]Pt{ p[3], p[0], p[7], center, p[8], p[1], p[5] };
        const across = [_]Pt{ p[0], p[3], p[4], p[7] };
        if (!increasing(&along, f.along) or !increasing(&across, f.away)) continue;
        for (along[0..6], along[1..]) |a, b| keep(storage, count, &used, f.along, a, b);
        for (across[0..3], across[1..]) |a, b| keep(storage, count, &used, f.away, a, b);
    }
    return .{ storage[0..used[0]], storage[count..][0..used[1]] };
}

// ---- private ----

fn capacity(nl: *const Netlist) usize {
    var n: usize = 0;
    for (nl.graph.edges.items(.kind), 0..) |kind, d| if (kind == .subckt and ports(nl, .from(d)) != null) {
        n += 1;
    };
    return n;
}
fn ports(nl: *const Netlist, edge: EdgeId) ?[3]u2 {
    const def = nl.defOf(edge) orelse return null;
    if (block_symbols.identify(def.name, def.ports) != .center_tap or nl.graph.members(edge).len != 3) return null;
    var p: [3]u2 = undefined;
    for (def.ports, 0..) |name, i| for ([_][]const u8{ "n1", "n2", "n3" }, 0..) |want, j| if (std.ascii.eqlIgnoreCase(name, want)) {
        p[j] = @intCast(i);
    };
    return p;
}
fn same(p: []const VertexId, a: VertexId, b: VertexId) bool {
    return p.len == 2 and ((p[0] == a and p[1] == b) or (p[0] == b and p[1] == a));
}
fn raw(nl: *const Netlist, coil: EdgeId) ?Group {
    const c = &nl.graph;
    const cp = ports(nl, coil) orelse return null;
    const p = c.members(coil);
    const ends = [2]VertexId{ p[cp[0]], p[cp[1]] };
    var group: Group = .{ coil, .from(sch.none), .from(sch.none), .from(sch.none) };
    var rivals: usize = 0;
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt) continue;
        const other = EdgeId.from(d);
        const op = ports(nl, other) orelse continue;
        const q = c.members(other);
        if ((q[op[0]] == ends[0] and q[op[1]] == ends[1]) or (q[op[0]] == ends[1] and q[op[1]] == ends[0])) rivals += 1;
    }
    if (rivals != 1) return null;
    var far: [2]VertexId = undefined;
    for (ends, 0..) |net, i| {
        var n: usize = 0;
        for (c.incident(net)) |edge| if (c.edges.items(.kind)[edge.index()] == .inductor) {
            n += 1;
            group[1 + i] = edge;
        };
        if (n != 1) return null;
        const q = c.members(group[1 + i]);
        if (q.len != 2 or q[0] == q[1]) return null;
        far[i] = if (q[0] == net) q[1] else q[0];
    }
    const nets = [_]VertexId{ ends[0], ends[1], far[0], far[1], p[cp[2]] };
    for (nets, 0..) |net, i| for (nets[0..i]) |old| if (net == old) return null;
    var caps: usize = 0;
    for (c.edges.items(.kind), 0..) |kind, d| if (kind == .capacitor and same(c.members(.from(d)), far[0], far[1])) {
        caps += 1;
        group[3] = .from(d);
    };
    return if (caps == 1 and group[1] != group[2]) group else null;
}
fn find(nl: *const Netlist, roles: []const sch.Role, coil: EdgeId) ?Group {
    const group = raw(nl, coil) orelse return null;
    for (nl.graph.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt or d == coil.index()) continue;
        const other = raw(nl, .from(d)) orelse continue;
        for (group) |a| for (other) |b| if (a == b) return null;
    }
    const cp = ports(nl, coil).?;
    const p = nl.graph.members(coil);
    if (roles[p[cp[2]].index()] != .supply) return null;
    for (group[1..]) |edge| for (nl.graph.members(edge)) |net| if (roles[net.index()].isRail()) return null;
    return group;
}
fn held(nl: *const Netlist, sk: *const skeleton.Skeleton, st: *const structure.Structure, edge: EdgeId) bool {
    for (nl.hints, sk.verdicts, st.verdicts) |hint, sv, tv| {
        const verdict = sv orelse tv orelse continue;
        if (verdict.state != .honoured and verdict.state != .relaxed) continue;
        switch (hint.verb) {
            .off, .symmetry_off, .axis => return true,
            .pair, .mirror, .bank, .stack, .cross, .nogroup, .symmetric, .row, .above, .order, .cell, .face, .upright, .bridge, .at => {},
            else => continue,
        }
        for (hint.args) |name| if ((nl.device(name) orelse continue) == edge) return true;
    }
    return false;
}
fn binding(nl: *const Netlist, group: Group, i: usize) struct { usize, usize } {
    assert(i < 9);
    const cp = ports(nl, group[0]).?;
    if (i < 3) return .{ 0, cp[i] };
    const side = if (i < 7) (i - 3) / 2 else i - 7;
    const near = nl.graph.members(group[0])[cp[side]];
    const lp = nl.graph.members(group[side + 1]);
    const first: usize = @intFromBool(lp[0] != near);
    if (i < 7) return .{ side + 1, if ((i - 3) % 2 == 0) first else 1 - first };
    return .{ 3, @intFromBool(nl.graph.members(group[3])[0] != lp[1 - first]) };
}
fn tip(s: *const sch.Schematic, edge: EdgeId, pin: usize) Pt {
    const row = s.devices.get(edge.index());
    return row.orient.apply(s.lib.at(row.class).terminals[pin].at).sub(row.grid);
}
fn frame(s: *const sch.Schematic, nl: *const Netlist, group: Group) ?Frame {
    const d = group[0].index();
    const class = s.lib.at(s.devices.items(.class)[d]);
    if (class.terminals.len != 3) return null;
    for (class.terminals) |p| if (p.hidden or p.ground_ref) return null;
    const cp = ports(nl, group[0]).?;
    const a, const b, const t = .{ tip(s, group[0], cp[0]), tip(s, group[0], cp[1]), tip(s, group[0], cp[2]) };
    if (@as(i64, a.x) + b.x != 0 or @as(i64, a.y) + b.y != 0) return null;
    const along = Side.of(b) orelse return null;
    const tap = Side.of(t) orelse return null;
    if ((b.x != 0 and b.y != 0) or (t.x != 0 and t.y != 0) or !along.perpendicular(tap)) return null;
    if (s.pinSide(d, cp[0]) != along.opposite() or s.pinSide(d, cp[1]) != along or s.pinSide(d, cp[2]) != tap) return null;
    return .{ .along = along, .away = tap.opposite(), .half = project(b, along) };
}
fn turn(s: *sch.Schematic, nl: *const Netlist, edge: EdgeId, first: usize, side: Side, centered: bool) bool {
    const d = edge.index();
    const class = s.lib.at(s.devices.items(.class)[d]);
    if (class.terminals.len != 2) return false;
    for (class.terminals) |p| if (p.hidden or p.ground_ref) return false;
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
        s.devices.items(.orientation)[d] = form;
        s.devices.items(.flip_x)[d] = flips[0];
        s.devices.items(.flip_y)[d] = flips[1];
        sch.settleDevice(s, &nl.graph, d);
        const a, const b = .{ tip(s, edge, first), tip(s, edge, 1 - first) };
        if (project(b, side) <= project(a, side) or project(a, side.transposed()) != project(b, side.transposed())) continue;
        if (s.pinSide(d, first) != side.opposite() or s.pinSide(d, 1 - first) != side) continue;
        var anchor = a;
        if (centered) {
            const x, const y = .{ @as(i64, a.x) + b.x, @as(i64, a.y) + b.y };
            if (@mod(x, 2) != 0 or @mod(y, 2) != 0) continue;
            anchor = .{ .x = @intCast(@divExact(x, 2)), .y = @intCast(@divExact(y, 2)) };
        }
        actual_anchor.move(s, nl, d, anchor);
        if (actual_anchor.representable(s, nl, d)) return true;
    };
    return false;
}
fn attempt(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, group: Group) bool {
    const f = frame(s, nl, group) orelse return false;
    var before: [3]sch.DeviceInfo = undefined;
    for (group[1..], &before) |edge, *row| row.* = s.devices.get(edge.index());
    var committed = false;
    defer if (!committed) {
        for (group[1..], before) |edge, row| s.devices.set(edge.index(), row);
    };
    for (0..3) |i| {
        const member, const pin = binding(nl, group, if (i < 2) 3 + 2 * i else 7);
        if (!turn(s, nl, group[member], pin, if (i < 2) f.away else f.along, i == 2)) return false;
    }
    const far0 = binding(nl, group, 4)[1];
    const far1 = binding(nl, group, 6)[1];
    const cap_end = binding(nl, group, 8)[1];
    const length = project(tip(s, group[1], far0), f.away);
    if (length != project(tip(s, group[2], far1), f.away)) return false;
    const half = project(tip(s, group[3], cap_end), f.along);
    if (half <= 0 or half >= f.half) return false;
    var box: [4]library.Rect = undefined;
    for (group, &box) |edge, *b| b.* = s.boxAt(edge.index(), .zero);
    const gap: i64 = @max(len.stack, len.clearance + 1);
    const h = @max(f.half + gap, @max(high(box[1], f.along) - low(box[0], f.along) + gap, high(box[0], f.along) - low(box[2], f.along) + gap));
    const near = @max(1, high(box[0], f.away) - @min(low(box[1], f.away), low(box[2], f.away)) + gap);
    const far = @max(near + length + gap, near + @max(high(box[1], f.away), high(box[2], f.away)) - low(box[3], f.away) + gap);
    const origin = Pt.round(at[group[0].index()]);
    const points = [3]Pt{ mapped(origin, f, -h, near) orelse return false, mapped(origin, f, h, near) orelse return false, mapped(origin, f, 0, far) orelse return false };
    for (group[1..], points, 0..) |edge, p, i| {
        const candidate = s.boxAt(edge.index(), p).grow(len.clearance);
        for (group[1..][i + 1 ..], points[i + 1 ..]) |other, q| if (candidate.intersects(s.boxAt(other.index(), q))) return false;
        for (at, sk.drawn, 0..) |xy, visible, d| {
            if (!visible or contains(group[1..], d)) continue;
            const other = if (ats[d]) |fixed| s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin) else s.boxAt(@intCast(d), Pt.round(xy));
            if (candidate.intersects(other)) return false;
        }
    }
    for (group[1..], points) |edge, p| at[edge.index()] = p.toF();
    committed = true;
    return true;
}
fn contains(group: []const EdgeId, d: usize) bool {
    for (group) |edge| if (edge.index() == d) return true;
    return false;
}
fn project(p: Pt, side: Side) i64 {
    const v = side.unit();
    return @as(i64, p.x) * v.x + @as(i64, p.y) * v.y;
}
fn low(box: library.Rect, side: Side) i64 {
    return @min(project(box.min, side), project(box.max, side));
}
fn high(box: library.Rect, side: Side) i64 {
    return @max(project(box.min, side), project(box.max, side));
}
fn mapped(origin: Pt, f: Frame, u: i64, v: i64) ?Pt {
    const a, const b = .{ f.along.unit(), f.away.unit() };
    return .{ .x = std.math.cast(i32, @as(i64, origin.x) + a.x * u + b.x * v) orelse return null, .y = std.math.cast(i32, @as(i64, origin.y) + a.y * u + b.y * v) orelse return null };
}
fn increasing(points: []const Pt, side: Side) bool {
    for (points[0 .. points.len - 1], points[1..]) |a, b| if (project(a, side) >= project(b, side)) return false;
    return true;
}
fn keep(storage: [][2]i32, capacity_: usize, used: *[2]usize, side: Side, a: Pt, b: Pt) void {
    const axis: usize = @intFromBool(!side.isHorizontal());
    const x, const y = if (axis == 0) .{ a.x, b.x } else .{ a.y, b.y };
    assert(used[axis] < capacity_ and x != y);
    storage[axis * capacity_ + used[axis]] = .{ @min(x, y), @max(x, y) };
    used[axis] += 1;
}

test {
    _ = @import("ct_series_tanks_test.zig");
}

test "CT series selector: complete competitors and shared owners precede eligibility" {
    const testing = std.testing;
    const base = "Series selector\n.subckt ct_inductor n1 n2 n3\nL1 n1 n3 1n\nL2 n3 n2 1n\n.ends\nXL a b vdd ct_inductor\nLS1 a c 1n\nLS2 b d 1n\nC1 c d 1p\n";
    for ([_][]const u8{
        "",                               "Lextra a z 1n\n",                                          "Lextra a a 1n\n", "Cextra d c 1p\n",
        "Xextra b a other ct_inductor\n", "Cextra a b 1p\nXextra c d unclassified_tap ct_inductor\n",
    }, 0..) |extra, index| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try a.print("{s}{s}", .{ base, extra });
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        const coil = nl.device("xl").?;
        try testing.expectEqual(index == 0, find(&nl, roles, coil) != null);
        if (index == 5) {
            try testing.expect(raw(&nl, coil) != null);
            const other = nl.device("xextra").?;
            try testing.expect(raw(&nl, other) != null);
            try testing.expect(roles[nl.graph.members(other)[2].index()] != .supply);
        }
    }
}
