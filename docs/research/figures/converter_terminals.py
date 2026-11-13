#!/usr/bin/env python3
"""Verify converter terminal caches against actual builtin SVG lead strokes.

Usage: converter_terminals.py <examples-dir> <output.json> [--native <json-dir>]

The existing topology study selects grounded shunts, their main MOS/coil
neighbors, and grounded capacitors on the main switches' outer endpoints.
Only then are cached terminal coordinates compared with transformed SVG
line/polyline endpoints, or the first/last endpoints of an inductor path.
Opaque block geometry is deliberately outside this audit: its cached ports
can differ from its rendered custom glyph. Missing or ambiguous symbols and
unsupported SVG transforms fail; an unmatched terminal fails after writing
the named evidence. Counts never substitute for the exact device inventory.
"""

import argparse
import collections
import hashlib
import json
import math
import re
from pathlib import Path
from xml.etree import ElementTree

import power_paths as power


IDENTITY = (1, 0, 0, 1, 0, 0)
NUMBER = r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"
BUILTINS = {"nmos", "pmos", "capacitor", "inductor", "inductor-compact"}
TOLERANCE = 1e-5  # Arithmetic error from quarter-turn sine/cosine, not layout slack.


def multiply(a, b):
    return (a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
            a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
            a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5])


def transform(text):
    matrix = IDENTITY
    operations = re.findall(r"(\w+)\(([^)]*)\)", text)
    if re.sub(r"\w+\([^)]*\)", "", text).strip():
        raise ValueError(f"unsupported SVG transform: {text}")
    for name, arguments in operations:
        values = [float(x) for x in re.findall(NUMBER, arguments)]
        if name == "translate" and len(values) in (1, 2):
            operation = (1, 0, 0, 1, values[0], values[1] if len(values) == 2 else 0)
        elif name == "scale" and len(values) in (1, 2):
            operation = (values[0], 0, 0, values[-1], 0, 0)
        elif name == "rotate" and len(values) in (1, 3):
            c, s = math.cos(math.radians(values[0])), math.sin(math.radians(values[0]))
            operation = (c, s, -s, c, 0, 0)
            if len(values) == 3:
                x, y = values[1:]
                operation = multiply(multiply((1, 0, 0, 1, x, y), operation), (1, 0, 0, 1, -x, -y))
        elif name == "matrix" and len(values) == 6:
            operation = tuple(values)
        else:
            raise ValueError(f"unsupported SVG transform: {text}")
        matrix = multiply(matrix, operation)
    return matrix


def apply(matrix, point):
    a, b, c, d, x, y = matrix
    return [a * point[0] + c * point[1] + x, b * point[0] + d * point[1] + y]


def close(a, b):
    return all(abs(x - y) <= TOLERANCE for x, y in zip(a, b))


def capacitor_geometry(signal, ground, main, coil):
    return dict(signal_xy=signal, ground_xy=ground, main_xy=main, coil_xy=coil,
                outside=(signal[0] - main[0]) * (main[0] - coil[0]) > 0,
                at_or_below=signal[1] >= main[1], vertical=signal[0] == ground[0],
                ground_below=ground[1] > signal[1])


def transformed_elements(element, parent=IDENTITY):
    matrix = multiply(parent, transform(element.get("transform", "")))
    yield element, matrix
    for child in element:
        yield from transformed_elements(child, matrix)


def glyphs(root):
    for element, matrix in transformed_elements(root):
        kind = element.get("data-symbol-id")
        if kind not in BUILTINS:
            continue
        children = list(element)
        if len(children) != 1:
            raise ValueError(f"unexpected builtin SVG container: {element.attrib}")
        origin = apply(multiply(matrix, transform(children[0].get("transform", ""))), [0, 0])
        points = []
        for child, local in transformed_elements(children[0], matrix):
            tag = child.tag.rsplit("}", 1)[-1]
            if tag == "polyline":
                values = [float(x) for x in re.findall(NUMBER, child.get("points", ""))]
                if len(values) < 4 or len(values) % 2:
                    raise ValueError(f"malformed SVG polyline: {child.attrib}")
                points.extend((apply(local, values[:2]), apply(local, values[-2:])))
            elif tag == "line":
                points.extend(apply(local, [float(child.get(x)), float(child.get(y))])
                              for x, y in (("x1", "y1"), ("x2", "y2")))
            elif tag == "path" and kind.startswith("inductor"):
                path = child.get("d", "")
                first = re.search(rf"^M\s*({NUMBER})\s+({NUMBER})", path)
                last = re.search(rf"L\s*({NUMBER})\s+({NUMBER})\s*$", path)
                if not first or not last:
                    raise ValueError(f"unsupported inductor SVG path: {path}")
                points.extend(apply(local, list(map(float, match.groups()))) for match in (first, last))
        yield dict(type=kind, origin=origin, endpoints=points, object=element.get("data-object-id"))


def capacitors(human, drawn, selected, group, cards):
    """Grounded capacitors at outer main-channel nets; selection uses only cards."""
    coil = group["coil"]
    coil_ends = cards[coil][1:3]
    rows = []
    for names, near in zip(group["endpoint_switches"], coil_ends):
        main = names[0]
        a, gate, b, _ = selected[main]["nets"]
        outer = b if a == near else a
        matches = []
        for name, words in cards.items():
            if name[0] != "c" or outer not in words[1:3]:
                continue
            other = words[2] if words[1] == outer else words[1]
            if other not in (outer, gate, near) and power.MOS.rail(other) == "sink":
                matches.append((name, other))
        for name, ground in matches:
            signal_xy = power.path_pin(drawn[name], outer)
            ground_xy = power.path_pin(drawn[name], ground)
            main_xy = power.path_pin(drawn[main], outer)
            coil_xy = power.path_pin(drawn[coil], near)
            rows.append(dict(id=human["id"], card=name, main=main, coil=coil,
                             outer_net=outer, near_net=near, ground_net=ground, endpoint_candidates=len(matches),
                             **capacitor_geometry(signal_xy, ground_xy, main_xy, coil_xy)))
    return rows


def verify(human, drawn, targets, symbols):
    rows = []
    for card, cohorts in sorted(targets.items()):
        device = drawn[card]
        matches = [symbol for symbol in symbols if symbol["type"] == device["type"] and
                   close(symbol["origin"], [device["x"], device["y"]])]
        if len(matches) != 1:
            raise ValueError(f"{human['id']}:{card}: expected one SVG glyph, found {len(matches)}")
        symbol = matches[0]
        pins = ("D", "S") if device["type"] in ("nmos", "pmos") else tuple(device["terminals"])
        terminals = {pin: device["terminals"][pin] for pin in pins}
        matched = [pin for pin, point in terminals.items() if any(close(point, end) for end in symbol["endpoints"])]
        rows.append(dict(name=human["id"] + ":" + card, svg_object=symbol["object"],
                         cohorts=sorted(cohorts), terminals=terminals, matched_terminals=matched,
                         verified=sorted(matched) == sorted(terminals)))
    return rows


def native_capacitors(directory, caps):
    drawings, hashes, rows = {}, {}, []
    for row in caps:
        name = row["id"]
        if name not in drawings:
            path = directory / (name + ".json")
            hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
            drawings[name] = {d["name"]: d for d in json.loads(path.read_text())["devices"]}
        devices = drawings[name]
        points = [power.path_pin(devices[card], net, True) for card, net in
                  ((row["card"], row["outer_net"]), (row["card"], row["ground_net"]),
                   (row["main"], row["outer_net"]), (row["coil"], row["near_net"]))]
        rows.append(dict(id=name, card=row["card"], **capacitor_geometry(*points)))
    return dict(input_sha256=hashes, rows=rows,
                summary={key: sum(row[key] for row in rows)
                         for key in ("outside", "at_or_below", "vertical", "ground_below")})


def main():
    # Literal transformed endpoints check SVG order, reflection and tolerance.
    assert close(apply(transform("translate(170 110) rotate(270)"), [10, 20]), [190, 100])
    assert close(apply(transform("translate(550 110) scale(-1 1) rotate(270)"), [10, 20]), [530, 100])
    assert not close([1, 2], [1, 2.001])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path, help="Compare the same named capacitor terminals in retained native JSON")
    args = parser.parse_args()
    paths = sorted(args.examples.glob("*.human.json"))
    if not paths:
        parser.error("no *.human.json files")
    rows, caps, hashes = [], [], {}
    for path in paths:
        human = json.loads(path.read_text())
        deck = path.with_name(human["id"] + ".cir")
        text = deck.read_text()
        selected, coils = power.classify(text)
        if not coils:
            continue
        svg = path.with_name(human["id"] + ".svg")
        hashes.update((source.name, hashlib.sha256(source.read_bytes()).hexdigest()) for source in (path, deck, svg))
        drawn = {device["card"]: device for device in human["devices"]}
        targets = collections.defaultdict(set)
        cards = power.MOS.read_cards(text)
        for coil, pair in coils.items():
            group = power.chain(human, drawn, selected, coil, pair)
            if group["ambiguous"]:
                raise ValueError(f"{human['id']}:{coil}: ambiguous converter path")
            shunts = power.controls(human, drawn, selected, [], pair, group)[2]
            for shunt in shunts:
                for card in (shunt["card"], shunt["main"], coil):
                    targets[card].add("shunt_path")
            observed = capacitors(human, drawn, selected, group, cards)
            for cap in observed:
                targets[cap["card"]].add("ground_capacitor")
                neighbors = [row for row in shunts if row["endpoint_net"] == cap["near_net"]]
                if len(neighbors) == 1:
                    shunt_y = neighbors[0]["interval"]["shunt_xy"][1]
                    cap["shunt_row_relation"] = ("above" if cap["signal_xy"][1] < shunt_y else
                                                 "below" if cap["signal_xy"][1] > shunt_y else "level")
            caps.extend(observed)
        rows.extend(verify(human, drawn, targets, list(glyphs(ElementTree.parse(svg).getroot()))))
    expected = [row["name"] for row in rows]
    verified = [row["name"] for row in rows if row["verified"]]
    if len(set(expected)) != len(expected):
        raise ValueError("duplicate selected device names")
    cohorts = {}
    for cohort in ("shunt_path", "ground_capacitor"):
        selected = [row for row in rows if cohort in row["cohorts"]]
        cohorts[cohort] = dict(devices=len(selected), terminals=sum(len(row["terminals"]) for row in selected),
                               names=[row["name"] for row in selected],
                               verified_names=[row["name"] for row in selected if row["verified"]])
    result = dict(source_sha256=hashes, tolerance=TOLERANCE, expected_names=expected,
                  verified_names=verified, cohorts=cohorts, terminals=rows, ground_capacitors=caps,
                  capacitor_summary=dict(devices=len(caps), circuits=len({r["id"] for r in caps}),
                      **{key: sum(r[key] for r in caps) for key in ("outside", "at_or_below", "vertical", "ground_below")},
                      ambiguous=[r for r in caps if r["endpoint_candidates"] != 1],
                      shunt_row_relation=dict(collections.Counter(r["shunt_row_relation"] for r in caps if "shunt_row_relation" in r))))
    if args.native:
        result["native_capacitors"] = native_capacitors(args.native, caps)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(cohorts={k: {field: value for field, value in v.items() if not field.endswith("names")}
                                  for k, v in cohorts.items()}, capacitors=result["capacitor_summary"]), indent=2))
    if verified != expected:
        raise ValueError(f"unmatched SVG lead terminals: {sorted(set(expected) - set(verified))}")


if __name__ == "__main__":
    main()
