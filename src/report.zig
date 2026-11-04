//! The decision report (docs/research/steering.md §5), as one JSON document:
//! what a caller, an agent above all, reads to judge a drawing and steer the
//! next one.
//!
//! - `gates`: every finding of `checks.find`; none is the guarantee.
//! - `requests`: each `*@` line of the deck, by line number: honoured,
//!   relaxed, dropped or rejected, why, and the lines that blocked it. An
//!   honoured line the finished drawing does not show (`checks.drawnAs`) is
//!   reported relaxed, `not_drawn`: a bug.
//! - `metrics`: crossings between nets, bends, the nets drawn as names.
//! - `decisions`: the engine's decisions as the `*@` lines that state them,
//!   rungs 1 and 2; a deck plus these lines, under `*@ grouping off`, draws
//!   the same picture.
//! - `grid`: the skeleton's rows, each device at its lattice column.
//!
//! Contents:
//! - `pub fn verdicts(arena: Allocator, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, p: ?*const Placed) Allocator.Error![]const Verdict`
//! - `pub fn decisions(arena: Allocator, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, rung: u8) Allocator.Error![]const []const u8`
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
const hints = @import("hints.zig");
const relations = @import("relations.zig");

const Library = library.Library;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Placed = placed.Placed;
const Role = sch.Role;
const Structure = structure.Structure;
const Skeleton = skeleton.Skeleton;
const Verdict = hints.Verdict;

/// What became of each of `nl`'s hints: the verdict of the stage that owns
/// it, `rejected` for a verb none takes yet; with `p`, an honoured line
/// `p` does not show is `relaxed`, `not_drawn`.
pub fn verdicts(arena: Allocator, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, p: ?*const Placed) Allocator.Error![]const Verdict {
    assert(st.verdicts.len == nl.hints.len and sk.verdicts.len == nl.hints.len);
    const out = try arena.alloc(Verdict, nl.hints.len);
    for (out, nl.hints, st.verdicts, sk.verdicts) |*v, h, a, b| {
        v.* = a orelse b orelse .{ .state = .rejected, .code = if (h.verb == .unknown) .unknown_verb else .not_built };
        if (v.state != .honoured) continue;
        const drawing = p orelse continue;
        if (checks.drawnAs(drawing, nl, h) == false) v.* = .{ .state = .relaxed, .code = .not_drawn };
    }
    return out;
}

/// The engine's decisions on rungs 1 to `rung` (1 or 2) as the `*@` lines
/// that state them: each block a `group` line (a stack top to bottom); then
/// each two-pin device's form, each column device's upper end and gate
/// side, each lattice row's devices, the rows top down and the columns left
/// to right.
pub fn decisions(arena: Allocator, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, rung: u8) Allocator.Error![]const []const u8 {
    const c = &nl.graph;
    const names = c.edges.items(.name);
    const kinds = c.edges.items(.kind);
    var out: std.ArrayList([]const u8) = .empty;
    for (st.block_kind, 0..) |k, b| {
        var line: std.ArrayList(u8) = .empty;
        try line.print(arena, "*@ group {t}", .{k});
        for (st.members(b)) |d| try line.print(arena, " {s}", .{names[d]});
        try out.append(arena, line.items);
    }
    if (rung < 2) return out.items;
    const n = c.edgeCount();
    // Forms of the two-pin devices.
    for ([_]skeleton.Form{ .vertical, .horizontal }) |f| {
        var line: std.ArrayList(u8) = .empty;
        try line.appendSlice(arena, if (f == .vertical) "*@ upright" else "*@ bridge");
        const empty = line.items.len;
        for (0..n) |d| {
            const pins = c.members(EdgeId.from(d));
            if (!sk.drawn[d] or sk.form[d] != f or !relations.twoPin(kinds[d]) or pins.len < 2 or pins[0] == pins[1]) continue;
            try line.print(arena, " {s}", .{names[d]});
        }
        if (line.items.len > empty) try out.append(arena, line.items);
    }
    // Ends and gate sides.
    for (0..n) |d| {
        if (!sk.drawn[d] or sk.form[d] != .vertical) continue;
        const pins = c.members(EdgeId.from(d));
        const up = for (pins, 0..) |net, k| {
            if (net.index() == sk.upper[d]) break k;
        } else unreachable;
        try out.append(arena, try std.fmt.allocPrint(arena, "*@ face {s} {s} up", .{ names[d], try relations.pinName(arena, kinds[d], @intCast(up)) }));
        if (!isFet(kinds[d]) or pins.len < 3) continue;
        try out.append(arena, try std.fmt.allocPrint(arena, "*@ face {s} {s} {s}", .{ names[d], try relations.pinName(arena, kinds[d], 1), if (sk.gate_right[d]) "right" else "left" }));
    }
    // Rows: each one's devices left to right, then one of each top down.
    const order = try columnDevices(arena, sk);
    std.mem.sort(u32, order, sk, struct {
        fn lt(k: *const Skeleton, a: u32, b: u32) bool {
            return if (k.y[a] != k.y[b]) k.y[a] < k.y[b] else k.x[a] < k.x[b];
        }
    }.lt);
    var downs: std.ArrayList(u8) = .empty;
    try downs.appendSlice(arena, "*@ above");
    var rows: usize = 0;
    var at: usize = 0;
    while (at < order.len) {
        var end = at + 1;
        while (end < order.len and sk.y[order[end]] == sk.y[order[at]]) end += 1;
        if (end - at >= 2) {
            var line: std.ArrayList(u8) = .empty;
            try line.appendSlice(arena, "*@ row");
            for (order[at..end]) |d| try line.print(arena, " {s}", .{names[d]});
            try out.append(arena, line.items);
        }
        try downs.print(arena, " {s}", .{names[order[at]]});
        rows += 1;
        at = end;
    }
    if (rows >= 2) try out.append(arena, downs.items);
    // Columns: the top device of each, left to right.
    std.mem.sort(u32, order, sk, struct {
        fn lt(k: *const Skeleton, a: u32, b: u32) bool {
            return if (k.x[a] != k.x[b]) k.x[a] < k.x[b] else k.y[a] < k.y[b];
        }
    }.lt);
    var across: std.ArrayList(u8) = .empty;
    try across.appendSlice(arena, "*@ order");
    var cols: usize = 0;
    for (order, 0..) |d, i| {
        if (i > 0 and sk.x[order[i - 1]] == sk.x[d]) continue;
        try across.print(arena, " {s}", .{names[d]});
        cols += 1;
    }
    if (cols >= 2) try out.append(arena, across.items);
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

    try w.writeAll("  \"requests\": [");
    for (nl.hints, try verdicts(a, nl, &st, &sk, p), 0..) |h, v, i| {
        try w.writeAll(if (i == 0) "\n    " else ",\n    ");
        try w.print("{{ \"line\": {d}, \"text\": ", .{h.line});
        try std.json.Stringify.value(h.text, .{}, w);
        try w.print(", \"state\": \"{t}\", \"code\": \"{t}\", \"blocked_by\": [", .{ v.state, v.code });
        for (v.blocked_by, v.alone, 0..) |b, solo, k| {
            if (k > 0) try w.writeAll(", ");
            try w.print("{{ \"line\": {d}, \"alone\": {} }}", .{ nl.hints[b].line, solo });
        }
        try w.writeAll("] }");
    }
    try w.writeAll(if (nl.hints.len == 0) "],\n" else "\n  ],\n");

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
    const lines = try decisions(a, nl, &st, &sk, 2);
    for (lines, 0..) |line, i| {
        try w.writeAll(if (i == 0) "\n    " else ",\n    ");
        try std.json.Stringify.value(line, .{}, w);
    }
    try w.writeAll(if (lines.len == 0) "],\n" else "\n  ],\n");

    try w.writeAll("  \"grid\": [");
    try grid(a, w, nl, &sk);
    try w.writeAll("]\n}\n");
}

// ---- private ----

fn isFet(kind: netlist.DeviceKind) bool {
    return switch (kind) {
        .mosfet, .bjt, .jfet, .mesfet => true,
        else => false,
    };
}

/// The drawn column devices.
fn columnDevices(arena: Allocator, sk: *const Skeleton) ![]u32 {
    var out: std.ArrayList(u32) = .empty;
    for (sk.drawn, sk.form, 0..) |dr, f, d| if (dr and f == .vertical) try out.append(arena, @intCast(d));
    return out.items;
}

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
