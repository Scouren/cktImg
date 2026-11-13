//! The `lint.zon` settings file, three tables:
//!
//! - `.layout`: the drawing's lengths and the router's costs
//!   (docs/ALGORITHM.md §4);
//! - `.rules`: one severity per lint rule (`lint.zig`);
//! - `.render`: colours and line widths for the TikZ emitter.
//!
//! Lengths are in units, one unit being a two-pin symbol from pin end to pin
//! end. Every key is optional; an absent key keeps its default, and an
//! unrecognized key or a malformed value is reported, never fatal — failing
//! to draw a schematic over a typo in a style file is the wrong trade. Keys
//! of the wire-first layout whose rules went with it (`min_pitch`,
//! `junction`, `bend`) are reported as unknown.
//!
//! ```zon
//! .{ .layout = .{ .stack = 1.5 }, .rules = .{ .no_ground = .err }, .render = .{ .wire = "000000" } }
//! ```
//!
//! Human Rules:
//! - config.1 (habit) By default, two devices in series in one column
//!   stand half a unit apart or more, and the trunk that pins facing one
//!   way meet on half a unit from its pin. People: 18,863 of the 20,127
//!   pairs in series in one column of 5,263 hand-drawn schematics stand
//!   half a unit apart or more, half a unit the commonest gap (30.2%); a
//!   pin's first piece of wire to a corner or a T is half a unit at the
//!   median, and the commonest (38.5% of 90,607). `Layout.stack`,
//!   `Layout.tap`
//! - config.2 (habit) Neighbouring columns stand one unit apart or more.
//!   People: 30,907 of 35,678 neighbouring columns (86.6%), 1.75 units at
//!   the median. `Layout.series`
//! - config.3 (habit) A supply bar is one of the two forms people draw:
//!   by default a named rail running past its outer pins, its ends T's and
//!   not corners, no symbol on it (people 1,255 of 1,370 named bars); off,
//!   a bar carrying its symbol and ending on its outer pins (1,083 of 1,140
//!   bars with a symbol). `Layout.rail_past`
//! - config.4 (habit) An input or output port, and a net label, stands
//!   half a unit from its pin. People: 15,113 of 16,816 ports stand half a
//!   unit or more from the pin or wire they join (three quarters at the
//!   median); their net labels name no net, so a label's distance is not
//!   in the hand drawings. `Layout.terminal`, `Layout.label`
//! - config.5 (choice) A wire keeps a quarter unit from another net's wire
//!   or point: the router's room, so two nets never read as one.
//!   `Layout.clearance`
//! - config.6 (choice) A bend costs the router one unit of wire, a
//!   crossing of another net's wire two: weights that trade length for
//!   fewer bends and crossings. `Layout.bend_cost`, `Layout.cross_cost`
//! - config.7 (habit) A drawing is closed up: its empty room taken out
//!   toward the mirror axis and the top, down to the lengths above.
//!   People: nine in ten of their neighbouring columns stand 4.0 units
//!   apart or less, and of their devices one under the other 3.5 (35,678
//!   and 27,035 pairs); the engine's own stand 5.25 and 5.25.
//!   `Layout.compact`
//! - config.8 (habit) One internal net's wire crosses at most three wires
//!   of other nets (rails aside); a net crossing more is joined by name,
//!   its near pins still wired. People: of the 4,567 wires that cross
//!   another net's, 4,417 cross at most three (4,232 at most two); three
//!   writes about as many names as they do (10,492 against their 11,371
//!   over 5,263 hand-drawn schematics; two writes 12,241).
//!   `Layout.cross_max`
//! - config.9 (habit) A row of the drawing holds twelve device columns
//!   before it wraps into rows of columns, one under the other, unless a
//!   `*@ shelf` line says otherwise. People: of the 686 circuits eight
//!   columns wrapped, 504 are drawn in one band of rows, 18.0 units wide
//!   and 9.0 high at the median (eight: 14.8 by 15.2; twelve: 17.2 by
//!   13.2), in 5,263 hand-drawn schematics. `Layout.shelf`
//! - config.10 (choice) Wires are drawn blue (`1565c0`) 1.5 pt wide,
//!   symbols 1.2 pt: the TikZ emitter's own style. `Render`
//! - config.11 (choice) A rail symbol stands half a unit from its pin.
//!   People: on the pin itself in 10,885 of 18,313 rail symbols (6,883 of
//!   8,367 on a two-pin part's end, 3,612 of 8,921 on a transistor's), half
//!   a unit away in a third. `Layout.rail`
//!
//! Contents:
//! - `pub const Layout = struct`, `pub const Render = struct`
//! - `pub const Config = struct`, `Config.default`
//! - `Config.parse(arena: Allocator, text: []const u8, diags: ?*std.ArrayList(Diagnostic)) Allocator.Error!Config`
//! - `Config.load(arena: Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, diags: ?*std.ArrayList(Diagnostic)) Allocator.Error!Config`
//! - `pub const Diagnostic = struct`, `Diagnostic.Kind`

const std = @import("std");
const Allocator = std.mem.Allocator;
const Zoir = std.zig.Zoir;
const lint = @import("lint.zig");

/// The drawing's lengths, in units, and the router's costs, in units of
/// wire. A default is a length people draw at or above, a rail symbol's
/// aside (the counts are the Human Rules' above, from 5,263 hand-drawn
/// schematics). A length moves nothing to another row or column: rows,
/// columns and order are the layout's.
pub const Layout = struct {
    // People: 18,863 of 20,127 pairs in series in one column stand this
    // far apart or more, and this far is the commonest (30.2%).
    /// Between neighbouring rows: the wire between two devices of one column.
    stack: f32 = 0.5,
    // People: 30,907 of 35,678 neighbouring columns stand this far apart
    // or more (1.75 units at the median).
    /// Between neighbouring columns.
    series: f32 = 1.0,
    // People set a rail symbol on its pin in 10,885 of 18,313, this far
    // from it in a third.
    /// A pin to its supply or ground symbol; the supply bar over its pins.
    rail: f32 = 0.5,
    // People: a named bar with no symbol runs past both ends in 1,255 of
    // 1,370; a bar of wire carrying the supply's symbol ends on its outer
    // pins in 1,083 of 1,140.
    /// Which of people's two supply bars is drawn: on, a named rail running
    /// `rail` past its outer pins, no symbol on it (1,255 of 1,370 named
    /// bars); off, a bar carrying its symbol and ending on its outer pins
    /// (1,083 of 1,140 bars with a symbol).
    rail_past: bool = true,
    // People: 15,113 of 16,816 ports stand this far or more from the pin
    // or wire they join (three quarters of a unit at the median).
    /// A pin to its input or output port.
    terminal: f32 = 0.5,
    /// A pin to its net label.
    label: f32 = 0.5,
    // People: a pin's first piece of wire to a corner or a T is this long
    // at the median and most often (38.5% of 90,607).
    /// Pins facing one way to the trunk that joins them.
    tap: f32 = 0.5,
    /// The router's room between a wire and another net's wire or point.
    clearance: f32 = 0.25,
    /// What the router pays for a bend, in wire.
    bend_cost: f32 = 1.0,
    /// What the router pays to cross another net's wire, in wire.
    cross_cost: f32 = 2.0,
    /// Whether the drawing is closed up (`compact.zig`): its empty room
    /// taken out toward the mirror axis and the top, down to `series`
    /// between columns, `stack` between rows, `tap` of wire between two
    /// symbols, bends or junctions, and `clearance`.
    compact: bool = true,
    /// The most wires of other nets (rails aside) one internal net's wire
    /// may cross: a net crossing more is joined by name, its near pins
    /// still wired (`thin.zig`). Of the 4,567 wires people draw across
    /// another net's, 4,417 cross at most three; three writes about as many
    /// names as they do (10,492 against their 11,371 over 5,263 hand-drawn
    /// schematics; two writes 12,241).
    cross_max: u32 = 3,
    /// Device columns a row of the drawing holds before it wraps into rows
    /// of columns, one under the other (`wrap.zig`); 0 keeps one row. Twelve
    /// is a person's page: of the 686 reference circuits eight wrapped,
    /// people draw 504 in one band, 18.0 by 9.0 units at the median. A
    /// deck's `*@ shelf` line says otherwise for that deck.
    shelf: u32 = 12,
};

/// How the TikZ emitter strokes a drawing.
pub const Render = struct {
    /// Wire colour: six hex digits, no `#`.
    wire: []const u8 = "1565c0",
    /// Symbol stroke width, in points.
    sym_w: f32 = 1.2,
    /// Wire stroke width, in points.
    wire_w: f32 = 1.5,
};

pub const Config = struct {
    layout: Layout = .{},
    rules: lint.Rules = .{},
    render: Render = .{},

    pub const default: Config = .{};

    /// Parse a `lint.zon` document. `arena` backs the diagnostics. Malformed
    /// input is reported through `diags` and leaves the affected key at its
    /// default.
    pub fn parse(arena: Allocator, text: []const u8, diags: ?*std.ArrayList(Diagnostic)) Allocator.Error!Config {
        var cfg: Config = .default;
        var sink: Sink = .{ .arena = arena, .out = diags };

        const src = try arena.dupeSentinel(u8, text, 0);
        const ast = try std.zig.Ast.parse(arena, src, .{ .mode = .zon });
        if (ast.errors.len > 0) {
            try sink.add(lineOfToken(ast, ast.errors[0].token), "<document>", .bad_value);
            return cfg;
        }
        const zoir_value = try std.zig.ZonGen.generate(arena, ast, .{ .parse_str_lits = false });
        const zoir = &zoir_value;
        if (zoir.hasCompileErrors()) {
            try sink.add(1, "<document>", .bad_value);
            return cfg;
        }
        const tables = switch (Zoir.Node.Index.root.get(zoir)) {
            .empty_literal => return cfg,
            .struct_literal => |s| s,
            else => {
                try sink.add(1, "<document>", .bad_value);
                return cfg;
            },
        };
        // A table of the document is a field of `Config`.
        outer: for (tables.names, 0..) |name, i| {
            const key = name.get(zoir);
            const node = tables.vals.at(@intCast(i));
            inline for (@typeInfo(Config).@"struct".field_names, @typeInfo(Config).@"struct".field_types) |table, T| {
                if (std.mem.eql(u8, key, table)) {
                    try patch(T, arena, ast, zoir, node, &@field(cfg, table), &sink);
                    continue :outer;
                }
            }
            try sink.add(lineOfNode(ast, zoir, node), key, .unknown_key);
        }
        return cfg;
    }

    /// Load from `path` in `dir`; a missing file gives the defaults.
    pub fn load(arena: Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, diags: ?*std.ArrayList(Diagnostic)) Allocator.Error!Config {
        const text = dir.readFileAlloc(io, path, arena, .limited(1 << 20)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.FileNotFound => return .default,
            else => {
                var sink: Sink = .{ .arena = arena, .out = diags };
                try sink.add(1, "<file>", .bad_value);
                return .default;
            },
        };
        return parse(arena, text, diags);
    }
};

/// A complaint about the config document. Lines are 1-based.
pub const Diagnostic = struct {
    line: u32,
    key: []const u8,
    kind: Kind,

    pub const Kind = enum { unknown_key, bad_value };
};

/// Overwrites only the fields `node` names; each is parsed on its own, so one
/// bad value costs one key rather than the table.
fn patch(comptime T: type, arena: Allocator, ast: std.zig.Ast, zoir: *const Zoir, node: Zoir.Node.Index, out: *T, sink: *Sink) Allocator.Error!void {
    const lit = switch (node.get(zoir)) {
        .empty_literal => return,
        .struct_literal => |s| s,
        else => return sink.add(lineOfNode(ast, zoir, node), @typeName(T), .bad_value),
    };
    outer: for (lit.names, 0..) |name, i| {
        const key = name.get(zoir);
        const child = lit.vals.at(@intCast(i));
        inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |f_name, f_type| {
            if (std.mem.eql(u8, key, f_name)) {
                // Zig 0.17's `fromZoir` drops its `.node` and parses the
                // root, so the value's own source is parsed instead.
                const value_src = try arena.dupeSentinel(u8, ast.getNodeSource(child.getAstNode(zoir)), 0);
                var zd: std.zon.parse.Diagnostics = undefined;
                const v = std.zon.parse.fromSlice(f_type, .{ .gpa = arena, .arena = arena, .source = value_src, .diagnostics = &zd }) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.ParseZon => {
                        try sink.add(lineOfNode(ast, zoir, child), key, .bad_value);
                        continue :outer;
                    },
                };
                // A length must be a length.
                if (comptime f_type == f32) if (!(v >= 0)) {
                    try sink.add(lineOfNode(ast, zoir, child), key, .bad_value);
                    continue :outer;
                };
                if (comptime f_type == []const u8) if (!validHex(v)) {
                    try sink.add(lineOfNode(ast, zoir, child), key, .bad_value);
                    continue :outer;
                };
                @field(out, f_name) = v;
                continue :outer;
            }
        }
        try sink.add(lineOfNode(ast, zoir, child), key, .unknown_key);
    }
}

const Sink = struct {
    arena: Allocator,
    out: ?*std.ArrayList(Diagnostic),

    fn add(self: *Sink, line: u32, key: []const u8, kind: Diagnostic.Kind) Allocator.Error!void {
        const out = self.out orelse return;
        try out.append(self.arena, .{ .line = line, .key = try self.arena.dupe(u8, key), .kind = kind });
    }
};

fn lineOfToken(ast: std.zig.Ast, token: std.zig.Ast.TokenIndex) u32 {
    return @intCast(ast.tokenLocation(0, token).line + 1);
}

fn lineOfNode(ast: std.zig.Ast, zoir: *const Zoir, node: Zoir.Node.Index) u32 {
    return lineOfToken(ast, ast.nodeMainToken(node.getAstNode(zoir)));
}

/// Six hex digits: what TikZ's HTML colour model takes.
fn validHex(s: []const u8) bool {
    if (s.len != 6) return false;
    for (s) |c| if (!std.ascii.isHex(c)) return false;
    return true;
}

test "config: rules and render tables" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diags: std.ArrayList(Diagnostic) = .empty;
    const cfg = try Config.parse(arena.allocator(),
        \\.{ .rules = .{ .no_ground = .err, .nonsense = .warn }, .render = .{ .wire = "ff0000", .sym_w = 2 } }
    , &diags);
    try std.testing.expectEqual(lint.Severity.err, cfg.rules.no_ground);
    try std.testing.expectEqualStrings("ff0000", cfg.render.wire);
    try std.testing.expectEqual(2, cfg.render.sym_w);
    try std.testing.expectEqual(1, diags.items.len);
}

test "config: absent keys keep defaults, unknown keys and bad values are reported" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags: std.ArrayList(Diagnostic) = .empty;
    const cfg = try Config.parse(a,
        \\.{
        \\    .render = .{ .sym_w = 2, .wobble = 3, .wire_w = -1 },
        \\    .layout = .{ .stack = 0.5, .min_pitch = 1, .tap = -1 },
        \\}
    , &diags);
    try std.testing.expectEqual(2, cfg.render.sym_w);
    try std.testing.expectEqual((Render{}).wire_w, cfg.render.wire_w); // -1 rejected
    try std.testing.expectEqualStrings((Render{}).wire, cfg.render.wire);
    try std.testing.expectEqual(0.5, cfg.layout.stack);
    try std.testing.expectEqual((Layout{}).tap, cfg.layout.tap); // -1 rejected
    try std.testing.expectEqual((Layout{}).terminal, cfg.layout.terminal);
    try std.testing.expectEqual(4, diags.items.len);
    try std.testing.expectEqualStrings("wobble", diags.items[0].key);
    try std.testing.expectEqual(Diagnostic.Kind.unknown_key, diags.items[0].kind);
    try std.testing.expectEqualStrings("wire_w", diags.items[1].key);
    try std.testing.expectEqual(Diagnostic.Kind.bad_value, diags.items[1].kind);
    // A key whose rule went with the wire-first layout (issue #8).
    try std.testing.expectEqualStrings("min_pitch", diags.items[2].key);
    try std.testing.expectEqual(Diagnostic.Kind.unknown_key, diags.items[2].kind);
    try std.testing.expectEqualStrings("tap", diags.items[3].key);
    try std.testing.expectEqual(Diagnostic.Kind.bad_value, diags.items[3].kind);
}

test "config: a malformed document gives the defaults" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diags: std.ArrayList(Diagnostic) = .empty;
    const cfg = try Config.parse(arena.allocator(), ".{ .render = ", &diags);
    try std.testing.expectEqual((Render{}).sym_w, cfg.render.sym_w);
    try std.testing.expectEqual(1, diags.items.len);
}
