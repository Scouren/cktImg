//! Pairwise two-part routes for fully identified reflected complementary stacks.
//! A selected, acyclic parent supplies two triples of exact ordered MOS contacts.
//! Recheck the visible pins and strokes on each final canvas, then draw both
//! drain pairs and their isolated gate names in one append transaction.

const std = @import("std");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const library = @import("library.zig");
const netlist = @import("netlist.zig");
const netlines = @import("netlines.zig");
const wire_parts = @import("wire_parts.zig");
const Allocator = std.mem.Allocator;
const Canvas = canvas.Canvas;
const Netlist = netlist.Netlist;
const Pt = library.Pt;

/// Ordered graph handles of one three-contact output. The gate belongs to
/// a different parent; the input collector retains raw ownership authority.
pub const Output = struct { net: u32, pmos: u32, nmos: u32, gate: u32 };
/// Reflected siblings share one admission and withdrawal decision.
pub const Pair = [2]Output;
/// Result of the latest attempt, retained through ordinary thinning.
pub const State = enum(u8) { ready, drawn, failed, withdrawn };

/// Cold per-drawing requests and dispositions. Empty during compaction.
pub const Trial = struct {
    pairs: []const Pair = &.{},
    states: []State = &.{},
    nl: ?*const Netlist = null,

    /// Draws pairs after ordinary rails and before mirror/ordinary signals.
    pub fn draw(t: Trial, c: *Canvas, lines: *const netlines.NetLines, pins_of: []const std.ArrayList(u32), routed: []const bool, handled: []bool) Allocator.Error!void {
        std.debug.assert(t.pairs.len == t.states.len);
        for (t.pairs, t.states) |pair, *state| {
            if (state.* == .withdrawn) continue;
            state.* = .failed;
            var mapped: [2][3]u32 = undefined;
            for (pair, &mapped) |o, *actual| {
                const n = o.net;
                if (n >= handled.len or routed[n] or handled[n] or c.s.labeled[n] or c.s.roles[n] != .internal or lines.port[n] != null) break;
                if (lines.style[n] != .auto and lines.style[n] != .cut) break;
                if (for (c.segs.items) |seg| {
                    if (seg.net == n) break true;
                } else false) break;
                actual.* = map(c, t.nl.?, o, pins_of[n].items) orelse break;
            } else {
                if (!try drawPair(c, pair, mapped)) continue;
                for (pair) |o| {
                    handled[o.net] = true;
                    c.s.labeled[o.net] = true;
                }
                state.* = .drawn;
            }
        }
    }

    /// Withdraws a failed pair, including a sibling promoted to labels on
    /// this round. Its caller restores initial styles and rebuilds fresh.
    pub fn withdraw(t: Trial, style: []const netlines.Style) bool {
        var changed = false;
        for (t.pairs, t.states) |p, *s| {
            if (s.* == .withdrawn) continue;
            if (s.* == .drawn and style[p[0].net] != .label and style[p[1].net] != .label) continue;
            s.* = .withdrawn;
            changed = true;
        }
        return changed;
    }
};

/// Original caller directives on either sibling or its endpoint devices
/// keep their ordinary behavior, including accepted default-looking styles.
pub fn admitted(nl: *const Netlist, pair: Pair, lines: *const netlines.NetLines) bool {
    if (lines.first.len != 0 or pair[0].net == pair[1].net) return false;
    for (pair) |o| {
        if (o.net >= lines.style.len or lines.style[o.net] != .auto or lines.port[o.net] != null) return false;
        for (lines.routes) |r| if (r.net == o.net) return false;
        for (nl.hints) |h| switch (h.verb) {
            .role, .port, .wire, .label, .rail, .route, .via => {
                if (h.args.len > 0 and (nl.net(h.args[0]) orelse continue).index() == o.net) return false;
            },
            .off, .symmetry_off, .axis => return false,
            .refdes, .expand => {},
            else => for (h.args) |arg| {
                const d = (nl.device(arg) orelse continue).index();
                if (d == o.pmos or d == o.nmos or d == o.gate) return false;
            },
        };
    }
    return true;
}

// ---- private ----

fn drawPair(c: *Canvas, pair: Pair, mapped: [2][3]u32) !bool {
    const before = wire_parts.Checkpoint.take(c);
    var done = false;
    defer if (!done) before.restore(c);
    for (pair, &mapped) |o, *p| {
        if (!try wire_parts.draw(c, o.net, p[0..2], p[2..], .name)) return false;
    }
    done = true;
    return true;
}

fn map(c: *const Canvas, nl: *const Netlist, o: Output, pins: []const u32) ?[3]u32 {
    if (pins.len != 3 or nl.graph.incident(netlist.VertexId.from(o.net)).len != 3) return null;
    const devs = [3]u32{ o.pmos, o.nmos, o.gate };
    var out: [3]u32 = @splat(sch.none);
    const indices = [3]u8{ 0, 0, 1 };
    for (pins) |p| {
        const pin = c.s.pins.get(p);
        const i = std.mem.indexOfScalar(u32, &devs, pin.device) orelse return null;
        if (out[i] != sch.none or pin.net != o.net or pin.index != indices[i]) return null;
        const e = netlist.EdgeId.from(pin.device);
        const raw = nl.graph.members(e);
        if (raw.len != 4 or raw[pin.index].index() != o.net or nl.graph.edges.items(.kind)[e.index()] != .mosfet) return null;
        const model = nl.modelType(e) orelse return null;
        const row = c.s.devices.get(pin.device);
        const class = c.s.lib.at(row.class);
        if (!std.mem.eql(u8, model, "pmos") and !std.mem.eql(u8, model, "nmos")) return null;
        if (class.terminals.len < 3 or class.terminals.len > 4) return null;
        const names = [_][]const u8{ "d", "g", "s", "b" };
        for (names[0..class.terminals.len], class.terminals, 0..) |name, t, index| {
            if (!std.ascii.eqlIgnoreCase(t.name, name) or class.shows(index) != (index != 3)) return null;
        }
        const want = if (i == 0) "pmos" else if (i == 1) "nmos" else model;
        if (!std.mem.eql(u8, class.name, want) or !std.mem.eql(u8, model, want)) return null;
        if (!row.kept or !class.shows(pin.index) or class.side(pin.index, row.orient) != pin.side) return null;
        if (!lead(class, pin.index)) return null;
        const node = c.s.deviceNode(pin.device) orelse return null;
        const origin = Pt.round(c.s.xy[node]);
        const offset = row.orient.apply(class.terminals[pin.index].at);
        const actual = canvas.pinAt(c.s, p);
        if (@as(i64, origin.x) - row.grid.x + offset.x != actual.x or @as(i64, origin.y) - row.grid.y + offset.y != actual.y) return null;
        out[i] = p;
    }
    for (out) |p| if (p == sch.none) return null;
    return out;
}

fn lead(class: library.Class, index: u8) bool {
    const tip = class.terminals[index].at;
    const side = class.side(index, .{}) orelse return false;
    var joint: ?Pt = null;
    var lead_index: usize = 0;
    for (class.draw, 0..) |stroke, i| {
        const pts: []const Pt = switch (stroke) {
            .line => |line| &.{ line.a, line.b },
            .polyline => |pts| pts,
            else => continue,
        };
        if (pts.len < 2) continue;
        const begin = pts[0].eql(tip);
        if (!begin and !pts[pts.len - 1].eql(tip)) continue;
        const inner = if (begin) pts[1] else pts[pts.len - 2];
        const delta = tip.sub(inner);
        if (joint != null or (delta.x != 0 and delta.y != 0) or library.Side.of(delta) != side) return false;
        joint = if (begin) pts[pts.len - 1] else pts[0];
        lead_index = i;
    }
    const attach = joint orelse return false;
    for (class.draw, 0..) |stroke, i| {
        if (i == lead_index) continue;
        const pts: []const Pt = switch (stroke) {
            .line => |line| &.{ line.a, line.b },
            .polyline => |pts| pts,
            .circle => |circle| {
                const delta = attach.sub(circle.c);
                if (@as(i64, delta.x) * delta.x + @as(i64, delta.y) * delta.y == @as(i64, circle.r) * circle.r) return true;
                continue;
            },
            else => continue,
        };
        if (pts.len < 2) continue;
        for (pts[0 .. pts.len - 1], pts[1..]) |a, b| {
            if ((a.x == b.x or a.y == b.y) and library.Rect.fromCorners(a, b).contains(attach)) return true;
        }
    }
    return false;
}

test "reflected outputs: second failure and allocator failure restore both sibling routes and names" {
    try pairRollback(std.testing.allocator, true);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, pairRollback, .{false});
}

fn pairRollback(gpa: Allocator, fail_second: bool) !void {
    var lib: library.Library = .init(gpa);
    defer lib.deinit();
    var s: sch.Schematic = .{ .arena = .init(gpa), .lib = &lib, .device_kind = &.{}, .device_name = &.{}, .net_name = &.{ "l", "r", "prior" }, .device_pin_count = &.{}, .roles = &.{ .internal, .internal, .internal } };
    defer s.deinit();
    const a = s.arena.allocator();
    var xy: std.ArrayList([2]f32) = .empty;
    const pts = [_][2]f32{ .{ 0, 0 }, .{ 60, 0 }, .{ 160, 100 }, .{ 0, 200 }, .{ 60, 200 }, .{ 160, 300 } };
    for (pts, 0..) |point, i| {
        const net: u32 = @intCast(i / 3);
        const node = try s.addNode(.{ .kind = .terminal, .ref = net, .group = sch.none });
        try xy.append(a, point);
        _ = try s.addPin(.{ .home = node, .net = net, .side = if (i % 3 == 0) .right else .left, .device = sch.none, .index = 0 });
    }
    s.xy = xy.items;
    var c = try Canvas.init(gpa, &s, &xy, .of(.{}, 10), &.{}, &.{});
    defer c.deinit();
    const prior = [2]Pt{ .{ .x = 300, .y = 400 }, .{ .x = 330, .y = 400 } };
    try std.testing.expect(try c.commit(2, &prior));
    const saved = wire_parts.Checkpoint.take(&c);
    const pair: Pair = .{ .{ .net = 0, .pmos = 0, .nmos = 1, .gate = 2 }, .{ .net = 1, .pmos = 3, .nmos = 4, .gate = 5 } };
    const gates: [2][3]u32 = .{ .{ 0, 1, 2 }, .{ 3, 4, if (fail_second) 4 else 5 } };
    const result = drawPair(&c, pair, gates) catch |err| {
        try std.testing.expectEqualDeep(saved, wire_parts.Checkpoint.take(&c));
        try std.testing.expectEqualDeep(prior[0], c.segs.items[0].a);
        try std.testing.expectEqualDeep(prior[1], c.segs.items[0].b);
        return err;
    };
    try std.testing.expectEqual(!fail_second, result);
    if (fail_second) try std.testing.expectEqualDeep(saved, wire_parts.Checkpoint.take(&c)) else try std.testing.expectEqual(saved.pins + 4, s.pins.len);
}
