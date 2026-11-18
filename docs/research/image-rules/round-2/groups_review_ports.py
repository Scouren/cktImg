#!/usr/bin/env python3
"""Independent cross-review probes and exact composed candidate census.

No production edits. A probe can expose an unimplemented rejection boundary;
its observed value is retained alongside the desired contract disposition.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
import ports_contracts as contracts
import ports_predicates as predicates
import interaction_candidates as interactions


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contract_probes():
    _, cards, defs = contracts.deck(2212)
    call = contracts.prior.calls(cards, defs)[0]
    rows = []
    for label, delta in [('missing_binding', -1), ('extra_binding', 1)]:
        changed = copy.deepcopy(call)
        if delta < 0:
            changed['bindings'].pop()
        else:
            changed['bindings'].append('unexpected')
        rows.append(dict(name=label, call=changed, required_contract=None,
                         observed_contract=contracts.candidate(changed),
                         observed_interaction_contract=interactions.extended_signed(changed)))
    permutations = []
    original_roles = interactions.extended_signed(call)
    for output_index in range(9):
        pairs = [(p, n) for p, n in zip(call['ports'], call['bindings']) if p != 'out']
        pairs.insert(output_index, ('out', 'net0'))
        changed = copy.deepcopy(call)
        changed['ports'], changed['bindings'] = map(list, zip(*pairs))
        assert contracts.candidate(changed) == 'four_bias_signed'
        assert interactions.extended_signed(changed) == original_roles
        assert changed['ports'][output_index] == 'out'
        permutations.append(dict(call=changed, output_index=output_index,
                                 bits_required=max(1, output_index.bit_length())))
    return rows, permutations


def lead_probe():
    body = [(-6, -6), (-6, 6), (6, 0)]
    path = [(-6, 0), (-8, 0), (0, 0), (8, 0)]
    try:
        result = contracts.own_lead(body, dict(path=path))
    except (AssertionError, ValueError):
        result = None
    return dict(name='exits_then_reenters_body', body=body, path=path,
                required_rejection=True, observed_rejection=result is None,
                accepted_record=result)


def bias_index_probe():
    # Literal consumer-ready binding, not a claim that today's 8-port reader
    # admits the proposed extension. The future recognition change exposes i=8.
    call = dict(card='xa', family='opamp',
                ports='vdd vss inn inp out vb2 vb3 vb4 vb1'.split(),
                bindings='vdd vss signal_n signal_p result vb2 vb3 vb4 local_control'.split())
    peer = dict(card='xb', family='bias', ports='vdd vss nb'.split(),
                bindings='vdd vss local_control'.split())
    assert contracts.candidate(call) == 'four_bias_signed'
    assert call['bindings'][:2] == peer['bindings'][:2]
    incidence = [[c['card'], i, p] for c in (call, peer)
                 for i, (p, net) in enumerate(zip(c['ports'], c['bindings'])) if net == 'local_control']
    assert incidence == [['xa', 8, 'vb1'], ['xb', 2, 'nb']]
    assert 8 > (1 << 3) - 1 and 2 <= (1 << 3) - 1
    return dict(amplifier=call, peer=peer, internal_net='local_control', ordered_incidence=incidence,
                existing_consumer='bias_neighbors.Pair.pins: [2]u3; find @intCast(i)',
                current_eight_port_contract_admits=False, proposed_contract_admits=True,
                amplifier_index=8, amplifier_bits_required=4, peer_index=2, peer_bits_required=2,
                production_execution_claim=False)


def incidence_probes():
    rows = []
    previous = predicates.old.signed
    predicates.old.signed = interactions.extended_signed
    try:
        for seed in (2187, 2212):
            cards, definitions, models = predicates.read(seed)
            assert predicates.strengthened('regulator', cards, definitions, models)
            for label in ('supply_at_regulated_output', 'exported_gate', 'exported_feedback'):
                cs, ds = copy.deepcopy(cards), copy.deepcopy(definitions)
                if label == 'supply_at_regulated_output':
                    predicates.bind(cs, ds, 'vdd', 'vout')
                else:
                    ds['dut'].append('net0' if label == 'exported_gate' else 'fb')
                hit = predicates.strengthened('regulator', cs, ds, models)
                rows.append(dict(seed=seed, name=label, cards=cs, definitions=ds,
                                 models=models, conservative_pose_requires_decline=True,
                                 observed_acceptance=hit is not None, accepted_record=hit))
        cards, definitions, models = predicates.read(2658)
        for label, net in [('sample_exported_junction', 'vcx'), ('sample_exported_negative', 'net0')]:
            ds = copy.deepcopy(definitions)
            ds['dut'].append(net)
            hit = predicates.strengthened('sample', cards, ds, models)
            rows.append(dict(seed=2658, name=label, cards=cards, definitions=ds,
                             models=models, conservative_pose_requires_decline=True,
                             observed_acceptance=hit is not None, accepted_record=hit))
    finally:
        predicates.old.signed = previous
    return rows


def composed_census():
    paths = sorted((ROOT / 'external/examples/analoggenie').glob('ag-*.cir'))
    names = [p.stem for p in paths]
    index = sorted(x['id'] for x in json.loads((ROOT / 'external/examples/analoggenie/index.json').read_text()))
    assert names == index
    prior = json.loads((HERE / 'interaction_candidates.json').read_text())
    assert set(prior['deck_sha256']) == set(names)
    results = dict(old=dict(regulator={}, sample={}), extended=dict(regulator={}, sample={}))
    previous = predicates.old.signed
    try:
        for p in paths:
            assert digest(p) == prior['deck_sha256'][p.stem]
            cards, defs, models = predicates.read(int(p.stem[3:]))
            for mode, function in [('old', interactions.ORIGINAL_SIGNED), ('extended', interactions.extended_signed)]:
                predicates.old.signed = function
                for kind in ('regulator', 'sample'):
                    hit = predicates.strengthened(kind, cards, defs, models)
                    if hit is not None:
                        results[mode][kind][p.stem] = hit
                        # Compare acceptance under card order and equal formal/net transport.
                        assert predicates.strengthened(kind, dict(reversed(list(cards.items()))), defs, models)
                        changed_cards, changed_defs = predicates.rename(cards, defs)
                        assert predicates.strengthened(kind, changed_cards, changed_defs, models)
    finally:
        predicates.old.signed = previous
    for mode, key in [('old', 'full_corpus_old'), ('extended', 'full_corpus_four_bias_extension')]:
        for kind, earlier_kind in [('regulator', 'regulator'), ('sample', 'sampling')]:
            assert results[mode][kind].keys() == prior[key][earlier_kind].keys()
    assert results['extended']['sample'] == results['old']['sample']
    assert set(results['extended']['regulator']) - set(results['old']['regulator']) == {'ag-2212'}
    for name, row in results['old']['regulator'].items():
        assert results['extended']['regulator'][name] == row
    return dict(names=names, index_sha256=digest(ROOT / 'external/examples/analoggenie/index.json'),
                records=results, controls=['card_order_acceptance', 'equal_formal_net_transport_acceptance',
                                         'exact_names_match_independent_interaction_census'])


def views():
    notes = {
        2212: 'Source positive reference above negative feedback, four separate bias leads including a bent fourth; native nine-port box puts negative above positive. Glyph recognition and pose are distinct.',
        808: 'Source comparator has a bottom clock and the separate opamp has IB. Native boxes both. Four switches and two blocks prohibit treating the clocked glyph contract as the two-switch sampling owner.',
        1242: 'Actual source EA faces left with positive above negative and four biases; native box faces right in a larger converter. Exact contract does not grant complete converter placement.',
        2637: 'Biased source sampling pair is flat with shunt and top feedback. Native retains flat switches but puts feedback far left and shunt far below; recognizing bias leads alone did not select this local pose.',
        789: 'Source/native both retain the flat two-switch path, junction shunt and upper feedback. This keep is outside the old converter shard.'}
    records = []
    for n, observation in notes.items():
        for side in ('source', 'native'):
            path = HERE / f'figures/ports/ag-{n}-{side}.png'
            artifact = ROOT / (f'external/examples/analoggenie/ag-{n}.svg' if side == 'source' else f'.objective/human-schematic-equivalence/runs/iteration21-resume1/gallery-preview/img/ag-{n}.ours.svg')
            records.append(dict(id=f'ag-{n}', side=side, actual_view=True, observation=observation,
                                path=str(path.relative_to(ROOT)), sha256=digest(path),
                                underlying_svg=str(artifact.relative_to(ROOT)), underlying_sha256=digest(artifact)))
    return records


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    probes, permutations = contract_probes()
    result = dict(scope='Adversarial port/interaction research review, not engine execution or automatic placement authority.',
                  peer_sha256={p.name: digest(p) for p in [HERE / (s + '.py') for s in
                              ('ports_contracts', 'ports_predicates', 'interaction_candidates')]},
                  script_sha256=digest(Path(__file__)), contract_probes=probes,
                  output_index_permutations=permutations, lead_probe=lead_probe(),
                  additional_index_consumer=bias_index_probe(),
                  incidence_probes=incidence_probes(), composed=composed_census(), views=views())
    result = json.loads(json.dumps(result))
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(contract_probe_results=[r['observed_contract'] for r in probes],
                          lead_reentry_rejected=result['lead_probe']['observed_rejection'],
                          incidence_acceptances=[r['observed_acceptance'] for r in result['incidence_probes']],
                          composition={mode: {kind: len(v) for kind, v in d.items()} for mode, d in result['composed']['records'].items()})))


if __name__ == '__main__':
    main()
