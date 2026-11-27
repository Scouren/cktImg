#!/usr/bin/env python3
"""Freeze exact source names, cell bindings and tools for host_audit.py."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', type=Path, required=True)
    parser.add_argument('--host-directory', type=Path, required=True)
    parser.add_argument('--examples', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--focused', action='store_true', help='the exact nine named release controls')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    inventory = root / 'tests/host_audit_cases.json'
    cases = json.loads(inventory.read_text())
    helper = root / 'tests/roundtrip.py'
    records = root / 'tests/host_records.py'
    runner = root / 'tests/host_audit.py'
    manifest = root / 'schemify.project'
    contract = root / 'tools/schemify/plugin.zig'
    rt = load(helper, 'host_plan_roundtrip')
    methods = load(runner, 'host_plan_runner').self_checks()
    methods += load(records, 'host_plan_records').self_checks()
    assert 'plugin netlist-import path netlist-import.wasm' in manifest.read_text()
    assert 'const cards_max = 200;' in contract.read_text()
    assert '"netlist-import: " ++ fmt' in contract.read_text()
    assert '"{s}: {d} element cards; the plugin converts at most {d} (split the netlist)"' in contract.read_text()
    artifact, host = args.artifact.resolve(), args.host_directory.resolve()
    files = [inventory, helper, records, runner, manifest, contract, Path(__file__).resolve(), artifact]
    files += [host / name for name in ('schemify', 'spicecmp', 'gui')]
    selected = cases['focused_names'] if args.focused else [row['name'] for row in cases['decks']]
    by_name = {row['name']: row for row in cases['decks']}
    assert len(by_name) == len(cases['decks']) and len(set(selected)) == len(selected)
    decks = []
    for name in selected:
        row = dict(by_name[name])
        source = (args.examples / name.removeprefix('external/examples/')
                  if name.startswith('external/examples/') else root / name).resolve()
        if sha(source) != row['sha256']:
            raise ValueError('source content changed: ' + name)
        top, subs = rt.split(source.read_text())
        assert list(subs) == row['ordered_subcircuits'], name
        assert rt.has_devices(top) == row['top_devices'], name
        expected = (['$top'] if row['top_devices'] or not subs else []) + list(subs)
        if row['refusal'] is None:
            assert expected == row['expected_comparisons'], name
        else:
            assert row['expected_comparisons'] == [], name
        row['path'] = str(source)
        decks.append(row)
        files.append(source)
    plan = {
        'schema': 1, 'status': 'prepared_not_executed', 'artifact': str(artifact),
        'artifact_sha256': sha(artifact), 'artifact_bytes': artifact.stat().st_size,
        'host_directory': str(host), 'fuel_limit': 100_000_000_000,
        'plugin_manifest': str(manifest), 'roundtrip_helper': str(helper),
        'record_helper': str(records), 'decks': decks,
        'input_sha256': {str(path): sha(path) for path in files}, 'methods': methods,
        'expected_same_names': [row['name'] for row in decks if row['refusal'] is None],
        'expected_refused_names': [row['name'] for row in decks if row['refusal'] is not None],
        'expected_comparison_names': [row['name'] + ':' + cell for row in decks
                                      for cell in row['expected_comparisons']],
        'scope': 'Exact named source declarations; every cell, top bench and capacity refusal. No universal optimizer equivalence claim.',
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x') as output:
        output.write(json.dumps(plan, indent=2, sort_keys=True) + '\n')
    print(json.dumps({'plan': str(args.output), 'sha256': sha(args.output),
                      'deck_names': selected, 'comparison_names': plan['expected_comparison_names']}))


if __name__ == '__main__':
    main()
