//! The deck's placement lines (steering rung 2): `upright`, `bridge`,
//! `face`, `row` and `above`, applied by the skeleton. In: the netlist, its
//! structure, and the skeleton's tables as each stage leaves them. Out: the
//! tables changed as the lines say, the rows' constraints for `levels`, and
//! a verdict per line.
//!
//! Rows and their order are difference constraints: `row a b` an equality,
//! `above a b` an edge. Lines are admitted strongest first
//! (`hints.admitOrder`), each when it closes no cycle with those already in,
//! else dropped with its preferred conflict. A line on one of a mated pair
//! also states its mirror image, kept where it fits. The engine's own
//! decisions (column links, mates, blocks, the ground drop) come after, and
//! give way.
//!
//! Contents:
//! - `pub const Relations = struct`, `Relations.find(r: *const Relations, d: u32) u32`, `Relations.refuses(r: *const Relations, gpa: Allocator, below: []const u32, u: u32, l: u32) Allocator.Error!bool`
//! - `Check.holds(ck: Check, lines: []const u32) Allocator.Error!bool`: the admission test `hints.conflict` calls
//! - `pub fn forms(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []Form, verdicts: []?Verdict) Allocator.Error!void`
//! - `pub fn ends(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32, verdicts: []?Verdict) Allocator.Error!void`
//! - `pub fn rows(gpa: Allocator, arena: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, verdicts: []?Verdict) Allocator.Error!Relations`
//! - `pub fn faces(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, mate: []const u32, gate_right: []bool, verdicts: []?Verdict) Allocator.Error!bool`
//! - `pub fn pinIndex(nl: *const Netlist, d: u32, word: []const u8) ?u32`
//! - `pub fn twoPin(kind: DeviceKind) bool`
//! - `pub fn pinName(arena: Allocator, kind: DeviceKind, k: u32) Allocator.Error![]const u8`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const structure = @import("structure.zig");
const hints = @import("hints.zig");
const skeleton = @import("skeleton.zig");

const Netlist = netlist.Netlist;
const DeviceKind = netlist.DeviceKind;
const EdgeId = netlist.EdgeId;
const Structure = structure.Structure;
const Form = skeleton.Form;
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

const honoured: Verdict = .{ .state = .honoured, .code = .ok };

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

/// `upright <dev>` and `bridge <dev>`: a drawn transistor, or a two-pin
/// device on two nets, stands in a column or bridges.
pub fn forms(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []Form, verdicts: []?Verdict) Allocator.Error!void {
    _ = arena;
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .upright and h.verb != .bridge) continue;
        verdicts[i] = for (h.args) |name| {
            const d = (nl.device(name) orelse break reject(.unknown_name)).index();
            const pins = c.members(EdgeId.from(d));
            const ok = drawn[d] and switch (kinds[d]) {
                .mosfet, .bjt, .jfet, .mesfet => h.verb == .upright and pins.len >= 3 and pins[0].index() != pins[2].index(),
                else => twoPin(kinds[d]) and pins.len >= 2 and pins[0].index() != pins[1].index(),
            };
            if (!ok) break reject(.not_placeable);
        } else if (h.args.len == 0) reject(.bad_args) else honoured;
        if (verdicts[i].?.state != .honoured) continue;
        for (h.args) |name| form[nl.device(name).?.index()] = if (h.verb == .upright) .vertical else .horizontal;
    }
}

/// `face <dev> <end> up|down`: which of a vertical device's ends is up.
pub fn ends(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32, verdicts: []?Verdict) Allocator.Error!void {
    _ = arena;
    const c = &nl.graph;
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .face or h.args.len != 3) continue;
        const dir = h.args[2];
        const up = std.mem.eql(u8, dir, "up");
        if (!up and !std.mem.eql(u8, dir, "down")) continue;
        const d = (nl.device(h.args[0]) orelse {
            verdicts[i] = reject(.unknown_name);
            continue;
        }).index();
        if (!drawn[d] or form[d] != .vertical) {
            verdicts[i] = reject(.not_placeable);
            continue;
        }
        const pin = pinIndex(nl, d, h.args[1]) orelse {
            verdicts[i] = reject(.unknown_name);
            continue;
        };
        const net = c.members(EdgeId.from(d))[pin].index();
        if (net != upper[d] and net != lower[d]) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        const other = if (net == upper[d]) lower[d] else upper[d];
        upper[d] = if (up) net else other;
        lower[d] = if (up) other else net;
        assert(upper[d] != lower[d]);
        verdicts[i] = honoured;
    }
}

/// Admits the `row` and `above` lines; their devices must be drawn column
/// devices, but a `row` line's may bridge (it takes the row of the line's
/// first column device).
pub fn rows(gpa: Allocator, arena: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, verdicts: []?Verdict) Allocator.Error!Relations {
    const n = nl.graph.edgeCount();
    // The valid lines' constraints, by hint: `[a, b, eq]`.
    const own = try arena.alloc([]const [3]u32, nl.hints.len);
    @memset(own, &.{});
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .row and h.verb != .above) continue;
        if (h.args.len < 2) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        var devs: std.ArrayList(u32) = .empty;
        var spans: usize = 0;
        const bad: ?hints.Code = for (h.args) |name| {
            const d = (nl.device(name) orelse break .unknown_name).index();
            if (!drawn[d]) break .not_placeable;
            if (form[d] != .vertical) {
                if (h.verb != .row) break .not_placeable;
                spans += 1;
                continue;
            }
            try devs.append(arena, d);
        } else null;
        if (bad orelse if (devs.items.len == 0) @as(?hints.Code, .not_placeable) else null) |code| {
            verdicts[i] = reject(code);
            continue;
        }
        if (devs.items.len == 1 and spans == 0) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        var cs: std.ArrayList([3]u32) = .empty;
        const eq: u32 = @intFromBool(h.verb == .row);
        for (devs.items[0 .. devs.items.len - 1], devs.items[1..]) |a, b| {
            if (a == b) continue;
            assert(devs.items.len >= 2);
            try cs.append(arena, .{ if (eq == 1) devs.items[0] else a, b, eq });
        }
        own[i] = cs.items;
    }
    var admitted: std.ArrayList(u32) = .empty;
    defer admitted.deinit(gpa);
    var held: std.ArrayList([3]u32) = .empty;
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
        verdicts[i] = honoured;
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
        if (image.items.len == 0) continue;
        try held.appendSlice(arena, image.items);
        if (!try consistent(gpa, n, held.items)) held.shrinkRetainingCapacity(held.items.len - image.items.len);
    }
    const class = try arena.alloc(u32, n);
    for (class, 0..) |*k, d| k.* = @intCast(d);
    var edges: std.ArrayList([2]u32) = .empty;
    const bridge_row = try arena.alloc(u32, n);
    @memset(bridge_row, none);
    // Bridges, later lines last so they win; each mate takes the image row.
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .row or verdicts[i] == null or verdicts[i].?.state != .honoured) continue;
        var first: u32 = none;
        for (h.args) |name| {
            const d = nl.device(name).?.index();
            if (form[d] == .vertical and first == none) first = d;
        }
        for (h.args) |name| {
            const b = nl.device(name).?.index();
            if (form[b] == .vertical) continue;
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
/// Returns false when a line turned a mated pair's gates out of their
/// mirror.
pub fn faces(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, mate: []const u32, gate_right: []bool, verdicts: []?Verdict) Allocator.Error!bool {
    const before = try arena.dupe(bool, gate_right);
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    const n = c.edgeCount();
    // Later lines win: apply in file order, then mirror onto unnamed mates.
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .face) continue;
        if (verdicts[i] != null) continue; // an end's, or rejected
        if (h.args.len != 3) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        const right = std.mem.eql(u8, h.args[2], "right");
        if (!right and !std.mem.eql(u8, h.args[2], "left")) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        const d = (nl.device(h.args[0]) orelse {
            verdicts[i] = reject(.unknown_name);
            continue;
        }).index();
        const pin = pinIndex(nl, d, h.args[1]) orelse {
            verdicts[i] = reject(.unknown_name);
            continue;
        };
        const side_pin = switch (kinds[d]) {
            .mosfet, .bjt, .jfet, .mesfet => pin == 1,
            else => false,
        };
        if (!drawn[d] or form[d] != .vertical or !side_pin) {
            verdicts[i] = reject(.not_placeable);
            continue;
        }
        gate_right[d] = right;
        verdicts[i] = honoured;
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
        const gated = switch (kinds[d]) {
            .mosfet, .bjt, .jfet, .mesfet => true,
            else => false,
        };
        if (gated and gate_right[m] == gate_right[d] and before[m] != before[d]) return false;
    }
    return true;
}

/// Pin `word` of device `d`: a terminal name of its kind (`d g s b`, `c b
/// e`, `a b` for two pins, `p n` for a source, or the pin's number from 1),
/// or a net it touches.
pub fn pinIndex(nl: *const Netlist, d: u32, word: []const u8) ?u32 {
    const c = &nl.graph;
    const pins = c.members(EdgeId.from(d));
    for (terminals(c.edges.items(.kind)[d]), 0..) |name, k| if (k < pins.len and std.mem.eql(u8, name, word)) return @intCast(k);
    if (hints.int(word)) |k| if (k >= 1 and k <= pins.len) return @intCast(k - 1);
    const net = nl.net(word) orelse return null;
    for (pins, 0..) |p, k| if (p == net) return @intCast(k);
    return null;
}

/// A device of `kind` that `upright` and `bridge` take: two pins the
/// current passes through.
pub fn twoPin(kind: DeviceKind) bool {
    return switch (kind) {
        .resistor, .capacitor, .inductor, .vsource, .isource, .diode, .vswitch, .cswitch => true,
        else => false,
    };
}

/// The name `pinIndex` reads for pin `k` of a device of `kind`: its
/// terminal's, else its number from 1.
pub fn pinName(arena: Allocator, kind: DeviceKind, k: u32) Allocator.Error![]const u8 {
    const names = terminals(kind);
    if (k < names.len) return names[k];
    return std.fmt.allocPrint(arena, "{d}", .{k + 1});
}

// ---- private ----

fn terminals(kind: DeviceKind) []const []const u8 {
    return switch (kind) {
        .mosfet, .jfet, .mesfet => &.{ "d", "g", "s", "b" },
        .bjt => &.{ "c", "b", "e", "s" },
        .resistor, .capacitor, .inductor, .diode, .vswitch, .cswitch => &.{ "a", "b" },
        .vsource, .isource => &.{ "p", "n" },
        else => &.{},
    };
}

fn reject(code: hints.Code) Verdict {
    return .{ .state = .rejected, .code = code };
}

fn namedFace(nl: *const Netlist, verdicts: []const ?Verdict, d: u32) bool {
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .face or h.args.len != 3 or verdicts[i] == null or verdicts[i].?.state != .honoured) continue;
        if (nl.device(h.args[0]).?.index() == d) return true;
    }
    return false;
}

/// Whether equalities and edges (`[a, b, 1]`, `[a, b, 0]`) over `n` devices
/// admit levels: no edge within a class, no cycle among classes (Kahn).
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
    const indeg = try gpa.alloc(u32, n);
    defer gpa.free(indeg);
    @memset(indeg, 0);
    for (cs) |k| if (k[2] == 0) {
        if (r.find(k[0]) == r.find(k[1])) return false;
        indeg[r.find(k[1])] += 1;
    };
    var queue: std.ArrayList(u32) = .empty;
    defer queue.deinit(gpa);
    for (0..n) |d| if (r.find(@intCast(d)) == d and indeg[d] == 0) try queue.append(gpa, @intCast(d));
    var done: usize = 0;
    while (queue.pop()) |k| {
        done += 1;
        for (cs) |e| if (e[2] == 0 and r.find(e[0]) == k) {
            const t = r.find(e[1]);
            indeg[t] -= 1;
            if (indeg[t] == 0) try queue.append(gpa, t);
        };
    }
    var classes: usize = 0;
    for (0..n) |d| classes += @intFromBool(r.find(@intCast(d)) == d);
    assert(done <= classes);
    return done == classes;
}
