//! Where Schemify puts the import's cells, and so how they refer to each other (Schemify
//! format spec §4, header `place` and `lib`, added 2026-11-04). The host writes a bare cell
//! file name into the directory of the first `place <glob> <dir>` attribute whose glob matches it, so a
//! bench and its components can land in different directories; `./cell` resolves only
//! beside the referencing file and `lib:cell` only at a library's top, so a reference that
//! crosses directories names the library whose `path` is the target's directory.
//!
//! Contents: `pub const Place` (`parse`, `dirOf`, `ref`), `fn globMatch`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;
const mem = std.mem;
const testing = std.testing;

/// The header's `place` attributes and the local `lib` rows of a project manifest. Empty (the default) puts every
/// file in one directory, so every reference is `./cell`.
pub const Place = struct {
    /// `place` globs and their directories, in file order; the root is `""`.
    glob: ArrayList([]const u8) = .empty,
    dir: ArrayList([]const u8) = .empty,
    /// `lib <name> path <path>` rows with their `subdir`, as root-relative directories.
    lib_name: ArrayList([]const u8) = .empty,
    lib_dir: ArrayList([]const u8) = .empty,

    /// Manifest rows past which the rest is ignored (a manifest holds a few dozen).
    const rows_max = 1024;

    /// Reads the rows of manifest `text`; `git`, `url` and `map` libraries have no local
    /// directory and are skipped. Slices borrow `text`, which must outlive the result.
    // ponytail: unquoted values only (a quoted path or glob is skipped); add the format's
    // quoting if a project ever names a directory with a space.
    pub fn parse(a: Allocator, text: []const u8) Allocator.Error!Place {
        var p: Place = .{};
        var lines = mem.splitScalar(u8, text, '\n');
        var rows: u32 = 0;
        var last_lib = false;
        while (lines.next()) |line| : (rows += 1) {
            if (rows == rows_max) break;
            var f = mem.tokenizeAny(u8, line, " \t\r");
            const word = f.next() orelse continue;
            if (mem.indexOfScalar(u8, line, '"') != null) continue;
            const indented = line[0] == ' ' or line[0] == '\t';
            if (indented) {
                // `  subdir <dir>` belongs to the `lib` row above it; `  place <glob> <dir>`
                // to the header (the only record with that attribute).
                if (last_lib and mem.eql(u8, word, "subdir")) if (f.next()) |sub| {
                    const d = &p.lib_dir.items[p.lib_dir.items.len - 1];
                    d.* = try join(a, d.*, clean(sub));
                };
                if (mem.eql(u8, word, "place")) if (f.next()) |glob| if (f.next()) |dir| {
                    try p.glob.append(a, glob);
                    try p.dir.append(a, clean(dir));
                };
                continue;
            }
            last_lib = false;
            const x = f.next() orelse continue;
            const y = f.next() orelse continue;
            if (mem.eql(u8, word, "lib") and mem.eql(u8, y, "path")) {
                const path = f.next() orelse continue;
                try p.lib_name.append(a, x);
                try p.lib_dir.append(a, clean(path));
                last_lib = true;
            }
        }
        assert(p.glob.items.len == p.dir.items.len);
        assert(p.lib_name.items.len == p.lib_dir.items.len);
        return p;
    }

    /// The root-relative directory bare file name `file` lands in (`""`: the root).
    pub fn dirOf(p: *const Place, file: []const u8) []const u8 {
        assert(file.len > 0 and mem.indexOfScalar(u8, file, '/') == null);
        for (p.glob.items, p.dir.items) |g, d| if (globMatch(g, file)) return d;
        return "";
    }

    /// The reference file `from` writes for cell `stem`, whose file is `to`: `./<stem>` when
    /// both land in one directory, else `<lib>:<stem>` for the library at `to`'s directory;
    /// `null` when no library is (the cell cannot be reached from `from`).
    pub fn ref(p: *const Place, a: Allocator, from: []const u8, to: []const u8, stem: []const u8) Allocator.Error!?[]const u8 {
        const dir = p.dirOf(to);
        if (mem.eql(u8, p.dirOf(from), dir)) return try a.print("./{s}", .{stem});
        for (p.lib_name.items, p.lib_dir.items) |name, d| {
            if (mem.eql(u8, d, dir)) return try a.print("{s}:{s}", .{ name, stem });
        }
        return null;
    }
};

// ---- private ----

/// Whether `glob` (`*` any run, `?` one byte, else literal) matches all of `name`. One
/// backtrack point at a time: O(glob × name) at worst.
fn globMatch(glob: []const u8, name: []const u8) bool {
    var g: usize = 0;
    var n: usize = 0;
    // The last `*` and the name position it was tried at.
    var star: ?[2]usize = null;
    var steps: usize = 0;
    while (n < name.len) {
        steps += 1;
        assert(steps <= (glob.len + 1) * (name.len + 1));
        if (g < glob.len and glob[g] == '*') {
            star = .{ g, n };
            g += 1;
        } else if (g < glob.len and (glob[g] == '?' or glob[g] == name[n])) {
            g += 1;
            n += 1;
        } else if (star) |s| {
            star = .{ s[0], s[1] + 1 };
            g = s[0] + 1;
            n = s[1] + 1;
        } else return false;
    }
    while (g < glob.len and glob[g] == '*') g += 1;
    return g == glob.len;
}

/// `dir` without a leading `./`, a trailing `/`, or `.` for the root.
fn clean(dir: []const u8) []const u8 {
    var d = dir;
    while (mem.startsWith(u8, d, "./")) d = d[2..];
    while (mem.endsWith(u8, d, "/")) d = d[0 .. d.len - 1];
    return if (mem.eql(u8, d, ".")) "" else d;
}

fn join(a: Allocator, dir: []const u8, sub: []const u8) Allocator.Error![]const u8 {
    if (dir.len == 0) return sub;
    if (sub.len == 0) return dir;
    return a.print("{s}/{s}", .{ dir, sub });
}

test "globs match whole names" {
    // Oracle: the POSIX `fnmatch` meaning of `*` and `?` over plain names.
    for ([_][2][]const u8{ .{ "*.shcomp", "top.shcomp" }, .{ "tb_*.shcomp", "tb_a.shcomp" }, .{ "*", "" }, .{ "a*b*c", "abxbc" }, .{ "?b", "ab" } }) |c|
        try testing.expect(globMatch(c[0], c[1]));
    for ([_][2][]const u8{ .{ "*.shcomp", "top.shbench" }, .{ "tb_*", "top" }, .{ "?", "" }, .{ "a*b", "abc" } }) |c|
        try testing.expect(!globMatch(c[0], c[1]));
}

test "references cross directories through the library at the target's" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // AMTemplate's block manifest (format spec §4 example).
    const p = try Place.parse(a,
        \\schemify 1 project
        \\  init project.lua
        \\  root ../..
        \\  place *.shbench test
        \\  place *.shcomp schematics
        \\  place *.shprim .
        \\
        \\lib blk path ./schematics/
        \\lib tech map tech.map
        \\lib pdk path pdks
        \\  subdir sky130
        \\
    );
    try testing.expectEqualStrings("test", p.dirOf("rcdiv.shbench"));
    try testing.expectEqualStrings("schematics", p.dirOf("rcdiv.shcomp"));
    try testing.expectEqualStrings("", p.dirOf("spice_d.shprim"));
    try testing.expectEqualStrings("pdks/sky130", p.lib_dir.items[1]);
    try testing.expectEqualStrings("blk:rcdiv", (try p.ref(a, "tb.shbench", "rcdiv.shcomp", "rcdiv")).?);
    try testing.expectEqualStrings("./inv", (try p.ref(a, "rcdiv.shcomp", "inv.shcomp", "inv")).?);
    try testing.expectEqual(null, try p.ref(a, "rcdiv.shcomp", "spice_d.shprim", "spice_d"));
    // No manifest rows: one directory, `./` throughout.
    const none: Place = .{};
    try testing.expectEqualStrings("./rcdiv", (try none.ref(a, "tb.shbench", "rcdiv.shcomp", "rcdiv")).?);
}
