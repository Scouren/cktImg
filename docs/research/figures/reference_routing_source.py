#!/usr/bin/env python3
"""Revalidate named actual source terminals and the opaque outer-topology control."""
import hashlib,json
from pathlib import Path
import reference_amplifiers_connectivity as proof
from channel_bridges import read_cards
from trunk_rungs import pins

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

EXPECTED = {
    'ag-2415': ('vin', [('m1',2),('mchg',2),('mres',2)]),
    'ag-2428': ('vin', [('m1',2),('m4',2),('m8',2)]),
    'ag-2434': ('vin', [('m1',2),('mchg',2),('mres',2)]),
    'ag-2436': ('net4', [('m1',1),('msen',1),('x1',4)]),
}

def replay(root,before,after,expected):
    """Every retained source proof and native loss must independently recur."""
    from itertools import combinations
    names=[ident+':'+net+':'+n+'.'+str(i)+'--'+m+'.'+str(j) for ident,(net,ks) in EXPECTED.items() for (n,i),(m,j) in combinations(ks,2)]
    assert [r['name'] for r in expected]==names,'named loss inventory changed'
    assert [r['name'] for r in expected if r['source']['status']=='source_disconnected']==[n for n in names if n.startswith('ag-2434:')]
    refs=json.loads(Path(__file__).with_name('reference_amplifiers_cases.json').read_text())
    proof.REFERENCE_ROWS.update({(r['id'],r['card']):r for r in refs['rows']})
    contexts={};drawings={};rows=[]
    for old in expected:
        ident=old['id'];net=old['net'];paths=[d/(ident+'.json') for d in (before,after)]
        if ident not in contexts:
            contexts[ident]=proof.native.load_source(root/'external/examples/analoggenie',ident)
            drawings[ident]=[json.loads(p.read_text()) for p in paths]
        assert [sha(p) for p in paths]==old['native_sha256'],(ident,'native geometry')
        maps=[pins(d) for d in drawings[ident]];keys=[tuple(k) for k in old['pins']]
        assert all([ps[k][2] for k in keys]==old['terms'] for ps in maps)
        assert all(all(ps[k][0]==net for k in keys) for ps in maps)
        comps=[proof.native.components(d,net,keys,ps) for d,ps in zip(drawings[ident],maps)]
        assert [c[keys[0]]==c[keys[1]] for c in comps]==[True,False],old['name']
        assert [[list(ps[k][1]) for k in keys] for ps in maps]==[old['before'],old['after']]
        row=dict(old,source=proof.source_observation(contexts[ident],old))
        assert row==old,(old['name'],'source evidence changed')
        rows.append(row)
    return rows

def outer_certificate(root,before,after):
    """Literal vertex substitution preserves all eleven ordered DUT cards.

    Internal AEA definitions differ. This certificate concerns the opaque
    instance graph and declared port contract seen by the layout engine.
    """
    examples=root/'external/examples/analoggenie'
    paths=[examples/(n+'.cir') for n in ('ag-2415','ag-2434')]
    texts=[p.read_text() for p in paths];a,b=[read_cards(t) for t in texts]
    rename={'net0':'net1','net1':'net4','net2':'net0','net3':'net3','net4':'net2'}
    assert sorted(a)==sorted(b)==['m1','m2','m3','mbias','mchg','mctrl','mgen','minj','mres','msen','x1']
    mapped={}
    for name,card in a.items():
        n=4
        changed=[card[0]]+[rename.get(v,v) for v in card[1:n+1]]+card[n+1:]
        assert changed==b[name],name
        mapped[name]=dict(before=card,after=changed)
    contracts=[[l.lower().split() for l in t.splitlines() if l.lower().startswith('.subckt aea ')] for t in texts]
    assert contracts==[[['.subckt','aea','vdd','vss','vref','out']]]*2
    coordinates={}
    for label,directory in [('17',before),('18',after)]:
        native=[pins(json.loads((directory/(n+'.json')).read_text())) for n in ('ag-2415','ag-2434')]
        keys=[('m1',2),('mchg',2),('mres',2)]
        points=[[list(p[k][1]) for k in keys] for p in native]
        assert points[0]==points[1]
        coordinates[label]=points[0]
    return dict(names=['ag-2415','ag-2434'],source_sha256={p.name:sha(p) for p in paths},net_substitution=rename,ordered_card_certificate=mapped,declared_contract=contracts[0][0],native_vin_pin_coordinates=coordinates,limits='The outer opaque DUT graphs and port contracts match; AEA internal implementations differ. Source VIN ink is continuous in 2415 and separated in 2434, so this visible topology alone cannot choose both source partitions.')
