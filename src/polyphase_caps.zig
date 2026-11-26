//! A four-section RC lattice with two capacitor banks connecting adjacent phases.
//! Each of eight external nodes has one resistor and one capacitor. The
//! resistor midpoints define the rows; both capacitor banks must prove the
//! same four-cycle. All 16 ordered device incidences are consumed.
//!
//! Contents:
//! - `pub const Part`, `pub const Port`, `pub const Pose`, `pub const Layout`
//! - `pub fn match`, `pub fn hints`

const std = @import("std");
const library = @import("library.zig");

/// Ordered terminals of one resistor or capacitor.
pub const Part = struct { cap: bool, nets: [2]u32 };
/// Actual selected-definition formal with its lowercase source spelling.
pub const Port = struct { net: u32, name: []const u8 };
/// Centre in half-symbol units, full class orientation, and symbol kind.
pub const Pose = struct { x: u8, y: u8, turn: bool, cap: bool };
/// Poses in the calling cell's original card order.
pub const Layout = [16]Pose;
const Contact = struct { part: u8, inner: u32 };
const Leaf = struct { net: u32, resistor: Contact, cap: Contact };

/// Matches a closed two-bank cycle, starting at the first declared input
/// formal. Card names, values and device order play no part in admission.
pub fn match(parts: *const [16]Part, ports: *const [8]Port) ?Layout {
    var inputs: [4]Leaf = undefined;
    var outputs: [4]Leaf = undefined;
    var n_in: usize = 0;
    var n_out: usize = 0;
    var used: u16 = 0;
    for (ports) |port| {
        const leaf: Leaf = .{
            .net = port.net,
            .resistor = contact(parts, port.net, false) orelse return null,
            .cap = contact(parts, port.net, true) orelse return null,
        };
        const bits = bit(leaf.resistor.part) | bit(leaf.cap.part);
        if (used & bits != 0 or leaf.resistor.inner == leaf.cap.inner) return null;
        for (ports) |other| if (other.net == leaf.resistor.inner or other.net == leaf.cap.inner) return null;
        used |= bits;
        switch (library.named(port.name, .net) orelse return null) {
            .in, .inp, .inn => {
                if (n_in == 4 or byMid(inputs[0..n_in], leaf.resistor.inner) != null) return null;
                inputs[n_in] = leaf;
                n_in += 1;
            },
            .out => {
                if (n_out == 4 or byMid(outputs[0..n_out], leaf.resistor.inner) != null) return null;
                outputs[n_out] = leaf;
                n_out += 1;
            },
            else => return null,
        }
    }
    if (n_in != 4 or n_out != 4 or used != std.math.maxInt(u16)) return null;
    var layout: Layout = undefined;
    var at: usize = 0;
    var visited: u16 = 0;
    for (0..4) |row| {
        const lhs = inputs[at];
        const mid = lhs.resistor.inner;
        const rhs = outputs[byMid(&outputs, mid) orelse return null];
        const next = byMid(&inputs, lhs.cap.inner) orelse return null;
        const following = outputs[byMid(&outputs, lhs.cap.inner) orelse return null];
        if (visited & bit(at) != 0 or following.cap.inner != mid) return null;
        visited |= bit(at);
        const y: u8 = @intCast(5 + 4 * row);
        layout[lhs.resistor.part] = pose(parts, lhs.resistor.part, 7, y, lhs.net);
        layout[rhs.resistor.part] = pose(parts, rhs.resistor.part, 15, y, mid);
        layout[lhs.cap.part] = pose(parts, lhs.cap.part, 7, y + 2, lhs.net);
        layout[following.cap.part] = pose(parts, following.cap.part, 15, y + 2, mid);
        at = next;
    }
    return if (at == 0) layout else null;
}

/// Writes the selected-cell placement in symbol units using the target's
/// oblique plate glyph and its ordered canonical resistor contacts.
pub fn hints(w: *std.Io.Writer, layout: Layout, names: []const []const u8, res_points_right: bool) std.Io.Writer.Error!void {
    for (layout, names) |p, name| {
        if (p.cap) try w.print("*@ weak class {s} cap_oblique\n", .{name});
        try w.print("*@ at {s} {d}.5 {d}.5 {s}\n", .{ name, p.x / 2, p.y / 2, if (p.turn != (!p.cap and res_points_right)) "R180" else "R0" });
    }
}

// ---------------- private ----------------

fn contact(parts: *const [16]Part, net: u32, cap: bool) ?Contact {
    var found: ?Contact = null;
    for (parts, 0..) |p, i| {
        if (p.cap != cap) continue;
        for (p.nets, 0..) |end, k| if (end == net) {
            if (found != null) return null;
            found = .{ .part = @intCast(i), .inner = p.nets[1 - k] };
        };
    }
    return found;
}

fn bit(i: usize) u16 {
    return @as(u16, 1) << @intCast(i);
}

fn byMid(leaves: []const Leaf, mid: u32) ?usize {
    for (leaves, 0..) |l, i| if (l.resistor.inner == mid) return i;
    return null;
}

fn pose(parts: *const [16]Part, i: u8, x: u8, y: u8, first: u32) Pose {
    const p = parts[i];
    return .{ .x = x, .y = y, .cap = p.cap, .turn = p.nets[0] != first };
}
