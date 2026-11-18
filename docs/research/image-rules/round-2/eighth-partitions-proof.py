#!/usr/bin/env python3
"""Replay source partitions and test complete physical-part/name obligations."""
import argparse
import collections
import copy
import importlib.util
import itertools
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0,str(HERE.parent))
sys.path.insert(0,str(HERE.parents[1]/'figures'))
import grouping_evidence as previous
import thin_connectivity as ink
spec = importlib.util.spec_from_file_location('part_fixtures',HERE/'eighth-partitions-fixtures.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)
sha = fixtures.sha


def canonical(blocks):
    return sorted([sorted(block) for block in blocks])


def partition(keys, pairs, field):
    keys = [tuple(k) for k in keys]
    parent = {k:k for k in keys}
    def root(k):
        while parent[k] != k:
            k = parent[k]
        return k
    for row in pairs:
        a,b = map(tuple,row['pins'])
        if row[field]:
            parent[root(a)] = root(b)
    assert len(pairs) == len(keys)*(len(keys)-1)//2
    for row in pairs:
        a,b = map(tuple,row['pins'])
        assert (root(a)==root(b)) == row[field], 'inconsistent pair equivalence'
    blocks = collections.defaultdict(list)
    for k in keys:
        blocks[root(k)].append(f'{k[0]}.{k[1]}')
    return canonical(blocks.values())


def exported_markers(drawing, raw_names):
    result = [dict(identity='label:'+str(i),kind='label',net=l['net'],at=l['at']) for i,l in enumerate(drawing['labels'])]
    for d in drawing['devices']:
        if d['name'] in raw_names:
            continue
        assert d['class'] in ('gnd','vdd','ipin','opin'), ('unsupported marker class',d)
        assert len(d['pins']) == 1
        p = d['pins'][0]
        result.append(dict(identity=d['name'],kind=d['class'],net=p['net'],at=p['xy']))
    return result


def native_contract(drawing, net, pins, expected=None):
    """All actual exported route components, raw pins and reachable markers.

    Exported marker binding is checked here; SVG visibility and host round trip
    are separate future gates. Labels never union the physical components.
    """
    selected = {k:v for k,v in pins.items() if v[0] == net}
    assert selected
    markers = exported_markers(drawing,{k[0] for k in pins})
    # Markers must never become graph vertices: an undotted proper X has
    # two components even when a text anchor sits exactly at its crossing.
    all_points = dict(selected)
    segments = list(ink.segments(drawing,net))
    for i,(a,b) in enumerate(segments):
        for end,point in enumerate((a,b)):
            key = ('@stroke',2*i+end)
            assert key not in all_points
            all_points[key] = (net,tuple(point),'stroke')
    connected = ink.components(drawing,net,list(all_points),all_points)
    roots = collections.defaultdict(list)
    for k in selected:
        roots[connected[k]].append(f'{k[0]}.{k[1]}')
    blocks = canonical(roots.values())
    if expected is not None:
        assert canonical(expected) == blocks, ('physical partition changed',net,expected,blocks)
    named = {r:[] for r in roots}
    for i,m in enumerate(markers):
        touching = {connected[k] for k,v in selected.items() if tuple(m['at'])==v[1]}
        for s,(a,b) in enumerate(segments):
            if ink.on(m['at'],a,b):
                touching.add(connected['@stroke',2*s])
        assert len(touching)<=1, ('marker touches unjoined components',net,m,sorted(touching))
        root = next(iter(touching),None)
        if root in roots:
            assert m['net'] == net, ('conflicting reachable marker',net,m)
            named[root].append(m)
        elif m['net'] == net:
            raise AssertionError(('detached bound marker',net,m))
    if len(blocks) > 1:
        assert all(named.values()), ('unnamed physical component',net,roots,named)
    return dict(net=net,blocks=blocks,components=[dict(pins=sorted(roots[r]),markers=named[r]) for r in sorted(roots)],
                exported_marker_scope='All exported labels and generated terminal records; actual source text attachment is separate.')


def literal_controls():
    pins = {('a',0):('n',(0,0),'a'),('b',0):('n',(10,0),'a'),
            ('c',0):('n',(0,20),'a'),('d',0):('n',(10,20),'a')}
    d = dict(devices=[],wires=[dict(net='n',segments=[[[0,0],[10,0]],[[0,20],[10,20]]])],
             junctions=[],labels=[dict(net='n',at=[10,0]),dict(net='n',at=[10,20])])
    expected = [['a.0','b.0'],['c.0','d.0']]
    native_contract(d,'n',pins,expected)
    tests = []
    def rejected(name, change, change_pins=None, change_expected=None):
        m,p,e = copy.deepcopy(d),copy.deepcopy(pins),copy.deepcopy(expected)
        change(m)
        if change_pins:
            change_pins(p)
        if change_expected:
            change_expected(e)
        try:
            native_contract(m,'n',p,e)
        except AssertionError:
            tests.append(name)
        else:
            raise AssertionError(('mutation passed',name))
    rejected('missing_name_on_one_piece',lambda m:m['labels'].pop())
    rejected('wrong_reachable_name',lambda m:m['labels'][0].update(net='other'))
    rejected('extra_conflicting_marker_beside_correct_marker',lambda m:m['labels'].append(dict(net='other',at=[5,0])))
    rejected('detached_name',lambda m:m['labels'][0].update(at=[11,1]))
    rejected('same_net_bridge_joins_forbidden_pieces',lambda m:m['wires'][0]['segments'].append([[5,0],[5,20]]))
    rejected('lost_local_join',lambda m:m['wires'][0].update(segments=[[[0,0],[4,0]],[[6,0],[10,0]],[[0,20],[10,20]]]))
    rejected('omitted_terminal_from_expected_partition',lambda m:None,change_expected=lambda e:e[0].pop())
    rejected('duplicated_terminal_in_expected_partition',lambda m:None,change_expected=lambda e:e[1].append('a.0'))
    rejected('changed_raw_binding',lambda m:None,change_pins=lambda p:p.__setitem__(('b',0),('other',(10,0),'a')))
    rejected('extra_raw_terminal_not_covered',lambda m:None,change_pins=lambda p:p.__setitem__(('e',0),('n',(5,0),'a')))
    renamed = copy.deepcopy(d)
    for w in renamed['wires']:
        w['net']='renamed'
    for label in renamed['labels']:
        label['net']='renamed'
    renamed_pins = {('r'+k[0],k[1]):('renamed',v[1],v[2]) for k,v in pins.items()}
    native_contract(renamed,'renamed',renamed_pins,[[f'r{x}' for x in block] for block in expected])
    tests.append('net_and_device_rename_covariance')
    shuffled = copy.deepcopy(d)
    shuffled['wires'][0]['segments'] = [list(reversed(s)) for s in reversed(shuffled['wires'][0]['segments'])]
    shuffled['labels'].reverse()
    native_contract(shuffled,'n',pins,expected)
    tests.append('route_order_direction_and_marker_order_invariance')
    x = dict(devices=[],wires=[dict(net='n',segments=[[[-10,0],[10,0]],[[0,-10],[0,10]]])],
             junctions=[],labels=[dict(net='n',at=[10,0]),dict(net='n',at=[0,10])])
    x_pins = {('a',0):('n',(-10,0),'a'),('b',0):('n',(10,0),'a'),
              ('c',0):('n',(0,-10),'a'),('d',0):('n',(0,10),'a')}
    native_contract(x,'n',x_pins,expected)
    x['labels'].append(dict(net='n',at=[0,0]))
    try:
        native_contract(x,'n',x_pins)
    except AssertionError as e:
        assert e.args[0][0]=='marker touches unjoined components'
    else:
        raise AssertionError('a label joined undotted physical crossing')
    tests.append('undotted_X_marker_ambiguity_rejected_without_union')
    x['junctions']=[[0,0]]
    native_contract(x,'n',x_pins,[['a.0','b.0','c.0','d.0']])
    tests.append('actual_dot_joins_X_before_marker_attachment')
    return tests


def source_extra(row, drawing):
    ident = 'ag-'+str(row['source_id'])
    context = ink.load_source(ROOT/'external/examples/analoggenie',ident)
    ps = ink.pins(drawing)
    records = []
    for net in sorted({p[0] for p in ps.values()}):
        keys = sorted(k for k in ps if ps[k][0]==net)
        components = ink.components(drawing,net,keys,ps)
        for a,b in itertools.combinations(keys,2):
            obs = ink.source(context,dict(net=net,pins=[a,b],terms=[ps[a][2],ps[b][2]]))
            records.append(dict(net=net,pins=[a,b],native_connected=components[a]==components[b],source=obs))
    return dict(id=ident,source_sha256=context['source_sha256'],pairs=records,
                counts=dict(collections.Counter(p['source']['status'] for p in records)))


def marker_review():
    path = ROOT/'.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/root-partition-review/label-crossing-before.json'
    before = json.loads(path.read_text())
    snapshot = ROOT/before['script']
    assert sha(snapshot)==before['sha256']
    # The retained function body runs unchanged, with its original imports
    # resolved from the research directory instead of the archive directory.
    namespace = dict(__name__='retained_before',__file__=str(Path(__file__)))
    exec(compile(snapshot.read_text(),str(snapshot),'exec'),namespace)
    literal = before['literal']
    ps = {(name.split('.')[0],int(name.split('.')[1])):('n',tuple(xy),'a') for name,xy in literal['pins'].items()}
    d = dict(devices=[],wires=[dict(net='n',segments=literal['wires'])],junctions=literal['junctions'],
             labels=[dict(net='n',at=xy) for xy in literal['original_markers']])
    old = namespace['native_contract']
    assert old(d,'n',ps)['blocks']==before['observed_before']
    d['labels'].append(dict(net='n',at=literal['added_marker']))
    assert old(d,'n',ps)['blocks']==before['observed_after_added_label']
    try:
        native_contract(d,'n',ps)
    except AssertionError as error:
        assert error.args[0][0]=='marker touches unjoined components'
    else:
        raise AssertionError('reviewed crossing marker accepted')
    return dict(before_evidence=str(path.relative_to(ROOT)),before_sha256=sha(path),old_script_sha256=sha(snapshot),
                old_merges_without_ink_change=True,repaired_declines_ambiguous_attachment=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output',type=Path,default=HERE/'eighth-partitions-proof.json')
    ap.add_argument('--check',type=Path)
    args = ap.parse_args()
    old_path = HERE.parent/'figures/grouping-evidence.json'
    old = json.loads(old_path.read_text())
    replay = previous.audit(ROOT/'external/examples/analoggenie',HERE.parent/'figures/grouping')
    assert json.loads(json.dumps(replay)) == old
    manifest_path = HERE/'eighth-partitions-fixtures.json'
    manifest = json.loads(manifest_path.read_text())
    assert sha(ROOT/manifest['binary']) == manifest['binary_sha256']
    rows = {r['name']:r for r in manifest['runs']}
    records = []
    native = {}
    for name,row in rows.items():
        deck = ROOT/row['deck']
        assert sha(deck)==row['deck_sha256']
        defs,cards = fixtures.cards(deck.read_text())
        for out in row['outputs'].values():
            assert sha(ROOT/out['path'])==out['sha256']
        d = json.loads((ROOT/row['outputs']['.json']['path']).read_text())
        assert fixtures.bindings(d,defs,cards) == row['complete_bindings']
        assert json.loads((ROOT/row['outputs']['.report.json']['path']).read_text()) == row['report']
        ps = ink.pins(d)
        parts = [native_contract(d,net,ps) for net in sorted({p[0] for p in ps.values()})]
        native[name] = d
        records.append(dict(name=name,partitions=parts,requests=row['report']['requests']))
    sources = []
    for ident,c in old['cases'].items():
        owner = {n:i for i,r in enumerate(c['regions']) for n in r['members']}
        nets = []
        for net,n in c['nets'].items():
            source = partition(n['pins'],n['pairs'],'source_connected')
            actual = partition(n['pins'],n['pairs'],'native_connected')
            owner_blocks = collections.defaultdict(list)
            for device,index in n['pins']:
                owner_blocks[owner[device]].append(f'{device}.{index}')
            owner_joins = [dict(net=net,pins=p['pins'],would_join=owner[p['pins'][0][0]]==owner[p['pins'][1][0]],
                               source_connected=p['source_connected']) for p in n['pairs']
                           if (owner[p['pins'][0][0]]==owner[p['pins'][1][0]])!=p['source_connected']]
            nets.append(dict(net=net,source=source,native=actual,owner_only=canonical(owner_blocks.values()),
                             owner_only_mismatches=owner_joins,source_literal_labels=n['literal_svg_labels']))
        sources.append(dict(id=ident,partitions=nets,owner_only_mismatch_count=sum(len(n['owner_only_mismatches']) for n in nets),
                            source_native_mismatches=len(c['physical_mismatches']),complete_visible_pairs=sum(len(n['pairs']) for n in c['nets'].values())))
    extras = [source_extra(rows[name],native[name]) for name in ('921-base','1479-base')]
    assert extras[0]['counts'] == {'source_connected':19,'source_disconnected':12}
    assert extras[1]['counts'] == {'source_connected':8,'source_disconnected':1,'unsupported':9}
    expected_sizes = {'1080-base':{'net0':[1,1,1],'fn1':[1,1,1],'vdd':[13]},
                      '1080-wire-net0':{'net0':[3]},'1080-wire-fn1':{'fn1':[3]},'1080-label-fn1':{'fn1':[1,1,1]},
                      '1080-rail-each':{'vdd':[1]*13},'1080-rail-bar':{'vdd':[13]},
                      '928-base':{'vbias':[2]},'928-label-vbias':{'vbias':[1,1]},'928-wire-vbias':{'vbias':[2]}}
    for name,nets in expected_sizes.items():
        for net,sizes in nets.items():
            parts = next(p for r in records if r['name']==name for p in r['partitions'] if p['net']==net)
            assert sorted(map(len,parts['blocks']))==sizes,(name,net,parts)
    for row in rows.values():
        if row['hint']:
            request = next(q for q in row['report']['requests'] if q['text']==row['hint'].lower())
            assert (request['state'],request['code'])==('honoured','ok')
    # Whole-net choices cannot express the actual FN1 2+1 partition.
    fn1 = next(n for s in sources if s['id']=='ag-1080' for n in s['partitions'] if n['net']=='fn1')['source']
    assert sorted(map(len,fn1))==[1,2]
    assert all(fn1!=next(p for r in records if r['name']==name for p in r['partitions'] if p['net']=='fn1')['blocks']
               for name in ('1080-base','1080-wire-fn1','1080-label-fn1'))
    controls = literal_controls()
    view_path = HERE/'eighth-partitions-views.json'
    views = json.loads(view_path.read_text())
    for view in views:
        if 'files' in view:
            assert sha(ROOT/view['pair']) == view['pair_sha256']
            for panel in view['files']:
                assert sha(ROOT/panel['path']) == panel['sha256']
                assert sha(ROOT/panel['png']) == panel['png_sha256']
        else:
            assert sha(ROOT/view['path']) == view['sha256']
            assert sha(ROOT/view['svg']['path']) == view['svg']['sha256']
        assert view['actual_view']
    dependencies = {}
    for name in ('wire_parts','wires','netlines','thin','sketch','dots','wire_requests','ct_four_wires','resistor_downstream','power_loop_wires'):
        for base in (ROOT,fixtures.BINARY.parents[2]):
            path = base/'src'/(name+'.zig')
            if path.exists():
                dependencies[str(path.relative_to(ROOT))] = sha(path)
    out = dict(scope='Four source/native cases, two retained exhaustive partition certificates, scoped new controls; no selector or engine implementation.',
               script_sha256=sha(Path(__file__)),fixture_manifest_sha256=sha(manifest_path),previous_evidence_sha256=sha(old_path),
               viewed_artifacts=views,view_ledger_sha256=sha(view_path),current_and_frozen_code=dependencies,
               independent_marker_review=marker_review(),
               source_partitions=sources,new_source_pair_checks=extras,native_runs=records,literal_controls=controls,
               caller_partition_sizes=expected_sizes,
               limits=['Actual source free-label attachment is not proved by literal text alone.',
                       'AG1479 has nine unresolved source pairs touching X1; all complete raw/native bindings are retained.',
                       'Native marker checks bind exported JSON anchors, not a new SVG/host round-trip certificate.',
                       'Owner-only partitions are rejected hypotheses, not implemented defaults.'])
    out = json.loads(json.dumps(out))
    if args.check:
        assert json.loads(args.check.read_text())==out
    args.output.write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(runs=len(records),old_pairs=268,new_source_pairs=49,unsupported_source_pairs=9,
                         owner_only_mismatches={s['id']:s['owner_only_mismatch_count'] for s in sources},controls=len(controls))))


if __name__=='__main__':
    main()
