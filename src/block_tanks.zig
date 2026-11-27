//! Actual paired block outputs -> one unique center-tapped tank frame.
//!
//! Human Rules:
//! - block_tanks.1 (habit, bounded) One actual AG1103 rectangle has unique
//!   OUTP/OUTN bindings across a unique CT/cap pair, with capacitor-only
//!   outer fanout. Its actual output/cap/coil midpoints align; the capacitor
//!   lies between the outputs and coil, named ends match, tap faces away.
//!   Count all competitors before visibility/role/frame filtering. This
//!   single source case is not a universal block-load rule. `find`
//! - block_tanks.2 (choice) Preserve the block frame and cell. Reanchor both passive
//!   midpoints to its actual output midpoint and try a body-spaced position,
//!   then quarter-unit steps through one extra unit. Caller geometry,
//!   sides, mates, groups, shelves and styles/ports/routes win. Failure restores
//!   both complete device rows and all coordinates. A first-net request
//!   still owns routing order; it does not prohibit placement. `collect`, `place`
//! - block_tanks.3 (invariant) Only a successful specific owner removes
//!   its pair from generic coil_tanks. Equal transverse grid tracks retain
//!   midpoint equality, including shifted class frames; strict actual
//!   output/cap/coil/tap orders enter the existing compactor. `orders`
//! - block_tanks.4 (choice) A fresh lattice reserves the actual nearest
//!   composite envelope at the anchor cell before ordinary column spacing.
//!   Whole-scene preflight uses all future passive boxes. A rejection
//!   restores ordinary coordinates; fixed/relay/direct placement bypasses
//!   reservation. No extra slots or farther search are introduced. `lattice`
//!
//! Data: CSR, declared binds, actual classes and admitted requests in;
//! cold 20-byte group records and two passive poses out. Each record is
//! read together once per draw; u32 typed handles and u8 block pins match
//! existing table bounds. At most one group per subckt; six i32 order pairs
//! per group, plus one 20-byte numeric room request. Caller owns all three
//! buffers, allocated before mutation. Two old rows/coordinates live on
//! the stack. No retained state or speed claim.
//!
//! Contents: Group, Batch, Batch.deinit, collect, lattice, rooms, propose, fits, commit,
//! place, orders; private proofs/tests.

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
const coil_tanks = @import("coil_tanks.zig");
const actual_lead = @import("actual_lead.zig");
const actual_anchor = @import("actual_anchor.zig");
const antiparallel = @import("antiparallel.zig");
const Lengths = @import("canvas.zig").Lengths;
const geometry = @import("lattice_geometry.zig");
const Room = geometry.Room;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Pt = library.Pt;
const Side = library.Side;

/// Unique passive pair, read-only block, and block pins bound to N1/N2.
pub const Group = struct { pair: coil_tanks.Pair, block: EdgeId, pins: [2]u8 };

/// Cold candidates/successes and immediate compaction-order storage.
pub const Batch = struct {
    groups: std.ArrayList(Group),
    coordinates: [][2]i32,
    room: []Room,

    /// Releases all three buffers with the collection allocator.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.groups.deinit(gpa);
        gpa.free(self.coordinates);
        gpa.free(self.room);
        self.* = undefined;
    }
};

const Proposal = struct { side: Side, points: [2]Pt };

comptime {
    assert(@sizeOf(Group) == 20);
}

/// Collects complete unheld groups before relay consumes weak stays.
/// Input slices span the graph; all allocations precede geometry writes.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    const c = &nl.graph;
    assert(ats.len == c.edgeCount() and sk.drawn.len == c.edgeCount());
    assert(lines.style.len == c.vertexCount() and st.device_mate.len == c.edgeCount());
    var capacity: usize = 0;
    for (c.edges.items(.kind)) |kind| capacity += @intFromBool(kind == .subckt);
    var groups: std.ArrayList(Group) = .empty;
    errdefer groups.deinit(gpa);
    try groups.ensureTotalCapacity(gpa, capacity);
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt) continue;
        const group = find(nl, s.roles, EdgeId.from(d)) orelse continue;
        const members = [_]EdgeId{ group.block, group.pair.coil, group.pair.cap };
        const blocked = blocked: for (members) |edge| {
            const i = edge.index();
            if (!sk.drawn[i] or ats[i] != null or sk.shelf[i] != sk.shelf[d] or st.device_mate[i] != sch.none) break true;
            if (antiparallel.held(nl, sk.verdicts, edge, edge) or antiparallel.held(nl, st.verdicts, edge, edge)) break true;
            for (st.block_devices) |owned| if (owned == i) break :blocked true;
            if (nl.defOf(edge)) |def| for (def.sides) |side| if (side != null) break :blocked true;
        } else false;
        if (blocked) continue;
        const styled = styled: for (c.members(group.pair.coil)) |net| {
            if (lines.style[net.index()] != .auto or lines.port[net.index()] != null) break true;
            for (lines.routes) |route| if (route.net == net.index()) break :styled true;
        } else false;
        if (!styled) groups.appendAssumeCapacity(group);
    }
    std.sort.heap(Group, groups.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Group, b: Group) bool {
            return rank[a.pair.coil.index()] < rank[b.pair.coil.index()];
        }
    }.less);
    const coordinates = try gpa.alloc([2]i32, 6 * groups.items.len);
    errdefer gpa.free(coordinates);
    const room = try gpa.alloc(Room, groups.items.len);
    return .{ .groups = groups, .coordinates = coordinates, .room = room };
}

/// Fresh-lattice transaction; caller excludes direct placement and every
/// admitted fixed/relay coordinate. Allocates both possible coordinate
/// results before writing at or poses. A rejected whole proposal returns
/// the ordinary coordinates, unchanged rows/fallback, and false. No room
/// request survives that rejection; true consumes all selected pairs.
pub fn lattice(gpa: Allocator, s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, len: Lengths, at: [][2]f32, batch: *Batch, fallback: *std.ArrayList(coil_tanks.Pair)) Allocator.Error!bool {
    assert(at.len == s.devices.len and sk.drawn.len == at.len);
    assert(batch.room.len >= batch.groups.items.len);
    const room = rooms(s, nl, len, &batch.groups, batch.room);
    const ordinary = try geometry.coordinates(gpa, s, nl, sk, len, &.{});
    defer gpa.free(ordinary.xs);
    defer gpa.free(ordinary.ys);
    if (room.len > 0) {
        const reserved = try geometry.coordinates(gpa, s, nl, sk, len, room);
        defer gpa.free(reserved.xs);
        defer gpa.free(reserved.ys);
        fill(at, sk, reserved);
        if (fits(s, nl, sk, len, at, batch.groups.items)) {
            commit(s, nl, len, at, batch.groups.items, fallback);
            return true;
        }
        batch.groups.items.len = 0;
    }
    fill(at, sk, ordinary);
    return false;
}

/// Prepares one nearest actual composite envelope per supported group.
/// Restores every temporary pose. Only a fresh lattice with no admitted
/// fixed coordinates or relay stays may consume these immediate requests.
pub fn rooms(s: *sch.Schematic, nl: *const Netlist, len: Lengths, groups: *std.ArrayList(Group), storage: []Room) []const Room {
    assert(storage.len >= groups.items.len);
    assert(s.devices.len == nl.graph.edgeCount());
    var kept: usize = 0;
    for (groups.items) |group| {
        const old = save(s, group);
        defer restore(s, group, old);
        const proposal = prepare(s, nl, len, group) orelse continue;
        const bounds = s.boxAt(group.pair.coil.index(), proposal.points[0]).merge(s.boxAt(group.pair.cap.index(), proposal.points[1])).grow(len.clearance);
        storage[kept] = .{ .anchor = group.block, .bounds = bounds };
        groups.items[kept] = group;
        kept += 1;
    }
    groups.items = groups.items[0..kept];
    return storage[0..kept];
}

/// Settles the two passive rows and returns their nearest positions relative
/// to the unchanged block grid. The shared room coordinator owns restoration
/// on null or collision and checks the complete future scene before commit.
pub fn propose(s: *sch.Schematic, nl: *const Netlist, len: Lengths, group: Group) ?[2]Pt {
    assert(s.devices.len == nl.graph.edgeCount());
    assert(group.block.index() < s.devices.len);
    return (prepare(s, nl, len, group) orelse return null).points;
}

/// Checks the complete proposed scene, including candidate pairs instead
/// of their stale passive positions. All temporary poses are restored.
/// A false result requires ordinary lattice coordinates before local work.
pub fn fits(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, len: Lengths, at: []const [2]f32, groups: []const Group) bool {
    assert(at.len == s.devices.len and sk.drawn.len == at.len);
    assert(groups.len <= at.len);
    for (groups, 0..) |group, i| {
        const old = save(s, group);
        defer restore(s, group, old);
        const proposal = prepare(s, nl, len, group) orelse return false;
        const points = located(proposal, Pt.round(at[group.block.index()]));
        const owned = [_]EdgeId{ group.pair.coil, group.pair.cap };
        if (s.boxAt(owned[0].index(), points[0]).grow(len.clearance).intersects(s.boxAt(owned[1].index(), points[1]))) return false;
        for (owned, points) |edge, point| {
            const box = s.boxAt(edge.index(), point).grow(len.clearance);
            for (at, sk.drawn, 0..) |xy, visible, d| {
                if (!visible or ownedBy(groups, d)) continue;
                if (box.intersects(s.boxAt(@intCast(d), Pt.round(xy)))) return false;
            }
            for (groups[i + 1 ..]) |other| {
                const previous = save(s, other);
                defer restore(s, other, previous);
                const candidate = prepare(s, nl, len, other) orelse return false;
                const next = located(candidate, Pt.round(at[other.block.index()]));
                if (box.intersects(s.boxAt(other.pair.coil.index(), next[0])) or box.intersects(s.boxAt(other.pair.cap.index(), next[1]))) return false;
            }
        }
    }
    return true;
}

/// Commits a fresh scene already accepted by fits without intervening
/// geometry writes. No allocation or further failure occurs. All selected
/// pairs leave the generic tank batch only after their complete preflight.
pub fn commit(s: *sch.Schematic, nl: *const Netlist, len: Lengths, at: [][2]f32, groups: []const Group, fallback: *std.ArrayList(coil_tanks.Pair)) void {
    assert(at.len == s.devices.len);
    assert(groups.len <= at.len);
    for (groups) |group| {
        const proposal = prepare(s, nl, len, group) orelse unreachable;
        const points = located(proposal, Pt.round(at[group.block.index()]));
        at[group.pair.coil.index()] = points[0].toF();
        at[group.pair.cap.index()] = points[1].toF();
    }
    consume(groups, fallback);
}

/// Tries the two-row transaction, retaining successes only. A success
/// consumes its generic tank request; a failure leaves that fallback intact.
/// Coordinates and full device rows commit only after whole-scene clearance.
pub fn place(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, groups: *std.ArrayList(Group), fallback: *std.ArrayList(coil_tanks.Pair)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (groups.items) |group| {
        if (!attempt(s, nl, sk, ats, len, at, group)) continue;
        groups.items[kept] = group;
        kept += 1;
    }
    groups.items = groups.items[0..kept];
    consume(groups.items, fallback);
}

/// Supplies the three initially strict outward actual-coordinate orders.
/// Equal grid tracks preserve transverse midpoint equality. Storage has six
/// pairs per success, split equally between x/y, and remains caller-owned.
pub fn orders(s: *const sch.Schematic, groups: []const Group, storage: [][2]i32) [2][]const [2]i32 {
    assert(storage.len >= 6 * groups.len);
    assert(s.xy.len == s.nodes.len);
    const capacity = 3 * groups.len;
    var counts: [2]usize = .{ 0, 0 };
    for (groups) |group| {
        const side = actual_lead.leadSide(s, group.block.index(), group.pins[0]) orelse continue;
        const axis: usize = @intFromBool(!side.isHorizontal());
        const points = [_]Pt{
            current(s, group.block, group.pins[0]),          current(s, group.pair.cap, group.pair.first),
            current(s, group.pair.coil, group.pair.pins[0]), current(s, group.pair.coil, group.pair.pins[2]),
        };
        for (points[0..3], points[1..]) |a, b| {
            assert(project(a, side) < project(b, side));
            const from, const to = if (axis == 0) .{ a.x, b.x } else .{ a.y, b.y };
            storage[axis * capacity + counts[axis]] = .{ @min(from, to), @max(from, to) };
            counts[axis] += 1;
        }
    }
    return .{ storage[0..counts[0]], storage[capacity..][0..counts[1]] };
}

// ---- private ----

fn fill(at: [][2]f32, sk: *const skeleton.Skeleton, geo: geometry.Geo) void {
    for (at, sk.drawn, 0..) |*p, visible, d| if (visible) {
        p.* = .{ @floatFromInt(geo.xs[@intCast(sk.x[d])]), @floatFromInt(geo.ys[@intCast(sk.y[d])]) };
    };
}

fn consume(groups: []const Group, fallback: *std.ArrayList(coil_tanks.Pair)) void {
    var kept: usize = 0;
    for (fallback.items) |pair| {
        const consumed = for (groups) |group| {
            if (group.pair.coil == pair.coil) break true;
        } else false;
        if (consumed) continue;
        fallback.items[kept] = pair;
        kept += 1;
    }
    fallback.items = fallback.items[0..kept];
}

fn save(s: *const sch.Schematic, group: Group) [2]sch.DeviceInfo {
    return .{ s.devices.get(group.pair.coil.index()), s.devices.get(group.pair.cap.index()) };
}

fn restore(s: *sch.Schematic, group: Group, previous: [2]sch.DeviceInfo) void {
    s.devices.set(group.pair.coil.index(), previous[0]);
    s.devices.set(group.pair.cap.index(), previous[1]);
}

fn located(proposal: Proposal, origin: Pt) [2]Pt {
    return .{ origin.add(proposal.points[0]), origin.add(proposal.points[1]) };
}

fn ownedBy(groups: []const Group, d: usize) bool {
    for (groups) |group| if (group.pair.coil.index() == d or group.pair.cap.index() == d) return true;
    return false;
}

fn find(nl: *const Netlist, roles: []const sch.Role, coil: EdgeId) ?Group {
    const c = &nl.graph;
    const pair = coil_tanks.find(nl, coil) orelse return null;
    const p = c.members(coil);
    const ends = [_]netlist.VertexId{ p[pair.pins[0]], p[pair.pins[1]] };
    for (ends) |net| if (roles[net.index()].isRail()) return null;
    var block: ?EdgeId = null;
    var previous: ?EdgeId = null;
    for (c.incident(ends[0])) |edge| {
        if (previous == edge) continue;
        previous = edge;
        if (edge == coil or c.edges.items(.kind)[edge.index()] != .subckt) continue;
        if (std.mem.indexOfScalar(netlist.VertexId, c.members(edge), ends[1]) == null) continue;
        if (block != null) return null;
        block = edge;
    }
    const selected = block orelse return null;
    const def = nl.defOf(selected) orelse return null;
    var named: [2]?u8 = .{ null, null };
    for (def.ports, 0..) |name, i| for ([_][]const u8{ "outp", "outn" }, 0..) |want, j| {
        if (!std.ascii.eqlIgnoreCase(name, want)) continue;
        if (named[j] != null or i > std.math.maxInt(u8)) return null;
        named[j] = @intCast(i);
    };
    if (named[0] == null or named[1] == null) return null;
    var bound: [2]u8 = undefined;
    for (ends, &bound) |net, *pin| {
        var index: ?u8 = null;
        for (c.members(selected), 0..) |member, i| if (member == net) {
            if (index != null or i > std.math.maxInt(u8)) return null;
            index = @intCast(i);
        };
        pin.* = index orelse return null;
        if (pin.* != named[0].? and pin.* != named[1].?) return null;
        for (c.incident(net)) |edge| {
            if (edge != coil and edge != selected and c.edges.items(.kind)[edge.index()] != .capacitor) return null;
        }
    }
    return .{ .pair = pair, .block = selected, .pins = bound };
}

fn prepare(s: *sch.Schematic, nl: *const Netlist, len: Lengths, group: Group) ?Proposal {
    const block = group.block.index();
    const side = actual_lead.leadSide(s, block, group.pins[0]) orelse return null;
    if (actual_lead.leadSide(s, block, group.pins[1]) != side) return null;
    const a, const b = .{ tip(s, group.block, group.pins[0]), tip(s, group.block, group.pins[1]) };
    if (project(a, side) != project(b, side) or a.eql(b)) return null;
    const span = Side.of(b.sub(a)) orelse return null;
    if (!span.perpendicular(side)) return null;
    const midpoint = middle(a, b) orelse return null;
    const offset = if (side.isHorizontal()) Pt{ .x = 0, .y = midpoint.y } else Pt{ .x = midpoint.x, .y = 0 };
    if (!turn(s, nl, group.pair.coil, group.pair.pins[0..2].*, group.pair.pins[2], side, span, offset)) return null;
    if (!turn(s, nl, group.pair.cap, .{ group.pair.first, 1 - group.pair.first }, null, side, span, offset)) return null;
    const cb = s.boxAt(group.pair.cap.index(), .zero);
    const wb = s.boxAt(group.pair.coil.index(), .zero);
    const gap = @max(len.stack, len.clearance + 1);
    const cap_offset = project(a, side) + gap - @min(project(cb.min, side), project(cb.max, side));
    const coil_offset = cap_offset + @max(project(cb.min, side), project(cb.max, side)) + gap - @min(project(wb.min, side), project(wb.max, side));
    const v = side.unit();
    return .{ .side = side, .points = .{
        .{ .x = v.x * coil_offset, .y = v.y * coil_offset },
        .{ .x = v.x * cap_offset, .y = v.y * cap_offset },
    } };
}

fn attempt(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, group: Group) bool {
    const before = save(s, group);
    var committed = false;
    defer if (!committed) restore(s, group, before);
    const proposal = prepare(s, nl, len, group) orelse return false;
    const owned = [_]EdgeId{ group.pair.coil, group.pair.cap };
    const step = @max(1, @divTrunc(len.unit, 4));
    const attempts: usize = @intCast(@divFloor(len.unit, step) + 1);
    assert(attempts <= 8);
    const origin = Pt.round(at[group.block.index()]);
    const v = proposal.side.unit();
    for (0..attempts) |i| {
        const extra = @as(i32, @intCast(i)) * step;
        const points = located(proposal, origin.add(.{ .x = v.x * extra, .y = v.y * extra }));
        const blocked = blocked: for (owned, points) |edge, point| {
            const candidate = s.boxAt(edge.index(), point).grow(len.clearance);
            for (at, sk.drawn, 0..) |xy, visible, d| {
                if (!visible or d == owned[0].index() or d == owned[1].index()) continue;
                const box = if (ats[d]) |fixed| s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin) else s.boxAt(d, Pt.round(xy));
                if (candidate.intersects(box)) break :blocked true;
            }
        } else false;
        if (blocked or s.boxAt(owned[0].index(), points[0]).grow(len.clearance).intersects(s.boxAt(owned[1].index(), points[1]))) continue;
        for (owned, points) |edge, point| at[edge.index()] = point.toF();
        committed = true;
        return true;
    }
    return false;
}

fn turn(s: *sch.Schematic, nl: *const Netlist, d: EdgeId, ends: [2]u2, tap: ?u2, outward: Side, span: Side, offset: Pt) bool {
    const c = s.lib.at(s.devices.items(.class)[d.index()]);
    if (c.terminals.len != (if (tap != null) @as(usize, 3) else 2)) return false;
    for (c.terminals) |t| if (t.hidden or t.ground_ref) return false;
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
        s.devices.items(.orientation)[d.index()] = form;
        s.devices.items(.flip_x)[d.index()] = flips[0];
        s.devices.items(.flip_y)[d.index()] = flips[1];
        sch.settleDevice(s, &nl.graph, d.index());
        const a, const b = .{ tip(s, d, ends[0]), tip(s, d, ends[1]) };
        if (project(a, outward) != project(b, outward) or Side.of(b.sub(a)) != span) continue;
        if (s.pinSide(d.index(), ends[0]) != span.opposite() or s.pinSide(d.index(), ends[1]) != span) continue;
        const midpoint = middle(a, b) orelse continue;
        if (tap) |pin| {
            const delta = tip(s, d, pin).sub(midpoint);
            if ((delta.x != 0 and delta.y != 0) or Side.of(delta) != outward or s.pinSide(d.index(), pin) != outward) continue;
        }
        actual_anchor.move(s, nl, d.index(), midpoint.sub(offset));
        return actual_anchor.representable(s, nl, d.index());
    };
    return false;
}

fn middle(a: Pt, b: Pt) ?Pt {
    const x, const y = .{ @as(i64, a.x) + b.x, @as(i64, a.y) + b.y };
    if (@mod(x, 2) != 0 or @mod(y, 2) != 0) return null;
    return .{ .x = @intCast(@divExact(x, 2)), .y = @intCast(@divExact(y, 2)) };
}

fn tip(s: *const sch.Schematic, d: EdgeId, pin: usize) Pt {
    const row = s.devices.get(d.index());
    return row.orient.apply(s.lib.at(row.class).terminals[pin].at).sub(row.grid);
}

fn current(s: *const sch.Schematic, d: EdgeId, pin: usize) Pt {
    return Pt.round(s.xy[s.deviceNode(d.index()).?]).add(tip(s, d, pin));
}

fn project(p: Pt, side: Side) i32 {
    const v = side.unit();
    return p.x * v.x + p.y * v.y;
}

test "block tanks topology: complete incidence before roles or visibility excludes ambiguity" {
    const testing = std.testing;
    const header = "Block tank topology\n.subckt ct_inductor n1 n2 n3\nL1 n1 n3 1n\nL2 n3 n2 1n\n.ends\n" ++
        ".subckt stage inp outp outn\n.ends\n.subckt opaque a b\n.ends\n";
    const body = "XL a b bias ct_inductor\nC1 a b 1p\nX1 input a b stage\nC2 a other 1p\nRref reference 0 1k\n";
    const mutations = [_][]const u8{
        "",                "C3 b a 1p\n",     "XX b a bias ct_inductor\n",          "X2 other a b stage\n",
        "X2 a b opaque\n", "R1 a other 1k\n", "Q1 a b other 0 qn\n.model qn npn\n",
    };
    for (mutations, 0..) |addition, i| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.mem.concat(a, u8, &.{ header, body, addition });
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        for ([_][]const u8{ "a", "b" }) |name| try testing.expectEqual(sch.Role.internal, roles[nl.net(name).?.index()]);
        const result = find(&nl, roles, nl.device("xl").?);
        try testing.expectEqual(i == 0, result != null);
        if (result) |group| {
            try testing.expectEqual(nl.device("x1").?, group.block);
            try testing.expectEqualDeep([2]u8{ 1, 2 }, group.pins);
        }
    }
    for ([_][]const u8{
        "XL a b a ct_inductor\nC1 a b 1p\nX1 input a b stage\n",
        "XL a b bias ct_inductor\nC1 a b 1p\nX1 a a b stage\n",
        "XL a b bias ct_inductor\nC1 a b 1p\nX1 a input b stage\n",
    }) |wrong| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.mem.concat(a, u8, &.{ header, wrong, "Rref reference 0 1k\n" });
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        try testing.expect(find(&nl, roles, nl.device("xl").?) == null);
    }
}

test {
    _ = @import("block_tanks_test.zig");
}
