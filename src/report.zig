//! The decision report (docs/research/steering.md §5), as one JSON document:
//! what a caller, an agent above all, reads to judge a drawing and steer the
//! next one.
//!
//! - `gates`: every finding of `checks.find`; none is the guarantee.
//! - `metrics`: crossings between nets, bends, the nets drawn as names.
//! - `decisions`: the engine's decisions as the `*@` lines that state them,
//!   those the deck can already take (`*@ group`, rung 1); a deck plus these
//!   lines draws the same picture.
//! - `grid`: the skeleton's rows, each device at its lattice column.
//!
//! Contents:
//! - `pub fn decisions(arena: Allocator, nl: *const Netlist, st: *const Structure) Allocator.Error![]const []const u8`
//! - `pub fn write(gpa: Allocator, w: *Writer, p: *const Placed, lib: *const Library, nl: *const Netlist, roles: []const Role) !void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const assert = std.debug.assert;
const library = @import("library.zig");
const netlist = @import("netlist.zig");
const placed = @import("placed.zig");
const sch = @import("schematic.zig");
const checks = @import("checks.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");

const Library = library.Library;
const Netlist = netlist.Netlist;
const Placed = placed.Placed;
const Role = sch.Role;
const Structure = structure.Structure;

/// Each block of `st` as the `*@ group` line that states it, in the order
/// recognition lists them (a stack's members top to bottom), so the lines
/// read back give the same blocks in the same order.
pub fn decisions(arena: Allocator, nl: *const Netlist, st: *const Structure) Allocator.Error![]const []const u8 {
    const names = nl.graph.edges.items(.name);
    var out: std.ArrayList([]const u8) = .empty;
    for (st.block_kind, 0..) |k, b| {
        var line: std.ArrayList(u8) = .empty;
        try line.print(arena, "*@ group {t}", .{k});
        for (st.members(b)) |d| try line.print(arena, " {s}", .{names[d]});
        try out.append(arena, line.items);
    }
    assert(out.items.len == st.block_kind.len);
    return out.items;
}

/// The report on `p`, drawn from `nl` and `roles` with `lib`. The structure
/// and skeleton are worked out again (both are pure), in `gpa`, freed
/// before this returns.
pub fn write(gpa: Allocator, w: *Writer, p: *const Placed, lib: *const Library, nl: *const Netlist, roles: []const Role) !void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const st = try structure.analyze(a, a, nl, roles);
    const sk = try skeleton.place(a, a, nl, roles, &st);
    var found: std.ArrayList(checks.Finding) = .empty;
    try checks.find(a, &found, p, lib);

    try w.writeAll("{\n  \"gates\": [");
    for (found.items, 0..) |f, i| {
        try w.writeAll(if (i == 0) "\n    " else ",\n    ");
        try w.print("{{ \"rule\": \"{t}\", \"net\": ", .{f.rule});
        try netName(w, p, f.net);
        try w.print(", \"at\": [{d}, {d}], \"other\": {d} }}", .{ f.at.x, f.at.y, f.other });
    }
    try w.writeAll(if (found.items.len == 0) "],\n" else "\n  ],\n");

    try w.print("  \"metrics\": {{ \"crossings\": {d}, \"bends\": {d}, \"labelled\": [", .{ crossings(p), bends(p) });
    var first = true;
    for (0..p.netCount()) |n| {
        const named = for (p.labels) |l| {
            if (l.net == n) break true;
        } else false;
        if (!named) continue;
        if (!first) try w.writeAll(", ");
        first = false;
        try netName(w, p, @intCast(n));
    }
    try w.writeAll("] },\n  \"decisions\": [");
    for (try decisions(a, nl, &st), 0..) |line, i| {
        try w.writeAll(if (i == 0) "\n    " else ",\n    ");
        try std.json.Stringify.value(line, .{}, w);
    }
    try w.writeAll(if (st.block_kind.len == 0) "],\n" else "\n  ],\n");

    try w.writeAll("  \"grid\": [");
    try grid(a, w, nl, &sk);
    try w.writeAll("]\n}\n");
}

// ---- private ----

fn netName(w: *Writer, p: *const Placed, n: u32) Writer.Error!void {
    if (n >= p.netCount()) return w.writeAll("null");
    try std.json.Stringify.value(p.net_name[n], .{}, w);
}

/// Wires of two nets crossing strictly inside both.
fn crossings(p: *const Placed) u32 {
    var count: u32 = 0;
    for (0..p.netCount()) |n| {
        var h = p.segments(n);
        while (h.next()) |hp| for (hp[0 .. hp.len - 1], hp[1..]) |a, b| {
            if (a.y != b.y) continue;
            for (0..p.netCount()) |m| {
                if (m == n) continue;
                var v = p.segments(m);
                while (v.next()) |vp| for (vp[0 .. vp.len - 1], vp[1..]) |c, d| {
                    if (c.x != d.x) continue;
                    if (c.x > @min(a.x, b.x) and c.x < @max(a.x, b.x) and a.y > @min(c.y, d.y) and a.y < @max(c.y, d.y)) count += 1;
                };
            }
        };
    }
    return count;
}

/// Points where a wire turns.
fn bends(p: *const Placed) u32 {
    var count: u32 = 0;
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        while (it.next()) |poly| {
            if (poly.len < 3) continue;
            for (poly[0 .. poly.len - 2], poly[1 .. poly.len - 1], poly[2..]) |a, b, c| {
                count += @intFromBool((a.x == b.x) != (b.x == c.x));
            }
        }
    }
    return count;
}

/// One string per lattice row with a drawn device, top down: each device as
/// `name@column`, left to right.
fn grid(arena: Allocator, w: *Writer, nl: *const Netlist, sk: *const skeleton.Skeleton) !void {
    const names = nl.graph.edges.items(.name);
    var order: std.ArrayList(u32) = .empty;
    for (sk.drawn, 0..) |dr, d| if (dr) try order.append(arena, @intCast(d));
    std.mem.sort(u32, order.items, sk, struct {
        fn lt(k: *const skeleton.Skeleton, x: u32, y: u32) bool {
            if (k.y[x] != k.y[y]) return k.y[x] < k.y[y];
            return k.x[x] < k.x[y];
        }
    }.lt);
    var line: std.ArrayList(u8) = .empty;
    var rows: u32 = 0;
    for (order.items, 0..) |d, i| {
        if (i == 0 or sk.y[order.items[i - 1]] != sk.y[d]) {
            line.clearRetainingCapacity();
            try line.print(arena, "row {d}:", .{sk.y[d]});
        }
        try line.print(arena, " {s}@{d}", .{ names[d], sk.x[d] });
        if (i + 1 == order.items.len or sk.y[order.items[i + 1]] != sk.y[d]) {
            try w.writeAll(if (rows == 0) "\n    " else ",\n    ");
            try std.json.Stringify.value(line.items, .{}, w);
            rows += 1;
        }
    }
    if (rows > 0) try w.writeAll("\n  ");
}
