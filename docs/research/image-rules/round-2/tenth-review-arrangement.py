#!/usr/bin/env python3
"""Independent literal/interface review of saved tenth arrangements; no CLI run."""
import argparse
import ast
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
RUN = BASE / 'image-rule-round-2/bodies/tenth-review-arrangement'
FROZEN = BASE / 'resistor-output-integrated-common'
EXAMPLES = ROOT / 'external/examples/analoggenie'
NOTES = {
    'ag-1028-keep': 'Actual view: output branches surround the input pair; the retained pose is nested, not a left/right stage split.',
    'ag-1028-right': 'Actual view: input parent left and translated output parent right, with very long shared rail and interface wires; expression does not establish compactness.',
    'ag-1028-below': 'Actual view: translated output parent below, separated by a large blank region and long interface paths; no preference inference.',
    'ag-364-keep': 'Actual view: two output branches flank the tall nine-device inner parent, preserving the original source nested relation.',
    'ag-364-right': 'Actual view: inner parent remains left and output branches move right together; long interface paths connect them.',
    'ag-364-below': 'Actual view: output branches move below the inner parent with a large vertical interval and long external interfaces.',
    'ag-364-tail-keep': 'Actual view: invented M14 feeds an outer bridge around the retained inner parent; vb3 text is crossed by a short core gate connection, so no whole-drawing readability claim.',
    'ag-364-tail-right': 'Actual view: invented tail and both output branches translate right together, retaining a tall output-parent scaffold; no source human arrangement exists for this mutation.',
    'ag-1028': 'Fresh original pair view: source is left/right stages while native output branches surround the input pair. Boundary identity alone does not select the source arrangement.',
    'ag-364': 'Fresh original pair view: source and native both place the output branches around the inner nine-device parent.',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def literal_deck(text):
    """Strict reader for these flat MOS-only literals, independent of peer parser."""
    cards, models, hints, formals = {}, {}, {}, None
    active = False
    for line in text.lower().splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == '*@':
            assert len(words) == 6 and words[1] == 'at'
            assert words[2] not in hints
            hints[words[2]] = words[3:]
        elif words[0].startswith('*'):
            continue
        elif words[0] == '.model':
            assert not active and len(words) == 3 and words[1] not in models
            models[words[1]] = words[2:]
        elif words[0] == '.subckt':
            assert words[1] == 'dut' and formals is None
            active, formals = True, words[2:]
        elif words[0] == '.ends':
            assert active and words == ['.ends', 'dut']
            active = False
        else:
            assert active and words[0].startswith('m') and words[0] not in cards
            assert len(words) == 10 and words[5] in models
            assert all('=' in value for value in words[6:])
            cards[words[0]] = words
    assert formals is not None and not active
    return cards, formals, models, hints


def raw_stars(record, cards):
    parents = record['parents']
    members = [d for parent in parents for d in parent]
    assert len(members) == len(set(members)) and set(members) == set(cards)
    owner = {d: k for k, parent in enumerate(parents) for d in parent}
    incidence = {}
    for d, card in sorted(cards.items()):
        for role, net in enumerate(card[1:5]):
            incidence.setdefault(net, []).append([d, role, owner[d], card[5:]])
    assert incidence == record['all_terminal_incidences']
    stars = {}
    for net, rows in incidence.items():
        producers = {p for _, role, p, _ in rows if role in (0, 2)}
        consumers = {p for _, role, p, _ in rows if role == 1}
        if net in record['admitted_rail_facts'] or not producers:
            continue
        assert len(producers) == 1
        producer = next(iter(producers))
        if consumers - producers:
            stars[net] = dict(producer=producer, consumers=sorted(consumers - producers), all_incidences=rows)
    assert stars == record['boundary_stars']
    return stars


def tree_leaves(node):
    if isinstance(node, ast.Constant):
        assert isinstance(node.value, int) and node.value >= 0
        return [node.value]
    assert isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    assert node.func.id in ('H', 'V') and len(node.args) == 2 and not node.keywords
    return tree_leaves(node.args[0]) + tree_leaves(node.args[1])


def check_graphs(graphs):
    rows = {}
    for name, record in graphs['candidates'].items():
        cards, formals, models, hints = literal_deck((EXAMPLES / (name + '.cir')).read_text())
        assert not hints and [cards[n] for n in sorted(cards)] == record['ordered_cards']
        assert record['formals'] == formals and record['model_definitions'] == models
        stars = raw_stars(record, cards)
        n = len(record['parents'])
        path = ROOT / record['finite_symbolic_candidates']['path']
        assert sha(path) == record['finite_symbolic_candidates']['sha256']
        trees = path.read_text().splitlines()
        assert trees[0] == 'KEEP_INCUMBENT' and len(trees) == len(set(trees))
        # Catalan shapes * leaf permutations * independent binary H/V choices.
        expected_count = math.comb(2 * (n - 1), n - 1) // n * math.factorial(n) * 2 ** (n - 1) + 1
        assert len(trees) == expected_count == record['finite_symbolic_candidates']['count']
        for tree in trees[1:]:
            assert sorted(tree_leaves(ast.parse(tree, mode='eval').body)) == list(range(n))
        rows[name] = dict(devices=len(cards), ordered_terminal_occurrences=4 * len(cards),
                          boundary_stars=stars, symbolic_rows=expected_count)
    a, b = graphs['candidates']['ag-1028'], graphs['candidates']['ag-364']
    assert a['model_definitions'] == b['model_definitions'] == {'nch': ['nmos'], 'pch': ['pmos']}
    transport = graphs['ag1028_to_ag364_boundary_transport']
    dm, nm = transport['device_map'], transport['net_map']
    assert dm == dict(m1='m3', m2='m4', m3='m5', m4='m6', m6='m9', m7='m10')
    assert nm == dict(net3='x', net1='y')
    for net, target in nm.items():
        left, right = a['boundary_stars'][net], b['boundary_stars'][target]
        assert len(left['all_incidences']) == len(right['all_incidences']) == 3
        assert sorted([dm[d], role, parent, params] for d, role, parent, params in left['all_incidences']) == sorted(right['all_incidences'])
        assert left['producer'] == right['producer'] and left['consumers'] == right['consumers']
        assert net not in a['formals'] and target not in b['formals']
        assert nm[a['reflection']['nets'][net]] == b['reflection']['nets'][target]
    for d, target in dm.items():
        assert dm[a['reflection']['devices'][d]] == b['reflection']['devices'][target]
    assert len(a['ordered_cards']) == 10 and len(b['ordered_cards']) == 13
    assert len(a['formals']) == 8 and len(b['formals']) == 11
    return rows


def physical_pins(d):
    """Frozen default class literal points and independent integer rotation matrix."""
    matrices = [(1, 0, 0, 1), (0, -1, 1, 0), (-1, 0, 0, -1), (0, 1, -1, 0)]
    a, b, c, e = matrices[d['rot']]
    points = []
    for x, y in [(20, 0), (0, -20), (-20, 0)]:
        x *= -1 if d['mirror'] else 1
        points.append([d['pos'][0] + a * x + b * y, d['pos'][1] + c * x + e * y])
    return points


def native_bindings(cards, models, hints, data):
    assert len(data['devices']) == len({d['name'] for d in data['devices']})
    devices = {d['name']: d for d in data['devices'] if d['class'] in ('nmos', 'pmos')}
    assert set(devices) == set(cards)
    for d, card in cards.items():
        actual = devices[d]
        assert actual['class'] == models[card[5]][0]
        assert [p['term'] for p in actual['pins']] == ['d', 'g', 's']
        assert [p['net'] for p in actual['pins']] + [actual['bulk']] == card[1:5]
        assert actual['value'].split() == card[5:]
        x, y, orient = hints[d]
        assert actual['pos'] == [float(x) * 40, float(y) * 40]
        assert actual['rot'] == int(orient.lstrip('m')[1:]) // 90
        assert actual['mirror'] == orient.startswith('m')
        assert [p['xy'] for p in actual['pins']] == physical_pins(actual)
    return devices


def check_literals(literals):
    by_name = {r['name']: r for r in literals['records']}
    results = {}
    for name, record in by_name.items():
        deck = ROOT / record['deck']
        assert sha(deck) == record['deck_sha256']
        for path, digest in record['outputs'].items():
            assert sha(ROOT / path) == digest
        cards, formals, models, hints = literal_deck(deck.read_text())
        assert cards == record['raw_facts']['cards'] and formals == record['raw_facts']['formals']
        assert models == record['raw_facts']['models'] and set(hints) == set(cards)
        path = next(ROOT / p for p in record['outputs'] if p.endswith('.json') and not p.endswith('.report.json'))
        data = json.loads(path.read_text())
        devices = native_bindings(cards, models, hints, data)
        assert devices == record['actual_devices']
        baseline_name = name.rsplit('-', 1)[0] + '-keep'
        baseline = by_name[baseline_name]
        assert cards == baseline['raw_facts']['cards']
        offset = {'keep': [0, 0], 'right': [1000, 0], 'below': [0, 800]}[record['arrangement']]
        translated = set(record['raw_decomposition']['proposed_groups'][1])
        for d, actual in devices.items():
            before = baseline['actual_devices'][d]
            shift = offset if d in translated else [0, 0]
            assert [actual['pos'][k] - before['pos'][k] for k in range(2)] == shift
            assert (actual['rot'], actual['mirror']) == (before['rot'], before['mirror'])
            assert [[p['xy'][k] - q['xy'][k] for k in range(2)] for p, q in zip(actual['pins'], before['pins'])] == [shift] * 3
        results[name] = dict(devices=len(devices), raw_terminal_occurrences=4 * len(devices),
                             checked_visible_contacts=3 * len(devices), parent_translation=offset)
    base = by_name['ag-364-keep']['raw_facts']['cards']
    tail = by_name['ag-364-tail-keep']['raw_facts']['cards']
    assert set(tail) - set(base) == {'m14'} and not set(base) - set(tail)
    changes = [[d, k, a, b] for d in base for k, (a, b) in enumerate(zip(base[d], tail[d])) if a != b]
    assert sorted(changes) == [['m10', 3, 'vdd', 'ptail'], ['m9', 3, 'vdd', 'ptail']]
    assert tail['m14'] == ['m14', 'ptail', 'vb3', 'vdd', 'vdd', 'pch', 'l=0.15', 'w=1', 'nf=1', 'm=1']
    assert len(by_name['ag-364-tail-keep']['raw_decomposition']['channel_components']) == 2
    return results


def attacks(literals):
    parser = module(HERE / 'ninth-local-groups-census.py', 'ninth_attack_parser')
    old = module(RUN / 'tenth-arrangement-literals-before-review.py', 'old_literals')
    current = module(HERE / 'tenth-arrangement-literals.py', 'new_literals')
    record = literals['records'][0]
    report = json.loads((ROOT / next(p for p in record['outputs'] if p.endswith('.report.json'))).read_text())
    results = {}
    for name in ('extra_mos', 'duplicate_mos'):
        data = json.loads((RUN / (name + '.json')).read_text())
        args = ((ROOT / record['deck']).read_text(), record['raw_facts']['cards'], record['actual_devices'], data, report, parser)
        old.check_actual(*args)
        try:
            current.check_actual(*args)
        except AssertionError:
            results[name] = dict(old_accepted=True, current_rejected=True, mutation_sha256=sha(RUN / (name + '.json')))
        else:
            raise AssertionError('retained inventory attack still accepted: ' + name)
    helper = module(ROOT / 'docs/research/figures/channel_bridges.py', 'stub_helper')
    probe = json.loads((RUN / 'hidden-stub-probe.json').read_text())
    source, mutation = EXAMPLES / 'ag-1028.svg', RUN / 'ag-1028-hidden-own-stub.svg'
    assert sha(source) == probe['original_sha256'] and sha(mutation) == probe['mutation_sha256']
    assert sha(Path(helper.__file__)) == probe['helper_sha256']
    assert helper.svg_channel(source, probe['device']) == helper.svg_channel(mutation, probe['device'])
    assert any(e.get('visibility') == 'hidden' and e.get('points') == probe['original_stub_attributes']['points'] for e in ET.parse(mutation).getroot().iter())
    results['hidden_own_stub'] = dict(helper_unchanged_acceptance=True, scope='Frozen-original geometry only; no visibility/CSS admission.', **probe)
    return results


def oracle_controls(graphs, literals):
    rejected = []
    for name in ('missing_body_incidence', 'missing_interface_consumer'):
        record = copy.deepcopy(graphs['candidates']['ag-1028'])
        cards, _, _, _ = literal_deck((EXAMPLES / 'ag-1028.cir').read_text())
        if name == 'missing_body_incidence':
            record['all_terminal_incidences']['vss'].remove(['m1', 3, 0, cards['m1'][5:]])
        else:
            record['boundary_stars']['net3']['all_incidences'].remove(['m6', 1, 1, cards['m6'][5:]])
        try:
            raw_stars(record, cards)
        except AssertionError:
            rejected.append(name)
        else:
            raise AssertionError('changed raw incidence accepted')
    r = literals['records'][0]
    data = json.loads((ROOT / next(p for p in r['outputs'] if p.endswith('.json') and not p.endswith('.report.json'))).read_text())
    cards, _, models, hints = literal_deck((ROOT / r['deck']).read_text())
    for name in ('changed_actual_bulk', 'swapped_actual_gate_source_roles', 'one_contact_shifted', 'unexpected_actual_mos'):
        changed = copy.deepcopy(data)
        d = next(d for d in changed['devices'] if d['name'] == 'm1')
        if name == 'changed_actual_bulk':
            d['bulk'] = 'vdd'
        elif name == 'swapped_actual_gate_source_roles':
            d['pins'][1]['term'], d['pins'][2]['term'] = d['pins'][2]['term'], d['pins'][1]['term']
        elif name == 'one_contact_shifted':
            d['pins'][1]['xy'][0] += 1
        else:
            extra = copy.deepcopy(d)
            extra['name'] = 'm_extra'
            changed['devices'].append(extra)
        try:
            native_bindings(cards, models, hints, changed)
        except AssertionError:
            rejected.append(name)
        else:
            raise AssertionError('changed native contract accepted')
    return rejected


def metric_comparison(literals):
    scores = {}
    for record in literals['records']:
        path = ROOT / next(p for p in record['outputs'] if p.endswith('.report.json'))
        metrics = json.loads(path.read_text())['metrics']
        family = record['name'].rsplit('-', 1)[0]
        scores.setdefault(family, {})[record['name']] = [metrics['crossings'], metrics['bends']]
    results = {}
    for family, candidates in scores.items():
        best = min(candidates.values())
        ties = sorted(name for name, value in candidates.items() if value == best)
        winner = family + '-keep' if family + '-keep' in ties else ties[0]
        results[family] = dict(scores=candidates, winner=winner)
    assert results['ag-1028']['winner'] == 'ag-1028-below'
    assert results['ag-364']['winner'] == 'ag-364-keep'
    assert results['ag-364-tail']['winner'] == 'ag-364-tail-keep'
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'tenth-review-arrangement.json')
    args = ap.parse_args()
    graph_path, literal_path = [HERE / ('tenth-arrangement-' + n + '.json') for n in ('graphs', 'literals')]
    graphs, literals = [json.loads(p.read_text()) for p in (graph_path, literal_path)]
    for path, digest in literals['dependencies'].items():
        assert sha(ROOT / path) == digest
    symbol_path = FROZEN / 'tests/symbols.zon'
    for symbol in ('nmos', 'pmos'):
        line = next(line for line in symbol_path.read_text().splitlines() if '.name = "' + symbol + '"' in line)
        assert re.findall(r'\.name = "([dgs])", \.at = \.\{ \.x = (-?\d+), \.y = (-?\d+)', line) == [('d', '20', '0'), ('g', '0', '-20'), ('s', '-20', '0')]
    views = []
    for name, note in NOTES.items():
        subdir = 'ninth' if name in ('ag-1028', 'ag-364') else 'tenth'
        suffix = '-pair.png' if subdir == 'ninth' else '.png'
        path = HERE / 'figures/groups' / subdir / (name + suffix)
        views.append(dict(path=rel(path), sha256=sha(path), observation=note))
    result = dict(graphs=check_graphs(graphs), literals=check_literals(literals), attacks=attacks(literals), views=views,
                  independent_oracle_mutations_rejected=oracle_controls(graphs, literals),
                  independent_reported_metric_comparison=metric_comparison(literals),
                  reviewed_documents={rel(HERE / name): sha(HERE / name) for name in (
                      'tenth-arrangement-plan.md', 'tenth-arrangement-proof.py', 'tenth-arrangement-proof.json',
                      'tenth-arrangement-raster-proof.py', 'tenth-arrangement-raster-proof.json',
                      'tenth-acceptance-plan.md', 'tenth-search-contract.md')},
                  view_revision='All eight normalized PNGs actually re-viewed after deterministic metadata repair; original two source/native pair rasters unchanged.',
                  dependencies={rel(p): sha(p) for p in (Path(__file__), graph_path, literal_path,
                      HERE / 'tenth-arrangement-literals.py', RUN / 'tenth-arrangement-literals-before-review.py',
                      symbol_path, FROZEN / 'src/library.zig')},
                  scope='Independent saved-artifact, raw-literal and proof-boundary review; no new engine/host execution, automatic selection or invented human preference.')
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(graphs=len(result['graphs']), symbolic_rows=sum(r['symbolic_rows'] for r in result['graphs'].values()),
                         arrangements=len(result['literals']), native_devices=sum(r['devices'] for r in result['literals'].values()), attacks=len(result['attacks']))))


if __name__ == '__main__':
    main()
