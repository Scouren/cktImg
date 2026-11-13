#!/usr/bin/env python3
"""Named predicates for the frozen unsigned-amplifier routing interaction."""

def checks(result):
    states={(s['id'],s['version'],s['compact']):s for s in result['states']};passed=[]
    assert sorted(states)==sorted((n,v,c) for n in ['ag-2415','ag-2428','ag-2434','ag-2436'] for v in ['17','18'] for c in [False,True]);passed.append('exact_sixteen_diagnostic_geometry_and_report_identities')
    causes=[]
    for ident,old,new in [('ag-2415',240,270),('ag-2428',230,260),('ag-2434',240,270)]:
     for version,want in [('17',old),('18',new)]:
      s=states[ident,version,True];assert len(s['rounds'])==1;r=s['rounds'][0];assert r['changes']==[]
      near=[x for x in r['extra'] if x[:2]==['ported_near','vin']];assert len(near)==1
      _,_,x0,y0,x1,y1,bound,verdict=near[0];span=int(x1)-int(x0)+int(y1)-int(y0)
      assert span==want and int(bound)==240 and (verdict=='true')==(version=='17')
      assert bool([x for x in r['extra'] if x[:2]==['trunk_result','vin']])==(version=='17')
      assert [p['connection']['continuous'] for p in r['source_pairs']]==[version=='17']*3
     passed.append(ident+'_exact_input_near_rejection_before_trunk_without_thinning')
     causes.append(dict(id=ident,mechanism='input_proximity_boundary',baseline_span=old,candidate_span=new,limit=240,source_status='source_disconnected' if ident=='ag-2434' else 'source_connected'))
    for compact in [True,False]:
     a,b=[states['ag-2436',v,compact]['rounds'] for v in ['17','18']]
     assert len(a)==1 and a[0]['changes']==[] and all(p['connection']['continuous'] for p in a[0]['source_pairs'])
     assert len(b)==2 and [(c['name'],c['before'],c['after'],c['count']) for c in b[0]['changes']]==[('net4','auto','cut',4)]
     assert b[1]['changes']==[] and all(p['connection']['continuous'] for p in b[0]['source_pairs']) and not any(p['connection']['continuous'] for p in b[1]['source_pairs'])
     n=next(int(n) for n,v in b[0]['nets'].items() if v['name']=='net4')
     crossing_names=sorted(next(name for name in c['names'] if name!='net4') for c in b[0]['crossings'] if n in c['nets'])
     assert crossing_names==['net0','net0','verr','vout']
     part=[p for p in b[1]['parts'] if p['net']=='net4'];by_pin={p['pin']:p for p in b[1]['pins']};groups={}
     for p in part:groups.setdefault(p['group'],[]).append(by_pin[p['pin']]['device'])
     assert sorted(sorted(g) for g in groups.values())==[['m1','x1'],['msen']]
     assert 'net4' not in b[1]['part_all_label']
     assert [(p['members'],p['drawn']) for p in b[1]['part_trunk'] if p['net']=='net4']==[(2,False),(1,False)]
     passed.append('ag2436_compact_'+str(compact).lower()+'_four_crossings_then_two_parts_failed_near_trunk')
     # Exact rejected off-row approaches: every finite-cost candidate's first leg
     # ends on the same foreign vertical conductor, and its vertical leg overlaps it.
     ex=b[1]['extra'];barriers=[x for x in ex if x[:2]==['trunk_barrier','net0']];assert any(int(x[2])==int(x[4])==260 for x in barriers)
     finite=[x for x in ex if x[0]=='trunk_candidate' and int(x[4])<2**63-1]
     assert [x[1] for x in finite]==['level','level']
     for cand in finite:
      _,lay,track,offset,*_=cand
      assert ['trunk_fit',lay,track,offset,'false'] in ex
      points=[x for x in ex if x[:5]==['trunk_point',lay,track,offset,'0']]
      assert [int(p[-2]) for p in points]==[240,260,260]
     passed.append('ag2436_compact_'+str(compact).lower()+'_finite_approaches_end_on_foreign_net0_spine')
    causes.append(dict(id='ag-2436',mechanism='four_crossings_then_two_parts_and_failed_backside_gate_approach',foreign_spine_x=260,source_gate_facing='both_left',native_gate_facing=['m1:right','msen:left'],whole_part_collapse=False))
    return passed, causes
