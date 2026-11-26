#!/usr/bin/env python3
"""Audit every frozen source cell through the actual optimized Schemify plugin.

The caller supplies a frozen plan and fresh evidence paths. Successful projects, raw/final netlists, expected
probes, complete stdout/stderr and named capacity failures are all retained.
No Zig build or mutation of a shipping file occurs.
"""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import shutil
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def equal(a, b, name):
    if a != b:
        raise ValueError(name)


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def refusal(rule, code, stdout, stderr, files):
    equal(code, 1, 'capacity refusal exit code')
    equal(stdout, rule['stdout'], 'capacity refusal exact diagnostic')
    equal(stderr, '', 'capacity refusal unexpected stderr')
    equal(sorted(files), [], 'capacity refusal wrote partial output')


def self_checks():
    line = ('netlist-import: netlist-import: n2s/rstring_ladder.spice: 279 element cards; '
            'the plugin converts at most 200 (split the netlist)\n')
    rule = {'stdout': line}
    refusal(rule, 1, line, '', [])
    checks = ['literal_capacity_refusal_accepted']
    mutations = {
        'unexpected_import_success_rejected': (0, line, '', []),
        'usage_io_failure_rejected': (2, line, '', []),
        'fuel_failure_rejected': (1, 'netlist-import: E_FUEL\n', '', []),
        'trap_rejected': (1, 'netlist-import: wasm trap\n', '', []),
        'wrong_deck_rejected': (1, line.replace('rstring_ladder', 'write_dac'), '', []),
        'wrong_card_count_rejected': (1, line.replace('279', '280'), '', []),
        'wrong_limit_rejected': (1, line.replace('200', '199'), '', []),
        'missing_diagnostic_rejected': (1, '', '', []),
        'additional_stdout_error_rejected': (1, line + 'netlist-import: E_FUEL\n', '', []),
        'additional_stderr_rejected': (1, line, 'I/O failure\n', []),
        'partial_record_rejected': (1, line, '', ['n2s/partial.shcomp']),
    }
    for name, values in mutations.items():
        try:
            refusal(rule, *values)
        except ValueError:
            checks.append(name)
        else:
            raise AssertionError(name)
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=pathlib.Path)
    parser.add_argument('--work', type=pathlib.Path)
    parser.add_argument('--output', type=pathlib.Path)
    parser.add_argument('--self-check', action='store_true')
    args = parser.parse_args()
    checks = self_checks()
    if args.self_check:
        print(json.dumps(checks, indent=2))
        return
    if None in (args.plan, args.work, args.output):
        parser.error('--plan, --work and --output required')
    plan = json.loads(args.plan.read_text())
    work, output = args.work.resolve(), args.output.resolve()
    if work.exists() or output.exists() or work in output.parents:
        raise ValueError('choose new work/output paths; output must be outside work')
    for name, value in plan['input_sha256'].items():
        equal(sha(pathlib.Path(name)), value, 'input changed: ' + name)
    rt = load(pathlib.Path(plan['roundtrip_helper']), 'full_host_roundtrip')
    records_helper = load(pathlib.Path(plan['record_helper']), 'full_host_records')
    checks += records_helper.self_checks()
    work.mkdir(parents=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {'status': 'running', 'plan_sha256': sha(args.plan), 'script_sha256': sha(pathlib.Path(__file__)),
              'input_sha256': plan['input_sha256'], 'methods': checks, 'fuel_limit': plan['fuel_limit'],
              'scope': 'Exact frozen named-deck actual-host audit; no universal optimizer-equivalence claim.',
              'commands': [], 'cases': [], 'failures': []}

    def save():
        output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')

    def call(command, cwd, label):
        index = len(report['commands'])
        stdout_file, stderr_file = [work / ('command-%03d.%s' % (index, channel))
                                    for channel in ('stdout', 'stderr')]
        row = {'name': label, 'command': command, 'cwd': str(cwd),
               'stdout': str(stdout_file), 'stderr': str(stderr_file)}
        report['commands'].append(row)
        save()
        start = time.monotonic()
        try:
            result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=1800)
            code, stdout, stderr = result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired as error:
            code, stdout, stderr = None, error.stdout or b'', error.stderr or b''
            row['timed_out'] = True
        stdout_file.write_bytes(stdout)
        stderr_file.write_bytes(stderr)
        row.update(exit_code=code, seconds=time.monotonic() - start,
                   stdout_sha256=sha(stdout_file), stderr_sha256=sha(stderr_file))
        save()
        return index, code, stdout.decode('utf8'), stderr.decode('utf8')

    def required(command, cwd, label):
        index, code, _, _ = call(command, cwd, label)
        equal(code, 0, 'host command failed: ' + label)
        return index

    def inventory(directory):
        return {p.relative_to(directory).as_posix(): {'sha256': sha(p), 'bytes': p.stat().st_size}
                for p in sorted(directory.rglob('*')) if p.is_file()}

    try:
        plugin = work / 'plugin'
        plugin.mkdir()
        shutil.copyfile(plan['artifact'], plugin / 'netlist-import.wasm')
        shutil.copyfile(plan['plugin_manifest'], plugin / 'schemify.project')
        equal(sha(plugin / 'netlist-import.wasm'), plan['artifact_sha256'], 'copied artifact differs')
        init = work / 'init.lua'
        init.write_text('schemify.pack.add({ { path = %s, name = "netlist-import", '
                        'grant = { "read_project", "write_project" }, fuel = %d } })\n' %
                        (json.dumps(str(plugin)), plan['fuel_limit']))
        report['plugin'] = inventory(plugin)
        report['init_sha256'] = sha(init)
        host = pathlib.Path(plan['host_directory'])
        cli = [str(host / 'schemify'), '-u', str(init)]
        required(cli + ['pack', 'sync'], work, 'pack-sync')
        for index, entry in enumerate(plan['decks']):
            case = {'name': entry['name'], 'status': 'running', 'netlists': []}
            report['cases'].append(case)
            project = work / ('p%03d' % index)
            (project / 'n2s').mkdir(parents=True)
            (project / 'schemify.project').write_text('schemify 1 project\n')
            source = pathlib.Path(entry['path'])
            original = project / 'n2s' / source.name
            shutil.copyfile(source, original)
            case['project'] = str(project)
            try:
                text = source.read_text()
                top, subs = rt.split(text)
                equal(list(subs), entry['ordered_subcircuits'], 'source cell order differs')
                equal(rt.has_devices(top), entry['top_devices'], 'top device classification differs')
                cmd, code, stdout, stderr = call(cli + ['cmd', str(project), 'netlist.import', 'n2s/' + source.name],
                                                 project, entry['name'] + ':import')
                case['import_command'] = cmd
                equal(original.read_bytes(), source.read_bytes(), 'source changed during import')
                if entry['refusal'] is not None:
                    generated = [p.relative_to(project).as_posix() for p in (project / 'n2s').rglob('*')
                                 if p.is_file() and p != original]
                    refusal(entry['refusal'], code, stdout, stderr, generated)
                    case.update(status='expected_capacity_refusal', refusal=entry['refusal'], records={})
                else:
                    equal(code, 0, 'unexpected import failure')
                    records = records_helper.record_bytes(project, original)
                    comps, benches = records_helper.coverage(records, list(subs), entry['top_devices'])
                    case['records'] = {name: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                                       for name, data in records.items()}
                    context = ''
                    if benches:
                        nc = required(cli + ['netlist', benches[0], '--dialect', 'ngspice', '-o', 'bench.back.sp'],
                                      project, entry['name'] + ':$bench:netlist')
                        exported = (project / 'bench.back.sp').read_text()
                        if entry['top_devices'] or not subs:
                            cc = required([str(host / 'spicecmp'), 'n2s/' + source.name, 'bench.back.sp'],
                                          project, entry['name'] + ':$top:spicecmp')
                            case['netlists'].append({'name': '$top', 'netlist_command': nc, 'spicecmp_command': cc,
                                                    'expected_sha256': sha(original), 'back_sha256': sha(project / 'bench.back.sp')})
                            context = '\n'.join(line for line in rt.split(exported)[0]
                                if line.strip().lower().startswith(('.model', '.param', '.global', '.include', '.lib', '.option'))) + '\n'
                        else:
                            equal(rt.has_devices(rt.split(exported)[0]), False, 'declaration bench exported devices')
                            context = '\n'.join(line for line in exported.splitlines() if line.strip().lower() != '.end') + '\n'
                    (project / 'exported-context.sp').write_text(context)
                    for j, name in enumerate(subs):
                        back, probe, raw = ['sub%03d.%s.sp' % (j, ending) for ending in ('back', 'expected', 'raw')]
                        nc = required(cli + ['netlist', comps[name], '--dialect', 'ngspice', '-o', raw],
                                      project, entry['name'] + ':' + name + ':netlist')
                        (project / probe).write_text(rt.probe(text, name))
                        (project / back).write_text(context + (project / raw).read_text())
                        cc = required([str(host / 'spicecmp'), probe, back], project, entry['name'] + ':' + name + ':spicecmp')
                        case['netlists'].append({'name': name, 'netlist_command': nc, 'spicecmp_command': cc,
                            'expected_sha256': sha(project / probe), 'raw_sha256': sha(project / raw),
                            'back_sha256': sha(project / back)})
                    equal([row['name'] for row in case['netlists']], entry['expected_comparisons'], 'exact source comparison names differ')
                    equal(records_helper.record_bytes(project, original), records, 'netlisting changed generated records')
                    case['status'] = 'same'
            except Exception as error:
                case.update(status='fail', error=str(error))
                report['failures'].append({'name': entry['name'], 'error': str(error)})
            case['retained_files'] = inventory(project)
            save()
            print(case['status'], entry['name'], flush=True)
        equal([row['name'] for row in report['cases']], [row['name'] for row in plan['decks']], 'exact audited deck set differs')
        actual_same = [row['name'] for row in report['cases'] if row['status'] == 'same']
        actual_refused = [row['name'] for row in report['cases'] if row['status'] == 'expected_capacity_refusal']
        report['same_names'], report['refused_names'] = actual_same, actual_refused
        report['comparison_names'] = [row['name'] + ':' + cell['name'] for row in report['cases'] for cell in row['netlists']]
        equal(actual_same, plan['expected_same_names'], 'exact success names differ')
        equal(actual_refused, plan['expected_refused_names'], 'exact refusal names differ')
        equal(report['comparison_names'], plan['expected_comparison_names'], 'exact full cell inventory differs')
        for name, value in plan['input_sha256'].items():
            equal(sha(pathlib.Path(name)), value, 'input changed during audit: ' + name)
        report['status'] = 'pass'
        save()
    except BaseException as error:
        report.update(status='fail', error=str(error))
        save()
        raise


if __name__ == '__main__':
    main()
