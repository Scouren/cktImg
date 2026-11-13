//! Physical wire polylines and exact terminals -> an ink-only continuity certificate.
//! Cites: Manhattan endpoint/T-junction connectivity, independently checked by
//! literal crossing, detached-label, wrong-net and remote-spur mutations in
//! converter_loops.zig. Labels and port names cannot join disconnected ink.
//!
//! Contents:
//! - `pub fn connected(gpa: std.mem.Allocator, p: *const np.Placed, terminals: []const usize) !bool`
//! - `pub fn onPolyline(poly: []const np.Pt, point: np.Pt) bool`

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");

/// Whether all exact terminal indices connect through their net's own
/// Manhattan wire polylines. Temporary arrays use caller-owned `gpa`.
/// Endpoint/T contacts join; proper crossings without a vertex do not.
pub fn connected(gpa: std.mem.Allocator, p: *const np.Placed, terminals: []const usize) !bool {
    std.debug.assert(terminals.len >= 2);
    const net = p.pin_net[terminals[0]];
    for (terminals) |t| try testing.expectEqual(net, p.pin_net[t]);
    var polys: std.ArrayList([]const np.Pt) = .empty;
    defer polys.deinit(gpa);
    var it = p.segments(net);
    while (it.next()) |poly| {
        for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            try testing.expect(a.x == b.x or a.y == b.y);
            try testing.expect(!a.eql(b));
        }
        try polys.append(gpa, poly);
    }
    const seen = try gpa.alloc(bool, polys.items.len);
    defer gpa.free(seen);
    for (polys.items, seen) |poly, *visited| visited.* = onPolyline(poly, p.pin_xy[terminals[0]]);
    for (0..polys.items.len) |_| {
        var changed = false;
        for (polys.items, 0..) |a, i| {
            if (!seen[i]) continue;
            for (polys.items, 0..) |b, j| {
                if (seen[j] or !wiresTouch(a, b)) continue;
                seen[j] = true;
                changed = true;
            }
        }
        if (!changed) break;
    }
    for (terminals) |t| {
        const reached = for (polys.items, seen) |poly, visited| {
            if (visited and onPolyline(poly, p.pin_xy[t])) break true;
        } else false;
        if (!reached) return false;
    }
    return true;
}

/// Exact membership on one of a nonempty Manhattan polyline's segments.
pub fn onPolyline(poly: []const np.Pt, point: np.Pt) bool {
    for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
        if (a.x == b.x and point.x == a.x and point.y >= @min(a.y, b.y) and point.y <= @max(a.y, b.y)) return true;
        if (a.y == b.y and point.y == a.y and point.x >= @min(a.x, b.x) and point.x <= @max(a.x, b.x)) return true;
    }
    return false;
}

// ---- private ----

fn wiresTouch(a: []const np.Pt, b: []const np.Pt) bool {
    for (a) |point| if (onPolyline(b, point)) return true;
    for (b) |point| if (onPolyline(a, point)) return true;
    return false;
}
