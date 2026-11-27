#!/usr/bin/env python3
"""Exact generated-record names, bytes and declared-cell coverage."""
import pathlib

def equal(a, b, description):
    if a != b:
        raise ValueError(description)

def compare_records(a, b):
    equal(sorted(a), sorted(b), 'generated record filename set differs')
    for name in sorted(a):
        equal(a[name], b[name], 'generated record bytes differ: ' + name)

def record_bytes(project, original):
    made = {}
    for path in sorted((project / 'n2s').rglob('*')):
        if path.is_file() and path != original:
            name = path.relative_to(project).as_posix()
            if path.suffix not in ('.shcomp', '.shprim', '.shbench'):
                raise ValueError('unexpected generated file: ' + name)
            made[name] = path.read_bytes()
    if not made:
        raise ValueError('import wrote no records')
    return made

def coverage(records, expected_subcircuits, top_devices):
    comps = {}
    benches = []
    for name in records:
        p = pathlib.PurePosixPath(name)
        if p.suffix == '.shcomp':
            key = p.stem.lower()
            if key in comps:
                raise ValueError('duplicate generated subcircuit stem: ' + key)
            comps[key] = name
        elif p.suffix == '.shbench':
            benches.append(name)
    equal(sorted(comps), sorted(expected_subcircuits), 'exact declared subcircuit coverage differs')
    if len(benches) > 1 or (top_devices and len(benches) != 1):
        raise ValueError('top-level bench coverage differs')
    return comps, benches

def self_checks():
    names = []
    original = {'n2s/a.shcomp': b'component A', 'n2s/l.shprim': b'leaf L'}
    compare_records(original, dict(reversed(list(original.items()))))
    names.append('record_order_does_not_hide_exact_named_byte_equality')
    mutations = {
        'missing_record_rejected': {'n2s/a.shcomp': b'component A'},
        'renamed_record_rejected': {'n2s/z.shcomp': b'component A', 'n2s/l.shprim': b'leaf L'},
        'changed_record_content_rejected': {'n2s/a.shcomp': b'component B', 'n2s/l.shprim': b'leaf L'},
        'extra_record_rejected': {**original, 'n2s/x.shcomp': b'extra'},
    }
    for name, mutated in mutations.items():
        try:
            compare_records(original, mutated)
        except ValueError:
            names.append(name)
        else:
            raise ValueError('accepted literal mutation: ' + name)
    coverage(original, ['a'], False)
    for name, expected, top in [('missing_source_subcircuit_rejected', ['a', 'b'], False),
                                ('undeclared_component_rejected', [], False),
                                ('missing_top_bench_rejected', ['a'], True)]:
        try:
            coverage(original, expected, top)
        except ValueError:
            names.append(name)
        else:
            raise ValueError('accepted coverage mutation: ' + name)
    return names
