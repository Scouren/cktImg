//! Ordered fourth MOS terminals, target contact capabilities, and omitted-contact reporting.
//! A target may explicitly pair a compact class with a compatible D/G/S/B symbol.
//! The SPICE row remains the source of the body identity for either class.
//!
//! Contents:
//! - `pub fn compactFor`
//! - `pub fn needsBody`
//! - `pub fn writeUnshown`

const std = @import("std");
const library = @import("library.zig");
const netlist = @import("netlist.zig");
const placed = @import("placed.zig");
const schematic = @import("schematic.zig");

/// The registered class that can safely acquire this optional fourth-contact
/// mapping. Independently edited geometry leaves both classes available by name.
pub fn compactFor(lib: *const library.Library, name: []const u8, spec: library.Spec) error{IncompatibleBody}!?library.ClassId {
    const id = lib.find(name) orelse return error.IncompatibleBody;
    const base = lib.at(id);
    if (spec.terminals.len != 4 or spec.terminals[3].hidden or
        std.ascii.eqlIgnoreCase(spec.name, base.name) or !bodyPinNames(spec.terminals)) return error.IncompatibleBody;
    // A backend may replace just the compact geometry in a symbol file.
    // Keep both classes available explicitly; the old mapping no longer fits.
    if (base.terminals.len < 3 or base.terminals.len > 4 or base.shows(3) or
        !library.sameTerminals(base.terminals[0..3], spec.terminals[0..3])) return null;
    if (base.terminals.len == 4 and !base.terminals[3].at.eql(spec.terminals[3].at)) return null;
    if (base.body_variant) |v| if (!std.ascii.eqlIgnoreCase(lib.at(v).name, spec.name)) return error.IncompatibleBody;
    return id;
}

/// A non-rail body distinct from this occurrence's source needs a contact.
/// Rail and source conventions stay with the target's compact class. A
/// caller's full four-contact class keeps showing every ordered body.
pub fn needsBody(nl: *const netlist.Netlist, roles: []const schematic.Role, e: netlist.EdgeId) bool {
    const pins = nl.graph.members(e);
    return nl.graph.edges.items(.kind)[e.index()] == .mosfet and pins.len == 4 and
        pins[3] != pins[2] and !roles[pins[3].index()].isRail();
}

/// Writes a report member only when a distinct non-rail body lacks a visible
/// landing. The device/net identity comes from its original ordered SPICE card.
pub fn writeUnshown(w: *std.Io.Writer, p: *const placed.Placed, lib: *const library.Library, nl: *const netlist.Netlist, roles: []const schematic.Role) std.Io.Writer.Error!void {
    var unshown: usize = 0;
    for (p.dev_name, p.dev_class) |name, id| {
        const e = nl.device(name) orelse continue;
        const class = lib.at(id);
        if (class.shows(3) or !needsBody(nl, roles, e)) continue;
        try w.writeAll(if (unshown == 0) "  \"unshown_bodies\": [" else ", ");
        try w.writeAll("{ \"device\": ");
        try std.json.Stringify.value(name, .{}, w);
        try w.writeAll(", \"terminal\": \"b\", \"net\": ");
        try std.json.Stringify.value(nl.graph.vertices.items(.name)[nl.graph.members(e)[3].index()], .{}, w);
        try w.print(", \"reason\": \"{s}\" }}", .{if (class.terminals.len > 3) "hidden" else "no_contact"});
        unshown += 1;
    }
    if (unshown != 0) try w.writeAll("],\n");
}

// ---------------- private ----------------

fn bodyPinNames(terms: []const library.Terminal) bool {
    for (terms, "dgsb") |term, letter| {
        if (term.name.len != 1 or std.ascii.toLower(term.name[0]) != letter) return false;
    }
    return true;
}
