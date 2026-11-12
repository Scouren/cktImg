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
/// wire. The defaults are the pitch people draw at (half a unit between
/// two devices in series, a wire and a rail symbol half a unit from their
/// pin: 5,274 hand-drawn schematics, Analog Canvas gallery). A
/// length moves nothing to another row or column: rows, columns and order
/// are the layout's.
pub const Layout = struct {
    /// Between neighbouring rows: the wire between two devices of one column.
    stack: f32 = 0.5,
    /// Between neighbouring columns.
    series: f32 = 1.0,
    /// A pin to its supply or ground symbol; the supply bar over its pins.
    rail: f32 = 0.5,
    /// Whether a supply bar runs on `rail` past its outer pins, its ends
    /// T's and not corners: a rail, as half the hand drawings draw one
    /// (1,258 of 2,506 supply bars; the rest end on their outer pins).
    rail_past: bool = true,
    /// A pin to its input or output port.
    terminal: f32 = 0.5,
    /// A pin to its net label.
    label: f32 = 0.5,
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
    /// still wired (`thin.zig`). People seldom draw more than two; three
    /// writes about as many names as they do (10,492 against their 11,371
    /// over 5,263 hand-drawn schematics; two writes 12,241).
    cross_max: u32 = 3,
    /// Device columns a row of the drawing holds before it wraps into rows
    /// of columns, one under the other (`wrap.zig`); 0 keeps one row. Eight
    /// is a person's page: drawn so, 5,263 reference circuits are as wide
    /// as their hand drawings at the median. A deck's `*@ shelf` line says
    /// otherwise for that deck.
    shelf: u32 = 8,
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
