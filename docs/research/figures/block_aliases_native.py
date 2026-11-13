#!/usr/bin/env python3
"""Actual native glyphs for block_aliases.py's exact 24-instance source cohort.

Usage: block_aliases_native.py <source-report.json> <examples-dir>
       <native-dir> <output.json> [--bin cktimg-json] [--require-triangles]

The source report supplies independently observed bodies/signs and declared
port order. Native JSON supplies placement and electrical binding; actual SVG
ink supplies the drawn body, signs, leads and label sizes. Ordered wire paths
establish and verify the renderer's display transform. Each body must be
centered on its own placed device, and every named pin must end at one of
that body's external leads. Other symbols' triangles cannot satisfy a case.

Source cached-frame mismatches and missing cached source VSS coordinates remain
separate from native electrical preservation. This is no routing round trip
or proof of matching source geometry. The SVG adapter follows tests/svg.zig:
wires precede symbols, glyph text has a three-pixel baseline offset, and
refdes labels are outside the symbol-ink group. Unsupported structure fails.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import block_aliases as source

PIXEL_TOLERANCE = .11  # Native SVG coordinates are serialized to 0.1 pixels.


def tag(node):
    return node.tag.rsplit("}", 1)[-1]


def points(node):
    if tag(node) != "polyline":
        raise ValueError("expected a native SVG polyline")
    parsed = [tuple(map(float, word.split(","))) for word in node.get("points", "").split()]
    if len(parsed) < 2 or any(len(p) != 2 or not all(math.isfinite(v) for v in p) for p in parsed):
        raise ValueError("malformed native polyline")
    return parsed


def near(a, b, tolerance=PIXEL_TOLERANCE):
    return all(abs(x - y) < tolerance for x, y in zip(a, b))


def frame(drawing, root):
    """Fit one scale/translation from wires, then verify every wire vertex."""
    if any(n.get("transform") for n in root.iter()):
        raise ValueError("native SVG adapter does not accept nested transforms")
    groups = [g for g in root if tag(g) == "g" and any(tag(n) == "polyline" for n in g)]
    if len(groups) != 1:
        raise ValueError("native SVG has no unique symbol/wire ink group")
    ink = list(groups[0])
    if any(tag(n) not in ("polyline", "circle", "text") for n in ink):
        raise ValueError("unsupported native symbol primitive")
    wires = [segment for net in drawing["wires"] for segment in net["segments"]]
    if not wires or len(ink) <= len(wires):
        raise ValueError("native frame requires wire paths and symbol ink")
    pairs = []
    for expected, node in zip(wires, ink):
        actual = points(node)
        if len(expected) != len(actual):
            raise ValueError("native wire path structure differs between JSON and SVG")
        pairs.extend(zip(expected, actual))
    a, b = pairs[0]
    scales = []
    for axis in range(2):
        witnesses = [(p, q) for p, q in pairs if p[axis] != a[axis]]
        if not witnesses:
            raise ValueError("wire paths do not determine both display axes")
        p, q = max(witnesses, key=lambda pq: abs(pq[0][axis] - a[axis]))
        scales.append((q[axis] - b[axis]) / (p[axis] - a[axis]))
    if not scales[0] > 0 or abs(scales[0] - scales[1]) > 1e-5:
        raise ValueError("native SVG does not have one positive display scale")
    scale = sum(scales) / 2
    offset = [b[i] - scale * a[i] for i in range(2)]
    if not all(near([scale * p[i] + offset[i] for i in range(2)], q) for p, q in pairs):
        raise ValueError("native SVG wire coordinates disagree with its JSON")
    return round(scale, 9), [round(v, 6) for v in offset], ink[len(wires):]


def inverse(device, world):
    x, y = [world[i] - device["pos"][i] for i in range(2)]
    rot = device["rot"]
    if type(rot) is not int or rot not in range(4) or type(device["mirror"]) is not bool:
        raise ValueError("invalid native placement orientation")
    x, y = ((x, y), (y, -x), (-x, -y), (-y, x))[rot]
    return (round(-x if device["mirror"] else x, 6), round(y, 6))


def center(points_):
    return [(min(p[i] for p in points_) + max(p[i] for p in points_)) / 2 for i in range(2)]


def extent(points_):
    return [max(p[i] for p in points_) - min(p[i] for p in points_) for i in range(2)]


def edge_point(p, a, b, tolerance):
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    if length == 0:
        raise ValueError("degenerate native body edge")
    return (abs(dx * (p[1] - a[1]) - dy * (p[0] - a[0])) / length < tolerance
            and all(min(a[i], b[i]) - tolerance <= p[i] <= max(a[i], b[i]) + tolerance for i in range(2)))


def location(p, body, tolerance):
    edges = list(zip(body, body[1:] + body[:1]))
    if any(edge_point(p, a, b, tolerance) for a, b in edges):
        return "boundary"
    cross = [(b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) for a, b in edges]
    return "inside" if all(v > 0 for v in cross) or all(v < 0 for v in cross) else "outside"


def shape(body, tolerance):
    if len(body) == 3:
        if abs((body[1][0] - body[0][0]) * (body[2][1] - body[0][1])
               - (body[1][1] - body[0][1]) * (body[2][0] - body[0][0])) <= tolerance:
            raise ValueError("degenerate native triangle")
        return "triangle"
    if len(body) == 4 and all(abs(a[0] - b[0]) < tolerance or abs(a[1] - b[1]) < tolerance
                              for a, b in zip(body, body[1:] + body[:1])):
        return "box"
    raise ValueError("unsupported native body outline")


def inspect(drawing, root, row):
    devices = [d for d in drawing["devices"] if d["name"] == row["card"]]
    if len(devices) != 1:
        raise ValueError("no unique named native instance")
    device = devices[0]
    scale, offset, ink = frame(drawing, root)
    tolerance = PIXEL_TOLERANCE / scale
    world = lambda p: [(p[i] - offset[i]) / scale for i in range(2)]
    local = lambda p: inverse(device, world(p))
    at = [scale * device["pos"][i] + offset[i] for i in range(2)]
    bodies = []
    for index, node in enumerate(ink):
        if tag(node) != "polyline":
            continue
        ps = points(node)
        if len(ps) >= 4 and near(ps[0], ps[-1]) and near(center(ps[:-1]), at):
            bodies.append((index, ps[:-1]))
    if len(bodies) != 1:
        raise ValueError("no unique native body centered on the named placement")
    body_index, body_pixels = bodies[0]
    body = [local(p) for p in body_pixels]
    kind = shape(body, tolerance)
    leads = []
    for pin in device["pins"]:
        target = inverse(device, pin["xy"])
        matches = []
        for index, node in enumerate(ink):
            if tag(node) != "polyline":
                continue
            ps = [local(p) for p in points(node)]
            if len(ps) != 2:
                continue
            for endpoint, attachment in (ps, ps[::-1]):
                if near(endpoint, target, tolerance) and location(attachment, body, tolerance) == "boundary":
                    matches.append(dict(index=index, endpoint=endpoint, attachment=attachment))
        if len(matches) != 1 or location(target, body, tolerance) != "outside":
            raise ValueError(f"pin {pin['term']} has no unique own-body external lead")
        leads.append(dict(term=pin["term"], net=pin["net"], **matches[0]))
    if len({lead["index"] for lead in leads}) != len(leads):
        raise ValueError("two declared pins alias one native SVG lead")
    texts = []
    for index, node in enumerate(ink):
        if tag(node) != "text" or node.get("text-anchor") != "middle":
            continue
        pixel = [float(node.get("x")), float(node.get("y")) - 3]
        p = local(pixel)
        if location(p, body, tolerance) == "inside":
            texts.append(dict(index=index, text="".join(node.itertext()), at=p,
                              anchor_pixels=pixel, font_pixels=float(node.get("font-size"))))
    signs = [t for t in texts if t["text"] in ("+", "-")]
    interior_polylines = []
    for index, node in enumerate(ink):
        if tag(node) == "polyline":
            ps = [local(p) for p in points(node)]
            if all(location(p, body, tolerance) == "inside" for p in ps):
                interior_polylines.append(dict(index=index, points=ps))
    expected = sorted("+" if mark == "positive" else "-" for mark in row["expected_marks"])
    sign_bindings, signal_geometry = {}, {}
    if kind == "triangle":
        bases = [(a, b) for a, b in zip(body, body[1:] + body[:1])
                 if abs(a[0] - b[0]) < tolerance or abs(a[1] - b[1]) < tolerance]
        if len(bases) != 1:
            raise ValueError("native triangle has no unique cardinal input base")
        a, b = bases[0]
        axis = 0 if abs(a[1] - b[1]) < tolerance else 1
        apex = next(p for p in body if p != a and p != b)
        midpoint = [(a[i] + b[i]) / 2 for i in range(2)]
        for port in row["ports"]:
            role = source.role(port)
            if role not in source.INPUTS | {"output"}:
                continue
            lead = next(l for l in leads if l["term"] == port)
            if role == "output":
                delta = [lead["endpoint"][i] - apex[i] for i in range(2)]
                signal_geometry[port] = (near(lead["attachment"], apex, tolerance)
                                         and abs(delta[axis]) < tolerance
                                         and delta[1-axis] * (apex[1-axis] - midpoint[1-axis]) > 0)
                continue
            signal_geometry[port] = edge_point(lead["attachment"], a, b, tolerance)
            if role == "unsigned":
                continue
            wanted = "+" if role == "positive" else "-"
            sign_bindings[port] = (signal_geometry[port]
                                  and sum(t["text"] == wanted and abs(t["at"][axis] - lead["endpoint"][axis]) < tolerance
                                          for t in signs) == 1)
    refdes = [n for n in root if tag(n) == "text" and "".join(n.itertext()) == row["card"]]
    if len(refdes) != 1:
        raise ValueError("no unique native reference label")
    refdes = refdes[0]
    ordered_ports = [p["term"] for p in device["pins"]]
    ordered_nets = [p["net"] for p in device["pins"]]
    if ordered_ports != row["ports"] or ordered_nets != row["bindings"]:
        raise ValueError("native ordered electrical port bindings changed")
    return dict(shape=kind, shape_agrees=kind == row["shape"],
                signs_agree=kind == "triangle" and sorted(t["text"] for t in signs) == expected and all(sign_bindings.values()),
                signal_geometry_agrees=kind == "triangle" and all(signal_geometry.values()),
                signal_geometry=signal_geometry,
                sign_bindings=sign_bindings, signs=signs, body_local=body, body_pixels=body_pixels,
                body_size_units=extent(body), body_size_pixels=extent(body_pixels),
                display_scale=scale, display_offset=offset, viewport=source.glyph.numbers(root.get("viewBox")),
                body_ink_index=body_index, leads=leads, interior_text=texts,
                interior_polylines=interior_polylines,
                interior_port_labels=[p for p in row["ports"] if any(t["text"] == p for t in texts)],
                interior_family_label=any(t["text"] == row.get("family") for t in texts),
                refdes=dict(text=row["card"], at_pixels=[float(refdes.get("x")), float(refdes.get("y"))],
                            font_pixels=float(refdes.get("font-size"))),
                native_class=device["class"], placement={k: device[k] for k in ("pos", "rot", "mirror")},
                ordered_ports=ordered_ports, ordered_bindings=ordered_nets,
                ports_preserved=True, bindings_preserved=True, every_pin_has_svg_lead=True,
                source_missing_cached_terminal_geometry=row["missing_source_ports"],
                source_signal_frame_mismatches=row["signal_frame_mismatches"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_report", type=Path)
    parser.add_argument("examples", type=Path)
    parser.add_argument("native", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--bin", type=Path)
    parser.add_argument("--require-triangles", action="store_true")
    args = parser.parse_args()
    selfcheck()
    report = json.loads(args.source_report.read_text())
    inventory = json.loads(Path(__file__).with_name("block_aliases_cases.json").read_text())["corpora"][args.examples.name]
    rows = report["selected"]
    names = sorted(r["id"] + ":" + r["card"] for r in rows)
    source.check_inventory(names, sorted(n for f in source.FAMILIES for n in inventory["complete_contracts"][f]), "native selected names")
    source.check_inventory({r["id"] + ":" + r["card"]: r["signal_frame_mismatches"] for r in rows if r["signal_frame_mismatches"]},
                           inventory["selected_signal_frame_mismatches"], "retained source signal-frame mismatches")
    if report["corpus"] != args.examples.name:
        raise ValueError("source report belongs to another corpus")
    for name, expected_hash in report["audit_sha256"].items():
        if hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest() != expected_hash:
            raise ValueError(f"source audit dependency changed: {name}; rerun the source audit")
    for row in rows:
        cid, card = row["id"], row["card"]
        for suffix in (".cir", ".svg", ".human.json"):
            path = args.examples / (cid + suffix)
            if hashlib.sha256(path.read_bytes()).hexdigest() != report["source_sha256"][path.name]:
                raise ValueError(f"{cid}: source {suffix} changed since its audit")
        deck = args.examples / (cid + ".cir")
        contracts = [r for r in source.scan(deck.read_text(), cid) if r["card"] == card and r["admitted"]]
        if len(contracts) != 1 or any(contracts[0][k] != row[k] for k in ("family", "ports", "bindings")):
            raise ValueError(f"{cid}:{card}: source contract is stale")
        if row["shape"] != "triangle" or not row["marks_agree"]:
            raise ValueError(f"{cid}:{card}: source no longer supports the expected triangle/sign contract")
    if args.bin:
        args.native.mkdir(parents=True, exist_ok=True)
        for cid in sorted({r["id"] for r in rows}):
            run = subprocess.run([str(args.bin.resolve()), "--svg", str(args.native / (cid + ".svg")),
                                  str(args.examples / (cid + ".cir")), str(args.native / (cid + ".json"))],
                                 capture_output=True, text=True, timeout=30)
            if run.returncode:
                raise ValueError(f"{cid}: native renderer failed: {run.stderr}")
    selected = []
    for row in rows:
        cid, card = row["id"], row["card"]
        drawing, svg = args.native / (cid + ".json"), args.native / (cid + ".svg")
        try:
            native = inspect(json.loads(drawing.read_text()), ET.parse(svg).getroot(), row)
        except ValueError as error:
            raise ValueError(f"{cid}:{card}: {error}") from error
        selected.append(dict(id=cid, card=card, family=row["family"], native=native,
                             json_sha256=hashlib.sha256(drawing.read_bytes()).hexdigest(),
                             svg_sha256=hashlib.sha256(svg.read_bytes()).hexdigest()))
    failures = [r["id"] + ":" + r["card"] for r in selected
                if not all(r["native"][k] for k in ("shape_agrees", "signs_agree", "signal_geometry_agrees"))]
    summary = {k: sum(r["native"][k] for r in selected)
               for k in ("shape_agrees", "signs_agree", "signal_geometry_agrees", "ports_preserved", "bindings_preserved", "every_pin_has_svg_lead")}
    summary.update(instances=len(selected), triangles=sum(r["native"]["shape"] == "triangle" for r in selected),
                   boxes=sum(r["native"]["shape"] == "box" for r in selected),
                   ordered_pins=sum(len(r["native"]["ordered_ports"]) for r in selected))
    result = dict(summary=summary, selected=selected, shape_or_sign_failures=failures,
                  source_report_sha256=hashlib.sha256(args.source_report.read_bytes()).hexdigest(),
                  source_corpus_sha256=report["corpus_sha256"],
                  renderer_sha256=hashlib.sha256(args.bin.read_bytes()).hexdigest() if args.bin else None,
                  audit_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  source_audit_sha256=hashlib.sha256(Path(source.__file__).read_bytes()).hexdigest(),
                  pixel_tolerance=PIXEL_TOLERANCE,
                  limits="Own-body shape, sign and ordered-binding audit; no claim of full glyph-stroke parity, source/native endpoint geometry, routing equivalence or full text bounding-box/overlap parity. Extra interior polylines are recorded separately. Missing cached source terminals do not establish absent source SVG leads. Font sizes and anchors are observed SVG attributes.")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, sort_keys=True, indent=2))
    if args.require_triangles and failures:
        raise ValueError("native shape/sign/signal-role mismatch: " + ", ".join(failures))


def selfcheck():
    device = dict(pos=[100, 200], rot=1, mirror=True)
    assert inverse(device, [80, 190]) == (10, 20)
    assert shape([[-40, -40], [40, 0], [-40, 40]], .01) == "triangle"
    assert shape([[-30, -40], [30, -40], [30, 40], [-30, 40]], .01) == "box"
    assert location([30, 0], [[-30, -40], [30, -40], [30, 40], [-30, 40]], .01) == "boundary"
    assert location([31, 0], [[-30, -40], [30, -40], [30, 40], [-30, 40]], .01) == "outside"
    # Literal two-symbol drawing: the neighboring triangle cannot make the
    # target box pass. Then replace just the target with an independently
    # specified signed triangle and detect a swapped electrical port order.
    row = dict(card="x1", ports=["inn", "inp", "out"], bindings=["n", "p", "o"],
               expected_marks=["negative", "positive"], shape="triangle",
               missing_source_ports=[], signal_frame_mismatches=[])
    for triangular in (False, True):
        ps = [[-40, -40], [40, 0], [-40, 40]] if triangular else [[-30, -40], [30, -40], [30, 40], [-30, 40]]
        inputs, output = (-60, 60) if triangular else (-40, 40)
        pins = [dict(term=t, net=n, xy=p) for t, n, p in zip(row["ports"], row["bindings"],
                ([inputs, -20], [inputs, 20], [output, 0]))]
        device = dict(name="x1", pos=[0, 0], rot=0, mirror=False, pins=pins, **{"class": "block:literal"})
        wires = [[[-100, -100], [-100, 100]], [[-100, 100], [300, 100]]]
        drawing = dict(devices=[device], wires=[dict(segments=wires)])
        xml = '<svg viewBox="0 0 800 500"><g>'
        poly = lambda points_: '<polyline points="' + ' '.join(f'{2*x+220},{2*y+220}' for x, y in points_) + '"/>'
        xml += ''.join(poly(w) for w in wires) + poly(ps + ps[:1])
        edge = 40 if triangular else 30
        for pin in pins:
            x, y = pin["xy"]
            xml += poly([[x, y], [-edge if x < 0 else edge, y]])
        if triangular:
            xml += '<text x="160" y="183" text-anchor="middle" font-size="11">-</text>'
            xml += '<text x="160" y="263" text-anchor="middle" font-size="11">+</text>'
        xml += poly([[160, -40], [240, 0], [160, 40], [160, -40]])
        xml += '</g><text x="310" y="210" font-size="11">x1</text></svg>'
        root = ET.fromstring(xml)
        actual = inspect(drawing, root, row)
        assert actual["shape_agrees"] == triangular and actual["signs_agree"] == triangular
        assert actual["signal_geometry_agrees"] == triangular
        assert actual["body_size_units"] == ([80, 80] if triangular else [60, 80])
        assert actual["ports_preserved"] and actual["every_pin_has_svg_lead"]
        if triangular:
            # Correct term/net order alone cannot prove that OUT reaches
            # the apex. Swap OUT with an existing supply lead while the
            # SVG, signed inputs and ordered electrical bindings stay put.
            row4 = dict(row, ports=row["ports"] + ["vdd"], bindings=row["bindings"] + ["vdd"])
            device["pins"] = pins + [dict(term="vdd", net="vdd", xy=[0, -60])]
            root[0].append(ET.fromstring(poly([[0, -60], [0, -20]])))
            assert inspect(drawing, root, row4)["signal_geometry_agrees"]
            pins[2]["xy"], device["pins"][3]["xy"] = device["pins"][3]["xy"], pins[2]["xy"]
            wrong = inspect(drawing, root, row4)
            assert wrong["shape_agrees"] and wrong["signs_agree"] and wrong["ports_preserved"]
            assert not wrong["signal_geometry_agrees"] and not wrong["signal_geometry"]["out"]
            pins[2]["xy"] = [output, 0]
        device["pins"] = list(reversed(pins))
        try:
            inspect(drawing, root, row)
        except ValueError as error:
            assert "ordered electrical port bindings changed" in str(error)
        else:
            raise AssertionError("native audit accepted a changed port order")


if __name__ == "__main__":
    main()
