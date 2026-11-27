//! A closed four-bit control interface whose exact scalar names the host can expand.
//!
//! Contents
//! - `pub const Row`
//! - `pub const Candidate`
//! - `pub fn find`
//! - `pub fn direct`

const std = @import("std");
const spice = @import("spice.zig");
const layout = @import("layout.zig");
const recognize = @import("recognize.zig");

/// Four consecutive original formal slots, in SPICE positional order.
pub const Row = struct {
    cell: u32,
    first: u32,
    nets: [4]u32,

    /// Index within the four control slots for this original cell-local net.
    pub fn index(row: Row, net: u32) ?usize {
        return std.mem.indexOfScalar(u32, &row.nets, net);
    }
};

/// Both sides of the one closed editable cell reference, with their ordered atom list.
pub const Candidate = struct {
    leaf: Row,
    parent: Row,
    instance: u32,
    expression: []const u8,
    caption: []const u8,

    /// The row belonging to the original cell, if this interface reaches it.
    pub fn row(b: Candidate, cell: u32) ?Row {
        if (cell == b.leaf.cell) return b.leaf;
        if (cell == b.parent.cell) return b.parent;
        return null;
    }
};

/// Finds the direct four-bit call in an otherwise opaque differential tuning bank.
/// Every source device, formal and ancestor is checked before the emitter may share a contact.
pub fn find(a: std.mem.Allocator, d: *const spice.Deck) std.mem.Allocator.Error!?Candidate {
    const leaf = d.findCell("varactor_switched_caps") orelse return null;
    const pins = d.ports(leaf);
    if (pins.len != 8 or d.devs(leaf).len() != 0) return null;
    for (d.code_cell) |cell| if (cell == leaf) return null;
    for ([_]usize{ 0, 1, 6, 7 }, [_][]const u8{ "von", "vop", "vcn", "vcp" }) |i, name|
        if (!std.mem.eql(u8, d.netKey(leaf, pins[i]), name)) return null;
    var atoms: [4][]const u8 = undefined;
    for (pins[2..6], &atoms, 0..) |net, *atom, k| {
        atom.* = d.netName(leaf, net);
        const word = atom.*;
        if (word.len < 4 or !std.ascii.isAlphabetic(word[0])) return null;
        const suffix = word[word.len - 3 ..];
        if (suffix[0] != '_' or suffix[1] != '3' - @as(u8, @intCast(k)) or suffix[2] != '_') return null;
        for (word[0 .. word.len - 3]) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '_') return null;
        if (k > 0 and !std.mem.eql(u8, word[0 .. word.len - 3], atoms[0][0 .. atoms[0].len - 3])) return null;
        if (d.isGlobal(d.netKey(leaf, net))) return null;
    }
    var instance: ?u32 = null;
    var parent: u32 = 0;
    for (0..d.cells()) |ci| {
        const r = d.devs(@intCast(ci));
        for (r.lo..r.hi) |i| {
            if (!std.ascii.eqlIgnoreCase(d.dev_sub[i], d.cell_name[leaf])) continue;
            if (ci == 0 or instance != null) return null;
            instance = @intCast(i);
            parent = @intCast(ci);
        }
    }
    const owner = instance orelse return null;
    for (d.dev_sub) |sub| if (std.ascii.eqlIgnoreCase(sub, d.cell_name[parent])) return null;
    const ns = d.netsOf(owner);
    if (ns.len != pins.len or d.devs(parent).len() > layout.cell_devices_max) return null;
    const first = std.mem.indexOf(u32, d.ports(parent), ns[2..6]) orelse return null;
    for (ns[2..6], atoms) |net, atom| {
        if (!std.mem.eql(u8, d.netName(parent, net), atom) or std.mem.count(u32, d.ports(parent), &.{net}) != 1) return null;
        var hits: usize = 0;
        const r = d.devs(parent);
        for (r.lo..r.hi) |i| hits += std.mem.count(u32, d.netsOf(@intCast(i)), &.{net});
        if (hits != 1) return null;
    }
    const leaf_row: Row = .{ .cell = leaf, .first = 2, .nets = pins[2..6][0..4].* };
    const parent_row: Row = .{ .cell = parent, .first = @intCast(first), .nets = ns[2..6][0..4].* };
    for ([_]Row{ leaf_row, parent_row }) |r| {
        const dir = d.pinInfo(d.netKey(r.cell, r.nets[0]));
        for (r.nets, 0..) |n, k| {
            if (d.pinInfo(d.netKey(r.cell, n)) != dir or d.port_side[d.portRange(r.cell).lo + r.first + k] != .auto) return null;
        }
    }
    return .{ .leaf = leaf_row, .parent = parent_row, .instance = owner, .expression = try std.mem.join(a, ",", &atoms), .caption = try a.print("{s}<3:0>", .{atoms[0][0 .. atoms[0].len - 3]}) };
}

/// Confirms that the ordinary drawing already ties each scalar port directly to its
/// own pin, with no wire, label or second occurrence to remove when sharing the contact.
pub fn direct(b: Candidate, d: *const spice.Deck, rec: *const recognize.Recognized, drawn: *const layout.Drawn) bool {
    if (drawn.strays != 0 or drawn.fallback != null) return false;
    for (d.directive, d.directive_cell, d.directive_line) |line, cell, n| {
        if (cell != b.parent.cell) continue;
        var h = @import("NetlistParser").hints.read(line) orelse continue;
        switch (h.verb) {
            .label, .wire, .port, .role, .rail, .via, .route => {},
            else => continue,
        }
        const arg = h.names.next() orelse continue;
        for (b.parent.nets) |net| {
            if (!std.ascii.eqlIgnoreCase(d.netKey(cell, net), arg)) continue;
            // The normal resolver records every rejected or relaxed directive by its original line.
            for (drawn.notes.items) |note| {
                const sep = std.mem.indexOfScalar(u8, note, ':') orelse continue;
                if (sep > 5 and (std.fmt.parseInt(u32, note[5..sep], 10) catch continue) == n) break;
            } else return false;
        }
    }
    const i = b.instance - d.devs(b.parent.cell).lo;
    const pins = rec.syms.pins(rec.parts.sym.items[b.instance]);
    if (pins.len != 8) return false;
    for (b.parent.nets, pins[2..6]) |n, p| {
        const v = layout.xform(drawn.orient.items[i], p.x, p.y);
        const pt = [2]i32{ drawn.x.items[i] + v[0], drawn.y.items[i] + v[1] };
        var hits: u32 = 0;
        for (drawn.mark.items) |m| {
            if (m.net != n) continue;
            if (!m.port or !std.mem.eql(i32, &m.at, &pt)) return false;
            hits += 1;
        }
        if (hits != 1) return false;
        for (drawn.wire.items) |s| if (s[0] <= pt[0] and pt[0] <= s[2] and s[1] <= pt[1] and pt[1] <= s[3]) return false;
    }
    return true;
}
