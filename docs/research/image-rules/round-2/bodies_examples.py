#!/usr/bin/env python3
"""Body-terminal research: exact card binding, actual source ink, frozen JSON.

No engine implementation. A cached B landing inside a channel polygon is
recorded separately from an actual fourth lead. Unsupported source frames
remain named unresolved rows. Run with --render DIR for independent SVG panels.
"""
import argparse
import copy
import json
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

from bodies_census import ROOT, BASE, SELECTED, parse, incidence, relation, ties, sha

HERE = Path(__file__).resolve().parent
RUN = BASE/'image-rule-round-2/bodies'
EXAMPLES = ROOT/'external/examples/analoggenie'
sys.path.insert(0, str(ROOT/'docs/research/figures'))
from cross_caps import actual_glyph, conductor_ink
from input_resistors import actual_resistor
from input_resistor_legs import verified_segments
from thin_connectivity import source_connection, junctions, actual_inductor
from converter_terminals import transformed_elements, apply, close, NUMBER


def in_polygon(p, points):
    signs = []
    for a, b in zip(points, points[1:]+points[:1]):
        cross = (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])
        if abs(cross) > 1e-5: signs.append(cross > 0)
    return bool(signs) and (all(signs) or not any(signs))


def body_geometry(root, device):
    own = actual_glyph(root, device)
    labels = [''.join(e.itertext()).strip().lower() for e in root.iter()
              if e.get('data-object-id') == 'instance-label-'+own['object']]
    if len(labels) != 1:
        raise ValueError('missing or ambiguous actual instance label: '+device['card'])
    body = device['terminals']['B']; endpoints, polygons = [], []
    for element, matrix in transformed_elements(root):
        if element.get('data-object-id') != own['object']: continue
        for child, local in transformed_elements(element, matrix):
            tag = child.tag.rsplit('}', 1)[-1]
            if tag == 'line':
                endpoints.extend(apply(local, [float(child.get(x)),float(child.get(y))])
                                 for x,y in (('x1','y1'),('x2','y2')))
            elif tag in ('polyline', 'polygon'):
                values = list(map(float,re.findall(NUMBER,child.get('points',''))))
                points = [apply(local, values[i:i+2]) for i in range(0,len(values),2)]
                if tag == 'polyline': endpoints.extend([points[0],points[-1]])
                elif child.get('fill') not in (None,'none') and in_polygon(body,points):
                    polygons.append(points)
    return dict(actual_DGS=own, actual_instance_label=labels[0], cached_name=device['name'],
                card_name=device['card'], literal_label_matches_card=labels[0]==device['card'],
                identity_basis='raw/cache binding plus unique type/origin and three actual lead endpoints; label aliases retained, not inferred', cached_B=body,
                B_is_own_lead_endpoint=any(close(body,p) for p in endpoints),
                containing_filled_polygons=polygons)


def touch(segments, point):
    return [s for s in segments if any(close(p,point) for p in s)]


def landing_status(geometry, named_touch):
    attached = geometry['B_is_own_lead_endpoint'] or bool(geometry['containing_filled_polygons'])
    return ('detached_cached_body_landing' if not attached else
            'supported_body_landing' if named_touch else 'no_named_body_ink_at_cached_landing')


def source_binding(device, pins):
    assert [device['nets'][r].lower() for r in ('D','G','S','B')] == pins


def native_binding(device, pins):
    allpins = [p['net'] for p in device['pins']]
    if 'bulk' in device: allpins.append(device['bulk'])
    allpins.extend(device.get('hidden', []))
    assert allpins == pins, (device['name'], allpins, pins)
    assert [p['term'].lower() for p in device['pins'][:3]] == ['d','g','s']
    if len(device['pins']) == 4:
        assert device['pins'][3]['term'].lower() == 'b', 'typed MOS fourth terminal role'


def source_peer(root, device, index, role):
    kind = device['card'][0]
    if kind == 'm':
        if index == 3:
            geometry = body_geometry(root,device)
            if not (geometry['B_is_own_lead_endpoint'] or geometry['containing_filled_polygons']):
                raise ValueError('body peer landing lacks own glyph support')
            return geometry['cached_B']
        return actual_glyph(root,device)['terminals'][role]
    if kind in 'rcldiv':
        keys = list(device['nets'])
        if len(keys) != 2: raise ValueError('ambiguous two-terminal schema')
        # Only the literal schemas admitted by the independent terminal study.
        schemas = [('1','2'),('P1','P2')] if kind in 'rcl' else [('+','-'),('1','2')] if kind in 'vi' else [('A','K'),('1','2')]
        matches = [s for s in schemas if set(s) == set(keys)]
        if len(matches) != 1: raise ValueError('unknown two-terminal order')
        glyph = (actual_resistor if kind == 'r' else actual_inductor if kind == 'l' else actual_glyph)(root,device)
        return glyph['terminals'][matches[0][index]]
    return None


def inspect(ident):
    paths = {k:EXAMPLES/(ident+s) for k,s in [('deck','.cir'),('source_json','.human.json'),('source_svg','.svg')]}
    paths['native_svg'] = HERE/'figures/bodies'/(ident+'.ours.svg')
    paths['native_json'] = RUN/'native'/(ident+'.json')
    assert paths['native_svg'].read_bytes() == (BASE/'gallery-preview/img'/(ident+'.ours.svg')).read_bytes()
    human = json.loads(paths['source_json'].read_text()); root = ET.parse(paths['source_svg']).getroot()
    native = json.loads(paths['native_json'].read_text()); native_by = {d['name']:d for d in native['devices']}
    drawn = {d['card']:d for d in human['devices']}; formals, rows = parse(paths['deck'].read_text())
    inc = incidence(rows); ink = conductor_ink(root); dots = dict(junctions=junctions(root))
    rails = sorted({m['net'].lower() for m in human['markers'] if m.get('net') and m.get('kind') in ('supply','ground')})
    result = []
    for row in rows:
        if row['kind'] != 'm': continue
        card, pins = row['card'],row['nets']; body = pins[3]; dev = drawn[card]; nd = native_by[card]
        source_binding(dev,pins); native_binding(nd,pins)
        item = dict(card=card, raw=row['raw'], ordered_DGSB=pins, relation=relation(pins), ties=ties(pins),
                    body_formal=body in formals, source_rail_annotation=body in rails,
                    complete_body_incidence=inc[body], native_ordered_binding='pass',
                    native_body_storage='bulk_without_xy' if 'bulk' in nd else 'class_terminal',
                    source_metadata_binding='pass')
        try:
            item['source_geometry'] = body_geometry(root,dev)
            verified, missing = verified_segments(human,body,ink)
            item['source_body_routes'] = dict(named_ink=verified, cache_without_ink=missing,
                named_ink_touching_B=touch(verified,dev['terminals']['B']),
                all_ink_touching_B=touch(ink,dev['terminals']['B']))
            paths_to_peers = []
            for peer,index,role in inc[body]:
                if peer == card and index == 3: continue
                if peer not in drawn: continue
                target = source_peer(root,drawn[peer],index,role)
                if target is None: continue
                paths_to_peers.append(dict(peer=[peer,index,role],
                    peer_point_kind='body_polygon_landing' if peer[0]=='m' and index==3 else 'actual_lead_endpoint',
                    **source_connection(dots,verified,[dev['terminals']['B'],target])))
            item['source_B_landing_paths_to_verified_peer_points'] = paths_to_peers
            item['source_status'] = landing_status(item['source_geometry'],item['source_body_routes']['named_ink_touching_B'])
        except (ValueError,KeyError,AssertionError) as error:
            item['source_status'] = 'unresolved_source_frame'
            item['source_error'] = str(error)
        nc = []
        for peer,index,role in inc[body]:
            if peer not in native_by or index >= len(native_by[peer]['pins']): continue
            pin = native_by[peer]['pins'][index]
            if pin['xy'] in native['no_connects']:
                nc.append(dict(peer=[peer,index,role],xy=pin['xy'],raw_occurrences=len(inc[body])))
        item['native_no_connects_on_body_net_visible_peers'] = nc
        result.append(item)
    return dict(id=ident, formals=formals, source_rail_nets=rails,
                files={k:dict(path=str(p.relative_to(ROOT)),sha256=sha(p)) for k,p in paths.items()}, mos=result)


def controls():
    root = ET.fromstring('''<svg><g data-object-id="literal-m1" data-symbol-id="nmos"><g>
      <polyline points="-4,-7 10,-7 10,-20"/><line x1="-9" y1="0" x2="-20" y2="0"/>
      <polyline points="-4,7 10,7 10,20"/><polygon points="-6,-12 -6,12 -3,12 -3,-12" fill="#000"/>
      </g></g><text data-object-id="instance-label-literal-m1">M1</text>
      <path data-role="conductor-ink" d="M -4 0 L 40 0"/></svg>''')
    device = dict(card='m1',name='M1',type='nmos',x=0,y=0,nets=dict(D='d',G='g',S='s',B='b'),
                  terminals=dict(D=[10,-20],G=[-20,0],S=[10,20],B=[-4,0]))
    actual = body_geometry(root,device)
    assert not actual['B_is_own_lead_endpoint'] and actual['containing_filled_polygons']
    assert touch(conductor_ink(root),device['terminals']['B'])
    altered = copy.deepcopy(device); altered['terminals']['B'] = [-4,1]
    assert not touch(conductor_ink(root),altered['terminals']['B'])
    altered = copy.deepcopy(device); altered['terminals']['D'][1] -= 1
    try: body_geometry(root,altered)
    except ValueError: pass
    else: raise AssertionError('shifted cached D survived')
    deleted = copy.deepcopy(root)
    for e in list(deleted):
        if e.get('data-role') == 'conductor-ink': deleted.remove(e)
    assert not touch(conductor_ink(deleted),device['terminals']['B'])
    renamed = copy.deepcopy(device); renamed['nets'] = dict(zip(('D','G','S','B'),('n0','n1','n2','n3')))
    assert body_geometry(root,renamed) == actual
    native = dict(name='m1',pins=[dict(term=t,net=n) for t,n in zip(('d','g','s'),('d','g','s'))],bulk='b')
    native_binding(native,['d','g','s','b'])
    rejected = []
    for mutation in ('drop_bulk','swap_G_B','swap_role'):
        wrong = copy.deepcopy(native)
        if mutation == 'drop_bulk': del wrong['bulk']
        elif mutation == 'swap_G_B': wrong['bulk'],wrong['pins'][1]['net'] = wrong['pins'][1]['net'],wrong['bulk']
        else: wrong['pins'][1]['term'] = 'b'
        try: native_binding(wrong,['d','g','s','b'])
        except AssertionError: rejected.append(mutation)
        else: raise AssertionError(('native mutation survived',mutation))
    four=copy.deepcopy(native);del four['bulk'];four['pins'].append(dict(term='g',net='b'))
    try: native_binding(four,['d','g','s','b'])
    except AssertionError: rejected.append('wrong_fourth_visible_role')
    else: raise AssertionError('fourth visible G role accepted as B')
    # Actual-source peer attack: a correct-net marker is not a body attachment.
    hp=EXAMPLES/'ag-1014.human.json'; actual_h=json.loads(hp.read_text())
    actual_r=ET.parse(EXAMPLES/'ag-1014.svg').getroot()
    moved=copy.deepcopy(next(d for d in actual_h['devices'] if d['card']=='m1'))
    moved['terminals']['B']=[60,110]
    detached=body_geometry(actual_r,moved)
    named,_=verified_segments(actual_h,'vi1',conductor_ink(actual_r))
    assert touch(named,moved['terminals']['B'])
    assert not detached['B_is_own_lead_endpoint'] and not detached['containing_filled_polygons']
    assert landing_status(detached,touch(named,moved['terminals']['B'])) == 'detached_cached_body_landing'
    return dict(literal_three_leads_and_polygon_landing=True, shifted_B_landing_loses_ink=True,
                shifted_D_cache_rejected=True, actual_conductor_deletion_detected=True,
                net_renaming_geometry_invariant=True, native_mutation_rejections=rejected,
                actual_ag1014_correct_net_marker_is_not_body_attachment=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output',type=Path); ap.add_argument('--check',type=Path); ap.add_argument('--render',type=Path)
    args=ap.parse_args(); cases=[inspect('ag-'+str(n)) for n in SELECTED]
    dependencies=[Path(__file__),HERE/'bodies_census.py']+[ROOT/'docs/research/figures'/n for n in
        ('cross_caps.py','input_resistors.py','input_resistor_legs.py','thin_connectivity.py',
         'converter_terminals.py','converter_loops.py','trunk_rungs.py','channel_bridges.py','sampling_cells.py','power_paths.py')]
    result=dict(scope='20 actually enlarged cases; all MOS rows, exact D/G/S/B binding; B landing is not a fourth glyph lead',
                cases=cases,controls=controls(),dependency_sha256={str(p.relative_to(ROOT)):sha(p) for p in dependencies},
                binary_sha256=sha(BASE/'resistor-output-integrated-common/zig-out/bin/cktimg-json'))
    if args.check: assert result == json.loads(args.check.read_text()),'named evidence or hashes changed'
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    if args.render:
        args.render=args.render.resolve()
        args.render.mkdir(parents=True,exist_ok=True)
        rendered=[]
        for row in cases:
            panels=[]
            for kind in ('source_svg','native_svg'):
                panel=args.render/(row['id']+'-'+kind+'.png')
                subprocess.run(['magick','-background','white',str(ROOT/row['files'][kind]['path']),
                                '-resize','1100x900','-gravity','center','-extent','1120x940',str(panel)],check=True)
                panels.append(panel)
            pair=args.render/(row['id']+'.png')
            subprocess.run(['magick',*map(str,panels),'+append',str(pair)],check=True)
            rendered.append(dict(id=row['id'],path=str(pair.relative_to(ROOT)),sha256=sha(pair),
                panels=[dict(path=str(p.relative_to(ROOT)),sha256=sha(p)) for p in panels]))
        (args.render/'rendered.json').write_text(json.dumps(rendered,indent=2)+'\n')
    summary={}
    for row in cases:
        summary[row['id']]={status:[m['card'] for m in row['mos'] if m['source_status']==status]
                           for status in sorted({m['source_status'] for m in row['mos']})}
    print(json.dumps(summary,indent=2))


if __name__ == '__main__': main()
