#!/usr/bin/env python3
"""Replay actual source leads and native facing for all 58 observed banks.

Usage: driven_banks_native.py EXAMPLES WORK_DIR OUTPUT
       --baseline-bin BIN --candidate-bin BIN
       --baseline-corpus AG --baseline-corpus AMS
       --candidate-corpus AG --candidate-corpus AMS [--check]

This audit reads frozen executables and complete scored corpora. It verifies
every ordered block port and MOS D/G/S/body binding before comparing actual
terminal coordinates. The source reader independently replays SVG leads,
contact dots and exact source scope. It does not infer wire continuity from
gate facing; driven_banks_connectivity.py owns that separate measurement.
"""
import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import driven_banks as source


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def same(actual, expected, context):
    if actual != expected:
        raise ValueError(context + ' differs from the exact inventory')


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or '').split('.')[0] + '.py'
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    return dict(sorted(found.items()))


def corpus(examples, directory, binary):
    """Exact source/drawing/report filenames and all scored content hashes."""
    score = json.loads((directory / 'scorecard.json').read_text())
    names = sorted(p.name.removesuffix('.human.json') for p in examples.glob('*.human.json'))
    if not names:
        raise ValueError('empty source corpus')
    same(sorted(score['ids']), names, 'complete score IDs')
    same(sorted(score['results']), names, 'complete scored results')
    files = sorted(['scorecard.json'] + [n + s for n in names for s in ('.json', '.report.json')])
    same(sorted(p.name for p in directory.glob('*.json')), files, 'complete native files')
    same(score['binary_sha256'], digest(binary), 'frozen executable')
    same(digest(directory / 'cktimg-json'), digest(binary), 'corpus executable')
    same(score['index_sha256'], digest(examples / 'index.json'), 'source index')
    rows = []
    for name in names:
        paths = dict(deck_sha256=examples / (name + '.cir'), source_sha256=examples / (name + '.human.json'),
                     preview_sha256=examples / (name + '.svg'), geometry_sha256=directory / (name + '.json'),
                     report_sha256=directory / (name + '.report.json'))
        hashes = {key: digest(path) for key, path in paths.items()}
        for key, value in hashes.items():
            same(score['results'][name][key], value, name + ':' + key)
        rows.append(dict(id=name, **hashes))
    return dict(corpus=examples.name, binary_sha256=digest(binary), scorecard_sha256=digest(directory / 'scorecard.json'),
                inputs={k: score[k] for k in ('corpus_sha256', 'issues', 'index_sha256', 'measure_sha256', 'runner_sha256', 'scorer_sha256')},
                rows=rows)


def observe(drawing, row):
    devices = {d['name']: d for d in drawing['devices'] if d['name']}
    if len(devices) != sum(bool(d['name']) for d in drawing['devices']):
        raise ValueError('repeated native device name')
    driver = devices[row['driver']]
    same([(p['term'], p['net']) for p in driver['pins']], list(zip(row['ports'], row['bindings'])),
         'every ordered driver port and binding')
    output = driver['pins'][row['output_pin']]
    same((output['term'], output['net']), (row['output_port'], row['net']), 'declared output binding')
    gates = []
    for name in row['bank']:
        device = devices[name]
        card = row['bank_cards'][name]
        same([(p['term'], p['net']) for p in device['pins']], list(zip(('d', 'g', 's'), card[1:4])), 'MOS ordered D/G/S bindings')
        same(device['bulk'], card[4], 'MOS body binding')
        points = {p['term']: p['xy'] for p in device['pins']}
        gates.append(dict(card=name, terminals=points,
                          side=source.side(points['g'], [points['d'], points['s']]),
                          toward_output=source.toward(points['g'], [points['d'], points['s']], output['xy'])))
    return dict(driver_ports=driver['pins'], output=output['xy'], gates=gates)


def methods():
    row = dict(driver='x1', ports=['inp', 'out'], bindings=['ref', 'control'], output_pin=1,
               output_port='out', net='control', bank=['m1', 'm2'],
               bank_cards={'m1': 'm1 a control vdd vdd pch'.split(), 'm2': 'm2 b control vdd vdd pch'.split()})
    drawing = dict(devices=[dict(name='x1', pins=[dict(term='inp', net='ref', xy=[-40, 0]), dict(term='out', net='control', xy=[-20, 0])])])
    for i, name in enumerate(row['bank']):
        x = 20 + 80 * i
        drawing['devices'].append(dict(name=name, bulk='vdd', pins=[dict(term=t, net=n, xy=p) for t, n, p in
            zip(('d', 'g', 's'), row['bank_cards'][name][1:4], ([x, -20], [x-20, 0], [x, 20]))]))
    value = observe(drawing, row)
    assert all(g['side'] == 'left' and g['toward_output'] for g in value['gates'])
    names = ['actual_gate_relative_to_channel_not_origin']
    reverse = copy.deepcopy(drawing)
    reverse['devices'].reverse()
    same(observe(reverse, row), value, 'device card permutation')
    names.append('device_card_permutation')
    for name, mutate in (
        ('wrong_output_binding', lambda d: d['devices'][0]['pins'][1].update(net='other')),
        ('wrong_nonoutput_binding', lambda d: d['devices'][0]['pins'][0].update(net='other')),
        ('swapped_ordered_block_ports', lambda d: d['devices'][0]['pins'].reverse()),
        ('wrong_gate_binding', lambda d: d['devices'][1]['pins'][1].update(net='other')),
        ('wrong_body_binding', lambda d: d['devices'][1].update(bulk='other')),
        ('noncardinal_actual_gate', lambda d: d['devices'][1]['pins'][1].update(xy=[0, 5]))):
        changed = copy.deepcopy(drawing)
        mutate(changed)
        try:
            observe(changed, row)
        except ValueError:
            names.append(name)
        else:
            raise ValueError('mutation incorrectly accepted: ' + name)
    changed = copy.deepcopy(drawing)
    changed['devices'][1]['pins'][1]['xy'] = [40, 0]
    observed = observe(changed, row)
    assert observed['gates'][0]['side'] == 'right' and not observed['gates'][0]['toward_output']
    names.append('reflected_actual_gate_changes_facing')
    return names


def frozen(result):
    canonical = json.dumps(result, sort_keys=True, separators=(',', ':')).encode()
    return dict(evidence_sha256=hashlib.sha256(canonical).hexdigest(), source_inventory_sha256=result['source_inventory_sha256'],
                dependency_sha256=result['dependency_sha256'], method_checks=result['method_checks'],
                selected_names=result['selected_names'], broad_names=result['broad_names'],
                summaries=result['summaries'], changes=result['changes'],
                binary_sha256={stage: [c['binary_sha256'] for c in result['corpora'][stage]] for stage in ('baseline', 'candidate')})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('examples', 'work_dir', 'output'):
        parser.add_argument(name, type=Path)
    for stage in ('baseline', 'candidate'):
        parser.add_argument('--' + stage + '-bin', required=True, type=Path)
        parser.add_argument('--' + stage + '-corpus', action='append', required=True, type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    args.work_dir.mkdir(parents=True, exist_ok=True)
    source_path = args.work_dir / 'driven-bank-source.json'
    subprocess.run([sys.executable, '-B', str(HERE / 'driven_banks.py'), str(args.examples), str(source_path), '--check'], check=True, capture_output=True, text=True)
    evidence = json.loads(source_path.read_text())
    corpora, directories = {}, {}
    for stage in ('baseline', 'candidate'):
        dirs = getattr(args, stage + '_corpus')
        if len(dirs) != 2:
            raise ValueError('exactly one AG and one AMS directory are required')
        snapshots, by_name = [], {}
        for directory in dirs:
            ids = json.loads((directory / 'scorecard.json').read_text())['ids']
            name = 'analoggenie' if all(i.startswith('ag-') for i in ids) else 'amsnet'
            if name in by_name:
                raise ValueError('repeated corpus')
            by_name[name] = directory
            snapshots.append(corpus(args.examples / name, directory, getattr(args, stage + '_bin')))
        same(sorted(by_name), ['amsnet', 'analoggenie'], 'both source corpora')
        corpora[stage], directories[stage] = sorted(snapshots, key=lambda c: c['corpus']), by_name
    changes = dict(drawings=[], reports=[])
    for old, new in zip(corpora['baseline'], corpora['candidate']):
        same(old['corpus'], new['corpus'], 'paired corpus')
        same(old['inputs'], new['inputs'], 'paired score inputs')
        for a, b in zip(old['rows'], new['rows']):
            same(a['id'], b['id'], 'paired deck')
            for field in ('deck_sha256', 'source_sha256', 'preview_sha256'):
                same(a[field], b[field], 'paired source ' + field)
            for kind, field in (('drawings', 'geometry_sha256'), ('reports', 'report_sha256')):
                if a[field] != b[field]:
                    changes[kind].append(a['id'])
    rows = []
    for row in evidence['rows']:
        observations = {}
        for stage in ('baseline', 'candidate'):
            path = directories[stage][row['corpus']] / (row['id'] + '.json')
            observations[stage] = dict(observe(json.loads(path.read_text()), row), geometry_sha256=digest(path))
        rows.append(dict(name=row['id'] + ':' + row['driver'], admitted=row['admitted'],
                         source=row['source'], **observations))
    summaries = {}
    for stage in ('baseline', 'candidate'):
        selected = [r for r in rows if r['admitted']]
        mismatches = [r['name'] + ':' + gate['card'] for r in selected for gate, original in zip(r[stage]['gates'], r['source']['gates']) if gate['side'] != original['side']]
        summaries[stage] = dict(selected_banks=len(selected), selected_gates=2 * len(selected),
                                both_source_facing=[r['name'] for r in selected if all(g['side'] == h['side'] for g, h in zip(r[stage]['gates'], r['source']['gates']))],
                                both_toward_native_output=[r['name'] for r in selected if all(g['toward_output'] for g in r[stage]['gates'])],
                                source_facing_mismatches=mismatches)
    result = dict(source_inventory_sha256=digest(HERE / 'driven_banks_cases.json'), dependency_sha256=dependencies(),
                  selected_names=evidence['selected_names'], broad_names=[r['name'] for r in rows], method_checks=methods(),
                  corpora=corpora, rows=rows, summaries=summaries, changes={k: sorted(v) for k, v in changes.items()},
                  limits='Actual ordered native pins versus independently verified source leads. Source gate facing and physical connectivity remain separate; exact remaining facing mismatches are retained. No arbitrary caller-frame or whole-drawing equivalence claim.')
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if args.check:
        same(frozen(result), json.loads((HERE / 'driven_banks_native_cases.json').read_text()), 'every source/native facing field')
    print(json.dumps(dict(summaries=summaries, changes=result['changes']), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
