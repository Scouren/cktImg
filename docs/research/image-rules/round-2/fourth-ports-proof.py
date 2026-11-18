#!/usr/bin/env python3
"""Independent literal/current and future-only relations for fourth fixtures."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('fourth_fixtures', HERE / 'fourth-ports-fixtures.py')
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
DEFAULT = {'vdd': [0, -60], 'vss': [0, 60], 'inn': [-60, -20], 'inp': [-60, 20], 'out': [60, 0]}
CUSTOM = {'vdd': [0, -60], 'vss': [0, 60], 'inn': [-90, 30], 'inp': [-90, -30], 'out': [90, 0]}
SIDES = {'vdd': [0, -50], 'vss': [0, 50], 'inn': [40, -20], 'inp': [-40, 0], 'out': [40, 20]}
REGULATORS = [('regulator', 'xa', ['ma', 'ral', 'rau', 'xa']), ('regulator', 'xb', ['mb', 'rbl', 'rbu', 'xb'])]
SHARED = [('regulator', 'xreg', ['mreg', 'rlow', 'rup', 'xreg']), ('sample', 'xsample', ['cf', 'cs', 'ms1', 'ms2', 'xsample'])]


def signature(rows):
    return [(r['kind'], r['amplifier'], r['members']) for r in rows]


def bias_pairs(text):
    """Bounded fixture witness from declared pins; no visibility or hints."""
    cards, defs, _ = f.parse(text)
    calls = f.p.old.calls(cards, defs)
    inc = f.p.incidences(cards, defs)
    outer = set(defs['dut'])
    amp = next(c for c in calls if c['card'] == 'xamp')
    assert amp['ports'] == ['vdd', 'vss', 'inn', 'inp', 'out', 'vb1', 'vb2']
    bound = dict(zip(amp['ports'], amp['bindings']))
    result = []
    for formal in ('vb1', 'vb2'):
        net = bound[formal]
        if net in outer or len(inc[net]) != 2:
            continue
        for peer in calls:
            if peer['family'] != 'bias' or peer['ports'] != ['vdd', 'vss', 'nb']:
                continue
            if peer['bindings'] != [bound['vdd'], bound['vss'], net]:
                continue
            result.append(dict(anchor='xamp', peer=peer['card'], amp_index=amp['ports'].index(formal), peer_index=2,
                               net=net, incidence=inc[net], complete_amplifier=amp, complete_peer=peer))
    return sorted(result, key=lambda x: x['peer'])


def geometry(block):
    d = block['final_device']
    return {k: d[k] for k in ('pos', 'rot', 'mirror', 'pins')}


def assert_bindings(blocks):
    wanted = {'xreg': ['vdd', 'vss', 'fb', 'vref', 'gate'], 'xsample': ['vdd', 'vss', 'sn', 'vss', 'sout']}
    for name, nets in wanted.items():
        pins = blocks[name]['final_device']['pins']
        assert [p['term'] for p in pins] == ['vdd', 'vss', 'inn', 'inp', 'out']
        assert [p['net'] for p in pins] == nets


def assert_two_policies(blocks):
    assert_bindings(blocks)
    for name, positive_above in [('xreg', True), ('xsample', False)]:
        pins = blocks[name]['canonical_pins']
        assert pins == f.local_pins(blocks[name]['final_device']), 'cached frame contradicts final terminal coordinates'
        assert (pins['inp'][1] < pins['inn'][1]) == positive_above
        assert pins['vdd'][1] < 0 < pins['vss'][1]
        assert pins['out'][0] > 0 and pins['inp'][0] == pins['inn'][0] < 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=HERE / 'fourth-ports-proof.json')
    parser.add_argument('--check', type=Path)
    args = parser.parse_args()
    manifest_path = HERE / 'fourth-ports-fixtures.json'
    manifest = json.loads(manifest_path.read_text())
    assert f.sha(f.BINARY) == manifest['binary_sha256'] == f.EXPECTED_BINARY
    for path, digest in manifest['dependencies'].items():
        assert f.sha(f.ROOT / path) == digest, path
    runs = {r['name']: r for r in manifest['runs']}
    for r in runs.values():
        assert f.sha(f.ROOT / r['deck']) == r['deck_sha256']
        for out in r['outputs'].values():
            assert f.sha(f.ROOT / out['path']) == out['sha256']
        for call in r['complete_calls']:
            pins = r['blocks'][call['card']]['final_device']['pins']
            assert [p['term'] for p in pins] == call['ports']
            assert [p['net'] for p in pins] == call['bindings']
    raw = manifest['local_candidate_census']
    for name, rows in raw.items():
        expected = [] if name == 'shared-projected' else SHARED if name.startswith('shared-') else REGULATORS[:1] if 'single' in name else REGULATORS
        assert signature(rows) == expected, name
    # Independent raw closure negatives: a subset must not hide another consumer.
    reg = (HERE / 'fourth-ports-two-regulators.cir').read_text()
    shared = (HERE / 'fourth-ports-shared-definition.cir').read_text()
    closure = []
    for name, text, expected in [
        ('reg_a_feedback_extra_consumer', reg.replace('.ends dut', 'CX fba VSS 1p\n.ends dut'), REGULATORS[1:]),
        ('reg_b_gate_extra_consumer', reg.replace('.ends dut', 'CX gateb VSS 1p\n.ends dut'), REGULATORS[:1]),
        ('sample_input_extra_consumer', shared.replace('.ends dut', 'RX SIN VSS 1k\n.ends dut'), SHARED[:1]),
        ('sample_body_on_reg_feedback', shared.replace('MS1 SIN PHI1 sj VSS', 'MS1 SIN PHI1 sj fb'), []),
    ]:
        observed = signature(f.local_candidates(text))
        assert observed == expected, (name, observed)
        path = HERE / ('fourth-ports-negative-' + name + '.cir')
        path.write_text(text)
        closure.append(dict(name=name, deck=f.relative(path), sha256=f.sha(path), expected=expected, observed=observed))
    # Current exact same-anchor ambiguity: count both private peers first.
    bias = []
    for name, r in runs.items():
        if not name.startswith('bias-'):
            continue
        pairs = bias_pairs((f.ROOT / r['deck']).read_text())
        expected = [] if name.endswith('opaque') else ['xba'] if 'single' in name else ['xba', 'xbb']
        assert [p['peer'] for p in pairs] == expected
        fixed = {q['text'].split()[2] for q in r['report']['requests']
                 if q['state'] == 'honoured' and q['text'].startswith('*@ at ')}
        eligible = [p for p in pairs if not {p['anchor'], p['peer']} & fixed]
        raw_then_filter = eligible if len(pairs) == 1 else []
        filter_then_unique = eligible if len(eligible) == 1 else []
        bias.append(dict(name=name, raw_pairs=pairs, fixed_peers=sorted(fixed),
                         intended_same_anchor_admission=[p['peer'] for p in raw_then_filter],
                         filter_first_mutant_admission=[p['peer'] for p in filter_then_unique]))
    by_bias = {r['name']: r for r in bias}
    assert by_bias['bias-fixed-b']['intended_same_anchor_admission'] == []
    assert by_bias['bias-fixed-b']['filter_first_mutant_admission'] == ['xba']
    assert by_bias['bias-single-a-unrelated-fixed']['intended_same_anchor_admission'] == ['xba']
    assert by_bias['bias-single-a-anchor-fixed']['intended_same_anchor_admission'] == []
    for name in ('bias-base', 'bias-fixed-b'):
        assert {k: geometry(v) for k, v in runs[name]['blocks'].items()} == {k: geometry(v) for k, v in runs[name + '-opaque']['blocks'].items()}
    one = runs['bias-single-a']['blocks']['xba']['final_device']
    opaque = runs['bias-single-a-opaque']['blocks']['xba']['final_device']
    assert (one['pos'], one['rot']) == ([100, 200], 1)
    assert (opaque['pos'], opaque['rot']) == ([290, 60], 0)
    assert geometry(runs['bias-single-a-unrelated-fixed']['blocks']['xba']) == geometry(runs['bias-single-a']['blocks']['xba'])
    held = runs['bias-single-a-anchor-fixed']['blocks']
    assert (held['xba']['final_device']['pos'], held['xba']['final_device']['rot']) == ([290, 60], 0)
    assert held['xamp']['final_device']['pos'] == [-1200, -1200]
    unrelated = json.loads((f.ROOT / runs['bias-single-a-unrelated-fixed']['outputs']['.json']['path']).read_text())
    rx = next(d for d in unrelated['devices'] if d['name'] == 'rx')
    assert (rx['pos'], rx['rot'], rx['mirror']) == ([-1200, -1200], 1, False)
    for a, b in [('reg-fixed-b', 'reg-fixed-b-reversed'), ('bias-fixed-b', 'bias-fixed-b-reversed'), ('shared-base', 'shared-reversed')]:
        assert runs[a]['blocks'] == runs[b]['blocks']
    # Caller geometry is asserted on final pins, independently of report status.
    caller = []
    for name, r in runs.items():
        if not name.startswith('shared-'):
            continue
        blocks = r['blocks']
        assert_bindings(blocks)
        for dev, b in blocks.items():
            is_custom = ('family-custom' in name or 'custom-reg' in name and dev == 'xreg'
                         or 'custom-sample' in name and dev == 'xsample')
            expected = CUSTOM if is_custom else SIDES if name == 'shared-sides' else DEFAULT
            assert b['canonical_pins'] == expected, (name, dev)
            cls = 'b17' if name == 'shared-projected' else 'opamp' if 'family-custom' in name else 'caller_signed' if is_custom else 'block:opamp'
            assert b['class_name'] == cls, (name, dev)
        for q in r['report']['requests']:
            if q['text'].startswith(('*@ at ', '*@ class ')):
                assert q['state'] == 'honoured' and q['code'] == 'ok'
        if name in ('shared-fixed-reg', 'shared-custom-reg-fixed', 'shared-custom-reg-mirrored'):
            d = blocks['xreg']['final_device']
            assert (d['pos'], d['rot'], d['mirror']) == ([-1200, -1200], 1, name.endswith('mirrored'))
        caller.append(dict(name=name, classes={k: b['class_name'] for k, b in blocks.items()},
                           canonical_pins={k: b['canonical_pins'] for k, b in blocks.items()}))
    fixed = runs['shared-custom-reg-fixed']['blocks']['xreg']['final_device']
    mirrored = runs['shared-custom-reg-mirrored']['blocks']['xreg']['final_device']
    assert [p['xy'] for p in fixed['pins']] == [[-1140, -1200], [-1260, -1200], [-1230, -1290], [-1170, -1290], [-1200, -1110]]
    assert [p['xy'] for p in mirrored['pins']] == [[-1140, -1200], [-1260, -1200], [-1230, -1110], [-1170, -1110], [-1200, -1290]]
    # Generated-class projection preserves the actual complete terminals but
    # not the original family identity needed by this exact contract reader.
    for dev in ('xreg', 'xsample'):
        assert runs['shared-projected']['blocks'][dev]['canonical_pins'] == runs['shared-base']['blocks'][dev]['canonical_pins']
    assert raw['shared-projected'] == [] and signature(raw['shared-base']) == SHARED
    # The desired pair is already executable with a per-instance caller class.
    # Automatic source-derived signed policy is not implemented by this binary.
    assert_two_policies(runs['shared-custom-reg']['blocks'])
    controls = []
    def sync_r0(block):
        # Mutants alter actual geometry too, avoiding a cache-only rejection.
        d = block['final_device']
        assert d['rot'] == 0 and not d['mirror']
        for pin in d['pins']:
            pin['xy'] = [a + b for a, b in zip(d['pos'], block['canonical_pins'][pin['term']])]
    def rejects(label, blocks):
        try:
            assert_two_policies(blocks)
        except AssertionError:
            controls.append(label)
        else:
            raise AssertionError('mutation escaped: ' + label)
    rejects('automatic_current_default_is_RED_for_regulator_policy', runs['shared-base']['blocks'])
    changed = copy.deepcopy(runs['shared-custom-reg']['blocks'])
    changed['xsample']['canonical_pins'] = copy.deepcopy(changed['xreg']['canonical_pins'])
    sync_r0(changed['xsample'])
    rejects('mutating_shared_class_changes_other_instance', changed)
    changed = copy.deepcopy(runs['shared-custom-reg']['blocks'])
    pins = changed['xreg']['final_device']['pins']
    pins[2]['xy'], pins[3]['xy'] = pins[3]['xy'], pins[2]['xy']
    rejects('stale_canonical_cache_cannot_hide_swapped_final_input_points', changed)
    changed = copy.deepcopy(runs['shared-custom-reg']['blocks'])
    pins = changed['xreg']['final_device']['pins']
    pins[2]['net'], pins[3]['net'] = pins[3]['net'], pins[2]['net']
    rejects('swapping_raw_input_bindings_to_get_pretty_signs', changed)
    changed = copy.deepcopy(runs['shared-custom-reg']['blocks'])
    pins = changed['xreg']['final_device']['pins']
    pins[2], pins[3] = pins[3], pins[2]
    rejects('reordering_terminal_records_changes_formal_indices', changed)
    changed = copy.deepcopy(runs['shared-custom-reg']['blocks'])
    changed['xreg']['canonical_pins'] = {n: [x, -y] for n, (x, y) in DEFAULT.items()}
    sync_r0(changed['xreg'])
    rejects('whole_symbol_vertical_reflection_moves_supply_and_ground', changed)
    # Do not turn two disjoint tuples into a global local-owner rejection.
    disjoint = set(REGULATORS[0][2]).isdisjoint(REGULATORS[1][2])
    assert disjoint
    for filename in ('src/bias_neighbors.zig',):
        for root in (f.ROOT, f.FROZEN):
            code = (root / filename).read_text()
            assert 'if (result != null) return null;' in code
            assert code.index('const pair = find(') < code.index('if (!sk.drawn[a]')
    result = dict(scope='Current native caller/ambiguity observations, bounded raw enumeration, and explicitly future-only signed policies.',
                  manifest_sha256=f.sha(manifest_path), script_sha256=f.sha(Path(__file__)),
                  raw_closure_controls=closure, same_anchor_bias=bias, caller_cases=caller,
                  mutation_rejections=controls,
                  cardinality=dict(bias='Same amplifier anchor; competing private peers must be counted before admission.',
                                   dual_regulator='Two disjoint member tuples: reject the old single whole-DUT special case; compatibility of future local owners is a separate decision.',
                                   shared_definition='One regulator and one sampler with disjoint members; opposite per-instance policies only after each owner is admitted.'),
                  future_only=dict(automatic_regulator_slot='RED in frozen shared-base, positive reference should be above negative feedback when this local policy is admitted.',
                                   automatic_sampling_slot='Negative above positive, already the default; retain rails and all raw ordered bindings.',
                                   collectors='No production local regulator/sampling collector is executed by this Python subset census.',
                                   plugin='No plugin execution or netlist round trip was run. Shared-symbol isolation remains a downstream acceptance requirement.'))
    result = json.loads(json.dumps(result))
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('PASS 29 frozen fixtures, same-anchor ambiguity, final caller geometry, 4 closure controls, 6 policy mutations, b17 contract boundary.')


if __name__ == '__main__':
    main()
