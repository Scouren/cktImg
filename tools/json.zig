//! `cktimg-json`: a SPICE netlist in, the placed schematic as one JSON
//! document out (`src/json.zig` has the shape), for a script that would
//! rather read a file than link the library.
//!
//!     cktimg-json [--config lint.zon] [--symbols file.zon] [--target manifest.json] [--svg out.svg] [--report r.json] [--decisions 1-4] [--from last.json] deck.spice [out.json]
//!
//! The symbol set is the tests' (`tests/symbols.zon`), embedded at build
//! time, or `--symbols file.zon`: a backend whose symbols differ in size or
//! pin positions passes its own, so every wire ends on its pins. `--target` adds a `"target"` block that maps each device's class to
//! the backend's symbol and pin order (docs/TARGETS.md); `--svg` also draws
//! the placement, headless, with the gallery's renderer; `--report` writes the
//! decision report (`src/report.zig`): the checks' findings, each `*@`
//! line's verdict, scores, the engine's decisions as `*@` lines and the
//! lattice rows. `--decisions <rung>` prints the engine's decisions on rungs
//! 1 to `<rung>` as `*@` lines, one per line, to stdout (the JSON then needs
//! an output path): a deck plus them draws the same picture. `--from
//! last.json` relays the deck from its last drawing (this tool's JSON, as
//! written or as someone moved things in it): only what the deck's structure
//! no longer puts where that drawing has it is laid again (`src/relay.zig`).
//!
//! Two things a subcircuit library file needs and SPICE does not give it:
//! a file whose first line is `.subckt` has no title line, so the file name
//! is used as one; and a deck with no top-level devices draws the body of
//! its last `.subckt` (the top cell), its ports as nets, its instances as
//! blocks and its voltage sources in the circuit (a cell has no bench).

const std = @import("std");
const np = @import("NetlistParser");
const symbols = @import("symbols").text;
const svg = @import("svg");

const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const Value = std.json.Value;

const usage =
    \\cktimg-json — place a SPICE netlist and write the geometry as JSON
    \\
    \\Usage: cktimg-json [options] <netlist.spice> [out.json]
    \\
    \\Options:
    \\  --config <path>   layout settings and lint severities from a lint.zon file
    \\  --symbols <path>  device symbols from a .zon symbol file (default: built in)
    \\  --target <path>   map classes to a backend's symbols (docs/TARGETS.md) and
    \\                    add a "target" block to the document
    \\  --svg <path>      also draw the placed schematic as SVG
    \\  --report <path>   also write the decision report: findings, each *@ line's
    \\                    verdict, scores, the engine's decisions, the lattice rows
    \\  --decisions <n>   print the engine's decisions on rungs 1 to n (1 to 4) as
    \\                    *@ lines to stdout
    \\  --from <path>     relay the deck from its last drawing (this tool's JSON):
    \\                    devices stay where it has them, and only what the deck's
    \\                    structure moves, or is new to it, is laid again
    \\  -h, --help        this message
    \\
    \\Exit status: 0 written; 1 bad command line, netlist, config, symbols or manifest
    \\(nothing written).
    \\
;

const Options = struct {
    netlist: []const u8,
    out: ?[]const u8 = null,
    config: ?[]const u8 = null,
    symbols: ?[]const u8 = null,
    target: ?[]const u8 = null,
    svg: ?[]const u8 = null,
    report: ?[]const u8 = null,
    decisions: ?[]const u8 = null,
    from: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const cwd: std.Io.Dir = .cwd();

    const opts = parseArgs(try init.minimal.args.toSlice(arena)) orelse return;

    const raw = cwd.readFileAlloc(io, opts.netlist, arena, .limited(1 << 22)) catch |err| fatal("cannot read netlist '{s}': {t}", .{ opts.netlist, err });
    const cfg: np.Config = if (opts.config) |path| blk: {
        const t = cwd.readFileAlloc(io, path, arena, .limited(1 << 20)) catch |err| fatal("cannot read config '{s}': {t}", .{ path, err });
        var diags: std.ArrayList(np.config.Diagnostic) = .empty;
        const c = try np.Config.parse(arena, t, &diags);
        for (diags.items) |d| std.log.warn("{s}:{d}: {t} '{s}'", .{ path, d.line, d.kind, d.key });
        break :blk c;
    } else .default;
    // Read before placing: a manifest typo is reported before any work.
    const target: ?Target = if (opts.target) |path| blk: {
        const t = cwd.readFileAlloc(io, path, arena, .limited(1 << 22)) catch |err| fatal("cannot read target manifest '{s}': {t}", .{ path, err });
        break :blk Target.parse(arena, t) catch fatal("{s}: {s}", .{ path, Target.why });
    } else null;

    const sym_text = if (opts.symbols) |path|
        cwd.readFileAlloc(io, path, arena, .limited(1 << 22)) catch |err| fatal("cannot read symbols '{s}': {t}", .{ path, err })
    else
        symbols;
    var lib = np.Library.init(gpa);
    defer lib.deinit();
    var sym_diags: std.ArrayList(np.library.ZonDiagnostic) = .empty;
    try lib.loadZon(arena, sym_text, &sym_diags);
    if (sym_diags.items.len > 0) fatal("symbols: {s}: {t}", .{ sym_diags.items[0].class, sym_diags.items[0].err });

    var diag: np.netlist.Diagnostic = .{};
    const srcs = deckSources(gpa, arena, &lib, opts.netlist, raw, &diag) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => fatal("{s}:{d}: {t} near '{s}'", .{ opts.netlist, diag.line, err, diag.token() }),
    };
    if (opts.from) |path| {
        const last = cwd.readFileAlloc(io, path, arena, .limited(1 << 26)) catch |err| fatal("cannot read drawing '{s}': {t}", .{ path, err });
        const lines = stays(arena, last, lib.unit) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => fatal("{s}: not a cktimg-json drawing", .{path}),
        };
        srcs[0] = try std.mem.concat(arena, u8, &.{ srcs[0], "\n", lines });
    }
    var placed = placeSelected(gpa, arena, &cfg, &lib, srcs, if (opts.from == null and opts.symbols == null and opts.target == null) raw else null, &diag) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => fatal("{s}:{d}: {t} near '{s}'", .{ opts.netlist, diag.line, err, diag.token() }),
    };
    defer placed.deinit();

    if (opts.svg) |path| {
        const pic = try svg.alloc(gpa, &placed, &lib, .{});
        defer gpa.free(pic);
        cwd.writeFile(io, .{ .sub_path = path, .data = pic }) catch |err| fatal("cannot write '{s}': {t}", .{ path, err });
    }

    // Parsing and roles are pure: the same sources give the netlist `place`
    // drew.
    const rung: ?u8 = if (opts.decisions) |word| (std.fmt.parseInt(u8, word, 10) catch 0) else null;
    if (rung) |r| if (r < 1 or r > 4) fatal("--decisions takes 1 to 4, not '{s}'", .{opts.decisions.?});
    if (opts.report != null or rung != null) {
        var nl = try np.netlist.parse(gpa, srcs, null);
        defer nl.deinit(gpa);
        const roles = try np.guessRoles(gpa, &nl);
        defer gpa.free(roles);
        if (opts.report) |path| {
            var rw: Writer.Allocating = .init(arena);
            try np.report.write(gpa, &rw.writer, &placed, &lib, &nl, roles, cfg.layout);
            cwd.writeFile(io, .{ .sub_path = path, .data = rw.written() }) catch |err| fatal("cannot write '{s}': {t}", .{ path, err });
        }
        if (rung) |r| {
            const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
            const sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{ .shelf = cfg.layout.shelf });
            var buf: [64 * 1024]u8 = undefined;
            var sw = std.Io.File.stdout().writerStreaming(io, &buf);
            for (try np.report.decisions(arena, &nl, &st, &sk, &placed, lib.unit, r)) |line| try sw.interface.print("{s}\n", .{line});
            try sw.interface.flush();
            if (opts.out == null) return;
        }
    }

    // The rails and ports the layout added have no name; a consumer that
    // keys symbols by name needs one.
    const names = try arena.alloc([:0]const u8, placed.deviceCount());
    for (names, placed.dev_name, placed.dev_class, 0..) |*n, old, c, d| {
        n.* = if (old.len > 0) old else try std.fmt.allocPrintSentinel(arena, "_{s}{d}", .{ lib.at(c).name, d }, 0);
    }
    placed.dev_name = names;

    // Resolved before a byte is written, so a refusal leaves no half file.
    const block: ?[]u8 = if (target) |t| t.block(arena, &placed, &lib) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => fatal("{s}: {s}", .{ opts.target.?, Target.why }),
    } else null;

    var aw: Writer.Allocating = .init(arena);
    try np.json.write(&placed, &lib, &aw.writer);
    var doc = aw.written();
    if (block) |b| {
        // `json.write` ends the document with "\n}\n": add one member before it.
        doc = try std.mem.concat(arena, u8, &.{ doc[0 .. doc.len - 3], ",\n  \"target\": ", b, "\n}\n" });
    }
    if (opts.out) |path| {
        cwd.writeFile(io, .{ .sub_path = path, .data = doc }) catch |err| fatal("cannot write '{s}': {t}", .{ path, err });
    } else {
        var buf: [64 * 1024]u8 = undefined;
        var sw = std.Io.File.stdout().writerStreaming(io, &buf);
        try sw.interface.writeAll(doc);
        try sw.interface.flush();
    }
}

/// The sources to place for deck `raw` (see the module comment): itself, or
/// its top cell's body followed by the deck for the definitions.
pub fn deckSources(gpa: Allocator, arena: Allocator, lib: ?*np.Library, path: []const u8, raw: []const u8, diag: *np.netlist.Diagnostic) ![][]const u8 {
    const first = std.mem.trimStart(u8, raw, " \t\r\n");
    const text = if (std.ascii.startsWithIgnoreCase(first, ".subckt")) try std.fmt.allocPrint(arena, "{s}\n{s}", .{ path, raw }) else raw;
    var nl = try np.netlist.parse(gpa, &.{text}, diag);
    defer nl.deinit(gpa);
    if (nl.graph.edgeCount() > 0 or nl.defs.len == 0) return try arena.dupe([]const u8, &.{text});
    const top = nl.defs[nl.defs.len - 1];
    const title_end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    const rest = text[@min(title_end + 1, text.len)..];
    const body = try std.fmt.allocPrint(arena, "{s}\n{s}", .{ text[0..title_end], top.body });
    const inline_lines = try cellSources(gpa, arena, &.{ body, rest }, diag);
    const with_sources = try std.mem.concat(arena, u8, &.{ body, "\n", inline_lines });
    const roles = try prepareCell(gpa, arena, &.{ with_sources, rest }, top.ports, lib, diag);
    return try arena.dupe([]const u8, &.{ try std.mem.concat(arena, u8, &.{ with_sources, roles }), rest });
}

fn placeSelected(gpa: Allocator, arena: Allocator, cfg: *const np.Config, lib: *np.Library, srcs: []const []const u8, raw: ?[]const u8, diag: *np.netlist.Diagnostic) !np.Placed {
    var nl = try np.netlist.parse(gpa, srcs, diag);
    defer nl.deinit(gpa);
    const pairs = if (raw) |source| try np.parent_outputs.eligible(arena, try np.parent_context.bind(arena, source, &nl, &np.parent_context.standard_rails)) else &.{};
    return np.placeBound(gpa, gpa, cfg, lib, &nl, pairs);
}

/// The `*@ weak at` stays of a drawing: one line per named device of
/// `text` (this tool's JSON), its `pos` in units of `unit` and its turn.
/// A device the deck no longer has, or does not draw, is a line the engine
/// rejects and nothing more. Error: `text` is not such a document.
fn stays(arena: Allocator, text: []const u8, unit: i32) ![]const u8 {
    const doc = try std.json.parseFromSliceLeaky(Value, arena, text, .{});
    if (doc != .object) return error.NotADrawing;
    const devices = doc.object.get("devices") orelse return error.NotADrawing;
    if (devices != .array) return error.NotADrawing;
    var out: std.ArrayList(u8) = .empty;
    const u: f64 = @floatFromInt(unit);
    for (devices.array.items) |dev| {
        if (dev != .object) return error.NotADrawing;
        const name = dev.object.get("name") orelse return error.NotADrawing;
        const pos = dev.object.get("pos") orelse return error.NotADrawing;
        const rot = dev.object.get("rot") orelse return error.NotADrawing;
        const mirror = dev.object.get("mirror") orelse return error.NotADrawing;
        if (name != .string or pos != .array or pos.array.items.len != 2 or rot != .integer or mirror != .bool) return error.NotADrawing;
        // A rail or port symbol the layout added: the engine places those.
        if (name.string.len == 0 or name.string[0] == '_' or std.mem.indexOfAny(u8, name.string, " \t\r\n") != null) continue;
        var xy: [2]f64 = undefined;
        for (&xy, pos.array.items) |*v, c| v.* = switch (c) {
            .integer => |i| @floatFromInt(i),
            .float => |x| x,
            else => return error.NotADrawing,
        };
        if (rot.integer < 0 or rot.integer > 3) return error.NotADrawing;
        try out.print(arena, "*@ weak at {s} ", .{name.string});
        // Written as `report.decisions` writes a place: whole, or to 1e-4.
        for (xy) |v| if (@rem(v, u) == 0) try out.print(arena, "{d} ", .{v / u}) else try out.print(arena, "{d:.4} ", .{v / u});
        try out.print(arena, "{s}{d}\n", .{ if (mirror.bool) "MR" else "R", rot.integer * 90 });
    }
    return out.items;
}

/// `*@ weak driver <src> inline` lines for the top cell's voltage sources:
/// a source in a cell's body is a device of the circuit, wired where it
/// stands (as people draw 971 of 972 in 5,263 hand-drawn schematics), not a
/// bench source to set apart.
fn cellSources(gpa: Allocator, arena: Allocator, sources: []const []const u8, diag: *np.netlist.Diagnostic) ![]const u8 {
    var nl = try np.netlist.parse(gpa, sources, diag);
    defer nl.deinit(gpa);
    var out: Writer.Allocating = .init(arena);
    for (nl.graph.edges.items(.kind), nl.graph.edges.items(.name)) |kind, name| {
        if (kind == .vsource) try out.writer.print("*@ weak driver {s} inline\n", .{name});
    }
    return out.written();
}

/// Prepare this top cell’s generated amplifier frame from its declared
/// interface. Emit `*@ weak role` lines for its ports whose names say nothing of
/// their role (R1 leaves them internal): a port only gates hang on is an
/// input, any other an output. So every port is drawn as one, and a port on
/// one gate is no dangling pin.
fn prepareCell(gpa: Allocator, arena: Allocator, sources: []const []const u8, ports: []const []const u8, lib: ?*np.Library, diag: *np.netlist.Diagnostic) ![]const u8 {
    var nl = try np.netlist.parse(gpa, sources, diag);
    defer nl.deinit(gpa);
    if (lib) |draw_lib| try @import("regulator.zig").select(arena, &nl, ports, draw_lib);
    const roles = try np.guessRoles(gpa, &nl);
    defer gpa.free(roles);
    const driven = try gpa.alloc(bool, roles.len);
    defer gpa.free(driven);
    @memset(driven, false);
    for (nl.graph.edges.items(.kind), 0..) |kind, d| {
        const transistor = switch (kind) {
            .mosfet, .bjt, .jfet, .mesfet => true,
            else => false,
        };
        // A transistor drives its first and third nets; its gate and body listen.
        for (nl.graph.members(.from(d)), 0..) |net, pin| {
            if (!transistor or pin == 0 or pin == 2) driven[net.index()] = true;
        }
    }
    var out: Writer.Allocating = .init(arena);
    for (ports) |port| {
        const net = nl.net(port) orelse continue;
        if (roles[net.index()] != .internal) continue;
        try out.writer.print("*@ weak role {s} {s}\n", .{ port, if (driven[net.index()]) "output" else "input" });
    }
    return out.written();
}

/// A target manifest (docs/TARGETS.md): class → the backend's symbol and
/// the order it wants the pins in.
const Target = struct {
    root: std.json.ObjectMap,
    classes: std.json.ObjectMap,
    /// `unmapped.mode`.
    mode: enum { box, skip, @"error" },

    /// The reason for the last `error.Bad`, for the message.
    var why: []const u8 = "";
    var why_buf: [256]u8 = undefined;

    fn bad(comptime fmt: []const u8, args: anytype) error{Bad} {
        why = std.fmt.bufPrint(&why_buf, fmt, args) catch &why_buf;
        return error.Bad;
    }

    fn parse(arena: Allocator, text: []const u8) !Target {
        const root = std.json.parseFromSliceLeaky(Value, arena, text, .{}) catch |err| return bad("malformed JSON ({t})", .{err});
        if (root != .object) return bad("top level must be an object", .{});
        const o = root.object;
        if (o.get("target") == null or o.get("target").? != .string) return bad("\"target\" must be a string", .{});
        const v = o.get("version") orelse return bad("missing \"version\"", .{});
        if (v != .integer or v.integer != 1) return bad("\"version\" must be 1", .{});
        const u = o.get("unmapped") orelse return bad("missing \"unmapped\"", .{});
        if (u != .object) return bad("\"unmapped\" must be an object", .{});
        const m = u.object.get("mode") orelse return bad("\"unmapped\" has no \"mode\"", .{});
        const mode = if (m == .string) std.meta.stringToEnum(@FieldType(Target, "mode"), m.string) else null;
        if (mode == null) return bad("\"unmapped.mode\" must be box, skip or error", .{});
        if (mode.? == .box) try checkEntry("unmapped", u);
        const c = o.get("classes") orelse return bad("missing \"classes\"", .{});
        if (c != .object) return bad("\"classes\" must be an object", .{});
        var it = c.object.iterator();
        while (it.next()) |e| try checkEntry(e.key_ptr.*, e.value_ptr.*);
        return .{ .root = o, .classes = c.object, .mode = mode.? };
    }

    fn checkEntry(key: []const u8, e: Value) !void {
        if (e != .object) return bad("class \"{s}\" must be an object", .{key});
        const s = e.object.get("sym") orelse return bad("class \"{s}\" has no \"sym\"", .{key});
        if (s != .string or s.string.len == 0) return bad("class \"{s}\": \"sym\" must be a non-empty string", .{key});
        if (e.object.get("pins")) |p| {
            if (p != .array) return bad("class \"{s}\": \"pins\" must be an array of terminal names", .{key});
            for (p.array.items) |t| if (t != .string) return bad("class \"{s}\": \"pins\" must be an array of terminal names", .{key});
        }
    }

    /// The mapping for `class`: by its name, or for a subcircuit block
    /// (`block:<name>`) by the subcircuit's name.
    fn lookup(t: *const Target, class: []const u8) ?Value {
        if (t.classes.get(class)) |e| return e;
        if (std.mem.startsWith(u8, class, "block:")) return t.classes.get(class["block:".len..]);
        return null;
    }

    /// The `"target"` member's value for `p`. Fails when `unmapped` is
    /// `error` and a class has no mapping, or a `pins` list is not a
    /// permutation of that class's terminals.
    fn block(t: *const Target, arena: Allocator, p: *const np.Placed, lib: *const np.Library) ![]u8 {
        var aw: Writer.Allocating = .init(arena);
        var s: std.json.Stringify = .{ .writer = &aw.writer };
        try s.beginObject();
        try s.objectField("name");
        try s.write(t.root.get("target").?);
        try s.objectField("version");
        try s.write(1);
        inline for (.{ "units", "style" }) |k| if (t.root.get(k)) |v| {
            try s.objectField(k);
            try s.write(v);
        };
        try s.objectField("devices");
        try s.beginArray();
        for (0..p.deviceCount()) |d| {
            const class = lib.at(p.dev_class[d]);
            const entry = t.lookup(class.name) orelse switch (t.mode) {
                .box => t.root.get("unmapped").?,
                .skip => continue,
                .@"error" => return bad("no mapping for class \"{s}\", and \"unmapped\" is \"error\"", .{class.name}),
            };
            // The pins the document lists: one per class terminal the card has.
            const lo, const hi = p.pinRange(d);
            const n = @min(hi - lo, class.terminals.len);
            const order = try arena.alloc(usize, n);
            for (order, 0..) |*o, k| o.* = k;
            if (entry.object.get("pins")) |pins| {
                if (pins.array.items.len != n) return bad("class \"{s}\": \"pins\" has {d} names, the class has {d} terminals", .{ class.name, pins.array.items.len, n });
                for (pins.array.items, order, 0..) |name, *o, j| {
                    o.* = for (class.terminals[0..n], 0..) |term, k| {
                        if (std.mem.eql(u8, term.name, name.string)) break k;
                    } else return bad("class \"{s}\": \"{s}\" is not one of its terminals", .{ class.name, name.string });
                    for (order[0..j]) |earlier| if (earlier == o.*) return bad("class \"{s}\": \"{s}\" is listed twice", .{ class.name, name.string });
                }
            }
            try s.beginObject();
            try s.objectField("device");
            try s.write(d);
            try s.objectField("name");
            try s.write(p.dev_name[d]);
            try s.objectField("class");
            try s.write(class.name);
            try s.objectField("sym");
            try s.write(entry.object.get("sym").?);
            if (entry.object.get("style")) |st| {
                try s.objectField("style");
                try s.write(st);
            }
            try s.objectField("pins");
            try s.write(order);
            try s.endObject();
        }
        try s.endArray();
        try s.endObject();
        return aw.written();
    }
};

fn parseArgs(argv: []const [:0]const u8) ?Options {
    var opts: Options = .{ .netlist = "" };
    var positional: usize = 0;
    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            std.debug.print("{s}", .{usage});
            return null;
        }
        const slot: ?*?[]const u8 = if (std.mem.eql(u8, a, "--config")) &opts.config else if (std.mem.eql(u8, a, "--symbols")) &opts.symbols else if (std.mem.eql(u8, a, "--target")) &opts.target else if (std.mem.eql(u8, a, "--svg")) &opts.svg else if (std.mem.eql(u8, a, "--report")) &opts.report else if (std.mem.eql(u8, a, "--decisions")) &opts.decisions else if (std.mem.eql(u8, a, "--from")) &opts.from else null;
        if (slot) |s| {
            i += 1;
            if (i >= argv.len) fatal("{s} needs a path", .{a});
            s.* = argv[i];
        } else if (a.len > 1 and a[0] == '-') {
            fatal("unknown option '{s}'\n{s}", .{ a, usage });
        } else {
            switch (positional) {
                0 => opts.netlist = a,
                1 => opts.out = a,
                else => fatal("too many arguments\n{s}", .{usage}),
            }
            positional += 1;
        }
    }
    if (positional == 0) fatal("no netlist\n{s}", .{usage});
    return opts;
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err(fmt, args);
    std.process.exit(1);
}

test "target: a manifest maps classes and subcircuits, and pins are checked" {
    const gpa = std.testing.allocator;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var lib = np.Library.init(gpa);
    defer lib.deinit();
    try lib.loadZon(arena, symbols, null);
    var placed = try np.place(gpa, &.default, &lib, &.{
        \\t
        \\.subckt amp in out vdd
        \\R1 vdd out 1k
        \\M1 out in 0 0 nch
        \\.ends
        \\V1 vdd 0 1
        \\X1 a b vdd amp
        \\R2 b 0 1k
        \\R3 a vdd 1k
    }, null);
    defer placed.deinit();

    const t = try Target.parse(arena,
        \\{ "target": "t", "version": 1, "units": { "scale": 2 }, "unmapped": { "mode": "skip" },
        \\  "classes": { "res": { "sym": "r.sym", "pins": ["b", "a"] }, "amp": { "sym": "amp.sym", "style": { "k": 1 } } } }
    );
    const out = try t.block(arena, &placed, &lib);
    const doc = try std.json.parseFromSliceLeaky(Value, arena, out, .{});
    try std.testing.expectEqual(2, doc.object.get("units").?.object.get("scale").?.integer);
    var amp = false;
    var res: usize = 0;
    for (doc.object.get("devices").?.array.items) |e| {
        const sym = e.object.get("sym").?.string;
        const pins = e.object.get("pins").?.array.items;
        if (std.mem.eql(u8, sym, "amp.sym")) {
            amp = true;
            try std.testing.expectEqualStrings("block:amp", e.object.get("class").?.string);
            try std.testing.expectEqual(3, pins.len);
        } else {
            try std.testing.expectEqualStrings("r.sym", sym);
            try std.testing.expectEqual(1, pins[0].integer);
            res += 1;
        }
    }
    try std.testing.expect(amp);
    try std.testing.expectEqual(2, res); // nothing else is mapped: skipped

    try std.testing.expectError(error.Bad, Target.parse(arena, "{ \"target\": \"t\", \"version\": 2, \"unmapped\": { \"mode\": \"skip\" }, \"classes\": {} }"));
    try std.testing.expectError(error.Bad, Target.parse(arena, "{ \"target\": \"t\", \"version\": 1, \"unmapped\": { \"mode\": \"box\" }, \"classes\": {} }"));
    const wrong = try Target.parse(arena, "{ \"target\": \"t\", \"version\": 1, \"unmapped\": { \"mode\": \"skip\" }, \"classes\": { \"res\": { \"sym\": \"r\", \"pins\": [\"a\", \"x\"] } } }");
    try std.testing.expectError(error.Bad, wrong.block(arena, &placed, &lib));
    const strict = try Target.parse(arena, "{ \"target\": \"t\", \"version\": 1, \"unmapped\": { \"mode\": \"error\" }, \"classes\": {} }");
    try std.testing.expectError(error.Bad, strict.block(arena, &placed, &lib));
}

test "deck: a subcircuit file draws its top cell" {
    const gpa = std.testing.allocator;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diag: np.netlist.Diagnostic = .{};
    const srcs = try deckSources(gpa, arena, null, "cell.spice",
        \\.subckt inv in out vdd vss
        \\XM1 out in vss vss sky130_fd_pr__nfet_01v8 W=1 L=0.15
        \\XM2 out in vdd vdd sky130_fd_pr__pfet_01v8 W=2 L=0.15
        \\.ends inv
        \\.subckt buf in out vdd vss
        \\X1 in mid vdd vss inv
        \\X2 mid out vdd vss inv
        \\.ends buf
    , &diag);
    var nl = try np.netlist.parse(gpa, srcs, &diag);
    defer nl.deinit(gpa);
    try std.testing.expectEqualStrings("cell.spice", nl.title);
    try std.testing.expectEqual(2, nl.graph.edgeCount()); // buf's x1, x2 as blocks
    try std.testing.expectEqualStrings("inv", nl.defOf(nl.device("x1").?).?.name);
}

test "deck: a top cell's voltage source is a device of the circuit, not a driver set apart" {
    // Oracle: how people draw it. Of the 972 voltage sources the engine set
    // apart in 5,263 hand-drawn subcircuits, 971 are wired where they stand.
    // `vx` holds a drain node: the node stays an internal net (no port by
    // R2) and the source is no driver (R3).
    const gpa = std.testing.allocator;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    var diag: np.netlist.Diagnostic = .{};
    const srcs = try deckSources(gpa, arena_state.allocator(), null, "cs.spice",
        \\.subckt dut vdd vss vb
        \\M1 n0 vb vss vss nch
        \\RD vdd n0 1k
        \\VX n0 vss dc 1
        \\.ends dut
    , &diag);
    var nl = try np.netlist.parse(gpa, srcs, &diag);
    defer nl.deinit(gpa);
    const roles = try np.guessRoles(gpa, &nl);
    defer gpa.free(roles);
    try std.testing.expectEqual(np.Role.internal, roles[nl.net("n0").?.index()]);
    try std.testing.expect(!np.schematic.isDriver(&nl.graph, roles, nl.device("vx").?.index()));
}

test "deck: the top cell's ports that no name gives a role are inputs and outputs" {
    // Oracle: the cell's own header. `vip` is a port on one gate (R1 knows
    // `vin*`, not `vip`): drawn as a dangling pin before, an input now; `x`
    // is driven by a drain, so an output.
    const gpa = std.testing.allocator;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    var diag: np.netlist.Diagnostic = .{};
    const srcs = try deckSources(gpa, arena_state.allocator(), null, "ota.spice",
        \\.subckt dut vdd vss vin x vip vb
        \\M1 n0 vin n1 vss nch
        \\M2 x vip n1 vss nch
        \\M3 n1 vb vss vss nch
        \\M4 x n0 vdd vdd pch
        \\M5 n0 n0 vdd vdd pch
        \\.ends dut
    , &diag);
    var nl = try np.netlist.parse(gpa, srcs, &diag);
    defer nl.deinit(gpa);
    const roles = try np.guessRoles(gpa, &nl);
    defer gpa.free(roles);
    try std.testing.expectEqual(np.Role.input, roles[nl.net("vip").?.index()]);
    try std.testing.expectEqual(np.Role.output, roles[nl.net("x").?.index()]);
    try std.testing.expectEqual(np.Role.bias, roles[nl.net("vb").?.index()]); // R1's, kept
    try std.testing.expectEqual(np.Role.internal, roles[nl.net("n1").?.index()]); // no port
}

test "from: a drawing's JSON gives the stays its decisions give" {
    // Oracle: `report.decisions`, which writes the same places from the
    // `Placed` itself; here they are read back out of the JSON document.
    const gpa = std.testing.allocator;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var lib = np.Library.init(gpa);
    defer lib.deinit();
    var sym_diags: std.ArrayList(np.library.ZonDiagnostic) = .empty;
    try lib.loadZon(arena, symbols, &sym_diags);
    const deck =
        \\Five-transistor OTA
        \\.model nch nmos level=1
        \\.model pch pmos level=1
        \\Vdd vdd 0 1.8
        \\M1 f vin1 p 0 nch
        \\M2 vout vin2 p 0 nch
        \\M3 f f vdd vdd pch
        \\M4 vout f vdd vdd pch
        \\M5 p vb 0 0 nch
        \\
    ;
    var nl = try np.netlist.parse(arena, &.{deck}, null);
    const roles = try np.guessRoles(arena, &nl);
    const st = try np.schematic.structure.analyze(arena, arena, &nl, roles);
    const sk = try np.schematic.skeleton.place(arena, arena, &nl, roles, &st, .{});
    const s = try np.layout(arena, &nl, roles, &lib, .{});
    const p = try np.Placed.init(arena, &s, &nl);
    var aw: Writer.Allocating = .init(arena);
    try np.json.write(&p, &lib, &aw.writer);
    var want: std.ArrayList(u8) = .empty;
    for (try np.report.decisions(arena, &nl, &st, &sk, &p, lib.unit, 4)) |line| {
        if (std.mem.startsWith(u8, line, "*@ weak at ")) try want.print(arena, "{s}\n", .{line});
    }
    try std.testing.expect(want.items.len > 0);
    // The JSON also holds the driver, which the engine draws apart: its
    // line is one the engine rejects, so it is left out of the comparison.
    var got: std.ArrayList(u8) = .empty;
    var lines = std.mem.tokenizeScalar(u8, try stays(arena, aw.written(), lib.unit), '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "*@ weak at vdd ")) try got.print(arena, "{s}\n", .{line});
    }
    try std.testing.expectEqualStrings(want.items, got.items);
    try std.testing.expectError(error.NotADrawing, stays(arena, "{\"devices\": 3}", lib.unit));
}

test "AG2187 signed slots follow the literal cell interface and original port order" {
    const t = std.testing;
    var arena: std.heap.ArenaAllocator = .init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\* AG2187 with reordered formal/actual pairs and arbitrary internal names
        \\.model mod nmos
        \\.subckt opamp INP OUT VDD INN VSS
        \\.ends
        \\.subckt dut p gnd i ref o{s}
        \\Cload e o 1p
        \\R1 f o 1k
        \\R2 gnd f 1k
        \\R3 e gnd 1k
        \\M1 i c o gnd mod
        \\X1 ref c p f gnd opamp
        \\.ends
        \\
    ;
    // Exposing either feedback or the driven gate removes the certificate.
    for ([_][]const u8{ "", " c", " f" }) |extra| {
        var lib: np.Library = .init(t.allocator);
        defer lib.deinit();
        var diag: np.netlist.Diagnostic = .{};
        const srcs = try deckSources(t.allocator, a, &lib, "reg.cir", try std.fmt.allocPrint(a, text, .{extra}), &diag);
        var nl = try np.netlist.parse(t.allocator, srcs, null);
        defer nl.deinit(t.allocator);
        const def = nl.defOf(nl.device("x1").?).?;
        const glyph = lib.at(try lib.blockFor(def));
        const pins = glyph.terminals;
        try t.expectEqual(extra.len == 0, pins[0].at.y < pins[3].at.y);
        try t.expect(pins[2].at.y < @min(pins[0].at.y, pins[3].at.y));
        try t.expect(pins[4].at.y > @max(pins[0].at.y, pins[3].at.y));
        for (glyph.draw) |op| if (op == .text) {
            const p = if (std.mem.eql(u8, op.text.s, "+")) pins[0] else pins[3];
            try t.expectEqual(p.at.y, op.text.at.y);
        };
    }
}
