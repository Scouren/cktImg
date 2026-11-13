//! Bridges (issue #8, stage 3): where each horizontal device stands, in
//! the channels between the columns. In: the netlist, its roles and
//! structure, and the vertical devices' cells and rows. Out: each bridge's
//! cell.
//!
//! Human Rules:
//! - bridges.1 (book) Flat two-pin parts and MOS channels in series,
//!   joined by nets that hold just the two current paths (gates and bodies
//!   aside), lie in one row as a chain, in their order along the nets.
//!   AnalogGenie ag-738 and ag-995 put the MOS and its compensation
//!   capacitor together between stages. `chainOf`
//! - bridges.2 (unmeasured) Any other flat device except a transistor
//!   (an op-amp, a part with
//!   a side pin) is a chain of one whose ends are its first and its last
//!   net that is no rail: its input and its output, as a subcircuit lists
//!   its ports, not the supply its first port is often on. `chainOf`
//! - bridges.3 (unmeasured) A chain lies evenly between two columns, its
//!   first member nearest the first column, each half the other's mirror
//!   image; what varies is the two columns and the row (bridges.4 to
//!   bridges.12). `chainSlots`
//! - bridges.4 (unmeasured) The two columns are the nearest pair of
//!   distinct columns, one on each end net (ties: the leftmost), when the
//!   gap holds the chain and no column stands between them, or no column
//!   is on both end nets. `chainSlots`
//! - bridges.5: retired; the case of bridges.15 where the driven gates
//!   stood in one column and no column was on the block's first net.
//! - bridges.6 (unmeasured) Else the chain stands beside the column on both
//!   end nets (or on either), one slot past its own, toward the axis when
//!   an end net lies on the axis. `chainSlots`
//! - bridges.7 (order: signal) Else, with an end on an input, left of that
//!   column: what drives stands left of what reads. `chainSlots`
//! - bridges.8 (unmeasured) Else away from the axis: right of the column
//!   with no axis, or for a column on the axis. `chainSlots`
//! - bridges.9 (unmeasured) Beside one column, the member whose end is on
//!   the column stands next to it. `chainSlots`
//! - bridges.10 (unmeasured) The chain's row is the tap row of its first
//!   end that has one: the channel just below the lowest device ending on
//!   the net from above, else just above the highest below. `chainSlots`
//! - bridges.11 (habit) With no channel ending on either end net, the
//!   chain takes the row of the one gate an end is on, its wire straight
//!   into the gate (else a chain of one takes any pin's tap row). People:
//!   597 of 1,198 such nets of 5,263 hand-drawn schematics have the flat
//!   part level with the gate it joins. `chainSlots`
//! - bridges.12 (book) A chain between two columns whose row a column
//!   between them runs through lies under the drawing, a row past the
//!   lowest devices, as the book draws a second stage's CMFB resistors
//!   under the circuit; the code names no figure. `outside`
//! - bridges.13 (unmeasured) A chain whose every member's mate stands
//!   already is that chain's mirror image about the axis. `place`
//! - bridges.14 (choice) Where a slot is taken, the whole chain moves out,
//!   away from the axis (right with none), one lattice column at a time:
//!   a cell holds one device. Chains are placed in rank order. `place`
//! - bridges.15 (order: signal) A block with a port named as an input or
//!   an output stands in the signal's order, as a column does: left of
//!   the leftmost column with a gate its output drives, level with that
//!   gate, and right of the rightmost column on an input's net left of it
//!   when none stands between the two; with no gate to drive, right of
//!   the rightmost column on an input's net. Before bridges.4 to .8.
//!   People: 266 of 320 blocks whose output drives a gate stand left of
//!   every such gate, and 522 of the 590 that drive none stand right of
//!   every upright device on their inputs' nets, in 5,263 hand-drawn
//!   schematics. `passage`
//! - bridges.16 (order: signal) A flat transistor bridges its channel's
//!   two nets. Its gate and body do not select its columns: the signal
//!   crosses the channel, as in AnalogGenie ag-385 and ag-386. `chainOf`
//!
//! Contents:
//! - `pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, order: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, axis2: ?i32, x: []i32, y: []i32) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");
const forms = @import("forms.zig");
const library = @import("library.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Structure = structure.Structure;
const Form = skeleton.Form;
const none = structure.none;
const isRail = Role.isRail;

/// Where a chain stands: the two x it lies evenly between (two columns,
/// or one column and the slot past the chain's beside it), and its row.
const Spot = struct { pair: [2]i32, row: i32 };

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
        // Mirrored when every member's mate stands as a bridge already: one
        // that stands upright (a line of the deck's) has no slot to mirror.
        const mirrored = axis2 != null and for (chain.items) |b| {
            const mb = st.device_mate[b];
            if (mb == none or mb == b or !placed[mb]) break false;
        } else true;
        if (mirrored) {
            // The mirror image of the mate's chain, member by member.
            for (chain.items) |b| {
                const mb = st.device_mate[b];
                try slots.append(gpa, .{ axis2.? - x[mb], y[mb] });
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
            assert(!taken.contains(at));
            try taken.put(gpa, at, {});
            x[b] = at[0];
            y[b] = at[1];
            placed[b] = true;
        }
    }
}

// ---- private ----

/// The bridges in series with `d` (two-pin parts and MOS channels joined
/// by nets that hold just those paths), in order, into `out`; returns its end
/// nets (a transistor's channel ends; for other devices with side pins,
/// the first and the last nets that are no rail).
fn chainOf(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, placed: []const bool, d: u32, out: *std.ArrayList(u32)) ![2]u32 {
    const c = &nl.graph;
    out.clearRetainingCapacity();
    try out.append(gpa, d);
    const kind = c.edges.items(.kind)[d];
    if (device.isTransistor(kind)) {
        const path = nl.path(EdgeId.from(d)).?;
        if (kind != .mosfet or path[0] == path[1]) return path;
    }
    const pins = c.members(EdgeId.from(d));
    if (kind != .mosfet and !forms.isTwoEnded(nl, d)) {
        // A block stands between the first and the last of its nets that
        // are no rail: its input and its output, as a subcircuit lists its
        // ports, not the supply its first port is often on.
        var ends: [2]u32 = .{ pins[0].index(), pins[0].index() };
        var found = false;
        for (pins) |p| if (!isRail(roles[p.index()])) {
            if (!found) ends[0] = p.index();
            ends[1] = p.index();
            found = true;
        };
        return ends;
    }
    var tips = nl.path(EdgeId.from(d)).?;
    // Grow from each end in turn: the far end leftward, then rightward.
    for (0..2) |side| {
        var steps: usize = 0;
        while (steps < c.edgeCount()) : (steps += 1) {
            const net = tips[side];
            const next = linked(nl, roles, drawn, form, upper, lower, placed, out.items, net) orelse break;
            if (side == 0) try out.insert(gpa, 0, next) else try out.append(gpa, next);
            const path = nl.path(EdgeId.from(next)).?;
            tips[side] = if (path[0] == net) path[1] else path[0];
        }
    }
    assert(out.items.len >= 1);
    return tips;
}

/// The one other two-pin part or MOS bridge on `net` when just two drawn
/// current paths meet there, one in `chain`; gates and bodies do not count.
fn linked(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, placed: []const bool, chain: []const u32, net: u32) ?u32 {
    const c = &nl.graph;
    if (isRail(roles[net])) return null;
    var other: ?u32 = null;
    var count: usize = 0;
    var previous: u32 = none;
    for (c.incident(VertexId.from(net))) |e| {
        const v = e.index();
        // CSR lists one incidence per pin, sorted by device: a body
        // tied to its source is still one channel, not another path.
        if (v == previous) continue;
        previous = v;
        if (!drawn[v]) continue;
        const kind = c.edges.items(.kind)[v];
        if (device.isTransistor(kind)) {
            const path = nl.path(e).?;
            if (path[0] != net and path[1] != net) continue;
            if (path[0] == path[1]) return null;
        }
        if (form[v] == .vertical and upper[v] != net and lower[v] != net) continue;
        count += 1;
        if (std.mem.indexOfScalar(u32, chain, v) != null) continue;
        if (form[v] != .horizontal or placed[v] or (kind != .mosfet and !forms.isTwoEnded(nl, v))) return null;
        other = v;
    }
    return if (count == 2) other else null;
}

/// The slots of a chain whose tips are `tips`, in chain order: evenly
/// between the two columns its tips stand at. For a block with named
/// ports those are the signal's (`passage`). Else the nearest pair of
/// distinct columns on its two tips when no other column stands between
/// them; else a column on both tips (or on either) and, for the tip with
/// none of its own, the slot one past the chain's beside it: toward the
/// axis when an end net is on it, an input's side, or away from the axis;
/// the member whose tip is on the column stands next to it. Its row: the first end's
/// tap row; else the row of the one gate on an end no channel ends on;
/// else any pin's tap row; under the drawing when a column between runs
/// through that row.
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
    // A tip no channel ends on, with one gate on it: the chain stands on
    // that gate's row, its wire straight into the gate (people draw a flat
    // part level with the gate it joins in 597 of 1,198 such nets of 5,263
    // hand-drawn schematics).
    var row: i32 = -1;
    for (tips) |net| if (!isRail(roles[net])) {
        if (tapRow(nl, drawn, form, upper, lower, rank, net)) |r| {
            row = r;
            break;
        }
    };
    if (row == -1) for (tips) |net| if (!isRail(roles[net])) {
        if (gateRow(nl, drawn, form, upper, lower, rank, net)) |r| {
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
    // The columns its two tips stand at, and its row: the chain lies evenly
    // between the two.
    const spot: Spot = stand: {
        // A block stands where the signal's order puts it, as a column does
        // (people: 266 of 320 blocks left of every gate they drive, 522 of
        // 590 that drive none right of every device on their inputs' nets,
        // in 5,263 hand-drawn schematics).
        if (chain.len == 1) if (passage(nl, drawn, form, upper, lower, rank, x, chain[0], row)) |by_signal| break :stand by_signal;
        if (best) |pair| {
            const lo = @min(pair[0], pair[1]);
            const hi = @max(pair[0], pair[1]);
            const between = for (0..c.edgeCount()) |v| {
                if (drawn[v] and form[v] == .vertical and x[v] > lo and x[v] < hi) break true;
            } else false;
            if (hi - lo > k and (!between or shared == null)) {
                break :stand .{ .pair = pair, .row = if (crosses(drawn, form, x, y, lo, hi, row)) outside(drawn, form, y) else row };
            }
        }
        // Beside one column, the tip with no column of its own one past the
        // chain's slots: on the left when an end is an input (what drives
        // stands left of what reads); else the axis decides.
        const at = shared orelse any orelse 0;
        const on_axis = st.net_mate[tips[0]] == tips[0] or st.net_mate[tips[1]] == tips[1];
        const inward_left = axis2 != null and 2 * at > axis2.?;
        const left = if (axis2 != null and on_axis)
            inward_left
        else
            roles[tips[0]] == .input or roles[tips[1]] == .input or (axis2 != null and !inward_left and 2 * at != axis2.?);
        const far = at + (if (left) -(k + 1) else k + 1);
        // The member whose tip is on the column stands next to it: the chain
        // runs from its first tip, so it is turned when only the second tip
        // has a device there.
        var on = [2]bool{ false, false };
        for (tips, &on) |net, *o| for (c.incident(VertexId.from(net))) |e| {
            const d = e.index();
            if (drawn[d] and form[d] == .vertical and x[d] == at) o.* = true;
        };
        break :stand .{ .pair = if (on[1] and !on[0]) .{ far, at } else .{ at, far }, .row = row };
    };
    // Evenly between, the first member nearest the first end's column, each
    // half the other's mirror image.
    const span: i32 = @intCast(@abs(spot.pair[1] - spot.pair[0]));
    const sign: i32 = if (spot.pair[1] < spot.pair[0]) -1 else 1;
    for (0..chain.len) |i| {
        const near = 2 * i + 1 <= chain.len;
        const j: i32 = @intCast(if (near) i else chain.len - 1 - i);
        const off = @divFloor(2 * span * (j + 1) + k + 1, 2 * (k + 1));
        try out.append(gpa, .{ spot.pair[0] + sign * (if (near) off else span - off), spot.row });
    }
}

/// Where the signal's order stands block `d`, its ports' roles their names'
/// (`library.portRole`): left of the leftmost column with a gate its
/// output drives, level with that gate, and right of the rightmost column
/// on an input's net left of it when no column stands between the two;
/// with no such gate, right of the rightmost column on an input's net, on
/// `row`. Null for a device with no port so named, or with no upright
/// device on those nets.
fn passage(nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, x: []const i32, d: u32, row: i32) ?Spot {
    const c = &nl.graph;
    const def = nl.defOf(EdgeId.from(d)) orelse return null;
    const pins = c.members(EdgeId.from(d));
    if (def.ports.len != pins.len) return null;
    // The leftmost gate its output drives (the upper of two in a column).
    var gate: ?u32 = null;
    for (pins, def.ports) |p, name| {
        if (library.portRole(def.ports, name) != .out) continue;
        for (c.incident(p)) |e| {
            const v = e.index();
            if (!drawn[v] or form[v] != .vertical or upper[v] == p.index() or lower[v] == p.index()) continue;
            if (gate == null or x[v] < x[gate.?] or (x[v] == x[gate.?] and rank[v] < rank[gate.?])) gate = v;
        }
    }
    // The rightmost column on an input's net, left of that gate.
    var from: ?i32 = null;
    for (pins, def.ports) |p, name| {
        switch (library.portRole(def.ports, name)) {
            .in, .inp, .inn => {},
            .out, .rail, .other => continue,
        }
        for (c.incident(p)) |e| {
            const v = e.index();
            if (!drawn[v] or form[v] != .vertical or (gate != null and x[v] >= x[gate.?])) continue;
            from = @max(from orelse x[v], x[v]);
        }
    }
    const g = gate orelse return if (from) |at| .{ .pair = .{ at, at + 2 }, .row = row } else null;
    // Between the two when the way is clear; else beside the gate.
    const clear = from != null and for (0..drawn.len) |v| {
        if (drawn[v] and form[v] == .vertical and x[v] > from.? and x[v] < x[g]) break false;
    } else true;
    return .{ .pair = .{ if (clear) from.? else x[g] - 2, x[g] }, .row = 2 * @as(i32, @intCast(rank[g])) };
}

/// A column strictly between `lo` and `hi` runs through `row`: one of its
/// devices stands above it and one below, or one stands on it.
fn crosses(drawn: []const bool, form: []const Form, x: []const i32, y: []const i32, lo: i32, hi: i32, row: i32) bool {
    assert(lo < hi);
    for (0..drawn.len) |a| {
        if (!drawn[a] or form[a] != .vertical or x[a] <= lo or x[a] >= hi or y[a] > row) continue;
        if (y[a] == row) return true;
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

/// The row of the one upright transistor whose gate is on `net`, when no
/// upright device ends on the net; else null.
fn gateRow(nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, net: u32) ?i32 {
    const c = &nl.graph;
    var row: ?i32 = null;
    for (c.incident(VertexId.from(net))) |e| {
        const d = e.index();
        if (!drawn[d] or form[d] != .vertical) continue;
        if (lower[d] == net or upper[d] == net) return null;
        const gate = device.of(c.edges.items(.kind)[d]).gate orelse continue;
        if (c.members(e)[gate].index() != net) continue;
        if (row != null) return null;
        row = 2 * @as(i32, @intCast(rank[d]));
    }
    return row;
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
