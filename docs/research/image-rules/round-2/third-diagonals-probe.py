#!/usr/bin/env python3
"""Independent source-ink census and exact literals for a proposed 45-degree capability.

No engine/host implementation is executed here. Geometry oracles use exact
Decimal/Fraction arithmetic; translated current formulas are explicitly named.
The source census admits only the actual untransformed M/L path grammar and
fails on any other tagged conductor. Images are viewed separately by an agent.
"""
import argparse
from collections import Counter, defaultdict
from decimal import Decimal
from fractions import Fraction
import hashlib
import json
from math import gcd
from pathlib import Path
import re
import struct
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/groups'
NUMBER = r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?'
COMMAND = re.compile(r'([ML])\s*(' + NUMBER + r')[\s,]+(' + NUMBER + r')')
QUANTUM = Decimal('0.000001')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def actual_segments(root):
    """Independent fail-closed reader for this inventory's conductor grammar."""
    segments, paths = [], 0

    def visit(element, ancestors):
        nonlocal paths
        transforms = ancestors + ([element.get('transform')] if element.get('transform') else [])
        if element.get('data-role') == 'conductor-ink':
            assert element.tag.rsplit('}', 1)[-1] == 'path', 'unsupported conductor element'
            assert not transforms, 'this independent census declines transformed conductors'
            paths += 1
            text, end, previous = element.get('d', ''), 0, None
            for match in COMMAND.finditer(text):
                assert not text[end:match.start()].strip(' ,\t\r\n'), 'unsupported path syntax'
                point = tuple(Decimal(v) for v in match.groups()[1:])
                if match[1] == 'L':
                    assert previous is not None, 'line without a move'
                    segments.append((previous, point))
                previous, end = point, match.end()
            assert previous is not None and not text[end:].strip(' ,\t\r\n'), 'empty/unsupported path'
        for child in element:
            visit(child, transforms)

    visit(root, [])
    return segments, paths


def direction(a, b, normalize=True):
    dx, dy = (b[k] - a[k] for k in (0, 1))
    if normalize:
        dx, dy = (v.quantize(QUANTUM) for v in (dx, dy))
    if dx == dy == 0:
        return 'zero'
    if dx == 0:
        return 'vertical'
    if dy == 0:
        return 'horizontal'
    return 'diagonal:' + str(abs(Fraction(dy) / Fraction(dx)))


def diagonal_union_count(segments):
    """Geometric collinear union only, never net identity or route counting."""
    lines = defaultdict(list)
    unique = set()
    for a, b in segments:
        a, b = [tuple(v.quantize(QUANTUM) for v in p) for p in (a, b)]
        if direction(a, b) != 'diagonal:1':
            continue
        if a > b:
            a, b = b, a
        unique.add((a, b))
        slope = 1 if b[1] > a[1] else -1
        lines[(slope, a[1] - slope * a[0])].append((a[0], b[0]))
    components = 0
    for spans in lines.values():
        high = None
        for low, end in sorted(spans):
            if high is None or low > high:
                components += 1
            high = end if high is None else max(high, end)
    return len(unique), components


def census():
    manifest = json.loads((HERE / 'manifest.json').read_text())
    inventory_path = Path(manifest['prior_audit']) / 'all-images.json'
    assert sha(inventory_path) == manifest['frozen_inventory_sha256']
    inventory = json.loads(inventory_path.read_text())
    expected = json.loads((HERE / 'wire_angles.json').read_text())
    peers = {r['id']: r for r in expected['records']}
    assert len(peers) == len(inventory) == 2202
    assert set(peers) == {r['id'] for r in inventory}
    totals, records, normalized_names = Counter(), [], []
    max_residue, max_direction_residue, minimum_nonzero = Decimal(0), Decimal(0), None
    unique_total = union_total = path_count = 0
    for item in inventory:
        path = Path(item['source_svg'])
        assert sha(path) == item['source_svg_sha256']
        segments, paths = actual_segments(ET.parse(path).getroot())
        path_count += paths
        counts = Counter(direction(a, b) for a, b in segments)
        assert dict(counts) == peers[item['id']]['counts'], item['id']
        changed = sum(direction(a, b, False) != direction(a, b) for a, b in segments)
        if changed:
            normalized_names.append(item['id'])
        local_residue = Decimal(0)
        for a, b in segments:
            delta = [b[k] - a[k] for k in (0, 1)]
            local_residue = max(local_residue, *(abs(v - v.quantize(QUANTUM)) for v in delta))
            kind = direction(a, b)
            residue = abs(delta[1]) if kind == 'horizontal' else abs(delta[0]) if kind == 'vertical' else abs(abs(delta[0])-abs(delta[1]))
            max_direction_residue = max(max_direction_residue, residue)
            length = max(abs(v.quantize(QUANTUM)) for v in delta)
            if length:
                minimum_nonzero = length if minimum_nonzero is None else min(minimum_nonzero, length)
        max_residue = max(max_residue, local_residue)
        unique, unions = diagonal_union_count(segments)
        unique_total += unique
        union_total += unions
        totals.update(counts)
        records.append(dict(id=item['id'], source_svg_sha256=sha(path), counts=dict(sorted(counts.items())),
                            normalization_changes=changed, maximum_delta_residue=str(local_residue),
                            unique_diagonal_segments=unique, geometric_collinear_unions=unions))
    assert dict(totals) == expected['totals']
    return dict(inventory_sha256=sha(inventory_path), peer_sha256=sha(HERE/'wire_angles.json'),
                exact_named_records=records, totals=dict(sorted(totals.items())), tagged_paths=path_count,
                diagonal_names=[r['id'] for r in records if r['unique_diagonal_segments']],
                normalization_changed_names=normalized_names, maximum_delta_residue=str(max_residue),
                maximum_direction_closure_residue=str(max_direction_residue),
                minimum_normalized_nonzero_chebyshev_span=str(minimum_nonzero),
                unique_diagonal_segments=unique_total, geometric_collinear_unions=union_total,
                other_conductor_tags=0, transformed_conductor_paths=0)


def cross(a, b):
    return a[0]*b[1] - a[1]*b[0]


def subtract(a, b):
    return a[0]-b[0], a[1]-b[1]


def bbox(p, a, b):
    return all(min(a[k], b[k]) <= p[k] <= max(a[k], b[k]) for k in (0, 1))


def on_segment(p, a, b):
    return cross(subtract(p, a), subtract(b, a)) == 0 and bbox(p, a, b)


def intersection(a, b, c, d):
    u, v, w = subtract(b, a), subtract(d, c), subtract(c, a)
    denominator = cross(u, v)
    if not denominator:
        return None
    t, q = Fraction(cross(w, v), denominator), Fraction(cross(w, u), denominator)
    if not (0 <= t <= 1 and 0 <= q <= 1):
        return None
    return tuple(Fraction(a[k]) + t*u[k] for k in (0, 1))


def rays(at, segments):
    directions = set()
    for a, b in segments:
        if not on_segment(at, a, b):
            continue
        for p in (a, b):
            dx, dy = subtract(p, at)
            divisor = gcd(abs(dx), abs(dy))
            if divisor:
                directions.add((dx//divisor, dy//divisor))
    return directions


def f32(v):
    return struct.unpack('f', struct.pack('f', v))[0]


def literals():
    a, b = (0, 0), (10, 10)
    assert bbox((2, 8), a, b) and not on_segment((2, 8), a, b)
    # Exact L1 distance to this diagonal: all points (t,t), 2 <= t <= 8,
    # attain |t-2|+|t-8| = 6. The bounding rectangle has distance zero.
    assert min(abs(t-2)+abs(t-8) for t in range(11)) == 6
    assert intersection(a, b, (0, 10), (4, 6)) is None
    crossing = intersection(a, b, (0, 10), (10, 0))
    assert crossing == (5, 5)
    third = ((0,5),(10,5))
    assert intersection(a,b,*third) == intersection((0,10),(10,0),*third) == crossing
    odd = intersection((0, 0), (9, 9), (0, 9), (9, 0))
    assert odd == (Fraction(9, 2), Fraction(9, 2))
    fan = [((-10, -10), (0, 0)), ((0, 0), (10, -10))]
    assert rays((0, 0), fan) == {(-1, -1), (1, -1)}
    # Translated current four-cardinal-bit bbox formula; not a call to Zig.
    legacy_directions = {axis for p in [(-10, -10), (10, -10)]
                         for axis, value in [('left', -p[0]), ('right', p[0]), ('up', -p[1]), ('down', p[1])]
                         if value > 0}
    assert len(legacy_directions) == 3  # already enough to manufacture a dot
    negative = ((0, 9), (9, 0))
    old_midpoint = tuple((negative[0][k] + negative[1][k])//2 for k in (0, 1))
    assert old_midpoint == (4, 4) and not on_segment(old_midpoint, *negative)
    assert on_segment((4, 5), *negative)
    large = ((2**24, 0), (2**24+9, 9))
    rounded = [tuple(int(f32(v)) for v in p) for p in large]
    assert subtract(rounded[1], rounded[0]) == (8, 9)
    assert int(f32(2**31-1)) == 2**31  # outside Pt's i32 result domain
    lo, hi = -2**31, 2**31-1
    determinant = cross((hi-lo, hi-lo), (hi-lo, lo-hi))
    assert abs(determinant) > 2**64
    # Endpoint reversal, translation, transpose, reflection preserve exact contact.
    for transform in (lambda p:p, lambda p:(p[0]+13,p[1]-8),
                      lambda p:(p[1],p[0]), lambda p:(-p[0],p[1])):
        first = tuple(map(transform, (a, b)))
        second = tuple(map(transform, ((0, 10), (10, 0))))
        assert intersection(*first, *second) == transform(crossing)
        assert intersection(*reversed(first), *second) == transform(crossing)
    assert rays((5, 5), [(a,b),(a,b),(b,a)]) == {(-1,-1),(1,1)}
    # Same-net physical parts need an actual endpoint split for this host model.
    other = ((0,10),(10,0))
    unsplit_connected = any(on_segment(p,*other) for p in (a,b)) or any(on_segment(p,a,b) for p in other)
    assert not unsplit_connected
    assert on_segment((5,5), (0,10), (10,0))
    malformed = ['<line data-role="conductor-ink" x1="0" y1="0" x2="1" y2="1"/>',
                 '<path data-role="conductor-ink" d="M 0 0 Q 1 2 3 4"/>',
                 '<path data-role="conductor-ink" d="L 0 0 L 1 1"/>',
                 '<path data-role="conductor-ink" d="M 0 0 L 1"/>']
    for text in malformed:
        try:
            actual_segments(ET.fromstring('<svg>'+text+'</svg>'))
        except AssertionError:
            pass
        else:
            raise AssertionError('unsupported geometry did not decline')
    tiny = ((Decimal(0), Decimal(0)), (Decimal('0.0000004'), Decimal('0.0000004')))
    assert direction(*tiny, False) == 'diagonal:1' and direction(*tiny) == 'zero'
    return dict(scope='Independent exact expectations and translated formulas; no engine or host execution.',
                off_segment_bbox_point=[2,8], bounded_disjoint_crossing=None,
                near_tree=dict(point=[2,8],box_distance=0,actual_L1_distance=6,limit=5,admit=False),
                third_net_at_intended_crossing=dict(point=[5,5],segment=third,policy='initial bounded pair declines'),
                integer_crossing=list(map(str,crossing)), half_grid_crossing=list(map(str,odd)),
                two_diagonal_rays=sorted(rays((0,0),fan)), legacy_cardinal_bits=sorted(legacy_directions),
                negative_diagonal_midpoint=dict(segment=negative,old=old_midpoint,on_wire=False,valid_integer=[4,5]),
                f32_transport=dict(input=large,rounded=rounded,original_delta=[9,9],rounded_delta=[8,9],
                                   i32_max_rounded=int(f32(2**31-1))),
                wide_arithmetic=dict(determinant=determinant,exceeds_signed_i64=True),
                controls=['endpoint_reverse','translation','transpose','reflection','duplicate_ray_union',
                          'host_unsplit_X_is_disconnected','host_split_endpoint_connects',
                          'nonpath_declines','curve_declines','missing_move_declines','missing_coordinate_declines',
                          'normalization_is_not_a_general_geometry_tolerance'])


def views():
    notes = {
        90: 'Source PMOS reciprocal links form a small diagonal X with cardinal terminal stubs. Native preserves the two columns with orthogonal reciprocal paths; geometry capability alone does not force a source-style choice.',
        493: 'Source RC bank uses diagonal capacitor bodies and their diagonal leads, with orthogonal resistor rows. Native uses cardinal capacitor poses and one long interleaved row. A wire-only diagonal capability cannot reproduce the source body orientation or row grouping.',
        1080: 'Source partitions several clocked stages and shows two diagonal cross-coupling X patterns in the bottom latch. Native spreads the devices in broad rows. Stage membership and local pose must precede choosing diagonal interiors.',
        404: 'Source two-stage reciprocal feedback is entirely orthogonal, using an outer bottom return. Native is orthogonal too. Reciprocal topology does not establish a universal diagonal requirement.',
        647: 'Source mixer uses adjacent source pairs, orthogonal crossed drain bars, and a level output capacitor. Native retains adjacent source pairs and orthogonal bars. This is a keep/control for a diagonal option.'}
    records = json.loads((RUN/'diagonal-rendered.json').read_text())
    for row in records:
        assert sha(ROOT/row['path']) == row['sha256']
        assert sha(Path(row['artifact_path'])) == row['artifact_sha256']
        row.update(actual_view=True, observation=notes[int(row['id'][3:])])
    return records


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--check', type=Path)
    args=ap.parse_args()
    files=['include/cktimg.h','src/abi.zig','src/library.zig','src/schematic.zig','src/canvas.zig',
           'src/maze.zig','src/thin.zig','src/dots.zig','src/placed.zig','src/checks.zig',
           'src/report.zig','src/trunk.zig','src/wire_parts.zig','src/wires.zig','src/routes.zig','src/netlines.zig',
           'tests/abi_test.c','tools/schemify/layout.zig','tools/schemify/emit.zig',
           '../../Schemify/crates/model/elab/src/connect.rs','../../Schemify/crates/model/elab/src/nets.rs',
           '../../Schemify/crates/model/elab/tests/connectivity.rs','../../Schemify/crates/model/doc/src/record.rs']
    result=dict(scope=__doc__,script_sha256=sha(Path(__file__)),implementation_sha256={f:sha(ROOT/f) for f in files},
                census=census(),literals=literals(),actual_views=views(),
                unexecuted=['Zig production literals','allocator failure injection','C ABI capability negotiation',
                            'plugin import/export','host connectivity execution','SPICE round trip'])
    result=json.loads(json.dumps(result))
    if args.check:
        assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
    print(json.dumps({k:result['census'][k] for k in ['totals','tagged_paths','maximum_delta_residue',
                     'minimum_normalized_nonzero_chebyshev_span','unique_diagonal_segments','geometric_collinear_unions']}))


if __name__=='__main__':
    main()
