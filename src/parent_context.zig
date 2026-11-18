//! Original selected-cell authority bound to the actual graph before local-parent analysis.
//!
//! Contents:
//! - `pub const Reason`
//! - `pub const NetKind`
//! - `pub const Rail`
//! - `pub const standard_rails`
//! - `pub const Context`
//! - `pub fn bind(arena: Allocator, raw: []const u8, nl: *const netlist.Netlist, rails: []const Rail) !Context`

const std = @import("std");
const netlist = @import("netlist.zig");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;

/// Why the original input, ownership or arrangement policy declined.
pub const Reason = enum {
    empty_cell,
    non_mos_attachment_or_component,
    duplicate_model_definition,
    unowned_conventional_rail,
    unsupported_declaration,
    unsupported_formal_contract,
    unused_formal_ownership_unresolved,
    unsupported_raw_mos_grammar,
    unsupported_model_definition,
    nonrail_body_or_source_body_tie,
    body_rail_polarity_outside_scope,
    shorted_channel,
    original_graph_mismatch,
    internal_gate_without_channel_owner,
    no_nontrivial_involution,
    multiple_full_ordered_involutions,
    bounded_search_incomplete,
    intergroup_gate_dependency_cycle,
};
/// An original internal net, formal signal or individually distinguished rail.
pub const NetKind = enum { internal, formal, supply, sink };
/// Distinguished source or sink, transported with any original net renaming.
pub const Rail = struct { name: []const u8, kind: NetKind };
/// Default distinguished nets in the selected native corpus.
pub const standard_rails = [_]Rail{ .{ .name = "0", .kind = .sink }, .{ .name = "vss", .kind = .sink }, .{ .name = "vdd", .kind = .supply } };
/// Source and graph remain borrowed for the analysis lifetime. `kind` indexes
/// this exact graph, including its possibly unused built-in ground vertex.
pub const Context = struct {
    nl: *const netlist.Netlist,
    source: []const u8,
    kind: []NetKind,
    reasons: std.EnumSet(Reason) = .empty,
    original_intent: bool = false,
};

/// Binds the bare last cell's literal ordered MOS cards and declarations to
/// `nl`. Graph inputs synthesized by a caller cannot replace original evidence.
pub fn bind(arena: Allocator, raw: []const u8, nl: *const netlist.Netlist, rails: []const Rail) !Context {
    const kind = try arena.alloc(NetKind, nl.graph.vertexCount());
    @memset(kind, .internal);
    var ctx = Context{ .nl = nl, .source = raw, .kind = kind };
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), "*@")) {
        ctx.original_intent = true;
        break;
    };
    for (nl.graph.edges.items(.kind)) |k| if (k != .mosfet) {
        ctx.reasons.insert(.non_mos_attachment_or_component);
        return ctx;
    };
    const text = std.ascii.lowerString(try arena.alloc(u8, raw.len), raw);
    const title = !std.mem.startsWith(u8, std.mem.trimStart(u8, text, " \t\r\n"), ".subckt");
    var cards = netlist.OriginalCards.init(text, title);
    var models: std.StringHashMapUnmanaged(?NetKind) = .empty;
    var header_names: std.StringHashMapUnmanaged(void) = .empty;
    var header: []const []const u8 = &.{};
    var depth: usize = 0;
    while (try cards.next(arena)) |f| {
        if (eql(u8, f[0], ".model") and f.len >= 3) {
            const entry = try models.getOrPut(arena, f[1]);
            if (entry.found_existing) ctx.reasons.insert(.duplicate_model_definition);
            entry.value_ptr.* = if (f.len != 3) null else if (eql(u8, f[2], "nmos")) .sink else if (eql(u8, f[2], "pmos")) .supply else null;
        } else if (eql(u8, f[0], ".subckt") and f.len >= 2) {
            if (depth != 0 or (try header_names.getOrPut(arena, f[1])).found_existing) ctx.reasons.insert(.unsupported_formal_contract);
            depth += 1;
            header = try arena.dupe([]const u8, f);
        } else if (eql(u8, f[0], ".ends") and depth > 0) depth -= 1 else if (f[0][0] == '.' or depth == 0) ctx.reasons.insert(.unsupported_declaration);
    }
    if (depth != 0 or header.len < 2) {
        ctx.reasons.insert(.unsupported_formal_contract);
        return ctx;
    }
    if (nl.graph.edgeCount() == 0) ctx.reasons.insert(.empty_cell);
    for (header[2..]) |name| {
        if (name.len == 0 or eql(u8, name, "params:") or eql(u8, name, "=")) ctx.reasons.insert(.unsupported_formal_contract);
        const n = nl.net(name) orelse {
            ctx.reasons.insert(.unused_formal_ownership_unresolved);
            continue;
        };
        if (nl.graph.incident(n).len == 0) ctx.reasons.insert(.unused_formal_ownership_unresolved);
        if (kind[n.index()] != .internal) ctx.reasons.insert(.unsupported_formal_contract);
        kind[n.index()] = .formal;
    }
    for (rails) |rail| {
        if (nl.net(rail.name)) |n| {
            if (nl.graph.incident(n).len == 0) continue;
            if (rail.kind != .supply and rail.kind != .sink) {
                ctx.reasons.insert(.unsupported_formal_contract);
                continue;
            }
            if (n != netlist.ground and kind[n.index()] != .formal) ctx.reasons.insert(.unowned_conventional_rail);
            kind[n.index()] = rail.kind;
        }
    }
    const seen = try arena.alloc(bool, nl.graph.edgeCount());
    @memset(seen, false);
    var active = false;
    cards = netlist.OriginalCards.init(text, title);
    while (try cards.next(arena)) |f| {
        if (eql(u8, f[0], ".subckt")) {
            active = f.len >= 2 and eql(u8, f[1], header[1]);
            continue;
        }
        if (eql(u8, f[0], ".ends")) {
            active = false;
            continue;
        }
        if (!active or f[0][0] == '.') continue;
        if (f[0][0] != 'm') {
            ctx.reasons = .empty;
            ctx.reasons.insert(.non_mos_attachment_or_component);
            return ctx;
        }
        const d = nl.device(f[0]) orelse {
            ctx.reasons.insert(.original_graph_mismatch);
            continue;
        };
        if (seen[d.index()]) ctx.reasons.insert(.original_graph_mismatch);
        seen[d.index()] = true;
        const pins = nl.graph.members(d);
        if (f.len < 6 or (f.len - 6) % 3 != 0 or pins.len != 4) {
            ctx.reasons.insert(.unsupported_raw_mos_grammar);
            continue;
        }
        var i: usize = 6;
        while (i < f.len) : (i += 3) {
            if (!eql(u8, f[i + 1], "=") or eql(u8, f[i], "=")) ctx.reasons.insert(.unsupported_raw_mos_grammar);
            _ = netlist.parseValue(f[i + 2]) catch {
                ctx.reasons.insert(.unsupported_raw_mos_grammar);
                continue;
            };
        }
        for (pins, f[1..5]) |n, original| if (!eql(u8, original, nl.graph.vertices.items(.name)[n.index()])) ctx.reasons.insert(.original_graph_mismatch);
        const params = nl.params(d);
        if (params.len != f.len - 5) ctx.reasons.insert(.original_graph_mismatch) else for (params, f[5..]) |got, expected| if (!eql(u8, got, expected)) ctx.reasons.insert(.original_graph_mismatch);
        const model = (models.get(f[5]) orelse null) orelse {
            ctx.reasons.insert(.unsupported_model_definition);
            continue;
        };
        const body = kind[pins[3].index()];
        if (body != .supply and body != .sink) ctx.reasons.insert(.nonrail_body_or_source_body_tie) else if (body != model) ctx.reasons.insert(.body_rail_polarity_outside_scope);
        if (pins[0] == pins[2]) ctx.reasons.insert(.shorted_channel);
    }
    if (std.mem.indexOfScalar(bool, seen, false) != null) ctx.reasons.insert(.original_graph_mismatch);
    return ctx;
}

test "original duplicate model, continued formal and body survive normalized graph equality" {
    const a = std.testing.allocator;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const body = "deck\nM1 out in vss vss nch w=1\n.model nch nmos\n";
    var nl = try netlist.parse(a, &.{body}, null);
    defer nl.deinit(a);
    const raw = "deck\n.model nch nmos\n.subckt dut in\n+ out vss\nM1 out in vss vss nch w=1\n.ends\n";
    const ctx = try bind(scratch.allocator(), raw, &nl, &standard_rails);
    try std.testing.expect(ctx.reasons.count() == 0);
    const duplicate = "deck\n.model nch pmos\n" ++ raw[5..];
    try std.testing.expect((try bind(scratch.allocator(), duplicate, &nl, &standard_rails)).reasons.contains(.duplicate_model_definition));
}

test "source scope rejects extra formal, qualified model, missing rail formal and altered original pins" {
    const a = std.testing.allocator;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var nl = try netlist.parse(a, &.{"deck\nM1 out in vss vss nch w=1\n.model nch nmos\n"}, null);
    defer nl.deinit(a);
    const raw = "deck\n.model nch nmos\n.subckt dut in\n+ out vss\nM1 out in vss vss nch w=1\n.ends\n";
    const edits = [_]struct { before: []const u8, after: []const u8, reason: Reason }{
        .{ .before = "+ out vss", .after = "+ out vss unknown", .reason = .unused_formal_ownership_unresolved },
        .{ .before = ".model nch nmos", .after = ".model nch nmos level=1", .reason = .unsupported_model_definition },
        .{ .before = "+ out vss", .after = "+ out", .reason = .unowned_conventional_rail },
        .{ .before = "M1 out in", .after = "M1 in out", .reason = .original_graph_mismatch },
    };
    for (edits) |edit| {
        const changed = try std.mem.replaceOwned(u8, scratch.allocator(), raw, edit.before, edit.after);
        try std.testing.expect((try bind(scratch.allocator(), changed, &nl, &standard_rails)).reasons.contains(edit.reason));
    }
    const requested = try std.mem.replaceOwned(u8, scratch.allocator(), raw, ".ends", "*@ wire out\n.ends");
    const ctx = try bind(scratch.allocator(), requested, &nl, &standard_rails);
    try std.testing.expect(ctx.original_intent);
    try std.testing.expectEqual(@as(usize, 0), ctx.reasons.count());
}
