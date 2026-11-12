//! What an order of the columns costs (issue #8, stage 3): the span of its
//! wired nets, and how far it runs against the signal's way. In: the
//! columns' context (`columns.Ctx`) and each column's x. Out: a cost,
//! lower the better; and whether the signal enters on the left.
//!
//! A wired net spans from its leftmost column to its rightmost, and a
//! bridge between two wired nets adds the gap between their columns. With
//! `flow` an order is judged first by the pins that stand left of the
//! device that drives their net (`against`), then by span.
//!
//! Contents:
//! - `pub fn span(ctx: Ctx, x: []const i32) !i64`
//! - `pub fn flowsRight(ctx: Ctx, x: []const i32) bool`
//! - `pub fn isChannelPin(ctx: Ctx, d: u32, pin: usize) bool`

const std = @import("std");
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const columns = @import("columns.zig");

const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;
const Ctx = columns.Ctx;

const none: u32 = std.math.maxInt(u32);

/// The total width of the wired nets, each from its leftmost column to its
/// rightmost, and of the gaps the bridges cross, over the columns `placed`
/// so far; with `ctx.flow`, each pin
/// `against` the signal's way first, counted as more than any span.
pub fn span(ctx: Ctx, x: []const i32) !i64 {
    const c = &ctx.nl.graph;
    assert(x.len == ctx.cols.count());
    var total: i64 = if (ctx.flow) against(ctx, x) << 32 else 0;
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
    const parts_only = for (kinds) |kind| switch (kind) {
        .mosfet, .bjt, .jfet, .mesfet, .subckt => break false,
        else => {},
    } else true;
    // Its sources, when it has any in a column, are where the signal
    // enters, whatever its nets are called.
    const sourced = parts_only and found: for (0..ctx.cols.count()) |k| {
        for (ctx.cols.of(k)) |d| if (kinds[d] == .vsource or kinds[d] == .isource) break :found true;
    } else false;
    var in: [2]i64 = .{ 0, 0 };
    var out: [2]i64 = .{ 0, 0 };
    var all: [2]i64 = .{ 0, 0 };
    for (0..ctx.cols.count()) |k| {
        var reads = false;
        var drives = false;
        for (ctx.cols.of(k)) |d| {
            reads = reads or (sourced and (kinds[d] == .vsource or kinds[d] == .isource));
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

/// A pin current flows through: a transistor's drain and source (collector
/// and emitter), a switch's or controlled source's first two, any pin of
/// anything else. A switch's control pins tie every switch on a clock.
pub fn isChannelPin(ctx: Ctx, d: u32, pin: usize) bool {
    assert(pin < ctx.nl.graph.members(EdgeId.from(d)).len);
    return switch (ctx.nl.graph.edges.items(.kind)[d]) {
        .mosfet, .bjt, .jfet, .mesfet => pin == 0 or pin == 2,
        .vswitch, .cswitch, .vcvs, .vccs => pin < 2,
        else => true,
    };
}

// ---- private ----

/// How many pins stand left of every device that drives their net (a
/// transistor's or controlled source's channel pin on it), over the wired
/// nets and the columns `placed` so far: a gate, a base or a controlled
/// source's input before its driver, a load before its stage. The signal
/// going right to left.
fn against(ctx: Ctx, x: []const i32) i64 {
    const c = &ctx.nl.graph;
    assert(x.len == ctx.cols.count());
    var count: i64 = 0;
    for (0..c.vertexCount()) |n| {
        if (!ctx.wired[n]) continue;
        var first: i32 = std.math.maxInt(i32);
        for ([_]bool{ true, false }) |drivers| for (c.incident(VertexId.from(n))) |e| {
            const d = e.index();
            const k = ctx.column_of[d];
            if (k == none or !ctx.placed[k]) continue;
            const is_controlled = controlled(c.edges.items(.kind)[d]);
            for (c.members(e), 0..) |net, pin| {
                if (net.index() != n or (is_controlled and isChannelPin(ctx, d, pin)) != drivers) continue;
                if (drivers) first = @min(first, x[k]) else count += @intFromBool(x[k] < first and first != std.math.maxInt(i32));
            }
        };
    }
    assert(count >= 0);
    return count;
}

/// A device with a control pin: what it drives follows what it reads.
fn controlled(kind: netlist.DeviceKind) bool {
    return switch (kind) {
        .mosfet, .bjt, .jfet, .mesfet, .vswitch, .cswitch, .vcvs, .vccs => true,
        else => false,
    };
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
