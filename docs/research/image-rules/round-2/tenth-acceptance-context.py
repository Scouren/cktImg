#!/usr/bin/env python3
"""Three frozen native literals distinguish raw context from rendered output."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
RUN = BASE / 'image-rule-round-2/ports/tenth-acceptance-context'
BINARY = BASE / 'resistor-output-integrated-common/zig-out/bin/cktimg-json'
BINARY_SHA = 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'
SOURCE = ROOT / 'external/examples/analoggenie/ag-1080.cir'
REFERENCE = BASE / 'image-rule-round-2/groups/ninth/ag-1080.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def module():
    sys.path.insert(0, str(HERE))
    spec = importlib.util.spec_from_file_location('tenth_raw_context', HERE / 'ninth-local-groups-census.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--output', type=Path, default=HERE / 'tenth-acceptance-context.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    assert sha(BINARY) == BINARY_SHA
    oracle = module()
    source = SOURCE.read_text()
    base = oracle.decompose(*oracle.facts(source))
    assert base['disposition'] == 'raw_multigroup_candidate'
    reference = json.loads(REFERENCE.read_text())
    edits = {
        'duplicate_model': ('.model nch nmos', '.model nch pmos\n.model nch nmos', 'duplicate_model_definition'),
        'unused_continued_formal': ('CLKB OUTP OUTN\n', 'CLKB OUTP OUTN\n+ unused_formal\n', 'unused_formal_ownership_unresolved'),
        'model_parameter': ('.model nch nmos', '.model nch nmos level=1', 'unsupported_model_definition'),
    }
    RUN.mkdir(parents=True, exist_ok=True)
    records = []
    for name, (before, after, reason) in edits.items():
        assert source.count(before) == 1
        text = source.replace(before, after)
        deck = HERE / ('tenth-acceptance-' + name + '.cir')
        prefix = RUN / name
        command = [str(BINARY), '--svg', str(prefix.with_suffix('.svg')), '--report',
                   str(prefix.with_suffix('.report.json')), str(deck), str(prefix.with_suffix('.json'))]
        if args.execute:
            deck.write_text(text)
            done = subprocess.run(command, capture_output=True)
            prefix.with_suffix('.stdout').write_bytes(done.stdout)
            prefix.with_suffix('.stderr').write_bytes(done.stderr)
            assert done.returncode == 0, (name, done.returncode, done.stderr)
        assert deck.read_text() == text
        raw = oracle.decompose(*oracle.facts(deck.read_text()))
        assert raw['disposition'] == 'decline_input_boundary' and reason in raw['reasons']
        assert raw['ordered_cards'] == base['ordered_cards']
        actual = json.loads(prefix.with_suffix('.json').read_text())
        # Compare the actual complete JSON value, not cached positions or reports.
        assert actual == reference, (name, 'native drawing differs')
        cards = {row[0]: row for row in raw['ordered_cards']}
        devices = {d['name']: d for d in actual['devices'] if d['name'] in cards}
        assert set(devices) == set(cards) and len(cards) == 32
        bindings = []
        for n, row in sorted(cards.items()):
            dev = devices[n]
            assert [p['term'] for p in dev['pins']] == ['d', 'g', 's']
            nodes = [p['net'] for p in dev['pins']] + [dev['bulk']]
            assert nodes == row[1:5]
            assert dev['value'].split() == row[5:]
            bindings.append(dict(device=n, ordered_nodes=nodes, model_parameters=row[5:]))
        report = json.loads(prefix.with_suffix('.report.json').read_text())
        records.append(dict(name=name, deck=rel(deck), deck_sha256=sha(deck), command=command,
                            exit_code=0, raw_formals=raw['formals'], raw_disposition=raw['disposition'],
                            raw_reasons=raw['reasons'], complete_bindings=bindings,
                            normalized_native_json_equal=True,
                            svg_byte_equal=prefix.with_suffix('.svg').read_bytes() == REFERENCE.with_suffix('.svg').read_bytes(),
                            report_is_separate=bool(report),
                            outputs={rel(p): sha(p) for p in sorted(RUN.glob(name + '.*'))}))
    result = dict(scope='Executed three frozen CLI literals; no new-engine, current-worktree or target execution. No images viewed in this microstudy; JSON/ink bytes compared.',
                  script_sha256=sha(Path(__file__)), binary_sha256=BINARY_SHA,
                  dependencies={rel(p): sha(p) for p in [SOURCE, REFERENCE, REFERENCE.with_suffix('.svg'),
                                HERE / 'ninth-local-groups-census.py', HERE / 'groups_candidates.py',
                                HERE.parent.parent / 'figures/channel_bridges.py']},
                  reference_disposition=base['disposition'], exact_names=sorted(edits),
                  ordered_terminal_occurrences=384, records=records)
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(names=result['exact_names'], equal_native_records=len(records),
                          complete_ordered_terminal_occurrences=384)))


if __name__ == '__main__':
    main()
