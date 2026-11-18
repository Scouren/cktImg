#!/usr/bin/env python3
"""Independent actual-artifact replay and bounded cache attacks; no engine edits."""
import argparse
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/ports/seventh-review-groups'
NAMES = ['quad-axis-alone', 'quad-relations', 'pair-stack', 'pair-stack-compatible',
         'pair-fixed', 'pair-fixed-weak-compatible', 'quad-mate-conflict', 'quad-mate-conflict-reversed']
VIEWS = {
    'quad-axis-alone': 'Four gate frames form nested left/right pairs around the center. I1 is centered beneath them, while I2 and both of its vertical terminals are visibly right of that axis.',
    'pair-stack': 'M5 is visibly below M1 in their shared left column; source path from the input pair descends into M5. The caller requested M5 then M1.',
    'pair-fixed': 'Full overview shows horizontal M1 far upper-left and the rest lower-right, joined by long orthogonal routes. This is consistent with the exact remote caller placement; numerical pose is read separately.',
    'pair-fixed-weak-compatible': 'The wider pair keeps opposing input gate frames and matching resistor loads. M5 sits below the midpoint. Image translation alone does not reveal the requested negative world coordinates.',
    'quad-mate-conflict': 'M1 and M3 are the selected inner facing pair; the two physical source groups remain separately visible with I1 and I2 below. The winning caller pair differs from default M1/M2.',
    'quad-mate-conflict-reversed': 'Reversed caller priority returns the nested M1/M2 and M3/M4 appearance. I2 remains to the right of the global center, but this deck contains no axis request for it.',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def raw_deck(path):
    lines = path.read_text().lower().splitlines()
    scope = False
    cards, formals, models, requests = {}, None, [], []
    for line in lines[1:]:
        w = line.split()
        if not w:
            continue
        if w[0] == '.model':
            models.append(w)
        elif w[0] == '.subckt':
            assert not scope and formals is None and w[1] == 'dut'
            scope, formals = True, w[2:]
        elif w[0] == '.ends':
            assert scope and w[1:] == ['dut']
            scope = False
        elif w[0] == '*@':
            assert scope
            requests.append(' '.join(w))
        elif not w[0].startswith(('*', '.')):
            assert scope and w[0][0] in 'mri' and w[0] not in cards
            assert len(w) == (8 if w[0][0] == 'm' else 4)
            cards[w[0]] = w
    assert not scope and formals is not None
    return cards, formals, models, requests


def reflect(point, twice_axis):
    # Literal affine reflection matrix, independent of peer frame helpers.
    return [-point[0] + twice_axis, point[1]]


def reflected_pair(devices, left, right, twice_axis):
    a, b = devices[left], devices[right]
    assert [p['term'] for p in a['pins']] == [p['term'] for p in b['pins']]
    actual = [b['pos']] + [p['xy'] for p in b['pins']]
    expected = [reflect(a['pos'], twice_axis)] + [reflect(p['xy'], twice_axis) for p in a['pins']]
    return dict(left=left, right=right, twice_axis=twice_axis,
                expected=expected, actual=actual, holds=actual == expected)


def actual_run(row):
    deck = ROOT / row['deck']
    assert sha(deck) == row['deck_sha256']
    cards, formals, models, hints = raw_deck(deck)
    assert cards == row['raw_ordered_cards'] and formals == row['dut_formals']
    assert models == row['model_definitions']
    for out in row['outputs'].values():
        assert sha(ROOT / out['path']) == out['sha256']
    native = json.loads((ROOT / row['outputs']['.json']['path']).read_text())
    report = json.loads((ROOT / row['outputs']['.report.json']['path']).read_text())
    assert report['requests'] == row['requests']
    assert [r['text'] for r in report['requests']] == hints
    devices = {d['name']: d for d in native['devices'] if d['name'] in cards}
    assert sum(d['name'] in cards for d in native['devices']) == len(cards)
    assert set(devices) == set(cards) and devices == row['devices']
    for name, card in cards.items():
        d = devices[name]
        width = 3 if name.startswith('m') else 2
        assert [p['net'] for p in d['pins']] == card[1:1 + width]
        assert [p['term'] for p in d['pins']] == (['d', 'g', 's'] if width == 3 else ['a', 'b'])
        if width == 3:
            assert d['bulk'] == card[4]
    return devices, report, cards


def peer_probe(script, folder):
    spec = importlib.util.spec_from_file_location('reviewed_groups', script)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.HERE, mod.ROOT = folder, ROOT
    saved = sys.argv
    sys.argv = [str(script), '--output', str(folder / 'peer-result.json')]
    stream = io.StringIO()
    try:
        with contextlib.redirect_stdout(stream):
            mod.main()
        return dict(accepted=True, stdout=stream.getvalue())
    except AssertionError as e:
        return dict(accepted=False, assertion=str(e))
    finally:
        sys.argv = saved


def cache_attacks(manifest):
    before = json.loads((HERE / 'seventh-review-groups-before.json').read_text())
    snapshot = ROOT / before['snapshot']
    assert sha(snapshot) == before['original_proof_sha256']
    results = []
    for name in ('report_verdict', 'raw_body_binding'):
        folder = RUN / name
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'figures').mkdir(exist_ok=True)
        link = folder / 'figures/groups'
        if not link.exists():
            link.symlink_to(HERE / 'figures/groups', target_is_directory=True)
        changed = copy.deepcopy(manifest)
        row = next(r for r in changed['runs'] if r['name'] == 'quad-axis-alone')
        if name == 'report_verdict':
            data = json.loads((ROOT / row['outputs']['.report.json']['path']).read_text())
            data['requests'][0]['state'], data['requests'][0]['code'] = 'dropped', 'conflict'
            path = folder / 'actual-mutant.report.json'
            path.write_text(json.dumps(data, indent=2) + '\n')
            row['outputs']['.report.json'] = dict(path=rel(path), sha256=sha(path))
        else:
            text = (ROOT / row['deck']).read_text()
            mutant = text.replace('M4 OUTN INP s2 VSS', 'M4 OUTN INP s2 VDD')
            assert mutant != text
            path = folder / 'actual-mutant.cir'
            path.write_text(mutant)
            row['deck'], row['deck_sha256'] = rel(path), sha(path)
        manifest_path = folder / 'sixth-groups-fixtures.json'
        manifest_path.write_text(json.dumps(changed, indent=2) + '\n')
        old, repaired = peer_probe(snapshot, folder), peer_probe(HERE / 'sixth-groups-proof.py', folder)
        assert old['accepted'] and not repaired['accepted'], (name, old, repaired)
        results.append(dict(name=name, actual_mutant=rel(path), sha256=sha(path),
                            old_checker=old, repaired_checker=repaired))
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--output', type=Path, default=HERE / 'seventh-review-groups-proof.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    RUN.mkdir(parents=True, exist_ok=True)
    manifest_path = HERE / 'sixth-groups-fixtures.json'
    manifest = json.loads(manifest_path.read_text())
    binary = ROOT / manifest['binary']
    assert sha(binary) == manifest['binary_sha256']
    rows = {r['name']: r for r in manifest['runs']}
    actual = {name: actual_run(row) for name, row in rows.items()}
    replay = []
    for name in NAMES:
        row = rows[name]
        prefix = RUN / name
        command = [str(binary), '--svg', str(prefix.with_suffix('.svg')), '--report',
                   str(prefix.with_suffix('.report.json')), str(ROOT / row['deck']), str(prefix.with_suffix('.json'))]
        if args.execute:
            p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            assert p.returncode == 0, (name, p.stderr)
        outputs = {}
        for suffix in ('.json', '.svg', '.report.json'):
            path = prefix.with_suffix(suffix)
            assert path.read_bytes() == (ROOT / row['outputs'][suffix]['path']).read_bytes()
            outputs[suffix] = dict(path=rel(path), sha256=sha(path))
        replay.append(dict(name=name, outputs=outputs, command=[rel(Path(s)) if s.startswith(str(ROOT)) else s for s in command]))
    observations = []
    for name in ('quad-axis-alone', 'quad-relations'):
        d, report, cards = actual[name]
        witnesses = [reflected_pair(d, a, b, 480) for a, b in [('m1', 'm2'), ('m3', 'm4'), ('r1', 'r2')]]
        assert all(w['holds'] for w in witnesses)
        assert d['i1']['pos'][0] == 240 and d['i2']['pos'][0] == 340
        assert all(p['xy'][0] == 340 for p in d['i2']['pins'])
        axis = next(q for q in report['requests'] if q['text'] == '*@ axis i2')
        assert (axis['state'], axis['code']) == ('honoured', 'ok')
        assert all(' at ' not in q['text'] for q in report['requests'])
        observations.append(dict(name=name, classification='actual final axis violation without fixed-placement conflict',
                                 common_axis=240, i2_origin=d['i2']['pos'], i2_pins=d['i2']['pins'], request=axis, mirrors=witnesses))
    d, report, _ = actual['pair-stack']
    compatible, other_report, _ = actual['pair-stack-compatible']
    assert d == compatible and d['m5']['pos'] == [80, 170] and d['m1']['pos'] == [80, 90]
    assert all(q['state'] == 'honoured' for q in report['requests'] + other_report['requests'])
    observations.append(dict(name='pair-stack', classification='published written-order invariant conflicts with explicit unordered implementation',
                             m5=d['m5']['pos'], m1=d['m1']['pos'], opposite_order_has_identical_devices=True,
                             reports=[report['requests'], other_report['requests']]))
    d, report, _ = actual['pair-fixed']
    assert (d['m1']['pos'], d['m1']['rot'], d['m1']['mirror']) == ([-800, -800], 0, False)
    w = reflected_pair(d, 'm1', 'm2', d['m1']['pos'][0] + d['m2']['pos'][0])
    assert not w['holds'] and all(q['state'] == 'honoured' for q in report['requests'])
    observations.append(dict(name='pair-fixed', classification='higher-priority exact pose retained; relation verdict lacks final downgrade', mirror=w, requests=report['requests']))
    d, report, _ = actual['pair-fixed-weak-compatible']
    axis2 = d['m1']['pos'][0] + d['m2']['pos'][0]
    assert (d['m1']['pos'], d['m1']['rot'], d['m1']['mirror']) == ([-800, -800], 3, False)
    assert reflected_pair(d, 'm1', 'm2', axis2)['holds'] and reflected_pair(d, 'r1', 'r2', axis2)['holds']
    assert 2 * d['m5']['pos'][0] == axis2
    observations.append(dict(name='pair-fixed-weak-compatible', classification='compatible weak pose and complete mirror frame both hold', axis2=axis2, requests=report['requests']))
    for name, winner in [('quad-mate-conflict', 'm3'), ('quad-mate-conflict-reversed', 'm2')]:
        d, report, _ = actual[name]
        request = next(q for q in report['requests'] if q['state'] == 'honoured')
        assert request['text'] == '*@ symmetric m1 ' + winner
        assert next(q for q in report['requests'] if q['state'] == 'dropped')['code'] == 'conflict'
        w = reflected_pair(d, 'm1', winner, d['m1']['pos'][0] + d[winner]['pos'][0])
        assert w['holds']
        observations.append(dict(name=name, classification='later equal-strength valid relation wins and actual pins mirror', mirror=w, requests=report['requests']))
    literal = {'a': dict(pos=[-2, 4], pins=[dict(term='g', xy=[-5, 4])]),
               'b': dict(pos=[8, 4], pins=[dict(term='g', xy=[11, 4])])}
    assert reflected_pair(literal, 'a', 'b', 6)['holds']
    literal['b']['pins'][0]['xy'][0] += 1
    assert not reflected_pair(literal, 'a', 'b', 6)['holds']
    views = []
    for name, note in VIEWS.items():
        path = HERE / 'figures/groups' / ('sixth-' + name + '.png')
        views.append(dict(name=name, actual_view=True, path=rel(path), sha256=sha(path), observation=note,
                          actual_svg=rows[name]['outputs']['.svg']))
    aliases = []
    for alias, viewed in [('quad-relations', 'quad-axis-alone'), ('pair-stack-compatible', 'pair-stack')]:
        a, b = [HERE / 'figures/groups' / ('sixth-' + n + '.png') for n in (alias, viewed)]
        assert a.read_bytes() == b.read_bytes()
        aliases.append(dict(name=alias, byte_identical_viewed_alias=viewed, sha256=sha(a)))
    result = dict(scope='Independent actual-artifact review; no production fix or internal trace.',
                  script_sha256=sha(Path(__file__)), manifest_sha256=sha(manifest_path),
                  reviewed_proof_sha256=sha(HERE / 'sixth-groups-proof.py'), binary_sha256=sha(binary),
                  all_23_actual_artifact_names=sorted(rows), raw_devices_checked=sum(len(v[2]) for v in actual.values()),
                  independent_replays=replay, observations=observations, cache_attack_repairs=cache_attacks(manifest),
                  literal_reflection_control=['translated reflection holds', 'changed actual gate rejects with origins unchanged'],
                  fresh_views=views, identical_view_aliases=aliases,
                  limits=['Stack behavior requires an explicit contract decision.', 'Exact caller pose must remain authoritative.',
                          'Source corpus equivalence and plugin round trip are outside these synthetic fixtures.',
                          'Code locations are candidate owners; no internal phase trace was executed.'])
    if args.check:
        assert json.loads(args.check.read_text()) == result
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(actual_runs=len(rows), replayed=len(replay), raw_devices=result['raw_devices_checked'],
                          repaired_cache_attacks=len(result['cache_attack_repairs']), fresh_views=len(views))))


if __name__ == '__main__':
    main()
