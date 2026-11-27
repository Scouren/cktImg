//! Native display projection of a closed switched-capacitor control bus.
//!
//! Contents
//! - `pub fn select`
//! - `pub fn json`

const std = @import("std");
const np = @import("NetlistParser");
const svg = @import("svg");
const spice = @import("schemify/spice.zig");
const port_bundle = @import("schemify/port_bundle.zig");

/// Verifies the actual native terminals and four single-segment links to distinct
/// external ports. The electrical placement stays available in full for every renderer.
pub fn select(a: std.mem.Allocator, raw: []const u8, srcs: []const []const u8, p: *const np.Placed, lib: *const np.Library) !?svg.Bundle {
    const deck = try spice.parse(a, raw);
    const b = (try port_bundle.find(a, &deck)) orelse return null;
    if (deck.devs(0).len() != 0 or b.parent.cell + 1 != deck.cells()) return null;
    const d = for (p.dev_name, 0..) |name, i| {
        if (std.ascii.eqlIgnoreCase(deck.dev_name[b.instance], name)) break i;
    } else return null;
    const class = lib.at(p.dev_class[d]);
    if (!std.ascii.eqlIgnoreCase(class.name, "block:varactor_switched_caps") or class.terminals.len != 8) return null;
    const lo, const hi = p.pinRange(d);
    if (hi - lo != class.terminals.len) return null;
    for (class.terminals, deck.ports(b.leaf.cell), deck.netsOf(b.instance), lo..) |t, formal, actual, k| {
        if (t.hidden or !std.ascii.eqlIgnoreCase(t.name, deck.netKey(b.leaf.cell, formal)) or !std.ascii.eqlIgnoreCase(p.net_name[p.pin_net[k]], deck.netKey(b.parent.cell, actual))) return null;
    }
    if (try held(a, &deck, b, srcs, p, lib)) return null;
    var out: svg.Bundle = .{ .dev = d, .first = lo + 2, .ports = undefined, .nets = undefined, .label = b.caption };
    for (&out.ports, &out.nets, out.first..) |*port, *net, bit| {
        net.* = p.pin_net[bit];
        var count: usize = 0;
        for (0..p.deviceCount()) |i| {
            const pl, const ph = p.pinRange(i);
            for (pl..ph) |k| {
                if (p.pin_net[k] != net.* or k == bit) continue;
                const role = lib.at(p.dev_class[i]).role;
                if (p.dev_name[i].len != 0 or ph != pl + 1 or (role != .input_port and role != .output_port)) return null;
                count += 1;
                port.* = i;
            }
        }
        if (count != 1) return null;
        const at = p.pin_xy[p.dev_pin0[port.*]];
        var seg = p.segments(net.*);
        const pts = seg.next() orelse return null;
        if (pts.len != 2 or seg.next() != null) return null;
        if (!(pts[0].eql(at) and pts[1].eql(p.pin_xy[bit])) and !(pts[1].eql(at) and pts[0].eql(p.pin_xy[bit]))) return null;
        for (p.labels) |l| if (l.net == net.*) return null;
    }
    return out;
}

fn held(a: std.mem.Allocator, deck: *const spice.Deck, b: port_bundle.Candidate, srcs: []const []const u8, p: *const np.Placed, lib: *const np.Library) !bool {
    // Generated top-cell roles describe the ordinary synthetic terminal symbols.
    // Only an actual, honoured original scalar presentation reserves its own access.
    if (deck.directive.len == 0) return false;
    var nl = try np.netlist.parse(a, srcs, null);
    defer nl.deinit(a);
    const roles = try np.guessRoles(a, &nl);
    const st = try np.schematic.structure.analyze(a, a, &nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, &nl, roles, &st, .{});
    const verdicts = try np.report.verdicts(a, &nl, roles, &st, &sk, p, lib);
    for (nl.hints, verdicts) |h, v| {
        if (v.state != .honoured or h.args.len == 0) continue;
        switch (h.verb) {
            .label, .wire, .port, .role, .rail, .via, .route => {},
            else => continue,
        }
        for (b.parent.nets) |n| {
            if (!std.ascii.eqlIgnoreCase(h.args[0], deck.netKey(b.parent.cell, n))) continue;
            for (deck.directive, deck.directive_cell) |line, c| {
                if (c == b.parent.cell and std.ascii.eqlIgnoreCase(line, h.text)) return true;
            }
        }
    }
    return false;
}

/// Returns the optional view's ordered atom table, leaving the original scalar JSON intact.
pub fn json(a: std.mem.Allocator, p: *const np.Placed, lib: *const np.Library, view: ?svg.Bundle) ![]const u8 {
    const b = view orelse return "[]";
    const Atom = struct { slot: usize, term: []const u8, net: []const u8, xy: [2]i32 };
    var atoms: [4]Atom = undefined;
    const class = lib.at(p.dev_class[b.dev]);
    for (&atoms, b.first..) |*atom, k| {
        const i = k - p.dev_pin0[b.dev];
        atom.* = .{ .slot = i, .term = class.terminals[i].name, .net = p.net_name[p.pin_net[k]], .xy = .{ p.pin_xy[k].x, p.pin_xy[k].y } };
    }
    return std.json.Stringify.valueAlloc(a, .{.{ .device = p.dev_name[b.dev], .label = b.label, .contact = atoms[0].xy, .atoms = atoms }}, .{});
}
