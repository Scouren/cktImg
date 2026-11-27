//! Filled-disk export contract across SVG, TikZ and Schemify.
//! The old hollow circle and new filled disk remain observably distinct.
//!
//! Contents: independent record readers and renderer boundary tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const cktimg = @import("cktimg");
const svg = @import("svg.zig");

const Circle = struct { x: f32, y: f32, fill: []const u8 };
const shifts = [_][2]f32{
    .{ 77, 6 },  .{ -6, 77 },  .{ -77, -6 }, .{ 6, -77 },
    .{ -77, 6 }, .{ -6, -77 }, .{ 77, -6 },  .{ 6, 77 },
};

// ---- private ----

fn attr(line: []const u8, name: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, line, name) orelse return error.MissingAttribute;
    const tail = line[start + name.len ..];
    const end = std.mem.indexOfScalar(u8, tail, '"') orelse return error.BadAttribute;
    return tail[0..end];
}

fn svgCircle(bytes: []const u8, radius: f32) !Circle {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var found: ?Circle = null;
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "<circle ") == null) continue;
        if (try std.fmt.parseFloat(f32, try attr(line, " r=\"")) != radius) continue;
        if (found != null) return error.AmbiguousCircle;
        found = .{
            .x = try std.fmt.parseFloat(f32, try attr(line, " cx=\"")),
            .y = try std.fmt.parseFloat(f32, try attr(line, " cy=\"")),
            .fill = try attr(line, " fill=\""),
        };
    }
    return found orelse error.MissingCircle;
}

fn tikzCircle(bytes: []const u8, radius: i32) !Circle {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var found: ?Circle = null;
    while (lines.next()) |line| {
        const at = std.mem.indexOf(u8, line, " circle[radius=") orelse continue;
        const tail = line[at + " circle[radius=".len ..];
        const end = std.mem.indexOf(u8, tail, "pt]") orelse return error.BadCircle;
        if (try std.fmt.parseInt(i32, tail[0..end], 10) != radius) continue;
        if (found != null) return error.AmbiguousCircle;
        const open = std.mem.indexOfScalar(u8, line[0..at], '(') orelse return error.BadCircle;
        const comma = std.mem.indexOf(u8, line[open..at], "pt,") orelse return error.BadCircle;
        const close = std.mem.indexOf(u8, line[open + comma + 3 .. at], "pt)") orelse return error.BadCircle;
        const prefix = line[0..open];
        const fill = if (std.mem.indexOf(u8, prefix, "fill=white") != null) "white" else if (std.mem.indexOf(u8, prefix, "fill=black") != null or std.mem.indexOf(u8, prefix, "\\fill[") != null or
            std.mem.indexOf(u8, prefix, "\\fill ") != null) "ink" else "missing";
        found = .{
            .x = try std.fmt.parseFloat(f32, line[open + 1 .. open + comma]),
            .y = try std.fmt.parseFloat(f32, line[open + comma + 3 .. open + comma + 3 + close]),
            .fill = fill,
        };
    }
    return found orelse error.MissingCircle;
}

fn emittedDisk(bytes: []const u8, at: np.Pt, radius: i32) bool {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var selected = false;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (line[0] != ' ') {
            selected = false;
            var words = std.mem.tokenizeScalar(u8, line, ' ');
            if (!std.mem.eql(u8, words.next() orelse continue, "circle")) continue;
            const x = std.fmt.parseInt(i32, words.next() orelse return false, 10) catch return false;
            const y = std.fmt.parseInt(i32, words.next() orelse return false, 10) catch return false;
            const r = std.fmt.parseInt(i32, words.next() orelse return false, 10) catch return false;
            selected = x == at.x and y == at.y and r == radius and words.next() == null;
        } else if (selected and std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), "fill true")) return true;
    }
    return false;
}

test "center-tap renderers: SVG and enabled TikZ distinguish filled and hollow circles" {
    // Oracle: two literal displaced disks with different radii. Their
    // relative positions under eight poses are the hand-written table,
    // independently of the renderer's placement or viewport transform.
    if (comptime @hasField(np.library.DrawOp, "filled_circle")) {
        var lib = np.Library.init(testing.allocator);
        defer lib.deinit();
        _ = try lib.register(.{ .name = "ink_probe", .terminals = &.{
            .{ .name = "a", .at = .{ .x = -40, .y = 0 } },
            .{ .name = "b", .at = .{ .x = 40, .y = 0 } },
        }, .draw = &.{
            .circ(-7, 11, 3),
            .{ .filled_circle = .{ .c = .{ .x = 70, .y = 17 }, .r = 9 } },
        } });
        var p = try np.place(testing.allocator, &.{}, &lib, &.{"two disks\n.subckt ink_probe a b\n.ends\nX1 p q ink_probe\n"}, null);
        defer p.deinit();
        const d = for (p.dev_name, 0..) |name, i| {
            if (std.mem.eql(u8, name, "x1")) break i;
        } else return error.MissingInstance;
        const poses = try p.arena.allocator().dupe(np.Orient, p.dev_orient);
        p.dev_orient = poses;
        for (shifts, 0..) |shift, i| {
            poses[d] = .{ .rot = @intCast(i & 3), .mirror = i >= 4 };
            const bytes = try svg.alloc(testing.allocator, &p, &lib, .{ .scale = 1 });
            defer testing.allocator.free(bytes);
            const hollow = try svgCircle(bytes, 3);
            const filled = try svgCircle(bytes, 9);
            try testing.expectEqualStrings("#ffffff", hollow.fill);
            try testing.expect(!std.mem.eql(u8, "#ffffff", filled.fill) and
                !std.mem.eql(u8, "white", filled.fill) and !std.mem.eql(u8, "none", filled.fill) and filled.fill.len > 0);
            try testing.expectEqual(shift[0], filled.x - hollow.x);
            try testing.expectEqual(shift[1], filled.y - hollow.y);
            // This branch is compiled only by the required renderer=true
            // build. renderer=false deliberately has no TikZ API.
            if (comptime np.latex != void) {
                var out = std.Io.Writer.Allocating.init(testing.allocator);
                defer out.deinit();
                try np.latex.write(testing.allocator, &p, &lib, &.{}, &out.writer);
                const old = try tikzCircle(out.written(), 3);
                const disk = try tikzCircle(out.written(), 9);
                try testing.expectEqualStrings("white", old.fill);
                try testing.expectEqualStrings("ink", disk.fill);
                try testing.expectEqual(shift[0], disk.x - old.x);
                try testing.expectEqual(-shift[1], disk.y - old.y);
            }
        }
    } else try testing.expect(false);
}

test "center-tap renderers: emitted midpoint disk has a local fill attribute" {
    // Oracle: Schemify's rank-2 circle + fill true record contract. A filled
    // unrelated circle or a body count cannot substitute for the tap dot.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var c = try cktimg.Converter.init(testing.allocator, a, "tap.sp", "* tap\n.subckt ct_inductor n1 n2 n3\n.ends\nX1 a b tap ct_inductor\n");
    defer c.deinit();
    const sym = cktimg.recognize.subSymbol(c.deck.findCell("ct_inductor").?);
    const glyph = c.lib.at(c.lib.find(try std.fmt.allocPrint(a, "b{d}", .{sym})).?);
    try c.step();
    if (comptime @hasField(np.library.DrawOp, "filled_circle")) {
        const disk = for (glyph.draw) |op| {
            if (op == .filled_circle) break op.filled_circle;
        } else return error.MissingTapDisk;
        try testing.expect(emittedDisk(c.out.files.items[0].bytes, disk.c, disk.r));
    } else try testing.expect(false);
}

test "center-tap renderers: literal readers reject hollow and unrelated filled records" {
    const at = np.Pt{ .x = 0, .y = 0 };
    try testing.expect(emittedDisk("circle 0 0 2\n  fill true\n", at, 2));
    try testing.expect(!emittedDisk("circle 0 0 2\n", at, 2));
    try testing.expect(!emittedDisk("circle 0 0 2\n  fill false\n", at, 2));
    try testing.expect(!emittedDisk("circle 0 0 2\ncircle 8 8 2\n  fill true\n", at, 2));
    try testing.expect(!emittedDisk("circle 1 0 2\n  fill true\n", at, 2));
    const hollow = try svgCircle("<circle cx=\"7\" cy=\"9\" r=\"2\" fill=\"white\"/>", 2);
    try testing.expectEqualStrings("white", hollow.fill);
    const disk = try tikzCircle("  \\draw[cktsym,fill=black] (7pt,-9pt) circle[radius=2pt];", 2);
    try testing.expectEqualDeep(Circle{ .x = 7, .y = -9, .fill = "ink" }, disk);
    const open = try tikzCircle("  \\draw[cktsym,fill=white] (7pt,-9pt) circle[radius=2pt];", 2);
    try testing.expectEqualStrings("white", open.fill);
}
