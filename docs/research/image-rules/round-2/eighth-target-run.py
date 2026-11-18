#!/usr/bin/env python3
"""Existing hash-bound host/plugin only; fresh isolated project, no build."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
HOST = BASE / 'host-target/debug'
PLUGIN = BASE / 'feedback-native'
ARCHIVE = BASE / 'image-rule-round-2/groups/eighth-target'
EXPECTED = {
    HOST / 'schemify': '9e400edd678b5423f779e4a5a9c33fe443a0c23882f24798f3e55739ede05bc9',
    HOST / 'spicecmp': '5d97d5d6318667061fe0eecb853bc624baa29d01aa2bf2f13346f19f74e32018',
    PLUGIN / 'cktimg.wasm': '843fa0c9c916d6357bff40b9b3e3e2714134274465568c790345a63415863c4d',
    PLUGIN / 'schemify.project': '133e2e663e4e4d3d49b9cbaba22e024c6e7c66083971e4b070fa8b9e32576e73',
}
CASES = {
    **{name: BASE / 'image-rule-round-2/bodies/sixth-bodies' / (name + '.cir')
       for name in ('one_body_peer', 'two_body_peers', 'two_bodies_and_resistor')},
    **{name: HERE / ('sixth-symbols-' + name + '.cir') for name in ('pfd-base', 'pfd-pininfo')},
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def bind(path):
    return dict(path=rel(path), sha256=sha(path), bytes=path.stat().st_size)


def helper():
    path = PLUGIN / 'tests/roundtrip.py'
    spec = importlib.util.spec_from_file_location('frozen_host_roundtrip', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def source_rows(text):
    """Complete supported ordered raw rows, including behavioral expressions."""
    h = helper()
    top, subs = h.split(text)
    return dict(models=[line.lower().split() for line in top if line.lower().startswith('.model')],
                subcircuits={name: dict(header=header.lower().split(),
                                       body=[line.lower().split() for line in body
                                             if line.strip() and not line.lstrip().startswith('*')])
                             for name, (header, body) in subs.items()})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--output', type=Path, default=HERE / 'eighth-target-run.json')
    args = ap.parse_args()
    for path, expected in EXPECTED.items():
        assert sha(path) == expected, path
    if not args.execute:
        data = json.loads(args.output.read_text())
        assert data['script_sha256'] == sha(Path(__file__))
        assert [r['name'] for r in data['cases']] == list(CASES)
        for row in data['inputs'] + data['artifacts']:
            assert sha(ROOT / row['path']) == row['sha256'], row['path']
        for case in data['cases']:
            assert case['source'] == source_rows(CASES[case['name']].read_text())
        print(json.dumps(dict(status=data['status'], cases=len(data['cases']), commands=len(data['commands']))))
        return
    assert not ARCHIVE.exists(), 'never overwrite earlier host evidence'
    ARCHIVE.mkdir(parents=True)
    work = Path(tempfile.mkdtemp(prefix='cktimg-eighth-target-'))
    env = os.environ.copy()
    isolated = {key: str(work / key.lower()) for key in
                ('XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR')}
    isolated['SCHEMIFY_APPNAME'] = 'cktimg-eighth-target'
    for value in list(isolated.values())[:-1]:
        Path(value).mkdir(mode=0o700)
    env.update(isolated)
    inputs = list(EXPECTED) + list(CASES.values()) + [
        PLUGIN / 'tests/roundtrip.py',
        BASE / 'optimized-full-host-inputs/provenance/feedback-host-all-command.json',
        BASE / 'optimized-full-host-inputs/provenance/dev-host-build-command.json',
        BASE / 'optimized-full-host-inputs/provenance/dev-host-source-manifest.json',
    ]
    for source in ('tools/schemify/layout.zig', 'tools/schemify/recognize.zig', 'src/sketch.zig'):
        inputs.extend([PLUGIN / source, BASE / 'resistor-output-integrated-common' / source])
    result = dict(status='running', script_sha256=sha(Path(__file__)), inputs=[bind(p) for p in inputs],
                  archive=rel(ARCHIVE), isolated_work=str(work), isolated_environment=isolated,
                  scope='Recorded older feedback-native plugin, not the bf7b native binary or a build from its snapshot.',
                  commands=[], cases=[], artifacts=[])

    def save():
        args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')

    def run(command, cwd, label):
        number = len(result['commands'])
        process = subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=180)
        stem = ARCHIVE / ('command-%03d' % number)
        stem.with_suffix('.stdout').write_bytes(process.stdout)
        stem.with_suffix('.stderr').write_bytes(process.stderr)
        result['commands'].append(dict(label=label, argv=command, cwd=str(cwd), exit_code=process.returncode,
                                       stdout=bind(stem.with_suffix('.stdout')), stderr=bind(stem.with_suffix('.stderr'))))
        save()
        return process

    plugin = work / 'plugin'
    plugin.mkdir()
    for name in ('cktimg.wasm', 'schemify.project'):
        shutil.copy2(PLUGIN / name, plugin / name)
    init = work / 'init.lua'
    init.write_text('schemify.pack.add({ { path = ' + json.dumps(str(plugin)) +
                    ', name = "cktimg", grant = { "read_project", "write_project" }, fuel = 100000000000 } })\n')
    cli = [str(HOST / 'schemify'), '-u', str(init)]
    try:
        assert run(cli + ['pack', 'sync'], work, 'pack-sync').returncode == 0
        h = helper()
        for name, source in CASES.items():
            project = work / name
            (project / 'n2s').mkdir(parents=True)
            (project / 'schemify.project').write_text('schemify 1 project\n')
            copied = project / 'n2s/input.cir'
            shutil.copy2(source, copied)
            case = dict(name=name, source=source_rows(source.read_text()), comparisons=[])
            result['cases'].append(case)
            assert run(cli + ['cmd', str(project), 'cktimg.import', 'n2s/input.cir'], project, name + ':import').returncode == 0
            assert copied.read_bytes() == source.read_bytes()
            records = sorted((project / 'n2s').glob('*.sh*'))
            case['records'] = [str(p.relative_to(project)) for p in records]
            top, subs = h.split(source.read_text())
            components = {p.stem.lower(): p for p in records if p.suffix == '.shcomp'}
            assert set(components) == set(subs), (name, list(components), list(subs))
            benches = [p for p in records if p.suffix == '.shbench']
            assert len(benches) == 1
            assert run(cli + ['netlist', str(benches[0].relative_to(project)), '--dialect', 'ngspice', '-o', 'bench.back.sp'],
                       project, name + ':bench-netlist').returncode == 0
            bench = (project / 'bench.back.sp').read_text()
            # These five inputs have subcircuit bodies and model declarations only.
            # The host preserves the plain-text source title in its model bench;
            # the old helper's any-alphabetic-line test calls that title a device.
            # Keep the complete bench as evidence, but carry only its declarations
            # into the independent component comparison, as roundtrip.py does for
            # a bench with top-level content. Never copy source declarations here.
            declarations = ('.model', '.param', '.global', '.include', '.lib', '.option')
            context = '\n'.join(line for line in bench.splitlines()
                                if line.strip().lower().startswith(declarations)) + '\n'
            case['exported_declaration_context'] = context
            for sub, component in components.items():
                back = sub + '.back.sp'
                expected = sub + '.expected.sp'
                assert run(cli + ['netlist', str(component.relative_to(project)), '--dialect', 'ngspice', '-o', back],
                           project, name + ':' + sub + ':netlist').returncode == 0
                (project / expected).write_text(h.probe(source.read_text(), sub))
                raw = project / (sub + '.raw-back.sp')
                shutil.copy2(project / back, raw)
                (project / back).write_text(context + raw.read_text())
                compared = run([str(HOST / 'spicecmp'), expected, back], project, name + ':' + sub + ':spicecmp')
                case['comparisons'].append(dict(subcircuit=sub, exit_code=compared.returncode,
                                                expected=expected, back=back, raw_back=raw.name))
            shutil.copytree(project, ARCHIVE / name)
            print(name, [(c['subcircuit'], c['exit_code']) for c in case['comparisons']], flush=True)
        result['status'] = 'pass' if all(c['exit_code'] == 0 for case in result['cases'] for c in case['comparisons']) else 'roundtrip-mismatch'
    except BaseException as error:
        result['status'] = 'failed'
        result['error'] = repr(error)
        raise
    finally:
        shutil.copy2(init, ARCHIVE / 'init.lua')
        result['artifacts'] = [bind(p) for p in sorted(ARCHIVE.rglob('*')) if p.is_file()]
        for row in result['inputs']:
            assert sha(ROOT / row['path']) == row['sha256']
        save()
    print(json.dumps(dict(status=result['status'], cases=len(result['cases']), commands=len(result['commands']))))


if __name__ == '__main__':
    main()
