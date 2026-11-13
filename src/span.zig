//! What an order of the columns costs (issue #8, stage 3): the span of its
//! wired nets, and how far it runs against the signal's way. In: the
//! columns' context (`columns.Ctx`) and each column's x. Out: a cost,
//! lower the better; and whether the signal enters on the left.
//!
//! Human Rules:
//! - span.1 (unmeasured) Columns stand in the order that makes the wired
//!   nets narrowest: each from its leftmost column to its rightmost, plus
//!   the gap a flat two-pin device between two wired nets crosses. `span`
//! - span.2 (order: signal) A pin stands right of the device that drives
//!   its net, on every net but a rail: a gate after its driver, a load
//!   after its stage. Counted before any width, with a mirrored core or
//!   without. People: 5,614 of 7,584 gates in circuits with a core stand
//!   right of or level with the leftmost device driving their net, 1,863
//!   of 2,507 in circuits without (74% both), in 5,263 hand-drawn
//!   schematics: a tendency pin by pin (where the signal comes back round
//!   a loop one pin must stand left), a rule of the whole drawing
//!   (columns.13). `against`
//! - span.3 (order: signal) The columns that read an input stand, on
//!   average, no further right than those that drive an output; else the
//!   whole row is turned end for end. People: 893 of the 931 hand drawings
//!   with a named input and output that run either way run left to right.
//!   `flowsRight`
//! - span.4 (habit) In a circuit of parts the signal enters at its
//!   source, on the left. People: the part farther from the source stands
//!   right of the nearer in 90.1% of 1,676 pairs in 5,263 hand-drawn
//!   schematics. `flowsRight`
//! - span.5 (choice) With no output named, a circuit of parts ends at
//!   the middle of its columns: something must stand for the far end.
//!   `flowsRight`
//!
//! Contents:
//! - `pub fn span(ctx: Ctx, x: []const i32) !i64`
//! - `pub fn flowsRight(ctx: Ctx, x: []const i32) bool`
//! - `pub fn isChannelPin(ctx: Ctx, d: u32, pin: usize) bool`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const device = @import("device.zig");
const columns = @import("columns.zig");
const forms = @import("forms.zig");

const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Ctx = columns.Ctx;

const none: u32 = std.math.maxInt(u32);

/// What the columns `placed` so far cost at `x`: each pin `against` the
/// signal's way, counted as more than any width; then the total width of
/// the wired nets, each from its leftmost column to its rightmost, and of
/// the gaps the bridges cross.
pub fn span(ctx: Ctx, x: []const i32) !i64 {
    const c = &ctx.nl.graph;
    assert(x.len == ctx.cols.count());
    var total: i64 = against(ctx, x) << 32;
    for (0..c.vertexCount()) |n| {
        if (!ctx.wired[n]) continue;
        var lo: i32 = std.math.maxInt(i32);
        var hi: i32 = std.math.minInt(i32);
        for (c.incident(VertexId.from(n))) |e| {
            const k = ctx.column_of[e.index()];
            if (k == none or !ctx.placed[k]) continue;
            lo = @min(lo, x[k]);
            hi = @max(hi, x[k]);
        }
        if (lo <= hi) total += hi - lo;
    }
    // A bridge joins two nets: the gap between their columns is its wire.
    for (0..c.edgeCount()) |d| {
        const pins = c.members(EdgeId.from(d));
        if (ctx.column_of[d] != none or pins.len != 2) continue;
        if (!ctx.wired[pins[0].index()] or !ctx.wired[pins[1].index()]) continue;
        const a = extent(ctx, x, pins[0]) orelse continue;
        const b = extent(ctx, x, pins[1]) orelse continue;
        total += @max(0, a[0] - b[1], b[0] - a[1]);
    }
    return total;
}

/// Whether the signal passes the columns left to right: those with a pin
/// on an input stand, on average, no further right than those that drive
/// an output (a channel pin on it). True with no input or no output. In a
/// circuit of parts (no transistor, no block) a source's column is an
/// input's, and with no output named the columns' middle stands for it.
pub fn flowsRight(ctx: Ctx, x: []const i32) bool {
    assert(x.len == ctx.cols.count());
    const kinds = ctx.nl.graph.edges.items(.kind);
    // A circuit of parts has no stage to tell the signal's way: it enters
    // at its source, which people draw on the left (the part farther from
    // the source stands right of the nearer in 90.1% of 1,676 pairs in
    // 5,263 hand-drawn schematics).
    const parts_only = forms.isPartsOnly(ctx.nl);
    // Its sources, when it has any in a column, are where the signal
    // enters, whatever its nets are called.
    const sourced = parts_only and found: for (0..ctx.cols.count()) |k| {
        for (ctx.cols.of(k)) |d| if (device.of(kinds[d]).source == .independent) break :found true;
    } else false;
    var in: [2]i64 = .{ 0, 0 };
    var out: [2]i64 = .{ 0, 0 };
    var all: [2]i64 = .{ 0, 0 };
    for (0..ctx.cols.count()) |k| {
        var reads = false;
        var drives = false;
        for (ctx.cols.of(k)) |d| {
            reads = reads or (sourced and device.of(kinds[d]).source == .independent);
            for (ctx.nl.graph.members(EdgeId.from(d)), 0..) |net, pin| {
                reads = reads or (!sourced and ctx.roles[net.index()] == .input);
                drives = drives or (ctx.roles[net.index()] == .output and isChannelPin(ctx, d, pin));
            }
        }
        if (reads) in = .{ in[0] + x[k], in[1] + 1 };
        if (drives) out = .{ out[0] + x[k], out[1] + 1 };
        all = .{ all[0] + x[k], all[1] + 1 };
    }
    // With no output named, a circuit of parts ends at its middle.
    if (parts_only and out[1] == 0) out = all;
    if (in[1] == 0 or out[1] == 0) return true;
    return in[0] * out[1] <= out[0] * in[1];
}

/// A pin current flows through (`device.carries`): a pin of a transistor's
/// path, a switch's or controlled source's first two, any pin of anything
/// else. A switch's control pins tie every switch on a clock. Asserts that
/// `d` has a pin `pin`.
pub fn isChannelPin(ctx: Ctx, d: u32, pin: usize) bool {
    assert(pin < ctx.nl.graph.members(EdgeId.from(d)).len);
    return device.carries(ctx.nl.graph.edges.items(.kind)[d], pin);
}

// ---- private ----

/// How many pins stand left of every device that drives their net, over
/// every net but a rail and the columns `placed` so far: a gate, a base or
/// a controlled source's input before its driver, a load before its stage.
/// The signal going right to left. A pin drives its net when it carries
/// current and its device reads a net (`device.reads`): what it drives
/// follows what it reads. A net nothing here drives (an input, a bias from
/// outside) counts nothing; one a bias generator drives counts as any.
fn against(ctx: Ctx, x: []const i32) i64 {
    const c = &ctx.nl.graph;
    assert(x.len == ctx.cols.count());
    var count: i64 = 0;
    for (0..c.vertexCount()) |n| {
        // Any net a device here drives, whatever its name: a bias generator
        // stands left of what it biases as a stage does of the next (people:
        // 74% of 10,091 gates, with a mirrored core or without).
        if (ctx.roles[n].isRail()) continue;
        var first: i32 = std.math.maxInt(i32);
        for ([_]bool{ true, false }) |drivers| for (c.incident(VertexId.from(n))) |e| {
            const d = e.index();
            const k = ctx.column_of[d];
            if (k == none or !ctx.placed[k]) continue;
            const kind = c.edges.items(.kind)[d];
            const reads = device.reads(kind);
            for (c.members(e), 0..) |net, pin| {
                if (net.index() != n or (reads and device.carries(kind, pin)) != drivers) continue;
                if (drivers) first = @min(first, x[k]) else count += @intFromBool(x[k] < first and first != std.math.maxInt(i32));
            }
        };
    }
    assert(count >= 0);
    return count;
}

/// The leftmost and rightmost column placed so far with a device on `n`.
fn extent(ctx: Ctx, x: []const i32, n: VertexId) ?[2]i32 {
    var lo: i32 = std.math.maxInt(i32);
    var hi: i32 = std.math.minInt(i32);
    for (ctx.nl.graph.incident(n)) |e| {
        const k = ctx.column_of[e.index()];
        if (k == none or !ctx.placed[k]) continue;
        lo = @min(lo, x[k]);
        hi = @max(hi, x[k]);
    }
    return if (lo <= hi) .{ lo, hi } else null;
}
