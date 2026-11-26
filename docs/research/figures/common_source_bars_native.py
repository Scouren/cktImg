#!/usr/bin/env python3
"""Replay named common-source frames and emitted straight intervals.

Usage: common_source_bars_native.py EXAMPLES OUTPUT --baseline-ag DIR
 --baseline-ams DIR --candidate-ag DIR --candidate-ams DIR
 --baseline-bin FILE --candidate-bin FILE [--check] [--require-bars]

The source census is freshly replayed first. Native JSON supplies placed
D/G/S endpoints and emitted conductor segments; this is not a raster or
whole-symbol appearance comparison. All 2,936 named artifact/hash bindings
are checked before measuring the exact 31 source topologies.
"""
import argparse, itertools, json
from pathlib import Path
import common_source_bars as study
from trunk_rungs import segments, pins

HERE=Path(__file__).resolve().parent
sha=study.digest

def corpus(examples,directory,binary,deck_hashes):
    names=sorted(p.stem for p in examples.glob('*.cir'))
    assert {p.name:sha(p) for p in examples.glob('*.cir')}==deck_hashes
    expected=sorted(['scorecard.json']+[n+s for n in names for s in ('.json','.report.json')])
    assert sorted(p.name for p in directory.glob('*.json'))==expected,'incomplete native corpus'
    score=json.loads((directory/'scorecard.json').read_text())
    assert sorted(score['results'])==names and sorted(score['ids'])==names
    assert score['binary_sha256']==sha(binary)
    assert score['index_sha256']==sha(examples/'index.json')
    hashes={}
    for name in names:
        row=score['results'][name]
        for field,path in [('deck_sha256',examples/(name+'.cir')),('source_sha256',examples/(name+'.human.json')),('preview_sha256',examples/(name+'.svg')),('geometry_sha256',directory/(name+'.json')),('report_sha256',directory/(name+'.report.json'))]:
            assert row[field]==sha(path),(name,field)
        hashes[name]=[row['geometry_sha256'],row['report_sha256']]
    return dict(names=names,hashes=hashes,scorecard_sha256=sha(directory/'scorecard.json'),binary_sha256=sha(binary))

def observation(row,path):
    j=json.loads(path.read_text());ds={d['name'].lower():d for d in j['devices'] if d['name']}
    raw=row['topology'];names=raw['pair']+[raw['tail']];gs={}
    for name in names:
        d=ds[name]; ps=d['pins']; assert [p['term'] for p in ps]==['d','g','s']
        assert [p['net'].lower() for p in ps]==raw['bindings'][name][:3]
        assert d['bulk'].lower()==raw['bindings'][name][3]
        gs[name]=[p['xy'] for p in ps]
    a,b=[gs[d] for d in raw['pair']];t=gs[raw['tail']];tips=[a[2],t[0],b[2]]
    v=all(g[0][0]==g[2][0] and min(g[0][1],g[2][1])<g[1][1]<max(g[0][1],g[2][1]) for g in (a,b,t))
    sign=lambda x:(x>0)-(x<0)
    eligible=v and len({p[1] for p in tips})==1 and min(a[2][0],b[2][0])<t[0][0]<max(a[2][0],b[2][0]) and sign(a[2][1]-a[0][1])==sign(b[2][1]-b[0][1])==-sign(t[0][1]-t[2][1])
    ss=list(segments(j,raw['net']))
    straight=eligible and study.horizontal_interval(ss,tips[0][1],min(p[0] for p in tips),max(p[0] for p in tips))
    keys=[(raw['pair'][0],2),(raw['tail'],0),(raw['pair'][1],2)]
    native_pins=pins(j);components=study.ink.components(j,raw['net'],keys,native_pins)
    relations=[dict(pins=[keys[i],keys[k]],continuous=components[keys[i]]==components[keys[k]]) for i,k in itertools.combinations(range(3),2)]
    return dict(name=row['name'],tips=tips,actual_frames=gs,eligible=eligible,straight=straight,pair_relations=relations,native_sha256=sha(path))

def audit(args):
    source=study.audit(args.examples);expected=json.loads((HERE/'common_source_bars_cases.json').read_text())
    if source!=expected:raise ValueError('fresh source census differs')
    before,after={},{}
    observations={label:[] for label in ('baseline','candidate')}
    for short,folder in [('ag','analoggenie'),('ams','amsnet')]:
        for label,output in [('baseline',before),('candidate',after)]:
            directory=getattr(args,label+'_'+short);binary=getattr(args,label+'_bin')
            output[short]=corpus(args.examples/folder,directory,binary,source['corpus_deck_sha256'][short])
            for row in source['rows']:
                if row['corpus']==short:observations[label].append(observation(row,directory/(row['name'].split(':')[0]+'.json')))
    names=[r['name'] for r in source['rows']]
    for rows in observations.values():assert [r['name'] for r in rows]==names
    changed={c:dict(drawings=[n for n in before[c]['names'] if before[c]['hashes'][n][0]!=after[c]['hashes'][n][0]],reports=[n for n in before[c]['names'] if before[c]['hashes'][n][1]!=after[c]['hashes'][n][1]]) for c in before}
    transitions=[]
    for source_row,a,b in zip(source['rows'],observations['baseline'],observations['candidate']):
        assert a['name']==b['name']==source_row['name']
        for sp,bp,ap in zip(source_row['source']['pair_proofs'],a['pair_relations'],b['pair_relations']):
            assert [list(p) for p in bp['pins']]==sp['pins']
            assert bp['pins']==ap['pins']
            if bp['continuous']!=ap['continuous']:transitions.append(dict(name=a['name'],pins=bp['pins'],source=sp['source']['continuous'],before=bp['continuous'],after=ap['continuous']))
    selected=source['summary']['ag']['source_eligible']
    missing={label:[r['name'] for r in rows if r['name'] in selected and not r['straight']] for label,rows in observations.items()}
    return json.loads(json.dumps(dict(source_inventory_sha256=sha(HERE/'common_source_bars_cases.json'),script_sha256=sha(Path(__file__)),source_dependencies=source['dependencies'],corpora=dict(baseline=before,candidate=after),observations=observations,changed=changed,physical_transitions=transitions,missing_source_bars=missing,limits=['Native frames are exported actual named terminals, not an SVG symbol-stroke comparison.','Four source bars are correlated observations in one figure.','This companion measures exact named triads; the separate full-corpus physical gate remains required.'])))

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('examples',type=Path);ap.add_argument('output',type=Path)
    for label in ('baseline','candidate'):
        for kind in ('ag','ams','bin'):ap.add_argument('--'+label+'-'+kind,type=Path,required=True)
    ap.add_argument('--check',action='store_true');ap.add_argument('--require-bars',action='store_true');args=ap.parse_args()
    result=audit(args);args.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
    if args.check and result!=json.loads((HERE/'common_source_bars_native_cases.json').read_text()):raise ValueError('frozen native common-source observation differs')
    print(json.dumps(dict(changed=result['changed'],missing=result['missing_source_bars'],physical_transitions=result['physical_transitions']),sort_keys=True))
    if args.require_bars and result['missing_source_bars']['candidate']:raise ValueError('source straight bars remain missing')
if __name__=='__main__':main()
