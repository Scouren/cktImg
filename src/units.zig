//! The deck's `stage` lines (steering rung 2): devices named as one unit,
//! which a `row` or `order` line then moves whole. In: the skeleton's
//! cells once the relations, bridges and anchors stand, before the `cell`
//! lines. Out: each unit a line names moved rigidly, and a verdict per
//! `stage` line and per `row` or `order` line naming a stage.
//!
//!     *@ stage bit0 x1 x2 m1 m2 m3 m4 m5 m6 m7 m8
//!     *@ stage bit1 x3 x4 m9 m10 m11 m12 m13 m14 m15 m16
//!     *@ row bit0 bit1        the two cells level, side by side
//!     *@ order bit0 out       the output stage right of bit0
//!     *@ repeat bit0 bit1     bit1 laid as bit0 is, beside it
//!
//! Asked for by three agents of the Fable round (ag-1067: four identical
//! cells drawn as a staircase; ag-2532, ag-641, ag-2500: `order` lines of
//! 17 to 24 names) and one of round 2 (ag-2402: the output stage as one
//! group right of the amplifier).
//!
//! Human Rules:
//! - units.1 (invariant) A `row` or `order` line that names a stage moves
//!   only the devices of the units it names, each unit rigidly: its
//!   devices keep their cells relative to each other. A device of no
//!   unit within a moved unit's box (the rows and columns it spans) moves
//!   out of it to the nearest free cell of its row, as cells.3; no other
//!   device moves. `shift`
//! - units.2 (choice) `row` levels each unit's top row with the first
//!   unit's, and a unit that would then overlap one before it in the line
//!   moves right until it clears it; `order` moves each unit right, only
//!   as far as it must, until it stands right of the one before. A name
//!   of a device that is no stage is a unit of one. `apply`
//! - units.3 (invariant) A device stands in one stage: a `stage` line
//!   naming a device an admitted one holds is dropped, `taken`. `read`
//! - units.4 (choice) `repeat` lays each unit after the first as the first
//!   is laid, level with it and right of the unit before: member k of
//!   each `stage` line stands where member k of the first does in its
//!   unit, so the deck lists the cells' devices in one order. Units of two
//!   sizes are `bad_args`. Narrowing: alike on the lattice, so in the
//!   drawing each member keeps the first unit's rows and column order;
//!   the columns' widths follow each unit's own wires (compaction knows no
//!   equal gaps yet). Asked for by two agents (ag-1067: a tile per bit).
//!   `repeat`
//!
//! Contents:
//! - `pub fn unit(nl: *const Netlist, name: []const u8) ?[]const []const u8`
//! - `pub fn claims(nl: *const Netlist, h: hints.Hint) bool`
//! - `pub const alone`, `pub fn read(arena: Allocator, nl: *const Netlist, drawn: []const bool, verdicts: []?Verdict) Allocator.Error![]const u32`
//! - `pub fn apply(gpa: Allocator, arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const hints = @import("hints.zig");
const skeleton = @import("skeleton.zig");

const Netlist = netlist.Netlist;
const Form = skeleton.Form;
const Verdict = hints.Verdict;

/// Lattice columns between neighbouring device columns (`skeleton.spread`
/// times its two-apart positions): a unit moves by whole columns.
const pitch = 8;

/// `read`'s entry for a device no stage holds.
pub const alone = std.math.maxInt(u32);

/// The device names of the stage called `name`: the first `stage` line of
/// that name, its arguments after the name; null when no line names one.
pub fn unit(nl: *const Netlist, name: []const u8) ?[]const []const u8 {
    return nl.hints[stageLine(nl, name) orelse return null].args[1..];
}

/// Whether `h` is a `repeat` line, or a `row` or `order` line naming a
/// stage: this module's, which `relations` and `sequence` leave alone.
pub fn claims(nl: *const Netlist, h: hints.Hint) bool {
    if (h.verb == .repeat) return true;
    if (h.verb != .row and h.verb != .order) return false;
    for (h.args) |name| if (unit(nl, name) != null) return true;
    return false;
}

/// Admits the `stage` lines (units.3): per device, the index of the line
/// whose unit holds it, or `alone`.
pub fn read(arena: Allocator, nl: *const Netlist, drawn: []const bool, verdicts: []?Verdict) Allocator.Error![]const u32 {
    const owner = try arena.alloc(u32, drawn.len);
    @memset(owner, alone);
    for (try hints.admitOrder(arena, nl.hints)) |i| {
        if (nl.hints[i].verb != .stage) continue;
        verdicts[i] = try admit(arena, nl, drawn, owner, i);
    }
    return owner;
}

/// Moves the units of each line `claims`, the preferred line last so it
/// stands (units.1, units.2, units.4). `read` has judged
/// the `stage` lines.
pub fn apply(gpa: Allocator, arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void {
    const n = x.len;
    assert(y.len == n and drawn.len == n and form.len == n);
    for (try hints.applyOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if (!claims(nl, h)) continue;
        const units = resolve(arena, nl, drawn, verdicts, h) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Bad => {
                verdicts[i] = bad(nl, drawn, verdicts, h);
                continue;
            },
        };
        try place(gpa, drawn, form, x, y, h.verb, units);
        verdicts[i] = .of(.ok);
    }
}

// ---- private ----

/// The verdict of `stage` line `i`: its name no device's, its members
/// drawn, distinct and in no admitted stage, which it then takes.
fn admit(arena: Allocator, nl: *const Netlist, drawn: []const bool, owner: []u32, i: u32) Allocator.Error!Verdict {
    const h = nl.hints[i];
    if (h.args.len < 2) return .of(.bad_args);
    if (nl.device(h.args[0]) != null) return .at(.bad_args, 0);
    // A second line of one name: the first defines it (`unit`).
    for (nl.hints[0..i]) |g| if (g.verb == .stage and g.args.len >= 2 and std.mem.eql(u8, g.args[0], h.args[0])) return .at(.bad_args, 0);
    for (h.args[1..], 1..) |name, k| {
        const d = (nl.device(name) orelse return .at(.unknown_name, @intCast(k))).index();
        if (!drawn[d]) return .at(.not_placeable, @intCast(k));
        for (h.args[1..k]) |seen| if (std.mem.eql(u8, seen, name)) return .at(.bad_args, @intCast(k));
        if (owner[d] != alone) return .blocked(arena, .dropped, .taken, &.{owner[d]});
    }
    for (h.args[1..]) |name| owner[nl.device(name).?.index()] = i;
    return .of(.ok);
}

/// Per name of line `h`, its devices: an honoured stage's, else the one
/// drawn device of that name; `error.Bad` for anything else, or a device
/// named twice.
fn resolve(arena: Allocator, nl: *const Netlist, drawn: []const bool, verdicts: []const ?Verdict, h: hints.Hint) error{ OutOfMemory, Bad }![]const []const u32 {
    if (h.args.len < 2) return error.Bad;
    const units = try arena.alloc([]const u32, h.args.len);
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    for (h.args, units) |name, *u| {
        const names: []const []const u8 = if (stageLine(nl, name)) |s| blk: {
            const v = verdicts[s] orelse return error.Bad;
            if (v.state != .honoured) return error.Bad;
            break :blk nl.hints[s].args[1..];
        } else &.{name};
        const devs = try arena.alloc(u32, names.len);
        for (names, devs) |m, *d| {
            d.* = @intCast((nl.device(m) orelse return error.Bad).index());
            if (!drawn[d.*]) return error.Bad;
            if ((try seen.fetchPut(arena, d.*, {})) != null) return error.Bad;
        }
        u.* = devs;
    }
    if (h.verb == .repeat) for (units) |u| if (u.len != units[0].len) return error.Bad;
    return units;
}

/// The verdict of a stage line `resolve` refused, the first name at fault.
fn bad(nl: *const Netlist, drawn: []const bool, verdicts: []const ?Verdict, h: hints.Hint) Verdict {
    if (h.args.len < 2) return .of(.bad_args);
    for (h.args, 0..) |name, k| {
        const at: u32 = @intCast(k);
        if (stageLine(nl, name)) |s| {
            if (verdicts[s] == null or verdicts[s].?.state != .honoured) return .at(.not_placeable, at);
            continue;
        }
        const d = nl.device(name) orelse return .at(.unknown_name, at);
        if (!drawn[d.index()]) return .at(.not_placeable, at);
    }
    // Every name is fine alone: a device named twice, or a `repeat` of
    // units of two sizes.
    return .of(.bad_args);
}

/// The index of the `stage` line defining `name`, or null.
fn stageLine(nl: *const Netlist, name: []const u8) ?u32 {
    for (nl.hints, 0..) |h, i| {
        if (h.verb == .stage and h.args.len >= 2 and std.mem.eql(u8, h.args[0], name)) return @intCast(i);
    }
    return null;
}

/// A unit's extent on the lattice: columns and rows, ends included.
const Box = struct {
    lo: [2]i32,
    hi: [2]i32,

    fn of(form: []const Form, x: []const i32, y: []const i32, devs: []const u32) Box {
        assert(devs.len > 0);
        var b: Box = .{ .lo = .{ std.math.maxInt(i32), std.math.maxInt(i32) }, .hi = .{ std.math.minInt(i32), std.math.minInt(i32) } };
        for (devs) |d| {
            b.lo = .{ @min(b.lo[0], x[d]), @min(b.lo[1], y[d]) };
            b.hi = .{ @max(b.hi[0], x[d]), @max(b.hi[1], y[d]) };
        }
        // The top is an upright device's row where the unit has one: a
        // flat part stands between rows.
        var top: i32 = std.math.maxInt(i32);
        for (devs) |d| if (form[d] == .vertical) {
            top = @min(top, y[d]);
        };
        if (top != std.math.maxInt(i32)) b.lo[1] = top;
        return b;
    }

    fn overlaps(a: Box, b: Box) bool {
        return a.lo[0] <= b.hi[0] and b.lo[0] <= a.hi[0] and a.lo[1] <= b.hi[1] and b.lo[1] <= a.hi[1];
    }
};

/// Moves each unit after the first as line verb `verb` says (units.2).
fn place(gpa: Allocator, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verb: hints.Verb, units: []const []const u32) Allocator.Error!void {
    assert(verb == .row or verb == .order or verb == .repeat);
    if (verb == .repeat) return repeat(gpa, drawn, form, x, y, units);
    for (units[1..], 1..) |u, j| {
        var b: Box = .of(form, x, y, u);
        var dx: i32 = 0;
        var dy: i32 = 0;
        if (verb == .row) {
            // Even: an upright device keeps an even row.
            dy = Box.of(form, x, y, units[0]).lo[1] - b.lo[1];
            dy -= @mod(dy, 2);
            b.lo[1] += dy;
            b.hi[1] += dy;
            // Clear of every unit before it, moving right.
            var moved = true;
            var rounds: usize = 0;
            while (moved) : (rounds += 1) {
                assert(rounds <= units.len);
                moved = false;
                for (units[0..j]) |e| {
                    const other: Box = .of(form, x, y, e);
                    if (!b.overlaps(other)) continue;
                    const step = other.hi[0] + pitch - b.lo[0];
                    dx += step;
                    b.lo[0] += step;
                    b.hi[0] += step;
                    moved = true;
                }
            }
        } else {
            const prev: Box = .of(form, x, y, units[j - 1]);
            dx = @max(0, prev.hi[0] + pitch - b.lo[0]);
        }
        dx += @mod(-dx, pitch);
        const by = try gpa.alloc([2]i32, u.len);
        defer gpa.free(by);
        @memset(by, .{ dx, dy });
        try shift(gpa, drawn, x, y, u, by);
        if (verb == .order) assert(Box.of(form, x, y, u).lo[0] > Box.of(form, x, y, units[j - 1]).hi[0]);
    }
}

/// Lays each unit after the first as the first is laid, member k on the
/// first's member k's cell relative to its box, level with it and right
/// of the unit before (units.4). Asserts the units are of one size.
fn repeat(gpa: Allocator, drawn: []const bool, form: []const Form, x: []i32, y: []i32, units: []const []const u32) Allocator.Error!void {
    const first: Box = .of(form, x, y, units[0]);
    const by = try gpa.alloc([2]i32, units[0].len);
    defer gpa.free(by);
    for (units[1..], 1..) |u, j| {
        assert(u.len == units[0].len);
        var left = Box.of(form, x, y, units[j - 1]).hi[0] + pitch;
        left += @mod(first.lo[0] - left, pitch);
        for (u, units[0], by) |d, model, *b| b.* = .{ x[model] - first.lo[0] + left - x[d], y[model] - y[d] };
        try shift(gpa, drawn, x, y, u, by);
        for (u, units[0]) |d, model| assert(x[d] - left == x[model] - first.lo[0] and y[d] == y[model]);
    }
}

/// Moves each of the devices `devs` by its `by`; a device of no unit
/// within their box, the rows and columns they then span, moves out of it
/// to the nearest free cell of its row (units.1).
fn shift(gpa: Allocator, drawn: []const bool, x: []i32, y: []i32, devs: []const u32, by: []const [2]i32) Allocator.Error!void {
    assert(by.len == devs.len and devs.len > 0);
    var at: std.AutoHashMapUnmanaged([2]i32, u32) = .empty;
    defer at.deinit(gpa);
    for (drawn, 0..) |dr, d| if (dr) try at.put(gpa, .{ x[d], y[d] }, @intCast(d));
    for (devs) |d| _ = at.remove(.{ x[d], y[d] });
    var lo: [2]i32 = .{ std.math.maxInt(i32), std.math.maxInt(i32) };
    var hi: [2]i32 = .{ std.math.minInt(i32), std.math.minInt(i32) };
    for (devs, by) |d, b| {
        x[d] += b[0];
        y[d] += b[1];
        lo = .{ @min(lo[0], x[d]), @min(lo[1], y[d]) };
        hi = .{ @max(hi[0], x[d]), @max(hi[1], y[d]) };
    }
    // The devices in the box, out of the map until they move.
    var out: std.ArrayList(u32) = .empty;
    defer out.deinit(gpa);
    for (drawn, 0..) |dr, e| {
        if (!dr or x[e] < lo[0] or x[e] > hi[0] or y[e] < lo[1] or y[e] > hi[1]) continue;
        if (std.mem.indexOfScalar(u32, devs, @intCast(e)) != null) continue;
        _ = at.remove(.{ x[e], y[e] });
        try out.append(gpa, @intCast(e));
    }
    for (devs) |d| try at.put(gpa, .{ x[d], y[d] }, d);
    for (out.items) |e| {
        const row = y[e];
        var right = hi[0] + 1;
        while (at.contains(.{ right, row })) right += 1;
        var left = lo[0] - 1;
        while (at.contains(.{ left, row })) left -= 1;
        x[e] = if (right - x[e] <= x[e] - left) right else left;
        try at.put(gpa, .{ x[e], row }, e);
    }
    for (drawn, 0..) |dr, d| if (dr) assert(at.get(.{ x[d], y[d] }).? == d);
}
