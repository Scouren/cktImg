#!/usr/bin/env python3
"""Reciprocal transistor capacitors: topology selection, actual SVG evidence.

Usage: cross_caps.py <examples-dir> <output.json> [--native <json-dir>]

The proposed cohort has two same-polarity MOS/BJT devices, four distinct
nonrail D/C and G/B nets, one capacitor from each D/C to the other G/B,
and exactly one DC path at each control: resistors to one third bias net.
Selection never reads geometry. The broad reciprocal cohort is retained as
named counterexamples. This is research, not an implemented placement rule.

Actual SVG lead endpoints verify the cached terminal coordinates. Actual
conductor ink verifies every studied wire segment before the human wire
pieces are used to find capacitor-to-opposite-control paths. Disconnected
pieces of one named net are retained: a label is not a continuous wire.
Unknown cards, missing glyphs, unmatched terminals and unsupported ink fail.
The numeric-ID split has no selected holdout here; these examples do not
constitute independent validation of a general rule.
"""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

from channel_bridges import read_cards, rail
from converter_terminals import NUMBER, apply, close, transformed_elements


def reciprocal(cards, model_types):
    """One electrical certificate per unordered transistor pair; no coordinates."""
    transistors = {n: w for n, w in cards.items() if n[0] in "mq"}
    caps = {n: w for n, w in cards.items() if n[0] == "c"}
    dc = collections.defaultdict(set)
    for name, words in cards.items():
        if name[0] not in "rlviefhgdwsqjzm":
            continue
        for net in (words[1], words[3] if name[0] in "qjzm" else words[2]):
            dc[net].add(name)
    for a, wa in sorted(transistors.items()):
        for b, wb in sorted(transistors.items()):
            if a >= b or model_types[a] != model_types[b]:
                continue
            if len(set(wa[1:4])) != 3 or len(set(wb[1:4])) != 3:
                continue
            ends = {wa[1], wb[1], wa[2], wb[2]}
            if len(ends) != 4 or any(rail(net) for net in ends):
                continue
            pair = [[n for n, w in caps.items() if set(w[1:3]) == {own[1], other[2]}]
                    for own, other in ((wa, wb), (wb, wa))]
            if any(len(matches) != 1 for matches in pair):
                continue
            resistors, biases = [], []
            for gate in (wa[2], wb[2]):
                if len(dc[gate]) != 1:
                    continue
                resistor = next(iter(dc[gate]))
                if resistor[0] != "r":
                    continue
                words = cards[resistor]
                resistors.append(resistor)
                biases.append(words[2] if words[1] == gate else words[1])
            admitted = len(biases) == 2 and biases[0] == biases[1] and biases[0] not in ends
            yield dict(transistors=[a, b], caps=[p[0] for p in pair],
                       bias_resistors=resistors, bias=biases[0] if admitted else None,
                       admitted=admitted)


def actual_glyph(root, device):
    """Associate by type/origin, then require every studied pin at an ink endpoint."""
    matches = []
    for element, matrix in transformed_elements(root):
        if element.get("data-symbol-id") != device["type"]:
            continue
        children = list(element)
        if len(children) != 1:
            raise ValueError("unexpected primitive container")
        first = next(transformed_elements(children[0], matrix))[1]
        if not close(apply(first, [0, 0]), [device["x"], device["y"]]):
            continue
        endpoints = []
        for child, local in transformed_elements(children[0], matrix):
            tag = child.tag.rsplit("}", 1)[-1]
            if tag == "line":
                endpoints.extend(apply(local, [float(child.get(x)), float(child.get(y))])
                                 for x, y in (("x1", "y1"), ("x2", "y2")))
            elif tag == "polyline":
                values = [float(x) for x in re.findall(NUMBER, child.get("points", ""))]
                if len(values) < 4 or len(values) % 2:
                    raise ValueError("malformed SVG lead polyline")
                endpoints.extend((apply(local, values[:2]), apply(local, values[-2:])))
        pins = ("D", "G", "S") if device["card"][0] == "m" else ("C", "B", "E") if device["card"][0] == "q" else tuple(device["terminals"])
        actual = {}
        for pin in pins:
            found = [point for point in endpoints if close(point, device["terminals"][pin])]
            if not found:
                raise ValueError("cached terminal has no actual lead: " + device["card"] + ":" + pin)
            # Quarter-turn trigonometry leaves sub-micro-unit residue.
            actual[pin] = [round(value, 6) for value in found[0]]
        matches.append(dict(object=element.get("data-object-id"), terminals=actual))
    if len(matches) != 1:
        raise ValueError("missing or ambiguous primitive: " + device["card"])
    return matches[0]


def conductor_ink(root):
    segments = []
    for element, matrix in transformed_elements(root):
        if element.get("data-role") != "conductor-ink":
            continue
        text = element.get("d", "")
        tokens = re.findall(r"[A-Za-z]|" + NUMBER, text)
        if re.sub(r"[ML]|" + NUMBER + r"|[\s,]", "", text):
            raise ValueError("unsupported conductor path")
        point = None
        for offset in range(0, len(tokens), 3):
            command, x, y = tokens[offset:offset + 3]
            following = apply(matrix, [float(x), float(y)])
            if command == "L":
                if point is None:
                    raise ValueError("line before move in conductor path")
                segments.append([point, following])
            elif command != "M":
                raise ValueError("unsupported conductor command")
            point = following
    return segments


def feedback_path(human, devices, cap, transistor, ink):
    control = "G" if transistor[0] == "m" else "B"
    target = devices[transistor]["terminals"][control]
    net = devices[transistor]["nets"][control]
    source = next(point for pin, point in devices[cap]["terminals"].items()
                  if devices[cap]["nets"][pin] == net)
    segments = [segment for wire in human["wires"] if wire["net"] == net for segment in wire["segments"]]
    for a, b in segments:
        if not any((close(a, c) and close(b, d)) or (close(a, d) and close(b, c)) for c, d in ink):
            raise ValueError(f"wire cache disagrees with actual ink: {human['id']}:{net}:{a}:{b}")
    graph = collections.defaultdict(list)
    for a, b in segments:
        graph[tuple(a)].append(tuple(b)); graph[tuple(b)].append(tuple(a))
    queue = collections.deque([(tuple(source), [])]); seen = {tuple(source)}
    path = None
    while queue:
        point, steps = queue.popleft()
        if point == tuple(target):
            path = steps; break
        for following in graph[point]:
            if following not in seen:
                seen.add(following); queue.append((following, steps + [[point, following]]))
    piece = [segment for segment in segments if tuple(segment[0]) in seen and tuple(segment[1]) in seen]
    return dict(net=net, cap=cap, transistor=transistor, start=source, target=target,
                diagonal_segments=sum(a[0] != b[0] and a[1] != b[1] for a, b in (path if path is not None else piece)),
                capacitor_piece_segments=piece if path is None else None,
                continuous=path is not None, path=path,
                capacitor_piece=sorted(seen) if path is None else None,
                verified_ink_segments=segments)


def relations(points):
    caps, drains, gates = points
    cx = [sum(p[0] for p in pair) / 2 for pair in caps]
    cy = [sum(p[1] for p in pair) / 2 for pair in caps]
    lo, hi = sorted(p[0] for p in drains)
    return dict(horizontal=sum(pair[0][1] == pair[1][1] for pair in caps),
                same_row=cy[0] == cy[1], above_drains=max(cy) < min(p[1] for p in drains),
                inside_columns=all(lo < x < hi for x in cx),
                near_own_drain=all(abs(cx[i]-drains[i][0]) < abs(cx[i]-drains[1-i][0]) for i in (0, 1)),
                gates_inward=sum((gates[i][0]-drains[i][0])*(drains[1-i][0]-drains[i][0]) > 0 for i in (0, 1)))


def crossings(first, second):
    """Strict interior intersections, so an endpoint/junction is never a crossing."""
    points = set()
    for a, b in first:
        for c, d in second:
            u = (b[0]-a[0], b[1]-a[1]); v = (d[0]-c[0], d[1]-c[1])
            den = u[0]*v[1]-u[1]*v[0]
            if den == 0:
                continue
            w = (c[0]-a[0], c[1]-a[1])
            t = (w[0]*v[1]-w[1]*v[0])/den; q = (w[0]*u[1]-w[1]*u[0])/den
            if 0 < t < 1 and 0 < q < 1:
                points.add((round(a[0]+t*u[0], 6), round(a[1]+t*u[1], 6)))
    return sorted(points)


def study(examples, native):
    rows, digest, native_hashes = [], hashlib.sha256(), {}
    paths = sorted(examples.glob("*.human.json"))
    if not paths:
        raise ValueError("no paired human drawings")
    for path in paths:
        identifier = path.name.removesuffix(".human.json")
        deck, svg = [path.with_name(identifier + suffix) for suffix in (".cir", ".svg")]
        human = json.loads(path.read_text()); devices = {d["card"]: d for d in human["devices"]}
        text = deck.read_text(); cards = read_cards(text)
        models = {w[1]: w[2] for line in text.lower().splitlines()
                  if (w := line.split()) and w[0] == ".model"}
        model_types = {}
        for name, words in cards.items():
            if name[0] not in "mq":
                continue
            model = words[5] if name[0] == "m" else next((w for w in words[4:] if w in models), None)
            if model not in models or models[model] != devices[name]["type"]:
                raise ValueError("missing model or deck/drawing polarity disagreement")
            model_types[name] = models[model]
        certificates = list(reciprocal(cards, model_types))
        if certificates:
            root = ET.parse(svg).getroot(); ink = conductor_ink(root)
            generated = {}
            if native:
                filename = native / (identifier + ".json")
                native_hashes[filename.name] = hashlib.sha256(filename.read_bytes()).hexdigest()
                generated = {d["name"].lower(): d for d in json.loads(filename.read_text())["devices"]}
            for row in certificates:
                names = row["caps"] + row["transistors"]
                glyphs = {name: actual_glyph(root, devices[name]) for name in names}
                caps = [list(glyphs[n]["terminals"].values()) for n in row["caps"]]
                drains = [glyphs[n]["terminals"]["D" if n[0] == "m" else "C"] for n in row["transistors"]]
                gates = [glyphs[n]["terminals"]["G" if n[0] == "m" else "B"] for n in row["transistors"]]
                native_relations = None
                if native:
                    pins = {n: {p["term"].lower(): p["xy"] for p in generated[n]["pins"]} for n in names}
                    nc = [list(pins[n].values())[:2] for n in row["caps"]]
                    nd = [pins[n]["d" if n[0] == "m" else "c"] for n in row["transistors"]]
                    ng = [pins[n]["g" if n[0] == "m" else "b"] for n in row["transistors"]]
                    native_relations = relations((nc, nd, ng))
                row.update(id=identifier, split="holdout" if int(identifier.rsplit("-", 1)[1]) % 5 == 0 else "discovery",
                    source=relations((caps, drains, gates)), source_glyphs=glyphs, native=native_relations,
                    feedback=[feedback_path(human, devices, cap, opposite, ink)
                              for cap, opposite in zip(row["caps"], reversed(row["transistors"]))],
                    source_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (path, deck, svg)})
                feedback = [p["path"] if p["continuous"] else p["capacitor_piece_segments"] for p in row["feedback"]]
                row["source_feedback_crossings"] = crossings(*feedback)
                rows.append(row)
        for source in (path, deck, svg):
            data = source.read_bytes(); name = source.name.encode()
            digest.update(len(name).to_bytes(8, "big") + name + len(data).to_bytes(8, "big") + data)
    selected = [r for r in rows if r["admitted"]]
    fields = ("horizontal", "same_row", "above_drains", "inside_columns", "near_own_drain", "gates_inward")
    return dict(drawings=len(paths), corpus_sha256=digest.hexdigest(),
        dependencies_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
                             (Path(__file__), Path(__file__).with_name("channel_bridges.py"), Path(__file__).with_name("converter_terminals.py"))},
        native_sha256=native_hashes,
        native_binary_sha256=hashlib.sha256((native / "cktimg-json").read_bytes()).hexdigest() if native and (native / "cktimg-json").exists() else None,
        selected=selected, excluded=[r for r in rows if not r["admitted"]],
        selected_names=sorted(r["id"]+":"+n for r in selected for n in r["caps"]),
        summary=dict(pairs=len(selected), circuits=len({r["id"] for r in selected}),
                     source={f: sum(r["source"][f] for r in selected) for f in fields},
                     native={f: sum(r["native"][f] for r in selected) for f in fields} if native else None,
                     continuous_feedback=sum(p["continuous"] for r in selected for p in r["feedback"]),
                     diagonal_feedback=sum(p["diagonal_segments"] > 0 for r in selected for p in r["feedback"]),
                     one_crossing_pairs=sum(len(r["source_feedback_crossings"]) == 1 for r in selected),
                     holdout_pairs=sum(r["split"] == "holdout" for r in selected)))


if __name__ == "__main__":
    assert crossings([[[0, 0], [4, 4]]], [[[0, 4], [4, 0]]]) == [(2.0, 2.0)]
    assert crossings([[[0, 0], [4, 4]]], [[[4, 4], [4, 0]]]) == []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path); parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path)
    args = parser.parse_args()
    result = study(args.examples, args.native)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result["summary"], indent=2))
