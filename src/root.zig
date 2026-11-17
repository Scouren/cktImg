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
//! Contents (the new shared glyph entry; the existing exports follow below):
//! - `pub const device = @import("device.zig")`
//! - `pub const library = @import("library.zig")`
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
/// What a device of a kind is to a drawing: its current path and side pins.
pub const device = @import("device.zig");
/// The `*@` grouping hints a deck gives `layout` (issue #7).
pub const hints = @import("hints.zig");
pub const analysis = @import("analysis.zig");
pub const csr = @import("csr.zig");
pub const library = @import("library.zig");
/// Signed input order from raw NMOS regulator connections and declared cell ports.
pub const regulator = @import("regulator.zig");
/// Conventional glyphs for subcircuits with verified named port contracts.
pub const block_symbols = @import("block_symbols.zig");
pub const config = @import("config.zig");
pub const schematic = @import("schematic.zig");
pub const placed = @import("placed.zig");
pub const geom = @import("geom.zig");
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

// ---- private ----

/// Every stage in order, the one list both tiers run: each stage's
/// temporaries in `tmp`, freed before it returns, the result in `out`.
fn stages(tmp: Allocator, out: Allocator, cfg: *const Config, lib: *Library, sources: []const []const u8, diag: ?*netlist.Diagnostic) PlaceError!Placed {
    var nl = try netlist.parse(tmp, sources, diag);
    defer nl.deinit(tmp);
    return placeBound(tmp, out, cfg, lib, &nl, &.{});
}

/// Draws this exact parsed graph with the supplied fully bound parent outputs.
/// The caller keeps the graph alive and owns the returned placement.
pub fn placeBound(tmp: Allocator, out: Allocator, cfg: *const Config, lib: *Library, nl: *const netlist.Netlist, pairs: []const parent_outputs.Pair) PlaceError!Placed {
    const roles = try guessRoles(tmp, nl);
    defer tmp.free(roles);
    var s = try schematic.sketch.layWithParents(tmp, nl, roles, lib, cfg.layout, pairs);
    defer s.deinit();
    return Placed.init(out, &s, nl);
}

test {
    std.testing.refAllDecls(@This());
    // Reached only through `schematic.sketch`, which nothing here calls.
    _ = @import("maze.zig");
}
