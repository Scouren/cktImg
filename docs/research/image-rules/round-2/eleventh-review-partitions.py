#!/usr/bin/env python3
"""Independent raw selector, segment-component oracle and retained input attacks."""
import argparse
import collections
import copy
from fractions import Fraction as Q
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
RUN = BASE / 'image-rule-round-2/bodies/eleventh-review-partitions'
EXAMPLES = ROOT / 'external/examples/analoggenie'
sys.path.insert(0, str(HERE))
from bodies_census import parse


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def signature(row, devices=None, nets=None):
    """Net-first reference; includes every raw role before considering parents."""
    dn, nn = devices or {}, nets or {}
    d, n = lambda x: dn.get(x, x), lambda x: nn.get(x, x)
    groups = row.get('proposed_groups', [])
    if not groups or not row.get('enumeration_complete'):
        return []
    maps = [m for m in row['enumerated_involutions'] if any(a != b for a, b in m['nets'].items())]
    if len(maps) != 1:
        return []
    reflection = maps[0]
    cards = {r[0]: r for r in row['ordered_cards']}
    owner = {x: tuple(g) for g in groups for x in g}
    assert len(owner) == len(cards) == sum(map(len, groups))
    inc = collections.defaultdict(list)
    for name, card in cards.items():
        for role, net in enumerate(card[1:5]):
            inc[net].append((name, role))
    by_parent = collections.defaultdict(list)
    for net, occurrences in inc.items():
        if len(occurrences) != 3 or net in row['formals'] or net in row['admitted_rail_facts']:
            continue
        if sorted(i for _, i in occurrences) != [0, 0, 1]:
            continue
        drains = [x for x, i in occurrences if i == 0]
        gate = next(x for x, i in occurrences if i == 1)
        if owner[drains[0]] != owner[drains[1]] or owner[gate] == owner[drains[0]]:
            continue
        parent = owner[drains[0]]
        if len(parent) != 4 or {reflection['devices'][x] for x in parent} != set(parent):
            continue
        types = {row['model_definitions'][cards[x][5]][0]: x for x in drains}
        if set(types) != {'pmos', 'nmos'}:
            continue
        if any(cards[x][3] != cards[x][4] or cards[x][3] not in row['admitted_rail_facts'] for x in drains):
            continue
        by_parent[parent].append((net, types['pmos'], types['nmos'], gate, owner[gate], tuple(sorted(occurrences))))
    found = []
    for parent, stacks in by_parent.items():
        if len(stacks) != 2:
            continue
        a, b = stacks
        if reflection['nets'][a[0]] != b[0] or any(reflection['devices'][a[i]] != b[i] for i in (1, 2, 3)) or a[4] != b[4]:
            continue
        for net, p, x, gate, outside, occurrences in stacks:
            found.append([sorted(d(y) for y in parent), n(net), d(p), d(x), d(gate), sorted(d(y) for y in outside),
                          sorted([d(y), i] for y, i in occurrences), n(cards[p][2]), n(cards[x][2])])
    return sorted(found)


def projected(found):
    return sorted([r['parent_members'], s['net'], s['p'], s['n'], s['outside_gate'], s['outside_parent'],
                   s['complete_occurrences'], r['control_nets']['p'][i], r['control_nets']['n'][i]]
                  for r in found for i, s in enumerate(r['stacks']))


def raw_review(saved, peer):
    census = json.loads((HERE / 'ninth-local-groups-census.json').read_text())
    assert saved['exact_names'] == census['names'] == sorted(p.stem for p in EXAMPLES.glob('*.cir'))
    assert saved['exact_parent_dispositions'] == census['disposition_names']
    all_names, signatures, invariant = {}, {}, {}
    for name in saved['exact_names']:
        path, row = EXAMPLES / (name + '.cir'), census['cases'][name]
        assert sha(path) == row['deck_sha256'] == saved['cases'][name]['deck_sha256']
        assert (row['disposition'], row['reasons']) == (saved['cases'][name]['parent_disposition'], saved['cases'][name]['parent_reasons'])
        actual = peer.raw.decompose(*peer.raw.facts(path.read_text()))
        assert actual == {k: v for k, v in row.items() if k not in ('deck_sha256', 'controls')}
        observed = signature(row)
        assert sorted({tuple(r[0]) for r in observed}) == sorted(tuple(r) for r in saved['cases'][name]['candidate_parent_members'])
        all_names.setdefault(row['disposition'], []).append(name)
        if not observed:
            continue
        assert observed == projected(saved['matching_cases'][name]['candidates'])
        formals, cards = parse(path.read_text())
        assert formals == row['formals'] and sorted(c['raw'].lower().split() for c in cards) == row['ordered_cards']
        models = {w[1]: w[2:] for line in path.read_text().lower().splitlines() if (w := line.split()) and w[0] == '.model'}
        assert models == row['model_definitions']
        signatures[name] = observed
        values = peer.raw.facts(path.read_text())
        cards, formals, models, rails, declarations = values
        reverse = peer.raw.decompose(dict(reversed(list(cards.items()))), formals, models, rails, declarations)
        assert signature(reverse) == observed
        dm = {d: 'mopaque' + str(i) for i, d in enumerate(reversed(sorted(cards)))}
        nm = {n: 'opaque' + str(i) for i, n in enumerate(reversed(sorted({n for c in cards.values() for n in c[1:5]})))}
        renamed = {dm[d]: [dm[d]] + [nm[n] for n in card[1:5]] + card[5:] for d, card in cards.items()}
        rr = peer.raw.decompose(renamed, [nm[n] for n in formals], models, {nm[n]: role for n, role in rails.items()}, declarations)
        assert signature(rr, {b: a for a, b in dm.items()}, {b: a for a, b in nm.items()}) == observed
        assert projected(peer.candidates(reverse)) == signature(reverse)
        assert projected(peer.candidates(rr)) == signature(rr)
        invariant[name] = ['card_order_complete_signature', 'rename_complete_incidence_controls_and_owner_signature']
    assert all_names == saved['exact_parent_dispositions']
    assert sorted(signatures) == ['ag-1053', 'ag-1079', 'ag-1080']
    assert {name: sorted({tuple(r[0]) for r in rows}) for name, rows in signatures.items()} == {
        'ag-1053': [('mn4', 'mn5', 'mp4', 'mp5')], 'ag-1079': [('m6', 'm7', 'm8', 'm9')],
        'ag-1080': [('m15', 'm16', 'm17', 'm18'), ('m6', 'm7', 'm8', 'm9')]}
    cycle = saved['matching_cases']['ag-1053']['complete_parent_context']['group_dependencies']
    assert cycle == {'0': [1], '1': [0]}
    return dict(exact_dispositions=all_names, complete_tuple_signatures=signatures, invariances=invariant, cycle=cycle)


def on(p, a, b):
    return (p[0]-a[0])*(b[1]-a[1]) == (p[1]-a[1])*(b[0]-a[0]) and all(min(a[k], b[k]) <= p[k] <= max(a[k], b[k]) for k in (0, 1))


def connected(segments, dots, a, b):
    """Independent segment adjacency: endpoint/T/overlap or explicit dot, no labels."""
    parent = list(range(len(segments)))
    def root(i):
        while parent[i] != i:
            i = parent[i]
        return i
    for i, (p, q) in enumerate(segments):
        for j, (r, s) in enumerate(segments[:i]):
            if any(on(t, r, s) for t in (p, q)) or any(on(t, p, q) for t in (r, s)) or any(on(t, p, q) and on(t, r, s) for t in dots):
                parent[root(i)] = root(j)
    hits = [{root(i) for i, (p, q) in enumerate(segments) if on(t, p, q)} for t in (a, b)]
    assert all(len(h) <= 1 for h in hits), 'ambiguous terminal on unjoined crossing'
    return a == b or bool(hits[0] & hits[1])


def svg_geometry(path, human, models, cards):
    """Literal original schema: untransformed world conductors, upright mirrored MOS."""
    root = ET.parse(path).getroot()
    parents = {c: p for p in root.iter() for c in p}
    def plain(element, allow_transform=False):
        e = element
        while True:
            assert not any(k in e.attrib for k in ('visibility', 'display', 'opacity', 'stroke-opacity', 'style', 'filter', 'mask', 'clip-path'))
            if not allow_transform or e is not element:
                assert 'transform' not in e.attrib
            if e not in parents:
                break
            e = parents[e]
    segments, dots, glyphs = [], [], {}
    for e in root.iter():
        if e.get('data-role') == 'conductor-ink':
            plain(e)
            assert e.get('stroke') == '#000' and Q(e.get('stroke-width')) > 0
            tokens = e.get('d').split()
            assert len(tokens) % 3 == 0
            point = None
            for i in range(0, len(tokens), 3):
                command, x, y = tokens[i:i+3]
                following = (Q(x), Q(y))
                if command == 'L':
                    assert point is not None
                    segments.append((point, following))
                else:
                    assert command == 'M'
                point = following
        if e.tag.rsplit('}', 1)[-1] == 'circle' and (e.get('data-node-kind') == 'contact' or e.get('data-object-id', '').endswith('-junction')):
            plain(e)
            dots.append((Q(e.get('cx')), Q(e.get('cy'))))
    for device in human['devices']:
        name = device['card']
        assert device['type'] == models[cards[name][5]][0]
        matches = []
        for e in root.iter():
            if e.get('data-symbol-id') != device['type']:
                continue
            plain(e)
            inner = list(e)[0]
            m = re.fullmatch(r'translate\((-?\d+) (-?\d+)\)( scale\(-1 1\))? rotate\(0\)', inner.get('transform', ''))
            assert m
            x, y, sign = Q(m[1]), Q(m[2]), -1 if m[3] else 1
            if [x, y] != [device['x'], device['y']]:
                continue
            points = []
            for c in inner.iter():
                assert c is inner or 'transform' not in c.attrib
                assert not any(k in c.attrib for k in ('visibility', 'display', 'opacity', 'style'))
                tag = c.tag.rsplit('}', 1)[-1]
                if tag == 'polyline':
                    values = [Q(v) for v in re.split('[ ,]+', c.get('points').strip())]
                    points.extend([(x+sign*values[0], y+values[1]), (x+sign*values[-2], y+values[-1])])
                elif tag == 'line':
                    points.extend((x+sign*Q(c.get(a)), y+Q(c.get(b))) for a, b in [('x1', 'y1'), ('x2', 'y2')])
            dy = -20 if device['type'] == 'nmos' else 20
            expected = {'D': (x+sign*10, y+dy), 'G': (x-sign*20, y), 'S': (x+sign*10, y-dy)}
            assert all(p in points and list(p) == device['terminals'][role] for role, p in expected.items())
            matches.append(expected)
        assert len(matches) == 1
        glyphs[name] = matches[0]
    return segments, dots, glyphs


def physical_review(saved):
    result = {}
    for ident, record in saved['physical_evidence'].items():
        context = saved['matching_cases'][ident]['complete_parent_context']
        cards = {r[0]: r for r in context['ordered_cards']}
        human = json.loads((EXAMPLES / (ident + '.human.json')).read_text())
        path = EXAMPLES / (ident + '.svg')
        segments, dots, glyphs = svg_geometry(path, human, context['model_definitions'], cards)
        drawing = json.loads((BASE / 'image-rule-round-2/groups/ninth' / (ident + '.json')).read_text())
        assert len({d['name'] for d in drawing['devices']}) == len(drawing['devices'])
        devices = {d['name']: d for d in drawing['devices'] if d['class'] in ('nmos', 'pmos')}
        assert set(devices) == set(cards)
        source_devices = {d['card']: d for d in human['devices']}
        for name, card in cards.items():
            d = devices[name]
            assert d['class'] == context['model_definitions'][card[5]][0]
            assert [p['term'] for p in d['pins']] == ['d', 'g', 's']
            assert [p['net'] for p in d['pins']] + [d['bulk']] == card[1:5] and d['value'].split() == card[5:]
            assert [source_devices[name]['nets'][r].lower() for r in 'DGSB'] == card[1:5]
        checks = []
        assert sorted(record['nets']) == {'ag-1053': ['net1', 'net3'], 'ag-1079': ['rn', 'rp'],
                                          'ag-1080': ['fn1', 'fp1', 'rn', 'rp']}[ident]
        for net, row in record['nets'].items():
            occurrences = sorted([name, i] for name, card in cards.items() for i, n in enumerate(card[1:5]) if n == net)
            assert len(occurrences) == 3
            assert [p['pins'] for p in row['pairs']] == [list(pair) for pair in itertools.combinations(occurrences, 2)]
            named = [(tuple(a), tuple(b)) for w in human['wires'] if w['net'].lower() == net for poly in w['segments'] for a, b in zip(poly, poly[1:])]
            assert all(s in segments or tuple(reversed(s)) in segments for s in named)
            native = [(tuple(a), tuple(b)) for w in drawing['wires'] if w['net'] == net for poly in w['segments'] for a, b in zip(poly, poly[1:])]
            for pair in row['pairs']:
                a, b = [glyphs[d]['DGS'[i]] for d, i in pair['pins']]
                positive = connected(named, dots, a, b)
                assert positive == pair['source_connected']
                assert positive == (ident == 'ag-1053' or all(i == 0 for _, i in pair['pins']))
                if not positive:
                    assert not connected(segments, dots, a, b)
                x, y = [tuple(devices[d]['pins'][i]['xy']) for d, i in pair['pins']]
                actual = connected(native, [tuple(p) for p in drawing['junctions']], x, y)
                assert actual == pair['native_connected']
                assert actual == (ident != 'ag-1080' or net not in ('fn1', 'fp1'))
                checks.append(dict(net=net, pins=pair['pins'], source_connected=positive, native_connected=actual))
        result[ident] = dict(glyphs=len(glyphs), bindings=4*len(cards), checked_pairs=checks,
                             conductor_segments=len(segments), source_svg_sha256=sha(path))
    return result


def retained_attacks(peer):
    snapshot = RUN / 'eleventh-partition-candidates-before-review.py'
    namespace = dict(__name__='archived_eleventh', __file__=str(HERE / 'eleventh-partition-candidates.py'))
    exec(compile(snapshot.read_text(), str(snapshot), 'exec'), namespace)
    results = {}
    for name in ('extra_unrelated_mos', 'duplicate_raw_mos', 'wrong_selected_class'):
        case = RUN / name
        namespace['HERE'], namespace['BASE'] = case / 'manifest', case / 'base'
        old_rejected = False
        try:
            namespace['caller_controls']()
        except (AssertionError, ValueError):
            old_rejected = True
        original_here, original_base = peer.HERE, peer.BASE
        peer.HERE, peer.BASE = case / 'manifest', case / 'base'
        try:
            peer.caller_controls()
        except (AssertionError, ValueError):
            current_rejected = True
        else:
            current_rejected = False
        finally:
            peer.HERE, peer.BASE = original_here, original_base
        assert old_rejected == (name == 'duplicate_raw_mos') and current_rejected
        results[name] = dict(old_rejected=old_rejected, current_rejected=current_rejected)
    return results


def scope_controls(saved, peer):
    controls = []
    cross = [((0, 0), (20, 0)), ((10, -10), (10, 10))]
    assert not connected(cross, [], (0, 0), (10, 10))
    assert connected(cross, [(10, 0)], (0, 0), (10, 10))
    assert not connected([((0, 0), (4, 0)), ((6, 0), (10, 0))], [], (0, 0), (10, 0))
    assert connected([((0, 0), (10, 0)), ((5, 0), (5, 10))], [], (0, 0), (5, 10))
    controls.extend(['undotted_X_separates', 'explicit_dot_joins', 'gap_separates', 'endpoint_T_joins'])
    pair = dict(net='fn1', pins=[['m16', 0], ['m18', 0]], terms=['d', 'd'])
    context = peer.ink.load_source(EXAMPLES, 'ag-1080')
    context['human']['wires'] = [w for w in context['human']['wires'] if w['net'].lower() != 'fn1']
    unassigned = peer.ink.source(context, pair)
    assert unassigned['status'] == 'unsupported' and unassigned['whole_svg_connection']['continuous']
    controls.append('actual_unassigned_FN1_path_declines_instead_of_false_separation')
    meta = json.loads((RUN / 'hidden-conductor-scope.json').read_text())
    path = ROOT / meta['mutation']
    assert sha(path) == meta['mutation_sha256']
    context = peer.ink.load_source(EXAMPLES, 'ag-1080')
    context['root'] = ET.parse(path).getroot()
    context['ink'] = peer.ink.conductor_ink(context['root'])
    context['source_sha256']['ag-1080.svg'] = sha(path)
    assert peer.ink.source(context, pair)['status'] == 'source_connected'
    raw = saved['matching_cases']['ag-1080']['complete_parent_context']
    try:
        svg_geometry(path, context['human'], raw['model_definitions'], {r[0]: r for r in raw['ordered_cards']})
    except AssertionError:
        controls.append('own_literal_scope_rejects_hidden_conductor')
    else:
        raise AssertionError('hidden conductor accepted by independent literal admission')
    return dict(controls=controls, retained_hidden_geometry_acceptance=meta)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'eleventh-review-partitions.json')
    args = ap.parse_args()
    path = HERE / 'eleventh-partition-candidates.json'
    saved = json.loads(path.read_text())
    peer = module(HERE / 'eleventh-partition-candidates.py', 'reviewed_eleventh')
    assert saved['script_sha256'] == sha(Path(peer.__file__))
    for name, digest in saved['dependencies'].items():
        assert sha(ROOT / name) == digest
    result = dict(raw=raw_review(saved, peer), physical=physical_review(saved), attacks=retained_attacks(peer),
                  source_scope_controls=scope_controls(saved, peer),
                  dependencies={str(p.relative_to(ROOT)): sha(p) for p in (Path(__file__), path, Path(peer.__file__),
                      HERE / 'eleventh-partition-candidates.md', HERE / 'bodies_census.py', RUN / 'eleventh-partition-candidates-before-review.py')},
                  views=[dict(id=ident, path=str(p.relative_to(ROOT)), sha256=sha(p)) for ident in ('ag-1053', 'ag-1079', 'ag-1080')
                         for p in [HERE / 'figures/groups/ninth' / (ident + '-pair.png')]],
                  scope='Independent raw selector and original-schema geometry reference; no general CSS, automatic N0, native execution or target equivalence claim.')
    result = json.loads(json.dumps(result))
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    print(json.dumps(dict(corpus=len(saved['exact_names']), cases=len(result['physical']), pairs=sum(len(r['checked_pairs']) for r in result['physical'].values()),
                         glyphs=sum(r['glyphs'] for r in result['physical'].values()), bindings=sum(r['bindings'] for r in result['physical'].values()))))


if __name__ == '__main__':
    main()
