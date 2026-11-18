#!/usr/bin/env python3
"""Independent raw bindings, generated pin/label records and comparator mutations."""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
RUN = BASE / 'image-rule-round-2/groups/eighth-target'
CONTROLS = BASE / 'image-rule-round-2/groups/eighth-target-controls'
NAMES = ['one_body_peer', 'two_body_peers', 'two_bodies_and_resistor', 'pfd-base', 'pfd-pininfo']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return str(path.relative_to(ROOT))


def rows(text):
    return [line.lower().split() for line in text.splitlines() if line.strip() and not line.lstrip().startswith('*')]


def top_cards(text):
    result = {}
    in_sub = False
    for row in rows(text):
        if row[0] == '.subckt':
            assert not in_sub
            in_sub = True
        elif row[0] == '.ends':
            in_sub = False
        elif not in_sub and row[0][0].isalpha():
            assert row[0] not in result
            result[row[0]] = row
    return result


def pins(text):
    return [row[1:] for row in rows(text) if row[0] == 'pin']


def b_labels(text):
    return [row for row in rows(text) if row[0] == 'label' and row[-1] == 'b']


def verify_actual(run=RUN):
    expected = {
        'one_body_peer': {'m1': ['d', 'g', 's', 'b'], 'r1': ['b', '0']},
        'two_body_peers': {'m1': ['d1', 'g1', 's1', 'b'], 'm2': ['d2', 'g2', 's2', 'b']},
        'two_bodies_and_resistor': {'m1': ['d1', 'g1', 's1', 'b'], 'm2': ['d2', 'g2', 's2', 'b'], 'r1': ['b', '0']},
    }
    bodies = []
    for name, wanted in expected.items():
        actual = top_cards((run / name / 'dut.raw-back.sp').read_text())
        assert set(actual) == set(wanted)
        for device, nets in wanted.items():
            assert actual[device][1:len(nets) + 1] == nets
            assert actual[device][len(nets) + 1:] == (['nm'] if device[0] == 'm' else ['1k', 'm=1'])
        symbol = (run / name / 'n2s/spice_nmos4.shprim').read_text()
        assert pins(symbol) == [['d', 'inout', '20', '-30'], ['g', 'in', '-20', '0'],
                                ['s', 'inout', '20', '30'], ['b', 'in', '20', '0']]
        component = (run / name / 'n2s/dut.shcomp').read_text()
        labels = b_labels(component)
        assert len(labels) == len(wanted)
        assert not any(row[0] == 'nc' for row in rows(component))
        bodies.append(dict(name=name, full_export_cards=actual, body_labels=labels,
                           primitive_pins=pins(symbol), no_serialized_nc=True))
    pfd = []
    complete_pfd = {
        'c': ['c', 'vcont', 'vss', '1p', 'm=1'],
        'm1': ['m1', 'net0', 'vb1', 'vss', 'vss', 'nch', 'w=1', 'l=0.15', 'nf=1', 'm=1'],
        'm2': ['m2', 'net1', 'vb2', 'vdd', 'vdd', 'pch', 'w=1', 'l=0.15', 'nf=1', 'm=1'],
        'm3': ['m3', 'vcont', 'qb', 'net0', 'vss', 'nch', 'w=1', 'l=0.15', 'nf=1', 'm=1'],
        'm4': ['m4', 'vcont', 'qa_bar', 'net1', 'vdd', 'pch', 'w=1', 'l=0.15', 'nf=1', 'm=1'],
        'x1': ['x1', 'vdd', 'vss', 'qa', 'qa_bar', 'inverter'],
        'xpfd': ['xpfd', 'a', 'b', 'qa', 'qb', 'pfd'],
    }
    inverter_rows = rows('''.param vt=0.01 td=1e-11
BY Y VSS V={V(ndl,VSS)}
Bf nfn VSS V={V(VDD,VSS)*(1-V(hA))}
BhA hA 0 V={0.5*(1+tanh((V(A,VSS)-0.5*V(VDD,VSS))/vt))}
Cd ndl VSS {td/1000} m=1
Rd nfn ndl 1k m=1
.end''')
    for name in NAMES[3:]:
        text = (run / name / 'dut.raw-back.sp').read_text()
        actual = top_cards(text)
        assert actual == complete_pfd
        assert actual['xpfd'] == ['xpfd', 'a', 'b', 'qa', 'qb', 'pfd']
        assert actual['x1'] == ['x1', 'vdd', 'vss', 'qa', 'qa_bar', 'inverter']
        assert [r for r in rows(text) if r[:2] == ['.subckt', 'pfd']] == [['.subckt', 'pfd', 'a', 'b', 'qa', 'qb']]
        assert rows((run / name / 'pfd.raw-back.sp').read_text()) == [['.end']]
        assert rows((run / name / 'inverter.raw-back.sp').read_text()) == inverter_rows
        assert rows(text) == list(complete_pfd.values()) + [
            ['.subckt', 'pfd', 'a', 'b', 'qa', 'qb'], ['.ends', 'pfd'],
            ['.subckt', 'inverter', 'vdd', 'vss', 'a', 'y']] + inverter_rows[:-1] + [['.ends', 'inverter'], ['.end']]
        records = pins((run / name / 'n2s/PFD.shcomp').read_text())
        assert [r[0] for r in records] == ['a', 'b', 'qa', 'qb']
        assert records == ([['a', 'inout', '60', '-30'], ['b', 'inout', '60', '-10'],
                            ['qa', 'inout', '60', '10'], ['qb', 'inout', '60', '30']] if name == 'pfd-base' else
                           [['a', 'in', '-60', '-10'], ['b', 'in', '-60', '10'],
                            ['qa', 'out', '60', '-10'], ['qb', 'out', '60', '10']])
        pfd.append(dict(name=name, full_export_cards=actual, actual_declared_pins=records,
                        ordered_call_and_formals_preserved=True))
    assert (run / 'pfd-base/dut.raw-back.sp').read_bytes() == (run / 'pfd-pininfo/dut.raw-back.sp').read_bytes()
    return bodies, pfd


def verify_manifest(manifest):
    """Exact executed name inventory and independently reconstructed compare inputs."""
    assert manifest['status'] == 'pass'
    assert [r['name'] for r in manifest['cases']] == NAMES
    expected_names = ['pack-sync']
    expected_comparisons = {name: (['dut'] if not name.startswith('pfd-') else ['pfd', 'dut', 'inverter']) for name in NAMES}
    spec = importlib.util.spec_from_file_location('recorded_roundtrip', BASE / 'feedback-native/tests/roundtrip.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for case in manifest['cases']:
        name = case['name']
        expected_names.extend([name + ':import', name + ':bench-netlist'])
        wanted = expected_comparisons[name]
        assert [c['subcircuit'] for c in case['comparisons']] == wanted
        assert all(c['exit_code'] == 0 for c in case['comparisons'])
        model_context = '.model nm nmos\n' if not name.startswith('pfd-') else '.model nch nmos\n.model pch pmos\n'
        assert case['exported_declaration_context'] == model_context
        for component in wanted:
            expected_names.extend([name + ':' + component + ':netlist', name + ':' + component + ':spicecmp'])
            original = (RUN / name / 'n2s/input.cir').read_text()
            assert (RUN / name / (component + '.expected.sp')).read_text() == module.probe(original, component)
            raw = (RUN / name / (component + '.raw-back.sp')).read_text()
            assert (RUN / name / (component + '.back.sp')).read_text() == model_context + raw
    assert [c['label'] for c in manifest['commands']] == expected_names
    assert all(c['exit_code'] == 0 for c in manifest['commands'])
    assert len(expected_names) == 29
    assert {p['path'] for p in manifest['artifacts']} == {relative(p) for p in RUN.rglob('*') if p.is_file()}
    assert len(manifest['artifacts']) == len({p['path'] for p in manifest['artifacts']})
    for item in manifest['inputs'] + manifest['artifacts']:
        assert sha(ROOT / item['path']) == item['sha256']
    for command in manifest['commands']:
        if command['label'].endswith(':spicecmp'):
            assert command['argv'][0] == str(BASE / 'host-target/debug/spicecmp')
            assert (ROOT / command['stdout']['path']).read_text().startswith('equivalent: devices ')


def rejection_controls(manifest):
    rejected = []
    for kind in ('nonpass_status', 'command_failure', 'comparison_failure', 'duplicate_command_name',
                 'missing_command', 'duplicate_component', 'missing_component', 'changed_expected_component_name'):
        mutant = copy.deepcopy(manifest)
        if kind == 'nonpass_status':
            mutant['status'] = 'roundtrip-mismatch'
        elif kind == 'command_failure':
            mutant['commands'][4]['exit_code'] = 1
        elif kind == 'comparison_failure':
            mutant['cases'][0]['comparisons'][0]['exit_code'] = 1
        elif kind == 'duplicate_command_name':
            mutant['commands'][4]['label'] = mutant['commands'][3]['label']
        elif kind == 'missing_command':
            mutant['commands'].pop()
        elif kind == 'duplicate_component':
            mutant['cases'][0]['comparisons'].append(mutant['cases'][0]['comparisons'][0])
        elif kind == 'missing_component':
            mutant['cases'][0]['comparisons'].clear()
        else:
            mutant['cases'][0]['comparisons'][0]['subcircuit'] = 'other'
        try:
            verify_manifest(mutant)
        except AssertionError:
            rejected.append(kind)
        else:
            raise AssertionError(('accepted saved run mutation', kind))
    # Re-hashing changed bytes cannot grant authority to changed terminal order.
    for kind, case, old, new in [
        ('actual_body_binding_changed_rehashed', 'one_body_peer', 'M1 d g s b nm', 'M1 d g s s nm'),
        ('actual_pfd_binding_changed_rehashed', 'pfd-base', 'XPFD A B QA QB PFD', 'XPFD B A QA QB PFD'),
    ]:
        with tempfile.TemporaryDirectory(prefix='cktimg-eighth-proof-') as work:
            copied = Path(work) / 'copy'
            shutil.copytree(RUN, copied)
            target = copied / case / 'dut.raw-back.sp'
            original = target.read_text()
            assert original.count(old) == 1
            target.write_text(original.replace(old, new))
            rehashed = sha(target)
            try:
                verify_actual(copied)
            except AssertionError:
                rejected.append(dict(name=kind, changed_sha256=rehashed))
            else:
                raise AssertionError(('accepted changed actual export', kind))
    return rejected


def execute_mutations(manifest):
    assert not CONTROLS.exists(), 'preserve previous control execution'
    CONTROLS.mkdir()
    work = Path(tempfile.mkdtemp(prefix='cktimg-eighth-controls-'))
    env = os.environ.copy()
    env.update(manifest['isolated_environment'])
    binary = str(BASE / 'host-target/debug/spicecmp')
    commands = []

    def run(command, cwd, name):
        p = subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=180)
        for suffix, data in [('.stdout', p.stdout), ('.stderr', p.stderr)]:
            (CONTROLS / (name + suffix)).write_bytes(data)
        commands.append(dict(name=name, argv=command, cwd=str(cwd), exit_code=p.returncode))
        return p.returncode

    for name, case, old, new in [
        ('mos_body_changed_to_source', 'one_body_peer', 'M1 d g s b nm', 'M1 d g s s nm'),
        ('pfd_inputs_swapped', 'pfd-base', 'XPFD A B QA QB PFD', 'XPFD B A QA QB PFD'),
        ('pfd_outputs_swapped', 'pfd-base', 'XPFD A B QA QB PFD', 'XPFD A B QB QA PFD'),
        ('pfd_missing_call', 'pfd-base', 'XPFD A B QA QB PFD\n', ''),
    ]:
        source = (RUN / case / 'dut.back.sp').read_text()
        assert source.count(old) == 1
        mutant = CONTROLS / (name + '.sp')
        mutant.write_text(source.replace(old, new))
        run([binary, str(RUN / case / 'dut.expected.sp'), str(mutant)], work, name)
    project = work / 'body-label-removed'
    shutil.copytree(RUN / 'one_body_peer', project)
    component = project / 'n2s/dut.shcomp'
    original = component.read_text()
    remove = 'label sx6217 55 90 R270 b\n'
    assert original.count(remove) == 1
    component.write_text(original.replace(remove, ''))
    cli = [str(BASE / 'host-target/debug/schemify'), '-u', str(Path(manifest['isolated_work']) / 'init.lua')]
    assert run(cli + ['netlist', 'n2s/dut.shcomp', '--dialect', 'ngspice', '-o', 'removed.raw-back.sp'],
               project, 'body_peer_label_removed_netlist') == 0
    raw = (project / 'removed.raw-back.sp').read_text()
    context = manifest['cases'][0]['exported_declaration_context']
    changed = CONTROLS / 'body_peer_label_removed.sp'
    changed.write_text(context + raw)
    run([binary, str(RUN / 'one_body_peer/dut.expected.sp'), str(changed)], work, 'body_peer_label_removed_compare')
    shutil.copy2(component, CONTROLS / 'body_peer_label_removed.shcomp')
    (CONTROLS / 'commands.json').write_text(json.dumps(commands, sort_keys=True, indent=2) + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute-controls', action='store_true')
    ap.add_argument('--output', type=Path, default=HERE / 'eighth-target-proof.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    manifest_path = HERE / 'eighth-target-run.json'
    manifest = json.loads(manifest_path.read_text())
    verify_manifest(manifest)
    bodies, pfd = verify_actual()
    if args.execute_controls:
        execute_mutations(manifest)
    commands = json.loads((CONTROLS / 'commands.json').read_text())
    assert [(c['name'], c['exit_code']) for c in commands] == [
        ('mos_body_changed_to_source', 1), ('pfd_inputs_swapped', 0), ('pfd_outputs_swapped', 0),
        ('pfd_missing_call', 1), ('body_peer_label_removed_netlist', 0), ('body_peer_label_removed_compare', 1)]
    result = dict(script_sha256=sha(Path(__file__)), manifest_sha256=sha(manifest_path),
                  named_cases=NAMES, actual_body_records=bodies, actual_pfd_records=pfd,
                  rejected_saved_evidence_mutations=rejection_controls(manifest),
                  controls=commands, inputs={relative(p): sha(p) for p in sorted(CONTROLS.iterdir()) if p.is_file()},
                  scope='Existing recorded host/plugin version only; no same-version native/plugin geometry claim.')
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(actual_cases=len(NAMES), comparator_controls=[(c['name'], c['exit_code']) for c in commands])))


if __name__ == '__main__':
    main()
