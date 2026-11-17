//! Signed input order on the complete capacitor/ESR-loaded NMOS regulator.
//! AnalogGenie AG2187 draws the reference above the feedback tap. Check the
//! original ordered bindings, including bulk, and literal cell interface.
//!
//! Human Rules:
//! - regulator.1 (choice) A single signed amplifier driving a pass NMOS
//!   above a grounded divider and parallel series C/ESR branch draws its
//!   reference above feedback. AG2187 Fig. A.1 and Wang US 7,446,515
//!   Fig. 1A show the order; TI LDO Basics Fig. 4 rotates it with the
//!   amplifier. All 40 AnalogGenie decks reuse one panel. The signed marks
//!   follow their own ports; rail and bias leads retain their positions.
//!   AG2212 retains its generic box because its fourth bias lacks a
//!   recognized frame. Schemify keeps a shared .shcomp’s default frame.
//!   `positiveAbove`
//!
//! Contents: `Card`, `positiveAbove`.

const std = @import("std");
const lib = @import("library.zig");

/// One of the six original cards. Readers certify the MOS model and the
/// complete generated amplifier shape before passing their ordered net IDs.
pub const Card = struct {
    kind: enum { amplifier, nmos, resistor, capacitor },
    nets: []const u32,
};

/// True for one amplifier driving the sole NMOS gate, a resistor divider
/// feeding its negative input and a separate capacitor/ESR output branch.
/// Each private node differs from every boundary port. Card, R/C terminal
/// and MOS channel order are immaterial. Borrows all slices for the call.
pub fn positiveAbove(cards: [6]Card, ports: []const []const u8, external: []const u32) bool {
    var amp: []const u32 = &.{};
    var mos: []const u32 = &.{};
    var cap: []const u32 = &.{};
    var resistors: [3][2]u32 = undefined;
    var nr: usize = 0;
    for (cards) |card| switch (card.kind) {
        .amplifier => amp = card.nets,
        .nmos => mos = card.nets,
        .capacitor => cap = card.nets,
        .resistor => {
            if (nr == resistors.len or card.nets.len != 2) return false;
            resistors[nr] = card.nets[0..2].*;
            nr += 1;
        },
    };
    if (nr != 3 or mos.len != 4 or cap.len != 2 or amp.len != ports.len or amp.len < 4 or amp.len > 8) return false;
    var neg: ?u32 = null;
    var gate: ?u32 = null;
    var gnd: ?u32 = null;
    var pos: ?u32 = null;
    for (ports, amp, 0..) |p, n, i| {
        if (contains(amp[0..i], n)) return false;
        const role = lib.portRole(ports, p);
        switch (role) {
            .inn => neg = n,
            .inp => pos = n,
            .out => gate = n,
            else => if (lib.named(p, .role) == .ground) {
                gnd = n;
            },
        }
        const private = neg == n or gate == n;
        // A declared supply can be local to the DUT (AG2225).
        if (role != .rail and contains(external, n) == private) return false;
    }
    const tap = neg orelse return false;
    const ground = gnd orelse return false;
    if (pos == null or gate != mos[1] or mos[0] == mos[2]) return false;
    const node = if (other(cap, mos[0])) |n| n else other(cap, mos[2]) orelse return false;
    const output = other(cap, node).?;
    const input = if (output == mos[0]) mos[2] else mos[0];
    if (!contains(external, output) or !contains(external, input) or contains(external, node)) return false;
    if (node == output or contains(amp, node) or contains(amp, output)) return false;
    if (mos[3] != output and mos[3] != ground) return false;
    for (amp, ports) |n, p| if (n == input and lib.named(p, .role) != .supply) return false;
    var upper = false;
    var lower = false;
    var esr = false;
    for (resistors) |r| {
        upper = upper or other(&r, tap) == output;
        lower = lower or other(&r, tap) == ground;
        esr = esr or other(&r, node) == ground;
    }
    return upper and lower and esr;
}

// ---- private ----

fn contains(nets: []const u32, net: u32) bool {
    return std.mem.indexOfScalar(u32, nets, net) != null;
}

fn other(pair: []const u32, net: u32) ?u32 {
    std.debug.assert(pair.len == 2);
    if (pair[0] == net) return pair[1];
    if (pair[1] == net) return pair[0];
    return null;
}
