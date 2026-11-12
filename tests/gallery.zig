//! The development gallery, on the public API and the tests' symbol set:
//!
//!   zig build gallery -- --svgs dir [deck]     every textbook circuit as dir/<name>.svg (and .cir), the golden set as dir/golden_<name>.svg; the golden scores
//!   zig build gallery -- --score               the golden set scored against its figures (tests/golden.zig)
//!   zig build gallery -- --cells [deck]        the skeleton's cells of the golden set, as grids
//!   zig build gallery -- --gallery out.html    every textbook circuit in one page
//!   zig build gallery -- --dump in.cir         every node, pin and wire of one layout
//!   zig build gallery -- in.cir out.svg [lib.cir…]   one deck, the rest lending it `.subckt`s
//!
//! Contents:
//! - `pub fn main(init: std.process.Init) !void`

const std = @import("std");
const np = @import("NetlistParser");
const textbook = @import("textbook.zig");
const support = @import("support.zig");
const svg = @import("svg.zig");
const golden = @import("golden.zig");

/// A drawing, and how many nets it names instead of wiring.
const Drawn = struct { svg: []u8, labeled: u32 };

const head =
    \\<!doctype html>
    \\<html lang="en"><head><meta charset="utf-8">
    \\<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    \\<title>Hypergraph → schematic: textbook circuits</title>
    \\<style>
    \\:root{box-sizing:border-box;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px);
    \\  --bg:#f4f3ef;--card:#ffffff;--ink:#1d2330;--muted:#5d6577;--line:#dcd9d0;--net:#2a62b8}
    \\@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#15171c;--card:#1f232b;--ink:#e8e9ec;--muted:#9aa1b1;--line:#343a46;--net:#7fa8e8}}
    \\:root[data-theme="dark"]{--bg:#15171c;--card:#1f232b;--ink:#e8e9ec;--muted:#9aa1b1;--line:#343a46;--net:#7fa8e8}
    \\html{scroll-padding-top:env(safe-area-inset-top,0px)}
    \\*,*::before,*::after{box-sizing:inherit}
    \\body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 "Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif}
    \\main{max-width:980px;margin:0 auto;padding:2rem 1.25rem 4rem}
    \\h1{font-size:1.9rem;margin:0 0 .4rem;font-weight:600;letter-spacing:-.01em}
    \\h2.part{font:600 1.3rem/1.3 Helvetica,Arial,sans-serif;margin:2.4rem 0 .3rem}
    \\h3{font:600 1.05rem/1.3 Helvetica,Arial,sans-serif;margin:0 0 .3rem}
    \\.lede{color:var(--muted);max-width:66ch;margin:0 0 1rem}
    \\.legend{display:flex;flex-wrap:wrap;gap:.4rem 1.4rem;font:13px/1.4 Helvetica,Arial,sans-serif;color:var(--muted);margin-bottom:1rem}
    \\.legend em{color:var(--net)}
    \\section{border-top:1px solid var(--line);padding:1.4rem 0 .6rem}
    \\.book{color:var(--muted);margin:0 0 .9rem;max-width:80ch;font-size:14px}
    \\figure{margin:0;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:.6rem}
    \\figcaption{font:12px/1.4 Helvetica,Arial,sans-serif;color:var(--muted);margin:.4rem .2rem 0}
    \\.scroll{overflow-x:auto}
    \\.scroll svg{display:block;max-width:100%;height:auto;border-radius:4px}
    \\</style></head><body><main>
    \\<h1>Hypergraph → schematic, on textbook circuits</h1>
    \\<p class="lede">Every picture is generated from the SPICE netlist by the algorithm in docs/ALGORITHM.md;
    \\nothing is hand-placed. Nets are never nodes: they are straight wires between facing pins,
    \\bends drawn by the layout, or labels.</p>
    \\<div class="legend"><span><em>italic blue</em> = a net label (xschem lab_pin): the same name is the same net</span>
    \\<span>bubble on the gate = PMOS (source toward the supply)</span><span>dot = three or more wire directions meet</span></div>
    \\
;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const cwd = std.Io.Dir.cwd();
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--gallery")) {
        const out = if (args.len >= 3) args[2] else "gallery.html";
        var aw: std.Io.Writer.Allocating = .init(gpa);
        defer aw.deinit();
        const w = &aw.writer;
        try w.writeAll(head);
        try w.writeAll("<h2 class=\"part\">Acceptance set</h2><p class=\"lede\">Each drawing is compared with the book's figure below it.</p>\n");
        for (textbook.all) |c| try section(gpa, lib, w, c);
        try w.writeAll("<h2 class=\"part\">Beyond the set</h2><p class=\"lede\">Textbook circuits beyond the acceptance set; docs/ALGORITHM.md lists what is still open.</p>\n");
        for (textbook.beyond) |c| try section(gpa, lib, w, c);
        try w.writeAll("</main></body></html>\n");
        try cwd.writeFile(io, .{ .sub_path = out, .data = aw.written() });
        std.debug.print("wrote {s}\n", .{out});
        return;
    }
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--score")) {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        for (golden.decks) |d| {
            const s = try golden.score(arena.allocator(), lib, d.spice);
            std.debug.print("{s}\n", .{try golden.formatScore(arena.allocator(), d.name, s)});
        }
        return;
    }
    if (args.len >= 3 and std.mem.eql(u8, args[1], "--svgs")) {
        var dir = try cwd.createDirPathOpen(io, args[2], .{});
        defer dir.close(io);
        const only: ?[]const u8 = if (args.len >= 4) args[3] else null;
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        for (golden.decks) |d| {
            if (only != null and !std.mem.eql(u8, only.?, d.name)) continue;
            const s = try golden.score(arena.allocator(), lib, d.spice);
            std.debug.print("{s}\n", .{try golden.formatScore(arena.allocator(), d.name, s)});
        }
        var name_buf: [64]u8 = undefined;
        for (textbook.all ++ textbook.beyond) |c| {
            if (only != null and !std.mem.eql(u8, only.?, c.name)) continue;
            const d = try draw(gpa, lib, &.{c.spice}, null, true);
            defer gpa.free(d.svg);
            try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name_buf, "{s}.svg", .{c.name}), .data = d.svg });
            // The netlist beside it, for round trips through other netlisters.
            try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name_buf, "{s}.cir", .{c.name}), .data = c.spice });
            std.debug.print("{s:<22} labelled nets {d}\n", .{ c.name, d.labeled });
        }
        // The golden set, to compare with its figures in the owner's notes.
        for (golden.decks) |c| {
            if (only != null and !std.mem.eql(u8, only.?, c.name)) continue;
            const d = try draw(gpa, lib, &.{c.spice}, null, true);
            defer gpa.free(d.svg);
            try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name_buf, "golden_{s}.svg", .{c.name}), .data = d.svg });
        }
        return;
    }
    if (args.len >= 2 and std.mem.eql(u8, args[1], "--cells")) {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        for (golden.decks) |d| {
            if (args.len >= 3 and !std.mem.eql(u8, args[2], d.name)) continue;
            try cells(arena.allocator(), d.name, d.spice);
        }
        return;
    }
    if (args.len >= 3 and std.mem.eql(u8, args[1], "--dump")) {
        const text = try cwd.readFileAlloc(io, args[2], gpa, .unlimited);
        defer gpa.free(text);
        return dump(gpa, lib, text);
    }
    if (args.len < 3) {
        std.debug.print("usage: gallery in.cir out.svg [lib.cir...]\n       gallery --gallery [out.html]\n       gallery --svgs <dir> [deck]\n", .{});
        return;
    }
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var sources: std.ArrayList([]const u8) = .empty;
    try sources.append(arena.allocator(), try cwd.readFileAlloc(io, args[1], arena.allocator(), .unlimited));
    for (args[3..]) |path| try sources.append(arena.allocator(), try cwd.readFileAlloc(io, path, arena.allocator(), .unlimited));
    var diag: np.netlist.Diagnostic = .{};
    const d = draw(gpa, lib, sources.items, &diag, true) catch |err| {
        std.debug.print("{s}:{d}: {s} near '{s}'\n", .{ args[1], diag.line, @errorName(err), diag.token() });
        return err;
    };
    defer gpa.free(d.svg);
    try cwd.writeFile(io, .{ .sub_path = args[2], .data = d.svg });
    std.debug.print("labelled nets {d}\n", .{d.labeled});
}

// ---- private ----

/// A deck laid out and drawn as SVG.
fn draw(gpa: std.mem.Allocator, lib: *np.Library, sources: []const []const u8, diag: ?*np.netlist.Diagnostic, caption: bool) !Drawn {
    var nl = try np.netlist.parse(gpa, sources, diag);
    defer nl.deinit(gpa);
    const roles = try np.guessRoles(gpa, &nl);
    defer gpa.free(roles);
    var s = try np.layout(gpa, &nl, roles, lib, .{});
    defer s.deinit();
    var p = try np.Placed.init(gpa, &s, &nl);
    defer p.deinit();
    var labeled: u32 = 0;
    for (s.labeled) |l| labeled += @intFromBool(l);
    return .{ .svg = try svg.alloc(gpa, &p, lib, .{ .caption = if (caption) nl.title else "" }), .labeled = labeled };
}

/// The skeleton's cells as a grid, a device's name in its cell, then `=`
/// for a bridge, else `>`/`<` as its gate faces right or left.
fn cells(arena: std.mem.Allocator, name: []const u8, spice: []const u8) !void {
    var nl = try np.netlist.parse(arena, &.{spice}, null);
    const roles = try np.guessRoles(arena, &nl);
    const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
    const sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{});
    var w: i32 = 0;
    var h: i32 = 0;
    for (sk.drawn, sk.x, sk.y) |dr, x, y| if (dr) {
        w = @max(w, x + 1);
        h = @max(h, y + 1);
    };
    std.debug.print("{s}\n", .{name});
    for (0..@intCast(h)) |row| {
        for (0..@intCast(w)) |col| {
            var text: []const u8 = ".";
            for (sk.drawn, sk.x, sk.y, 0..) |dr, x, y, d| if (dr and x == col and y == row) {
                text = try arena.print("{s}{s}", .{ nl.graph.edges.items(.name)[d], if (sk.form[d] == .horizontal) "=" else if (sk.gate_right[d]) ">" else "<" });
            };
            std.debug.print("{s:<7}", .{text});
        }
        std.debug.print("\n", .{});
    }
}

/// Every node, pin and wire of a layout: for debugging.
fn dump(gpa: std.mem.Allocator, lib: *np.Library, text: []const u8) !void {
    var nl = try np.netlist.parse(gpa, &.{text}, null);
    defer nl.deinit(gpa);
    const roles = try np.guessRoles(gpa, &nl);
    defer gpa.free(roles);
    var s = try np.layout(gpa, &nl, roles, lib, .{});
    defer s.deinit();
    const pr = std.debug.print;
    const none = np.schematic.none;
    for (0..s.nodes.len) |i| {
        const n = s.nodes.get(i);
        pr("node {d} {t} {s} group {d} at {any}\n", .{ i, n.kind, if (n.kind == .device) s.device_name[n.ref] else s.net_name[n.ref], n.group, s.xy[i] });
    }
    for (0..s.pins.len) |i| {
        const q = s.pins.get(i);
        pr("pin {d} {s}.{d} net {s} side {t} home {d}\n", .{ i, if (q.device == none) "-" else s.device_name[q.device], q.index, s.net_name[q.net], q.side, q.home });
    }
    for (s.routes.items) |r| pr("route net {s} {any}\n", .{ s.net_name[r.net], r.pts[0..r.len] });
    for (s.labeled, 0..) |l, n| if (l) pr("labeled {s}\n", .{s.net_name[n]});
}

fn section(gpa: std.mem.Allocator, lib: *np.Library, w: *std.Io.Writer, c: textbook.Circuit) !void {
    const d = try draw(gpa, lib, &.{c.spice}, null, false);
    defer gpa.free(d.svg);
    try w.print("<section><h3>{s}</h3><p class=\"book\"><b>Book:</b> {s}</p>", .{ c.spice[0 .. std.mem.indexOfScalar(u8, c.spice, '\n') orelse c.spice.len], c.book });
    try w.print("<figure><div class=\"scroll\">{s}</div><figcaption>labelled nets {d}</figcaption></figure></section>\n", .{ d.svg, d.labeled });
}
