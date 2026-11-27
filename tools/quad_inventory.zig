//! Native diagnostic of original selected-cell MOS slots before placement admission.
//!
//! Contents:
//! - `pub fn write`
const std = @import("std");
const np = @import("NetlistParser");
const Edge = np.netlist.EdgeId;
const J = std.json.Stringify;

/// Emits original MOS scope, ordered slot occupants, ambiguity reasons and
/// each supported shape's overlapping raw rectangle count.
pub fn write(j: *J, a: std.mem.Allocator, raw: []const u8, nl: *const np.netlist.Netlist) !void {
    try j.objectField("switch_rectangles");
    try j.beginObject();
    const cards = try selected(a, raw, nl);
    try j.objectField("scope");
    try j.write(if (cards == null) "unbound_original_mos" else "selected_cell");
    const rows = if (cards) |mos| try np.switch_rectangles.fromDevices(a, nl, mos) else &.{};
    try j.objectField("rows");
    try j.beginArray();
    for (rows) |r| {
        try j.beginObject();
        try j.objectField("sources");
        try nets(j, nl, &r.sources);
        try j.objectField("drains");
        try nets(j, nl, &r.drains);
        try j.objectField("slots");
        try j.beginArray();
        for (r.slots) |slot| {
            try j.beginArray();
            for (slot) |d| try j.write(nl.graph.edges.items(.name)[d.index()]);
            try j.endArray();
        }
        try j.endArray();
        try j.objectField("reasons");
        try j.beginArray();
        var reasons = r.reasons.iterator();
        while (reasons.next()) |v| try j.write(@tagName(v));
        try j.endArray();
        if (r.reasons.count() == 0) {
            var members: [4]u32 = undefined;
            for (&members, r.slots) |*e, slot| e.* = slot[0].index();
            try j.objectField("uncontested");
            try j.write(np.switch_rectangles.alone(rows, &members));
        }
        try j.endObject();
    }
    try j.endArray();
    try j.endObject();
}

// ---- private ----

fn nets(j: *J, nl: *const np.netlist.Netlist, nodes: []const np.netlist.VertexId) !void {
    try j.beginArray();
    for (nodes) |n| try j.write(nl.graph.vertices.items(.name)[n.index()]);
    try j.endArray();
}

fn selected(a: std.mem.Allocator, raw: []const u8, nl: *const np.netlist.Netlist) !?[]const Edge {
    if (nl.defs.len == 0) return null;
    const owner = nl.defs[nl.defs.len - 1].name;
    const text = std.ascii.lowerString(try a.alloc(u8, raw.len), raw);
    var input = np.netlist.OriginalCards.init(text, !std.mem.startsWith(u8, std.mem.trimStart(u8, text, " \t\r\n"), ".subckt"));
    var active = false;
    var opened = false;
    var mos: std.ArrayList(Edge) = .empty;
    while (try input.next(a)) |row| {
        if (std.mem.eql(u8, row[0], ".subckt")) {
            if (active) return null;
            active = row.len >= 2 and std.mem.eql(u8, row[1], owner);
            if (active and opened) return null;
            opened = opened or active;
            continue;
        }
        if (std.mem.eql(u8, row[0], ".ends")) {
            active = false;
            continue;
        }
        if (!active or row[0][0] != 'm') continue;
        if (row.len < 6 or mos.items.len == 128) return null;
        const d = nl.device(row[0]) orelse return null;
        if (nl.graph.edges.items(.kind)[d.index()] != .mosfet or std.mem.indexOfScalar(Edge, mos.items, d) != null) return null;
        const pins = nl.graph.members(d);
        const params = nl.params(d);
        if (pins.len != 4 or row.len != 5 + params.len) return null;
        for (pins, row[1..5]) |n, name| if (!std.mem.eql(u8, nl.graph.vertices.items(.name)[n.index()], name)) return null;
        for (params, row[5..]) |p, q| if (!std.mem.eql(u8, p, q)) return null;
        try mos.append(a, d);
    }
    return if (opened and !active) mos.items else null;
}
