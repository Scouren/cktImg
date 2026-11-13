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
//! - wrap.5 (choice) No cut parts the devices a `row` or `order` line
//!   names together, and a deck with `cell` or strong `at` lines is not
//!   wrapped: those are places of the drawing as it stands (relaid from a
//!   `weak at` stay, a deck wraps as it did). `cut`
//! - wrap.6 (choice) Shelves stand `shelf_gap` (6) lattice rows apart, and
//!   a shelf's rows that only another shelf's columns filled are closed
//!   up: the shelves are read off the cells, so the engine's own decisions
//!   pasted back give the shelves they came from. `shelves`
//! - wrap.7 (habit, bounded) A certified converter's main PMOS–coil–PMOS
//!   path and its required grounded shunts and active gate drivers stay
//!   on one shelf. A cut must not undo their channel order or put the
//!   power path below its controls. Source: the 252 groups and 365/92
//!   shunt/driver relations in the power-path study. Unrelated bias
//!   columns may still wrap. Cell/at instructions and shelf-off retain
//!   their existing precedence. `cutCost`, `power_paths.controlBounds`
//!
//! Contents:
//! - `pub fn shelves(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, columns: u32, x: []i32, y: []i32, shelf: []u32, verdicts: []?hints.Verdict) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const hints = @import("hints.zig");
const power_paths = @import("power_paths.zig");

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
pub fn shelves(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, columns: u32, x: []i32, y: []i32, shelf: []u32, verdicts: []?hints.Verdict) Allocator.Error!void {
    const n = nl.graph.edgeCount();
    assert(drawn.len == n and form.len == n and mate.len == n);
    assert(x.len == n and y.len == n and shelf.len == n);
    try cut(gpa, nl, roles, drawn, form, mate, columns, x, y, verdicts);
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
fn cut(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, columns: u32, x: []i32, y: []i32, verdicts: []?hints.Verdict) Allocator.Error!void {
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
            const cost = cutCost(nl, roles, drawn, form, mate, x, col[first], col[j]) orelse continue;
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
/// cut would part a device from its mate, or two devices a `row` or `order`
/// line names together, or a certified power path from its required
/// controls (their existing row/order relation would no longer hold).
fn cutCost(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, x: []const i32, from: i32, at: i32) ?u32 {
    const c = &nl.graph;
    assert(from < at);
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
        if (lo < at and hi >= at) return null;
    }
    for (nl.hints) |h| {
        if (h.verb != .row and h.verb != .order) continue;
        var sides = [2]bool{ false, false };
        for (h.args) |name| {
            const d = (nl.device(name) orelse continue).index();
            if (drawn[d] and x[d] >= from) sides[@intFromBool(x[d] >= at)] = true;
        }
        if (sides[0] and sides[1]) return null;
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
