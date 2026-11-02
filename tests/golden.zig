//! The golden set (issue #8): figures from the owner's analog notes are the
//! oracle for how a drawing should look. Each deck in `golden/` is a netlist
//! whose device names match its figure's; its `*%` comment lines carry the
//! figure. `*% <device> <x> <y> <L|R|->` is the device's node in the figure
//! (cm, y up) and the side its gate or base faces; `*% labels <nets>` lists
//! the nets the figure draws as names instead of wires.
//!
//! A drawing is scored against its figure by relations that hold at any
//! scale: the left/right order of every pair of devices (up to a mirror of
//! the whole drawing) and their above/below order, the rows and columns pairs
//! share, the pairs the figure draws mirror-symmetric, gate sides, and the
//! nets drawn in pieces joined only by names. Supply and ground are symbols
//! in both, so they are never counted as labels.
//!
//! Contents:
//! - `pub const Deck = struct { name: []const u8, spice: []const u8 }`
//! - `pub const decks: [14]Deck`
//! - `pub const Ratio = struct { agree: u16, of: u16 }`
//! - `pub const Overlap = struct { both: u16, drawing_only: u16, figure_only: u16 }`
//! - `pub const Score = struct`
//! - `pub fn score(arena: Allocator, lib: *np.Library, spice: []const u8) !Score`
//! - `pub fn formatScore(arena: Allocator, name: []const u8, s: Score) ![]const u8`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const np = @import("NetlistParser");
const support = @import("support.zig");
const textbook = @import("textbook.zig");

pub const Deck = struct { name: []const u8, spice: []const u8 };

pub const decks = [_]Deck{
    deck("ota_5t"),
    deck("two_stage_pmos"),
    deck("fd_two_stage"),
    deck("telescopic_fd"),
    deck("folded_cascode"),
    deck("strongarm"),
    deck("gilbert"),
    deck("cmfb_two_stage"),
    deck("bandgap_ptat"),
    deck("cascode_mirror"),
    deck("wide_swing"),
    deck("beta_multiplier"),
    deck("diff_pair_resistive"),
    deck("telescopic_se"),
};

/// `agree` of `of` cases.
pub const Ratio = struct { agree: u16 = 0, of: u16 = 0 };

/// Device pairs a relation holds for: in both, only in the drawing, only in
/// the figure.
pub const Overlap = struct { both: u16 = 0, drawing_only: u16 = 0, figure_only: u16 = 0 };

/// A drawing against its figure. Pairs are unordered pairs of the figure's
/// devices.
pub const Score = struct {
    /// Pairs the figure orders left/right, and how many the drawing orders
    /// the same way: the drawing or its mirror image, whichever agrees more.
    x_order: Ratio = .{},
    /// Pairs the figure orders above/below, and how many the drawing does.
    y_order: Ratio = .{},
    rows: Overlap = .{},
    columns: Overlap = .{},
    /// The figure's mirror-symmetric pairs and the devices on its axis, and
    /// how many the drawing places mirror-symmetric about one axis.
    symmetric: Ratio = .{},
    /// Transistors, and how many have their gate on the figure's side
    /// (mirrored with the drawing).
    gates: Ratio = .{},
    /// Nets the drawing leaves in pieces joined only by names where the
    /// figure wires them, and the reverse. Sorted.
    extra_labels: []const []const u8 = &.{},
    missing_labels: []const []const u8 = &.{},
};

/// Positions this close (cm) share a row or column in a figure.
const figure_tol: f64 = 0.2;
/// The same in a drawing, in its integer units.
const drawing_tol: f64 = 2;

const Gate = enum { left, right, none };

const Figure = struct {
    /// Lowercase, as the netlist stores them.
    names: []const []const u8,
    x: []const f64,
    y: []const f64,
    gate: []const Gate,
    labels: []const []const u8,
};

/// Where the drawing put each figure device, index for index.
const Drawn = struct {
    device: []const usize,
    x: []const f64,
    /// Up, like a figure's.
    y: []const f64,
    gate: []const Gate,
};

const Shuffle = enum { reversed, rotated };

const Placement = struct { at: np.Pt, orient: np.library.Orient };

/// One line per golden deck, as `formatScore` writes it: today's drawing.
/// A change in either direction fails until the line is updated, so the
/// numbers in the tree are always the measured ones.
const recorded = [decks.len][]const u8{
    "ota_5t x 8/8 y 8/8 rows 1+0-1 cols 2+0-0 sym 2/3 gates 5/5 labels +[] -[]",
    "two_stage_pmos x 33/33 y 26/26 rows 4+0-6 cols 3+0-0 sym 3/3 gates 6/7 labels +[vbias] -[]",
    "fd_two_stage x 22/32 y 22/24 rows 8+2-4 cols 4+0-0 sym 2/5 gates 5/8 labels +[vb1,x,y] -[]",
    "telescopic_fd x 24/24 y 32/32 rows 4+0-0 cols 12+0-0 sym 4/5 gates 5/8 labels +[vb1,vb2,vb3] -[]",
    "folded_cascode x 29/43 y 40/50 rows 5+6-0 cols 6+1-6 sym 3/6 gates 6/10 labels +[x,y] -[]",
    "strongarm x 34/49 y 18/46 rows 4+24-5 cols 0+1-6 sym 0/6 gates 4/7 labels +[p,q,t,x,y] -[]",
    "gilbert x 19/36 y 8/29 rows 2+9-5 cols 0+1-0 sym 0/0 gates 3/6 labels +[a,b,t,x,y] -[inn,inp]",
    "cmfb_two_stage x 50/74 y 56/64 rows 3+7-11 cols 4+2-0 sym 0/7 gates 7/8 labels +[vout1,vout2,x,y] -[]",
    "bandgap_ptat x 18/29 y 27/29 rows 5+2-2 cols 7+0-0 sym 0/0 gates 6/6 labels +[g] -[]",
    "cascode_mirror x 6/6 y 8/8 rows 2+0-0 cols 4+0-0 sym 2/2 gates 4/4 labels +[] -[]",
    "wide_swing x 16/16 y 15/19 rows 1+4-1 cols 4+0-1 sym 0/0 gates 4/5 labels +[n] -[]",
    "beta_multiplier x 8/11 y 11/13 rows 2+2-0 cols 2+0-2 sym 1/2 gates 4/5 labels +[a,b] -[]",
    "diff_pair_resistive x 8/8 y 8/8 rows 2+0-0 cols 2+0-0 sym 3/3 gates 2/2 labels +[] -[]",
    "telescopic_se x 0/0 y 6/6 rows 0+0-0 cols 6+0-0 sym 0/0 gates 4/4 labels +[] -[]",
};

/// Decks whose drawing still changes with the order of their cards. Issue #8
/// empties this list; a deck that starts passing fails until it is removed.
const order_dependent = [_][]const u8{
    "current_mirror",
    "diff_pair_resistive",
    "ota_5t",
    "two_stage_opamp",
    "bandgap",
    "noninverting_amp",
    "telescopic_cascode",
    "sallen_key",
    "ring_oscillator",
    "golden/ota_5t",
    "golden/two_stage_pmos",
    "golden/fd_two_stage",
    "golden/telescopic_fd",
    "golden/folded_cascode",
    "golden/strongarm",
    "golden/gilbert",
    "golden/cmfb_two_stage",
    "golden/bandgap_ptat",
    "golden/cascode_mirror",
    "golden/wide_swing",
    "golden/beta_multiplier",
    "golden/diff_pair_resistive",
};

/// Lays `spice` out with the default settings and scores the drawing
/// against the figure in its `*%` lines. Everything lives in `arena`.
pub fn score(arena: Allocator, lib: *np.Library, spice: []const u8) !Score {
    const fig = try readFigure(arena, spice);
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    var s = try np.Schematic.build(arena, &nl, roles, lib);
    try np.layout(arena, &s, &.default);
    const p = try np.Placed.init(arena, &s, &nl);
    const drawn = try locate(arena, &p, fig.names);

    // The mirror image of the drawing may match the figure better: more
    // left/right orders, then more gates. The score is the same for a
    // mirrored figure.
    const as_is = relate(fig, drawn, 1);
    const mirrored = relate(fig, drawn, -1);
    const better = mirrored.x_order.agree > as_is.x_order.agree or
        (mirrored.x_order.agree == as_is.x_order.agree and mirrored.gates.agree > as_is.gates.agree);
    var out = if (better) mirrored else as_is;
    out.symmetric = try symmetric(arena, fig, drawn);
    const shown = try labelled(arena, &p, &nl, roles, drawn.device);
    out.extra_labels = try minus(arena, shown, fig.labels);
    out.missing_labels = try minus(arena, fig.labels, shown);
    return out;
}

/// One line: the deck's name and every count of its score. The tests record
/// these lines, and `gallery --score` prints them.
pub fn formatScore(arena: Allocator, name: []const u8, s: Score) ![]const u8 {
    return arena.print("{s} x {d}/{d} y {d}/{d} rows {d}+{d}-{d} cols {d}+{d}-{d} sym {d}/{d} gates {d}/{d} labels +[{s}] -[{s}]", .{
        name,
        s.x_order.agree,
        s.x_order.of,
        s.y_order.agree,
        s.y_order.of,
        s.rows.both,
        s.rows.drawing_only,
        s.rows.figure_only,
        s.columns.both,
        s.columns.drawing_only,
        s.columns.figure_only,
        s.symmetric.agree,
        s.symmetric.of,
        s.gates.agree,
        s.gates.of,
        try joined(arena, s.extra_labels),
        try joined(arena, s.missing_labels),
    });
}

// ---- private ----

fn deck(comptime name: []const u8) Deck {
    return .{ .name = name, .spice = @embedFile("golden/" ++ name ++ ".cir") };
}

fn readFigure(arena: Allocator, spice: []const u8) !Figure {
    var names: std.ArrayList([]const u8) = .empty;
    var xs: std.ArrayList(f64) = .empty;
    var ys: std.ArrayList(f64) = .empty;
    var gates: std.ArrayList(Gate) = .empty;
    var labels: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, spice, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "*%")) continue;
        var it = std.mem.tokenizeAny(u8, line[2..], " \t\r");
        const head = it.next() orelse continue;
        if (std.mem.eql(u8, head, "labels")) {
            while (it.next()) |net| try labels.append(arena, try std.ascii.allocLowerString(arena, net));
            continue;
        }
        try names.append(arena, try std.ascii.allocLowerString(arena, head));
        try xs.append(arena, try std.fmt.parseFloat(f64, it.next() orelse return error.BadFigureLine));
        try ys.append(arena, try std.fmt.parseFloat(f64, it.next() orelse return error.BadFigureLine));
        const side = it.next() orelse return error.BadFigureLine;
        try gates.append(arena, switch (side[0]) {
            'L' => .left,
            'R' => .right,
            '-' => .none,
            else => return error.BadFigureLine,
        });
    }
    std.mem.sort([]const u8, labels.items, {}, lessThan);
    return .{ .names = names.items, .x = xs.items, .y = ys.items, .gate = gates.items, .labels = labels.items };
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// A transistor's spot is its drain line and gate row, where a figure puts
/// its node; a two-pin device's is its middle; anything else's the mean of
/// its pins.
fn locate(arena: Allocator, p: *const np.Placed, names: []const []const u8) !Drawn {
    const device = try arena.alloc(usize, names.len);
    const xs = try arena.alloc(f64, names.len);
    const ys = try arena.alloc(f64, names.len);
    const gates = try arena.alloc(Gate, names.len);
    for (names, device, xs, ys, gates) |name, *d, *x, *y, *g| {
        d.* = for (p.dev_name, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) break i;
        } else {
            std.debug.print("golden: the figure's {s} is not in the drawing\n", .{name});
            return error.UnknownDevice;
        };
        const lo, const hi = p.pinRange(d.*);
        const pins = p.pin_xy[lo..hi];
        assert(pins.len >= 2);
        const f = struct {
            fn v(i: i32) f64 {
                return @floatFromInt(i);
            }
        }.v;
        switch (name[0]) {
            'm', 'q', 'j', 'z' => {
                x.* = f(pins[0].x);
                y.* = -f(pins[1].y);
                g.* = if (pins[1].x < pins[0].x) .left else .right;
            },
            'r', 'c', 'l', 'i', 'v', 'd', 's', 'w' => {
                x.* = (f(pins[0].x) + f(pins[1].x)) / 2;
                y.* = -(f(pins[0].y) + f(pins[1].y)) / 2;
                g.* = .none;
            },
            else => {
                var sx: f64 = 0;
                var sy: f64 = 0;
                for (pins) |q| {
                    sx += f(q.x);
                    sy += f(q.y);
                }
                x.* = sx / f(@intCast(pins.len));
                y.* = -sy / f(@intCast(pins.len));
                g.* = .none;
            },
        }
    }
    return .{ .device = device, .x = xs, .y = ys, .gate = gates };
}

/// Orders, rows, columns and gates, with the drawing's x scaled by `sign`.
fn relate(fig: Figure, at: Drawn, sign: f64) Score {
    var out: Score = .{};
    const n = fig.names.len;
    for (0..n) |i| for (i + 1..n) |j| {
        const fx = fig.x[j] - fig.x[i];
        const fy = fig.y[j] - fig.y[i];
        const dx = sign * (at.x[j] - at.x[i]);
        const dy = at.y[j] - at.y[i];
        order(&out.x_order, fx, dx);
        order(&out.y_order, fy, dy);
        overlap(&out.columns, @abs(fx) <= figure_tol, @abs(dx) <= drawing_tol);
        overlap(&out.rows, @abs(fy) <= figure_tol, @abs(dy) <= drawing_tol);
    };
    for (fig.gate, at.gate) |want, got| {
        if (want == .none) continue;
        out.gates.of += 1;
        const seen: Gate = if (sign > 0) got else switch (got) {
            .left => .right,
            .right => .left,
            .none => .none,
        };
        out.gates.agree += @intFromBool(seen == want);
    }
    return out;
}

fn order(r: *Ratio, figure_d: f64, drawing_d: f64) void {
    if (@abs(figure_d) <= figure_tol) return;
    r.of += 1;
    r.agree += @intFromBool(@abs(drawing_d) > drawing_tol and (drawing_d > 0) == (figure_d > 0));
}

fn overlap(o: *Overlap, in_figure: bool, in_drawing: bool) void {
    if (in_figure and in_drawing) {
        o.both += 1;
    } else if (in_drawing) {
        o.drawing_only += 1;
    } else if (in_figure) {
        o.figure_only += 1;
    }
}

/// The figure's mirror pairs: devices of one kind in one row with mirrored
/// gates (or none), about the axis most such pairs share, plus the devices
/// on that axis. A figure with fewer than two pairs is not symmetric. The
/// drawing's axis is the one most of them share there; each pair in one row
/// and each device on it counts.
fn symmetric(arena: Allocator, fig: Figure, at: Drawn) !Ratio {
    const n = fig.names.len;
    var pairs: std.ArrayList([2]usize) = .empty;
    var axes: std.ArrayList(f64) = .empty;
    for (0..n) |i| for (i + 1..n) |j| {
        const mirrored = (fig.gate[i] == .none and fig.gate[j] == .none) or
            (fig.gate[i] != .none and fig.gate[j] != .none and fig.gate[i] != fig.gate[j]);
        if (fig.names[i][0] != fig.names[j][0] or !mirrored) continue;
        if (@abs(fig.y[i] - fig.y[j]) > figure_tol or @abs(fig.x[i] - fig.x[j]) <= figure_tol) continue;
        try pairs.append(arena, .{ i, j });
        try axes.append(arena, (fig.x[i] + fig.x[j]) / 2);
    };
    const axis, const on_axis = mode(axes.items, figure_tol / 2);
    if (on_axis < 2) return .{};

    const used = try arena.alloc(bool, n);
    @memset(used, false);
    var sums: std.ArrayList(f64) = .empty;
    var level: std.ArrayList(bool) = .empty;
    for (pairs.items, axes.items) |pr, a| {
        if (@abs(a - axis) > figure_tol / 2 or used[pr[0]] or used[pr[1]]) continue;
        used[pr[0]] = true;
        used[pr[1]] = true;
        try sums.append(arena, at.x[pr[0]] + at.x[pr[1]]);
        try level.append(arena, @abs(at.y[pr[0]] - at.y[pr[1]]) <= drawing_tol);
    }
    for (0..n) |i| {
        if (used[i] or @abs(fig.x[i] - axis) > figure_tol / 2) continue;
        try sums.append(arena, 2 * at.x[i]);
        try level.append(arena, true);
    }
    const drawn_axis, _ = mode(sums.items, drawing_tol);
    var r: Ratio = .{ .of = @intCast(sums.items.len) };
    for (sums.items, level.items) |sum, same_row| r.agree += @intFromBool(same_row and @abs(sum - drawn_axis) <= drawing_tol);
    return r;
}

/// The value most others lie within `tol` of, and how many do (the first
/// such value on a tie).
fn mode(values: []const f64, tol: f64) struct { f64, usize } {
    var best: f64 = 0;
    var best_n: usize = 0;
    for (values) |a| {
        var k: usize = 0;
        for (values) |b| k += @intFromBool(@abs(a - b) <= tol);
        if (k > best_n) {
            best = a;
            best_n = k;
        }
    }
    return .{ best, best_n };
}

/// Nets whose pins on the figure's devices the drawing leaves in two or
/// more pieces, supply and ground aside: wires join a piece where a pin or
/// a wire's end lies on a wire. Sorted.
fn labelled(arena: Allocator, p: *const np.Placed, nl: *const np.netlist.Netlist, roles: []const np.schematic.Role, devices: []const usize) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (0..p.netCount()) |n| {
        const name = p.net_name[n];
        const id = nl.net(name) orelse continue;
        const role = roles[id.index()];
        if (role == .supply or role == .sink) continue;
        var pts: std.ArrayList(np.Pt) = .empty;
        for (devices) |d| {
            const lo, const hi = p.pinRange(d);
            for (lo..hi) |k| if (p.pin_net[k] == n) try pts.append(arena, p.pin_xy[k]);
        }
        const pins = pts.items.len;
        if (pins < 2) continue;
        var spans: std.ArrayList([2]usize) = .empty;
        var it = p.segments(n);
        while (it.next()) |poly| {
            for (poly, 0..) |q, k| {
                try pts.append(arena, q);
                if (k > 0) try spans.append(arena, .{ pts.items.len - 2, pts.items.len - 1 });
            }
        }
        const root = try arena.alloc(usize, pts.items.len);
        for (root, 0..) |*r, i| r.* = i;
        for (spans.items) |sp| {
            join(root, sp[0], sp[1]);
            const box = np.Rect.fromCorners(pts.items[sp[0]], pts.items[sp[1]]);
            for (pts.items, 0..) |q, i| if (box.contains(q)) join(root, i, sp[0]);
        }
        for (0..pins) |i| for (i + 1..pins) |j| {
            if (std.meta.eql(pts.items[i], pts.items[j])) join(root, i, j);
        };
        const first = find(root, 0);
        const pieces = for (1..pins) |i| {
            if (find(root, i) != first) break true;
        } else false;
        if (pieces) try out.append(arena, name);
    }
    std.mem.sort([]const u8, out.items, {}, lessThan);
    return out.items;
}

fn find(root: []usize, i: usize) usize {
    var x = i;
    while (root[x] != x) x = root[x];
    return x;
}

fn join(root: []usize, a: usize, b: usize) void {
    root[find(root, a)] = find(root, b);
}

/// The names in `a` (sorted) that are not in `b` (sorted).
fn minus(arena: Allocator, a: []const []const u8, b: []const []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (a) |x| {
        for (b) |y| {
            if (std.mem.eql(u8, x, y)) break;
        } else try out.append(arena, x);
    }
    return out.items;
}

fn joined(arena: Allocator, names: []const []const u8) ![]const u8 {
    return std.mem.join(arena, ",", names);
}

/// `spice` with its element cards reordered; title, dot cards and comments
/// first, in their order. A `+` line stays with its card.
fn shuffled(arena: Allocator, spice: []const u8, how: Shuffle) ![]const u8 {
    var rest: std.ArrayList(u8) = .empty;
    var cards: std.ArrayList(std.ArrayList(u8)) = .empty;
    var lines = std.mem.splitScalar(u8, spice, '\n');
    const title = lines.next() orelse return spice;
    try rest.appendSlice(arena, title);
    try rest.append(arena, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trimStart(u8, line, " \t");
        if (t.len > 0 and t[0] == '+' and cards.items.len > 0) {
            try cards.items[cards.items.len - 1].appendSlice(arena, line);
            try cards.items[cards.items.len - 1].append(arena, '\n');
        } else if (t.len > 0 and std.ascii.isAlphabetic(t[0])) {
            var card: std.ArrayList(u8) = .empty;
            try card.appendSlice(arena, line);
            try card.append(arena, '\n');
            try cards.append(arena, card);
        } else {
            try rest.appendSlice(arena, line);
            try rest.append(arena, '\n');
        }
    }
    const items = cards.items;
    switch (how) {
        .reversed => std.mem.reverse(std.ArrayList(u8), items),
        .rotated => if (items.len > 1) std.mem.rotate(std.ArrayList(u8), items, 1),
    }
    for (items) |card| try rest.appendSlice(arena, card.items);
    return rest.items;
}

/// Each named device that is not a source (a driver stands apart, in card
/// order), at its place and orientation.
fn placements(arena: Allocator, lib: *np.Library, spice: []const u8) !std.StringHashMapUnmanaged(Placement) {
    const p = try np.place(arena, &.default, lib, &.{spice}, null);
    var out: std.StringHashMapUnmanaged(Placement) = .empty;
    for (p.dev_name, p.dev_pos, p.dev_orient) |name, at, o| {
        if (name.len == 0 or name[0] == 'v') continue;
        try out.put(arena, name, .{ .at = at, .orient = o });
    }
    return out;
}

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

/// A deck with its figure's x mirrored and its gate sides swapped.
fn mirroredFigure(arena: Allocator, spice: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, spice, '\n');
    while (lines.next()) |line| {
        var it = std.mem.tokenizeAny(u8, line, " \t\r");
        const lead = it.next() orelse "";
        const name = it.next() orelse "";
        if (!std.mem.eql(u8, lead, "*%") or std.mem.eql(u8, name, "labels")) {
            try out.appendSlice(arena, line);
        } else {
            const x = try std.fmt.parseFloat(f64, it.next().?);
            const y = it.next().?;
            const side = it.next().?;
            const swapped: []const u8 = if (side[0] == 'L') "R" else if (side[0] == 'R') "L" else side;
            try out.print(arena, "*% {s} {d} {s} {s}", .{ name, -x, y, swapped });
        }
        try out.append(arena, '\n');
    }
    return out.items;
}

test "golden: every figure scores what is recorded" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var changed: usize = 0;
    for (decks, recorded) |d, want| {
        const got = try formatScore(arena, d.name, try score(arena, lib, d.spice));
        if (std.mem.eql(u8, got, want)) continue;
        changed += 1;
        std.debug.print("golden {s}:\n  recorded \"{s}\"\n  now      \"{s}\",\n", .{ d.name, want, got });
    }
    try std.testing.expectEqual(0, changed);
}

test "golden: the score sees a device the figure moves, and not a mirrored figure" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const spice = decks[0].spice;
    const base = try score(arena, lib, spice);
    // The tail drawn above the loads: its four above/below relations flip.
    const moved = try std.mem.replaceOwned(u8, arena, spice, "*% M5 1.3 -1.2 L", "*% M5 1.3 5.2 L");
    const worse = try score(arena, lib, moved);
    try std.testing.expectEqual(base.y_order.agree - 4, worse.y_order.agree);
    // A mirror image of the figure is the same figure.
    const mirror = try score(arena, lib, try mirroredFigure(arena, spice));
    try std.testing.expectEqualDeep(base, mirror);
}

test "golden: the drawing does not depend on the order of the cards" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var all: std.ArrayList(Deck) = .empty;
    for (textbook.all ++ textbook.beyond) |c| try all.append(arena, .{ .name = c.name, .spice = c.spice });
    for (decks) |d| try all.append(arena, .{ .name = try arena.print("golden/{s}", .{d.name}), .spice = d.spice });
    var dependent: std.ArrayList([]const u8) = .empty;
    for (all.items) |d| {
        const base = try placements(arena, lib, d.spice);
        const same = for ([_]Shuffle{ .reversed, .rotated }) |how| {
            const other = try placements(arena, lib, try shuffled(arena, d.spice, how));
            if (other.count() != base.count()) break false;
            var it = base.iterator();
            const all_same = while (it.next()) |e| {
                const o = other.get(e.key_ptr.*) orelse break false;
                if (!std.meta.eql(o, e.value_ptr.*)) break false;
            } else true;
            if (!all_same) break false;
        } else true;
        if (!same) try dependent.append(arena, d.name);
    }
    var wrong: usize = 0;
    for (dependent.items) |name| if (!contains(&order_dependent, name)) {
        std.debug.print("card order changes the drawing of {s}\n", .{name});
        wrong += 1;
    };
    for (order_dependent) |name| if (!contains(dependent.items, name)) {
        std.debug.print("{s} no longer depends on card order: remove it from order_dependent\n", .{name});
        wrong += 1;
    };
    try std.testing.expectEqual(0, wrong);
}
