//! Successful complete four-side CT owner -> its observed physical parts.
//!
//! Human Rules:
//! - ct_four_wires.1 (bounded observation) One complete 26-device source
//!   scene has four local five-pin outputs with an isolated outer gate,
//!   two lower CT/L parts separated from their remote three-pin branches,
//!   and one shared opposed-tap supply. The unchanged 148-pair certificate
//!   includes every separation: docs/research/ct-four-sides.md. No figure,
//!   device name, distance threshold or generic net rule selects these parts.
//! - ct_four_wires.2 (boundary) Borrow only successful placement Groups.
//!   Recheck every actual visible lead and complete net membership. Original
//!   routes/ats, first-net requests, explicit styles/ports and admitted rail
//!   representation win, including a normalized default-equivalent rail.
//! - ct_four_wires.3 (choice) Use ordinary trunk competition for each part,
//!   in the measured larger-part-first order. Commit a complete two-part
//!   net or restore all appended ink and symbol rows. Inclusive same-net
//!   contact joins parts, including proper X crossings; reject it explicitly.
//!   Every part must retain its own correctly bound name/port. `parts`
//! - ct_four_wires.4 (boundary) Current auto/cut rounds can retain these
//!   parts; label rounds use ordinary labels. No crossing-budget exemption,
//!   route fallback or Canvas behavior changes. Previously successful nets
//!   remain when a later independent net declines or returns an error.
//!
//! Data: borrowed 104-byte Group and existing per-net/request tables; at most
//! six original pin handles and points per request. Static member/role pairs
//! use u5/u2. Cold stack checkpoint lengths use usize and live for one net;
//! Canvas owns all output allocation. No retained flags, graph or allocator
//! replacement. Six bounded requests run outside trunk candidate loops. No
//! hot-path, residue or speed claim. Six data answers are in the source study.
//!
//! Contents: qualify, rail, parts; private mapping, frame and transaction.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const canvas = @import("canvas.zig");
const netlines = @import("netlines.zig");
const hints = @import("hints.zig");
const owner = @import("ct_four_sides.zig");
const wire_parts = @import("wire_parts.zig");
const Requests = @import("wire_requests.zig").Requests;
const Group = owner.Group;
const Canvas = canvas.Canvas;
const Pt = library.Pt;
const Netlist = netlist.Netlist;
const NetLines = netlines.NetLines;

const Port = struct { member: u5, role: u2 };
const Spec = struct { ports: [6]Port, len: u3, split: u3, output: bool };
const specs = [_]Spec{
    .{ .ports = .{ portSpec(6, 1), portSpec(3, 1), portSpec(11, 0), portSpec(8, 1), portSpec(9, 0), portSpec(10, 1) }, .len = 6, .split = 5, .output = true },
    .{ .ports = .{ portSpec(6, 0), portSpec(2, 1), portSpec(10, 0), portSpec(8, 0), portSpec(9, 1), portSpec(11, 1) }, .len = 6, .split = 5, .output = true },
    .{ .ports = .{ portSpec(7, 1), portSpec(5, 1), portSpec(16, 0), portSpec(13, 1), portSpec(14, 0), portSpec(15, 1) }, .len = 6, .split = 5, .output = true },
    .{ .ports = .{ portSpec(7, 0), portSpec(4, 1), portSpec(15, 0), portSpec(13, 0), portSpec(14, 1), portSpec(16, 1) }, .len = 6, .split = 5, .output = true },
    .{ .ports = .{ portSpec(18, 1), portSpec(19, 0), portSpec(21, 2), portSpec(4, 0), portSpec(1, 0), portSpec(0, 0) }, .len = 5, .split = 3, .output = false },
    .{ .ports = .{ portSpec(22, 1), portSpec(23, 0), portSpec(25, 2), portSpec(5, 0), portSpec(1, 1), portSpec(0, 0) }, .len = 5, .split = 3, .output = false },
};
const Mapped = struct { pins: [6]u32, points: [6]Pt };
comptime {
    assert(@sizeOf(Port) == 2);
    for (specs) |spec| {
        assert(spec.len <= 6 and spec.split > 0 and spec.split < spec.len);
        for (spec.ports[0..spec.len]) |p| assert(p.member < 26 and p.role < 3);
    }
}

/// Borrows the successful owner slice or an empty slice. Read the original
/// admitted net-line verdicts before scaffolding defers paths or thinning
/// changes styles. The caller owns all inputs; this allocates nothing.
pub fn qualify(nl: *const Netlist, groups: []const Group, verdicts: []const ?hints.Verdict, lines: *const NetLines) []const Group {
    assert(groups.len <= 1 and verdicts.len == nl.hints.len);
    if (groups.len == 0 or lines.first.len != 0) return &.{};
    const g = groups[0];
    const supply = bound(nl, g, .{ .member = 0, .role = 2 });
    for (g) |edge| for (nl.graph.members(edge)) |net| {
        if (lines.style[net.index()] != .auto or lines.port[net.index()] != null) return &.{};
        for (lines.routes) |route| if (route.net == net.index()) return &.{};
    };
    for (nl.hints, verdicts) |hint, optional| {
        const verdict = optional orelse continue;
        if (verdict.state != .honoured and verdict.state != .relaxed) continue;
        if (hint.verb == .rail and hint.args.len != 0 and (nl.net(hint.args[0]) orelse continue).index() == supply) return &.{};
    }
    return groups;
}

/// Runs before ordinary rails. The opposed actual taps share one connector
/// and one rightward midpoint supply symbol. drawn changes only after the
/// complete rail and correctly attached symbol commit; false cases fall back.
pub fn rail(c: *Canvas, nl: *const Netlist, groups: []const Group, lines: *const NetLines, requests: Requests, pins_of: []const std.ArrayList(u32), routed: []const bool, drawn: []bool) Allocator.Error!void {
    sizes(c, nl, groups, lines, requests, pins_of, routed, drawn);
    for (groups) |g| {
        const net = bound(nl, g, .{ .member = 0, .role = 2 });
        if (!eligible(g, net, lines, requests, routed, drawn) or c.s.roles[net] != .supply or lines.rail[net] != .bar) continue;
        const mapped = map(c, nl, g, &.{ .{ .member = 0, .role = 2 }, .{ .member = 1, .role = 2 } }, net, pins_of[net].items) orelse continue;
        const a, const b = .{ mapped.points[0], mapped.points[1] };
        if (a.x != b.x or a.y >= b.y or c.s.pins.items(.side)[mapped.pins[0]] != .down or c.s.pins.items(.side)[mapped.pins[1]] != .up) continue;
        if (@as(i64, a.x) + c.len.rail > std.math.maxInt(i32) or existing(c, net)) continue;
        const middle: Pt = .{ .x = a.x, .y = @intCast(@divFloor(@as(i64, a.y) + b.y, 2)) };
        const saved = wire_parts.Checkpoint.take(c);
        var accepted = false;
        defer if (!accepted) saved.restore(c);
        if (!try c.commit(net, &.{ a, b })) continue;
        if (!try c.stub(.terminal, net, middle, .right, c.len.rail)) continue;
        if (!wire_parts.symbol(c, net, mapped.pins[0..2], saved.pins, saved.ink.segs, .port)) continue;
        c.wall(); // Only the newly committed symbol stub is a wall.
        accepted = true;
        drawn[net] = true;
    }
}

/// Runs after rails and before ordinary signals/mirror replication. Each
/// complete net is atomic, including generated names/ports; on allocation
/// error its original rows survive while earlier successful nets remain.
pub fn parts(c: *Canvas, nl: *const Netlist, groups: []const Group, lines: *const NetLines, requests: Requests, pins_of: []const std.ArrayList(u32), routed: []const bool, drawn: []bool) Allocator.Error!void {
    sizes(c, nl, groups, lines, requests, pins_of, routed, drawn);
    for (groups) |g| for (specs) |spec| {
        const net = bound(nl, g, spec.ports[0]);
        if (!eligible(g, net, lines, requests, routed, drawn)) continue;
        if (c.s.roles[net] != (if (spec.output) sch.Role.output else sch.Role.internal)) continue;
        const mapped = map(c, nl, g, spec.ports[0..spec.len], net, pins_of[net].items) orelse continue;
        if (existing(c, net)) continue;
        const a = mapped.pins[0..spec.split];
        const b = mapped.pins[spec.split..spec.len];
        if (try wire_parts.draw(c, net, a, b, if (spec.output) .port else .name)) {
            drawn[net] = true;
            c.s.labeled[net] = true;
        }
    };
}

// ---- private ----

fn sizes(c: *const Canvas, nl: *const Netlist, groups: []const Group, lines: *const NetLines, requests: Requests, pins: []const std.ArrayList(u32), routed: []const bool, drawn: []const bool) void {
    assert(groups.len <= 1 and requests.ats.len == nl.graph.edgeCount());
    assert(pins.len == c.s.net_name.len and lines.style.len == pins.len);
    assert(routed.len == pins.len and drawn.len == pins.len);
}
fn portSpec(member: u5, role: u2) Port {
    return .{ .member = member, .role = role };
}
fn bound(nl: *const Netlist, g: Group, p: Port) u32 {
    return nl.graph.members(g[p.member])[owner.binding(nl, g, p.member, p.role)].index();
}
fn eligible(g: Group, net: u32, lines: *const NetLines, requests: Requests, routed: []const bool, drawn: []const bool) bool {
    if (lines.first.len != 0 or routed[net] or drawn[net] or lines.port[net] != null) return false;
    if (lines.style[net] != .auto and lines.style[net] != .cut) return false;
    for (g) |edge| if (requests.ats[edge.index()] != null) return false;
    for (requests.routes) |route| if (route.net == net) return false;
    for (lines.routes) |route| if (route.net == net) return false;
    return true;
}
fn map(c: *const Canvas, nl: *const Netlist, g: Group, ports: []const Port, net: u32, pins: []const u32) ?Mapped {
    assert(ports.len >= 2 and ports.len <= 6);
    if (pins.len != ports.len) return null;
    var result: Mapped = .{ .pins = @splat(sch.none), .points = undefined };
    for (pins) |p| {
        const pin = c.s.pins.get(p);
        const slot = for (ports, 0..) |port, i| {
            if (pin.device == g[port.member].index() and pin.index == owner.binding(nl, g, port.member, port.role)) break i;
        } else return null;
        if (result.pins[slot] != sch.none or pin.net != net or bound(nl, g, ports[slot]) != net) return null;
        result.pins[slot] = p;
        result.points[slot] = actual(c, nl, p, net) orelse return null;
    }
    for (result.pins[0..ports.len]) |p| if (p == sch.none) return null;
    return result;
}
fn actual(c: *const Canvas, nl: *const Netlist, p: u32, net: u32) ?Pt {
    const pin = c.s.pins.get(p);
    if (pin.device == sch.none or pin.device >= c.s.devices.len) return null;
    const members = nl.graph.members(.from(pin.device));
    if (pin.index >= members.len or members[pin.index].index() != net) return null;
    const row = c.s.devices.get(pin.device);
    const class = c.s.lib.at(row.class);
    if (!row.kept or !class.shows(pin.index) or sch.referencePin(c.s, pin.device, pin.index, net)) return null;
    if (class.side(pin.index, row.orient) != pin.side) return null;
    const node = c.s.deviceNode(pin.device) orelse return null;
    const origin = Pt.round(c.s.xy[node]);
    const offset = row.orient.apply(class.terminals[pin.index].at);
    const point = canvas.pinAt(c.s, p);
    if (@as(i64, origin.x) - row.grid.x + offset.x != point.x or @as(i64, origin.y) - row.grid.y + offset.y != point.y) return null;
    return point;
}
fn existing(c: *const Canvas, net: u32) bool {
    for (c.segs.items) |segment| if (segment.net == net) return true;
    return false;
}

test {
    _ = @import("ct_four_wires_test.zig");
}
