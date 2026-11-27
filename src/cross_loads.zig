//! Differential input pairs driving two diode-connected and two reciprocal MOS loads.
//!
//! Human Rules:
//! - cross_loads.1 (bounded habit) AG215 and AG1034 put the diode-connected
//!   loads outside their reciprocal pair. The two input drain columns carry
//!   either the reciprocal devices (AG215, gates cross) or the references
//!   (AG1034, drains cross). Keep that branch alignment when ordering the row.
//! - cross_loads.2 (choice) Use the existing four mirrored load sites and
//!   their input pair's axis. Leave caller groups and cells in their places.
//!
//! The cold placement query borrows the netlist and existing cells. Its six
//! device handles live only while their recognized cross pair is visited.
//!
//! Contents:
//! - `pub fn place(nl: *const netlist.Netlist, roles: []const sch.Role, st: *const structure.Structure, mate: []const u32, drawn: []const bool, form: []const skeleton.Form, x: []i32, y: []const i32, gate_right: []bool, verdicts: []const ?hints.Verdict) void`

const std = @import("std");
const device = @import("device.zig");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");
const hints = @import("hints.zig");

const EdgeId = netlist.EdgeId;
const Branch = struct { cross: u32, diode: u32, input: u32 };

/// Arranges complete mirrored load rows before explicit gate faces. All cell
/// and device slices cover the graph. Uses no new cells or storage.
pub fn place(nl: *const netlist.Netlist, roles: []const sch.Role, st: *const structure.Structure, mate: []const u32, drawn: []const bool, form: []const skeleton.Form, x: []i32, y: []const i32, gate_right: []bool, verdicts: []const ?hints.Verdict) void {
    std.debug.assert(x.len == nl.graph.edgeCount());
    std.debug.assert(y.len == x.len and mate.len == x.len);
    for (st.block_kind, 0..) |kind, block| {
        if (kind != .cross) continue;
        const cross = st.members(block);
        if (cross.len != 2 or mate[cross[0]] != cross[1]) continue;
        const a = branch(nl, roles, cross[0], cross[1]) orelse continue;
        const b = branch(nl, roles, cross[1], cross[0]) orelse continue;
        if (mate[a.diode] != b.diode or mate[a.input] != b.input) continue;
        const inputs = nl.graph.members(EdgeId.from(a.input));
        const other = nl.graph.members(EdgeId.from(b.input));
        if (inputs[2] != other[2] or inputs[1] == other[1] or inputs[3] != other[3]) continue;
        const tail = nl.graph.incident(inputs[2]);
        if (tail.len != 3) continue;
        const driver = for (tail) |e| {
            if (e.index() != a.input and e.index() != b.input) break e;
        } else continue;
        const tail_kind = nl.graph.edges.items(.kind)[driver.index()];
        if (tail_kind != .isource and (tail_kind != .mosfet or nl.graph.members(driver)[0] != inputs[2])) continue;
        const members = [6]u32{ a.cross, b.cross, a.diode, b.diode, a.input, b.input };
        const upright = for (members) |d| {
            if (!drawn[d] or form[d] != .vertical) break false;
        } else true;
        if (!upright) continue;
        if (held(nl, st, verdicts, members)) continue;
        if (y[a.input] != y[b.input] or y[a.input] == y[a.diode]) continue;
        if (y[a.cross] != y[b.cross] or y[a.cross] != y[a.diode] or y[a.cross] != y[b.diode]) continue;
        if (x[a.cross] != -x[b.cross] or x[a.diode] != -x[b.diode] or x[a.input] != -x[b.input]) continue;
        const ref_col = x[a.input] == x[a.diode];
        if (!ref_col and x[a.input] != x[a.cross]) continue;
        const inner = @min(@abs(x[a.diode]), @abs(x[a.cross]));
        const outer = @max(@abs(x[a.diode]), @abs(x[a.cross]));
        if (inner == 0 or inner == outer) continue;
        const inside: i32 = @intCast(inner);
        const outside: i32 = @intCast(outer);
        const input_x = if (ref_col) outside else inside;
        const occupied = for (drawn, 0..) |visible, d| {
            if (visible and d != a.input and d != b.input and y[d] == y[a.input] and @abs(x[d]) == input_x) break true;
        } else false;
        if (occupied) continue;
        for ([2]Branch{ a, b }) |part| {
            const sign: i32 = if (x[part.input] < 0) -1 else 1;
            x[part.diode] = sign * outside;
            x[part.cross] = (if (ref_col) -sign else sign) * inside;
            x[part.input] = sign * input_x;
            gate_right[part.diode] = (sign < 0) == ref_col;
            gate_right[part.cross] = (x[part.cross] > 0) == ref_col;
        }
    }
}

// ---- private ----

/// Each output must have exactly the diode D/G, one reciprocal D, its
/// partner's G and one opposite-polarity input D, including all hidden pins.
fn branch(nl: *const netlist.Netlist, roles: []const sch.Role, cross: u32, other: u32) ?Branch {
    const c = &nl.graph;
    if (c.edges.items(.kind)[cross] != .mosfet or c.edges.items(.kind)[other] != .mosfet) return null;
    const e = EdgeId.from(cross);
    const pins = c.members(e);
    const peer = c.members(EdgeId.from(other));
    if (pins.len != 4 or peer.len != 4 or pins[0] == pins[1] or pins[0] != peer[1] or pins[1] != peer[0]) return null;
    if (pins[2] != pins[3] or pins[2] != peer[2] or !roles[pins[2].index()].isRail() or roles[pins[0].index()].isRail()) return null;
    const on = c.incident(pins[0]);
    if (on.len != 5) return null;
    const pol = device.polarity(nl.modelType(e));
    if (pol == .other) return null;
    var diode: ?u32 = null;
    var input: ?u32 = null;
    for (on) |edge| {
        const d = edge.index();
        if (d == cross or d == other) continue;
        const p = c.members(edge);
        if (c.edges.items(.kind)[d] != .mosfet or p.len != 4 or p[0] != pins[0]) return null;
        const typ = device.polarity(nl.modelType(edge));
        if (p[1] == p[0] and p[2] == pins[2] and p[3] == p[2] and typ == pol) {
            diode = d;
        } else if (typ != .other and typ != pol and p[1] != p[0] and p[1] != p[2] and !roles[p[2].index()].isRail() and roles[p[3].index()].isRail()) {
            input = d;
        } else return null;
    }
    return .{ .cross = cross, .diode = diode orelse return null, .input = input orelse return null };
}

fn held(nl: *const netlist.Netlist, st: *const structure.Structure, verdicts: []const ?hints.Verdict, members: [6]u32) bool {
    for (nl.hints, 0..) |hint, i| {
        const verdict = verdicts[i] orelse st.verdicts[i];
        if (verdict) |v| if (v.state != .honoured and v.state != .relaxed) continue;
        switch (hint.verb) {
            .off => return true,
            .pair, .cross, .mirror, .bank, .stack, .nogroup, .order, .cell, .at, .above, .column, .class, .kind => {},
            else => continue,
        }
        for (hint.args) |word| {
            const d = nl.device(word) orelse continue;
            if (std.mem.indexOfScalar(u32, &members, d.index()) != null) return true;
        }
    }
    return false;
}
