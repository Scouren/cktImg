//! Random small netlists through the whole pipeline (`zig build fuzz`, in
//! CI): every layout ends, every net is one piece as a netlister reads it,
//! no wire touches another net's point, and the cards reversed draw the same
//! picture. Each deck carries random `*@` lines of rungs 1 and 2 (steering):
//! every line gets a verdict, and none the engine honoured is missing from
//! the drawing. Reports how many netlists name a net instead of wiring it,
//! and the smallest one.
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
        try w.writeAll("fuzz\n");
        const devices = r.intRangeAtMost(u32, 2, 6);
        try randomLines(r, &w, devices, &nets);
        try w.writeAll(".model nch nmos level=1\n.model pch pmos level=1\nVdd vdd 0 1.8\nVin in 0 ac 1\n");
        for (0..devices) |i| {
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
        // Every line a verdict; none honoured that the drawing lacks.
        for (sk.nl.hints, try np.report.verdicts(a, &sk.nl, sk.roles, &sk.st, &sk.sk, &sk.p, lib)) |h, v| {
            if (v.state == .relaxed and v.code == .not_drawn) {
                std.debug.print("`{s}` honoured but not drawn:\n{s}\n", .{ h.text, text });
                return error.NotDrawn;
            }
        }
        cases[0].record(sk.labeled > 0, text);
    }
    std.debug.print("{d} random netlists with random *@ lines: every layout ended, each net one piece, no wire on another net's point, the same picture with the cards reversed, every line a verdict and none honoured that the drawing lacks\n", .{runs});
    for (cases) |c| {
        std.debug.print("\n== {s}: {d}\n", .{ c.name, c.count });
        if (c.count > 0) std.debug.print("{s}", .{c.text[0..c.len]});
    }
}

// ---- private ----

/// A netlist laid out, its stages kept, and how many nets it labels.
fn draw(a: std.mem.Allocator, lib: *np.Library, text: []const u8) !struct { p: np.Placed, labeled: u32, nl: netlist.Netlist, roles: []np.Role, st: sch.structure.Structure, sk: sch.skeleton.Skeleton } {
    var nl = try netlist.parse(a, &.{text}, null);
    const roles = try sch.guessRoles(a, &nl);
    const s = try np.layout(a, &nl, roles, lib, .{});
    var labeled: u32 = 0;
    for (s.labeled) |l| labeled += @intFromBool(l);
    const st = try sch.structure.analyze(a, a, &nl, roles);
    const sk = try sch.skeleton.place(a, a, &nl, roles, &st);
    return .{ .p = try np.Placed.init(a, &s, &nl), .labeled = labeled, .nl = nl, .roles = roles, .st = st, .sk = sk };
}

/// Up to four `*@` lines of rungs 1 and 2, on devices `r0`..`m<devices>` (a
/// name the deck lacks is fine: it is rejected) and on `nets`.
fn randomLines(r: std.Random, w: *std.Io.Writer, devices: u32, nets: []const []const u8) !void {
    const letters = "rcm";
    for (0..r.intRangeAtMost(u32, 0, 4)) |_| {
        const dev = struct {
            fn pick(rr: std.Random, n: u32, ls: []const u8) [2]u8 {
                return .{ ls[rr.intRangeLessThan(usize, 0, ls.len)], '0' + @as(u8, @intCast(rr.intRangeLessThan(u32, 0, n))) };
            }
        }.pick;
        const a = dev(r, devices, letters);
        const b = dev(r, devices, letters);
        const c = dev(r, devices, letters);
        const net = nets[r.intRangeLessThan(usize, 0, nets.len)];
        if (r.boolean() and r.boolean()) try w.writeAll("*@ weak ");
        if (w.buffered().len > 0 and w.buffered()[w.buffered().len - 1] != ' ') try w.writeAll("*@ ");
        switch (r.intRangeAtMost(u32, 0, 15)) {
            0 => try w.print("above {s} {s} {s}\n", .{ &a, &b, &c }),
            1 => try w.print("row {s} {s}\n", .{ &a, &b }),
            2 => try w.print("order {s} {s} {s}\n", .{ &a, &b, &c }),
            3 => try w.print("face {s} g {s}\n", .{ &a, if (r.boolean()) "left" else "right" }),
            4 => try w.print("face {s} {s} up\n", .{ &a, if (r.boolean()) "a" else "d" }),
            5 => try w.writeAll("symmetry off\n"),
            6 => try w.print("symmetric {s} {s}\n", .{ &a, &b }),
            7 => try w.print("group {s} {s} {s}\n", .{ if (r.boolean()) "pair" else "stack", &a, &b }),
            8 => try w.print("{s} {s}\n", .{ if (r.boolean()) "upright" else "bridge", &a }),
            9 => try w.print("label {s}\n", .{net}),
            10 => try w.print("wire {s} {s}\n", .{ net, if (r.boolean()) "trunk" else "route" }),
            11 => try w.print("port {s} {s}\n", .{ net, if (r.boolean()) "left" else "top" }),
            12 => try w.print("rail {s} {s}\n", .{ net, if (r.boolean()) "bar" else "each" }),
            13 => try w.print("first {s}\n", .{net}),
            14 => try w.print("role {s} {s}\n", .{ net, if (r.boolean()) "bias" else "output" }),
            else => try w.print("nogroup {s}\n", .{&a}),
        }
    }
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
