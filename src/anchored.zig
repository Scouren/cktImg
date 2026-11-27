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
//!     *@ hang rb cg.a        rb out past cg's end on net a: a chain
//!     *@ hang rf x1.outp     rf right of x1's output
//!
//! Human Rules:
//! - anchored.1 (invariant) An `above` line's flat devices stand in the
//!   column of its anchor, each on a row above the next one the line
//!   names: the anchor is the first upright device the line names, else
//!   its first block, else its first device. Going out from the anchor,
//!   an upright device the line names takes the anchor's part for the
//!   flat devices past it; one alone in its column first moves past the
//!   flat devices before it, so the line holds (ag-1094: `above r7 c9 r8
//!   x1 r10 c10 r9`). `place`
//! - anchored.2 (choice) A flat device stands on the nearest free cell
//!   past its neighbour in the line's direction: a cell holds one device,
//!   and the device moves as little as possible. `place`
//! - anchored.3 (habit) `hang <part> <dev>.<pin>` stands the part by that
//!   pin: under an upright device's lower end, over its upper end, or half
//!   a column out on its gate's side, level with the gate when the part
//!   lies flat (its end on the gate's net toward the gate) and a row
//!   lower, hanging from the gate's wire, when it stands. Asked for by
//!   three agents of the hinting trial (ar-239, ag-1108, ag-1094), who
//!   wrote cells for it. `hang`
//! - anchored.4 (habit) The pin may be any device's: a block's stands the
//!   part out on the side its box draws that port on (`library.portSide`),
//!   as a gate's does; a flat part's end, out past that end (an end no
//!   `face` line turned has its first pin left). Lines apply in deck
//!   order, so a part hung from a part hung earlier makes a chain (`hang
//!   c3 m5.g`, then `hang r1 c3.b`). A pin's cell taken, the part stands
//!   a row under it, then over it (under or over a flat part's end, the
//!   end turned the same way), so several parts share one pin; further
//!   out it is `relaxed no_room`.
//!   Asked for by three agents of the second hinting trial (ag-1094's bias
//!   chains, `hang rl c2.b`, `hang rs x1.net0`). `hang`
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
const library = @import("library.zig");
const block_symbols = @import("block_symbols.zig");

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
                    // One alone in its column moves past the flat devices
                    // before it; any other keeps its row.
                    const alone = for (0..n) |e| {
                        if (e != d and drawn[e] and x[e] == x[d]) break false;
                    } else true;
                    if (alone and dir * (y[d] - y[ref]) <= 0) {
                        _ = taken.remove(.{ x[d], y[d] });
                        y[d] = y[ref] + dir;
                        var steps: usize = 0;
                        while (taken.contains(.{ x[d], y[d] })) : (y[d] += dir) {
                            steps += 1;
                            assert(steps <= n);
                        }
                        try taken.put(gpa, .{ x[d], y[d] }, {});
                    }
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
/// of any device (anchored.3, anchored.4), the lines in deck order, a
/// weak line before every strong one.
pub fn hang(gpa: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, gate_right: []const bool, left_end: []skeleton.End, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void {
    const n = x.len;
    assert(y.len == n and form.len == n and drawn.len == n);
    var taken: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer taken.deinit(gpa);
    for (0..n) |d| if (drawn[d]) try taken.put(gpa, .{ x[d], y[d] }, {});
    const order = try hints.applyOrder(gpa, nl.hints);
    defer gpa.free(order);
    // Per device, whether a line has hung it yet: its cell is its own.
    const hung = try gpa.alloc(bool, n);
    defer gpa.free(hung);
    @memset(hung, false);
    // First every line's part off its cell, so no part a later line hangs
    // stands in the way; then each hung, in deck order.
    for ([_]bool{ true, false }) |freeing| for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .hang) continue;
        // The argument a name refusal points at.
        var arg: u32 = 0;
        const code: hints.Code = code: {
            if (h.args.len != 2) break :code .bad_args;
            const p = (nl.device(h.args[0]) orelse break :code .unknown_name).index();
            arg = 1;
            const dot = std.mem.lastIndexOfScalar(u8, h.args[1], '.') orelse break :code .bad_args;
            const d = (nl.device(h.args[1][0..dot]) orelse break :code .unknown_name).index();
            const pin = relations.pinIndex(nl, d, h.args[1][dot + 1 ..]) orelse break :code .unknown_name;
            if (p == d or !drawn[p] or !drawn[d]) break :code .not_placeable;
            const pins = nl.graph.members(EdgeId.from(d));
            const net = pins[pin].index();
            const ends = nl.graph.members(EdgeId.from(p));
            const own: u32 = for (ends, 0..) |q, k| {
                if (q.index() == net) break @intCast(k);
            } else break :code .bad_args;
            const flat = form[d] == .horizontal and nl.defOf(EdgeId.from(d)) == null;
            if (flat and (pins.len != 2 or pins[0] == pins[1])) break :code .not_placeable;
            if (freeing) {
                _ = taken.remove(.{ x[p], y[p] });
                continue;
            }
            // The way out of the pin: an upright device's end or gate, a
            // block's side, a flat part's end (anchored.3, anchored.4).
            const step: [2]i32 = step: {
                if (form[d] == .vertical) {
                    const gate = pin == (device.of(nl.graph.edges.items(.kind)[d]).gate orelse pin + 1);
                    if (!gate and net == upper[d]) break :step .{ 0, -1 };
                    if (!gate and net == lower[d]) break :step .{ 0, 1 };
                    break :step if (gate_right[d]) .{ 1, 0 } else .{ -1, 0 };
                }
                if (nl.defOf(EdgeId.from(d))) |def| break :step switch (library.portSide(def, block_symbols.boxSlots(def.name, def.ports), pin)) {
                    .left => .{ -1, 0 },
                    .right => .{ 1, 0 },
                    .top => .{ 0, -1 },
                    .bottom => .{ 0, 1 },
                };
                assert(flat);
                // ponytail: an end no line has turned yet is held with its
                // first pin left, so the part stays where it was hung.
                if (left_end[d] == .auto) left_end[d] = .first;
                break :step if ((pin == 0) == (left_end[d] == .first)) .{ -1, 0 } else .{ 1, 0 };
            };
            // The first cell to try: a side's half a column out, level with
            // the pin, a row lower for a part that stands; an end's next row.
            const at: [2]i32 = if (step[0] != 0)
                .{ x[d] + 2 * step[0], y[d] + @intFromBool(form[p] == .vertical) }
            else
                .{ x[d], y[d] + step[1] };
            // The cells beside the pin first, so several parts share one:
            // a row under and over it, or under and over a flat part's end.
            if (hung[p]) _ = taken.remove(.{ x[p], y[p] });
            hung[p] = true;
            const pivot: [2]i32 = if (flat) .{ x[d], y[d] } else at;
            const across: [2]i32 = .{ @intCast(@abs(step[1])), @intCast(@abs(step[0])) };
            const near = [_][2]i32{ at, .{ pivot[0] + across[0], pivot[1] + across[1] }, .{ pivot[0] - across[0], pivot[1] - across[1] } };
            var cell = for (near) |c| {
                if (!taken.contains(c)) break c;
            } else at;
            var steps: i32 = 0;
            while (taken.contains(cell)) : (cell = .{ at[0] + steps * step[0], at[1] + steps * step[1] }) {
                steps += 1;
                assert(steps <= @as(i32, @intCast(n)));
            }
            x[p] = cell[0];
            y[p] = cell[1];
            try taken.put(gpa, cell, {});
            // A flat part beside a pin turns its end on the net toward it,
            // under or over an end, the way that end does, unless a `face`
            // line turned it.
            const toward = if (cell[0] == x[d]) -step[0] else step[0];
            if (toward != 0 and form[p] == .horizontal and ends.len == 2 and left_end[p] == .auto)
                left_end[p] = if ((own == 0) == (toward < 0)) .second else .first;
            // Pushed past the cells beside the pin: by it no more, but near it.
            if (steps > 0) break :code .no_room;
            break :code .ok;
        };
        if (freeing) continue;
        verdicts[i] = switch (code) {
            .no_room => .{ .state = .relaxed, .code = code },
            .unknown_name, .not_placeable => .at(code, arg),
            else => .of(code),
        };
    };
    for (0..n) |d| if (drawn[d]) assert(taken.contains(.{ x[d], y[d] }));
}
