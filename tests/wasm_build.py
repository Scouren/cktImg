#!/usr/bin/env python3
"""Exercise the production plugin build edge in a fresh miniature project.

The oracle is literal output bytes plus a test-only optimizer invocation log.
Only the raw-module producer is replaced; executable, flags, declared inputs,
output and install edges are copied from build.zig. Run inside nix develop.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


NAMES = ['initial', 'unchanged-cache-hit', 'raw-content',
         'same-path-executable-content', 'command-flag', 'flake-content',
         'lock-content', 'final-unchanged-cache-hit', 'optimizer-failure', 'missing-optimizer']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def production_edge(text):
    start = text.index('    const optimizer = ')
    end = text.index('\n}', start)
    edge = text[start:end] + '\n'
    flags = re.findall(r'"(--[^"\n]+|-O[^"\n]+)"', edge)
    assert flags == ['--enable-bulk-memory-opt', '--enable-nontrapping-float-to-int', '-Oz']
    for statement in [
        'b.addRunFile(b.findProgramLazy(.{ .names = &.{"wasm-opt"} }))',
        'optimizer.addFileArg(exe.getEmittedBin());',
        'optimizer.addFileInput(b.path("flake.nix"));',
        'optimizer.addFileInput(b.path("flake.lock"));',
        'optimizer.expectExitCode(0);',
        'optimizer.addOutputFileArg2("netlist-import.wasm", .{})',
        'b.addInstallFileWithDir(optimized, .prefix, "../netlist-import.wasm")',
    ]:
        assert edge.count(statement) == 1, statement
    return edge


def mock_tool(work, tag, fail=False):
    # This invocation log exists only in the fixture, not the production edge.
    return (f'#!{sys.executable}\nimport json, pathlib, sys\n'
            f'log = pathlib.Path({str(work / "invocations.jsonl")!r})\n'
            f'with log.open("a") as out: out.write(json.dumps({{"tag": {tag!r}, "args": sys.argv[1:]}})+"\\n")\n'
            + ('sys.exit(17)\n' if fail else
               'args = sys.argv[1:]\nidx = args.index("-o")\n'
               f'pathlib.Path(args[idx+1]).write_bytes(pathlib.Path(args[idx-1]).read_bytes()+{tag.encode()!r}+b"\\n"+" ".join(args[:idx-1]).encode())\n'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    work, evidence = args.work.resolve(), args.evidence.resolve()
    if work.exists() or evidence.exists() or work in evidence.parents or evidence in work.parents:
        raise ValueError('work and evidence must be fresh, disjoint directories')
    available = next(int(line.split()[1]) * 1024 for line in Path('/proc/meminfo').read_text().splitlines()
                     if line.startswith('MemAvailable:'))
    if available < 6 * 1024**3:
        raise ValueError('at least 6 GiB available memory required')
    zig = shutil.which('zig')
    if zig is None:
        raise ValueError('run inside nix develop: Zig not found')
    zig = str(Path(zig).resolve())
    inputs = {str(path): sha(path) for path in [root / 'build.zig', root / 'flake.nix',
              root / 'flake.lock', Path(__file__).resolve(), Path(zig)]}
    edge = production_edge((root / 'build.zig').read_text())
    mini = edge.replace('exe.getEmittedBin()', 'b.path("raw.wasm")')
    assert mini.replace('b.path("raw.wasm")', 'exe.getEmittedBin()') == edge
    work.mkdir(parents=True)
    evidence.mkdir(parents=True)
    (work / 'bin').mkdir()
    (work / 'build.zig').write_text('const std = @import("std");\n\n'
        'pub fn build(b: *std.Build) void {\n' + mini + '}\n')
    (work / 'raw.wasm').write_bytes(b'literal raw bytes v1\n')
    for name in ('flake.nix', 'flake.lock'):
        (work / name).write_text('literal ' + name + ' input v1\n')
    tool = work / 'bin/wasm-opt'
    tool.write_text(mock_tool(work, 'tool-one'))
    tool.chmod(0o755)
    env = dict(os.environ, PATH=str(work / 'bin'))
    output, log = work / 'netlist-import.wasm', work / 'invocations.jsonl'
    rows = []
    command = [zig, 'build', '--build-file', str(work / 'build.zig'),
               '--cache-dir', str(root / '.zig-cache'), '--prefix', str(work / 'zig-out'),
               '-j2', '--summary', 'all', '--verbose']

    def stage(name, calls, success=True, tag=None):
        folder = evidence / (name + '-inputs')
        folder.mkdir()
        files = ['build.zig', 'raw.wasm', 'flake.nix', 'flake.lock']
        if tool.exists():
            files.append('bin/wasm-opt')
        for file in files:
            (folder / file).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(work / file, folder / file)
        before = log.read_text().splitlines() if log.exists() else []
        if not success and output.exists():
            shutil.copyfile(output, folder / 'previous-installed.wasm')
            output.unlink()
        write(evidence / (name + '-command.json'), {'command': command, 'cwd': str(work),
              'PATH': env['PATH'], 'input_sha256': inputs, 'available_memory_bytes': available})
        start = time.monotonic()
        logfile = evidence / (name + '.log')
        with logfile.open('wb') as stream:
            result = subprocess.run(command, cwd=work, env=env, stdout=stream, stderr=subprocess.STDOUT)
        row = {'name': name, 'exit_code': result.returncode, 'seconds': time.monotonic() - start,
               'log_sha256': sha(logfile), 'inputs': {n: sha(folder / n) for n in files}}
        write(evidence / (name + '-result.json'), row)
        after = log.read_text().splitlines() if log.exists() else []
        assert (result.returncode == 0) == success, name
        assert len(after) - len(before) == calls, name
        if success:
            event = json.loads(after[-1])
            assert event['tag'] == tag, name
            expected = (work / 'raw.wasm').read_bytes() + tag.encode() + b'\n' + ' '.join(event['args'][:-3]).encode()
            assert output.read_bytes() == expected, name
        else:
            assert not output.exists(), name
        row.update(invocations=calls, success=success, installed_sha256=sha(output) if output.exists() else None)
        rows.append(row)
        write(evidence / 'progress.json', rows)

    stage('initial', 1, tag='tool-one')
    stage('unchanged-cache-hit', 0, tag='tool-one')
    (work / 'raw.wasm').write_bytes(b'literal raw bytes v2\n')
    stage('raw-content', 1, tag='tool-one')
    tool.write_text(mock_tool(work, 'tool-two'))
    stage('same-path-executable-content', 1, tag='tool-two')
    path = work / 'build.zig'
    path.write_text(path.read_text().replace('"-Oz"', '"-O2"'))
    stage('command-flag', 1, tag='tool-two')
    (work / 'flake.nix').write_text('literal flake input v2\n')
    stage('flake-content', 1, tag='tool-two')
    (work / 'flake.lock').write_text('literal lock input v2\n')
    stage('lock-content', 1, tag='tool-two')
    stage('final-unchanged-cache-hit', 0, tag='tool-two')
    tool.write_text(mock_tool(work, 'tool-failure', fail=True))
    stage('optimizer-failure', 1, success=False)
    tool.unlink()
    stage('missing-optimizer', 0, success=False)
    assert [row['name'] for row in rows] == NAMES
    for path, expected in inputs.items():
        assert sha(Path(path)) == expected, path
    write(evidence / 'result.json', {'status': 'pass', 'checks': rows, 'input_sha256': inputs})
    print(json.dumps({'status': 'pass', 'names': NAMES}))


if __name__ == '__main__':
    main()
