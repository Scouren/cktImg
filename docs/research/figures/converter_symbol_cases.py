#!/usr/bin/env python3
"""Replay source-ink certificates for the complete third visual-review shard.

This is a research predicate, not engine code. IDs select reviewed examples
only; the two circuit predicates use complete ports and raw connectivity.
Native sign measurements inspect SVG text marks, not cached source frames.
"""
import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import block_aliases as aliases
import digital_symbols as digital
import remaining_amplifiers as remaining
from cross_caps import actual_glyph, conductor_ink
from converter_loops import wire_tree

KNOWN = frozenset('opamp icm_opamp_vdd_vss voltage_amplifier amp amp1 ea cmp comp comparator a1 ea1 aea'.split())
EXAMPLES = [1674,1707,1709,1730,1752,1768,2182,2187,2190,2199,2212,2277,2280,2365,2376,2415,2420,2434,2435,2444,2452,2460,2486,2550,2637,2657,2658,2665,2699,2757,3177,3327,3437,3492,3493,3495]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = sha(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or '').split('.')[0] + '.py'
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    return dict(sorted(found.items()))


def calls(cards, definitions):
    out = []
    for name, words in cards.items():
        if name[0] != 'x':
            continue
        end = next((i for i,w in enumerate(words) if '=' in w or w == 'params:'), len(words)) - 1
        family = words[end]
        ports = definitions[family]
        assert len(ports) == end - 1
        out.append(dict(card=name, family=family, ports=ports, bindings=words[1:end]))
    return out


def signed(call):
    roles = aliases.contract(call['ports'])
    if call['family'] not in KNOWN or roles is None or not {'positive','negative','output','ground'} <= set(roles):
        return None
    return dict(zip(roles,call['bindings']))


def pass_divider(cards, definitions):
    blocks = calls(cards, definitions)
    mos = [w for k,w in cards.items() if k[0] == 'm']
    resistors = [w for k,w in cards.items() if k[0] == 'r']
    if len(blocks) != 1 or len(mos) != 1 or any(k[0] not in 'xrcm' for k in cards):
        return None
    nets = signed(blocks[0])
    if nets is None or len(set(nets[r] for r in ('positive','negative','output','ground'))) != 4:
        return None
    m = mos[0]
    if m[2] != nets['output'] or len(set(m[1:4])) != 3:
        return None
    found = []
    for output in (m[1],m[3]):
        upper = [r for r in resistors if set(r[1:3]) == {output,nets['negative']}]
        lower = [r for r in resistors if set(r[1:3]) == {nets['negative'],nets['ground']}]
        if len(upper) == len(lower) == 1 and output not in (nets['negative'],nets['positive'],nets['ground']):
            found.append(dict(amplifier=blocks[0], pass_device=m[0], divider=[upper[0][0],lower[0][0]], output=output, nets=nets))
    return found[0] if len(found) == 1 else None


def sample_cell(cards, definitions):
    blocks = calls(cards,definitions)
    mos = [w for k,w in cards.items() if k[0] == 'm']
    caps = [w for k,w in cards.items() if k[0] == 'c']
    if len(blocks) != 1 or len(mos) != 2 or len(caps) != 2 or len(cards) != 5:
        return None
    nets = signed(blocks[0])
    if nets is None or nets['positive'] != nets['ground'] or nets['negative'] in (nets['ground'],nets['output']):
        return None
    if any(len(set(m[1:4])) != 3 for m in mos) or mos[0][2] == mos[1][2]:
        return None
    channels = [set((m[1],m[3])) for m in mos]
    common = channels[0] & channels[1]
    if len(common) != 1:
        return None
    junction = next(iter(common))
    ends = (channels[0] | channels[1]) - common
    if nets['negative'] not in ends or nets['ground'] in channels[0] | channels[1]:
        return None
    if any(m[2] in channels[0] | channels[1] | {nets['output'],nets['ground']} for m in mos):
        return None
    raw_nets = [net for m in mos for net in m[1:5]] + [net for c in caps for net in c[1:3]] + blocks[0]['bindings']
    if any(raw_nets.count(m[2]) != 1 for m in mos):
        return None
    shunt = [c for c in caps if set(c[1:3]) == {junction,nets['ground']}]
    feedback = [c for c in caps if set(c[1:3]) == {nets['negative'],nets['output']}]
    if len(shunt) != 1 or len(feedback) != 1 or shunt[0] == feedback[0]:
        return None
    return dict(amplifier=blocks[0], switches=[m[0] for m in mos], shunt=shunt[0][0], feedback=feedback[0][0],
                junction=junction, nets=nets, bias_ports=[p for p in blocks[0]['ports'] if p in ('vb','vb1','vb2','vb3','bias')])


def source_block(prefix, call):
    human = json.loads(prefix.with_suffix('.human.json').read_text())
    root = ET.parse(prefix.with_suffix('.svg')).getroot()
    dev, group, parent = aliases.source_group(human,root,call['card'])
    body,leads,interior = aliases.primitives(group,parent)
    marks = aliases.polarity_marks(interior)
    triangle = remaining.structure(body,leads,marks)
    bound = dict(zip(call['ports'],call['bindings']))
    assert all(bound.get(p.lower()) == n.lower() for p,n in dev['nets'].items() if n is not None), (prefix.name,call['card'],'cached binding')
    unknown_cached_bindings = sorted(p.lower() for p,n in dev['nets'].items() if n is None)
    mapping = {}
    for port,point in dev['terminals'].items():
        match = [i for i,lead in enumerate(leads) if remaining.glyph.close(point,lead['endpoint'])]
        if len(match) > 1:
            raise ValueError('ambiguous declared actual lead')
        if match and port.lower() not in unknown_cached_bindings:
            mapping[port.lower()] = dict(endpoint=leads[match[0]]['endpoint'],lead=match[0],net=bound[port.lower()])
    return dict(call,source_object=group.get('data-object-id'),body=body,leads=leads,marks=marks,
                triangle=triangle,declared_actual_matches=mapping,unknown_cached_bindings=unknown_cached_bindings,
                unresolved_geometry=sorted(set(call['ports'])-set(mapping)))


def sign_order(root):
    marks = {s:[[float(n.get('x')),float(n.get('y'))] for n in root.iter()
                if n.tag.endswith('text') and ''.join(n.itertext()) == s] for s in ('+','-')}
    if any(len(points) != 1 for points in marks.values()):
        raise ValueError('native single-amplifier sign oracle is ambiguous')
    return dict(marks=marks,positive_above_negative=marks['+'][0][1] < marks['-'][0][1])


def native_signs(path):
    return sign_order(ET.parse(path).getroot())


def primitive(root, device, card):
    names = ('D','G','S','B') if card[0][0] == 'm' else ('1','2')
    assert all(device['nets'][pin].lower() == net for pin,net in zip(names,card[1:])), (device['card'],'raw binding')
    return actual_glyph(root,device)['terminals']


def source_signed(prefix, call):
    human = json.loads(prefix.with_suffix('.human.json').read_text())
    root = ET.parse(prefix.with_suffix('.svg')).getroot()
    device = next(d for d in human['devices'] if d['card'].lower() == call['card'])
    cached = {p.lower(): n for p,n in device['nets'].items()}
    bound = dict(zip(call['ports'],call['bindings']))
    assert all(p in bound and n is not None and n.lower() == bound[p] for p,n in cached.items()), (prefix.name,call['card'],'raw block binding')
    signals = [p for p,r in zip(call['ports'],aliases.contract(call['ports'])) if r in ('positive','negative','output')]
    assert all(p in cached for p in signals), (prefix.name,'missing signal binding')
    proof = aliases.inspect(human,root,call['card'],call['ports'])
    if proof['shape'] != 'triangle' or not proof['marks_agree']:
        raise ValueError('actual signed source triangle changed')
    inputs = [p for p,r in zip(call['ports'],aliases.contract(call['ports'])) if r in ('positive','negative')]
    assert all(proof['signal_frame_matches'][p] for p in inputs), (prefix.name,'cached input does not reach its own marked lead')
    return proof, human, root


def methods(examples):
    prefix = examples/'analoggenie/ag-2187'
    text = prefix.with_suffix('.cir').read_text()
    c,d = aliases.read_cards(text),digital.declarations(text)
    checks = []
    def check(name, yes, cards, defs=d):
        assert (pass_divider(cards,defs) is not None) == yes,name
        checks.append(name)
    check('literal_pass_divider_accept',True,c)
    for name,change in (
        ('reject_second_pass',lambda x:x.update(mother=['mother','vin','net0','vout','vss','nch'])),
        ('reject_duplicate_upper_resistor',lambda x:x.update(rx=['rx',*x['r1'][1:]])),
        ('reject_gate_binding_change',lambda x:x['mnp'].__setitem__(2,'other')),
        ('reject_feedback_binding_change',lambda x:x['x1'].__setitem__(3,'other'))):
        m=copy.deepcopy(c);change(m);check(name,False,m)
    dd=copy.deepcopy(d);dd['opamp'].append('vx');cc=copy.deepcopy(c);cc['x1'].insert(-1,'vx');check('reject_extra_auxiliary_port',False,cc,dd)
    dd=copy.deepcopy(d);cc=copy.deepcopy(c);dd['opamp'].reverse();cc['x1'][1:-1]=list(reversed(cc['x1'][1:-1]));check('accept_declared_port_permutation',True,cc,dd)
    cc={k:[('changed_'+w if w in {'net0','fb','vout','vref','vin'} else w) for w in row] for k,row in c.items()};check('accept_net_renaming',True,cc)
    for cid,expected in ((2637,True),(2658,True),(2699,False),(3177,False)):
        t=(examples/f'analoggenie/ag-{cid}.cir').read_text();assert (sample_cell(aliases.read_cards(t),digital.declarations(t)) is not None)==expected
        checks.append('sample_'+str(cid)+'_'+str(expected).lower())
    t=(examples/'analoggenie/ag-2637.cir').read_text();cc=aliases.read_cards(t);dd=digital.declarations(t)
    phase=cc['m1'][2]
    for name,change in (('sample_reject_phase_on_body',lambda x:x['m2'].__setitem__(4,phase)),
                        ('sample_reject_phase_on_bias',lambda x:x['x1'].__setitem__(1+dd['opamp'].index('vb1'),phase))):
        mutation=copy.deepcopy(cc);change(mutation);assert sample_cell(mutation,dd) is None,name;checks.append(name)
    root=ET.fromstring('<svg><text x="0" y="10">+</text><text x="0" y="20">-</text></svg>')
    assert sign_order(root)['positive_above_negative'];checks.append('literal_native_sign_order')
    root[0].set('y','30');assert not sign_order(root)['positive_above_negative'];checks.append('reject_swapped_native_sign_order')
    root.append(copy.deepcopy(root[0]))
    try:
        sign_order(root)
    except ValueError:
        checks.append('reject_ambiguous_native_sign_count')
    else:
        raise AssertionError('duplicate sign accepted')
    return checks


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--assignment',type=Path,required=True)
    p.add_argument('--examples',type=Path,required=True)
    p.add_argument('--native-dir',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--check',type=Path)
    args=p.parse_args(); assignment=json.loads(args.assignment.read_text())
    selected=[];sampling=[];examples=[];input_hashes={}
    for row in assignment['images']:
        cid=row['id'];prefix=args.examples/'analoggenie'/cid
        for suffix,field in (('.cir','netlist'),('.svg','source_svg'),('.human.json','source_json')):
            assert sha(prefix.with_suffix(suffix))==row[field+'_sha256'],(cid,field)
        input_hashes[cid]={k:row[k] for k in ('netlist_sha256','source_svg_sha256','source_json_sha256','native_svg_sha256')}
        text=prefix.with_suffix('.cir').read_text();cards=aliases.read_cards(text);defs=digital.declarations(text)
        hit=pass_divider(cards,defs)
        if hit:
            proof,human,root=source_signed(prefix,hit['amplifier']);signals=proof['actual_signal_leads']
            actual=primitive(root,next(d for d in human['devices'] if d['card'].lower()==hit['pass_device']),cards[hit['pass_device']])['G']
            path=wire_tree(conductor_ink(root),[signals['output'],actual])
            assert path is not None,'source apex must meet declared pass gate'
            native=args.native_dir/(cid+'.ours.svg');assert sha(native)==row['native_svg_sha256']
            selected.append(dict(id=cid,topology=hit,source_signals=signals,source_marks=proof['source_marks'],source_body=proof['body'],
                source_positive_above_negative=signals['positive'][1]<signals['negative'][1],source_gate=actual,source_output_gate_path=path,
                source_cached_mismatches=proof['signal_frame_mismatches'],source_missing_ports=proof['missing_source_ports'],native=native_signs(native)))
        hit=sample_cell(cards,defs)
        if hit:
            proof,human,root=source_signed(prefix,hit['amplifier']);devices={d['card'].lower():d for d in human['devices']}
            actual={n:primitive(root,devices[n],cards[n]) for n in hit['switches']+[hit['shunt'],hit['feedback']]}
            feedback=list(actual[hit['feedback']].values());shunt=list(actual[hit['shunt']].values());signals=proof['actual_signal_leads']
            relations=dict(flat_switches=all(actual[n]['D'][1]==actual[n]['S'][1] for n in hit['switches']),
                           upright_shunt=shunt[0][0]==shunt[1][0],flat_feedback=feedback[0][1]==feedback[1][1],
                           feedback_above_amplifier=max(p[1] for p in feedback)<min(signals['negative'][1],signals['output'][1]))
            sampling.append(dict(id=cid,topology=hit,actual_source_terminals=actual,source_amplifier_signals=proof['actual_signal_leads'],source_relations=relations,source_missing_ports=proof['missing_source_ports']))
        if int(cid.split('-')[1]) in EXAMPLES:
            examples.append(dict(id=cid,blocks=[source_block(prefix,call) for call in calls(cards,defs)]))
    result=dict(scope='Exactly the 734 assigned source/native overviews; source predicates are bounded research, not implementation.',
                assignment_sha256=sha(args.assignment),input_hashes=input_hashes,dependencies=dependencies(),method_checks=methods(args.examples),
                pass_divider=selected,sampling_cells=sampling,selected_block_examples=examples)
    result = json.loads(json.dumps(result))  # Normalize SVG tuple vertices to the serialized schema.
    if args.check:
        assert result==json.loads(args.check.read_text()),'frozen evidence differs'
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'pass_divider_names':[r['id'] for r in selected],
                      'sampling_plain':[r['id'] for r in sampling if not r['topology']['bias_ports']],
                      'sampling_bias':[r['id'] for r in sampling if r['topology']['bias_ports']],
                      'method_checks':result['method_checks']},indent=2))


if __name__=='__main__':
    main()
