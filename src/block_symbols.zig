//! Recognized subcircuit glyphs shared by native drawings and Schemify.
//!
//! Human Rules:
//! - block_symbols.1 (choice) A known amplifier or logic gate uses its
//!   conventional glyph when every named port has an unambiguous role.
//!   AG807/750/806 show amplifier/comparator triangles; AG1044/438/1070/1076
//!   show inversion bubbles and logic gates. An unfamiliar name or extra
//!   control stays a box: AG1070's charge pumps and AG1677's VA port.
//!   `identify`
//! - block_symbols.2 (invariant) A glyph preserves every SPICE port, in
//!   order, including supply pins. Inputs enter left, output exits right,
//!   supply above and ground below. A caller symbol or explicit side hint
//!   takes precedence in the caller. `draw`
//! - block_symbols.3 (choice) A fully differential amplifier retains two
//!   signed outputs (AG479/782). The default places positive output above
//!   negative: seven of twelve source glyphs cross input/output signs.
//!   Port order and electrical identity never change. `identify`, `draw`
//! - block_symbols.4 (habit) An otherwise complete amplifier with named
//!   VB1/VB2/VB3 bias pins retains its triangle (85 of 85 source instances,
//!   including AG1561/1661/1700/2223). Bias pins remain separate below the
//!   body; an unknown control such as AG1677's VA still keeps a box.
//!   `identify`, `draw`
//! - block_symbols.5 (choice) Known opamp/comparator families, including
//!   `comp`, may declare one input: 47/47 source glyphs retain a triangle
//!   with the matching minus, plus or unsigned input (AG1401/1432/1422).
//!   A complete single-input contract creates no missing second pin.
//!   Unknown controls, duplicate roles and mixed input contracts stay boxes.
//!   `identify`, `draw`
//! - block_symbols.6 (choice) Exact AMP/AMP1/CMP/EA family names with the
//!   same complete port contract use triangles: all 24 selected source
//!   glyphs agree (AG2553/2550/1367/1237). AMP1 is a whole name, not a
//!   prefix. ZCD remains a source box.
//!   Shape/sign evidence does not certify cached source pin coordinates.
//!   docs/research/block-aliases.md; `identify`
//! - block_symbols.7 (choice) Generic comp/comparator/CMP triangles are
//!   plain: 15/48/6 source instances have no interior step. The explicit
//!   ICM_IDEAL_COMPARATOR_VDD retains its step (AG806/809). AG1390's source
//!   box and AG1398's missing plus mark remain named disagreements; neither
//!   creates an instance-specific rendering exception. Appearance does not
//!   infer electrical function. figures/comparator_strokes.py; `identify`
//! - block_symbols.8 (choice) Exact A1/EA1/AEA names use triangles only
//!   with the same complete contract: all 39 selected source glyphs agree.
//!   Named polarity survives declaration order; AG2423 has only a negative
//!   input. Unknown controls remain boxed, including AG1752's extra Z.
//!   Every declared port remains present despite omitted source VSS ink.
//!   docs/research/remaining-amplifiers.md; `identify`, `draw`
//! - block_symbols.9 (choice) Exact AEA/ERRORAMP/ERROR_AMPLIFIER/ERROR_AMP
//!   reference contracts use unsigned triangles: all 15 source glyphs
//!   agree. VREF enters left; OUT/VEA leaves the apex. Optional VDD/VSS
//!   and one VB1/VBN/NB bias keep distinct leads. Unknown controls and
//!   ERRAMP remain boxes; AEA without VREF retains its signed contract.
//!   Declared VSS survives absent source ink; supply/bias side exceptions
//!   do not change the canonical glyph. docs/research/reference-amplifiers.md;
//!   `identify`, `draw`
//!
//! - block_symbols.10 (order: signal) Complete amplifier and reference
//!   contracts expose their unique output to placement. The 21 selected
//!   source banks face that output; contextual VEA belongs only to the
//!   complete reference shape. Digital, differential and opaque contracts
//!   supply no such certificate. docs/research/driven-banks.md; `analogOutput`
//!
//! - block_symbols.11 (choice) Three four-bias amplifier contracts and
//!   four clocked comparator contracts retain a signed triangle. All
//!   50 declared terminals stay in order, including seven undrawn VSS
//!   contacts in their source redraws. A clock is an input; VB4 alone,
//!   AG808's extra IB and incompatible caller directions stay generic.
//!   AG1242 and AG3492 motivate canonical lead clearance. See the
//!   seven-case third-ports study. `identify`, `draw`
//!
//! Cold, bounded work: at most nine ports, once per registered symbol
//! or participating placement candidate.
//! The caller owns the arena and the existing terminal/DrawOp tables.
//!
//! Contents:
//! - `pub const Shape = enum(u8)`
//! - `pub const Drawing = struct`
//! - `pub fn clockFormal(port: []const u8) bool`
//! - `pub fn identify(name: []const u8, ports: []const []const u8) Shape`
//! - `pub inline fn analogOutput(name: []const u8, ports: []const []const u8) ?u4`
//! - `pub fn draw(arena: Allocator, shape: Shape, ports: []const []const u8, pitch: i32) Allocator.Error!Drawing`

const std = @import("std");
const lib = @import("library.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Pt = lib.Pt;
const DrawOp = lib.DrawOp;

/// Appearance only; every recognized symbol remains an electrical subcircuit.
pub const Shape = enum(u8) { box, amplifier, comparator, buffer, inverter, and_gate, nand_gate, or_gate, nor_gate, xor_gate, xnor_gate, differential_amplifier, reference_amplifier, regulator_amplifier, four_bias_amplifier, clocked_comparator };

/// Terminals and strokes allocated in `arena`, which the caller releases
/// together. `ports` and its strings must outlive the returned drawing.
pub const Drawing = struct { terminals: []const lib.Terminal, ops: []const DrawOp };

const Role = enum(u4) { supply, ground, positive, negative, input, second, output, out_positive, out_negative, bias1, bias2, bias3, bias4, clock, unknown };
const ports_max = 9;

/// The conventional glyph for a whole, case-insensitive family name and a
/// complete port contract; `.box` for unknown names, duplicate roles or extra
/// controls. No truth table is inferred from a subcircuit's implementation.
pub fn identify(name: []const u8, ports: []const []const u8) Shape {
    if (ports.len < 2 or ports.len > ports_max) return .box;
    const aliases = [_]struct { names: []const u8, shape: Shape }{
        .{ .names = "opamp icm_opamp_vdd_vss voltage_amplifier amp amp1 ea cmp comp comparator a1 ea1 aea", .shape = .amplifier },
        .{ .names = "opamp_differential", .shape = .differential_amplifier },
        .{ .names = "icm_ideal_comparator_vdd", .shape = .comparator },
        .{ .names = "buffer buf", .shape = .buffer },
        .{ .names = "inverter inv", .shape = .inverter },
        .{ .names = "and_gate and", .shape = .and_gate },
        .{ .names = "nand_gate nand", .shape = .nand_gate },
        .{ .names = "or_gate or", .shape = .or_gate },
        .{ .names = "nor_gate nor", .shape = .nor_gate },
        .{ .names = "xor_gate xor", .shape = .xor_gate },
        .{ .names = "xnor_gate xnor", .shape = .xnor_gate },
    };
    const shape: Shape = found: {
        if (oneOf(name, "aea erroramp error_amplifier error_amp")) {
            for (ports) |port| if (oneOf(port, "vref")) break :found .reference_amplifier;
        }
        for (aliases) |row| if (oneOf(name, row.names)) break :found row.shape;
        return .box;
    };
    if (shape == .amplifier and ports.len == 9) return extended(.four_bias_amplifier, ports);
    if (std.ascii.eqlIgnoreCase(name, "comparator") and (ports.len == 5 or ports.len == 6)) {
        for (ports) |p| if (clockFormal(p)) return extended(.clocked_comparator, ports);
    }
    var seen: [@typeInfo(Role).@"enum".field_names.len]bool = @splat(false);
    for (ports) |port| {
        const r = role(shape, ports, port);
        if (r == .unknown or seen[@backingInt(r)]) return .box;
        seen[@backingInt(r)] = true;
    }
    const outputs = if (shape == .differential_amplifier)
        seen[@backingInt(Role.out_positive)] and seen[@backingInt(Role.out_negative)]
    else
        seen[@backingInt(Role.output)];
    if (!outputs) return .box;
    const differential = shape == .differential_amplifier or shape == .comparator or (shape == .amplifier and !oneOf(name, "voltage_amplifier"));
    const inputs = @as(u8, @intFromBool(seen[@backingInt(Role.positive)])) + @as(u8, @intFromBool(seen[@backingInt(Role.negative)])) + @as(u8, @intFromBool(seen[@backingInt(Role.input)]));
    const valid = if (differential)
        (seen[@backingInt(Role.positive)] and seen[@backingInt(Role.negative)] and !seen[@backingInt(Role.input)]) or (shape != .differential_amplifier and inputs == 1)
    else if (twoInputs(shape))
        seen[@backingInt(Role.input)] and seen[@backingInt(Role.second)]
    else
        seen[@backingInt(Role.input)] and !seen[@backingInt(Role.second)] and !seen[@backingInt(Role.positive)] and !seen[@backingInt(Role.negative)];
    return if (valid) shape else .box;
}

/// The unique output index of a complete amplifier or reference-amplifier
/// contract, or null for any other shape or incomplete declaration. The
/// index is below the nine-port limit. Borrows only for this call
/// and allocates nothing; contextual VEA does not alter generic port roles.
/// Inlines the bounded scan in both placement callers and the codegen probe.
pub inline fn analogOutput(name: []const u8, ports: []const []const u8) ?u4 {
    const reference = switch (identify(name, ports)) {
        .amplifier, .four_bias_amplifier => false,
        .reference_amplifier => true,
        else => return null,
    };
    assert(ports.len >= 2);
    assert(ports.len <= ports_max);
    for (ports, 0..) |port, i| {
        const is_output = if (reference)
            std.ascii.eqlIgnoreCase(port, "out") or std.ascii.eqlIgnoreCase(port, "vea")
        else
            lib.portRole(ports, port) == .out;
        if (is_output) return @intCast(i);
    }
    unreachable;
}

/// Draws a previously verified non-box `shape`. `pitch` is half the distance
/// between two input pins. Asserts `4 <= pitch <= 1_000_000`, two to nine
/// verified ports, and a non-box shape. Allocation failure leaves arena
/// cleanup with the caller, as on success.
pub fn draw(arena: Allocator, selected: Shape, ports: []const []const u8, pitch: i32) Allocator.Error!Drawing {
    const regulator = selected == .regulator_amplifier;
    const frame: Shape = if (regulator and ports.len == 9) .four_bias_amplifier else if (regulator) .amplifier else selected;
    const wide = frame == .four_bias_amplifier;
    const clocked = frame == .clocked_comparator;
    const shape: Shape = if (wide or clocked) .amplifier else frame;
    const radius: i32 = if (wide) 4 * pitch else 3 * pitch;
    assert(shape != .box);
    assert(pitch >= 4);
    assert(pitch <= 1_000_000);
    assert(ports.len >= 2);
    assert(ports.len <= ports_max);
    const differential = shape == .differential_amplifier;
    const triangle = differential or shape == .amplifier or shape == .comparator or shape == .buffer or shape == .inverter or shape == .reference_amplifier;
    const rounded = shape == .or_gate or shape == .nor_gate or shape == .xor_gate or shape == .xnor_gate;
    const exclusive = shape == .xor_gate or shape == .xnor_gate;
    const inverted = shape == .inverter or shape == .nand_gate or shape == .nor_gate or shape == .xnor_gate;
    const biased = for (ports) |name| {
        const r = role(frame, ports, name);
        if (r == .bias1 or r == .bias2 or r == .bias3) break true;
    } else false;
    var ops: std.ArrayList(DrawOp) = .empty;
    const outline: []const [2]i32 = if (wide)
        &.{ .{ -60, -60 }, .{ 60, 0 }, .{ -60, 60 }, .{ -60, -60 } }
    else if (triangle)
        &.{ .{ -40, -40 }, .{ 40, 0 }, .{ -40, 40 }, .{ -40, -40 } }
    else if (rounded)
        &.{ .{ -40, -40 }, .{ -15, -40 }, .{ 0, -35 }, .{ 4, -34 }, .{ 22, -20 }, .{ 40, 0 }, .{ 22, 20 }, .{ 4, 34 }, .{ 0, 35 }, .{ -15, 40 }, .{ -40, 40 }, .{ -27, 20 }, .{ -22, 0 }, .{ -27, -20 }, .{ -40, -40 } }
    else
        &.{ .{ -40, -40 }, .{ 0, -40 }, .{ 15, -37 }, .{ 28, -28 }, .{ 37, -15 }, .{ 40, 0 }, .{ 37, 15 }, .{ 28, 28 }, .{ 15, 37 }, .{ 0, 40 }, .{ -40, 40 }, .{ -40, -40 } };
    try poly(arena, &ops, outline, pitch);
    if (exclusive) try poly(arena, &ops, &.{ .{ -48, -40 }, .{ -35, -20 }, .{ -30, 0 }, .{ -35, 20 }, .{ -48, 40 } }, pitch);
    if (inverted) try ops.append(arena, .circ(scale(45, pitch), 0, scale(5, pitch)));
    if (shape == .comparator) try poly(arena, &ops, &.{ .{ -4, 5 }, .{ 1, 5 }, .{ 1, -5 }, .{ 9, -5 } }, pitch);
    const terminals = try arena.alloc(lib.Terminal, ports.len);
    for (ports, terminals) |name, *terminal| {
        const r = role(frame, ports, name);
        assert(r != .unknown);
        const y: i32 = switch (r) {
            .positive => if (regulator) -pitch else pitch,
            .negative => if (regulator) pitch else -pitch,
            .second, .out_negative => pitch,
            .out_positive => -pitch,
            .input => if (twoInputs(shape)) -pitch else 0,
            else => 0,
        };
        const side: lib.Side = switch (r) {
            .supply, .clock => .up,
            .ground, .bias1, .bias2, .bias3, .bias4 => .down,
            .output, .out_positive, .out_negative => .right,
            else => .left,
        };
        var at: Pt = switch (side) {
            .up => .{ .x = if (r == .clock) pitch else if (differential) -pitch else 0, .y = -radius },
            .down => .{ .x = switch (r) {
                .bias1 => -pitch,
                .bias2 => 0,
                .bias3 => pitch,
                .bias4 => 2 * pitch,
                else => if (biased) -2 * pitch else if (differential or clocked) -pitch else 0,
            }, .y = radius },
            .right => .{ .x = radius, .y = y },
            .left => .{ .x = -radius, .y = y },
        };
        // A sloping triangle edge moves one vertical unit per two
        // horizontal ones. Align auxiliary leads with an integer contact
        // on that edge even when the requested pitch is odd.
        if ((wide or clocked) and !side.isHorizontal()) at.x += @mod(radius - pitch - at.x, 2);
        const edge: Pt = switch (side) {
            .up, .down => .{ .x = at.x, .y = (if (side == .up) @as(i32, -1) else 1) * (if (triangle) @divTrunc(radius - pitch - at.x, 2) else if (rounded) scale(35, pitch) else 2 * pitch) },
            .right => .{ .x = scale(if (differential) 0 else if (inverted) 50 else if (wide) 60 else 40, pitch), .y = y },
            .left => .{ .x = scale(if (rounded) -27 else if (wide) -60 else -40, pitch), .y = y },
        };
        terminal.* = .{ .name = name, .at = at, .side = side };
        try ops.append(arena, .{ .line = .{ .a = at, .b = edge } });
        if (r == .positive or r == .negative) try ops.append(arena, .{ .text = .{ .at = .{ .x = scale(if (wide) -50 else -30, pitch), .y = y }, .s = if (r == .positive) "+" else "-", .size = 7 } });
        if (r == .out_positive or r == .out_negative) try ops.append(arena, .{ .text = .{ .at = .{ .x = scale(-10, pitch), .y = y }, .s = if (r == .out_positive) "+" else "-", .size = 7 } });
    }
    assert(terminals.len == ports.len);
    return .{ .terminals = terminals, .ops = ops.items };
}

/// True for the two measured clock formal spellings on clocked comparators.
/// PININFO directions are checked against the control's input role in Schemify.
pub fn clockFormal(port: []const u8) bool {
    return oneOf(port, "clk phi3");
}

// ---- private ----

fn extended(shape: Shape, ports: []const []const u8) Shape {
    var seen: std.EnumSet(Role) = .empty;
    for (ports) |p| {
        const r = extendedRole(p);
        if (r == .unknown or seen.contains(r)) return .box;
        seen.insert(r);
    }
    var want = std.EnumSet(Role).initMany(&.{ .ground, .positive, .negative, .output });
    if (shape == .four_bias_amplifier) {
        for ([_]Role{ .supply, .bias1, .bias2, .bias3, .bias4 }) |r| want.insert(r);
    } else {
        want.insert(.clock);
        if (ports.len == 6) want.insert(.supply);
    }
    return if (seen.eql(want)) shape else .box;
}

fn extendedRole(port: []const u8) Role {
    const names = [_]struct { []const u8, Role }{
        .{ "vdd", .supply },      .{ "vss", .ground },    .{ "inp vp", .positive },
        .{ "inn vn", .negative }, .{ "out vo", .output }, .{ "vb1", .bias1 },
        .{ "vb2", .bias2 },       .{ "vb3", .bias3 },     .{ "vb4", .bias4 },
    };
    for (names) |entry| if (oneOf(port, entry[0])) return entry[1];
    return if (clockFormal(port)) .clock else .unknown;
}

fn twoInputs(s: Shape) bool {
    return switch (s) {
        .and_gate, .nand_gate, .or_gate, .nor_gate, .xor_gate, .xnor_gate => true,
        else => false,
    };
}

fn oneOf(name: []const u8, words: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, words, ' ');
    while (it.next()) |word| if (std.ascii.eqlIgnoreCase(name, word)) return true;
    return false;
}

fn role(shape: Shape, ports: []const []const u8, name: []const u8) Role {
    if (shape == .four_bias_amplifier or shape == .clocked_comparator) return extendedRole(name);
    if (shape == .reference_amplifier) {
        if (oneOf(name, "vdd")) return .supply;
        if (oneOf(name, "vss")) return .ground;
        if (oneOf(name, "vref")) return .input;
        if (oneOf(name, "out vea")) return .output;
        return if (oneOf(name, "vb1 vbn nb")) .bias1 else .unknown;
    }
    if (lib.named(name, .role)) |named| switch (named) {
        .supply => return .supply,
        .ground => return .ground,
        else => {},
    };
    if (shape == .amplifier or shape == .comparator) {
        if (oneOf(name, "vb vb1 bias")) return .bias1;
        if (oneOf(name, "vb2")) return .bias2;
        if (oneOf(name, "vb3")) return .bias3;
    }
    if (shape == .differential_amplifier) {
        if (oneOf(name, "vop vo+ outp out+")) return .out_positive;
        if (oneOf(name, "von vo- outn out-")) return .out_negative;
        if (lib.portRole(ports, name) == .out) return .unknown;
    }
    if (shape != .amplifier and shape != .differential_amplifier and shape != .comparator) {
        if (oneOf(name, "a")) return .input;
        if (twoInputs(shape) and oneOf(name, "b")) return .second;
        return if (oneOf(name, "y")) .output else .unknown;
    }
    return switch (lib.portRole(ports, name)) {
        .inp => .positive,
        .inn => .negative,
        .in => .input,
        .out => .output,
        else => .unknown,
    };
}

fn scale(n: i32, pitch: i32) i32 {
    return @divTrunc(n * pitch, 20);
}

fn poly(a: Allocator, ops: *std.ArrayList(DrawOp), points: []const [2]i32, pitch: i32) Allocator.Error!void {
    const ps = try a.alloc(Pt, points.len);
    for (points, ps) |p, *out| out.* = .{ .x = scale(p[0], pitch), .y = scale(p[1], pitch) };
    try ops.append(a, .{ .polyline = ps });
}
