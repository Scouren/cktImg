#!/usr/bin/env python3
"""Certify retained clamp diagnostic captures; this is not the final native gate.

Usage: antiparallel_diagnostics.py ARCHIVE TRACE_PARENT OUTPUT [--check]

ARCHIVE contains iteration21-placement-{a,b}, both antiparallel-placement
directories and the captured trace JSON/raw-artifact directories. TRACE_PARENT
contains the two immutable copied-source trace builds. Every retained native,
report and SVG file is checked byte-for-byte against its instrumented twin.
Both frozen and instrumented source hashes are checked before interpreting
traces. The source relation certificate is independently replayed by
antiparallel_clamps.py and antiparallel_anchors.py.
"""
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
IDS = ['ag-1048', 'ag-1052', 'ag-1149', 'ag-739']
COPIES = {'a': 'cktimg-clamp-trace21', 'b': 'cktimg-clamp-anchors-trace21'}
TRACE = {'a': 'iteration21-antiparallel-trace-a', 'b': 'iteration21-antiparallel-anchor-trace-b'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def same(a, b, context):
    if a != b:
        raise ValueError(context)


def identity(original, instrumented):
    if original != instrumented:
        raise ValueError('instrumentation changed artifact bytes')
    return hashlib.sha256(original).hexdigest()


def exact_names(rows):
    return [r['id'] + ':compact=' + str(r['compact']).lower() + ':high_budget=' +
            str(r['high_budget']).lower() for r in rows]


def methods():
    same(identity(b'one', b'one'), hashlib.sha256(b'one').hexdigest(), 'identity oracle')
    for name, a, b in [('changed_geometry', b'pin=1', b'pin=2'),
                       ('changed_report', b'honoured', b'relaxed'),
                       ('changed_svg', b'line', b'label')]:
        try:
            identity(a, b)
        except ValueError:
            pass
        else:
            raise ValueError('mutation survived: ' + name)
    return ['literal_equal_bytes', 'changed_geometry', 'changed_report', 'changed_svg',
            'exact_sixteen_named_states', 'every_frozen_source_hash',
            'every_instrumented_source_hash', 'every_binary_hash',
            'every_raw_trace_hash', 'every_native_source_path_name',
            'reciprocal_mate_handles_bound_to_device_names']


def inspect(archive, trace_parent, version, expected_paths):
    native = archive / ('iteration21-antiparallel-placement-' + version)
    raw = archive / TRACE[version]
    frozen = archive / ('iteration21-placement-' + version)
    copied = trace_parent / COPIES[version]
    observed_path = native / 'observations.json'
    trace_path = archive / (TRACE[version] + '.json')
    observed = json.loads(observed_path.read_text())
    traced = json.loads(trace_path.read_text())
    manifest = traced['manifest']
    same(digest(observed_path), traced['observations_sha256'], 'captured observation provenance')
    same(digest(frozen / 'cktimg-json'), observed['binary_sha256'], 'frozen native binary')
    same(manifest['frozen_binary_sha256'], observed['binary_sha256'], 'trace frozen binary')
    trace_binary = copied / 'out/bin/cktimg-json-trace'
    same(digest(trace_binary), traced.get('trace_binary_sha256', traced.get('binary_sha256')), 'trace binary')
    trace_only_inputs = {}
    for rel, wanted in manifest['source_sha256'].items():
        frozen_path = frozen / 'sources' / rel
        if version == 'a' and rel == 'tests/symbols.zon':
            # The original placement-a freeze predates retained generated
            # inputs. This extra trace input is preserved in the copy only;
            # exact rendered bytes certify the sixteen observed states.
            trace_only_inputs[rel] = wanted
        else:
            same(digest(frozen_path), wanted, 'frozen source: ' + rel)
        if rel not in manifest['instrumented_sha256'] and rel != 'build.zig':
            same(digest(copied / rel), wanted, 'unchanged copied source: ' + rel)
    for rel, wanted in manifest['instrumented_sha256'].items():
        same(digest(copied / rel), wanted, 'instrumented source: ' + rel)
    generated = {}
    if version == 'b':
        declared = json.loads((frozen / 'manifest.json').read_text())['generated_inputs']
        for rel, wanted in declared.items():
            same(digest(frozen / rel), wanted, 'frozen generated input: ' + rel)
            generated[rel] = wanted
    wanted_names = [n + ':compact=' + str(c).lower() + ':high_budget=' + str(h).lower()
                    for n in IDS for c in (False, True) for h in (False, True)]
    same(traced['exact_names'], wanted_names, 'exact trace names')
    same(exact_names(traced['rows']), wanted_names, 'trace state order')
    same([(r['id'], r['compact'], r['diagnostic_high_crossing_budget']) for r in observed['observations']],
         [(n, c, h) for n in IDS for c in (False, True) for h in (False, True)], 'native state order')
    rows = []
    for obs, trace in zip(observed['observations'], traced['rows']):
        mode = ('compact' if obs['compact'] else 'uncompacted') + ('-high-budget' if trace['high_budget'] else '')
        stem = obs['id'] + '-' + mode
        hashes = {}
        for kind, suffix in [('json', '.json'), ('svg', '.svg'), ('report', '.report.json')]:
            filename = stem + suffix
            hashes[filename] = identity((native / filename).read_bytes(), (raw / filename).read_bytes())
            same(hashes[filename], obs['artifacts'][kind], 'native artifact hash: ' + filename)
            retained = trace.get('output_sha256', trace.get('unchanged_sha256'))
            same(hashes[filename], retained[filename], 'trace artifact hash: ' + filename)
        same(digest(raw / (stem + '.log')), trace['log_sha256'], 'raw trace hash')
        same([p['name'] for p in obs['paths']], expected_paths[obs['id']], 'exact physical-path names')
        paths = [dict(name=p['name'], net=p['net'], pins=p['pins'], points=p['points'],
                      continuous=p['continuous']) for p in obs['paths']]
        row = dict(id=obs['id'], compact=obs['compact'], high_budget=trace['high_budget'],
                   geometry=obs['geometry'], paths=paths, artifacts_sha256=hashes,
                   raw_trace_sha256=trace['log_sha256'])
        if version == 'a':
            row['rounds'] = [dict(round=r['round'], changes=r['changes'],
                                  whole_part_labels=r['part_all_label'], part_trunks=r['part_trunk'])
                             for r in trace['rounds']]
        else:
            row['placement_trace'] = trace['trace']
            row['strict_anchor_relation'] = trace['relation']
            if not obs['compact'] and not trace['high_budget'] and obs['id'] in ('ag-1048', 'ag-1052'):
                drawing = json.loads((native / (stem + '.json')).read_text())
                pair = ('m5', 'm6') if obs['id'] == 'ag-1048' else ('m6', 'm7')
                handles = {d['name']: i for i, d in enumerate(drawing['devices'])}
                mates = {}
                for line in trace['trace']:
                    words = line.split()
                    if words[:2] == ['CLAMP', 'member'] and words[2] in pair:
                        mates[words[2]] = int(words[-1].split('=')[1])
                same(mates, {pair[0]: handles[pair[1]], pair[1]: handles[pair[0]]}, 'actual reciprocal mates')
                same(trace['trace'][-1], 'CLAMP collect mate', 'exact pre-proposal rejection')
                row['reciprocal_mates'] = {name: dict(handle=handles[name], mate=mates[name]) for name in pair}
        rows.append(row)
    return dict(version=version, binary_sha256=observed['binary_sha256'],
                trace_binary_sha256=digest(trace_binary), source_sha256=manifest['source_sha256'],
                instrumented_source_sha256=manifest['instrumented_sha256'],
                generated_inputs_sha256=generated, trace_only_inputs_sha256=trace_only_inputs,
                capture_sha256={'observations': digest(observed_path), 'trace': digest(trace_path)},
                exact_names=wanted_names, rows=rows)


def audit(archive, trace_parent):
    source_path = HERE / 'antiparallel_clamps_cases.json'
    source = json.loads(source_path.read_text())
    paths = {n: [] for n in IDS}
    for p in source['group_paths'] + source['ag1149_regression_paths']:
        paths[p['id']].append(p['id'] + ':' + p['net'] + ':' + '--'.join(n + '.' + str(i) for n, i in p['pins']))
    return dict(methods=methods(), source_certificate_sha256=digest(source_path),
                audit_sha256=digest(Path(__file__)), captures=[inspect(archive, trace_parent, v, paths) for v in ('a', 'b')],
                limits='Historical placement-a/b diagnostics, not final checkpoint validation. High-budget states are diagnostic only. AG1149 remains a named source-connected failure. Captured source manifests identify dirty snapshots; neither is a claimed Git revision.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('trace_parent', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = audit(args.archive, args.trace_parent)
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    if args.check:
        same(result, json.loads((HERE / 'antiparallel_diagnostics_cases.json').read_text()), 'every recorded diagnostic field')
    print(json.dumps(dict(methods=result['methods'], captures={c['version']: c['exact_names'] for c in result['captures']}), sort_keys=True))


if __name__ == '__main__':
    main()
