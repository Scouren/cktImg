#!/usr/bin/env python3
"""Materialize raw-ambiguity and per-instance signed-slot research fixtures.

Runs the already frozen native CLI. Never builds or edits engine sources.
Literal ordered terminal maps and explicit caller geometry are the oracle;
future automatic owner decisions are labelled separately from observations.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import subprocess

import ports_predicates as p

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FROZEN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/resistor-output-integrated-common'
BINARY = FROZEN / 'zig-out/bin/cktimg-json'
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/ports/fourth'
EXPECTED_BINARY = 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'
CUSTOM_TERMS = {'vdd': [0, -60], 'vss': [0, 60], 'inn': [-90, 30], 'inp': [-90, -30], 'out': [90, 0]}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return str(path.relative_to(ROOT))


def hint(text, line):
    return text.replace('.ends dut', line + '\n.ends dut')


def reverse_cards(text):
    lines = text.splitlines()
    start = next(i for i, s in enumerate(lines) if s.startswith('.subckt dut')) + 1
    end = lines.index('.ends dut')
    cards = [s for s in lines[start:end] if s and s[0].lower() in 'xmrc']
    rest = [s for s in lines[start:end] if s not in cards]
    return '\n'.join(lines[:start] + list(reversed(cards)) + rest + lines[end:]) + '\n'


def symbols(name):
    base = (FROZEN / 'tests/symbols.zon').read_text()
    if name == 'b17':
        # Literal five-port generated triangle, representing the registered
        # b<s> boundary. This is a CLI proxy, not a plugin execution.
        points = {'vdd': [0, -60], 'vss': [0, 60], 'inn': [-60, -20], 'inp': [-60, 20], 'out': [60, 0]}
        terms = ', '.join('.{ .name = "%s", .at = .{ .x = %s, .y = %s } }' % (n, x, y)
                          for n, (x, y) in points.items())
        ops = ['.{ .polyline = .{ .{ .x = -40, .y = -40 }, .{ .x = 40, .y = 0 }, .{ .x = -40, .y = 40 }, .{ .x = -40, .y = -40 } } }']
        for (x, y), (a, b) in [((0, -60), (0, -20)), ((0, 60), (0, 20)),
                                ((-60, -20), (-40, -20)), ((-60, 20), (-40, 20)), ((60, 0), (40, 0))]:
            ops.append('.{ .line = .{ .a = .{ .x = %d, .y = %d }, .b = .{ .x = %d, .y = %d } } }' % (x, y, a, b))
        for y, label in [(-20, '-'), (20, '+')]:
            ops.append('.{ .text = .{ .at = .{ .x = -30, .y = %d }, .s = "%s", .size = 7 } }' % (y, label))
        own = '        .{ .name = "b17", .terminals = .{ %s }, .draw = .{ %s } },\n' % (terms, ', '.join(ops))
        where = base.rindex('    },')
        return base[:where] + own + base[where:]
    terms = ', '.join('.{ .name = "%s", .at = .{ .x = %s, .y = %s } }' % (n, x, y)
                      for n, (x, y) in CUSTOM_TERMS.items())
    ops = ['.{ .polyline = .{ .{ .x = -60, .y = -45 }, .{ .x = 60, .y = -45 }, .{ .x = 60, .y = 45 }, .{ .x = -60, .y = 45 }, .{ .x = -60, .y = -45 } } }']
    for (x, y), (a, b) in [((0, -60), (0, -45)), ((0, 60), (0, 45)),
                            ((-90, 30), (-60, 30)), ((-90, -30), (-60, -30)), ((90, 0), (60, 0))]:
        ops.append('.{ .line = .{ .a = .{ .x = %d, .y = %d }, .b = .{ .x = %d, .y = %d } } }' % (x, y, a, b))
    for x, y, label in [(-48, -30, '+'), (-48, 30, '-'), (0, 0, 'CALLER')]:
        ops.append('.{ .text = .{ .at = .{ .x = %d, .y = %d }, .s = "%s", .size = 10 } }' % (x, y, label))
    own = '        .{ .name = "%s", .terminals = .{ %s }, .draw = .{ %s } },\n' % (name, terms, ', '.join(ops))
    where = base.rindex('    },')
    return base[:where] + own + base[where:]


def fixtures():
    reg = (HERE / 'fourth-ports-two-regulators.cir').read_text()
    shared = (HERE / 'fourth-ports-shared-definition.cir').read_text()
    bias = (HERE / 'fourth-ports-two-bias-peers.cir').read_text()
    single_reg = '\n'.join(s for s in reg.splitlines() if not s.startswith(('XB ', 'MB ', 'RBU ', 'RBL '))) + '\n'
    single_bias = bias.replace('XBB VDD VSS bb bias\n', '').replace('OUT ba bb opamp', 'OUT ba VB2 opamp').replace('VSS INN INP OUT\n', 'VSS INN INP OUT VB2\n')
    rows = {
        'reg-base': (reg, None),
        'reg-fixed-b': (hint(reg, '*@ at XB -30 -30 r90'), None),
        'reg-fixed-a': (hint(reg, '*@ at XA -30 -30 r90'), None),
        'reg-custom-b': (hint(reg, '*@ class XB caller_signed'), 'instance'),
        'reg-single-a': (single_reg, None),
        'reg-single-a-fixed': (hint(single_reg, '*@ at XA -30 -30 r90'), None),
        'shared-base': (shared, None),
        'shared-reversed': (reverse_cards(shared), None),
        'shared-projected': (shared.replace('opamp', 'b17'), 'projected'),
        'shared-custom-reg': (hint(shared, '*@ class XREG caller_signed'), 'instance'),
        'shared-custom-sample': (hint(shared, '*@ class XSAMPLE caller_signed'), 'instance'),
        'shared-family-custom': (shared, 'family'),
        'shared-family-custom-sides': (shared.replace('.ends opamp', '*@ right INN\n*@ left INP\n.ends opamp'), 'family'),
        'shared-sides': (shared.replace('.ends opamp', '*@ right INN\n*@ left INP\n.ends opamp'), None),
        'shared-fixed-reg': (hint(shared, '*@ at XREG -30 -30 r90'), None),
        'shared-custom-reg-fixed': (hint(shared, '*@ class XREG caller_signed\n*@ at XREG -30 -30 r90'), 'instance'),
        'shared-custom-reg-mirrored': (hint(shared, '*@ class XREG caller_signed\n*@ at XREG -30 -30 mr90'), 'instance'),
        'shared-both-fixed': (hint(shared, '*@ at XREG -15 -12 r0\n*@ at XSAMPLE 15 12 r0'), None),
        'bias-base': (bias, None),
        'bias-fixed-b': (hint(bias, '*@ at XBB -30 -30 r90'), None),
        'bias-single-a': (single_bias, None),
        'bias-single-a-fixed': (hint(single_bias, '*@ at XBA -30 -30 r90'), None),
        'bias-single-a-anchor-fixed': (hint(single_bias, '*@ at XAMP -30 -30 r90'), None),
        'bias-single-a-unrelated-fixed': (hint(single_bias, 'RX VDD VSS 1k\n*@ at RX -30 -30 r90'), None),
    }
    rows['reg-fixed-b-reversed'] = (reverse_cards(rows['reg-fixed-b'][0]), None)
    rows['bias-fixed-b-reversed'] = (reverse_cards(rows['bias-fixed-b'][0]), None)
    # Disable only the exact peer family predicate, retaining all ports/bindings.
    for name in ('bias-base', 'bias-fixed-b', 'bias-single-a'):
        rows[name + '-opaque'] = (rows[name][0].replace('bias', 'opaque'), None)
    return rows


def parse(text):
    # Deliberately keep caller hints out of raw electrical enumeration.
    electrical = '\n'.join(s for s in text.splitlines() if not s.lstrip().startswith('*@'))
    cards = p.old.aliases.read_cards(electrical)
    defs = p.old.digital.declarations(electrical)
    models = {w[1]: w[2] for line in text.lower().splitlines() if (w := line.split()) and w[0] == '.model'}
    return cards, defs, models


def local_candidates(text):
    """Bounded exhaustive subset witness, then full-DUT incidence closure.

    This research enumerator is not a production collector. Literal fixture
    tuples below are its independent oracle. No caller state enters it.
    """
    cards, defs, models = parse(text)
    full = p.incidences(cards, defs)
    out = []
    for kind, count in [('regulator', 4), ('sample', 5)]:
        for names in itertools.combinations(sorted(cards), count):
            subset = {n: cards[n] for n in names}
            hit = p.strengthened(kind, subset, defs, models)
            if hit is None:
                continue
            top = hit['topology']
            nets = top['nets']
            protected = [nets['negative'], nets['output'], nets['positive']]
            if kind == 'sample':
                protected = [nets['negative'], nets['output'], top['junction']]
                protected += [cards[n][2] for n in top['switches']]
                channels = {cards[n][i] for n in top['switches'] for i in (1, 3)}
                protected += list(channels - {nets['negative'], top['junction']})
            protected += [net for role, net in nets.items() if role.startswith('bias')]
            # Exposing unrelated cards cannot silently remove a consumer.
            if any(sorted(full[n]) != sorted(hit['raw_incidence'][n]) for n in set(protected)):
                continue
            out.append(dict(kind=kind, amplifier=top['amplifier']['card'], members=list(names),
                            complete_call=top['amplifier'], topology=top,
                            closed_nets={n: full[n] for n in sorted(set(protected))},
                            desired_signed_slot='positive_above' if kind == 'regulator' else 'negative_above'))
    return sorted(out, key=lambda x: (x['kind'], x['amplifier']))


def local_pins(dev):
    # Invert the documented mirror-then-clockwise transform for observed pins.
    out = {}
    for pin in dev['pins']:
        x, y = [a - b for a, b in zip(pin['xy'], dev['pos'])]
        for _ in range(dev['rot']):
            x, y = y, -x
        if dev['mirror']:
            x = -x
        out[pin['term']] = [x, y]
    return out


def run(name, text, sym, execute):
    deck = HERE / ('fourth-ports-' + name + '.cir')
    if deck.exists():
        assert deck.read_text() == text, 'fixture drift: ' + name
    else:
        deck.write_text(text)
    target = RUN / name
    args = [str(BINARY), '--svg', str(target.with_suffix('.svg')), '--report', str(target.with_suffix('.report.json'))]
    symfile = HERE / ('fourth-ports-caller-' + sym + '.zon') if sym else None
    if symfile:
        args += ['--symbols', str(symfile)]
    args += [str(deck), str(target.with_suffix('.json'))]
    if execute:
        result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
        assert result.returncode == 0, (name, result.returncode, result.stderr)
        assert not result.stderr, (name, result.stderr)
    data = json.loads(target.with_suffix('.json').read_text())
    cards, defs, _ = parse(text)
    calls = p.old.calls(cards, defs)
    devices = {d['name']: d for d in data['devices'] if d['name'] in cards}
    for call in calls:
        dev = devices[call['card']]
        assert [pin['net'] for pin in dev['pins']] == call['bindings'], (name, call['card'], 'raw binding changed')
        assert [pin['term'] for pin in dev['pins']] == call['ports'], (name, call['card'], 'formal order changed')
    for card, words in cards.items():
        dev = devices[card]
        if card[0] == 'm':
            assert [pin['net'] for pin in dev['pins']] == words[1:4]
            assert dev['bulk'] == words[4]
        elif card[0] in 'rc':
            assert [pin['net'] for pin in dev['pins']] == words[1:3]
    blocks = {call['card']: dict(class_name=devices[call['card']]['class'],
                                canonical_pins=local_pins(devices[call['card']]),
                                final_device=devices[call['card']]) for call in calls}
    report = json.loads(target.with_suffix('.report.json').read_text())
    return dict(name=name, command=[relative(Path(x)) if x.startswith(str(ROOT)) else x for x in args],
                deck=relative(deck), deck_sha256=sha(deck),
                symbols=relative(symfile) if symfile else None, symbols_sha256=sha(symfile) if symfile else None,
                outputs={suffix: dict(path=relative(target.with_suffix(suffix)), sha256=sha(target.with_suffix(suffix)))
                         for suffix in ('.json', '.svg', '.report.json')},
                complete_calls=calls, blocks=blocks, report=report)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute', action='store_true', help='Run the frozen CLI; without this, verify saved files.')
    parser.add_argument('--output', type=Path, default=HERE / 'fourth-ports-fixtures.json')
    parser.add_argument('--check', type=Path)
    args = parser.parse_args()
    assert sha(BINARY) == EXPECTED_BINARY
    RUN.mkdir(parents=True, exist_ok=True)
    for kind, name in [('instance', 'caller_signed'), ('family', 'opamp'), ('projected', 'b17')]:
        path = HERE / ('fourth-ports-caller-' + kind + '.zon')
        text = symbols(name)
        if path.exists():
            assert path.read_text() == text
        else:
            path.write_text(text)
    rows = fixtures()
    runs = [run(name, text, sym, args.execute) for name, (text, sym) in sorted(rows.items())]
    # Additional current/future relations are kept in a separate verifier.
    result = dict(scope='Frozen CLI observations; automatic local owner policies remain future-only.',
                  binary=relative(BINARY), binary_sha256=sha(BINARY), runs=runs,
                  literal_custom_terms=CUSTOM_TERMS,
                  local_candidate_census={name: local_candidates(text) for name, (text, _) in sorted(rows.items()) if not name.startswith('bias-')},
                  dependencies={relative(x): sha(x) for x in [Path(__file__), HERE / 'ports_predicates.py',
                      ROOT / 'src/library.zig', ROOT / 'src/schematic.zig', ROOT / 'src/bias_neighbors.zig',
                      ROOT / 'src/block_input_rc.zig', ROOT / 'src/opamp.zig', ROOT / 'tools/schemify/recognize.zig',
                      ROOT / 'src/sketch.zig', ROOT / 'tools/schemify/layout.zig', ROOT / 'tools/schemify/names.zig', ROOT / 'tools/schemify/emit.zig',
                      FROZEN / 'src/library.zig', FROZEN / 'src/bias_neighbors.zig', FROZEN / 'tests/symbols.zon']})
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('PASS', len(runs), 'frozen CLI runs; ordered call bindings retained.')


if __name__ == '__main__':
    main()
