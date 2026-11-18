#!/usr/bin/env python3
"""Independent source attacks, scalar-bus literals and sibling gate CLI probes."""
import argparse
from fractions import Fraction
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('sixth_symbol_proof', HERE / 'sixth-symbols-proof.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)
ROOT = p.ROOT
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/seventh-symbols'
BIN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/resistor-output-integrated-common/zig-out/bin/cktimg-json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_attacks(require_fixed):
    before = json.loads((HERE / 'seventh-review-symbols-before.json').read_text())
    results = []
    for row in before['attacks']:
        path = ROOT / row['file']
        assert sha(path) == row['sha256']
        try:
            p.side_source(439, root_override=p.ET.parse(path).getroot())
        except (AssertionError, ValueError) as error:
            result = dict(mutation=row['mutation'], rejected=True, reason=str(error))
        else:
            result = dict(mutation=row['mutation'], rejected=False)
        if require_fixed:
            assert result['rejected'], result
        results.append(result)
    return dict(before_sha256=sha(HERE / 'seventh-review-symbols-before.json'),
                original_positive_ids=[p.side_source(n)['id'] for n in [439, 440, 515, 516]],
                replayed_mutated_actual_svgs=results)


def gate_probe(name, family, supplies, execute):
    roles = ['vdd', 'vss', 'a', 'b', 'y'] if supplies else ['a', 'b', 'y']
    nets = ['vdd', 'vss', 'i', 'j', 'o'] if supplies else ['i', 'j', 'o']
    text = ('* Independent sibling-class contact literal\n.subckt ' + family + ' ' + ' '.join(roles) +
            '\n.ends ' + family + '\n.subckt dut ' + ' '.join(nets) +
            '\nX1 ' + ' '.join(nets) + ' ' + family + '\n.ends dut\n')
    deck, data, svg = [RUN / (name + ext) for ext in ['.cir', '.json', '.svg']]
    if execute:
        deck.write_text(text)
        subprocess.run([str(BIN), '--svg', str(svg), str(deck), str(data)], check=True, capture_output=True)
    assert deck.read_text() == text
    expected = dict(card='x1', family=family, ports=roles, bindings=nets,
                    source=dict(body='curved', circles=[{}] if family in ['nor_gate', 'xnor_gate'] else [],
                                open_paths=int(family in ['xor_gate', 'xnor_gate'])))
    document = json.loads(data.read_text())
    shape = json.loads(json.dumps(p.d.native_ink(document, p.ET.parse(svg).getroot(), expected)))
    assert shape['body_category_agrees'] and shape['bubble_count_agrees']
    assert shape['extra_input_path_count_agrees'] and shape['terminal_sides_agree']
    assert shape['input_order_agrees']
    checks = {lead['term']: p.first_contact(shape['body_vertices'], shape['circles'], *lead['vertices'])
              for lead in shape['leads']}
    bad = sorted(role for role, check in checks.items() if not check['terminates_at_first_contact'])
    assert bad == (['vdd', 'vss'] if supplies else [])
    rational = None
    if supplies:
        # Independent exact line equation through manually read own outline
        # vertices, not the target's ray/polygon intersection implementation.
        vertices = shape['body_vertices']
        for point in [[-15., -40.], [4., -34.], [-15., 40.], [4., 34.]]:
            assert vertices.count(point) == 1
        y = Fraction(-40) + Fraction(15, 19) * 6
        penetration = Fraction(-35) - y
        assert y == Fraction(-670, 19) and penetration == Fraction(5, 19)
        for lead in shape['leads']:
            if lead['term'] in ['vdd', 'vss']:
                sign = -1 if lead['term'] == 'vdd' else 1
                assert lead['vertices'] == [[0., sign * 60.], [0., sign * 35.]]
                assert abs(checks[lead['term']]['attachment_error_along_lead'] - float(penetration)) < 5e-9
        rational = dict(top_outline_at_x0=str(y), bottom_outline_at_x0=str(-y),
                        inward_supply_lead_overshoot=str(penetration))
    return dict(name=name, family=family, roles=roles, nets=nets, shape=shape,
                contacts=checks, expected_nonterminating_contacts=bad, independent_rational_oracle=rational,
                files={str(f.relative_to(ROOT)): sha(f) for f in [deck, data, svg]})


def bus_control():
    calls = p.calls((p.EXAMPLES / 'ag-1146.cir').read_text())
    row = next(c for c in calls if c['family'] == 'varactor_switched_caps')
    roles = ['von', 'vop', 'b_3_', 'b_2_', 'b_1_', 'b_0_', 'vcn', 'vcp']
    assert row['ports'] == roles and row['bindings'] == roles
    actual = p.opaque(row, 'ag-1146')
    assert len(actual['source']['lines']) == 5
    assert [x['pin'] for x in actual['actual_pin_labels']] == ['Von', 'Vop', 'B<3:0>', 'Vcn', 'Vcp']
    assert actual['native']['ordered_ports'] == roles
    assert actual['native']['ordered_bindings'] == roles
    assert len(actual['native']['leads']) == 8
    rejected = []
    data = json.loads((p.RUN / 'sixth-native/ag-1146.json').read_text())
    svg = p.ET.parse(p.RUN / 'sixth-native/ag-1146.svg').getroot()
    import copy
    for mode in ['drop_scalar_bus_pin', 'swap_scalar_bus_bindings']:
        changed = copy.deepcopy(data)
        dev = next(d for d in changed['devices'] if d['name'] == row['card'])
        if mode == 'drop_scalar_bus_pin':
            del dev['pins'][3]
        else:
            dev['pins'][2]['net'], dev['pins'][3]['net'] = dev['pins'][3]['net'], dev['pins'][2]['net']
        try:
            p.d.native_ink(changed, svg, dict(row, source=actual['source']))
        except ValueError:
            rejected.append(mode)
        else:
            raise AssertionError(('scalar bus mutation survived', mode))
    return dict(id='ag-1146', card=row['card'], literal_ordered_roles=roles,
                source_drawn_leads=5, native_scalar_leads=8,
                same_named_source_label_absent_for=['b_3_', 'b_2_', 'b_1_', 'b_0_'],
                rejected_actual_native_json_mutations=rejected,
                limitation='No independent host bus-expression or bit-order netlisting certificate.')


def caller_control(execute):
    baseline = (HERE / 'sixth-symbols-pfd-sides.cir').read_text()
    assert baseline.count('*@ left A') == baseline.count('*@ right QA') == 1
    text = baseline.replace('*@ left A', '*@ right A').replace('*@ right QA', '*@ left QA')
    deck, data, svg = [RUN / ('pfd-caller-contrary' + ext) for ext in ['.cir', '.json', '.svg']]
    if execute:
        deck.write_text(text)
        subprocess.run([str(BIN), '--svg', str(svg), str(deck), str(data)], check=True, capture_output=True)
    assert deck.read_text() == text
    raw = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('*@'))
    calls = p.calls(raw)
    document = json.loads(data.read_text())
    for call in calls:
        device = next(d for d in document['devices'] if d['name'] == call['card'])
        assert [v['term'] for v in device['pins']] == call['ports']
        assert [v['net'] for v in device['pins']] == call['bindings']
    device = next(d for d in document['devices'] if d['name'] == 'xpfd')
    local = {v['term']: list(p.d.native.inverse(device, v['xy'])) for v in device['pins']}
    assert local['a'][0] > 0 and local['qa'][0] < 0
    assert local['b'][0] < 0 and local['qb'][0] > 0
    return dict(name='pfd-caller-contrary', canonical_pins=local, all_complete_X_calls=calls,
                required_future_default_boundary='An automatic A/B-left QA/QB-right choice must yield to these admitted opposite caller sides.',
                files={str(f.relative_to(ROOT)): sha(f) for f in [deck, data, svg]})


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', type=Path)
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--require-fixed', action='store_true')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    RUN.mkdir(parents=True, exist_ok=True)
    assert sha(BIN) == 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'
    rows = [gate_probe(family, family, True, args.execute)
            for family in ['or_gate', 'nor_gate', 'xor_gate', 'xnor_gate']]
    rows.append(gate_probe('xor_without_supplies', 'xor_gate', False, args.execute))
    result = dict(scope='Four source positives, four actual-SVG attacks, one scalar-bus literal, five sibling-class and one contrary-caller native executions; no plugin or host execution.',
                  source_attacks=source_attacks(args.require_fixed), scalar_bus=bus_control(), gate_classes=rows,
                  contrary_caller=caller_control(args.execute),
                  binary_sha256=sha(BIN), script_sha256=sha(Path(__file__)),
                  dependencies={str(f.relative_to(ROOT)): sha(f) for f in [HERE / 'sixth-symbols-proof.py',
                      Path(p.d.__file__), Path(p.d.native.__file__), Path(p.d.source.__file__)]})
    result = json.loads(json.dumps(result))
    if args.check:
        assert result == json.loads(args.check.read_text()), 'named review evidence changed'
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('PASS source attacks, complete scalar bus, five sibling classes and contrary caller control')


if __name__ == '__main__':
    main()
