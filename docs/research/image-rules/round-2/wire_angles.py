#!/usr/bin/env python3
"""Actual source conductor directions, excluding symbol bodies and metadata wires.

This census is geometric evidence, not net identity, route ownership, an image
view, or proof that every conductor ought to be diagonal. Quarter-turn floating
residue is rounded to six decimal places solely when comparing directions.
"""

import argparse
import collections
import json
from fractions import Fraction
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

from quad_equivalence import sha, dependencies

HERE = Path(__file__).resolve().parent
FIGURES = HERE.parent.parent / "figures"
sys.path.insert(0, str(FIGURES))
from cross_caps import conductor_ink


def direction(a, b):
    dx = Fraction(str(round(b[0] - a[0], 6)))
    dy = Fraction(str(round(b[1] - a[1], 6)))
    if dx == dy == 0:
        return "zero"
    if not dx:
        return "vertical"
    if not dy:
        return "horizontal"
    return "diagonal:" + str(abs(dy / dx))


def controls():
    literals = [([0, 0], [10, 10], "diagonal:1"),
                ([0, 10], [10, 0], "diagonal:1"),
                ([1, 2], [7, 5], "diagonal:1/2"),
                ([1, 2], [4, 8], "diagonal:2"),
                ([2, 2], [2, 7], "vertical"),
                ([2, 7], [8, 7], "horizontal"),
                ([2, 7], [2, 7], "zero")]
    for a, b, expected in literals:
        assert direction(a, b) == direction(b, a) == expected
    root = ET.fromstring('<svg><path d="M 0 0 L 5 8"/>'
                         '<g transform="translate(3 4)"><path data-role="conductor-ink" '
                         'd="M 0 0 L 10 10 L 10 20"/></g></svg>')
    assert conductor_ink(root) == [[[3, 4], [13, 14]], [[13, 14], [13, 24]]]
    return ["literal_angles_and_reversed_endpoints", "actual_conductor_only", "transform_retained"]


def collect():
    manifest = json.loads((HERE / "manifest.json").read_text())
    inventory = Path(manifest["prior_audit"]) / "all-images.json"
    assert sha(inventory) == manifest["frozen_inventory_sha256"]
    records, totals = [], collections.Counter()
    for item in json.loads(inventory.read_text()):
        path = Path(item["source_svg"])
        assert sha(path) == item["source_svg_sha256"]
        segments = conductor_ink(ET.parse(path).getroot())
        counts = collections.Counter(direction(a, b) for a, b in segments)
        totals.update(counts)
        records.append(dict(id=item["id"], source_svg_sha256=sha(path),
                            counts=dict(sorted(counts.items())),
                            diagonals=[dict(segment=s, direction=direction(*s)) for s in segments
                                       if direction(*s).startswith("diagonal:")]))
    deps = dependencies()
    deps[str(Path(__file__).relative_to(HERE.parents[3]))] = sha(Path(__file__))
    return dict(scope=__doc__, dependencies=deps, inventory_sha256=sha(inventory),
                controls=controls(), totals=dict(sorted(totals.items())), records=records)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    result = collect()
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(dict(totals=result["totals"],
                          diagonal_names=[r["id"] for r in result["records"] if r["diagonals"]],
                          non45_names=[r["id"] for r in result["records"]
                                       if any(d["direction"] != "diagonal:1" for d in r["diagonals"])])))


if __name__ == "__main__":
    main()
