//! The deck's `cell` lines (steering rung 3): a device's lattice cell, in the
//! skeleton's own frame (before it shifts the drawing to start at 0, so
//! moving one device renumbers nothing). In: the skeleton's cells as the
//! rest of placement leaves them. Out: the named devices on their cells, the
//! devices they displaced on the nearest free cell of their row, the mates
//! no longer mirrored dropped, and a verdict per line.
//!
//! Lines are admitted strongest first (`hints.admitOrder`): a cell a
//! stronger line holds, or a device it placed, drops the line, blocked by
//! it; the engine's own cells give way. A line on one of a mated pair puts
//! the unnamed mate on the mirror cell (the core stands about x = 0 here).
//!
//! Contents:
//! - `pub fn apply(gpa: Allocator, arena: Allocator, nl: *const Netlist, drawn: []const bool, mate: []u32, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const hints = @import("hints.zig");
const structure = @import("structure.zig");

const Netlist = netlist.Netlist;
const Verdict = hints.Verdict;
const none = structure.none;

/// Places each `cell` line's device; see the module comment.
pub fn apply(gpa: Allocator, arena: Allocator, nl: *const Netlist, drawn: []const bool, mate: []u32, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void {
    const n = x.len;
    assert(y.len == n and mate.len == n and drawn.len == n);
    // Each line's device and cell, once valid.
    const want = try arena.alloc(?struct { d: u32, at: [2]i32 }, nl.hints.len);
    @memset(want, null);
    const named = try gpa.alloc(bool, n);
    defer gpa.free(named);
    @memset(named, false);
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .cell) continue;
        if (h.args.len != 3) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        const d = (nl.device(h.args[0]) orelse {
            verdicts[i] = reject(.unknown_name);
            continue;
        }).index();
        if (!drawn[d]) {
            verdicts[i] = reject(.not_placeable);
            continue;
        }
        const col = hints.int(h.args[1]);
        const row = hints.int(h.args[2]);
        if (col == null or row == null) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        want[i] = .{ .d = @intCast(d), .at = .{ col.?, row.? } };
        named[d] = true;
    }
    // The line that fixed each device, and the cells taken.
    const fixed = try gpa.alloc(u32, n);
    defer gpa.free(fixed);
    @memset(fixed, none);
    var at: std.AutoHashMapUnmanaged([2]i32, u32) = .empty;
    defer at.deinit(gpa);
    for (0..n) |d| if (drawn[d]) try at.put(gpa, .{ x[d], y[d] }, @intCast(d));
    for (try hints.admitOrder(arena, nl.hints)) |i| {
        const w = want[i] orelse continue;
        const holder = if (fixed[w.d] != none) fixed[w.d] else if (at.get(w.at)) |e| (if (e != w.d) fixed[e] else none) else none;
        if (holder != none) {
            verdicts[i] = .{ .state = .dropped, .code = .conflict, .blocked_by = try arena.dupe(u32, &.{holder}), .alone = try arena.dupe(bool, &.{true}) };
            continue;
        }
        try put(gpa, &at, drawn, x, y, w.d, w.at);
        fixed[w.d] = i;
        verdicts[i] = .{ .state = .honoured, .code = .ok };
        // The unnamed mate, on the mirror cell when nothing stronger is there.
        const m = mate[w.d];
        if (m == none or m == w.d or named[m] or fixed[m] != none or !drawn[m]) continue;
        const image: [2]i32 = .{ -w.at[0], w.at[1] };
        if (at.get(image)) |e| if (e != m and fixed[e] != none) continue;
        try put(gpa, &at, drawn, x, y, m, image);
        fixed[m] = i;
    }
    // Mates a line moved off their mirror are mates no more; a device on
    // the axis is its own mate, its mirror cell its own at x = 0.
    for (mate, 0..) |*m, d| {
        if (m.* == none or @as(i64, x[d]) + x[m.*] == 0) continue;
        mate[m.*] = none;
        m.* = none;
    }
    for (0..n) |d| if (drawn[d]) assert(at.get(.{ x[d], y[d] }).? == d);
}

// ---- private ----

fn reject(code: hints.Code) Verdict {
    return .{ .state = .rejected, .code = code };
}

/// Moves device `d` to cell `to`; a device there moves to the nearest free
/// cell of its row.
fn put(gpa: Allocator, at: *std.AutoHashMapUnmanaged([2]i32, u32), drawn: []const bool, x: []i32, y: []i32, d: u32, to: [2]i32) !void {
    assert(drawn[d]);
    if (x[d] == to[0] and y[d] == to[1]) return;
    _ = at.remove(.{ x[d], y[d] });
    if (at.get(to)) |e| {
        assert(e != d);
        _ = at.remove(to);
        var step: i32 = 1;
        while (true) : (step += 1) {
            assert(step <= @as(i32, @intCast(2 * x.len + 2)));
            const right: [2]i32 = .{ to[0] + step, to[1] };
            const left: [2]i32 = .{ to[0] - step, to[1] };
            const free: ?[2]i32 = if (!at.contains(right)) right else if (!at.contains(left)) left else null;
            if (free) |f| {
                x[e] = f[0];
                y[e] = f[1];
                try at.put(gpa, f, e);
                break;
            }
        }
    }
    x[d] = to[0];
    y[d] = to[1];
    try at.put(gpa, to, d);
}
