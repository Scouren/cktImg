#!/usr/bin/env python3
"""Actual source-lead geometry and named raw grouping boundaries, not placement."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EXAMPLES = ROOT / 'external/examples/analoggenie'
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
sys.path.insert(0, str(HERE.parent.parent / 'figures'))
from channel_bridges import svg_channel
sys.path.insert(0, str(HERE.parent))
from ag1080_channel_groups import certify, read_cells

NOTES = {
    'ag-1016': 'Source is a unified current-mode drawing with nested/interleaved proposed groups; the five raw components do not justify five disjoint placement boxes. Native also presents a global mirrored core.',
    'ag-1028': 'Source separates two five-device stages left/right; native places second-stage outputs outside the first stage under one broad axis. Grouping candidate is useful, exact packing remains separate.',
    'ag-1046': 'Source has two separately drawn latch/input cores left/right. Native interleaves their devices around one axis; source group order is not inferred from numerical device names.',
    'ag-1047': 'Source places two cores vertically, with diagonal internal coupling in the lower core. Native spreads both across one axis. Membership does not dictate horizontal packing.',
    'ag-1051': 'Source shows two vertically separated clocked cores, with long interfaces outside them. Native interleaves the cores and uses repeated signal labels.',
    'ag-1071': 'Source has separate left input core and right regenerative core. Native puts output branches outside the input core. Internal crossed-gate routing remains a separate requirement.',
    'ag-1075': 'Source upper amplifier and lower latch are separated vertically. Native flattens their devices across one wide core. Visible diagonal latch routing does not authorize diagonal outer interfaces.',
    'ag-1077': 'Source stacks two cores; the second tail has a horizontal glyph. Native places its tail at the top of a global axis. Candidate membership alone does not preserve that tail pose.',
    'ag-1079': 'Source presents three groups with the final latch below the first two. Native flattens them across one large mirrored span.',
    'ag-1080': 'Source presents five parent groups with two serial branches feeding a larger bottom latch. Bottom group includes separate two-device side branches joined by OUTP/OUTN names; not one compact or continuous region. Native flattens the parents across one broad axis.',
    'ag-364': 'Source nests two output branches around the inner nine-device core. Native retains the same inner/outer relationship. Two raw parent groups must not automatically become disjoint boxes.',
    'ag-928': 'Source and native both retain one stacked differential core. Local group work must preserve this whole; individual facing and spacing remain separate.',
    'ag-1037': 'Source has two mirrored conduction branches forming one latch. Reflected-component merging correctly keeps one parent; diagonal source coupling is independent of group count.',
    'ag-925': 'Source has a core plus common-mode/bias attachments; native mixes several attachments across the whole. Multiple exact involutions make a unique new decomposition unavailable.',
    'ag-1053': 'Source integrates the feedback side branches with its main core. The proposed two-parent dependency cycle is declined; treating it as a serial cascade is unsupported.',
    'ag-924': 'Source visibly separates main core and common-mode feedback block. Conservative cycle decline misses this useful example, so the bounded collector is not complete.',
    'ag-1057': 'Source explicitly shows PWELL and separate source/body ties. Narrow admitted VDD/VSS body ownership declines this whole example; no body equivalence claim.',
    'ag-2361': 'Source has a regulator/control family with internal pb/nb controls and a separate amplifier block. The unsupported floating-control boundary declines it; labels are not silently treated as rails.',
    'ag-459': 'Source and native both preserve source-degenerated local mates. Passive/current attachments decline the all-MOS experiment; this is a kept native arrangement, not a membership failure.',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_census_module():
    spec = importlib.util.spec_from_file_location('ninth_census', HERE / 'ninth-local-groups-census.py')
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(HERE))
    spec.loader.exec_module(module)
    return module


def box(points):
    return [min(p[0] for p in points), min(p[1] for p in points),
            max(p[0] for p in points), max(p[1] for p in points)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE / 'ninth-local-groups-proof.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    paths = {key: HERE / ('ninth-local-groups-' + key + '.json') for key in ('census', 'native')}
    census, native = [json.loads(paths[k].read_text()) for k in ('census', 'native')]
    module = load_census_module()
    assert census['script_sha256'] == sha(HERE / 'ninth-local-groups-census.py')
    assert native['census_sha256'] == sha(paths['census'])
    assert set(NOTES) == set(native['names']) and len(native['names']) == 19
    views = []
    for record in native['records']:
        ident = record['id']
        for key in ('output_sha256', 'raster_sha256'):
            for path, digest in record[key].items():
                assert sha(ROOT / path) == digest
        deck = EXAMPLES / (ident + '.cir')
        assert sha(deck) == record['deck_sha256'] == census['cases'][ident]['deck_sha256']
        assert sha(deck.with_suffix('.svg')) == record['source_sha256']
        raw = module.facts(deck.read_text())[0]
        assert [raw[n] for n in sorted(raw)] == census['cases'][ident]['ordered_cards']
        actual_path = BASE / 'image-rule-round-2/groups/ninth' / (ident + '.json')
        actual = {d['name']: d for d in json.loads(actual_path.read_text())['devices'] if d['name'] in raw}
        assert actual == record['complete_native_devices'] and set(actual) == set(raw)
        for name, row in raw.items():
            count = 3 if name.startswith('m') else 2
            assert [p['net'] for p in actual[name]['pins']] == row[1:count + 1]
            if name.startswith('m'):
                assert actual[name]['bulk'] == row[4]
        pair = HERE / 'figures/groups/ninth' / (ident + '-pair.png')
        views.append(dict(id=ident, path=str(pair.relative_to(ROOT)), sha256=sha(pair), actual_view_note=NOTES[ident]))
    certificates = {}
    for ident in census['disposition_names']['raw_multigroup_candidate'] + ['ag-928']:
        prefix = EXAMPLES / ident
        human = json.loads(prefix.with_suffix('.human.json').read_text())
        devices = {d['card']: d for d in human['devices']}
        case = census['cases'][ident]
        assert set(devices) == {r[0] for r in case['ordered_cards']}
        actual_leads = {name: svg_channel(prefix.with_suffix('.svg'), d)[1] for name, d in sorted(devices.items())}
        bounds = [box([point for name in group for point in actual_leads[name]]) for group in case['proposed_groups']]
        overlaps = [[a, b] for a in range(len(bounds)) for b in range(a + 1, len(bounds))
                    if max(bounds[a][0], bounds[b][0]) < min(bounds[a][2], bounds[b][2])
                    and max(bounds[a][1], bounds[b][1]) < min(bounds[a][3], bounds[b][3])]
        assert bool(overlaps) == (ident in ['ag-1016', 'ag-364'])
        incidences = [[row[0], index, terminal, row[index + 1]] for row in case['ordered_cards']
                      for index, terminal in enumerate(['D', 'G', 'S', 'B'])]
        certificates[ident] = dict(source_svg_sha256=sha(prefix.with_suffix('.svg')),
                                   source_human_sha256=sha(prefix.with_suffix('.human.json')),
                                   actual_svg_channel_leads=actual_leads, groups=case['proposed_groups'],
                                   channel_lead_boxes=bounds, positive_area_box_overlaps=overlaps,
                                   all_ordered_terminal_incidences=incidences,
                                   scope='Bounds of actual own channel stubs only, not full wire/glyph ownership or compactness.')
    legacy = {}
    for ident in ['ag-1080', 'ag-928']:
        case = census['cases'][ident]
        report_path = BASE / 'image-rule-round-2/groups/ninth' / (ident + '.report.json')
        rows = {row[0]: row[1:] for row in case['ordered_cards']}
        old = certify(rows, read_cells(json.loads(report_path.read_text())), {'0', 'vdd', 'vss'})
        maps = [m for m in case['enumerated_involutions'] if any(a != b for a, b in m['nets'].items())]
        assert len(maps) == 1 and maps[0]['devices'] == old['device_map'] and maps[0]['nets'] == old['net_map']
        assert {tuple(sorted(g)) for g in old['paired_channel_groups']} == {tuple(sorted(g)) for g in case['proposed_groups']}
        legacy[ident] = dict(report_sha256=sha(report_path), raw_unique_involution_equals_certified_report=True)
    original = (EXAMPLES / 'ag-1080.cir').read_text()
    parser_controls = {}
    for name, text, wanted in [
        ('continued_extra_formal', original.replace('OUTP OUTN\n', 'OUTP OUTN\n+ unused_formal\n'), 'decline_input_boundary'),
        ('continued_original_formals', original.replace('OUTP OUTN\n', '\n+ OUTP OUTN\n'), 'raw_multigroup_candidate'),
        ('duplicate_contradictory_model', original.replace('.model nch nmos', '.model nch pmos\n.model nch nmos'), 'decline_input_boundary'),
        ('nonformal_named_rails', original.replace('dut VDD VSS ', 'dut '), 'decline_input_boundary'),
    ]:
        candidate = module.decompose(*module.facts(text))
        assert candidate['disposition'] == wanted
        if name == 'continued_original_formals':
            assert candidate['formals'] == census['cases']['ag-1080']['formals']
            assert candidate['proposed_groups'] == census['cases']['ag-1080']['proposed_groups']
        parser_controls[name] = dict(source_sha256=hashlib.sha256(text.encode()).hexdigest(),
                                     disposition=wanted, reasons=candidate['reasons'])
    result = dict(script_sha256=sha(Path(__file__)), input_sha256={str(p.relative_to(ROOT)): sha(p) for p in paths.values()},
                  exact_source_overlap_names=['ag-1016', 'ag-364'], source_certificates=certificates,
                  raw_vs_report_controls=legacy, parser_authority_controls=parser_controls, views=views,
                  claim='11 raw candidates; nine have nonoverlapping own-channel-stub box interiors, two overlap. This is not automatic placement admission.')
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(views=len(views), source_lead_cases=len(certificates),
                         source_channel_pairs=sum(len(c['actual_svg_channel_leads']) for c in certificates.values()),
                         overlap_names=result['exact_source_overlap_names'])))


if __name__ == '__main__':
    main()
