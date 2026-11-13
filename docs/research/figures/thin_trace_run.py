#!/usr/bin/env python3
"""Run the diagnostic binary only after the owner has built its copied tree."""
from pathlib import Path
import hashlib,json,subprocess
from input_resistor_legs import connection

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def parse(text):
    rounds=[];current=None
    for line in text.splitlines():
        w=line.split()
        if not w or w[0]!='TRACE':continue
        tag=w[1];v=w[2:]
        if tag=='round_begin':
            current={'round':int(v[0]),'nets':{},'pins':[],'segments':[],'crossings':[],'counts':[],'worst':[],'changes':[],'parts':[],'part_all_label':[],'part_trunk':[]}
            rounds.append(current);continue
        if current is None:continue
        if tag=='net':
            current['nets'][int(v[0])]={'name':v[1],'role':v[2],'rank':int(v[3]),'style':v[4],'mate':int(v[5])}
        elif tag=='pin':
            current['pins'].append(dict(pin=int(v[0]),net=int(v[1]),device=v[2],index=int(v[3]),side=v[4],at=[int(v[5]),int(v[6])],kind=v[7]))
        elif tag=='segment':
            current['segments'].append(dict(net=int(v[0]),route=int(v[1]),a=[int(v[2]),int(v[3])],b=[int(v[4]),int(v[5])]))
        elif tag=='crossing':current['crossings'].append(dict(nets=[int(v[0]),int(v[1])],at=[int(v[2]),int(v[3])]))
        elif tag=='count':current['counts'].append(dict(iteration=int(v[0]),net=int(v[1]),count=int(v[2]),style=v[3],gone=v[4]=='true',eligible=v[5]=='true',limit=int(v[6])))
        elif tag=='worst':current['worst'].append(dict(iteration=int(v[0]),net=int(v[1])))
        elif tag=='change':current['changes'].append(dict(iteration=int(v[0]),net=int(v[1]),before=v[2],after=v[3],count=int(v[4])))
        elif tag=='part':current['parts'].append(dict(net=v[0],pin=int(v[1]),group=int(v[2]),at=[int(v[3]),int(v[4])],side=v[5]))
        elif tag=='part_all_label':current['part_all_label'].append(v[0])
        elif tag=='part_trunk':current['part_trunk'].append(dict(net=v[0],group=int(v[1]),members=int(v[2]),drawn=v[3]=='true'))
        elif tag!='round_drawn':raise AssertionError(line)
    assert rounds
    for r in rounds:
        for row in r['changes']+r['counts']:row['name']=r['nets'][row['net']]['name']
        for row in r['crossings']:row['names']=[r['nets'][n]['name'] for n in row['nets']]
        for row in r['worst']:row['name']=r['nets'][row['net']]['name'] if row['net']!=4294967295 else None
    return rounds

def run(root, here, baseline):
    trace=here/'out/bin/cktimg-json-trace'
    manifest=json.loads((here/'manifest.json').read_text())
    pairs={'ag-2309':('vx',['m11','m12']),'ag-2318':('vx',['m11','m12']),'ag-2319':('vx',['m11','m12']),'ag-2452':('vz',['m34','m40']),'ag-2376':('net0',['m4','m5']),'ag-2274':('vn',['m5','m6']),'ag-1411':('vb1',['m11','m14'])}
    rows=[]
    for name in manifest['cases']:
        deck=root/'external/examples/analoggenie'/f'{name}.cir'
        for compact in [True,False]:
            directory=here/'results'/f'{name}-compact-{int(compact)}';directory.mkdir(parents=True,exist_ok=True)
            config=directory/'layout.zon';config.write_text('.{ .layout = .{ .compact = '+str(compact).lower()+' } }\n')
            for label,binary in [('baseline',baseline),('trace',trace)]:
                command=[str(binary),'--config',str(config),'--report',str(directory/f'{label}.report.json'),str(deck),str(directory/f'{label}.json')]
                result=subprocess.run(command,cwd=root,capture_output=True,text=True,timeout=90)
                (directory/f'{label}.log').write_text(result.stderr)
                assert result.returncode==0,(name,compact,label,result.returncode,result.stderr[-4000:])
            for suffix in ['.json','.report.json']:
                assert (directory/('baseline'+suffix)).read_bytes()==(directory/('trace'+suffix)).read_bytes(),(name,compact,'trace changed output',suffix)
            rounds=parse((directory/'trace.log').read_text())
            row=dict(name=name,compact=compact,deck_sha256=digest(deck),final_geometry_sha256=digest(directory/'trace.json'),final_report_sha256=digest(directory/'trace.report.json'),rounds=rounds)
            if name in pairs:
                target,devices=pairs[name];row['target']=target;row['target_devices']=devices
                for r in rounds:
                    net,= [n for n,meta in r['nets'].items() if meta['name']==target]
                    targets=[]
                    for d in devices:
                        pin,=[p for p in r['pins'] if p['device']==d and p['index']==1]
                        assert pin['net']==net
                        targets.append(pin['at'])
                    r['target_connection']=connection([[s['a'],s['b']] for s in r['segments'] if s['net']==net],targets)
                    r['target_style']=r['nets'][net]['style']
                    r['target_crossings']=[c for c in r['crossings'] if net in c['nets']]
            rows.append(row)
            changes=[';'.join(c['name']+':'+c['before']+'>'+c['after']+'('+str(c['count'])+')' for c in r['changes']) for r in rounds]
            connections=[r.get('target_connection',{}).get('continuous') for r in rounds]
            print(name,compact,'round changes=',changes,'target continuous=',connections,flush=True)
    result={'source_manifest':manifest,'baseline_binary_sha256':digest(baseline),'trace_binary_sha256':digest(trace),'cases':rows,'named_byte_identical_cases':[r['name']+':compact='+str(r['compact']).lower() for r in rows]}
    return result
