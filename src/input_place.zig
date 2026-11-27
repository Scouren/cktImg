//! Private voltage-source/resistor branches → a horizontal gate approach.
//!
//! Human Rules:
//! - input_place.1 (habit, bounded) The resistor lies between its private
//!   grounded voltage source and one MOS gate, on that gate's row. The
//!   source stands outside it, signal above ground and at/below the gate
//!   row. All 22 source branches have these relations and continuous
//!   source legs; the same gate witnesses the straight resistor approach.
//!   Other gates and channel incidences on that net need not share its row.
//!   See docs/research/input-resistors.md and input_resistor_legs.py.
//! - input_place.2 (choice) Keep the MOS fixed and use two free adjacent
//!   cells on its gate side, the source two rows below. Canonical device
//!   order decides competing branches and breaks ties between available
//!   gates. Only a clear local rectangle qualifies; its span stays on one
//!   shelf. Actual terminal lines and
//!   extents are supplied by schematic.settleDevice and sketch.coordinates:
//!   their grid anchors align collinear R ends with the MOS gate, including
//!   shifted caller frames, without treating symbol origins as terminals.
//! - input_place.3 (invariant) Branch mates and honoured row/above/order/
//!   cell/face requests keep their placement. Incompatible forms/ends
//!   abstain. Explicit origins remain owned by sketch.keepAts.
//!
//! Data: existing per-device cells, forms, ends, rank and admitted hints
//! in; only R/source cells and the R's semantic left end change. The cold
//! three-handle certificate is queried per resistor, with no retained
//! state. One protected interval per drawn resistor is the maximum; the
//! caller owns and frees that array. Capacity is reserved before writes.
//!
//! Contents:
//! - `pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, order: []const u32, rank: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, mate: []const u32, gate_right: []const bool, left_end: []End, x: []i32, y: []i32, verdicts: []const ?hints.Verdict, spans: *std.ArrayList([2]i32)) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const hints = @import("hints.zig");
const input_resistors = @import("input_resistors.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Form = skeleton.Form;
const End = skeleton.End;
const none = sch.none;

/// Places unheld compatible R/source branches after relation/cell/face
/// admission and appends their inclusive x spans. All device slices cover
/// the graph; `order` lists devices by canonical `rank`. The caller owns
/// `spans` and passes it to wrapping. Allocation failure occurs before any
/// cell write.
pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, order: []const u32, rank: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, mate: []const u32, gate_right: []const bool, left_end: []End, x: []i32, y: []i32, verdicts: []const ?hints.Verdict, spans: *std.ArrayList([2]i32)) Allocator.Error!void {
    const c = &nl.graph;
    const n = c.edgeCount();
    assert(drawn.len == n and form.len == n and upper.len == n and mate.len == n);
    assert(x.len == n and y.len == n and gate_right.len == n and left_end.len == n and rank.len == n);
    assert(verdicts.len == nl.hints.len and order.len == n);
    var capacity: usize = 0;
    for (c.edges.items(.kind), drawn) |kind, visible| capacity += @intFromBool(visible and kind == .resistor);
    try spans.ensureUnusedCapacity(gpa, capacity);
    for (order, 0..) |r, i| {
        assert(r < n and rank[r] == i);
        if (c.edges.items(.kind)[r] != .resistor) continue;
        const branch = input_resistors.find(nl, roles, drawn, r) orelse continue;
        const v = branch.source;
        if (form[r] != .horizontal or form[v] != .vertical or upper[v] != branch.junction) continue;
        if (mate[r] != none or mate[v] != none) continue;
        const held = held: for (nl.hints, verdicts) |h, verdict| {
            const state = verdict orelse continue;
            if (state.state != .honoured) continue;
            switch (h.verb) {
                .row, .above, .column, .order, .cell, .face, .hang => {},
                else => continue,
            }
            for (h.args) |name| {
                const d = (nl.device(name) orelse continue).index();
                if (d == r or d == v) break :held true;
            }
        } else false;
        if (held) continue;
        var anchor: ?u32 = null;
        for (c.incident(VertexId.from(branch.gate_net))) |e| {
            const g = e.index();
            if (!input_resistors.isGate(nl, drawn, branch.gate_net, g) or form[g] != .vertical) continue;
            const sign: i32 = if (gate_right[g]) 1 else -1;
            const outer = x[g] + 2 * sign;
            const clear = for (drawn, 0..) |visible, d| {
                if (!visible or d == r or d == v or d == g) continue;
                if (x[d] == x[g] or x[d] < @min(outer, x[g]) or x[d] > @max(outer, x[g])) continue;
                if (y[d] >= y[g] and y[d] <= y[g] + 2) break false;
            } else true;
            if (clear and (anchor == null or rank[g] < rank[anchor.?])) anchor = g;
        }
        const g = anchor orelse continue;
        const sign: i32 = if (gate_right[g]) 1 else -1;
        x[r] = x[g] + sign;
        x[v] = x[g] + 2 * sign;
        y[r] = y[g];
        y[v] = y[g] + 2;
        const first = c.members(EdgeId.from(r))[0].index() == branch.junction;
        left_end[r] = if (first == (sign < 0)) .first else .second;
        spans.appendAssumeCapacity(.{ @min(x[v], x[g]), @max(x[v], x[g]) });
    }
}

// ---- private ----

test "input branch placement: competing private branches ignore card order" {
    // Metamorphic oracle: these cards describe the same named circuit and
    // the same initial cells. Both branches can use the sole free gate
    // approach before either moves; permuting cards cannot choose its owner.
    // Literal initial cells deliberately avoid earlier bridge placement
    // choosing a winner before this owner gets its input.
    const head = "Competing input branches\n.model nch nmos\n";
    const decks = [_][]const u8{
        head ++ "R1 j1 gate 1k\nV1 j1 0 1\nR2 j2 gate 2k\nV2 j2 0 2\nM1 out gate 0 0 nch\n",
        head ++ "M1 out gate 0 0 nch\nV2 j2 0 2\nR2 j2 gate 2k\nV1 j1 0 1\nR1 j1 gate 1k\n",
    };
    const names = [_][]const u8{ "m1", "r1", "r2", "v1", "v2" };
    const initial = [_][2]i32{ .{ 0, 0 }, .{ -3, -1 }, .{ -4, -1 }, .{ -3, 2 }, .{ -4, 2 } };
    var results: [2][5][2]i32 = undefined;
    for (decks, 0..) |text, version| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        try std.testing.expectEqual(names.len, nl.graph.edgeCount());
        var rank: [5]u32 = undefined;
        var order: [5]u32 = undefined;
        const drawn: [5]bool = @splat(true);
        var form: [5]Form = @splat(.vertical);
        var upper: [5]u32 = @splat(none);
        const mate: [5]u32 = @splat(none);
        const gate_right: [5]bool = @splat(false);
        var left_end: [5]End = @splat(.auto);
        var x: [5]i32 = undefined;
        var y: [5]i32 = undefined;
        for (names, initial, 0..) |name, cell, r| {
            const d = nl.device(name).?.index();
            rank[d] = @intCast(r);
            order[r] = d;
            x[d] = cell[0];
            y[d] = cell[1];
        }
        for ([_][]const u8{ "r1", "r2" }) |name| form[nl.device(name).?.index()] = .horizontal;
        upper[nl.device("v1").?.index()] = nl.net("j1").?.index();
        upper[nl.device("v2").?.index()] = nl.net("j2").?.index();
        var spans: std.ArrayList([2]i32) = .empty;
        try place(a, &nl, roles, &order, &rank, &drawn, &form, &upper, &mate, &gate_right, &left_end, &x, &y, &.{}, &spans);
        try std.testing.expectEqual(1, spans.items.len);
        for (names, 0..) |name, i| {
            const d = nl.device(name).?.index();
            results[version][i] = .{ x[d], y[d] };
        }
    }
    // The first ordering actually claims the available approach.
    try std.testing.expectEqual([2]i32{ -1, 0 }, results[0][1]);
    try std.testing.expectEqualSlices([2]i32, &results[0], &results[1]);
}
