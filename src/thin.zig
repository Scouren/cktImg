//! Thinning (stage 4): the nets whose wires cross too many others, drawn
//! in parts joined by name instead. In: the drawing's routes, the nets'
//! roles and how the deck's lines style each net. Out: the style of each
//! net it thins set to `cut`, or `label` if it was `cut` already; the
//! caller wires the drawing again.
//!
//! Human Rules:
//! - thin.1 (habit) No internal net's wire crosses more than `max` wires
//!   of other nets: past that the net is joined by name. People: of 43,282
//!   wired nets in 5,263 hand-drawn reference schematics (Analog Canvas
//!   gallery), 423 cross more than two others. `name`
//! - thin.2 (habit) A net over the budget is first `cut`: each group of
//!   near pins on one wire, one name a group (`wires.zig`). People: 75% of
//!   their named nets keep the pins that stand near each other wired.
//!   `name`
//! - thin.3 (choice) A `cut` net is named at every pin only when one
//!   physical part still crosses more than two other wires. Disconnected
//!   parts do not pool their budgets (AG2309/2318/2319). Route chunks
//!   meeting at an endpoint, T, overlap or same-net X form one part:
//!   `dots.2` puts a junction at the X. `name`
//! - thin.4 (book) A rail's wires are not counted: a gate line crosses the
//!   stubs up to the supply bar. Razavi Fig. 12.20. `name`
//! - thin.5 (choice) The net crossing the most wires goes first (on a tie,
//!   the first in the nets' canonical order), and the crossings are
//!   counted again without it, until none is over. Total crossings still
//!   rank eligible nets, including `cut` nets; the order of the cards
//!   chooses nothing. `name`
//! - thin.6 (invariant) A rail, a port and a net a deck line styles keep
//!   their wires: only internal nets the deck's lines leave to the engine
//!   are thinned. `steps`
//! - thin.7 (invariant) A thinned net's mirror image goes with it, so a
//!   mirrored drawing stays mirrored. `name`
//!
//! Contents:
//! - `pub fn name(gpa: Allocator, routes: []const Route, roles: []const Role, rank: []const u32, net_mate: ?[]const u32, max: u32, style: []Style) Allocator.Error!bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const sch = @import("schematic.zig");
const netlines = @import("netlines.zig");

const Route = sch.Route;
const Role = sch.Role;
const Style = netlines.Style;
const none = sch.none;

/// The most other wires one physical part of a `cut` net may cross.
const cut_max = 2;

/// Takes each net whose wires in `routes` cross more than `max` wires of
/// other nets (rails aside) one step further from a whole wire, the worst
/// first (on a tie the net first in `rank`, the nets' canonical order, so
/// the order of the cards chooses nothing), counting again without it:
/// `auto` to `cut`, a net already `cut` to `label`; and its image in
/// `net_mate` with it. A `cut` net qualifies only when one connected part
/// exceeds `cut_max`; its total crossings still rank it. Routes must be
/// Manhattan polylines of two to six points with valid net handles.
/// Returns whether any style changed. `gpa` backs temporary work; all
/// fallible work precedes style changes, so an error leaves styles intact.
pub fn name(gpa: Allocator, routes: []const Route, roles: []const Role, rank: []const u32, net_mate: ?[]const u32, max: u32, style: []Style) Allocator.Error!bool {
    assert(roles.len == style.len and rank.len == style.len);
    const has_cut = for (style) |s| {
        if (s == .cut) break true;
    } else false;
    // Route handles have the slice's usize range. Each row is contiguous;
    // joined rows share a root. No component work is needed for auto nets.
    const parent = try gpa.alloc(usize, if (has_cut) routes.len else 0);
    defer gpa.free(parent);
    for (parent, 0..) |*p, i| p.* = i;
    for (routes) |r| {
        assert(r.net < style.len);
        assert(r.len >= 2 and r.len <= r.pts.len);
        for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |a, b| assert(a[0] == b[0] or a[1] == b[1]);
    }
    // One pair of route handles per existing strict crossing occurrence.
    // Route identity also gives each crossing its physical component.
    var pairs: std.ArrayList([2]usize) = .empty;
    defer pairs.deinit(gpa);
    for (routes, 0..) |r, i| for (routes[i + 1 ..], i + 1..) |q, j| {
        if (r.net == q.net) {
            if (style[r.net] == .cut and touches(r, q)) {
                const a = root(parent, i);
                const b = root(parent, j);
                parent[@max(a, b)] = @min(a, b);
            }
            continue;
        }
        if (roles[r.net].isRail() or roles[q.net].isRail()) continue;
        for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |a, b| for (q.pts[0 .. q.len - 1], q.pts[1..q.len]) |c, d| {
            if (crosses(a, b, c, d) or crosses(c, d, a, b)) try pairs.append(gpa, .{ i, j });
        };
    };
    for (parent, 0..) |*p, i| p.* = root(parent, i);
    // Eligibility needs only 0..cut_max+1; saturation at three is exact.
    comptime assert(cut_max + 1 == std.math.maxInt(u2));
    const part_count = try gpa.alloc(u2, parent.len);
    defer gpa.free(part_count);
    const peak = try gpa.alloc(u2, if (has_cut) style.len else 0);
    defer gpa.free(peak);
    const count = try gpa.alloc(u32, style.len);
    defer gpa.free(count);
    // Nets taken a step here: out of the count, and not taken twice.
    const gone = try gpa.alloc(bool, style.len);
    defer gpa.free(gone);
    @memset(gone, false);
    var any = false;
    for (0..style.len) |_| {
        @memset(count, 0);
        @memset(part_count, 0);
        @memset(peak, 0);
        for (pairs.items) |p| {
            if (gone[routes[p[0]].net] or gone[routes[p[1]].net]) continue;
            for (p) |r| {
                const net = routes[r].net;
                count[net] += 1;
                if (style[net] == .cut) {
                    const part = parent[r];
                    part_count[part] +|= 1;
                    peak[net] = @max(peak[net], part_count[part]);
                }
            }
        }
        var worst: u32 = none;
        for (count, 0..) |k, net| {
            if (!steps(roles[net], style[net], gone[net])) continue;
            if (if (style[net] == .cut) peak[net] <= cut_max else k <= max) continue;
            if (worst == none or k > count[worst] or (k == count[worst] and rank[net] < rank[worst])) worst = @intCast(net);
        }
        if (worst == none) break;
        any = true;
        for ([_]u32{ worst, if (net_mate) |m| m[worst] else none }) |net| {
            if (net == none or !steps(roles[net], style[net], gone[net])) continue;
            style[net] = if (style[net] == .auto) .cut else .label;
            gone[net] = true;
        }
    }
    return any;
}

// ---- private ----

fn root(parent: []usize, i: usize) usize {
    assert(i < parent.len);
    var at = i;
    while (parent[at] != at) {
        assert(parent[at] < at); // Every link descends: at most parent.len steps.
        parent[at] = parent[parent[at]];
        at = parent[at];
    }
    return at;
}

/// Inclusive Manhattan contact, including the X junctions drawn by dots.2.
fn touches(r: Route, q: Route) bool {
    assert(r.net == q.net);
    assert(r.len >= 2 and q.len >= 2);
    for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |a, b| for (q.pts[0 .. q.len - 1], q.pts[1..q.len]) |c, d| {
        if (@max(@min(a[0], b[0]), @min(c[0], d[0])) <= @min(@max(a[0], b[0]), @max(c[0], d[0])) and
            @max(@min(a[1], b[1]), @min(c[1], d[1])) <= @min(@max(a[1], b[1]), @max(c[1], d[1]))) return true;
    };
    return false;
}

/// Whether a net may go a step further from a whole wire: an internal net
/// the deck's lines leave to the engine, once a call.
fn steps(role: Role, style: Style, gone: bool) bool {
    return role == .internal and !gone and (style == .auto or style == .cut);
}

/// Whether level wire `a`-`b` and upright wire `c`-`d` cross inside both.
fn crosses(a: [2]f32, b: [2]f32, c: [2]f32, d: [2]f32) bool {
    if (a[1] != b[1] or c[0] != d[0]) return false;
    return c[0] > @min(a[0], b[0]) and c[0] < @max(a[0], b[0]) and a[1] > @min(c[1], d[1]) and a[1] < @max(c[1], d[1]);
}

test {
    _ = @import("thin_parts_test.zig");
}

test "name: the net crossing the most wires is named first, and the count taken again" {
    // Oracle: worked by hand. Net 0 runs level through the uprights of
    // nets 1, 2 and 3; net 4 runs level through net 1's only.
    const gpa = std.testing.allocator;
    const level = struct {
        fn f(net: u32, y: f32) Route {
            var r: Route = .{ .pts = undefined, .len = 2, .net = net };
            r.pts[0] = .{ 0, y };
            r.pts[1] = .{ 40, y };
            return r;
        }
    }.f;
    const upright = struct {
        fn f(net: u32, x: f32, y1: f32) Route {
            var r: Route = .{ .pts = undefined, .len = 2, .net = net };
            r.pts[0] = .{ x, 0 };
            r.pts[1] = .{ x, y1 };
            return r;
        }
    }.f;
    const routes = [_]Route{ level(0, 5), upright(1, 10, 30), upright(2, 20, 10), upright(3, 30, 10), level(4, 20) };
    const roles: [5]Role = @splat(.internal);
    const rank = [5]u32{ 0, 1, 2, 3, 4 };
    var style: [5]Style = @splat(.auto);
    // Net 0 crosses three wires, net 1 two, the rest one each.
    try std.testing.expect(!try name(gpa, &routes, &roles, &rank, null, 3, &style));
    try std.testing.expect(try name(gpa, &routes, &roles, &rank, null, 2, &style));
    try std.testing.expectEqualSlices(Style, &.{ .cut, .auto, .auto, .auto, .auto }, &style);
    // Still over when counted again (the same wires): named at every pin.
    try std.testing.expect(try name(gpa, &routes, &roles, &rank, null, 2, &style));
    try std.testing.expectEqualSlices(Style, &.{ .label, .auto, .auto, .auto, .auto }, &style);
    // A budget of one: net 0 goes, and net 1 then crosses net 4 alone.
    style = @splat(.auto);
    try std.testing.expect(try name(gpa, &routes, &roles, &rank, null, 1, &style));
    try std.testing.expectEqualSlices(Style, &.{ .cut, .auto, .auto, .auto, .auto }, &style);
    // None: net 0, then net 1 (or 4: the first in rank on a tie).
    style = @splat(.auto);
    try std.testing.expect(try name(gpa, &routes, &roles, &rank, null, 0, &style));
    try std.testing.expectEqualSlices(Style, &.{ .cut, .cut, .auto, .auto, .auto }, &style);
    // The rank breaks the tie, not the net's number: the same deck with
    // its cards in another order numbers its nets otherwise.
    style = @splat(.auto);
    try std.testing.expect(try name(gpa, &routes, &roles, &.{ 0, 4, 2, 3, 1 }, null, 0, &style));
    try std.testing.expectEqualSlices(Style, &.{ .cut, .auto, .auto, .auto, .cut }, &style);
    // A net a line wires keeps its wire.
    style = .{ .wire, .auto, .auto, .auto, .auto };
    try std.testing.expect(!try name(gpa, &routes, &roles, &rank, null, 2, &style));
    // Crossing a rail's wire costs nothing: net 0 crosses two others.
    style = @splat(.auto);
    try std.testing.expect(!try name(gpa, &routes, &.{ .internal, .supply, .internal, .internal, .internal }, &rank, null, 2, &style));
}
