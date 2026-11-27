#!/usr/bin/env python3
"""Named actual leads of the source DA/PA boxes, without inferring a glyph.

Usage: paired_amplifier_ports.py EXAMPLES OUTPUT [--check]

The complete corpus selects three calls. Their own attached SVG leads must
match the declared, named source terminals one-to-one. VSS has no source
geometry and remains unknown. This certificate does not assign amplifier
semantics, infer a triangle, or connect equal net labels physically.
"""
import argparse
import copy
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import remaining_amplifiers as remaining

EXPECTED = ['ag-1103:x1', 'ag-1103:x2', 'ag-1103:x3']
PORTS = dict(da='vss vb inp inn outp outn src'.split(),
             pa='vdd vss vb inp inn outp outn src'.split())


def certificate(row):
    """Certify visible identity against actual attached ink, never ordering."""
    required = PORTS.get(row['family'])
    if required is None or sorted(row['ports']) != sorted(required):
        raise ValueError('unobserved complete DA/PA contract')
    if len(row['bindings']) != len(required):
        raise ValueError('incomplete declared call')
    declared = dict(zip(row['ports'], row['bindings']))
    if row['declared_bindings'] != declared:
        raise ValueError('declared call changed')
    visible = set(required) - {'vss'}
    body, leads = row['body'], row['external_leads']
    if (row['shape'] != 'box' or row['triangle'] is not None or row['source_marks']
            or len(body) != 4 or len(leads) != len(visible)
            or row['absent_cached_ports'] != ['vss']
            or row['cached_frame_mismatches'] or set(row['cached_terminals']) != visible):
        raise ValueError('incomplete actual rectangular source frame')
    xs, ys = {p[0] for p in body}, {p[1] for p in body}
    if (len(xs) != 2 or len(ys) != 2
            or {tuple(p) for p in body} != {(x, y) for x in xs for y in ys}):
        raise ValueError('source body is not a rectangle')
    mapping = {}
    used = set()
    for port in sorted(visible):
        at = row['cached_terminals'][port]
        matches = [i for i, lead in enumerate(leads)
                   if remaining.glyph.close(at, lead['endpoint'])]
        if len(matches) != 1 or matches[0] in used:
            raise ValueError('named source terminal lacks a unique own lead')
        i = matches[0]
        lead = leads[i]
        attach, endpoint = lead['attachment'], lead['endpoint']
        if (not any(remaining.aliases.on_segment(attach, a, b)
                    for a, b in zip(body, body[1:] + body[:1]))
                or min(xs) <= endpoint[0] <= max(xs) and min(ys) <= endpoint[1] <= max(ys)
                or lead['path'][0] != attach or lead['path'][-1] != endpoint):
            raise ValueError('lead is detached or has no external endpoint')
        used.add(i)
        mapping[port] = dict(endpoint=endpoint, attachment=attach, path=lead['path'],
                             net=declared[port], method='declared named port matches its own attached SVG lead')
    return dict(id=row['id'], card=row['card'], family=row['family'], ports=row['ports'],
                bindings=row['bindings'], source_object=row['source_object'],
                source_sha256=row['source_sha256'], body=body,
                visible_port_mapping=mapping, missing_geometry=['vss'])


def checks(rows):
    """Literal points and mutations independently reject incomplete evidence."""
    expected = {
        'x1': dict(vb=[400, -20], inp=[340, 30], inn=[340, 70], outp=[460, 30], outn=[460, 70], src=[400, 120]),
        'x2': dict(vdd=[130, 220], vb=[170, 220], inp=[90, 270], inn=[90, 310], outp=[210, 270], outn=[210, 310], src=[150, 360]),
        'x3': dict(vdd=[540, 220], vb=[500, 220], inp=[580, 270], inn=[580, 310], outp=[460, 270], outn=[460, 310], src=[520, 360]),
    }
    for row in rows:
        observed = certificate(row)
        points = {p: list(proof['endpoint']) for p, proof in observed['visible_port_mapping'].items()}
        if points != expected[row['card']]:
            raise ValueError('literal actual source coordinates changed')
    methods = ['twenty_literal_named_actual_endpoints', 'horizontal_reflection_keeps_named_input_identity']
    row = rows[0]
    variants = []
    for name, field, value in (
        ('unknown_family', 'family', 'DA_extra'),
        ('missing_vss_not_synthesized', 'absent_cached_ports', []),
        ('triangle_not_a_box', 'shape', 'triangle'),
        ('unmatched_terminal', 'cached_frame_mismatches', ['inp']),
        ('wrong_declared_binding', 'bindings', ['wrong'] + row['bindings'][1:])):
        changed = copy.deepcopy(row)
        changed[field] = value
        variants.append((name, changed))
    changed = copy.deepcopy(row)
    changed['external_leads'].pop()
    variants.append(('missing_own_lead', changed))
    changed = copy.deepcopy(row)
    changed['cached_terminals']['inp'] = changed['cached_terminals']['inn']
    variants.append(('two_named_ports_cannot_share_a_lead', changed))
    changed = copy.deepcopy(row)
    changed['external_leads'][0]['attachment'] = [12345, 12345]
    variants.append(('detached_body_attachment', changed))
    changed = copy.deepcopy(row)
    changed['external_leads'][0]['path'] = [[1, 2], changed['external_leads'][0]['endpoint']]
    variants.append(('disconnected_lead_path', changed))
    for name, changed in variants:
        try:
            certificate(changed)
        except ValueError:
            methods.append(name + '_rejected')
        else:
            raise ValueError('source certificate accepted ' + name)
    return methods


def replay(examples):
    unknown, _, counts, hashes = remaining.census.scan(examples)
    selected = [r for r in unknown if r['family'] in PORTS]
    if [r['id'] + ':' + r['card'] for r in selected] != EXPECTED:
        raise ValueError('exact DA/PA source inventory changed')
    rows = [remaining.inspect(row, examples) for row in selected]
    return dict(names=EXPECTED, corpus_counts=counts, corpus_sha256=hashes,
                method_checks=checks(rows), rows=[certificate(row) for row in rows])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = json.loads(json.dumps(replay(args.examples)))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if args.check and result != json.loads((HERE/'paired_amplifier_ports_cases.json').read_text()):
        raise ValueError('source certificate differs from frozen inventory')
    print(json.dumps(dict(names=result['names'], method_checks=result['method_checks'])))


if __name__ == '__main__':
    main()
