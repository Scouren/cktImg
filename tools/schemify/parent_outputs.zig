//! Maps source-certified MOS parent outputs through one Schemify cell's actual emitted names.
//!
//! Contents:
//! - `pub const Bound`
//! - `pub fn forCell(gpa: Allocator, a: Allocator, source: []const u8, deck: *const spice.Deck, rec: *const recognize.Recognized, c: u32, names: []const []const u8, actual: *const np.netlist.Netlist) Allocator.Error!Bound`
const std = @import("std");
const np = @import("NetlistParser");
const spice = @import("spice.zig");
const recognize = @import("recognize.zig");
const names_ = @import("names.zig");
const Allocator = std.mem.Allocator;

/// Qualified owner identities mapped to the actual generated graph.
pub const Bound = struct { pairs: []const np.parent_outputs.Pair = &.{}, stages: []const np.parent_stages.Stage = &.{} };

/// The first target scope is one original subcircuit with complete, recognized
/// four-pin MOS devices. Both original and emitted graphs are checked against
/// every selected Deck device and each of its four ordered original net ids.
pub fn forCell(gpa: Allocator, a: Allocator, source: []const u8, deck: *const spice.Deck, rec: *const recognize.Recognized, c: u32, names: []const []const u8, actual: *const np.netlist.Netlist) Allocator.Error!Bound {
    if (source.len == 0 or c != 1 or deck.cells() != 2 or deck.devs(0).len() != 0) return .{};
    const range = deck.devs(c);
    if (range.len() < 5 or range.len() > 128 or actual.graph.edgeCount() != range.len()) return .{};
    for (range.lo..range.hi) |d| {
        const family = rec.syms.family.items[rec.parts.sym.items[d]];
        if ((family != .nmos and family != .pmos) or std.ascii.toLower(deck.dev_name[d][0]) != 'm' or deck.netsOf(@intCast(d)).len != 4) return .{};
    }
    var lines: std.ArrayList(u8) = .empty;
    try lines.appendSlice(a, "* selected MOS cell\n");
    for (range.lo..range.hi) |d| {
        try lines.appendSlice(a, deck.dev_name[d]);
        for (deck.netsOf(@intCast(d))) |n| try lines.print(a, " {s}", .{deck.netKey(c, n)});
        try lines.print(a, " {s}\n", .{deck.dev_rest[d]});
    }
    const has_header = std.ascii.startsWithIgnoreCase(std.mem.trimStart(u8, source, " \t\r\n"), ".subckt");
    const first = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
    const declarations = if (has_header) source else source[@min(first + 1, source.len)..];
    var original = np.netlist.parse(gpa, &.{ lines.items, declarations }, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{},
    };
    defer original.deinit(gpa);
    const ctx = try np.parent_context.bind(a, source, &original, &np.parent_context.standard_rails);
    if (ctx.reasons.count() != 0 or original.graph.edgeCount() != actual.graph.edgeCount()) return .{};
    const parents = try np.local_parents.collect(a, ctx, .{});
    if (parents.disposition != .raw_multigroup_candidate) return .{};
    const rows = try np.parent_outputs.collect(a, ctx, parents);
    const stages = try np.parent_stages.collect(a, ctx, parents);
    if (rows.len == 0 and stages.len == 0) return .{};
    const devices = try a.alloc(u32, range.len());
    const nets = try a.alloc(u32, original.graph.vertexCount());
    @memset(nets, std.math.maxInt(u32));
    const seen = try a.alloc(bool, actual.graph.edgeCount());
    @memset(seen, false);
    const emitted = try names_.deviceNames(a, deck, rec, c);
    for (range.lo..range.hi, emitted) |d, name| {
        const origin = original.device(try std.ascii.allocLowerString(a, deck.dev_name[d])) orelse return .{};
        const target = actual.device(name) orelse return .{};
        if (seen[target.index()]) return .{};
        seen[target.index()] = true;
        const ps = original.graph.members(origin);
        const qs = actual.graph.members(target);
        if (ps.len != 4 or qs.len != 4 or actual.graph.edges.items(.kind)[target.index()] != .mosfet) return .{};
        const pol = actual.modelType(target) orelse return .{};
        if (!std.mem.eql(u8, pol, if (ctx.kind[ps[3].index()] == .supply) "pmos" else "nmos")) return .{};
        devices[origin.index()] = target.index();
        for (ps, qs, deck.netsOf(@intCast(d))) |x, y, n| {
            if (!std.mem.eql(u8, original.graph.vertices.items(.name)[x.index()], deck.netKey(c, n)) or !std.mem.eql(u8, actual.graph.vertices.items(.name)[y.index()], names[n])) return .{};
            if (nets[x.index()] != std.math.maxInt(u32) and nets[x.index()] != y.index()) return .{};
            nets[x.index()] = y.index();
        }
    }
    const mapped = try a.alloc(np.parent_outputs.Pair, rows.len);
    for (rows, mapped) |pair, *dst| for (pair, dst) |o, *out| {
        out.* = .{ .net = nets[o.net], .pmos = devices[o.pmos], .nmos = devices[o.nmos], .gate = devices[o.gate] };
    };
    const target_stages = try a.alloc(np.parent_stages.Stage, stages.len);
    for (stages, target_stages) |stage, *dest| {
        dest.* = stage;
        for (stage.devices, &dest.devices) |d, *mapped_id| mapped_id.* = devices[d];
    }
    return .{ .pairs = mapped, .stages = target_stages };
}
