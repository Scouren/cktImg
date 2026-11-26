//! One complete CT/NPN feedback stage -> an actual source-oriented frame.
//!
//! Human Rules:
//! - ct_feedback_stage.1 (bounded observation) AG1149 alone supplies the
//!   nine-member NPN/antiparallel/reciprocal-C/private-L stage in the full
//!   source census. Count complete incidences and raw alternatives before
//!   roles, visibility or frames. Source: docs/research/ct-feedback-stage.md.
//! - ct_feedback_stage.2 (choice) Keep the old actual coil center x. Make
//!   one body-spaced horizontal-tap-up / emitter-down proposal above the
//!   foreign body band. No foreign row, class or routing policy changes.
//!   Eight actual poses per member; unsupported frames or collisions undo
//!   all nine rows. No search, lattice insertion or source distance rule.
//!   The actual base, feedback-inner and bias-control columns progress
//!   inward in that order; the bias body fits before the center track.
//! - ct_feedback_stage.3 (boundary) Admitted member requests and every
//!   touched net's style/port/route/first win, including tap and substrate.
//!   Exact mates and scenes with automatic blocks abstain; the latter
//!   protects unexposed propagated column mates. The source has neither.
//! - ct_feedback_stage.4 (invariant) Actual anchors share real coordinate
//!   tracks. Initially strict lead orders enter the existing one-pass
//!   compactor. Five source wire trees remain independent requirements.
//!
//! Data: borrowed CSR/classes/requests in; cold nine-EdgeId records out,
//! 36 bytes read together once per draw. At most one per complete CT;
//! thirty i32 order pairs per success. Caller-owned two-buffer lifetime
//! ends after drawing; allocations precede mutation. Nine old rows and
//! candidate points are bounded stack scratch. No hot-loop/speed claim.
//! Candidates run in canonical order: earlier commits change the foreign
//! obstacle table, so this placement pass is deliberately sequential.
//!
//! Contents: Group, Batch, Batch.deinit, collect, place, orders; private.

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
const device = @import("device.zig");
const antiparallel = @import("antiparallel.zig");
const actual_anchor = @import("actual_anchor.zig");
const Lengths = @import("canvas.zig").Lengths;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Pt = library.Pt;
const Rect = library.Rect;
const Side = library.Side;

/// CT, two outer-ordered drivers, N2/N1 clamps, two feedback C, two bias L.
pub const Group = [9]EdgeId;

/// Caller-owned cold candidates/successes and bounded coordinate storage.
pub const Batch = struct {
    groups: std.ArrayList(Group),
    coordinates: [][2]i32,

    /// Releases both buffers with the collection allocator.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.groups.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

const missing: EdgeId = .from(sch.none);
comptime {
    assert(@sizeOf(Group) == 36);
}

/// Collects complete unheld stages before weak stays are consumed. All
/// slices span the graph; both allocations finish before geometry writes.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    const c = &nl.graph;
    assert(ats.len == c.edgeCount() and sk.drawn.len == c.edgeCount());
    assert(lines.style.len == c.vertexCount() and st.device_mate.len == c.edgeCount());
    var groups: std.ArrayList(Group) = .empty;
    errdefer groups.deinit(gpa);
    if (st.block_kind.len == 0) {
        var capacity: usize = 0;
        for (c.edges.items(.kind), 0..) |kind, d| if (kind == .subckt and ports(nl, .from(d)) != null) {
            capacity += 1;
        };
        try groups.ensureTotalCapacity(gpa, capacity);
        for (c.edges.items(.kind), 0..) |kind, d| {
            if (kind != .subckt) continue;
            const group = find(nl, s.roles, .from(d)) orelse continue;
            const blocked = blocked: for (group) |edge| {
                const i = edge.index();
                if (!sk.drawn[i] or ats[i] != null or sk.shelf[i] != sk.shelf[d] or st.device_mate[i] != sch.none) break true;
                if (antiparallel.held(nl, sk.verdicts, edge, edge) or antiparallel.held(nl, st.verdicts, edge, edge)) break true;
                if (nl.defOf(edge)) |def| for (def.sides) |side| if (side != null) break :blocked true;
                for (c.members(edge)) |net| {
                    const n = net.index();
                    if (lines.style[n] != .auto or lines.port[n] != null or std.mem.indexOfScalar(u32, lines.first, n) != null) break :blocked true;
                    for (lines.routes) |route| if (route.net == n) break :blocked true;
                }
            } else false;
            if (!blocked) groups.appendAssumeCapacity(group);
        }
    }
    std.sort.heap(Group, groups.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Group, b: Group) bool {
            return rank[a[0].index()] < rank[b[0].index()];
        }
    }.less);
    const coordinates = try gpa.alloc([2]i32, 30 * groups.items.len);
    return .{ .groups = groups, .coordinates = coordinates };
}

/// Attempts one whole-stage frame, retaining successful requests only.
/// No allocation; failure restores all rows and leaves coordinates intact.
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

/// Records twelve x and fifteen y inequalities from current actual tips.
/// Equal row/column anchors already share tracks. Storage is thirty pairs
/// per group; the caller retains it through the single compaction pass.
pub fn orders(s: *const sch.Schematic, nl: *const Netlist, groups: []const Group, storage: [][2]i32) [2][]const [2]i32 {
    const capacity = 15 * groups.len;
    assert(storage.len >= 2 * capacity);
    assert(s.xy.len == s.nodes.len);
    var count: [2]usize = .{ 0, 0 };
    for (groups) |group| {
        var p: [23]Pt = undefined;
        for (&p, 0..) |*point, i| {
            const member, const pin = binding(nl, group, i);
            point.* = Pt.round(s.xy[s.deviceNode(group[member].index()).?]).add(tip(s, group[member], pin));
        }
        // N3 is on the real longitudinal midpoint track.
        for ([_][2]usize{ .{ 3, 0 }, .{ 1, 6 }, .{ 4, 2 }, .{ 2, 7 }, .{ 16, 2 }, .{ 2, 17 }, .{ 20, 2 }, .{ 2, 21 }, .{ 4, 16 }, .{ 16, 19 }, .{ 22, 17 }, .{ 17, 7 } }) |ij| keep(storage[0..capacity], &count[0], p[ij[0]].x, p[ij[1]].x);
        for (9..15) |i| {
            keep(storage[capacity..], &count[1], p[0].y, p[i].y);
            keep(storage[capacity..], &count[1], p[i].y, p[15].y);
        }
        for ([_][2]usize{ .{ 9, 12 }, .{ 15, 3 }, .{ 4, 19 } }) |ij| keep(storage[capacity..], &count[1], p[ij[0]].y, p[ij[1]].y);
    }
    return .{ storage[0..count[0]], storage[capacity..][0..count[1]] };
}

// ---- private ----

fn ports(nl: *const Netlist, edge: EdgeId) ?[3]u2 {
    const def = nl.defOf(edge) orelse return null;
    if (block_symbols.identify(def.name, def.ports) != .center_tap or nl.graph.members(edge).len != 3) return null;
    var out: [3]u2 = undefined;
    for (def.ports, 0..) |name, i| for ([_][]const u8{ "n1", "n2", "n3" }, 0..) |want, j| if (std.ascii.eqlIgnoreCase(name, want)) {
        out[j] = @intCast(i);
    };
    return out;
}

fn sameEnds(p: []const VertexId, a: VertexId, b: VertexId) bool {
    return p.len == 2 and ((p[0] == a and p[1] == b) or (p[1] == a and p[0] == b));
}

fn find(nl: *const Netlist, roles: []const sch.Role, coil: EdgeId) ?Group {
    const c = &nl.graph;
    const cp = ports(nl, coil) orelse return null;
    const p = c.members(coil);
    const outer = [2]VertexId{ p[cp[0]], p[cp[1]] };
    const tap = p[cp[2]];
    if (outer[0] == outer[1] or roles[outer[0].index()].isRail() or roles[outer[1].index()].isRail()) return null;
    var group: Group = @splat(missing);
    group[0] = coil;
    var drivers: [2]u32 = .{ 0, 0 };
    var clamps: [2]u32 = .{ 0, 0 };
    var coils: u32 = 0;
    for (c.edges.items(.kind), 0..) |kind, d| {
        const edge: EdgeId = .from(d);
        const q = c.members(edge);
        if (kind == .subckt) {
            const ps = ports(nl, edge) orelse continue;
            if ((q[ps[0]] == outer[0] and q[ps[1]] == outer[1]) or (q[ps[0]] == outer[1] and q[ps[1]] == outer[0])) coils += 1;
        } else if (device.isTransistor(kind) and q.len >= 3) for (outer, 0..) |net, i| {
            if (q[0] != net) continue;
            if (q[1] != net) {
                drivers[i] += 1;
                group[1 + i] = edge;
            } else if (q[2] == outer[1 - i]) {
                clamps[i] += 1;
                group[4 - i] = edge;
            }
        };
    }
    if (coils != 1 or drivers[0] != 1 or drivers[1] != 1 or clamps[0] != 1 or clamps[1] != 1 or roles[tap.index()] != .supply) return null;
    const body = c.members(group[1]);
    if (body.len != 4 or roles[body[3].index()] != .sink) return null;
    for (group[1..5]) |edge| {
        const q = c.members(edge);
        if (c.edges.items(.kind)[edge.index()] != .bjt or q.len != 4 or q[3] != body[3] or !std.mem.eql(u8, nl.modelType(edge) orelse return null, "npn")) return null;
    }
    const control = [2]VertexId{ body[1], c.members(group[2])[1] };
    var bias: [2]VertexId = undefined;
    for (outer, 0..) |net, i| {
        if (c.incident(net).len != 6 or c.incident(control[i]).len != 3) return null;
        var caps: u32 = 0;
        for (c.edges.items(.kind), 0..) |kind, d| if (kind == .capacitor and sameEnds(c.members(.from(d)), net, control[1 - i])) {
            caps += 1;
            group[5 + i] = .from(d);
        };
        if (caps != 1) return null;
    }
    for (control, 0..) |net, i| {
        var count: u32 = 0;
        for (c.incident(net)) |edge| {
            if (edge == group[1 + i] or edge == group[6 - i]) continue;
            count += 1;
            const q = c.members(edge);
            if (c.edges.items(.kind)[edge.index()] != .inductor or q.len != 2 or q[0] == q[1]) return null;
            group[7 + i] = edge;
            bias[i] = if (q[0] == net) q[1] else q[0];
        }
        if (count != 1) return null;
    }
    if (bias[0] != bias[1] or c.incident(bias[0]).len != 2 or roles[bias[0].index()].isRail()) return null;
    const nets = [_]VertexId{ outer[0], outer[1], control[0], control[1], tap, bias[0], body[2], c.members(group[2])[2] };
    for (nets, 0..) |net, i| {
        if (i != 4 and roles[net.index()].isRail()) return null;
        for (nets[0..i]) |previous| if (net == previous) return null;
    }
    for (group, 0..) |edge, i| for (group[0..i]) |previous| if (edge == previous) return null;
    return group;
}

fn binding(nl: *const Netlist, group: Group, index: usize) struct { usize, usize } {
    assert(index < 23);
    if (index < 3) return .{ 0, ports(nl, group[0]).?[index] };
    if (index < 15) return .{ 1 + (index - 3) / 3, (index - 3) % 3 };
    const member = 5 + (index - 15) / 2;
    const first = (index - 15) % 2 == 0;
    // The named outer/control endpoint is left for N1's passives and
    // right for N2's. Their other endpoint follows the same actual card.
    const net = switch (member) {
        5 => nl.graph.members(group[1])[0],
        6 => nl.graph.members(group[2])[0],
        7 => nl.graph.members(group[1])[1],
        else => nl.graph.members(group[2])[1],
    };
    const outward = if (member == 5 or member == 7) first else !first;
    const pin: usize = @intFromBool(nl.graph.members(group[member])[0] != net);
    return .{ member, if (outward) pin else 1 - pin };
}

fn tip(s: *const sch.Schematic, edge: EdgeId, pin: usize) Pt {
    const row = s.devices.get(edge.index());
    return row.orient.apply(s.lib.at(row.class).terminals[pin].at).sub(row.grid);
}

fn turn(s: *sch.Schematic, nl: *const Netlist, group: Group, member: usize) bool {
    const edge = group[member];
    const class = s.lib.at(s.devices.items(.class)[edge.index()]);
    const count: usize = if (member >= 5) 2 else 3;
    if (class.terminals.len < count) return false;
    for (0..count) |i| if (!class.shows(i) or class.terminals[i].ground_ref) return false;
    for (count..class.terminals.len) |i| if (class.shows(i)) return false;
    const first: usize = if (member == 0) ports(nl, edge).?[0] else if (member < 5) 0 else binding(nl, group, if (member == 5) 15 else if (member == 6) 18 else if (member == 7) 19 else 22)[1];
    const last: usize = if (member == 0) ports(nl, edge).?[1] else if (member < 5) 2 else 1 - first;
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
        s.devices.items(.orientation)[edge.index()] = form;
        s.devices.items(.flip_x)[edge.index()] = flips[0];
        s.devices.items(.flip_y)[edge.index()] = flips[1];
        sch.settleDevice(s, &nl.graph, edge.index());
        const a, const b = .{ tip(s, edge, first), tip(s, edge, last) };
        var anchor = a;
        var side: Side = .left;
        if (member == 1 or member == 2) {
            const base = tip(s, edge, 1);
            if (a.x != b.x or a.y >= base.y or base.y >= b.y or (if (member == 1) base.x <= a.x else base.x >= a.x)) continue;
            if (s.pinSide(edge.index(), 1) != (if (member == 1) Side.right else Side.left)) continue;
            side = .up;
        } else {
            if (a.y != b.y or a.x == b.x) continue;
            side = if (member == 3 or member == 6 or member == 8) .right else .left;
            if ((a.x < b.x) != (side == .left)) continue;
            if (member < 5) {
                if (@mod(@as(i64, a.x) + b.x, 2) != 0) continue;
                anchor = .{ .x = @intCast(@divExact(@as(i64, a.x) + b.x, 2)), .y = a.y };
                const k: usize = if (member == 0) ports(nl, edge).?[2] else 1;
                const base = tip(s, edge, k);
                if (member == 0 and base.x != anchor.x) continue;
                if (member != 0 and (base.x <= @min(a.x, b.x) or base.x >= @max(a.x, b.x))) continue;
                if ((if (member == 4) base.y <= a.y else base.y >= a.y) or s.pinSide(edge.index(), k) != (if (member == 4) Side.down else Side.up)) continue;
            }
        }
        if (s.pinSide(edge.index(), first) != side or s.pinSide(edge.index(), last) != side.opposite()) continue;
        actual_anchor.move(s, nl, edge.index(), anchor);
        if (!actual_anchor.representable(s, nl, edge.index())) continue;
        return true;
    };
    return false;
}

fn attempt(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, group: Group) bool {
    const cp = ports(nl, group[0]).?;
    const old_mid = middle(tip(s, group[0], cp[0]), tip(s, group[0], cp[1])) orelse return false;
    const origin = Pt.round(at[group[0].index()]).add(old_mid);
    var before: [9]sch.DeviceInfo = undefined;
    for (group, &before) |edge, *row| row.* = s.devices.get(edge.index());
    var committed = false;
    defer if (!committed) {
        for (group, before) |edge, row| s.devices.set(edge.index(), row);
    };
    for (0..9) |i| if (!turn(s, nl, group, i)) return false;
    if (tip(s, group[1], 1).y != tip(s, group[2], 1).y or tip(s, group[1], 2).y != tip(s, group[2], 2).y) return false;
    var boxes: [9]Rect = undefined;
    for (group, &boxes) |edge, *box| box.* = s.boxAt(edge.index(), .zero);
    const gap: i64 = @max(len.stack, len.clearance + 1);
    const left_inner = tip(s, group[5], binding(nl, group, 16)[1]).x;
    const right_inner = tip(s, group[6], binding(nl, group, 17)[1]).x;
    if (tip(s, group[1], 1).x >= left_inner or right_inner >= tip(s, group[2], 1).x) return false;
    const left_bias = @as(i64, left_inner) + gap;
    const right_bias = @as(i64, right_inner) - gap;
    var extent = @max(-@as(i64, tip(s, group[0], cp[0]).x), @as(i64, tip(s, group[0], cp[1]).x)) + gap;
    for ([_]usize{ 1, 5 }) |i| extent = @max(extent, @as(i64, boxes[i].max.x) + gap);
    for ([_]usize{ 2, 6 }) |i| extent = @max(extent, -@as(i64, boxes[i].min.x) + gap);
    extent = @max(extent, left_bias + boxes[7].max.x + gap);
    extent = @max(extent, -right_bias - boxes[8].min.x + gap);
    var points: [9][2]i64 = .{ .{ 0, 0 }, .{ -extent, 0 }, .{ extent, 0 }, .{ tip(s, group[0], cp[0]).x, 0 }, .{ tip(s, group[0], cp[1]).x, 0 }, .{ -extent, 0 }, .{ extent, 0 }, .{ -extent + left_bias, 0 }, .{ extent + right_bias, 0 } };
    var bottom: i64 = boxes[0].max.y;
    for ([_][]const usize{ &.{3}, &.{4}, &.{ 5, 6 }, &.{ 1, 2 }, &.{ 7, 8 } }) |band| {
        var upper: i64 = std.math.maxInt(i32);
        var lower: i64 = std.math.minInt(i32);
        for (band) |i| {
            upper = @min(upper, boxes[i].min.y);
            lower = @max(lower, boxes[i].max.y);
        }
        const row = bottom + gap - upper;
        for (band) |i| points[i][1] = row;
        bottom = row + lower;
    }
    var foreign_top: ?i64 = null;
    for (at, sk.drawn, 0..) |xy, visible, d| {
        if (!visible or contains(group, d)) continue;
        const box = foreign(s, ats, @intCast(d), Pt.round(xy));
        foreign_top = if (foreign_top) |old| @min(old, box.min.y) else box.min.y;
    }
    const dy = if (foreign_top) |top| top - gap - bottom else origin.y;
    var proposed: [9]Pt = undefined;
    for (points, &proposed) |point, *out| {
        const x = @as(i64, origin.x) + point[0];
        const y = dy + point[1];
        if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or y < std.math.minInt(i32) or y > std.math.maxInt(i32)) return false;
        out.* = .{ .x = @intCast(x), .y = @intCast(y) };
    }
    for (group, proposed, 0..) |edge, point, i| {
        const candidate = s.boxAt(edge.index(), point).grow(len.clearance);
        for (group[i + 1 ..], proposed[i + 1 ..]) |other, other_point| if (candidate.intersects(s.boxAt(other.index(), other_point))) return false;
        for (at, sk.drawn, 0..) |xy, visible, d| if (visible and !contains(group, d) and candidate.intersects(foreign(s, ats, @intCast(d), Pt.round(xy)))) return false;
    }
    for (group, proposed) |edge, point| at[edge.index()] = point.toF();
    committed = true;
    return true;
}

fn middle(a: Pt, b: Pt) ?Pt {
    const x, const y = .{ @as(i64, a.x) + b.x, @as(i64, a.y) + b.y };
    if (@mod(x, 2) != 0 or @mod(y, 2) != 0) return null;
    return .{ .x = @intCast(@divExact(x, 2)), .y = @intCast(@divExact(y, 2)) };
}
fn contains(group: Group, d: usize) bool {
    for (group) |edge| if (edge.index() == d) return true;
    return false;
}
fn foreign(s: *const sch.Schematic, ats: []const ?pinned.At, d: u32, point: Pt) Rect {
    return if (ats[d]) |fixed| s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin) else s.boxAt(d, point);
}
fn keep(storage: [][2]i32, count: *usize, a: i32, b: i32) void {
    if (a >= b) return;
    assert(count.* < storage.len);
    storage[count.*] = .{ a, b };
    count.* += 1;
}

// ---- tests ----

test {
    _ = @import("ct_feedback_stage_test.zig");
}
