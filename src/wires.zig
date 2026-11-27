//! Wires (issue #8, stage 4): every net of a placed drawing, as terminal
//! symbols, wires and labels, by the book's patterns. In: a `Schematic`
//! whose devices are placed and pinned, the devices' boxes, and the
//! drawing's mirror if it has one. Out: its routes, terminal and label
//! nodes, and the nets drawn as labels.
//!
//! Human Rules:
//! - wires.1 (choice) Rails are wired first, then the symbol of an input
//!   or a bias of one pin, then the internal nets and the outputs, then
//!   the wires of the inputs and biases, each group in the canonical net
//!   order: a net wired earlier claims its room first, and the order of
//!   the cards chooses nothing. A symbol takes little room and has one
//!   place; an input's or a bias's part can always end in ports
//!   (wires.13), a wire cannot: drawn last, it takes its track among the
//!   wires it would cross (trunk.2). Over the 5,263 reference circuits,
//!   with trunk.2's crossings, against inputs and biases second:
//!   crossings 7,395 -> 7,279, corners 39,521 -> 39,185. `drawStep`
//! - wires.2 (choice) A `via` line's wire runs from the net's top-left pin
//!   to each point in turn by one L, along the row first, and skips a
//!   point neither L reaches: the line names points, not the path.
//!   `pinned`
//! - wires.3 (habit) A rail drawn as a bar takes each of its pins that
//!   faces the bar (up for a supply, down for ground) and stands no more
//!   than two units from it; a pin farther off has a symbol of its own.
//!   People: of 9,149 upright supply runs in 5,263 hand-drawn schematics,
//!   97% are no longer. `bar`
//! - wires.4 (unmeasured) A rail pin that does not face its bar, every
//!   pin when fewer than two reach the bar, and a pin whose stub to it
//!   does not fit, each have a rail symbol of their own. `bar`
//! - wires.5 (choice) A rail's bar stands one rail stub (`rail`) past the
//!   outermost of its pins facing it: the outermost pin meets it on the
//!   stub its symbol would have had. `bar`
//! - wires.6 (habit) A rail's bar that ends on its outer pins carries one
//!   symbol on each unbroken run of it, at the run's middle stub. People:
//!   1,083 of 1,140 supply bars carrying a symbol end on their outer pins.
//!   `bar`
//! - wires.7 (habit) A supply bar's run of two stubs or more is instead a
//!   named rail, where both ends fit: it goes on `rail` past its outer pins,
//!   carries no symbol, and its name stands at its right end; never a
//!   symbol and a run past both. People: 1,255 of 1,370 named bars run past
//!   both ends, the name at the right end in 1,252 of 1,256; no person
//!   draws a symbol on a bar that runs past (0 of 730). `rail_past` off,
//!   every bar is wires.6's (`config.Layout.rail_past`). `bar`
//!   Narrowing: a supply's bar only; a ground drawn as a bar ends on its
//!   outer pins.
//! - wires.8 (unmeasured) No other net's wire crosses a rail's bar or its
//!   run past its pins. `bar`
//! - wires.9 (unmeasured) A rail drawn as a plain bar brings every pin
//!   facing it to the bar however far; where the bar breaks or a pin does
//!   not reach it, each run and each pin off it carries the net's name,
//!   and a bar in one piece carries none. `bar`
//! - wires.10 (habit) A rail symbol on a two-pin part's end stands on the
//!   pin; on any other pin, and a port at a pin, one stub out from it,
//!   toward the side a `port` line asks, else the way the pin faces; a
//!   name on the pin where neither stub fits. People: on the pin 6,883 of
//!   8,367 rail symbols at a two-pin part's end in 5,263 hand-drawn
//!   schematics, 3,612 of 8,921 at a transistor's path end. `terminal`
//!   Narrowing: no name's stub is tried before the pin, as
//!   `Canvas.labelAt` would.
//! - wires.11 (habit) A bias net of two gates facing each other on one row
//!   is one straight gate line between them, a port symbol hanging from
//!   its middle. If the midpoint is occupied, two MOS gates allow a
//!   tap one quarter unit to either side, strictly inside the span, before
//!   falling back to a name. AG725 retains one VB3 feed this way. `ported`
//! - wires.12 (habit) An input's or a bias's pins standing near each other
//!   (the box round them no more than 6 units around half) are one wire
//!   with one port at a free end. People wire 87% of their inputs of two
//!   pins or more to one symbol and cut a connection past 5.5 to 7.5
//!   units (5,274 drawings). `near`
//!   Narrowing: one cut for every pin kind; per-edge cuts (gate to gate 3,
//!   gate to other 5.5, other 7.5) once the pitch is the human one.
//! - wires.13 (habit) An input or a bias whose pins stand farther apart, or
//!   whose wire has no free end for its port, has a port on a stub at each
//!   pin; a bias is never a written name. People: of 4,378 nets named
//!   `vb*` or `bias*` in 5,263 hand-drawn schematics, 3,228 carry port
//!   symbols and none a written name. `ported`
//! - wires.14 (choice) Any other net takes the first pattern that fits: a
//!   ladder, then a column or a trunk (`trunk.zig`); one no pattern fits
//!   is routed (`routes.zig`) after every pattern: a pattern is the shape
//!   a reader knows, the router what is left. `patterned`
//! - wires.15 (unmeasured) An internal net whose pins face each other in
//!   pairs along rows, one pair a row on two rows or more, is a ladder: a
//!   rung between each pair and one upright through them all at the
//!   mirror axis when it lies within every rung, else at the rungs' shared
//!   middle, as a CMFB midpoint meets its gate line. `ladder`
//! - wires.16 (choice) A bias a `wire` line wires, or a `route` or `via`
//!   line pins, carries its name once, at its top-left pin: the name
//!   joins it to its sources drawn apart, and card order chooses nothing.
//!   `wire`
//! - wires.17 to wires.19: a net joined by name, in parts (`name_parts.zig`).
//! - wires.20 (habit, bounded) After rails claim their room, a certified
//!   converter loop connects its selected local terminals before ordinary
//!   nets. Its outside pins retain the normal port/name/wire choice.
//!   All 145 selected source loops have seven continuous local trees with
//!   no crossing between them; power_loop_wires.1 names the source audit.
//!   A seeded input component gets its port at the actual tree boundary;
//!   nearby outside pins attach under wires.12's distance limit. Measure
//!   their whole cluster plus its shortest reach to the actual tree ink;
//!   the retained routing handle is not its boundary. Distant pins retain
//!   ports. This native proximity choice does not infer source block layout.
//!   Explicit styles and first-net requests abstain. `power_loop_wires.seed`
//! - wires.21 (habit, bounded) A complete CT-linked common-base bias stage
//!   keeps its two actual opposing B leads in one cut part when the direct
//!   interval fits. The five-member source observation and exclusions are
//!   ct_controls.1; this changes neither ordinary near grouping nor the
//!   whole-part fallback and later crossing cuts. `parts`
//!
//! - wires.22 (bounded observation) Successful complete resistor-load
//!   stages put their load bar through the actual resistor tips. The cold
//!   owner consumer runs after rails, uses ordinary contact checks, and
//!   declines caller styles, sequencing or later cut/label rounds. No net
//!   gets an exemption from automatic thinning. `resistor_load_wires.seed`
//! - wires.23 (bounded observation) A successfully placed complete four-side
//!   CT scene retains its source-separated components and one shared tap
//!   supply. The cold owner checks actual pins, names and same-net contacts
//!   atomically; normal trunk costs and later thinning remain. `ct_four_wires`
//!
//! - wires.24 (bounded observation) One qualified linked-load owner keeps
//!   its two downstream local resistor/drain pieces separate from remote
//!   input gates. Original caller intent and complete raw supply/body
//!   contracts select; ordinary names, contacts and thinning remain.
//!   `resistor_downstream`
//! - wires.25 (invariant) An input a `wire` line wires is one wire with
//!   one port: a trunk's, out from its free end, else the router's wire
//!   with the port out from its outermost point (`routes.port`); a pin no
//!   path reaches carries the name. `wire`
//! - wires.26 (invariant) A pin a `label ... at` line names carries the
//!   net's name and joins no wire; the net's other pins are drawn without
//!   it, and their wire, if they are one, carries the name once. `wire`
//!
//! Contents:
//! - `pub fn wire(gpa: Allocator, s: *Schematic, nl: *const Netlist, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror, net_rank: []const u32, lines: *const NetLines, requests: Requests, loops: []const power_loops.Group, trial: parent_parts.Trial, bridged_t: bool, final_routes: bool, load_singles: []const resistor_loads.Group, load_pairs: []const resistor_loads.Pair, downstream: []const resistor_loads.Pair, four_groups: []const ct_four_sides.Group) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const sch = @import("schematic.zig");
const canvas = @import("canvas.zig");
const routes = @import("routes.zig");
const maze = @import("maze.zig");
const netlines = @import("netlines.zig");
const trunk = @import("trunk.zig");
const name_parts = @import("name_parts.zig");
const power_loops = @import("power_loops.zig");
const power_loop_wires = @import("power_loop_wires.zig");
const resistor_loads = @import("resistor_loads.zig");
const resistor_load_wires = @import("resistor_load_wires.zig");
const resistor_downstream = @import("resistor_downstream.zig");
const ct_four_sides = @import("ct_four_sides.zig");
const ct_four_wires = @import("ct_four_wires.zig");
const ct_controls = @import("ct_controls.zig");
const ct_mirror_controls = @import("ct_mirror_controls.zig");
const Netlist = @import("netlist.zig").Netlist;
const NetLines = netlines.NetLines;
const parent_parts = @import("parent_parts.zig");
const Requests = @import("wire_requests.zig").Requests;

const Side = library.Side;
const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const Role = sch.Role;
const Canvas = canvas.Canvas;
const Lengths = canvas.Lengths;
const Line = canvas.Line;

const linesFit = canvas.linesFit;
const pinAt = canvas.pinAt;
const topLeft = canvas.topLeft;

/// The half perimeter, in units, of the box around an input's pins up to
/// which they are wired to one port; farther apart, each pin gets a port.
/// People wire 87% of their inputs of two pins or more to one symbol and
/// cut a connection past 5.5 to 7.5 units (5,274 drawings).
// ponytail: one cut for every pin kind; per-edge cuts (gate to gate 3,
// gate to other 5.5, other 7.5) once the pitch is the human one.
const input_reach = 6;

/// The longest stub from a rail pin to its bar, in units: a pin farther
/// from the bar carries a symbol of its own. Of 9,149 upright supply runs
/// in 5,263 hand-drawn schematics, 97% are no longer.
const rail_reach = 2;

/// What a net is drawn as by its role.
const Drawn = enum(u8) {
    /// A supply or a ground: its symbols, or a bar.
    rail,
    /// An input or a bias, driven from outside: its port.
    port,
    /// An internal net or an output: a wire.
    wire,

    fn of(role: Role) Drawn {
        return switch (role) {
            .supply, .sink => .rail,
            .input, .bias => .port,
            .internal, .output => .wire,
        };
    }
};

/// Draws every net of `s`; `xy` holds the nodes' points (`s.xy` is kept
/// in step with it), `len` the drawing's lengths, `hidden` the points of
/// pins drawn on their symbol with no wire. Asserts `lines` is
/// `netlines.read`'s of these nets: an entry a net, every rail's bar or
/// symbols chosen. `loops` holds requests
/// collected before automatic thinning, after explicit net instructions.
/// `nl` is the complete netlist that owns `s`'s borrowed device/net tables;
/// a cut-net stage certificate counts its hidden and undrawn incidences too.
/// requests borrows original admitted routes and poses, including those
/// deferred during scaffolding; only lines.routes are actually drawn here.
/// load_singles/load_pairs borrow successfully placed full stage owners;
/// their automatic internal load trees retain ordinary thinning policies.
pub fn wire(gpa: Allocator, s: *Schematic, nl: *const Netlist, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror, net_rank: []const u32, lines: *const NetLines, requests: Requests, loops: []const power_loops.Group, trial: parent_parts.Trial, bridged_t: bool, final_routes: bool, load_singles: []const resistor_loads.Group, load_pairs: []const resistor_loads.Pair, downstream: []const resistor_loads.Pair, four_groups: []const ct_four_sides.Group) Allocator.Error!void {
    assert(net_rank.len == s.net_name.len);
    assert(lines.style.len == s.net_name.len);
    assert(lines.port.len == s.net_name.len and lines.rail.len == s.net_name.len);
    var c = try Canvas.init(gpa, s, xy, len, boxes, hidden);
    defer c.deinit();
    c.port_side = lines.port;
    const n_nets = s.net_name.len;
    const pins_of = try gpa.alloc(std.ArrayList(u32), n_nets);
    defer {
        for (pins_of) |*l| l.deinit(gpa);
        gpa.free(pins_of);
    }
    @memset(pins_of, .empty);
    for (s.pins.items(.net), 0..) |net, p| try pins_of[net].append(gpa, @intCast(p));
    const order = try gpa.alloc(u32, n_nets);
    defer gpa.free(order);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    const Order = struct { roles: []const Role, rank: []const u32, pins_of: []const std.ArrayList(u32) };
    std.sort.heap(u32, order, Order{ .roles = s.roles, .rank = net_rank, .pins_of = pins_of }, struct {
        fn lt(o: Order, x: u32, y: u32) bool {
            const fx = drawStep(o.roles[x], o.pins_of[x].items.len);
            const fy = drawStep(o.roles[y], o.pins_of[y].items.len);
            if (fx != fy) return fx < fy;
            return o.rank[x] < o.rank[y] or (o.rank[x] == o.rank[y] and x < y);
        }
    }.lt);
    // Nets whose wire is named once: a bias a line wires (as a gate line
    // is, so its wire joins the source drawn apart under that name), and a
    // net some of whose pins a `label ... at` line names, a name each and
    // off the wire.
    var named: std.ArrayList(u32) = .empty;
    defer named.deinit(gpa);
    for (lines.named_at) |k| for (s.pins.items(.net), 0..) |net, p| {
        if (s.pins.items(.device)[p] != k[0] or s.pins.items(.index)[p] != k[1]) continue;
        _ = pins_of[net].swapRemove(std.mem.indexOfScalar(u32, pins_of[net].items, @intCast(p)) orelse break);
        try c.labelAt(@intCast(p));
        if (Drawn.of(s.roles[net]) == .wire and std.mem.indexOfScalar(u32, named.items, net) == null) try named.append(gpa, net);
        break;
    };
    // Pinned routes and vias claim their room before anything else.
    const routed = try gpa.alloc(bool, n_nets);
    defer gpa.free(routed);
    @memset(routed, false);
    for (lines.routes) |r| {
        if (try pinned(&c, r, pins_of[r.net].items)) routed[r.net] = true;
    }
    for (lines.style, 0..) |style, net| {
        if ((style != .over and style != .under) or routed[net] or pins_of[net].items.len < 2) continue;
        // The run past the symbols alone; the router joins the pins to it.
        if (try c.commit(@intCast(net), &around(&c, pins_of[net].items, style == .over))) routed[net] = true;
    }
    // The `first` nets lead, in their order.
    var lead: usize = 0;
    for (lines.first) |net| {
        const at = std.mem.indexOfScalar(u32, order, net).?;
        std.mem.copyBackwards(u32, order[lead + 1 .. at + 1], order[lead..at]);
        order[lead] = net;
        lead += 1;
    }
    var gate_labels: std.ArrayList(u32) = .empty;
    defer gate_labels.deinit(gpa);
    var waiting: std.ArrayList(u32) = .empty;
    defer waiting.deinit(gpa);
    // Inputs a line wires that no trunk took: their port once routed.
    var ported_late: std.ArrayList(u32) = .empty;
    defer ported_late.deinit(gpa);
    // The nets drawn so far: a mate drawn as its net's mirror image is not
    // drawn again.
    const drawn = try gpa.alloc(bool, n_nets);
    defer gpa.free(drawn);
    @memset(drawn, false);
    try ct_four_wires.rail(&c, nl, four_groups, lines, requests, pins_of, routed, drawn);
    const mates: []u32 = if (loops.len != 0 and mirror != null) try gpa.dupe(u32, mirror.?.net_mate) else &.{};
    defer gpa.free(mates);
    const own_mirror: ?routes.Mirror = if (mates.len != 0) .{ .axis2 = mirror.?.axis2, .net_mate = mates } else mirror;
    const anchors: []u32 = if (loops.len != 0) try gpa.alloc(u32, n_nets) else &.{};
    defer gpa.free(anchors);
    @memset(anchors, sch.none);
    var seeded = loops.len == 0 and trial.pairs.len == 0 and load_singles.len == 0 and load_pairs.len == 0 and four_groups.len == 0;
    for (order, 0..) |net, position| {
        if (!seeded and position >= lead and !s.roles[net].isRail()) {
            if (loops.len != 0) try power_loop_wires.seed(&c, loops, pins_of, mates, anchors);
            try trial.draw(&c, lines, pins_of, routed, drawn);
            try resistor_load_wires.seed(&c, nl, load_singles, load_pairs, lines, pins_of, routed, drawn);
            try resistor_downstream.parts(&c, nl, downstream, lines, requests, pins_of, routed, drawn);
            try ct_four_wires.parts(&c, nl, four_groups, lines, requests, pins_of, routed, drawn);
            seeded = true;
        }
        const pins = pins_of[net].items;
        const anchor = if (anchors.len != 0) anchors[net] else sch.none;
        if (pins.len == 0 or drawn[net]) continue;
        drawn[net] = true;
        const axis2: ?i32 = if (own_mirror) |m| (if (m.net_mate[net] == net) m.axis2 else null) else null;
        const style = lines.style[net];
        if (routed[net]) {
            // The router joins its other pins to the pinned wire.
            if (s.roles[net] == .bias) try named.append(gpa, net);
            continue;
        }
        if (style == .label) {
            for (pins) |p| try c.labelAt(p);
            s.labeled[net] = true;
            continue;
        }
        if (style == .cut) {
            try name_parts.draw(&c, nl, net, pins, lines, requests);
            s.labeled[net] = true;
            continue;
        }
        if (bridged_t and style == .auto and lines.port[net] == null and s.roles[net].isPort()) {
            if (try @import("passive_filters.zig").port(&c, net, pins)) continue;
        }
        const preferred = ct_mirror_controls.interval(&c, nl, net, pins, lines, requests);
        switch (Drawn.of(s.roles[net])) {
            // A rail's pins face out along the rows, a supply's up and a
            // ground's down: a symbol at each, or one bar past them all.
            .rail => switch (lines.rail[net]) {
                .each => for (pins) |p| try terminal(&c, p),
                .bar, .plain => |r| try bar(&c, pins, if (s.roles[net] == .supply) .up else .down, r == .plain),
                .auto => unreachable,
            },
            // A bias a line wires is a wire like any other, named once; an
            // input one wire with one port, out from a free end of its
            // trunk, else from the wire the router draws.
            .port => if (style == .auto or pins.len < 2) try ported(&c, net, pins, anchor, if (final_routes) &gate_labels else null) else {
                if (s.roles[net] == .bias) try named.append(gpa, net);
                if (!try patterned(&c, net, pins, axis2, if (s.roles[net] == .bias or style == .route) style else .trunk, preferred)) {
                    try waiting.append(gpa, net);
                    if (s.roles[net] == .input) try ported_late.append(gpa, net);
                }
            },
            .wire => {
                if (s.roles[net] == .output and try power_loop_wires.port(&c, net, pins, anchor)) continue;
                const from = c.segs.items.len;
                const pin_from = s.pins.len;
                if (!try patterned(&c, net, pins, axis2, style, preferred)) {
                    try waiting.append(gpa, net);
                    continue;
                }
                // Its mirror mate as the mirror image of its wire (routes.2;
                // people 1,070 of 1,112 pairs).
                const m = own_mirror orelse continue;
                const mate = m.net_mate[net];
                if (mate == sch.none or mate == net or drawn[mate] or routed[mate] or lines.style[mate] != style or Drawn.of(s.roles[mate]) != .wire) continue;
                drawn[mate] = try mirrorMate(&c, net, mate, pins, pins_of[mate].items, from, pin_from, m.axis2);
            },
        }
    }
    try routes.draw(&c, waiting.items, pins_of, own_mirror, anchors);
    for (ported_late.items) |net| try routes.port(&c, net);
    try joinRouted(&c, routed, pins_of);
    // On its top-left pin, so card order changes nothing.
    for (named.items) |net| if (!s.labeled[net]) {
        const of = pins_of[net].items;
        try c.labelAt(of[topLeft(s, of)]);
    };
    for (gate_labels.items) |label| {
        const net = s.pins.items(.net)[label];
        try routes.gatePort(&c, net, pins_of[net].items, label);
    }
    assert(xy.items.len == s.nodes.len);
}

// ---- private ----

/// When a net of `role` with `n_pins` pins is drawn (wires.1): a rail's
/// symbols or bar, then a symbol alone (an input's or a bias's lone pin),
/// then the wires, then the wires of the nets driven from outside.
fn drawStep(role: Role, n_pins: usize) u8 {
    return switch (Drawn.of(role)) {
        .rail => 0,
        .port => if (n_pins == 1) 1 else 3,
        .wire => 2,
    };
}

/// `net`'s mate drawn as the mirror image of what `net` drew from segment
/// `seg_from` and pin `pin_from` on: its wire, then its symbols and names
/// (routes.2). False, with nothing drawn, when the mate's pins are not the
/// images of `pins` or its wire does not fit.
fn mirrorMate(c: *Canvas, net: u32, mate: u32, pins: []const u32, mate_pins: []const u32, seg_from: usize, pin_from: usize, axis2: i32) !bool {
    if (!try routes.mirrored(c, net, mate, pins, mate_pins, seg_from, axis2)) return false;
    const s = c.s;
    // The leaves `net` drew: a pin of no device on the net.
    for (pin_from..s.pins.len) |p| {
        const pin = s.pins.get(p);
        if (pin.device != sch.none or pin.net != net) continue;
        const at = pinAt(s, @intCast(p));
        try c.leaf(s.nodes.items(.kind)[pin.home], mate, .{ .x = axis2 - at.x, .y = at.y }, pin.side.flipX());
    }
    return true;
}

/// Draws route or via `r` of a net with pins `pins`, whole or not at all: a
/// route must end on one of the pins; a via runs from the net's top-left pin
/// through each point in turn (an L each way), skipping one it cannot reach.
/// Whether anything was drawn.
fn pinned(c: *Canvas, r: netlines.Route, pins: []const u32) !bool {
    if (pins.len == 0) return false;
    if (!r.via) {
        for (pins) |p| {
            const at = pinAt(c.s, p);
            if (at.eql(r.pts[0]) or at.eql(r.pts[r.pts.len - 1])) return commitThrough(c, r.net, pins, r.pts);
        }
        return false;
    }
    var from = pinAt(c.s, pins[topLeft(c.s, pins)]);
    var drew = false;
    for (r.pts) |to| {
        if (to.eql(from)) continue;
        const reached = for ([_]Pt{ .{ .x = to.x, .y = from.y }, .{ .x = from.x, .y = to.y } }) |corner| {
            const path: []const Pt = if (corner.eql(from) or corner.eql(to)) &.{ from, to } else &.{ from, corner, to };
            if (try commitThrough(c, r.net, pins, path)) break true;
        } else false;
        if (!reached) continue;
        from = to;
        drew = true;
    }
    return drew;
}

/// The run of a `wire <net> over|under` line with pins `pins`: from their
/// leftmost x to their rightmost, one unit past every symbol and pin, above
/// the drawing (`top`) or below it.
fn around(c: *const Canvas, pins: []const u32, top: bool) [2]Pt {
    assert(pins.len >= 2);
    var lo = pinAt(c.s, pins[0]);
    var hi = lo;
    var edge = lo.y;
    for (pins) |p| {
        const at = pinAt(c.s, p);
        lo.x = @min(lo.x, at.x);
        hi.x = @max(hi.x, at.x);
    }
    for (c.boxes) |b| edge = if (top) @min(edge, b.min.y) else @max(edge, b.max.y);
    for (c.s.pins.items(.net), 0..) |_, p| {
        const y = pinAt(c.s, @intCast(p)).y;
        edge = if (top) @min(edge, y) else @max(edge, y);
    }
    const y = if (top) edge - c.len.unit else edge + c.len.unit;
    // Pins in one column: a run one unit wide, still a segment.
    return .{ .{ .x = lo.x, .y = y }, .{ .x = @max(hi.x, lo.x + c.len.unit), .y = y } };
}

/// Commits polyline `pts` of `net`, each of its pins the polyline passes
/// made a point of it (a pin joins a wire only at a point). False, with
/// nothing drawn, when a piece does not fit.
fn commitThrough(c: *Canvas, net: u32, pins: []const u32, pts: []const Pt) !bool {
    var all: std.ArrayList(Pt) = .empty;
    defer all.deinit(c.gpa);
    for (pts, 0..) |b, k| {
        if (k > 0) {
            const a = pts[k - 1];
            // The pins strictly inside a..b, in order along it.
            const step: Pt = .{ .x = std.math.sign(b.x - a.x), .y = std.math.sign(b.y - a.y) };
            var q = a.add(step);
            var guard: usize = 0;
            while (!q.eql(b)) : (q = q.add(step)) {
                guard += 1;
                assert(guard <= 1 << 24);
                for (pins) |p| if (pinAt(c.s, p).eql(q)) {
                    try all.append(c.gpa, q);
                    break;
                };
            }
        }
        try all.append(c.gpa, b);
    }
    return c.commit(net, all.items);
}

/// Each net a route or via drew: its pins off that wire joined to it by
/// the router (`routes.attach`), its port if an output.
fn joinRouted(c: *Canvas, routed: []const bool, pins_of: []const std.ArrayList(u32)) !void {
    const gpa = c.gpa;
    var off: std.ArrayList(u32) = .empty;
    defer off.deinit(gpa);
    for (routed, 0..) |r, net| {
        if (!r) continue;
        off.clearRetainingCapacity();
        var anchor: ?u32 = null;
        for (pins_of[net].items) |p| {
            if (c.onNet(@intCast(net), pinAt(c.s, p))) {
                anchor = anchor orelse p;
            } else try off.append(gpa, p);
        }
        // A route ends on a pin and a via starts at one: some pin is on it.
        // An `over` or `under` run touches none: its first pin stands in.
        try routes.attach(c, @intCast(net), off.items, anchor orelse off.items[0]);
    }
}

/// Whether an input's pins stand near enough to share one wire and one
/// port: the box around them no more than `input_reach` units around half.
/// With an existing tree, the outside cluster must also reach its ink
/// within that same bound; the whole tree need not fit in a new small box.
fn near(c: *const Canvas, pins: []const u32, tree: ?u32) bool {
    assert(pins.len >= 1);
    var box: Rect = .point(pinAt(c.s, pins[0]));
    for (pins[1..]) |p| box = box.merge(.point(pinAt(c.s, p)));
    const limit = input_reach * c.len.unit;
    if (tree) |net| return nearTree(box, net, c.segs.items, limit);
    return box.max.x - box.min.x + box.max.y - box.min.y <= limit;
}

fn nearTree(box: Rect, net: u32, segments: []const maze.Wire, limit: i32) bool {
    assert(box.min.x <= box.max.x and box.min.y <= box.max.y);
    assert(limit >= 0);
    const span = @as(i64, box.max.x) - box.min.x + @as(i64, box.max.y) - box.min.y;
    if (span > limit) return false;
    for (segments) |segment| {
        if (segment.net != net) continue;
        assert(segment.a.x == segment.b.x or segment.a.y == segment.b.y);
        const reach = Rect.fromCorners(segment.a, segment.b);
        const dx = @max(0, @max(@as(i64, reach.min.x) - box.max.x, @as(i64, box.min.x) - reach.max.x));
        const dy = @max(0, @max(@as(i64, reach.min.y) - box.max.y, @as(i64, box.min.y) - reach.max.y));
        if (span + dx + dy <= limit) return true;
    }
    return false;
}

/// A wire by the pattern `style` asks (`auto` and `wire`: a ladder, else a
/// trunk); false, with nothing drawn, when it does not fit (or for `route`):
/// the router takes the net.
fn patterned(c: *Canvas, net: u32, pins: []const u32, axis2: ?i32, style: netlines.Style, preferred: ?[2]Pt) !bool {
    // One pin: nothing to route; its port, if any, as by default.
    return switch (if (pins.len < 2) .auto else style) {
        .auto, .wire => try ladder(c, net, pins, axis2) or try trunk.drawPreferred(c, net, pins, .port, preferred),
        .ladder => try ladder(c, net, pins, axis2),
        .trunk => try trunk.draw(c, net, pins, .port),
        .route, .over, .under => false,
        .label, .cut => unreachable,
    };
}

/// A rail's symbol or a port one gap out from pin `p`, on a stub: toward
/// the side a `port` line asks, then the way the pin faces, the first whose
/// stub fits; a label on the pin itself when neither does. Narrowing: no
/// name's stub is tried before the pin, as `Canvas.labelAt` would.
fn terminal(c: *Canvas, p: u32) !void {
    const side = c.s.pins.items(.side)[p];
    const net = c.s.pins.items(.net)[p];
    const rail = c.rails[net];
    const d = c.s.pins.items(.device)[p];
    // A rail symbol stands on a two-pin part's end, no stub: people 6,883
    // of 8,367; on a transistor's path end 3,612 of 8,921 (the stub stays).
    if (rail and d != sch.none and c.s.device_pin_count[d] == 2) {
        return c.leaf(.terminal, net, pinAt(c.s, p), (c.port_side[net] orelse side).opposite());
    }
    if (try c.markAt(.terminal, p, &.{ c.port_side[net] orelse side, side }, if (rail) c.len.rail else c.len.terminal)) {
        // A rail's stub is a wall.
        if (rail) c.wall();
    } else c.s.labeled[net] = true;
}

/// Rail pins facing `out` (up for a supply, down for ground): stubs to a
/// bar a gap past the outermost, one symbol on each unbroken run of the bar
/// at its middle stub; a supply's run of two or more stubs instead goes on
/// `len.past` beyond its outer ones where both fit, named at its right end.
/// Any other pin: a symbol of its own. `plain`, the bar
/// is a wire and carries no symbol: where it is in pieces, each run and
/// each pin off it carries the net's name instead.
fn bar(c: *Canvas, pins: []const u32, out: Side, plain: bool) !void {
    const s = c.s;
    const gpa = c.gpa;
    assert(out == .up or out == .down);
    var ups: std.ArrayList(u32) = .empty;
    defer ups.deinit(gpa);
    var top: i32 = if (out == .up) std.math.maxInt(i32) else std.math.minInt(i32);
    for (pins) |p| {
        if (s.pins.items(.side)[p] != out) continue;
        top = if (out == .up) @min(top, pinAt(s, p).y) else @max(top, pinAt(s, p).y);
    }
    // A plain bar is the net's one wire: every pin facing it comes down to
    // it, however far.
    const reach = if (plain) std.math.maxInt(i32) else rail_reach * c.len.unit - c.len.rail;
    for (pins) |p| {
        if (s.pins.items(.side)[p] == out and @abs(pinAt(s, p).y - top) <= reach) try ups.append(gpa, p);
    }
    if (pins.len == 0) return;
    const net = s.pins.items(.net)[pins[0]];
    // Pieces of a plain bar: the pins off it and its runs.
    var pieces: usize = 0;
    for (pins) |p| if (ups.items.len < 2 or std.mem.indexOfScalar(u32, ups.items, p) == null) {
        if (plain) try c.labelAt(p) else try terminal(c, p);
        pieces += 1;
    };
    if (plain and pieces > 0) s.labeled[net] = true;
    if (ups.items.len < 2) return;
    const y_bar = if (out == .up) top - c.len.rail else top + c.len.rail;
    // pins_of is filled in ascending pin-id order; filtering keeps it.
    // Pin ids therefore preserve the prior stable order at equal columns.
    for (ups.items[0 .. ups.items.len - 1], ups.items[1..]) |a, b| assert(a < b);
    std.sort.heap(u32, ups.items, s, struct {
        fn lt(sc: *Schematic, x: u32, y: u32) bool {
            const a, const b = .{ pinAt(sc, x).x, pinAt(sc, y).x };
            return if (a == b) x < y else a < b;
        }
    }.lt);
    // A pin whose stub would touch something gets a symbol of its own.
    var on_bar: std.ArrayList(u32) = .empty;
    defer on_bar.deinit(gpa);
    for (ups.items) |p| {
        const at = pinAt(s, p);
        if (try c.commit(net, &.{ at, .{ .x = at.x, .y = y_bar } })) {
            if (@abs(at.y - y_bar) <= c.len.rail) c.wall();
            try on_bar.append(gpa, p);
        } else {
            if (plain) try c.labelAt(p) else try terminal(c, p);
            pieces += 1;
        }
    }
    if (on_bar.items.len == 0) return;
    var mids: std.ArrayList(Pt) = .empty;
    defer mids.deinit(gpa);
    // The bar in pieces between stubs, so every joint is a wire's end; a
    // piece that does not fit ends a run, and each run gets a symbol at its
    // middle stub.
    var run: usize = 0;
    for (on_bar.items, 0..) |q, i| {
        const last = i + 1 == on_bar.items.len;
        const joined = !last and blk: {
            const x0 = pinAt(s, q).x;
            const x1 = pinAt(s, on_bar.items[i + 1]).x;
            if (x0 == x1) break :blk true;
            if (!try c.commit(net, &.{ .{ .x = x0, .y = y_bar }, .{ .x = x1, .y = y_bar } })) break :blk false;
            c.wall();
            break :blk true;
        };
        if (joined) continue;
        defer run = i + 1;
        // A supply's bar is either a named rail running on past its outer
        // pins, its name at the right end (people 1,255 of 1,370; the name
        // right 1,252 of 1,256), or a bar carrying the symbol and ending on
        // them (1,083 of 1,140): never both.
        const x_lo = pinAt(s, on_bar.items[run]).x;
        const x_hi = pinAt(s, q).x;
        if (out == .up and !plain and c.len.past > 0 and x_lo != x_hi) {
            const cp = c.save();
            if (try c.commit(net, &.{ .{ .x = x_lo - c.len.past, .y = y_bar }, .{ .x = x_lo, .y = y_bar } })) {
                c.wall();
                if (try c.commit(net, &.{ .{ .x = x_hi, .y = y_bar }, .{ .x = x_hi + c.len.past, .y = y_bar } })) {
                    c.wall();
                    try c.leaf(.label, net, .{ .x = x_hi + c.len.past, .y = y_bar }, .left);
                    continue;
                }
            }
            c.restore(cp);
        }
        const mid = pinAt(s, on_bar.items[(run + i) / 2]);
        if (plain) try mids.append(gpa, .{ .x = mid.x, .y = y_bar }) else try c.leaf(.terminal, net, .{ .x = mid.x, .y = y_bar }, out.opposite());
    }
    // A plain bar in one piece is the whole net: a wire, nothing to name.
    if (pieces + mids.items.len < 2) return;
    for (mids.items) |at| try c.leaf(.label, net, at, out.opposite());
    s.labeled[net] = true;
}

/// A net driven from outside (an input, a bias). Pins standing near each
/// other: one trunk, one port out from a free end. Else a port on a stub at
/// each pin, as people draw a bias: of 4,378 nets named `vb*` or `bias*` in
/// 5,263 hand-drawn schematics, 3,228 carry port symbols and none a written
/// name. Before either, a bias of two gates of one row facing each other:
/// a gate line between them, named at its middle. A successfully seeded
/// input tree gets its boundary port before nearby outside pins attach;
/// distant outside pins retain their ordinary input patterns and ports.
fn ported(c: *Canvas, net: u32, all: []const u32, anchor: u32, gate_labels: ?*std.ArrayList(u32)) !void {
    const s = c.s;
    assert(all.len >= 1);
    const bias = s.roles[net] == .bias;
    assert(bias or s.roles[net] == .input);
    var pins = all;
    if (!bias and try power_loop_wires.port(c, net, pins, anchor)) {
        pins = pins[0 .. pins.len - 1];
        if (pins.len == 0) return;
        if (near(c, pins, net)) {
            try routes.attach(c, net, pins, anchor);
            return;
        }
    }
    if (bias and pins.len == 2) {
        const a = pinAt(s, pins[0]);
        const b = pinAt(s, pins[1]);
        const sa = s.pins.items(.side)[pins[0]];
        const sb = s.pins.items(.side)[pins[1]];
        const facing = a.y == b.y and ((a.x < b.x and sa == .right and sb == .left) or (b.x < a.x and sb == .right and sa == .left));
        if (facing and try c.commit(net, &.{ a, b })) {
            // Keep the gate line intact when another wire crosses its midpoint.
            const mid: Pt = .{ .x = @divFloor(a.x + b.x, 2), .y = a.y };
            for ([_]Side{ .down, .up }) |t| if (try c.stub(.terminal, net, mid, t, c.len.terminal)) return;
            try c.labelAt(pins[0]);
            if (gate_labels) |list| {
                for (pins) |pin| {
                    const d = s.pins.items(.device)[pin];
                    if (d == sch.none or s.device_kind[d] != .mosfet or s.pins.items(.index)[pin] != 1) break;
                } else try list.append(c.gpa, @intCast(s.pins.len - 1));
            }
            return;
        }
    }
    // A bias's port stands where a name would, on a name's stub.
    if (pins.len >= 2 and near(c, pins, null) and try trunk.draw(c, net, pins, if (bias) .name else .port)) return;
    for (pins) |p| try terminal(c, p);
    // A bias's ports are its name written out: it is drawn with labels.
    if (bias) s.labeled[net] = true;
}

/// An internal net whose pins all face each other in pairs along rows, one
/// pair a row on two rows or more, the pairs' spans sharing an x: a rung
/// between each pair and an upright at that x (the axis when `axis2` is
/// set and inside, else the middle) through them all. False, with nothing
/// drawn, when a piece does not fit.
fn ladder(c: *Canvas, net: u32, pins: []const u32, axis2: ?i32) !bool {
    const s = c.s;
    if (s.roles[net] != .internal or pins.len < 4 or pins.len % 2 != 0) return false;
    const sides = s.pins.items(.side);
    var rungs: std.ArrayList([3]i32) = .empty;
    defer rungs.deinit(c.gpa);
    var lo: i32 = std.math.minInt(i32);
    var hi: i32 = std.math.maxInt(i32);
    for (pins) |p| {
        if (sides[p] != .right) continue;
        const a = pinAt(s, p);
        // The nearest pin facing back from the right on its row.
        var end: ?i32 = null;
        for (pins) |q| {
            const b = pinAt(s, q);
            if (sides[q] == .left and b.y == a.y and b.x > a.x and (end == null or b.x < end.?)) end = b.x;
        }
        try rungs.append(c.gpa, .{ a.y, a.x, end orelse return false });
        lo = @max(lo, a.x);
        hi = @min(hi, end.?);
    }
    if (2 * rungs.items.len != pins.len or hi - lo < 2) return false;
    // Equal rows are rejected below, before any route is emitted.
    std.sort.heap([3]i32, rungs.items, {}, struct {
        fn lt(_: void, a: [3]i32, b: [3]i32) bool {
            return a[0] < b[0];
        }
    }.lt);
    for (rungs.items[0 .. rungs.items.len - 1], rungs.items[1..]) |a, b| if (a[0] == b[0]) return false;
    const mid = @divFloor(lo + hi, 2);
    const x: i32 = if (axis2) |a2| (if (@mod(a2, 2) == 0 and a2 > 2 * lo and a2 < 2 * hi) @divExact(a2, 2) else mid) else mid;
    var lines: std.ArrayList(Line) = .empty;
    defer lines.deinit(c.gpa);
    for (rungs.items) |r| {
        try lines.append(c.gpa, .of(&.{ .{ .x = r[1], .y = r[0] }, .{ .x = x, .y = r[0] } }));
        try lines.append(c.gpa, .of(&.{ .{ .x = x, .y = r[0] }, .{ .x = r[2], .y = r[0] } }));
    }
    for (rungs.items[0 .. rungs.items.len - 1], rungs.items[1..]) |a, b| {
        try lines.append(c.gpa, .of(&.{ .{ .x = x, .y = a[0] }, .{ .x = x, .y = b[0] } }));
    }
    if (!linesFit(c, net, lines.items)) return false;
    for (lines.items) |*l| assert(try c.commit(net, l.slice()));
    return true;
}

test "wires: an outside cluster reaches actual same-net tree ink within the input bound" {
    // Literal oracle: a long vertical tree can be reached at its middle
    // or its lower end, independently of a retained pin at its top.
    const tree = [_]maze.Wire{.{ .a = .{ .x = 0, .y = 0 }, .b = .{ .x = 0, .y = 100 }, .net = 7 }};
    const middle: Rect = .point(.{ .x = 10, .y = 50 });
    try std.testing.expect(nearTree(middle, 7, &tree, 10));
    try std.testing.expect(!nearTree(middle, 7, &tree, 9));
    const below: Rect = .point(.{ .x = 0, .y = 110 });
    try std.testing.expect(nearTree(below, 7, &tree, 10));
    try std.testing.expect(!nearTree(below, 7, &tree, 9));
    try std.testing.expect(!nearTree(middle, 8, &tree, 100));
    try std.testing.expect(!nearTree(middle, 7, &.{}, 100));
    // A 10-by-10 outside cluster needs its 20 extent plus a 10-unit reach.
    const cluster: Rect = .{ .min = .{ .x = 10, .y = 20 }, .max = .{ .x = 20, .y = 30 } };
    try std.testing.expect(nearTree(cluster, 7, &tree, 30));
    try std.testing.expect(!nearTree(cluster, 7, &tree, 29));
    // Both pins individually stand near the tree, but their cluster is
    // already 101 units tall. Per-pin chaining must not admit it at 100.
    const wide: Rect = .{ .min = .{ .x = 1, .y = 0 }, .max = .{ .x = 1, .y = 101 } };
    try std.testing.expect(!nearTree(wide, 7, &tree, 100));
}
