//! Shelves (issue #8, stage 3): a row of device columns too wide for a page
//! is wrapped into rows of columns, one under the other. In: each drawn
//! device's cell and mate. Out: the cells, wrapped, and each one's shelf.
//!
//! Human Rules:
//! - wrap.1 (habit) A row of more device columns than a page holds is cut
//!   into shelves of equal width, one under the other. People: their
//!   drawings of over 30 devices are 20 units wide at the median over 5,263
//!   hand-drawn schematics; one row of columns was 37. The page is the
//!   layout's (`config.Layout.shelf`, 8 columns, whose rule it is; 0 keeps
//!   one row); `*@ shelf <columns>` sets it for a deck, `*@ shelf off`
//!   keeps one row. `cut`
//! - wrap.2 (unmeasured) Each cut goes between the two columns the fewest
//!   nets but rails cross, within a third of a shelf of its equal-width
//!   place (ties: the nearer). `cutCost`
//! - wrap.3 (invariant) No cut parts a device from its mate: the mirrored
//!   core stays whole on one shelf and keeps its x. `cutCost`
//! - wrap.4 (unmeasured) Every shelf starts at the left edge of the core's
//!   shelf, or of the first shelf when there is no core. `cut`
//! - wrap.5 (choice) No cut parts an honoured `row`, `order` or `column` group,
//!   or puts an `above` line's upper device on a later shelf than its
//!   lower device. Left shelves precede right shelves, so an upper-left
//!   to lower-right pair may cross a cut. Rejected, dropped and unhandled
//!   instructions impose no cut restriction. Admission and bridge
//!   placement have already set these verdicts.
//!   A deck with `cell` or strong `at` lines is not wrapped: those are
//!   places of the drawing as it stands (relaid from a `weak at` stay,
//!   a deck wraps as it did). `cut`, `cutCost`
//! - wrap.6 (choice) Shelves stand `shelf_gap` (6) lattice rows apart, and
//!   a shelf's rows that only another shelf's columns filled are closed
//!   up: the shelves are read off the cells, so the engine's own decisions
//!   pasted back give the shelves they came from. A shelf containing a
//!   placed converter loop retains its reserved row gaps. `shelves`
//! - wrap.7 (habit, bounded) A certified converter's main PMOS–coil–PMOS
//!   path and its required grounded shunts and active gate drivers stay
//!   on one shelf. A cut must not undo their channel order or put the
//!   power path below its controls. Source: the 252 groups and 365/92
//!   shunt/driver relations in the power-path study. Unrelated bias
//!   columns may still wrap. Cell/at instructions and shelf-off retain
//!   their existing precedence. `cutCost`, `power_paths.controlBounds`
//! - wrap.8 (habit, bounded) Each unique upright outer reservoir stays on
//!   its main path's shelf. All 359 source capacitors stand beyond their
//!   main switch away from the coil; separate shelves can reverse that x
//!   order and put the capacitor above the path. Preserve existing cap
//!   columns and admitted rows/mates. `cutCost`, `power_paths.reservoir`
//! - wrap.9 (habit, bounded) A successfully placed flying-capacitor loop
//!   stays on one shelf. All 145 selected source groups keep its seven
//!   local nets continuous. The placement pass supplies only spans whose
//!   members accepted the group layout; caller-constrained groups do not
//!   acquire this protection. Preserve that shelf's existing row gaps:
//!   sparse cell rows cannot reveal the supply stubs and bars occupying
//!   reserved room beside the lower return. AG1222 and 16 other selected
//!   cases lose their local tree when these gaps close before routing.
//!   Keeping the whole shelf's gaps is a conservative placement choice;
//!   later compaction measures actual ink and symbol clearance.
//!   `loop_place.place`, `cut`, `cutCost`
//! - wrap.10 (habit, bounded) A placed private grounded-source/resistor
//!   branch stays with its chosen MOS gate on one shelf. All 22 selected
//!   source branches have continuous source legs and a straight approach
//!   to that gate. Its two-row source drop is reserved with the protected
//!   interval, using the same caller-owned span mechanism. `input_place`
//! - wrap.11 (habit, bounded) A unique center-tapped coil and its parallel
//!   tank capacitor share a shelf. Cold collection supplies cut-only spans;
//!   it does not preserve all empty rows. A custom class may decline the
//!   later relative placement while retaining semantic grouping. `coil_tanks`
//!
//! Contents:
//! - `pub fn shelves(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, columns: u32, x: []i32, y: []i32, shelf: []u32, verdicts: []?hints.Verdict, protected: []const [2]i32) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const hints = @import("hints.zig");
const power_paths = @import("power_paths.zig");
const coil_tanks = @import("coil_tanks.zig");
const ct_four_sides = @import("ct_four_sides.zig");

const Netlist = netlist.Netlist;
const VertexId = netlist.VertexId;
const Role = sch.Role;
const Form = skeleton.Form;

const none: u32 = std.math.maxInt(u32);

/// Lattice rows between one shelf's lowest cell and the next one's top:
/// two device rows left empty, which no one row of columns has, so rows
/// that far apart are two shelves wherever the cells come from.
const shelf_gap = 6;

/// Wraps the cells `x`, `y` of the drawn devices toward `columns` device
/// columns per shelf; protected groups may exceed that target (0: none;
/// or what a `*@ shelf` line says, its verdict into `verdicts`). Writes
/// each device's shelf to `shelf`:
/// the bands of rows `shelf_gap` apart, wrapped here or not. `mate` is
/// each device's mirror image, or `none`: a pair is never parted.
/// Relation verdicts must already contain their admission results;
/// honoured relation arguments must name drawn devices.
/// No cut crosses an inclusive x interval in `protected`; shelves holding
/// those intervals retain their existing row gaps.
pub fn shelves(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, columns: u32, x: []i32, y: []i32, shelf: []u32, verdicts: []?hints.Verdict, protected: []const [2]i32) Allocator.Error!void {
    const n = nl.graph.edgeCount();
    assert(drawn.len == n and form.len == n and mate.len == n);
    assert(x.len == n and y.len == n and shelf.len == n);
    try cut(gpa, nl, roles, drawn, form, mate, columns, x, y, verdicts, protected);
    // Shelves are read off the cells, so cells a deck's lines pin (the
    // engine's own decisions pasted back) give the shelves they came from.
    const rows = try gpa.alloc(i32, n);
    defer gpa.free(rows);
    var count: usize = 0;
    for (0..n) |d| if (drawn[d]) {
        rows[count] = y[d];
        count += 1;
    };
    std.sort.heap(i32, rows[0..count], {}, std.sort.asc(i32));
    for (0..n) |d| {
        shelf[d] = 0;
        if (!drawn[d]) continue;
        for (rows[0..count -| 1], rows[1..count]) |a, b| {
            if (b <= y[d] and b - a >= shelf_gap) shelf[d] += 1;
        }
    }
}

// ---- private ----

/// Cuts the row of columns and moves each shelf under the one before.
fn cut(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, columns: u32, x: []i32, y: []i32, verdicts: []?hints.Verdict, protected: []const [2]i32) Allocator.Error!void {
    const n = nl.graph.edgeCount();
    assert(verdicts.len == nl.hints.len);
    // The deck's `*@ shelf <columns|off>` lines, the preferred one last.
    var shelf_cols: usize = columns;
    const order = try hints.applyOrder(gpa, nl.hints);
    defer gpa.free(order);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .shelf) continue;
        const cols_asked: ?usize = if (h.args.len != 1) null else if (std.mem.eql(u8, h.args[0], "off")) 0 else std.fmt.parseInt(usize, h.args[0], 10) catch null;
        verdicts[i] = .of(if (cols_asked == null) .bad_args else .ok);
        shelf_cols = cols_asked orelse continue;
    }
    if (shelf_cols == 0) return;
    for (nl.hints) |h| switch (h.verb) {
        // Cells are the wrapped drawing's already.
        .cell => return,
        // A stay (`--from`) is a place of the wrapped drawing: relaid, the
        // deck wraps as it did.
        .at => if (!h.weak) return,
        else => {},
    };
    var xs: std.ArrayList(i32) = .empty;
    defer xs.deinit(gpa);
    for (0..n) |d| if (drawn[d] and form[d] == .vertical) try xs.append(gpa, x[d]);
    std.sort.heap(i32, xs.items, {}, std.sort.asc(i32));
    var cols: usize = 0;
    for (xs.items) |v| if (cols == 0 or xs.items[cols - 1] != v) {
        xs.items[cols] = v;
        cols += 1;
    };
    if (cols <= shelf_cols) return;
    const col = xs.items[0..cols];
    var tanks = try coil_tanks.spans(gpa, nl, drawn, x, protected);
    defer tanks.deinit(gpa);
    const tank_spans = if (tanks.items.len == 0) protected else tanks.items;
    var stage = try ct_four_sides.spans(gpa, nl, roles, drawn, x, tank_spans);
    defer stage.deinit(gpa);
    const cut_spans = if (stage.items.len == 0) tank_spans else stage.items;

    // Each shelf's first column: shelves of equal width, each cut moved to
    // the cheapest gap within a third of a shelf of its place.
    // ponytail: a cut at a time; a dynamic program over all of them if
    // the shelves come out uneven.
    var starts: std.ArrayList(i32) = .empty;
    defer starts.deinit(gpa);
    try starts.append(gpa, col[0]);
    const count_max = @divCeil(cols, shelf_cols);
    const width = @divCeil(cols, count_max);
    var first: usize = 0;
    for (1..count_max) |k| {
        const ideal = k * width;
        const slack = @max(1, width / 3);
        var best: ?usize = null;
        var best_cost: u64 = std.math.maxInt(u64);
        for (@max(first + 1, ideal -| slack)..@min(cols, ideal + slack + 1)) |j| {
            const cost = cutCost(nl, roles, drawn, form, mate, x, verdicts, cut_spans, col[first], col[j]) orelse continue;
            // Fewest nets cut, then nearest its place.
            const key = (@as(u64, cost) << 32) | @abs(@as(i64, @intCast(j)) - @as(i64, @intCast(ideal)));
            if (key < best_cost) {
                best = j;
                best_cost = key;
            }
        }
        first = best orelse continue;
        try starts.append(gpa, col[first]);
    }
    if (starts.items.len == 1) return;
    const lift = try gpa.alloc(i32, n);
    defer gpa.free(lift);
    @memset(lift, 0);

    // A shelf holds a few of the row's columns, so some rows of the whole
    // are empty in it: closed up, or two of its rows `shelf_gap` apart would
    // read as two shelves. A gap keeps its parity (device rows even, the
    // channels between them odd).
    const count = starts.items.len;
    const rows = try gpa.alloc(i32, n);
    defer gpa.free(rows);
    for (0..count) |s| {
        const reserved = for (protected) |span| {
            if (shelfOf(starts.items, span[0]) == s) break true;
        } else false;
        if (reserved) continue;
        var held: usize = 0;
        for (0..n) |d| if (drawn[d] and shelfOf(starts.items, x[d]) == s) {
            rows[held] = y[d];
            held += 1;
        };
        std.sort.heap(i32, rows[0..held], {}, std.sort.asc(i32));
        // Per device, how far up it moves: the room closed above its row.
        for (0..n) |d| {
            if (!drawn[d] or shelfOf(starts.items, x[d]) != s) continue;
            var closed: i32 = 0;
            for (rows[0..held -| 1], rows[1..held]) |a, b| {
                if (b > y[d]) break;
                if (b - a > 2) closed += b - a - 2 + @mod(b - a, 2);
            }
            lift[d] = closed;
        }
    }
    for (0..n) |d| if (drawn[d]) {
        y[d] -= lift[d];
    };

    // Each shelf's top and bottom row, then its place under the one before.
    const top = try gpa.alloc(i32, count);
    defer gpa.free(top);
    const bottom = try gpa.alloc(i32, count);
    defer gpa.free(bottom);
    @memset(top, std.math.maxInt(i32));
    @memset(bottom, std.math.minInt(i32));
    for (0..n) |d| if (drawn[d]) {
        const s = shelfOf(starts.items, x[d]);
        top[s] = @min(top[s], y[d]);
        bottom[s] = @max(bottom[s], y[d]);
    };
    // The core's shelf keeps its x: mated devices mirror about one axis.
    var anchor: usize = 0;
    for (mate, 0..) |m, d| if (m != none and drawn[d]) {
        anchor = shelfOf(starts.items, x[d]);
    };
    var base: i32 = 0;
    const base_of = try gpa.alloc(i32, count);
    defer gpa.free(base_of);
    for (base_of, top, bottom) |*b, *t, lo| {
        assert(t.* <= lo);
        // Device rows stay even, the channels between them odd.
        t.* -= @mod(t.*, 2);
        b.* = base;
        base += lo - t.* + shelf_gap;
        base += @mod(base, 2);
    }
    for (0..n) |d| if (drawn[d]) {
        const s = shelfOf(starts.items, x[d]);
        x[d] += starts.items[anchor] - starts.items[s];
        y[d] += base_of[s] - top[s];
    };
}

/// The shelf a cell at `x` is in: the last one starting at or left of it.
fn shelfOf(starts: []const i32, x: i32) usize {
    assert(starts.len > 0);
    var s: usize = 0;
    for (starts[1..], 1..) |v, k| {
        if (x >= v) s = k;
    }
    return s;
}

/// How many nets but rails have a device on both sides of a cut before the
/// column at `at`, among the devices at or right of `from`; null where the
/// cut would reverse an honoured `above` pair or part a device from its
/// mate, an honoured `row`/`order` group, or a certified power path from its required
/// controls (their existing row/order relation would no longer hold).
fn cutCost(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, x: []const i32, verdicts: []const ?hints.Verdict, protected: []const [2]i32, from: i32, at: i32) ?u32 {
    const c = &nl.graph;
    assert(from < at);
    assert(verdicts.len == nl.hints.len);
    for (protected) |span| {
        assert(span[0] <= span[1]);
        if (span[0] < at and span[1] >= at) return null;
    }
    for (mate, 0..) |m, d| {
        if (m == none or !drawn[d] or !drawn[m]) continue;
        if ((x[d] < at) != (x[m] < at)) return null;
    }
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .inductor) continue;
        const group = power_paths.series(nl, roles, drawn, form, @intCast(d)) orelse continue;
        var lo = @min(x[group[0]], @min(x[group[1]], x[group[2]]));
        var hi = @max(x[group[0]], @max(x[group[1]], x[group[2]]));
        if (power_paths.controlBounds(nl, roles, drawn, form, group, x)) |bounds| {
            lo = @min(lo, bounds[0]);
            hi = @max(hi, bounds[1]);
        }
        for ([_]u32{ group[0], group[2] }, nl.path(netlist.EdgeId.from(group[1])).?) |main, inner| {
            const cap = power_paths.reservoir(nl, roles, drawn, form, main, inner) orelse continue;
            lo = @min(lo, x[cap]);
            hi = @max(hi, x[cap]);
        }
        if (lo < at and hi >= at) return null;
    }
    for (nl.hints, verdicts) |h, verdict| {
        if (h.verb != .row and h.verb != .order and h.verb != .above and h.verb != .column) continue;
        const v = verdict orelse continue;
        if (v.state != .honoured) continue;
        if (h.verb == .above) {
            assert(h.args.len >= 2);
            for (h.args[0 .. h.args.len - 1], h.args[1..]) |upper, lower| {
                const a = nl.device(upper).?.index();
                const b = nl.device(lower).?.index();
                assert(drawn[a] and drawn[b]);
                if (x[a] >= at and x[b] < at) return null;
            }
            continue;
        }
        var lo: i32 = std.math.maxInt(i32);
        var hi: i32 = std.math.minInt(i32);
        for (h.args) |name| {
            const d = nl.device(name).?.index();
            assert(drawn[d]);
            lo = @min(lo, x[d]);
            hi = @max(hi, x[d]);
        }
        if (lo < at and hi >= at) return null;
    }
    var cost: u32 = 0;
    for (roles, 0..) |r, net| {
        if (r.isRail()) continue;
        var left = false;
        var right = false;
        for (c.incident(VertexId.from(@intCast(net)))) |e| {
            const d = e.index();
            if (!drawn[d] or x[d] < from) continue;
            if (x[d] < at) left = true else right = true;
        }
        cost += @intFromBool(left and right);
    }
    return cost;
}
