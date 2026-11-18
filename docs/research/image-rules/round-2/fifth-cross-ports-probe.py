#!/usr/bin/env python3
"""Independent fourth-port review: exact saved outputs, attacks, scoped ownership.

No native execution, plugin execution, compiler, or production edits. The old
small checker is retained literally to show the rejected proof strategy; it
is not represented as a byte-preserved snapshot of the entire old script.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
spec = importlib.util.spec_from_file_location('reviewed_fourth_proof', HERE / 'fourth-ports-proof.py')
peer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(peer)

NAMES = '''reg-base reg-fixed-b reg-fixed-a reg-custom-b reg-single-a reg-single-a-fixed
shared-base shared-reversed shared-projected shared-custom-reg shared-custom-sample
shared-family-custom shared-family-custom-sides shared-sides shared-fixed-reg
shared-custom-reg-fixed shared-custom-reg-mirrored shared-both-fixed bias-base
bias-fixed-b bias-single-a bias-single-a-fixed bias-single-a-anchor-fixed
bias-single-a-unrelated-fixed reg-fixed-b-reversed bias-fixed-b-reversed
bias-base-opaque bias-fixed-b-opaque bias-single-a-opaque'''.split()
VIEWS = {
    'shared-base': 'Upper sampler and lower regulator both use negative-above triangles; the future regulator preference is not implemented.',
    'shared-custom-reg': 'Only lower regulator becomes the caller rectangle with positive-above; sampler retains its triangle and signed order.',
    'shared-custom-sample': 'Only upper sampler becomes the caller rectangle with positive-above, overriding the proposed automatic sampler preference; lower regulator stays default.',
    'shared-projected': 'Visually matches shared-base including both triangle input signs and wire placement; this is a native b17 proxy, not a plugin import.',
    'shared-sides': 'Both stages use directed boxes with negative input right and positive input left; some labels overlap but explicit terminal geometry remains visible.',
    'shared-family-custom-sides': 'Both instances retain caller rectangles with positive-above left inputs despite opposing definition-side directives.',
    'shared-custom-reg-mirrored': 'Overview of a large canvas: custom regulator is remote upper-left, mirrored and quarter-turned; output up and inputs down. Numeric pins, not overview pixels, certify exact pose.',
    'reg-base': 'Two separate regulators share rails; each owns its own pass MOS and divider. Both negative feedback inputs lie above positive reference inputs.',
    'reg-fixed-b': 'Overview: second amplifier is remote upper-left and down-facing; the other amplifier and both divider paths remain lower-right. Fixing one anchor does not erase either raw tuple.',
    'bias-base': 'Amplifier left, two ordinary bias boxes right; neither peer takes the unique-peer under-amplifier pose.',
    'bias-fixed-b': 'Overview: one bias box is remote upper-left and rotated; amplifier and remaining ordinary bias box are lower-right. Exact coordinates require JSON.',
    'bias-single-a': 'Unique bias peer sits below amplifier, turned with NB up toward the actual VB1 lead; remaining VB2 is exported.',
    'bias-single-a-opaque': 'Same complete peer terminals but opaque family gives an ordinary box to the right, confirming the recognized one-peer arrangement has a positive control.',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def frame(dev):
    """Independent inverse: explicit quarter-turn matrices, then unmirror."""
    a, b, c, d = [(1, 0, 0, 1), (0, 1, -1, 0), (-1, 0, 0, -1), (0, -1, 1, 0)][dev['rot']]
    result = {}
    for p in dev['pins']:
        x, y = p['xy'][0] - dev['pos'][0], p['xy'][1] - dev['pos'][1]
        u, v = a * x + b * y, c * x + d * y
        result[p['term']] = [-u if dev['mirror'] else u, v]
    return result


def old_policy(blocks):
    """Pre-repair checker body, reproduced to isolate the observed failure."""
    peer.assert_bindings(blocks)
    for name, positive_above in [('xreg', True), ('xsample', False)]:
        pins = blocks[name]['canonical_pins']
        assert (pins['inp'][1] < pins['inn'][1]) == positive_above
        assert pins['vdd'][1] < 0 < pins['vss'][1]
        assert pins['out'][0] > 0 and pins['inp'][0] == pins['inn'][0] < 0


def rejected(check, value):
    try:
        check(value)
    except AssertionError:
        return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE / 'fifth-cross-ports-probe.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    manifest_file = HERE / 'fourth-ports-fixtures.json'
    manifest = json.loads(manifest_file.read_text())
    proof = json.loads((HERE / 'fourth-ports-proof.json').read_text())
    runs = {r['name']: r for r in manifest['runs']}
    assert len(runs) == len(manifest['runs']) and set(runs) == set(NAMES)
    assert sha(ROOT / manifest['binary']) == manifest['binary_sha256'] == peer.f.EXPECTED_BINARY
    bindings = []
    for name in sorted(runs):
        r = runs[name]
        assert sha(ROOT / r['deck']) == r['deck_sha256']
        if r['symbols']:
            assert sha(ROOT / r['symbols']) == r['symbols_sha256']
        for out in r['outputs'].values():
            assert sha(ROOT / out['path']) == out['sha256']
        raw = json.loads((ROOT / r['outputs']['.json']['path']).read_text())
        actual = {d['name']: d for d in raw['devices']}
        for call in r['complete_calls']:
            dev = actual[call['card']]
            block = r['blocks'][call['card']]
            assert dev == block['final_device']
            assert [p['term'] for p in dev['pins']] == call['ports']
            assert [p['net'] for p in dev['pins']] == call['bindings']
            assert frame(dev) == block['canonical_pins']
            bindings.append(dict(run=name, instance=call['card'], ordered_formals=call['ports'],
                                 ordered_nets=call['bindings'], actual_pins=dev['pins'], frame=frame(dev)))
    assert proof['manifest_sha256'] == sha(manifest_file)
    peer.assert_two_policies(runs['shared-custom-reg']['blocks'])
    changed = copy.deepcopy(runs['shared-custom-reg']['blocks'])
    pins = changed['xreg']['final_device']['pins']
    pins[2]['xy'], pins[3]['xy'] = pins[3]['xy'], pins[2]['xy']
    assert not rejected(old_policy, changed)
    assert rejected(peer.assert_two_policies, changed)
    assert frame(changed['xreg']['final_device']) != changed['xreg']['canonical_pins']
    # A literal semantic policy mutation updates actual geometry AND the cache.
    leak = copy.deepcopy(runs['shared-custom-reg']['blocks'])
    b = leak['xsample']
    b['canonical_pins'] = copy.deepcopy(leak['xreg']['canonical_pins'])
    assert b['final_device']['rot'] == 0 and not b['final_device']['mirror']
    for pin in b['final_device']['pins']:
        pin['xy'] = [x + y for x, y in zip(b['final_device']['pos'], b['canonical_pins'][pin['term']])]
    assert frame(b['final_device']) == b['canonical_pins']
    assert rejected(peer.assert_two_policies, leak)
    # No global fixed-device predicate: only this raw tuple's two members matter.
    expected_bias = {
        'bias-fixed-b': (['xba', 'xbb'], ['xbb'], [], ['xba']),
        'bias-single-a': (['xba'], [], ['xba'], ['xba']),
        'bias-single-a-unrelated-fixed': (['xba'], ['rx'], ['xba'], ['xba']),
        'bias-single-a-anchor-fixed': (['xba'], ['xamp'], [], []),
    }
    observed_bias = []
    saved_bias = {r['name']: r for r in proof['same_anchor_bias']}
    for name, (raw_names, fixed_names, want, wrong_order) in expected_bias.items():
        pairs = peer.bias_pairs((ROOT / runs[name]['deck']).read_text())
        assert [p['peer'] for p in pairs] == raw_names
        fixed = set(fixed_names)
        raw_then_admit = [p['peer'] for p in pairs if not {p['anchor'], p['peer']} & fixed] if len(pairs) == 1 else []
        eligible = [p['peer'] for p in pairs if not {p['anchor'], p['peer']} & fixed]
        filter_first = eligible if len(eligible) == 1 else []
        old_global = [p['peer'] for p in pairs] if len(pairs) == 1 and not fixed else []
        assert (raw_then_admit, filter_first) == (want, wrong_order)
        assert saved_bias[name]['intended_same_anchor_admission'] == want
        assert saved_bias[name]['fixed_peers'] == sorted(fixed)
        observed_bias.append(dict(name=name, complete_pairs=pairs, fixed=sorted(fixed),
                                  corrected_admission=raw_then_admit, filter_first_mutant=filter_first,
                                  old_global_fixed_mutant=old_global))
    single = runs['bias-single-a']['blocks']['xba']['final_device']
    unrelated = runs['bias-single-a-unrelated-fixed']['blocks']['xba']['final_device']
    assert peer.geometry({'final_device': single}) == peer.geometry({'final_device': unrelated})
    assert (single['pos'], single['rot']) == ([100, 200], 1)
    held = runs['bias-single-a-anchor-fixed']['blocks']
    assert (held['xba']['final_device']['pos'], held['xba']['final_device']['rot']) == ([290, 60], 0)
    a, b = manifest['local_candidate_census']['reg-base']
    assert a['amplifier'] == 'xa' and b['amplifier'] == 'xb'
    assert set(a['members']).isdisjoint(b['members'])
    assert manifest['local_candidate_census']['shared-projected'] == []
    for name in ('xreg', 'xsample'):
        assert frame(runs['shared-base']['blocks'][name]['final_device']) == frame(runs['shared-projected']['blocks'][name]['final_device'])
    view_data = json.loads((HERE / 'fourth-ports-views.json').read_text())
    view_rows = {r['name']: r for r in view_data['rendered']}
    views = []
    for name, observation in sorted(VIEWS.items()):
        row = view_rows[name]
        assert sha(ROOT / row['svg']) == row['svg_sha256']
        assert sha(ROOT / row['png']) == row['png_sha256']
        views.append(dict(name=name, source_deck=runs[name]['deck'], deck_sha256=runs[name]['deck_sha256'],
                          svg=row['svg'], svg_sha256=row['svg_sha256'], png=row['png'], png_sha256=row['png_sha256'],
                          actual_view=True, observation=observation))
    paths = ['fourth-ports-fixtures.py', 'fourth-ports-fixtures.json', 'fourth-ports-proof.py',
             'fourth-ports-proof.json', 'fourth-ports-views.json']
    dependencies = {rel(HERE / p): sha(HERE / p) for p in paths}
    for p in ['tools/schemify/recognize.zig', 'tools/schemify/layout.zig', 'tools/schemify/names.zig',
              'tools/schemify/emit.zig', 'src/library.zig', 'src/opamp.zig', 'src/bias_neighbors.zig']:
        dependencies[p] = sha(ROOT / p)
    result = dict(scope='Independent saved-artifact review; no plugin execution or automatic signed-policy implementation.',
                  script_sha256=sha(Path(__file__)), dependencies=dependencies, binary_sha256=manifest['binary_sha256'],
                  exact_run_names=sorted(runs), ordered_call_bindings=bindings,
                  checker_attack=dict(old_literal_checker_accepts=True, repaired_checker_rejects=True,
                                      geometry=changed['xreg'], synchronized_class_leak_rejected=True,
                                      historical_scope='Both gaps were executed against the pre-repair helpers during review; their entire old file was not snapshotted. The isolated old logic above is reproducible.'),
                  bias_scope=observed_bias, disjoint_regulators=[a, b], fresh_actual_views=views,
                  plugin_scope=dict(origin_values=['core', 'sub', 'leaf', 'lib'], symbol_shape_field='shape',
                                    generated_named_glyph='Original formals survive, original family becomes b<s>.',
                                    generated_box_and_external_lib='Definition formals become pN; registered terminal names still original.',
                                    native_countercontrol='opamp.amplifier is formal-role based, not def-name based.',
                                    no_parity_claim='b17 CLI projection is not a plugin or host run.'))
    if args.check:
        assert json.loads(args.check.read_text()) == result
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(runs=len(runs), ordered_calls=len(bindings), views=len(views), attacks_repaired=2)))


if __name__ == '__main__':
    main()
