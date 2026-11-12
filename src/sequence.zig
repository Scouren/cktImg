//! The deck's `order` lines (steering rung 2): devices left to right. In:
//! the netlist, its structure, and the skeleton's tables as each stage
//! leaves them. Out: the column links that would break an order refused,
//! the columns reordered, bridges set between their neighbours (and on the
//! rows `row` lines give them), and a verdict per line.
//!
//! An order line's column devices give edges "left of", admitted strongest
//! first; a line that closes a cycle is dropped with its preferred conflict.
//! Devices one line names stand in different columns, so a link the engine
//! would make between them is not made. A line on mated devices also states
//! its mirror image (reversed), weighed after every line and kept where it
//! fits; the columns' order then drops the mates it no longer mirrors.
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

pub const Sequence = struct {
    /// `[a, b]`: column device a's column left of b's.
    left: []const [2]u32,
    /// Per bridge an order line places: its nearest column devices before
    /// and after it in the line (`none` at an end); `{none, none}` for the
    /// rest.
    between: []const [2]u32,
    /// Per bridge so placed: the line that placed it, or `none`.
    placed_by: []const u32,

    /// Whether linking `u` over `l` (with the columns `above` holds so far)
    /// puts two devices an order line separates in one column, or closes a
    /// cycle among the columns.
    pub fn refuses(s: *const Sequence, gpa: Allocator, above: []const u32, u: u32, l: u32) Allocator.Error!bool {
        if (s.left.len == 0) return false;
        const tu = top(above, u);
        const tl = top(above, l);
        var nodes: std.ArrayList(u32) = .empty;
        defer nodes.deinit(gpa);
        var edges: std.ArrayList([2]u32) = .empty;
        defer edges.deinit(gpa);
        for (s.left) |e| {
            var ca = top(above, e[0]);
            var cb = top(above, e[1]);
            if (ca == tl) ca = tu;
            if (cb == tl) cb = tu;
            if (ca == cb) return true;
            try edges.append(gpa, .{ ca, cb });
            for ([_]u32{ ca, cb }) |k| if (std.mem.indexOfScalar(u32, nodes.items, k) == null) try nodes.append(gpa, k);
        }
        return !try acyclic(gpa, nodes.items, edges.items);
    }
};

/// The admission test for order lines: their column devices' edges and
/// each line's devices pairwise distinct hold together, every device its
/// own column.
const Check = struct {
    gpa: Allocator,
    own: []const []const u32,
    form: []const Form,

    pub fn holds(ck: Check, lines: []const u32) Allocator.Error!bool {
        var edges: std.ArrayList([2]u32) = .empty;
        defer edges.deinit(ck.gpa);
        for (lines) |i| {
            // Bridges count too: one placed between two columns orders them.
            for (ck.own[i][0 .. ck.own[i].len - 1], ck.own[i][1..]) |a, b| try edges.append(ck.gpa, .{ a, b });
        }
        return devicesAcyclic(ck.gpa, std.math.maxInt(u32), edges.items);
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
        const bad: ?hints.Code = for (h.args) |name| {
            const d = (nl.device(name) orelse break .unknown_name).index();
            if (!drawn[d]) break .not_placeable;
            if (std.mem.indexOfScalar(u32, devs.items, d) != null) break .bad_args;
            try devs.append(arena, d);
        } else if (h.args.len < 2) .bad_args else null;
        if (bad) |code| {
            verdicts[i] = .{ .state = .rejected, .code = code };
            continue;
        }
        own[i] = devs.items;
    }
    const check: Check = .{ .gpa = gpa, .own = own, .form = form };
    var admitted: std.ArrayList(u32) = .empty;
    defer admitted.deinit(gpa);
    var left: std.ArrayList([2]u32) = .empty;
    const between = try arena.alloc([2]u32, n);
    @memset(between, .{ none, none });
    const placed_by = try arena.alloc(u32, n);
    @memset(placed_by, none);
    var images: std.ArrayList(struct { line: u32, devices: []const u32 }) = .empty;
    for (try hints.admitOrder(arena, nl.hints)) |i| {
        if (nl.hints[i].verb != .order or verdicts[i] != null) continue;
        try admitted.append(gpa, i);
        if (!try check.holds(admitted.items)) {
            _ = admitted.pop();
            verdicts[i] = try hints.conflict(gpa, arena, check, admitted.items, i, .cycle);
            continue;
        }
        verdicts[i] = .{ .state = .honoured, .code = .ok };
        const line = own[i];
        try columnEdges(arena, form, line, &left);
        try place(form, line, between, placed_by, i);
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
    // it goes.
    for (images.items) |image| {
        const before = left.items.len;
        try columnEdges(arena, form, image.devices, &left);
        if (!try devicesAcyclic(gpa, n, left.items)) {
            left.shrinkRetainingCapacity(before);
            continue;
        }
        try place(form, image.devices, between, placed_by, image.line);
    }
    assert(try devicesAcyclic(gpa, n, left.items));
    return .{ .left = left.items, .between = between, .placed_by = placed_by };
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
/// `order` line places strictly between its neighbours' x, on a free cell,
/// in canonical order (`by_rank`); a bridge with no free cell there stays,
/// its line relaxed.
pub fn bridges(gpa: Allocator, s: *const Sequence, bridge_row: []const u32, by_rank: []const u32, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void {
    const n = x.len;
    var taken: std.AutoHashMapUnmanaged([2]i32, void) = .empty;
    defer taken.deinit(gpa);
    for (0..n) |d| if (drawn[d]) try taken.put(gpa, .{ x[d], y[d] }, {});
    assert(by_rank.len == n);
    for (by_rank) |b| {
        if (!drawn[b] or form[b] == .vertical) continue;
        const r = bridge_row[b];
        const nb = s.between[b];
        if (r == none and nb[0] == none and nb[1] == none) continue;
        const want_y = if (r != none) y[r] else y[b];
        var lo: i32 = std.math.minInt(i32) / 2;
        var hi: i32 = std.math.maxInt(i32) / 2;
        if (nb[0] != none) lo = x[nb[0]] + 1;
        if (nb[1] != none) hi = x[nb[1]] - 1;
        const want_x = std.math.clamp(x[b], lo, @max(lo, hi));
        _ = taken.remove(.{ x[b], y[b] });
        // The free cell nearest the wanted one, within the bounds.
        const at: ?[2]i32 = for (0..@as(usize, @intCast(2 * n + 2))) |step| {
            const off: i32 = @intCast((step + 1) / 2);
            const cx = if (step % 2 == 0) want_x + off else want_x - off;
            if (cx < lo or cx > hi) continue;
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

/// The "left of" edges of a line's column devices, each to the next.
fn columnEdges(arena: Allocator, form: []const Form, line: []const u32, out: *std.ArrayList([2]u32)) !void {
    var prev: u32 = none;
    for (line) |d| {
        if (form[d] != .vertical) continue;
        if (prev != none) try out.append(arena, .{ prev, d });
        prev = d;
    }
}

/// Each bridge of `line` between its nearest column devices in it.
fn place(form: []const Form, line: []const u32, between: [][2]u32, placed_by: []u32, i: u32) !void {
    for (line, 0..) |b, k| {
        if (form[b] == .vertical) continue;
        var l: u32 = none;
        var r: u32 = none;
        var j = k;
        while (j > 0) {
            j -= 1;
            if (form[line[j]] == .vertical) {
                l = line[j];
                break;
            }
        }
        for (line[k + 1 ..]) |d| if (form[d] == .vertical) {
            r = d;
            break;
        };
        between[b] = .{ l, r };
        placed_by[b] = i;
    }
}

fn separated(s: *const Sequence, column_of: []const u32, a: u32, b: u32) bool {
    for (s.left) |e| {
        const ca = column_of[e[0]];
        const cb = column_of[e[1]];
        if ((ca == a and cb == b) or (ca == b and cb == a)) return true;
    }
    return false;
}

/// Whether `edges` over `nodes` have no cycle (Kahn).
fn acyclic(gpa: Allocator, nodes: []const u32, edges: []const [2]u32) !bool {
    const indeg = try gpa.alloc(u32, nodes.len);
    defer gpa.free(indeg);
    @memset(indeg, 0);
    for (edges) |e| indeg[std.mem.indexOfScalar(u32, nodes, e[1]).?] += 1;
    var queue: std.ArrayList(u32) = .empty;
    defer queue.deinit(gpa);
    for (indeg, 0..) |d, k| if (d == 0) try queue.append(gpa, @intCast(k));
    var done: usize = 0;
    while (queue.pop()) |k| {
        done += 1;
        for (edges) |e| if (e[0] == nodes[k]) {
            const t = std.mem.indexOfScalar(u32, nodes, e[1]).?;
            indeg[t] -= 1;
            if (indeg[t] == 0) try queue.append(gpa, @intCast(t));
        };
    }
    assert(done <= nodes.len);
    return done == nodes.len;
}

fn devicesAcyclic(gpa: Allocator, n: usize, edges: []const [2]u32) !bool {
    var nodes: std.ArrayList(u32) = .empty;
    defer nodes.deinit(gpa);
    for (edges) |e| for (e) |d| if (std.mem.indexOfScalar(u32, nodes.items, d) == null) try nodes.append(gpa, d);
    assert(nodes.items.len <= n);
    return acyclic(gpa, nodes.items, edges);
}
