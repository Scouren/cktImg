#!/usr/bin/env python3
"""Independent observed-curve distance intervals, separate from table generation.

De Casteljau chord capsules bound source flattening. Sampling the two complete
polyline traces uses the distance function's unit Lipschitz constant, so the
reported upper bound covers points between samples, not just table vertices.
This measures centerlines; raster stroke width is outside this certificate.
"""
import functools
import math
import re

SOURCE_ERROR = 0.002
SAMPLE_STEP = 0.04


def distance(point, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    norm = dx*dx+dy*dy
    t = max(0, min(1, ((point[0]-a[0])*dx+(point[1]-a[1])*dy)/norm)) if norm else 0
    return math.hypot(point[0]-a[0]-t*dx, point[1]-a[1]-t*dy)


def middle(a, b):
    return tuple((x+y)/2 for x, y in zip(a, b))


def flatten(control, depth=0):
    if depth > 24:
        raise ValueError('source cubic did not reach the named flattening bound')
    if max(distance(p, control[0], control[-1]) for p in control[1:-1]) <= SOURCE_ERROR:
        return [control[-1]]
    a, b, c = [middle(p, q) for p, q in zip(control, control[1:])]
    d, e = middle(a, b), middle(b, c)
    f = middle(d, e)
    return flatten((control[0], a, d, f), depth+1)+flatten((f, e, c, control[-1]), depth+1)


def source_trace(path):
    tokens = re.findall(r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?', path)
    points, i = [], 0
    while i < len(tokens):
        command = tokens[i]
        i += 1
        if command not in ('M', 'L', 'C') or (command == 'M' and points):
            raise ValueError('unsupported or disconnected source curve')
        size = 6 if command == 'C' else 2
        values = list(map(float, tokens[i:i+size]))
        if len(values) != size:
            raise ValueError('incomplete source command')
        i += size
        ps = list(zip(values[::2], values[1::2]))
        if command == 'C':
            points.extend(flatten((points[-1], *ps)))
        else:
            points.extend(ps)
    return points


def directed(first, second):
    maximum, gap, samples = 0.0, 0.0, 0
    edges = list(zip(second, second[1:]))
    for a, b in zip(first, first[1:]):
        length = math.dist(a, b)
        steps = max(1, math.ceil(length/SAMPLE_STEP))
        gap = max(gap, length/steps)
        for i in range(steps+1):
            p = tuple(x+(y-x)*i/steps for x, y in zip(a, b))
            maximum = max(maximum, min(distance(p, u, v) for u, v in edges))
            samples += 1
    # Every point lies within half a sample interval of a measured point.
    return dict(lower=max(0, maximum-SOURCE_ERROR), upper=maximum+gap/2+SOURCE_ERROR,
                samples=samples, sample_gap=gap)


@functools.lru_cache(maxsize=32)
def measure(path, native):
    original = source_trace(path)
    if len(native) < 2:
        raise ValueError('missing native winding')
    a, b = directed(native, original), directed(original, native)
    return dict(native_to_source=a, source_to_native=b,
                lower=max(a['lower'], b['lower']), upper=max(a['upper'], b['upper']),
                source_flattening_bound=SOURCE_ERROR, requested_sample_step=SAMPLE_STEP,
                source_chord_vertices=len(original))


def methods():
    if distance((1, 2), (0, 0), (2, 0)) != 2 or distance((3, 4), (0, 0), (0, 0)) != 5:
        raise ValueError('literal segment distance oracle failed')
    a = measure('M 0 0 L 4 0', ((0, 0), (4, 0)))
    b = measure('M 0 0 L 4 0', ((0, 2), (4, 2)))
    if not (a['lower'] == 0 and a['upper'] < .03 and b['lower'] < 2 < b['upper']):
        raise ValueError('literal parallel-trace distance interval failed')
    c = measure('M 0 0 C 0 4 4 4 4 0', ((0, 0), (4, 0)))
    if not c['lower'] < 3 < c['upper']:
        raise ValueError('interior cubic maximum escaped endpoint-independent measurement')
    return ['literal_point_segment_distance', 'identical_trace_interval',
            'parallel_trace_distance_interval', 'cubic_interior_peak_not_endpoints']
