#!/usr/bin/env python3
"""Bounded five-MOS organization witnesses; no production selector or placer."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
RUN = BASE / 'image-rule-round-2/groups/twelfth'
FIG = HERE / 'figures/groups/twelfth'
EXAMPLES = ROOT / 'external/examples/analoggenie'
BINARY = BASE / 'resistor-output-integrated-common/zig-out/bin/cktimg-json'
BINARY_SHA = 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'
sys.path.insert(0, str(HERE.parent.parent / 'figures'))
from channel_bridges import svg_channel


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def rel(p):
    return str(p.relative_to(ROOT))


def module(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def collect(case):
    if case['disposition'] != 'raw_multigroup_candidate':
        return []
    cards = {r[0]: r for r in case['ordered_cards']}
    formal, rails = set(case['formals']), case['admitted_rail_facts']
    types = {d: case['model_definitions'][r[5]][0] for d, r in cards.items()}
    mate = case['unique_reflection']['devices']
    found = []
    for group in case['proposed_groups']:
        if len(group) != 5:
            continue
        for tail in group:
            t = cards[tail]
            pair = sorted(d for d in group if d != tail and cards[d][3] == t[1])
            if len(pair) != 2 or mate[tail] != tail or mate[pair[0]] != pair[1]:
                continue
            if t[1] in formal or t[1] in rails or t[3] != t[4] or t[3] not in rails:
                continue
            incidence = sorted((d, k) for d, r in cards.items() for k, n in enumerate(r[1:5]) if n == t[1])
            if incidence != sorted([(tail, 0)] + [(d, 2) for d in pair]):
                continue
            if any(types[d] != types[tail] for d in pair):
                continue
            if any(cards[d][2] not in formal for d in pair) or cards[pair[0]][2] == cards[pair[1]][2]:
                continue
            loads = []
            for d in pair:
                choices = [q for q in group if q not in pair + [tail] and cards[q][1] == cards[d][1]]
                if len(choices) != 1:
                    break
                loads.append(choices[0])
            if len(set(loads)) != 2 or set(pair + loads + [tail]) != set(group):
                continue
            if mate[loads[0]] != loads[1] or any(types[q] == types[tail] for q in loads):
                continue
            if any(cards[q][3] != cards[q][4] or cards[q][3] not in rails or cards[q][3] == t[3] for q in loads):
                continue
            if cards[loads[0]][2] != cards[loads[1]][2] or cards[loads[0]][2] not in formal or t[2] not in formal:
                continue
            if {cards[d][2] for d in pair} & {t[2], cards[loads[0]][2]}:
                continue
            gate_formals = {cards[d][2] for d in pair} | {t[2], cards[loads[0]][2]}
            if any(k != 1 for r in cards.values() for k, net in enumerate(r[1:5]) if net in gate_formals):
                continue
            if any(cards[d][1] in formal or cards[d][1] in rails for d in pair):
                continue
            boundary = {}
            for net in sorted({n for d in group for n in cards[d][1:5]}):
                inside = [[d, k] for d in sorted(group) for k, n in enumerate(cards[d][1:5]) if n == net]
                outside = [[d, k] for d, r in sorted(cards.items()) if d not in group for k, n in enumerate(r[1:5]) if n == net]
                boundary[net] = dict(inside=inside, outside=outside, formal=net in formal, rail=rails.get(net))
            found.append(dict(members=group, tail=tail, inputs=pair, loads=loads, input_type=types[tail],
                              common_control=t[2] == cards[loads[0]][2], complete_boundary=boundary))
    assert len({tuple(x['members']) for x in found}) == len(found)
    return found


def geometry(leads, candidate):
    center = {d: [(p[0][0] + p[1][0]) / 2, (p[0][1] + p[1][1]) / 2] for d, p in leads.items()}
    a, b = candidate['inputs']
    l, r = candidate['loads']
    t = candidate['tail']
    sign = 1 if candidate['input_type'] == 'nmos' else -1
    lo, hi = sorted([center[a][0], center[b][0]])
    return dict(branch_columns=all(leads[d][0][0] == leads[d][1][0] for d in candidate['members']) and
                center[a][0] == center[l][0] and center[b][0] == center[r][0],
                inputs_same_row=center[a][1] == center[b][1], loads_same_row=center[l][1] == center[r][1],
                tail_between=lo < center[t][0] < hi,
                tail_exact_channel_midpoint=2 * center[t][0] == lo + hi,
                branch_order=all(sign * (center[d][1] - center[q][1]) > 0 for d, q in zip([a, b], [l, r])),
                tail_beyond_inputs=all(sign * (center[t][1] - center[d][1]) > 0 for d in [a, b]),
                span=hi - lo, height=max(center[d][1] for d in candidate['members']) - min(center[d][1] for d in candidate['members']),
                centers={d: center[d] for d in candidate['members']})


def native_cards(document, cards, models):
    names = [d['name'] for d in document['devices']]
    assert len(names) == len(set(names))
    result = {}
    for index, d in enumerate(document['devices']):
        if d['name'] not in cards:
            assert d['class'] in ('vdd', 'gnd', 'ipin', 'opin')
            assert d['name'] == f"_{d['class']}{index}" and d['value'] == '' and 'bulk' not in d
            assert len(d['pins']) == 1 and d['pins'][0]['term'] == 'p'
            continue
        row = cards[d['name']]
        assert d['class'] == models[row[5]][0]
        assert [p['term'] for p in d['pins']] == ['d', 'g', 's']
        assert [p['net'] for p in d['pins']] == row[1:4] and d['bulk'] == row[4]
        assert d['value'].split() == row[5:]
        result[d['name']] = d
    assert set(result) == set(cards)
    return result


def run(name, text, execute):
    deck = RUN / (name + '.cir')
    if deck.exists():
        assert deck.read_text() == text
    else:
        deck.write_text(text)
    prefix = RUN / name
    command = [str(BINARY), '--svg', str(prefix.with_suffix('.svg')), '--report', str(prefix.with_suffix('.report.json')),
               str(deck), str(prefix.with_suffix('.json'))]
    render = ['magick', '-background', 'white', '-density', '144', str(prefix.with_suffix('.svg')), '-resize',
              '1800x1400', '-define', 'png:exclude-chunks=date,time', str(FIG / (name + '.png'))]
    if execute:
        p = subprocess.run(command, capture_output=True)
        prefix.with_suffix('.stdout').write_bytes(p.stdout)
        prefix.with_suffix('.stderr').write_bytes(p.stderr)
        prefix.with_suffix('.exit').write_text(str(p.returncode) + '\n')
        assert p.returncode == 0
        subprocess.run(render, capture_output=True, check=True)
    assert prefix.with_suffix('.exit').read_text() == '0\n'
    return dict(command=command, render_command=render, artifacts={rel(p): sha(p) for p in sorted(RUN.glob(name + '.*'))},
                raster=dict(path=rel(FIG / (name + '.png')), sha256=sha(FIG / (name + '.png'))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'twelfth-organization-probe.json')
    args = ap.parse_args()
    assert sha(BINARY) == BINARY_SHA
    RUN.mkdir(exist_ok=True)
    FIG.mkdir(exist_ok=True)
    parser = module('ninth-local-groups-census')
    census_path = HERE / 'ninth-local-groups-census.json'
    census = json.loads(census_path.read_text())
    cases, found = {}, {}
    for ident in census['names']:
        p = EXAMPLES / (ident + '.cir')
        assert sha(p) == census['cases'][ident]['deck_sha256']
        row = parser.decompose(*parser.facts(p.read_text()))
        assert all(census['cases'][ident][k] == v for k, v in row.items())
        cases[ident] = row
        found[ident] = collect(row)
    expected = ['ag-1028', 'ag-1046', 'ag-1071', 'ag-1079', 'ag-1080']
    assert [n for n in census['names'] if found[n]] == expected
    records = []
    for ident in expected:
        case = cases[ident]
        raw = {r[0]: r for r in case['ordered_cards']}
        human = json.loads((EXAMPLES / (ident + '.human.json')).read_text())
        leads = {d['card']: svg_channel(EXAMPLES / (ident + '.svg'), d)[1] for d in human['devices']}
        native_path = BASE / 'image-rule-round-2/groups/ninth' / (ident + '.json')
        native = native_cards(json.loads(native_path.read_text()), raw, case['model_definitions'])
        native_leads = {d: [v['pins'][0]['xy'], v['pins'][2]['xy']] for d, v in native.items()}
        for candidate in found[ident]:
            members = candidate['members']
            selected = {d: raw[d] for d in members}
            boundary = candidate['complete_boundary']
            projected_formals = [n for n in case['formals'] if n in boundary]
            projected_formals += sorted(n for n, r in boundary.items() if r['outside'] and n not in projected_formals)
            models = {raw[d][5]: case['model_definitions'][raw[d][5]] for d in members}
            text = '.subckt dut ' + ' '.join(projected_formals) + '\n'
            text += '\n'.join(' '.join(raw[d]) for d in members) + '\n'
            text += '\n'.join('.model ' + n + ' ' + ' '.join(v) for n, v in sorted(models.items())) + '\n.ends dut\n'
            name = ident + '-' + candidate['tail'] + '-isolated'
            outputs = run(name, text, args.execute)
            doc = json.loads((RUN / (name + '.json')).read_text())
            isolated = native_cards(doc, selected, models)
            isolated_leads = {d: [v['pins'][0]['xy'], v['pins'][2]['xy']] for d, v in isolated.items()}
            records.append(dict(id=ident, name=name, candidate=candidate, raw_cards=selected, models=models,
                                original_formals=case['formals'], projected_formals=projected_formals,
                                original_deck_sha256=sha(EXAMPLES / (ident + '.cir')),
                                projection_losses=dict(removed_ordered_cards=[r for r in case['ordered_cards'] if r[0] not in members],
                                    omitted_original_formals=[n for n in case['formals'] if n not in projected_formals],
                                    newly_exported_boundary_nets=[n for n in projected_formals if n not in case['formals']],
                                    absent_context=['outside device classes/poses and occupied ink', 'outside route and name reservations',
                                                    'full-DUT parent dependencies and page composition', 'full-DUT port placement and generated role geometry']),
                                source_geometry=geometry(leads, candidate), native_geometry=geometry(native_leads, candidate),
                                isolated_geometry=geometry(isolated_leads, candidate), isolated_devices=isolated,
                                source_svg_sha256=sha(EXAMPLES / (ident + '.svg')), source_human_sha256=sha(EXAMPLES / (ident + '.human.json')),
                                native_json_sha256=sha(native_path), **outputs))
    controls = {}
    values = parser.facts((EXAMPLES / 'ag-1080.cir').read_text())
    for what in ('different_tail_control', 'extra_tail_consumer', 'input_gate_tied', 'one_model_changed'):
        v = copy.deepcopy(values)
        if what == 'different_tail_control': v[0]['m5'][2] = 'clkb'
        elif what == 'extra_tail_consumer': v[0]['m6'][2] = v[0]['m5'][1]
        elif what == 'input_gate_tied': v[0]['m2'][2] = v[0]['m1'][2]
        else:
            v[0]['m1'][5] = 'other'; v[2]['other'] = ['nmos']
        result = parser.decompose(*v)
        controls[what] = dict(disposition=result['disposition'], candidates=collect(result), cards=v[0])
    assert not next(c for c in controls['different_tail_control']['candidates'] if c['tail'] == 'm5')['common_control']
    assert all(not any(c['tail'] == 'm5' for c in controls[k]['candidates']) for k in ('extra_tail_consumer', 'input_gate_tied', 'one_model_changed'))
    v = parser.facts((EXAMPLES / 'ag-1028.cir').read_text())
    aliases = {'net3': 'vin+', 'net1': 'vin-'}
    for row in v[0].values():
        row[1:5] = [aliases.get(n, n) for n in row[1:5]]
    aliased = parser.decompose(*v)
    assert aliased['disposition'] == 'raw_multigroup_candidate' and not collect(aliased)
    controls['ag1028_outputs_aliased_to_inputs'] = dict(disposition=aliased['disposition'], candidates=collect(aliased), cards=v[0])
    for r in records:
        if r['candidate']['common_control']:
            assert all(r['source_geometry'][k] for k in ('branch_columns','inputs_same_row','loads_same_row','tail_between','branch_order','tail_beyond_inputs'))
    assert not records[0]['candidate']['common_control'] and not records[0]['source_geometry']['inputs_same_row']
    result = dict(script_sha256=sha(Path(__file__)), binary_sha256=BINARY_SHA, census_sha256=sha(census_path),
                  dependencies={rel(p):sha(p) for p in (HERE / 'ninth-local-groups-census.py', HERE.parent.parent / 'figures/channel_bridges.py')},
                  all_names=census['names'], original_disposition_names=census['disposition_names'],
                  trial_domain_names=census['disposition_names']['raw_multigroup_candidate'],
                  not_shape_searched_names=[n for n in census['names'] if cases[n]['disposition'] != 'raw_multigroup_candidate'],
                  raw_five_mos_names=expected, proposed_common_control_names=sorted({r['id'] for r in records if r['candidate']['common_control']}),
                  complete_census={n:found[n] for n in census['names']}, records=records, raw_mutations=controls,
                  scope='All 2202 original O0 dispositions are reread and preserved. Five-MOS shape search is ONLY inside the 11 raw acyclic multigroup candidates: six parents in five circuits, narrowed to five common-control parents in four circuits. Empty rows outside those 11 mean not shape-searched, not shape-free. Isolated native references are chosen diagnostic footprints, not source-independent optimality or full-context routing evidence.')
    if args.check: assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
    print(json.dumps({'five_mos_parents':len(records),'common_control_parents':sum(r['candidate']['common_control'] for r in records),
                      'measurements':[(r['name'],r['source_geometry']['span'],r['native_geometry']['span'],r['isolated_geometry']['span']) for r in records]}))


if __name__ == '__main__':
    main()
