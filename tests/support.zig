//! What every test needs from outside the library: a symbol set, and the
//! checks every drawing must pass.
//!
//! Contents:
//! - `pub const symbols: *const [N:0]u8`
//! - `pub const wide_chain`
//! - `pub const inverting_amp`
//! - `pub fn library(gpa: std.mem.Allocator) !*np.Library`
//! - `pub fn freeLibrary(gpa: std.mem.Allocator, lib: *np.Library) void`
//! - `pub fn shorts(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32`
//! - `pub fn dots(gpa: std.mem.Allocator, p: *const np.Placed, print: bool) !u32`
//! - `pub fn generatedStack(p: *const np.Placed, upper: []const u8, lower: []const u8) bool`
//! - `pub fn expectConnected(p: *const np.Placed, lib: *const np.Library) !void`

const std = @import("std");
const np = @import("NetlistParser");

pub const symbols = @embedFile("symbols.zon");

/// Twelve common-source stages in a chain: a row of twelve columns, which
/// wraps into two shelves of six with the net `n6` between them.
pub const wide_chain = "chain\n.model nch nmos level=1\nVDD vdd 0 1.8\n" ++
    "M1 n1 in 0 0 nch\nR1 vdd n1 1k\nM2 n2 n1 0 0 nch\nR2 vdd n2 1k\nM3 n3 n2 0 0 nch\nR3 vdd n3 1k\n" ++
    "M4 n4 n3 0 0 nch\nR4 vdd n4 1k\nM5 n5 n4 0 0 nch\nR5 vdd n5 1k\nM6 n6 n5 0 0 nch\nR6 vdd n6 1k\n" ++
    "M7 n7 n6 0 0 nch\nR7 vdd n7 1k\nM8 n8 n7 0 0 nch\nR8 vdd n8 1k\nM9 n9 n8 0 0 nch\nR9 vdd n9 1k\n" ++
    "M10 n10 n9 0 0 nch\nR10 vdd n10 1k\nM11 n11 n10 0 0 nch\nR11 vdd n11 1k\nM12 out n11 0 0 nch\nR12 vdd out 1k\n";

/// The standard symbol set (`symbols.zon`), on the heap so that schematics
/// can point at it while their owner moves.
/// An inverting amplifier on an op-amp block: an input resistor, a
/// feedback resistor, a load. The op-amp placement draws it (`opamp.zig`).
pub const inverting_amp = "Inverting amplifier\n.subckt opamp vdd vss vip vin vout\nR1 vip vout 1k\n.ends\n" ++
    "X1 vdd 0 0 x out opamp\nR1 in x 1k\nRF x out 10k\nRL out 0 10k\n";

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
/// A two-primitive stack seen directly in the emitted drawing. The random
/// generator emits MOS D/G/S and otherwise two-terminal paths or E/G output
/// pairs in SPICE order. A single common path terminal must share its x.
pub fn generatedStack(p: *const np.Placed, upper: []const u8, lower: []const u8) bool {
    const top = np.checks.deviceIn(p, upper) orelse return false;
    const bottom = np.checks.deviceIn(p, lower) orelse return false;
    if (p.dev_pos[top].y >= p.dev_pos[bottom].y) return false;
    var pins: [2][2]u32 = undefined;
    for ([_]usize{ top, bottom }, &pins) |dev, *ends| {
        const last: u32 = switch (p.dev_name[dev][0]) {
            'm' => 2,
            'r', 'c', 'v', 'e', 'g' => 1,
            else => unreachable, // The generator's card families above.
        };
        const first = p.dev_pin0[dev];
        if (first + last >= p.dev_pin0[dev + 1]) return false;
        ends.* = .{ first, first + last };
    }
    var shared: u8 = 0;
    var aligned: u8 = 0;
    for (pins[0]) |a| for (pins[1]) |b| {
        if (p.pin_net[a] == p.pin_net[b]) {
            shared += 1;
            aligned += @intFromBool(p.pin_xy[a].x == p.pin_xy[b].x);
        }
    };
    return shared != 1 or aligned == 1;
}

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
