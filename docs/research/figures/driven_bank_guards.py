#!/usr/bin/env python3
"""Reproduce the private placement-mate observation without editing the engine.

Usage: driven_bank_guards.py EXAMPLES ENGINE_SRC OUTPUT [--prepare DIRECTORY]
       [--log PRIVATE_PROBE_LOG]

The inventory contains all 21 complete normalized decks, the standalone
public-table Zig probe, one logging-only insertion, original engine hashes,
and the measured private trace. --prepare writes a separate source copy;
it never compiles or edits shipping files. The caller runs Zig with that
copy as NetlistParser, then --log verifies every measured observation.
ENGINE_SRC must be the recorded iteration-19 source checkout or archive.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def observations(text):
    """Ignore build diagnostics; retain all bank calls and named public rows."""
    rows, pending, current = [], [], None
    for line in text.splitlines():
        match = re.search(r'(PLACEMENT_BANK |BANK |MEMBER |GROUP )', line)
        if not match:
            continue
        line = line[match.start():]
        kind = line.split()[0]
        if kind == 'PLACEMENT_BANK':
            pending.append(line)
        elif kind == 'BANK':
            current = dict(id=line.split()[1], placement=pending, public=[line])
            rows.append(current)
            pending = []
        else:
            if current is None or line.split()[1] != current['id']:
                raise ValueError('unbound public observation')
            current['public'].append(line)
    if pending or len({r['id'] for r in rows}) != len(rows):
        raise ValueError('unbound/repeated placement observation')
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('examples', 'engine_src', 'output'):
        parser.add_argument(name, type=Path)
    parser.add_argument('--prepare', type=Path)
    parser.add_argument('--log', type=Path)
    args = parser.parse_args()
    frozen = json.loads((HERE / 'driven_bank_guards_cases.json').read_text())
    if digest(Path(__file__)) != frozen['reader_sha256']:
        raise ValueError('guard reader changed')
    if hashlib.sha256(frozen['private_probe_log'].encode()).hexdigest() != frozen['recorded_log_sha256']:
        raise ValueError('recorded actual trace hash differs')
    if digest(HERE / 'driven_banks_cases.json') != frozen['source_inventory_sha256']:
        raise ValueError('source census changed')
    actual = {p.name: digest(p) for p in args.engine_src.glob('*.zig')}
    if actual != frozen['engine_source_sha256']:
        raise ValueError('use the recorded iteration-19 engine source, not a later revision')
    for row in frozen['decks']:
        for suffix, expected in row['source_sha256'].items():
            if digest(args.examples / 'analoggenie' / (row['id'] + suffix)) != expected:
                raise ValueError('source input changed: ' + row['id'] + suffix)
        if hashlib.sha256(row['text'].encode()).hexdigest() != row['normalized_sha256']:
            raise ValueError('frozen normalized deck hash differs')
    patch = frozen['logging_insertion']
    original = (args.engine_src / 'skeleton.zig').read_text()
    if original.count(patch['before']) != 1:
        raise ValueError('logging seam is not unique')
    changed = original.replace(patch['before'], patch['insert'] + patch['before'])
    if hashlib.sha256(changed.encode()).hexdigest() != frozen['instrumented_skeleton_sha256']:
        raise ValueError('logging-only copied source differs')
    if args.prepare:
        args.prepare.mkdir(parents=True, exist_ok=True)
        shutil.copytree(args.engine_src, args.prepare / 'src', dirs_exist_ok=True)
        (args.prepare / 'src/skeleton.zig').write_text(changed)
        (args.prepare / 'probe.zig').write_text(frozen['probe_zig'])
        for row in frozen['decks']:
            (args.prepare / (row['id'] + '.cir')).write_text(row['text'])
        (args.prepare / 'build_options.zig').write_text('pub const c_abi = false;\npub const zon_config = false;\npub const latex_renderer = false;\n')
    trace = frozen['private_probe_log'] if args.log is None else args.log.read_text()
    measured = observations(trace)
    if measured != frozen['observations']:
        raise ValueError('exact private/public guard observations changed')
    if [r['id'] for r in measured] != [r['id'] for r in frozen['decks']]:
        raise ValueError('exact 21-deck coverage changed')
    result = dict(source_inventory_sha256=frozen['source_inventory_sha256'],
                  engine_source_sha256=actual, instrumented_skeleton_sha256=frozen['instrumented_skeleton_sha256'],
                  probe_sha256=hashlib.sha256(frozen['probe_zig'].encode()).hexdigest(),
                  measured_log_sha256=hashlib.sha256(trace.encode()).hexdigest(),
                  recorded_log_sha256=frozen['recorded_log_sha256'], observations=measured,
                  guarded_cases=frozen['guarded_cases'],
                  replay='fresh supplied log' if args.log else 'recorded actual trace with verified inputs',
                  limits='Diagnostic observation only; inferred placement mates differ from exact structural symmetry. This creates no new routing or mate-priority rule.')
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(observed_decks=len(measured), guarded_cases=frozen['guarded_cases']), sort_keys=True))


if __name__ == '__main__':
    main()
