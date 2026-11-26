//! SPICE netlist in, placed schematic out. See docs/API.md for the usage code
//! this surface was written from, and docs/ALGORITHM.md for the layout.
//!
//! Human Rules: none of its own; it runs the stages, whose files list the
//! rules.
//!
//! Tiers, coarse to fine — each is the one below it with the choices made:
//!
//! | call | gives you |
//! |------|-----------|
//! | `place(gpa, cfg, lib, sources, diag)` | an owned `Placed` |
//! | `Pipeline.run` | a borrowed `Placed`, pages reused across documents |
//! | `netlist.parse` → `guessRoles` → `layout` → `Placed.init` | every stage, each usable alone |
//!
//! The caller's `Library` supplies primitive symbols and may override every
//! subcircuit glyph; recognized blocks have conventional generated symbols.
//!
//! Contents (shared symbol and source-qualified layout entries):
//! - `pub const parent_context`, `pub const local_parents`, `pub const parent_outputs`, `pub const parent_stages`
//! - `pub const source_regions`, `pub const source_bridge`, `pub const source_layout`, `pub fn placeSourceLayout`
//! - `pub fn placeBound`, `pub fn placeOrganized`, `pub fn placeSourceBridge`
//! - `pub const device = @import("device.zig")`
//! - `pub const library = @import("library.zig")`
//! - `pub const polyphase_caps`
//! - `pub const regulator = @import("regulator.zig")`
//! - `pub const block_symbols = @import("block_symbols.zig")`

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const netlist = @import("netlist.zig");
/// Cold ordered-MOS parent analysis for callers retaining original source authority.
pub const parent_context = @import("parent_context.zig");
/// Cold structural analysis; a complete reflection is independent of placement mates.
pub const local_parents = @import("local_parents.zig");
/// Two private drain outputs proven by a complete ordered reflection.
pub const parent_outputs = @import("parent_outputs.zig");
/// Relative organization of a complete five-MOS common-control parent.
pub const parent_stages = @import("parent_stages.zig");
/// Cold source-region incidence and passive/current/tail attachment witnesses.
pub const source_regions = @import("source_regions.zig");
/// An ordered horizontal two-arm source-degeneration bridge.
pub const source_bridge = @import("source_bridge.zig");
/// Complete source-certified mixed-device arrangements.
pub const source_layout = @import("source_layout.zig");
/// What a device of a kind is to a drawing: its current path and side pins.
pub const device = @import("device.zig");
/// The `*@` grouping hints a deck gives `layout` (issue #7).
pub const hints = @import("hints.zig");
pub const analysis = @import("analysis.zig");
pub const csr = @import("csr.zig");
pub const library = @import("library.zig");
/// Complete two-bank passive RC lattice and ordered capacitor poses.
pub const polyphase_caps = @import("polyphase_caps.zig");
/// Certified signed controller pose for a regulated pass transistor.
pub const regulator = @import("regulator.zig");
/// Conventional glyphs for subcircuits with verified named port contracts.
pub const block_symbols = @import("block_symbols.zig");
pub const config = @import("config.zig");
pub const schematic = @import("schematic.zig");
pub const placed = @import("placed.zig");
pub const geom = @import("geom.zig");
/// Exact integer membership for horizontal, vertical and 45-degree wire records.
pub const wire_geometry = @import("wire_geometry.zig");
pub const lint = @import("lint.zig");
/// The drawing's guarantees, checked on a finished `Placed`.
pub const checks = @import("checks.zig");
pub const report = @import("report.zig");
/// The TikZ emitter, only with `-Dlatex_renderer=true`; `void` otherwise, so
/// a reference without the option is a compile error naming it.
pub const latex = if (build_options.latex_renderer) @import("latex.zig") else void;
const build_options = @import("build_options");
/// Plain-data JSON of a `Placed` (what `cktimg_json` writes).
pub const json = @import("json.zig");
/// The C ABI, `include/cktimg.h`. Nothing in Zig calls it, so it is forced
/// into the build here, or the static library would export nothing; the
/// Schemify plugin builds without it (`c_abi = false`), exporting only its own.
pub const abi = if (build_options.c_abi) @import("abi.zig") else void;
comptime {
    _ = abi;
}

pub const Library = library.Library;
pub const Class = library.Class;
pub const ClassId = library.ClassId;
pub const Pt = library.Pt;
pub const Rect = library.Rect;
pub const Orient = library.Orient;
pub const Side = library.Side;
pub const Config = config.Config;
pub const Netlist = netlist.Netlist;
pub const Schematic = schematic.Schematic;
pub const Role = schematic.Role;
pub const Placed = placed.Placed;
pub const Label = placed.Label;

/// Proposes a role per net (supply, sink, input, output, bias, internal);
/// edit the result freely before `layout`.
pub const guessRoles = schematic.guessRoles;
/// A netlist and its roles drawn: its structure found, its devices placed
/// by it, its nets wired (docs/ALGORITHM.md), spaced by `config.Layout`'s
/// lengths. The caller frees the result with `Schematic.deinit`.
pub const layout = schematic.sketch.lay;

/// What can stop a placement: a card the parser does not represent (see
/// `diag` for where), or memory.
pub const PlaceError = netlist.Error || library.RegisterError;

/// Parse, lay out and export in one call; the caller owns the result.
///
/// `sources[0]` is the netlist (its first line the title); later sources are
/// read as if appended (model files). `lib` gains a generated box class for
/// any device kind it has no class for. Of `cfg`, the layout reads
/// `.layout`.
pub fn place(
    gpa: Allocator,
    cfg: *const Config,
    lib: *Library,
    sources: []const []const u8,
    diag: ?*netlist.Diagnostic,
) PlaceError!Placed {
    return stages(gpa, gpa, cfg, lib, sources, diag);
}

/// `place` for many documents with one set of pages: each `run` returns a
/// borrowed `Placed`, valid until the next `run`, `reset` or `deinit`.
pub const Pipeline = struct {
    /// Stage temporaries: netlist, schematic. Reset every run.
    scratch: std.heap.ArenaAllocator,
    /// The current result.
    out: std.heap.ArenaAllocator,
    cfg: *const Config,
    lib: *Library,
    current: ?Placed = null,

    /// Borrows `cfg` and `lib`; both must outlive the pipeline.
    pub fn init(gpa: Allocator, cfg: *const Config, lib: *Library) Pipeline {
        return .{ .scratch = .init(gpa), .out = .init(gpa), .cfg = cfg, .lib = lib };
    }

    pub fn deinit(self: *Pipeline) void {
        self.scratch.deinit();
        self.out.deinit();
        self.* = undefined;
    }

    pub fn run(self: *Pipeline, sources: []const []const u8, diag: ?*netlist.Diagnostic) PlaceError!*const Placed {
        self.reset();
        self.current = try stages(self.scratch.allocator(), self.out.allocator(), self.cfg, self.lib, sources, diag);
        _ = self.scratch.reset(.retain_capacity);
        return &self.current.?;
    }

    /// Drops the current result and keeps the pages.
    pub fn reset(self: *Pipeline) void {
        self.current = null;
        _ = self.out.reset(.retain_capacity);
        _ = self.scratch.reset(.retain_capacity);
    }
};

/// Draws this exact parsed graph with the supplied fully bound parent outputs.
/// The caller keeps the graph alive and owns the returned placement.
pub fn placeBound(tmp: Allocator, out: Allocator, cfg: *const Config, lib: *Library, nl: *const netlist.Netlist, pairs: []const parent_outputs.Pair) PlaceError!Placed {
    const roles = try guessRoles(tmp, nl);
    defer tmp.free(roles);
    var s = try schematic.sketch.layWithParents(tmp, nl, roles, lib, cfg.layout, pairs);
    defer s.deinit();
    return Placed.init(out, &s, nl);
}

/// Draws certified stages; a failed local room, mandatory route or final
/// connectivity/short/junction check restores the ordinary paired layout.
pub fn placeOrganized(gpa: Allocator, cfg: *const Config, lib: *Library, nl: *const netlist.Netlist, pairs: []const parent_outputs.Pair, stages_: []const parent_stages.Stage) PlaceError!Placed {
    return placeQualified(gpa, cfg, lib, nl, pairs, stages_, null);
}

/// Draws a certified complete two-arm bridge, with ordinary layout as fallback.
pub fn placeSourceBridge(gpa: Allocator, cfg: *const Config, lib: *Library, nl: *const netlist.Netlist, request: source_bridge.Request) PlaceError!Placed {
    return placeSourceLayout(gpa, cfg, lib, nl, .{ .bridge = request });
}

/// Draws a complete mixed-device room, retaining the ordinary result if a
/// selected symbol, original request, or final electrical gate declines it.
pub fn placeSourceLayout(gpa: Allocator, cfg: *const Config, lib: *Library, nl: *const netlist.Netlist, request: source_layout.Owner) PlaceError!Placed {
    return placeQualified(gpa, cfg, lib, nl, &.{}, &.{}, request);
}

// ---- private ----

/// Every stage in order, the one list both tiers run: each stage's
/// temporaries in `tmp`, freed before it returns, the result in `out`.
fn stages(tmp: Allocator, out: Allocator, cfg: *const Config, lib: *Library, sources: []const []const u8, diag: ?*netlist.Diagnostic) PlaceError!Placed {
    var nl = try netlist.parse(tmp, sources, diag);
    defer nl.deinit(tmp);
    return placeBound(tmp, out, cfg, lib, &nl, &.{});
}

fn placeQualified(gpa: Allocator, cfg: *const Config, lib: *Library, nl: *const netlist.Netlist, pairs: []const parent_outputs.Pair, stages_: []const parent_stages.Stage, bridge: ?source_layout.Owner) PlaceError!Placed {
    if (stages_.len > 0 or bridge != null) {
        const roles = try guessRoles(gpa, nl);
        defer gpa.free(roles);
        const try_panels = @import("comparator_panels.zig").eligible(stages_, pairs);
        for (0..if (try_panels) @as(usize, 2) else 1) |attempt| {
            const panels = try_panels and attempt == 0;
            var accepted = false;
            var diagram = try schematic.sketch.layPanels(gpa, nl, roles, lib, cfg.layout, pairs, stages_, bridge, panels, &accepted);
            defer diagram.deinit();
            if (accepted) {
                var candidate = try Placed.init(gpa, &diagram, nl);
                errdefer candidate.deinit();
                var findings: std.ArrayList(checks.Finding) = .empty;
                defer findings.deinit(gpa);
                try checks.find(gpa, &findings, &candidate, lib);
                const bridge_intact = if (bridge) |r| source_layout.intact(r, &candidate, nl, lib) else true;
                const receivers_clear = if (panels) clear: {
                    for (pairs) |pair| for (pair) |o| {
                        if (!parent_stages.clearDevice(&candidate, lib, nl, o.pmos) or !parent_stages.clearDevice(&candidate, lib, nl, o.nmos)) break :clear false;
                    };
                    break :clear true;
                } else true;
                if (findings.items.len == 0 and bridge_intact and receivers_clear and parent_stages.clearWires(&candidate, lib, nl, stages_)) {
                    const intent = @import("parent_intent.zig");
                    if (!intent.needsDrawing(nl)) return candidate;
                    var incumbent = try placeBound(gpa, gpa, cfg, lib, nl, pairs);
                    errdefer incumbent.deinit();
                    var scratch = std.heap.ArenaAllocator.init(gpa);
                    defer scratch.deinit();
                    if (try intent.preserved(scratch.allocator(), nl, roles, cfg.layout, lib, &incumbent, &candidate)) {
                        incumbent.deinit();
                        return candidate;
                    }
                    candidate.deinit();
                    if (!panels) return incumbent;
                    incumbent.deinit();
                    continue;
                }
                candidate.deinit();
            }
        }
    }
    return placeBound(gpa, gpa, cfg, lib, nl, pairs);
}

test {
    std.testing.refAllDecls(@This());
    // Reached only through `schematic.sketch`, which nothing here calls.
    _ = @import("maze.zig");
}
