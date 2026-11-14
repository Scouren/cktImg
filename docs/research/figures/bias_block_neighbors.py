#!/usr/bin/env python3
"""Actual amplifier-bias/neighbor geometry, with topology and exclusions separate.

Source-only output is deterministic and checked against an exact inventory.
Optional --native LABEL=SVGDIR and --corpus LABEL=CORPUSDIR pairs add own-body
native measurements. SVG JSON must equal the complete scored corpus. No
source coordinate, connectivity or terminal side is inferred from a name.
This is future research; it does not select production layout behavior.
"""

import argparse
import collections
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import remaining_amplifiers as remaining
import digital_symbols as digital
import thin_connectivity as graph
import block_aliases_native as native
import controller_glyphs as glyph
from mos_forms import read_cards

UNITS = dict(left=(-1, 0), right=(1, 0), up=(0, -1), down=(0, 1))
OPPOSITE = dict(left='right', right='left', up='down', down='up')
PRIMITIVE = dict(m=['d', 'g', 's', 'b'], q=['c', 'b', 'e'], r=['1', '2'], c=['1', '2'], l=['1', '2'])


def primitive_ports(words, models):
    if words[0].startswith('q'):
        model_at = [i for i in (4, 5) if i < len(words) and words[i] in models]
        if len(model_at) != 1:
            raise ValueError('BJT card has no unique declared model position')
        return ['c', 'b', 'e', 's'][:model_at[0]-1]
    return PRIMITIVE[words[0][0]]


def calls(examples, ident):
    text = (examples/'analoggenie'/(ident+'.cir')).read_text()
    definitions, cards = digital.declarations(text), read_cards(text)
    models = {w[1] for line in text.lower().splitlines() if (w := line.split()) and w[0]=='.model'}
    bindings, rows = {}, {}
    for card, words in cards.items():
        if card.startswith('x'):
            end = next((i for i, w in enumerate(words) if '=' in w or w=='params:'), len(words))
            family, nets = words[end-1], words[1:end-1]
            ports = definitions[family]
            if len(ports) != len(nets) or len(set(ports)) != len(ports):
                raise ValueError('ambiguous declared block ports')
            rows[card] = dict(id=ident, card=card, corpus='analoggenie', family=family, ports=ports, bindings=nets)
        else:
            ports = primitive_ports(words, models)
            nets = words[1:1+len(ports)]
        bindings.update({(card, p): n for p, n in zip(ports, nets)})
    return rows, bindings, list(definitions.values())[-1]


def isolated(peer, public, incidences):
    """Observed nonrail isolation condition, not a transfer-function proof."""
    return all(net in public and incidences[net] == [(peer['card'], port)]
               for port, net in zip(peer['ports'], peer['bindings'])
               if port not in ('vdd', 'vss', peer['port']))


def relation(a, side, b, body):
    unit = UNITS[side]
    projection = lambda p: sum((p[i]-a[i])*unit[i] for i in range(2))
    return dict(endpoint_projection=projection(b), same_axis=abs((b[0]-a[0])*unit[1]-(b[1]-a[1])*unit[0]) < .01,
                whole_body_outward=None if body is None else all(projection(p) > 0 for p in body))


def peer_ink(examples, context, call_rows, card, port):
    if card.startswith('x'):
        row = remaining.inspect(call_rows[card], examples)
        if port not in row['cached_port_leads']:
            raise ValueError('peer declared pin has no actual own-lead match')
        lead = row['external_leads'][row['cached_port_leads'][port]]
        visible = {p: dict(row['external_leads'][i]) for p, i in row['cached_port_leads'].items()}
        return dict(endpoint=lead['endpoint'], lead=lead, body=row['body'], source_object=row['source_object'],
                    visible_named_leads=visible, unknown_geometry=row['absent_cached_ports']+row['cached_frame_mismatches'],
                    method='declared cached ports match actual own-body SVG leads')
    device = context['devices'][card]
    term = next(p for p in device['nets'] if p.lower()==port)
    reader = graph.actual_resistor if card[0]=='r' else graph.actual_inductor if card[0]=='l' else graph.actual_glyph
    actual = reader(context['root'], device)
    return dict(endpoint=actual['terminals'][term], actual_glyph=actual, method='actual primitive named SVG lead')


def source(examples, old, references):
    rows, amplifiers = [], []
    for kind, selected in [('known_opamp', old['selected']), ('reference', references['rows'])]:
        for original in selected:
            ident, card = original['id'], original['card']
            call_rows, bindings, public = calls(examples, ident)
            call = call_rows[card]
            if call['ports'] != original['ports']:
                raise ValueError('source declaration inventory changed')
            context = graph.load_source(examples/'analoggenie', ident)
            if set(context['cards']) != {d.lower() for d in context['devices']}:
                raise ValueError('outer source device inventory disagrees')
            inspected = remaining.inspect(call, examples)
            amplifiers.append(ident+':'+card)
            incidences = {}
            for pin, net in bindings.items():
                incidences.setdefault(net, []).append(pin)
            if kind=='reference':
                if original['source_sha256'] != inspected['source_sha256'] or original['bindings'] != call['bindings']:
                    raise ValueError('reference certificate differs from current source')
                bias = [p for p, proof in original['visible_port_mapping'].items() if proof['role']=='bias']
            else:
                if call['family'] != 'opamp':
                    raise ValueError('known bias cohort family changed')
                bias = [p for p in call['ports'] if p in ('vb', 'vb1', 'vb2', 'vb3', 'bias')]
            for port in bias:
                net = bindings[(card, port)]
                proof = None
                if kind=='reference':
                    proof = original['visible_port_mapping'][port]
                    if not glyph.close(proof['endpoint'], inspected['external_leads'][proof['lead']]['endpoint']):
                        raise ValueError('reference certificate no longer owns actual source lead')
                elif port in inspected['cached_port_leads']:
                    index = inspected['cached_port_leads'][port]
                    proof = dict(inspected['external_leads'][index], method='declared cached port matches actual own-body SVG lead', lead=index)
                others = [p for p in incidences[net] if p!=(card, port)]
                row = dict(name=ident+':'+card+':'+port, id=ident, card=card, port=port, net=net, kind=kind,
                           source_sha256=inspected['source_sha256'], external_dut_port=net in public,
                           amp_body=inspected['body'], amp_bias_proof=proof,
                           all_declared_other_pin_incidences=others, other_pins=[])
                for other, term in others:
                    peer = dict(card=other, port=term)
                    if other.startswith('x'):
                        peer.update(call_rows[other])
                        peer['same_named_rail_bindings'] = all((card, p) in bindings and bindings[(card, p)]==n
                            for p, n in zip(peer['ports'], peer['bindings']) if p in ('vdd', 'vss'))
                        peer['other_nonrail_bindings'] = [dict(port=p, net=n, public_dut_port=n in public,
                            all_declared_incidences=incidences[n]) for p, n in zip(peer['ports'], peer['bindings'])
                            if p not in ('vdd', 'vss', term)]
                        peer['no_other_local_nonrail_connection'] = isolated(peer, public, incidences)
                    actual_bindings = {p.lower(): n.lower() for p, n in context['devices'][other]['nets'].items()}
                    if actual_bindings.get(term) != net:
                        raise ValueError('named actual source peer binding differs from declared card')
                    peer.update(peer_ink(examples, context, call_rows, other, term))
                    if proof:
                        peer.update(relation(proof['endpoint'], proof['outward_direction'], peer['endpoint'], peer.get('body')))
                        if 'lead' in peer:
                            peer['opposite_lead_directions'] = peer['lead']['outward_direction']==OPPOSITE[proof['outward_direction']]
                        ink, missing = graph.verified_segments(context['human'], net, context['ink'])
                        peer['verified_wire'] = graph.source_connection(context, ink, [proof['endpoint'], peer['endpoint']])
                        peer['cache_segments_without_ink'] = missing
                        peer['literal_net_labels'] = graph.label_evidence(context['root'], net)
                        if not peer['verified_wire']['continuous']:
                            peer['whole_ink_connection'] = graph.source_connection(context, context['ink'], [proof['endpoint'], peer['endpoint']])
                            if peer['whole_ink_connection']['continuous']:
                                raise ValueError('source-negative claim lacks a named conductor assignment')
                    row['other_pins'].append(peer)
                row['isolated_block_case'] = (not row['external_dut_port'] and len(others)==1 and others[0][0]!=card
                    and row['other_pins'][0].get('same_named_rail_bindings', False)
                    and row['other_pins'][0].get('no_other_local_nonrail_connection', False))
                if row['isolated_block_case'] and proof is None:
                    raise ValueError('admitted local block case lacks actual amplifier bias lead')
                rows.append(row)
    return dict(amplifier_names=amplifiers, rows=rows, isolated_names=sorted(r['name'] for r in rows if r['isolated_block_case']),
                unmapped_bias_names=sorted(r['name'] for r in rows if r['amp_bias_proof'] is None))


def native_rows(examples, result, directory, corpus):
    # Prove complete scored corpus coverage, source hashes and binary identity.
    audit = graph.audit(examples/'analoggenie', corpus, corpus)
    score = json.loads((corpus/'scorecard.json').read_text())
    observations = []
    for row in result['rows']:
        if row['kind']!='reference' or len(row['other_pins'])!=1:
            continue
        path = directory/(row['id']+'.json')
        if path.read_bytes() != (corpus/path.name).read_bytes():
            raise ValueError('fresh native glyph JSON differs from scored corpus')
        drawing, root = json.loads(path.read_text()), ET.parse(path.with_suffix('.svg')).getroot()
        call_rows, _, _ = calls(examples, row['id'])
        scale, offset, ink = native.frame(drawing, root)
        shapes, keys = {}, []
        targets = [(row['card'], row['port']), (row['other_pins'][0]['card'], row['other_pins'][0]['port'])]
        for card, port in targets:
            call = dict(call_rows[card], shape='triangle' if card==row['card'] else 'box', expected_marks=[],
                        missing_source_ports=[], signal_frame_mismatches=[])
            observed = native.inspect(drawing, root, call)
            device = next(d for d in drawing['devices'] if d['name']==card)
            pin = next(p for p in device['pins'] if p['term']==port)
            lead = next(p for p in observed['leads'] if p['term']==port)
            world = lambda p: [(p[i]-offset[i])/scale for i in range(2)]
            ends = [world(p) for p in native.points(ink[lead['index']])]
            matches = [i for i, p in enumerate(ends) if glyph.close(p, pin['xy'])]
            if len(matches)!=1 or len(ends)!=2:
                raise ValueError('native world pin does not own one actual lead endpoint')
            attachment = ends[1-matches[0]]
            shapes[card] = dict(body=[world(p) for p in observed['body_pixels']], endpoint=pin['xy'], attachment=attachment,
                outward_direction=glyph.direction(attachment, pin['xy']), ordered_ports=observed['ordered_ports'],
                ordered_bindings=observed['ordered_bindings'], every_pin_has_svg_lead=observed['every_pin_has_svg_lead'])
            keys.append((card, call['ports'].index(port)))
        a, b = [shapes[card] for card, _ in targets]
        components = graph.components(drawing, row['net'], keys, graph.pins(drawing))
        observations.append(dict(name=row['name'], shapes=shapes, **relation(a['endpoint'], a['outward_direction'], b['endpoint'], b['body']),
            opposite_lead_directions=b['outward_direction']==OPPOSITE[a['outward_direction']], continuous=components[keys[0]]==components[keys[1]],
            drawing_sha256=graph.digest(path), svg_sha256=graph.digest(path.with_suffix('.svg'))))
    return dict(binary_sha256=score['binary_sha256'], scorecard_sha256=graph.digest(corpus/'scorecard.json'),
                paired_names=audit['paired_names'], rows=observations)


def checks():
    peer = dict(card='x2', port='nb', ports=['vdd', 'vss', 'vb1', 'nb'], bindings=['p', 'g', 'bias', 'j'])
    incidence = dict(bias=[('x2', 'vb1')])
    assert isolated(peer, ['bias'], incidence)
    assert not isolated(peer, [], incidence)
    assert not isolated(peer, ['bias'], dict(bias=[('x2', 'vb1'), ('m1', 'g')]))
    assert not isolated(peer, ['bias'], dict(bias=[('x2', 'vb1'), ('m1', 'b')]))
    assert not isolated(peer, ['bias'], dict(bias=[('x2', 'vb1'), ('x2', 'other')]))
    assert primitive_ports(['q1', 'a', 'b', 'c', 'qnpn'], {'qnpn'}) == ['c', 'b', 'e']
    assert primitive_ports(['q1', 'a', 'b', 'c', 'bias', 'qnpn'], {'qnpn'}) == ['c', 'b', 'e', 's']
    touching = relation([0, 0], 'up', [0, 0], [[-2, -3], [2, -3], [2, -1], [-2, -1]])
    assert touching==dict(endpoint_projection=0, same_axis=True, whole_body_outward=True)
    assert not relation([0, 0], 'down', [0, -2], [[-1, -3], [1, -3], [1, -1]])['whole_body_outward']
    assert not relation([0, 0], 'up', [1, -2], [[-1, -3], [1, -3], [1, -1]])['same_axis']
    return ['isolated_public_bias_port', 'nonpublic_peer_control_rejected', 'other_gate_incidence_rejected',
            'hidden_body_incidence_rejected', 'aliased_peer_port_rejected', 'three_terminal_bjt', 'four_terminal_bjt_keeps_substrate', 'touching_leads_keep_strict_body_gap',
            'opposite_body_rejected', 'offset_column_rejected']


def named(values):
    result = {}
    for value in values:
        label, path = value.split('=', 1)
        if not label or label in result:
            raise ValueError('missing or repeated native label')
        result[label] = Path(path)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--native', action='append', default=[])
    parser.add_argument('--corpus', action='append', default=[])
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='bias-block-source-') as work:
        reports = {}
        for corpus in ('analoggenie', 'amsnet'):
            out = Path(work)/(corpus+'.json')
            subprocess.run([sys.executable, '-B', str(HERE/'biased_amplifiers.py'), str(args.examples/corpus), str(out)], check=True, capture_output=True)
            reports[corpus] = json.loads(out.read_text())
        out = Path(work)/'reference.json'
        subprocess.run([sys.executable, '-B', str(HERE/'reference_amplifiers.py'), str(args.examples), str(out)], check=True, capture_output=True)
        refs = json.loads(out.read_text())
    if refs != json.loads((HERE/'reference_amplifiers_cases.json').read_text()) or reports['amsnet']['selected']:
        raise ValueError('source cohort inventory changed')
    result = source(args.examples, reports['analoggenie'], refs)
    result.update(method_checks=checks(), source_census={c: dict(corpus_sha256=r['corpus_sha256'], drawings=r['drawings'], selected=[x['id']+':'+x['card'] for x in r['selected']]) for c, r in reports.items()},
                  limits='Future bounded relative placement study, not a production selector or transfer-function proof. Unknown source bias/VSS geometry is not fabricated. Seven isolated block cases are distinct from external bias ports, primitive networks and the extra-control separated block. Native facing may improve without matching every source port side.')
    dependencies = set(refs['audit_sha256']) | {Path(__file__).name, 'biased_amplifiers.py', 'thin_connectivity.py', 'block_aliases_native.py', 'reference_amplifiers_cases.json', 'trunk_rungs.py', 'input_resistors.py', 'input_resistor_legs.py', 'channel_bridges.py'}
    result['dependency_sha256'] = {n: graph.digest(HERE/n) for n in sorted(dependencies)}
    source_result = json.loads(json.dumps(result))
    natives, corpora = named(args.native), named(args.corpus)
    if set(natives)!=set(corpora):
        raise ValueError('every native SVG directory needs its named scored corpus')
    if natives:
        result['native'] = {name: native_rows(args.examples, result, path, corpora[name]) for name, path in sorted(natives.items())}
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    if args.check and source_result != json.loads((HERE/'bias_block_neighbors_cases.json').read_text()):
        raise ValueError('exact source evidence or named exclusions changed')
    print(json.dumps(dict(amplifiers=len(result['amplifier_names']), bias_ports=len(result['rows']),
                         isolated=result['isolated_names'], unknown=result['unmapped_bias_names']), indent=2))


if __name__ == '__main__':
    main()
