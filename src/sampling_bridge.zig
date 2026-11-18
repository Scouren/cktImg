//! Four directed branches around the input and hold nodes of a diode sampler.
//! AG763 and AG1042 both put the input branch on the left and the held
//! capacitor and buffer on the right. The two output-feedback diodes remain
//! separate. A diode diamond alone does not identify this arrangement.
//!
//! Contents:
//! - `pub fn place` groups the four unmatched diodes on the existing lattice.

const std = @import("std");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const library = @import("library.zig");

const Netlist = netlist.Netlist;
const Vertex = netlist.VertexId;
const Edge = netlist.EdgeId;

/// Places each complete sampler beside its hold capacitor. The existing
/// arrays carry device cells and form/end decisions through to routing.
pub fn place(gpa: std.mem.Allocator, spans: *std.ArrayList([2]i32), nl: *const Netlist, roles: []const sch.Role, drawn: []const bool, mate: []const u32, form: []skeleton.Form, upper: []u32, lower: []u32, x: []i32, y: []i32) std.mem.Allocator.Error!void {
    const c = &nl.graph;
    std.debug.assert(x.len == c.edgeCount() and y.len == x.len);
    std.debug.assert(roles.len == c.vertexCount());
    for (nl.hints) |hint| switch (hint.verb) {
        .role, .refdes, .label, .wire, .rail, .port => {},
        else => return,
    };
    for (c.edges.items(.kind), 0..) |kind, cap| {
        if (kind != .capacitor or !drawn[cap] or form[cap] != .vertical) continue;
        const ends = c.members(Edge.from(cap));
        if (ends.len != 2) continue;
        const held = if (roles[ends[0].index()] == .sink) ends[1] else if (roles[ends[1].index()] == .sink) ends[0] else continue;
        if (upper[cap] != held.index() or roles[held.index()] != .internal) continue;
        const group = members(nl, roles, held) orelse continue;
        for (group) |d| {
            if (!drawn[d] or mate[d] != sch.none) break;
        } else {
            // Put the hold-side midpoint beside the capacitor's upper pin.
            // Try slots immediately to the left, moving the complete group
            // left of any occupied column. Each attempt passes a fixed device.
            const top = y[cap] - 2;
            var right = x[cap] - 2;
            for (0..drawn.len + 1) |_| {
                var blocked: ?i32 = null;
                for (drawn, 0..) |visible, d| {
                    if (!visible or y[d] < top or y[d] > y[cap]) continue;
                    if (x[d] < right - 2 or x[d] > right) continue;
                    if (std.mem.indexOfScalar(u32, &group, @intCast(d)) != null) continue;
                    blocked = if (blocked) |b| @min(b, x[d]) else x[d];
                }
                if (blocked) |b| {
                    right = b - 2;
                    continue;
                }
                try spans.append(gpa, .{ right - 2, x[cap] });
                for (group, 0..) |d, i| {
                    const p = c.members(Edge.from(d));
                    x[d] = right - (if (i % 2 == 0) @as(i32, 2) else 0);
                    y[d] = if (i < 2) top else y[cap];
                    form[d] = .vertical;
                    upper[d] = p[0].index();
                    lower[d] = p[1].index();
                }
                break;
            }
        }
    }
}

// ---- private ----

// The private hold midpoint joins the capacitor, two diode ends and one
// buffer input. At the other midpoint the same two outer nodes span an
// input. Two opposite diodes return the buffer output to those outer nodes.
fn members(nl: *const Netlist, roles: []const sch.Role, held: Vertex) ?[4]u32 {
    const c = &nl.graph;
    if (c.incident(held).len != 4) return null;
    var output: ?Vertex = null;
    var upper: ?Edge = null;
    var lower: ?Edge = null;
    for (c.incident(held)) |e| {
        const p = c.members(e);
        switch (c.edges.items(.kind)[e.index()]) {
            .capacitor => {},
            .diode => {
                if (p.len != 2 or p[0] == p[1]) return null;
                if (p[1] == held) {
                    upper = e;
                } else {
                    lower = e;
                }
            },
            .subckt => {
                const def = nl.defOf(e) orelse return null;
                var has_input = false;
                for (p, def.ports) |net, name| switch (library.portRole(def.ports, name)) {
                    .inp, .inn, .in => has_input = has_input or net == held,
                    .out => {
                        if (output != null) return null;
                        output = net;
                    },
                    else => {},
                };
                if (!has_input) return null;
            },
            else => return null,
        }
    }
    const a = c.members(upper orelse return null)[0];
    const k = c.members(lower orelse return null)[1];
    const out = output orelse return null;
    if (a == k or out == a or out == k or out == held) return null;
    if (roles[a.index()].isRail() or roles[k.index()].isRail() or roles[out.index()].isRail()) return null;
    if (diode(nl, out, a) == null or diode(nl, k, out) == null) return null;
    var input_upper: ?Edge = null;
    var input_lower: ?Edge = null;
    for (c.incident(a)) |e| {
        if (c.edges.items(.kind)[e.index()] != .diode) continue;
        const p = c.members(e);
        if (p.len != 2 or p[0] != a or roles[p[1].index()] != .input or c.incident(p[1]).len != 2) continue;
        const d = diode(nl, p[1], k) orelse continue;
        if (input_upper != null) return null;
        input_upper = e;
        input_lower = d;
    }
    return .{ (input_upper orelse return null).index(), upper.?.index(), input_lower.?.index(), lower.?.index() };
}

fn diode(nl: *const Netlist, from: Vertex, to: Vertex) ?Edge {
    const c = &nl.graph;
    var match: ?Edge = null;
    for (c.incident(from)) |e| {
        if (c.edges.items(.kind)[e.index()] != .diode) continue;
        const p = c.members(e);
        if (p.len != 2 or p[0] != from or p[1] != to) continue;
        if (match != null) return null;
        match = e;
    }
    return match;
}
