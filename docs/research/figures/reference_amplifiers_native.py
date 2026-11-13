#!/usr/bin/env python3
"""Actual unsigned reference glyphs, every ordered port, and caller-side precedence.

Usage: reference_amplifiers_native.py EXAMPLES WORK_DIR OUTPUT
       --baseline-bin BIN --candidate-bin BIN
       [--baseline-corpus DIR --candidate-corpus DIR] ... [--check]

Both binaries and complete native corpus directories are frozen inputs.
This verifies canonical local symbol geometry and electrical bindings,
not source-facing/rail-bias placement or whole-drawing equivalence.
PININFO is covered by the Schemify API tests, not this native CLI.
"""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import reference_amplifiers as source
import remaining_amplifiers_native as shared
import block_aliases_native as native

NEGATIVES=[
 ('erramp_box','ERRAMP','VDD VSS VREF VBN OUT'),
 ('ea1_unknown_controls','EA1','VDD VSS VFP1 VREF VX2 VB1 VISR VX1'),
 ('mixed_positive','AEA','VDD VSS VREF INP OUT VX'),
 ('extra_ib','AEA','VDD VSS VREF OUT IB'),('extra_vbt','AEA','VDD VSS VREF OUT VBT'),
 ('family_suffix','AEA2','VDD VSS VREF OUT'),('family_prefix','my_aea','VDD VSS VREF OUT'),
 ('error_suffix','error_amp_extra','VDD VSS VREF OUT'),
 ('duplicate_output','ERRORAMP','VDD VSS VREF OUT VEA'),
 ('duplicate_bias_vb1_vbn','ERROR_AMP','VDD VSS VREF OUT VB1 VBN'),
 ('duplicate_bias_vbn_nb','ERROR_AMP','VDD VSS VREF OUT VBN NB'),
 ('duplicate_bias_vb1_nb','ERROR_AMPLIFIER','VDD VSS VREF OUT VB1 NB'),
 ('mixed_negative','AEA','VDD VSS VREF OUT INN'),('mixed_unsigned','AEA','VDD VSS VREF OUT IN'),
 ('unknown_enable','AEA','VDD VSS VREF OUT ENABLE'),('unknown_vb2','AEA','VDD VSS VREF OUT VB2'),
 ('missing_reference','ERRORAMP','VDD VSS OUT'),('missing_output','ERROR_AMP','VDD VSS VREF VB1'),
 ('unknown_vcc','ERROR_AMPLIFIER','VCC VSS VREF OUT'),
 ('unrelated_opamp','OPAMP','VDD VSS VREF OUT'),('unrelated_vea','AMP','VDD VSS INN VEA'),
 ('unrelated_vbn','COMP','VDD VSS INN OUT VBN'),('signed_vea','AEA','VDD VSS INN VEA'),
 ('signed_nb','AEA','VDD VSS INN OUT NB'),
]
POSITIVE=[('permuted_aea','aEa','OUT VBN VREF VSS VDD'),('permuted_erroramp','ErrorAmp','VREF OUT VSS VDD'),
 ('permuted_error_amplifier','ERROR_AMPLIFIER','VEA VREF VSS'),('permuted_error_amp','Error_Amp','NB OUT VDD VREF VSS'),
 ('no_rails','AEA','VREF VEA'),('supply_only','ERRORAMP','VREF VDD OUT VB1')]


def check_reference(drawing,root,row):
    observed=native.inspect(drawing,root,row)
    if observed['shape']!='triangle':return dict(observed,reference_geometry=False,lead_sides={})
    tolerance=native.PIXEL_TOLERANCE/observed['display_scale']
    body=observed['body_local'];lead_by_name={l['term']:l for l in observed['leads']}
    cardinal=[]
    for a,b in zip(body,body[1:]+body[:1]):
        if abs(a[0]-b[0])<tolerance or abs(a[1]-b[1])<tolerance:cardinal.append((a,b))
    if len(cardinal)!=1:raise ValueError('reference has no unique cardinal base')
    a,b=cardinal[0];apex=next(p for p in body if p!=a and p!=b)
    axis=0 if abs(a[1]-b[1])<tolerance else 1
    roles=source.roles(row['family'],row['ports'])
    if roles is None:raise ValueError('reference inspection requires complete role contract')
    named=dict(zip(roles,row['ports']))
    inp,out=lead_by_name[named['input']],lead_by_name[named['output']]
    correct=(native.edge_point(inp['attachment'],a,b,tolerance)
             and native.near(out['attachment'],apex,tolerance)
             and abs(inp['endpoint'][axis]-apex[axis])<tolerance
             and abs(out['endpoint'][axis]-apex[axis])<tolerance
             and (inp['endpoint'][1-axis]-inp['attachment'][1-axis])*(apex[1-axis]-inp['attachment'][1-axis])<0
             and (out['endpoint'][1-axis]-apex[1-axis])*(apex[1-axis]-inp['attachment'][1-axis])>0)
    sides={}
    for lead in observed['leads']:
        delta=[lead['endpoint'][i]-lead['attachment'][i] for i in (0,1)]
        if abs(delta[0])<tolerance and abs(delta[1])>tolerance:sides[lead['term']]='down' if delta[1]>0 else 'up'
        elif abs(delta[1])<tolerance and abs(delta[0])>tolerance:sides[lead['term']]='right' if delta[0]>0 else 'left'
        else:raise ValueError('reference port has no cardinal outward lead')
    # Account for ALL own-body external lead strokes, including an orphan.
    scale,offset,ink=native.frame(drawing,root);device=next(d for d in drawing['devices'] if d['name']==row['card'])
    local=lambda p:native.inverse(device,[(p[i]-offset[i])/scale for i in (0,1)])
    external=[]
    for index,node in enumerate(ink):
        if native.tag(node)!='polyline':continue
        ps=[local(p) for p in native.points(node)]
        if len(ps)!=2:continue
        if sorted(native.location(p,body,tolerance) for p in ps)==['boundary','outside']:external.append(index)
    if sorted(external)!=sorted(l['index'] for l in observed['leads']):raise ValueError('unbound or repeated own-body external lead')
    return dict(observed,reference_geometry=correct,reference_roles=named,lead_sides=sides)


def accepted(value):
    return (value['shape']=='triangle' and value['reference_geometry'] and value['signs_agree']
            and not value['signs'] and not value['interior_polylines'])


def adapted(row,shape='triangle'):
    return dict(row,shape=shape,expected_marks=[],missing_source_ports=row.get('missing_geometry',[]),
                signal_frame_mismatches=row.get('cached_frame_mismatches',[]))


def observe(prefix,row,reference=True):
    jp,sp=prefix.with_suffix('.json'),prefix.with_suffix('.svg')
    drawing,root=json.loads(jp.read_text()),ET.parse(sp).getroot()
    value=check_reference(drawing,root,row) if reference else native.inspect(drawing,root,row)
    return dict(native=value,native_sha256={'.json':shared.digest(jp),'.svg':shared.digest(sp)})


def selfchecks():
    shared.literal_checks()
    row=adapted(dict(card='x1',family='aea',ports=['vref','vea'],bindings=['a','b']))
    d=dict(devices=[dict(name='x1',pos=[0,0],rot=0,mirror=False,**{'class':'untrusted'},pins=[dict(term='vref',net='a',xy=[-60,0]),dict(term='vea',net='b',xy=[60,0])])],
           wires=[dict(segments=[[[-100,-100],[-100,100],[100,100]]])])
    svg=ET.fromstring('<svg viewBox="-110 -110 220 220"><g><polyline points="-100,-100 -100,100 100,100"/><polyline points="-40,-40 40,0 -40,40 -40,-40"/><polyline points="-60,0 -40,0"/><polyline points="40,0 60,0"/></g><text x="50" y="-30" font-size="11">x1</text></svg>')
    assert accepted(check_reference(d,svg,row))
    names=['literal_unsigned_reference_and_vea_apex']
    for name,change in (
        ('added_polarity_rejected',lambda r:r[0].append(ET.fromstring('<text x="-30" y="3" text-anchor="middle" font-size="11">+</text>'))),
        ('interior_step_rejected',lambda r:r[0].append(ET.fromstring('<polyline points="-20,5 -10,5 -10,-5 0,-5"/>'))),
        ('missing_input_lead_rejected',lambda r:r[0].remove(r[0][2])),
        ('orphan_body_lead_rejected',lambda r:r[0].append(ET.fromstring('<polyline points="-40,20 -60,20"/>')))):
        changed=copy.deepcopy(svg);change(changed)
        try:assert not accepted(check_reference(d,changed,row)),name
        except ValueError:pass
        names.append(name)
    for name,change in (
        ('wrong_ordered_binding_rejected',lambda r:r['devices'][0]['pins'][0].update(net='wrong')),
        ('missing_declared_port_rejected',lambda r:r['devices'][0]['pins'].pop()),
        ('input_output_geometry_swap_rejected',lambda r:[r['devices'][0]['pins'][i].update(xy=xy) for i,xy in enumerate(([60,0],[-60,0]))])):
        changed=copy.deepcopy(d);change(changed)
        try:assert not accepted(check_reference(changed,svg,row)),name
        except (ValueError,KeyError):pass
        names.append(name)
    grounded=copy.deepcopy(d)
    grounded['devices'][0]['pins'].append(dict(term='vss',net='0',xy=[0,60]))
    ground_row=adapted(dict(card='x1',family='aea',ports=['vref','vea','vss'],bindings=['a','b','0']))
    ground_svg=copy.deepcopy(svg)
    ground_svg[0].append(ET.fromstring('<polyline points="0,20 0,60"/>'))
    assert accepted(check_reference(grounded,ground_svg,ground_row))
    grounded['devices'][0]['pins'].pop()
    try:check_reference(grounded,ground_svg,ground_row)
    except ValueError:pass
    else:raise AssertionError('declared native VSS deletion accepted')
    names.append('declared_native_vss_deletion_rejected')
    return names


def source_rows(examples,directory):
    path=directory/'reference-source.json'
    subprocess.run([sys.executable,'-B',str(HERE/'reference_amplifiers.py'),str(examples),str(path)],check=True,capture_output=True)
    current=json.loads(path.read_text());expected=json.loads((HERE/'reference_amplifiers_cases.json').read_text())
    shared.same(current,expected,'every reference source evidence field')
    assert current['selected']==source.EXPECTED and sum(len(r['ports']) for r in current['rows'])==68
    unknown,_,_,_=source.census.scan(examples)
    raw={source.remaining.key(r):r for r in unknown}
    excluded=[]
    for row in current['excluded']:
        value=source.remaining.inspect(raw[row['name']],examples)
        expected=shared.adapter_row(value)
        if row['name']=='ag-2423:x1':assert expected['shape']=='triangle' and expected['expected_marks']==['negative']
        else:assert expected['shape']=='box'
        excluded.append(expected)
    return current,excluded


def literal(binary,directory,name,family,ports,shape,extra='',reference=True):
    ports=ports.lower().split();bindings=['n'+str(i) for i in range(len(ports))]
    prefix=directory/('literal-'+name);deck=prefix.with_suffix('.cir')
    deck.write_text('* native reference check\n.subckt '+family+' '+' '.join(ports)+'\n'+extra+'\n.ends\nX1 '+' '.join(bindings)+' '+family+'\nRframea fa fb 1k\nRframeb fb 0 1k\nVframe fa 0 1\n')
    shared.render(binary,deck,prefix)
    row=adapted(dict(card='x1',family=family.lower(),ports=ports,bindings=bindings),shape)
    value=observe(prefix,row,reference=reference)
    assert value['native']['shape']==shape,(name,value['native']['shape'],shape)
    if shape=='triangle' and reference:assert accepted(value['native']),name
    return dict(name=name,family=family.lower(),ports=ports,deck_sha256=shared.digest(deck),**value)


def snapshot(binary,directory,examples,inventory,excluded,baseline,corpora):
    directory.mkdir(parents=True,exist_ok=True)
    rows=inventory['rows']
    for ident in sorted({r['id'] for r in rows+excluded}):shared.render(binary,examples/'analoggenie'/(ident+'.cir'),directory/ident)
    selected=[]
    for row in rows:
        value=observe(directory/row['id'],adapted(row))
        assert value['native']['shape']==('box' if baseline else 'triangle'),row['id']
        if not baseline:
            assert accepted(value['native']),row['id']
            want=dict(zip(row['ports'],['left' if role=='input' else 'right' if role=='output' else 'up' if role=='supply' else 'down' for role in source.roles(row['family'],row['ports'])]))
            assert value['native']['lead_sides']==want,row['id']
        selected.append(dict(name=row['id']+':'+row['card'],source_sha256=row['source_sha256'],**value))
    controls=[]
    for row in excluded:
        value=observe(directory/row['id'],row,reference=False)
        assert value['native']['shape']==row['shape'],row['id']
        if row['shape']=='triangle':assert shared.accepted(value['native']),row['id']
        controls.append(dict(name=row['id']+':'+row['card'],**value))
    negatives=[literal(binary,directory,*row,'box',reference=False) for row in NEGATIVES]
    positive=[]
    if not baseline:
        positive=[literal(binary,directory,*row,'triangle') for row in POSITIVE]
        for family in sorted(source.FAMILIES):
            variants=[literal(binary,directory,family+'-bias-'+bias,family,'VDD VSS VREF OUT '+bias,'triangle') for bias in ('VB1','VBN','NB')]
            def geometry(row):
                n=row['native'];return dict(body=n['body_local'],leads=[{k:l[k] for k in ('endpoint','attachment')} for l in n['leads']],signs=n['signs'],interior=n['interior_polylines'])
            assert all(geometry(r)==geometry(variants[0]) for r in variants[1:]),family
            positive.extend(variants)
    explicit=[]
    for family in sorted(source.FAMILIES):
        side=literal(binary,directory,family+'-explicit-side',family,'VDD VSS VREF VBN OUT','box','*@ right VREF',reference=False)
        lead=next(l for l in side['native']['leads'] if l['term']=='vref')
        assert lead['endpoint'][0]>lead['attachment'][0] and native.near([lead['endpoint'][1]],[lead['attachment'][1]]),family
        explicit.append(side)
    # Every real source rendering must equal its scored snapshot exactly.
    rendered=[]
    for path in sorted(directory.glob('ag-*.json')):
        if corpora:
            frozen=[d/path.name for d in corpora if (d/path.name).is_file()]
            if len(frozen)!=1 or path.read_bytes()!=frozen[0].read_bytes():
                raise ValueError('fresh native rendering differs from its unique scored drawing: '+path.name)
        rendered.append(dict(name=path.name,json_sha256=shared.digest(path),svg_sha256=shared.digest(path.with_suffix('.svg'))))
    return dict(renderer_sha256=shared.digest(binary),selected=selected,excluded=controls,literal_negatives=negatives,
                literal_positive_policy=positive,explicit_requests=explicit,scored_renderings=rendered,
                summary=dict(selected=len(selected),ordered_ports=sum(len(r['native']['ordered_ports']) for r in selected),
                             triangles=[r['name'] for r in selected if r['native']['shape']=='triangle'],excluded_names=[r['name'] for r in controls]))


def frozen(result):
    """Exact named inventory plus a digest of every native/source evidence field."""
    if 'whole_native_corpus' not in result:
        raise ValueError('frozen replay requires both complete corpus pairs')
    import hashlib
    return dict(evidence_sha256=hashlib.sha256(json.dumps(result,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
                source_inventory_sha256=result['source_inventory_sha256'],dependency_sha256=result['dependency_sha256'],
                method_checks=result['method_checks'],selected_names=result['selected_names'],excluded_names=result['excluded_names'],
                snapshots={name:dict(renderer_sha256=result[name]['renderer_sha256'],summary=result[name]['summary'],
                                     literal_negative_names=[r['name'] for r in result[name]['literal_negatives']],
                                     literal_policy_names=[r['name'] for r in result[name]['literal_positive_policy']],
                                     explicit_side_names=[r['name'] for r in result[name]['explicit_requests']])
                           for name in ('baseline','candidate')},
                whole_native_count=result['whole_native_corpus']['count'],changed_drawings=result['whole_native_corpus']['changed'])


def scored_inputs(before,after,examples,expected):
    """Bind every frozen score entry to its actual source, drawing and report."""
    changed=[]
    for old_dir,new_dir in zip(before,after):
        scores=[]
        for directory in (old_dir,new_dir):
            score=json.loads((directory/'scorecard.json').read_text())
            corpus='analoggenie' if all(n.startswith('ag-') for n in score['ids']) else 'amsnet'
            source_dir=examples/corpus
            names=sorted(p.name.removesuffix('.human.json') for p in source_dir.glob('*.human.json'))
            shared.same(sorted(score['ids']),names,'complete source/scorecard names')
            shared.same(sorted(score['results']),names,'complete scored result names')
            shared.same(sorted(p.name for p in directory.glob('*.json')),
                        sorted(['scorecard.json']+[n+s for n in names for s in ('.json','.report.json')]),'native filenames')
            shared.same(shared.digest(source_dir/'index.json'),score['index_sha256'],'source index hash')
            for name in names:
                paths={'deck_sha256':source_dir/(name+'.cir'),'source_sha256':source_dir/(name+'.human.json'),
                       'preview_sha256':source_dir/(name+'.svg'),'geometry_sha256':directory/(name+'.json'),
                       'report_sha256':directory/(name+'.report.json')}
                for field,path in paths.items():
                    shared.same(shared.digest(path),score['results'][name][field],name+':'+field)
            scores.append(score)
        for field in ('ids','corpus_sha256','issues','index_sha256','measure_sha256','runner_sha256','scorer_sha256'):
            shared.same(scores[0][field],scores[1][field],'paired score input '+field)
        changed.extend(name for name in scores[0]['ids']
                       if scores[0]['results'][name]['report_sha256']!=scores[1]['results'][name]['report_sha256'])
    shared.same(sorted(changed),sorted({n.split(':')[0] for n in expected}),'entire changed report names')
    return sorted(changed)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('examples','work_dir','output'):p.add_argument(name,type=Path)
    for stage in ('baseline','candidate'):
        p.add_argument('--'+stage+'-bin',type=Path,required=True)
        p.add_argument('--'+stage+'-corpus',type=Path,action='append',default=[])
    p.add_argument('--check',action='store_true');a=p.parse_args()
    a.work_dir.mkdir(parents=True,exist_ok=True)
    methods=selfchecks();inventory,excluded=source_rows(a.examples,a.work_dir)
    before=snapshot(a.baseline_bin,a.work_dir/'baseline',a.examples,inventory,excluded,True,a.baseline_corpus)
    after=snapshot(a.candidate_bin,a.work_dir/'candidate',a.examples,inventory,excluded,False,a.candidate_corpus)
    shared.same(before['summary']['triangles'],[],'baseline exact15 boxes')
    shared.same(after['summary']['triangles'],inventory['selected'],'candidate exact15 unsigned triangles')
    assert before['summary']['ordered_ports']==after['summary']['ordered_ports']==68
    result=dict(method_checks=methods,source_inventory_sha256=shared.digest(HERE/'reference_amplifiers_cases.json'),
                baseline=before,candidate=after,selected_names=inventory['selected'],excluded_names=[r['name'] for r in inventory['excluded']],
                limits='Actual own-body unsigned reference triangle, ordered electrical ports, canonical local roles and explicit-side precedence. Source facing/rail-bias placement is not claimed. PININFO is a Schemify parser feature, absent from this native CLI; its shape and exact direction preservation are covered by the separate Schemify API test.')
    if a.baseline_corpus or a.candidate_corpus:
        result['whole_native_corpus']=shared.corpus_changes(a.baseline_corpus,a.candidate_corpus,
                                                          (a.baseline_bin,a.candidate_bin),a.examples,inventory['selected'])
        result['whole_native_corpus']['changed_reports']=scored_inputs(a.baseline_corpus,a.candidate_corpus,a.examples,inventory['selected'])
    dependencies=sorted(set(inventory['audit_sha256'])|{Path(__file__).name,'block_aliases_native.py','remaining_amplifiers_native.py'})
    result['dependency_sha256']={name:shared.digest(HERE/name) for name in dependencies}
    if a.check:
        shared.same(frozen(result),json.loads((HERE/'reference_amplifiers_native_cases.json').read_text()),'every frozen source/native glyph field')
    a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:v['summary'] for k,v in result.items() if k in ('baseline','candidate')},indent=2))


if __name__=='__main__':main()
