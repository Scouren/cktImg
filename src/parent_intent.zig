//! Maps an admitted drawing request to the physical owner it can constrain.
//!
//! Contents:
//! - `pub fn touches(nl: *const netlist.Netlist, h: hints.Hint, verdict: hints.Verdict, devices: []const u32, nets: []const u32) bool`
//! - `pub fn admitted(a: std.mem.Allocator, nl: *const netlist.Netlist, s: *const sch.Schematic, st: *const structure.Structure, sk: *const skeleton.Skeleton) ![]const hints.Verdict`
//! - `pub fn needsDrawing(nl: *const netlist.Netlist) bool`, `pub fn preserved(a: std.mem.Allocator, nl: *const netlist.Netlist, roles: []const sch.Role, cfg: config.Layout, lib: *const library.Library, before: *const placed.Placed, after: *const placed.Placed) !bool`
const std = @import("std");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const report = @import("report.zig");
const sch = @import("schematic.zig");
const config = @import("config.zig");
const library = @import("library.zig");
const placed = @import("placed.zig");
const hints = @import("hints.zig");
const netlist = @import("netlist.zig");

/// Tests a request and its own semantic verdict against graph-bound device
/// and net handles. Known members of a partially accepted group remain held.
/// Argument positions follow the verb, so a value spelling a name cannot match.
pub fn touches(nl: *const netlist.Netlist, h: hints.Hint, verdict: hints.Verdict, devices: []const u32, nets: []const u32) bool {
    if (verdict.state != .honoured and !(verdict.state == .relaxed and verdict.code == .unknown_name and h.verb.grouping())) return false;
    const first = h.args[0..@min(1, h.args.len)];
    const args = switch (h.verb) {
        .off, .symmetry_off, .shelf => return true,
        .unknown, .refdes, .expand => return false,
        .role, .port, .rail, .label, .wire, .via, .route, .kind, .class, .driver, .axis, .at, .cell, .face => first,
        .first, .pair, .cross, .bank, .mirror, .stack, .nogroup, .symmetric, .row, .above, .order, .upright, .bridge => h.args,
    };
    switch (h.verb) {
        .axis, .symmetric => {
            if (args.len == 0) return false;
            const devices_first = nl.device(args[0]) != null;
            for (args) |arg| {
                if (devices_first) {
                    const id = nl.device(arg) orelse continue;
                    if (std.mem.indexOfScalar(u32, devices, id.index()) != null) return true;
                } else {
                    const id = nl.net(arg) orelse continue;
                    if (std.mem.indexOfScalar(u32, nets, id.index()) != null) return true;
                }
            }
        },
        .role, .port, .rail, .label, .wire, .via, .route, .first => {
            for (args) |arg| if (nl.net(arg)) |id| {
                if (std.mem.indexOfScalar(u32, nets, id.index()) != null) return true;
            };
        },
        else => {
            for (args) |arg| if (nl.device(arg)) |id| {
                if (std.mem.indexOfScalar(u32, devices, id.index()) != null) return true;
            };
        },
    }
    return false;
}

/// Resolves parser, structure and skeleton requests. A class line is honoured
/// here only when device initialization actually accepted that exact class.
pub fn admitted(a: std.mem.Allocator, nl: *const netlist.Netlist, s: *const sch.Schematic, st: *const structure.Structure, sk: *const skeleton.Skeleton) ![]const hints.Verdict {
    const rows = try report.verdicts(a, nl, s.roles, st, sk, null, s.lib);
    var corrected: ?[]hints.Verdict = null;
    for (rows, nl.hints, 0..) |v, h, i| {
        if (v.state != .honoured or h.verb != .class) continue;
        const d = nl.device(h.args[0]).?.index();
        if (s.lib.find(h.args[1]) == s.devices.items(.class)[d]) continue;
        if (corrected == null) corrected = try a.dupe(hints.Verdict, rows);
        corrected.?[i] = .of(.bad_args);
    }
    return corrected orelse rows;
}

/// Whether a final pose or wire can change any request's existing verdict.
/// Synthesized native formal roles carry no physical placement obligation.
pub fn needsDrawing(nl: *const netlist.Netlist) bool {
    for (nl.hints) |h| switch (h.verb) {
        .role, .kind, .class, .refdes, .expand, .unknown => {},
        else => return true,
    };
    return false;
}

/// Confirms that every honoured incumbent request remains honoured in the
/// complete candidate, including cross-parent rows and explicit global axes.
pub fn preserved(a: std.mem.Allocator, nl: *const netlist.Netlist, roles: []const sch.Role, cfg: config.Layout, lib: *const library.Library, before: *const placed.Placed, after: *const placed.Placed) !bool {
    const st = try sch.structure.analyze(a, a, nl, roles);
    const sk = try sch.skeleton.place(a, a, nl, roles, &st, .{ .shelf = cfg.shelf });
    const baseline = try report.verdicts(a, nl, roles, &st, &sk, before, lib);
    const candidate = try report.verdicts(a, nl, roles, &st, &sk, after, lib);
    for (baseline, candidate) |old, new| {
        if (old.state == .honoured and new.state != .honoured) return false;
    }
    return true;
}
