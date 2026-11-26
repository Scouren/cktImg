//! Output-tank and input-RC requests -> one fresh-lattice transaction.
//!
//! Human Rules:
//! - block_rooms.1 (invariant) Empty or declined RC work preserves the old
//!   output-tank transaction exactly, including its successful owners and
//!   generic fallback pairs. No rejected RC envelope expands the scene.
//! - block_rooms.2 (choice) Reserve all actual composite envelopes together.
//!   Check every future passive body against every future body, including
//!   other candidates. One failure restores every temporary row before the
//!   old output-only path runs; no farther search or routing exception.
//!
//! Data: borrowed cold owner batches and graph/lattice tables in; coordinates
//! and full passive rows commit together. Scratch has one group copy per
//! candidate, one Room per group, and two/five u32 handles plus full rows per
//! output/input group. Handles and rows are separate arrays, accessed together
//! only during rollback. Coordinate scratch spans the existing device table.
//! All allocation precedes temporary row writes. Scratch dies before routing;
//! scene checks and commit are serial, with no hot-loop or speed claim.
//!
//! Contents: lattice; private prior path, ownership and scene checks.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const sch = @import("schematic.zig");
const netlist = @import("netlist.zig");
const skeleton = @import("skeleton.zig");
const library = @import("library.zig");
const tanks = @import("block_tanks.zig");
const input = @import("block_input_rc.zig");
const place = @import("block_input_place.zig");
const coils = @import("coil_tanks.zig");
const geometry = @import("lattice_geometry.zig");
const Lengths = @import("canvas.zig").Lengths;
const Pt = library.Pt;
const EdgeId = netlist.EdgeId;
const Netlist = netlist.Netlist;
const Skeleton = skeleton.Skeleton;

/// Fresh-lattice coordinator; caller excludes direct/along placement and all
/// admitted fixed/relay coordinates. Returns whether output tanks were already
/// committed. Input survivors are precisely successful combined placements.
/// On allocation failure, coordinates, rows and generic fallback are unchanged.
pub fn lattice(gpa: Allocator, s: *sch.Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths, at: [][2]f32, outputs: *tanks.Batch, inputs: *input.Batch, fallback: *std.ArrayList(coils.Pair)) Allocator.Error!bool {
    assert(at.len == s.devices.len and sk.drawn.len == at.len);
    assert(outputs.room.len >= outputs.groups.items.len and inputs.room.len >= inputs.groups.items.len);
    if (inputs.groups.items.len == 0) return tanks.lattice(gpa, s, nl, sk, len, at, outputs, fallback);
    const out = try gpa.dupe(tanks.Group, outputs.groups.items);
    defer gpa.free(out);
    const ins = try gpa.dupe(input.Group, inputs.groups.items);
    defer gpa.free(ins);
    const room = try gpa.alloc(geometry.Room, out.len + ins.len);
    defer gpa.free(room);
    const capacity = 2 * out.len + 5 * ins.len;
    const edges = try gpa.alloc(EdgeId, capacity);
    defer gpa.free(edges);
    const saved = try gpa.alloc(sch.DeviceInfo, capacity);
    defer gpa.free(saved);
    const next = try gpa.dupe([2]f32, at);
    defer gpa.free(next);
    var output_groups: std.ArrayList(tanks.Group) = .empty;
    output_groups.items = out;
    output_groups.capacity = out.len;
    const output_room = tanks.rooms(s, nl, len, &output_groups, room[0..out.len]);
    var work: input.Batch = .{ .groups = .empty, .coordinates = &.{}, .room = room[output_room.len..] };
    work.groups.items = ins;
    work.groups.capacity = ins.len;
    const input_room = place.rooms(s, nl, len, &work);
    if (input_room.len == 0) return prior(gpa, s, nl, sk, len, at, outputs, inputs, fallback);
    const owned = ownership(edges, output_groups.items, work.groups.items) orelse return prior(gpa, s, nl, sk, len, at, outputs, inputs, fallback);
    const reserved = try geometry.coordinates(gpa, s, nl, sk, len, room[0 .. output_room.len + input_room.len]);
    defer gpa.free(reserved.xs);
    defer gpa.free(reserved.ys);
    for (next, sk.drawn, 0..) |*point, visible, d| if (visible) {
        point.* = .{ @floatFromInt(reserved.xs[@intCast(sk.x[d])]), @floatFromInt(reserved.ys[@intCast(sk.y[d])]) };
    };
    for (owned, saved[0..owned.len]) |edge, *row| row.* = s.devices.get(edge.index());
    if (!prepare(s, nl, sk, len, next, output_groups.items, work.groups.items, owned, saved[0..owned.len])) return prior(gpa, s, nl, sk, len, at, outputs, inputs, fallback);
    // No fallible work remains. Preserve original buffer ownership/capacity.
    @memcpy(at, next);
    @memcpy(outputs.groups.items[0..output_groups.items.len], output_groups.items);
    outputs.groups.items.len = output_groups.items.len;
    @memcpy(inputs.groups.items[0..work.groups.items.len], work.groups.items);
    inputs.groups.items.len = work.groups.items.len;
    tanks.commit(s, nl, len, at, outputs.groups.items, fallback);
    return true;
}

// ---- private ----

fn prior(gpa: Allocator, s: *sch.Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths, at: [][2]f32, outputs: *tanks.Batch, inputs: *input.Batch, fallback: *std.ArrayList(coils.Pair)) Allocator.Error!bool {
    const result = try tanks.lattice(gpa, s, nl, sk, len, at, outputs, fallback);
    inputs.groups.items.len = 0;
    return result;
}

fn ownership(storage: []EdgeId, outputs: []const tanks.Group, inputs: []const input.Group) ?[]const EdgeId {
    assert(storage.len >= 2 * outputs.len + 5 * inputs.len);
    var count: usize = 0;
    for (outputs) |group| {
        storage[count..][0..2].* = .{ group.pair.coil, group.pair.cap };
        count += 2;
    }
    for (inputs) |group| {
        storage[count..][0..5].* = input.members(group);
        count += 5;
    }
    const owned = storage[0..count];
    for (owned, 0..) |edge, i| {
        for (owned[0..i]) |previous| if (edge == previous) return null;
        for (outputs) |group| if (group.block == edge) return null;
        for (inputs) |group| if (group.block == edge) return null;
    }
    assert(count <= storage.len);
    return owned;
}

fn prepare(s: *sch.Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths, at: [][2]f32, outputs: []const tanks.Group, inputs: []const input.Group, owned: []const EdgeId, saved: []const sch.DeviceInfo) bool {
    assert(owned.len == saved.len);
    assert(at.len == sk.drawn.len and at.len == s.devices.len);
    var accepted = false;
    defer if (!accepted) for (owned, saved) |edge, row| {
        s.devices.set(edge.index(), row);
    };
    for (outputs) |group| {
        const points = tanks.propose(s, nl, len, group) orelse return false;
        if (!located(at, group.block, &.{ group.pair.coil, group.pair.cap }, &points)) return false;
    }
    for (inputs) |group| {
        const points = place.propose(s, nl, len, group) orelse return false;
        const members = input.members(group);
        if (!located(at, group.block, &members, &points)) return false;
    }
    // Every selected row and coordinate is now the proposed one. Neither
    // stale passive positions nor per-group commit order affects clearance.
    for (owned) |edge| {
        const bounds = s.boxAt(edge.index(), Pt.round(at[edge.index()])).grow(len.clearance);
        for (at, sk.drawn, 0..) |point, visible, d| {
            if (!visible or d == edge.index()) continue;
            if (bounds.intersects(s.boxAt(d, Pt.round(point)))) return false;
        }
    }
    accepted = true;
    return true;
}

fn located(at: [][2]f32, anchor: EdgeId, edges: []const EdgeId, points: []const Pt) bool {
    assert(edges.len == points.len);
    assert(anchor.index() < at.len);
    const origin = Pt.round(at[anchor.index()]);
    for (edges, points) |edge, point| {
        const x, const y = .{ @as(i64, origin.x) + point.x, @as(i64, origin.y) + point.y };
        if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or y < std.math.minInt(i32) or y > std.math.maxInt(i32)) return false;
        at[edge.index()] = (Pt{ .x = @intCast(x), .y = @intCast(y) }).toF();
    }
    return true;
}
