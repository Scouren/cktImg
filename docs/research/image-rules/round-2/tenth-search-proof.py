#!/usr/bin/env python3
"""Exact finite-map literals and search-completeness contract; no production run."""
import argparse
import copy
import importlib.util
import itertools
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from bodies_census import ROOT, BASE, sha

RUN = BASE / 'image-rule-round-2/bodies/tenth-search'
SNAPSHOT = RUN / 'ninth-census-reviewed.py'


def load_snapshot():
    spec = importlib.util.spec_from_file_location('reviewed_ninth', SNAPSHOT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def key(mapping):
    return (tuple(sorted(mapping['devices'].items())), tuple(sorted(mapping['nets'].items())))


def nontrivial(mapping):
    return any(a != b for a, b in mapping['nets'].items())


def contract(maps, complete, unsupported=None):
    """Proposed cold decision seam; input map validity is checked separately."""
    if unsupported:
        return dict(status='unsupported', reason=unsupported)
    real = sorted({key(m) for m in maps if nontrivial(m)})
    if len(real) >= 2:
        return dict(status='ambiguous', witnesses=real[:2], complete_enumeration_claim=False)
    if not complete:
        return dict(status='exhausted', valid_nontrivial_witnesses_seen=len(real))
    return dict(status='complete_unique' if real else 'complete_none', witnesses=real)


def pair_family(count):
    """Each distinct model admits only its own pair's independent fix/swap."""
    models = ['.model n%d nmos' % i for i in range(count)]
    formals, cards = ['vss'], []
    for i in range(count):
        for j in range(2):
            d, g = 'd%d%d' % (i, j), 'g%d%d' % (i, j)
            formals.extend([d, g])
            cards.append('M%d%d %s %s vss vss n%d' % (i, j, d, g, i))
    return '\n'.join(['independent symmetric MOS pairs'] + models +
                     ['.subckt dut ' + ' '.join(formals)] + cards + ['.ends dut', ''])


def literal_maps(count):
    """Cartesian pair choices, independent of incidence colors/backtracking."""
    result = []
    for bits in itertools.product((0, 1), repeat=count):
        devices, nets = {}, {'vss': 'vss'}
        for i, bit in enumerate(bits):
            for j in range(2):
                devices['m%d%d' % (i, j)] = 'm%d%d' % (i, j ^ bit)
                for role in ('d', 'g'):
                    nets[role + '%d%d' % (i, j)] = role + '%d%d' % (i, j ^ bit)
        result.append(dict(devices=devices, nets=nets))
    return sorted(result, key=key)


def validate_literal(maps, expected):
    allowed = {key(m) for m in expected}
    assert all(key(m) in allowed for m in maps), 'map violates exact independent-pair oracle'


def evaluate(module, values, states=100000, maps=256):
    previous = module.LIMIT_STATES, module.LIMIT_MAPS
    try:
        module.LIMIT_STATES, module.LIMIT_MAPS = states, maps
        return module.decompose(*values)
    finally:
        module.LIMIT_STATES, module.LIMIT_MAPS = previous


def measured(row):
    return dict(disposition=row['disposition'], entry_attempts=row.get('search_states'),
                stored_complete_maps=len(row.get('enumerated_involutions', [])),
                nontrivial_maps_seen=row.get('nontrivial_net_involution_count'),
                enumeration_complete=row.get('enumeration_complete'), reasons=row['reasons'])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE / 'tenth-search-evidence.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    module = load_snapshot()
    families = {}
    for count in (1, 2, 3, 4, 5, 6, 9):
        text = pair_family(count)
        path = RUN / ('pairs%d.cir' % count)
        path.write_text(text)
        row = evaluate(module, module.facts(text))
        expected = literal_maps(count)
        actual = row['enumerated_involutions']
        want = {key(m) for m in expected}
        validate_literal(actual, expected)
        if count < 9:
            assert row['enumeration_complete'] and {key(m) for m in actual} == want
        else:
            assert not row['enumeration_complete'] and len(actual) == 257
            assert row['disposition'] == 'decline_enumeration_bound'
        families['pairs%d' % count] = dict(path=str(path.relative_to(ROOT)), sha256=sha(path),
                                         literal_complete_map_count=len(expected),
                                         literal_nontrivial_count=len(expected) - 1,
                                         observed=measured(row), proposed_contract=contract(actual, row['enumeration_complete']))
    values = module.facts(pair_family(2))
    cut = evaluate(module, values, states=6)
    assert len(cut['enumerated_involutions']) == 2 and cut['nontrivial_net_involution_count'] == 1
    assert cut['disposition'] == 'decline_enumeration_bound' and not cut['enumeration_complete']
    assert contract(cut['enumerated_involutions'], False)['status'] == 'exhausted'
    # Deliberately wrong consumer: exactly one observed map becomes "unique".
    unsafe = len([m for m in cut['enumerated_involutions'] if nontrivial(m)]) == 1
    assert unsafe and len(literal_maps(2)) - 1 == 3
    map_one = evaluate(module, module.facts(pair_family(1)), maps=1)
    assert map_one['enumeration_complete'] and len(map_one['enumerated_involutions']) == 2
    partial_ambiguous = literal_maps(2)[:3]
    assert contract(partial_ambiguous, False)['status'] == 'ambiguous'
    assert contract([literal_maps(1)[0]], False)['status'] == 'exhausted'
    assert contract([literal_maps(1)[0]], True)['status'] == 'complete_none'
    assert contract(literal_maps(1), True)['status'] == 'complete_unique'
    assert contract(literal_maps(1), True, 'unsupported body ownership')['status'] == 'unsupported'
    # Global ambiguity does not imply ambiguity of every separately bounded
    # owner question. These local questions include complete interface facts.
    local_questions = []
    raw, formals, models, rails, declarations = module.facts(pair_family(2))
    for model in sorted(models):
        selected = {d: c for d, c in raw.items() if c[5] == model}
        used = {n for c in selected.values() for n in c[1:5]}
        assert len(selected) == 2
        assert not any(n in used - set(rails) for d, c in raw.items() if d not in selected for n in c[1:5])
        local = evaluate(module, (selected, [n for n in formals if n in used], models, rails, declarations))
        verdict = contract(local['enumerated_involutions'], local['enumeration_complete'])
        assert verdict['status'] == 'complete_unique'
        local_questions.append(dict(members=sorted(selected), formal_interfaces=sorted(used - set(rails)),
                                    no_outside_nonrail_incidence=True, proposed_contract=verdict))
    # A map can be geometrically unusable without invalidating this raw verdict.
    mutated = copy.deepcopy(literal_maps(2))
    mutated[1]['devices']['m00'] = 'm10'
    try:
        validate_literal(mutated, literal_maps(2))
    except AssertionError:
        pass
    else:
        raise AssertionError('wrong-model mate survived the same literal checker')
    corpus_path = HERE / 'ninth-local-groups-census.json'
    census = json.loads(corpus_path.read_text())
    corpus_rows = {name: dict(entry_attempts=row['search_states'], devices=len(row['ordered_cards']),
                              nets=len({n for c in row['ordered_cards'] for n in c[1:5]}),
                              returned_maps=len(row['enumerated_involutions']),
                              complete=row['enumeration_complete'], disposition=row['disposition'])
                   for name, row in census['cases'].items() if 'search_states' in row}
    assert len(corpus_rows) == 86 and all(r['complete'] for r in corpus_rows.values())
    actual_cuts = {}
    for name in ('ag-1080', 'ag-1078'):
        values = module.facts((ROOT / 'external/examples/analoggenie' / (name + '.cir')).read_text())
        full = evaluate(module, values)
        choices, prefixes = [], {}
        for budget in range(1, full['search_states']):
            row = evaluate(module, values, states=budget)
            assert not row['enumeration_complete'] and row['disposition'] == 'decline_enumeration_bound'
            prefixes.setdefault(str(row['nontrivial_net_involution_count']), []).append(budget)
            if row['nontrivial_net_involution_count'] == 1:
                choices.append((budget, row))
        if name == 'ag-1080':
            assert not choices and set(prefixes) == {'0'}
        else:
            assert choices
        budget, row = choices[0] if choices else (full['search_states'] - 1,
            evaluate(module, values, states=full['search_states'] - 1))
        actual_cuts[name] = dict(full=measured(full), selected_incomplete_budget=budget,
                                 prefix_budgets_by_nontrivial_count=prefixes,
                                 partial=measured(row), proposed_contract=contract(row['enumerated_involutions'], False))
    result = dict(scope='Executed research snapshot and exact independent-pair reference only; no production symmetry execution, timing or production budget recommendation.',
                  families=families, state_prefix_control=dict(state_budget=6, observed=measured(cut),
                  unsafe_count_only_consumer_would_claim_unique=unsafe, literal_full_nontrivial_maps=3,
                  correct_contract=contract(cut['enumerated_involutions'], False)),
                  non_strict_map_capacity_control=dict(declared_limit=1, observed=measured(map_one)),
                  reference_outcomes=['complete_none', 'complete_unique', 'ambiguous', 'unsupported', 'exhausted'],
                  partial_ambiguity_is_conclusive=contract(partial_ambiguous, False),
                  separate_local_questions_despite_global_ambiguity=local_questions,
                  wrong_model_pair_mapping_rejected_by_literal_oracle=True,
                  actual_corpus_cut_controls=actual_cuts, corpus_searches=corpus_rows,
                  corpus_totals=dict(searches=len(corpus_rows), entry_attempts=sum(r['entry_attempts'] for r in corpus_rows.values()),
                                     returned_maps=sum(r['returned_maps'] for r in corpus_rows.values()),
                                     max_entry_attempts=max(r['entry_attempts'] for r in corpus_rows.values()),
                                     max_entry_names=sorted(n for n, r in corpus_rows.items() if r['entry_attempts'] == 51),
                                     max_returned_maps=max(r['returned_maps'] for r in corpus_rows.values())),
                  provenance={str(p.relative_to(ROOT)): sha(p) for p in [Path(__file__), SNAPSHOT, corpus_path,
                      ROOT / 'src/symmetry.zig', HERE / 'current-worktree-rules.md']})
    # JSON-native tuples before exact replay, preserving the earlier census lesson.
    result = json.loads(json.dumps(result))
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result['corpus_totals']))
    print(json.dumps({k: v['observed'] for k, v in families.items()}))


if __name__ == '__main__':
    main()
