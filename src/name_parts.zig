//! A net joined by name (style `cut`, `netlines.zig`), drawn in parts. In:
//! the canvas and the net's pins. Out: each part's trunk with one name, or
//! names at pins.
//!
//! Human Rules:
//! - name_parts.1 (habit) A net joined by name falls into parts, each pin no
//!   farther from another of its part (along x plus along y) than 15, 11
//!   or 6 half units as neither, one or both of the two face sideways.
//!   People: fitted on the connections people wire and name in 5,274
//!   hand-drawn schematics (93.6% of nets right on those held out).
//!   `within`
//! - name_parts.2 (unmeasured) Each part of two pins or more of a net joined
//!   by name is one trunk with one name at a free end; a part no trunk
//!   fits is wired two near pins at a time, the nearest pair first, where
//!   a trunk fits the pair; a pin alone, or one no pair's trunk took,
//!   carries the name. `draw`
//! - name_parts.3 (choice) A net joined by name that is all one part is named
//!   at every pin (name_parts.4): it was cut because its one wire crossed
//!   too much. `draw`
//! - name_parts.4 (invariant) A net the engine names at its pins (`thin.zig`;
//!   a `label <net>` line keeps every pin apart) first joins each two
//!   pins facing each other on one row or column, with nothing between
//!   them and no wire across, by that straight wire; then each wired
//!   island carries one name: at its first wire's middle, its text
//!   across the wire, else at its top-left pin. Near
//!   pins stay wired, and two facing pins never write two names on one
//!   point. `atPins`
//!
//! Contents:
//! - `pub fn draw(c: *Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) Allocator.Error!void`
//! - `pub fn atPins(c: *Canvas, net: u32, pins: []const u32, join: bool) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const canvas = @import("canvas.zig");
const trunk = @import("trunk.zig");
const ct_controls = @import("ct_controls.zig");
const Netlist = @import("netlist.zig").Netlist;
const NetLines = @import("netlines.zig").NetLines;
const Requests = @import("wire_requests.zig").Requests;

const Canvas = canvas.Canvas;
const Pt = @import("library.zig").Pt;
const pinAt = canvas.pinAt;

/// The longest connection kept as wire in a net joined by name, in half
/// units, by how many of its two pins face sideways (a gate, a base):
/// neither, one, both. Fitted on the connections people wire and name in
/// 5,274 hand-drawn schematics (93.6% of nets right on those held out).
const cut = [3]u32{ 15, 11, 6 };

/// A net joined by name between its parts: the pins standing near each
/// other (each within `cut` of another of its part) on one trunk with one
/// name; a pin on its own, or a part no trunk fits, a name at each pin.
pub fn draw(c: *Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) Allocator.Error!void {
    assert(pins.len >= 1);
    const gpa = c.gpa;
    // Each pin's part: the least index of a pin in it.
    const part = try gpa.alloc(u32, pins.len);
    defer gpa.free(part);
    for (part, 0..) |*g, i| g.* = @intCast(i);
    if (ct_controls.adjacent(c, nl, net, pins, lines, requests)) |pair| part[pair[1]] = pair[0];
    var merged = true;
    var rounds: usize = 0;
    while (merged) : (rounds += 1) {
        assert(rounds <= pins.len); // every round but the last joins two parts
        merged = false;
        for (pins, 0..) |p, i| for (pins[i + 1 ..], i + 1..) |q, j| {
            if (part[i] == part[j] or !within(c, p, q)) continue;
            const keep = @min(part[i], part[j]);
            const drop = @max(part[i], part[j]);
            for (part) |*g| {
                if (g.* == drop) g.* = keep;
            }
            merged = true;
        };
    }
    // One part is the whole net, the wire that crossed too much: names.
    if (std.mem.allEqual(u32, part, 0)) return atPins(c, net, pins, true);
    var members: std.ArrayList(u32) = .empty;
    defer members.deinit(gpa);
    for (0..pins.len) |g| {
        members.clearRetainingCapacity();
        for (pins, part) |p, of| {
            if (of == g) try members.append(gpa, p);
        }
        if (members.items.len == 0) continue;
        if (members.items.len >= 2 and try trunk.draw(c, net, members.items, .name)) continue;
        try nearPairs(c, net, members.items);
    }
}

/// Names `pins` of `net`, one name a wired island: with `join`, each two
/// pins facing each other on one row or column, nothing between them and
/// no wire across, first joined by that straight wire, its name at the
/// wire's middle (name_parts.4); without, a name at each pin, never two on
/// one point (canvas.9), as a `label <net>` line asks.
pub fn atPins(c: *Canvas, net: u32, pins: []const u32, join: bool) Allocator.Error!void {
    assert(pins.len >= 1);
    const gpa = c.gpa;
    // Each pin's island: the least index of a pin in it, and the middle of
    // its first wire, where its name goes.
    const island = try gpa.alloc(u32, pins.len);
    defer gpa.free(island);
    const middle = try gpa.alloc(?Pt, pins.len);
    defer gpa.free(middle);
    for (island, middle, 0..) |*g, *m, i| {
        g.* = @intCast(i);
        m.* = null;
    }
    for (pins, 0..) |p, i| for (pins[i + 1 ..], i + 1..) |q, j| {
        if (!join or island[i] == island[j] or !facing(c, p, q)) continue;
        const a = pinAt(c.s, p);
        const b = pinAt(c.s, q);
        if (c.crossed(net, a, b)) continue;
        const m = midway(a, b);
        const path: []const Pt = if (m) |at| &.{ a, at, b } else &.{ a, b };
        if (!try c.commit(net, path)) continue;
        const keep = @min(island[i], island[j]);
        const drop = @max(island[i], island[j]);
        middle[keep] = middle[keep] orelse middle[drop] orelse m;
        for (island) |*g| {
            if (g.* == drop) g.* = keep;
        }
    };
    var members: std.ArrayList(u32) = .empty;
    defer members.deinit(gpa);
    for (island, middle, 0..) |root, mid, i| {
        if (root != i) continue;
        if (mid) |at| {
            // Its text across the wire: above a level one, right of an
            // upright one.
            const level = c.s.pins.items(.side)[pins[i]].isHorizontal();
            try c.leaf(.label, net, at, if (level) .down else .left);
            continue;
        }
        members.clearRetainingCapacity();
        for (pins, island) |p, g| if (g == root) try members.append(gpa, p);
        assert(members.items.len >= 1);
        try c.labelAt(members.items[canvas.topLeft(c.s, members.items)]);
    }
}

// ---- private ----

/// Whether pins `p` and `q` stand on one row or column, each facing the
/// other.
fn facing(c: *const Canvas, p: u32, q: u32) bool {
    const a = pinAt(c.s, p);
    const b = pinAt(c.s, q);
    if (a.eql(b) or (a.x != b.x and a.y != b.y)) return false;
    const toward: Pt = .{ .x = std.math.sign(b.x - a.x), .y = std.math.sign(b.y - a.y) };
    const sides = c.s.pins.items(.side);
    return sides[p].unit().eql(toward) and sides[q].unit().eql(.{ .x = -toward.x, .y = -toward.y });
}

/// The whole point halfway along straight wire `a`-`b`, as a bias's gate
/// line takes its port (wires.11); null when none lies strictly between.
fn midway(a: Pt, b: Pt) ?Pt {
    assert(a.x == b.x or a.y == b.y);
    const m: Pt = .{ .x = @divFloor(a.x + b.x, 2), .y = @divFloor(a.y + b.y, 2) };
    return if (m.eql(a) or m.eql(b)) null else m;
}

/// A part of a net joined by name that no one trunk fits: its near pins
/// (`within`) two by two, the nearest pair first, each pair a trunk fits
/// one wire with one name; any other pin a name.
fn nearPairs(c: *Canvas, net: u32, members: []const u32) !void {
    const gpa = c.gpa;
    const Pair = struct { far: i32, i: u32, j: u32 };
    var near_pairs: std.ArrayList(Pair) = .empty;
    defer near_pairs.deinit(gpa);
    for (members, 0..) |p, i| for (members[i + 1 ..], i + 1..) |q, j| {
        if (!within(c, p, q)) continue;
        const a = pinAt(c.s, p);
        const b = pinAt(c.s, q);
        try near_pairs.append(gpa, .{ .far = @intCast(@abs(a.x - b.x) + @abs(a.y - b.y)), .i = @intCast(i), .j = @intCast(j) });
    };
    std.sort.insertion(Pair, near_pairs.items, {}, struct {
        fn lt(_: void, x: Pair, y: Pair) bool {
            return if (x.far != y.far) x.far < y.far else if (x.i != y.i) x.i < y.i else x.j < y.j;
        }
    }.lt);
    const wired = try gpa.alloc(bool, members.len);
    defer gpa.free(wired);
    @memset(wired, false);
    for (near_pairs.items) |pr| {
        if (wired[pr.i] or wired[pr.j]) continue;
        if (!try trunk.draw(c, net, &.{ members[pr.i], members[pr.j] }, .name)) continue;
        wired[pr.i] = true;
        wired[pr.j] = true;
    }
    var alone: std.ArrayList(u32) = .empty;
    defer alone.deinit(gpa);
    for (members, wired) |p, w| if (!w) try alone.append(gpa, p);
    if (alone.items.len != 0) try atPins(c, net, alone.items, true);
}

/// Whether two pins of a net stand near enough to stay wired when the net
/// is joined by name: the connections people keep (`cut`).
fn within(c: *const Canvas, p: u32, q: u32) bool {
    const a = pinAt(c.s, p);
    const b = pinAt(c.s, q);
    const sides = c.s.pins.items(.side);
    const sideways = @as(usize, @intFromBool(sides[p].isHorizontal())) + @intFromBool(sides[q].isHorizontal());
    return 2 * (@abs(a.x - b.x) + @abs(a.y - b.y)) <= cut[sideways] * @as(u32, @intCast(c.len.unit));
}

test {
    _ = @import("name_parts_test.zig");
}
