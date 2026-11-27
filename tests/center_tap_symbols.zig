//! Center-tapped coil contract from the 19 actual source glyphs documented
//! in docs/research/center-tap-symbols.md. These geometry cases went red
//! before the supported glyph and filled-circle operation were added.
//!
//! Contents: independent glyph geometry oracle, then contract boundaries.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");

// ---- private ----

fn pin(c: np.Class, name: []const u8) ?np.Pt {
    for (c.terminals) |p| if (std.ascii.eqlIgnoreCase(name, p.name)) return p.at;
    return null;
}

fn on(p: np.Pt, a: np.Pt, b: np.Pt) bool {
    const cross = (@as(i64, p.x) - a.x) * (@as(i64, b.y) - a.y) - (@as(i64, p.y) - a.y) * (@as(i64, b.x) - a.x);
    return cross == 0 and p.x >= @min(a.x, b.x) and p.x <= @max(a.x, b.x) and p.y >= @min(a.y, b.y) and p.y <= @max(a.y, b.y);
}

fn branch(c: np.Class, from: np.Pt, to: np.Pt) bool {
    for (c.draw) |op| switch (op) {
        .line => |l| if (on(from, l.a, l.b) and on(to, l.a, l.b)) return true,
        .polyline => |ps| {
            if (ps.len < 2) continue;
            for (ps[0 .. ps.len - 1], ps[1..]) |a, b| if (on(from, a, b) and on(to, a, b)) return true;
        },
        else => {},
    };
    return false;
}

fn winding(c: np.Class, outer: np.Pt, joint: np.Pt) bool {
    // Actual source winding paths end on their outer lead and midpoint
    // bridge. A detached decorative coil beside a straight bypass fails.
    for (c.draw) |op| if (op == .polyline) {
        const ps = op.polyline;
        if (ps.len < 3 or ps[0].eql(ps[ps.len - 1])) continue;
        if (for (ps) |p| {
            if (p.x < @min(outer.x, joint.x) or p.x > @max(outer.x, joint.x)) break true;
        } else false) continue;
        const first = ps[0];
        const last = ps[ps.len - 1];
        const forward = (first.eql(outer) or branch(c, first, outer)) and (last.eql(joint) or branch(c, last, joint));
        const reverse = (last.eql(outer) or branch(c, last, outer)) and (first.eql(joint) or branch(c, first, joint));
        if (!forward and !reverse) continue;
        var reversals: usize = 0;
        var previous: i32 = 0;
        for (ps[0 .. ps.len - 1], ps[1..]) |a, b| {
            const dy = std.math.sign(b.y - a.y);
            if (dy == 0) continue;
            reversals += @intFromBool(previous != 0 and previous != dy);
            previous = dy;
        }
        if (reversals >= 3) return true;
    };
    return false;
}

fn filledDot(c: np.Class, joint: np.Pt) bool {
    // The absent additive operation is an assertion RED, not a compiler
    // error. Existing hollow circles retain their old distinct contract.
    if (comptime @hasField(np.library.DrawOp, "filled_circle")) {
        var count: usize = 0;
        for (c.draw) |op| if (op == .filled_circle) {
            if (!op.filled_circle.c.eql(joint) or op.filled_circle.r <= 0) return false;
            count += 1;
        };
        return count == 1;
    }
    return false;
}

fn centerTap(c: np.Class) bool {
    const a = pin(c, "n1") orelse return false;
    const b = pin(c, "n2") orelse return false;
    const tap = pin(c, "n3") orelse return false;
    if (c.terminals.len != 3 or a.y != b.y or a.x >= tap.x or tap.x >= b.x or tap.y <= a.y) return false;
    if (2 * @as(i64, tap.x) != @as(i64, a.x) + b.x) return false;
    const joint = np.Pt{ .x = tap.x, .y = a.y };
    for (c.draw) |op| if (op == .polyline and op.polyline.len >= 64) return false;
    return branch(c, tap, joint) and filledDot(c, joint) and winding(c, a, joint) and winding(c, b, joint);
}

fn allocationFailure(gpa: std.mem.Allocator) !void {
    var lib = np.Library.init(gpa);
    defer lib.deinit();
    const id = blk: {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const drawing = try np.block_symbols.draw(arena.allocator(), .center_tap, &.{ "n3", "n1", "n2" }, 20);
        break :blk lib.register(.{ .name = "ct_inductor", .terminals = drawing.terminals, .draw = drawing.ops }) catch |err| {
            try testing.expectEqual(@as(usize, 0), lib.count());
            try testing.expect(lib.find("ct_inductor") == null);
            return err;
        };
    };
    // Registration owns copies; the construction arena is already gone.
    try testing.expectEqual(@as(usize, 1), lib.count());
    try testing.expect(centerTap(lib.at(id)));
}

test "center-tap glyph: allocation failures release construction scratch without publishing a partial class" {
    // Oracle: allocation failure injection covers construction and copying.
    // The public class is absent on error and owns complete actual geometry
    // after the caller's temporary arena is released on success.
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationFailure, .{});
}

test "center-tap glyph: N1 and N2 remain outer ends and N3 is the connected midpoint tap" {
    // Oracle: AG1114/1168/1180 SVG ink and every observed cell body:
    // L1 n1 n3; L2 n3 n2. N2 is not the tap. All 19 source glyphs have
    // two winding regions joined by a midpoint branch. World orientation
    // is deliberately outside this canonical-symbol test.
    for ([_][]const u8{ "N1 N2 N3", "N1 N3 N2", "N2 N1 N3", "N2 N3 N1", "N3 N1 N2", "N3 N2 N1" }) |ports| {
        const text = try std.fmt.allocPrint(testing.allocator, "coil\n.subckt CT_INDUCTOR {s} params: l1=1n l2=1n k=0\nL1 n1 n3 {{l1}}\nL2 n3 n2 {{l2}}\nK12 L1 L2 {{k}}\n.ends\n", .{ports});
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib = np.Library.init(testing.allocator);
        defer lib.deinit();
        const def = &nl.defs[0];
        const c = lib.at(try lib.blockFor(def));
        try testing.expect(centerTap(c));
        try testing.expectEqual(def.ports.len, c.terminals.len);
        for (def.ports, c.terminals) |name, terminal| {
            try testing.expectEqualStrings(name, terminal.name);
            try testing.expect(!terminal.hidden and !terminal.ground_ref);
        }
        // Named mutation: treating the second positional pin as the tap
        // must fail even though the same three visible anchors survive.
        const changed = try testing.allocator.dupe(np.library.Terminal, c.terminals);
        defer testing.allocator.free(changed);
        for (changed) |*p| {
            if (std.mem.eql(u8, p.name, "n2")) p.name = "n3" else if (std.mem.eql(u8, p.name, "n3")) p.name = "n2";
        }
        var wrong = c;
        wrong.terminals = changed;
        try testing.expect(!centerTap(wrong));
    }
}

test "center-tap glyph: literal disconnected winding and hollow midpoint mutations fail" {
    // Oracle: literal topology and silhouette, independent of generated
    // coil samples. The synthetic paths deliberately are not cubic curves.
    if (comptime @hasField(np.library.DrawOp, "filled_circle")) {
        var left = [_]np.Pt{
            .{ .x = -30, .y = 0 },  .{ .x = -27, .y = -6 }, .{ .x = -23, .y = 0 },
            .{ .x = -19, .y = -6 }, .{ .x = -15, .y = 0 },  .{ .x = -10, .y = -6 },
            .{ .x = -5, .y = 0 },
        };
        const right = [_]np.Pt{
            .{ .x = 5, .y = 0 },   .{ .x = 10, .y = -6 }, .{ .x = 15, .y = 0 },
            .{ .x = 19, .y = -6 }, .{ .x = 23, .y = 0 },  .{ .x = 27, .y = -6 },
            .{ .x = 30, .y = 0 },
        };
        var ops = [_]np.library.DrawOp{
            .{ .polyline = &left },                                      .{ .polyline = &right },
            .ln(-40, 0, -30, 0),                                         .ln(30, 0, 40, 0),
            .ln(-5, 0, 5, 0),                                            .ln(0, 0, 0, 20),
            .{ .filled_circle = .{ .c = .{ .x = 0, .y = 0 }, .r = 2 } },
        };
        const c = np.Class{ .name = "literal", .terminals = &.{
            .{ .name = "n1", .at = .{ .x = -40, .y = 0 } },
            .{ .name = "n2", .at = .{ .x = 40, .y = 0 } },
            .{ .name = "n3", .at = .{ .x = 0, .y = 20 } },
        }, .draw = &ops };
        try testing.expect(centerTap(c));
        left[0].y = 1;
        try testing.expect(!centerTap(c));
        left[0].y = 0;
        ops[6] = .circ(0, 0, 2);
        try testing.expect(!centerTap(c));
        ops[6] = .{ .filled_circle = .{ .c = .{ .x = 1, .y = 0 }, .r = 2 } };
        try testing.expect(!centerTap(c));
        ops[6] = .ln(0, 0, 1, 0);
        try testing.expect(!centerTap(c));
    } else try testing.expect(false);
}

test "center-tap glyph: the exact family and complete named port contract bound recognition" {
    // Oracle: AG1181 tcoil additionally has a capacitor bridge and polarity
    // marks; AG1182 xfmr has four winding ends. Neither is this glyph.
    for ([_]struct { []const u8, []const []const u8 }{
        .{ "tcoil", &.{ "n1", "n2", "n3" } },
        .{ "xfmr", &.{ "p_minus", "p_plus", "s_minus", "s_plus" } },
        .{ "ct_inductor_extra", &.{ "n1", "n2", "n3" } },
        .{ "ct_inductor", &.{ "n1", "n2" } },
        .{ "ct_inductor", &.{ "n1", "n2", "n2" } },
        .{ "ct_inductor", &.{ "n1", "n2", "n3", "shield" } },
        .{ "ct_inductor", &.{ "a", "b", "c" } },
    }) |row| try testing.expectEqual(.box, np.block_symbols.identify(row[0], row[1]));
}

test "center-tap glyph: explicit side directives and caller symbols retain precedence" {
    // Oracle: public caller precedence, independent of family recognition.
    var nl = try np.netlist.parse(testing.allocator, &.{"coil\n.subckt ct_inductor N1 N2 N3\n*@ right N3\n.ends\n"}, null);
    defer nl.deinit(testing.allocator);
    var lib = np.Library.init(testing.allocator);
    defer lib.deinit();
    const def = &nl.defs[0];
    const c = lib.at(try lib.blockFor(def));
    try testing.expectEqual(np.Side.right, c.side(2, .r0).?);
    try testing.expectEqualStrings("n3", c.terminals[2].name);
    try testing.expect(!centerTap(c));
    var own = np.Library.init(testing.allocator);
    defer own.deinit();
    const custom = try own.register(.{ .name = def.name, .terminals = &.{
        .{ .name = "n1", .at = .{ .x = -40, .y = 0 } },
        .{ .name = "n2", .at = .{ .x = 40, .y = 0 } },
        .{ .name = "n3", .at = .{ .x = 0, .y = -40 } },
    } });
    try testing.expectEqual(custom, try own.blockFor(def));
    try testing.expectEqual(@as(i32, -40), own.at(custom).terminals[2].at.y);
}
