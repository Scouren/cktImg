//! Recognized subcircuit glyphs shared by native drawings and Schemify.
//!
//! Human Rules:
//! - block_symbols.1 (choice) A known amplifier or logic gate uses its
//!   conventional glyph when every named port has an unambiguous role.
//!   AG807/750/806 show amplifier/comparator triangles; AG1044/438/1070/1076
//!   show inversion bubbles and logic gates. An unfamiliar name or extra
//!   control stays a box: AG1070's charge pumps and AG1677's bias ports.
//!   `identify`
//! - block_symbols.2 (invariant) A glyph preserves every SPICE port, in
//!   order, including supply pins. Inputs enter left, output exits right,
//!   supply above and ground below. A caller symbol or explicit side hint
//!   takes precedence in the caller. `draw`
//!
//! Cold, bounded work: at most five ports, once per registered symbol.
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
pub const Shape = enum(u8) { box, amplifier, comparator, buffer, inverter, and_gate, nand_gate, or_gate, nor_gate, xor_gate, xnor_gate };

/// Terminals and strokes allocated in `arena`, which the caller releases
/// together. `ports` and its strings must outlive the returned drawing.
pub const Drawing = struct { terminals: []const lib.Terminal, ops: []const DrawOp };

const Role = enum(u3) { supply, ground, positive, negative, input, second, output, unknown };
const ports_max = 5;

/// The conventional glyph for a whole, case-insensitive family name and a
/// complete port contract; `.box` for unknown names, duplicate roles or extra
/// controls. No truth table is inferred from a subcircuit's implementation.
pub fn identify(name: []const u8, ports: []const []const u8) Shape {
    if (ports.len < 2 or ports.len > ports_max) return .box;
    const aliases = .{
        .{ "opamp icm_opamp_vdd_vss voltage_amplifier", Shape.amplifier },
        .{ "comparator icm_ideal_comparator_vdd", Shape.comparator },
        .{ "buffer buf", Shape.buffer },
        .{ "inverter inv", Shape.inverter },
        .{ "and_gate and", Shape.and_gate },
        .{ "nand_gate nand", Shape.nand_gate },
        .{ "or_gate or", Shape.or_gate },
        .{ "nor_gate nor", Shape.nor_gate },
        .{ "xor_gate xor", Shape.xor_gate },
        .{ "xnor_gate xnor", Shape.xnor_gate },
    };
    const shape: Shape = found: {
        inline for (aliases) |row| if (oneOf(name, row[0])) break :found row[1];
        return .box;
    };
    var seen: [8]bool = @splat(false);
    for (ports) |port| {
        const r = role(shape, ports, port);
        if (r == .unknown or seen[@backingInt(r)]) return .box;
        seen[@backingInt(r)] = true;
    }
    if (!seen[@backingInt(Role.output)]) return .box;
    const differential = shape == .comparator or (shape == .amplifier and !oneOf(name, "voltage_amplifier"));
    const valid = if (differential)
        seen[@backingInt(Role.positive)] and seen[@backingInt(Role.negative)] and !seen[@backingInt(Role.input)]
    else if (twoInputs(shape))
        seen[@backingInt(Role.input)] and seen[@backingInt(Role.second)]
    else
        seen[@backingInt(Role.input)] and !seen[@backingInt(Role.second)] and !seen[@backingInt(Role.positive)] and !seen[@backingInt(Role.negative)];
    return if (valid) shape else .box;
}

/// Draws a previously verified non-box `shape`. `pitch` is half the distance
/// between two input pins. Asserts `4 <= pitch <= 1_000_000`, two to five
/// verified ports, and a non-box shape. Allocation failure leaves arena
/// cleanup with the caller, as on success.
pub fn draw(arena: Allocator, shape: Shape, ports: []const []const u8, pitch: i32) Allocator.Error!Drawing {
    assert(shape != .box);
    assert(pitch >= 4);
    assert(pitch <= 1_000_000);
    assert(ports.len >= 2);
    assert(ports.len <= ports_max);
    const triangle = shape == .amplifier or shape == .comparator or shape == .buffer or shape == .inverter;
    const rounded = shape == .or_gate or shape == .nor_gate or shape == .xor_gate or shape == .xnor_gate;
    const exclusive = shape == .xor_gate or shape == .xnor_gate;
    const inverted = shape == .inverter or shape == .nand_gate or shape == .nor_gate or shape == .xnor_gate;
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
            .positive, .second => pitch,
            .negative => -pitch,
            .input => if (twoInputs(shape)) -pitch else 0,
            else => 0,
        };
        const side: lib.Side = switch (r) {
            .supply => .up,
            .ground => .down,
            .output => .right,
            else => .left,
        };
        const at: Pt = switch (side) {
            .up => .{ .x = 0, .y = -3 * pitch },
            .down => .{ .x = 0, .y = 3 * pitch },
            .right => .{ .x = 3 * pitch, .y = 0 },
            .left => .{ .x = -3 * pitch, .y = y },
        };
        const edge: Pt = switch (side) {
            .up, .down => .{ .x = 0, .y = (if (side == .up) @as(i32, -1) else 1) * (if (triangle) pitch else if (rounded) scale(35, pitch) else 2 * pitch) },
            .right => .{ .x = scale(if (inverted) 50 else 40, pitch), .y = 0 },
            .left => .{ .x = scale(if (rounded) -27 else -40, pitch), .y = y },
        };
        terminal.* = .{ .name = name, .at = at, .side = side };
        try ops.append(arena, .{ .line = .{ .a = at, .b = edge } });
        if (r == .positive or r == .negative) try ops.append(arena, .{ .text = .{ .at = .{ .x = scale(-30, pitch), .y = y }, .s = if (r == .positive) "+" else "-", .size = 7 } });
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
    if (shape != .amplifier and shape != .comparator) {
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
