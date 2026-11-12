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
//!   rungs 1 to 4 (cells and places as `weak` stays); a deck plus these
//!   lines, under `*@ grouping off`, draws the same picture.
//! - `grid`: the skeleton's rows, each device at its lattice column.
//!
//! Contents:
//! - `pub fn verdicts(arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, p: ?*const Placed, lib: ?*const Library) Allocator.Error![]const Verdict`
//! - `pub fn decisions(arena: Allocator, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, p: ?*const Placed, unit: i32, rung: u8) Allocator.Error![]const []const u8`
//! - `pub fn write(gpa: Allocator, w: *Writer, p: *const Placed, lib: *const Library, nl: *const Netlist, roles: []const Role, layout: config.Layout) !void`

const std = @import("std");
const config = @import("config.zig");
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
const netlines = @import("netlines.zig");
const pinned = @import("pinned.zig");
const geom = @import("geom.zig");

const Library = library.Library;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Placed = placed.Placed;
const Role = sch.Role;
const Structure = structure.Structure;
const Skeleton = skeleton.Skeleton;
const Verdict = hints.Verdict;

/// What became of each of `nl`'s hints: the verdict of the stage that owns
/// it (the parser, the structure, the skeleton, the net lines), `role` and
/// `class` judged here (`class` with `lib`), `rejected` for a verb none
/// takes yet. Of lines setting one value (a device's gate side, a net's
/// style, ...), the preferred stands and the rest are dropped, blocked by
/// it. With `p`, an honoured line `p` does not show is `relaxed`:
/// `no_room` for a `wire` or `port` that fell back to names, else
/// `not_drawn`, a bug.
pub fn verdicts(arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, p: ?*const Placed, lib: ?*const Library) Allocator.Error![]const Verdict {
    assert(st.verdicts.len == nl.hints.len and sk.verdicts.len == nl.hints.len);
    const drawn = try arena.alloc(?Verdict, nl.hints.len);
    @memset(drawn, null);
    const unit = if (lib) |l| l.unit else 1;
    _ = try netlines.read(arena, nl, roles, unit, drawn);
    _ = try pinned.read(arena, nl, unit, sk.drawn, drawn);
    _ = try pinned.sides(arena, nl, drawn);
    const out = try arena.alloc(Verdict, nl.hints.len);
    for (out, nl.hints, nl.verdicts, st.verdicts, sk.verdicts, drawn) |*v, h, a, b, c, d| {
        v.* = a orelse b orelse c orelse d orelse own(nl, roles, h, p, lib);
        // A net no device drawn in the circuit touches (an apart driver's
        // alone) has nothing for a net line to draw.
        const on_net = h.verb == .label or h.verb == .wire or h.verb == .port;
        if (v.state == .honoured and on_net and !inCircuit(nl, sk, nl.net(h.args[0]).?.index())) v.* = .{ .state = .rejected, .code = .not_placeable };
    }
    // Lines setting one value: the preferred one stands, the rest give way.
    const order = try hints.admitOrder(arena, nl.hints);
    for (order, 0..) |i, k| {
        if (out[i].state != .honoured) continue;
        const mine = slot(nl.hints[i]) orelse continue;
        const by = for (order[0..k]) |j| {
            if (out[j].state != .honoured) continue;
            const theirs = slot(nl.hints[j]) orelse continue;
            if (theirs.family == mine.family and std.mem.eql(u8, theirs.target, mine.target)) break j;
        } else continue;
        out[i] = .{ .state = .dropped, .code = .conflict, .blocked_by = try arena.dupe(u32, &.{by}), .alone = try arena.dupe(bool, &.{true}) };
    }
    // A cell as the skeleton holds it, in the frame the line uses.
    for (out, nl.hints) |*v, h| {
        if (v.state != .honoured or h.verb != .cell) continue;
        const d = nl.device(h.args[0]).?.index();
        const at: [2]i32 = .{ sk.x[d] + sk.origin[0], sk.y[d] + sk.origin[1] };
        if (at[0] != hints.int(h.args[1]).? or at[1] != hints.int(h.args[2]).?) v.* = .{ .state = .relaxed, .code = .not_drawn };
    }
    // What still stands, checked against the drawing. A wire or port with
    // no room falls back to names, as it may; a place, route or via a
    // guarantee refuses is not drawn.
    const drawing = p orelse return out;
    for (out, nl.hints) |*v, h| {
        if (v.state != .honoured or checks.drawnAs(drawing, nl, h, unit) != false) continue;
        // A cell or place on one of its devices is the more exact line: it
        // stands, and this one gives way to it.
        if (try placedBy(arena, nl, out, h)) |by| {
            v.* = .{ .state = .dropped, .code = .conflict, .blocked_by = by, .alone = try arena.alloc(bool, by.len) };
            @memset(@constCast(v.alone), true);
            continue;
        }
        v.* = switch (h.verb) {
            .wire, .port => .{ .state = .relaxed, .code = .no_room },
            .at, .route, .via => .{ .state = .dropped, .code = .guarantee },
            else => .{ .state = .relaxed, .code = .not_drawn },
        };
    }
    // A name where a `refdes` line asks, when there is room.
    const l = lib orelse return out;
    const anchors = try geom.refdesAnchors(arena, drawing, l);
    for (out, nl.hints) |*v, h| {
        if (v.state != .honoured or h.verb != .refdes) continue;
        const d = for (drawing.dev_name, 0..) |n, k| {
            if (std.mem.eql(u8, n, h.args[0])) break k;
        } else continue;
        const box = drawing.deviceRect(l, d);
        const r = geom.refdesRect(anchors[d], h.args[0]);
        const there = switch (drawing.dev_refdes[d].?) {
            .left => r.max.x <= box.min.x,
            .right => r.min.x >= box.max.x,
            .up => r.max.y <= box.min.y,
            .down => r.min.y >= box.max.y,
        };
        if (!there) v.* = .{ .state = .relaxed, .code = .no_room };
    }
    return out;
}

/// The engine's decisions on rungs 1 to `rung` (1 to 4) as the `*@` lines
/// that state them: each block a `group` line (a stack top to bottom); then
/// each two-pin device's form, each column device's upper end and gate
/// side, each lattice row's devices, the rows top down and the columns left
/// to right; then each drawn device's cell, as a `weak` stay in the frame
/// `cell` lines use; then, from the drawing `p` (in units of `unit`), each
/// drawn device's place and turn, a `weak` stay too.
pub fn decisions(arena: Allocator, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, p: ?*const Placed, unit: i32, rung: u8) Allocator.Error![]const []const u8 {
    assert(rung >= 1 and rung <= 4);
    assert(unit > 0);
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
    if (rung < 3) return out.items;
    for (0..n) |d| if (sk.drawn[d]) {
        try out.append(arena, try std.fmt.allocPrint(arena, "*@ weak cell {s} {d} {d}", .{ names[d], sk.x[d] + sk.origin[0], sk.y[d] + sk.origin[1] }));
    };
    if (rung < 4) return out.items;
    const drawing = p orelse return out.items;
    for (drawing.dev_name, drawing.dev_pos, drawing.dev_orient) |name, pos, o| {
        const e = (if (name.len > 0) nl.device(name) else null) orelse continue;
        if (!sk.drawn[e.index()]) continue;
        try out.append(arena, try std.fmt.allocPrint(arena, "*@ weak at {s} {s} {s} {s}{d}", .{ name, try units(arena, pos.x, unit), try units(arena, pos.y, unit), if (o.mirror) "MR" else "R", @as(u16, o.rot) * 90 }));
    }
    return out.items;
}

/// The report on `p`, drawn from `nl` and `roles` with `lib` under `layout`
/// (the one `p` was laid out with). The structure
/// and skeleton are worked out again (both are pure), in `gpa`, freed
/// before this returns.
pub fn write(gpa: Allocator, w: *Writer, p: *const Placed, lib: *const Library, nl: *const Netlist, roles: []const Role, layout: config.Layout) !void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();
    const st = try structure.analyze(a, a, nl, roles);
    const sk = try skeleton.place(a, a, nl, roles, &st, .{ .shelf = layout.shelf });
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
    for (nl.hints, try verdicts(a, nl, roles, &st, &sk, p, lib), 0..) |h, v, i| {
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
    const lines = try decisions(a, nl, &st, &sk, p, lib.unit, 4);
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

/// `v` drawing units as symbol units: whole, or to four places (exact for
/// any unit under 5000).
fn units(arena: Allocator, v: i32, unit: i32) ![]const u8 {
    if (@mod(v, unit) == 0) return std.fmt.allocPrint(arena, "{d}", .{@divExact(v, unit)});
    return std.fmt.allocPrint(arena, "{d:.4}", .{@as(f64, @floatFromInt(v)) / @as(f64, @floatFromInt(unit))});
}

/// The verdict of a line no stage owns: `role` against the roles drawn
/// with, `class` against the library and the drawing; any other verb is
/// one the engine does not take yet.
fn own(nl: *const Netlist, roles: []const Role, h: hints.Hint, p: ?*const Placed, lib: ?*const Library) Verdict {
    const reject = struct {
        fn f(code: hints.Code) Verdict {
            return .{ .state = .rejected, .code = code };
        }
    }.f;
    switch (h.verb) {
        .role => {
            if (h.args.len != 2) return reject(.bad_args);
            const net = nl.net(h.args[0]) orelse return reject(.unknown_name);
            const role = sch.roleWord(h.args[1]) orelse return reject(.bad_args);
            return if (roles[net.index()] == role) .{ .state = .honoured, .code = .ok } else .{ .state = .relaxed, .code = .conflict };
        },
        .class => {
            if (h.args.len != 2) return reject(.bad_args);
            _ = nl.device(h.args[0]) orelse return reject(.unknown_name);
            const l = lib orelse return .{ .state = .honoured, .code = .ok };
            const id = l.find(h.args[1]) orelse return reject(.unknown_name);
            const drawing = p orelse return .{ .state = .honoured, .code = .ok };
            // Taken only when it has the terminals of the class it replaces.
            for (drawing.dev_name, drawing.dev_class) |n, k| if (std.mem.eql(u8, n, h.args[0])) {
                return if (k == id) .{ .state = .honoured, .code = .ok } else reject(.bad_args);
            };
            return .{ .state = .honoured, .code = .ok };
        },
        .unknown => return reject(.unknown_verb),
        else => return reject(.not_built),
    }
}

/// The value a line sets, when one line can override another: its kind of
/// value and what it is set on.
fn slot(h: hints.Hint) ?struct { family: u8, target: []const u8 } {
    if (h.args.len == 0) return null;
    const family: u8 = switch (h.verb) {
        .face => if (h.args.len == 3 and (std.mem.eql(u8, h.args[2], "up") or std.mem.eql(u8, h.args[2], "down"))) 1 else 2,
        .upright, .bridge => 3,
        .driver => 4,
        .label, .wire => 5,
        .port => 6,
        .rail => 7,
        .role => 8,
        .class => 9,
        .kind => 10,
        .at => 11,
        .refdes => 12,
        .cell => 13,
        else => return null,
    };
    return .{ .family = family, .target = h.args[0] };
}

/// The honoured `cell` and `at` lines that name a device `h` names, when
/// `h` is a relation they can displace; null for none.
fn placedBy(arena: Allocator, nl: *const Netlist, out: []const Verdict, h: hints.Hint) !?[]const u32 {
    switch (h.verb) {
        .row, .above, .order, .face => {},
        else => return null,
    }
    var by: std.ArrayList(u32) = .empty;
    for (nl.hints, out, 0..) |g, v, i| {
        if ((g.verb != .cell and g.verb != .at) or v.state != .honoured or g.args.len == 0) continue;
        const names = if (h.verb == .face) h.args[0..1] else h.args;
        for (names) |name| if (std.mem.eql(u8, name, g.args[0])) {
            try by.append(arena, @intCast(i));
            break;
        };
    }
    return if (by.items.len == 0) null else by.items;
}

/// Whether a device the skeleton draws has a pin on `net`.
fn inCircuit(nl: *const Netlist, sk: *const Skeleton, net: u32) bool {
    for (nl.graph.incident(netlist.VertexId.from(net))) |e| if (sk.drawn[e.index()]) return true;
    return false;
}

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
