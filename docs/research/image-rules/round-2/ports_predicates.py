#!/usr/bin/env python3
"""Falsify round-1 predicates, then replay narrower raw-incidence boundaries.

Oracle: literal mutation verdicts and the frozen exact 39/35 name lists.
This is a research selector proposal, not a production implementation. The
source's electrical roles and caller-owned eligibility remain separate.
"""
import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT/'docs/research/figures'))
import converter_symbol_cases as old


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(n):
    text=(ROOT/f'external/examples/analoggenie/ag-{n}.cir').read_text()
    models={w[1]:w[2] for line in text.lower().splitlines() if (w:=line.split()) and w[0]=='.model'}
    return old.aliases.read_cards(text),old.digital.declarations(text),models


def incidences(cards,definitions):
    out=collections.defaultdict(list)
    calls={c['card']:c for c in old.calls(cards,definitions)}
    for name,w in cards.items():
        if name[0]=='m': ns=w[1:5];ps=['D','G','S','B']
        elif name[0] in 'rc': ns=w[1:3];ps=['1','2']
        elif name[0]=='x': ns=calls[name]['bindings'];ps=calls[name]['ports']
        else: raise ValueError('unsupported raw incidence card '+name)
        for pin,net in zip(ps,ns):out[net].append([name,pin])
    return dict(sorted(out.items()))


def strengthened(kind,cards,defs,models):
    hit=(old.pass_divider if kind=='regulator' else old.sample_cell)(cards,defs)
    if hit is None:return None
    ns=hit['nets'];inc=incidences(cards,defs);outer=set(defs['dut'])
    bias=[net for role,net in ns.items() if role.startswith('bias')]
    if len(set(bias))!=len(bias):return None
    private={ns['negative'],ns['output']}
    # A bias name labels a role; it does not prove externality or privacy.
    if any(net not in outer or len(inc[net])!=1 for net in bias):return None
    if ns.get('supply') in private|{ns['ground'],ns['positive']} or any(n in private|{ns['ground'],ns['positive'],ns.get('supply')} for n in bias):return None
    mos=[w for n,w in cards.items() if n[0]=='m']
    if any(models.get(w[5])!='nmos' for w in mos):return None
    if kind=='regulator':
        m=mos[0];out=hit['output'];incoming=next(n for n in (m[1],m[3]) if n!=out)
        if private & outer or ns.get('supply')==out:return None
        if m[4] not in (ns['ground'],out):return None
        if len(inc[ns['negative']])!=3 or len(inc[ns['output']])!=2:return None
        if ns['positive'] not in outer or len(inc[ns['positive']])!=1:return None
        if incoming not in outer or out not in outer:return None
        if incoming in {ns['positive'],ns['negative'],ns['output'],ns['ground']}|set(bias):return None
    else:
        junction=hit['junction'];channels={n for w in mos for n in (w[1],w[3])}
        if junction in outer or ns['negative'] in outer:return None
        input_net=next(n for n in channels if n not in (junction,ns['negative']))
        if ns['output'] in channels|{ns['ground']}:return None
        if ns.get('supply') in channels|{ns['output']}:return None
        if any(w[4]!=ns['ground'] for w in mos):return None
        if len(inc[junction])!=3 or len(inc[ns['negative']])!=3 or len(inc[ns['output']])!=2:return None
        if input_net not in outer or len(inc[input_net])!=1:return None
        if ns['output'] not in outer or any(w[2] not in outer for w in mos):return None
    return dict(topology=hit,raw_incidence=inc,outer_ports=defs['dut'],models=models,
                authority='Raw candidate only: caller and actual-frame eligibility still required.')


def automatic(raw_candidates,eligible):
    """Planning model: raw uniqueness is tested before caller eligibility."""
    return len(raw_candidates)==1 and eligible.get(raw_candidates[0],False)


def record(kind,name,cards,defs,models,expected_old,expected_new):
    previous=(old.pass_divider if kind=='regulator' else old.sample_cell)(cards,defs) is not None
    newer=strengthened(kind,cards,defs,models) is not None
    assert (previous,newer)==(expected_old,expected_new),(name,previous,newer)
    return dict(name=name,kind=kind,expected_old=expected_old,expected_new=expected_new,
                observed_old=previous,observed_new=newer,cards=cards,definitions=defs,models=models)


def bind(cards,defs,formal,net):
    call=old.calls(cards,defs)[0];cards[call['card']][1+call['ports'].index(formal)]=net


def rename(cards,defs):
    cs=copy.deepcopy(cards);ds=copy.deepcopy(defs)
    nets=incidences(cs,ds);mapping={net:'q'+str(i) for i,net in enumerate(nets)}
    calls={r['card']:r for r in old.calls(cs,ds)}
    for name,w in cs.items():
        count=4 if name[0]=='m' else len(calls[name]['ports']) if name[0]=='x' else 2
        for i in range(1,count+1):w[i]=mapping[w[i]]
    ds['dut']=[mapping.get(n,n) for n in ds['dut']]
    return cs,ds


def mutations():
    rows=[]
    for kind,seed in [('regulator',2187),('sample',2658)]:
        c,d,m=read(seed)
        rows.append(record(kind,'literal_'+kind+'_positive',c,d,m,True,True))
        cn,dn=rename(c,d);rows.append(record(kind,kind+'_arbitrary_net_renaming',cn,dn,m,True,True))
        cn=copy.deepcopy(c);dn=copy.deepcopy(d);call=old.calls(c,d)[0]
        dn[call['family']]=list(reversed(call['ports']));cn[call['card']][1:1+len(call['ports'])]=list(reversed(call['bindings']))
        rows.append(record(kind,kind+'_paired_declaration_binding_permutation',cn,dn,m,True,True))
        cn=copy.deepcopy(c);bind(cn,d,'vdd','net0')
        rows.append(record(kind,kind+'_supply_aliases_private_signal',cn,d,m,True,False))
        cn=copy.deepcopy(c);name=next(n for n in c if n[0]=='m');cn[name][5]='unresolved_model'
        rows.append(record(kind,kind+'_unknown_mos_model',cn,d,m,True,False))
        dn=copy.deepcopy(d);dn[call['family']]=[p if p!='inn' else 'unresolved_input' for p in call['ports']]
        rows.append(record(kind,kind+'_unknown_formal_rejected',c,dn,m,False,False))
    c,d,m=read(2187)
    for name,net,device in [('regulator_feedback_extra_resistor','fb','r'),('regulator_gate_extra_capacitor','net0','c')]:
        cn=copy.deepcopy(c);cn[device+'extra']=[device+'extra',net,'external_extra' if device=='r' else 'vss','1k' if device=='r' else '1p']
        rows.append(record('regulator',name,cn,d,m,True,False))
    cn=copy.deepcopy(c);cn['mnp'][4]='fb'
    rows.append(record('regulator','regulator_body_consumes_feedback',cn,d,m,True,False))
    cn=copy.deepcopy(c);cn['mnp'][1]='vref'
    rows.append(record('regulator','regulator_reference_is_pass_input',cn,d,m,True,False))
    cn=copy.deepcopy(c);bind(cn,d,'vdd','vout')
    rows.append(record('regulator','regulator_supply_consumes_regulated_output',cn,d,m,True,False))
    for net in ('fb','net0'):
        dn=copy.deepcopy(d);dn['dut'].append(net)
        rows.append(record('regulator','regulator_protected_net_exported_'+net,c,dn,m,True,False))
    c,d,m=read(2637)
    for name,net in [('sample_bias_taps_junction','vcx'),('sample_bias_taps_output','vco'),('sample_bias_aliases_other_bias','vb2'),('sample_bias_is_unexported','orphan')]:
        cn=copy.deepcopy(c);bind(cn,d,'vb1',net)
        rows.append(record('sample',name,cn,d,m,True,False))
    c,d,m=read(2658)
    cn=copy.deepcopy(c);cn['m1'][4]='vcx'
    rows.append(record('sample','sample_body_taps_junction',cn,d,m,True,False))
    for name,out in [('sample_output_is_junction','vcx'),('sample_output_is_ground','vss')]:
        cn=copy.deepcopy(c);bind(cn,d,'out',out);cn['c2'][2]=out
        rows.append(record('sample',name,cn,d,m,True,False))
    dn=copy.deepcopy(d);dn['dut'].remove('phi1')
    rows.append(record('sample','sample_clock_not_external',c,dn,m,True,False))
    for net in ('vcx','net0'):
        dn=copy.deepcopy(d);dn['dut'].append(net)
        rows.append(record('sample','sample_protected_net_exported_'+net,c,dn,m,True,False))
    # Caller choices are orthogonal: identical cards stay a raw positive.
    caller=[]
    for name,raw,allowed,expected in [
      ('literal_unique_eligible',['A'],{'A':True},True),
      ('caller_custom_symbol_wins',['A'],{'A':False},False),
      ('caller_side_hint_wins',['A'],{'A':False},False),
      ('caller_absolute_position_wins',['A'],{'A':False},False),
      ('caller_group_membership_wins',['A'],{'A':False},False),
      ('raw_second_candidate_hidden',['A','B'],{'A':True,'B':False},False),
      ('raw_second_candidate_ineligible',['A','B'],{'A':False,'B':True},False),
      ('raw_candidate_order_permutation',['B','A'],{'A':True,'B':False},False)]:
        result=automatic(raw,allowed);assert result==expected,name
        caller.append(dict(name=name,raw=raw,eligible=allowed,expected=expected,observed=result))
    return rows,caller


def census():
    assignment=ROOT/'docs/research/image-rules/converters_assignment.json'
    expected=json.loads((ROOT/'docs/research/image-rules/converters_cases.json').read_text())
    result={k:[] for k in ('regulator','sample')};hashes={}
    for row in json.loads(assignment.read_text())['images']:
        cid=row['id'];c,d,m=read(int(cid.split('-')[1]));hashes[cid]=sha(ROOT/f'external/examples/analoggenie/{cid}.cir')
        for kind in result:
            if hit:=strengthened(kind,c,d,m):result[kind].append(dict(id=cid,cards=c,**hit))
    for kind,oldkind in [('regulator','pass_divider'),('sample','sampling_cells')]:
        assert [x['id'] for x in result[kind]]==[x['id'] for x in expected[oldkind]],kind+' exact positive name set changed'
    result['bias_sample_names']=[x['id'] for x in result['sample'] if x['topology']['bias_ports']]
    assert result['bias_sample_names']==['ag-2637','ag-2657','ag-2757']
    result['all_deck_hashes']=hashes
    return result


def global_census(shard):
    result={k:[] for k in ('regulator','sample')};hashes={}
    paths=sorted((ROOT/'external/examples/analoggenie').glob('ag-*.cir'),key=lambda p:int(p.stem[3:]))
    assert len(paths)==2202
    for p in paths:
        c,d,m=read(int(p.stem[3:]));hashes[p.stem]=sha(p)
        for kind in result:
            if hit:=strengthened(kind,c,d,m):result[kind].append(dict(id=p.stem,cards=c,**hit))
    for kind in result:
        expected=[x['id'] for x in shard[kind]]
        if kind=='sample':expected=['ag-789']+expected
        assert [x['id'] for x in result[kind]]==expected,kind+' global names differ'
    result['all_deck_hashes']=hashes
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--check',type=Path);args=p.parse_args()
    rows,caller=mutations()
    shard=census()
    result=dict(scope='Additional necessary guards for an automatic local pose; not a full production recognizer.',
                census=shard,full_corpus=global_census(shard),mutation_controls=rows,caller_planning_controls=caller,
                dependencies=old.dependencies(),script_sha256=sha(Path(__file__)),
                prior_proof_sha256=sha(ROOT/'docs/research/image-rules/converters_cases.json'))
    if args.check:assert result==json.loads(args.check.read_text()),'predicate evidence differs'
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'regulator_names':[r['id'] for r in result['census']['regulator']],
                      'sample_names':[r['id'] for r in result['census']['sample']],
                      'falsified_old_cases':[r['name'] for r in rows if r['observed_old'] and not r['observed_new']],
                      'caller_controls':[r['name'] for r in caller]}))

if __name__=='__main__':main()
