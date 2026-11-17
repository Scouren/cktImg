//! Stage 4 of issue #8: a drawing from the skeleton. In: the netlist, its
//! roles and a symbol library. Out: a laid-out `Schematic`, as
//! `Placed.init` reads one: every drawn device oriented and placed, its
//! pins, terminal symbols, wires, labels, dots and no-connect crosses. How
//! each net is wired is `wires.zig`'s.
//!
//! Human Rules:
//! - sketch.1 (order: potential) An upright device's end on its upper net
//!   faces up, and no end of it on that net faces down. `fits`
//! - sketch.2 (unmeasured) An upright device's gate faces the side the
//!   skeleton gives it; of its four flips, the first that keeps sketch.1
//!   and this. `fits`
//! - sketch.3 (invariant) A `face` line says which end of a flat part is
//!   its left: the user's word. `firstLeft`
//! - sketch.4 (habit) A flat device's end on the net of the nearest device
//!   beside it faces that device: its ends are its path's two pins (a box
//!   of two ports: its two pins), and of the devices on their two nets
//!   that stand in another column, the nearest is the one fewest cells
//!   away, columns plus rows. So two parts in series are one line, and a
//!   part with one end on a port turns the other toward its net. People:
//!   4,414 of 4,471 flat two-pin parts (98.7%) and 1,684 of 1,719 other
//!   flat devices with a path (a pass transistor, a switch: 98.0%) in
//!   5,263 hand-drawn schematics; turned by a series neighbour, a lone pin
//!   and then the mean column, 91.5% of the parts. `fits`, `firstLeft`
//! - sketch.6 (habit) Where no device stands beside it, or two as near
//!   pull opposite ways, a flat device's first end is its left one when
//!   the devices on that end's net stand, at their mean column, no further
//!   right than those on the other's. People: 370 of 460 such parts
//!   (80.4%). `firstLeft`
//! - sketch.7 (invariant) No two devices of the lattice touch: each column
//!   is as wide as its widest device's reach on each side, each row as
//!   tall as its tallest device's (its body, where that reaches more than
//!   `stack` past its pins). `coordinates`
//! - sketch.8 (unmeasured) A pin on a port or rail net has room beyond it
//!   for its symbol: the symbol's stub (none for a rail symbol on a
//!   two-pin part, which stands on the pin: wires.10), and a unit more on
//!   a left or right side; a supply pin facing up takes none (its bar runs
//!   over the top).
//!   `coordinates`
//! - sketch.9 (choice) Neighbouring columns stand `series` apart and rows
//!   `stack` apart, and a lattice column with no device takes no room: the
//!   lengths are `config.Layout`'s. `coordinates`
//! - sketch.10 (invariant) Mirrored columns are as wide as each other, so
//!   the drawing keeps the skeleton's symmetry exactly. `coordinates`
//! - sketch.11 (invariant) A deck carrying a previous drawing's stays
//!   (`*@ weak at`) is relaid from them (`relay.zig`), unless it is an
//!   op-amp circuit (`opamp.zig`). `drawValid`
//!   Narrowing: a deck with a `weak at` line, even one rejected or
//!   overridden, is relaid; the general form asks for an `At.weak`.
//! - sketch.12 (invariant) A drawing closed up (`compact.zig`) has no
//!   symbol on another: where the squeeze leaves two overlapping, the
//!   lattice's places stand; a deck whose every device has its `at` line
//!   is not closed up. `drawValid`
//! - sketch.13 (invariant) A device stands where its `at` line puts it,
//!   turned as the line says, unless its symbol would overlap another
//!   drawn device's; the least preferred `at` gives way first and stands
//!   where the lattice has it. `keepAts`
//! - sketch.14 (unmeasured) An internal net with drawn pins on two shelves
//!   is joined by name, each shelf's pins wired, unless a deck line styles
//!   it. `drawValid`
//! - sketch.15 (choice) After the nets that cross too many wires are named
//!   (`thin.zig`), the drawing is wired again, at most three times: a wire
//!   gone may free a path that crosses anew, and the bound ends the work.
//!   `drawValid`
//! - sketch.16 (unmeasured) A MOS body, an op-amp's reference pin and a
//!   card pin its class lacks are drawn on the symbol, with no wire.
//!   `wiredSide`
//! - sketch.17 (invariant) No other net's wire touches a pin drawn only on
//!   its symbol. `hiddenPins`
//! - sketch.18 (invariant) No two pins of one side of a device meet at one
//!   point: a pin off its device's line for that side (an op-amp's second
//!   input) is wired from its own line. `placeDevices`
//! - sketch.19 (unmeasured) A device pin with no other pin on its net
//!   carries a no-connect cross. `noConnects`
//! - sketch.20 (habit) A flat complementary transmission pair's gates face
//!   outward while its members still share a column on separate rows,
//!   after cell and row instructions. People: ag-386 and ag-751, both
//!   source pairs selected by forms.19. An explicit `at` turn takes
//!   precedence when devices are placed. `fits`
//! - sketch.21 (habit) A flat MOS control faces its drawn active drivers
//!   when every driver stands strictly above it or every driver below it.
//!   Active terminals are transistor paths and named block outputs; other
//!   gates, bodies, sources and passive loads do not vote. A same-row or
//!   opposing driver leaves the class's side unchanged. People: 107/107
//!   qualifying converter controls face their drivers (75 block outputs,
//!   18 two-drain and 14 four-drain networks). Source terminal coordinates
//!   qualify that observation; distinct lattice rows are the placement
//!   proxy here. External controls use power_paths.6 where qualified;
//!   others abstain, and sketch.20 takes priority.
//!   Across all flat MOS, 139/142 qualifying sources agree; ag-809:m10,
//!   ag-813:m7 and ag-3103:m12 keep upward labelled controls from separate
//!   drawing groups. This habit does not yet recognize those local groups.
//!   `controlSide`, `fits`; docs/research/figures/gate_facing.py
//! - sketch.22 (habit, bounded) A converter controller below its unique
//!   main switch on the same final column points OUT up at its downward
//!   gate: 67 of 75 selected source SVGs do so. AG1354/1358/1366/1369/
//!   1372/1377/1393/1396 face right; their case remains unresolved. Cached
//!   terminal geometry alone incorrectly suggests 75. The actual OUT pin sets
//!   the controller's column, including a signed glyph's offset. Explicit
//!   origins or definition sides, an off-column main gate and an unsafe
//!   pin envelope abstain. `orientAll`; schematic.16
//! - sketch.23 (habit, bounded) An isolated amplifier bias peer uses its
//!   actual class frame after lattice coordinates, before scaffold wiring.
//!   Only its whole orientation and grid anchor change; admitted cells,
//!   stays and other caller geometry keep precedence. `bias_neighbors`
//!
//! Contents:
//! - `pub fn lay(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout) !Schematic`
//! - `pub fn draw(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton) !void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");
const opamp = @import("opamp.zig");
const transmission = @import("transmission.zig");
const power_paths = @import("power_paths.zig");
const power_loops = @import("power_loops.zig");
const power_loop_wires = @import("power_loop_wires.zig");
const wires = @import("wires.zig");
const netlines = @import("netlines.zig");
const pinned = @import("pinned.zig");
const hints = @import("hints.zig");
const routes = @import("routes.zig");
const maze = @import("maze.zig");
const canvas = @import("canvas.zig");
const power_compact = @import("power_compact.zig");
const bias_neighbors = @import("bias_neighbors.zig");
const thin = @import("thin.zig");
const relay = @import("relay.zig");
const config = @import("config.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const Library = library.Library;
const Orient = library.Orient;
const Side = library.Side;
const Pt = library.Pt;
const Rect = library.Rect;
const Schematic = sch.Schematic;
const Role = sch.Role;
const Skeleton = skeleton.Skeleton;
const Structure = structure.Structure;
const Lengths = canvas.Lengths;
const boxAt = Schematic.boxAt;
const toPt = Pt.round;
const toF = Pt.toF;
const none = sch.none;

/// How often the drawing is wired again after naming the nets that cross
/// too many wires: a wire gone may free a path that crosses anew.
const thin_rounds = 3;

/// Cold graph-bound MOS output pairs supplied by the selected-cell caller.
pub const parent_parts = @import("parent_parts.zig");
const parent_stages = @import("parent_stages.zig");

/// Lattice column and row → coordinate.
const Geo = struct {
    xs: []const i32,
    ys: []const i32,
};

/// A device's four flips, in the order they are tried.
const flips = [_][2]bool{ .{ false, false }, .{ true, false }, .{ false, true }, .{ true, true } };

/// The stages in one call: the structure (`structure.analyze`), the
/// skeleton (`skeleton.place`), then `draw`.
pub fn lay(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout) !Schematic {
    return layWithParents(gpa, nl, roles, lib, layout, &.{});
}

/// The ordinary layout with source-qualified output pairs for final routing.
pub fn layWithParents(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout, pairs: []const parent_parts.Pair) !Schematic {
    var accepted = false;
    return layOrganized(gpa, nl, roles, lib, layout, pairs, &.{}, &accepted);
}

/// Reconstructs source-qualified relative branch sites for a bounded trial. A
/// missing room or failed mandatory paired route leaves `accepted` false.
pub fn layOrganized(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout, pairs: []const parent_parts.Pair, stages: []const parent_stages.Stage, accepted: *bool) !Schematic {
    var s = try sch.initDevices(gpa, nl, roles, lib);
    errdefer s.arena.deinit();
    const a = s.arena.allocator();
    const st = try structure.analyze(gpa, a, nl, roles);
    const sk = try skeleton.place(gpa, a, nl, roles, &st, .{ .shelf = layout.shelf });
    // `place`'s skeletons always hold.
    skeleton.validate(&sk, nl) catch unreachable;
    try drawValid(gpa, &s, nl, layout, &st, &sk, pairs, stages, accepted);
    return s;
}

/// The drawing of a skeleton: each device oriented and placed, its nets
/// wired, into `s` (from `schematic.initDevices`). `st` and `sk` are
/// `structure.analyze`'s and `skeleton.place`'s, a caller's edits between
/// the stages included: a skeleton the drawing cannot use is refused
/// (`skeleton.Invalid`) before anything is drawn.
pub fn draw(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton) !void {
    return drawWithParents(gpa, s, nl, layout, st, sk, &.{});
}

/// A caller-edited skeleton with qualified source pairs; physical contacts
/// are admitted only against actual selected classes and settled poses.
pub fn drawWithParents(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton, pairs: []const parent_parts.Pair) !void {
    try skeleton.validate(sk, nl);
    var accepted = false;
    try drawValid(gpa, s, nl, layout, st, sk, pairs, &.{}, &accepted);
}

// ---- private ----

fn drawValid(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton, pairs: []const parent_parts.Pair, stages: []const parent_stages.Stage, accepted: *bool) !void {
    // The deck's drawing lines; their verdicts are the report's to give.
    const sa = s.arena.allocator();
    const scratch = try sa.alloc(?hints.Verdict, nl.hints.len);
    @memset(scratch, null);
    var ats = try pinned.read(sa, nl, s.lib.unit, sk.drawn, scratch);
    // A circuit of amplifier blocks and parts is placed along its signal
    // (`opamp.zig`), every device, unless a line of the deck places one.
    const along = try opamp.place(sa, nl, s.roles, sk.drawn, s.lib, s.devices.items(.class));
    if (along) |own| ats = own;
    s.refdes = try pinned.sides(sa, nl, scratch);
    orientAll(s, nl, sk, ats);
    var bias_pairs = try bias_neighbors.collect(gpa, nl, s, sk, st, ats);
    defer bias_pairs.deinit(gpa);
    const len = Lengths.of(layout, s.lib.unit);
    const lines = try netlines.read(sa, nl, s.roles, s.lib.unit, scratch);
    const states = try gpa.alloc(parent_parts.State, pairs.len);
    defer gpa.free(states);
    for (pairs, states) |p, *state| state.* = if (parent_parts.admitted(nl, p, &lines)) .ready else .withdrawn;
    const trial: parent_parts.Trial = .{ .states = states, .pairs = pairs, .nl = nl };
    const loops = try power_loop_wires.collect(gpa, nl, s.roles, sk.drawn, &lines);
    defer gpa.free(loops);
    // Each drawn device's point: the lattice's.
    const n = nl.graph.edgeCount();
    const at = try gpa.alloc([2]f32, n);
    defer gpa.free(at);
    @memset(at, .{ 0, 0 });
    var placed_all = true;
    {
        const geo = try coordinates(gpa, s, nl, sk, len);
        defer gpa.free(geo.xs);
        defer gpa.free(geo.ys);
        for (at, 0..) |*p, d| if (sk.drawn[d]) {
            p.* = .{ @floatFromInt(geo.xs[@intCast(sk.x[d])]), @floatFromInt(geo.ys[@intCast(sk.y[d])]) };
            placed_all = placed_all and ats[d] != null;
        };
        // A drawing relaid: its stays anchor the lattice's lines, and only
        // what the deck's structure no longer puts there is laid again.
        // A stay is a place a `weak at` line gave: a line that is rejected
        // or overridden gives none, and changes nothing.
        const stays = for (ats) |a| {
            if (a != null and a.?.weak) break true;
        } else false;
        if (along == null and stays) placed_all = try relay.place(gpa, s, sk, geo.xs, geo.ys, ats, at);
    }
    bias_neighbors.place(s, nl, sk, ats, len, at, &bias_pairs.pairs);
    var xy: std.ArrayList([2]f32) = .empty;
    // Closed up: the drawing as the engine alone makes it (the deck's `at`,
    // `route` and `via` lines are in the finished drawing's coordinates, so
    // they wait), squeezed; the devices' places there are the placement.
    // Its wires are scaffolding: the real ones are drawn below, on the
    // canvas, so every guarantee holds by construction.
    if (layout.compact and !placed_all) {
        const no_ats = try gpa.alloc(?pinned.At, n);
        defer gpa.free(no_ats);
        @memset(no_ats, null);
        var own = lines;
        own.routes = &.{};
        try wireUp(gpa, s, nl, sk, st, len, at, no_ats, &own, loops, .{}, &xy, false);
        try power_compact.squeeze(gpa, s, nl, sk, ats, len, try drawnAxis2(gpa, s, sk), bias_neighbors.orders(s, bias_pairs.pairs.items, bias_pairs.coordinates));
        const boxes = try deviceBoxes(gpa, s, nl, sk);
        defer gpa.free(boxes);
        const clear = clear: for (boxes, 0..) |a, i| {
            for (boxes[i + 1 ..]) |b| if (a.intersects(b)) break :clear false;
        } else true;
        // ponytail: an overlap after the squeeze keeps the lattice's places.
        if (clear) for (at, 0..) |*p, d| if (sk.drawn[d]) {
            p.* = s.xy[s.deviceNode(@intCast(d)).?];
        };
        wipe(s, &xy);
    }
    try keepAts(gpa, s, nl, sk, at, ats);
    accepted.* = stages.len > 0 and try parent_stages.arrange(gpa, s, sk, at, stages);
    // Wired; then a net crossing too many wires is named and the drawing
    // wired again without it, which may free a path for another.
    // ponytail: thinned on the finished places only, so a relaid drawing
    // thins alike; the closing up still leaves room for the named nets'
    // wires. Thin the scaffolding too if that room shows.
    const style = try gpa.dupe(netlines.Style, lines.style);
    defer gpa.free(style);
    var thinned = lines;
    thinned.style = style;
    // A net between two shelves is joined by name, each shelf's pins wired.
    for (style, s.roles, 0..) |*sty, role, net| {
        if (along != null or sty.* != .auto or role != .internal) continue;
        var first: ?u32 = null;
        for (nl.graph.incident(netlist.VertexId.from(@intCast(net)))) |e| {
            if (!sk.drawn[e.index()]) continue;
            if (first == null) first = sk.shelf[e.index()];
            if (sk.shelf[e.index()] != first.?) sty.* = .cut;
        }
    }
    const initial = if (pairs.len != 0) try gpa.dupe(netlines.Style, style) else &.{};
    defer gpa.free(initial);
    restart: for (0..pairs.len + 1) |_| {
        for (0..thin_rounds + 1) |round| {
            try wireUp(gpa, s, nl, sk, st, len, at, ats, &thinned, loops, trial, &xy, true);
            const mirror = drawnMirror(s, sk, st);
            const changed = round != thin_rounds and try thin.name(gpa, s.routes.items, s.roles, st.net_rank, if (mirror) |m| m.net_mate else null, layout.cross_max, style);
            if (trial.withdraw(style)) {
                wipe(s, &xy);
                @memcpy(style, initial);
                continue :restart;
            }
            if (!changed) break;
            wipe(s, &xy);
        }
        break;
    } else unreachable;
    if (accepted.*) for (states) |state| {
        if (state != .drawn) {
            accepted.* = false;
            break;
        }
    };
    try noConnects(gpa, s);
    assert(s.xy.len == s.nodes.len);
}

/// The drawing's nodes, pins and wires taken off again, its devices too.
fn wipe(s: *Schematic, xy: *std.ArrayList([2]f32)) void {
    s.nodes.shrinkRetainingCapacity(0);
    s.pins.shrinkRetainingCapacity(0);
    s.routes.clearRetainingCapacity();
    xy.clearRetainingCapacity();
    s.xy = &.{};
    @memset(s.labeled, false);
}

/// The devices at `at` (an `at` line's place first), then every net wired.
fn wireUp(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, st: *const Structure, len: Lengths, at: []const [2]f32, ats: []const ?pinned.At, lines: *const netlines.NetLines, loops: []const power_loops.Group, trial: parent_parts.Trial, xy: *std.ArrayList([2]f32), final_routes: bool) !void {
    try placeDevices(s, nl, sk, at, ats, xy);
    s.xy = xy.items;
    const boxes = try deviceBoxes(gpa, s, nl, sk);
    defer gpa.free(boxes);
    const hidden = try hiddenPins(gpa, s, nl, sk);
    defer gpa.free(hidden);
    try wires.wire(gpa, s, xy, len, boxes, hidden, drawnMirror(s, sk, st), st.net_rank, lines, loops, trial, sk.bridged_t, final_routes);
    s.xy = xy.items;
}

/// Keeps each `at` whose symbol, at its place and turn, overlaps no other
/// drawn device's (the preferred of two `at` devices stays), and turns the
/// kept ones; drops the rest (`ats[d] = null`). The report says which.
fn keepAts(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, at: []const [2]f32, ats: []?pinned.At) !void {
    const n = nl.graph.edgeCount();
    const info = s.devices.slice();
    const boxes = try gpa.alloc(Rect, n);
    defer gpa.free(boxes);
    const order = try hints.admitOrder(gpa, nl.hints);
    defer gpa.free(order);
    for (0..n) |d| {
        if (!sk.drawn[d]) continue;
        boxes[d] = if (ats[d]) |a|
            s.lib.at(info.items(.class)[d]).box(a.orient orelse info.items(.orient)[d], a.origin)
        else
            boxAt(s, d, toPt(at[d]));
    }
    // The least preferred `at` gives way first, and stands where the
    // lattice has it: another `at` may be on that place, and gives way in
    // turn, until none overlaps.
    var dropped = true;
    var passes: usize = 0;
    while (dropped) : (passes += 1) {
        assert(passes <= nl.hints.len);
        dropped = false;
        var k = order.len;
        while (k > 0) {
            k -= 1;
            if (nl.hints[order[k]].verb != .at) continue;
            const d = (nl.device(nl.hints[order[k]].args[0]) orelse continue).index();
            const a = ats[d] orelse continue;
            if (a.line != order[k]) continue;
            for (0..n) |e| {
                if (e == d or !sk.drawn[e] or !boxes[d].intersects(boxes[e])) continue;
                ats[d] = null;
                boxes[d] = boxAt(s, d, toPt(at[d]));
                dropped = true;
                break;
            }
        }
    }
    for (0..n) |d| {
        const o = (ats[d] orelse continue).orient orelse continue;
        for ([_]sch.Orientation{ .vertical, .horizontal }) |form| for (flips) |f| {
            if (!std.meta.eql(Orient.flipped(sch.form(form), f[0], f[1]), o)) continue;
            info.items(.orientation)[d] = form;
            info.items(.flip_x)[d] = f[0];
            info.items(.flip_y)[d] = f[1];
        };
        sch.settleDevice(s, &nl.graph, @intCast(d));
    }
}

/// Kept and driver flags, then each drawn device's flips: the first of the
/// four that puts its upper end up and its gate on the skeleton's side (a
/// vertical device), or its end toward the nearest device on its net (a
/// bridge).
fn orientAll(s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At) void {
    const c = &nl.graph;
    const info = s.devices.slice();
    assert(info.len == c.edgeCount());
    assert(sk.drawn.len == c.edgeCount());
    for (0..c.edgeCount()) |d| {
        info.items(.kept)[d] = sk.drawn[d];
        // A device with pins the skeleton leaves out is a driver (R3).
        info.items(.driver)[d] = c.members(EdgeId.from(d)).len > 0 and !sk.drawn[d];
        const vertical = sk.drawn[d] and sk.form[d] == .vertical;
        info.items(.orientation)[d] = if (vertical) .vertical else .horizontal;
        info.items(.flip_x)[d] = false;
        info.items(.flip_y)[d] = false;
        if (!sk.drawn[d]) continue;
        const class = s.lib.at(info.items(.class)[d]);
        const base = sch.form(info.items(.orientation)[d]);
        const gate_side = if (vertical) null else controlSide(nl, s.roles, sk, @intCast(d));
        for (flips) |f| {
            if (!fits(nl, sk, class, @intCast(d), Orient.flipped(base, f[0], f[1]), vertical, gate_side)) continue;
            info.items(.flip_x)[d] = f[0];
            info.items(.flip_y)[d] = f[1];
            break;
        }
    }
    sch.settleDevices(s, c);
    // Only initial candidates participate. Later rejected ats must not
    // introduce a new turn after coordinates have already reserved room.
    for (0..c.edgeCount()) |d| {
        const main, const pin = power_paths.blockTarget(nl, s.roles, sk.drawn, sk.form, @intCast(d)) orelse continue;
        if (ats[d] != null or ats[main] != null or sk.x[d] != sk.x[main] or sk.y[d] <= sk.y[main]) continue;
        const directed = for (nl.defOf(EdgeId.from(d)).?.sides) |side| {
            if (side != null) break true;
        } else false;
        if (directed or wiredSide(s, main, 1, c.members(EdgeId.from(main))[1].index()) != .down) continue;
        const main_class = s.lib.at(info.items(.class)[main]);
        if (info.items(.orient)[main].apply(main_class.terminals[1].at).x != info.items(.grid)[main].x) continue;
        const side = s.lib.at(info.items(.class)[d]).side(pin, .r0) orelse continue;
        const before = s.devices.get(d);
        info.items(.orientation)[d] = if (side.isHorizontal()) .vertical else .horizontal;
        info.items(.flip_x)[d] = side == .left or side == .down;
        info.items(.flip_y)[d] = info.items(.flip_x)[d];
        sch.settleDevice(s, c, @intCast(d));
        if (s.pinSide(@intCast(d), pin) != .up or !sch.alignPin(s, c, @intCast(d), pin)) s.devices.set(d, before);
    }
}

/// A flat MOS gate's side: a parallel pair's exterior first, a certified
/// reservoir path's external gate down, otherwise unanimous active
/// drivers on strictly different rows. Reads existing
/// CSR incidences and cells once per device; no storage survives the call.
fn controlSide(nl: *const Netlist, roles: []const Role, sk: *const Skeleton, d: u32) ?Side {
    const c = &nl.graph;
    assert(d < c.edgeCount());
    assert(roles.len == c.vertexCount());
    if (c.edges.items(.kind)[d] != .mosfet) return null;
    if (transmission.mate(nl, d)) |m| {
        if (sk.drawn[m] and sk.form[m] == .horizontal and sk.x[d] == sk.x[m] and sk.y[d] != sk.y[m]) {
            return if (sk.y[d] < sk.y[m]) .up else .down;
        }
    }
    const pins = c.members(EdgeId.from(d));
    if (pins[0] == pins[2] or pins[1] == pins[0] or pins[1] == pins[2] or roles[pins[1].index()].isRail()) return null;
    if (power_paths.externalReservoirGate(nl, roles, sk.drawn, sk.form, d)) return .down;
    var side: ?Side = null;
    for (c.incident(pins[1])) |e| {
        const v = e.index();
        if (v == d or !sk.drawn[v]) continue;
        const kind = c.edges.items(.kind)[v];
        const q = c.members(e);
        const active = if (device.isTransistor(kind)) blk: {
            const path = device.of(kind).path.?;
            break :blk q[path[0]] == pins[1] or q[path[1]] == pins[1];
        } else if (kind == .subckt) blk: {
            const def = nl.defOf(e) orelse break :blk false;
            if (def.ports.len != q.len) break :blk false;
            for (q, def.ports) |net, port| {
                if (net == pins[1] and library.portRole(def.ports, port) == .out) break :blk true;
            }
            break :blk false;
        } else false;
        if (!active) continue;
        if (sk.y[v] == sk.y[d]) return null;
        const toward: Side = if (sk.y[v] < sk.y[d]) .up else .down;
        if (side != null and side.? != toward) return null;
        side = toward;
    }
    return side;
}

/// Whether turn `o` puts drawn device `d` on its line as the drawing's two
/// orders have it. Upright, the rows': its end on the skeleton's upper net
/// faces up, and its gate the skeleton's side. Flat, the columns': its
/// path's first pin faces left when it is the left end (`firstLeft`).
fn fits(nl: *const Netlist, sk: *const Skeleton, class: library.Class, d: u32, o: Orient, vertical: bool, gate_side: ?Side) bool {
    assert(sk.drawn[d]);
    const pins = nl.graph.members(EdgeId.from(d));
    if (vertical) {
        assert(sk.upper[d] != none);
        var up = false;
        for (pins, 0..) |net, i| {
            const side = class.side(i, o) orelse continue;
            if (side == .up and net.index() == sk.upper[d]) up = true;
            if (side == .down and net.index() == sk.upper[d] and net.index() != sk.lower[d]) return false;
        }
        if (!up) return false;
        const gate = device.of(nl.graph.edges.items(.kind)[d]).gate orelse return true;
        const g = class.side(gate, o) orelse return true;
        return (g == .right) == sk.gate_right[d];
    }
    if (gate_side) |side| {
        const gate = class.side(1, o) orelse return true;
        if (gate != side) return false;
    }
    // Its ends are its path's, whatever else is on its card (a gate, a
    // control pair); a box of two ports has its two pins. People turn a
    // flat transistor or switch as they turn a part: 1,684 of 1,719 face
    // the nearest device on their nets (98.0%).
    const path: [2]u8 = device.of(nl.graph.edges.items(.kind)[d]).path orelse if (pins.len == 2) .{ 0, 1 } else return true;
    const s0 = class.side(path[0], o) orelse return true;
    return (s0 == .left) == (firstLeft(nl, sk, d, path) orelse return true);
}

/// Whether the first of flat device `d`'s two ends, card pins `path`, is
/// its left end; null when both are on one net (a dummy, a MOS capacitor)
/// and no line says: it faces nothing, and lies as its class is drawn.
fn firstLeft(nl: *const Netlist, sk: *const Skeleton, d: u32, path: [2]u8) ?bool {
    const all = nl.graph.members(EdgeId.from(d));
    assert(path[0] < all.len and path[1] < all.len);
    assert(path[0] != path[1]);
    const pins = [2]netlist.VertexId{ all[path[0]], all[path[1]] };
    // A `face` line says which end is left.
    if (sk.left_end[d] != .auto) return sk.left_end[d] == .first;
    if (pins[0] == pins[1]) return null;
    // The nearest device beside it, on either net, has that net's end
    // facing it; cells are counted along the columns plus along the rows.
    // People: 4,414 of 4,471 flat two-pin parts (98.7%) in 5,263 hand-drawn
    // schematics. Two as near that pull opposite ways decide nothing.
    // ponytail: cells stand in for lengths (a device column is four, a row
    // two), and the drawing's own nearest is this one for 96.1% of its
    // flat parts; the lengths themselves if the two drift further apart.
    var best: u32 = std.math.maxInt(u32);
    var pulls = [2]bool{ false, false }; // the first pin rightward, leftward
    for (pins, 0..) |net, i| for (nl.graph.incident(net)) |e| {
        const v = e.index();
        if (v == d or !sk.drawn[v] or sk.x[v] == sk.x[d]) continue;
        const cells = @abs(sk.x[v] - sk.x[d]) + @abs(sk.y[v] - sk.y[d]);
        if (cells > best) continue;
        if (cells < best) pulls = .{ false, false };
        best = cells;
        pulls[@intFromBool((i == 0) == (sk.x[v] < sk.x[d]))] = true;
    };
    if (pulls[0] != pulls[1]) return pulls[1];
    // None beside it, or a tie: the mean columns (people: 370 of 460 such
    // parts, 80.4%).
    return meanX(nl, sk, pins[0].index(), d) <= meanX(nl, sk, pins[1].index(), d);
}

/// The mean column of the drawn devices other than `skip` on `net`, twice.
fn meanX(nl: *const Netlist, sk: *const Skeleton, net: u32, skip: u32) i64 {
    assert(net < nl.graph.vertexCount());
    assert(skip < nl.graph.edgeCount());
    var sum: i64 = 0;
    var count: i64 = 0;
    for (nl.graph.incident(netlist.VertexId.from(net))) |e| {
        const v = e.index();
        if (v == skip or !sk.drawn[v]) continue;
        sum += sk.x[v];
        count += 1;
    }
    return if (count == 0) 0 else @divFloor(2 * sum, count);
}

/// Each lattice column as wide as its widest device's reach on each side,
/// plus room for a port, label or rail symbol (its stub and a unit) where a
/// side pin on a net driven from outside, an output or a rail faces that
/// side; rows as tall as their tallest device (its pins' reach, or its body
/// where that reaches more than `stack` past them), plus a port's or rail
/// symbol's stub where such a pin faces up or down (the supply's bar over
/// the top aside). `len.series` between neighbouring columns, `len.stack`
/// between rows.
fn coordinates(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths) !Geo {
    const c = &nl.graph;
    var w: usize = 1;
    var h: usize = 1;
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        w = @max(w, @as(usize, @intCast(sk.x[d])) + 1);
        h = @max(h, @as(usize, @intCast(sk.y[d])) + 1);
    };
    // Per column, room left and right; per row, up and down.
    const room = try gpa.alloc([2]i32, w + h);
    defer gpa.free(room);
    @memset(room, .{ 0, 0 });
    const cols = room[0..w];
    const rows = room[w..];
    const reach = s.devices.items(.reach);
    const up = @backingInt(Side.up);
    const down = @backingInt(Side.down);
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        const r = reach[d];
        const x: usize = @intCast(sk.x[d]);
        const y: usize = @intCast(sk.y[d]);
        // What it needs on each side.
        var need = r;
        // A body reaching farther than `stack` past its pins (a block with
        // pins on its sides only) takes its own room: two such in one
        // column touched, a pin of one on a pin of the other.
        const body = boxAt(s, d, .zero);
        if (-body.min.y > need[up] + len.stack) need[up] = -body.min.y;
        if (body.max.y > need[down] + len.stack) need[down] = body.max.y;
        for (c.members(EdgeId.from(d)), 0..) |net, i| {
            const side = s.pinSide(@intCast(d), i) orelse continue;
            const role = s.roles[net.index()];
            // A symbol's stub out from the pin (none for a rail's on a
            // two-pin part: `wires.terminal`), and a unit for a symbol
            // beside the device; the supply's bar over the top aside.
            const two = c.members(EdgeId.from(d)).len == 2;
            const stub = if (role.isPort()) len.terminal else if (role.isRail()) (if (two) 0 else len.rail) else continue;
            if (role == .supply and side == .up) continue;
            need[@backingInt(side)] = r[@backingInt(side)] + stub + if (side.isHorizontal()) len.unit else 0;
        }
        cols[x] = .{ @max(cols[x][0], need[@backingInt(Side.left)]), @max(cols[x][1], need[@backingInt(Side.right)]) };
        rows[y] = .{ @max(rows[y][0], need[up]), @max(rows[y][1], need[down]) };
    };
    // Mirrored columns as wide as each other, so the drawing keeps the
    // skeleton's symmetry exactly.
    if (sk.axis2) |a2| for (0..w) |k| {
        const m = a2 - @as(i32, @intCast(k));
        if (m < 0 or m >= w) continue;
        const mk: usize = @intCast(m);
        const left = @max(cols[k][0], cols[mk][1]);
        const right = @max(cols[k][1], cols[mk][0]);
        cols[k] = .{ left, right };
        cols[mk] = .{ right, left };
    };
    const xs = try gpa.alloc(i32, w);
    errdefer gpa.free(xs);
    const ys = try gpa.alloc(i32, h);
    errdefer gpa.free(ys);
    // An empty lattice column takes no room: devices stand `series` apart.
    const used = try gpa.alloc(bool, w);
    defer gpa.free(used);
    @memset(used, false);
    for (0..c.edgeCount()) |d| if (sk.drawn[d]) {
        used[@intCast(sk.x[d])] = true;
    };
    var prev: ?usize = null;
    for (xs, cols, used, 0..) |*x, need, u, k| {
        x.* = if (prev) |p| xs[p] + (if (u) cols[p][1] + len.series + need[0] else 0) else need[0];
        if (u) prev = k;
    }
    for (ys, rows, 0..) |*y, need, k| y.* = if (k == 0) need[0] else ys[k - 1] + rows[k - 1][1] + len.stack + need[0];
    for (1..w) |k| assert(xs[k] >= xs[k - 1]);
    for (1..h) |k| assert(ys[k] > ys[k - 1]);
    return .{ .xs = xs, .ys = ys };
}

/// A node per drawn device at its cell, and a pin per drawn card pin. A pin
/// whose terminal is off its device's line for that side (an op-amp's
/// second input) gets a copy node on its own line, so no two pins of one
/// side meet at one point.
fn placeDevices(s: *Schematic, nl: *const Netlist, sk: *const Skeleton, places: []const [2]f32, ats: []const ?pinned.At, xy: *std.ArrayList([2]f32)) !void {
    const a = s.arena.allocator();
    const c = &nl.graph;
    const info = s.devices.slice();
    for (0..c.edgeCount()) |d| {
        if (!sk.drawn[d]) continue;
        // An `at` line's origin, else the layout's point.
        const at: [2]f32 = if (ats[d]) |p| toF(p.origin.add(info.items(.grid)[d])) else places[d];
        const node = try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = none });
        try xy.append(a, at);
        const class = s.lib.at(info.items(.class)[d]);
        const o = info.items(.orient)[d];
        const grid = info.items(.grid)[d];
        for (c.members(EdgeId.from(d)), 0..) |net, i| {
            const side = wiredSide(s, @intCast(d), i, net.index()) orelse continue;
            // The terminal, from the device's grid point.
            const t = o.apply(class.terminals[i].at).sub(grid);
            const across: f32 = @floatFromInt(if (side.isHorizontal()) t.y else t.x);
            var home = node;
            if (across != 0) {
                home = try s.addNode(.{ .kind = .device, .ref = @intCast(d), .group = node });
                try xy.append(a, if (side.isHorizontal()) .{ at[0], at[1] + across } else .{ at[0] + across, at[1] });
            }
            _ = try s.addPin(.{ .home = home, .side = side, .net = net.index(), .device = @intCast(d), .index = @intCast(i) });
        }
    }
    assert(xy.items.len == s.nodes.len);
    for (s.pins.items(.home)) |h| assert(h < s.nodes.len);
}

/// The side pin `i` of device `d`, on `net`, is wired from; null: a pin
/// `Placed` draws on its symbol with no wire (a MOS body, an op-amp's
/// reference, a card pin its class lacks).
fn wiredSide(s: *const Schematic, d: u32, i: usize, net: u32) ?Side {
    return if (sch.referencePin(s, d, i, net)) null else s.pinSide(d, i);
}

/// The drawing's mirror: twice the x its mated devices stand about, when
/// every mated pair agrees; null when none stands mirrored.
fn drawnMirror(s: *const Schematic, sk: *const Skeleton, st: *const structure.Structure) ?routes.Mirror {
    if (sk.axis2 == null) return null;
    var axis2: ?i32 = null;
    for (st.device_mate, 0..) |m, d| {
        if (m == none or m == d or !sk.drawn[d] or !sk.drawn[m]) continue;
        const a = toPt(s.xy[s.deviceNode(@intCast(d)).?]).x + toPt(s.xy[s.deviceNode(m).?]).x;
        if (axis2 != null and axis2.? != a) return null;
        axis2 = a;
    }
    return if (axis2) |a| .{ .axis2 = a, .net_mate = st.net_mate } else null;
}

/// Twice the x the skeleton's mirrored columns stand about in the drawing,
/// when every pair of them agrees (an `at` line may move one off it); else
/// null. The skeleton mirrors a pair's columns even where the circuit has
/// no symmetry of its own (a mirror load), which `drawnMirror` asks for.
fn drawnAxis2(gpa: Allocator, s: *const Schematic, sk: *const Skeleton) !?i32 {
    const a2 = sk.axis2 orelse return null;
    const x = try gpa.alloc(?i32, sk.drawn.len);
    defer gpa.free(x);
    for (x, 0..) |*v, d| v.* = if (sk.drawn[d]) toPt(s.xy[s.deviceNode(@intCast(d)).?]).x else null;
    var axis2: ?i32 = null;
    for (x, 0..) |xd, d| for (x[d..], d..) |xe, e| {
        if (xd == null or xe == null or sk.x[d] + sk.x[e] != a2) continue;
        if (axis2 != null and axis2.? != xd.? + xe.?) return null;
        axis2 = xd.? + xe.?;
    };
    return axis2;
}

/// The points of pins `Placed` draws on their symbol with no wire (a MOS
/// body, an op-amp's reference, a card pin its class lacks): no other net's
/// wire may touch them.
fn hiddenPins(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) ![]maze.Mark {
    var out: std.ArrayList(maze.Mark) = .empty;
    errdefer out.deinit(gpa);
    const info = s.devices.slice();
    assert(sk.drawn.len == nl.graph.edgeCount());
    for (0..nl.graph.edgeCount()) |d| {
        if (!sk.drawn[d]) continue;
        const origin = toPt(s.xy[s.deviceNode(@intCast(d)).?]).sub(info.items(.grid)[d]);
        const class = s.lib.at(info.items(.class)[d]);
        const o = info.items(.orient)[d];
        for (nl.graph.members(EdgeId.from(d)), 0..) |net, i| {
            if (wiredSide(s, @intCast(d), i, net.index()) != null) continue;
            const at = if (i < class.terminals.len) origin.add(o.apply(class.terminals[i].at)) else origin;
            try out.append(gpa, .{ .at = at, .net = net.index() });
        }
    }
    for (out.items) |m| assert(m.net < nl.graph.vertexCount());
    return out.toOwnedSlice(gpa);
}

fn deviceBoxes(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) ![]Rect {
    var out: std.ArrayList(Rect) = .empty;
    errdefer out.deinit(gpa);
    for (0..nl.graph.edgeCount()) |d| {
        if (!sk.drawn[d]) continue;
        const r = boxAt(s, d, toPt(s.xy[s.deviceNode(@intCast(d)).?]));
        assert(r.min.x <= r.max.x and r.min.y <= r.max.y);
        try out.append(gpa, r);
    }
    assert(out.items.len <= nl.graph.edgeCount());
    return out.toOwnedSlice(gpa);
}

/// A no-connect cross on each device pin with no other pin on its net.
fn noConnects(gpa: Allocator, s: *Schematic) !void {
    const count = try gpa.alloc(u32, s.net_name.len);
    defer gpa.free(count);
    @memset(count, 0);
    for (s.pins.items(.net)) |n| count[n] += 1;
    for (s.pins.items(.net)) |n| assert(count[n] >= 1);
    s.no_connects.clearRetainingCapacity();
    for (s.pins.items(.net), s.pins.items(.device), 0..) |n, d, p| {
        if (d != none and count[n] == 1) try s.no_connects.append(s.arena.allocator(), @intCast(p));
    }
}
