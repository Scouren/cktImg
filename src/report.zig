//! The decision report (docs/research/steering.md §5), as one JSON document:
//! what a caller, an agent above all, reads to judge a drawing and steer the
//! next one.
//!
//! - `gates`: every finding of `checks.find`; none is the guarantee.
//! - `requests`: each `*@` line of the deck, by line number: honoured,
//!   relaxed, dropped or rejected, why, and the lines that blocked it. An
//!   honoured line the finished drawing does not show (`checks.drawnAs`) is
//!   reported relaxed, `not_drawn`: a bug.
//! - `unshown_bodies`: device, terminal and net of a distinct non-rail body
//!   whose selected symbol has no B contact or marks its B hidden.
//! - `metrics`: crossings between nets, bends, the nets drawn as names.
//! - `decisions`: the engine's decisions as the `*@` lines that state them,
//!   rungs 1 to 4 (cells and places as `weak` stays); a deck plus these
//!   lines, under `*@ grouping off`, draws the same picture.
//! - `grid`: the skeleton's rows, each device at its lattice column.
//!
//! Human Rules:
//! - report.1: Two distinct nets cross where nonparallel segments meet strictly
//!   inside both segments. Opt-in diagonals can cross at half-grid points.
//! - report.2: A corner has exactly two noncollinear wire arms of one net
//!   and no terminal. A shared endpoint between pieces can be a corner.
//!   `crossings`, `bends`
//!   Both agree with the scorer the 5,263 hand-drawn reference schematics
//!   are compared by: on 200 of its drawings, 305 crossings and 1,178
//!   corners either way, none differing.
//!
//! Contents:
//! - `pub fn verdicts(arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, p: ?*const Placed, lib: ?*const Library) Allocator.Error![]const Verdict`
//! - `pub fn decisions(arena: Allocator, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, p: ?*const Placed, unit: i32, rung: u8) Allocator.Error![]const []const u8`
//! - `pub fn write(gpa: Allocator, w: *Writer, p: *const Placed, lib: *const Library, nl: *const Netlist, roles: []const Role, layout: config.Layout) !void`

const std = @import("std");
const config = @import("config.zig");
const opamp = @import("opamp.zig");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const assert = std.debug.assert;
const device = @import("device.zig");
const library = @import("library.zig");
const netlist = @import("netlist.zig");
const placed = @import("placed.zig");
const sch = @import("schematic.zig");
const checks = @import("checks.zig");
const wire_geometry = @import("wire_geometry.zig");
const drawn_symmetry = @import("drawn_symmetry.zig");
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

/// One of the two orders of lattice cells: by `major`, then `minor`. Rows
/// top down are y then x; columns left to right are x then y.
const Lattice = struct {
    major: []const i32,
    minor: []const i32,

    fn before(l: Lattice, a: u32, b: u32) bool {
        return if (l.major[a] != l.major[b]) l.major[a] < l.major[b] else l.minor[a] < l.minor[b];
    }
};

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
        if (v.state == .honoured and on_net and !inCircuit(nl, sk, p, lib, nl.net(h.args[0]).?.index())) v.* = .of(.not_placeable);
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
        out[i] = try .blocked(arena, .dropped, .conflict, &.{by});
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
        if (v.state != .honoured or h.verb == .stack or checks.drawnAs(drawing, nl, h, unit) != false) continue;
        // A cell or place on one of its devices is the more exact line: it
        // stands, and this one gives way to it.
        if (try placedBy(arena, nl, out, h)) |by| {
            v.* = try .blocked(arena, .dropped, .conflict, by);
            continue;
        }
        v.* = switch (h.verb) {
            .wire, .port => .{ .state = .relaxed, .code = .no_room },
            .at, .route, .via => .{ .state = .dropped, .code = .guarantee },
            else => .{ .state = .relaxed, .code = .not_drawn },
        };
    }
    // A later exact pose may break an admitted symmetry. Check the finished
    // poses first, so a discarded weak stay can never become a blocker.
    const has_symmetry = for (nl.hints, out) |h, v| {
        if (v.state == .honoured and (h.verb == .axis or h.verb == .symmetric)) break true;
    } else false;
    const axis = if (has_symmetry) drawn_symmetry.plane(nl, st, sk, drawing) else null;
    for (nl.hints, out) |h, *v| {
        if (v.state != .honoured) continue;
        switch (h.verb) {
            .stack => if (checks.drawnAs(drawing, nl, h, unit) != false) continue,
            .axis, .symmetric => if (nl.device(h.args[0]) == null or drawn_symmetry.shows(drawing, h, axis)) continue,
            else => continue,
        }
        v.* = if (try placedBy(arena, nl, out, h)) |by|
            try .blocked(arena, .dropped, .conflict, by)
        else
            .{ .state = .relaxed, .code = .not_drawn };
    }
    // A name where a `refdes` line asks, when there is room.
    const l = lib orelse return out;
    const anchors = try geom.refdesAnchors(arena, drawing, l);
    for (out, nl.hints) |*v, h| {
        if (v.state != .honoured or h.verb != .refdes) continue;
        const d = checks.deviceIn(drawing, h.args[0]) orelse continue;
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
        try line.appendSlice(arena, k.verb().head(.strong));
        const members = st.members(b);
        var reversed = false;
        if (k == .stack and p != null) {
            var forward = true;
            reversed = true;
            for (members[0 .. members.len - 1], members[1..]) |a, z| {
                forward = forward and checks.stackStep(p.?, nl, names[a], names[z]);
                reversed = reversed and checks.stackStep(p.?, nl, names[z], names[a]);
            }
            if (!forward and !reversed) continue;
        }
        for (0..members.len) |i| {
            const d = members[if (reversed) members.len - 1 - i else i];
            try line.print(arena, " {s}", .{names[d]});
        }
        try out.append(arena, line.items);
    }
    if (rung < 2) return out.items;
    const n = c.edgeCount();
    // An op-amp circuit is placed along its signal, not on the lattice
    // (`opamp.zig`): its places are the decision, every device's.
    if (p) |drawing| {
        const roles = try sch.guessRoles(arena, nl);
        if (opamp.applies(nl, roles, sk.drawn) and !try opamp.steered(arena, nl, roles, st, sk)) {
            try places(arena, &out, hints.Verb.at.head(.strong), nl, sk, drawing, unit);
            return out.items;
        }
    }
    // Forms of the two-pin devices.
    for ([_]skeleton.Form{ .vertical, .horizontal }) |f| {
        var line: std.ArrayList(u8) = .empty;
        try line.appendSlice(arena, hints.Verb.head(if (f == .vertical) .upright else .bridge, .strong));
        const empty = line.items.len;
        for (0..n) |d| {
            // What `upright` and `bridge` take (`relations.forms`).
            const a, const b = nl.path(EdgeId.from(d)) orelse continue;
            if (!sk.drawn[d] or sk.form[d] != f or !relations.twoPin(kinds[d]) or a == b) continue;
            try line.print(arena, " {s}", .{names[d]});
        }
        if (line.items.len > empty) try out.append(arena, line.items);
    }
    // Ends and gate sides.
    for (0..n) |d| {
        if (!sk.drawn[d] or sk.form[d] != .vertical) continue;
        const pins = c.members(EdgeId.from(d));
        // Kept as it was: the first card pin on the upper net. The general
        // form is the end of its path there (`device.of(kind).path`), which
        // reads `s` where a gate tied to the upper source reads `g` today.
        const up = for (pins, 0..) |net, k| {
            if (net.index() == sk.upper[d]) break k;
        } else unreachable;
        try out.append(arena, try std.fmt.allocPrint(arena, "{s} {s} {s} up", .{ hints.Verb.face.head(.strong), names[d], try relations.pinName(arena, kinds[d], @intCast(up)) }));
        const gate = device.of(kinds[d]).gate orelse continue;
        assert(gate < pins.len); // upright with a gate: a transistor with its three pins
        try out.append(arena, try std.fmt.allocPrint(arena, "{s} {s} {s} {s}", .{ hints.Verb.face.head(.strong), names[d], try relations.pinName(arena, kinds[d], gate), if (sk.gate_right[d]) "right" else "left" }));
    }
    // The two orders. Rows, top down: each one's devices left to right as a
    // `row` line, then the first of each as the `above` line.
    const order = try columnDevices(arena, sk);
    std.mem.sort(u32, order, Lattice{ .major = sk.y, .minor = sk.x }, Lattice.before);
    var at: usize = 0;
    while (at < order.len) {
        var end = at + 1;
        while (end < order.len and sk.y[order[end]] == sk.y[order[at]]) end += 1;
        if (end - at >= 2) {
            var line: std.ArrayList(u8) = .empty;
            try line.appendSlice(arena, hints.Verb.row.head(.strong));
            for (order[at..end]) |d| try line.print(arena, " {s}", .{names[d]});
            try out.append(arena, line.items);
        }
        at = end;
    }
    try heads(arena, &out, hints.Verb.above.head(.strong), names, order, sk.y);
    // Columns, left to right: the top device of each as the `order` line.
    std.mem.sort(u32, order, Lattice{ .major = sk.x, .minor = sk.y }, Lattice.before);
    try heads(arena, &out, hints.Verb.order.head(.strong), names, order, sk.x);
    if (rung < 3) return out.items;
    for (0..n) |d| if (sk.drawn[d]) {
        try out.append(arena, try std.fmt.allocPrint(arena, "{s} {s} {d} {d}", .{ hints.Verb.cell.head(.weak), names[d], sk.x[d] + sk.origin[0], sk.y[d] + sk.origin[1] }));
    };
    if (rung < 4) return out.items;
    try places(arena, &out, hints.Verb.at.head(.weak), nl, sk, p orelse return out.items, unit);
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

    try @import("mos_bodies.zig").writeUnshown(w, p, lib, nl, roles);
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
    switch (h.verb) {
        .role => {
            if (h.args.len != 2) return .of(.bad_args);
            const net = nl.net(h.args[0]) orelse return .of(.unknown_name);
            const role = sch.roleWord(h.args[1]) orelse return .of(.bad_args);
            return if (roles[net.index()] == role) .of(.ok) else .{ .state = .relaxed, .code = .conflict };
        },
        .class => {
            if (h.args.len != 2) return .of(.bad_args);
            _ = nl.device(h.args[0]) orelse return .of(.unknown_name);
            const l = lib orelse return .of(.ok);
            const id = l.find(h.args[1]) orelse return .of(.unknown_name);
            const drawing = p orelse return .of(.ok);
            // Taken only when it has the terminals of the class it replaces.
            const d = checks.deviceIn(drawing, h.args[0]) orelse return .of(.ok);
            return .of(if (drawing.dev_class[d] == id) .ok else .bad_args);
        },
        .unknown => return .of(.unknown_verb),
        else => return .of(.not_built),
    }
}

/// The value a line sets, when one line can override another: its kind of
/// value and what it is set on.
fn slot(h: hints.Hint) ?struct { family: u8, target: []const u8 } {
    if (h.args.len == 0) return null;
    const family: u8 = switch (h.verb) {
        .face => if (h.args.len == 3 and !(h.verb.side(library.Side, h.args[2]) orelse library.Side.left).isHorizontal()) 1 else 2,
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
/// `h` is a relation they can displace; the honoured `route` and `via`
/// lines on the net a `label` names (the wire they draw is no name); null
/// for none.
fn placedBy(arena: Allocator, nl: *const Netlist, out: []const Verdict, h: hints.Hint) !?[]const u32 {
    const exact: [2]hints.Verb = switch (h.verb) {
        .row, .above, .order, .face, .symmetric, .axis, .stack => .{ .cell, .at },
        .label => .{ .route, .via },
        else => return null,
    };
    var by: std.ArrayList(u32) = .empty;
    for (nl.hints, out, 0..) |g, v, i| {
        if ((g.verb != exact[0] and g.verb != exact[1]) or v.state != .honoured or g.args.len == 0) continue;
        const names = if (h.verb == .face or h.verb == .label) h.args[0..1] else h.args;
        for (names) |name| if (std.mem.eql(u8, name, g.args[0])) {
            try by.append(arena, @intCast(i));
            break;
        };
    }
    return if (by.items.len == 0) null else by.items;
}

/// Whether a device the skeleton draws has a pin on `net` that its symbol
/// shows: with the drawing `p` and its library, a pin past the class's
/// terminals (a dependent source's control pair, a body) or on a hidden one
/// is none.
fn inCircuit(nl: *const Netlist, sk: *const Skeleton, p: ?*const Placed, lib: ?*const Library, net: u32) bool {
    const c = &nl.graph;
    for (c.incident(netlist.VertexId.from(net))) |e| {
        if (!sk.drawn[e.index()]) continue;
        const drawing = p orelse return true;
        const l = lib orelse return true;
        const d = checks.deviceIn(drawing, c.edges.items(.name)[e.index()]) orelse return true;
        const class = l.at(drawing.dev_class[d]);
        for (c.members(e), 0..) |pin, k| {
            if (pin.index() == net and class.shows(k)) return true;
        }
    }
    return false;
}

/// Each device of `p` the skeleton draws as an `at` line under `head`: its
/// place in symbol units, and its turn.
fn places(arena: Allocator, out: *std.ArrayList([]const u8), head: []const u8, nl: *const Netlist, sk: *const Skeleton, p: *const Placed, unit: i32) !void {
    for (p.dev_name, p.dev_pos, p.dev_orient) |name, pos, o| {
        const e = (if (name.len > 0) nl.device(name) else null) orelse continue;
        if (!sk.drawn[e.index()]) continue;
        try out.append(arena, try std.fmt.allocPrint(arena, "{s} {s} {s} {s} {s}{d}", .{ head, name, try units(arena, pos.x, unit), try units(arena, pos.y, unit), if (o.mirror) "MR" else "R", @as(u16, o.rot) * 90 }));
    }
}

/// The drawn column devices.
fn columnDevices(arena: Allocator, sk: *const Skeleton) ![]u32 {
    var out: std.ArrayList(u32) = .empty;
    for (sk.drawn, sk.form, 0..) |dr, f, d| if (dr and f == .vertical) try out.append(arena, @intCast(d));
    return out.items;
}

/// One `verb` line naming the first device of each run of `order` that
/// shares a `major`; none when all share one.
fn heads(arena: Allocator, out: *std.ArrayList([]const u8), verb: []const u8, names: []const []const u8, order: []const u32, major: []const i32) !void {
    var line: std.ArrayList(u8) = .empty;
    try line.appendSlice(arena, verb);
    var runs: usize = 0;
    for (order, 0..) |d, i| {
        if (i > 0 and major[order[i - 1]] == major[d]) continue;
        try line.print(arena, " {s}", .{names[d]});
        runs += 1;
    }
    if (runs >= 2) try out.append(arena, line.items);
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
            for (n + 1..p.netCount()) |m| {
                var v = p.segments(m);
                while (v.next()) |vp| for (vp[0 .. vp.len - 1], vp[1..]) |c, d| {
                    count += @intFromBool(wire_geometry.properCross(a, b, c, d) != null);
                };
            }
        };
    }
    return count;
}

/// Corners as a reader counts them: the points with no pin on them that a
/// net's wire leaves exactly two ways, at a right angle. A T, a crossing of
/// its own and a straight joint are none; a trunk drawn in pieces has its
/// corners where two pieces end.
fn bends(p: *const Placed) u32 {
    var count: u32 = 0;
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        var li: usize = 0;
        while (it.next()) |poly| : (li += 1) for (poly, 0..) |at, pi| {
            // Each point once, where it first stands.
            var jt = p.segments(n);
            var lj: usize = 0;
            const seen = seen: while (jt.next()) |q| : (lj += 1) {
                if (lj > li) break false;
                for (q[0..if (lj == li) pi else q.len]) |o| if (o.eql(at)) break :seen true;
            } else false;
            if (seen) continue;
            // The ways out: bits 0 and 1 along the row, 2 and 3 along the column.
            const ways = checks.wireRays(p, n, at);
            const on_pin = for (p.pin_xy, p.pin_net) |q, net| {
                if (net == n and q.eql(at)) break true;
            } else false;
            count += @intFromBool(!on_pin and @popCount(ways) == 2 and ways != 3 and ways != 12 and ways != 48 and ways != 192);
        };
    }
    return count;
}

/// One string per lattice row with a drawn device, top down: each device as
/// `name@column`, left to right.
fn grid(arena: Allocator, w: *Writer, nl: *const Netlist, sk: *const skeleton.Skeleton) !void {
    const names = nl.graph.edges.items(.name);
    var order: std.ArrayList(u32) = .empty;
    for (sk.drawn, 0..) |dr, d| if (dr) try order.append(arena, @intCast(d));
    std.mem.sort(u32, order.items, Lattice{ .major = sk.y, .minor = sk.x }, Lattice.before);
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
