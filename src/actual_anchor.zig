//! Actual symbol anchors for cold local placement owners.
//!
//! Human Rules:
//! - actual_anchor.1 (invariant) Reanchoring changes the device grid and
//!   recomputes visible outward reach from every actual terminal. It does
//!   not rewrite the caller's class or electrical pins. Shared CT banks
//!   anchor midpoints/drains; their private chains anchor path ends/midpoints.
//!
//! Contents:
//! - `pub fn move(s: *sch.Schematic, nl: *const netlist.Netlist, d: u32, offset: library.Pt) void`
//! - `pub fn representable(s: *const sch.Schematic, nl: *const netlist.Netlist, d: u32) bool`

const std = @import("std");
const sch = @import("schematic.zig");
const netlist = @import("netlist.zig");
const library = @import("library.zig");

/// Moves a settled device's grid by its local actual offset and recomputes
/// all visible reaches. The caller owns orientation and coordinate writes;
/// hidden/reference pins stay unchanged. No allocation occurs here.
pub fn move(s: *sch.Schematic, nl: *const netlist.Netlist, d: u32, offset: library.Pt) void {
    std.debug.assert(d < s.devices.len);
    std.debug.assert(s.devices.len == nl.graph.edgeCount());
    s.devices.items(.grid)[d] = s.devices.items(.grid)[d].add(offset);
    const info = s.devices.get(d);
    const c = s.lib.at(info.class);
    const members = nl.graph.members(netlist.EdgeId.from(d));
    var reach: [4]i32 = @splat(0);
    for (c.terminals, 0..) |terminal, j| {
        if (j >= members.len or sch.referencePin(s, d, j, members[j].index())) continue;
        const side = c.side(j, info.orient) orelse continue;
        const p = info.orient.apply(terminal.at).sub(info.grid);
        reach[@backingInt(side)] = @max(reach[@backingInt(side)], @as(i32, @intCast(if (side.isHorizontal()) @abs(p.x) else @abs(p.y))));
    }
    s.devices.items(.reach)[d] = reach;
}

/// Whether every visible nonreference terminal remains in the outward
/// half-plane of its declared side after reanchoring. Negative signed
/// reach cannot be represented by the router's nonnegative reach table.
/// Does not change the caller's class, pose or electrical bindings.
pub fn representable(s: *const sch.Schematic, nl: *const netlist.Netlist, d: u32) bool {
    std.debug.assert(d < s.devices.len);
    std.debug.assert(s.devices.len == nl.graph.edgeCount());
    const info = s.devices.get(d);
    const c = s.lib.at(info.class);
    const members = nl.graph.members(netlist.EdgeId.from(d));
    for (c.terminals, 0..) |terminal, j| {
        if (j >= members.len or sch.referencePin(s, d, j, members[j].index())) continue;
        const side = c.side(j, info.orient) orelse continue;
        const p = info.orient.apply(terminal.at).sub(info.grid);
        const v = side.unit();
        if (@as(i64, p.x) * v.x + @as(i64, p.y) * v.y < 0) return false;
    }
    return true;
}
