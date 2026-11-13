#!/usr/bin/env python3
"""Grounded voltage-source input resistors: topology and actual lead evidence.

Usage: input_resistors.py <examples-dir> <output.json> [--native <json-dir>]

A resistor joins a distinct nonrail MOS gate to a private source junction.
Exactly the resistor and one independent voltage source have pins on that
junction; the source's other terminal is ground. D/G/S of the driven MOS
are distinct. Model type distinguishes a MOS from the BJT counterexample.
No value, device label or input-net spelling selects a resistor. Broader
private source/resistor branches are retained as named boundary cases.
"""
import argparse
import collections
import hashlib
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

from channel_bridges import read_cards, rail
from cross_caps import actual_glyph
from converter_terminals import NUMBER, apply, close, transformed_elements
from sampling_cells import pin, channel



def actual_resistor(root, device):
    """Read both outer endpoints of the actual transformed zigzag path."""
    matches = []
    for element, matrix in transformed_elements(root):
        if element.get("data-symbol-id") != device["type"]:
            continue
        children = list(element)
        if len(children) != 1:
            raise ValueError("unexpected resistor primitive container")
        local = next(transformed_elements(children[0], matrix))[1]
        if not close(apply(local, [0, 0]), [device["x"], device["y"]]):
            continue
        endpoints = []
        for child, local in transformed_elements(children[0], matrix):
            if child.tag.rsplit("}", 1)[-1] != "path":
                continue
            path = child.get("d", "")
            if re.sub(r"[ML]|" + NUMBER + r"|[\s,]", "", path):
                raise ValueError("unsupported resistor SVG path")
            tokens = re.findall(r"[A-Za-z]|" + NUMBER, path)
            if len(tokens) < 6 or len(tokens) % 3 or tokens[0] != "M" or any(tokens[i] != "L" for i in range(3, len(tokens), 3)):
                raise ValueError("malformed resistor SVG path")
            endpoints.extend(apply(local, list(map(float, pair))) for pair in (tokens[1:3], tokens[-2:]))
        actual = {}
        for terminal, cached in device["terminals"].items():
            found = [point for point in endpoints if close(point, cached)]
            if not found:
                raise ValueError("cached resistor terminal has no actual lead: " + terminal)
            actual[terminal] = [round(value, 6) for value in found[0]]
        matches.append(dict(object=element.get("data-object-id"), terminals=actual))
    if len(matches) != 1:
        raise ValueError("missing or ambiguous resistor primitive")
    return matches[0]


def actual(root, device):
    return actual_resistor(root, device) if device["card"][0] == "r" else actual_glyph(root, device)


def nodes(cards, text):
    models, ports = {}, {}
    for line in text.lower().splitlines():
        w = line.split()
        if not w:
            continue
        if w[0] == ".model":
            models[w[1]] = w[2]
        if w[0] == ".subckt":
            ports[w[1]] = []
            for token in w[2:]:
                if token == "params:" or "=" in token:
                    break
                ports[w[1]].append(token)
    result = {}
    for name, w in cards.items():
        k = name[0]
        if k == "k":
            result[name] = []
        elif k == "x":
            found = [i for i, word in enumerate(w[1:], 1) if word in ports and i == len(ports[word]) + 1]
            if len(found) != 1:
                raise ValueError("ambiguous X pin count: " + name)
            result[name] = w[1:found[0]]
        elif k in "qd":
            found = [i for i, word in enumerate(w) if word in models and i in ((4, 5) if k == "q" else (3, 4))]
            if len(found) != 1:
                raise ValueError("ambiguous model/pin count: " + name)
            result[name] = w[1:found[0]]
        else:
            count = 4 if k in "megsto" else 3 if k in "jzu" else 2
            result[name] = w[1:count + 1]
    return result, models


def select(text):
    cards = read_cards(text)
    pins, models = nodes(cards, text)
    incident = collections.defaultdict(set)
    for name, ends in pins.items():
        for net in ends:
            incident[net].add(name)
    rows = []
    for name, w in sorted(cards.items()):
        if name[0] != "r" or w[1] == w[2]:
            continue
        for junction, gate in (w[1:3], w[1:3][::-1]):
            if rail(junction) or rail(gate) or len(incident[junction]) != 2:
                continue
            other = next(n for n in incident[junction] if n != name)
            if other[0] != "v":
                continue
            v = cards[other]
            ground = v[2] if v[1] == junction else v[1]
            if rail(ground) != "sink":
                continue
            mos, bjt = [], []
            for target in sorted(incident[gate]):
                t = cards[target]
                if target[0] not in "mq" or t[2] != gate or len(set(t[1:4])) != 3:
                    continue
                if target[0] == "m":
                    if models.get(t[5]) not in ("nmos", "pmos"):
                        raise ValueError("unknown MOS model")
                    mos.append(target)
                else:
                    bjt.append(target)
            rows.append(dict(card=name, source=other, junction=junction, gate_net=gate, ground=ground,
                             mos=mos, bjt=bjt, admitted=bool(mos)))
    return cards, rows


def geometry(row, devices, native=False):
    r, v = devices[row["card"]], devices[row["source"]]
    a, b = [pin(r, n, native) for n in (row["junction"], row["gate_net"])]
    vs, ground = [pin(v, n, native) for n in (row["junction"], row["ground"])]
    targets = [channel(devices[n], native)[2] for n in row["mos"]]
    rx = (a[0] + b[0]) / 2
    return dict(resistor_horizontal=a[1] == b[1], source_vertical=vs[0] == ground[0],
                source_ground_below=ground[1] > vs[1],
                resistor_at_gate_level=any(g[1] == b[1] == a[1] for g in targets),
                resistor_between_source_and_gate=any(min(vs[0], g[0]) < rx < max(vs[0], g[0]) for g in targets),
                source_signal_at_or_below_resistor=vs[1] >= a[1])


def initial_form(cards, row):
    """Explain forms.6/7's stated criteria; this is not the orientation oracle."""
    adjacency = collections.defaultdict(list)
    for name, w in cards.items():
        if name[0] not in "rlvifhgdwsqjzm":
            continue
        a, b = w[1], w[3] if name[0] in "qjzm" else w[2]
        adjacency[a].append(b)
        adjacency[b].append(a)
    distance = {}
    for role in ("supply", "sink"):
        dist = {n: 0 for n in adjacency if rail(n) == role}
        queue = list(dist)
        for net in queue:
            if rail(net) and rail(net) != role:
                continue
            for other in adjacency[net]:
                if other not in dist:
                    dist[other] = dist[net] + 1
                    queue.append(other)
        distance[role] = dist
    a, b = row["junction"], row["gate_net"]
    inf = float("inf")
    sa, sb = [distance["supply"].get(n, inf) for n in (a, b)]
    ga, gb = [distance["sink"].get(n, inf) for n in (a, b)]
    return dict(dc_degrees=[len(adjacency[a]), len(adjacency[b])],
                series=len(adjacency[a]) == len(adjacency[b]) == 2,
                down=(sa < sb and ga > gb) or (sa > sb and ga < gb))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path)
    args = parser.parse_args()
    paths = sorted(args.examples.glob("*.human.json"))
    if not paths:
        raise ValueError("no paired source drawings")
    selected, excluded, hashes, native_hashes = [], [], {}, {}
    for hp in paths:
        ident = hp.name.removesuffix(".human.json")
        deck, svg = [hp.with_name(ident + suffix) for suffix in (".cir", ".svg")]
        cards, rows = select(deck.read_text())
        if not rows:
            continue
        human = json.loads(hp.read_text())
        devices = {d["card"]: d for d in human["devices"]}
        root = ET.parse(svg).getroot()
        targets = {n for r in rows for n in [r["card"], r["source"]] + r["mos"] + r["bjt"]}
        verified = {n: actual(root, devices[n]) for n in sorted(targets)}
        for n, glyph in verified.items():
            devices[n]["terminals"].update(glyph["terminals"])
        for p in (hp, deck, svg):
            hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
        native = {}
        if args.native and any(r["admitted"] for r in rows):
            p = args.native / (ident + ".json")
            native_hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
            native = {d["name"].lower(): d for d in json.loads(p.read_text())["devices"]}
        for r in rows:
            r.update(id=ident, source_geometry=geometry(r, devices),
                     source_glyphs={n: verified[n] for n in [r["card"], r["source"]] + r["mos"] + r["bjt"]},
                     split="holdout" if int(ident.rsplit("-", 1)[1]) % 5 == 0 else "discovery")
            if r["admitted"]:
                r["initial_form_criteria"] = initial_form(cards, r)
                if native:
                    r["native_geometry"] = geometry(r, native, True)
                selected.append(r)
            else:
                excluded.append(r)
    summary = dict(resistors=len(selected), circuits=len({r["id"] for r in selected}),
                   names=sorted(r["id"] + ":" + r["card"] for r in selected),
                   holdout_names=sorted(r["id"] + ":" + r["card"] for r in selected if r["split"] == "holdout"))
    for origin in ("source_geometry", "native_geometry"):
        summary[origin] = dict(collections.Counter(k for r in selected if origin in r for k, v in r[origin].items() if v))
    result = dict(corpus_drawings=len(paths), summary=summary, selected=selected, excluded_no_mos_gate=excluded,
                  source_sha256=hashes, native_sha256=native_hashes, script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
