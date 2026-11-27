//! Stage 3 of issue #8: where each drawn device stands, as a cell of a
//! lattice. In: the netlist, its roles and its structure. Out, per device:
//! drawn or not; its form (vertical: current enters at its top and leaves
//! at its bottom; horizontal: a bridge between columns); which side its
//! gate faces; its x and y. Neighbouring device columns stand eight
//! lattice columns apart and device rows two apart, so a channel lies
//! between any two: taps, bridges and wires go there. Forms are
//! `forms.zig`'s, mates `mates.zig`'s, rows `levels.zig`'s, column order
//! `columns.zig`'s, flat parts `bridges.zig`'s, shelves `wrap.zig`'s.
//!
//! Human Rules:
//! - skeleton.1 (order: potential) Upright devices stand in one column
//!   when one's lower end and the other's upper end are one net, never
//!   through a rail; a column is a chain current flows down. `link`
//!   A `column` line links its devices whatever their nets
//!   (relations.13).
//! - skeleton.2 (unmeasured) Where several devices meet on a net, a stack
//!   block's two (hinted or recognized) share a column first. `choose`
//! - skeleton.3 (unmeasured) No column runs through a pair: where the
//!   devices above or below a net are two mates or a differential or
//!   cross-coupled pair, nothing links across it, and the pair's tail
//!   stands in a column of its own. `choose`
//! - skeleton.4 (habit) Else the link follows the current: the device
//!   below is of the upper one's type first; then, on either side, a
//!   transistor before a part and a part direct current passes before a
//!   capacitor, which hangs beside the column. People, on the nets where
//!   one device meets several that differ on it, in 5,263 hand-drawn
//!   schematics: the same type 278 of 291, a transistor 369 of 401, direct
//!   current 749 of 778. Then one whose column reaches a rail, the engine's
//!   tie-break (people: 261 of 465), then rank. `choose`
//! - skeleton.5 (invariant) The net the symmetry pairs with a net gets
//!   the mirror image of its link. `link`
//! - skeleton.6 (choice) Device columns stand 8 lattice columns apart and
//!   device rows 2 apart: a channel between any two holds taps, wires and
//!   seven bridge slots. `lay`
//! - skeleton.7 (invariant) Mated upright devices stand mirror images
//!   about one axis; a pair a line moves apart, or a device its own mate
//!   whose column left the axis, is mated no more. `lay`
//! - skeleton.8 (invariant) No two drawn devices share a cell.
//!   `expectDistinctCells`
//! - skeleton.9 (habit) A transistor's gate faces the mean of the rest of
//!   its gate net, what drives it and what it drives with it. People:
//!   4,558 of 5,685 transistors of no block in 5,263 hand-drawn schematics
//!   (3,982 of 4,374 where a current path drives the net). `gates`
//! - skeleton.14 (order: signal) A gate with nothing in the drawing to face
//!   (alone on its net, or on a rail) faces left, the side its signal
//!   enters by; one with a mate elsewhere faces away from its mate, the
//!   mirror image (skeleton.7). People: 2,684 of 3,317 left, 283 of 367
//!   away from the mate; away from the drawing's middle, the rule this
//!   replaces, 1,914 of 3,043. `gates`
//! - skeleton.10 (habit) A differential pair's gates face out. People:
//!   1,396 of 1,579 pairs in 5,263 hand-drawn schematics. `gates`
//! - skeleton.11 (habit) The two of a mirror or cross-coupled pair face
//!   each other. People: 2,685 of 3,130 mirrors of two and 214 of 239
//!   cross-coupled pairs. A bank's two do too here, a choice: people 962
//!   of 1,968 (600 face out). A mirror or bank of three or more has no
//!   rule of its own: skeleton.9 turns each gate (people turn all of one
//!   left, the rule retired as skeleton.12, in 12 of 1,103 such mirrors
//!   and 88 of 380 banks). A reciprocal load row with two diodes follows
//!   its input columns and their associated terminals. `gates`, `cross_loads`
//! - skeleton.15 (habit, bounded) A two-MOS bank with one complete analog
//!   block output and otherwise only capacitors on its gate net faces an
//!   exterior driver. All 42 actual source gates in 21 selected banks do
//!   so. Keep existing mates, ambiguous incidences and an interior driver;
//!   explicit faces still run last. No source row or universal wire-tree
//!   policy follows: 17 banks occupy unequal rows and two have a detached
//!   remote gate. docs/research/driven-banks.md; `bankDriver`, `gates`
//! - skeleton.13 (choice) A flat part `forms.crooked` stands upright
//!   (forms.15) is placed by laying the whole drawing again, not moved
//!   alone: it then follows every rule an upright part does. `place`
//!
//! Contents:
//! - `pub const Form = enum(u8) { vertical, horizontal }`
//! - `pub const End = enum(u8) { auto, first, second }`
//! - `pub const Skeleton = struct`
//! - `pub const Options = struct { shelf: u32 = (config.Layout{}).shelf }`
//! - `pub fn place(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, opts: Options) Allocator.Error!Skeleton`
//! - `pub const Invalid = error{...}`, `pub fn validate(sk: *const Skeleton, nl: *const Netlist) Invalid!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const symmetry = @import("symmetry.zig");
const columns = @import("columns.zig");
const levels = @import("levels.zig");
const bridges = @import("bridges.zig");
const block_symbols = @import("block_symbols.zig");
const relations = @import("relations.zig");
const anchored = @import("anchored.zig");
const sequence = @import("sequence.zig");
const mates = @import("mates.zig");
const wrap = @import("wrap.zig");
const cells = @import("cells.zig");
const units = @import("units.zig");
const hints = @import("hints.zig");
const forms = @import("forms.zig");
const passive_filters = @import("passive_filters.zig");
const loop_place = @import("loop_place.zig");
const sampling_bridge = @import("sampling_bridge.zig");
const cross_loads = @import("cross_loads.zig");
const input_place = @import("input_place.zig");
const config = @import("config.zig");

const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Structure = structure.Structure;
const none = structure.none;
const isTransistor = device.isTransistor;
const isRail = Role.isRail;

pub const Form = enum(u8) { vertical, horizontal };

/// The end of a flat two-pin device a `face` line puts on the left: its
/// first pin, its second, or `auto`, the drawing's choice.
pub const End = enum(u8) { auto, first, second };

/// What of the drawing's style (`config.Layout`) decides a cell.
pub const Options = struct {
    /// Device columns a row holds before it wraps (`wrap.zig`); 0: one row.
    shelf: u32 = (config.Layout{}).shelf,
};

/// One entry per device, in card order. A device that is not drawn (a
/// driver, a card with no pins) has `drawn` false and the rest unspecified.
pub const Skeleton = struct {
    /// The tapped two-arm path owns both ports in a matched passive bridged T.
    bridged_t: bool = false,
    drawn: []const bool,
    form: []const Form,
    /// A vertical device's upper and lower ends' nets; `none` otherwise.
    upper: []const u32,
    lower: []const u32,
    /// Its gate (side pins) faces right.
    gate_right: []const bool,
    /// A flat two-pin device's end a `face` line puts on the left.
    left_end: []const End,
    /// Its cell; the smallest of each axis is 0.
    x: []const i32,
    y: []const i32,
    /// The row of columns its cell is in, top 0 (`wrap.zig`): a net between
    /// two is joined by name.
    shelf: []const u32,
    /// Twice the x of the axis mated devices mirror about, if any.
    axis2: ?i32,
    /// Where cell (0, 0) is in the frame `cell` lines use (before the cells
    /// shift to start at 0): add it to a cell to get that frame's.
    origin: [2]i32,
    /// Per deck hint: what became of it, for the lines this stage owns
    /// (`upright`, `bridge`, `face`, `row`, `above`); null for the rest.
    verdicts: []const ?hints.Verdict,
};

/// What a skeleton edited by a caller can get wrong for the drawing.
pub const Invalid = error{
    /// A slice is not one entry per device.
    WrongLength,
    /// A drawn device's cell is negative.
    OffLattice,
    /// Two drawn devices share a cell.
    CellTaken,
    /// A vertical device's ends are not two of its nets.
    BadEnds,
};

/// Lattice columns between neighbouring device columns, per step of
/// `columns.order`: the slots between hold bridges.
const spread = 4;

/// Each device's neighbours in its column, or `none`.
const Chain = struct {
    above: []u32,
    below: []u32,
};

/// Asserts that `roles` has one entry per net and `st` comes from `nl`.
pub fn place(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, opts: Options) Allocator.Error!Skeleton {
    const passive = passive_filters.find(nl, roles, st.net_rank, opts.shelf);
    const first = try lay(gpa, arena, nl, roles, st, opts, null, passive);
    if (passive != null) return first;
    // A flat part that cannot be wired straight stands upright, and the
    // skeleton is laid once more (`crooked`).
    const stood = try gpa.alloc(bool, nl.graph.edgeCount());
    defer gpa.free(stood);
    if (!forms.crooked(nl, roles, st, &first, spread, stood)) return first;
    return lay(gpa, arena, nl, roles, st, opts, stood, null);
}

/// Checks what `sketch.draw` relies on in `sk`, as a caller may have edited
/// it: one entry per device, drawn devices on distinct cells of the lattice
/// (x and y at least 0), and each vertical device's upper and lower ends two
/// distinct nets it touches. `place`'s own skeletons always pass.
pub fn validate(sk: *const Skeleton, nl: *const Netlist) Invalid!void {
    const c = &nl.graph;
    const n = c.edgeCount();
    for ([_]usize{ sk.drawn.len, sk.form.len, sk.upper.len, sk.lower.len, sk.gate_right.len, sk.left_end.len, sk.x.len, sk.y.len, sk.shelf.len }) |len| {
        if (len != n) return error.WrongLength;
    }
    for (0..n) |d| {
        if (!sk.drawn[d]) continue;
        if (sk.x[d] < 0 or sk.y[d] < 0) return error.OffLattice;
        for (d + 1..n) |e| {
            if (sk.drawn[e] and sk.x[e] == sk.x[d] and sk.y[e] == sk.y[d]) return error.CellTaken;
        }
        if (sk.form[d] != .vertical) continue;
        const up = sk.upper[d];
        const low = sk.lower[d];
        if (up == low or up >= c.vertexCount() or low >= c.vertexCount()) return error.BadEnds;
        var has_up = false;
        var has_low = false;
        for (c.members(EdgeId.from(d))) |net| {
            has_up = has_up or net.index() == up;
            has_low = has_low or net.index() == low;
        }
        if (!has_up or !has_low) return error.BadEnds;
    }
}

// ---- private ----

/// The skeleton with the forms `classify` gives, and the devices `stood`
/// marks (if any) upright all the same.
fn lay(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, opts: Options, stood: ?[]const bool, passive: ?passive_filters.Frame) Allocator.Error!Skeleton {
    const c = &nl.graph;
    const n = c.edgeCount();
    assert(roles.len == c.vertexCount());
    assert(st.device_rank.len == n);
    const drawn = try arena.alloc(bool, n);
    const form = try arena.alloc(Form, n);
    const upper = try arena.alloc(u32, n);
    const lower = try arena.alloc(u32, n);
    const gate_right = try arena.alloc(bool, n);
    const left_end = try arena.alloc(End, n);
    @memset(left_end, .auto);
    const x = try arena.alloc(i32, n);
    const y = try arena.alloc(i32, n);
    @memset(x, 0);
    @memset(y, 0);
    @memset(gate_right, false);

    const verdicts = try arena.alloc(?hints.Verdict, nl.hints.len);
    @memset(verdicts, null);
    const shelf = try arena.alloc(u32, n);
    @memset(shelf, 0);
    if (passive) |frame| {
        @memset(drawn, true);
        if (n == 5) try relations.drivers(gpa, nl, drawn, verdicts);
        frame.apply(nl, form, upper, lower, left_end, x, y);
        return .{ .bridged_t = n == 4, .drawn = drawn, .form = form, .upper = upper, .lower = lower, .gate_right = gate_right, .left_end = left_end, .x = x, .y = y, .shelf = shelf, .axis2 = null, .origin = .{ 0, 0 }, .verdicts = verdicts };
    }
    try forms.classify(gpa, nl, roles, st, drawn, form, verdicts);
    try relations.forms(arena, nl, drawn, form, verdicts);
    if (stood) |up| for (up, form, drawn) |u, *f, dr| {
        if (u and dr) f.* = .vertical;
    };
    try forms.ends(gpa, nl, roles, drawn, form, upper, lower);
    // A MOS whose image traded its drain and source (symmetry.8) turns
    // with it: its upper end is the image of its mate's.
    for (st.device_mate, 0..) |m, d| {
        if (m == none or m <= d or !drawn[d] or form[d] != .vertical or form[m] != .vertical) continue;
        if (c.edges.items(.kind)[m] == .mosfet and st.net_mate[upper[d]] == lower[m]) std.mem.swap(u32, &upper[m], &lower[m]);
    }
    try relations.ends(arena, nl, drawn, form, upper, lower, verdicts);
    const rel = try relations.rows(gpa, arena, nl, st, drawn, form, verdicts);
    const seq = try sequence.read(gpa, arena, nl, st, drawn, form, rel.links, verdicts);
    const unit = try units.read(arena, nl, drawn, verdicts);
    const net_rank = st.net_rank;
    const above = try gpa.alloc(u32, n);
    defer gpa.free(above);
    const below = try gpa.alloc(u32, n);
    defer gpa.free(below);
    var chain: Chain = .{ .above = above, .below = below };
    try link(gpa, nl, roles, st, net_rank, &rel, &seq, drawn, form, upper, lower, &chain);

    // Columns: chains from their top devices, in rank order.
    const column_of = try gpa.alloc(u32, n);
    defer gpa.free(column_of);
    @memset(column_of, none);
    var start: std.ArrayList(u32) = .empty;
    defer start.deinit(gpa);
    var members: std.ArrayList(u32) = .empty;
    defer members.deinit(gpa);
    try start.append(gpa, 0);
    const devices_by_rank = try byRank(gpa, st.device_rank);
    defer gpa.free(devices_by_rank);
    for (devices_by_rank) |d| {
        if (!drawn[d] or form[d] != .vertical or chain.above[d] != none) continue;
        var at = d;
        while (at != none) : (at = chain.below[at]) {
            assert(members.items.len < n);
            column_of[at] = @intCast(start.items.len - 1);
            try members.append(gpa, at);
        }
        try start.append(gpa, @intCast(members.items.len));
    }

    const mate = try mates.find(gpa, nl, roles, st, drawn, form, column_of, chain.above, chain.below, start.items.len - 1);
    defer gpa.free(mate);
    const rank = try levels.rows(gpa, nl, roles, st, &rel, mate, chain.below, unit, drawn, form, upper, lower);
    defer gpa.free(rank);
    const cols: columns.Columns = .{ .start = start.items, .devices = members.items };
    const partners = try gpa.alloc(u32, n);
    defer gpa.free(partners);
    for (partners, 0..) |*p, d| p.* = blockPartner(st, @intCast(d));
    const col_x = try columns.order(gpa, nl, roles, cols, column_of, mate, partners, st.device_rank, rank);
    defer gpa.free(col_x);
    try sequence.columns(gpa, &seq, column_of, col_x);
    for (0..n) |d| {
        if (!drawn[d] or form[d] != .vertical) continue;
        x[d] = spread * col_x[column_of[d]];
        y[d] = 2 * @as(i32, @intCast(rank[d]));
    }
    // The axis row can hold only one independent tail. Resolve collisions
    // in canonical device order; cell and exact poses are admitted later.
    const has_axis = for (nl.hints, st.verdicts) |h, v| {
        if (h.verb == .axis and v != null and v.?.state == .honoured) break true;
    } else false;
    if (has_axis) for (devices_by_rank) |d| {
        if (mate[d] != d or !drawn[d] or form[d] != .vertical or x[d] == 0) continue;
        if (c.edges.items(.kind)[d] != .isource or roles[lower[d]] != .sink) continue;
        if (chain.above[d] != none or chain.below[d] != none) continue;
        const requested = for (nl.hints, st.verdicts) |h, v| {
            if (h.verb != .axis or v == null or v.?.state != .honoured) continue;
            // The same verb also accepts net identities.
            const target = nl.device(h.args[0]) orelse continue;
            if (target.index() == d) break true;
        } else false;
        if (!requested) continue;
        // Retain admitted row/above/order relations including bridge rows.
        const bound = for (seq.pairs) |e| {
            if (e[0] == d or e[1] == d) break true;
        } else for (rel.edges) |e| {
            if (e[0] == d or e[1] == d) break true;
        } else for (rel.bridge_row, 0..) |bridge_row, e| {
            if (bridge_row == d or (e != d and rel.find(@intCast(e)) == rel.find(d))) break true;
        } else false;
        if (bound) continue;
        var bottom = y[d];
        var occupied = false;
        for (drawn, form, x, y) |shown, orientation, cx, cy| {
            if (!shown or orientation != .vertical) continue;
            bottom = @max(bottom, cy);
            occupied = occupied or (cx == 0 and cy == y[d]);
        }
        x[d] = 0;
        if (occupied) y[d] = bottom + 2;
    };
    // The core stands about x = 0 until the cells shift to start at 0; a
    // device its own mate whose column went free keeps none.
    var mated = false;
    for (mate, 0..) |*m, d| {
        // An order line that moved one of a pair ends the pair.
        if (m.* != none and m.* != d and x[d] + x[m.*] != 0) {
            mate[m.*] = none;
            m.* = none;
        }
        if (m.* == d and x[d] != 0) m.* = none;
        mated = mated or (m.* != none and drawn[d] and form[d] == .vertical);
    }
    try bridges.place(gpa, nl, roles, st, devices_by_rank, drawn, form, upper, lower, rank, mate, seq.pairs, if (mated) 0 else null, x, y);
    // Bridges an order line moves first: a block it moves carries the parts
    // an `above` line stands in its column.
    try sequence.bridges(gpa, &seq, rel.bridge_row, devices_by_rank, drawn, form, x, y, verdicts);
    try anchored.place(gpa, nl, drawn, form, x, y, verdicts);
    try units.apply(gpa, arena, nl, drawn, form, x, y, verdicts);
    try cells.apply(gpa, arena, nl, drawn, mate, x, y, verdicts);
    mated = false;
    for (mate, 0..) |m, d| mated = mated or (m != none and drawn[d] and form[d] == .vertical);
    gates(nl, roles, st, mate, drawn, form, x, gate_right);
    cross_loads.place(nl, roles, st, mate, drawn, form, x, y, gate_right, verdicts);
    // A gate a line turns against its mate's ends the mirror.
    const mirrored = try relations.faces(arena, nl, drawn, form, mate, gate_right, left_end, verdicts);
    try anchored.hang(gpa, nl, drawn, form, upper, lower, gate_right, left_end, x, y, verdicts);
    var protected = try loop_place.place(gpa, nl, roles, drawn, form, upper, mate, left_end, x, y, verdicts);
    defer protected.deinit(gpa);
    try input_place.place(gpa, nl, roles, devices_by_rank, st.device_rank, drawn, form, upper, mate, gate_right, left_end, x, y, verdicts, &protected);
    try sampling_bridge.place(gpa, &protected, nl, roles, drawn, mate, form, upper, lower, x, y);
    try wrap.shelves(gpa, nl, roles, drawn, form, mate, opts.shelf, x, y, shelf, verdicts, protected.items);
    const origin = normalize(drawn, x, y);
    try expectDistinctCells(gpa, drawn, x, y);
    const axis2: ?i32 = if (mated and mirrored) -2 * origin[0] else null;
    if (axis2) |a2| for (mate, 0..) |m, d| if (m != none and drawn[d] and form[d] == .vertical) assert(x[d] + x[m] == a2);
    return .{ .drawn = drawn, .form = form, .upper = upper, .lower = lower, .gate_right = gate_right, .left_end = left_end, .x = x, .y = y, .shelf = shelf, .axis2 = axis2, .origin = origin, .verdicts = verdicts };
}

fn byRank(gpa: Allocator, rank: []const u32) ![]u32 {
    const order = try gpa.alloc(u32, rank.len);
    for (rank, 0..) |r, d| {
        assert(r < rank.len);
        order[r] = @intCast(d);
    }
    for (order, 0..) |d, r| assert(rank[d] == r);
    return order;
}

/// The other member of `d`'s differential or cross-coupled pair, or `none`.
fn blockPartner(st: *const Structure, d: u32) u32 {
    for (st.block_kind, 0..) |k, b| {
        if (!k.ofTwo()) continue;
        const ms = st.members(b);
        if (ms[0] == d) return ms[1];
        if (ms[1] == d) return ms[0];
    }
    return none;
}

/// The `column` lines' links, then one link per net: from a device whose
/// lower end is on it to one whose upper end is, none across a pair (a tail
/// stands alone). The symmetry's mate net gets the mirrored link.
fn link(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, net_rank: []const u32, rel: *const relations.Relations, seq: *const sequence.Sequence, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, chain: *Chain) !void {
    assert(net_rank.len == roles.len);
    assert(chain.above.len == drawn.len);
    @memset(chain.above, none);
    @memset(chain.below, none);
    // The `column` lines' links first: the engine's own go around them.
    for (rel.links) |k| {
        assert(chain.below[k[0]] == none or chain.below[k[0]] == k[1]);
        chain.below[k[0]] = k[1];
        chain.above[k[1]] = k[0];
    }
    var ups: std.ArrayList(u32) = .empty;
    defer ups.deinit(gpa);
    var downs: std.ArrayList(u32) = .empty;
    defer downs.deinit(gpa);
    const nets = try byRank(gpa, net_rank);
    defer gpa.free(nets);
    // Each device's next one down its stack block, hinted or recognized.
    const stacked = try gpa.alloc(u32, drawn.len);
    defer gpa.free(stacked);
    @memset(stacked, none);
    for (st.block_kind, 0..) |k, b| if (k == .stack) {
        const ms = st.members(b);
        for (ms[0 .. ms.len - 1], ms[1..]) |u, l| stacked[u] = l;
    };
    for (nets) |net| {
        if (isRail(roles[net])) continue;
        const m = st.net_mate[net];
        if (m != none and m != net and net_rank[m] < net_rank[net]) continue;
        try endsOn(gpa, nl, drawn, form, upper, lower, net, &ups, &downs);
        const u, const l = choose(nl, st, upper, lower, roles, chain, stacked, ups.items, downs.items) orelse continue;
        if (closesLoop(chain, u, l) or try rel.refuses(gpa, chain.below, u, l) or try seq.refuses(gpa, chain.above, u, l)) continue;
        chain.below[u] = l;
        chain.above[l] = u;
        if (m == none or m == net) continue;
        const mu = st.device_mate[u];
        const ml = st.device_mate[l];
        if (mu == none or ml == none or chain.below[mu] != none or chain.above[ml] != none) continue;
        if (lower[mu] != m or upper[ml] != m or closesLoop(chain, mu, ml) or try rel.refuses(gpa, chain.below, mu, ml) or try seq.refuses(gpa, chain.above, mu, ml)) continue;
        chain.below[mu] = ml;
        chain.above[ml] = mu;
    }
    for (chain.below, 0..) |b, d| if (b != none) assert(chain.above[b] == d);
}

/// Whether `u` over `l` closes a loop: `u` stands below `l` already (two
/// devices joined by both their ends, each over the other on one net).
fn closesLoop(chain: *const Chain, u: u32, l: u32) bool {
    var d = l;
    var steps: usize = 0;
    while (d != none) : (steps += 1) {
        assert(steps <= chain.below.len);
        if (d == u) return true;
        d = chain.below[d];
    }
    return false;
}

/// The drawn vertical devices with their lower end (`ups`) and upper end
/// (`downs`) on `net`, each once.
fn endsOn(gpa: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, net: u32, ups: *std.ArrayList(u32), downs: *std.ArrayList(u32)) !void {
    ups.clearRetainingCapacity();
    downs.clearRetainingCapacity();
    for (nl.graph.incident(VertexId.from(net))) |e| {
        const d = e.index();
        if (!drawn[d] or form[d] != .vertical) continue;
        if (lower[d] == net and std.mem.indexOfScalar(u32, ups.items, d) == null) try ups.append(gpa, d);
        if (upper[d] == net and std.mem.indexOfScalar(u32, downs.items, d) == null) try downs.append(gpa, d);
    }
}

/// The link to keep among `ups` over `downs`, or null: a stack block's
/// (`stacked` picks adjacent members in either order; the finished drawing
/// certifies the caller's written top-to-bottom direction),
/// the first by rank; else none when either side is a pair (its tail
/// stands alone), else the best free device on each side.
fn choose(nl: *const Netlist, st: *const Structure, upper: []const u32, lower: []const u32, roles: []const Role, chain: *const Chain, stacked: []const u32, ups: []const u32, downs: []const u32) ?struct { u32, u32 } {
    if (ups.len == 0 or downs.len == 0) return null;
    const rank = st.device_rank;
    var block: ?struct { u32, u32 } = null;
    for (ups) |u| for (downs) |l| {
        if (u == l or chain.below[u] != none or chain.above[l] != none) continue;
        if (stacked[u] != l and stacked[l] != u) continue;
        const bu, const bl = block orelse .{ u, l };
        if (block == null or rank[u] < rank[bu] or (u == bu and rank[l] < rank[bl])) block = .{ u, l };
    };
    if (block) |b| return b;
    if (isPair(st, ups) or isPair(st, downs)) return null;
    const kinds = nl.graph.edges.items(.kind);
    // Whom a device shares its column with where it meets several, in 5,263
    // hand-drawn schematics: below, a transistor of its own type (278 of
    // 291 nets whose candidates differ on it); on either side a transistor
    // before a part (369 of 401), and a part direct current passes before
    // a capacitor (749 of 778; 612 of 1,423 here while a load capacitor's
    // way to ground and its name won it the link). One whose column reaches
    // a rail is the engine's tie-break (people: 261 of 465), then rank.
    var u: u32 = none;
    var u_score: i64 = std.math.minInt(i64);
    for (ups) |d| {
        if (chain.below[d] != none) continue;
        const s = flows(kinds[d]) * 2 + @intFromBool(reachesRail(roles, upper, lower, chain, d, .up));
        const score = s * 1_000_000 - st.device_rank[d];
        if (score > u_score) {
            u_score = score;
            u = d;
        }
    }
    if (u == none) return null;
    const pol_u = symmetry.polarity(nl.modelType(EdgeId.from(u)));
    var l: u32 = none;
    var l_score: i64 = std.math.minInt(i64);
    for (downs) |d| {
        if (chain.above[d] != none or d == u) continue;
        const same = isTransistor(kinds[d]) and symmetry.polarity(nl.modelType(EdgeId.from(d))) == pol_u;
        const s = @as(i64, @intFromBool(same)) * 8 + flows(kinds[d]) * 2 + @intFromBool(reachesRail(roles, upper, lower, chain, d, .down));
        const score = s * 1_000_000 - st.device_rank[d];
        if (score > l_score) {
            l_score = score;
            l = d;
        }
    }
    if (l == none) return null;
    assert(u != l);
    assert(chain.below[u] == none and chain.above[l] == none);
    return .{ u, l };
}

/// Exactly two devices that are a differential or cross-coupled pair, or
/// each other's mates.
fn isPair(st: *const Structure, ds: []const u32) bool {
    if (ds.len != 2) return false;
    if (st.device_mate[ds[0]] == ds[1]) return true;
    return blockPartner(st, ds[0]) == ds[1];
}

/// How well a device of `kind` continues a column, the chain direct current
/// flows down: a transistor (2), a part direct current passes (1), a
/// capacitor (0).
fn flows(kind: netlist.DeviceKind) i64 {
    return @as(i64, @intFromBool(isTransistor(kind))) + @intFromBool(device.of(kind).dc);
}

/// Whether following `d`'s end up (or down) through single devices reaches
/// a rail.
fn reachesRail(roles: []const Role, upper: []const u32, lower: []const u32, chain: *const Chain, d0: u32, dir: enum { up, down }) bool {
    var d = d0;
    var steps: usize = 0;
    while (steps <= upper.len) : (steps += 1) {
        const net = if (dir == .up) upper[d] else lower[d];
        if (isRail(roles[net])) return true;
        const next = if (dir == .up) chain.above[d] else chain.below[d];
        if (next == none) return false;
        d = next;
    }
    return false;
}

/// Every transistor's gate faces the rest of its gate net; where that is a
/// rail or holds nothing else, left, or away from its mate (`mate`, as
/// `mates.find` gives it); then a differential pair's face out and the two
/// of a mirror, bank or cross-coupled pair face each other.
fn gates(nl: *const Netlist, roles: []const Role, st: *const Structure, mate: []const u32, drawn: []const bool, form: []const Form, x: []const i32, gate_right: []bool) void {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    assert(gate_right.len == c.edgeCount());
    assert(mate.len == c.edgeCount());
    for (0..c.edgeCount()) |d| {
        if (!drawn[d] or form[d] != .vertical) continue;
        const gate = c.members(EdgeId.from(d))[device.of(kinds[d]).gate orelse continue];
        var sum: i64 = 0;
        var count: i64 = 0;
        if (!isRail(roles[gate.index()])) for (c.incident(gate)) |e| {
            const v = e.index();
            if (v == d or !drawn[v]) continue;
            sum += x[v];
            count += 1;
        };
        // Twice the coordinates, so a middle between columns is exact.
        // With nothing in the drawing to face, a gate faces left, the side
        // its signal enters by (people: 2,684 of 3,317 such gates in 5,263
        // hand-drawn schematics; away from the drawing's middle, as here
        // before, 1,914 of 3,043); one with a mate elsewhere faces away
        // from it, the mirror image (283 of 367).
        const own: i64 = 2 * @as(i64, x[d]);
        gate_right[d] = if (count > 0) @divFloor(2 * sum, count) > own else mate[d] != none and x[d] > x[mate[d]];
    }
    // A block of two only: a larger mirror's or bank's gates face the rest
    // of their net as any gate does. People turn all of one left in 12 of
    // 1,103 mirrors of three or more and 88 of 380 banks (5,263 hand-drawn
    // schematics); in 567 of those mirrors every gate faces one point
    // inside the block.
    for (st.block_kind, 0..) |k, b| {
        const ms = st.members(b);
        if (k == .stack or ms.len != 2) continue;
        const a, const z = if (x[ms[0]] <= x[ms[1]]) .{ ms[0], ms[1] } else .{ ms[1], ms[0] };
        if (x[a] == x[z]) continue;
        if (k == .bank) if (bankDriver(nl, roles, mate, drawn, form, .{ a, z })) |driver| {
            if (x[driver] < x[a] or x[driver] > x[z]) {
                gate_right[a] = x[driver] > x[a];
                gate_right[z] = x[driver] > x[z];
                continue;
            }
        };
        gate_right[a] = k != .pair;
        gate_right[z] = k == .pair;
    }
    // A mate's gate is its image's (mates.1) where the symmetry traded a
    // MOS's ends (symmetry.8): it maps a block onto one of another kind.
    // Elsewhere the rules above stand (mirrored or not, as they were).
    const traded = for (st.device_mate, 0..) |m, d| {
        if (m == none or m == d or kinds[d] != .mosfet) continue;
        const p = c.members(EdgeId.from(d));
        const q = c.members(EdgeId.from(m));
        if (q[0] != q[2] and st.net_mate[p[0].index()] == q[2].index()) break true;
    } else false;
    if (traded) for (mate, 0..) |m, d| {
        if (m == none or m <= d or st.device_mate[d] != m or !drawn[d] or form[d] != .vertical) continue;
        gate_right[m] = !gate_right[d];
    };
}

/// One complete analog output on the bank's shared gate, with no other
/// incident device except capacitor loads. Each member must touch this net
/// only at its gate, including optional body pins. The caller supplies two
/// distinct bank handles; all scans borrow existing CSR and placement rows.
fn bankDriver(nl: *const Netlist, roles: []const Role, mate: []const u32, drawn: []const bool, form: []const Form, pair: [2]u32) ?u32 {
    const c = &nl.graph;
    const kinds = c.edges.items(.kind);
    assert(pair[0] != pair[1]);
    assert(pair[0] < c.edgeCount() and pair[1] < c.edgeCount());
    for (pair) |d| if (!drawn[d] or form[d] != .vertical or kinds[d] != .mosfet or mate[d] != none) return null;
    const a = c.members(EdgeId.from(pair[0]));
    const z = c.members(EdgeId.from(pair[1]));
    const gate = a[1];
    if (gate != z[1] or isRail(roles[gate.index()])) return null;
    const polarity = device.polarity(nl.modelType(EdgeId.from(pair[0])));
    if (polarity == .other or polarity != device.polarity(nl.modelType(EdgeId.from(pair[1])))) return null;
    for (pair) |d| {
        const pins = c.members(EdgeId.from(d));
        if (pins[0] == pins[2]) return null;
        for (pins, 0..) |p, i| if (p == gate and i != 1) return null;
    }
    var driver: u32 = none;
    for (c.incident(gate)) |edge| {
        const d = edge.index();
        if (!drawn[d]) return null;
        if (d == pair[0] or d == pair[1] or kinds[d] == .capacitor) continue;
        if (driver != none) {
            if (driver != d) return null;
            continue;
        }
        const def = nl.defOf(edge) orelse return null;
        const pins = c.members(edge);
        if (pins.len != def.ports.len) return null;
        const output = block_symbols.analogOutput(def.name, def.ports) orelse return null;
        if (pins[output] != gate) return null;
        for (pins, 0..) |p, i| if (p == gate and i != output) return null;
        driver = d;
    }
    return if (driver == none) null else driver;
}

/// Two devices on one cell is a bug of the placement above.
fn expectDistinctCells(gpa: Allocator, drawn: []const bool, x: []const i32, y: []const i32) !void {
    var seen: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer seen.deinit(gpa);
    for (drawn, x, y) |dr, px, py| if (dr) {
        const gop = try seen.getOrPut(gpa, .{ px, py });
        assert(!gop.found_existing);
    };
}

/// Shifts every cell so the smallest x and y are 0; returns the shift.
fn normalize(drawn: []const bool, x: []i32, y: []i32) [2]i32 {
    var mx: i32 = std.math.maxInt(i32);
    var my: i32 = std.math.maxInt(i32);
    for (drawn, x, y) |dr, px, py| if (dr) {
        mx = @min(mx, px);
        my = @min(my, py);
    };
    if (mx == std.math.maxInt(i32)) return .{ 0, 0 };
    for (x, y) |*px, *py| {
        px.* -= mx;
        py.* -= my;
    }
    for (drawn, x, y) |dr, px, py| if (dr) {
        assert(px >= 0);
        assert(py >= 0);
    };
    return .{ mx, my };
}
