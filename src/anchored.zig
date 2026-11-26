//! Flat devices a deck's `above` line places by another device's cell
//! (steering rung 2). A block or a flat part has no row of its own among
//! the columns' rows, so the line stands it in the column of the device it
//! names it with. In: the skeleton's cells once the bridges stand. Out: the
//! named flat devices on their cells.
//!
//!     *@ above r5 x1 r4      r5 over the block x1, r4 under it
//!     *@ above x1 x2         the block x2 under x1
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
//!
//! Contents:
//! - `pub fn anchor(nl: *const Netlist, form: []const Form, args: []const []const u8) u32`
//! - `pub fn place(gpa: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []const ?Verdict) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const hints = @import("hints.zig");
const skeleton = @import("skeleton.zig");

const Netlist = netlist.Netlist;
const Form = skeleton.Form;
const Verdict = hints.Verdict;

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
