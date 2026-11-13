#!/usr/bin/env python3
"""Named expected-mismatch gate for four bounded17 interaction circuits.

This is a failure inventory, not desired behavior. It requires exactly the
retained source-connected pair mismatches. An unexpected repair fails until
its marker is reviewed and removed. Full-corpus discovery remains separate:
this gate covers the complete pin-pair sets of four named affected nets.
"""
import argparse,itertools,json
from pathlib import Path
from converter_loops import wire_tree
from thin_interactions import CASES,source,sha
from trunk_rungs import pins,segments

EXPECTED = [
 'ag-1170:q-:m4.0,m8.0',
 'ag-2486:vx:m16.0,m17.0','ag-2486:vx:m16.0,m18.0','ag-2486:vx:m16.0,m18.1',
 'ag-2486:vx:m17.0,m18.0','ag-2486:vx:m17.0,m18.1','ag-2486:vx:m18.0,m18.1',
 'ag-2571:vout:c2.1,m1.0','ag-2571:vout:c2.1,m2.2','ag-2571:vout:c2.1,r2.0',
 'ag-989:net4:cc.1,m11.0','ag-989:net4:cc.1,m4.0','ag-989:net4:cc.1,m6.1',
 'ag-989:net4:m11.0,m4.0','ag-989:net4:m11.0,m6.1','ag-989:net4:m4.0,m6.1',
]

def audit(root,before,after):
 historical=json.loads(Path(__file__).with_name('thin_interactions_cases.json').read_text())
 frozen={r['name']:r for r in historical['sources']}
 rows=[];loss_names=[];mismatches=[];scanned=[]
 for ident,(net,expected_pairs) in CASES.items():
  paths=[d/(ident+'.json') for d in (before,after)];a,b=[json.loads(p.read_text()) for p in paths]
  pa,pb=pins(a),pins(b);keys=sorted(k for k,v in pa.items() if v[0]==net)
  assert keys==sorted(k for k,v in pb.items() if v[0]==net),(ident,'terminal set changed')
  assert all(pa[k]==pb[k] for k in keys),(ident,'terminal identities or geometry changed')
  old,new=[segments(d,net) for d in (a,b)];actual=[]
  for pair in itertools.combinations(keys,2):
   targets=[list(pa[k][1]) for k in pair]
   continuous=[wire_tree(ss,targets) is not None for ss in (old,new)]
   name=ident+':'+net+':'+','.join(n+'.'+str(i) for n,i in pair)
   scanned.append(dict(name=name,points=targets,baseline=continuous[0],candidate=continuous[1]))
   if continuous==[True,False]:actual.append(tuple(n+'.'+str(i) for n,i in pair))
  assert actual==expected_pairs,(ident,'lost-pair set changed',actual,expected_pairs)
  for pair in actual:
   r=source(root/'external/examples/analoggenie',ident,net,pair,a,b)
   for field in ('source_sha256','source_glyphs','source_connection','verified_ink','cache_only_ink'):
    assert r[field]==frozen[r['name']][field],(r['name'],field,'source evidence changed')
   rows.append(r);loss_names.append(r['name'])
   if r['source_connection']['continuous']:mismatches.append(r['name'])
 assert mismatches==EXPECTED,('expected source mismatch names changed',mismatches,EXPECTED)
 return dict(provenance=dict(before_binary_sha256=sha(before/'cktimg-json'),after_binary_sha256=sha(after/'cktimg-json'),before_revision='450e4cd0',after_state='bounded17 candidate, identified by binary and drawing hashes; not initial17 trace',native_sha256={ident:{label:sha(d/(ident+'.json')) for label,d in [('before',before),('after',after)]} for ident in CASES}),
             expected_source_connected_mismatches=mismatches,expected_all_native_loss_names=loss_names,
             scanned_pin_pairs=scanned,rows=rows,
             method_checks=['exact_named_net_terminal_sets','unchanged_terminal_identity_and_coordinates','all_pairs_in_four_named_nets_checked','exact_native_loss_names','actual_source_proof_matches_frozen_trace_companion','exact_sixteen_source_connected_mismatch_names'])

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for n in ('before','after','output'):p.add_argument(n,type=Path)
 p.add_argument('--check',action='store_true');a=p.parse_args()
 result=json.loads(json.dumps(audit(Path(__file__).resolve().parents[3],a.before,a.after)))
 if a.check:assert result==json.loads(Path(__file__).with_name('thin_interactions_native_cases.json').read_text()),'native mismatch snapshot changed'
 a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
 print('Expected source-connected mismatches:',result['expected_source_connected_mismatches'])
if __name__=='__main__':main()
