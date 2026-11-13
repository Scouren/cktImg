#!/usr/bin/env python3
"""Outer digital-family contracts -> own-symbol source/native ink inventory.

Usage: digital_symbols.py <examples-dir> <output.json>
       [--native-dir DIR --bin cktimg-json]

All conventional source gate/buffer/inverter assets are inventoried, even if
their family is unknown. PFD, DAC and CP are named opaque counterexamples.
Only complete exact-family A[/B]/Y plus optional unique VDD/VSS contracts
count as supported. Source paths, bubble circles and external lead endpoints
come from each actual SVG group. Native bodies belong to the named placement;
ordered JSON ports/nets and actual SVG leads are checked separately. Curved
source paths versus native polygons are recorded, not called full parity.
"""

import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import block_aliases as source
import block_aliases_native as native

GATES = {"buffer": "buffer", "inverter": "inverter", "and_gate": "and-gate",
         "nand_gate": "nand-gate", "or_gate": "or-gate", "nor_gate": "nor-gate",
         "xor_gate": "xor-gate", "xnor_gate": "xnor-gate"}
OPAQUE = frozenset(("pfd", "dac", "cp"))
INVERTED = frozenset(("inverter", "nand_gate", "nor_gate", "xnor_gate"))
EXCLUSIVE = frozenset(("xor_gate", "xnor_gate"))


def declarations(text):
    definitions = {}
    for line in text.lower().splitlines():
        words = line.split()
        if words and words[0] == ".subckt":
            end = next((i for i, word in enumerate(words) if "=" in word or word == "params:"), len(words))
            if words[1] in definitions:
                raise ValueError("duplicate subcircuit definition")
            definitions[words[1]] = words[2:end]
    return definitions


def complete(family, ports):
    signals = {"a", "y"} if family in ("buffer", "inverter") else {"a", "b", "y"}
    return (family in GATES and len(set(ports)) == len(ports)
            and signals <= set(ports) <= signals | {"vdd", "vss"})


def path_data(node, transform):
    data = node.get("d", "")
    number = r"[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?"
    tokens = re.findall(r"[A-Za-z]|" + number, data)
    if re.sub(r"[A-Za-z]|" + number, "", data).strip(" ,\n\t"):
        raise ValueError("unparsed SVG path text")
    commands, vertices, cursor = [], [], 0
    while cursor < len(tokens):
        command = tokens[cursor]
        count = {"M": 2, "L": 2, "C": 6, "Z": 0}.get(command)
        if count is None or cursor + count >= len(tokens):
            raise ValueError("unsupported or incomplete digital path")
        values = list(map(float, tokens[cursor + 1:cursor + count + 1]))
        commands.append(command)
        vertices.extend(source.glyph.point(transform, p) for p in zip(values[::2], values[1::2]))
        cursor += count + 1
    if not commands or commands[0] != "M" or not vertices:
        raise ValueError("digital path must start with a move")
    return dict(path=data, commands=commands, control_vertices=vertices,
                closed=commands[-1] == "Z" or source.glyph.close(vertices[0], vertices[-1]))


def source_ink(human, root, card):
    device, group, parent = source.source_group(human, root, card)
    paths, circles, lines, polygons = [], [], [], []
    for node, transform, _ in source.glyph.walk(group, parent):
        tag = native.tag(node)
        if tag == "path":
            paths.append(path_data(node, transform))
        elif tag == "circle":
            xscale, yscale = math.hypot(*transform[:2]), math.hypot(*transform[2:4])
            if abs(xscale - yscale) > 1e-6 or abs(transform[0] * transform[2] + transform[1] * transform[3]) > 1e-6:
                raise ValueError("circle transform is not an isometry with uniform scale")
            circles.append(dict(center=source.glyph.point(transform, (float(node.get("cx")), float(node.get("cy")))),
                                radius=float(node.get("r")) * xscale))
        elif tag == "line":
            lines.append([source.glyph.point(transform, (float(node.get("x1")), float(node.get("y1")))),
                          source.glyph.point(transform, (float(node.get("x2")), float(node.get("y2"))))])
        elif tag == "polygon":
            numbers = source.glyph.numbers(node.get("points", ""))
            if len(numbers) != 8:
                raise ValueError("unsupported opaque polygon")
            polygons.append([source.glyph.point(transform, p) for p in zip(numbers[::2], numbers[1::2])])
        elif tag not in ("g", "text", "tspan"):
            raise ValueError(f"unsupported source primitive {tag}")
    closed = [p for p in paths if p["closed"]]
    if len(closed) + len(polygons) != 1:
        raise ValueError("no unique digital body")
    body = ("box" if polygons else "curved" if "C" in closed[0]["commands"] else "triangle")
    if body == "triangle" and len(set(closed[0]["control_vertices"])) != 3:
        raise ValueError("non-curved body is not a triangle")
    cached = {p.lower(): xy for p, xy in device["terminals"].items()}
    signal_matches = {p: sum(any(source.glyph.close(xy, q) for q in line) for line in lines)
                      for p, xy in cached.items() if p in ("a", "b", "y")}
    return dict(asset=device["type"], object=group.get("data-object-id"), body=body,
                paths=paths, circles=circles, lines=lines, polygons=polygons,
                cached_signal_lead_matches=signal_matches, cached_ports=sorted(cached),
                open_paths=sum(not p["closed"] for p in paths))


def native_ink(drawing, root, row):
    matches = [d for d in drawing["devices"] if d["name"] == row["card"]]
    if len(matches) != 1:
        raise ValueError("no unique native instance")
    device = matches[0]
    if ([p["term"] for p in device["pins"]] != row["ports"]
            or [p["net"] for p in device["pins"]] != row["bindings"]):
        raise ValueError("ordered electrical bindings changed")
    scale, offset, ink = native.frame(drawing, root)
    local = lambda p: native.inverse(device, [(p[i] - offset[i]) / scale for i in range(2)])
    tolerance = native.PIXEL_TOLERANCE / scale
    polylines = [(i, [local(p) for p in native.points(n)]) for i, n in enumerate(ink) if native.tag(n) == "polyline"]
    bodies = [(i, ps[:-1]) for i, ps in polylines if len(ps) >= 4 and native.near(ps[0], ps[-1], tolerance)
              and native.near(native.center(ps[:-1]), (0, 0), tolerance)]
    if len(bodies) != 1:
        raise ValueError("no unique own-placement native body")
    body_index, body = bodies[0]
    kind = "triangle" if len(body) == 3 else "box" if len(body) == 4 else "polygonal_curve"
    leads = []
    for pin in device["pins"]:
        end = native.inverse(device, pin["xy"])
        candidates = [(i, ps if native.near(ps[0], end, tolerance) else ps[::-1])
                      for i, ps in polylines if len(ps) == 2 and any(native.near(p, end, tolerance) for p in ps)]
        if len(candidates) != 1:
            raise ValueError(f"no unique native pin stroke for {pin['term']}")
        leads.append(dict(term=pin["term"], net=pin["net"], ink_index=candidates[0][0], vertices=candidates[0][1]))
    if len({p["ink_index"] for p in leads}) != len(leads):
        raise ValueError("native pins share a stroke")
    bubbles, extras, sides = [], [], {}
    input_order = True
    if row["family"] in GATES:
        for lead in leads:
            x, y = lead["vertices"][0]
            sides[lead["term"]] = {
                "a": x < min(p[0] for p in body), "b": x < min(p[0] for p in body),
                "y": x > max(p[0] for p in body), "vdd": y < min(p[1] for p in body),
                "vss": y > max(p[1] for p in body),
            }[lead["term"]]
        inputs = {p["term"]: p["vertices"][0] for p in leads if p["term"] in ("a", "b")}
        if "b" in inputs:
            input_order = inputs["a"][1] < inputs["b"][1]
        output = next(p for p in leads if p["term"] == "y")["vertices"][0]
        for index, node in enumerate(ink):
            if native.tag(node) != "circle":
                continue
            center = local((float(node.get("cx")), float(node.get("cy"))))
            if max(p[0] for p in body) < center[0] < output[0] and abs(center[1] - output[1]) < tolerance:
                bubbles.append(dict(ink_index=index, center=center, radius=float(node.get("r")) / scale))
        for index, ps in polylines:
            if len(ps) < 3 or native.near(ps[0], ps[-1], tolerance):
                continue
            if all(-60 - tolerance <= p[0] <= 0 and -40 - tolerance <= p[1] <= 40 + tolerance for p in ps):
                extras.append(dict(ink_index=index, vertices=ps))
    for lead in leads:
        p = lead["vertices"][1]
        distances = []
        for a, b in zip(body, body[1:] + body[:1]):
            delta = [b[i] - a[i] for i in range(2)]
            norm = sum(v * v for v in delta)
            if norm == 0:
                raise ValueError("degenerate native body edge")
            t = max(0, min(1, sum((p[i] - a[i]) * delta[i] for i in range(2)) / norm))
            distances.append(math.hypot(*(p[i] - a[i] - t * delta[i] for i in range(2))))
        distances += [abs(math.hypot(*(p[i] - circle["center"][i] for i in range(2))) - circle["radius"])
                      for circle in bubbles]
        lead["attachment_outline_distance"] = round(min(distances), 6)
        lead["attachment_meets_outline"] = min(distances) < tolerance
    expected = "polygonal_curve" if row["source"]["body"] == "curved" else row["source"]["body"]
    return dict(body=kind, body_category_agrees=kind == expected,
                bubble_count_agrees=len(bubbles) == len(row["source"]["circles"]),
                extra_input_path_count_agrees=len(extras) == row["source"]["open_paths"],
                terminal_sides=sides, terminal_sides_agree=all(sides.values()), input_order_agrees=input_order,
                body_vertices=body, body_ink_index=body_index, body_dimensions=native.extent(body),
                circles=bubbles, extra_input_paths=extras, leads=leads,
                ordered_ports=row["ports"], ordered_bindings=row["bindings"],
                placement={k: device[k] for k in ("pos", "rot", "mirror")},
                display_scale=scale, display_offset=offset)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native-dir", type=Path)
    parser.add_argument("--bin", type=Path)
    args = parser.parse_args()
    if bool(args.native_dir) != bool(args.bin):
        parser.error("native-dir and bin are required together")
    selfcheck()
    rows, all_families, all_assets, hashes = [], collections.Counter(), collections.Counter(), {}
    digest = hashlib.sha256()
    files = sorted(args.examples.glob("*.human.json"))
    if not files:
        parser.error("no paired source drawings")
    for hp in files:
        cid = hp.name.removesuffix(".human.json")
        for suffix in (".human.json", ".cir", ".svg"):
            path = hp.with_name(cid + suffix)
            data, name = path.read_bytes(), path.name.encode()
            digest.update(len(name).to_bytes(8, "big") + name + len(data).to_bytes(8, "big") + data)
            hashes[path.name] = hashlib.sha256(data).hexdigest()
        human, text = json.loads(hp.read_text()), hp.with_name(cid + ".cir").read_text()
        definitions, selected = declarations(text), []
        devices = {d["card"].lower(): d for d in human["devices"]}
        for card, words in source.read_cards(text).items():
            if not card.startswith("x"):
                continue
            end = next((i for i, word in enumerate(words) if "=" in word or word == "params:"), len(words))
            family, asset = words[end - 1], devices[card]["type"]
            all_families[family] += 1
            all_assets[asset] += 1
            if family not in GATES and family not in OPAQUE and asset not in GATES.values():
                continue
            ports, bindings = definitions[family], words[1:end - 1]
            if len(ports) != len(bindings):
                raise ValueError(f"{cid}:{card}: incomplete call")
            selected.append(dict(id=cid, card=card, family=family, ports=ports, bindings=bindings,
                                 complete_contract=complete(family, ports)))
        if not selected:
            continue
        root = ET.parse(hp.with_name(cid + ".svg")).getroot()
        for row in selected:
            ink = source_ink(human, root, row["card"])
            row.update(source=ink, missing_cached_ports=sorted(set(row["ports"]) - set(ink["cached_ports"])))
            if row["family"] in GATES:
                expected_body = "triangle" if row["family"] in ("buffer", "inverter") else "curved"
                expected_signals = {"a", "y"} if row["family"] in ("buffer", "inverter") else {"a", "b", "y"}
                if (ink["body"] != expected_body or len(ink["circles"]) != (row["family"] in INVERTED)
                        or ink["open_paths"] != (row["family"] in EXCLUSIVE)
                        or set(ink["cached_signal_lead_matches"]) != expected_signals
                        or any(n != 1 for n in ink["cached_signal_lead_matches"].values())):
                    raise ValueError(f"{cid}:{row['card']}: source digital glyph changed")
            elif ink["body"] != "box":
                raise ValueError(f"{cid}:{row['card']}: negative family is no longer opaque")
            rows.append(row)
    if args.bin:
        args.native_dir.mkdir(parents=True, exist_ok=True)
        for cid in sorted({r["id"] for r in rows}):
            run = subprocess.run([str(args.bin.resolve()), "--svg", str(args.native_dir / (cid + ".svg")),
                                  str(args.examples / (cid + ".cir")), str(args.native_dir / (cid + ".json"))],
                                 capture_output=True, text=True, timeout=30)
            if run.returncode:
                raise ValueError(f"{cid}: native render failed: {run.stderr}")
        for row in rows:
            jp, sp = [args.native_dir / (row["id"] + suffix) for suffix in (".json", ".svg")]
            row["native"] = native_ink(json.loads(jp.read_text()), ET.parse(sp).getroot(), row)
            row["native_sha256"] = {p.suffix: hashlib.sha256(p.read_bytes()).hexdigest() for p in (jp, sp)}
    inventory = {f: sorted(r["id"] + ":" + r["card"] for r in rows if r["family"] == f) for f in sorted(GATES.keys() | OPAQUE)}
    inventory_path = Path(__file__).with_name("digital_symbols_cases.json")
    expected = json.loads(inventory_path.read_text())[args.examples.name]
    source.check_inventory(inventory, expected, "digital exact-name inventory")
    summary = {f: dict(occurrences=len(names), complete_contracts=sum(r["family"] == f and r["complete_contract"] for r in rows))
               for f, names in inventory.items()}
    result = dict(corpus=args.examples.name, drawings=len(files), corpus_sha256=digest.hexdigest(),
                  summary=summary, inventories=inventory, instances=rows,
                  all_outer_family_counts=dict(sorted(all_families.items())), all_outer_asset_counts=dict(sorted(all_assets.items())),
                  source_sha256=hashes, renderer_sha256=hashlib.sha256(args.bin.read_bytes()).hexdigest() if args.bin else None,
                  audit_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
                                [Path(__file__), Path(source.__file__), Path(native.__file__), Path(source.glyph.__file__),
                                 Path(__file__).with_name("mos_forms.py"), Path(__file__).with_name("power_paths.py"),
                                 Path(__file__).with_name("single_input_amplifiers.py"), Path(__file__).with_name("biased_amplifiers.py")]},
                  inventory_sha256=hashlib.sha256(inventory_path.read_bytes()).hexdigest(),
                  limits="Conventional digital glyph cohort and named opaque counterexamples; no function inferred from an arbitrary family name. Matching body category/bubble/extra-path counts does not establish exact curve, dimensions, cached frame or routing parity. Native extra supply leads are preserved electrical ports.")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))
    if args.bin:
        failures = [r["id"] + ":" + r["card"] for r in rows
                    if not all(r["native"][key] for key in ("body_category_agrees", "bubble_count_agrees", "extra_input_path_count_agrees",
                                                          "terminal_sides_agree", "input_order_agrees"))]
        if failures:
            raise ValueError("digital glyph category/terminal-side mismatch: " + ", ".join(failures))


def selfcheck():
    triangle = ET.fromstring('<path d="M 0 0 L 10 5 L 0 10 L 0 0"/>')
    p = path_data(triangle, source.glyph.IDENTITY)
    assert p["closed"] and p["commands"] == ["M", "L", "L", "L"]
    assert len(set(p["control_vertices"])) == 3
    curve = ET.fromstring('<path d="M 0 0 C 5 0 5 10 0 10"/>')
    assert not path_data(curve, source.glyph.IDENTITY)["closed"]
    assert complete("inverter", ["vdd", "vss", "a", "y"])
    assert complete("xor_gate", ["a", "b", "y"])
    assert not complete("pfd", ["a", "b", "qa", "qb"])
    assert not complete("buffer", ["a", "y", "enable"])
    assert not complete("buffer", ["a", "a", "y"])
    assert not complete("nand_gate", ["a", "y"])
    row = dict(card="x1", family="inverter", ports=["vdd", "vss", "a", "y"],
               bindings=["power", "ground", "input", "output"],
               source=dict(body="triangle", circles=[{}], open_paths=0))
    pins = [dict(term=t, net=n, xy=p) for t, n, p in zip(row["ports"], row["bindings"],
            ([0, -60], [0, 60], [-60, 0], [60, 0]))]
    device = dict(name="x1", pos=[0, 0], rot=0, mirror=False, pins=pins)
    wires = [[[-100, -100], [-100, 100]], [[-100, 100], [300, 100]]]
    drawing = dict(devices=[device], wires=[dict(segments=wires)])
    poly = lambda ps: '<polyline points="' + ' '.join(f'{2*x+220},{2*y+220}' for x, y in ps) + '"/>'
    xml = '<svg><g>' + ''.join(poly(w) for w in wires)
    xml += poly([[-40, -40], [40, 0], [-40, 40], [-40, -40]])
    xml += '<circle cx="310" cy="220" r="10"/>'
    for pin, end in zip(pins, ([0, -20], [0, 20], [-40, 0], [50, 0])):
        xml += poly([pin["xy"], end])
    xml += poly([[160, -40], [240, 0], [160, 40], [160, -40]]) + '</g></svg>'
    root = ET.fromstring(xml)
    observed = native_ink(drawing, root, row)
    assert observed["body_category_agrees"] and observed["bubble_count_agrees"]
    assert observed["terminal_sides_agree"] and all(p["attachment_meets_outline"] for p in observed["leads"])
    # Ordered binding preservation must not hide a swapped signal/rail
    # coordinate. A neighboring triangle cannot substitute for this body.
    pins[0]["xy"], pins[3]["xy"] = pins[3]["xy"], pins[0]["xy"]
    assert not native_ink(drawing, root, row)["terminal_sides_agree"]
    for bad in ('M 0 0 Q 1 1 2 2', 'M 0 0 L 1 garbage 2'):
        try:
            path_data(ET.fromstring('<path d="' + bad + '"/>'), source.glyph.IDENTITY)
        except ValueError:
            pass
        else:
            raise AssertionError("unsupported path admitted")


if __name__ == "__main__":
    main()
