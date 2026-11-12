//! The deck's net lines (steering rung 2): how each net is drawn. In: the
//! netlist and its roles. Out: per net its style, port side and rail style,
//! the nets to wire first, and a verdict per line. A pure function of the
//! deck, so the drawing (`wires`) and the report read the same.
//!
//!     *@ label vb1               names at its pins, no wire
//!     *@ wire vb1 [ladder|trunk|route]
//!     *@ port out right          an input's or output's port side
//!     *@ rail 0 bar              a rail as one bar, or a symbol per pin
//!     *@ first n1 n2             wired before the rest, in this order
//!     *@ route n1 2,0 2,3 5,3    a polyline of the net, in symbol units
//!     *@ via n1 4,1 4,6          points its wire passes, in order
//!
//! A `wire` the canvas cannot draw falls back to names (the report says so);
//! of two lines setting one net's style, port or rail, the preferred one
//! (`hints.admitOrder`) stands.
//!
//! Contents:
//! - `pub const Style`, `pub const Rail`, `pub const NetLines = struct`
//! - `pub const Route = struct`
//! - `pub fn read(arena: Allocator, nl: *const Netlist, roles: []const Role, unit: i32, verdicts: []?Verdict) Allocator.Error!NetLines`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const hints = @import("hints.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");

const Netlist = netlist.Netlist;
const Verdict = hints.Verdict;
const Side = library.Side;
const Pt = library.Pt;
const Role = sch.Role;

pub const Style = enum(u8) {
    /// The engine's choice.
    auto,
    /// Names at its pins.
    label,
    /// Names between its parts: pins standing near each other on one
    /// wire, one name a part. The engine's (`thin.zig`); no line asks it.
    cut,
    /// A wire, by whichever pattern fits.
    wire,
    ladder,
    trunk,
    route,
};

pub const Rail = enum(u8) { auto, bar, each };

/// A `route` (a polyline of the net, committed whole or not at all, one of
/// its ends on a pin of the net) or a `via` (points the net's wire passes,
/// in order), in drawing units.
pub const Route = struct { net: u32, pts: []const Pt, via: bool, line: u32 };

pub const NetLines = struct {
    style: []const Style,
    port: []const ?Side,
    rail: []const Rail,
    /// Nets to wire first, in order.
    first: []const u32,
    /// Strongest first.
    routes: []const Route,
};

/// Reads the lines; each valid one honoured (the report checks `label`,
/// `wire` and `port` against the drawing), each invalid one rejected.
pub fn read(arena: Allocator, nl: *const Netlist, roles: []const Role, unit: i32, verdicts: []?Verdict) Allocator.Error!NetLines {
    assert(unit > 0);
    const n = nl.graph.vertexCount();
    assert(roles.len == n);
    const style = try arena.alloc(Style, n);
    @memset(style, .auto);
    const port = try arena.alloc(?Side, n);
    @memset(port, null);
    const rail = try arena.alloc(Rail, n);
    @memset(rail, .auto);
    var first: std.ArrayList(u32) = .empty;
    // The preferred line on a net applied last, so it wins.
    for (try hints.applyOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        const code: ?hints.Code = switch (h.verb) {
            .label, .wire => blk: {
                if (h.args.len < 1 or h.args.len > 2) break :blk .bad_args;
                const net = (nl.net(h.args[0]) orelse break :blk .unknown_name).index();
                const r = roles[net];
                if (r == .supply or r == .sink) break :blk .not_placeable;
                if (h.verb == .wire and r == .input) break :blk .not_placeable;
                var s: Style = if (h.verb == .label) .label else .wire;
                if (h.args.len == 2) {
                    if (h.verb == .label) break :blk .bad_args;
                    s = std.meta.stringToEnum(Style, h.args[1]) orelse break :blk .bad_args;
                    if (s == .auto or s == .label or s == .cut or s == .wire) break :blk .bad_args;
                }
                style[net] = s;
                break :blk null;
            },
            .port => blk: {
                if (h.args.len != 2) break :blk .bad_args;
                const net = (nl.net(h.args[0]) orelse break :blk .unknown_name).index();
                if (roles[net] != .input and roles[net] != .output) break :blk .not_placeable;
                port[net] = sideOf(h.args[1]) orelse break :blk .bad_args;
                break :blk null;
            },
            .rail => blk: {
                if (h.args.len != 2) break :blk .bad_args;
                const net = (nl.net(h.args[0]) orelse break :blk .unknown_name).index();
                if (roles[net] != .supply and roles[net] != .sink) break :blk .not_placeable;
                const r = std.meta.stringToEnum(Rail, h.args[1]) orelse break :blk .bad_args;
                if (r == .auto) break :blk .bad_args;
                rail[net] = r;
                break :blk null;
            },
            else => continue,
        };
        verdicts[i] = if (code) |c| .{ .state = .rejected, .code = c } else .{ .state = .honoured, .code = .ok };
    }
    // `first` lines in file order: theirs is the order to wire in.
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .first) continue;
        const known = h.args.len > 0 and for (h.args) |name| {
            if (nl.net(name) == null) break false;
        } else true;
        if (!known) {
            verdicts[i] = .{ .state = .rejected, .code = if (h.args.len == 0) .bad_args else .unknown_name };
            continue;
        }
        for (h.args) |name| {
            const net = nl.net(name).?.index();
            if (std.mem.indexOfScalar(u32, first.items, net) == null) try first.append(arena, net);
        }
        verdicts[i] = .{ .state = .honoured, .code = .ok };
    }
    // Routes and vias: `<net> x,y ...` (`x y` pairs once split), Manhattan.
    var routes: std.ArrayList(Route) = .empty;
    for (try hints.admitOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if (h.verb != .route and h.verb != .via) continue;
        const via = h.verb == .via;
        const net = if (h.args.len > 0) nl.net(h.args[0]) else null;
        const pairs = if (h.args.len > 0) h.args.len - 1 else 0;
        if (net == null or pairs % 2 != 0 or pairs / 2 < @as(usize, if (via) 1 else 2)) {
            verdicts[i] = .{ .state = .rejected, .code = if (h.args.len > 0 and net == null) .unknown_name else .bad_args };
            continue;
        }
        // Rails and inputs are symbols at their pins, never one wire.
        const r = roles[net.?.index()];
        if (r == .supply or r == .sink or r == .input) {
            verdicts[i] = .{ .state = .rejected, .code = .not_placeable };
            continue;
        }
        const pts = try arena.alloc(Pt, pairs / 2);
        const u: f64 = @floatFromInt(unit);
        const ok = for (pts, 0..) |*p, k| {
            const x = std.fmt.parseFloat(f64, h.args[1 + 2 * k]) catch break false;
            const y = std.fmt.parseFloat(f64, h.args[2 + 2 * k]) catch break false;
            if (!std.math.isFinite(x) or !std.math.isFinite(y) or @abs(x) > 1e6 or @abs(y) > 1e6) break false;
            p.* = .{ .x = @intFromFloat(@round(x * u)), .y = @intFromFloat(@round(y * u)) };
            if (k > 0 and !via and (p.x == pts[k - 1].x) == (p.y == pts[k - 1].y)) break false;
        } else true;
        if (!ok) {
            verdicts[i] = .{ .state = .rejected, .code = .bad_args };
            continue;
        }
        try routes.append(arena, .{ .net = net.?.index(), .pts = pts, .via = via, .line = @intCast(i) });
        verdicts[i] = .{ .state = .honoured, .code = .ok };
    }
    return .{ .style = style, .port = port, .rail = rail, .first = first.items, .routes = routes.items };
}

// ---- private ----

fn sideOf(word: []const u8) ?Side {
    if (std.mem.eql(u8, word, "top")) return .up;
    if (std.mem.eql(u8, word, "bottom")) return .down;
    if (std.mem.eql(u8, word, "left")) return .left;
    if (std.mem.eql(u8, word, "right")) return .right;
    return null;
}
