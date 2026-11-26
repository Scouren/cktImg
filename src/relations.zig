//! The deck's placement lines (steering rung 2): `upright`, `bridge`,
//! `face`, `row` and `above`, applied by the skeleton. In: the netlist, its
//! structure, and the skeleton's tables as each stage leaves them. Out: the
//! tables changed as the lines say, the rows' constraints for `levels`, and
//! a verdict per line.
//!
//! Rows and their order are difference constraints: `row a b` an equality,
//! `above a b` an edge.
//!
//! Human Rules:
//! - relations.1 (invariant) `driver <dev> apart` draws a two-pin
//!   independent source apart, left of the circuit, upright between its
//!   net's symbol and ground; `driver <dev> inline` draws a device in the
//!   circuit. `drivers`
//! - relations.2 (invariant) A device an `upright` line names stands in a
//!   column, one a `bridge` line names lies flat between columns; a
//!   transistor only stands. `forms`
//!   Narrowing: no controlled source (E, G, F, H) is taken, which the
//!   general form admits (`twoPin`).
//! - relations.3 (choice) Of lines setting one value (a device's form, an
//!   end, a driver), the preferred stands, applied last: the deck's own
//!   ranking of its lines. `forms`
//! - relations.4 (invariant) `face <dev> <end> up|down` puts that end of
//!   an upright device up or down. `ends`
//! - relations.5 (invariant) The upright devices a `row` line names stand
//!   on one row; a bridge or block it names takes the row of the line's
//!   anchor (`anchored.anchor`: its first upright device, else its first
//!   block, else its first device). `rows`
//! - relations.6 (invariant) Each upright device an `above` line names
//!   stands on a row above the next one's; its flat devices stand by
//!   their anchor (`anchored.zig`). `rows`
//! - relations.7 (choice) Of `row` and `above` lines that close a cycle,
//!   the strongest stand and the rest are dropped with their preferred
//!   conflict: the deck's own ranking of its lines. `rows`
//! - relations.8 (unmeasured) A `row` or `above` line on mated devices also
//!   holds for their mirror images, where those are drawn upright and the
//!   image contradicts no line; a bridge's mate takes the image row. `rows`
//! - relations.9 (choice) The engine's own column links, mates, blocks and
//!   ground drop give way to the `row` and `above` lines: the deck is the
//!   user's word. `Relations.refuses`
//! - relations.10 (invariant) `face <dev> g left|right` puts a transistor's
//!   gate (or base) on that side; on a flat part, the named end stands on
//!   that side. `faces`
//!   Narrowing: a flat part by its pin count, as `sketch.fits` turns it;
//!   the device model's flat part also takes a four-pin switch and leaves
//!   out a two-port box.
//! - relations.11 (unmeasured) A `face` line on one of a mated pair turns
//!   the unnamed mate's gate the other way; a flat part's mate is not
//!   turned with it. `faces`
//! - relations.12 (invariant) A drawing whose mated pair's gates a line
//!   turned to face the same way is not drawn mirrored. `faces`
//!
//! Contents:
//! - `pub const Relations = struct`, `Relations.find(r: *const Relations, d: u32) u32`, `Relations.refuses(r: *const Relations, gpa: Allocator, below: []const u32, u: u32, l: u32) Allocator.Error!bool`
//! - `Check.holds(ck: Check, lines: []const u32) Allocator.Error!bool`: the admission test `hints.conflict` calls
//! - `pub fn drivers(gpa: Allocator, nl: *const Netlist, drawn: []bool, verdicts: []?Verdict) Allocator.Error!void`
//! - `pub fn forms(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []Form, verdicts: []?Verdict) Allocator.Error!void`
//! - `pub fn ends(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32, verdicts: []?Verdict) Allocator.Error!void`
//! - `pub fn rows(gpa: Allocator, arena: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, verdicts: []?Verdict) Allocator.Error!Relations`
//! - `pub fn faces(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, mate: []const u32, gate_right: []bool, left_end: []skeleton.End, verdicts: []?Verdict) Allocator.Error!bool`
//! - `pub fn pinIndex(nl: *const Netlist, d: u32, word: []const u8) ?u32`
//! - `pub fn twoPin(kind: DeviceKind) bool`
//! - `pub fn pinName(arena: Allocator, kind: DeviceKind, k: u32) Allocator.Error![]const u8`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const structure = @import("structure.zig");
const hints = @import("hints.zig");
const skeleton = @import("skeleton.zig");
const anchored = @import("anchored.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const Structure = structure.Structure;
const Form = skeleton.Form;
const Side = @import("library.zig").Side;
const Verdict = hints.Verdict;
const none = structure.none;

/// The rows the admitted `row` and `above` lines hold.
pub const Relations = struct {
    /// Per device, its representative: devices a `row` line holds level
    /// share one.
    class: []u32,
    /// `[a, b]`: a's row above b's.
    edges: []const [2]u32,
    /// Per bridge a `row` line names: a column device whose row it takes;
    /// `none` for the rest.
    bridge_row: []const u32,

    /// The representative of `d`'s class.
    pub fn find(r: *const Relations, d: u32) u32 {
        var k = d;
        var steps: usize = 0;
        while (r.class[k] != k) : (steps += 1) {
            assert(steps < r.class.len);
            k = r.class[k];
        }
        return k;
    }

    /// Whether a column link `u` over `l`, with the links in `below`, puts
    /// some device above another the lines hold level with or above it: `l`
    /// reaches `u` through the lines and the links, or shares its class.
    pub fn refuses(r: *const Relations, gpa: Allocator, below: []const u32, u: u32, l: u32) Allocator.Error!bool {
        if (r.edges.len == 0 and !r.merged()) return false;
        const n = r.class.len;
        assert(below.len == n);
        const target = r.find(u);
        if (r.find(l) == target) return true;
        const seen = try gpa.alloc(bool, n);
        defer gpa.free(seen);
        @memset(seen, false);
        var stack: std.ArrayList(u32) = .empty;
        defer stack.deinit(gpa);
        try stack.append(gpa, r.find(l));
        seen[r.find(l)] = true;
        while (stack.pop()) |k| {
            if (k == target) return true;
            // Out of class k: its members' links and the lines' edges.
            for (0..n) |d| {
                if (r.find(@intCast(d)) != k) continue;
                if (below[d] != none) try visit(r, gpa, &stack, seen, below[d]);
            }
            for (r.edges) |e| if (r.find(e[0]) == k) try visit(r, gpa, &stack, seen, e[1]);
        }
        return false;
    }

    fn merged(r: *const Relations) bool {
        for (r.class, 0..) |k, d| if (k != d) return true;
        return false;
    }

    fn visit(r: *const Relations, gpa: Allocator, stack: *std.ArrayList(u32), seen: []bool, d: u32) !void {
        const k = r.find(d);
        if (seen[k]) return;
        seen[k] = true;
        try stack.append(gpa, k);
    }
};

/// The admission test for a set of row lines: their constraints hold
/// together.
const Check = struct {
    gpa: Allocator,
    n: usize,
    own: []const []const [3]u32,

    pub fn holds(ck: Check, lines: []const u32) Allocator.Error!bool {
        var all: std.ArrayList([3]u32) = .empty;
        defer all.deinit(ck.gpa);
        for (lines) |i| try all.appendSlice(ck.gpa, ck.own[i]);
        return consistent(ck.gpa, ck.n, all.items);
    }
};

/// `driver <dev> apart|inline`: a two-pin source drawn apart, left of the
/// circuit (as one driving a terminal net is), or a device in it.
pub fn drivers(gpa: Allocator, nl: *const Netlist, drawn: []bool, verdicts: []?Verdict) Allocator.Error!void {
    const c = &nl.graph;
    const order = try hints.applyOrder(gpa, nl.hints);
    defer gpa.free(order);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .driver) continue;
        if (h.args.len != 2) {
            verdicts[i] = .of(.bad_args);
            continue;
        }
        const apart = std.mem.eql(u8, h.args[1], "apart");
        if (!apart and !std.mem.eql(u8, h.args[1], "inline")) {
            verdicts[i] = .of(.bad_args);
            continue;
        }
        const d = (nl.device(h.args[0]) orelse {
            verdicts[i] = .of(.unknown_name);
            continue;
        }).index();
        // Apart, a source stands upright between its net's symbol and
        // ground: only a two-pin source is drawn so.
        const source = device.of(c.edges.items(.kind)[d]).source == .independent and c.members(EdgeId.from(d)).len == 2;
        if (c.members(EdgeId.from(d)).len == 0 or (apart and !source)) {
            verdicts[i] = .of(.not_placeable);
            continue;
        }
        drawn[d] = !apart;
        verdicts[i] = .of(.ok);
    }
}

/// `upright <dev>` and `bridge <dev>`: a drawn device whose path joins two
/// nets stands in a column or bridges; one with a gate stands only.
pub fn forms(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []Form, verdicts: []?Verdict) Allocator.Error!void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    const order = try hints.applyOrder(arena, nl.hints);
    defer arena.free(order);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .upright and h.verb != .bridge) continue;
        verdicts[i] = .of(for (h.args) |name| {
            const d = (nl.device(name) orelse break .unknown_name).index();
            const a, const b = nl.path(EdgeId.from(d)) orelse break .not_placeable;
            const takes = if (device.isTransistor(kinds[d])) h.verb == .upright else twoPin(kinds[d]);
            if (!drawn[d] or !takes or a == b) break .not_placeable;
        } else if (h.args.len == 0) .bad_args else .ok);
        if (verdicts[i].?.state != .honoured) continue;
        for (h.args) |name| form[nl.device(name).?.index()] = if (h.verb == .upright) .vertical else .horizontal;
    }
}

/// `face <dev> <end> up|down`: which of a vertical device's ends is up.
pub fn ends(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32, verdicts: []?Verdict) Allocator.Error!void {
    const c = &nl.graph;
    const order = try hints.applyOrder(arena, nl.hints);
    defer arena.free(order);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .face or h.args.len != 3) continue;
        const side = h.verb.side(Side, h.args[2]) orelse continue;
        if (side.isHorizontal()) continue; // a gate's side: `faces` reads it
        const up = side == .up;
        const d = (nl.device(h.args[0]) orelse {
            verdicts[i] = .of(.unknown_name);
            continue;
        }).index();
        if (!drawn[d] or form[d] != .vertical) {
            verdicts[i] = .of(.not_placeable);
            continue;
        }
        const pin = pinIndex(nl, d, h.args[1]) orelse {
            verdicts[i] = .of(.unknown_name);
            continue;
        };
        const net = c.members(EdgeId.from(d))[pin].index();
        if (net != upper[d] and net != lower[d]) {
            verdicts[i] = .of(.bad_args);
            continue;
        }
        const other = if (net == upper[d]) lower[d] else upper[d];
        upper[d] = if (up) net else other;
        lower[d] = if (up) other else net;
        assert(upper[d] != lower[d]);
        verdicts[i] = .of(.ok);
    }
}

/// Admits the `row` and `above` lines; their devices must be drawn. A
/// flat one (a bridge, a block) takes no part in the rows' constraints: in
/// a `row` it takes the row of the line's anchor (`anchored.anchor`), in an
/// `above` its anchor's column (`anchored.place`).
pub fn rows(gpa: Allocator, arena: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, verdicts: []?Verdict) Allocator.Error!Relations {
    const n = nl.graph.edgeCount();
    // The valid lines' constraints, by hint: `[a, b, eq]`.
    const own = try arena.alloc([]const [3]u32, nl.hints.len);
    @memset(own, &.{});
    const order = try hints.applyOrder(arena, nl.hints);
    defer arena.free(order);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .row and h.verb != .above) continue;
        if (h.args.len < 2) {
            verdicts[i] = .of(.bad_args);
            continue;
        }
        var devs: std.ArrayList(u32) = .empty;
        var spans: usize = 0;
        const bad: ?hints.Code = each: for (h.args, 0..) |name, k| {
            const d = (nl.device(name) orelse break .unknown_name).index();
            if (!drawn[d]) break .not_placeable;
            for (h.args[0..k]) |seen| if (std.mem.eql(u8, seen, name)) break :each .bad_args;
            if (form[d] != .vertical) {
                spans += 1;
                continue;
            }
            try devs.append(arena, d);
        } else null;
        if (bad) |code| {
            verdicts[i] = .of(code);
            continue;
        }
        if (devs.items.len == 1 and spans == 0) {
            verdicts[i] = .of(.bad_args);
            continue;
        }
        var cs: std.ArrayList([3]u32) = .empty;
        const eq: u32 = @intFromBool(h.verb == .row);
        if (devs.items.len >= 2) for (devs.items[0 .. devs.items.len - 1], devs.items[1..]) |a, b| {
            if (a == b) continue;
            assert(devs.items.len >= 2);
            try cs.append(arena, .{ if (eq == 1) devs.items[0] else a, b, eq });
        };
        own[i] = cs.items;
    }
    var admitted: std.ArrayList(u32) = .empty;
    defer admitted.deinit(gpa);
    var held: std.ArrayList([3]u32) = .empty;
    var images: std.ArrayList([]const [3]u32) = .empty;
    const check: Check = .{ .gpa = gpa, .n = n, .own = own };
    for (try hints.admitOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if ((h.verb != .row and h.verb != .above) or verdicts[i] != null) continue;
        try admitted.append(gpa, i);
        if (!try check.holds(admitted.items)) {
            _ = admitted.pop();
            verdicts[i] = try hints.conflict(gpa, arena, check, admitted.items, i, .cycle);
            continue;
        }
        verdicts[i] = .of(.ok);
        try held.appendSlice(arena, own[i]);
        // Its mirror image, where the symmetry has one and it fits.
        var image: std.ArrayList([3]u32) = .empty;
        for (own[i]) |k| {
            const a = st.device_mate[k[0]];
            const b = st.device_mate[k[1]];
            if (a == none or b == none or (a == k[0] and b == k[1])) continue;
            if (!drawn[a] or !drawn[b] or form[a] != .vertical or form[b] != .vertical) continue;
            try image.append(arena, .{ a, b, k[2] });
        }
        if (image.items.len != 0) try images.append(arena, image.items);
    }
    // The images after every line, the strongest line's first: a line
    // admitted later stands, and the image that contradicts it goes.
    for (images.items) |image| {
        try held.appendSlice(arena, image);
        if (!try consistent(gpa, n, held.items)) held.shrinkRetainingCapacity(held.items.len - image.len);
    }
    assert(try consistent(gpa, n, held.items));
    const class = try arena.alloc(u32, n);
    for (class, 0..) |*k, d| k.* = @intCast(d);
    var edges: std.ArrayList([2]u32) = .empty;
    const bridge_row = try arena.alloc(u32, n);
    @memset(bridge_row, none);
    // Bridges, the preferred line last so it wins; each mate takes the image row.
    for (try hints.applyOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if (h.verb != .row or verdicts[i] == null or verdicts[i].?.state != .honoured) continue;
        const first = nl.device(h.args[anchored.anchor(nl, form, h.args)]).?.index();
        for (h.args) |name| {
            const b = nl.device(name).?.index();
            if (form[b] == .vertical or b == first) continue;
            bridge_row[b] = first;
            const mb = st.device_mate[b];
            const mf = st.device_mate[first];
            if (mb != none and mb != b and drawn[mb] and form[mb] != .vertical and mf != none and drawn[mf] and form[mf] == .vertical) bridge_row[mb] = mf;
        }
    }
    var out: Relations = .{ .class = class, .edges = &.{}, .bridge_row = bridge_row };
    for (held.items) |k| if (k[2] == 1) {
        const a = out.find(k[0]);
        const b = out.find(k[1]);
        if (a != b) class[a] = b;
    };
    for (held.items) |k| if (k[2] == 0) try edges.append(arena, .{ k[0], k[1] });
    out.edges = edges.items;
    return out;
}

/// `face <dev> <side pin> left|right`: a transistor's gate (or base) side;
/// on a mated pair, the mate turns the other way unless a line names it.
/// On a flat part, the end named stands on that side (`left_end`); its mate
/// is not turned with it. Returns false when a line turned a mated pair's
/// gates out of their mirror.
pub fn faces(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, mate: []const u32, gate_right: []bool, left_end: []skeleton.End, verdicts: []?Verdict) Allocator.Error!bool {
    const before = try arena.dupe(bool, gate_right);
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    const n = c.edgeCount();
    // The preferred line wins: applied last. Then mirror onto unnamed mates.
    for (try hints.applyOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if (h.verb != .face) continue;
        if (verdicts[i] != null) continue; // an end's, or rejected
        if (h.args.len != 3) {
            verdicts[i] = .of(.bad_args);
            continue;
        }
        const side = h.verb.side(Side, h.args[2]);
        const right = side == .right;
        if (!right and side != .left) {
            verdicts[i] = .of(.bad_args);
            continue;
        }
        const d = (nl.device(h.args[0]) orelse {
            verdicts[i] = .of(.unknown_name);
            continue;
        }).index();
        const pin = pinIndex(nl, d, h.args[1]) orelse {
            verdicts[i] = .of(.unknown_name);
            continue;
        };
        // A flat part: one of its two ends on that side. Narrowing: by its
        // pin count, as `sketch.fits` turns it; the device model's flat part
        // (`device.isPart`, an end of its path) also takes a four-pin switch
        // and leaves out a two-port box.
        if (drawn[d] and form[d] == .horizontal and c.members(EdgeId.from(d)).len == 2) {
            left_end[d] = if ((pin == 0) != right) .first else .second;
            verdicts[i] = .of(.ok);
            continue;
        }
        if (!drawn[d] or form[d] != .vertical or pin != (device.of(kinds[d]).gate orelse none)) {
            verdicts[i] = .of(.not_placeable);
            continue;
        }
        gate_right[d] = right;
        verdicts[i] = .of(.ok);
    }
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .face or verdicts[i] == null or verdicts[i].?.state != .honoured or h.args.len != 3) continue;
        const d = nl.device(h.args[0]).?.index();
        const m = mate[d];
        if (m == none or m == d or namedFace(nl, verdicts, m)) continue;
        gate_right[m] = !gate_right[d];
    }
    for (0..n) |d| {
        const m = mate[d];
        if (m == none or m == d or !drawn[d] or form[d] != .vertical) continue;
        if (device.isTransistor(kinds[d]) and gate_right[m] == gate_right[d] and before[m] != before[d]) return false;
    }
    return true;
}

/// Pin `word` of device `d`: a terminal name of its kind (`d g s b`, `c b
/// e`, `a b` for two pins, `p n` for a source, or the pin's number from 1),
/// or a net it touches.
pub fn pinIndex(nl: *const Netlist, d: u32, word: []const u8) ?u32 {
    const c = &nl.graph;
    const pins = c.members(EdgeId.from(d));
    for (device.of(c.edges.items(.kind)[d]).names, 0..) |name, k| if (k < pins.len and std.mem.eql(u8, name, word)) return @intCast(k);
    if (hints.int(word)) |k| if (k >= 1 and k <= pins.len) return @intCast(k - 1);
    const net = nl.net(word) orelse return null;
    for (pins, 0..) |p, k| if (p == net) return @intCast(k);
    return null;
}

/// A device of `kind` that `upright` and `bridge` take, and that the
/// op-amp placement stands as a part (`opamp.zig`): a part
/// (`device.isPart`), two pins the current passes through. Narrowing: no
/// controlled source (E, G, F, H), which the general form admits; a
/// circuit with one stays on the lattice.
pub fn twoPin(kind: DeviceKind) bool {
    return device.isPart(kind) and device.of(kind).source != .controlled;
}

/// The name `pinIndex` reads for pin `k` of a device of `kind`: its
/// terminal's, else its number from 1.
pub fn pinName(arena: Allocator, kind: DeviceKind, k: u32) Allocator.Error![]const u8 {
    const names = device.of(kind).names;
    if (k < names.len) return names[k];
    return std.fmt.allocPrint(arena, "{d}", .{k + 1});
}

// ---- private ----

fn namedFace(nl: *const Netlist, verdicts: []const ?Verdict, d: u32) bool {
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .face or h.args.len != 3 or verdicts[i] == null or verdicts[i].?.state != .honoured) continue;
        if (nl.device(h.args[0]).?.index() == d) return true;
    }
    return false;
}

/// Whether equalities and edges (`[a, b, 1]`, `[a, b, 0]`) over `n` devices
/// admit levels: no edge within a class, no cycle among classes.
fn consistent(gpa: Allocator, n: usize, cs: []const [3]u32) Allocator.Error!bool {
    const class = try gpa.alloc(u32, n);
    defer gpa.free(class);
    for (class, 0..) |*k, d| k.* = @intCast(d);
    const r: Relations = .{ .class = class, .edges = &.{}, .bridge_row = &.{} };
    for (cs) |k| if (k[2] == 1) {
        const a = r.find(k[0]);
        const b = r.find(k[1]);
        if (a != b) class[a] = b;
    };
    // The rows' order among the classes is an order like the columns'.
    var edges: std.ArrayList([2]u32) = .empty;
    defer edges.deinit(gpa);
    for (cs) |k| if (k[2] == 0) {
        if (r.find(k[0]) == r.find(k[1])) return false;
        try edges.append(gpa, .{ r.find(k[0]), r.find(k[1]) });
    };
    return hints.acyclic(gpa, n, edges.items);
}
