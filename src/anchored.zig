//! Flat devices a deck's `above` line places by another device's cell
//! (steering rung 2). A block or a flat part has no row of its own among
//! the columns' rows, so the line stands it in the column of the device it
//! names it with. In: the skeleton's cells once the bridges stand. Out: the
//! named flat devices on their cells.
//!
//!     *@ above r5 x1 r4      r5 over the block x1, r4 under it
//!     *@ above x1 x2         the block x2 under x1
//!     *@ hang ic m9.d        ic under m9's drain
//!     *@ hang cg m3.g        cg beside m3's gate, between the rows
//!
//! Human Rules:
//! - anchored.1 (invariant) An `above` line's flat devices stand in the
//!   column of its anchor, each on a row above the next one the line
//!   names: the anchor is the first upright device the line names, else
//!   its first block, else its first device. Going out from the anchor,
//!   an upright device the line names takes the anchor's part for the
//!   flat devices past it. `place`
//! - anchored.2 (choice) A flat device stands on the nearest free cell
//!   past its neighbour in the line's direction: a cell holds one device,
//!   and the device moves as little as possible. `place`
//! - anchored.3 (habit) `hang <part> <dev>.<pin>` stands the part by that
//!   pin of an upright device: under its lower end, over its upper end,
//!   or half a column out on its gate's side, level with the gate when the
//!   part lies flat (its end on the gate's net toward the gate) and a row
//!   lower, hanging from the gate's wire, when it stands. Asked for by three agents of the hinting trial (ar-239,
//!   ag-1108, ag-1094), who wrote cells for it. `hang`
//!
//! Contents:
//! - `pub fn anchor(nl: *const Netlist, form: []const Form, args: []const []const u8) u32`
//! - `pub fn hang(gpa: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, gate_right: []const bool, left_end: []skeleton.End, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void`
//! - `pub fn place(gpa: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []const ?Verdict) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const hints = @import("hints.zig");
const skeleton = @import("skeleton.zig");
const device = @import("device.zig");
const relations = @import("relations.zig");

const Netlist = netlist.Netlist;
const Form = skeleton.Form;
const Verdict = hints.Verdict;
const EdgeId = netlist.EdgeId;

/// The index into `args` (device names of a relation line, each in `nl`)
/// of the device the line holds its flat devices by: the first upright
/// one, else the first block (a device with no current path), else the
/// first. Asserts `args` is not empty.
pub fn anchor(nl: *const Netlist, form: []const Form, args: []const []const u8) u32 {
    assert(args.len > 0);
    for (args, 0..) |name, k| if (form[nl.device(name).?.index()] == .vertical) return @intCast(k);
    for (args, 0..) |name, k| if (nl.path(nl.device(name).?) == null) return @intCast(k);
    return 0;
}

/// Stands the flat devices of each honoured `above` line in its anchor's
/// column, the preferred line last so it wins (anchored.1, anchored.2).
pub fn place(gpa: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []const ?Verdict) Allocator.Error!void {
    const n = x.len;
    assert(y.len == n and form.len == n and drawn.len == n);
    var taken: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer taken.deinit(gpa);
    for (0..n) |d| if (drawn[d]) try taken.put(gpa, .{ x[d], y[d] }, {});
    const order = try hints.applyOrder(gpa, nl.hints);
    defer gpa.free(order);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .above or verdicts[i] == null or verdicts[i].?.state != .honoured) continue;
        const k0 = anchor(nl, form, h.args);
        // Up from the anchor, then down, each flat device past the last.
        for ([_]i32{ -1, 1 }) |dir| {
            var ref = nl.device(h.args[k0]).?.index();
            var k: i64 = @as(i64, k0) + dir;
            while (k >= 0 and k < h.args.len) : (k += dir) {
                const d = nl.device(h.args[@intCast(k)]).?.index();
                assert(drawn[d]);
                if (form[d] == .vertical) {
                    ref = d;
                    continue;
                }
                _ = taken.remove(.{ x[d], y[d] });
                var row = y[ref] + dir;
                var steps: usize = 0;
                while (taken.contains(.{ x[ref], row })) : (row += dir) {
                    steps += 1;
                    assert(steps <= n);
                }
                x[d] = x[ref];
                y[d] = row;
                try taken.put(gpa, .{ x[d], y[d] }, {});
                ref = d;
            }
        }
    }
    for (0..n) |d| if (drawn[d]) assert(taken.contains(.{ x[d], y[d] }));
}

/// `hang <part> <dev>.<pin>`: the part on the nearest free cell by that pin
/// of an upright device (anchored.3), the preferred line last so it wins.
pub fn hang(gpa: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, gate_right: []const bool, left_end: []skeleton.End, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void {
    const n = x.len;
    assert(y.len == n and form.len == n and drawn.len == n);
    var taken: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer taken.deinit(gpa);
    for (0..n) |d| if (drawn[d]) try taken.put(gpa, .{ x[d], y[d] }, {});
    const order = try hints.applyOrder(gpa, nl.hints);
    defer gpa.free(order);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .hang) continue;
        const code: hints.Code = code: {
            if (h.args.len != 2) break :code .bad_args;
            const p = (nl.device(h.args[0]) orelse break :code .unknown_name).index();
            const dot = std.mem.lastIndexOfScalar(u8, h.args[1], '.') orelse break :code .bad_args;
            const d = (nl.device(h.args[1][0..dot]) orelse break :code .unknown_name).index();
            const pin = relations.pinIndex(nl, d, h.args[1][dot + 1 ..]) orelse break :code .unknown_name;
            if (p == d or !drawn[p] or !drawn[d] or form[d] != .vertical) break :code .not_placeable;
            const net = nl.graph.members(EdgeId.from(d))[pin].index();
            const ends = nl.graph.members(EdgeId.from(p));
            const own: u32 = for (ends, 0..) |q, k| {
                if (q.index() == net) break @intCast(k);
            } else break :code .bad_args;
            // The first cell to try, and the way to look on from it.
            const gate = pin == (device.of(nl.graph.edges.items(.kind)[d]).gate orelse pin + 1);
            const side: i32 = if (gate_right[d]) 2 else -2;
            const at: [2]i32, const step: [2]i32 = if (!gate and net == upper[d])
                .{ .{ x[d], y[d] - 1 }, .{ 0, -1 } }
            else if (!gate and net == lower[d])
                .{ .{ x[d], y[d] + 1 }, .{ 0, 1 } }
            else
                .{ .{ x[d] + side, y[d] + @intFromBool(form[p] == .vertical) }, .{ std.math.sign(side), 0 } };
            _ = taken.remove(.{ x[p], y[p] });
            var cell = at;
            var steps: usize = 0;
            while (taken.contains(cell)) : (cell = .{ cell[0] + step[0], cell[1] + step[1] }) {
                steps += 1;
                assert(steps <= n);
            }
            x[p] = cell[0];
            y[p] = cell[1];
            try taken.put(gpa, cell, {});
            // A flat part beside a gate turns its end on the net toward it,
            // unless a `face` line turned it.
            if (step[0] != 0 and form[p] == .horizontal and ends.len == 2 and left_end[p] == .auto)
                left_end[p] = if ((own == 0) == (side < 0)) .second else .first;
            // Pushed past the first cell: by the pin no more, but near it.
            if (steps > 0) break :code .no_room;
            break :code .ok;
        };
        verdicts[i] = if (code == .no_room) .{ .state = .relaxed, .code = code } else .of(code);
    }
    for (0..n) |d| if (drawn[d]) assert(taken.contains(.{ x[d], y[d] }));
}
