//! Certified converter loops and admitted cells → one local power region.
//!
//! Human Rules:
//! - loop_place.1 (habit, bounded) A unique flying-capacitor converter
//!   keeps its main path above the flying/output capacitor drops and the
//!   lower MOS/diode return. All 145 source groups put the flying cap
//!   between input main and coil, output branches beyond the output main,
//!   and the downward divider above the diode. See converter-loops.md.
//! - loop_place.2 (choice) Use one main row and one lower return row.
//!   Default to divider, floating cap, grounded cap after the main path:
//!   114/145 source drawings use this order; the 31 named exceptions have
//!   no proven topology selector (converter-branches.md). This preference
//!   applies only after the caller/mate guards below. Exact row equality
//!   also has source exceptions. Start at the existing main row and reserve
//!   its whole horizontal band with one clear row above and below.
//!   Outside devices in that band
//!   can send supply bars across the loop even from distant columns.
//!   On collision, try the next disjoint band above. This fallback and
//!   its one-row margin are default-placement choices, not a guarantee
//!   for arbitrary rail/stack lengths. Actual wire fits still certify
//!   the entire tree or abstain; they never bypass a body or rail.
//! - loop_place.3 (invariant) Mates and honoured row/above/order/cell/face
//!   requests retain their placement. Incompatible forms or capacitor
//!   ends abstain. Rejected/dropped requests impose no restriction.
//!   Existing ground shunts move with the group. Separated controls may
//!   remain above or below. Actual body/pin reach is reserved by coordinates.
//!
//! Data: existing per-device cells/forms/ends and cold topology handles
//! in; changed cells/flat ends and protected x spans out. At most one
//! span per drawn coil, allocated once; the caller frees it after wrapping.
//! Handles are u32, signed lattice coordinates i32; a 12-member stack
//! holds ten selected devices and at most two shunts. Each candidate reads
//! these fields together. Placement is serial because earlier rectangles
//! occupy cells for later groups; no state survives the skeleton pass.
//!
//! Contents:
//! - `pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []const u32, mate: []const u32, left_end: []End, x: []i32, y: []i32, verdicts: []const ?hints.Verdict) Allocator.Error!std.ArrayList([2]i32)`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const hints = @import("hints.zig");
const power_paths = @import("power_paths.zig");
const power_loops = @import("power_loops.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Role = sch.Role;
const Form = skeleton.Form;
const End = skeleton.End;
const none = std.math.maxInt(u32);

/// Places compatible, unconstrained converter groups after relation/cell
/// admission. The returned span list belongs to `gpa`; free it after
/// wrapping. Allocation precedes every cell write. All per-device slices
/// must cover the graph, and verdicts must contain the admitted hints.
pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []const u32, mate: []const u32, left_end: []End, x: []i32, y: []i32, verdicts: []const ?hints.Verdict) Allocator.Error!std.ArrayList([2]i32) {
    const c = &nl.graph;
    assert(drawn.len == c.edgeCount() and form.len == drawn.len);
    assert(x.len == drawn.len and y.len == drawn.len);
    assert(upper.len == drawn.len and mate.len == drawn.len and left_end.len == drawn.len);
    assert(verdicts.len == nl.hints.len);
    var capacity: usize = 0;
    for (c.edges.items(.kind), drawn) |kind, visible| capacity += @intFromBool(visible and kind == .inductor);
    var spans: std.ArrayList([2]i32) = .empty;
    try spans.ensureTotalCapacity(gpa, capacity);
    for (c.edges.items(.kind), 0..) |kind, coil| {
        if (kind != .inductor) continue;
        const group = power_loops.find(nl, roles, drawn, @intCast(coil)) orelse continue;
        const d = group.devices;
        const nets = group.nets;
        const compatible = for (d, 0..) |part, i| {
            const vertical = i == 4 or i >= 6;
            if ((form[part] == .vertical) != vertical) break false;
        } else true;
        if (!compatible or upper[d[4]] != nets[1] or upper[d[6]] != nets[3] or upper[d[7]] != nets[3] or upper[d[8]] != nets[3] or upper[d[9]] != nets[6]) continue;
        var members: [12]u32 = undefined;
        @memcpy(members[0..10], &d);
        var count: usize = 10;
        var shunts: [2]u32 = .{ none, none };
        for (nets[1..3], 0..) |net, side| {
            const shunt = power_paths.groundShunt(nl, roles, drawn, form, net) orelse continue;
            shunts[side] = shunt;
            members[count] = shunt;
            count += 1;
        }
        const held = for (members[0..count]) |part| {
            if (mate[part] != none) break true;
        } else held: {
            for (nl.hints, verdicts) |h, verdict| {
                const v = verdict orelse continue;
                if (v.state != .honoured) continue;
                switch (h.verb) {
                    .row, .above, .order, .cell, .face => {},
                    else => continue,
                }
                for (h.args) |name| {
                    const part = (nl.device(name) orelse continue).index();
                    if (std.mem.indexOfScalar(u32, members[0..count], part) != null) break :held true;
                }
            }
            break :held false;
        };
        if (held) continue;

        // The common source order is a default, not a selector for the
        // 31 minority drawings. Admitted caller relations abstained above.
        const branches = [3]u32{ d[8], d[6], d[7] };
        const base = @min(x[d[0]], @min(x[d[1]], x[d[2]]));
        var top = @min(y[d[0]], @min(y[d[1]], y[d[2]]));
        var tries: usize = 0;
        while (true) : (tries += 1) {
            assert(tries <= c.edgeCount());
            const occupied = for (drawn, 0..) |visible, part| {
                if (!visible or y[part] < top - 1 or y[part] > top + 7) continue;
                if (std.mem.indexOfScalar(u32, members[0..count], @intCast(part)) == null) break true;
            } else false;
            if (!occupied) break;
            top -= 10;
        }
        const slots = [10][2]i32{ .{ 0, 0 }, .{ 4, 0 }, .{ 8, 0 }, .{ 0, 6 }, .{ 2, 2 }, .{ 4, 6 }, .{ 0, 2 }, .{ 0, 2 }, .{ 0, 2 }, .{ 0, 4 } };
        for (d, slots) |part, slot| {
            x[part] = base + slot[0];
            y[part] = top + slot[1];
        }
        for (branches, 0..) |part, i| x[part] = base + 10 + 2 * @as(i32, @intCast(i));
        x[d[9]] = x[d[8]];
        for (shunts, 0..) |part, side| {
            if (part == none) continue;
            x[part] = base + (if (side == 0) @as(i32, 3) else 6);
            y[part] = top + 4;
        }
        // Inferred electrical ends cannot be pulled backward by a nearby
        // unrelated branch. Caller faces were excluded before any write.
        for ([_]u32{ d[0], d[1], d[2], d[3], d[5] }, [_]u32{ nets[0], nets[1], nets[2], nets[0], nets[4] }) |part, left| {
            left_end[part] = if (nl.path(EdgeId.from(part)).?[0] == left) .first else .second;
        }
        spans.appendAssumeCapacity(.{ base, base + 14 });
    }
    assert(spans.items.len <= capacity);
    return spans;
}
