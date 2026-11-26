//! Visible-crossing multiplicity regressions.
//! Oracle: literal Manhattan ink, independently counted by crossing location
//! and unordered net pair. Duplicating or overlapping a stroke adds no visible
//! crossing. Distinct crossing sites remain distinct. This does not broaden
//! the existing strict-interior policy at route segment endpoints.
//!
//! Contents: tests only; duplicate-counting failures were recorded before repair.

const std = @import("std");
const thin = @import("thin.zig");
const sch = @import("schematic.zig");
const Style = @import("netlines.zig").Style;
const Route = sch.Route;
const P = [2]f32;

// ---- private ----

fn wire(net: u32, points: []const P) Route {
    std.debug.assert(points.len >= 2 and points.len <= 6);
    var result: Route = .{ .net = net, .len = @intCast(points.len), .pts = undefined };
    @memcpy(result.pts[0..points.len], points);
    return result;
}

fn expect(routes: []const Route, before: []const Style, after: []const Style, ranks: []const u32) !void {
    const gpa = std.testing.allocator;
    const styles = try gpa.dupe(Style, before);
    defer gpa.free(styles);
    const roles = try gpa.alloc(sch.Role, before.len);
    defer gpa.free(roles);
    @memset(roles, .internal);
    const changed = try thin.name(gpa, routes, roles, ranks, null, 2, styles);
    try std.testing.expectEqual(!std.mem.eql(Style, before, after), changed);
    try std.testing.expectEqualSlices(Style, after, styles);
}

fn two() [3]Route {
    return .{
        wire(0, &.{ .{ 0, 0 }, .{ 0, 100 } }),
        wire(1, &.{ .{ -10, 30 }, .{ 10, 30 } }),
        wire(2, &.{ .{ -10, 70 }, .{ 10, 70 } }),
    };
}

fn allocationFailure(gpa: std.mem.Allocator) !void {
    const base = two();
    const routes = base ++ [_]Route{wire(0, &.{ .{ 0, 20 }, .{ 0, 80 } })};
    const initial = [_]Style{ .cut, .wire, .wire };
    var styles = initial;
    const changed = thin.name(gpa, &routes, &.{ .internal, .internal, .internal }, &.{ 0, 1, 2 }, null, 2, &styles) catch |err| {
        try std.testing.expectEqualSlices(Style, &initial, &styles);
        return err;
    };
    try std.testing.expect(!changed);
    try std.testing.expectEqualSlices(Style, &initial, &styles);
}

// ---- tests ----

test "thin crossing sites: duplicate partial-overlap reflection and reversal preserve both budgets" {
    // Exactly two visible sites: (0,30) against net1 and (0,70) against net2.
    // Each variant duplicates one or both sites using the same physical ink.
    const base = two();
    const extras = [_]Route{
        base[0],
        wire(0, &.{ .{ 0, 20 }, .{ 0, 80 } }),
        wire(0, &.{ .{ 0, 20 }, .{ 0, 50 } }),
        base[1],
        wire(1, &.{ .{ -5, 30 }, .{ 5, 30 } }),
    };
    for (extras) |extra| {
        var routes = base ++ [_]Route{extra};
        for (0..2) |pass| {
            if (pass == 1) {
                for (&routes) |*r| {
                    for (r.pts[0..r.len]) |*p| p.* = .{ 50 - p[0], 200 - p[1] };
                    std.mem.reverse(P, r.pts[0..r.len]);
                }
                std.mem.reverse(Route, &routes);
            }
            for ([_]Style{ .auto, .cut }) |mode| {
                const styles = [_]Style{ mode, .wire, .wire };
                try expect(&routes, &styles, &styles, &.{ 0, 1, 2 });
            }
        }
    }
}

test "thin crossing sites: retraced segments within one route do not create crossings" {
    var routes = two();
    routes[0] = wire(0, &.{ .{ 0, 0 }, .{ 0, 100 }, .{ 0, 20 }, .{ 0, 80 } });
    routes[1] = wire(1, &.{ .{ -10, 30 }, .{ 10, 30 }, .{ -5, 30 }, .{ 5, 30 } });
    try expect(&routes, &.{ .auto, .wire, .wire }, &.{ .auto, .wire, .wire }, &.{ 0, 1, 2 });
    try expect(&routes, &.{ .cut, .wire, .wire }, &.{ .cut, .wire, .wire }, &.{ 0, 1, 2 });
}

test "thin crossing sites: separate sites against one foreign net still exceed the budget" {
    // A comb crosses one vertical at three different visible positions.
    const routes = [_]Route{
        wire(0, &.{ .{ 0, 0 }, .{ 0, 100 } }),
        wire(1, &.{ .{ -10, 20 }, .{ 10, 20 }, .{ 10, 50 }, .{ -10, 50 }, .{ -10, 80 }, .{ 10, 80 } }),
    };
    try expect(&routes, &.{ .auto, .wire }, &.{ .cut, .wire }, &.{ 0, 1 });
    try expect(&routes, &.{ .cut, .wire }, &.{ .label, .wire }, &.{ 0, 1 });
}

test "thin crossing sites: greedy rank uses visible sites rather than duplicated occurrences" {
    // A crosses B,C,D at three sites. B also crosses E: two sites total.
    // Duplicating B falsely ties A and B at four; B has earlier canonical
    // rank, so occurrence counting picks B instead of the truly worst A.
    const routes = [_]Route{
        wire(0, &.{ .{ 0, 0 }, .{ 40, 0 } }),
        wire(1, &.{ .{ 10, -10 }, .{ 10, 10 } }),
        wire(2, &.{ .{ 20, -10 }, .{ 20, 10 } }),
        wire(3, &.{ .{ 30, -10 }, .{ 30, 10 } }),
        wire(4, &.{ .{ 0, 5 }, .{ 15, 5 } }),
        wire(1, &.{ .{ 10, -10 }, .{ 10, 10 } }),
    };
    try expect(&routes, &.{ .auto, .auto, .wire, .wire, .wire }, &.{ .cut, .auto, .wire, .wire, .wire }, &.{ 1, 0, 2, 3, 4 });
    try expect(&routes, &.{ .cut, .cut, .wire, .wire, .wire }, &.{ .label, .cut, .wire, .wire, .wire }, &.{ 1, 0, 2, 3, 4 });
}

test "thin crossing sites: foreign endpoint contact keeps strict-interior semantics" {
    // Three foreign wires terminate on A; none passes through it.
    const routes = [_]Route{
        wire(0, &.{ .{ 0, 0 }, .{ 0, 100 } }),
        wire(1, &.{ .{ -10, 20 }, .{ 0, 20 } }),
        wire(1, &.{ .{ -10, 50 }, .{ 0, 50 } }),
        wire(1, &.{ .{ -10, 80 }, .{ 0, 80 } }),
    };
    try expect(&routes, &.{ .auto, .wire }, &.{ .auto, .wire }, &.{ 0, 1 });
    try expect(&routes, &.{ .cut, .wire }, &.{ .cut, .wire }, &.{ 0, 1 });
}

test "thin crossing sites: different net pairs at one coordinate remain distinct" {
    // This deliberately ambiguous foreign overlap tests the counter's key,
    // not valid routing: A meets three distinct nets at (0,0). Merging only
    // by coordinate would erase two net relationships from the budget.
    const routes = [_]Route{
        wire(0, &.{ .{ -10, 0 }, .{ 10, 0 } }),
        wire(1, &.{ .{ 0, -10 }, .{ 0, 10 } }),
        wire(2, &.{ .{ 0, -20 }, .{ 0, 20 } }),
        wire(3, &.{ .{ 0, -30 }, .{ 0, 30 } }),
    };
    try expect(&routes, &.{ .auto, .wire, .wire, .wire }, &.{ .cut, .wire, .wire, .wire }, &.{ 0, 1, 2, 3 });
    try expect(&routes, &.{ .cut, .wire, .wire, .wire }, &.{ .label, .wire, .wire, .wire }, &.{ 0, 1, 2, 3 });
}

test "thin crossing sites: allocation failures preserve styles and release scratch" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
}
