//! The device model every stage reads (issue #8): what a device of a kind
//! is to its card and to a drawing. In: a device kind, a card's letter, a
//! model type. Out: which of its pins do what.
//!
//! Human Rules:
//! - device.1 (invariant) A device's pins are its SPICE card's, in card
//!   order: the two its current passes through (its **path**), a gate or
//!   base, a body, a **control** pair (ngspice manual, ch. 2 to 11).
//!   `of`
//! - device.2 (invariant) A gate, a body and a control pair pass no
//!   current: no current path of the drawing runs through them. `carries`
//! - device.3 (order: potential) A device with a path stands upright with
//!   its two ends on two rows, or lies flat between two columns. `of`
//! - device.4 (unmeasured) A transistor's gate (a base) leaves its path
//!   sideways: on an upright one it points left or right. `of`
//! - device.5 (order: signal) A device whose path its gate, its control
//!   pair or a named source's current sets stands right of what drives
//!   that control. `reads`
//!   Narrowing: a source a named source sets (F, H) is left out, as a
//!   part is; the general form admits it.
//! - device.6 (order: potential) A source that feeds a load stands with
//!   its low end down: a voltage source's minus, the pin a current source
//!   draws from. `lowEnd`
//! - device.7 (order: potential) An upright transistor has the end of its
//!   path nearer the supply on top: a p-type's source (its emitter), an
//!   n-type's drain (its collector). `sourceUp`
//! - device.8 (choice) A transistor whose `.model` card gives no type is
//!   p-type when its model's name holds `pmos`, `pfet`, `pnp`, `pjf` or
//!   `pch` or starts with `p`, n-type likewise: the name is all the deck
//!   says. `polarity`
//! - device.9 (choice) A block, a transmission line (T, O, U), a B source
//!   and a coupling (K) have no path, so none stands between two rows:
//!   the table gives them none, and a block's ports go by their names
//!   (`library.portRole`). `of`
//!
//! Contents:
//! - `pub const DeviceKind = enum(u8)`, `pub const Pins = struct`, `pub const max_nodes`
//! - `pub const Source = enum(u8) { none, independent, controlled }`
//! - `pub const Control = enum(u8) { none, pair, named }`, `pub const Polarity = enum(u8) { n, p, other }`
//! - `pub fn of(kind: DeviceKind) Pins`, `pub fn ofLetter(letter: u8) ?DeviceKind`
//! - `pub fn isTransistor(kind: DeviceKind) bool`, `pub fn isPart(kind: DeviceKind) bool`
//! - `pub fn carries(kind: DeviceKind, pin: usize) bool`, `pub fn reads(kind: DeviceKind) bool`
//! - `pub fn lowEnd(kind: DeviceKind) u8`, `pub fn sourceUp(pol: Polarity) bool`
//! - `pub fn polarity(model: ?[]const u8) Polarity`

const std = @import("std");
const assert = std.debug.assert;

/// What a card is. The numbers are stable: symmetry's colours follow them.
pub const DeviceKind = enum(u8) {
    resistor,
    capacitor,
    inductor,
    coupling,
    vsource,
    isource,
    vcvs,
    vccs,
    cccs,
    ccvs,
    behavioral,
    diode,
    bjt,
    jfet,
    mesfet,
    mosfet,
    vswitch,
    cswitch,
    tline,
    ltra,
    urc,
    /// A block: `Netlist.defs[Device.def]`.
    subckt,
};

/// Whether a device is a source, and what sets it.
pub const Source = enum(u8) { none, independent, controlled };

/// What a device with no gate reads to set its path: nothing; two nets,
/// the `pair` of pins after its path on its card (`S n+ n- nc+ nc-`; a
/// behavioural `E` or `G` card leaves them out); or the current through a
/// voltage source its card names, no pin of its own (`W n+ n- vname`).
pub const Control = enum(u8) { none, pair, named };

/// A transistor's type: n- or p-channel (npn, pnp), else `.other`.
pub const Polarity = enum(u8) { n, p, other };

/// A device of one kind: its card, and what the pins on it do, by their
/// place there.
pub const Pins = struct {
    /// The lowercase letter its card starts with.
    letter: u8,
    /// How many nodes its card names, fewest and most: the optional ones
    /// stand before its model's name, or are its control pair. A block's
    /// are its subcircuit's ports: 0 here.
    nodes: [2]u8 = .{ 0, 0 },
    /// Its card names a `.model` after its nodes (`Netlist.modelType`).
    model: bool = false,
    /// The two pins its current passes through, in card order; null: a box.
    path: ?[2]u8 = null,
    /// The side pin a drawing turns left or right (a gate, a base).
    gate: ?u8 = null,
    /// A transistor's body or substrate pin, when its card names one.
    body: ?u8 = null,
    control: Control = .none,
    /// Its path's two ends are told apart (a source's plus, a diode's
    /// anode, a drain); a resistor's are not.
    polar: bool = false,
    source: Source = .none,
    /// A source of current (I, G, F); any other source sets the voltage
    /// across its path.
    current: bool = false,
    /// Direct current passes its path: not a capacitor's.
    dc: bool = true,
    /// Its terminals' names in a `*@` line, in card order; a pin past them
    /// goes by its number from 1.
    names: []const []const u8 = &.{},
};

comptime {
    assert(@sizeOf(Pins) <= 32);
}

/// The most nodes a card names (an `M` with its three optional ones); a
/// block's are not counted.
pub const max_nodes = blk: {
    var most: u8 = 0;
    for (std.enums.values(DeviceKind)) |kind| most = @max(most, of(kind).nodes[1]);
    break :blk most;
};

/// The row of a device of `kind`: the table, one prong per kind.
pub fn of(kind: DeviceKind) Pins {
    // Literal rows in a switch, not a load from an array: a caller's test
    // of one column then folds to a compare on the kind, as the switch it
    // replaced did (the residue probe; an array costs a load per test).
    return switch (kind) {
        .resistor => .{ .letter = 'r', .nodes = .{ 2, 2 }, .path = .{ 0, 1 }, .names = &.{ "a", "b" } },
        .capacitor => .{ .letter = 'c', .nodes = .{ 2, 2 }, .path = .{ 0, 1 }, .dc = false, .names = &.{ "a", "b" } },
        .inductor => .{ .letter = 'l', .nodes = .{ 2, 2 }, .path = .{ 0, 1 }, .names = &.{ "a", "b" } },
        .coupling => .{ .letter = 'k' },
        .vsource => .{ .letter = 'v', .nodes = .{ 2, 2 }, .path = .{ 0, 1 }, .polar = true, .source = .independent, .names = &.{ "p", "n" } },
        .isource => .{ .letter = 'i', .nodes = .{ 2, 2 }, .path = .{ 0, 1 }, .polar = true, .source = .independent, .current = true, .names = &.{ "p", "n" } },
        .vcvs => .{ .letter = 'e', .nodes = .{ 2, 4 }, .path = .{ 0, 1 }, .control = .pair, .polar = true, .source = .controlled },
        .vccs => .{ .letter = 'g', .nodes = .{ 2, 4 }, .path = .{ 0, 1 }, .control = .pair, .polar = true, .source = .controlled, .current = true },
        .cccs => .{ .letter = 'f', .nodes = .{ 2, 2 }, .path = .{ 0, 1 }, .control = .named, .polar = true, .source = .controlled, .current = true },
        .ccvs => .{ .letter = 'h', .nodes = .{ 2, 2 }, .path = .{ 0, 1 }, .control = .named, .polar = true, .source = .controlled },
        .behavioral => .{ .letter = 'b', .nodes = .{ 2, 2 } },
        .diode => .{ .letter = 'd', .nodes = .{ 2, 3 }, .model = true, .path = .{ 0, 1 }, .polar = true, .names = &.{ "a", "b" } },
        .bjt => .{ .letter = 'q', .nodes = .{ 3, 5 }, .model = true, .path = .{ 0, 2 }, .gate = 1, .body = 3, .polar = true, .names = &.{ "c", "b", "e", "s" } },
        .jfet => .{ .letter = 'j', .nodes = .{ 3, 3 }, .model = true, .path = .{ 0, 2 }, .gate = 1, .polar = true, .names = &.{ "d", "g", "s" } },
        .mesfet => .{ .letter = 'z', .nodes = .{ 3, 3 }, .model = true, .path = .{ 0, 2 }, .gate = 1, .polar = true, .names = &.{ "d", "g", "s" } },
        .mosfet => .{ .letter = 'm', .nodes = .{ 4, 7 }, .model = true, .path = .{ 0, 2 }, .gate = 1, .body = 3, .polar = true, .names = &.{ "d", "g", "s", "b" } },
        .vswitch => .{ .letter = 's', .nodes = .{ 4, 4 }, .path = .{ 0, 1 }, .control = .pair, .names = &.{ "a", "b" } },
        .cswitch => .{ .letter = 'w', .nodes = .{ 2, 2 }, .path = .{ 0, 1 }, .control = .named, .names = &.{ "a", "b" } },
        .tline => .{ .letter = 't', .nodes = .{ 4, 4 } },
        .ltra => .{ .letter = 'o', .nodes = .{ 4, 4 } },
        .urc => .{ .letter = 'u', .nodes = .{ 3, 3 } },
        .subckt => .{ .letter = 'x' },
    };
}

/// The kind of a card that starts with lowercase `letter`; null for a
/// letter no card of the table starts with.
pub fn ofLetter(letter: u8) ?DeviceKind {
    inline for (comptime std.enums.values(DeviceKind)) |kind| if (letter == comptime of(kind).letter) return kind;
    return null;
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

/// Whether pin `pin` of a device of `kind` passes current: a pin of its
/// path, for a device with a side pin on its card (a gate, a body, a
/// control pair pass none); any pin of anything else.
pub fn carries(kind: DeviceKind, pin: usize) bool {
    const p = of(kind);
    const side = p.gate != null or p.control == .pair;
    return !side or pin == p.path.?[0] or pin == p.path.?[1];
}

/// Whether something a device of `kind` reads sets its path: a gate, a
/// control pair, a named source. What it drives follows what it reads.
pub fn reads(kind: DeviceKind) bool {
    const p = of(kind);
    return switch (p.control) {
        .none => p.gate != null,
        .pair => true,
        // Narrowing: a source a named source sets (F, H) is left out, as
        // a part is; the general form admits it.
        .named => p.source == .none,
    };
}

/// The end of a source's path at the lower potential when it feeds a load,
/// the one its current enters by: a voltage source's second pin (its
/// minus), a current source's first (the one it draws from). Asserts that
/// `kind` is a source.
pub fn lowEnd(kind: DeviceKind) u8 {
    const p = of(kind);
    assert(p.source != .none);
    return p.path.?[@intFromBool(!p.current)];
}

/// A transistor's type from its model's type, or from its model's name
/// when no `.model` card gives one (`Netlist.modelType`).
pub fn polarity(model: ?[]const u8) Polarity {
    const m = model orelse return .other;
    for ([_][]const u8{ "pmos", "pfet", "pnp", "pjf", "pch" }) |p| if (std.mem.indexOf(u8, m, p) != null) return .p;
    for ([_][]const u8{ "nmos", "nfet", "npn", "njf", "nch" }) |p| if (std.mem.indexOf(u8, m, p) != null) return .n;
    if (m.len > 0 and m[0] == 'p') return .p;
    if (m.len > 0 and m[0] == 'n') return .n;
    return .other;
}

/// Whether a transistor of type `pol` stands with the second end of its
/// path up: a p-type's source (its emitter) is the end nearer the supply,
/// an n-type's drain.
pub fn sourceUp(pol: Polarity) bool {
    return pol == .p;
}

test "device: each kind's pins are its SPICE card's" {
    // Oracle: the SPICE card of each element (ngspice manual, ch. 2 to 11):
    // `M d g s b`, `Q c b e [s] [tj]`, `D n+ n- [tj]`, `R n1 n2`,
    // `S n+ n- nc+ nc-`, `W n+ n- vname`, `E n+ n- nc+ nc-`,
    // `F n+ n- vname`, `X nodes… subckt`.
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;
    try expectEqual([2]u8{ 0, 2 }, of(.mosfet).path.?);
    try expectEqual(1, of(.bjt).gate.?);
    try expectEqual(3, of(.mosfet).body.?);
    try expectEqual(null, of(.jfet).body);
    try std.testing.expectEqualStrings("e", of(.bjt).names[2]);
    try expectEqual([2]u8{ 0, 1 }, of(.resistor).path.?);
    try expectEqual(null, of(.resistor).gate);
    try expect(of(.vswitch).control == .pair and of(.vccs).control == .pair);
    try expect(of(.cswitch).control == .named and of(.cccs).control == .named);
    try expectEqual(null, of(.subckt).path);
    try expect(isTransistor(.jfet) and !isTransistor(.diode) and !isTransistor(.subckt));
    try expect(isPart(.capacitor) and isPart(.vcvs) and !isPart(.mosfet) and !isPart(.tline));
    // A transistor's body and gate pass no current; a control pair none.
    try expect(carries(.mosfet, 0) and carries(.mosfet, 2) and !carries(.mosfet, 1) and !carries(.mosfet, 3));
    try expect(carries(.vswitch, 1) and !carries(.vswitch, 2) and carries(.resistor, 1) and carries(.subckt, 5));
    try expect(carries(.cswitch, 1) and !carries(.vcvs, 3) and carries(.ccvs, 1));
    try expect(reads(.bjt) and reads(.vcvs) and reads(.cswitch) and !reads(.resistor) and !reads(.ccvs));
    try expect(of(.isource).source == .independent and of(.ccvs).source == .controlled);
    // Told apart: a diode's ends, not a switch's.
    try expect(of(.diode).polar and !of(.cswitch).polar and !of(.inductor).polar);
    // `V n+ n-` raises n+ over n-; `I n+ n-` draws from n+.
    try expect(lowEnd(.vsource) == 1 and lowEnd(.isource) == 0);
    try expect(!of(.capacitor).dc and of(.inductor).dc);
    // A round trip, every kind through its letter and back.
    for (std.enums.values(DeviceKind)) |kind| try expectEqual(kind, ofLetter(of(kind).letter).?);
    for ("anpy0R") |letter| try expectEqual(null, ofLetter(letter));
    try expectEqual([2]u8{ 2, 3 }, of(.diode).nodes);
    try expectEqual([2]u8{ 3, 5 }, of(.bjt).nodes);
    try expectEqual([2]u8{ 2, 4 }, of(.vcvs).nodes);
    try expectEqual(7, max_nodes);
    try expect(of(.jfet).model and of(.diode).model and !of(.resistor).model and !of(.subckt).model);
}

test "device: a model's type is its polarity, and a p-type stands source up" {
    // Oracle: the ngspice `.model` types and the PDK names the fixtures use.
    const expect = std.testing.expect;
    try expect(polarity("pmos") == .p and polarity("pjf") == .p and polarity("sky130_fd_pr__pfet_01v8") == .p);
    try expect(polarity("npn") == .n and polarity("sky130_fd_pr__nfet_01v8") == .n);
    try expect(polarity("d1n4148") == .other and polarity(null) == .other);
    try expect(sourceUp(.p) and !sourceUp(.n) and !sourceUp(.other));
}
