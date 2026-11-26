//! Closed paired RC inputs -> cold five-passive placement candidates.
//!
//! Human Rules:
//! - block_input_rc.1 (bounded observation) AG1103 X2/X3 have one C and R
//!   per named INP/INN, one common bias choke, and a unique upstream
//!   OUTP/OUTN block. Its choke far net is outside the five signal/bias
//!   nets. Count every raw pin before role/frame filtering.
//!   X1 lacks that upstream block and its caps do not share input rows.
//!   Actual source: docs/research/block-input-rc.md. `find`
//! - block_input_rc.2 (invariant) Caller geometry, sides, shelves, mates,
//!   grouping and local style/port/route requests defeat the whole inferred
//!   group. Invalid/dropped hints do not. Only five passives may move; the
//!   actual block and its declared input frame stay read-only. `collect`
//!
//! Data: borrowed graph/admission tables in; at most subckt-count cold
//! 28-byte records out. Six typed u32 handles and two u8 class pin indexes
//! are consumed together. Input nets/endpoint identity remain in CSR.
//! Twenty i32 order pairs and one Room per group are caller-owned until
//! the draw completes. All allocations precede geometry writes; no hot
//! table, retained state, ABI, parallel-commit or speed claim.
//!
//! Contents: Group, order_pair_capacity, Batch, Batch.deinit, collect, members, nearPin;
//! private raw-incidence selector and tests.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const block_symbols = @import("block_symbols.zig");
const antiparallel = @import("antiparallel.zig");
const Room = @import("lattice_geometry.zig").Room;
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;

/// Read-only block, INP/INN caps and resistors, unique choke and named input pins.
pub const Group = struct { block: EdgeId, caps: [2]EdgeId, resistors: [2]EdgeId, choke: EdgeId, pins: [2]u8 };
/// Ten strict source relations: six longitudinal, four transverse.
pub const order_pair_capacity: usize = 10;

/// Cold existence list with bounded immediate room and compact requests.
pub const Batch = struct {
    groups: std.ArrayList(Group),
    coordinates: [][2]i32,
    room: []Room,

    /// Releases each collection buffer with its allocation owner.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.groups.deinit(gpa);
        gpa.free(self.coordinates);
        gpa.free(self.room);
        self.* = undefined;
    }
};

comptime { assert(@sizeOf(Group) == 28); }

/// Collects complete unheld groups before relay consumes weak stays.
/// Every slice spans the original graph; hidden/undrawn competitors count.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    const c = &nl.graph;
    assert(ats.len == c.edgeCount() and sk.drawn.len == c.edgeCount());
    assert(lines.style.len == c.vertexCount() and st.device_mate.len == c.edgeCount());
    var capacity: usize = 0;
    for (c.edges.items(.kind)) |kind| capacity += @intFromBool(kind == .subckt);
    var groups: std.ArrayList(Group) = .empty;
    errdefer groups.deinit(gpa);
    try groups.ensureTotalCapacity(gpa, capacity);
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt) continue;
        const group = find(nl, s.roles, .from(d)) orelse continue;
        const owned = members(group);
        const all = [_]EdgeId{ group.block, owned[0], owned[1], owned[2], owned[3], owned[4] };
        const blocked = blocked: for (all) |edge| {
            const i = edge.index();
            if (!sk.drawn[i] or ats[i] != null or sk.shelf[i] != sk.shelf[d] or st.device_mate[i] != sch.none) break true;
            if (antiparallel.held(nl, sk.verdicts, edge, edge) or antiparallel.held(nl, st.verdicts, edge, edge)) break true;
            for (st.block_devices) |other| if (other == i) break :blocked true;
            if (nl.defOf(edge)) |def| for (def.sides) |side| if (side != null) break :blocked true;
        } else false;
        if (blocked) continue;
        const styled = styled: for (owned) |edge| {
            for (c.members(edge)) |net| {
                if (lines.style[net.index()] != .auto or lines.port[net.index()] != null) break :styled true;
                for (lines.routes) |route| if (route.net == net.index()) break :styled true;
            }
        } else false;
        if (!styled) groups.appendAssumeCapacity(group);
    }
    // Degree-three input nets normally imply disjointness; still reject a
    // shared device explicitly before admission filtering can hide a rival.
    var kept: usize = 0;
    for (groups.items) |group| {
        const overlaps = overlap: for (c.edges.items(.kind), 0..) |kind, d| {
            if (kind != .subckt or d == group.block.index()) continue;
            const other = find(nl, s.roles, .from(d)) orelse continue;
            for (members(group)) |a| for (members(other)) |b| if (a == b) break :overlap true;
        } else false;
        if (overlaps) continue;
        groups.items[kept] = group; kept += 1;
    }
    groups.items = groups.items[0..kept];
    std.sort.heap(Group, groups.items, st.device_rank, struct {
        fn less(rank: []const u32, a: Group, b: Group) bool { return rank[a.block.index()] < rank[b.block.index()]; }
    }.less);
    const coordinates = try gpa.alloc([2]i32, 2 * order_pair_capacity * groups.items.len);
    errdefer gpa.free(coordinates);
    const room = try gpa.alloc(Room, groups.items.len);
    return .{ .groups = groups, .coordinates = coordinates, .room = room };
}

/// Five owned devices: capacitor INP/INN, resistor INP/INN, then bias choke.
pub fn members(group: Group) [5]EdgeId { return .{ group.caps[0], group.caps[1], group.resistors[0], group.resistors[1], group.choke }; }

/// Raw 0/1 endpoint toward the block input, or toward resistor bias for the choke.
/// Requires a complete group; the five-member order is defined by members().
pub fn nearPin(nl: *const Netlist, group: Group, member: usize) u1 {
    assert(member < 5);
    const p = nl.graph.members(members(group)[member]);
    assert(p.len == 2);
    const block_input = nl.graph.members(group.block)[group.pins[member % 2]];
    const resistor = nl.graph.members(group.resistors[0]);
    const net = if (member < 4) block_input else if (resistor[0] == block_input) resistor[1] else resistor[0];
    assert(std.mem.count(VertexId, p, &.{net}) == 1);
    return @intFromBool(p[0] != net);
}

// ---- private ----

fn named(nl: *const Netlist, block: EdgeId, names: [2][]const u8) ?[2]u8 {
    const def = nl.defOf(block) orelse return null;
    var result: [2]?u8 = .{ null, null };
    for (def.ports, 0..) |port, i| for (names, 0..) |name, j| if (std.ascii.eqlIgnoreCase(port, name)) {
        if (result[j] != null or i > std.math.maxInt(u8)) return null;
        result[j] = @intCast(i);
    };
    return .{ result[0] orelse return null, result[1] orelse return null };
}

fn find(nl: *const Netlist, roles: []const sch.Role, block: EdgeId) ?Group {
    const c = &nl.graph;
    const indices = named(nl, block, .{ "inp", "inn" }) orelse return null;
    const block_nets = c.members(block);
    const inputs = [_]VertexId{ block_nets[indices[0]], block_nets[indices[1]] };
    if (inputs[0] == inputs[1] or roles[inputs[0].index()].isRail() or roles[inputs[1].index()].isRail()) return null;
    var group: Group = .{ .block = block, .caps = undefined, .resistors = undefined, .choke = undefined, .pins = indices };
    var upstream: [2]VertexId = undefined;
    var bias: [2]VertexId = undefined;
    for (inputs, 0..) |net, i| {
        if (c.incident(net).len != 3 or std.mem.count(VertexId, block_nets, &.{net}) != 1) return null;
        var cap: ?EdgeId = null;
        var resistor: ?EdgeId = null;
        for (c.incident(net)) |edge| {
            if (edge == block) continue;
            const p = c.members(edge);
            if (p.len != 2 or p[0] == p[1]) return null;
            switch (c.edges.items(.kind)[edge.index()]) {
                .capacitor => { if (cap != null) return null; cap = edge; upstream[i] = if (p[0] == net) p[1] else p[0]; },
                .resistor => { if (resistor != null) return null; resistor = edge; bias[i] = if (p[0] == net) p[1] else p[0]; },
                else => return null,
            }
        }
        group.caps[i] = cap orelse return null;
        group.resistors[i] = resistor orelse return null;
    }
    if (bias[0] != bias[1]) return null;
    const nets = [_]VertexId{ inputs[0], inputs[1], upstream[0], upstream[1], bias[0] };
    for (nets, 0..) |net, i| {
        if (roles[net.index()].isRail()) return null;
        for (nets[0..i]) |other| if (net == other) return null;
    }
    if (c.incident(bias[0]).len != 3) return null;
    var choke: ?EdgeId = null;
    for (c.incident(bias[0])) |edge| {
        if (edge == group.resistors[0] or edge == group.resistors[1]) continue;
        const p = c.members(edge);
        if (choke != null or c.edges.items(.kind)[edge.index()] != .inductor or p.len != 2 or p[0] == p[1]) return null;
        choke = edge;
    }
    group.choke = choke orelse return null;
    const choke_nets = c.members(group.choke);
    const far = if (choke_nets[0] == bias[0]) choke_nets[1] else choke_nets[0];
    if (std.mem.indexOfScalar(VertexId, &nets, far) != null) return null;
    const owned = members(group);
    for (owned, 0..) |edge, i| for (owned[0..i]) |other| if (edge == other) return null;
    var driver: ?EdgeId = null;
    for (c.edges.items(.kind), 0..) |kind, d| {
        if (kind != .subckt or d == block.index()) continue;
        const edge: EdgeId = .from(d);
        const p = c.members(edge);
        if (std.mem.indexOfScalar(VertexId, p, upstream[0]) == null or std.mem.indexOfScalar(VertexId, p, upstream[1]) == null) continue;
        const def = nl.defOf(edge) orelse return null;
        if (block_symbols.identify(def.name, def.ports) == .center_tap) continue;
        if (driver != null) return null;
        driver = edge;
    }
    const upstream_block = driver orelse return null;
    const outputs = named(nl, upstream_block, .{ "outp", "outn" }) orelse return null;
    const p = c.members(upstream_block);
    for (upstream, outputs) |net, pin| if (p[pin] != net or std.mem.count(VertexId, p, &.{net}) != 1) return null;
    return group;
}

test "block input topology: literal raw incidences and upstream contracts exclude ambiguity" {
    const testing = std.testing;
    const header = "RC selector\n.subckt driver outp outn\n.ends\n.subckt stage inp inn out vss\n.ends\n" ++
        ".subckt opaque a b\n.ends\n.subckt single p\n.ends\n" ++
        ".subckt ct_inductor n1 n2 n3\nL1 n1 n3 1n\nL2 n3 n2 1n\n.ends\n";
    const body = "XD a b driver\nXL a b tap ct_inductor\nX1 ip im out 0 stage\n" ++
        "C1 a ip 1p\nC2 b im 1p\nR1 ip bias 1k\nR2 im bias 1k\nLB bias ext 1n\nRREF other 0 1k\n";
    const Case = struct { name: []const u8, extra: []const u8, accepted: bool };
    for ([_]Case{
        .{ .name = "complete literal", .extra = "", .accepted = true },
        .{ .name = "second input capacitor", .extra = "CX ip extra 1p\n", .accepted = false },
        .{ .name = "second input resistor", .extra = "RX im extra 1k\n", .accepted = false },
        .{ .name = "unknown input incidence", .extra = "XX ip single\n", .accepted = false },
        .{ .name = "second bias choke", .extra = "LX bias extra 1n\n", .accepted = false },
        .{ .name = "unknown bias incidence", .extra = "XX bias single\n", .accepted = false },
        .{ .name = "second named driver", .extra = "XX a b driver\n", .accepted = false },
        .{ .name = "unknown paired driver", .extra = "XX a b opaque\n", .accepted = false },
        .{ .name = "complete passive coil is not a driver", .extra = "XX a b extra ct_inductor\n", .accepted = true },
    }) |case| {
        errdefer std.debug.print("RC selector case={s}\n", .{case.name});
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.mem.concat(a, u8, &.{ header, body, case.extra });
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        const found = find(&nl, roles, nl.device("x1").?);
        try testing.expectEqual(case.accepted, found != null);
        if (found) |group| {
            try testing.expectEqualDeep([2]u8{ 0, 1 }, group.pins);
            try testing.expectEqualDeep([5]EdgeId{ nl.device("c1").?, nl.device("c2").?, nl.device("r1").?, nl.device("r2").?, nl.device("lb").? }, members(group));
        }
    }
    const changes = [_]struct { name: []const u8, from: []const u8, to: []const u8 }{
        .{ .name = "no upstream block", .from = "XD a b driver\n", .to = "" },
        .{ .name = "reversed upstream bindings", .from = "XD a b driver", .to = "XD b a driver" },
        .{ .name = "input alias", .from = "X1 ip im out 0 stage", .to = "X1 ip ip out 0 stage" },
        .{ .name = "duplicate hidden binding", .from = "X1 ip im out 0 stage", .to = "X1 ip im out ip stage" },
        .{ .name = "degenerate cap", .from = "C1 a ip 1p", .to = "C1 ip ip 1p" },
        .{ .name = "different resistor bias", .from = "R2 im bias 1k", .to = "R2 im other 1k" },
        .{ .name = "bias is input", .from = "R1 ip bias 1k", .to = "R1 ip im 1k" },
        .{ .name = "missing choke", .from = "LB bias ext 1n\n", .to = "" },
    };
    for (changes) |change| {
        errdefer std.debug.print("RC selector mutation={s}\n", .{change.name});
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const offset = std.mem.indexOf(u8, body, change.from).?;
        const text = try std.mem.concat(a, u8, &.{ header, body[0..offset], change.to, body[offset+change.from.len..] });
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        try testing.expect(find(&nl, roles, nl.device("x1").?) == null);
    }
}

test "block input topology: declaration and passive-card permutations retain semantic endpoints" {
    const testing = std.testing;
    const text = "Permuted RC\n.subckt driver outn outp\n.ends\n.subckt stage inn out inp vss\n.ends\n" ++
        "XD b a driver\nX1 im out ip 0 stage\nC2 im b 1p\nR2 bias im 1k\nC1 ip a 1p\nR1 bias ip 1k\nLB bias ext 1n\nRREF other 0 1k\n";
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a, &.{text}, null);
    const roles = try sch.guessRoles(a, &nl);
    const group = find(&nl, roles, nl.device("x1").?) orelse return error.ExpectedLiteralGroup;
    try testing.expectEqualDeep([2]u8{ 2, 0 }, group.pins);
    try testing.expectEqualDeep([5]EdgeId{ nl.device("c1").?, nl.device("c2").?, nl.device("r1").?, nl.device("r2").?, nl.device("lb").? }, members(group));
    for ([_]u1{ 0, 0, 1, 1, 0 }, 0..) |pin, i| try testing.expectEqual(pin, nearPin(&nl, group, i));
    for ([_][]const u8{ "ip", "im", "a", "b", "bias" }) |name| {
        const index = nl.net(name).?.index();
        const old = roles[index];
        roles[index] = .supply;
        try testing.expect(find(&nl, roles, group.block) == null);
        roles[index] = old;
    }
}


test "block input topology: the choke far end stays outside all five local signal and bias nets" {
    const testing = std.testing;
    const header = "Choke boundary\n.subckt driver outp outn\n.ends\n.subckt stage inp inn out vss\n.ends\n";
    const body = "XD a b driver\nX1 ip im out 0 stage\nC1 a ip 1p\nC2 b im 1p\nR1 ip bias 1k\nR2 im bias 1k\n";
    for ([_][]const u8{ "ext", "ip", "im", "bias", "a", "b" }, 0..) |far, i| {
        errdefer std.debug.print("RC choke far-net boundary={s}\n", .{far});
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const text = try std.fmt.allocPrint(a, "{s}{s}LB bias {s} 1n\nRREF other 0 1k\n", .{ header, body, far });
        var nl = try netlist.parse(a, &.{text}, null);
        const roles = try sch.guessRoles(a, &nl);
        try testing.expectEqual(i == 0, find(&nl, roles, nl.device("x1").?) != null);
    }
}
