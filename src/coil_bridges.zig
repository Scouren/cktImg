//! Four direct/cross switches between already placed paired CT banks.
//!
//! Human Rules:
//! - coil_bridges.1 (habit, bounded) AG1180 puts corresponding-end switches
//!   on the two drain rows and the crossed pair vertically in the upper
//!   half, at distinct mirrored columns. This is one correlated figure;
//!   topology alone does not choose the upper half. The complete two-chain
//!   context is required. docs/research/center-tap-chains.md; `collect`
//! - coil_bridges.2 (invariant) Own only four switch poses, after the bank
//!   owner succeeds. All four card pins and the whole caller class remain
//!   intact. The source certifies path contacts, not control positions.
//!   Any held member or colliding candidate restores all four. `attempt`
//! - coil_bridges.3 (choice) Two reflected direct-switch poses keep the
//!   same path endpoints; full-body collision chooses the control side.
//!   Body-derived crossed columns clear the direct switches. Tips stay within
//!   the inner winding interval and the crossed lower tips above its
//!   midpoint. No routing or crossing-budget exemption follows. `orders`
//!
//! Data: existing CSR, exact mates, frames and successful bank key in;
//! cold 24-byte four-device owners out. One per parent bounds collection;
//! each stores five typed handles and four u1 end choices. Caller reserves
//! 24 order slots per owner before writes. Four stack rows provide rollback.
//! Two candidates/eight poses per member each; outside routing hot loops.
//!
//! Contents:
//! - `pub const Owner`, `Batch`, `Batch.deinit`
//! - `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, parents: []const banks.Pair) Allocator.Error!Batch`
//! - `pub fn place(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, parents: []const banks.Pair, owners: *std.ArrayList(Owner)) void`
//! - `pub fn orders(s: *const sch.Schematic, parents: []const banks.Pair, owners: []const Owner, storage: [][2]i32) [2][]const [2]i32`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const banks = @import("coil_banks.zig");
const chains = @import("coil_chains.zig");
const network = @import("coil_network.zig");
const actual_anchor = @import("actual_anchor.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Pt = library.Pt;
const Lengths = @import("canvas.zig").Lengths;

/// Parent first-coil key; corresponding upper/lower switches, then the
/// first-bank-upper and second-bank-upper crossed switches. `first` is
/// each path's semantic first terminal, independent of card reversal.
pub const Owner = network.Bridges;

/// Caller-owned requests and immediate existing-compactor order storage.
pub const Batch = struct {
    owners: std.ArrayList(Owner),
    coordinates: [][2]i32,

    /// Frees both buffers using the collection allocator.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.owners.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

comptime { assert(@sizeOf(Owner) == 24); }

/// Collects complete four-switch contexts before geometry mutation. The
/// parent collector already enforces outer-net style and bank precedence.
/// All per-device slices span the graph; the caller deinitializes.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, parents: []const banks.Pair) Allocator.Error!Batch {
    assert(ats.len == nl.graph.edgeCount() and sk.drawn.len == ats.len);
    assert(st.device_mate.len == ats.len);
    var owners: std.ArrayList(Owner) = .empty;
    errdefer owners.deinit(gpa);
    try owners.ensureTotalCapacity(gpa, parents.len);
    for (parents) |pair| {
        const owner = network.bridges(nl, s.roles, pair) orelse continue;
        const shared = shared: for (parents) |other| {
            if (other[0].devices[0] == owner.parent) continue;
            const candidate = network.bridges(nl, s.roles, other) orelse continue;
            for (owner.devices) |d| for (candidate.devices) |e| { if (d == e) break :shared true; };
        } else false;
        if (shared) continue;
        const blocked = blocked: for (owner.devices, 0..) |edge, i| {
            const d = edge.index();
            const mate = owner.devices[if (i < 2) i else 5 - i].index();
            if (st.device_mate[d] != mate or !sk.drawn[d] or ats[d] != null or sk.shelf[d] != sk.shelf[owner.parent.index()] or chains.held(nl, sk, st, d)) break :blocked true;
            for (st.block_devices) |member| if (member == d) break :blocked true;
            const c = s.lib.at(s.devices.items(.class)[d]);
            if (!c.shows(0) or !c.shows(1)) break :blocked true;
        } else false;
        if (!blocked) owners.appendAssumeCapacity(owner);
    }
    const coordinates = try gpa.alloc([2]i32, 24 * owners.items.len);
    return .{ .owners = owners, .coordinates = coordinates };
}

/// Tries two atomic rigid-pose candidates per surviving bank. Every
/// coordinate slice spans devices; a rejected owner changes no row or point.
pub fn place(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, parents: []const banks.Pair, owners: *std.ArrayList(Owner)) void {
    assert(at.len == s.devices.len and ats.len == at.len);
    assert(sk.drawn.len == at.len);
    var kept: usize = 0;
    for (owners.items) |owner| {
        const pair = parent(parents, owner) orelse continue;
        const accepted = for (0..2) |variant| {
            if (attempt(s, nl, sk, ats, len, at, pair, owner, @intCast(variant))) break true;
        } else false;
        if (!accepted) continue;
        owners.items[kept] = owner;
        kept += 1;
    }
    owners.items = owners.items[0..kept];
}

/// Appends only initially strict actual-tip orders. Equal drain rows are
/// already real grid tracks. Storage has twelve slots per axis per owner;
/// the bank owner supplies the same actual reflection axis to compaction.
pub fn orders(s: *const sch.Schematic, parents: []const banks.Pair, owners: []const Owner, storage: [][2]i32) [2][]const [2]i32 {
    assert(storage.len >= 24 * owners.len);
    assert(s.xy.len == s.nodes.len);
    const capacity = 12 * owners.len;
    var counts: [2]usize = .{ 0, 0 };
    for (owners) |owner| {
        const pair = parent(parents, owner).?;
        const ca = current(s, pair[0].devices[0].index(), pair[0].pins[0][0]);
        const cb = current(s, pair[1].devices[0].index(), pair[1].pins[0][0]);
        const lo, const hi = .{ @min(ca.x, cb.x), @max(ca.x, cb.x) };
        for (owner.devices, 0..) |edge, i| {
            const a = current(s, edge.index(), owner.first[i]);
            const b = current(s, edge.index(), 1 - owner.first[i]);
            keep(storage[0..capacity], &counts[0], lo, @min(a.x, b.x));
            keep(storage[0..capacity], &counts[0], @max(a.x, b.x), hi);
            if (i < 2) keep(storage[0..capacity], &counts[0], a.x, b.x) else {
                const mid = Pt.round(s.xy[s.deviceNode(pair[0].devices[0].index()).?]).y;
                keep(storage[capacity..], &counts[1], a.y, b.y);
                keep(storage[capacity..], &counts[1], b.y, mid);
            }
        }
        keep(storage[0..capacity], &counts[0], current(s, owner.devices[2].index(), owner.first[2]).x, current(s, owner.devices[3].index(), owner.first[3]).x);
        keep(storage[capacity..], &counts[1], current(s, owner.devices[0].index(), owner.first[0]).y, current(s, owner.devices[1].index(), owner.first[1]).y);
    }
    return .{ storage[0..counts[0]], storage[capacity..][0..counts[1]] };
}

// ---- private ----


fn parent(parents: []const banks.Pair, owner: Owner) ?banks.Pair {
    for (parents) |pair| if (pair[0].devices[0] == owner.parent) return pair;
    return null;
}

fn attempt(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pair: banks.Pair, owner: Owner, variant: u1) bool {
    var old: [4]sch.DeviceInfo = undefined;
    for (owner.devices, &old) |d, *row| row.* = s.devices.get(d.index());
    var committed = false;
    defer if (!committed) { for (owner.devices, old) |d, row| s.devices.set(d.index(), row); };
    const ca, const cb = .{ Pt.round(at[pair[0].devices[0].index()]), Pt.round(at[pair[1].devices[0].index()]) };
    const axis2 = @as(i64, ca.x) + cb.x;
    if (ca.x == cb.x or ca.y != cb.y or @mod(axis2, 2) != 0) return false;
    const forward = ca.x < cb.x;
    for (0..4) |i| if (!turn(s, nl, owner, i, forward, variant)) return false;
    // The crossed pair's actual full terminal frames reflect. Distinct
    // self-mated direct-switch controls retain their original offsets.
    const c2 = s.lib.at(s.devices.items(.class)[owner.devices[2].index()]);
    const c3 = s.lib.at(s.devices.items(.class)[owner.devices[3].index()]);
    if (c2.terminals.len != c3.terminals.len) return false;
    for (c2.terminals, 0..) |_, j| {
        const a = tip(s, owner.devices[2].index(), if (j < 2) end(owner, 2, j) else j);
        const b = tip(s, owner.devices[3].index(), if (j < 2) end(owner, 3, j) else j);
        if (@as(i64, a.x) + b.x != 0 or a.y != b.y) return false;
    }
    const row0 = Pt.round(at[pair[0].devices[3].index()]).add(tip(s, pair[0].devices[3].index(), 0)).y;
    const row1 = Pt.round(at[pair[0].devices[4].index()]).add(tip(s, pair[0].devices[4].index(), 0)).y;
    if (row0 >= ca.y or row1 <= ca.y) return false;
    const direct = s.boxAt(owner.devices[0].index(), .zero).merge(s.boxAt(owner.devices[1].index(), .zero));
    const crossed = s.boxAt(owner.devices[2].index(), .zero).merge(s.boxAt(owner.devices[3].index(), .zero));
    const distance = @max(@as(i64, @intCast(@abs(direct.min.x))), @as(i64, @intCast(@abs(direct.max.x)))) + @max(@as(i64, @intCast(@abs(crossed.min.x))), @as(i64, @intCast(@abs(crossed.max.x)))) + @max(len.stack, len.clearance + 1);
    const axis = @divTrunc(axis2, 2);
    var proposed: [4]Pt = undefined;
    for ([_]i64{ axis, axis, axis + (if (forward) -distance else distance), axis + (if (forward) distance else -distance) }, 0..) |x, i| {
        if (x < std.math.minInt(i32) or x > std.math.maxInt(i32)) return false;
        proposed[i] = .{ .x = @intCast(x), .y = if (i == 1) row1 else row0 };
        for (0..2) |j| {
            const p = proposed[i].add(tip(s, owner.devices[i].index(), end(owner, i, j)));
            if (p.x <= @min(ca.x, cb.x) or p.x >= @max(ca.x, cb.x)) return false;
            if (i >= 2 and j == 1 and p.y >= ca.y) return false;
        }
    }
    for (owner.devices, 0..) |edge, i| {
        const candidate = s.boxAt(edge.index(), proposed[i]).grow(len.clearance);
        for (at, sk.drawn, 0..) |xy, visible, d| {
            if (!visible or contains(owner, d)) continue;
            const box = if (ats[d]) |fixed| s.lib.at(s.devices.items(.class)[d]).box(fixed.orient orelse s.devices.items(.orient)[d], fixed.origin) else s.boxAt(d, Pt.round(xy));
            if (candidate.intersects(box)) return false;
        }
        for (i + 1..4) |j| if (candidate.intersects(s.boxAt(owner.devices[j].index(), proposed[j]))) return false;
    }
    for (owner.devices, proposed) |d, p| at[d.index()] = p.toF();
    committed = true;
    return true;
}

fn turn(s: *sch.Schematic, nl: *const Netlist, owner: Owner, i: usize, forward: bool, variant: u1) bool {
    const d = owner.devices[i].index();
    const c = s.lib.at(s.devices.items(.class)[d]);
    if (!c.shows(0) or !c.shows(1)) return false;
    // Each opposed collinear path has exactly two rigid poses. Reflect
    // the upper/lower direct frames together without moving their tips.
    var skip = i < 2 and (if (i == 0) variant == 1 else variant == 0);
    for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for ([_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } }) |flips| {
        s.devices.items(.orientation)[d] = form;
        s.devices.items(.flip_x)[d] = flips[0];
        s.devices.items(.flip_y)[d] = flips[1];
        sch.settleDevice(s, &nl.graph, d);
        const a = tip(s, d, owner.first[i]);
        const b = tip(s, d, 1 - owner.first[i]);
        var anchor: Pt = undefined;
        if (i < 2) {
            if (a.y != b.y or (if (forward) a.x >= b.x else a.x <= b.x) or @mod(@as(i64, a.x) + b.x, 2) != 0) continue;
            if (s.pinSide(d, owner.first[i]) != (if (forward) library.Side.left else library.Side.right) or s.pinSide(d, 1 - owner.first[i]) != (if (forward) library.Side.right else library.Side.left)) continue;
            if (skip) { skip = false; continue; }
            anchor = .{ .x = @intCast(@divTrunc(@as(i64, a.x) + b.x, 2)), .y = a.y };
        } else {
            if (a.x != b.x or a.y >= b.y or s.pinSide(d, owner.first[i]) != .up or s.pinSide(d, 1 - owner.first[i]) != .down) continue;
            anchor = a;
            // Try all poses until the second crossed switch is the full
            // first frame's reflected image, including caller controls.
            if (i == 3) {
                const other = owner.devices[2].index();
                const oc = s.lib.at(s.devices.items(.class)[other]);
                if (oc.terminals.len != c.terminals.len) continue;
                const equal = equal: for (c.terminals, 0..) |_, j| {
                    const p = tip(s, d, if (j < 2) end(owner, i, j) else j).sub(anchor);
                    const q = tip(s, other, if (j < 2) end(owner, 2, j) else j);
                    if (@as(i64, p.x) + q.x != 0 or p.y != q.y) break :equal false;
                } else true;
                if (!equal) continue;
            }
        }
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

test { _ = @import("coil_bridges_test.zig"); }
