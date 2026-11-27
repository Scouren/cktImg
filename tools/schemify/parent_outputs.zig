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
pub const Bound = struct { pairs: []const np.parent_outputs.Pair = &.{}, stages: []const np.parent_stages.Stage = &.{}, bridge: ?np.source_layout.Owner = null, crossover: ?np.crossover.Pair = null };

/// The first target scope is one original subcircuit with complete, recognized
/// four-pin MOS devices. Both original and emitted graphs are checked against
/// every selected Deck device and each of its four ordered original net ids.
pub fn forCell(gpa: Allocator, a: Allocator, source: []const u8, deck: *const spice.Deck, rec: *const recognize.Recognized, c: u32, names: []const []const u8, actual: *const np.netlist.Netlist) Allocator.Error!Bound {
    return forCellGeometry(gpa, a, source, deck, rec, c, names, actual, .manhattan);
}

/// Includes the verified reciprocal loads when the output target accepts their wire directions.
pub fn forCellGeometry(gpa: Allocator, a: Allocator, source: []const u8, deck: *const spice.Deck, rec: *const recognize.Recognized, c: u32, names: []const []const u8, actual: *const np.netlist.Netlist, mode: np.wire_geometry.Mode) Allocator.Error!Bound {
    if (source.len == 0 or c != 1 or deck.cells() != 2 or deck.devs(0).len() != 0) return .{};
    const range = deck.devs(c);
    if (range.len() < 5 or range.len() > 128 or actual.graph.edgeCount() != range.len()) return .{};
    var passives: usize = 0;
    for (range.lo..range.hi) |d| {
        const sym = rec.parts.sym.items[d];
        const family = rec.syms.family.items[sym];
        if (family == .two and rec.syms.origin.items[sym] == .core and deck.netsOf(@intCast(d)).len == 2) {
            const stem = switch (std.ascii.toLower(deck.dev_name[d][0])) {
                'r' => "res",
                'l' => "ind",
                'i' => "isource",
                'c' => "cap",
                else => return .{},
            };
            if (!std.mem.eql(u8, rec.syms.stem.items[sym], stem)) return .{};
            passives += 1;
            continue;
        }
        if ((family != .nmos and family != .pmos) or std.ascii.toLower(deck.dev_name[d][0]) != 'm' or deck.netsOf(@intCast(d)).len != 4) return .{};
    }
    if (passives != 0) {
        if (!((passives == 4 and range.len() == 7) or (passives == 9 and range.len() == 15) or (passives == 11 and range.len() == 19))) return .{};
        for (range.lo..range.hi) |d| if (rec.syms.origin.items[rec.parts.sym.items[d]] != .core) return .{};
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
    if (original.graph.edgeCount() != actual.graph.edgeCount()) return .{};
    var owners: Bound = .{};
    if (passives != 0) {
        owners.bridge = (try np.source_layout.collect(a, source, &original)) orelse return .{};
    } else {
        const ctx = try np.parent_context.bind(a, source, &original, &np.parent_context.standard_rails);
        if (ctx.reasons.count() != 0) return .{};
        const parents = try np.local_parents.collect(a, ctx, .{});
        if (mode == .allow_45 and original.graph.edgeCount() == 5) {
            const roles = try np.guessRoles(a, &original);
            owners.crossover = np.crossover.collect(&original, roles);
        }
        if (parents.disposition == .raw_multigroup_candidate) {
            owners.pairs = try np.parent_outputs.collect(a, ctx, parents);
            owners.stages = try np.parent_stages.collect(a, ctx, parents);
        }
        if (owners.pairs.len == 0 and owners.stages.len == 0 and owners.crossover == null) return .{};
    }
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
        const kind = original.graph.edges.items(.kind)[origin.index()];
        if (kind != actual.graph.edges.items(.kind)[target.index()] or ps.len != qs.len) return .{};
        if (kind == .mosfet) {
            if (ps.len != 4) return .{};
            const pol = actual.modelType(target) orelse return .{};
            if (!std.mem.eql(u8, pol, original.modelType(origin) orelse return .{})) return .{};
        } else if ((kind != .resistor and kind != .inductor and kind != .isource and kind != .capacitor) or ps.len != 2) return .{};
        devices[origin.index()] = target.index();
        for (ps, qs, deck.netsOf(@intCast(d))) |x, y, n| {
            if (!std.mem.eql(u8, original.graph.vertices.items(.name)[x.index()], deck.netKey(c, n)) or !std.mem.eql(u8, actual.graph.vertices.items(.name)[y.index()], names[n])) return .{};
            if (nets[x.index()] != std.math.maxInt(u32) and nets[x.index()] != y.index()) return .{};
            nets[x.index()] = y.index();
        }
    }
    const mapped = try a.alloc(np.parent_outputs.Pair, owners.pairs.len);
    for (owners.pairs, mapped) |pair, *dst| for (pair, dst) |o, *out| {
        out.* = .{ .net = nets[o.net], .pmos = devices[o.pmos], .nmos = devices[o.nmos], .gate = devices[o.gate] };
    };
    const target_stages = try a.alloc(np.parent_stages.Stage, owners.stages.len);
    for (owners.stages, target_stages) |stage, *dest| {
        dest.* = stage;
        for (stage.devices, &dest.devices) |d, *mapped_id| mapped_id.* = devices[d];
    }
    if (owners.bridge) |*bridge| {
        switch (bridge.*) {
            inline else => |*r| for (&r.devices) |*d| {
                d.* = devices[d.*];
            },
        }
    }
    if (owners.crossover) |*pair| {
        for (&pair.loads) |*d| d.* = devices[d.*];
        for (&pair.inputs) |*d| d.* = devices[d.*];
    }
    return .{ .pairs = mapped, .stages = target_stages, .bridge = owners.bridge, .crossover = owners.crossover };
}
