//! Stage 4 (issue #8): drawings from the skeleton. Each golden figure
//! against its drawing, labels included; every drawing, textbook and
//! golden, holds today's guarantees: each device once, every net one piece
//! as a netlister reads it, no wire on another net's point.
//!
//! Contents: tests only.

const std = @import("std");
const np = @import("NetlistParser");
const golden = @import("golden.zig");
const support = @import("support.zig");
const textbook = @import("textbook.zig");

/// One line per golden deck, as `golden.formatScore` writes it, for the
/// sketch's drawing. A change either way fails until the line is updated.
const recorded = [golden.decks.len][]const u8{
    "ota_5t x 8/8 y 8/8 rows 2+0-0 cols 2+0-0 sym 3/3 gates 5/5 labels +[] -[]",
    "two_stage_pmos x 31/33 y 26/26 rows 5+0-5 cols 3+2-0 sym 3/3 gates 7/7 labels +[vout] -[]",
    "fd_two_stage x 32/32 y 24/24 rows 12+0-0 cols 4+0-0 sym 5/5 gates 8/8 labels +[] -[]",
    "telescopic_fd x 24/24 y 32/32 rows 4+0-0 cols 12+0-0 sym 5/5 gates 8/8 labels +[] -[]",
    "folded_cascode x 43/43 y 44/50 rows 5+6-0 cols 12+0-0 sym 6/6 gates 2/10 labels +[] -[vb1,vb4]",
    "strongarm x 49/49 y 38/46 rows 9+8-0 cols 6+0-0 sym 6/6 gates 7/7 labels +[] -[]",
    "gilbert x 34/36 y 28/29 rows 7+1-0 cols 0+2-0 sym 0/0 gates 4/6 labels +[] -[]",
    "cmfb_two_stage x 70/74 y 50/64 rows 14+4-0 cols 4+4-0 sym 7/7 gates 8/8 labels +[q,x,y] -[]",
    "bandgap_ptat x 29/29 y 29/29 rows 7+0-0 cols 7+0-0 sym 0/0 gates 5/6 labels +[g,y] -[]",
    "cascode_mirror x 6/6 y 8/8 rows 2+0-0 cols 4+0-0 sym 2/2 gates 4/4 labels +[] -[]",
    "wide_swing x 16/16 y 16/19 rows 2+3-0 cols 5+0-0 sym 0/0 gates 4/5 labels +[n] -[]",
    "beta_multiplier x 11/11 y 13/13 rows 2+0-0 cols 4+0-0 sym 2/2 gates 4/5 labels +[] -[]",
    "diff_pair_resistive x 8/8 y 8/8 rows 2+0-0 cols 2+0-0 sym 3/3 gates 2/2 labels +[] -[]",
    "telescopic_se x 0/0 y 6/6 rows 0+0-0 cols 6+0-0 sym 0/0 gates 4/4 labels +[] -[]",
};

// ---- private ----

fn draw(arena: std.mem.Allocator, lib: *np.Library, spice: []const u8) !np.Placed {
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    const s = try np.schematic.sketch.lay(arena, &nl, roles, lib);
    return np.Placed.init(arena, &s, &nl);
}

test "sketch: each golden figure's drawing scores what is recorded" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var changed: usize = 0;
    for (golden.decks, recorded) |d, want| {
        const got = try golden.formatScore(arena, d.name, try golden.scoreWith(arena, lib, d.spice, .sketch));
        if (std.mem.eql(u8, got, want)) continue;
        changed += 1;
        std.debug.print("sketch {s}:\n  recorded \"{s}\"\n  now      \"{s}\",\n", .{ d.name, want, got });
    }
    try std.testing.expectEqual(0, changed);
}

test "sketch: every drawing keeps its devices, is connected, and shorts nothing" {
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var decks: std.ArrayList(struct { []const u8, []const u8 }) = .empty;
    for (golden.decks) |d| try decks.append(arena, .{ d.name, d.spice });
    for (textbook.all ++ textbook.beyond) |c| try decks.append(arena, .{ c.name, c.spice });
    var bad: usize = 0;
    for (decks.items) |d| {
        const p = try draw(arena, lib, d[1]);
        support.expectConnected(&p, lib) catch {
            std.debug.print("sketch {s}: a net in pieces\n", .{d[0]});
            bad += 1;
        };
        const shorts = try support.shorts(gpa, &p, true);
        if (shorts > 0) {
            std.debug.print("sketch {s}: {d} nets touch another's point\n", .{ d[0], shorts });
            bad += 1;
        }
    }
    try std.testing.expectEqual(0, bad);
}
