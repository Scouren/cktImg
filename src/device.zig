//! The device model every stage reads (issue #8): what a device of a kind
//! is to a drawing. In: a device kind. Out: which of its pins do what.
//!
//! A device is a **current path** with side pins, or a box. Its path is the
//! two pins its current passes through. A drawing's rows order potential,
//! supply above ground: a path stands upright with its ends on two rows, or
//! lies flat between two columns. Its side pins read a net and pass no
//! current: the **gate** a drawing turns left or right, a switch's or a
//! controlled source's **control** pair, a body. A drawing's columns order
//! signal: what drives a net stands left of what reads it. A box (a block,
//! a line) has no path, and its ports go by their names
//! (`library.portRole`).
//!
//! | kind | path | gate | control | ends told apart |
//! |---|---|---|---|---|
//! | M, J, Z | d, s | g | | yes |
//! | Q | c, e | b | | yes |
//! | R, C, L | 1, 2 | | | no |
//! | D | 1, 2 | | | yes |
//! | V, I | 1, 2 | | | yes |
//! | F, H | 1, 2 | | | yes |
//! | S, W | 1, 2 | | 3, 4 | no |
//! | E, G | 1, 2 | | 3, 4 | yes |
//! | X, T, O, U, B, K | | | | |
//!
//! Contents:
//! - `pub const Source = enum(u8) { none, independent, controlled }`
//! - `pub const Pins = struct`
//! - `pub fn of(kind: DeviceKind) Pins`
//! - `pub fn isTransistor(kind: DeviceKind) bool`, `pub fn isPart(kind: DeviceKind) bool`
//! - `pub fn carries(kind: DeviceKind, pin: usize) bool`, `pub fn reads(kind: DeviceKind) bool`

const std = @import("std");
const netlist = @import("netlist.zig");

const DeviceKind = netlist.DeviceKind;

/// Whether a device is a source, and what sets it.
pub const Source = enum(u8) { none, independent, controlled };

/// What the pins of a device of one kind do, by their place on its card.
pub const Pins = struct {
    /// The two pins its current passes through, in card order; null: a box.
    path: ?[2]u8 = null,
    /// The side pin a drawing turns left or right (a gate, a base).
    gate: ?u8 = null,
    /// The first of its control pins, which read a net past its path (a
    /// switch's pair, a voltage-controlled source's); null: none.
    control: ?u8 = null,
    /// Its path's two ends are told apart (a source's plus, a diode's
    /// anode, a drain); a resistor's are not.
    polar: bool = false,
    source: Source = .none,
    /// Its terminals' names in a `*@` line, in card order; a pin past them
    /// goes by its number from 1.
    names: []const []const u8 = &.{},
};

/// The pins of a device of `kind`.
pub fn of(kind: DeviceKind) Pins {
    return switch (kind) {
        .mosfet, .jfet, .mesfet => .{ .path = .{ 0, 2 }, .gate = 1, .polar = true, .names = &.{ "d", "g", "s", "b" } },
        .bjt => .{ .path = .{ 0, 2 }, .gate = 1, .polar = true, .names = &.{ "c", "b", "e", "s" } },
        .resistor, .capacitor, .inductor => .{ .path = .{ 0, 1 }, .names = &.{ "a", "b" } },
        .diode => .{ .path = .{ 0, 1 }, .polar = true, .names = &.{ "a", "b" } },
        .vsource, .isource => .{ .path = .{ 0, 1 }, .polar = true, .source = .independent, .names = &.{ "p", "n" } },
        .cccs, .ccvs => .{ .path = .{ 0, 1 }, .polar = true, .source = .controlled },
        .vswitch, .cswitch => .{ .path = .{ 0, 1 }, .control = 2, .names = &.{ "a", "b" } },
        .vcvs, .vccs => .{ .path = .{ 0, 1 }, .control = 2, .polar = true, .source = .controlled },
        .coupling, .behavioral, .tline, .ltra, .urc, .subckt => .{},
    };
}

/// A path with a gate.
pub fn isTransistor(kind: DeviceKind) bool {
    return of(kind).gate != null;
}

/// A path with no gate: a resistor, a capacitor, an inductor, a diode, a
/// source, a switch.
pub fn isPart(kind: DeviceKind) bool {
    const p = of(kind);
    return p.path != null and p.gate == null;
}

/// Whether pin `pin` of a device of `kind` passes current: a pin of a
/// transistor's path (its gate and body do not), a pin before the control
/// pair of a device that has one, any pin of anything else.
pub fn carries(kind: DeviceKind, pin: usize) bool {
    const p = of(kind);
    if (p.gate != null) return pin == p.path.?[0] or pin == p.path.?[1];
    return pin < p.control orelse return true;
}

/// Whether a device of `kind` has a pin that reads a net: a gate or a
/// control pair. What it drives follows what it reads.
pub fn reads(kind: DeviceKind) bool {
    const p = of(kind);
    return p.gate != null or p.control != null;
}

test "device: each kind's pins are its SPICE card's" {
    // Oracle: the SPICE card of each element (ngspice manual, ch. 2 to 11):
    // `M d g s b`, `Q c b e [s]`, `R n1 n2`, `S n+ n- nc+ nc-`,
    // `E n+ n- nc+ nc-`, `F n+ n- vname`, `X nodes… subckt`.
    const expectEqual = std.testing.expectEqual;
    try expectEqual([2]u8{ 0, 2 }, of(.mosfet).path.?);
    try expectEqual(1, of(.bjt).gate.?);
    try std.testing.expectEqualStrings("e", of(.bjt).names[2]);
    try expectEqual([2]u8{ 0, 1 }, of(.resistor).path.?);
    try expectEqual(null, of(.resistor).gate);
    try expectEqual(2, of(.vswitch).control.?);
    try expectEqual(2, of(.vccs).control.?);
    try expectEqual(null, of(.cccs).control);
    try expectEqual(null, of(.subckt).path);
    try std.testing.expect(isTransistor(.jfet) and !isTransistor(.diode) and !isTransistor(.subckt));
    try std.testing.expect(isPart(.capacitor) and isPart(.vcvs) and !isPart(.mosfet) and !isPart(.tline));
    // A transistor's body and gate pass no current; a control pair none.
    try std.testing.expect(carries(.mosfet, 0) and carries(.mosfet, 2) and !carries(.mosfet, 1) and !carries(.mosfet, 3));
    try std.testing.expect(carries(.vswitch, 1) and !carries(.vswitch, 2) and carries(.resistor, 1) and carries(.subckt, 5));
    try std.testing.expect(reads(.bjt) and reads(.vcvs) and !reads(.resistor) and !reads(.ccvs));
    try expectEqual(Source.independent, of(.isource).source);
    try expectEqual(Source.controlled, of(.ccvs).source);
    // Told apart: a diode's ends, not a switch's.
    try std.testing.expect(of(.diode).polar and !of(.cswitch).polar and !of(.inductor).polar);
}
