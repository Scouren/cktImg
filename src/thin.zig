//! Thinning (stage 4): the nets whose wires cross too many others, drawn
//! in parts joined by name instead. In: the drawing's routes, the nets'
//! roles and how the deck's lines style each net. Out: the style of each
//! net it thins set to `cut`, or `label` if it was `cut` already; the
//! caller wires the drawing again.
//!
//! A person's drawing seldom lets one net's wire cross more than two others
//! (of 43,282 wired nets in 5,263 hand-drawn reference schematics, Analog
//! Canvas gallery, 423 do): past that the net is joined by name. And a
//! person cuts only the far connection: 75% of their named nets keep the
//! pins that stand near each other wired. So a net over the budget is first
//! `cut` (`wires.zig`: each group of near pins on one wire, one name a
//! group), and named at every pin only if its parts still cross too much.
//! The net crossing the most wires goes first, and the crossings are
//! counted again without it, until none is over. Only internal nets the
//! deck's lines leave to the engine: a rail, a port and a net a line wires
//! keep theirs. A rail's wires are not counted: a gate line crosses the
//! stubs up to the supply bar as the book draws it (Razavi Fig. 12.20). A
//! thinned net's mirror image goes with it.
//!
//! Contents:
//! - `pub fn name(gpa: Allocator, routes: []const Route, roles: []const Role, net_mate: ?[]const u32, max: u32, style: []Style) Allocator.Error!bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const sch = @import("schematic.zig");
const netlines = @import("netlines.zig");

const Route = sch.Route;
const Role = sch.Role;
const Style = netlines.Style;
const none = sch.none;

/// The most other wires the parts of a `cut` net may cross.
const cut_max = 2;

/// Takes each net whose wires in `routes` cross more than `max` wires of
/// other nets (rails aside) one step further from a whole wire, the worst
/// first (the lower net on a tie), counting again without it: `auto` to
/// `cut`, a net already `cut` to `label`; and its image in `net_mate` with
/// it. Whether any was. `gpa` backs the work.
pub fn name(gpa: Allocator, routes: []const Route, roles: []const Role, net_mate: ?[]const u32, max: u32, style: []Style) Allocator.Error!bool {
    assert(roles.len == style.len);
    // One entry per point where two nets' wires cross.
    var pairs: std.ArrayList([2]u32) = .empty;
    defer pairs.deinit(gpa);
    for (routes, 0..) |r, i| for (routes[i + 1 ..]) |q| {
        if (r.net == q.net or rail(roles[r.net]) or rail(roles[q.net])) continue;
        for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |a, b| for (q.pts[0 .. q.len - 1], q.pts[1..q.len]) |c, d| {
            if (crosses(a, b, c, d) or crosses(c, d, a, b)) try pairs.append(gpa, .{ r.net, q.net });
        };
    };
    const count = try gpa.alloc(u32, style.len);
    defer gpa.free(count);
    // Nets taken a step here: out of the count, and not taken twice.
    const gone = try gpa.alloc(bool, style.len);
    defer gpa.free(gone);
    @memset(gone, false);
    var any = false;
    for (0..style.len) |_| {
        @memset(count, 0);
        for (pairs.items) |p| if (!gone[p[0]] and !gone[p[1]]) {
            count[p[0]] += 1;
            count[p[1]] += 1;
        };
        var worst: u32 = none;
        for (count, 0..) |k, net| {
            if (k <= (if (style[net] == .cut) cut_max else max) or !steps(roles[net], style[net], gone[net])) continue;
            if (worst == none or k > count[worst]) worst = @intCast(net);
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

/// Whether a net may go a step further from a whole wire: an internal net
/// the deck's lines leave to the engine, once a call.
fn steps(role: Role, style: Style, gone: bool) bool {
    return role == .internal and !gone and (style == .auto or style == .cut);
}

fn rail(role: Role) bool {
    return role == .supply or role == .sink;
}

/// Whether level wire `a`-`b` and upright wire `c`-`d` cross inside both.
fn crosses(a: [2]f32, b: [2]f32, c: [2]f32, d: [2]f32) bool {
    if (a[1] != b[1] or c[0] != d[0]) return false;
    return c[0] > @min(a[0], b[0]) and c[0] < @max(a[0], b[0]) and a[1] > @min(c[1], d[1]) and a[1] < @max(c[1], d[1]);
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
    var style: [5]Style = @splat(.auto);
    // Net 0 crosses three wires, net 1 two, the rest one each.
    try std.testing.expect(!try name(gpa, &routes, &roles, null, 3, &style));
    try std.testing.expect(try name(gpa, &routes, &roles, null, 2, &style));
    try std.testing.expectEqualSlices(Style, &.{ .cut, .auto, .auto, .auto, .auto }, &style);
    // Still over when counted again (the same wires): named at every pin.
    try std.testing.expect(try name(gpa, &routes, &roles, null, 2, &style));
    try std.testing.expectEqualSlices(Style, &.{ .label, .auto, .auto, .auto, .auto }, &style);
    // A budget of one: net 0 goes, and net 1 then crosses net 4 alone.
    style = @splat(.auto);
    try std.testing.expect(try name(gpa, &routes, &roles, null, 1, &style));
    try std.testing.expectEqualSlices(Style, &.{ .cut, .auto, .auto, .auto, .auto }, &style);
    // None: net 0, then net 1 (or 4: the lower on a tie).
    style = @splat(.auto);
    try std.testing.expect(try name(gpa, &routes, &roles, null, 0, &style));
    try std.testing.expectEqualSlices(Style, &.{ .cut, .cut, .auto, .auto, .auto }, &style);
    // A net a line wires keeps its wire.
    style = .{ .wire, .auto, .auto, .auto, .auto };
    try std.testing.expect(!try name(gpa, &routes, &roles, null, 2, &style));
    // Crossing a rail's wire costs nothing: net 0 crosses two others.
    style = @splat(.auto);
    try std.testing.expect(!try name(gpa, &routes, &.{ .internal, .supply, .internal, .internal, .internal }, null, 2, &style));
}
