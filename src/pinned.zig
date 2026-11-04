//! The deck's geometry lines (steering rung 4): exact coordinates and
//! orientation, and where a device's name goes.
//!
//!     *@ at M5 6 4.5 R90        the class origin at (6, 4.5) symbol units
//!     *@ refdes M5 left         its name left of it
//!
//! Coordinates are in units of the symbol set's `unit` (decimals rounded to
//! the nearest whole drawing unit), the frame `Placed` uses. Of two lines on
//! one device, the preferred stands (`hints.applyOrder`). An `at` whose
//! symbol would overlap another's is dropped; the drawing keeps every
//! guarantee.
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
/// when the line names one; `line` the hint that said so.
pub const At = struct { origin: Pt, orient: ?Orient, line: u32 };

/// Each drawn device's `at` line, the preferred one; invalid lines rejected.
pub fn read(arena: Allocator, nl: *const Netlist, unit: i32, drawn: []const bool, verdicts: []?Verdict) Allocator.Error![]?At {
    assert(unit > 0);
    const out = try arena.alloc(?At, nl.graph.edgeCount());
    @memset(out, null);
    for (try hints.applyOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if (h.verb != .at) continue;
        if (h.args.len != 3 and h.args.len != 4) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        const d = (nl.device(h.args[0]) orelse {
            verdicts[i] = reject(.unknown_name);
            continue;
        }).index();
        if (!drawn[d]) {
            verdicts[i] = reject(.not_placeable);
            continue;
        }
        const x = std.fmt.parseFloat(f64, h.args[1]) catch null;
        const y = std.fmt.parseFloat(f64, h.args[2]) catch null;
        const o: ?Orient = if (h.args.len == 4) orientWord(h.args[3]) else null;
        if (x == null or y == null or (h.args.len == 4 and o == null) or !std.math.isFinite(x.?) or !std.math.isFinite(y.?) or @abs(x.?) > 1e6 or @abs(y.?) > 1e6) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        const u: f64 = @floatFromInt(unit);
        out[d] = .{ .origin = .{ .x = @intFromFloat(@round(x.? * u)), .y = @intFromFloat(@round(y.? * u)) }, .orient = o, .line = @intCast(i) };
        verdicts[i] = .{ .state = .honoured, .code = .ok };
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
        if (h.args.len != 2) {
            verdicts[i] = reject(.bad_args);
            continue;
        }
        const d = (nl.device(h.args[0]) orelse {
            verdicts[i] = reject(.unknown_name);
            continue;
        }).index();
        const side: Side = if (std.mem.eql(u8, h.args[1], "left")) .left else if (std.mem.eql(u8, h.args[1], "right")) .right else if (std.mem.eql(u8, h.args[1], "above")) .up else if (std.mem.eql(u8, h.args[1], "below")) .down else {
            verdicts[i] = reject(.bad_args);
            continue;
        };
        out[d] = side;
        verdicts[i] = .{ .state = .honoured, .code = .ok };
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

// ---- private ----

fn reject(code: hints.Code) Verdict {
    return .{ .state = .rejected, .code = code };
}

test "orientWord: the eight words, and what is none" {
    try std.testing.expectEqual(Orient{ .rot = 1, .mirror = false }, orientWord("R90").?);
    try std.testing.expectEqual(Orient{ .rot = 3, .mirror = true }, orientWord("mr270").?);
    for ([_][]const u8{ "R45", "R360", "M", "X90", "" }) |w| try std.testing.expectEqual(null, orientWord(w));
}
