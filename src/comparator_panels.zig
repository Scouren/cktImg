//! Pre-amplifier rows formed by two certified comparator stages in succession.
//!
//! Contents:
//! - `pub fn eligible`, `pub fn arrange`
const std = @import("std");
const parts = @import("parent_parts.zig");
const stage = @import("parent_stages.zig");
const lib = @import("library.zig");
const sch = @import("schematic.zig");
const netlist = @import("netlist.zig");
const skeleton = @import("skeleton.zig");
const hints = @import("hints.zig");
const intent = @import("parent_intent.zig");
const Pt = lib.Pt;

/// Bounds the proposal to the one- and two-polarity pre-amplifier circuits
/// for which both the five-device stage and output-stack pair were certified.
pub fn eligible(stages: []const stage.Stage, pairs: []const parts.Pair) bool {
    return stages.len > 0 and stages.len <= 2 and stages.len == pairs.len and
        (stages.len == 1 or stages[0].nmos_input != stages[1].nmos_input);
}

/// Keeps the downstream devices at their existing sites. Each input stage
/// keeps its accepted five-device geometry. A complete receiving pair is
/// placed in two facing channel columns to its right. Both groups occupy one
/// row above the remaining circuit. Every movement belongs to the same trial.
pub fn arrange(nl: *const netlist.Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, at: [][2]f32, stages: []const stage.Stage, pairs: []const parts.Pair, states: []const parts.State, verdicts: []const hints.Verdict) bool {
    if (!eligible(stages, pairs)) return false;
    const unit = s.lib.unit;
    var receivers: [2][4]u32 = undefined;
    var used: [18]u32 = undefined;
    var count: usize = 0;
    for (stages, receivers[0..stages.len]) |owner, *matched| {
        var found = false;
        for (pairs, states) |pair, state| {
            if (state != .ready) return false;
            const order = connection(nl, owner, pair) orelse continue;
            if (found) return false;
            found = true;
            matched.* = .{ pair[order].pmos, pair[order].nmos, pair[1 - order].pmos, pair[1 - order].nmos };
        }
        if (!found) return false;
        const row = owner.devices ++ matched.*;
        for (row) |d| {
            if (!sk.drawn[d] or sk.form[d] != .vertical or std.mem.indexOfScalar(u32, used[0..count], d) != null) return false;
            used[count] = d;
            count += 1;
        }
        for (nl.hints, verdicts) |h, verdict| if (intent.touches(nl, h, verdict, &row, &.{})) return false;
    }
    var downstream: ?lib.Rect = null;
    for (at, 0..) |point, d| {
        if (!sk.drawn[d] or std.mem.indexOfScalar(u32, used[0..count], @intCast(d)) != null) continue;
        const box = s.boxAt(d, Pt.round(point));
        downstream = if (downstream) |bounds| bounds.merge(box) else box;
    }
    const lower = downstream orelse return false;
    const mid = @divFloor(lower.min.x + lower.max.x, 2);
    for (stages, receivers[0..stages.len]) |owner, paired| {
        const center_y = lower.min.y - unit * @as(i32, if (stages.len == 2 and owner.nmos_input) 12 else 5);
        const input = channel(s, owner.devices[0], at) orelse return false;
        const other = channel(s, owner.devices[1], at) orelse return false;
        const shift = (Pt{ .x = mid - 3 * unit, .y = center_y }).sub(.{ .x = @divFloor(input.x + other.x, 2), .y = input.y });
        for (owner.devices) |d| at[d] = Pt.round(at[d]).add(shift).toF();
        for (paired, 0..) |d, k| {
            const old = channel(s, d, at) orelse return false;
            const source = if (k < 2) input else other;
            const target = Pt{ .x = source.x + shift.x + 6 * unit, .y = if (k % 2 == 0) center_y - unit else center_y + unit };
            at[d] = Pt.round(at[d]).add(target.sub(old)).toF();
        }
    }
    return true;
}

// ---- private ----

fn connection(nl: *const netlist.Netlist, owner: stage.Stage, pair: parts.Pair) ?usize {
    const graph = &nl.graph;
    const a = graph.members(netlist.EdgeId.from(owner.devices[0]))[0];
    const b = graph.members(netlist.EdgeId.from(owner.devices[1]))[0];
    const x = graph.members(netlist.EdgeId.from(if (owner.nmos_input) pair[0].pmos else pair[0].nmos))[1];
    const y = graph.members(netlist.EdgeId.from(if (owner.nmos_input) pair[1].pmos else pair[1].nmos))[1];
    if (x == a and y == b) return 0;
    if (x == b and y == a) return 1;
    return null;
}

fn channel(s: *const sch.Schematic, d: u32, at: []const [2]f32) ?Pt {
    const info = s.devices.get(d);
    const frame = s.lib.at(info.class);
    if (frame.terminals.len < 3) return null;
    const drain = info.orient.apply(frame.terminals[0].at);
    const source = info.orient.apply(frame.terminals[2].at);
    if (drain.x != source.x or @abs(drain.y - source.y) != s.lib.unit) return null;
    return Pt.round(at[d]).sub(info.grid).add(.{ .x = drain.x, .y = @divExact(drain.y + source.y, 2) });
}
