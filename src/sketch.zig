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
//! - sketch.19 (invariant) A visible pin gets a no-connect cross only
//!   when its net has no electrical peer. With a hidden body peer the
//!   visible resistor pin may carry the net name (AG1167/1169). `noConnects`
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
//! - sketch.24 (habit, bounded) A unique parallel tank capacitor uses its
//!   actual centered frame beside its fixed coil, opposite the actual tap.
//!   Caller geometry and occupied local room take precedence. `coil_tanks`
//! - sketch.25 (habit, bounded) A unique antiparallel clamp pair's controls
//!   face outward and matching nets occupy the same spatial channel end.
//!   All eight actual source devices agree. Couple the turns only while
//!   both actual frames support the joint rows, without either member's
//!   admitted origin/relation override. `antiparallel.placedMate`, `fits`
//!
//! - sketch.26 (habit, bounded) A complete mirrored pair of shared CT
//!   banks owns its ten actual frames atomically. Caller requests and
//!   unsupported geometry abstain as a whole. `coil_banks`, `coil_bank_place`
//! - sketch.27 (habit, bounded) A unique MOS clamp with four complementary
//!   channel-ended anchors uses one clear actual-frame position strictly
//!   between their drain tips. No lattice row or anchor moves. `clamp_anchors`
//! - sketch.28 (habit, bounded) Two private C-S-C paths use the surviving
//!   mirrored banks as fixed anchors. Place only their six devices, with
//!   caller precedence, actual path frames and rollback. `coil_chains`
//! - sketch.29 (habit, bounded) The paired banks' four direct/cross
//!   switches use drain rows and the observed upper-half crossing pose.
//!   Keep full caller frames and exact mates; abstain atomically on a
//!   collision or request. No wire policy changes. `coil_bridges`
//! - sketch.30 (habit, bounded) One unique CT/capacitor tank follows a
//!   verified pair of actual block output leads. The block stays fixed;
//!   a successful two-row transaction supersedes generic tank placement.
//!   Explicit requests and occupied room retain precedence. `block_tanks`
//! - sketch.31 (bounded observation) One complete CT/NPN feedback stage
//!   uses the observed tap-up, emitter-down frame above the foreign body
//!   band. All nine members move atomically; actual frames, admitted
//!   requests, mates and collisions retain precedence. `ct_feedback_stage`
//!
//! - sketch.32 (bounded observation) A closed resistor-loaded differential
//!   stage owns its six actual frames; two feed-forward stages sharing a
//!   complete tail bank own twelve. Separate local axes refine automatic
//!   bank arrangement while preserving caller requests and mate identities.
//!   `resistor_loads`, `resistor_load_place`
//! - sketch.33 (bounded observation) Two complete downstream RC input
//!   branches and bias chokes follow their actual block input frame. Five passive rows
//!   share a fresh-lattice room transaction with output tanks; rejected
//!   work restores the prior output-only path. `block_input_rc`, `block_rooms`
//!
//! Contents:
//! - `pub const parent_parts`, `pub fn layPanels`
//! - `pub fn layWithParents`, `pub fn layOrganized`, `pub fn layQualified`, `pub fn drawWithParents`
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
const relations = @import("relations.zig");
const opamp = @import("opamp.zig");
const transmission = @import("transmission.zig");
const antiparallel = @import("antiparallel.zig");
const clamp_anchors = @import("clamp_anchors.zig");
const power_paths = @import("power_paths.zig");
const power_loops = @import("power_loops.zig");
const power_loop_wires = @import("power_loop_wires.zig");
const wires = @import("wires.zig");
const netlines = @import("netlines.zig");
const pinned = @import("pinned.zig");
const hints = @import("hints.zig");
const routes = @import("routes.zig");
const Requests = @import("wire_requests.zig").Requests;
const maze = @import("maze.zig");
const canvas = @import("canvas.zig");
const power_compact = @import("power_compact.zig");
const bias_neighbors = @import("bias_neighbors.zig");
const coil_tanks = @import("coil_tanks.zig");
const block_tanks = @import("block_tanks.zig");
const block_input_rc = @import("block_input_rc.zig");
const block_input_place = @import("block_input_place.zig");
const block_rooms = @import("block_rooms.zig");
const ct_feedback_stage = @import("ct_feedback_stage.zig");
const ct_four_sides = @import("ct_four_sides.zig");
const ct_four_place = @import("ct_four_place.zig");
const ct_four_wires = @import("ct_four_wires.zig");
const resistor_loads = @import("resistor_loads.zig");
const resistor_load_place = @import("resistor_load_place.zig");
const resistor_downstream = @import("resistor_downstream.zig");
const coil_banks = @import("coil_banks.zig");
const coil_bank_place = @import("coil_bank_place.zig");
const coil_chains = @import("coil_chains.zig");
const coil_chain_place = @import("coil_chain_place.zig");
const coil_bridges = @import("coil_bridges.zig");
const lattice_geometry = @import("lattice_geometry.zig");
const thin = @import("thin.zig");
const relay = @import("relay.zig");
const config = @import("config.zig");
const lattice = @import("lattice_coordinates.zig");

/// Cold graph-bound MOS output pairs supplied by the selected-cell caller.
pub const parent_parts = @import("parent_parts.zig");
const parent_stages = @import("parent_stages.zig");
const source_bridge = @import("source_bridge.zig");

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
    return layQualified(gpa, nl, roles, lib, layout, pairs, stages, null, accepted);
}

/// Draws source-qualified geometry and reports its physical acceptance.
pub fn layQualified(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout, pairs: []const parent_parts.Pair, stages: []const parent_stages.Stage, bridge: ?source_bridge.Request, accepted: *bool) !Schematic {
    return layPanels(gpa, nl, roles, lib, layout, pairs, stages, if (bridge) |r| .{ .bridge = r } else null, false, accepted);
}

/// Runs a complete panel trial when requested and reports the final route admission.
pub fn layPanels(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout, pairs: []const parent_parts.Pair, stages: []const parent_stages.Stage, bridge: ?@import("source_layout.zig").Owner, panels: bool, accepted: *bool) !Schematic {
    var s = try sch.initDevices(gpa, nl, roles, lib);
    errdefer s.arena.deinit();
    const a = s.arena.allocator();
    const st = try structure.analyze(gpa, a, nl, roles);
    const sk = try skeleton.place(gpa, a, nl, roles, &st, .{ .shelf = layout.shelf });
    // `place`'s skeletons always hold.
    skeleton.validate(&sk, nl) catch unreachable;
    try drawValid(gpa, &s, nl, layout, &st, &sk, pairs, stages, bridge, panels, accepted);
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
    try drawValid(gpa, s, nl, layout, st, sk, pairs, &.{}, null, false, &accepted);
}

// ---- private ----

fn drawValid(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton, pairs: []const parent_parts.Pair, stages: []const parent_stages.Stage, bridge: ?@import("source_layout.zig").Owner, panels: bool, accepted: *bool) !void {
    // The deck's drawing lines; their verdicts are the report's to give.
    const sa = s.arena.allocator();
    const scratch = try sa.alloc(?hints.Verdict, nl.hints.len);
    @memset(scratch, null);
    var ats = try pinned.read(sa, nl, s.lib.unit, sk.drawn, scratch);
    const requested_places: []const ?pinned.At = if (pairs.len != 0 and
        (for (ats) |pose| {
            if (pose != null) break true;
        } else false)) try gpa.dupe(?pinned.At, ats) else &.{};
    defer gpa.free(requested_places);
    // A circuit of amplifier blocks and parts is placed along its signal
    // (`opamp.zig`), every device, unless a line of the deck places one.
    const along = try opamp.place(sa, nl, s.roles, st, sk, s.lib, s.devices.items(.class));
    if (along) |own| ats = own;
    s.refdes = try pinned.sides(sa, nl, scratch);
    orientAll(s, nl, st, sk, ats);
    var bias_pairs = try bias_neighbors.collect(gpa, nl, s, sk, st, ats);
    defer bias_pairs.deinit(gpa);
    const len = Lengths.of(layout, s.lib.unit);
    const lines = try netlines.read(sa, nl, s.roles, s.lib.unit, scratch);
    const parent_verdicts: []const hints.Verdict = if (stages.len != 0 or pairs.len != 0 or bridge != null)
        try @import("parent_intent.zig").admitted(sa, nl, s, st, sk)
    else
        &.{};
    const states = try gpa.alloc(parent_parts.State, pairs.len);
    defer gpa.free(states);
    for (pairs, states) |p, *state| state.* = parent_parts.initial(nl, p, &lines, parent_verdicts);
    const trial: parent_parts.Trial = .{ .states = states, .pairs = pairs, .nl = nl };
    var tanks = try coil_tanks.collect(gpa, nl, s, sk, st, ats, &lines);
    defer tanks.deinit(gpa);
    var block_loads = try block_tanks.collect(gpa, nl, s, sk, st, ats, &lines);
    defer block_loads.deinit(gpa);
    var block_inputs = try block_input_rc.collect(gpa, nl, s, sk, st, ats, &lines);
    defer block_inputs.deinit(gpa);
    var banks = try coil_banks.collect(gpa, nl, s, sk, st, ats, &lines);
    defer banks.deinit(gpa);
    var chains = try coil_chains.collect(gpa, nl, s, sk, st, ats, &lines, banks.pairs.items);
    defer chains.deinit(gpa);
    var bridges = try coil_bridges.collect(gpa, nl, s, sk, st, ats, banks.pairs.items);
    defer bridges.deinit(gpa);
    var clamps = try clamp_anchors.collect(gpa, nl, s, sk, st, ats, &lines);
    defer clamps.deinit(gpa);
    var feedback = try ct_feedback_stage.collect(gpa, nl, s, sk, st, ats, &lines);
    defer feedback.deinit(gpa);
    var four_sides = try ct_four_sides.collect(gpa, nl, s, sk, st, ats, &lines);
    defer four_sides.deinit(gpa);
    var resistor_stages = try resistor_loads.collect(gpa, nl, s, sk, st, ats, &lines);
    defer resistor_stages.deinit(gpa);
    const loops = try power_loop_wires.collect(gpa, nl, s.roles, sk.drawn, &lines);
    defer gpa.free(loops);
    // Each drawn device's point: the lattice's.
    const n = nl.graph.edgeCount();
    const at = try gpa.alloc([2]f32, n);
    defer gpa.free(at);
    @memset(at, .{ 0, 0 });
    var placed_all = true;
    var block_reserved = false;
    const fresh = along == null and for (ats) |fixed| {
        if (fixed != null) break false;
    } else true;
    if (fresh and (block_loads.groups.items.len > 0 or block_inputs.groups.items.len > 0)) {
        block_reserved = try block_rooms.lattice(gpa, s, nl, sk, len, at, &block_loads, &block_inputs, &tanks.pairs);
        placed_all = false;
    } else {
        block_inputs.groups.items.len = 0;
        const geo = try lattice.coordinates(gpa, s, nl, sk, len);
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
    if (!block_reserved) block_tanks.place(s, nl, sk, ats, len, at, &block_loads.groups, &tanks.pairs);
    coil_tanks.place(s, nl, sk, ats, len, at, &tanks.pairs);
    coil_bank_place.place(s, nl, sk, ats, len, at, &banks.pairs);
    coil_chain_place.place(s, nl, sk, ats, len, at, banks.pairs.items, &chains.owners);
    coil_bridges.place(s, nl, sk, ats, len, at, banks.pairs.items, &bridges.owners);
    clamp_anchors.place(s, sk, ats, len, at, &clamps.groups);
    ct_feedback_stage.place(s, nl, sk, ats, len, at, &feedback.groups);
    ct_four_place.place(s, nl, sk, ats, len, at, &four_sides.groups);
    const four_wires = ct_four_wires.qualify(nl, four_sides.groups.items, scratch, &lines);
    resistor_load_place.place(s, nl, sk, ats, len, at, &resistor_stages);
    const load_parts = resistor_downstream.qualify(nl, s.roles, resistor_stages.pairs.items, sk.verdicts, st.verdicts, scratch, &lines);
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
        own.routes = &.{}; // Absolute paths wait; lines.routes still protects caller intent.
        try wireUp(gpa, s, nl, sk, st, len, at, no_ats, &own, .{ .routes = lines.routes, .ats = ats }, loops, .{}, resistor_stages.singles.items, resistor_stages.pairs.items, load_parts, four_wires, &xy, false);
        try power_compact.squeeze(gpa, s, nl, sk, ats, len, coil_bank_place.axis(s, banks.pairs.items) orelse ct_four_place.axis(s, four_sides.groups.items) orelse try power_compact.drawnAxis2(gpa, s, sk), &.{
            bias_neighbors.orders(s, bias_pairs.pairs.items, bias_pairs.coordinates),
            block_tanks.orders(s, block_loads.groups.items, block_loads.coordinates),
            block_input_place.orders(s, nl, &block_inputs),
            coil_tanks.orders(s, tanks.pairs.items, tanks.coordinates),
            coil_bank_place.orders(s, banks.pairs.items, banks.coordinates),
            coil_chain_place.orders(s, banks.pairs.items, chains.owners.items, chains.coordinates),
            coil_bridges.orders(s, banks.pairs.items, bridges.owners.items, bridges.coordinates),
            clamp_anchors.orders(s, clamps.groups.items, clamps.coordinates),
            ct_feedback_stage.orders(s, nl, feedback.groups.items, feedback.coordinates),
            ct_four_place.orders(s, nl, four_sides.groups.items, four_sides.coordinates),
            resistor_load_place.orders(s, nl, sk, &resistor_stages),
        });
        const clear = try power_compact.clear(gpa, s, nl, sk);
        // ponytail: an overlap after the squeeze keeps the lattice's places.
        if (clear) for (at, 0..) |*p, d| if (sk.drawn[d]) {
            p.* = s.xy[s.deviceNode(@intCast(d)).?];
        };
        wipe(s, &xy);
    }
    try keepAts(gpa, s, nl, sk, at, ats);
    var available: std.ArrayList(parent_stages.Stage) = .empty;
    for (stages) |stage| {
        for (nl.hints, parent_verdicts) |h, verdict| {
            if (@import("parent_intent.zig").touches(nl, h, verdict, &stage.devices, &.{})) break;
        } else try available.append(sa, stage);
    }
    accepted.* = available.items.len > 0 and try parent_stages.arrange(gpa, s, sk, at, available.items);
    if (panels) accepted.* = accepted.* and @import("comparator_panels.zig").arrange(nl, s, sk, at, available.items, pairs, states, parent_verdicts);
    if (bridge) |request| accepted.* = @import("source_layout.zig").arrange(request, nl, s, sk, at, parent_verdicts);
    trial.holdPlaces(s, requested_places, ats, at);
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
            try wireUp(gpa, s, nl, sk, st, len, at, ats, &thinned, .{ .routes = lines.routes, .ats = ats }, loops, trial, resistor_stages.singles.items, resistor_stages.pairs.items, load_parts, four_wires, &xy, true);
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
        if (state != .drawn and state != .caller) {
            accepted.* = false;
            break;
        }
    };
    try noConnects(gpa, s, nl, lines.style);
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
fn wireUp(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, st: *const Structure, len: Lengths, at: []const [2]f32, ats: []const ?pinned.At, lines: *const netlines.NetLines, requests: Requests, loops: []const power_loops.Group, trial: parent_parts.Trial, load_singles: []const resistor_loads.Group, load_pairs: []const resistor_loads.Pair, downstream: []const resistor_loads.Pair, four_groups: []const ct_four_sides.Group, xy: *std.ArrayList([2]f32), final_routes: bool) !void {
    try placeDevices(s, nl, sk, at, ats, xy);
    s.xy = xy.items;
    const boxes = try power_compact.deviceBoxes(gpa, s, nl, sk);
    defer gpa.free(boxes);
    const hidden = try hiddenPins(gpa, s, nl, sk);
    defer gpa.free(hidden);
    try wires.wire(gpa, s, nl, xy, len, boxes, hidden, drawnMirror(s, sk, st), st.net_rank, lines, requests, loops, trial, sk.bridged_t, final_routes, load_singles, load_pairs, downstream, four_groups);
    s.xy = xy.items;
}

/// Keeps each `at` whose symbol, at its place and turn, overlaps no other
/// drawn device's (the preferred of two `at` devices stays), and turns the
/// kept ones; drops the rest (`ats[d] = null`). The report says which. A
/// device no `at` places, standing where one puts another, steps right
/// first (`at[e]`), a unit at a time, to the first place no symbol holds.
fn keepAts(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, at: [][2]f32, ats: []?pinned.At) !void {
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
    // A line beats the engine: a device the lattice put on an `at`'s place
    // moves off it (a Schemify round trip pinned every device but one, or
    // added one; the lattice stood it on a pinned place, and that line
    // was dropped). Past every box it overlaps nothing.
    var right: i32 = std.math.minInt(i32);
    for (0..n) |d| if (sk.drawn[d]) {
        right = @max(right, boxes[d].max.x);
    };
    const step: f32 = @floatFromInt(s.lib.unit);
    for (0..n) |e| {
        if (!sk.drawn[e] or ats[e] != null) continue;
        const pinned_on = for (0..n) |d| {
            if (d != e and sk.drawn[d] and ats[d] != null and boxes[e].intersects(boxes[d])) break true;
        } else false;
        if (!pinned_on) continue;
        while (for (0..n) |d| {
            if (d != e and sk.drawn[d] and boxes[e].intersects(boxes[d])) break true;
        } else false) {
            assert(boxes[e].min.x <= right);
            at[e][0] += step;
            boxes[e] = boxAt(s, e, toPt(at[e]));
        }
        right = @max(right, boxes[e].max.x);
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
fn orientAll(s: *Schematic, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, ats: []const ?pinned.At) void {
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
        const clamp = if (vertical) null else if (antiparallel.placedMate(s, nl, sk, ats, EdgeId.from(d))) |m| m.index() else null;
        const gate_side = if (vertical) null else if (clamp) |m|
            (if (sk.y[d] < sk.y[m]) Side.up else Side.down)
        else
            controlSide(nl, s.roles, sk, @intCast(d));
        for (flips) |f| {
            if (!fits(nl, sk, class, @intCast(d), Orient.flipped(base, f[0], f[1]), vertical, gate_side, clamp)) continue;
            info.items(.flip_x)[d] = f[0];
            info.items(.flip_y)[d] = f[1];
            break;
        }
    }
    turnBlocks(s, nl, st, sk);
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

/// Turns each drawn block a `face <block> <port> <side>` line names
/// (admitted by `relations.faces`) to the first of its turns, unrotated
/// first, that puts the port on that side; the preferred line is applied
/// last. Then each pair of blocks an admitted `symmetric` line mates is
/// drawn as mirror images: the one a line turned, else the left one, leads.
fn turnBlocks(s: *Schematic, nl: *const Netlist, st: *const Structure, sk: *const Skeleton) void {
    const c = &nl.graph;
    const info = s.devices.slice();
    const kinds = c.edges.items(.kind);
    assert(st.device_mate.len == c.edgeCount());
    assert(sk.verdicts.len == nl.hints.len);
    for (nl.hints, sk.verdicts) |h, v| {
        if (h.verb != .face or h.args.len != 3 or v == null or v.?.state != .honoured) continue;
        const d = nl.device(h.args[0]).?.index();
        if (kinds[d] != .subckt or !sk.drawn[d]) continue;
        const pin = relations.pinIndex(nl, @intCast(d), h.args[1]).?;
        const side = h.verb.side(Side, h.args[2]).?;
        const class = s.lib.at(info.items(.class)[d]);
        turn: for ([_]sch.Orientation{ .horizontal, .vertical }) |form| for (flips) |f| {
            if (class.side(pin, Orient.flipped(sch.form(form), f[0], f[1])) != side) continue;
            info.items(.orientation)[d] = form;
            info.items(.flip_x)[d] = f[0];
            info.items(.flip_y)[d] = f[1];
            break :turn;
        };
    }
    for (nl.hints, st.verdicts) |h, v| {
        if (h.verb != .symmetric or h.args.len != 2 or v == null or v.?.state != .honoured) continue;
        const d = nl.device(h.args[0]).?.index();
        const m = st.device_mate[d];
        if (m != nl.device(h.args[1]).?.index() or kinds[d] != .subckt or kinds[m] != .subckt) continue;
        if (!sk.drawn[d] or !sk.drawn[m] or sk.x[d] == sk.x[m]) continue;
        const left, const right = if (sk.x[d] < sk.x[m]) .{ d, m } else .{ m, d };
        const lead, const image = if (blockFaced(nl, sk, right) and !blockFaced(nl, sk, left)) .{ right, left } else .{ left, right };
        if (blockFaced(nl, sk, image)) continue;
        info.items(.orientation)[image] = info.items(.orientation)[lead];
        info.items(.flip_x)[image] = !info.items(.flip_x)[lead];
        info.items(.flip_y)[image] = info.items(.flip_y)[lead];
    }
}

/// Whether an admitted `face` line names block `d`.
// ponytail: a pass over the deck's lines per mated block; a bitset if a
// deck ever holds many.
fn blockFaced(nl: *const Netlist, sk: *const Skeleton, d: usize) bool {
    for (nl.hints, sk.verdicts) |h, v| {
        if (h.verb != .face or h.args.len != 3 or v == null or v.?.state != .honoured) continue;
        if (nl.device(h.args[0]).?.index() == d) return true;
    }
    return false;
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
fn fits(nl: *const Netlist, sk: *const Skeleton, class: library.Class, d: u32, o: Orient, vertical: bool, gate_side: ?Side, clamp: ?u32) bool {
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
    const anchor = if (clamp) |m| (if (sk.y[d] < sk.y[m]) d else m) else d;
    const left = firstLeft(nl, sk, anchor, path) orelse return true;
    return (s0 == .left) == (if (anchor == d) left else !left);
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

/// A no-connect cross on each device pin with no other pin on its net.
fn noConnects(gpa: Allocator, s: *Schematic, nl: *const Netlist, style: []const netlines.Style) !void {
    const count = try gpa.alloc(u32, s.net_name.len);
    defer gpa.free(count);
    @memset(count, 0);
    for (s.pins.items(.net)) |n| count[n] += 1;
    for (s.pins.items(.net)) |n| assert(count[n] >= 1);
    s.no_connects.clearRetainingCapacity();
    s.peer_labels.clearRetainingCapacity();
    for (s.pins.items(.net), s.pins.items(.device), 0..) |n, d, p| {
        if (d == none or count[n] != 1) continue;
        if (nl.graph.incident(netlist.VertexId.from(n)).len == 1) {
            try s.no_connects.append(s.arena.allocator(), @intCast(p));
        } else if (style[n] == .auto and s.roles[n] == .internal) {
            try s.peer_labels.append(s.arena.allocator(), @intCast(p));
        }
    }
}
