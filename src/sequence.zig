//! The deck's `order` lines (steering rung 2): devices left to right. In:
//! the netlist, its structure, and the skeleton's tables as each stage
//! leaves them. Out: the column links that would break an order refused,
//! the columns reordered, bridges set between their neighbours (and on the
//! rows `row` lines give them), and a verdict per line.
//!
//! Human Rules:
//! - sequence.1 (invariant) The devices an `order` line names stand left to
//!   right in that order, each left of the next. `read`
//! - sequence.2 (choice) Of `order` lines that close a cycle, the strongest
//!   stand and the rest are dropped with their preferred conflict: the
//!   deck's own ranking of its lines. `read`
//! - sequence.3 (unmeasured) An `order` line on mated devices also holds
//!   for their mirror images, reversed, where every device it names has a
//!   mate of its form and the image closes no cycle with any line. `read`
//! - sequence.4 (invariant) Upright devices that a chain of "left of" pairs
//!   joins through bridges alone stand in that order: `order a b` and
//!   `order b c` with b a bridge put a's column left of c's. `read`
//! - sequence.5 (invariant) Two upright devices one line orders stand in
//!   different columns: the engine makes no link between them.
//!   `Sequence.refuses`
//! - sequence.6 (choice) The columns move as little as the lines allow: a
//!   stable order by present x, and columns that shared an x and that no
//!   line separates keep sharing it. `columns`
//! - sequence.7 (invariant) A bridge an `order` line names stands right of
//!   every device before it in a line and left of every one after it; with
//!   no free cell there it stays, its line relaxed. `bridges`
//! - sequence.8 (choice) A bridge a line places takes the free cell nearest
//!   its own (on the row a `row` line gives it), bridges a line puts first
//!   placed first, then in canonical order: moving as little as possible.
//!   `bridges`
//!
//! Contents:
//! - `pub const Sequence = struct`, `Sequence.refuses(s: *const Sequence, gpa: Allocator, above: []const u32, u: u32, l: u32) Allocator.Error!bool`
//! - `Check.holds(ck: Check, lines: []const u32) Allocator.Error!bool`: the admission test `hints.conflict` calls
//! - `pub fn read(gpa: Allocator, arena: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, verdicts: []?Verdict) Allocator.Error!Sequence`
//! - `pub fn columns(gpa: Allocator, s: *const Sequence, column_of: []const u32, col_x: []i32) Allocator.Error!void`
//! - `pub fn bridges(gpa: Allocator, s: *const Sequence, bridge_row: []const u32, by_rank: []const u32, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const structure = @import("structure.zig");
const hints = @import("hints.zig");
const skeleton = @import("skeleton.zig");

const Netlist = netlist.Netlist;
const Structure = structure.Structure;
const Form = skeleton.Form;
const Verdict = hints.Verdict;
const none = structure.none;
const acyclic = hints.acyclic;

pub const Sequence = struct {
    /// `[a, b]`: column device a's column left of b's.
    left: []const [2]u32,
    /// `[a, b]`: device a left of b, each two neighbours of an admitted
    /// line and of its mirror image where that fits.
    pairs: []const [2]u32,
    /// Per bridge a line names: the line, or `none`.
    placed_by: []const u32,

    /// Whether linking `u` over `l` (with the columns `above` holds so far)
    /// puts two devices an order line separates in one column, or closes a
    /// cycle among the columns.
    pub fn refuses(s: *const Sequence, gpa: Allocator, above: []const u32, u: u32, l: u32) Allocator.Error!bool {
        if (s.left.len == 0) return false;
        const tu = top(above, u);
        const tl = top(above, l);
        var edges: std.ArrayList([2]u32) = .empty;
        defer edges.deinit(gpa);
        for (s.left) |e| {
            var ca = top(above, e[0]);
            var cb = top(above, e[1]);
            if (ca == tl) ca = tu;
            if (cb == tl) cb = tu;
            if (ca == cb) return true;
            try edges.append(gpa, .{ ca, cb });
        }
        return !try acyclic(gpa, above.len, edges.items);
    }
};

/// The admission test for order lines: their column devices' edges and
/// each line's devices pairwise distinct hold together, every device its
/// own column.
const Check = struct {
    gpa: Allocator,
    own: []const []const u32,

    pub fn holds(ck: Check, lines: []const u32) Allocator.Error!bool {
        var edges: std.ArrayList([2]u32) = .empty;
        defer edges.deinit(ck.gpa);
        // Bridges count too: one placed between two columns orders them.
        for (lines) |i| try neighbours(ck.gpa, ck.own[i], &edges);
        return acyclic(ck.gpa, std.math.maxInt(u32), edges.items);
    }
};

/// Admits the `order` lines: two or more drawn devices each, column devices
/// or bridges; bridges are placed by `bridges`.
pub fn read(gpa: Allocator, arena: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, verdicts: []?Verdict) Allocator.Error!Sequence {
    const n = nl.graph.edgeCount();
    // Per line, its devices in order.
    const own = try arena.alloc([]const u32, nl.hints.len);
    @memset(own, &.{});
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .order) continue;
        var devs: std.ArrayList(u32) = .empty;
        var at: u32 = hints.no_arg;
        const bad: ?hints.Code = for (h.args, 0..) |name, k| {
            at = @intCast(k);
            const d = (nl.device(name) orelse break .unknown_name).index();
            if (!drawn[d]) break .not_placeable;
            if (std.mem.indexOfScalar(u32, devs.items, d) != null) break .bad_args;
            try devs.append(arena, d);
        } else done: {
            at = hints.no_arg;
            break :done if (h.args.len < 2) .bad_args else null;
        };
        if (bad) |code| {
            verdicts[i] = .at(code, at);
            continue;
        }
        own[i] = devs.items;
    }
    const check: Check = .{ .gpa = gpa, .own = own };
    var admitted: std.ArrayList(u32) = .empty;
    defer admitted.deinit(gpa);
    // What states pairs: each admitted line, then each one's mirror image.
    const Stated = struct { line: u32, devices: []const u32 };
    var stated: std.ArrayList(Stated) = .empty;
    var images: std.ArrayList(Stated) = .empty;
    for (try hints.admitOrder(arena, nl.hints)) |i| {
        if (nl.hints[i].verb != .order or verdicts[i] != null) continue;
        try admitted.append(gpa, i);
        if (!try check.holds(admitted.items)) {
            _ = admitted.pop();
            verdicts[i] = try hints.conflict(gpa, arena, check, admitted.items, i, .cycle);
            continue;
        }
        verdicts[i] = .of(.ok);
        const line = own[i];
        try stated.append(arena, .{ .line = i, .devices = line });
        // The mirror image, reversed, where every device has a mate.
        const image = try arena.alloc(u32, line.len);
        const whole = for (line, 0..) |d, k| {
            const m = st.device_mate[d];
            if (m == none or !drawn[m] or form[m] != form[d]) break false;
            image[line.len - 1 - k] = m;
        } else true;
        if (!whole or std.mem.eql(u32, image, line)) continue;
        try images.append(arena, .{ .line = i, .devices = image });
    }
    // The images after every line, the strongest line's first: a line
    // admitted later stands, and the image that would close a cycle with
    // it goes (a line closes none: it was admitted). What stands names its
    // bridges.
    try stated.appendSlice(arena, images.items);
    var pairs: std.ArrayList([2]u32) = .empty;
    const placed_by = try arena.alloc(u32, n);
    @memset(placed_by, none);
    for (stated.items) |s| {
        const before = pairs.items.len;
        try neighbours(arena, s.devices, &pairs);
        if (!try acyclic(gpa, n, pairs.items)) {
            pairs.shrinkRetainingCapacity(before);
            continue;
        }
        for (s.devices) |d| if (form[d] != .vertical) {
            placed_by[d] = s.line;
        };
    }
    assert(try acyclic(gpa, n, pairs.items));
    const left = try columnEdges(gpa, arena, form, pairs.items);
    assert(try acyclic(gpa, n, left));
    return .{ .left = left, .pairs = pairs.items, .placed_by = placed_by };
}

/// Reorders the columns so every `left` edge holds, moving as little as it
/// can: a stable topological order by present x, positions two apart from
/// the leftmost (columns that shared an x and nothing separates keep
/// sharing it).
pub fn columns(gpa: Allocator, s: *const Sequence, column_of: []const u32, col_x: []i32) Allocator.Error!void {
    if (s.left.len == 0 or col_x.len == 0) return;
    const k = col_x.len;
    const indeg = try gpa.alloc(u32, k);
    defer gpa.free(indeg);
    @memset(indeg, 0);
    for (s.left) |e| indeg[column_of[e[1]]] += 1;
    const done = try gpa.alloc(bool, k);
    defer gpa.free(done);
    @memset(done, false);
    const old = try gpa.dupe(i32, col_x);
    defer gpa.free(old);
    var lo: i32 = std.math.maxInt(i32);
    for (old) |v| lo = @min(lo, v);
    var prev: u32 = none;
    for (0..k) |_| {
        // The leftmost column nothing still holds back.
        var pick: u32 = none;
        for (0..k) |c| {
            if (done[c] or indeg[c] > 0) continue;
            if (pick == none or old[c] < old[pick]) pick = @intCast(c);
        }
        assert(pick != none); // the links kept the columns acyclic
        done[pick] = true;
        for (s.left) |e| if (column_of[e[0]] == pick) {
            indeg[column_of[e[1]]] -= 1;
        };
        const share = prev != none and old[prev] == old[pick] and !separated(s, column_of, prev, pick);
        col_x[pick] = if (prev == none) lo else if (share) col_x[prev] else col_x[prev] + 2;
        prev = pick;
    }
    for (s.left) |e| assert(col_x[column_of[e[0]]] < col_x[column_of[e[1]]]);
}

/// Sets each bridge a `row` line names on its row, and each bridge an
/// `order` line names right of every device before it in a line and left
/// of every one after, on the free cell nearest its own, the bridges a
/// line puts first placed first, then in canonical order (`by_rank`); a
/// bridge with no free cell there stays, its line relaxed.
pub fn bridges(gpa: Allocator, s: *const Sequence, bridge_row: []const u32, by_rank: []const u32, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void {
    const n = x.len;
    var taken: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer taken.deinit(gpa);
    for (0..n) |d| if (drawn[d]) try taken.put(gpa, .{ x[d], y[d] }, {});
    assert(by_rank.len == n);
    // The last cell each device may take: a column device's own, a bridge's
    // one left of whatever a line puts after it; and how many bridges a
    // line puts before it in a row.
    const hi = try gpa.alloc(i32, n);
    defer gpa.free(hi);
    for (hi, form, x) |*h, f, cx| h.* = if (f == .vertical) cx else std.math.maxInt(i32) / 2;
    const depth = try gpa.alloc(u32, n);
    defer gpa.free(depth);
    @memset(depth, 0);
    for (0..n + 1) |round| {
        var changed = false;
        for (s.pairs) |e| {
            if (form[e[0]] == .vertical) continue;
            if (hi[e[1]] - 1 < hi[e[0]]) {
                hi[e[0]] = hi[e[1]] - 1;
                changed = true;
            }
            if (form[e[1]] != .vertical and depth[e[1]] <= depth[e[0]]) {
                depth[e[1]] = depth[e[0]] + 1;
                changed = true;
            }
        }
        if (!changed) break;
        assert(round < n); // the pairs have no cycle
    }
    const order = try gpa.dupe(u32, by_rank);
    defer gpa.free(order);
    std.sort.insertion(u32, order, depth, struct {
        fn lt(dep: []const u32, a: u32, b: u32) bool {
            return dep[a] < dep[b];
        }
    }.lt);
    for (order) |b| {
        if (!drawn[b] or form[b] == .vertical) continue;
        const r = bridge_row[b];
        var lo: i32 = std.math.minInt(i32) / 2;
        var named = false;
        for (s.pairs) |e| {
            if (e[1] == b) lo = @max(lo, x[e[0]] + 1);
            named = named or e[0] == b or e[1] == b;
        }
        if (r == none and !named) continue;
        const want_y = if (r != none) y[r] else y[b];
        const want_x = std.math.clamp(x[b], lo, @max(lo, hi[b]));
        _ = taken.remove(.{ x[b], y[b] });
        // The free cell nearest the wanted one, within the bounds.
        const at: ?[2]i32 = for (0..@as(usize, @intCast(2 * n + 2))) |step| {
            const off: i32 = @intCast((step + 1) / 2);
            const cx = if (step % 2 == 0) want_x + off else want_x - off;
            if (cx < lo or cx > hi[b]) continue;
            if (!taken.contains(.{ cx, want_y })) break .{ cx, want_y };
        } else null;
        if (at) |a| {
            x[b] = a[0];
            y[b] = a[1];
        } else if (s.placed_by[b] != none) {
            verdicts[s.placed_by[b]] = .{ .state = .relaxed, .code = .no_room };
        }
        try taken.put(gpa, .{ x[b], y[b] }, {});
    }
}

// ---- private ----

fn top(above: []const u32, d0: u32) u32 {
    var d = d0;
    var steps: usize = 0;
    while (above[d] != none) : (steps += 1) {
        assert(steps < above.len);
        d = above[d];
    }
    return d;
}

/// Each two neighbours of `line` as a pair "left of".
fn neighbours(gpa: Allocator, line: []const u32, pairs: *std.ArrayList([2]u32)) !void {
    assert(line.len >= 2);
    for (line[0 .. line.len - 1], line[1..]) |a, b| try pairs.append(gpa, .{ a, b });
}

/// The "left of" edges among column devices: each to every column device
/// a path of `pairs` reaches from it through bridges alone.
fn columnEdges(gpa: Allocator, arena: Allocator, form: []const Form, pairs: []const [2]u32) ![]const [2]u32 {
    var out: std.ArrayList([2]u32) = .empty;
    var todo: std.ArrayList(u32) = .empty;
    defer todo.deinit(gpa);
    var seen: std.ArrayList(u32) = .empty;
    defer seen.deinit(gpa);
    for (pairs) |e| {
        if (form[e[0]] != .vertical) continue;
        seen.clearRetainingCapacity();
        try todo.append(gpa, e[1]);
        // Each device once a pair: at most `pairs.len + 1` of them.
        while (todo.pop()) |d| {
            if (std.mem.indexOfScalar(u32, seen.items, d) != null) continue;
            try seen.append(gpa, d);
            assert(seen.items.len <= pairs.len + 1);
            if (form[d] == .vertical) {
                try out.append(arena, .{ e[0], d });
                continue;
            }
            for (pairs) |f| if (f[0] == d) try todo.append(gpa, f[1]);
        }
    }
    return out.items;
}

fn separated(s: *const Sequence, column_of: []const u32, a: u32, b: u32) bool {
    for (s.left) |e| {
        const ca = column_of[e[0]];
        const cb = column_of[e[1]];
        if ((ca == a and cb == b) or (ca == b and cb == a)) return true;
    }
    return false;
}
