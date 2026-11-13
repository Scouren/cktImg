#!/usr/bin/env python3
"""Complete single-input amplifier contracts against independent SVG glyphs.

Usage: single_input_amplifiers.py <examples-dir> <output.json> [--native-dir DIR]

Known opamp/comparator families require exactly one signed or unsigned input,
one output, and optional unique rail/bias roles. An unknown control, duplicate
role or missing input is excluded. Selection reads only the source SPICE.
The source SVG supplies the triangle and polarity-mark oracle: line segments
strictly inside the triangle are a minus, a crossing plus, or no sign.
No missing electrical port is synthesized and no engine code is imported.
An optional native directory contains each selected ID's JSON and SVG drawing.
Its triangle, polarity and ordered electrical bindings are checked separately.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from biased_amplifiers import triangle
from mos_forms import read_cards


FAMILIES = {"opamp", "icm_opamp_vdd_vss", "comparator", "comp", "icm_ideal_comparator_vdd"}


def role(name):
    if name.startswith(("vdd", "vcc", "avdd", "dvdd", "vpp")):
        return "supply"
    if name == "0" or name.startswith(("gnd", "vss", "vee", "agnd", "dgnd")):
        return "ground"
    for kind, words in (("positive", "vip inp in+ vp vin+"), ("negative", "inn in- vn vin-"),
                        ("unsigned", "vin in a"), ("output", "vout out vo o y"),
                        ("bias1", "vb vb1 bias"), ("bias2", "vb2"), ("bias3", "vb3")):
        if name in words.split():
            return kind
    return None


def contract(family, ports):
    roles = [role(p) for p in ports]
    inputs = [r for r in roles if r in ("positive", "negative", "unsigned")]
    if (family not in FAMILIES or not 2 <= len(ports) <= 8 or None in roles
            or len(set(roles)) != len(roles) or len(inputs) != 1 or roles.count("output") != 1):
        return None
    return inputs[0]


def polarity_mark(group):
    """Source-only triangle interior lines, without terminal-name inference."""
    bodies = [n for n in group.iter() if n.tag.rsplit("}", 1)[-1] == "path"
              and re.findall(r"[A-Za-z]", n.get("d", "")) == ["M", "L", "L", "Z"]]
    if len(bodies) != 1:
        return "unsupported-outline"
    values = list(map(float, re.findall(r"-?\d+(?:\.\d+)?", bodies[0].get("d", ""))))
    if len(values) != 6:
        raise ValueError("triangle does not have three explicit vertices")
    points = list(zip(values[::2], values[1::2]))

    def inside(p):
        crosses = [(b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
                   for a, b in zip(points, points[1:] + points[:1])]
        return all(c > 1e-6 for c in crosses) or all(c < -1e-6 for c in crosses)

    marks = []
    for node in group.iter():
        if node.tag.rsplit("}", 1)[-1] != "line":
            continue
        a = (float(node.get("x1")), float(node.get("y1")))
        b = (float(node.get("x2")), float(node.get("y2")))
        if inside(a) and inside(b):
            marks.append((a, b))
    if not marks:
        return "unsigned"
    hs = [(a, b) for a, b in marks if a[1] == b[1] and a[0] != b[0]]
    vs = [(a, b) for a, b in marks if a[0] == b[0] and a[1] != b[1]]
    if len(marks) == len(hs) == 1:
        return "negative"
    if len(marks) == 2 and len(hs) == len(vs) == 1:
        a, b = hs[0]
        c, d = vs[0]
        if min(a[0], b[0]) < c[0] < max(a[0], b[0]) and min(c[1], d[1]) < a[1] < max(c[1], d[1]):
            return "positive"
    return "unsupported-interior"


def native_glyph(directory, cid, card, ports, bindings, mark):
    """Adapter for rendered SVG strokes, not the engine's family decision."""
    drawing, svg = directory / (cid + ".json"), directory / (cid + ".svg")
    device = next(d for d in json.loads(drawing.read_text())["devices"] if d["name"] == card)
    root, bodies = ET.parse(svg).getroot(), []
    for node in root.iter():
        if node.tag.rsplit("}", 1)[-1] != "polyline":
            continue
        points = [tuple(map(float, p.split(","))) for p in node.get("points", "").split()]
        if len(points) == 4 and points[0] == points[-1] and len(set(points)) == 3:
            a, b, c = points[:3]
            if (b[0] - a[0]) * (c[1] - a[1]) != (b[1] - a[1]) * (c[0] - a[0]):
                bodies.append(points[:3])
    # This cohort has one recognized triangle per drawing; an extra triangle
    # is an unsupported ambiguity, not permission to choose a passing one.
    signs = []
    if len(bodies) == 1:
        points = bodies[0]
        for node in root.iter():
            if node.tag.rsplit("}", 1)[-1] != "text" or node.text not in ("+", "-"):
                continue
            p = (float(node.get("x")), float(node.get("y")))
            cross = [(b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
                     for a, b in zip(points, points[1:] + points[:1])]
            if all(c > 0 for c in cross) or all(c < 0 for c in cross):
                signs.append(node.text)
    expected = {"positive": ["+"], "negative": ["-"], "unsigned": []}[mark]
    return dict(triangular=len(bodies) == 1, sign_agrees=len(bodies) == 1 and signs == expected,
                ports_preserved=[p["term"] for p in device["pins"]] == ports,
                bindings_preserved=[p["net"] for p in device["pins"]] == bindings,
                signs=signs, json_sha256=hashlib.sha256(drawing.read_bytes()).hexdigest(),
                svg_sha256=hashlib.sha256(svg.read_bytes()).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native-dir", type=Path)
    args = parser.parse_args()
    files = sorted(args.examples.rglob("*.human.json"))
    if not files:
        parser.error("no paired human drawings")
    selfcheck()
    rows, excluded = [], []
    digest = hashlib.sha256()
    for hp in files:
        cid = hp.name.removesuffix(".human.json")
        deck, svg = hp.with_name(cid + ".cir"), hp.with_name(cid + ".svg")
        hashes = {}
        for label, path in (("human", hp), ("deck", deck), ("svg", svg)):
            data, name = path.read_bytes(), path.relative_to(args.examples).as_posix().encode()
            digest.update(len(name).to_bytes(8, "big") + name + len(data).to_bytes(8, "big") + data)
            hashes[label] = hashlib.sha256(data).hexdigest()
        text = deck.read_text()
        cards, definitions = read_cards(text), {}
        for line in text.lower().splitlines():
            words = line.split()
            if not words or words[0] != ".subckt":
                continue
            end = next((i for i, w in enumerate(words) if "=" in w or w == "params:"), len(words))
            if words[1] in definitions:
                raise ValueError("duplicate source definition: " + words[1])
            definitions[words[1]] = words[2:end]
        selected = []
        for name, words in cards.items():
            if name[0] != "x":
                continue
            end = next((i for i, w in enumerate(words) if "=" in w or w == "params:"), len(words))
            family = words[end - 1]
            if family not in FAMILIES:
                continue
            ports = definitions[family]
            if len(words[1:end - 1]) != len(ports):
                raise ValueError(f"{cid}:{name}: incomplete call")
            mark = contract(family, ports)
            if mark is not None:
                assert contract(family, list(reversed(ports))) == mark
                selected.append((name, family, ports, mark, words[1:end - 1]))
            elif sum(role(p) in ("positive", "negative", "unsigned") for p in ports) == 1:
                excluded.append(dict(id=cid, card=name, family=family, ports=ports))
        if not selected:
            continue
        human = {d["card"]: d for d in json.loads(hp.read_text())["devices"]}
        groups = [g for g in ET.parse(svg).iter() if g.get("data-symbol-id")]
        for name, family, ports, mark, bindings in selected:
            asset = human[name]["type"]
            matches = [g for g in groups if g.get("data-symbol-id") == asset]
            if not matches:
                raise ValueError(f"{cid}:{name}: missing source SVG asset")
            signs = [polarity_mark(g) for g in matches]
            row = dict(id=cid, card=name, family=family, ports=ports, bindings=bindings, input_role=mark,
                             split="holdout" if int(cid.split("-")[-1]) % 5 == 0 else "discovery",
                             triangular=all(triangle(g) for g in matches), source_marks=signs,
                             sign_agrees=all(s == mark for s in signs), source_asset=asset, hashes=hashes)
            if args.native_dir:
                row["native"] = native_glyph(args.native_dir, cid, name, ports, bindings, mark)
            rows.append(row)
    summary = dict(instances=len(rows), triangles=sum(r["triangular"] for r in rows),
                   matching_signs=sum(r["sign_agrees"] for r in rows),
                   input_roles=dict(collections.Counter(r["input_role"] for r in rows)),
                   splits=dict(collections.Counter(r["split"] for r in rows)))
    result = dict(corpus_sha256=digest.hexdigest(), drawings=len(files), summary=summary,
                  selected=rows, excluded_incomplete_contracts=excluded,
                  exceptions=[f"{r['id']}:{r['card']}" for r in rows if not r["triangular"] or not r["sign_agrees"]])
    if args.native_dir:
        checks = ("triangular", "sign_agrees", "ports_preserved", "bindings_preserved")
        result["native_summary"] = {check: sum(r["native"][check] for r in rows) for check in checks}
        result["native_exceptions"] = [f"{r['id']}:{r['card']}" for r in rows
                                       if not all(r["native"][check] for check in checks)]
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({k: result[k] for k in ("corpus_sha256", "drawings", "summary")}, indent=2))
    if args.native_dir:
        print(json.dumps(result["native_summary"], indent=2))


def selfcheck():
    assert contract("opamp", "vdd vss vb1 out inn vb2 vb3".split()) == "negative"
    assert contract("comparator", "vb1 vdd inp out".split()) == "positive"
    assert contract("comparator", "vdd in out".split()) == "unsigned"
    assert contract("comp", "vdd vss vb1 vb2 inn out".split()) == "negative"
    assert contract("comp", "vdd vss in out".split()) == "unsigned"
    for family, ports in (("custom_stage", "in out"), ("opamp", "vdd out"),
                          ("opamp", "inp inn out"), ("opamp", "inp out tail"),
                          ("opamp", "in out vb vb1"), ("opamp", "in out vx"),
                          ("comp", "inn out vx"), ("comp", "inn out tail"),
                          ("comp", "inn out ib"), ("comp", "inn out vbn"),
                          ("comp", "inn out vb4 vb5")):
        assert contract(family, ports.split()) is None


if __name__ == "__main__":
    main()
