#!/usr/bin/env python3
"""Literal final-frame oracles; known native RED results are named, not hidden."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
NAMES = '''pair-axis-conflict pair-base pair-fixed pair-fixed-weak pair-fixed-weak-compatible
pair-group pair-nogroup pair-off pair-rejected pair-relations pair-relations-reversed
pair-stack pair-stack-compatible pair-symmetric-conflict quad-axis-alone quad-base
quad-fixed quad-groups quad-groups-reversed quad-mate-conflict quad-mate-conflict-reversed
quad-overlap quad-relations'''.split()
VIEWS = {
    'pair-relations': 'Both input MOS gates face outward; both resistor loads share the pair axis and M5 sits centered underneath.',
    'pair-stack': 'M5 is directly below M1 despite requested stack order M5 then M1. Numeric y coordinates confirm the reverse order.',
    'pair-stack-compatible': 'The same drawing puts M1 above M5 as requested by this opposite stack order.',
    'pair-fixed': 'Overview: caller-fixed M1 is remote upper-left, horizontal, while M2 and tail remain lower-right. Full pin geometry comes from JSON.',
    'pair-fixed-weak-compatible': 'Translated and wider pair keeps outward gates, centered M5 and mirrored loads; compatible weak pose does not break the common frame.',
    'quad-base': 'Two adjacent source pairs sit side by side with two tail sources beneath; this unhinted alternative is not a caller global-axis oracle.',
    'quad-relations': 'Outer and inner MOS pairs share the same center; I1 is centered, but I2 is displaced right although both axis requests are honoured.',
    'quad-axis-alone': 'Same nested drawing and right-displaced I2 with only the axis I2 request. No fixed-coordinate request explains the discrepancy.',
    'quad-overlap': 'Later pair request M2/M3 wins in the report; visible source pairs remain separated. Pair membership alone is not certified by proximity.',
    'quad-mate-conflict': 'M1 and M3 face inward across the central axis after the later M1/M3 request wins; the earlier M1/M2 request is dropped.',
    'quad-mate-conflict-reversed': 'Reversing equal-strength request order selects the M1/M2 mirror and nested arrangement. This confirms existing hint priority changes the selected relation.',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mirror(devices, a, b, axis2=None):
    left, right = devices[a], devices[b]
    axis2 = left['pos'][0] + right['pos'][0] if axis2 is None else axis2
    if left['pos'][0] + right['pos'][0] != axis2 or left['pos'][1] != right['pos'][1]:
        return False
    if [p['term'] for p in left['pins']] != [p['term'] for p in right['pins']]:
        return False
    return all(p['xy'][0] + q['xy'][0] == axis2 and p['xy'][1] == q['xy'][1]
               for p, q in zip(left['pins'], right['pins']))


def pair_frame(devices):
    axis2 = devices['m1']['pos'][0] + devices['m2']['pos'][0]
    return (mirror(devices, 'm1', 'm2', axis2) and mirror(devices, 'r1', 'r2', axis2)
            and 2 * devices['m5']['pos'][0] == axis2)


def quad_pairs(devices):
    axis2 = devices['m1']['pos'][0] + devices['m2']['pos'][0]
    return all(mirror(devices, a, b, axis2) for a, b in [('m1', 'm2'), ('m3', 'm4'), ('r1', 'r2')])


def state(run, text, want, code):
    row = next(r for r in run['requests'] if r['text'] == text)
    assert (row['state'], row['code']) == (want, code), (run['name'], text, row)
    return row


def automorphism(run, devices, nets):
    """Complete signed ordered-card witness, including B and model parameters."""
    cards = run['raw_ordered_cards']
    assert set(devices) == set(cards) == set(devices.values())
    seen_nets = {w[i] for w in cards.values() for i in range(1, 5 if w[0][0] == 'm' else 3)}
    assert set(nets) == seen_nets == set(nets.values())
    witness = []
    for old, new in sorted(devices.items()):
        row = list(cards[old])
        row[0] = new
        for i in range(1, 5 if old[0] == 'm' else 3):
            row[i] = nets[row[i]]
        assert row == cards[new], (old, row, cards[new])
        witness.append(dict(before=cards[old], after=row))
    return dict(device_map=devices, net_map=nets, ordered_rows=witness,
                model_definitions=run['model_definitions'], outer_formals=run['dut_formals'],
                scope='Layout symmetry permutes matching input/output nets; actual ordered DUT formals and output bindings are never rewritten.')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE / 'sixth-groups-proof.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    manifest_path = HERE / 'sixth-groups-fixtures.json'
    manifest = json.loads(manifest_path.read_text())
    runs = {r['name']: r for r in manifest['runs']}
    assert set(runs) == set(NAMES) and len(runs) == len(manifest['runs'])
    for path, digest in manifest['dependencies'].items():
        assert sha(ROOT / path) == digest, path
    assert sha(ROOT / manifest['binary']) == manifest['binary_sha256']
    for run in runs.values():
        assert sha(ROOT / run['deck']) == run['deck_sha256']
        source_rows = [line.lower().split() for line in (ROOT / run['deck']).read_text().splitlines()]
        models = [row for row in source_rows if row and row[0] == '.model']
        subcircuits = [row for row in source_rows if row and row[0] == '.subckt']
        cards = [row for row in source_rows if row and row[0][0] in 'mri']
        assert len(subcircuits) == 1 and subcircuits[0][1] == 'dut'
        assert models == run['model_definitions']
        assert subcircuits[0][2:] == run['dut_formals']
        assert len(cards) == len({row[0] for row in cards}), 'duplicate raw device'
        assert {row[0]: row for row in cards} == run['raw_ordered_cards']
        for out in run['outputs'].values():
            assert sha(ROOT / out['path']) == out['sha256']
        report = json.loads((ROOT / run['outputs']['.report.json']['path']).read_text())
        assert report['requests'] == run['requests'], 'cached request differs from actual report'
        actual = {d['name']: d for d in json.loads((ROOT / run['outputs']['.json']['path']).read_text())['devices']}
        for name, dev in run['devices'].items():
            assert actual[name] == dev
            w = run['raw_ordered_cards'][name]
            count = 3 if name.startswith('m') else 2
            assert [p['net'] for p in dev['pins']] == w[1:count + 1]
            assert [p['term'] for p in dev['pins']] == (['d', 'g', 's'] if count == 3 else ['a', 'b'])
            if count == 3:
                assert dev['bulk'] == w[4]
    pair_witness = automorphism(runs['pair-relations'], {'m1': 'm2', 'm2': 'm1', 'm5': 'm5', 'r1': 'r2', 'r2': 'r1'},
        {'vdd': 'vdd', 'vss': 'vss', 'inp': 'inn', 'inn': 'inp', 'outp': 'outn', 'outn': 'outp', 'vb': 'vb', 'tail': 'tail'})
    quad_witness = automorphism(runs['quad-relations'],
        {'m1': 'm2', 'm2': 'm1', 'm3': 'm4', 'm4': 'm3', 'r1': 'r2', 'r2': 'r1', 'i1': 'i1', 'i2': 'i2'},
        {'vdd': 'vdd', 'vss': 'vss', 'inp': 'inn', 'inn': 'inp', 'outp': 'outn', 'outn': 'outp', 's1': 's1', 's2': 's2'})
    for name in ['pair-base', 'pair-relations', 'pair-relations-reversed', 'pair-group', 'pair-rejected',
                 'pair-axis-conflict', 'pair-symmetric-conflict', 'pair-fixed-weak', 'pair-fixed-weak-compatible']:
        assert pair_frame(runs[name]['devices']), name
    for a, b in [('pair-relations', 'pair-relations-reversed'), ('quad-groups', 'quad-groups-reversed'), ('pair-stack', 'pair-stack-compatible')]:
        assert runs[a]['devices'] == runs[b]['devices']
    state(runs['pair-rejected'], '*@ symmetric m1 r1', 'dropped', 'asymmetric')
    state(runs['pair-rejected'], '*@ axis absent', 'rejected', 'unknown_name')
    state(runs['pair-rejected'], '*@ group pair m1', 'rejected', 'bad_args')
    state(runs['pair-nogroup'], '*@ group pair m1 m2', 'dropped', 'taken')
    state(runs['pair-nogroup'], '*@ nogroup m1', 'honoured', 'ok')
    for name, winner, loser in [('quad-mate-conflict', 'm1 m3', 'm1 m2'), ('quad-mate-conflict-reversed', 'm1 m2', 'm1 m3')]:
        state(runs[name], '*@ symmetric ' + winner, 'honoured', 'ok')
        state(runs[name], '*@ symmetric ' + loser, 'dropped', 'conflict')
        assert mirror(runs[name]['devices'], *winner.split())
    state(runs['quad-overlap'], '*@ group pair m1 m2', 'dropped', 'taken')
    state(runs['quad-overlap'], '*@ group pair m2 m3', 'honoured', 'ok')
    for text in ('*@ symmetric m1 m2', '*@ symmetric r1 r2', '*@ axis m5'):
        state(runs['pair-off'], text, 'dropped', 'conflict')
    state(runs['pair-off'], '*@ symmetry off', 'honoured', 'ok')
    state(runs['pair-fixed-weak'], '*@ weak at m1 -20 -20 r0', 'dropped', 'guarantee')
    state(runs['pair-fixed-weak-compatible'], '*@ weak at m1 -20 -20 r270', 'honoured', 'ok')
    weak = runs['pair-fixed-weak-compatible']['devices']['m1']
    assert (weak['pos'], weak['rot'], weak['mirror']) == ([-800, -800], 3, False)
    known_red = []
    for name in ['quad-relations', 'quad-groups', 'quad-groups-reversed', 'quad-axis-alone']:
        r = runs[name]
        d = r['devices']
        assert quad_pairs(d)
        assert d['i1']['pos'][0] == 240 and d['i2']['pos'][0] == 340
        assert 2 * d['i2']['pos'][0] != d['m1']['pos'][0] + d['m2']['pos'][0]
        verdict = state(r, '*@ axis i2', 'honoured', 'ok')
        known_red.append(dict(name=name, failed_relation='I2 on common requested mirror axis',
                              axis2=480, actual_i2_x=340, request=verdict))
    d = runs['pair-stack']['devices']
    verdict = state(runs['pair-stack'], '*@ group stack m5 m1', 'honoured', 'ok')
    assert d['m5']['pos'][0] == d['m1']['pos'][0] and d['m5']['pos'][1] == 170 > d['m1']['pos'][1] == 90
    state(runs['pair-stack-compatible'], '*@ group stack m1 m5', 'honoured', 'ok')
    known_red.append(dict(name='pair-stack', failed_relation='M5 above M1 as the written stack order',
                          actual_y={'m5': 170, 'm1': 90}, request=verdict,
                          classification='Published structure.5 promises written top-to-bottom order; skeleton.choose explicitly accepts either order. Reconcile that contract before changing behavior.'))
    strong = []
    for name, moved, mate in [('pair-fixed', 'm1', 'm2'), ('quad-fixed', 'm3', 'm4')]:
        r = runs[name]
        v = state(r, '*@ at ' + moved + ' -20 -20 r0', 'honoured', 'ok')
        d = r['devices'][moved]
        assert (d['pos'], d['rot'], d['mirror']) == ([-800, -800], 0, False)
        assert not mirror(r['devices'], moved, mate)
        relation = state(r, '*@ symmetric ' + moved + ' ' + mate, 'honoured', 'ok')
        strong.append(dict(name=name, exact_pose_retained=True, symmetric_geometry=False,
                           at_verdict=v, relation_verdict=relation,
                           classification='Preserve stronger exact placement; the relation report is not a final geometry certificate.'))
    # Mutants only: keep device origins but break one actual own terminal.
    mutant = copy.deepcopy(runs['pair-relations']['devices'])
    mutant['m2']['pins'][1]['xy'][0] += 1
    assert mutant['m1']['pos'][0] + mutant['m2']['pos'][0] == 2 * mutant['m5']['pos'][0]
    assert not pair_frame(mutant)
    # Two separately symmetric local groups need not share the caller's global axis.
    local = copy.deepcopy(runs['quad-relations']['devices'])
    for name in ('m3', 'm4'):
        local[name]['pos'][0] += 40
        for pin in local[name]['pins']:
            pin['xy'][0] += 40
    assert mirror(local, 'm1', 'm2') and mirror(local, 'm3', 'm4') and not quad_pairs(local)
    views = []
    for name, observation in sorted(VIEWS.items()):
        path = HERE / 'figures/groups' / ('sixth-' + name + '.png')
        r = runs[name]
        views.append(dict(name=name, actual_view=True, observation=observation,
                          path=str(path.relative_to(ROOT)), sha256=sha(path),
                          svg=r['outputs']['.svg'], deck=r['deck'], deck_sha256=r['deck_sha256'],
                          render_command=['magick', '-background', 'white', '-density', '144', r['outputs']['.svg']['path'], str(path.relative_to(ROOT))]))
    result = dict(scope='Current frozen final-frame observations, exact named native failures and future-only local-axis mutants.',
                  manifest_sha256=sha(manifest_path), script_sha256=sha(Path(__file__)), exact_run_names=sorted(runs),
                  complete_automorphisms=[pair_witness, quad_witness], known_native_red=known_red,
                  stronger_placement_controls=strong, positive_common_pair_frames=9,
                  mutation_rejections=['one_actual_gate_endpoint_moved_while_origins_agree', 'two_local_mirror_pairs_on_different_global_axes'],
                  fresh_actual_views=views,
                  limits=['No internal stage dump or compiler was run.', 'No generic group-membership geometry oracle is inferred from proximity.',
                          'Local-axis replacement, report repair and native fixes remain unimplemented.', 'This is not a source corpus equivalence or host connectivity proof.'])
    if args.check:
        assert json.loads(args.check.read_text()) == result
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(runs=len(runs), known_native_red_names=[r['name'] for r in known_red], stronger_place_controls=len(strong), views=len(views))))


if __name__ == '__main__':
    main()
