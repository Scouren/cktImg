#!/usr/bin/env python3
"""Exact amplifier family contracts against independently drawn SVG ink.

Usage: block_aliases.py <examples-dir> <output.json>

AMP, AMP1, CMP and EA are candidate whole family names. Complete contracts
have one output, one signed/unsigned input or a signed pair, and unique known
rail/bias roles. Family occurrences and complete contracts are counted
separately. A1 remains a generic name; ZCD is a box in its observed cases.
Neither negative family nor a prefix/suffix match is admitted.

Triangle bodies, polarity strokes and their external leads come from SVG,
independently of cached terminal coordinates. A matching triangle/sign count
does not establish terminal geometry: each signal's cached coordinate is
compared with the lead identified by its actual sign or output apex. Declared
ports absent from the source terminal table remain unknown geometry. All
source triples and audit dependencies are hashed. Exact inventories and
known frame mismatches are checked; unsupported or ambiguous ink fails.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import controller_glyphs as glyph
from mos_forms import read_cards
from single_input_amplifiers import role

FAMILIES = frozenset(("amp", "amp1", "cmp", "ea"))
EXCLUDED_FAMILIES = frozenset(("a1", "zcd"))
INPUTS = frozenset(("positive", "negative", "unsigned"))
TOLERANCE = .01  # Source SVG vertices are rounded to .001 units.


def contract(ports):
    roles = [role(p.lower()) for p in ports]
    inputs = [r for r in roles if r in INPUTS]
    if (not 2 <= len(ports) <= 8 or None in roles or len(set(roles)) != len(roles)
            or roles.count("output") != 1
            or not (len(inputs) == 1 or sorted(inputs) == ["negative", "positive"])):
        return None
    return roles


def admitted(family, ports):
    return family.lower() in FAMILIES and contract(ports) is not None


def source_group(human, root, card):
    devices = [d for d in human["devices"] if d["card"].lower() == card]
    if len(devices) != 1:
        raise ValueError(f"{human['id']}:{card}: no unique human device")
    device = devices[0]
    center = (device["x"], device["y"])
    groups = [(g, p) for g, _, p in glyph.walk(root)
              if g.get("data-symbol-id") == device["type"]
              and any(n.tag.endswith("g") and n.get("transform")
                      and glyph.close(glyph.point(t, (0, 0)), center)
                      for n, t, _ in glyph.walk(g, p))]
    if len(groups) != 1:
        raise ValueError(f"{human['id']}:{card}: no unique SVG asset at authored origin")
    return device, *groups[0]


def on_segment(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    if length == 0:
        raise ValueError("degenerate symbol edge")
    distance = abs(dx * (p[1] - a[1]) - dy * (p[0] - a[0])) / length
    return (distance < TOLERANCE and min(a[0], b[0]) - TOLERANCE <= p[0] <= max(a[0], b[0]) + TOLERANCE
            and min(a[1], b[1]) - TOLERANCE <= p[1] <= max(a[1], b[1]) + TOLERANCE)


def location(p, polygon):
    edges = list(zip(polygon, polygon[1:] + polygon[:1]))
    if any(on_segment(p, a, b) for a, b in edges):
        return "boundary"
    cross = [(b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) for a, b in edges]
    return "inside" if all(v > 0 for v in cross) or all(v < 0 for v in cross) else "outside"


def primitives(group, parent):
    bodies, lines = [], []
    for node, transform, _ in glyph.walk(group, parent):
        tag = node.tag.rsplit("}", 1)[-1]
        if tag == "path":
            if re.findall(r"[A-Za-z]", node.get("d", "")) != ["M", "L", "L", "Z"]:
                raise ValueError("unsupported symbol path")
            values = glyph.numbers(node.get("d"))
            if len(values) != 6:
                raise ValueError("triangle must contain three explicit vertices")
            bodies.append([glyph.point(transform, p) for p in zip(values[::2], values[1::2])])
        elif tag == "polygon":
            values = glyph.numbers(node.get("points", ""))
            if len(values) != 8:
                raise ValueError("unsupported symbol polygon")
            bodies.append([glyph.point(transform, p) for p in zip(values[::2], values[1::2])])
        elif tag == "line":
            line = [glyph.point(transform, (float(node.get("x1")), float(node.get("y1")))),
                    glyph.point(transform, (float(node.get("x2")), float(node.get("y2"))))]
            if glyph.close(*line):
                raise ValueError("zero-length symbol stroke")
            lines.append(line)
        elif tag not in ("g", "text", "tspan"):
            raise ValueError(f"unsupported symbol element: {tag}")
    if len(bodies) != 1:
        raise ValueError("symbol has no unique supported outline")
    body = bodies[0]
    if len(body) == 4:
        for a, b in zip(body, body[1:] + body[:1]):
            glyph.direction(a, b)  # A negative box must be an actual rectangle.
        if len({p[0] for p in body}) != 2 or len({p[1] for p in body}) != 2:
            raise ValueError("quadrilateral is not an axis-aligned box")
    leads, interior, extensions = [], [], []
    for a, b in lines:
        positions = (location(a, body), location(b, body))
        if positions == ("inside", "inside"):
            glyph.direction(a, b)
            interior.append((a, b))
        elif positions == ("boundary", "outside"):
            glyph.direction(a, b)
            leads.append(dict(attachment=a, endpoint=b, path=[a, b]))
        elif positions == ("outside", "boundary"):
            glyph.direction(b, a)
            leads.append(dict(attachment=b, endpoint=a, path=[b, a]))
        elif positions == ("outside", "outside"):
            glyph.direction(a, b)
            extensions.append((a, b))
        else:
            raise ValueError(f"stroke is neither an interior mark nor external lead: {a}, {b}")
    # AG1504's excluded generic A1 has two bent bias leads. Follow their
    # connected exterior strokes to the terminal rather than treating elbows
    # as endpoints or silently discarding non-signal ink.
    for lead in leads:
        while True:
            joins = [(i, b if glyph.close(lead["endpoint"], a) else a)
                     for i, (a, b) in enumerate(extensions)
                     if glyph.close(lead["endpoint"], a) or glyph.close(lead["endpoint"], b)]
            if not joins:
                break
            if len(joins) != 1:
                raise ValueError("external lead branches")
            i, endpoint = joins[0]
            if any(glyph.close(endpoint, other["endpoint"]) for other in leads if other is not lead):
                raise ValueError("external lead joins another lead")
            lead["endpoint"] = endpoint
            lead["path"].append(endpoint)
            extensions.pop(i)
    if extensions:
        raise ValueError("unconnected exterior symbol strokes")
    return body, leads, interior


def polarity_marks(interior):
    centers = [((a[0] + b[0]) / 2, (a[1] + b[1]) / 2) for a, b in interior]
    used, marks = set(), []
    for i, (a, b) in enumerate(interior):
        if i in used:
            continue
        same = [j for j in range(i + 1, len(interior)) if j not in used and glyph.close(centers[i], centers[j])]
        if len(same) > 1:
            raise ValueError("ambiguous interior polarity strokes")
        kind = "negative"
        if same:
            j = same[0]
            c, d = interior[j]
            if abs((b[0] - a[0]) * (d[0] - c[0]) + (b[1] - a[1]) * (d[1] - c[1])) > 1e-5:
                raise ValueError("coincident polarity strokes are not perpendicular")
            used.add(j)
            kind = "positive"
        marks.append(dict(role=kind, center=centers[i], strokes=[interior[j] for j in [i] + same]))
    return marks


def signal_leads(body, leads, marks, roles):
    if len(body) != 3:
        return {}, None
    bases = [(a, b) for a, b in zip(body, body[1:] + body[:1])
             if abs(a[0] - b[0]) < TOLERANCE or abs(a[1] - b[1]) < TOLERANCE]
    if len(bases) != 1:
        raise ValueError("triangle has no unique cardinal base")
    a, b = bases[0]
    axis = 0 if abs(a[1] - b[1]) < TOLERANCE else 1
    apex = next(p for p in body if p != a and p != b)
    outputs = [lead for lead in leads if glyph.close(lead["attachment"], apex)]
    if len(outputs) != 1:
        raise ValueError("triangle has no unique output lead")
    direction = glyph.direction(apex, outputs[0]["endpoint"])
    midpoint = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    if direction != glyph.direction(midpoint, apex):
        raise ValueError("output lead does not continue outward from triangle apex")
    actual = {"output": outputs[0]["endpoint"]}
    inputs = [lead for lead in leads if on_segment(lead["attachment"], a, b)]
    for mark in marks:
        # AG1367's upward triangle keeps its minus stroke screen-horizontal;
        # source authors need not rotate signs along with the body.
        candidates = [lead for lead in inputs if abs(lead["endpoint"][axis] - mark["center"][axis]) < TOLERANCE]
        if len(candidates) != 1 or mark["role"] in actual:
            raise ValueError("sign does not identify one unique input lead")
        actual[mark["role"]] = candidates[0]["endpoint"]
    if "unsigned" in roles:
        if marks or len(inputs) != 1:
            raise ValueError("unsigned input has ambiguous source leads")
        actual["unsigned"] = inputs[0]["endpoint"]
    expected = {r for r in roles if r in INPUTS or r == "output"}
    if set(actual) != expected or len(inputs) != len(expected) - 1:
        raise ValueError("actual source signal leads disagree with the complete contract")
    return actual, direction


def inspect(human, root, card, ports):
    device, group, parent = source_group(human, root, card)
    body, leads, interior = primitives(group, parent)
    marks = polarity_marks(interior)
    roles = contract(ports)
    if roles is None:
        raise ValueError("SVG inspection requires a complete port contract")
    actual, direction = signal_leads(body, leads, marks, roles)
    cached = {name.lower(): xy for name, xy in device["terminals"].items()}
    endpoint_matches = {p: p in cached and any(glyph.close(cached[p], lead["endpoint"]) for lead in leads) for p in ports}
    signals = {p: r for p, r in zip(ports, roles) if r in INPUTS or r == "output"}
    frame_matches = {p: p in cached and glyph.close(cached[p], actual[r]) for p, r in signals.items()} if actual else {}
    expected_marks = sorted(r for r in roles if r in ("positive", "negative"))
    return dict(source_asset=device["type"], source_object=group.get("data-object-id"),
                shape="triangle" if len(body) == 3 else "box", body=body, source_marks=marks,
                expected_marks=expected_marks, marks_agree=sorted(m["role"] for m in marks) == expected_marks,
                external_leads=leads, actual_signal_leads=actual, output_direction=direction,
                cached_terminals=cached, declared_endpoint_matches=endpoint_matches,
                missing_source_ports=sorted(p for p in ports if p not in cached),
                signal_frame_matches=frame_matches,
                signal_frame_mismatches=sorted(p for p, matches in frame_matches.items() if not matches))


def scan(text, cid):
    definitions = {}
    for line in text.lower().splitlines():
        words = line.split()
        if not words or words[0] != ".subckt":
            continue
        end = next((i for i, w in enumerate(words) if "=" in w or w == "params:"), len(words))
        if words[1] in definitions:
            raise ValueError(f"{cid}: duplicate definition {words[1]}")
        definitions[words[1]] = words[2:end]
    rows = []
    for card, words in read_cards(text).items():
        if not card.startswith("x"):
            continue
        end = next((i for i, w in enumerate(words) if "=" in w or w == "params:"), len(words))
        family = words[end - 1]
        if family not in FAMILIES | EXCLUDED_FAMILIES:
            continue
        if family not in definitions:
            raise ValueError(f"{cid}:{card}: undefined family")
        ports, bindings = definitions[family], words[1:end - 1]
        if len(ports) != len(bindings):
            raise ValueError(f"{cid}:{card}: incomplete instance call")
        complete = contract(ports) is not None
        rows.append(dict(id=cid, card=card, family=family, ports=ports, bindings=bindings,
                         complete_contract=complete, admitted=admitted(family, ports)))
    return rows


def check_inventory(actual, expected, label):
    if actual != expected:
        raise ValueError(f"{label} differs from exact inventory:\nexpected {expected}\nactual {actual}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--inventory", type=Path, default=Path(__file__).with_name("block_aliases_cases.json"))
    args = parser.parse_args()
    selfcheck()
    files = sorted(args.examples.rglob("*.human.json"))
    if not files:
        parser.error("examples directory contains no paired human drawings")
    expected = json.loads(args.inventory.read_text())["corpora"][args.examples.name]
    digest, occurrences, complete = hashlib.sha256(), [], []
    hashes = {}
    for hp in files:
        cid = hp.name.removesuffix(".human.json")
        deck, svg = hp.with_name(cid + ".cir"), hp.with_name(cid + ".svg")
        for path in (hp, deck, svg):
            data = path.read_bytes()
            name = path.relative_to(args.examples).as_posix()
            encoded = name.encode()
            digest.update(len(encoded).to_bytes(8, "big") + encoded + len(data).to_bytes(8, "big") + data)
            hashes[name] = hashlib.sha256(data).hexdigest()
        selected = scan(deck.read_text(), cid)
        occurrences.extend(selected)
        contracts = [r for r in selected if r["complete_contract"]]
        if not contracts:
            continue
        human, root = json.loads(hp.read_text()), ET.parse(svg).getroot()
        for row in contracts:
            try:
                evidence = inspect(human, root, row["card"], row["ports"])
            except ValueError as error:
                raise ValueError(f"{cid}:{row['card']}: {error}") from error
            complete.append(dict(**row, **evidence))
    families = sorted(FAMILIES | EXCLUDED_FAMILIES)
    names = lambda rows, family: sorted(r["id"] + ":" + r["card"] for r in rows if r["family"] == family)
    inventories = dict(family_occurrences={f: names(occurrences, f) for f in families},
                       complete_contracts={f: names(complete, f) for f in families})
    for label, inventory in inventories.items():
        check_inventory(inventory, expected[label], label)
    admitted_rows = [r for r in complete if r["admitted"]]
    mismatches = {r["id"] + ":" + r["card"]: r["signal_frame_mismatches"] for r in admitted_rows if r["signal_frame_mismatches"]}
    check_inventory(mismatches, expected["selected_signal_frame_mismatches"], "signal-frame mismatches")
    for row in admitted_rows:
        if row["shape"] != "triangle" or not row["marks_agree"]:
            raise ValueError(f"{row['id']}:{row['card']}: admitted family has contradictory SVG ink")
    for row in complete:
        if row["family"] == "zcd" and row["shape"] != "box":
            raise ValueError(f"{row['id']}:{row['card']}: ZCD negative is no longer a box")
    summary = {f: dict(occurrences=len(inventories["family_occurrences"][f]),
                       complete_contracts=len(inventories["complete_contracts"][f]),
                       admitted=sum(r["family"] == f for r in admitted_rows)) for f in families}
    dependencies = ["block_aliases.py", "controller_glyphs.py", "single_input_amplifiers.py",
                    "biased_amplifiers.py", "mos_forms.py", "power_paths.py"]
    result = dict(corpus=args.examples.name, corpus_sha256=digest.hexdigest(), drawings=len(files),
                  summary=summary, inventories=inventories, selected=admitted_rows,
                  excluded_complete_contracts=[r for r in complete if not r["admitted"]],
                  excluded_incomplete_contracts=[r for r in occurrences if not r["complete_contract"]],
                  selected_signal_frame_mismatches=mismatches, source_sha256=hashes,
                  audit_sha256={n: hashlib.sha256(Path(__file__).with_name(n).read_bytes()).hexdigest() for n in dependencies},
                  inventory_sha256=hashlib.sha256(args.inventory.read_bytes()).hexdigest(), tolerance=TOLERANCE,
                  limits="Shape/sign evidence only; cached frame comparisons do not establish source wiring equivalence or native glyph/port parity. Missing declared source terminals are retained as unknown geometry.")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(corpus=result["corpus"], drawings=len(files), corpus_sha256=digest.hexdigest(),
                         families=summary, triangles=sum(r["shape"] == "triangle" for r in admitted_rows),
                         marks_agree=sum(r["marks_agree"] for r in admitted_rows),
                         signal_frame_matches=sum(not r["signal_frame_mismatches"] for r in admitted_rows),
                         signal_frame_mismatches=mismatches), indent=2, sort_keys=True))


def selfcheck():
    for f in FAMILIES:
        assert admitted(f.upper(), ["vdd", "vss", "inp", "inn", "out"])
        assert admitted(f, ["vdd", "inn", "out", "vb1", "vb2"])
        assert admitted(f, ["in", "out"])
    for f in ("a1", "zcd", "my_cmp", "cmp1", "amp10", "preamp", "ea2"):
        assert not admitted(f, ["inp", "inn", "out"])
    for ports in (["out"], ["inp", "out", "enable"], ["inp", "inn", "out", "vb", "vb1"],
                  ["in", "inn", "out"], ["out", "vout", "inn"], ["vdd", "vcc", "inp", "out"]):
        assert not admitted("amp1", ports)
    svg = '<svg><g data-symbol-id="s"><g transform="translate(0 0)"><path d="M 0 0 L 0 40 L 40 20 Z"/>'
    for a, b in (((40, 20), (50, 20)), ((-10, 10), (0, 10)), ((-10, 30), (0, 30)),
                 ((5, 10), (11, 10)), ((8, 7), (8, 13)), ((5, 30), (11, 30))):
        svg += f'<line x1="{a[0]}" y1="{a[1]}" x2="{b[0]}" y2="{b[1]}"/>'
    svg += '</g></g></svg>'
    human = dict(id="literal", devices=[dict(card="x1", type="s", x=0, y=0,
                 terminals=dict(inp=[-10, 10], inn=[-10, 30], out=[50, 20]))])
    row = inspect(human, ET.fromstring(svg), "x1", ["inp", "inn", "out"])
    assert row["shape"] == "triangle" and row["marks_agree"] and not row["signal_frame_mismatches"]
    human["devices"][0]["terminals"]["inn"] = [-10, 10]
    wrong = inspect(human, ET.fromstring(svg), "x1", ["inp", "inn", "out"])
    assert wrong["declared_endpoint_matches"]["inn"] and wrong["signal_frame_mismatches"] == ["inn"]
    human["devices"][0].update(x=100, y=50, terminals=dict(inp=[90, 40], inn=[70, 40], out=[80, 100]))
    rotated = svg.replace('translate(0 0)', 'translate(100 50) rotate(90)')
    row = inspect(human, ET.fromstring(rotated), "x1", ["inp", "inn", "out"])
    assert row["output_direction"] == "down" and row["marks_agree"] and not row["signal_frame_mismatches"]
    bent = ET.fromstring('<g><polygon points="0,0 20,0 20,20 0,20"/>'
                        '<line x1="20" y1="10" x2="30" y2="10"/>'
                        '<line x1="30" y1="20" x2="30" y2="10"/></g>')
    body, leads, interior = primitives(bent, glyph.IDENTITY)
    assert len(body) == 4 and not interior and leads[0]["endpoint"] == (30, 20)
    assert leads[0]["path"] == [(20, 10), (30, 10), (30, 20)]
    try:
        check_inventory(["one", "two"], ["one", "three"], "same count, different names")
    except ValueError:
        pass
    else:
        raise AssertionError("inventory comparison accepted changed names")


if __name__ == "__main__":
    main()
