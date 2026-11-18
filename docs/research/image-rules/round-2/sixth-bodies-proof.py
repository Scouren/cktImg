#!/usr/bin/env python3
"""Frozen native no-connect controls and source-backed plugin boundary audit."""
import argparse
import copy
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
from bodies_census import ROOT, BASE, sha, parse, incidence
from bodies_examples import native_binding

FROZEN = BASE / 'resistor-output-integrated-common'
RUN = BASE / 'image-rule-round-2/bodies/sixth-bodies'
MODES = ('missing_body_geometry', 'visible_body', 'hidden_body')
CASES = {
    'lone_resistor': dict(
        formals='d g s', cards=['M1 d g s s nm', 'R1 b 0 1k'],
        expected={'m1': ['d', 'g', 's', 's'], 'r1': ['b', '0']},
        body_net_owners=[['r1', 0, '1']], crosses=[True, True, True]),
    'one_body_peer': dict(
        formals='d g s', cards=['M1 d g s b nm', 'R1 b 0 1k'],
        expected={'m1': ['d', 'g', 's', 'b'], 'r1': ['b', '0']},
        body_net_owners=[['m1', 3, 'B'], ['r1', 0, '1']], crosses=[True, False, True]),
    'two_body_peers': dict(
        formals='d1 g1 s1 d2 g2 s2', cards=['M1 d1 g1 s1 b nm', 'M2 d2 g2 s2 b nm'],
        expected={'m1': ['d1', 'g1', 's1', 'b'], 'm2': ['d2', 'g2', 's2', 'b']},
        body_net_owners=[['m1', 3, 'B'], ['m2', 3, 'B']], crosses=[False, False, False]),
    'two_bodies_and_resistor': dict(
        formals='d1 g1 s1 d2 g2 s2', cards=['M1 d1 g1 s1 b nm', 'M2 d2 g2 s2 b nm', 'R1 b 0 1k'],
        expected={'m1': ['d1', 'g1', 's1', 'b'], 'm2': ['d2', 'g2', 's2', 'b'], 'r1': ['b', '0']},
        body_net_owners=[['m1', 3, 'B'], ['m2', 3, 'B'], ['r1', 0, '1']], crosses=[True, False, True]),
    'formal_body_and_resistor': dict(
        formals='d g s b', cards=['M1 d g s b nm', 'R1 b 0 1k'],
        expected={'m1': ['d', 'g', 's', 'b'], 'r1': ['b', '0']},
        body_net_owners=[['m1', 3, 'B'], ['r1', 0, '1']], crosses=[False, False, False]),
    'source_tie_and_resistor': dict(
        formals='d g', cards=['M1 d g b b nm', 'R1 b 0 1k'],
        expected={'m1': ['d', 'g', 'b', 'b'], 'r1': ['b', '0']},
        body_net_owners=[['m1', 2, 'S'], ['m1', 3, 'B'], ['r1', 0, '1']], crosses=[False, False, False]),
}


def deck(case):
    return ('sixth body presentation literal\n.model nm nmos\n.subckt dut ' + case['formals'] +
            '\n' + '\n'.join(case['cards']) + '\n.ends dut\n')


def symbol_text(mode):
    text = (FROZEN / 'tests/symbols.zon').read_text()
    if mode == MODES[0]:
        return text
    lines = text.splitlines()
    k = next(i for i, line in enumerate(lines) if '.name = "nmos",' in line)
    old = '.name = "s", .at = .{ .x = -20, .y = 0 } }'
    new = old + ', .{ .name = "b", .at = .{ .x = 0, .y = 20 }, .hidden = ' + (
        'true' if mode == 'hidden_body' else 'false') + ' }'
    assert lines[k].count(old) == 1
    lines[k] = lines[k].replace(old, new)
    lines[k] = lines[k].replace('.draw = .{',
        '.draw = .{ .{ .line = .{ .a = .{ .x = 0, .y = -3 }, .b = .{ .x = 0, .y = 20 } } },', 1)
    return '\n'.join(lines) + '\n'


def verify(case, mode, document):
    """Literal raw bindings and expected mark sets, independent of engine loops."""
    actual = {d['name']: d for d in document['devices'] if d['name'] in case['expected']}
    assert set(actual) == set(case['expected'])
    for card, pins in case['expected'].items():
        if card.startswith('m'):
            native_binding(actual[card], pins)
            assert len(actual[card]['pins']) == (3 if mode == MODES[0] else 4)
        else:
            assert [p['net'] for p in actual[card]['pins']] == pins
    want_cross = case['crosses'][MODES.index(mode)]
    crosses = [actual['r1']['pins'][0]['xy']] if want_cross else []
    assert document['no_connects'] == crosses, (mode, document['no_connects'], crosses)
    return actual


def rejects(case, mode, document):
    mutations = {}
    for name in ('replace_body_with_source', 'invert_resistor_cross'):
        if name == 'invert_resistor_cross' and 'r1' not in case['expected']:
            continue
        changed = copy.deepcopy(document)
        if name == 'replace_body_with_source':
            m = next(d for d in changed['devices'] if d['name'] == 'm1')
            if case['expected']['m1'][2] == case['expected']['m1'][3]:
                continue
            if 'bulk' in m:
                m['bulk'] = m['pins'][2]['net']
            else:
                m['pins'][3]['net'] = m['pins'][2]['net']
        else:
            r = next(d for d in changed['devices'] if d['name'] == 'r1')
            changed['no_connects'] = [] if changed['no_connects'] else [r['pins'][0]['xy']]
        try:
            verify(case, mode, changed)
        except AssertionError:
            mutations[name] = 'rejected by same complete binding/mark checker'
        else:
            raise AssertionError(('mutation survived', name, mode))
    return mutations


def source_provenance():
    names = ['src/sketch.zig', 'src/placed.zig', 'src/json.zig', 'src/abi.zig',
             'include/cktimg.h', 'tools/schemify/layout.zig', 'src/library.zig', 'tests/svg.zig']
    rows = {}
    for name in names:
        current, frozen = ROOT / name, FROZEN / name
        rows[name] = dict(current_sha256=sha(current), frozen_sha256=sha(frozen),
                          complete_file_identical=current.read_bytes() == frozen.read_bytes())
    for fn in ('hiddenPins', 'noConnects'):
        pieces = [re.search(r'(?ms)^fn ' + fn + r'\(.*?^}', (p / 'src/sketch.zig').read_text()).group()
                  for p in (ROOT, FROZEN)]
        assert pieces[0] == pieces[1], ('relevant function differs', fn)
        rows['src/sketch.zig'][fn + '_identical_sha256'] = hashlib.sha256(pieces[0].encode()).hexdigest()
    return rows


def actual_hidden_bridge(svg):
    """Literal actual strokes, read independently from the rendered control."""
    root = ET.fromstring(svg)
    ns = '{http://www.w3.org/2000/svg}'
    # This certificate supports the frozen renderer's explicit subset only.
    # A transformed/invisible stroke or finer coordinate must decline, not be
    # mistaken for the untransformed visible literal by reading `points` alone.
    for el in root.iter():
        assert el.tag != ns + 'style', 'CSS is outside this literal certificate'
        assert not set(el.attrib).intersection({
            'transform', 'style', 'display', 'visibility', 'opacity',
            'stroke-opacity', 'fill-opacity', 'class', 'clip-path', 'mask'}), 'unsupported ink authority'
    groups = list(root.iter(ns + 'g'))
    assert len(groups) == 1 and groups[0].attrib == {
        'fill': 'none', 'stroke': '#1d2330', 'stroke-width': '1.6',
        'stroke-linejoin': 'round', 'stroke-linecap': 'round'}, 'unsupported stroke group'
    polys = []
    for el in root.iter(ns + 'polyline'):
        assert el in list(groups[0]) and set(el.attrib) == {'points'}, 'unsupported primitive scope'
        values = re.findall(r'-?\d+(?:\.\d+)?', el.attrib['points'])
        assert len(values) % 2 == 0
        precise = [Decimal(v) * 10 for v in values]
        assert all(v == v.to_integral_value() for v in precise), 'coordinates finer than exact tenths'
        integers = [int(v) for v in precise]
        polys.append([integers[k:k+2] for k in range(0, len(integers), 2)])
    # Tenths of SVG units. Both own B strokes meet at the same literal tip.
    left, right = [[1520, 1280], [1888, 1280]], [[2256, 1280], [1888, 1280]]
    channels = [[[1520, 1120], [1520, 1440]], [[2256, 1120], [2256, 1440]]]
    for p in [left, right] + channels:
        assert polys.count(p) == 1, ('missing/duplicate literal body stroke', p)
    assert left[1] == right[1]
    for lead, channel in zip([left, right], channels):
        assert lead[0][0] == channel[0][0] == channel[1][0]
        assert channel[0][1] < lead[0][1] < channel[1][1]
    return dict(units='tenths of actual SVG units', body_leads=[left, right], channels=channels,
                coincident_actual_tip=left[1], both_leads_attach_to_own_channel=True)


def hidden_bridge_control():
    stem = RUN / 'two_body_peers--hidden_body'
    document = json.loads(stem.with_suffix('.json').read_text())
    mos = [d for d in document['devices'] if d['name'] in ['m1', 'm2']]
    assert [m['pins'][3]['xy'] for m in mos] == [[100, 40], [100, 40]]
    assert not any(w['net'] == 'b' for w in document['wires'])
    assert document['labels'] == []
    svg = stem.with_suffix('.svg').read_text()
    result = actual_hidden_bridge(svg)
    result['json_body_contacts'] = [[100, 40], [100, 40]]
    result['no_net_b_routes_or_native_labels'] = True
    removed = []
    for points in ['152.0,128.0 188.8,128.0 ', '225.6,128.0 188.8,128.0 ']:
        root = ET.fromstring(svg)
        for parent in root.iter():
            matches = [el for el in parent if el.attrib.get('points') == points]
            for el in matches:
                parent.remove(el)
        try:
            actual_hidden_bridge(ET.tostring(root, encoding='unicode'))
        except AssertionError:
            removed.append(points)
        else:
            raise AssertionError('deleted actual B lead escaped checker')
    result['independent_actual_lead_deletions_rejected'] = removed
    attacks = {}
    right = '<polyline points="225.6,128.0 188.8,128.0 "/>'
    assert svg.count(right) == 1
    for name, altered in {
        'moved_actual_right_lead': right.replace('/>', ' transform="translate(0 10)"/>'),
        'invisible_actual_right_lead': right.replace('/>', ' visibility="hidden"/>'),
        'sub_tenth_actual_tip': right.replace('188.8,', '188.89,'),
    }.items():
        try:
            actual_hidden_bridge(svg.replace(right, altered))
        except AssertionError as error:
            attacks[name] = str(error)
        else:
            raise AssertionError(('unsupported actual ink accepted', name))
    result['independent_unsupported_ink_mutations_rejected'] = attacks
    return result


def execute():
    RUN.mkdir(parents=True, exist_ok=True)
    binary = FROZEN / 'zig-out/bin/cktimg-json'
    assert sha(binary) == 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'
    symbols = {}
    for mode in MODES:
        symbols[mode] = RUN / (mode + '.zon')
        symbols[mode].write_text(symbol_text(mode))
    rows = []
    for name, case in CASES.items():
        source = RUN / (name + '.cir')
        source.write_text(deck(case))
        formals, raw = parse(source.read_text())
        assert formals == case['formals'].split()
        assert {r['card']: r['nets'] for r in raw} == case['expected']
        assert incidence(raw)['b'] == case['body_net_owners']
        for mode in MODES:
            stem = name + '--' + mode
            output, svg = RUN / (stem + '.json'), RUN / (stem + '.svg')
            subprocess.run([str(binary), '--symbols', str(symbols[mode]), '--svg', str(svg),
                            str(source), str(output)], check=True, capture_output=True)
            document = json.loads(output.read_text())
            actual = verify(case, mode, document)
            body_pins = [{'card': card, 'net': pins[3],
                          'json_pin': actual[card]['pins'][3] if mode != MODES[0] else None,
                          'json_bulk': actual[card].get('bulk')}
                         for card, pins in case['expected'].items() if card.startswith('m')]
            body_routes = [wire for wire in document['wires'] if wire['net'] == 'b']
            if name == 'two_body_peers':
                assert bool(body_routes) == (mode == 'visible_body')
            rows.append(dict(case=name, mode=mode, expected_ordered_bindings=case['expected'],
                net_b_raw_occurrences=case['body_net_owners'], net_b_is_formal='b' in formals,
                native_no_connects=document['no_connects'], body_pins=body_pins,
                net_b_routes=body_routes, native_labels=document['labels'],
                rejected_output_mutations=rejects(case, mode, document),
                files={str(p.relative_to(ROOT)): sha(p) for p in (source, symbols[mode], output, svg)}))
    return dict(scope='18 native executions; no C ABI, plugin or host execution',
                binary_sha256=sha(binary), script_sha256=sha(Path(__file__)),
                checker_dependencies={p: sha(ROOT / p) for p in [
                    'docs/research/image-rules/round-2/bodies_census.py',
                    'docs/research/image-rules/round-2/bodies_examples.py']},
                current_and_frozen_code=source_provenance(), cases=rows,
                actual_hidden_lead_contact_control=hidden_bridge_control(),
                source_backed_plugin_claim='layout.library and translate both classify MOS index 3 as hidden; '
                    'translate names each hidden pin plus an unnamed visible peer and suppresses crosses at marks; '
                    'this code trace is not an executed target connectivity certificate')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', type=Path)
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    result = execute()
    if args.check:
        assert result == json.loads(args.check.read_text()), 'exact named evidence changed'
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('PASS 18 native executions, complete literal bindings, exact no-connect sets and mutation controls')


if __name__ == '__main__':
    main()
