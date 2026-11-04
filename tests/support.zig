//! What every test needs from outside the library: a symbol set, and the
//! checks every drawing must pass.
//!
//! Contents:
//! - `pub const symbols: *const [N:0]u8`
//! - `pub fn library(gpa: std.mem.Allocator) !*np.Library`
//! - `pub fn freeLibrary(gpa: std.mem.Allocator, lib: *np.Library) void`
//! - `pub fn shorts(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32`
//! - `pub fn dots(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32`
//! - `pub fn expectConnected(p: *const np.Placed, lib: *const np.Library) !void`

const std = @import("std");
const np = @import("NetlistParser");

pub const symbols = @embedFile("symbols.zon");

/// The standard symbol set (`symbols.zon`), on the heap so that schematics
/// can point at it while their owner moves.
pub fn library(gpa: std.mem.Allocator) !*np.Library {
    const lib = try gpa.create(np.Library);
    errdefer gpa.destroy(lib);
    lib.* = .init(gpa);
    errdefer lib.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var diags: std.ArrayList(np.library.ZonDiagnostic) = .empty;
    try lib.loadZon(arena.allocator(), symbols, &diags);
    for (diags.items) |d| std.debug.print("symbols.zon: {s}: {s}\n", .{ d.class, @errorName(d.err) });
    if (diags.items.len > 0) return error.BadSymbols;
    return lib;
}

pub fn freeLibrary(gpa: std.mem.Allocator, lib: *np.Library) void {
    lib.deinit();
    gpa.destroy(lib);
}

/// How many nets have a wire through or onto another net's point (a pin,
/// a wire's end or bend, a label: xschem joins by touch); prints the first
/// of each when `print`. `np.checks.shorts` finds them.
pub fn shorts(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32 {
    var found: std.ArrayList(np.checks.Finding) = .empty;
    defer found.deinit(gpa);
    try np.checks.shorts(gpa, &found, p);
    var count: u32 = 0;
    for (found.items, 0..) |f, i| {
        const first = for (found.items[0..i]) |g| {
            if (g.net == f.net) break false;
        } else true;
        if (!first) continue;
        count += 1;
        if (print) std.debug.print("net {s}: a wire touches a point of net {s} at {any}\n", .{ p.net_name[f.net], p.net_name[f.other], f.at });
    }
    return count;
}

/// How many points break the dot rule (`np.checks.dots`): a junction with no
/// dot, a dot with no junction, a net crossing itself; prints each when
/// `print`. A four-way junction with its dot is fine: the book draws them.
pub fn dots(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32 {
    var found: std.ArrayList(np.checks.Finding) = .empty;
    defer found.deinit(gpa);
    try np.checks.dots(gpa, &found, p);
    if (print) for (found.items) |f| {
        const net = if (f.net < p.netCount()) p.net_name[f.net] else "-";
        std.debug.print("net {s}: {t} at {any} ({d})\n", .{ net, f.rule, f.at, f.other });
    };
    return @intCast(found.items.len);
}

/// Every net is one piece, read the way a netlister reads the JSON
/// (`np.checks.connected`).
pub fn expectConnected(p: *const np.Placed, lib: *const np.Library) !void {
    // Its own scratch, so the fuzzer (no test runner) checks with it too.
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    var found: std.ArrayList(np.checks.Finding) = .empty;
    try np.checks.connected(arena.allocator(), &found, p, lib);
    for (found.items) |f| std.debug.print("net {s} is in {d} pieces\n", .{ p.net_name[f.net], f.other });
    if (found.items.len > 0) return error.SplitNet;
}
