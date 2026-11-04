//! The Schemify plugin (wasm32 only): contributions and the import job, over `convert.zig`.
//!
//! `cktimg.import <path>` (File ▸ Import SPICE netlist…, `Ctrl+Shift+I`) runs one job
//! through inverted I/O (plugin ABI §5) and timers, one phase per event:
//!
//! ```text
//! command        → fs_read(schemify.project)                    manifest
//! io_done(man.)  → its `place`/`lib` rows → fs_read(path)        read
//! io_done(read)  → each undefined `X` subckt → fs_read(<lib dir>/<name>.shprim|.shcomp)
//!                                                               cells (none: straight on)
//! io_done(cell)  → … all answered → parse + recognize → timer 0 draw
//! timer          → draw one cell → timer 0 … last cell → fs_read(each output name ×3 kinds)
//!                                                               probe (refuse to overwrite)
//! io_done(probe) → … all answered → fs_write(each new file)      write
//! io_done(write) → … all answered → log summary                  idle
//! ```
//!
//! One cell per timer event gives each cell the plugin's whole fuel budget and lets the
//! editor draw frames between cells. Without a path argument the command shows a small
//! panel with a path field whose Enter re-issues the command with the typed path. A new
//! command abandons a job in flight (late completions of its handles and timers of an older
//! job are ignored), so a trap or a fuel abort mid-job never wedges the plugin, and nothing
//! is written before every cell is drawn.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const mem = std.mem;
const schemify = @import("schemify");
const cktimg = @import("cktimg");
const Out = schemify.Out;

comptime {
    schemify.exportPlugin(@This());
}

/// The largest netlist the plugin reads: an `io_done` carries the whole file.
pub const schemify_input_max = 8 << 20;

/// The menu item; the path panel is appended while it is shown.
const ui =
    \\node file.cktimg_import item
    \\  parent menu.file
    \\  label "Import SPICE netlist…"
    \\  command cktimg.import
    \\  accel Ctrl+Shift+I
    \\
;
const panel =
    \\node cktimg.panel panel
    \\  parent window
    \\node cktimg.prompt label
    \\  parent cktimg.panel
    \\  label "SPICE netlist to import (project-relative .sp/.cir/.spice path), Enter to convert:"
    \\node cktimg.path text_input
    \\  parent cktimg.panel
    \\  command cktimg.import
    \\node cktimg.close button
    \\  parent cktimg.panel
    \\  label Close
    \\  command cktimg.close
    \\
;
const commands =
    \\command cktimg.import "Import SPICE netlist…"
    \\command cktimg.close "Close the SPICE import panel"
    \\
;
const keymap = "key Ctrl+Shift+I cktimg.import\n";
/// I/O requests kept in flight (the host's queue holds 256 per frame).
const window = 32;
/// Warnings echoed to the log per import.
const warnings_shown = 20;
/// Element cards per import: bounds the parse, recognition and file writing; larger
/// netlists are refused with a log. The engine's own work is bounded per cell by
/// `layout.cell_devices_max`/`drawn_devices_max` and by the fuel budget (one cell per
/// event): a cell whose layout needs more aborts the import with `E_FUEL`.
// ponytail: events run on the editor's frame thread, so a cell that needs 10^10 fuel still
// stalls the UI for seconds; the host running long events on a worker lifts that.
const cards_max = 200;

const gpa = std.heap.wasm_allocator;

/// What a handle in flight stands for: the manifest read, the netlist read, the read of
/// library cell file `cells[i]`, the probe of `probes[i]`, or the write of `files[i]`.
const Op = union(enum) { manifest, read, cell: u32, probe: u32, write: u32 };
const Flight = struct { handle: u32, op: Op };
const Probe = struct { path: []const u8, file: u32 };
/// A library file an `X` may call: `lib`'s `<dir>/<name>.<ext>`, and its bytes once read.
const CellFile = struct { lib: []const u8, name: []const u8, path: []const u8, bytes: ?[]const u8 = null };
/// Which list `pump` issues: library cell reads, output probes, or writes.
const Phase = enum { cells, probes, writes };

/// One import, from the command to the last completion. Everything lives in `arena`.
const Job = struct {
    arena: std.heap.ArenaAllocator,
    /// This job's number: the id of its timers (an older job's timer finds no match).
    serial: u32,
    source: []const u8,
    dir: []const u8,
    /// Where the host puts bare file names (the manifest's `place` and `lib` rows); empty
    /// for a netlist in a subdirectory, whose files are written beside it.
    place: cktimg.place.Place = .{},
    /// The manifest's rows wherever the netlist is: its `lib` rows name the libraries an
    /// `X` of an undefined subckt is looked up in.
    libs: cktimg.place.Place = .{},
    /// The netlist text, kept from its read until the library cells are in.
    text: []const u8 = "",
    cells: ArrayList(CellFile) = .empty,
    phase: Phase = .cells,
    /// The conversion while its cells are drawn, one per timer event.
    conv: ?cktimg.Converter = null,
    files: []const cktimg.OutFile = &.{},
    summary: []const u8 = "",
    probes: ArrayList(Probe) = .empty,
    /// Per file: some probed name exists.
    exists: []bool = &.{},
    /// Files to write, issued in order.
    writes: ArrayList(u32) = .empty,
    issued: usize = 0,
    failed: ArrayList(u8) = .empty,
    in_flight: ArrayList(Flight) = .empty,

    fn deinit(job: *Job) void {
        if (job.conv) |*c| c.deinit();
        job.arena.deinit();
    }
};

/// The job in flight.
var job_slot: ?Job = null;
/// Jobs started so far (the next job's `serial`).
var jobs: u32 = 0;

fn contribute(out: *Out, show_panel: bool) void {
    out.contribute(.ui, if (show_panel) ui ++ panel else ui);
    out.contribute(.commands, commands);
    out.contribute(.keymap, keymap);
}

/// Logs a formatted line at `level`; one too long for the buffer is cut.
fn logf(out: *Out, level: schemify.Level, comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    out.log(level, std.fmt.bufPrint(&buf, "cktimg: " ++ fmt, args) catch buf[0..]);
}

fn abandon() void {
    if (job_slot) |*j| j.deinit();
    job_slot = null;
}

pub fn onEvent(ev: schemify.Event, out: *Out) void {
    switch (ev) {
        .load => contribute(out, false),
        .command => |c| if (mem.eql(u8, c.name, "cktimg.close")) {
            contribute(out, false);
        } else if (mem.eql(u8, c.name, "cktimg.import")) {
            var path_buf: [1024]u8 = undefined;
            var path: Out = .init(&path_buf);
            var word_buf: [1024]u8 = undefined;
            var values = schemify.values(c.args);
            while (values.next(&word_buf) catch null) |w| {
                if (path.len > 0) path.put(" ");
                path.put(w);
            }
            if (path.len == 0 or path.overflow) return contribute(out, true);
            contribute(out, false);
            abandon();
            start(path.slice(), out);
        },
        .io_done => |io| {
            const job = &(job_slot orelse return);
            const at = for (job.in_flight.items, 0..) |f, i| {
                if (f.handle == io.handle) break i;
            } else return; // not ours (an abandoned job)
            const op = job.in_flight.swapRemove(at).op;
            const go = step(job, op, io.status, io.bytes, out) catch |e| fail(job, out, e);
            if (!go) abandon();
        },
        .timer => |id| {
            const job = &(job_slot orelse return);
            if (id != job.serial or job.conv == null) return; // an abandoned job's timer
            const go = draw(job, out) catch |e| fail(job, out, e);
            if (!go) abandon();
        },
        .rejected => |r| logf(out, .warn, "output rejected ({s}): {s}", .{ schemify.code_names[@backingInt(r.code) - 1], r.record }),
        else => {},
    }
}

fn fail(job: *const Job, out: *Out, e: anyerror) bool {
    logf(out, .@"error", "{s}: {t}", .{ job.source, e });
    return false;
}

fn hint(e: schemify.Error) []const u8 {
    return if (e == error.Denied) " (grant read_project and write_project in the plugin's schemify.pack.add spec, and use a project-relative path)" else "";
}

/// Starts an import of `path` (project-relative).
fn start(path: []const u8, out: *Out) void {
    assert(path.len > 0);
    const known = for ([_][]const u8{ ".sp", ".cir", ".spice", ".net", ".cdl" }) |e| {
        if (std.ascii.endsWithIgnoreCase(path, e)) break true;
    } else false;
    if (!known) logf(out, .warn, "{s}: not a .sp/.cir/.spice file; importing anyway", .{path});
    const h = schemify.fsRead("schemify.project") catch |e| return logf(out, .@"error", "cannot read schemify.project: {t}{s}", .{ e, hint(e) });
    var arena: std.heap.ArenaAllocator = .init(gpa);
    const a = arena.allocator();
    const source = a.dupe(u8, path) catch return logf(out, .@"error", "out of memory", .{});
    var job: Job = .{
        .arena = arena,
        .serial = jobs,
        .source = source,
        .dir = source[0 .. mem.lastIndexOfScalar(u8, source, '/') orelse 0],
    };
    jobs +%= 1;
    job.in_flight.append(a, .{ .handle = h, .op = .manifest }) catch return logf(out, .@"error", "out of memory", .{});
    job_slot = job;
}

fn outPath(job: *Job, name: []const u8) Allocator.Error![]const u8 {
    assert(name.len > 0 and mem.indexOfScalar(u8, name, '/') == null);
    if (job.dir.len == 0) return name;
    return job.arena.allocator().print("{s}/{s}", .{ job.dir, name });
}

fn codeName(status: i32) []const u8 {
    const c = @abs(status);
    return if (c >= 1 and c <= schemify.code_names.len) schemify.code_names[c - 1] else "E_GONE";
}

/// Handles completion `op`; returns whether the job continues.
fn step(job: *Job, op: Op, status: i32, bytes: []const u8, out: *Out) Allocator.Error!bool {
    const a = job.arena.allocator();
    switch (op) {
        .manifest => {
            // No manifest (E_GONE): nothing is placed. A netlist in a subdirectory writes
            // paths, which the host never places.
            if (status >= 0) job.libs = try .parse(a, try a.dupe(u8, bytes));
            if (job.dir.len == 0) job.place = job.libs;
            const h = schemify.fsRead(job.source) catch |e| {
                logf(out, .@"error", "cannot read {s}: {t}{s}", .{ job.source, e, hint(e) });
                return false;
            };
            try job.in_flight.append(a, .{ .handle = h, .op = .read });
            return true;
        },
        .read => {
            if (status < 0) {
                logf(out, .@"error", "cannot read {s}: {s}", .{ job.source, codeName(status) });
                return false;
            }
            var cards: usize = 0;
            var lines = mem.splitScalar(u8, bytes, '\n');
            while (lines.next()) |l| {
                const t = mem.trimStart(u8, l, cktimg.spice.ws);
                cards += @intFromBool(t.len > 0 and std.ascii.isAlphabetic(t[0]));
            }
            if (cards > cards_max) {
                logf(out, .@"error", "{s}: {d} element cards; the plugin converts at most {d} (split the netlist)", .{ job.source, cards, cards_max });
                return false;
            }
            // The event's bytes are reused after it returns; the deck borrows the text.
            job.text = try a.dupe(u8, bytes);
            for (try cktimg.calls(a, job.text)) |name| {
                if (mem.indexOfAny(u8, name, "/\\:") != null or mem.startsWith(u8, name, ".")) continue;
                for (job.libs.lib_name.items, job.libs.lib_dir.items) |lib, dir| for ([_][]const u8{ "shprim", "shcomp" }) |ext| {
                    const path = if (dir.len == 0) try a.print("{s}.{s}", .{ name, ext }) else try a.print("{s}/{s}.{s}", .{ dir, name, ext });
                    try job.cells.append(a, .{ .lib = lib, .name = name, .path = path });
                };
            }
            if (job.cells.items.len == 0) return convert(job, out);
            return pump(job, out);
        },
        .cell => |i| {
            if (status >= 0) job.cells.items[i].bytes = try a.dupe(u8, bytes);
            if (job.issued < job.cells.items.len or job.in_flight.items.len > 0) return pump(job, out);
            return convert(job, out);
        },
        .probe => |i| {
            if (status >= 0) job.exists[job.probes.items[i].file] = true;
            if (job.issued < job.probes.items.len or job.in_flight.items.len > 0) return pump(job, out);
            // Every name answered: refuse to overwrite a cell; keep shared leaves.
            var clash: ArrayList(u8) = .empty;
            for (job.files, job.exists) |f, e| if (e and !f.shared) try clash.print(a, " {s}", .{f.name});
            if (clash.items.len > 0) {
                logf(out, .@"error", "{s}: not imported, these cells already exist:{s}", .{ job.source, clash.items });
                return false;
            }
            for (job.exists, 0..) |e, k| if (!e) try job.writes.append(a, @intCast(k));
            if (job.writes.items.len == 0) {
                out.log(.info, job.summary);
                return false;
            }
            job.phase = .writes;
            job.issued = 0;
            return pump(job, out);
        },
        .write => |i| {
            if (status < 0) try job.failed.print(a, " {s}", .{job.files[i].name});
            if (job.issued < job.writes.items.len or job.in_flight.items.len > 0) return pump(job, out);
            if (job.failed.items.len == 0)
                out.log(.info, job.summary)
            else
                logf(out, .@"error", "{s}: could not write{s}", .{ job.source, job.failed.items });
            return false;
        },
    }
}

/// Parses and recognizes the netlist with the library cells read (the first file found per
/// subckt name, in `lib` row order), then starts drawing.
fn convert(job: *Job, out: *Out) Allocator.Error!bool {
    const a = job.arena.allocator();
    var libs: ArrayList(cktimg.recognize.LibCell) = .empty;
    for (job.cells.items) |f| {
        const bytes = f.bytes orelse continue;
        for (libs.items) |l| {
            if (mem.eql(u8, l.name, f.name)) break;
        } else if (try cktimg.place.libCell(a, f.lib, f.name, bytes)) |l| try libs.append(a, l);
    }
    job.conv = try .initLibs(gpa, a, job.source, job.text, libs.items);
    job.conv.?.place = job.place;
    if (job.conv.?.cellsLeft() == 0) {
        logf(out, .warn, "{s}: no subckt or top-level card to import", .{job.source});
        return false;
    }
    out.timer(job.serial, 0);
    return true;
}

/// Draws the job's next cell (a timer event); after the last one starts the probes.
fn draw(job: *Job, out: *Out) Allocator.Error!bool {
    const conv = &job.conv.?;
    assert(conv.cellsLeft() > 0);
    try conv.step();
    if (conv.cellsLeft() > 0) {
        out.timer(job.serial, 0);
        return true;
    }
    const result = try conv.finish();
    conv.deinit();
    job.conv = null;
    return probe(job, result, out);
}

/// Logs the conversion's warnings and probes every output name (each stem as `.shcomp`,
/// `.shprim` and `.shbench`).
fn probe(job: *Job, conv: cktimg.Conversion, out: *Out) Allocator.Error!bool {
    const a = job.arena.allocator();
    assert(conv.files.items.len > 0 and job.probes.items.len == 0);
    const s = conv.stats;
    job.summary = try a.print("cktimg: {s} → {d} files ({d} cells); {d} devices, {d} wires, {d} labels/ports; {d}/{d} nets fully wired; {d} warnings", .{
        job.source, conv.files.items.len, s.cells,      s.devices,               s.wires,
        s.markers,  s.nets_wired,         s.nets_multi, conv.warnings.items.len,
    });
    for (conv.warnings.items[0..@min(conv.warnings.items.len, warnings_shown)]) |w| logf(out, .warn, "{s}: {s}", .{ job.source, w });
    for (conv.files.items, 0..) |f, i| {
        const stem = f.name[0 .. mem.lastIndexOfScalar(u8, f.name, '.') orelse f.name.len];
        for ([_][]const u8{ "shcomp", "shprim", "shbench" }) |ext|
            try job.probes.append(a, .{ .path = try outPath(job, try a.print("{s}.{s}", .{ stem, ext })), .file = @intCast(i) });
    }
    job.files = conv.files.items;
    job.exists = try a.alloc(bool, job.files.len);
    @memset(job.exists, false);
    job.phase = .probes;
    job.issued = 0;
    return pump(job, out);
}

/// Issues the phase's queued reads, probes or writes up to `window` in flight; false after
/// a refused request (logged).
fn pump(job: *Job, out: *Out) Allocator.Error!bool {
    const a = job.arena.allocator();
    assert(job.in_flight.items.len <= window);
    const total = switch (job.phase) {
        .cells => job.cells.items.len,
        .probes => job.probes.items.len,
        .writes => job.writes.items.len,
    };
    while (job.issued < total and job.in_flight.items.len < window) {
        const i: u32 = @intCast(job.issued);
        const op: Op, const issued = switch (job.phase) {
            .cells => .{ .{ .cell = i }, schemify.fsRead(job.cells.items[i].path) },
            .probes => .{ .{ .probe = i }, schemify.fsRead(job.probes.items[i].path) },
            .writes => blk: {
                const k = job.writes.items[i];
                break :blk .{ .{ .write = k }, schemify.fsWrite(try outPath(job, job.files[k].name), job.files[k].bytes) };
            },
        };
        const handle = issued catch |e| {
            if (e == error.Space and job.in_flight.items.len > 0) break; // resume on the next completion
            logf(out, .@"error", "{s}: I/O refused: {t}{s}", .{ job.source, e, hint(e) });
            return false;
        };
        try job.in_flight.append(a, .{ .handle = handle, .op = op });
        job.issued += 1;
    }
    return true;
}
