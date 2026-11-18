#!/usr/bin/env python3
"""Narrow visibility-state admission layered over the unchanged fifth proof."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location('fifth_body_proof', HERE / 'fifth-bodies-proof.py')
f = importlib.util.module_from_spec(spec)
spec.loader.exec_module(f)
RUN = f.BASE / 'image-rule-round-2/bodies/eighth-visibility'


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def tag(node):
    return node.tag.rsplit('}', 1)[-1]


def visibility_admission(number, root, certificate):
    """Refuse unsupported display authority; never infer generic SVG visibility."""
    baseline = f.ET.parse(f.b.EXAMPLES / f'ag-{number}.svg').getroot()
    css = lambda tree: [''.join(e.itertext()) for e in tree.iter() if tag(e) == 'style']
    assert css(root) == css(baseline), 'global stylesheet differs from the fixed source profile'
    parents = {child: parent for parent in root.iter() for child in parent}
    # Full-width rail owners are logical route IDs, not symbol element IDs;
    # their actual label and conductor paths are inspected separately below.
    ids = {m['object'] for m in certificate['all_actual_markers'] if m['kind'] != 'power-rail'}
    ids.update(m['label']['object'] for m in certificate['all_actual_markers'] if m['label'])
    for row in certificate['body_bindings']:
        ident = row['source_geometry']['actual_DGS']['object']
        ids.update([ident, 'instance-label-' + ident])
    targets = [e for e in root.iter() if e.get('data-object-id') in ids or
               e.get('data-role') == 'conductor-ink' or e.get('data-node-kind') == 'contact' or
               e.get('data-object-id', '').endswith('-junction')]
    assert ids <= {e.get('data-object-id') for e in targets}
    scoped = set()
    for target in targets:
        scoped.update(target.iter())
        while target in parents:
            target = parents[target]
            scoped.add(target)
    forbidden = {'visibility', 'display', 'opacity', 'fill-opacity', 'stroke-opacity',
                 'clip-path', 'mask', 'filter', 'class'}
    for node in scoped:
        assert not forbidden.intersection(node.attrib), 'unsupported visibility/clipping/class authority'
        styles = dict(part.split(':', 1) for part in node.get('style', '').split(';') if ':' in part)
        styles = {k.strip().lower(): v.strip().lower() for k, v in styles.items()}
        assert set(styles) <= {'font-style', 'font-weight'}, 'unsupported inline style authority'
        assert styles.get('font-style', 'normal') in ['normal', 'italic']
        assert styles.get('font-weight', '400') in ['400', '700']
        for prop in ('fill', 'stroke'):
            if node.get(prop) is not None:
                assert node.get(prop).lower() in ['none', '#000', '#000000', '#fff', '#ffffff'], 'unsupported paint'
        if node.get('stroke-width') is not None:
            assert float(node.get('stroke-width')) > 0, 'zero or negative stroke width'
        if node.get('font-size') is not None:
            assert float(node.get('font-size').removesuffix('px')) > 0, 'zero or negative font size'
    # Evaluate only the fixed profile's simple inherited paint attributes.
    for node in scoped:
        if tag(node) not in ['line', 'polyline', 'path', 'circle', 'polygon', 'text', 'tspan']:
            continue
        chain = [node]
        while chain[-1] in parents:
            chain.append(parents[chain[-1]])
        paint = {'fill': '#000', 'stroke': 'none'}  # pinned source stylesheet
        for ancestor in reversed(chain):
            for prop in paint:
                if ancestor.get(prop) is not None:
                    paint[prop] = ancestor.get(prop).lower()
        black = {'#000', '#000000'}
        if tag(node) in ['text', 'tspan']:
            assert paint['fill'] in black, 'unsupported invisible text fill'
        elif tag(node) in ['line', 'polyline', 'path']:
            assert paint['stroke'] in black, 'unsupported invisible stroke'
        else:
            assert paint['fill'] in black or paint['stroke'] in black, 'unsupported invisible circle/polygon'
    return dict(objects=sorted(ids), inspected_elements=len(scoped),
                pinned_stylesheet_sha256=[digest(text) for text in css(root)])


def certify(number, root=None):
    if root is None:
        root = f.ET.parse(f.b.EXAMPLES / f'ag-{number}.svg').getroot()
    old = f.certify(number, root=root)
    admitted = visibility_admission(number, root, old)
    return dict(id=f'ag-{number}', ordered_body_bindings=[r['ordered_DGSB'] for r in old['body_bindings']],
                prior_certificate_sha256=digest(json.dumps(old, sort_keys=True)), admission=admitted)


def controls():
    root = f.ET.parse(f.b.EXAMPLES / 'ag-1014.svg').getroot()
    old = f.certify(1014, root=root)
    first = old['body_bindings'][0]
    marker = first['reachable_raw_markers'][0]['marker']
    rows = []
    for name in ['hidden_body_label', 'hidden_port_stem', 'hidden_body_conductor',
                 'invisible_own_channel', 'inherited_hidden_marker', 'stylesheet_hides_marker']:
        changed = copy.deepcopy(root)
        at = lambda ident: next(e for e in changed.iter() if e.get('data-object-id') == ident)
        if name == 'hidden_body_label':
            at(marker['label']['object']).set('visibility', 'hidden')
        elif name == 'hidden_port_stem':
            next(e for e in at(marker['object']).iter() if tag(e) == 'line').set('visibility', 'hidden')
        elif name == 'hidden_body_conductor':
            matches = [e for e in changed.iter() if e.get('data-role') == 'conductor-ink' and
                       'M 124 110 L 60 110' in e.get('d', '')]
            assert len(matches) == 1
            matches[0].set('visibility', 'hidden')
        elif name == 'invisible_own_channel':
            glyph = at(first['source_geometry']['actual_DGS']['object'])
            for e in glyph.iter():
                if tag(e) == 'polygon':
                    e.set('opacity', '0')
        elif name == 'inherited_hidden_marker':
            at(marker['object']).set('visibility', 'hidden')
        else:
            next(e for e in changed.iter() if tag(e) == 'style').text += '\n[data-symbol-id="port"]{visibility:hidden}'
        path = RUN / (name + '.svg')
        path.write_text(f.ET.tostring(changed, encoding='unicode'))
        prior = f.certify(1014, root=changed)  # preserves the old proof's exact scope
        assert len(prior['body_bindings']) == 2
        try:
            certify(1014, changed)
        except AssertionError as error:
            rows.append(dict(name=name, unchanged_fifth_proof_accepts=True, eighth_admission_rejects=str(error),
                             path=str(path.relative_to(f.ROOT)), sha256=f.sha(path)))
        else:
            raise AssertionError(('unsupported visibility mutation accepted', name))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', type=Path)
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    RUN.mkdir(parents=True, exist_ok=True)
    result = dict(scope='Added supported-visibility-state admission for the four fifth-body sources; previous proof unchanged.',
                  cases=[certify(n) for n in f.EXPECTED], controls=controls(),
                  dependencies={str(p.relative_to(f.ROOT)): f.sha(p) for p in [Path(__file__), HERE / 'fifth-bodies-proof.py']},
                  limitations=['Not a general CSS/occlusion/contrast evaluator.',
                               'Transformed text positions are recorded by the fifth proof; perceived label association remains unproved.',
                               'Free/route labels retain the fifth proof exclusions; no native or host claim.'])
    if args.check:
        assert result == json.loads(args.check.read_text()), 'exact visibility evidence changed'
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('PASS four original sources and six preserved old-scope/new-admission visibility controls')


if __name__ == '__main__':
    main()
