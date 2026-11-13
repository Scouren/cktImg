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
//!   schematics. Complete reference-amplifier contracts also resolve VEA
//!   as an output (AG2427); generic port roles stay unchanged. `passage`
//! - bridges.16 (order: signal) A flat transistor bridges its channel's
//!   two nets. Its gate and body do not select its columns: the signal
//!   crosses the channel, as in AnalogGenie ag-385 and ag-386. `chainOf`
//! - bridges.17 (habit) A flat complementary transmission pair shares one
//!   column, NMOS above PMOS, rather than becoming a series chain. Both
//!   source pairs selected by forms.19 (ag-386, ag-751) do so. Spatial
//!   instructions applied afterward take precedence. `place`
//! - bridges.18 (habit) A converter's inductor and its unique main PMOS
//!   at each end share one row in channel order, despite shunts on the
//!   intermediate nets. All 252 selected source coils lie between those
//!   switches; 243 share their exact row. Nine have a small offset on one
//!   switch (named in the power-path study). Ambiguous branches and an
//!   upright instruction keep the ordinary placement. `power_paths.series`
//! - bridges.19 (habit, bounded) A certified converter path stands above
//!   its grounded external-gate shunts and active gate drivers, before
//!   the generic outside-column fallback. A block whose named output
//!   drives one main switch stands below that switch in its column:
//!   all 75 source outputs are below the path. Actual SVG output leads
//!   align with the driven gate in 67 cases (all 75 cached terminals do),
//!   but this pass aligns lattice columns; exact output-pin
//!   alignment needs the later symbol geometry. An occupied cell moves
//!   the block downward.
//!   No order is imposed on unrelated bias devices; explicit deck
//!   instructions run afterward. `power_paths.controlBounds`, `power_paths.blockTarget`
//! - bridges.20 (habit, bounded) A unique externally controlled ground
//!   shunt uses a free column between its certified main MOS and coil.
//!   All 353 source shunts fit that terminal interval; the 101 paired
//!   source rows already agree with the existing row placement. Keep
//!   that row and an already interior column. The placement choice is
//!   the midpoint rounded toward the main switch, then the nearest free
//!   interior column to that integer, toward the coil on a tie.
//!   No free column, an existing mate or an admitted order edge
//!   leaves the ordinary placement. Vertical row/above/order hints have
//!   already run here; cell instructions still run afterward. `place`
//! - bridges.21 (habit, bounded) The main path stands above its unique
//!   outer reservoirs' existing rows. All 359 source signal pins are at
//!   or below the main channel. Keep capacitor coordinates and raise the
//!   three-part path together; symbol spacing later reserves actual lead
//!   reaches. Mixed rows and final cells/at retain their later precedence.
//!   Multiple grounded caps or an explicitly flat cap give no row bound.
//!   `power_paths.reservoir`
//!
//! Contents:
//! - `pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, order: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, mate: []const u32, order_pairs: []const [2]u32, axis2: ?i32, x: []i32, y: []i32) Allocator.Error!void`

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
const block_symbols = @import("block_symbols.zig");
const transmission = @import("transmission.zig");
const power_paths = @import("power_paths.zig");

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
/// Unique converter shunts may use an interior column, preserving their
/// rows, existing `mate` assignments and admitted `order_pairs` constraints.
pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, order: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, mate: []const u32, order_pairs: []const [2]u32, axis2: ?i32, x: []i32, y: []i32) Allocator.Error!void {
    const c = &nl.graph;
    const n = c.edgeCount();
    assert(x.len == n and y.len == n);
    assert(order.len == n and mate.len == n);
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
        const pair = if (transmission.mate(nl, d)) |m| (if (drawn[m] and form[m] == .horizontal and !placed[m]) m else null) else null;
        const power = if (power_paths.series(nl, roles, drawn, form, d)) |members| available: {
            for (members) |v| if (placed[v]) break :available null;
            break :available members;
        } else null;
        const tips = if (pair) |m| paired: {
            chain.clearRetainingCapacity();
            const first_n = device.polarity(nl.modelType(EdgeId.from(d))) == .n;
            try chain.appendSlice(gpa, if (first_n) &.{ d, m } else &.{ m, d });
            break :paired nl.path(EdgeId.from(chain.items[0])).?;
        } else if (power) |members| ordered: {
            chain.clearRetainingCapacity();
            try chain.appendSlice(gpa, &members);
            const coil = nl.path(EdgeId.from(members[1])).?;
            const first = nl.path(EdgeId.from(members[0])).?;
            const last = nl.path(EdgeId.from(members[2])).?;
            break :ordered .{ first[@intFromBool(first[0] == coil[0])], last[@intFromBool(last[0] == coil[1])] };
        } else try chainOf(gpa, nl, roles, drawn, form, upper, lower, placed, d, &chain);
        slots.clearRetainingCapacity();
        // Mirrored when every member's mate stands as a bridge already: one
        // that stands upright (a line of the deck's) has no slot to mirror.
        const mirrored = axis2 != null and for (chain.items) |b| {
            const mb = st.device_mate[b];
            if (mb == none or mb == b or !placed[mb]) break false;
        } else true;
        if (pair != null) {
            try chainSlots(gpa, nl, roles, st, drawn, form, upper, lower, rank, x, y, axis2, chain.items[0..1], tips, &slots);
            const middle = slots.items[0];
            slots.items[0][1] -= 1;
            try slots.append(gpa, .{ middle[0], middle[1] + 1 });
        } else if (mirrored) {
            // The mirror image of the mate's chain, member by member.
            for (chain.items) |b| {
                const mb = st.device_mate[b];
                try slots.append(gpa, .{ axis2.? - x[mb], y[mb] });
            }
        } else {
            try chainSlots(gpa, nl, roles, st, drawn, form, upper, lower, rank, x, y, axis2, chain.items, tips, &slots);
        }
        if (power) |members| {
            if (power_paths.controlBounds(nl, roles, drawn, form, members, y)) |bounds| {
                for (slots.items) |*slot| slot[1] = bounds[0] - 1;
            }
            for ([_]u32{ members[0], members[2] }, nl.path(EdgeId.from(members[1])).?) |main, inner| {
                const cap = power_paths.reservoir(nl, roles, drawn, form, main, inner) orelse continue;
                for (slots.items) |*slot| slot[1] = @min(slot[1], y[cap] - 1);
            }
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
    // The vertical rows and order constraints have already been applied.
    // Keep those rows; use only an existing free interior column, without
    // spreading the rest of the drawing or separating an existing mate.
    for (order) |coil| {
        if (c.edges.items(.kind)[coil] != .inductor) continue;
        const members = power_paths.series(nl, roles, drawn, form, coil) orelse continue;
        for (nl.path(EdgeId.from(coil)).?, 0..) |net, side| {
            const d = power_paths.groundShunt(nl, roles, drawn, form, net) orelse continue;
            if (mate[d] != none) continue;
            const ordered = for (order_pairs) |edge| {
                if (edge[0] == d or edge[1] == d) break true;
            } else false;
            if (ordered) continue;
            const main = members[2 * side];
            const lo = @min(x[main], x[coil]);
            const hi = @max(x[main], x[coil]);
            if (lo < x[d] and x[d] < hi) continue;
            const span = hi - lo;
            if (span < 2) continue;
            const sign: i32 = if (x[coil] > x[main]) 1 else -1;
            const middle = x[main] + @divTrunc(x[coil] - x[main], 2);
            const column: ?i32 = for (0..@as(usize, @intCast(2 * span))) |step| {
                const off: i32 = @intCast((step + 1) / 2);
                const at = middle + sign * (if (step % 2 == 0) -off else off);
                if (at <= lo or at >= hi or taken.contains(.{ at, y[d] })) continue;
                break at;
            } else null;
            if (column) |at| {
                const removed = taken.remove(.{ x[d], y[d] });
                assert(removed);
                try taken.put(gpa, .{ at, y[d] }, {});
                x[d] = at;
            }
        }
    }
    // All main paths now stand, regardless of the block's card/rank order.
    // A block's output supplies the semantic relation, not its port order.
    for (order) |d| {
        if (!drawn[d] or form[d] != .horizontal) continue;
        const target = power_paths.blockTarget(nl, roles, drawn, form, d) orelse continue;
        const main = target[0];
        const removed = taken.remove(.{ x[d], y[d] });
        assert(removed);
        var row = y[main] + 1;
        var tries: usize = 0;
        while (taken.contains(.{ x[main], row })) : (tries += 1) {
            assert(tries <= taken.count());
            row += 1;
        }
        try taken.put(gpa, .{ x[main], row }, {});
        x[d] = x[main];
        y[d] = row;
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
/// (`library.portRole`, plus a complete analog output contract): left of
/// the leftmost column with a gate its
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
    const analog = block_symbols.analogOutput(def.name, def.ports);
    var gate: ?u32 = null;
    for (pins, def.ports, 0..) |p, name, i| {
        if (library.portRole(def.ports, name) != .out and (analog == null or analog.? != i)) continue;
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
