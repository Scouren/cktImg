//! Bind stock native symbol geometry to the checked passive RC lattice.
//!
//! Contents:
//! - `pub fn write`, `pub fn plain`

const std = @import("std");
const engine = @import("NetlistParser");
const lattice = engine.polyphase_caps;

/// Emits an arrangement only for the selected raw cell with eight real
/// formals and exactly the sixteen supported ordinary two-terminal parts.
pub fn write(w: *std.Io.Writer, nl: *const engine.netlist.Netlist, formal: []const []const u8, lib: *const engine.Library) std.Io.Writer.Error!void {
    if (formal.len != 8 or nl.graph.edgeCount() != 16 or lib.find("cap_oblique") == null) return;
    var parts: [16]lattice.Part = undefined;
    for (&parts, nl.graph.edges.items(.kind), 0..) |*part, kind, i| {
        const nodes = nl.graph.members(.from(i));
        if ((kind != .resistor and kind != .capacitor) or nodes.len != 2) return;
        part.* = .{ .cap = kind == .capacitor, .nets = .{ nodes[0].index(), nodes[1].index() } };
    }
    var ports: [8]lattice.Port = undefined;
    for (&ports, formal) |*p, name| p.* = .{ .name = name, .net = (nl.net(name) orelse return).index() };
    const arrangement = lattice.match(&parts, &ports) orelse return;
    const resistor = lib.at(lib.find("res") orelse return);
    try lattice.hints(w, arrangement, nl.graph.edges.items(.name), resistor.terminals[0].at.x > 0);
}

/// A source body made only of passive cards, continuation lines and ordinary
/// comments. Source directions, directives and simulator code own their layout.
pub fn plain(body: []const u8) bool {
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimStart(u8, raw, " \t\r");
        if (line.len == 0) continue;
        switch (std.ascii.toLower(line[0])) {
            'r', 'c', '+' => {},
            '*' => if (std.mem.startsWith(u8, line, "*@") or std.ascii.startsWithIgnoreCase(line, "*.pininfo")) return false,
            else => return false,
        }
    }
    return true;
}
