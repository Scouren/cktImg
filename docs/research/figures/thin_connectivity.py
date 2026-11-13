#!/usr/bin/env python3
"""Named physical pin-pair transitions, verified against actual source ink.

Usage: thin_connectivity.py <examples-root> <output.json>
       --baseline <label> --candidate <label> --native-root <directory> [--check]

Only stable named device/card-pin identities on the same net are compared.
Endpoint/T/overlap and explicit native junctions connect; labels never do.
Source leads and named-net paths require actual SVG support. Every negative
source claim also checks ALL actual conductor ink, without net assignments.
This is a bounded manual research gate, not an electrical round-trip oracle.
"""
import argparse
import collections
import copy
import hashlib
import itertools
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from trunk_rungs import pins, segments
from cross_caps import actual_glyph, conductor_ink
from input_resistors import actual_resistor
from input_resistor_legs import verified_segments, connection
from channel_bridges import read_cards
from converter_terminals import transformed_elements, apply, glyphs as path_glyphs, close


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def on(p,a,b):
 return (p[0]-a[0])*(b[1]-a[1])==(p[1]-a[1])*(b[0]-a[0]) and min(a[0],b[0])<=p[0]<=max(a[0],b[0]) and min(a[1],b[1])<=p[1]<=max(a[1],b[1])

def components(d,net,keys,ps):
 ss=[(tuple(a),tuple(b)) for a,b in segments(d,net)]
 points={tuple(p) for s in ss for p in s}|{ps[k][1] for k in keys}
 points|={tuple(p) for p in d['junctions'] if sum(on(p,a,b) for a,b in ss)>=2}
 parent={p:p for p in points}
 def find(p):
  while parent[p]!=p:
   parent[p]=parent[parent[p]];p=parent[p]
  return p
 for a,b in ss:
  if a==b:continue
  assert a[0]==b[0] or a[1]==b[1]
  line=[p for p in points if on(p,a,b)]
  r=find(line[0])
  for p in line[1:]:parent[find(p)]=r
 return {k:find(ps[k][1]) for k in keys}

def method_checks():
 def d(ss,dots=[]):return dict(wires=[dict(net='n',segments=ss)],junctions=dots)
 keys=[('a',0),('b',0)]; ps={keys[0]:('n',(0,0),'p'),keys[1]:('n',(10,10),'p')}
 cases=[('bent',[[[0,0],[10,0],[10,10]]],[],True),('gap',[[[0,0],[4,0]],[[6,0],[10,0],[10,10]]],[],False),('T',[[[0,0],[20,0]],[[10,0],[10,10]]],[],True),('overlap',[[[0,0],[8,0]],[[4,0],[10,0],[10,10]]],[],True),('proper_X_without_dot',[[[0,0],[20,0]],[[10,-10],[10,10]]],[],False),('proper_X_with_dot',[[[0,0],[20,0]],[[10,-10],[10,10]]],[[10,0]],True)]
 for name,ss,dots,want in cases:
  c=components(d(ss,dots),'n',keys,ps);assert(c[keys[0]]==c[keys[1]])==want,name
  flipped=[list(reversed(s)) for s in reversed(ss)];assert components(d(flipped,dots),'n',keys,ps)[keys[0]]==components(d(flipped,dots),'n',keys,ps)[keys[1]] if want else components(d(flipped,dots),'n',keys,ps)[keys[0]]!=components(d(flipped,dots),'n',keys,ps)[keys[1]]
 other=d([[[0,0],[4,0]],[[6,0],[10,0],[10,10]]]);other['wires'].append(dict(net='other',segments=[[[4,0],[6,0]]]));c=components(other,'n',keys,ps);assert c[keys[0]]!=c[keys[1]]
 return [r[0] for r in cases]+['direction_and_order','other_net_excluded']

def terminal(device, index, native_term):
    kind = device['card'][0]
    if kind in 'mq':
        names = ('D', 'G', 'S') if kind == 'm' else ('C', 'B', 'E')
        if index >= len(names) or native_term.lower() != names[index].lower():
            raise ValueError('unsupported transistor card-pin identity')
    else:
        if kind not in 'rcldvi' or index not in (0, 1) or native_term != ('a', 'b')[index]:
            raise ValueError('unsupported two-terminal card-pin identity')
        schemas = (('1', '2'), ('P1', 'P2')) if kind in 'rcl' else (('A', 'K'), ('1', '2')) if kind == 'd' else (('+', '-'), ('1', '2'))
        matches = [pair for pair in schemas if set(pair) == set(device['nets'])]
        if len(matches) != 1:
            raise ValueError('unsupported or ambiguous source terminal schema')
        names = matches[0]
    return names[index]

def actual_inductor(root, device):
    matches = [g for g in path_glyphs(root) if g['type'] == device['type'] and close(g['origin'],[device['x'],device['y']])]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous actual inductor path')
    glyph=matches[0]; terminals={}
    for name,cached in device['terminals'].items():
        found=[p for p in glyph['endpoints'] if close(p,cached)]
        if len(found)!=1:
            raise ValueError('cached inductor terminal has no unique path endpoint: '+name)
        terminals[name]=[round(v,6) for v in found[0]]
    return dict(object=glyph['object'],terminals=terminals,actual_path_endpoints=glyph['endpoints'])

def label_evidence(root, net):
    # Text never connects pieces; retain exact literal labels for later visual review.
    found = []
    for element, matrix in transformed_elements(root):
        if element.tag.rsplit('}',1)[-1] != 'text': continue
        text = ''.join(element.itertext()).strip()
        if text.lower() != net: continue
        try: at = apply(matrix, [float(element.get('x','0')),float(element.get('y','0'))])
        except ValueError: continue
        found.append(dict(text=text, at=at, object=element.get('data-object-id'), kind=element.get('data-kind'), anchor_kind=element.get('data-anchor-kind')))
    return found

def junctions(root):
    """Actual source contact dots; cached points cannot invent a junction."""
    result = []
    for element, matrix in transformed_elements(root):
        if element.tag.rsplit('}', 1)[-1] != 'circle':
            continue
        name = element.get('data-object-id', '')
        if element.get('data-node-kind') != 'contact' and not name.endswith('-junction'):
            continue
        point = apply(matrix, [float(element.get('cx')), float(element.get('cy'))])
        result.append(dict(object=name, xy=[round(v, 6) for v in point]))
    return result


def source_connection(context, ink, targets):
    """Split supported conductor strokes at actual contact-dot centres."""
    split, used = [], []
    for start, end in ink:
        points = {tuple(start), tuple(end)}
        for dot in context.get('junctions', []):
            if on(dot['xy'], start, end):
                points.add(tuple(dot['xy']))
                if dot not in used:
                    used.append(dot)
        ordered = sorted(points, key=lambda p: (p[0]-start[0])*(end[0]-start[0]) + (p[1]-start[1])*(end[1]-start[1]))
        split.extend([[list(a), list(b)] for a, b in zip(ordered, ordered[1:])])
    return dict(connection(split, targets), actual_junctions=used)


def source(c, row):
    targets, glyphs, bindings = [], {}, []
    evidence = dict(source_sha256=c['source_sha256'], source_glyphs=glyphs, ordered_terminal_bindings=bindings,
                    literal_net_labels=label_evidence(c['root'],row['net']))
    try:
        for (card, index), term in zip(row['pins'],row['terms']):
            device = c['devices'][card]
            name = terminal(device,index,term)
            if c['cards'][card][index+1] != row['net'] or device['nets'][name].lower() != row['net']:
                raise ValueError('source/card/native binding mismatch '+card+':'+name)
            if card not in c['glyphs']:
                c['glyphs'][card] = (actual_resistor if card[0]=='r' else actual_inductor if card[0]=='l' else actual_glyph)(c['root'],device)
            glyphs[card]=c['glyphs'][card]
            point=glyphs[card]['terminals'][name]
            bindings.append(dict(card=card,card_index=index,native_term=term,source_term=name,net=row['net'],xy=point))
            targets.append(point)
        if row['net'] not in c['nets']:
            c['nets'][row['net']] = verified_segments(c['human'],row['net'],c['ink'])
        ink,missing=c['nets'][row['net']]
        evidence.update(verified_ink_segments=ink,cache_segments_without_ink=missing,
                        source_connection=source_connection(c,ink,targets))
        if evidence['source_connection']['continuous']:
            return dict(status='source_connected', **evidence)
        whole = source_connection(c,c['ink'],targets)
        evidence['whole_svg_connection'] = whole
        if whole['continuous']:
            return dict(status='unsupported', reason='actual conductor path lacks a verified named-net assignment', **evidence)
        return dict(status='source_disconnected', **evidence)
    except (ValueError, KeyError, IndexError, AssertionError) as error:
        return dict(status='unsupported',reason=str(error),**evidence)

def key(row):
    return row['id']+':'+row['net']+':'+'--'.join(card+'.'+str(i) for card,i in row['pins'])

def checks():
    result = list(method_checks())
    for kind, schema in (('r', ['1', '2']), ('c', ['P1', 'P2']), ('i', ['+', '-']), ('d', ['A', 'K'])):
        d = dict(card=kind+'1', nets={name:'n'+str(i) for i,name in enumerate(schema)})
        assert [terminal(d,i,('a','b')[i]) for i in range(2)] == schema
        result.append('literal_'+kind+'_ordered_source_schema')
    for d, index, term in ((dict(card='r1',nets={'1':'n','2':'q'}),0,'b'),
                           (dict(card='m1',nets={}),1,'d'),
                           (dict(card='x1',nets={'1':'n','2':'q'}),0,'a'),
                           (dict(card='c1',nets={'1':'n','2':'q','P1':'n','P2':'q'}),0,'a')):
        try: terminal(d,index,term)
        except ValueError: pass
        else: raise AssertionError('ambiguous or changed terminal role accepted')
    result.append('wrong_native_role_unknown_kind_ambiguous_schema_rejected')
    h = dict(wires=[dict(net='n',segments=[[[0,0],[4,0]],[[4,0],[6,0]],[[6,0],[10,0]]])])
    ink = [[[0,0],[4,0]],[[6,0],[10,0]]]
    verified, missing = verified_segments(h,'n',ink)
    assert missing == [[[4,0],[6,0]]]
    assert not connection(verified,[[0,0],[10,0]])['continuous']
    assert connection(ink+[missing[0]],[[0,0],[10,0]])['continuous']
    result += ['cache_only_bridge_excluded','literal_supported_bridge_restores_connection']
    return result + source_checks()


def source_checks():
    """Literal zigzag leads, missing cache ink, and an unassigned real path."""
    root = ET.fromstring('''<svg>
      <g data-object-id="r1-body" data-symbol-id="resistor"><g>
        <path d="M -20 0 L -10 0 L -5 5 L 5 -5 L 10 0 L 20 0"/>
      </g></g>
      <g data-object-id="r2-body" data-symbol-id="resistor"><g transform="translate(100 0)">
        <path d="M -20 0 L -10 0 L -5 5 L 5 -5 L 10 0 L 20 0"/>
      </g></g>
      <path data-role="conductor-ink" d="M 20 0 L 80 0"/>
      <text data-kind="net-label" x="50" y="20">n</text>
    </svg>''')
    row = dict(id='literal', net='n', pins=[['r1', 1], ['r2', 0]], terms=['b', 'a'])
    devices = {
        'r1': dict(card='r1', type='resistor', x=0, y=0,
                   nets={'1': 'a', '2': 'n'}, terminals={'1': [-20, 0], '2': [20, 0]}),
        'r2': dict(card='r2', type='resistor', x=100, y=0,
                   nets={'1': 'n', '2': 'b'}, terminals={'1': [80, 0], '2': [120, 0]}),
    }
    context = dict(root=root, devices=devices, glyphs={}, nets={}, source_sha256={},
                   cards={'r1': ['r1', 'a', 'n', '1k'], 'r2': ['r2', 'n', 'b', '1k']},
                   ink=conductor_ink(root), human=dict(wires=[dict(net='n', segments=[
                       [[20, 0], [80, 0]], [[30, 10], [40, 10]]])]))
    observed = source(copy.deepcopy(context), row)
    assert observed['status'] == 'source_connected'
    assert observed['cache_segments_without_ink'] == [[[30, 10], [40, 10]]]
    missing_assignment = copy.deepcopy(context)
    missing_assignment['human']['wires'][0]['segments'] = []
    observed = source(copy.deepcopy(missing_assignment), row)
    assert observed['status'] == 'unsupported' and observed['whole_svg_connection']['continuous']
    disconnected = copy.deepcopy(missing_assignment)
    disconnected['ink'] = []
    observed = source(disconnected, row)
    assert observed['status'] == 'source_disconnected' and observed['literal_net_labels']
    wrong_binding = copy.deepcopy(context)
    wrong_binding['cards']['r2'][1] = 'other'
    assert source(wrong_binding, row)['status'] == 'unsupported'
    wrong_lead = copy.deepcopy(context)
    wrong_lead['devices']['r1']['terminals']['2'] = [21, 0]
    assert source(wrong_lead, row)['status'] == 'unsupported'
    coil = ET.fromstring('''<svg><g data-object-id="coil" data-symbol-id="inductor"><g>
      <path d="M 0 -30 L 0 -20 C 10 -20 10 20 0 20 L 0 30"/>
    </g></g></svg>''')
    device = dict(card='l1', type='inductor', x=0, y=0, terminals={'1': [0, -30], '2': [0, 30]})
    assert actual_inductor(coil, device)['terminals'] == device['terminals']
    device['terminals']['2'] = [0, 31]
    try:
        actual_inductor(coil, device)
    except ValueError:
        pass
    else:
        raise AssertionError('detached inductor endpoint accepted')
    crossing = [[[0, 0], [20, 0]], [[10, -10], [10, 10]]]
    targets = [[0, 0], [10, 10]]
    assert not source_connection({}, crossing, targets)['continuous']
    dot = ET.fromstring('<svg><circle data-node-kind="contact" data-object-id="literal-dot" cx="10" cy="0" r="3"/></svg>')
    assert source_connection(dict(junctions=junctions(dot)), crossing, targets)['continuous']
    return ['literal_resistor_path_leads', 'unrelated_cache_only_spur_keeps_verified_path',
            'whole_ink_rejects_unassigned_source_negative', 'labels_do_not_join_source_pieces',
            'wrong_source_binding_rejected', 'detached_resistor_lead_rejected',
            'literal_inductor_path_ends', 'detached_inductor_endpoint_rejected',
            'source_proper_crossing_requires_actual_contact_dot']

def load_source(examples, ident):
    paths = [examples / (ident+s) for s in ('.cir', '.human.json', '.svg')]
    human = json.loads(paths[1].read_text())
    root = ET.parse(paths[2]).getroot()
    return dict(human=human, root=root, cards=read_cards(paths[0].read_text()),
                devices={d['card']:d for d in human['devices']},
                ink=conductor_ink(root), junctions=junctions(root), glyphs={}, nets={},
                source_sha256={p.name:digest(p) for p in paths})


def audit(examples, before, after):
    """Validate complete paired corpora; inspect changed native nets by name."""
    names = sorted(p.name.removesuffix('.human.json') for p in examples.glob('*.human.json'))
    scores = [json.loads((d/'scorecard.json').read_text()) for d in (before,after)]
    for directory, score in zip((before,after),scores):
        expected_files = sorted(['scorecard.json']+[name+suffix for name in names for suffix in ('.json','.report.json')])
        if sorted(p.name for p in directory.glob('*.json')) != expected_files:
            raise ValueError('native drawing/report filename inventory changed')
        if sorted(score['ids']) != names or sorted(score['results']) != names:
            raise ValueError('complete paired source/native name coverage changed')
        if digest(examples/'index.json') != score['index_sha256']:
            raise ValueError('source index differs from scored corpus')
        if digest(directory/'cktimg-json') != score['binary_sha256']:
            raise ValueError('native executable differs from scored corpus')
    for field in ('corpus_sha256','issues','index_sha256','measure_sha256','runner_sha256','scorer_sha256'):
        if scores[0][field] != scores[1][field]:
            raise ValueError('comparison inputs changed: '+field)
    result = dict(corpus=examples.name, binary_sha256=[s['binary_sha256'] for s in scores],
                  paired_names=names, scorecard_sha256=[digest(d/'scorecard.json') for d in (before,after)],
                  changed_drawings=[], changed_reports=[], checked=[], gains=[], losses=[], unstable=[])
    for ident in names:
        paths = [d/(ident+'.json') for d in (before,after)]
        for directory,score,path in zip((before,after),scores,paths):
            entry=score['results'][ident]
            expected={'deck_sha256':examples/(ident+'.cir'),'source_sha256':examples/(ident+'.human.json'),
                      'preview_sha256':examples/(ident+'.svg'),
                      'geometry_sha256':path,'report_sha256':directory/(ident+'.report.json')}
            for field,p in expected.items():
                if digest(p) != entry[field]:
                    raise ValueError(ident+': mismatched '+field)
        if scores[0]['results'][ident]['report_sha256'] != scores[1]['results'][ident]['report_sha256']:
            result['changed_reports'].append(ident)
        if paths[0].read_bytes() == paths[1].read_bytes():
            continue
        result['changed_drawings'].append(ident)
        drawings=[json.loads(p.read_text()) for p in paths]
        maps=[pins(d) for d in drawings]
        by_net={}
        for pin in sorted(maps[0].keys() | maps[1].keys()):
            if pin not in maps[0] or pin not in maps[1] or maps[0][pin][::2] != maps[1][pin][::2]:
                result['unstable'].append(dict(id=ident,pin=pin,before=maps[0].get(pin),after=maps[1].get(pin)))
            else:
                by_net.setdefault(maps[0][pin][0],[]).append(pin)
        context=None
        for net,keys in sorted(by_net.items()):
            if len(keys)<2:
                continue
            if segments(drawings[0],net)==segments(drawings[1],net) and all(maps[0][k]==maps[1][k] for k in keys) and drawings[0]['junctions']==drawings[1]['junctions']:
                continue
            comps=[components(d,net,keys,ps) for d,ps in zip(drawings,maps)]
            groups=[]
            for comp in comps:
                pieces={}
                for k in keys: pieces.setdefault(comp[k],[]).append(k)
                groups.append(sorted(pieces.values()))
            hashes=[digest(p) for p in paths]
            result['checked'].append(dict(id=ident,net=net,pins=keys,components=groups,native_sha256=hashes))
            for left,right in itertools.combinations(keys,2):
                old,new=[comp[left]==comp[right] for comp in comps]
                if old==new:
                    continue
                row=dict(id=ident,net=net,pins=[left,right],terms=[maps[0][left][2],maps[0][right][2]],
                         before=[maps[0][left][1],maps[0][right][1]],after=[maps[1][left][1],maps[1][right][1]],
                         baseline=old,candidate=new,native_sha256=hashes)
                if context is None: context=load_source(examples,ident)
                row.update(name=key(row),source=source(context,row))
                result['losses' if old else 'gains'].append(row)
    transitions=result['gains']+result['losses']
    if len({r['name'] for r in transitions})!=len(transitions):
        raise ValueError('repeated transition identity')
    result['summary']=dict(changed_nets_checked=len(result['checked']),
                           stable_pairs=sum(len(r['pins'])*(len(r['pins'])-1)//2 for r in result['checked']),
                           gains=len(result['gains']),losses=len(result['losses']),unstable=len(result['unstable']))
    result['source_inventory']={direction:{status:sorted(r['name'] for r in result[direction] if r['source']['status']==status)
                                         for status in ('source_connected','source_disconnected','unsupported')}
                                for direction in ('gains','losses')}
    result['expected_candidate_mismatches']={
        'extra_joins':result['source_inventory']['gains']['source_disconnected'],
        'missing_joins':result['source_inventory']['losses']['source_connected']}
    result['baseline_mismatches_resolved']={
        'missing_joins':result['source_inventory']['gains']['source_connected'],
        'extra_joins':result['source_inventory']['losses']['source_disconnected']}
    result['transition_groups']={}
    for row in transitions:
        name=row['id']+':'+row['net']
        group=result['transition_groups'].setdefault(name,dict(improved=[],regressed=[],unsupported=[]))
        status=row['source']['status']
        field='unsupported' if status=='unsupported' else 'improved' if row['candidate']==(status=='source_connected') else 'regressed'
        group[field].append(row['name'])
    return result


def frozen(result):
    """Exact names remain reviewable; the digest fixes every evidence field."""
    core={k:v for k,v in result.items() if k!='dependency_sha256'}
    canonical=json.dumps(core,sort_keys=True,separators=(',',':')).encode()
    return dict(evidence_sha256=hashlib.sha256(canonical).hexdigest(),method_checks=result['method_checks'],
                corpora={r['corpus']:{k:r[k] for k in ('binary_sha256','summary','changed_drawings','changed_reports',
                                                     'source_inventory','expected_candidate_mismatches','baseline_mismatches_resolved')}
                         for r in result['runs']})


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--native-root',type=Path,required=True)
    parser.add_argument('--baseline',default='iteration16-aliases')
    parser.add_argument('--candidate',default='iteration17-bounded')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    runs=[audit(args.examples/corpus,args.native_root/('all-'+tag+'-'+args.baseline),
                args.native_root/('all-'+tag+'-'+args.candidate))
          for corpus,tag in (('analoggenie','ag'),('amsnet','ams'))]
    result=dict(baseline=args.baseline,candidate=args.candidate,method_checks=checks(),runs=runs,
                limits='Changed stable named pin-pair physical continuity only. Pair counts are correlated. Source labels never connect ink; source-separated new joins remain mismatches. This is a manual checkpoint gate, not whole-corpus equivalence or an electrical correctness claim.')
    dependencies=('thin_connectivity.py','trunk_rungs.py','cross_caps.py','input_resistors.py','input_resistor_legs.py',
                  'converter_loops.py','converter_terminals.py','channel_bridges.py')
    result['dependency_sha256']={n:digest(Path(__file__).with_name(n)) for n in dependencies}
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    if args.check:
        expected=json.loads(Path(__file__).with_name('thin_connectivity_cases.json').read_text())
        if frozen(result)!=expected:
            raise ValueError('named transitions, expected mismatches or evidence changed; review added AND resolved cases')
    unsupported=[r['name'] for run in runs for direction in ('gains','losses') for r in run[direction] if r['source']['status']=='unsupported']
    if unsupported or any(r['unstable'] for r in runs):
        raise ValueError('unsupported source or unstable native pin identities: '+str(unsupported))
    print(json.dumps({r['corpus']:dict(r['summary'],source={direction:{k:len(v) for k,v in inventory.items()}
                                                         for direction,inventory in r['source_inventory'].items()}) for r in runs},indent=2,sort_keys=True))


if __name__=='__main__':
    main()
