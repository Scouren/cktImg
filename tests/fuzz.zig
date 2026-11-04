//! Random small netlists through the whole pipeline (`zig build fuzz`, in
//! CI): every layout ends, every net is one piece as a netlister reads it,
//! no wire touches another net's point, and the cards reversed draw the same
//! picture. Reports how many netlists name a net instead of wiring it, and
//! the smallest one.
//!
//! Contents:
//! - `pub fn main(init: std.process.Init) !void`

const std = @import("std");
const np = @import("NetlistParser");
const netlist = np.netlist;
const sch = np.schematic;
const support = @import("support.zig");
const golden = @import("golden.zig");

const runs = 4000;

const Case = struct {
    name: []const u8,
    count: u32 = 0,
    len: usize = std.math.maxInt(usize),
    text: [1024]u8 = undefined,

    fn record(c: *Case, hit: bool, text: []const u8) void {
        if (!hit) return;
        c.count += 1;
        if (text.len >= c.len) return;
        c.len = text.len;
        @memcpy(c.text[0..text.len], text);
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const nets = [_][]const u8{ "vdd", "0", "in", "out", "a", "b", "c" };
    var cases = [_]Case{
        .{ .name = "a net drawn as labels" },
    };
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    var prng = std.Random.DefaultPrng.init(12345);
    const r = prng.random();
    for (0..runs) |_| {
        var buf: [1024]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        try w.writeAll("fuzz\n.model nch nmos level=1\n.model pch pmos level=1\nVdd vdd 0 1.8\nVin in 0 ac 1\n");
        for (0..r.intRangeAtMost(u32, 2, 6)) |i| {
            const p = nets[r.intRangeLessThan(usize, 0, nets.len)];
            const q = nets[r.intRangeLessThan(usize, 0, nets.len)];
            const g = nets[r.intRangeLessThan(usize, 0, nets.len)];
            switch (r.intRangeAtMost(u32, 0, 3)) {
                0 => try w.print("R{d} {s} {s} 1k\n", .{ i, p, q }),
                1 => try w.print("C{d} {s} {s} 1p\n", .{ i, p, q }),
                2 => try w.print("M{d} {s} {s} {s} 0 nch\n", .{ i, p, g, q }),
                else => try w.print("M{d} {s} {s} {s} vdd pch\n", .{ i, p, g, q }),
            }
        }
        const text = w.buffered();
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const sk = draw(a, lib, text) catch |e| switch (e) {
            error.OutOfMemory => return e,
            else => continue, // a card the parser does not take
        };
        support.expectConnected(&sk.p, lib) catch |e| {
            std.debug.print("a net in pieces:\n{s}\n", .{text});
            return e;
        };
        if (try support.shorts(gpa, &sk.p, true) > 0) {
            std.debug.print("a wire touches another net:\n{s}\n", .{text});
            return error.Short;
        }
        if (try support.dots(gpa, &sk.p, true) > 0) {
            std.debug.print("a dot is wrong:\n{s}\n", .{text});
            return error.Dots;
        }
        // One picture per circuit: the cards reversed draw the same.
        const back = try draw(a, lib, try golden.shuffled(a, text, .reversed));
        const want = try canonical(a, &sk.p);
        const got = try canonical(a, &back.p);
        if (!std.mem.eql(u8, want, got)) {
            std.debug.print("the cards reversed draw differently:\n{s}\n", .{text});
            return error.CardOrder;
        }
        cases[0].record(sk.labeled > 0, text);
    }
    std.debug.print("{d} random netlists: every layout ended, each net one piece, no wire on another net's point, the same picture with the cards reversed\n", .{runs});
    for (cases) |c| {
        std.debug.print("\n== {s}: {d}\n", .{ c.name, c.count });
        if (c.count > 0) std.debug.print("{s}", .{c.text[0..c.len]});
    }
}

// ---- private ----

/// A netlist laid out, and how many nets it labels.
fn draw(a: std.mem.Allocator, lib: *np.Library, text: []const u8) !struct { p: np.Placed, labeled: u32 } {
    var nl = try netlist.parse(a, &.{text}, null);
    const roles = try sch.guessRoles(a, &nl);
    const s = try np.layout(a, &nl, roles, lib, .{});
    var labeled: u32 = 0;
    for (s.labeled) |l| labeled += @intFromBool(l);
    return .{ .p = try np.Placed.init(a, &s, &nl), .labeled = labeled };
}

/// Each device by name with its place and turn, then each net by name with
/// its wires' segments, sorted: equal for equal drawings, whatever the
/// order things were drawn in.
fn canonical(a: std.mem.Allocator, p: *const np.Placed) ![]const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    for (p.dev_name, p.dev_pos, p.dev_orient) |name, at, o| {
        if (name.len > 0) try lines.append(a, try std.fmt.allocPrint(a, "d {s} {d} {d} {any}", .{ name, at.x, at.y, o }));
    }
    for (p.net_name, 0..) |name, n| {
        for (p.net_seg[n]..p.net_seg[n + 1]) |k| {
            const pts = p.wire_pts[p.seg_pt[k]..p.seg_pt[k + 1]];
            for (pts[0 .. pts.len - 1], pts[1..]) |u, v| {
                const lo = if (u.x < v.x or (u.x == v.x and u.y < v.y)) u else v;
                const hi = if (lo.x == u.x and lo.y == u.y) v else u;
                try lines.append(a, try std.fmt.allocPrint(a, "w {s} {d} {d} {d} {d}", .{ name, lo.x, lo.y, hi.x, hi.y }));
            }
        }
    }
    std.mem.sort([]const u8, lines.items, {}, struct {
        fn lt(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.lessThan(u8, x, y);
        }
    }.lt);
    return std.mem.join(a, "\n", lines.items);
}
