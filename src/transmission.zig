//! Complementary parallel MOS channels, shared by placement and turning.
//!
//! Human Rules:
//! - transmission.1 (habit) Two complementary MOS channels on the same
//!   unordered drain/source nets, with distinct gates outside those nets,
//!   form a parallel transmission pair. Among forms.19's selected AG
//!   circuits, ag-386 and ag-751 both put NMOS above PMOS in one column,
//!   clocks outward (2/2). Same-type pairs are excluded: ag-761's lower
//!   switch points inward. An ambiguous bank of three is not a pair.
//!   `mate`; bridges and sketch apply the geometry only to flat members.
//!
//! Data: reads the existing netlist's MOS pin rows and model types, bounded
//! by one channel net's CSR incidences. Returns one device handle, borrowed
//! from that table; no storage, allocation, ownership or capacity changes.
//! The two callers own placement and orientation, respectively.
//!
//! Contents:
//! - `pub fn mate(nl: *const Netlist, d: u32) ?u32`

const std = @import("std");
const device = @import("device.zig");
const netlist = @import("netlist.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const assert = std.debug.assert;

/// The sole complementary MOS with the same distinct channel nets and a
/// different, non-channel gate. Returns null for other devices, unknown
/// polarity, or any additional parallel channel. Reads only `nl`; `d`
/// must name an existing device. The caller decides whether both are flat.
pub fn mate(nl: *const Netlist, d: u32) ?u32 {
    const c = &nl.graph;
    assert(d < c.edgeCount());
    if (c.edges.items(.kind)[d] != .mosfet) return null;
    const pins = c.members(EdgeId.from(d));
    assert(pins.len >= 3);
    if (pins[0] == pins[2] or pins[1] == pins[0] or pins[1] == pins[2]) return null;
    const pol = device.polarity(nl.modelType(EdgeId.from(d)));
    if (pol == .other) return null;
    var other: ?u32 = null;
    var previous: ?u32 = null;
    for (c.incident(pins[0])) |e| {
        const m: u32 = @intCast(e.index());
        if (previous == m) continue;
        previous = m;
        if (m == d or c.edges.items(.kind)[m] != .mosfet) continue;
        const q = c.members(e);
        const parallel = (pins[0] == q[0] and pins[2] == q[2]) or (pins[0] == q[2] and pins[2] == q[0]);
        if (!parallel) continue;
        if (other != null) return null;
        other = m;
    }
    const m = other orelse return null;
    const q = c.members(EdgeId.from(m));
    if (q[1] == pins[1] or q[1] == q[0] or q[1] == q[2]) return null;
    const opposite = device.polarity(nl.modelType(EdgeId.from(m)));
    return if (opposite != .other and opposite != pol) m else null;
}

test "transmission: same-type, shared-control and ambiguous parallel banks are not complementary pairs" {
    // Oracle: a transmission pair has one independent control per polarity.
    // AG761's same-type parallel switches do not face outward; a third
    // parallel device gives no unique partner. Body aliases do not add paths.
    const gpa = std.testing.allocator;
    const prefix = "Pair\n.model nch nmos\n.model pch pmos\nM1 a c1 b b nch\n";
    const cases = [_]struct { []const u8, bool }{
        .{ "M2 b c2 a vdd pch\n", true },
        .{ "M2 a c2 b b pch\n", true },
        .{ "M2 b c2 a 0 nch\n", false },
        .{ "M2 b c1 a vdd pch\n", false },
        .{ "M2 b a a vdd pch\n", false },
        .{ "M2 b c2 a vdd pch\nM3 a c3 b 0 nch\n", false },
    };
    for (cases) |row| {
        const text = try std.mem.concat(gpa, u8, &.{ prefix, row[0] });
        defer gpa.free(text);
        var nl = try netlist.parse(gpa, &.{text}, null);
        defer nl.deinit(gpa);
        const m1: u32 = @intCast(nl.device("m1").?.index());
        const other = mate(&nl, m1);
        try std.testing.expectEqual(row[1], other != null);
        if (other) |m2| {
            try std.testing.expectEqual(nl.device("m2").?.index(), m2);
            try std.testing.expectEqual(m1, mate(&nl, m2).?);
        }
    }
}
