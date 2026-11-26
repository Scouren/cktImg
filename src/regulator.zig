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
//!   AG2212 uses its certified nine-port frame. Every use of a shared Schemify
//!   definition must agree on a frame.
//!   `positiveAbove`
//!
//! Contents: `Card`, `localOwner`, `positiveAbove`, `held`.

const std = @import("std");
const lib = @import("library.zig");
const np = @import("root.zig");

/// One of the six original cards. Readers certify the MOS model and the
/// complete generated amplifier shape before passing their ordered net IDs.
pub const Card = struct {
    kind: enum { amplifier, nmos, resistor, capacitor, other },
    nets: []const u32,
};

/// Returns the pass MOS and the upper/lower divider resistor indices for
/// this amplifier. Protected net counts include every original pin, including
/// controls and bulks. The divider tap and the MOS gate cannot share another
/// owner. Complete signed formal recognition is the readers' responsibility.
pub fn localOwner(cards: []const Card, anchor: usize, ports: []const []const u8, external: []const u32, counts: []const u8) ?[3]u32 {
    const amp = cards[anchor].nets;
    if (amp.len != ports.len or ports.len > 9) return null;
    var neg: ?u32 = null;
    var gnd: ?u32 = null;
    var gate: ?u32 = null;
    for (ports, amp, 0..) |p, n, i| {
        if (contains(amp[0..i], n)) return null;
        switch (lib.portRole(ports, p)) {
            .inn => neg = n,
            .out => gate = n,
            .rail => if (lib.named(p, .role) == .ground) {
                gnd = n;
            },
            else => if (!contains(external, n) or counts[n] != 1) return null,
        }
    }
    const tap = neg orelse return null;
    const drive = gate orelse return null;
    const ground = gnd orelse return null;
    if (contains(external, tap) or contains(external, drive) or counts[tap] != 3 or counts[drive] != 2) return null;
    var mos: ?u32 = null;
    var low: ?u32 = null;
    var high: ?u32 = null;
    var output: u32 = undefined;
    for (cards, 0..) |card, i| {
        if (card.kind == .nmos and card.nets.len == 4 and card.nets[1] == drive) mos = @intCast(i);
        if (card.kind != .resistor or card.nets.len != 2) continue;
        const other_net = other(card.nets, tap) orelse continue;
        if (other_net == ground) {
            low = @intCast(i);
        } else {
            output = other_net;
            high = @intCast(i);
        }
    }
    const hi = high orelse return null;
    const lo = low orelse return null;
    const pass = mos orelse return null;
    const m = cards[pass].nets;
    const input = if (m[0] == output) m[2] else if (m[2] == output) m[0] else return null;
    if (output == input or contains(amp, output) or !contains(external, input) or !contains(external, output)) return null;
    if (m[3] != ground and m[3] != output) return null;
    for (amp, ports) |n, formal| if (n == input and lib.named(formal, .role) != .supply) return null;
    return .{ pass, hi, lo };
}

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
        .other => return false,
        .amplifier => amp = card.nets,
        .nmos => mos = card.nets,
        .capacitor => cap = card.nets,
        .resistor => {
            if (nr == resistors.len or card.nets.len != 2) return false;
            resistors[nr] = card.nets[0..2].*;
            nr += 1;
        },
    };
    if (nr != 3 or mos.len != 4 or cap.len != 2 or amp.len != ports.len or amp.len < 4 or amp.len > 9) return false;
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

/// Returns each device whose class, face, pose or cell is honoured in the
/// ordinary drawing. The empty slice means no such request was present.
pub fn held(a: std.mem.Allocator, nl: *const np.netlist.Netlist, symbols: *np.Library, cfg: *const np.Config) ![]const bool {
    for (nl.hints) |h| switch (h.verb) {
        .at, .cell, .class, .face => break,
        else => {},
    } else return &.{};
    // A caller can supply a weak pose that the ordinary drawing rejects.
    // Only the actual honoured endpoint has authority over the local frame.
    const roles = try np.guessRoles(a, nl);
    const st = try np.schematic.structure.analyze(a, a, nl, roles);
    const sk = try np.schematic.skeleton.place(a, a, nl, roles, &st, .{ .shelf = cfg.layout.shelf });
    var ordinary = try np.placeBound(a, a, cfg, symbols, nl, &.{});
    defer ordinary.deinit();
    const reserved = try a.alloc(bool, nl.graph.edgeCount());
    @memset(reserved, false);
    for (nl.hints, try np.report.verdicts(a, nl, roles, &st, &sk, &ordinary, symbols)) |h, verdict| {
        if (verdict.state != .honoured or h.args.len == 0) continue;
        switch (h.verb) {
            .at, .cell, .class, .face => if (nl.device(h.args[0])) |e| {
                if (h.verb == .class) {
                    const d = np.checks.deviceIn(&ordinary, h.args[0]) orelse continue;
                    if (symbols.find(h.args[1]) != ordinary.dev_class[d]) continue;
                }
                reserved[e.index()] = true;
            },
            else => {},
        }
    }
    return reserved;
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
