//! The deck's geometry lines (steering rung 4): exact coordinates and
//! orientation, and where a device's name goes.
//!
//!     *@ at M5 6 4.5 R90        the class origin at (6, 4.5) symbol units
//!     *@ refdes M5 left         its name left of it
//!
//! Human Rules:
//! - pinned.1 (invariant) A device with an `at` line has its class origin
//!   at the line's coordinates, in units of the symbol set's `unit`
//!   (rounded to the nearest whole drawing unit, the frame `Placed` uses),
//!   turned as its word says when it names one: the user's word. `read`
//! - pinned.2 (invariant) Of two lines on one device, the preferred stands
//!   (`hints.applyOrder`). `read`, `sides`
//! - pinned.3 (invariant) A `refdes` line puts the device's name on the
//!   side it names. `sides`
//! - pinned.4 (invariant) A line that cannot hold is refused with its
//!   verdict, and the device is laid as without it: a name the deck lacks,
//!   a device not drawn, a coordinate not finite or past 1e6 units, a word
//!   that is no turn or side. An `at` whose symbol would overlap another's
//!   is dropped (sketch.13). `read`, `sides`
//!
//! Contents:
//! - `pub const At = struct`
//! - `pub fn read(arena: Allocator, nl: *const Netlist, unit: i32, drawn: []const bool, verdicts: []?Verdict) Allocator.Error![]?At`
//! - `pub fn sides(arena: Allocator, nl: *const Netlist, verdicts: []?Verdict) Allocator.Error![]?Side`
//! - `pub fn orientWord(word: []const u8) ?Orient`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const hints = @import("hints.zig");
const library = @import("library.zig");

const Netlist = netlist.Netlist;
const Verdict = hints.Verdict;
const Orient = library.Orient;
const Pt = library.Pt;
const Side = library.Side;

/// Where an `at` line puts a device: its class origin, and its orientation
/// when the line names one; `line` the hint that said so, `weak` when that
/// line is a stay (`*@ weak at`): a relaid drawing's old place.
pub const At = struct { origin: Pt, orient: ?Orient, line: u32, weak: bool = false };

/// Each drawn device's `at` line, the preferred one; invalid lines rejected.
pub fn read(arena: Allocator, nl: *const Netlist, unit: i32, drawn: []const bool, verdicts: []?Verdict) Allocator.Error![]?At {
    assert(unit > 0);
    const out = try arena.alloc(?At, nl.graph.edgeCount());
    @memset(out, null);
    for (try hints.applyOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if (h.verb != .at) continue;
        const code: hints.Code = code: {
            if (h.args.len != 3 and h.args.len != 4) break :code .bad_args;
            const d = (nl.device(h.args[0]) orelse break :code .unknown_name).index();
            if (!drawn[d]) break :code .not_placeable;
            const x = std.fmt.parseFloat(f64, h.args[1]) catch null;
            const y = std.fmt.parseFloat(f64, h.args[2]) catch null;
            const o: ?Orient = if (h.args.len == 4) orientWord(h.args[3]) else null;
            if (x == null or y == null or (h.args.len == 4 and o == null) or !std.math.isFinite(x.?) or !std.math.isFinite(y.?) or @abs(x.?) > 1e6 or @abs(y.?) > 1e6) break :code .bad_args;
            const u: f64 = @floatFromInt(unit);
            out[d] = .{ .origin = .{ .x = @intFromFloat(@round(x.? * u)), .y = @intFromFloat(@round(y.? * u)) }, .orient = o, .line = @intCast(i), .weak = h.weak };
            break :code .ok;
        };
        // A device not drawn in the circuit (a driver apart): its name.
        verdicts[i] = if (code == .not_placeable) .at(code, 0) else .of(code);
    }
    return out;
}

/// Each device's `refdes` side, the preferred one; invalid lines rejected.
pub fn sides(arena: Allocator, nl: *const Netlist, verdicts: []?Verdict) Allocator.Error![]?Side {
    const out = try arena.alloc(?Side, nl.graph.edgeCount());
    @memset(out, null);
    for (try hints.applyOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if (h.verb != .refdes) continue;
        verdicts[i] = .of(code: {
            if (h.args.len != 2) break :code .bad_args;
            const d = (nl.device(h.args[0]) orelse break :code .unknown_name).index();
            out[d] = h.verb.side(Side, h.args[1]) orelse break :code .bad_args;
            break :code .ok;
        });
    }
    return out;
}

/// `R0`, `R90`, `R180`, `R270` (quarter turns clockwise, y down) and the
/// same after a mirror, `MR0` ... `MR270`, any case.
pub fn orientWord(word: []const u8) ?Orient {
    const mirror = word.len > 1 and std.ascii.toLower(word[0]) == 'm';
    const rest = word[@intFromBool(mirror)..];
    if (rest.len < 2 or std.ascii.toLower(rest[0]) != 'r') return null;
    const deg = std.fmt.parseInt(u16, rest[1..], 10) catch return null;
    if (deg % 90 != 0 or deg >= 360) return null;
    return .{ .rot = @intCast(deg / 90), .mirror = mirror };
}

test "orientWord: the eight words, and what is none" {
    try std.testing.expectEqual(Orient{ .rot = 1, .mirror = false }, orientWord("R90").?);
    try std.testing.expectEqual(Orient{ .rot = 3, .mirror = true }, orientWord("mr270").?);
    for ([_][]const u8{ "R45", "R360", "M", "X90", "" }) |w| try std.testing.expectEqual(null, orientWord(w));
}
