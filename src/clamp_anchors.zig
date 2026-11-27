//! Actual channel-ended anchor frames -> one local antiparallel placement.
//!
//! Human Rules:
//! - clamp_anchors.1 (habit, bounded) A unique MOS clamp between two
//!   complementary drain-ended stacks lies strictly inside their four drain
//!   tips. AG739/1048/1052 supply three actual source examples; AG1149 has
//!   only one external channel per end and is excluded. Count channel-end
//!   competitors before polarity, visibility or geometry. `find`
//! - clamp_anchors.2 (choice) Try one midpoint candidate, with separate
//!   channel rows spaced by the actual boxes and configured stack distance.
//!   No lattice rows or other devices move. Unsupported frames, admitted
//!   caller constraints, external mates, styles or collisions abstain for
//!   the whole pair. An inferred mirror's diode reference can move here;
//!   inferred reciprocal mates can move together. Honoured caller mirror
//!   and symmetry lines still own placement. Only the two positions
//!   commit. `collect`, `place`
//! - clamp_anchors.3 (invariant) Preserve initially strict actual terminal
//!   inequalities through the existing compactor. No wire or label rule
//!   changes, and no source-distance or shared-column claim follows. `orders`
//!
//! Data: CSR/model rows, settled symbols, admitted hints and positions in;
//! two coordinate writes and cold order requests out. Each 24-byte group
//! has six typed u32 handles, read together once per draw. At most half the
//! device count are candidates; sixteen i32 coordinate pairs per success.
//! Caller-owned buffers live only through drawValid; allocation precedes
//! mutation. Placement is serial because proposals share collision space.
//!
//! Contents: Group, Batch, Batch.deinit, collect, place, orders;
//! private queries and tests.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const library = @import("library.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const antiparallel = @import("antiparallel.zig");
const Lengths = @import("canvas.zig").Lengths;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Pt = library.Pt;
const Rect = library.Rect;

/// Two clamps, two upper drain anchors, then two lower drain anchors.
/// Each anchor pair follows the clamps' respective first-end nets.
pub const Group = [6]EdgeId;

/// Cold candidate/success rows and caller-owned compaction request storage.
pub const Batch = struct {
    groups: std.ArrayList(Group),
    coordinates: [][2]i32,

    /// Frees both buffers with the allocator used by collect.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.groups.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

comptime {
    assert(@sizeOf(Group) == 24);
}

/// Collects caller-unheld groups before relay consumes weak stays. Every
/// device/net slice spans nl; all allocations finish before geometry writes.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    const c = &nl.graph;
    assert(ats.len == c.edgeCount() and sk.drawn.len == c.edgeCount());
    assert(lines.style.len == c.vertexCount() and st.device_rank.len == c.edgeCount());
    var groups: std.ArrayList(Group) = .empty;
    errdefer groups.deinit(gpa);
    try groups.ensureTotalCapacity(gpa, c.edgeCount() / 2);
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .mosfet) continue;
        const group = find(nl, s.roles, EdgeId.from(d)) orelse continue;
        if (st.device_rank[d] > st.device_rank[group[1].index()]) continue;
        const blocked = for (group) |e| {
            const i = e.index();
            if (!sk.drawn[i] or ats[i] != null or sk.shelf[i] != sk.shelf[d] or
                antiparallel.held(nl, sk.verdicts, e, e) or antiparallel.held(nl, st.verdicts, e, e)) break true;
        } else false;
        if (blocked) continue;
        const other = group[1].index();
        const a_mate, const b_mate = .{ st.device_mate[d], st.device_mate[other] };
        if (!((a_mate == sch.none and b_mate == sch.none) or (a_mate == other and b_mate == d))) continue;
        const owned = owned: for (st.block_kind, 0..) |block, b| {
            if (block == .mirror) continue;
            for (st.members(b)) |e| {
                if (e == d or e == group[1].index()) break :owned true;
            }
        } else false;
        if (owned) continue;
        const p = c.members(group[0]);
        const styled = styled: for ([_]usize{ 0, 2 }) |pin| {
            const net = p[pin].index();
            if (lines.style[net] != .auto or lines.port[net] != null) break true;
            for (lines.routes) |route| if (route.net == net) break :styled true;
        } else false;
        if (!styled) groups.appendAssumeCapacity(group);
    }
    std.sort.heap(Group, groups.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Group, b: Group) bool {
            return rank[a[0].index()] < rank[b[0].index()];
        }
    }.less);
    const coordinates = try gpa.alloc([2]i32, 16 * groups.items.len);
    return .{ .groups = groups, .coordinates = coordinates };
}

/// Tries one actual-frame proposal per group and retains only successful
/// groups. Other device rows and all coordinates remain unchanged on failure.
/// No allocation, symbol reorientation or lattice mutation occurs here.
pub fn place(s: *const sch.Schematic, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, groups: *std.ArrayList(Group)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (groups.items) |group| {
        const points = proposal(s, group, len, at) orelse continue;
        const blocked = blocked: for (group[0..2], points) |e, point| {
            const candidate = s.boxAt(e.index(), point).grow(len.clearance);
            for (at, sk.drawn, 0..) |xy, visible, other| {
                if (!visible or other == group[0].index() or other == group[1].index()) continue;
                const box = if (ats[other]) |fixed|
                    s.lib.at(s.devices.items(.class)[other]).box(fixed.orient orelse s.devices.items(.orient)[other], fixed.origin)
                else
                    s.boxAt(other, Pt.round(xy));
                if (candidate.intersects(box)) break :blocked true;
            }
        } else false;
        if (blocked or s.boxAt(group[0].index(), points[0]).grow(len.clearance).intersects(s.boxAt(group[1].index(), points[1]))) continue;
        for (group[0..2], points) |e, point| at[e.index()] = point.toF();
        groups.items[kept] = group;
        kept += 1;
    }
    groups.items = groups.items[0..kept];
}

/// Records eight strict inequalities per axis from the actual wired
/// scaffold. Storage has sixteen slots per successful group; the compactor
/// owns all coordinate movement and the caller retains these slices.
pub fn orders(s: *const sch.Schematic, groups: []const Group, storage: [][2]i32) [2][]const [2]i32 {
    const capacity = 8 * groups.len;
    assert(storage.len >= 2 * capacity);
    assert(s.xy.len == s.nodes.len);
    var count: [2]usize = .{ 0, 0 };
    for (groups) |group| {
        var at: [6]Pt = undefined;
        for (group, &at) |e, *p| p.* = Pt.round(s.xy[s.deviceNode(e.index()).?]);
        const bounds = rectangle(s, group, at) orelse continue;
        for (group[0..2], at[0..2]) |e, point| for ([_]usize{ 0, 2 }) |pin| {
            const p = point.add(tip(s, e, pin));
            for ([_][3]i32{ .{ bounds.min.x, p.x, bounds.max.x }, .{ bounds.min.y, p.y, bounds.max.y } }, 0..) |v, axis| {
                if (v[0] >= v[1] or v[1] >= v[2]) continue;
                storage[axis * capacity + count[axis]] = .{ v[0], v[1] };
                storage[axis * capacity + count[axis] + 1] = .{ v[1], v[2] };
                count[axis] += 2;
            }
        };
    }
    return .{ storage[0..count[0]], storage[capacity..][0..count[1]] };
}

// ---- private ----

fn find(nl: *const Netlist, roles: []const sch.Role, d: EdgeId) ?Group {
    const c = &nl.graph;
    if (c.edges.items(.kind)[d.index()] != .mosfet) return null;
    const mate = antiparallel.find(nl, roles, d) orelse return null;
    var out: Group = .{ d, mate, d, d, d, d };
    const ends = [2]netlist.VertexId{ c.members(d)[0], c.members(mate)[0] };
    for (ends, 0..) |net, i| {
        var count: usize = 0;
        var seen: [2]bool = .{ false, false };
        var previous: ?EdgeId = null;
        for (c.incident(net)) |e| {
            if (previous == e) continue;
            previous = e;
            if (e == d or e == mate or !device.isTransistor(c.edges.items(.kind)[e.index()])) continue;
            const p = c.members(e);
            if (p[0] != net and p[2] != net) continue;
            count += 1;
            if (count > 2 or c.edges.items(.kind)[e.index()] != .mosfet or p[0] != net or p[2] == ends[0] or p[2] == ends[1]) return null;
            const polarity: usize = switch (device.polarity(nl.modelType(e))) {
                .p => 0,
                .n => 1,
                .other => return null,
            };
            if (seen[polarity]) return null;
            seen[polarity] = true;
            out[2 + 2 * polarity + i] = e;
        }
        if (count != 2) return null;
    }
    const high, const low = .{ c.members(out[2])[2], c.members(out[4])[2] };
    if (high != c.members(out[3])[2] or low != c.members(out[5])[2] or high == low) return null;
    for (out, 0..) |e, i| for (out[0..i]) |other| if (e == other) return null;
    return out;
}

fn tip(s: *const sch.Schematic, d: EdgeId, pin: usize) Pt {
    const info = s.devices.get(d.index());
    return info.orient.apply(s.lib.at(info.class).terminals[pin].at).sub(info.grid);
}

fn rectangle(s: *const sch.Schematic, group: Group, at: [6]Pt) ?Rect {
    var drains: [4]Pt = undefined;
    for (group[2..], at[2..], &drains, 0..) |e, point, *drain, i| {
        const class = s.lib.at(s.devices.items(.class)[e.index()]);
        if (!class.shows(0) or !class.shows(2) or class.terminals[0].ground_ref or class.terminals[2].ground_ref) return null;
        const a, const b = .{ tip(s, e, 0), tip(s, e, 2) };
        const down = i < 2;
        if (a.x != b.x or (if (down) a.y <= b.y else a.y >= b.y)) return null;
        if (s.pinSide(e.index(), 0) != (if (down) library.Side.down else .up) or s.pinSide(e.index(), 2) != (if (down) library.Side.up else .down)) return null;
        drain.* = point.add(a);
    }
    if ((drains[0].x < drains[1].x) != (drains[2].x < drains[3].x) or drains[0].x == drains[1].x or drains[2].x == drains[3].x) return null;
    const result: Rect = .{
        .min = .{ .x = @min(@min(drains[0].x, drains[1].x), @min(drains[2].x, drains[3].x)), .y = @max(drains[0].y, drains[1].y) },
        .max = .{ .x = @max(@max(drains[0].x, drains[1].x), @max(drains[2].x, drains[3].x)), .y = @min(drains[2].y, drains[3].y) },
    };
    return if (result.min.y < result.max.y) result else null;
}

fn proposal(s: *const sch.Schematic, group: Group, len: Lengths, positions: []const [2]f32) ?[2]Pt {
    var at: [6]Pt = undefined;
    for (group, &at) |e, *p| p.* = Pt.round(positions[e.index()]);
    const bounds = rectangle(s, group, at) orelse return null;
    var ends: [2][2]Pt = undefined;
    var controls: [2]Pt = undefined;
    for (group[0..2], 0..) |e, i| {
        const c = s.lib.at(s.devices.items(.class)[e.index()]);
        if (!antiparallel.frame(c)) return null;
        ends[i] = .{ tip(s, e, 0), tip(s, e, 2) };
        controls[i] = tip(s, e, 1);
        if (ends[i][0].y != ends[i][1].y or ends[i][0].x == ends[i][1].x or controls[i].y == ends[i][0].y) return null;
        if (s.pinSide(e.index(), 1) != (if (controls[i].y < ends[i][0].y) library.Side.up else .down)) return null;
    }
    if ((controls[0].y < ends[0][0].y) == (controls[1].y < ends[1][0].y)) return null;
    const left = at[2].add(tip(s, group[2], 0)).x < at[3].add(tip(s, group[3], 0)).x;
    if ((ends[0][0].x < ends[0][1].x) != left or (ends[1][1].x < ends[1][0].x) != left) return null;
    const upper: usize = @intFromBool(controls[0].y > ends[0][0].y);
    const lower = 1 - upper;
    const ub = s.boxAt(group[upper].index(), .zero);
    const lb = s.boxAt(group[lower].index(), .zero);
    const gap = @max(@as(i64, len.stack), @as(i64, ub.max.y) - ends[upper][0].y + ends[lower][0].y - lb.min.y + len.clearance + 1);
    const x = @divFloor(@as(i64, bounds.min.x) + bounds.max.x, 2);
    const y = @divFloor(@as(i64, bounds.min.y) + bounds.max.y - gap, 2);
    var result: [2]Pt = undefined;
    for (0..2) |i| {
        const px = x - @divFloor(@as(i64, ends[i][0].x) + ends[i][1].x, 2);
        const py = y + (if (i == lower) gap else 0) - ends[i][0].y;
        if (px < std.math.minInt(i32) or px > std.math.maxInt(i32) or py < std.math.minInt(i32) or py > std.math.maxInt(i32)) return null;
        result[i] = .{ .x = @intCast(px), .y = @intCast(py) };
        for (ends[i]) |p| {
            const ax, const ay = .{ px + p.x, py + p.y };
            if (ax <= bounds.min.x or ax >= bounds.max.x or ay <= bounds.min.y or ay >= bounds.max.y) return null;
        }
    }
    return result;
}

test {
    _ = @import("clamp_anchors_test.zig");
}

test "clamp anchors: exact complementary channel endpoints and ambiguity boundaries" {
    // Oracle: literal four-anchor cards; form and model visibility cannot
    // hide any additional transistor channel endpoint.
    const gpa = std.testing.allocator;
    const base = ".model nn nmos\n.model pp pmos\n" ++
        "M0 a a b 0 nn\nM1 b b a 0 nn\nM2 a ga high 0 pp\nM3 b gb high 0 pp\n" ++
        "M4 a gc low 0 nn\nM5 b gd low 0 nn\n";
    const extra = [_]struct { []const u8, bool }{
        .{ "", true },                      .{ "M6 c a d b nn\n", true },
        .{ "M6 a g c 0 unknown\n", false }, .{ "M6 c g a 0 nn\n", false },
        .{ "Q6 a g c 0 unknown\n", false }, .{ "J6 a g c unknown\n", false },
    };
    for (extra) |row| {
        const text = try std.mem.concat(gpa, u8, &.{ base, row[0] });
        defer gpa.free(text);
        var nl = try netlist.parse(gpa, &.{text}, null);
        defer nl.deinit(gpa);
        const roles = try sch.guessRoles(gpa, &nl);
        defer gpa.free(roles);
        const group = find(&nl, roles, nl.device("m0").?);
        try std.testing.expectEqual(row[1], group != null);
        if (group) |g| for (g, [_][]const u8{ "m0", "m1", "m2", "m3", "m4", "m5" }) |actual, want| {
            try std.testing.expectEqual(nl.device(want).?, actual);
        };
    }
    for ([_][2][]const u8{
        .{ "M2 a ga high 0 pp", "M2 a ga high 0 nn" },
        .{ "M2 a ga high 0 pp", "M2 high ga a 0 pp" },
        .{ "M3 b gb high 0 pp", "M3 b gb other 0 pp" },
        .{ " low ", " high " },
    }) |change| {
        const text = try std.mem.replaceOwned(u8, gpa, base, change[0], change[1]);
        defer gpa.free(text);
        var nl = try netlist.parse(gpa, &.{text}, null);
        defer nl.deinit(gpa);
        const roles = try sch.guessRoles(gpa, &nl);
        defer gpa.free(roles);
        try std.testing.expect(find(&nl, roles, nl.device("m0").?) == null);
    }
}
