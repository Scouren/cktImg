#!/usr/bin/env python3
"""Actual native bias peers against replayed source bodies, leads and bindings.

Usage: bias_block_neighbors_native.py EXAMPLES WORK_DIR OUTPUT
       --baseline-bin BIN --candidate-bin BIN
       --baseline-corpus AG --baseline-corpus AMS
       --candidate-corpus AG --candidate-corpus AMS [--require-relative] [--check]

Complete scored corpora and executable hashes are required. Fresh SVG/JSON
pairs must match their scored JSON before own-body lead measurements. The
relative placement contract is separate from source up/down and other-port
sides. Unknown source lead geometry is retained, never inferred. This checks
default rendered classes; the public tests own caller-frame coverage. Class-local
invariance covers body outlines and external leads, not interior text or decoration.
"""
import argparse
import ast
import copy
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import bias_block_neighbors as source
import block_aliases_native as glyph
import driven_banks_native as corpus
import remaining_amplifiers_native as renderer
import thin_connectivity as graph


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = corpus.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or '').split('.')[0] + '.py'
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    return dict(sorted(found.items()))



def exits_body(body, attachment, endpoint, tolerance):
    # A convex outline's attached edge supports the whole body on one side.
    # The terminal must lie strictly on the other side; a far-edge stroke
    # through the body cannot satisfy this certificate.
    for a, b in zip(body, body[1:]+body[:1]):
        if not glyph.edge_point(attachment, a, b, tolerance):
            continue
        dx, dy = b[0]-a[0], b[1]-a[1]
        length = math.hypot(dx, dy)
        signed = lambda p: (dx*(p[1]-a[1])-dy*(p[0]-a[0]))/length
        values, tip = [signed(p) for p in body], signed(endpoint)
        if ((min(values)>=-tolerance and max(values)>tolerance and tip < -tolerance)
            or (max(values)<=tolerance and min(values)<-tolerance and tip > tolerance)):
            return True
    return False


def shape(drawing, root, call, expected):
    contract = dict(call, shape=expected, expected_marks=[], missing_source_ports=[], signal_frame_mismatches=[])
    value = glyph.inspect(drawing, root, contract)
    corpus.same(value['shape'], expected, 'actual own-body shape')
    scale, offset, ink = glyph.frame(drawing, root)
    world = lambda p: [(p[i]-offset[i])/scale for i in range(2)]
    device = next(d for d in drawing['devices'] if d['name']==call['card'])
    tolerance = glyph.PIXEL_TOLERANCE / scale
    body = [world(p) for p in value['body_pixels']]
    leads, external = {}, []
    for lead, pin in zip(value['leads'], device['pins']):
        ends = [world(p) for p in glyph.points(ink[lead['index']])]
        matches = [i for i, point in enumerate(ends) if glyph.near(point, pin['xy'], tolerance)]
        if len(ends)!=2 or len(matches)!=1:
            raise ValueError('actual ordered pin lacks one own lead endpoint')
        attachment = ends[1-matches[0]]
        if not exits_body(body, attachment, pin['xy'], tolerance):
            raise ValueError('actual own lead does not exit its attached body edge')
        leads[pin['term']] = dict(endpoint=pin['xy'], attachment=attachment,
            outward_direction=source.glyph.direction(attachment, pin['xy']), net=pin['net'])
    for index, node in enumerate(ink):
        if glyph.tag(node)!='polyline':
            continue
        points = [glyph.inverse(device, world(p)) for p in glyph.points(node)]
        if len(points)==2 and sorted(glyph.location(p, value['body_local'], tolerance) for p in points)==['boundary', 'outside']:
            external.append(index)
    corpus.same(sorted(external), sorted(lead['index'] for lead in value['leads']), 'all own-body external leads')
    return dict(body=body, leads=leads, observed=value)


def relative(a, a_port, b, b_port):
    first, second = a['leads'][a_port], b['leads'][b_port]
    result = source.relation(first['endpoint'], first['outward_direction'], second['endpoint'], b['body'])
    result['opposite_lead_directions'] = second['outward_direction']==source.OPPOSITE[first['outward_direction']]
    result['relative_contract'] = (result['endpoint_projection']>=0 and result['same_axis']
                                   and result['whole_body_outward'] and result['opposite_lead_directions'])
    return result


def observe(drawing, root, row, calls):
    peer = row['other_pins'][0]
    a = shape(drawing, root, calls[row['card']], 'triangle')
    b = shape(drawing, root, calls[peer['card']], 'box')
    keys = [(row['card'], calls[row['card']]['ports'].index(row['port'])),
            (peer['card'], calls[peer['card']]['ports'].index(peer['port']))]
    pins = graph.pins(drawing)
    if any(pins[key][0]!=row['net'] for key in keys):
        raise ValueError('selected actual bias pins do not retain their declared common net')
    connected = graph.components(drawing, row['net'], keys, pins)
    side_mismatches = []
    for label, native, originals in (
        ('amplifier', a, {row['port']: row['amp_bias_proof']}),
        ('peer', b, peer['visible_named_leads'])):
        for port, proof in originals.items():
            if native['leads'][port]['outward_direction']!=proof['outward_direction']:
                side_mismatches.append(label+':'+port)
    return dict(amplifier=a, peer=b, **relative(a, row['port'], b, peer['port']),
                continuous=connected[keys[0]]==connected[keys[1]], source_side_mismatches=side_mismatches,
                unknown_source_peer_geometry=peer['unknown_geometry'])


def same_class(a, b):
    """SVG serialization accuracy bounds this local-frame comparison."""
    aa, bb = a['observed'], b['observed']
    tolerance = glyph.PIXEL_TOLERANCE * (1/aa['display_scale'] + 1/bb['display_scale'])
    if len(aa['body_local'])!=len(bb['body_local']) or len(aa['leads'])!=len(bb['leads']):
        return False
    if not all(glyph.near(p, q, tolerance) for p, q in zip(aa['body_local'], bb['body_local'])):
        return False
    return all(x['term']==y['term'] and x['net']==y['net']
               and all(glyph.near(x[k], y[k], tolerance) for k in ('endpoint', 'attachment'))
               for x, y in zip(aa['leads'], bb['leads']))


def methods():
    drawing = dict(devices=[
        dict(name='x1', pos=[0, 0], rot=0, mirror=False, **{'class':'untrusted'}, pins=[
            dict(term='vref', net='ref', xy=[-60, 0]), dict(term='nb', net='bias', xy=[0, 60]), dict(term='out', net='out', xy=[60, 0])]),
        dict(name='x2', pos=[0, 160], rot=0, mirror=False, **{'class':'untrusted'}, pins=[
            dict(term='nb', net='bias', xy=[0, 100]), dict(term='vdd', net='p', xy=[-60, 160]), dict(term='vss', net='g', xy=[60, 160])])],
        wires=[dict(net='frame', segments=[[[-100, -100], [-100, 240], [100, 240]]]),
               dict(net='bias', segments=[[[0, 60], [0, 100]]])], junctions=[])
    root = ET.fromstring('''<svg viewBox="-110 -110 220 360"><g>
      <polyline points="-100,-100 -100,240 100,240"/><polyline points="0,60 0,100"/>
      <polyline points="-40,-40 40,0 -40,40 -40,-40"/><polyline points="-60,0 -40,0"/>
      <polyline points="0,60 0,20"/><polyline points="40,0 60,0"/>
      <polyline points="-40,120 40,120 40,200 -40,200 -40,120"/><polyline points="0,100 0,120"/>
      <polyline points="-60,160 -40,160"/><polyline points="40,160 60,160"/>
      </g><text x="50" y="-30" font-size="11">x1</text><text x="50" y="130" font-size="11">x2</text></svg>''')
    calls = dict(x1=dict(card='x1', family='aea', ports=['vref','nb','out'], bindings=['ref','bias','out']),
                 x2=dict(card='x2', family='bias_circuit', ports=['nb','vdd','vss'], bindings=['bias','p','g']))
    row = dict(card='x1', port='nb', net='bias', amp_bias_proof=dict(outward_direction='down'), other_pins=[
        dict(card='x2', port='nb', visible_named_leads={'nb':dict(outward_direction='up')}, unknown_geometry=['vss'])])
    value = observe(drawing, root, row, calls)
    assert value['relative_contract'] and value['continuous'] and not value['source_side_mismatches']
    assert value['unknown_source_peer_geometry']==['vss']
    names = ['actual_own_body_leads_bindings_and_bias_ink']
    reversed_root = copy.deepcopy(root)
    reversed_root[0][6].set('points', ' '.join(reversed(reversed_root[0][6].get('points').split())))
    assert observe(drawing, reversed_root, row, calls)['relative_contract']
    names.append('body_winding_does_not_change_outward_lead_certificate')
    for name, mutate in (
        ('wrong_bias_binding', lambda d, r: d['devices'][1]['pins'][0].update(net='wrong')),
        ('wrong_other_port_binding', lambda d, r: d['devices'][1]['pins'][1].update(net='wrong')),
        ('reordered_ports', lambda d, r: d['devices'][1]['pins'].reverse()),
        ('missing_own_lead', lambda d, r: r[0].remove(r[0][7])),
        ('lead_crosses_own_body', lambda d, r: r[0][7].set('points', '0,100 0,200')),
        ('orphan_body_lead', lambda d, r: r[0].append(ET.fromstring('<polyline points="10,100 10,120"/>')))):
        d, r = copy.deepcopy(drawing), copy.deepcopy(root)
        mutate(d, r)
        try:
            observe(d, r, row, calls)
        except ValueError:
            names.append(name+'_rejected')
        else:
            raise ValueError('literal mutation accepted: '+name)
    a, b = value['amplifier'], value['peer']
    for name, mutate in (
        ('off_axis', lambda s: s['leads']['nb']['endpoint'].__setitem__(0, 1)),
        ('negative_gap', lambda s: s['leads']['nb']['endpoint'].__setitem__(1, 59)),
        ('same_facing', lambda s: s['leads']['nb'].update(outward_direction='down')),
        ('body_not_strictly_outward', lambda s: s['body'][0].__setitem__(1, 60))):
        changed = copy.deepcopy(b)
        mutate(changed)
        assert not relative(a, 'nb', changed, 'nb')['relative_contract'], name
        names.append(name+'_rejected')
    touching = copy.deepcopy(b)
    touching['leads']['nb']['endpoint'] = [0, 60]
    assert relative(a, 'nb', touching, 'nb')['relative_contract']
    names.append('zero_gap_is_permitted')
    names.extend('native_ink_'+name for name in graph.method_checks())
    return names


def frozen(result):
    encoded = json.dumps(result, sort_keys=True, separators=(',', ':')).encode()
    return dict(evidence_sha256=hashlib.sha256(encoded).hexdigest(),
                source_inventory_sha256=result['source_inventory_sha256'], dependency_sha256=result['dependency_sha256'],
                method_checks=result['method_checks'], selected_names=result['selected_names'], summaries=result['summaries'],
                changes=result['changes'], binary_sha256={k:[c['binary_sha256'] for c in v] for k,v in result['corpora'].items()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('examples', 'work_dir', 'output'):
        parser.add_argument(name, type=Path)
    for stage in ('baseline', 'candidate'):
        parser.add_argument('--'+stage+'-bin', type=Path, required=True)
        parser.add_argument('--'+stage+'-corpus', type=Path, action='append', required=True)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--require-relative', action='store_true')
    args = parser.parse_args()
    args.work_dir.mkdir(parents=True, exist_ok=True)
    checked = methods()
    source_path = args.work_dir / 'source.json'
    subprocess.run([sys.executable, '-B', str(HERE/'bias_block_neighbors.py'), str(args.examples), str(source_path), '--check'], check=True, capture_output=True)
    evidence = json.loads(source_path.read_text())
    rows = [r for r in evidence['rows'] if r['kind']=='reference' and len(r['other_pins'])==1]
    corpora, observations = {}, {}
    for stage in ('baseline', 'candidate'):
        binary = getattr(args, stage+'_bin')
        directory = args.work_dir / stage
        directory.mkdir(exist_ok=True)
        dirs, snapshots = {}, []
        for path in getattr(args, stage+'_corpus'):
            ids = json.loads((path/'scorecard.json').read_text())['ids']
            name = 'analoggenie' if all(i.startswith('ag-') for i in ids) else 'amsnet'
            if name in dirs:
                raise ValueError('repeated scored corpus')
            dirs[name] = path
            snapshots.append(corpus.corpus(args.examples/name, path, binary))
        corpus.same(sorted(dirs), ['amsnet', 'analoggenie'], 'both complete native corpora')
        corpora[stage] = sorted(snapshots, key=lambda r:r['corpus'])
        for ident in sorted({r['id'] for r in rows}):
            renderer.render(binary, args.examples/'analoggenie'/(ident+'.cir'), directory/ident)
            corpus.same((directory/(ident+'.json')).read_bytes(), (dirs['analoggenie']/(ident+'.json')).read_bytes(), 'fresh SVG-associated JSON '+ident)
        values = []
        for row in rows:
            path = directory/(row['id']+'.json')
            calls, _, _ = source.calls(args.examples, row['id'])
            value = observe(json.loads(path.read_text()), ET.parse(path.with_suffix('.svg')).getroot(), row, calls)
            values.append(dict(name=row['name'], selected=row['isolated_block_case'], source=row, **value,
                               json_sha256=corpus.digest(path), svg_sha256=corpus.digest(path.with_suffix('.svg'))))
        observations[stage] = values
    changes = dict(drawings=[], reports=[])
    for a, b in zip(corpora['baseline'], corpora['candidate']):
        corpus.same(a['corpus'], b['corpus'], 'paired corpus')
        corpus.same(a['inputs'], b['inputs'], 'paired scored inputs')
        for old, new in zip(a['rows'], b['rows']):
            corpus.same(old['id'], new['id'], 'paired source')
            for key in ('deck_sha256', 'source_sha256', 'preview_sha256'):
                corpus.same(old[key], new[key], 'paired source content')
            for label, key in (('drawings','geometry_sha256'), ('reports','report_sha256')):
                if old[key]!=new[key]:
                    changes[label].append(old['id'])
    local_changes = []
    for old, new in zip(observations['baseline'], observations['candidate']):
        corpus.same(old['name'], new['name'], 'paired native bias observation')
        for part in ('amplifier', 'peer'):
            if not same_class(old[part], new[part]):
                local_changes.append(old['name']+':'+part)
    summaries = {}
    for stage, values in observations.items():
        selected = [r for r in values if r['selected']]
        summaries[stage] = {key:[r['name'] for r in selected if r[key]] for key in
            ('whole_body_outward','same_axis','opposite_lead_directions','relative_contract','continuous')}
        summaries[stage]['side_mismatches'] = [r['name']+':'+p for r in values for p in r['source_side_mismatches']]
        summaries[stage]['excluded'] = [dict(name=r['name'], relative_contract=r['relative_contract'], continuous=r['continuous']) for r in values if not r['selected']]
    result = dict(source_inventory_sha256=corpus.digest(HERE/'bias_block_neighbors_cases.json'), dependency_sha256=dependencies(),
                  method_checks=checked, selected_names=evidence['isolated_names'], corpora=corpora, observations=observations,
                  summaries=summaries, changes={**{k:sorted(v) for k,v in changes.items()}, 'local_class_geometry':local_changes},
                  limits='Default actual rendered body/lead relative placement and complete bindings. Class-local invariance covers body outlines and external leads, not interior text or decoration. Source up/down and every visible peer-port side remain separate measured mismatches. Unknown source geometry stays unknown. Full changed-net physical connectivity and prior-cohort preservation are separate gates; no whole-drawing equivalence claim.')
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    if args.require_relative:
        for field in ('relative_contract', 'continuous'):
            corpus.same(sorted(summaries['candidate'][field]), evidence['isolated_names'], 'complete selected '+field)
        corpus.same(local_changes, [], 'unchanged class-local geometry and bindings')
    if args.check:
        corpus.same(frozen(result), json.loads((HERE/'bias_block_neighbors_native_cases.json').read_text()), 'every frozen native bias field')
    print(json.dumps(dict(summaries=summaries, changes=result['changes']), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
