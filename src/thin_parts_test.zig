//! Physical-component crossing-budget regressions.
//! Oracle: literal crossing diagrams. A cut net's disconnected parts each
//! have a budget of two; an automatic net keeps the existing total budget.
//! Route boundaries are storage chunks, never electrical boundaries.
//! Same-net endpoint, T, overlap and X meetings connect: dots.2 and
//! Placed.splitAtJunctions explicitly join same-net proper crossings.
//!
//! Contents: tests only.

const std = @import("std");
const thin = @import("thin.zig");
const sch = @import("schematic.zig");
const Style = @import("netlines.zig").Style;
const Route = sch.Route;
const Role = sch.Role;
const P = [2]f32;

const internal = [_]Role{ .internal, .internal, .internal, .internal };
const ranks = [_]u32{ 0, 1, 2, 3 };
const cut = [_]Style{ .cut, .wire, .wire, .wire };
const labeled = [_]Style{ .label, .wire, .wire, .wire };

// ---- private ----

fn wire(net: u32, points: []const P) Route {
    std.debug.assert(points.len >= 2 and points.len <= 6);
    var r: Route = .{ .net = net, .len = @intCast(points.len), .pts = undefined };
    @memcpy(r.pts[0..points.len], points);
    return r;
}

fn expect(routes: []const Route, roles: []const Role, before: []const Style, after: []const Style, rank: []const u32, mates: ?[]const u32, max: u32) !void {
    const gpa = std.testing.allocator;
    const style = try gpa.dupe(Style, before);
    defer gpa.free(style);
    const changed = try thin.name(gpa, routes, roles, rank, mates, max, style);
    try std.testing.expectEqual(!std.mem.eql(Style, before, after), changed);
    try std.testing.expectEqualSlices(Style, after, style);
}

fn separate() [5]Route {
    return .{
        wire(0, &.{ .{ 0, 0 }, .{ 40, 0 } }),
        wire(0, &.{ .{ 0, 100 }, .{ 40, 100 } }),
        wire(1, &.{ .{ 10, -10 }, .{ 10, 10 } }),
        wire(2, &.{ .{ 20, -10 }, .{ 20, 10 } }),
        wire(3, &.{ .{ 10, 90 }, .{ 10, 110 } }),
    };
}

fn allocationFailure(gpa: std.mem.Allocator) !void {
    const base = separate();
    const routes = base ++ [_]Route{wire(0, &.{ .{ 30, 0 }, .{ 30, 100 } })};
    var style = cut;
    const changed = thin.name(gpa, &routes, &internal, &ranks, null, 2, &style) catch |err| {
        try std.testing.expectEqualSlices(Style, &cut, &style);
        return err;
    };
    try std.testing.expect(changed);
    try std.testing.expectEqualSlices(Style, &labeled, &style);
}

test "thin parts: allocation failures leave every style intact and release scratch" {
    // Oracle: the literal joined two-plus-one diagram labels net 0 only
    // on success. Injected failure at every allocation must leave the
    // original styles byte-for-byte intact; the harness checks cleanup.
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailure, .{});
}

test "thin parts: disconnected two-plus-one crossings stay cut while auto still uses their total" {
    // Net 0's two horizontal parts cross two and one separate verticals.
    // No label identity or net identity alone joins the distant pieces.
    const routes = separate();
    try expect(&routes, &internal, &cut, &cut, &ranks, null, 2);
    try expect(&routes, &internal, &.{ .auto, .wire, .wire, .wire }, &cut, &ranks, null, 2);
}

test "thin parts: endpoint T overlap and proper-X bridges make one over-budget component" {
    // Every bridge joins both horizontal pieces without crossing any
    // foreign vertical. Thus the connected component has exactly three.
    const base = separate();
    const bridges = [_]Route{
        wire(0, &.{ .{ 40, 0 }, .{ 50, 0 }, .{ 50, 100 }, .{ 40, 100 } }),
        wire(0, &.{ .{ 30, 0 }, .{ 30, 100 } }),
        wire(0, &.{ .{ 30, 0 }, .{ 50, 0 }, .{ 50, 100 }, .{ 30, 100 } }),
        wire(0, &.{ .{ 30, -10 }, .{ 30, 110 } }),
    };
    for (bridges) |bridge| {
        var routes: [6]Route = undefined;
        @memcpy(routes[0..5], &base);
        routes[5] = bridge;
        try expect(&routes, &internal, &cut, &labeled, &ranks, null, 2);
        // Reverse all vertices and route order: only storage order changes.
        for (&routes) |*r| std.mem.reverse(P, r.pts[0..r.len]);
        std.mem.reverse(Route, &routes);
        try expect(&routes, &internal, &cut, &labeled, &ranks, null, 2);
    }
}

test "thin parts: chunk boundaries and transitive bridges do not split a component" {
    const base = separate();
    const routes = base ++ [_]Route{
        wire(0, &.{ .{ 50, 0 }, .{ 50, 50 } }),
        wire(0, &.{ .{ 50, 50 }, .{ 50, 100 } }),
        wire(0, &.{ .{ 50, 100 }, .{ 40, 100 } }),
        wire(0, &.{ .{ 40, 0 }, .{ 50, 0 } }),
    };
    try expect(&routes, &internal, &cut, &labeled, &ranks, null, 2);
    // No one added route reaches both rows. Proper-X contacts through the
    // middle horizontal route transitively join the two vertical routes.
    const crossed = base ++ [_]Route{
        wire(0, &.{ .{ 30, -10 }, .{ 30, 40 } }),
        wire(0, &.{ .{ 25, 30 }, .{ 40, 30 } }),
        wire(0, &.{ .{ 35, 20 }, .{ 35, 110 } }),
    };
    try expect(&crossed, &internal, &cut, &labeled, &ranks, null, 2);
    // A one-unit gap at either end leaves the two physical pieces apart.
    const gapped = base ++ [_]Route{wire(0, &.{ .{ 30, 1 }, .{ 30, 99 } })};
    try expect(&gapped, &internal, &cut, &cut, &ranks, null, 2);
}

test "thin parts: another net crossing both pieces never joins them" {
    // Each horizontal part has two crossings: one short foreign vertical,
    // and net 3's long vertical. The long vertical belongs to another net.
    const routes = [_]Route{
        wire(0, &.{ .{ 0, 0 }, .{ 40, 0 } }),
        wire(0, &.{ .{ 0, 100 }, .{ 40, 100 } }),
        wire(1, &.{ .{ 10, -10 }, .{ 10, 10 } }),
        wire(2, &.{ .{ 10, 90 }, .{ 10, 110 } }),
        wire(3, &.{ .{ 30, -10 }, .{ 30, 110 } }),
    };
    try expect(&routes, &internal, &cut, &cut, &ranks, null, 2);
}

test "thin parts: total crossings still rank eligible nets before greedy recount" {
    // Cut A crosses B three times in one part and explicit C three times
    // in another: total 6, largest part 3. Cut B also crosses explicit D
    // twice: total 5, largest part 5. A goes first by TOTAL; then B has 2
    // and stays cut. Ranking by largest part would incorrectly label both.
    const routes = [_]Route{
        wire(0, &.{ .{ 0, 0 }, .{ 40, 0 } }),
        wire(0, &.{ .{ 0, 100 }, .{ 40, 100 } }),
        wire(1, &.{ .{ 10, 10 }, .{ 10, -10 }, .{ 50, -10 }, .{ 50, 10 } }),
        wire(1, &.{ .{ 20, -10 }, .{ 20, 10 } }),
        wire(1, &.{ .{ 30, -10 }, .{ 30, 10 } }),
        wire(2, &.{ .{ 10, 90 }, .{ 10, 110 } }),
        wire(2, &.{ .{ 20, 90 }, .{ 20, 110 } }),
        wire(2, &.{ .{ 30, 90 }, .{ 30, 110 } }),
        wire(3, &.{ .{ 45, -5 }, .{ 55, -5 } }),
        wire(3, &.{ .{ 45, 5 }, .{ 55, 5 } }),
    };
    try expect(&routes, &internal, &.{ .cut, .cut, .wire, .wire }, &.{ .label, .cut, .wire, .wire }, &ranks, null, 2);
}

test "thin parts: rails explicit styles and eligible mirror partners retain existing rules" {
    const base = separate();
    const joined = base ++ [_]Route{wire(0, &.{ .{ 30, 0 }, .{ 30, 100 } })};
    try expect(&joined, &.{ .internal, .internal, .internal, .supply }, &cut, &cut, &ranks, null, 2);
    try expect(&joined, &internal, &.{ .wire, .wire, .wire, .wire }, &.{ .wire, .wire, .wire, .wire }, &ranks, null, 2);
    const roles = [_]Role{ .internal, .internal, .internal, .internal, .internal };
    const order = [_]u32{ 0, 1, 2, 3, 4 };
    const mates = [_]u32{ 4, sch.none, sch.none, sch.none, 0 };
    try expect(&joined, &roles, &.{ .cut, .wire, .wire, .wire, .cut }, &.{ .label, .wire, .wire, .wire, .label }, &order, &mates, 2);
    try expect(&joined, &roles, &.{ .cut, .wire, .wire, .wire, .wire }, &.{ .label, .wire, .wire, .wire, .wire }, &order, &mates, 2);
}

test "thin parts: canonical rank breaks equal total and component budgets" {
    // A connected horizontal comb and one vertical cross three times.
    // Removing either clears all crossings: rank alone chooses which one.
    var routes = [_]Route{
        wire(0, &.{ .{ -10, 0 }, .{ 40, 0 } }),
        wire(0, &.{ .{ -10, 0 }, .{ -10, 40 }, .{ 40, 40 } }),
        wire(0, &.{ .{ -10, 20 }, .{ 40, 20 } }),
        wire(1, &.{ .{ 10, -10 }, .{ 10, 50 } }),
    };
    try expect(&routes, &.{ .internal, .internal }, &.{ .cut, .cut }, &.{ .label, .cut }, &.{ 0, 1 }, null, 2);
    try expect(&routes, &.{ .internal, .internal }, &.{ .cut, .cut }, &.{ .cut, .label }, &.{ 1, 0 }, null, 2);
    std.mem.reverse(Route, &routes);
    try expect(&routes, &.{ .internal, .internal }, &.{ .cut, .cut }, &.{ .cut, .label }, &.{ 1, 0 }, null, 2);
}
