//! An original five-MOS common-control stage and its relative branch sites.
//!
//! Contents:
//! - `pub const Stage`, `pub fn collect(arena: std.mem.Allocator, ctx: context.Context, parents: local.Parents) ![]const Stage`
//! - `pub fn arrange(a: std.mem.Allocator, s: *const sch.Schematic, sk: *const skeleton.Skeleton, at: [][2]f32, stages: []const Stage) !bool`
//! - `pub fn clearWires(p: *const placed.Placed, library: *const lib.Library, nl: *const netlist.Netlist, stages: []const Stage) bool`
const std = @import("std");
const netlist = @import("netlist.zig");
const placed = @import("placed.zig");
const checks = @import("checks.zig");
const context = @import("parent_context.zig");
const local = @import("local_parents.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const lib = @import("library.zig");

/// Order is input A/B, the matching load A/B, then the shared tail.
pub const Stage = struct {
    /// Input A/B, their loads A/B, and the tail, all in this graph.
    devices: [5]u32,
    /// NMOS inputs put the shared tail below the inputs in the drawing.
    nmos_input: bool,
};

/// Only complete acyclic owners enter the trial. The shared formal control
/// and both inputs occur only as gates, including every outside occurrence.
pub fn collect(arena: std.mem.Allocator, ctx: context.Context, parents: local.Parents) ![]const Stage {
    if (parents.disposition != .raw_multigroup_candidate) return &.{};
    const graph = &ctx.nl.graph;
    const mate = parents.search.?.first.?.devices;
    var found: std.ArrayList(Stage) = .empty;
    for (0..parents.group_count) |owner| {
        var group: [5]u32 = undefined;
        var size: usize = 0;
        for (parents.groups, 0..) |g, d| if (g == owner) {
            if (size < 5) group[size] = @intCast(d);
            size += 1;
        };
        if (size != 5) continue;
        for (group) |tail| {
            if (mate[tail] != tail) continue;
            const ts = graph.members(netlist.EdgeId.from(tail));
            if (ctx.kind[ts[0].index()] != .internal or ts[2] != ts[3] or graph.incident(ts[0]).len != 3 or !gateOnly(ctx, ts[1])) continue;
            var inputs: [2]u32 = undefined;
            var loads: [2]u32 = undefined;
            var count: usize = 0;
            for (group) |d| {
                if (d == tail) continue;
                const ps = graph.members(netlist.EdgeId.from(d));
                if (ps[2] != ts[0]) continue;
                if (count == 2 or ps[3] != ts[3] or ctx.kind[ps[0].index()] != .internal or ps[1] == ts[1] or !gateOnly(ctx, ps[1])) break;
                const load = for (group) |l| {
                    const q = graph.members(netlist.EdgeId.from(l));
                    if (l != d and q[0] == ps[0] and q[1] == ts[1] and q[2] == q[3] and q[3] != ts[3] and ctx.kind[q[3].index()] != ctx.kind[ts[3].index()]) break l;
                } else break;
                inputs[count] = d;
                loads[count] = load;
                count += 1;
            } else {
                if (count != 2 or mate[inputs[0]] != inputs[1] or mate[loads[0]] != loads[1] or loads[0] == loads[1]) continue;
                if (graph.members(netlist.EdgeId.from(inputs[0]))[1] == graph.members(netlist.EdgeId.from(inputs[1]))[1]) continue;
                try found.append(arena, .{ .devices = .{ inputs[0], inputs[1], loads[0], loads[1], tail }, .nmos_input = ctx.kind[ts[3].index()] == .sink });
                break;
            }
        }
    }
    return found.items;
}

/// Realizes the local branch sites in the first clear neighbouring room. Total
/// group extents and all foreign symbol boxes exclude occupied rooms. Returns
/// false when the measured default contact frame or any complete room is absent.
pub fn arrange(a: std.mem.Allocator, s: *const sch.Schematic, sk: *const skeleton.Skeleton, at: [][2]f32, stages: []const Stage) !bool {
    if (stages.len == 0 or !validMembers(stages, at.len)) return false;
    // The native default and Schemify core4 reference frames were measured
    // independently on the five isolated source stages (channel centers).
    const unit = s.lib.unit;
    const shape: struct { half_width: i32, load_gap: i32, tail_gap: i32 } = switch (unit) {
        40 => .{ .half_width = 70, .load_gap = 70, .tail_gap = 70 },
        60 => .{ .half_width = 140, .load_gap = 90, .tail_gap = 120 },
        else => return false,
    };
    const rooms = try a.alloc(lib.Rect, stages.len);
    defer a.free(rooms);
    for (stages, 0..) |stage, i| {
        var delta: [5]lib.Pt = undefined;
        const sign: i32 = if (stage.nmos_input) 1 else -1;
        for (stage.devices, 0..) |d, k| {
            if (!sk.drawn[d] or sk.form[d] != .vertical) return false;
            const info = s.devices.get(d);
            const class = s.lib.at(info.class);
            if (class.terminals.len < 3) return false;
            const dxy = info.orient.apply(class.terminals[0].at).sub(info.grid);
            const sxy = info.orient.apply(class.terminals[2].at).sub(info.grid);
            const expected = if (k == 2 or k == 3) -sign else sign;
            if (dxy.x != sxy.x or expected * (sxy.y - dxy.y) != unit or !std.mem.eql(u8, class.terminals[0].name, "d") or !std.mem.eql(u8, class.terminals[2].name, "s")) return false;
            delta[k] = .{ .x = dxy.x, .y = @divExact(dxy.y + sxy.y, 2) };
        }
        const old_a = lib.Pt.round(at[stage.devices[0]]);
        const old_b = lib.Pt.round(at[stage.devices[1]]);
        const half = @min(shape.half_width, @max(unit, @divFloor(@as(i32, @intCast(@abs(old_b.x - old_a.x))), 2)));
        const left: i32 = if (old_a.x < old_b.x) -half else half;
        const rel = [5]lib.Pt{ .{ .x = left, .y = 0 }, .{ .x = -left, .y = 0 }, .{ .x = left, .y = -shape.load_gap * sign }, .{ .x = -left, .y = -shape.load_gap * sign }, .{ .x = 0, .y = shape.tail_gap * sign } };
        const tail = lib.Pt.round(at[stage.devices[4]]);
        const first = lib.Pt.round(at[stage.devices[0]]);
        const anchor = lib.Pt{ .x = tail.x, .y = first.y };
        // Build the actual symbol frames and the complete local room once.
        // Translating the room preserves both branch geometry and clearance.
        var offsets: [5]lib.Pt = undefined;
        var frames: [5]lib.Rect = undefined;
        for (stage.devices, rel, delta, 0..) |d, xy, off, k| {
            offsets[k] = xy.sub(off);
            frames[k] = s.boxAt(d, offsets[k]).grow(5);
            for (frames[0..k]) |earlier| if (frames[k].intersects(earlier)) return false;
        }
        var footprint = frames[0];
        for (frames[1..]) |frame| footprint = footprint.merge(frame);
        const origin = locate: for (0..at.len + 2) |step| {
            const dist: i32 = @intCast(step * @as(usize, @intCast(unit)));
            const translations = [8]lib.Pt{ .{ .x = -dist, .y = 0 }, .{ .x = dist, .y = 0 }, .{ .x = 0, .y = -dist }, .{ .x = 0, .y = dist }, .{ .x = -dist, .y = -dist }, .{ .x = dist, .y = -dist }, .{ .x = -dist, .y = dist }, .{ .x = dist, .y = dist } };
            for (translations) |tr| {
                const center = anchor.add(tr);
                const room = footprint.translate(center);
                if (clearRoom(s, sk, at, stage, rooms[0..i], room)) break :locate center;
                if (step == 0) break;
            }
        } else return false;
        rooms[i] = footprint.translate(origin);
        for (stage.devices, offsets) |d, pt| at[d] = origin.add(pt).toF();
    }
    return true;
}

/// Checks the final emitted wire segments against the open interiors of the
/// complete selected symbol frames, after routing, off-grid leads and thinning.
pub fn clearWires(p: *const placed.Placed, library: *const lib.Library, nl: *const netlist.Netlist, stages: []const Stage) bool {
    if (!validMembers(stages, nl.graph.edgeCount())) return false;
    for (stages) |stage| {
        for (stage.devices) |source_device| {
            const name = nl.graph.edges.items(.name)[source_device];
            const d = checks.deviceIn(p, name) orelse return false;
            // Coordinates are integral. The one-unit inset leaves the four
            // boundary contacts available for their incident wire endpoints.
            const inside = p.deviceRect(library, d).grow(-1);
            for (0..p.netCount()) |n| {
                var paths = p.segments(n);
                while (paths.next()) |path| {
                    for (path[0 .. path.len - 1], path[1..]) |a, b| {
                        if (inside.intersects(lib.Rect.fromCorners(a, b))) return false;
                    }
                }
            }
        }
    }
    return true;
}

// ---- private ----
fn validMembers(stages: []const Stage, device_count: usize) bool {
    if (stages.len > device_count / 5) return false;
    for (stages, 0..) |stage, i| {
        for (stage.devices, 0..) |id, slot| {
            if (id >= device_count or std.mem.indexOfScalar(u32, stage.devices[0..slot], id) != null) return false;
            for (stages[0..i]) |prior| if (std.mem.indexOfScalar(u32, &prior.devices, id) != null) return false;
        }
    }
    return true;
}

fn clearRoom(s: *const sch.Schematic, sk: *const skeleton.Skeleton, at: []const [2]f32, stage: Stage, reserved: []const lib.Rect, room: lib.Rect) bool {
    for (reserved) |r| if (room.intersects(r)) return false;
    for (at, 0..) |pt, d| {
        if (!sk.drawn[d] or std.mem.indexOfScalar(u32, &stage.devices, @intCast(d)) != null) continue;
        if (room.intersects(s.boxAt(d, lib.Pt.round(pt)))) return false;
    }
    return true;
}

fn gateOnly(ctx: context.Context, n: netlist.VertexId) bool {
    if (ctx.kind[n.index()] != .formal) return false;
    for (ctx.nl.graph.incident(n)) |e| {
        for (ctx.nl.graph.members(e), 0..) |pin, t| if (pin == n and t != 1) return false;
    }
    return true;
}

test "disjoint in-range roles before any room write" {
    const good = [_]Stage{
        .{ .devices = .{ 0, 1, 2, 3, 4 }, .nmos_input = true },
        .{ .devices = .{ 5, 6, 7, 8, 9 }, .nmos_input = false },
    };
    try std.testing.expect(validMembers(&good, 10));
    for ([_]u32{ 0, 8, 10, std.math.maxInt(u32) }) |wrong| {
        var changed = good;
        changed[1].devices[4] = wrong;
        try std.testing.expect(!validMembers(&changed, 10));
    }
    try std.testing.expect(!validMembers(&good, 9));
}
