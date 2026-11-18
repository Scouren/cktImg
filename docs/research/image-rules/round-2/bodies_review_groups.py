#!/usr/bin/env python3
"""Independent adversarial review; records pre-fix holes or verifies peer repair."""
import argparse
import copy
import json
from pathlib import Path
from bodies_census import ROOT, BASE, sha
import groups_candidates as candidate
import groups_evidence as evidence

HERE=Path(__file__).resolve().parent


def accepted(call):
    try:
        value=call()
    except (AssertionError,ValueError) as error:
        return dict(accepted=False,error=str(error),exception=type(error).__name__)
    return dict(accepted=True,value=value)


def attacks():
    deck='''.subckt dut a b o1 o2 vss
M1 o1 a s vss n
M2 o2 b s vss n
M3 s bias vss vss n
.ends'''
    cards=candidate.read_cards(deck);rails={'vss'}
    literal=candidate.census(cards,rails)
    assert literal['raw_source_regions'][0]['disposition']=='shape_candidate_pending_ownership'
    q4=copy.deepcopy(cards);q4['qx']=['qx','c','base','e','s','npnmod']
    qresult=candidate.census(q4,rails)['raw_source_regions'][0]
    qaccepted=qresult['disposition']=='shape_candidate_pending_ownership'
    unsupported_q={suffix:candidate.terminals(['qx','c','base','e','npnmod',suffix])
                   for suffix in ('off','on','2')}
    # An ineligible third source still has to participate in raw uniqueness.
    third=copy.deepcopy(cards);third['m4']=['m4','other','a','s','vss','different_model']
    tr=candidate.census(third,rails)['raw_source_regions'][0]
    assert tr['members']==['m1','m2','m4'] and 'not_exactly_two_sources' in tr['reasons']
    fourbody=copy.deepcopy(cards);fourbody['m1'][4]='s'
    br=candidate.census(fourbody,rails)['raw_source_regions'][0]
    assert 'nonprivate_incidence' in br['reasons']
    expected=json.loads((HERE/'groups_expected.json').read_text())['ag-459']
    examples=ROOT/'external/examples/analoggenie';native=BASE/'image-rule-round-2/groups/native'
    original=evidence.certify('ag-459',examples,native,expected)
    results={}
    for name in ('reverse_owned_rows','swap_current_source_owners','swap_resistor_owners'):
        changed=copy.deepcopy(expected)
        if name=='reverse_owned_rows':changed['owned'].reverse()
        else:
            left,right=('i1','i3') if name=='swap_current_source_owners' else ('r1','r2')
            ai=changed['owned'][0].index(left);bi=changed['owned'][1].index(right)
            changed['owned'][0][ai],changed['owned'][1][bi]=right,left
        results[name]=accepted(lambda: evidence.certify('ag-459',examples,native,changed)['literal_ownership'])
    raw_path=BASE/'image-rule-round-2/bodies/census.json'
    raw=json.loads(raw_path.read_text());groups=json.loads((HERE/'groups_census.json').read_text())
    qrows=[];hits=[]
    for circuit in raw['circuits']:
        for row in circuit['rows']:
            if row['kind']!='q' or len(row['nets'])!=4:continue
            qrows.append([circuit['id'],row['card'],row['nets']])
            for region in groups['cases'][circuit['id']]['raw_source_regions']:
                if row['nets'][3] in region['nets']:hits.append([circuit['id'],row['card'],region['members']])
    return dict(peer_sha256={p.name:sha(p) for p in (HERE/'groups_candidates.py',HERE/'groups_evidence.py',HERE/'groups_expected.json',HERE/'groups_census.json')},
        independent_raw_census_sha256=sha(raw_path),literal_deck=deck,
        missing_substrate=dict(mutated_card=q4['qx'],expected_incidence=['qx',3,'s'],
                               false_candidate_survived=qaccepted,observed=qresult),
        unsupported_Q_suffixes=unsupported_q,
        ownership_mutations=results,positive_original_owner_partition=original['literal_ownership'],
        passing_controls=dict(third_ineligible_raw_source_counted=tr,source_body_occurrence_not_filtered=br),
        actual_four_node_Q_rows=qrows,actual_Q_substrate_source_region_hits=hits)


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path)
    ap.add_argument('--require-fixed',action='store_true');args=ap.parse_args();r=attacks()
    if args.require_fixed:
        assert not r['missing_substrate']['false_candidate_survived']
        assert all(value is None for value in r['unsupported_Q_suffixes'].values())
        assert all(not x['accepted'] for x in r['ownership_mutations'].values())
    args.output.write_text(json.dumps(r,indent=2)+'\n')
    print(dict(substate_false_candidate=r['missing_substrate']['false_candidate_survived'],
        ownership={k:v['accepted'] for k,v in r['ownership_mutations'].items()},
        actual_Q4=len(r['actual_four_node_Q_rows']),actual_Q_hits=r['actual_Q_substrate_source_region_hits']))


if __name__=='__main__':main()
