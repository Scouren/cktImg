#!/usr/bin/env python3
"""Prepare source-pinned, printing-only diagnostics in an external directory.

Build commands are deliberately separate and run by the build owner. Replaying
geometry AND reports against the supplied frozen binary is mandatory: a trace
whose output differs cannot support a causal claim. See thin-parts.md and the thin_row_cases.json companion.
"""
from pathlib import Path
import hashlib,json,shutil,subprocess
import argparse
parser=argparse.ArgumentParser(description="Prepare a copied16/pre-row17 tree with printing-only thinning diagnostics; never builds.")
parser.add_argument("output",type=Path)
parser.add_argument("--version", choices=("16", "pre17"), required=True)
args=parser.parse_args()
root=Path(__file__).resolve().parents[3]
out=args.output.resolve()
assert out != root and root not in out.parents, "diagnostic copy must be outside the repository"
snapshot=json.loads(Path(__file__).with_name('thin_row_snapshot.json').read_text())
revision=subprocess.check_output(['git','rev-parse',snapshot['base_revision']],cwd=root,text=True).strip()
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',revision,'src'],cwd=root,text=True).splitlines()
paths=[p for p in paths if p.endswith('.zig')]+['tools/json.zig','tests/svg.zig','tests/symbols.zon']
overrides=snapshot['overrides'] if args.version=='pre17' else {}
paths=sorted(set(paths)|set(overrides))
source_hashes={}
for rel in paths:
    data=overrides[rel].encode() if rel in overrides else subprocess.check_output(['git','show',revision+':'+rel],cwd=root)
    target=out/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    source_hashes[rel]=hashlib.sha256(data).hexdigest()
if overrides:assert source_hashes==snapshot['source_sha256'],'pre-row source snapshot differs'
(out/'symbols.zig').write_text('pub const text = @embedFile("tests/symbols.zon");\n')
(out/'build.zig').write_text('''const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = b.addOptions();
    options.addOption(bool, "latex_renderer", false);
    options.addOption(bool, "zon_config", true);
    options.addOption(bool, "c_abi", false);
    const engine = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    engine.addOptions("build_options", options);
    const imports: []const std.Build.Module.Import = &.{.{ .name = "NetlistParser", .module = engine }};
    const svg = b.createModule(.{ .root_source_file = b.path("tests/svg.zig"), .imports = imports });
    const symbols = b.createModule(.{ .root_source_file = b.path("symbols.zig") });
    const tool = b.createModule(.{ .root_source_file = b.path("tools/json.zig"), .target = target, .optimize = optimize,
        .imports = &.{ .{ .name = "NetlistParser", .module = engine }, .{ .name = "svg", .module = svg }, .{ .name = "symbols", .module = symbols } } });
    b.installArtifact(b.addExecutable(.{ .name = "cktimg-json-trace", .root_module = tool }));
}
''')
cache=out/'.zig-cache'
if not cache.exists():cache.symlink_to(root/'.zig-cache',target_is_directory=True)

def edit(rel, old, new):
    p=out/rel;s=p.read_text();assert s.count(old)==1,(rel,old,s.count(old));p.write_text(s.replace(old,new))
edit('src/sketch.zig','''    for (0..thin_rounds + 1) |round| {
        try wireUp''','''    for (0..thin_rounds + 1) |round| {
        std.debug.print("TRACE round_begin {d}\\n", .{round});
        try wireUp''')
edit('src/sketch.zig','''        const mirror = drawnMirror(s, sk, st);
        if (round == thin_rounds''','''        const mirror = drawnMirror(s, sk, st);
        for (s.net_name, s.roles, st.net_rank, style, 0..) |name, role, rank, sty, net| {
            std.debug.print("TRACE net {d} {s} {t} {d} {t} {d}\\n", .{ net, name, role, rank, sty, if (mirror) |m| m.net_mate[net] else sch.none });
        }
        for (s.pins.items(.net), s.pins.items(.home), s.pins.items(.device), s.pins.items(.index), s.pins.items(.side), 0..) |net, home, trace_device, index, side, pin| {
            const p = s.pinPoint(@intCast(pin));
            std.debug.print("TRACE pin {d} {d} {s} {d} {t} {d} {d} {t}\\n", .{ pin, net, if (trace_device == sch.none) "-" else s.device_name[trace_device], index, side, @as(i32, @intFromFloat(p[0])), @as(i32, @intFromFloat(p[1])), s.nodes.items(.kind)[home] });
        }
        for (s.routes.items, 0..) |r, route| for (r.pts[0 .. r.len - 1], r.pts[1..r.len]) |a, b| {
            std.debug.print("TRACE segment {d} {d} {d} {d} {d} {d}\\n", .{ r.net, route, @as(i32, @intFromFloat(a[0])), @as(i32, @intFromFloat(a[1])), @as(i32, @intFromFloat(b[0])), @as(i32, @intFromFloat(b[1])) });
        };
        std.debug.print("TRACE round_drawn {d}\\n", .{round});
        if (round == thin_rounds''')
pair_ids = 'i, j' if 'ArrayList([2]usize)' in (out/'src/thin.zig').read_text() else 'r.net, q.net'
edit('src/thin.zig',('''            if (crosses(a, b, c, d) or crosses(c, d, a, b)) try pairs.append(gpa, .{ PAIR_IDS });''').replace('PAIR_IDS', pair_ids),'''            if (crosses(a, b, c, d) or crosses(c, d, a, b)) {
                try pairs.append(gpa, .{ PAIR_IDS });
                std.debug.print("TRACE crossing {d} {d} {d} {d}\\n", .{ r.net, q.net, @as(i32, @intFromFloat(if (a[1] == b[1]) c[0] else a[0])), @as(i32, @intFromFloat(if (a[1] == b[1]) a[1] else c[1])) });
            }'''.replace('PAIR_IDS', pair_ids))
edit('src/thin.zig','''    for (0..style.len) |_| {''','''    for (0..style.len) |trace_iteration| {''')
edit('src/thin.zig','''        if (worst == none) break;
        any = true;''','''        for (count, 0..) |n, net| if (n != 0 or gone[net]) {
            std.debug.print("TRACE count {d} {d} {d} {t} {} {} {d}\\n", .{ trace_iteration, net, n, style[net], gone[net], steps(roles[net], style[net], gone[net]), if (style[net] == .cut) cut_max else max });
        };
        std.debug.print("TRACE worst {d} {d}\\n", .{ trace_iteration, worst });
        if (worst == none) break;
        any = true;''')
if pair_ids == 'i, j':
    edit('src/thin.zig', '        var worst: u32 = none;', '''        for (peak, 0..) |value, net| if (style[net] == .cut) {
            std.debug.print("TRACE peak {d} {d} {d}\\n", .{ trace_iteration, net, value });
        };
        for (parent, part_count, 0..) |part, value, route| if (style[routes[route].net] == .cut) {
            std.debug.print("TRACE component {d} {d} {d} {d} {d}\\n", .{ trace_iteration, route, routes[route].net, part, value });
        };
        var worst: u32 = none;''')
edit('src/thin.zig','''            style[net] = if (style[net] == .auto) .cut else .label;''','''            std.debug.print("TRACE change {d} {d} {t} {t} {d}\\n", .{ trace_iteration, net, style[net], if (style[net] == .auto) Style.cut else Style.label, count[net] });
            style[net] = if (style[net] == .auto) .cut else .label;''')
edit('src/wires.zig','''    // One part is the whole net, the wire that crossed too much: names.
    if (std.mem.allEqual(u32, part, 0)) {''','''    for (pins, part) |pin, group| {
        const p = pinAt(c.s, pin);
        std.debug.print("TRACE part {s} {d} {d} {d} {d} {t}\\n", .{ c.s.net_name[net], pin, group, p.x, p.y, c.s.pins.items(.side)[pin] });
    }
    // One part is the whole net, the wire that crossed too much: names.
    if (std.mem.allEqual(u32, part, 0)) {
        std.debug.print("TRACE part_all_label {s}\\n", .{c.s.net_name[net]});''')
edit('src/wires.zig','''        if (members.items.len >= 2 and try trunk.draw(c, net, members.items, .name)) continue;
        for (members.items) |p| try c.labelAt(p);''','''        const trace_trunk = members.items.len >= 2 and try trunk.draw(c, net, members.items, .name);
        std.debug.print("TRACE part_trunk {s} {d} {d} {}\\n", .{ c.s.net_name[net], g, members.items.len, trace_trunk });
        if (trace_trunk) continue;
        for (members.items) |p| try c.labelAt(p);''')
if True:
 condition='std.mem.eql(u8, s.net_name[net], "veaout") and pins.len == 2'
 edit('src/trunk.zig','    const column = sameX(s, pins);', '''    if (CONDITION) {
        for (pins) |p| {
            const at = pinAt(s, p);
            std.debug.print("TRACE trunk_pin {d} {d} {d} {t}\\n", .{ p, at.x, at.y, s.pins.items(.side)[p] });
        }
        for (c.segs.items) |seg| if (seg.net != net) {
            std.debug.print("TRACE trunk_barrier {s} {d} {d} {d} {d}\\n", .{ s.net_name[seg.net], seg.a.x, seg.a.y, seg.b.x, seg.b.y });
        };
    }
    const column = sameX(s, pins);'''.replace('CONDITION',condition))
 edit('src/trunk.zig','                if (lay != .rungs and !tap_row and count >= fewest) continue;', '''                if (CONDITION) {
                    std.debug.print("TRACE trunk_candidate {t} {d} {d} {d} {d} {t}\\n", .{ lay, track, tap_dx, count, fewest, end });
                    for (tried.items, 0..) |*line, li| for (line.slice(), 0..) |point, pi| {
                        std.debug.print("TRACE trunk_point {t} {d} {d} {d} {d} {d} {d}\\n", .{ lay, track, tap_dx, li, pi, point.x, point.y });
                    };
                }
                if (lay != .rungs and !tap_row and count >= fewest) continue;'''.replace('CONDITION',condition))
 edit('src/trunk.zig','                if (count == std.math.maxInt(i64) or !linesFit(c, net, tried.items)) continue;', '''                const trace_fit = count != std.math.maxInt(i64) and linesFit(c, net, tried.items);
                if (CONDITION) std.debug.print("TRACE trunk_fit {t} {d} {d} {}\\n", .{ lay, track, tap_dx, trace_fit });
                if (!trace_fit) continue;'''.replace('CONDITION',condition))
manifest={'revision':revision,'source_sha256':source_hashes,'instrumented_sha256':{r:hashlib.sha256((out/r).read_bytes()).hexdigest() for r in ['src/sketch.zig','src/thin.zig','src/wires.zig','src/trunk.zig']},'cases':['ag-2365'],'snapshot_version':args.version}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
print('Prepared',out,'with',len(source_hashes),'frozen source files; no builds run')
