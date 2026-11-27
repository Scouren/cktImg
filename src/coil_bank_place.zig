//! Actual frames and atomic placement of the two linked CT banks.
//!
//! Human Rules:
//! - coil_bank_place.1 (habit, bounded) The two winding axes and capacitor
//!   share an actual midpoint; capacitor and ground-return NMOS devices
//!   lie successively outside the winding columns, opposite the taps.
//!   Drains bracket the winding ends, gates point inward and sources out.
//!   AG1180's two banks share exact reflection. `turn`, `proposal`
//! - coil_bank_place.2 (choice) Keep the existing actual reflection axis
//!   and bank side. Try one compact paired frame at the old winding row,
//!   outside the occupied central devices. This single declared candidate
//!   has body-derived spacing, not measured source distances. A collision
//!   or unsupported actual frame restores all ten device rows; coordinates
//!   commit only after all checks. Caller-owned classes never change.
//!   `place`, `attempt`
//! - coil_bank_place.3 (invariant) Anchor winding/cap coordinates at their
//!   actual midpoint and MOS coordinates at the actual drain. Equality
//!   then shares a compaction track. Preserve initially strict terminal
//!   inequalities and the verified actual reflection axis through the
//!   existing generic compactor. `orders`, `axis`
//!
//! Data: cold 56-byte certificates and settled device rows in; ten poses
//! and bounded coordinate orders out. Stack scratch holds ten old rows and
//! ten candidate points. No allocation or retained state during placement;
//! every fallible collection precedes this transaction. One candidate per
//! owner, eight orientations per member; this is not a routing hot loop.
//!
//! Contents:
//! - `pub fn place(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pairs: *std.ArrayList(Pair)) void`
//! - `pub fn orders(s: *const sch.Schematic, pairs: []const Pair, storage: [][2]i32) [2][]const [2]i32`
//! - `pub fn axis(s: *const sch.Schematic, pairs: []const Pair) ?i32`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const banks = @import("coil_banks.zig");
const actual_anchor = @import("actual_anchor.zig");
const Lengths = @import("canvas.zig").Lengths;
const Pair = banks.Pair;
const Bank = banks.Bank;
const Pt = library.Pt;
const Rect = library.Rect;
const Side = library.Side;

/// Places only complete successful owners, compacting the borrowed list.
/// All input slices span existing devices. A failed owner changes neither
/// its coordinates nor any device row; no allocation occurs here.
pub fn place(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pairs: *std.ArrayList(Pair)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (pairs.items) |pair| {
        const a = Pt.round(at[pair[0].devices[0].index()]);
        const b = Pt.round(at[pair[1].devices[0].index()]);
        const sum = @as(i64, a.x) + b.x;
        if (sum < std.math.minInt(i32) or sum > std.math.maxInt(i32) or a.x == b.x) continue;
        const axis2: i32 = @intCast(sum);
        var core = Rect.fromCorners(.{ .x = @divFloor(axis2, 2), .y = a.y }, .{ .x = @divFloor(axis2, 2), .y = a.y });
        for (at, sk.drawn, 0..) |xy, visible, d| {
            if (!visible or contains(pair, d)) continue;
            core = core.merge(box(s, ats, @intCast(d), Pt.round(xy)));
        }
        if (!attempt(s, nl, sk, ats, len, at, pair, core, axis2, a.y, a.x < b.x)) continue;
        pairs.items[kept] = pair;
        kept += 1;
    }
    pairs.items = pairs.items[0..kept];
}

/// Appends initially strict actual-coordinate inequalities. The caller
/// supplies at least forty slots per owner, twenty for each axis. Shared
/// midpoint/drain-column equalities already use identical device tracks.
pub fn orders(s: *const sch.Schematic, pairs: []const Pair, storage: [][2]i32) [2][]const [2]i32 {
    assert(storage.len >= 40 * pairs.len);
    assert(s.xy.len == s.nodes.len);
    const capacity = 20 * pairs.len;
    var counts: [2]usize = .{ 0, 0 };
    for (pairs) |pair| for (pair) |bank| {
        var p: [14]Pt = undefined;
        points(s, bank, &p);
        for ([_][2]usize{ .{ 8, 6 }, .{ 6, 0 }, .{ 6, 3 }, .{ 0, 3 } }) |ij| {
            keep(storage[0..capacity], &counts[0], p[ij[0]].x, p[ij[1]].x);
        }
        for ([_][2]usize{ .{ 8, 0 }, .{ 8, 3 }, .{ 1, 11 }, .{ 4, 11 }, .{ 9, 12 } }) |ij| {
            keep(storage[capacity..], &counts[1], p[ij[0]].y, p[ij[1]].y);
        }
    };
    return .{ storage[0..counts[0]], storage[capacity..][0..counts[1]] };
}

/// Returns the actual common axis only when every paired semantic lead
/// still has exact reflected x and equal y. Uses the current scaffold;
/// absent owners return null so ordinary axis discovery remains unchanged.
pub fn axis(s: *const sch.Schematic, pairs: []const Pair) ?i32 {
    assert(s.xy.len == s.nodes.len);
    var result: ?i32 = null;
    for (pairs) |pair| {
        var a: [14]Pt = undefined;
        var b: [14]Pt = undefined;
        points(s, pair[0], &a);
        points(s, pair[1], &b);
        for (a, b) |x, y| {
            const sum = @as(i64, x.x) + y.x;
            if (sum < std.math.minInt(i32) or sum > std.math.maxInt(i32) or x.y != y.y) return null;
            if (result) |old| {
                if (old != sum) return null;
            } else result = @intCast(sum);
        }
    }
    return result;
}

// ---- private ----

fn attempt(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pair: Pair, core: Rect, axis2: i32, row: i32, first_left: bool) bool {
    var before: [10]sch.DeviceInfo = undefined;
    for (pair, 0..) |bank, bi| for (bank.devices, 0..) |d, i| {
        before[bi * 5 + i] = s.devices.get(d.index());
    };
    var committed = false;
    defer if (!committed) {
        for (pair, 0..) |bank, bi| for (bank.devices, 0..) |d, i| {
            s.devices.set(d.index(), before[bi * 5 + i]);
        };
    };
    for (pair, 0..) |bank, bi| {
        const left = (bi == 0) == first_left;
        for (0..bank.devices.len) |i| if (!turn(s, nl, bank, @intCast(i), left)) return false;
    }
    // Corresponding actual frames must reflect, not merely their origins.
    for (pair[0].devices, pair[1].devices, 0..) |a, b, i| {
        const count: usize = if (i == 2) 2 else 3;
        for (0..count) |j| {
            const pa = tip(s, a.index(), pin(pair[0], i, j));
            const pb = tip(s, b.index(), pin(pair[1], i, j));
            if (@as(i64, pa.x) + pb.x != 0 or pa.y != pb.y) return false;
        }
    }
    var proposed: [10]Pt = undefined;
    if (!proposal(s, pair, core, axis2, row, first_left, len, &proposed)) return false;
    for (pair, 0..) |bank, bi| for (bank.devices, 0..) |d, i| {
        const index = bi * 5 + i;
        const candidate = s.boxAt(d.index(), proposed[index]).grow(len.clearance);
        for (at, sk.drawn, 0..) |xy, visible, other| {
            if (!visible or contains(pair, other)) continue;
            if (candidate.intersects(box(s, ats, @intCast(other), Pt.round(xy)))) return false;
        }
        for (pair, 0..) |other_bank, bj| for (other_bank.devices, 0..) |other, j| {
            if (bj * 5 + j <= index) continue;
            if (candidate.intersects(s.boxAt(other.index(), proposed[bj * 5 + j]))) return false;
        };
    };
    for (pair, 0..) |bank, bi| for (bank.devices, 0..) |d, i| {
        at[d.index()] = proposed[bi * 5 + i].toF();
    };
    committed = true;
    return true;
}

fn proposal(s: *const sch.Schematic, pair: Pair, core: Rect, axis2: i32, row: i32, first_left: bool, len: Lengths, out: *[10]Pt) bool {
    const left: usize = @intFromBool(!first_left);
    const bank = pair[left];
    const gap = @max(len.stack, len.clearance + 1);
    var bounds: [5]Rect = undefined;
    for (bank.devices, &bounds) |d, *r| r.* = s.boxAt(d.index(), .zero);
    var xs: [5]i64 = .{ 0, 0, 0, 0, 0 };
    xs[1] = @as(i64, bounds[0].min.x) - bounds[1].max.x - gap;
    xs[2] = xs[1] + bounds[1].min.x - bounds[2].max.x - gap;
    xs[3] = xs[2] + bounds[2].min.x - @max(bounds[3].max.x, bounds[4].max.x) - gap;
    xs[4] = xs[3];
    var extent: i64 = gap;
    for (bounds[0..3]) |r| extent = @max(extent, @max(@as(i64, @intCast(@abs(r.min.y))), @as(i64, @intCast(@abs(r.max.y)))) + gap);
    // Keep both inward gates strictly between the drain rows.
    extent = @max(extent, @as(i64, @intCast(@abs(tip(s, bank.devices[3].index(), 1).y))) + gap);
    extent = @max(extent, @as(i64, @intCast(@abs(tip(s, bank.devices[4].index(), 1).y))) + gap);
    const x = @min(@as(i64, core.min.x), @as(i64, axis2) - core.max.x) - gap - bounds[0].max.x;
    for (xs, 0..) |dx, i| {
        const px = x + dx;
        const py = @as(i64, row) + (if (i == 3) -extent else if (i == 4) extent else 0);
        const mirror = @as(i64, axis2) - px;
        for ([_]i64{ px, py, mirror }) |v| if (v < std.math.minInt(i32) or v > std.math.maxInt(i32)) return false;
        out[left * 5 + i] = .{ .x = @intCast(px), .y = @intCast(py) };
        out[(1 - left) * 5 + i] = .{ .x = @intCast(mirror), .y = @intCast(py) };
    }
    return true;
}

fn turn(s: *sch.Schematic, nl: *const netlist.Netlist, bank: Bank, i: u3, left: bool) bool {
    const d = bank.devices[i].index();
    const c = s.lib.at(s.devices.items(.class)[d]);
    const count: usize = if (i == 2) 2 else 3;
    if (c.terminals.len < count) return false;
    for (0..count) |j| if (!c.shows(pin(bank, i, j))) return false;
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
        s.devices.items(.orientation)[d] = form;
        s.devices.items(.flip_x)[d] = flips[0];
        s.devices.items(.flip_y)[d] = flips[1];
        sch.settleDevice(s, &nl.graph, d);
        const a = tip(s, d, pin(bank, i, 0));
        const b = tip(s, d, pin(bank, i, 1));
        var anchor: Pt = undefined;
        if (i < 3) {
            if (a.x != b.x or a.y >= b.y or @mod(@as(i64, a.y) + b.y, 2) != 0) continue;
            if (s.pinSide(d, pin(bank, i, 0)) != .up or s.pinSide(d, pin(bank, i, 1)) != .down) continue;
            anchor = .{ .x = a.x, .y = @intCast(@divTrunc(@as(i64, a.y) + b.y, 2)) };
            if (i < 2) {
                const t = tip(s, d, pin(bank, i, 2));
                if (t.y != anchor.y or (if (left) t.x <= anchor.x else t.x >= anchor.x)) continue;
                if (s.pinSide(d, pin(bank, i, 2)) != (if (left) Side.right else Side.left)) continue;
            }
        } else {
            const source = tip(s, d, 2);
            if (a.y != source.y or (if (left) a.x <= source.x else a.x >= source.x)) continue;
            if (b.x <= @min(a.x, source.x) or b.x >= @max(a.x, source.x)) continue;
            if (if (i == 3) b.y <= a.y else b.y >= a.y) continue;
            if (s.pinSide(d, 0) != (if (left) Side.right else Side.left) or s.pinSide(d, 2) != (if (left) Side.left else Side.right)) continue;
            if (s.pinSide(d, 1) != (if (i == 3) Side.down else Side.up)) continue;
            anchor = a;
        }
        actual_anchor.move(s, nl, d, anchor);
        return true;
    };
    return false;
}

fn pin(bank: Bank, member: usize, p: usize) usize {
    return if (member < 2) bank.pins[member][p] else if (member == 2) (if (p == 0) bank.first else 1 - bank.first) else p;
}

fn tip(s: *const sch.Schematic, d: u32, p: usize) Pt {
    const info = s.devices.get(d);
    return info.orient.apply(s.lib.at(info.class).terminals[p].at).sub(info.grid);
}

fn points(s: *const sch.Schematic, bank: Bank, out: *[14]Pt) void {
    var next: usize = 0;
    for (bank.devices, 0..) |d, i| {
        const at = Pt.round(s.xy[s.deviceNode(d.index()).?]);
        const count: usize = if (i == 2) 2 else 3;
        for (0..count) |j| {
            out[next] = at.add(tip(s, d.index(), pin(bank, i, j)));
            next += 1;
        }
    }
    assert(next == out.len);
}

fn keep(storage: [][2]i32, count: *usize, a: i32, b: i32) void {
    if (a == b) return;
    assert(count.* < storage.len);
    storage[count.*] = .{ @min(a, b), @max(a, b) };
    count.* += 1;
}

fn contains(pair: Pair, d: usize) bool {
    for (pair) |bank| for (bank.devices) |edge| if (edge.index() == d) return true;
    return false;
}

fn box(s: *const sch.Schematic, ats: []const ?pinned.At, d: u32, at: Pt) Rect {
    return if (ats[d]) |fixed| s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin) else s.boxAt(d, at);
}

fn collectFailure(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, st: *const @import("structure.zig").Structure, ats: []const ?pinned.At, lines: *const @import("netlines.zig").NetLines) !void {
    var before: [11]sch.DeviceInfo = undefined;
    std.debug.assert(s.devices.len == before.len);
    for (&before, 0..) |*row, d| row.* = s.devices.get(d);
    var batch = banks.collect(gpa, nl, s, sk, st, ats, lines) catch |err| {
        for (before, 0..) |row, d| try std.testing.expectEqualDeep(row, s.devices.get(d));
        return err;
    };
    defer batch.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), batch.pairs.items.len);
    for (before, 0..) |row, d| try std.testing.expectEqualDeep(row, s.devices.get(d));
}

test "shared coil banks: collision restores all ten rows and allocation failure leaves geometry intact" {
    // Literal reciprocal topology plus independently supplied exact mates.
    // One fixed candidate succeeds without the obstacle. Putting a foreign
    // body on that same candidate must restore every changed pose and keep
    // every old coordinate. The blocker cannot move the candidate anchor.
    const text = "Banks\n.model nch nmos\n" ++
        ".subckt ct_inductor n1 n2 n3\nL1 n1 n3 1n\nL2 n3 n2 1n\n.ends\n" ++
        "XLE1 a b vdd ct_inductor\nXLO1 a b vdd ct_inductor\nCT1 a b 1p\nM1 a b 0 0 nch\nM2 b a 0 0 nch\n" ++
        "XLE2 c d vdd ct_inductor\nXLO2 c d vdd ct_inductor\nCT2 c d 1p\nM3 c d 0 0 nch\nM4 d c 0 0 nch\nRBLOCK block 0 1k\n";
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{text}, null);
    const roles = try sch.guessRoles(a, &nl);
    var lib = library.Library.init(gpa);
    defer lib.deinit();
    _ = try lib.register(.{ .name = "cap", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 20, .y = 0 }, .side = .right },
    }, .draw = &.{.{ .line = .{ .a = .{ .x = -20, .y = 0 }, .b = .{ .x = 20, .y = 0 } } }} });
    _ = try lib.register(.{ .name = "nmos", .terminals = &.{
        .{ .name = "d", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 0, .y = 0 }, .hidden = true },
    }, .draw = &.{ .{ .line = .{ .a = .{ .x = -20, .y = 0 }, .b = .{ .x = 20, .y = 0 } } }, .{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .{ .x = 0, .y = 0 } } } } });
    var s = try sch.initDevices(gpa, &nl, roles, &lib);
    defer s.deinit();
    for (0..s.devices.len) |d| s.devices.set(d, .{ .kept = true, .driver = false, .class = s.devices.items(.class)[d], .orientation = .horizontal, .flip_x = false, .flip_y = false, .orient = .r0, .grid = .zero, .reach = @splat(0) });
    sch.settleDevices(&s, &nl.graph);
    var st = try @import("structure.zig").analyze(gpa, a, &nl, roles);
    var sk = try skeleton.place(gpa, a, &nl, roles, &st, .{ .shelf = 0 });
    const mates = try a.alloc(u32, s.devices.len);
    @memset(mates, sch.none);
    for ([_][2][]const u8{ .{ "xle1", "xle2" }, .{ "xlo1", "xlo2" }, .{ "ct1", "ct2" }, .{ "m1", "m3" }, .{ "m2", "m4" } }) |names| {
        const x, const y = .{ nl.device(names[0]).?.index(), nl.device(names[1]).?.index() };
        mates[x] = y;
        mates[y] = x;
    }
    st.device_mate = mates;
    const net_mates = try a.alloc(u32, roles.len);
    @memset(net_mates, sch.none);
    for ([_][2][]const u8{ .{ "a", "c" }, .{ "b", "d" }, .{ "vdd", "vdd" }, .{ "0", "0" } }) |names| {
        const x, const y = .{ nl.net(names[0]).?.index(), nl.net(names[1]).?.index() };
        net_mates[x] = y;
        net_mates[y] = x;
    }
    st.net_mate = net_mates;
    st.symmetry_off = false;
    sk.axis2 = 0;
    const drawn = try a.alloc(bool, s.devices.len);
    @memset(drawn, true);
    sk.drawn = drawn;
    const shelf = try a.alloc(u32, s.devices.len);
    @memset(shelf, 0);
    sk.shelf = shelf;
    const ats: [11]?pinned.At = @splat(null);
    const lines = try @import("netlines.zig").read(a, &nl, roles, lib.unit, &.{});
    try std.testing.checkAllAllocationFailures(gpa, collectFailure, .{ &nl, &s, &sk, &st, &ats, &lines });
    var batch = try banks.collect(gpa, &nl, &s, &sk, &st, &ats, &lines);
    defer batch.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), batch.pairs.items.len);
    const pair = batch.pairs.items[0];
    const obstacle = nl.device("rblock").?.index();
    var positions: [11][2]f32 = undefined;
    var original: [11]sch.DeviceInfo = undefined;
    for (&positions, &original, 0..) |*p, *row, d| {
        p.* = .{ @floatFromInt(d * 100), 1000 };
        row.* = s.devices.get(d);
    }
    const old_positions = positions;
    const len = Lengths.of(.{}, lib.unit);
    const core = Rect.fromCorners(.zero, .zero);
    drawn[obstacle] = false;
    try std.testing.expect(attempt(&s, &nl, &sk, &ats, len, &positions, pair, core, 0, 0, true));
    const blocked_position = positions[pair[0].devices[0].index()];
    for (original, 0..) |row, d| s.devices.set(d, row);
    positions = old_positions;
    positions[obstacle] = blocked_position;
    drawn[obstacle] = true;
    const before = positions;
    try std.testing.expect(!attempt(&s, &nl, &sk, &ats, len, &positions, pair, core, 0, 0, true));
    try std.testing.expectEqualDeep(before, positions);
    for (original, 0..) |row, d| try std.testing.expectEqualDeep(row, s.devices.get(d));
}
