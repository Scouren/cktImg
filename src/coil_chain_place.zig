//! Actual-frame placement of the two private CT coupling chains.
//!
//! Human Rules:
//! - coil_chain_place.1 (habit, bounded) In AG1180, each C-S-C path is
//!   straight and ordered between the inner winding columns, outside its
//!   corresponding drain row. Both chains reflect about the banks' actual
//!   axis. All four switch card pins remain electrical pins; the source
//!   exposes only two path contacts. `attempt`, `turn`
//! - coil_chain_place.2 (choice) Try one body-derived row outside each
//!   complete bank envelope. Banks and other devices stay fixed. Actual
//!   cap outer tips and switch path midpoints anchor the grid; caller
//!   classes are unchanged. Any incompatible frame or body collision
//!   restores all six rows before coordinates commit. `attempt`
//! - coil_chain_place.3 (invariant) Preserve only initially strict actual
//!   tip orders in the existing compactor. Shared path rows/outer columns
//!   already use identical grid tracks; the bank owner retains reflection.
//!   No wiring, style or crossing-budget exemption is added. `orders`
//!
//! Data: cold 36-byte owners and surviving bank keys in; six poses and at
//! most ten x/two y orders out. Stack scratch holds six old rows/points.
//! One candidate and eight orientations/member bound placement; caller
//! allocated all capacity before mutation. This is not a routing hot loop.
//!
//! Contents:
//! - `pub fn place(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, parents: []const banks.Pair, owners: *std.ArrayList(Owner)) void`
//! - `pub fn orders(s: *const sch.Schematic, parents: []const banks.Pair, owners: []const Owner, storage: [][2]i32) [2][]const [2]i32`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const banks = @import("coil_banks.zig");
const chains = @import("coil_chains.zig");
const actual_anchor = @import("actual_anchor.zig");
const Lengths = @import("canvas.zig").Lengths;
const Owner = chains.Owner;
const Pt = library.Pt;
const Rect = library.Rect;

/// Places six-member owners only after their bank key survived placement.
/// Every input slice spans devices. Failed attempts change no coordinates
/// or device row; successful requests compact in place without allocation.
pub fn place(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, parents: []const banks.Pair, owners: *std.ArrayList(Owner)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (owners.items) |owner| {
        const pair = parent(parents, owner) orelse continue;
        if (!attempt(s, nl, sk, ats, len, at, pair, owner)) continue;
        owners.items[kept] = owner;
        kept += 1;
    }
    owners.items = owners.items[0..kept];
}

/// Supplies initially true actual-tip inequalities; equal rows/columns
/// already share grid tracks. Storage has twenty-four slots per owner,
/// twelve per axis. Parents are the same surviving bank list used by place.
pub fn orders(s: *const sch.Schematic, parents: []const banks.Pair, owners: []const Owner, storage: [][2]i32) [2][]const [2]i32 {
    assert(storage.len >= 24 * owners.len);
    assert(s.xy.len == s.nodes.len);
    const capacity = 12 * owners.len;
    var counts: [2]usize = .{ 0, 0 };
    for (owners) |owner| {
        const pair = parent(parents, owner).?;
        for (0..2) |row| {
            var last: ?i32 = null;
            for (row * 3..row * 3 + 3) |i| for (0..2) |j| {
                const d = owner.devices[i].index();
                const pin = end(owner, i, j);
                const p = current(s, d, pin);
                if (last) |x| keep(storage[0..capacity], &counts[0], x, p.x);
                last = p.x;
            };
            const chain = current(s, owner.devices[row * 3].index(), owner.first[row * 3]);
            const drain = current(s, pair[0].devices[3 + row].index(), 0);
            keep(storage[capacity..], &counts[1], chain.y, drain.y);
        }
    }
    return .{ storage[0..counts[0]], storage[capacity..][0..counts[1]] };
}

// ---- private ----

fn parent(parents: []const banks.Pair, owner: Owner) ?banks.Pair {
    for (parents) |pair| if (pair[0].devices[0] == owner.parent) return pair;
    return null;
}

fn attempt(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pair: banks.Pair, owner: Owner) bool {
    var before: [6]sch.DeviceInfo = undefined;
    for (owner.devices, &before) |d, *old| old.* = s.devices.get(d.index());
    var committed = false;
    defer if (!committed) { for (owner.devices, before) |d, old| s.devices.set(d.index(), old); };
    const a = Pt.round(at[pair[0].devices[0].index()]);
    const b = Pt.round(at[pair[1].devices[0].index()]);
    const axis2 = @as(i64, a.x) + b.x;
    if (@mod(axis2, 2) != 0 or a.x == b.x) return false;
    const forward = a.x < b.x;
    for (0..owner.devices.len) |i| if (!turn(s, nl, owner, i, forward)) return false;
    // Capacitor path frames reflect. Self-mated switches anchor their
    // path midpoint; distinct visible controls keep their rigid glyph
    // offsets. The source provides no control-coordinate symmetry.
    for (0..2) |row| {
        const left, const right = .{ row * 3, row * 3 + 2 };
        for (0..2) |j| {
            const p = tip(s, owner.devices[left].index(), end(owner, left, j));
            const q = tip(s, owner.devices[right].index(), end(owner, right, 1 - j));
            if (@as(i64, p.x) + q.x != 0 or p.y != q.y) return false;
        }
    }
    var columns: [2]i32 = undefined;
    var envelope: ?Rect = null;
    for (pair, 0..) |bank, bi| {
        var nearest: u64 = std.math.maxInt(u64);
        for (bank.devices, 0..) |d, i| {
            const anchor = Pt.round(at[d.index()]);
            const bounds = s.boxAt(d.index(), anchor);
            envelope = if (envelope) |r| r.merge(bounds) else bounds;
            if (i >= 2) continue;
            const pin = bank.pins[i][0];
            const p = anchor.add(tip(s, d.index(), pin));
            const distance = @abs(2 * @as(i64, p.x) - axis2);
            if (distance < nearest) { nearest = distance; columns[bi] = p.x; }
        }
    }
    var proposed: [6]Pt = undefined;
    const gap = @max(len.stack, len.clearance + 1);
    for (0..2) |row| {
        var low: i32 = 0;
        var high: i32 = 0;
        for (row * 3..row * 3 + 3) |i| {
            const box = s.boxAt(owner.devices[i].index(), .zero);
            low = @min(low, box.min.y);
            high = @max(high, box.max.y);
        }
        const y: i64 = if (row == 0) @as(i64, envelope.?.min.y) - gap - high else @as(i64, envelope.?.max.y) + gap - low;
        if (y < std.math.minInt(i32) or y > std.math.maxInt(i32)) return false;
        for ([_]i64{ columns[0], @divTrunc(axis2, 2), columns[1] }, 0..) |x, j| {
            if (x < std.math.minInt(i32) or x > std.math.maxInt(i32)) return false;
            proposed[row * 3 + j] = .{ .x = @intCast(x), .y = @intCast(y) };
        }
        var last: ?i32 = null;
        for (row * 3..row * 3 + 3) |i| for (0..2) |j| {
            const p = proposed[i].add(tip(s, owner.devices[i].index(), end(owner, i, j)));
            if (last) |x| { if (if (forward) p.x <= x else p.x >= x) return false; }
            last = p.x;
        };
    }
    for (owner.devices, 0..) |edge, i| {
        const candidate = s.boxAt(edge.index(), proposed[i]).grow(len.clearance);
        for (at, sk.drawn, 0..) |xy, visible, d| {
            if (!visible or contains(owner, d)) continue;
            const box = if (ats[d]) |fixed| s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin) else s.boxAt(d, Pt.round(xy));
            if (candidate.intersects(box)) return false;
        }
        for (i + 1..owner.devices.len) |j| if (candidate.intersects(s.boxAt(owner.devices[j].index(), proposed[j]))) return false;
    }
    for (owner.devices, proposed) |d, point| at[d.index()] = point.toF();
    committed = true;
    return true;
}

fn turn(s: *sch.Schematic, nl: *const netlist.Netlist, owner: Owner, i: usize, forward: bool) bool {
    const d = owner.devices[i].index();
    const c = s.lib.at(s.devices.items(.class)[d]);
    if (!c.shows(0) or !c.shows(1)) return false;
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
        s.devices.items(.orientation)[d] = form;
        s.devices.items(.flip_x)[d] = flips[0];
        s.devices.items(.flip_y)[d] = flips[1];
        sch.settleDevice(s, &nl.graph, d);
        const a = tip(s, d, owner.first[i]);
        const b = tip(s, d, 1 - owner.first[i]);
        if (a.y != b.y or (if (forward) a.x >= b.x else a.x <= b.x)) continue;
        if (s.pinSide(d, owner.first[i]) != (if (forward) library.Side.left else library.Side.right) or s.pinSide(d, 1 - owner.first[i]) != (if (forward) library.Side.right else library.Side.left)) continue;
        const sum = @as(i64, a.x) + b.x;
        if (i % 3 == 1 and @mod(sum, 2) != 0) continue;
        const anchor: Pt = switch (i % 3) {
            0 => a,
            1 => .{ .x = @intCast(@divTrunc(sum, 2)), .y = a.y },
            else => b,
        };
        actual_anchor.move(s, nl, d, anchor);
        return true;
    };
    return false;
}

fn end(owner: Owner, i: usize, j: usize) u1 { return if (j == 0) owner.first[i] else 1 - owner.first[i]; }

fn tip(s: *const sch.Schematic, d: u32, pin: usize) Pt {
    const info = s.devices.get(d);
    return info.orient.apply(s.lib.at(info.class).terminals[pin].at).sub(info.grid);
}

fn current(s: *const sch.Schematic, d: u32, pin: usize) Pt { return Pt.round(s.xy[s.deviceNode(d).?]).add(tip(s, d, pin)); }

fn contains(owner: Owner, d: usize) bool {
    for (owner.devices) |edge| if (edge.index() == d) return true;
    return false;
}

fn keep(storage: [][2]i32, count: *usize, a: i32, b: i32) void {
    if (a == b) return;
    assert(count.* < storage.len);
    storage[count.*] = .{ @min(a, b), @max(a, b) };
    count.* += 1;
}

test { _ = @import("coil_chain_place_test.zig"); }
