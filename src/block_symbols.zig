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
//!   prefix. Generic A1 remains unrecognized; ZCD is a source box.
//!   Shape/sign evidence does not certify cached source pin coordinates.
//!   docs/research/block-aliases.md; `identify`
//! - block_symbols.7 (choice) Generic comp/comparator/CMP triangles are
//!   plain: 15/48/6 source instances have no interior step. The explicit
//!   ICM_IDEAL_COMPARATOR_VDD retains its step (AG806/809). AG1390's source
//!   box and AG1398's missing plus mark remain named disagreements; neither
//!   creates an instance-specific rendering exception. Appearance does not
//!   infer electrical function. figures/comparator_strokes.py; `identify`
//!
//! Cold, bounded work: at most eight ports, once per registered symbol.
//! The caller owns the arena and the existing terminal/DrawOp tables.
//!
//! Contents:
//! - `pub const Shape = enum(u8)`
//! - `pub const Drawing = struct`
//! - `pub fn identify(name: []const u8, ports: []const []const u8) Shape`
//! - `pub fn draw(arena: Allocator, shape: Shape, ports: []const []const u8, pitch: i32) Allocator.Error!Drawing`

const std = @import("std");
const lib = @import("library.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Pt = lib.Pt;
const DrawOp = lib.DrawOp;

/// Appearance only; every recognized symbol remains an electrical subcircuit.
pub const Shape = enum(u8) { box, amplifier, comparator, buffer, inverter, and_gate, nand_gate, or_gate, nor_gate, xor_gate, xnor_gate, differential_amplifier };

/// Terminals and strokes allocated in `arena`, which the caller releases
/// together. `ports` and its strings must outlive the returned drawing.
pub const Drawing = struct { terminals: []const lib.Terminal, ops: []const DrawOp };

const Role = enum(u4) { supply, ground, positive, negative, input, second, output, out_positive, out_negative, bias1, bias2, bias3, unknown };
const ports_max = 8;

/// The conventional glyph for a whole, case-insensitive family name and a
/// complete port contract; `.box` for unknown names, duplicate roles or extra
/// controls. No truth table is inferred from a subcircuit's implementation.
pub fn identify(name: []const u8, ports: []const []const u8) Shape {
    if (ports.len < 2 or ports.len > ports_max) return .box;
    const aliases = [_]struct { names: []const u8, shape: Shape }{
        .{ .names = "opamp icm_opamp_vdd_vss voltage_amplifier amp amp1 ea cmp comp comparator", .shape = .amplifier },
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
        for (aliases) |row| if (oneOf(name, row.names)) break :found row.shape;
        return .box;
    };
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

/// Draws a previously verified non-box `shape`. `pitch` is half the distance
/// between two input pins. Asserts `4 <= pitch <= 1_000_000`, two to eight
/// verified ports, and a non-box shape. Allocation failure leaves arena
/// cleanup with the caller, as on success.
pub fn draw(arena: Allocator, shape: Shape, ports: []const []const u8, pitch: i32) Allocator.Error!Drawing {
    assert(shape != .box);
    assert(pitch >= 4);
    assert(pitch <= 1_000_000);
    assert(ports.len >= 2);
    assert(ports.len <= ports_max);
    const differential = shape == .differential_amplifier;
    const triangle = differential or shape == .amplifier or shape == .comparator or shape == .buffer or shape == .inverter;
    const rounded = shape == .or_gate or shape == .nor_gate or shape == .xor_gate or shape == .xnor_gate;
    const exclusive = shape == .xor_gate or shape == .xnor_gate;
    const inverted = shape == .inverter or shape == .nand_gate or shape == .nor_gate or shape == .xnor_gate;
    const biased = for (ports) |name| {
        if (oneOf(name, "vb vb1 vb2 vb3 bias")) break true;
    } else false;
    var ops: std.ArrayList(DrawOp) = .empty;
    const outline: []const [2]i32 = if (triangle)
        &.{ .{ -40, -40 }, .{ 40, 0 }, .{ -40, 40 }, .{ -40, -40 } }
    else if (rounded)
        &.{ .{ -40, -40 }, .{ -15, -40 }, .{ 4, -34 }, .{ 22, -20 }, .{ 40, 0 }, .{ 22, 20 }, .{ 4, 34 }, .{ -15, 40 }, .{ -40, 40 }, .{ -27, 20 }, .{ -22, 0 }, .{ -27, -20 }, .{ -40, -40 } }
    else
        &.{ .{ -40, -40 }, .{ 0, -40 }, .{ 15, -37 }, .{ 28, -28 }, .{ 37, -15 }, .{ 40, 0 }, .{ 37, 15 }, .{ 28, 28 }, .{ 15, 37 }, .{ 0, 40 }, .{ -40, 40 }, .{ -40, -40 } };
    try poly(arena, &ops, outline, pitch);
    if (exclusive) try poly(arena, &ops, &.{ .{ -48, -40 }, .{ -35, -20 }, .{ -30, 0 }, .{ -35, 20 }, .{ -48, 40 } }, pitch);
    if (inverted) try ops.append(arena, .circ(scale(45, pitch), 0, scale(5, pitch)));
    if (shape == .comparator) try poly(arena, &ops, &.{ .{ -4, 5 }, .{ 1, 5 }, .{ 1, -5 }, .{ 9, -5 } }, pitch);
    const terminals = try arena.alloc(lib.Terminal, ports.len);
    for (ports, terminals) |name, *terminal| {
        const r = role(shape, ports, name);
        assert(r != .unknown);
        const y: i32 = switch (r) {
            .positive, .second, .out_negative => pitch,
            .negative, .out_positive => -pitch,
            .input => if (twoInputs(shape)) -pitch else 0,
            else => 0,
        };
        const side: lib.Side = switch (r) {
            .supply => .up,
            .ground, .bias1, .bias2, .bias3 => .down,
            .output, .out_positive, .out_negative => .right,
            else => .left,
        };
        const at: Pt = switch (side) {
            .up => .{ .x = if (differential) -pitch else 0, .y = -3 * pitch },
            .down => .{ .x = switch (r) {
                .bias1 => -pitch,
                .bias2 => 0,
                .bias3 => pitch,
                else => if (biased) -2 * pitch else if (differential) -pitch else 0,
            }, .y = 3 * pitch },
            .right => .{ .x = 3 * pitch, .y = y },
            .left => .{ .x = -3 * pitch, .y = y },
        };
        const edge: Pt = switch (side) {
            .up, .down => .{ .x = at.x, .y = (if (side == .up) @as(i32, -1) else 1) * (if (triangle) @divTrunc(2 * pitch - at.x, 2) else if (rounded) scale(35, pitch) else 2 * pitch) },
            .right => .{ .x = scale(if (differential) 0 else if (inverted) 50 else 40, pitch), .y = y },
            .left => .{ .x = scale(if (rounded) -27 else -40, pitch), .y = y },
        };
        terminal.* = .{ .name = name, .at = at, .side = side };
        try ops.append(arena, .{ .line = .{ .a = at, .b = edge } });
        if (r == .positive or r == .negative) try ops.append(arena, .{ .text = .{ .at = .{ .x = scale(-30, pitch), .y = y }, .s = if (r == .positive) "+" else "-", .size = 7 } });
        if (r == .out_positive or r == .out_negative) try ops.append(arena, .{ .text = .{ .at = .{ .x = scale(-10, pitch), .y = y }, .s = if (r == .out_positive) "+" else "-", .size = 7 } });
    }
    assert(terminals.len == ports.len);
    return .{ .terminals = terminals, .ops = ops.items };
}

// ---- private ----

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
