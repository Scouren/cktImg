//! Bounded source-derived center-tapped winding, built once per class.
//!
//! Human Rules:
//! - center_tap.1 (invariant) N1/N2 are the outer ends; N3 leaves their
//!   connected midpoint. All 19 source glyphs retain two open, looped
//!   winding paths and one filled dot. No ordinary inductor or transformer
//!   is inferred from the subcircuit name. `draw`
//! - center_tap.2 (choice) At pitch 20 the integer winding is within
//!   0.702219516315 source units of the measured cubic point-set in both
//!   directions. This bound covers winding ink only; radius 4 approximates
//!   the source 3.77907 dot, and AG1190 has longer outer leads. Other pitches
//!   add integer rescaling error. figures/center_tap_curves.py; `draw`
//!
//! Data: the cold caller supplies three port names, terminal storage and
//! its arena/list. This owner fills the ordered terminals and appends seven
//! operations; two 61-point slices live in the same arena. Coordinates use
//! one immutable signed-byte table, not per-instance retained metadata.
//! The table count is bounded by the renderer's 64-point capacity. Likely
//! curve, lead and dot changes stay here; recognition stays in block_symbols.
//! No placement scan, dispatch abstraction or runtime speed claim is added.
//!
//! Contents:
//! - `pub fn draw(arena: Allocator, ports: []const []const u8, pitch: i32, terminals: []lib.Terminal, ops: *std.ArrayList(lib.DrawOp)) Allocator.Error!void`

const std = @import("std");
const lib = @import("library.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const winding_points_max = 64;
const operation_count = 7;

// Exact source-derived table; see center_tap_curves_cases.json. The second
// source path is this same curve translated by (50, 0).
const winding = [_][2]i8{
    .{ -45, 0 },
    .{ -37, 0 },
    .{ -37, -1 },
    .{ -36, -4 },
    .{ -35, -5 },
    .{ -35, -6 },
    .{ -34, -7 },
    .{ -33, -7 },
    .{ -31, -5 },
    .{ -31, -3 },
    .{ -30, 0 },
    .{ -30, 5 },
    .{ -32, 7 },
    .{ -33, 7 },
    .{ -33, 6 },
    .{ -34, 5 },
    .{ -34, 3 },
    .{ -33, 0 },
    .{ -33, -3 },
    .{ -31, -5 },
    .{ -31, -6 },
    .{ -30, -6 },
    .{ -29, -7 },
    .{ -27, -7 },
    .{ -27, -6 },
    .{ -26, -5 },
    .{ -25, -3 },
    .{ -24, 0 },
    .{ -24, 5 },
    .{ -26, 7 },
    .{ -27, 7 },
    .{ -27, 6 },
    .{ -28, 5 },
    .{ -28, 3 },
    .{ -27, 0 },
    .{ -27, -3 },
    .{ -25, -5 },
    .{ -25, -6 },
    .{ -24, -6 },
    .{ -23, -7 },
    .{ -22, -7 },
    .{ -20, -5 },
    .{ -19, -3 },
    .{ -18, 0 },
    .{ -18, 5 },
    .{ -19, 6 },
    .{ -19, 7 },
    .{ -20, 7 },
    .{ -22, 5 },
    .{ -22, 0 },
    .{ -21, -3 },
    .{ -20, -5 },
    .{ -20, -6 },
    .{ -19, -6 },
    .{ -19, -7 },
    .{ -17, -7 },
    .{ -15, -5 },
    .{ -15, -4 },
    .{ -14, -1 },
    .{ -14, 0 },
    .{ -5, 0 },
};

comptime {
    assert(winding.len < winding_points_max);
    assert(@sizeOf(@TypeOf(winding)) == 122);
}

/// Appends a verified three-port center-tapped glyph to caller-owned tables.
/// `ports` contains N1/N2/N3 exactly once; its strings outlive the drawing.
/// The caller owns arena cleanup on success or allocation failure. `pitch`
/// is half the library unit, between 4 and 1_000_000 inclusive.
pub fn draw(arena: Allocator, ports: []const []const u8, pitch: i32, terminals: []lib.Terminal, ops: *std.ArrayList(lib.DrawOp)) Allocator.Error!void {
    assert(ports.len == 3);
    assert(terminals.len == ports.len);
    assert(pitch >= 4 and pitch <= 1_000_000);
    const points = try arena.alloc(lib.Pt, 2 * winding.len);
    try ops.ensureUnusedCapacity(arena, operation_count);
    for (0..2) |half| {
        const offset: i32 = @as(i32, @intCast(half)) * 50;
        for (winding, points[half * winding.len ..][0..winding.len]) |p, *out| {
            out.* = .{ .x = scale(@as(i32, p[0]) + offset, pitch), .y = scale(p[1], pitch) };
        }
    }
    var seen: u3 = 0;
    for (ports, terminals) |name, *terminal| {
        const index: u2 = if (std.ascii.eqlIgnoreCase(name, "n1")) 0 else if (std.ascii.eqlIgnoreCase(name, "n2")) 1 else if (std.ascii.eqlIgnoreCase(name, "n3")) 2 else unreachable;
        const bit = @as(u3, 1) << index;
        assert(seen & bit == 0);
        seen |= bit;
        const canonical = [_]lib.Pt{ .{ .x = -50, .y = 0 }, .{ .x = 50, .y = 0 }, .{ .x = 0, .y = 20 } };
        const sides = [_]lib.Side{ .left, .right, .down };
        terminal.* = .{ .name = name, .at = .{ .x = scale(canonical[index].x, pitch), .y = scale(canonical[index].y, pitch) }, .side = sides[index] };
    }
    assert(seen == 7);
    ops.appendSliceAssumeCapacity(&.{
        .{ .polyline = points[0..winding.len] },
        .{ .polyline = points[winding.len..] },
        .ln(scale(-50, pitch), 0, scale(-45, pitch), 0),
        .ln(scale(45, pitch), 0, scale(50, pitch), 0),
        .ln(scale(-5, pitch), 0, scale(5, pitch), 0),
        .ln(0, 0, 0, scale(20, pitch)),
        .{ .filled_circle = .{ .c = .zero, .r = @max(1, scale(4, pitch)) } },
    });
}

// ---- private ----

fn scale(value: i32, pitch: i32) i32 {
    return @divTrunc(value * pitch, 20);
}
