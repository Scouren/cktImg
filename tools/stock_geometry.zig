//! Checks the native symbol frames used by a source-certified local arrangement.
//!
//! Contents:
//! - `pub fn equivalent(arena: std.mem.Allocator, actual: *const np.Library, nl: *const np.netlist.Netlist, stock: []const u8) !bool`
const std = @import("std");
const np = @import("NetlistParser");
const eql = std.mem.eql;

/// Compares the actual selected device families and reachable port/rail
/// symbol roles with an independently loaded stock library. Terminal order,
/// visibility, anchors, sides and all canonical drawing operations must agree.
pub fn equivalent(arena: std.mem.Allocator, actual: *const np.Library, nl: *const np.netlist.Netlist, stock: []const u8) !bool {
    var reference = np.Library.init(arena);
    defer reference.deinit();
    var diags: std.ArrayList(np.library.ZonDiagnostic) = .empty;
    try reference.loadZon(arena, stock, &diags);
    std.debug.assert(diags.items.len == 0);
    if (actual.unit != reference.unit) return false;
    for (nl.graph.edges.items(.kind), 0..) |k, i| {
        const name = np.library.className(k, nl.modelType(np.netlist.EdgeId.from(i)));
        const x = reference.find(name) orelse return false;
        const y = actual.find(name) orelse return false;
        if (!same(reference.at(x), actual.at(y))) return false;
    }
    for ([_]np.library.Role{ .power_rail, .ground_rail, .input_port, .output_port }) |role| {
        const x = reference.findRole(role) orelse return false;
        const y = actual.findRole(role) orelse return false;
        if (!same(reference.at(x), actual.at(y))) return false;
    }
    return true;
}

// ---- private ----

fn same(x: np.library.Class, y: np.library.Class) bool {
    if (!eql(u8, x.name, y.name) or x.role != y.role or x.terminals.len != y.terminals.len or x.draw.len != y.draw.len) return false;
    for (x.terminals, y.terminals) |a, b| {
        if (!eql(u8, a.name, b.name) or !a.at.eql(b.at) or a.hidden != b.hidden or a.ground_ref != b.ground_ref or a.side != b.side) return false;
    }
    for (x.draw, y.draw) |a, b| {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        switch (a) {
            .line => |op| if (!op.a.eql(b.line.a) or !op.b.eql(b.line.b)) return false,
            .circle => |op| if (!op.c.eql(b.circle.c) or op.r != b.circle.r) return false,
            .text => |op| if (!op.at.eql(b.text.at) or op.size != b.text.size or !eql(u8, op.s, b.text.s)) return false,
            .polyline => |path| {
                if (path.len != b.polyline.len) return false;
                for (path, b.polyline) |px, py| if (!px.eql(py)) return false;
            },
        }
    }
    return true;
}
