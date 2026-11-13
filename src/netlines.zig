//! The deck's net lines (steering rung 2): how each net is drawn. In: the
//! netlist and its roles. Out: per net its style, port side and rail style,
//! the nets to wire first, and a verdict per line. A pure function of the
//! deck, so the drawing (`wires`) and the report read the same.
//!
//!     *@ label vb1               names at its pins, no wire
//!     *@ wire vb1 [ladder|trunk|route]
//!     *@ port out right          an input's or output's port side
//!     *@ rail 0 bar              a rail as one bar, a symbol per pin (`each`),
//!                                or one bar with no symbol (`plain`)
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

pub const Rail = enum(u8) {
    /// No line says. `read` gives a rail its role's style instead, so only
    /// a net that is no rail keeps this.
    auto,
    /// One bar past its pins, a rail symbol on each unbroken run of it.
    bar,
    /// A rail symbol at each pin.
    each,
    /// One bar and no symbol: a wire. Where the bar breaks, or a pin does
    /// not reach it, the pieces carry the net's name.
    plain,
};

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
/// `wire` and `port` against the drawing), each invalid one rejected. A
/// rail no line styles gets its role's style.
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
    // What a line says of one net: its words counted, its net known, the
    // net one the verb draws (`admits`), then what it says of it. The
    // preferred line on a net applied last, so it wins.
    for (try hints.applyOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        const least: usize = switch (h.verb) {
            .label, .wire => 1,
            .port, .rail => 2,
            else => continue,
        };
        const code: hints.Code = blk: {
            if (h.args.len < least or h.args.len > 2) break :blk .bad_args;
            const net = (nl.net(h.args[0]) orelse break :blk .unknown_name).index();
            if (!admits(h.verb, roles[net])) break :blk .not_placeable;
            switch (h.verb) {
                // Counted as `wire` is: a second word is refused only here,
                // after the net's name and role.
                .label => {
                    if (h.args.len == 2) break :blk .bad_args;
                    style[net] = .label;
                },
                .wire => {
                    var s: Style = .wire;
                    if (h.args.len == 2) {
                        s = std.meta.stringToEnum(Style, h.args[1]) orelse break :blk .bad_args;
                        if (s == .auto or s == .label or s == .cut or s == .wire) break :blk .bad_args;
                    }
                    style[net] = s;
                },
                .port => port[net] = h.verb.side(Side, h.args[1]) orelse break :blk .bad_args,
                .rail => {
                    const r = std.meta.stringToEnum(Rail, h.args[1]) orelse break :blk .bad_args;
                    if (r == .auto) break :blk .bad_args;
                    rail[net] = r;
                },
                else => unreachable,
            }
            break :blk .ok;
        };
        verdicts[i] = .of(code);
    }
    // `first` lines in file order: theirs is the order to wire in.
    for (nl.hints, 0..) |h, i| {
        if (h.verb != .first) continue;
        const code: hints.Code = blk: {
            if (h.args.len == 0) break :blk .bad_args;
            for (h.args) |name| if (nl.net(name) == null) break :blk .unknown_name;
            for (h.args) |name| {
                const net = nl.net(name).?.index();
                if (std.mem.indexOfScalar(u32, first.items, net) == null) try first.append(arena, net);
            }
            break :blk .ok;
        };
        verdicts[i] = .of(code);
    }
    // Routes and vias: `<net> x,y ...` (`x y` pairs once split), Manhattan.
    // Their points are counted once the net is known and before its role
    // is asked.
    var routes: std.ArrayList(Route) = .empty;
    for (try hints.admitOrder(arena, nl.hints)) |i| {
        const h = nl.hints[i];
        if (h.verb != .route and h.verb != .via) continue;
        const via = h.verb == .via;
        const code: hints.Code = blk: {
            if (h.args.len == 0) break :blk .bad_args;
            const net = (nl.net(h.args[0]) orelse break :blk .unknown_name).index();
            const pairs = h.args.len - 1;
            if (pairs % 2 != 0 or pairs / 2 < @as(usize, if (via) 1 else 2)) break :blk .bad_args;
            if (!admits(h.verb, roles[net])) break :blk .not_placeable;
            const pts = try arena.alloc(Pt, pairs / 2);
            const u: f64 = @floatFromInt(unit);
            for (pts, 0..) |*p, k| {
                const x = std.fmt.parseFloat(f64, h.args[1 + 2 * k]) catch break :blk .bad_args;
                const y = std.fmt.parseFloat(f64, h.args[2 + 2 * k]) catch break :blk .bad_args;
                if (!std.math.isFinite(x) or !std.math.isFinite(y) or @abs(x) > 1e6 or @abs(y) > 1e6) break :blk .bad_args;
                p.* = .{ .x = @intFromFloat(@round(x * u)), .y = @intFromFloat(@round(y * u)) };
                if (k > 0 and !via and (p.x == pts[k - 1].x) == (p.y == pts[k - 1].y)) break :blk .bad_args;
            }
            try routes.append(arena, .{ .net = net, .pts = pts, .via = via, .line = @intCast(i) });
            break :blk .ok;
        };
        verdicts[i] = .of(code);
    }
    // Unless a line says: a supply is one bar over its pins; a ground a
    // symbol at each pin, one per branch, as the book draws it; a reference
    // the engine gave a circuit with no ground is its bottom wire, as people
    // draw it: one bar and no symbol.
    for (rail, roles, 0..) |*r, role, net| {
        if (r.* != .auto) continue;
        r.* = switch (role) {
            .supply => .bar,
            .sink => if (sch.isReference(nl, roles, @intCast(net))) .plain else .each,
            .input, .bias, .internal, .output => continue,
        };
    }
    return .{ .style = style, .port = port, .rail = rail, .first = first.items, .routes = routes.items };
}

// ---- private ----

/// Whether `verb` says something of a net of `role`: a rail is its symbols,
/// never named or wired; an input is a port at its pins, never one wire. A
/// verb that is no net line's says nothing of any.
fn admits(verb: hints.Verb, role: Role) bool {
    const rail = role.isRail();
    return switch (verb) {
        .label => !rail,
        .wire, .route, .via => !rail and role != .input,
        .port => role == .input or role == .output,
        .rail => rail,
        else => false,
    };
}
