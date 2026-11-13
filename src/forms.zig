//! Forms and ends (issue #8, stage 3): which devices are drawn, which stand
//! upright in a column and which lie flat between columns, and each upright
//! device's upper and lower end. In: the netlist, its roles and structure;
//! for `crooked`, a laid skeleton. Out: `drawn`, `form`, `upper`, `lower`;
//! the flat parts to stand upright after all.
//!
//! Human Rules:
//! - forms.1 (choice) A card with no pins is not drawn: it has nothing to
//!   draw. A driver (`sch.isDriver`) is not drawn either, by that file's
//!   rule, unless a `driver` line says so. `classify`
//! - forms.2 (book) The book's ideal amplifier, an `E` with its low output
//!   on a ground and a gain of a thousand or more (`E1 out 0 inp inn 1e5`),
//!   is drawn as a box, the op-amp's triangle with its inputs wired, not as
//!   a part current passes. The code names no figure. `isAmplifier`
//! - forms.3 (habit) A dependent source (every `G`, and an `E` that is no
//!   ideal amplifier) is drawn with two terminals, its control pair no part
//!   of where it stands. People: 414 of 414 in 5,263 hand-drawn
//!   schematics. `isDependent`
//! - forms.4 (unmeasured) A transistor stands upright, except a shorted
//!   channel (forms.12) or a capacitor-coupled MOS channel (forms.19).
//!   `classify`
//! - forms.5 (unmeasured) A part with an end on a rail stands upright, a
//!   capacitor too. `classify`
//! - forms.6 (unmeasured) A part in series, each of its nets holding just
//!   one other channel element, stands upright; not a capacitor.
//!   `classify`
//! - forms.7 (habit) A part on the way down (one end nearer the supply,
//!   the other nearer the ground, counted through channel elements, never
//!   through a gate or another rail) stands upright; not a capacitor.
//!   People: 262 of 305 such resistors and 18 of 24 diodes in 5,263
//!   hand-drawn schematics. `classify`
//! - forms.8 (habit) A current source stands upright wherever it is.
//!   People: 76 of 83 current sources wherever they are, in those
//!   drawings. `classify`
//! - forms.9 (habit) A dependent source stands upright wherever it is.
//!   People: 398 of 414 in those drawings. `classify`
//! - forms.10 (unmeasured) A capacitor stands upright only with an end on
//!   a rail: in series or on the way down it lies flat. `classify`
//! - forms.11 (unmeasured) A part between two nets the symmetry swaps
//!   lies flat across the axis, whatever forms.5 to forms.9 say; a
//!   transistor does not. `classify`
//! - forms.12 (unmeasured) A device whose current path is shorted (a MOS
//!   dummy, both ends on one net) lies flat, a transistor too. `classify`
//! - forms.13 (order: potential) A transistor's upper end is set by its
//!   type: an n-type's drain is its upper end, a p-type's source.
//!   `ends`
//! - forms.14 (order: potential) An upright part's upper end is its end on
//!   the supply, else the end away from its end on ground, else the end
//!   fewer channel elements from the supply (ties: its first pin). `ends`
//! - forms.15 (habit) A flat part between two nets that both hold an
//!   upright device's pin stands upright, and the drawing is laid again,
//!   when not both nets have such a pin level with the part within a device
//!   column: flat, its wire would turn a corner. People: the wire leaves
//!   both pins of a flat part straight for 44.9% of 4,443 in 5,263
//!   hand-drawn schematics (12.6% of the 6,171 laid flat here), and people
//!   stand 55% to 62% of the parts between two such nets upright. `crooked`
//!   Narrowing: only a part whose card names its two path pins alone
//!   (`isTwoEnded`); one with a side pin (a control pair, a diode's third
//!   pin) lies as a block does.
//! - forms.16 (unmeasured) A flat part with a net no upright device is on
//!   (an input's, an output's, a block's) stays flat. `crooked`
//! - forms.17 (book) Two mated parts that meet (a pair of sense resistors
//!   on the axis) lie across it, as the book draws them; the code names no
//!   figure. `crooked`
//! - forms.18 (unmeasured) In a circuit of parts, no transistor and no
//!   block, no flat part is stood up: its series parts lie along its top
//!   wire. `crooked`
//!   Narrowing: a line (`T`, `O`, `U`), a `B` source and a coupling are no
//!   block here (`isPartsOnly`).
//! - forms.19 (habit) A MOS channel with distinct drain, source and gate,
//!   neither channel end on a rail, lies flat when an end meets a capacitor
//!   and either the channel cannot reach a rail through DC paths, or no
//!   other DC path ends at that capacitor node and the opposite channel
//!   end drives another gate/base. A capacitor across the channel, from
//!   gate to channel, or shorted gives no evidence. A gate and body give
//!   no path to a rail.
//!   This includes samplers (ag-385, ag-386) and series compensation
//!   (ag-738, ag-995), but not an ordinary loaded cascode. People: 239 of
//!   243 selected MOS in 2,202 AnalogGenie drawings lie flat; 20 of 23 in
//!   the 734 AMSNet drawings. Upright reset and clamp devices are exceptions
//!   (ag-1039, ag-1054); an `upright` line wins. Evidence and named exceptions:
//!   docs/research/analoggenie.md. `classify`
//!
//! Contents:
//! - `pub fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []bool, form: []Form, verdicts: []?hints.Verdict) !void`
//! - `pub fn ends(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32) !void`
//! - `pub fn crooked(nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, column: i32, stood: []bool) bool`
//! - `pub fn isTwoEnded(nl: *const Netlist, d: u32) bool`, `pub fn isPartsOnly(nl: *const Netlist) bool`
//! - `pub fn isDependent(nl: *const Netlist, roles: []const Role, d: u32) bool`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const relations = @import("relations.zig");
const hints = @import("hints.zig");
const skeleton = @import("skeleton.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const isRail = Role.isRail;
const Structure = structure.Structure;
const Form = skeleton.Form;
const Skeleton = skeleton.Skeleton;
const none = structure.none;

/// Drawn: not a driver (unless a `driver` line says) and with pins. Vertical: a transistor, a two-pin
/// device on a rail, one in series (each of its nets holds one other
/// channel element), one on the way down (one net nearer the supply, the
/// other nearer the ground), a current source; capacitors only on a rail;
/// never a two-pin device
/// between two nets the symmetry swaps, which straddles the axis, nor a
/// device whose current path is shorted (a MOS dummy: no current flows).
/// A capacitor-coupled MOS channel lies flat under forms.19's conditions.
pub fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []bool, form: []Form, verdicts: []?hints.Verdict) !void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    assert(drawn.len == c.edgeCount());
    assert(form.len == drawn.len);
    assert(roles.len == c.vertexCount());
    for (drawn, 0..) |*dr, d| {
        dr.* = c.members(EdgeId.from(d)).len > 0 and !sch.isDriver(c, roles, @intCast(d));
    }
    try relations.drivers(gpa, nl, drawn, verdicts);
    // Channel elements on each net: the ends of every path but a capacitor's.
    const count = try gpa.alloc(u32, c.vertexCount());
    defer gpa.free(count);
    @memset(count, 0);
    for (0..c.edgeCount()) |d| {
        if (!drawn[d] or !device.of(kinds[d]).dc) continue;
        for (pathNets(nl, roles, @intCast(d)) orelse continue) |net| count[net] += 1;
    }
    const from_supply = try railDistance(gpa, nl, roles, drawn, .supply);
    defer gpa.free(from_supply);
    const from_ground = try railDistance(gpa, nl, roles, drawn, .sink);
    defer gpa.free(from_ground);
    for (form, 0..) |*f, d| {
        f.* = .horizontal;
        if (!drawn[d]) continue;
        // A box has no path, and a shorted path passes no current.
        const a, const b = pathNets(nl, roles, @intCast(d)) orelse continue;
        if (a == b) continue;
        const k = device.of(kinds[d]);
        const on_rail = isRail(roles[a]) or isRail(roles[b]);
        const capacitive = coupled: {
            if (kinds[d] != .mosfet or on_rail) break :coupled false;
            const gate = c.members(EdgeId.from(d))[k.gate.?].index();
            if (gate == a or gate == b) break :coupled false;
            assert(count[a] > 0);
            assert(count[b] > 0);
            // Both ends share DC reachability through this channel. Gate
            // and body connections, and the capacitor, do not conduct it.
            const isolated = from_supply[a] == none and from_ground[a] == none;
            for ([_]u32{ a, b }) |net| {
                const opposite = if (net == a) b else a;
                if (!isolated) {
                    if (count[net] != 1) continue;
                    const drives = for (c.incident(VertexId.from(opposite))) |e| {
                        if (!drawn[e.index()]) continue;
                        const side = device.of(kinds[e.index()]).gate orelse continue;
                        if (c.members(e)[side].index() == opposite) break true;
                    } else false;
                    if (!drives) continue;
                }
                for (c.incident(VertexId.from(net))) |e| {
                    if (!drawn[e.index()] or kinds[e.index()] != .capacitor) continue;
                    const pins = c.members(e);
                    const other = pins[@intFromBool(pins[0].index() == net)].index();
                    if (other != net and other != gate and other != opposite) break :coupled true;
                }
            }
            break :coupled false;
        };
        if (capacitive) continue;
        const series = k.dc and count[a] == 2 and count[b] == 2;
        // On the way down: people stand 262 of 305 such resistors and 18
        // of 24 diodes upright in 5,263 hand-drawn schematics, and 76 of
        // 83 current sources wherever they are.
        const down = k.dc and
            (from_supply[a] < from_supply[b] and from_ground[a] > from_ground[b] or
                from_supply[a] > from_supply[b] and from_ground[a] < from_ground[b]);
        const straddles = st.net_mate[a] == b;
        // A dependent source stands upright wherever it is, as a
        // current source does: 398 of 414 in those drawings.
        const source = (k.current and k.source == .independent) or isDependent(nl, roles, @intCast(d));
        if (device.isTransistor(kinds[d]) or ((on_rail or series or down or source) and !straddles)) f.* = .vertical;
    }
}

/// Each upright device's path ends, the one nearer the supply `upper`: a
/// transistor's from its type (an n-type's drain is its upper end); a
/// part's from the rails, else the pin nearer the supply through channel
/// elements. Asserts that every upright device has a path.
pub fn ends(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32) !void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    @memset(upper, none);
    @memset(lower, none);
    const dist = try railDistance(gpa, nl, roles, drawn, .supply);
    defer gpa.free(dist);
    for (0..c.edgeCount()) |d| {
        if (!drawn[d] or form[d] != .vertical) continue;
        const e = EdgeId.from(d);
        // Only what has a path stands upright (`classify`, an `upright`
        // line, `crooked`).
        const a, const b = nl.path(e).?;
        const a_up = if (device.isTransistor(kinds[d]))
            !device.sourceUp(device.polarity(nl.modelType(e)))
        else
            roles[a] == .supply or roles[b] == .sink or
                (roles[b] != .supply and roles[a] != .sink and dist[a] <= dist[b]);
        upper[d] = if (a_up) a else b;
        lower[d] = if (a_up) b else a;
        assert(upper[d] != none and lower[d] != none);
        assert(upper[d] != lower[d]);
    }
}

/// Marks in `stood` the flat two-pin parts of `sk` that cannot be wired
/// straight, and says whether there is one: a part between two nets that
/// both hold an upright device's pin, where not both have such a pin level
/// with the part within a device column. Flat, it would be wired round a
/// corner (the wire leaves both pins of a flat part straight for 44.9% of
/// 4,443 in 5,263 hand-drawn schematics, and for 12.6% of the 6,171 laid
/// flat here); upright, its column gives it a straight wire, and people
/// stand 55% to 62% of the parts between two such nets upright. A part
/// with a net no upright device is on (an input's, an output's, a block's)
/// stays flat, as people draw it. Not a part a line of the deck names
/// (`upright`, `bridge`), one on a rail, one between two nets the symmetry
/// swaps, one that meets its mate (a pair across the axis), or any part of
/// a circuit with no transistor and no block. `column` is a device column's width in lattice columns.
pub fn crooked(nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, column: i32, stood: []bool) bool {
    const c = &nl.graph;
    assert(stood.len == c.edgeCount());
    @memset(stood, false);
    // A circuit of parts only has no column of stages to stand a part in:
    // its series parts lie along its top wire.
    if (isPartsOnly(nl)) return false;
    var any = false;
    for (0..c.edgeCount()) |d| {
        if (!sk.drawn[d] or sk.form[d] != .horizontal or !isTwoEnded(nl, @intCast(d))) continue;
        const a = c.members(EdgeId.from(d))[0].index();
        const b = c.members(EdgeId.from(d))[1].index();
        if (a == b or isRail(roles[a]) or isRail(roles[b]) or st.net_mate[a] == b) continue;
        // Two mated parts that meet (a pair of sense resistors on the axis)
        // lie across it, as the book draws them.
        const m = st.device_mate[d];
        if (m != none and m != d and sk.drawn[m]) {
            const mp = c.members(EdgeId.from(m));
            const meet = for (mp) |net| {
                if (net.index() == a or net.index() == b) break true;
            } else false;
            if (meet) continue;
        }
        const told = for (nl.hints) |h| {
            if (h.verb != .upright and h.verb != .bridge) continue;
            const named = for (h.args) |name| {
                if ((nl.device(name) orelse continue).index() == d) break true;
            } else false;
            if (named) break true;
        } else false;
        if (told) continue;
        // Both its nets on upright devices, and one of them with no pin
        // level with the part.
        var level_ends: usize = 0;
        const between = for ([_]u32{ a, b }) |net| {
            var upright = false;
            var level = false;
            for (c.incident(VertexId.from(net))) |e| {
                const v = e.index();
                if (v == d or !sk.drawn[v] or sk.form[v] != .vertical) continue;
                upright = true;
                const row = if (sk.upper[v] == net) sk.y[v] - 1 else if (sk.lower[v] == net) sk.y[v] + 1 else sk.y[v];
                level = level or (row == sk.y[d] and @abs(sk.x[v] - sk.x[d]) <= column);
            }
            if (!upright) break false;
            level_ends += @intFromBool(level);
        } else true;
        stood[d] = between and level_ends < 2;
        any = any or stood[d];
    }
    return any;
}

/// Whether `d` has two ends and no more: a part (`device.isPart`) whose
/// card names its path's two pins alone. Narrower than the table's path: a
/// part with a side pin on its card (a control pair, a diode's third pin)
/// lies as a block does.
pub fn isTwoEnded(nl: *const Netlist, d: u32) bool {
    return device.isPart(nl.graph.edges.items(.kind)[d]) and nl.graph.members(EdgeId.from(d)).len == 2;
}

/// A circuit of parts: no transistor and no block among its cards, so no
/// column of stages. Narrower than "every device has a path": a line
/// (`T`, `O`, `U`), a `B` source and a coupling are no block here.
pub fn isPartsOnly(nl: *const Netlist) bool {
    for (nl.graph.edges.items(.kind)) |kind| {
        if (device.isTransistor(kind) or kind == .subckt) return false;
    }
    return true;
}

/// A voltage-controlled source drawn as a dependent source: a two-pin part,
/// its control pins no part of where it stands. Every `G`, and an `E` that
/// is no ideal amplifier (its low output on a ground and a gain of a
/// thousand or more, `E1 out 0 inp inn 1e5`: the book's op-amp). People
/// draw each with two terminals (414 of 414 in 5,263 hand-drawn
/// schematics).
pub fn isDependent(nl: *const Netlist, roles: []const Role, d: u32) bool {
    const k = device.of(nl.graph.edges.items(.kind)[d]);
    return k.source == .controlled and k.control == .pair and
        nl.graph.members(EdgeId.from(d)).len >= 2 and !isAmplifier(nl, roles, d);
}

// ---- private ----

/// The nets on the two ends of `d`'s current path (`Netlist.path`); null
/// for the one path the table names that is drawn as a box (`isAmplifier`).
fn pathNets(nl: *const Netlist, roles: []const Role, d: u32) ?[2]u32 {
    return if (isAmplifier(nl, roles, d)) null else nl.path(EdgeId.from(d));
}

/// The one exception to the device table: the book's ideal amplifier, an
/// `E` with its low output on a ground and a gain of a thousand or more
/// (`E1 out 0 inp inn 1e5`). Its kind has a path, but it is drawn as a
/// box, the op-amp's triangle with its inputs wired, so no rule here
/// passes current through it.
fn isAmplifier(nl: *const Netlist, roles: []const Role, d: u32) bool {
    const c = &nl.graph;
    const pins = c.members(EdgeId.from(d));
    // An unreadable gain (a parameter) is no number: not an amplifier.
    return c.edges.items(.kind)[d] == .vcvs and pins.len >= 2 and
        roles[pins[1].index()] == .sink and @abs(c.edges.items(.value)[d]) >= 1000;
}

/// Hops from a net of role `from` (a rail) through channel elements (every
/// path but a capacitor's), never through another rail; `none` where no
/// such way leads.
fn railDistance(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, from: Role) ![]u32 {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    const dist = try gpa.alloc(u32, c.vertexCount());
    errdefer gpa.free(dist);
    @memset(dist, none);
    var queue: std.ArrayList(u32) = .empty;
    defer queue.deinit(gpa);
    for (roles, 0..) |r, net| if (r == from) {
        dist[net] = 0;
        try queue.append(gpa, @intCast(net));
    };
    var head: usize = 0;
    while (head < queue.items.len) : (head += 1) {
        assert(queue.items.len <= dist.len);
        const v = queue.items[head];
        if (isRail(roles[v]) and roles[v] != from) continue;
        for (c.incident(VertexId.from(v))) |e| {
            const d = e.index();
            if (!drawn[d] or !device.of(kinds[d]).dc) continue;
            const chan = pathNets(nl, roles, d) orelse continue;
            // Through the channel only: a gate or a body on `v` is no way.
            if (chan[0] != v and chan[1] != v) continue;
            for (chan) |w| if (dist[w] == none) {
                dist[w] = dist[v] + 1;
                try queue.append(gpa, w);
            };
        }
    }
    return dist;
}
