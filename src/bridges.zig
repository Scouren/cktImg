//! Bridges (issue #8, stage 3): where each horizontal device stands, in
//! the channels between the columns. In: the netlist, its roles and
//! structure, and the vertical devices' cells and rows. Out: each bridge's
//! cell.
//!
//! Two-pin bridges in series (through nets that join just the two of them,
//! gates aside) share the slots between the nearest columns of the chain's
//! two end nets, in order, at the first end's tap row, or under the drawing
//! when a column between runs through that row; a chain whose tips stand
//! on one column (or one end on none) stands beside it: toward the axis
//! when an end net lies on it, else toward an input's side or away from the
//! axis. Any other bridge (an op-amp) stands midway between its nets' two
//! nearest columns. A chain whose mate stands already mirrors it; taken
//! slots move it outward.
//!
//! Contents:
//! - `pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, order: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, axis2: ?i32, x: []i32, y: []i32) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Structure = structure.Structure;
const Form = skeleton.Form;
const none = structure.none;

/// Places every drawn horizontal device, `order` (devices by rank) chain by
/// chain, into a free cell of `x`, `y`; the vertical devices' cells are set,
/// `rank` holds their rows and `axis2` is twice the x they mirror about.
pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, order: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, axis2: ?i32, x: []i32, y: []i32) Allocator.Error!void {
    const c = &nl.graph;
    const n = c.edgeCount();
    assert(x.len == n and y.len == n);
    assert(order.len == n);
    var taken: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer taken.deinit(gpa);
    for (0..n) |d| if (drawn[d] and form[d] == .vertical) try taken.put(gpa, .{ x[d], y[d] }, {});
    const placed = try gpa.alloc(bool, n);
    defer gpa.free(placed);
    @memset(placed, false);
    var chain: std.ArrayList(u32) = .empty;
    defer chain.deinit(gpa);
    var slots: std.ArrayList([2]i32) = .empty;
    defer slots.deinit(gpa);
    for (order) |d| {
        if (!drawn[d] or form[d] != .horizontal or placed[d]) continue;
        const tips = try chainOf(gpa, nl, roles, drawn, form, upper, lower, placed, d, &chain);
        slots.clearRetainingCapacity();
        const m = st.device_mate[chain.items[0]];
        if (axis2 != null and m != none and m != chain.items[0] and placed[m]) {
            // The mirror image of the mate's chain, member by member.
            for (chain.items) |b| {
                const mb = st.device_mate[b];
                const at: [2]i32 = if (mb != none and placed[mb]) .{ axis2.? - x[mb], y[mb] } else .{ axis2.? - x[m], y[m] };
                try slots.append(gpa, at);
            }
        } else {
            try chainSlots(gpa, nl, roles, st, drawn, form, upper, lower, rank, x, y, axis2, chain.items, tips, &slots);
        }
        // Outward until every slot is free.
        const step: i32 = if (axis2 != null and 2 * slots.items[0][0] < axis2.?) -1 else 1;
        var shift: i32 = 0;
        var tries: usize = 0;
        while (for (slots.items) |sl| {
            if (taken.contains(.{ sl[0] + shift, sl[1] })) break true;
        } else false) : (tries += 1) {
            assert(tries <= taken.count() * slots.items.len);
            shift += step;
        }
        for (chain.items, slots.items) |b, sl| {
            const at: [2]i32 = .{ sl[0] + shift, sl[1] };
            try taken.put(gpa, at, {});
            x[b] = at[0];
            y[b] = at[1];
            placed[b] = true;
        }
    }
}

// ---- private ----

fn isTwoPin(kind: DeviceKind) bool {
    return switch (kind) {
        .resistor, .capacitor, .inductor, .vsource, .isource, .diode, .vswitch, .cswitch => true,
        else => false,
    };
}

fn isRail(r: Role) bool {
    return r == .supply or r == .sink;
}

/// The bridges in series with `d` (two-pin bridges joined by nets that hold
/// just the two of them), in order, into `out`; returns the chain's two end
/// nets (the same net twice for anything but a two-pin bridge).
fn chainOf(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, placed: []const bool, d: u32, out: *std.ArrayList(u32)) ![2]u32 {
    const c = &nl.graph;
    out.clearRetainingCapacity();
    try out.append(gpa, d);
    const pins = c.members(EdgeId.from(d));
    if (!isTwoPin(c.edges.items(.kind)[d]) or pins.len != 2) return .{ pins[0].index(), pins[0].index() };
    var tips: [2]u32 = .{ pins[0].index(), pins[1].index() };
    // Grow from each end in turn: the far end leftward, then rightward.
    for (0..2) |side| {
        var steps: usize = 0;
        while (steps < c.edgeCount()) : (steps += 1) {
            const net = tips[side];
            const next = linked(nl, roles, drawn, form, upper, lower, placed, out.items, net) orelse break;
            if (side == 0) try out.insert(gpa, 0, next) else try out.append(gpa, next);
            const np = c.members(EdgeId.from(next));
            tips[side] = if (np[0].index() == net) np[1].index() else np[0].index();
        }
    }
    assert(out.items.len >= 1);
    return tips;
}

/// The one other two-pin bridge on `net` when the net joins just two
/// drawn devices, both such bridges, one of them in `chain` (a gate on the
/// net, as a CMFB midpoint drives, does not count); else null.
fn linked(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, placed: []const bool, chain: []const u32, net: u32) ?u32 {
    const c = &nl.graph;
    if (isRail(roles[net])) return null;
    var other: ?u32 = null;
    var count: usize = 0;
    for (c.incident(VertexId.from(net))) |e| {
        const v = e.index();
        if (!drawn[v]) continue;
        if (form[v] == .vertical and upper[v] != net and lower[v] != net) continue;
        count += 1;
        if (std.mem.indexOfScalar(u32, chain, v) != null) continue;
        if (form[v] != .horizontal or placed[v] or !isTwoPin(c.edges.items(.kind)[v]) or c.members(e).len != 2) return null;
        other = v;
    }
    return if (count == 2) other else null;
}

/// The slots of a chain whose tips are `tips`, in chain order: evenly
/// between the nearest pair of distinct columns on its two tips when no
/// other column stands between them; else beside a column on both tips (or
/// on either), toward the axis when an end net is on it, an input's side,
/// or away from the axis. Its row: the first end's tap row, else any pin's;
/// under the drawing when a column between runs through that row.
fn chainSlots(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, x: []const i32, y: []const i32, axis2: ?i32, chain: []const u32, tips: [2]u32, out: *std.ArrayList([2]i32)) !void {
    const c = &nl.graph;
    const k: i32 = @intCast(chain.len);
    assert(chain.len >= 1);
    // The nearest pair of distinct columns, one per end (ties: leftmost),
    // and the leftmost column on both tips or else on either.
    var best: ?[2]i32 = null;
    var shared: ?i32 = null;
    var any: ?i32 = null;
    for (c.incident(VertexId.from(tips[0]))) |e0| {
        const a = e0.index();
        if (!drawn[a] or form[a] != .vertical) continue;
        any = @min(any orelse x[a], x[a]);
        for (c.incident(VertexId.from(tips[1]))) |e1| {
            const b = e1.index();
            if (!drawn[b] or form[b] != .vertical) continue;
            if (x[a] == x[b]) {
                shared = @min(shared orelse x[a], x[a]);
                continue;
            }
            const cand: [2]i32 = .{ x[a], x[b] };
            if (best == null or closer(cand, best.?)) best = cand;
        }
    }
    for (c.incident(VertexId.from(tips[1]))) |e1| {
        const b = e1.index();
        if (drawn[b] and form[b] == .vertical) any = @min(any orelse x[b], x[b]);
    }
    var row: i32 = -1;
    for (tips) |net| if (!isRail(roles[net])) {
        if (tapRow(nl, drawn, form, upper, lower, rank, net)) |r| {
            row = r;
            break;
        }
    };
    if (row == -1 and chain.len == 1) for (c.members(EdgeId.from(chain[0]))) |net| {
        if (isRail(roles[net.index()])) continue;
        if (tapRow(nl, drawn, form, upper, lower, rank, net.index())) |r| {
            row = r;
            break;
        }
    };
    if (best) |pair| {
        const lo = @min(pair[0], pair[1]);
        const hi = @max(pair[0], pair[1]);
        const between = for (0..c.edgeCount()) |v| {
            if (drawn[v] and form[v] == .vertical and x[v] > lo and x[v] < hi) break true;
        } else false;
        if (hi - lo > k and (!between or shared == null)) {
            const r = if (crosses(drawn, form, x, y, lo, hi, row)) outside(drawn, form, y) else row;
            // Evenly between, the first member nearest the first end's
            // column, each half the other's mirror image.
            const span: i32 = @intCast(@abs(pair[1] - pair[0]));
            const sign: i32 = if (pair[1] < pair[0]) -1 else 1;
            for (0..chain.len) |i| {
                const near = 2 * i + 1 <= chain.len;
                const j: i32 = @intCast(if (near) i else chain.len - 1 - i);
                const off = @divFloor(2 * span * (j + 1) + k + 1, 2 * (k + 1));
                try out.append(gpa, .{ pair[0] + sign * (if (near) off else span - off), r });
            }
            return;
        }
    }
    const at = shared orelse any orelse 0;
    const on_axis = st.net_mate[tips[0]] == tips[0] or st.net_mate[tips[1]] == tips[1];
    const inward_left = axis2 != null and 2 * at > axis2.?;
    const left = if (axis2 != null and on_axis)
        inward_left
    else
        roles[tips[0]] == .input or roles[tips[1]] == .input or (axis2 != null and !inward_left and 2 * at != axis2.?);
    const dir: i32 = if (left) -1 else 1;
    for (0..chain.len) |i| try out.append(gpa, .{ at + dir * (@as(i32, @intCast(i)) + 1), row });
}

/// A column strictly between `lo` and `hi` runs through `row`: one of its
/// devices stands above it, one below.
fn crosses(drawn: []const bool, form: []const Form, x: []const i32, y: []const i32, lo: i32, hi: i32, row: i32) bool {
    assert(lo < hi);
    for (0..drawn.len) |a| {
        if (!drawn[a] or form[a] != .vertical or x[a] <= lo or x[a] >= hi or y[a] >= row) continue;
        for (0..drawn.len) |b| if (drawn[b] and form[b] == .vertical and x[b] == x[a] and y[b] > row) return true;
    }
    return false;
}

/// The row just past the lowest devices, as the book draws a second
/// stage's CMFB resistors under the circuit.
fn outside(drawn: []const bool, form: []const Form, y: []const i32) i32 {
    var bottom: i32 = std.math.minInt(i32);
    for (drawn, form, y) |dr, f, py| if (dr and f == .vertical) {
        bottom = @max(bottom, py);
    };
    assert(bottom != std.math.minInt(i32));
    return bottom + 1;
}

/// Nearer columns first, then the leftmost pair, then the one whose first
/// end is on the left (so the order of the cards decides nothing).
fn closer(a: [2]i32, b: [2]i32) bool {
    const da = @abs(a[0] - a[1]);
    const db = @abs(b[0] - b[1]);
    if (da != db) return da < db;
    if (@min(a[0], a[1]) != @min(b[0], b[1])) return @min(a[0], a[1]) < @min(b[0], b[1]);
    return a[0] < b[0];
}

/// The odd row just below a net's lowest device above it, else just above
/// its highest device below it; null for a net no vertical device ends on.
fn tapRow(nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, net: u32) ?i32 {
    assert(net < nl.graph.vertexCount());
    assert(rank.len == drawn.len);
    var above: ?u32 = null;
    var below: ?u32 = null;
    for (nl.graph.incident(VertexId.from(net))) |e| {
        const d = e.index();
        if (!drawn[d] or form[d] != .vertical) continue;
        if (lower[d] == net) above = @max(above orelse 0, rank[d]);
        if (upper[d] == net) below = @min(below orelse std.math.maxInt(u32), rank[d]);
    }
    if (above) |r| return 2 * @as(i32, @intCast(r)) + 1;
    if (below) |r| return 2 * @as(i32, @intCast(r)) - 1;
    return null;
}
