#!/usr/bin/env python3
"""Independent raw-quad overlap probes and complete corpus set verification."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import quad_candidates as quad
import quad_equivalence as equivalence

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def probes():
    _, rows = quad.bodies_census.parse('''
.model n nmos
.subckt dut ga gb s1 s2 d1 d2 d3 bulk
M1 d1 ga s1 bulk n w=1
M2 d2 gb s1 bulk n w=1
M3 d3 ga s1 bulk n w=1
M4 d1 gb s2 bulk n w=1
M5 d2 ga s2 bulk n w=1
M6 d3 gb s2 bulk n w=1
.ends dut
''')
    raw, selected = quad.candidates(rows), quad.selected(rows)
    assert len(raw) == 3 and len(selected) == 2
    expected = [['m1', 'm2', 'm4', 'm5'], ['m2', 'm3', 'm5', 'm6']]
    assert [r['members'] for r in selected] == expected
    assert quad.candidates(list(reversed(rows))) == raw
    changed = copy.deepcopy(rows[:2] + rows[3:5])
    assert len(quad.selected(changed)) == 1
    # Raw shape deliberately survives non-MOS attachment; placement ownership
    # would need complete incidence and a unique whole-context certificate.
    capacitor = dict(card='cx', kind='c', roles=['1','2'], nets=['s1','outside'],
                     nonterminal_tokens=['1p'], raw='Cx s1 outside 1p')
    assert quad.selected(changed + [capacitor]) == quad.selected(changed)
    return dict(ordered_rows=rows, raw=raw, selected=selected,
                overlapping_members=['m2', 'm5'], eligibility_must_not_remove_competitor=True,
                extra_capacitor=capacitor, non_MOS_incidence_does_not_change_raw_shape=True)


def full_review():
    record = json.loads((HERE/'quad_candidates.json').read_text())
    index = json.loads((ROOT/'external/examples/analoggenie/index.json').read_text())
    assert set(record['deck_sha256']) == {r['id'] for r in index}
    assert set(record['deck_sha256']) == {p.stem for p in (ROOT/'external/examples/analoggenie').glob('*.cir')}
    for name, digest in record['deck_sha256'].items():
        assert sha(ROOT/f'external/examples/analoggenie/{name}.cir') == digest
    assert [r['id'] for r in record['shape_candidates']] == ['ag-'+str(n) for n in quad.EXPECTED]
    assert len(record['raw_candidates']) == 5811
    return dict(index_sha256=sha(ROOT/'external/examples/analoggenie/index.json'),
                inventory_names=sorted(record['deck_sha256']),
                exact_shape_members=[dict(id=r['id'],members=r['members']) for r in record['shape_candidates']],
                raw_candidates=len(record['raw_candidates']))


def views():
    notes = {80:'Source and native place the two source pairs beside one another.',
             82:'Source places M1/M2 outside M3/M4; native uses adjacent source pairs.',
             647:'Source and native use adjacent pairs with orthogonal output bars; a diagonal is not required.',
             805:'Source timing quad M7-M10 uses horizontal channels on distinct paths beside the amplifier; native disperses it among other stages. This is not an isolated single-row mixer.',
             1093:'Source quad M5-M8 has outputs above/below in a two-by-two stage; native puts these devices in one wide row. Raw shape does not choose a horizontal single-row pose.'}
    result=[]
    inventory={r['id']:r for r in json.loads((ROOT/'.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-audit/all-images.json').read_text())}
    for n,note in notes.items():
        for side in ('source','native'):
            paths=[HERE/f'figures/quads/ag-{n}-{side}_svg.png']
            if n in (805,1093):paths.append(HERE/f'figures/groups/quad-ag-{n}-{side}.png')
            for path in paths:
                result.append(dict(id=f'ag-{n}',side=side,path=str(path.relative_to(ROOT)),sha256=sha(path),
                                   actual_view=True,observation=note,
                                   artifact_sha256=inventory[f'ag-{n}'][side+'_svg_sha256']))
    return result


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--check',type=Path)
    args=ap.parse_args()
    result=dict(scope=__doc__,script_sha256=sha(Path(__file__)),
                peer_sha256={p.name:sha(p) for p in (HERE/'quad_candidates.py',HERE/'quad_equivalence.py',HERE/'bodies_census.py')},
                probes=probes(),census=full_review(),actual_views=views(),
                role_boundary=dict(transport=equivalence.NETS,
                                   implementation_sha256={p.name:sha(p) for p in (ROOT/'src/library.zig',ROOT/'src/schematic.zig')},
                                   raw_ordered_cards_equivalent=True,
                                   current_name_inferred_roles_preserved=False,
                                   examples=[['vin+','input','vcont+','internal'],['vcont1','internal','vin+','input']],
                                   source='src/library.zig spellings .net and src/schematic.zig roleFromName',
                                   claim='Topology-only ambiguity, not equivalent default role-coloured engine input.'))
    result=json.loads(json.dumps(result))
    if args.check:assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
    print(json.dumps(dict(raw_candidates=result['census']['raw_candidates'],shape_candidates=len(result['census']['exact_shape_members']),
                          overlap_embeddings=len(result['probes']['selected']),actual_views=len(result['actual_views']))))


if __name__=='__main__':main()
