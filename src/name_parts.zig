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
//!   at every pin: it was cut because its one wire crossed too much.
//!   `draw`
//!
//! Contents:
//! - `pub fn draw(c: *Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) Allocator.Error!void`

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
    if (std.mem.allEqual(u32, part, 0)) {
        for (pins) |p| try c.labelAt(p);
        return;
    }
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

// ---- private ----

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
    for (members, wired) |p, w| if (!w) try c.labelAt(p);
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
