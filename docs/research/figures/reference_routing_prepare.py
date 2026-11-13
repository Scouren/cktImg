#!/usr/bin/env python3
"""Prepare printing-only copied17/18 traces, never build or edit shipping files."""
from pathlib import Path
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--version',choices=('17','18'),required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[3]
snapshot=json.loads(Path(__file__).with_name('reference_routing_snapshot.json').read_text())
assert hashlib.sha256((root/'docs/research/figures/thin_row_trace_prepare.py').read_bytes()).hexdigest()==snapshot['base_instrumentation_sha256']
# Reuse frozen instrumentation statements, with source acquisition explicitly replaced.
s=(root/'docs/research/figures/thin_row_trace_prepare.py').read_text()
start=s.index('parser=argparse.ArgumentParser');end=s.index("(out/'symbols.zig').write_text")
replacement='''root=Path(ROOT_LITERAL)
out=Path(OUTPUT_LITERAL).resolve()
assert out != root and root not in out.parents
snapshot=json.loads((root/'docs/research/figures/reference_routing_snapshot.json').read_text())
revision=subprocess.check_output(['git','rev-parse',snapshot['base_revision']],cwd=root,text=True).strip()
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',revision,'src'],cwd=root,text=True).splitlines()
paths=sorted(p for p in paths if p.endswith('.zig'))+['tools/json.zig','tests/svg.zig','tests/symbols.zon']
source_hashes={}
for rel in paths:
    data=snapshot['overrides'][rel].encode() if VERSION_LITERAL=='18' and rel in snapshot['overrides'] else subprocess.check_output(['git','show',revision+':'+rel],cwd=root)
    target=out/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
    source_hashes[rel]=hashlib.sha256(data).hexdigest()
'''.replace('ROOT_LITERAL',repr(str(root))).replace('OUTPUT_LITERAL',repr(str(a.output))).replace('VERSION_LITERAL',repr(a.version))
s=s[:start]+replacement+s[end:]
s=s.replace("condition='std.mem.eql(u8, s.net_name[net], \"veaout\") and pins.len == 2'", "condition='std.mem.eql(u8, s.net_name[net], \"vin\") or std.mem.eql(u8, s.net_name[net], \"net4\")'")
s=s.replace('TRACE trunk_pin {d}', 'TRACE trunk_pin {s} {d}').replace('.{ p, at.x, at.y, s.pins.items(.side)[p] }', '.{ s.net_name[net], p, at.x, at.y, s.pins.items(.side)[p] }')
s=s[:s.index('manifest=')]
ns={};exec(compile(s,'frozen_trace_preparer','exec'),ns)
if a.version=='18':assert ns['source_hashes']==snapshot['source_sha256']
edit=ns['edit'];out=a.output.resolve();condition=ns['condition']
edit('src/trunk.zig','                if (needs_end and t_free == null) continue;', '''                if (CONDITION) std.debug.print("TRACE trunk_free {t} {d} {d} {} {any}\\n", .{ lay, track, tap_dx, needs_end, t_free });
                if (needs_end and t_free == null) continue;'''.replace('CONDITION',condition))
edit('src/trunk.zig','    if (fewest == std.math.maxInt(i64)) return false;', '''    if (CONDITION) std.debug.print("TRACE trunk_result {s} {t} {d} {d} {d} {d}\\n", .{ s.net_name[net], end, fewest, lo, hi, y_t });
    if (fewest == std.math.maxInt(i64)) return false;'''.replace('CONDITION',condition))
edit('src/wires.zig','''    return box.max.x - box.min.x + box.max.y - box.min.y <= limit;''','''    const result = box.max.x - box.min.x + box.max.y - box.min.y <= limit;
    std.debug.print("TRACE ported_near {s} {d} {d} {d} {d} {d} {}\\n", .{ c.s.net_name[c.s.pins.items(.net)[pins[0]]], box.min.x, box.min.y, box.max.x, box.max.y, limit, result });
    return result;''')
edit('src/wires.zig','''    if (pins.len >= 2 and near(c, pins, null) and try trunk.draw(c, net, pins, if (bias) .name else .port)) return;
    for (pins) |p| try terminal(c, p);''','''    if (pins.len >= 2 and near(c, pins, null) and try trunk.draw(c, net, pins, if (bias) .name else .port)) return;
    std.debug.print("TRACE ported_separate {s} {d}\\n", .{ s.net_name[net], pins.len });
    for (pins) |p| try terminal(c, p);''')
manifest=dict(revision=ns['revision'],snapshot_version=a.version,source_sha256=ns['source_hashes'],instrumented_sha256={r:hashlib.sha256((out/r).read_bytes()).hexdigest() for r in ['src/sketch.zig','src/thin.zig','src/wires.zig','src/trunk.zig']},cases=['ag-2415','ag-2428','ag-2434','ag-2436'],source_kind='committed17' if a.version=='17' else 'working18_exact_hashes',base_instrumentation_sha256=hashlib.sha256((root/'docs/research/figures/thin_row_trace_prepare.py').read_bytes()).hexdigest())
(out/'manifest.json').write_text(json.dumps(manifest,sort_keys=True,indent=2)+'\n')
print('Prepared',out,'No builds run')
