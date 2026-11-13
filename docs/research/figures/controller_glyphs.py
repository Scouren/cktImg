#!/usr/bin/env python3
"""Converter controller topology against actual SVG output leads.

Usage: controller_glyphs.py <examples-dir> <output.json> [--topology]

Selection reuses power_paths.py's netlist-only converter certificate. SVG
triangle apices and their outgoing leads supply direction independently of
cached terminal coordinates. For an opaque symbol, the named cached output
must coincide with a unique actual SVG lead before its direction is accepted.
Every source is hashed; ambiguous symbols or unsupported transforms fail.
"""

import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import power_paths as power

IDENTITY = (1., 0., 0., 1., 0., 0.)
# Named source exceptions to the upward habit, never selector conditions.
RIGHT_FACING = [f"ag-{n}:x1" for n in (1354, 1358, 1366, 1369, 1372, 1377, 1393, 1396)]


def numbers(text):
    return list(map(float, re.findall(r"[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?", text)))


def multiply(a, b):
    return (a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
            a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
            a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5])


def matrix(text):
    result = IDENTITY
    if re.sub(r"\w+\s*\([^)]*\)", "", text or "").strip(" ,\t\r\n"):
        raise ValueError(f"unsupported SVG transform: {text}")
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", text or ""):
        v = numbers(args)
        if name == "translate" and len(v) in (1, 2):
            transform = (1., 0., 0., 1., v[0], v[1] if len(v) > 1 else 0.)
        elif name == "scale" and len(v) in (1, 2):
            transform = (v[0], 0., 0., v[1] if len(v) > 1 else v[0], 0., 0.)
        elif name == "rotate" and len(v) in (1, 3):
            angle = math.radians(v[0])
            transform = (math.cos(angle), math.sin(angle), -math.sin(angle), math.cos(angle), 0., 0.)
            if len(v) == 3:
                transform = multiply(multiply((1., 0., 0., 1., v[1], v[2]), transform),
                                     (1., 0., 0., 1., -v[1], -v[2]))
        elif name == "matrix" and len(v) == 6:
            transform = tuple(v)
        else:
            raise ValueError(f"unsupported SVG transform: {name}({args})")
        result = multiply(result, transform)
    return result


def point(transform, p):
    return (round(transform[0] * p[0] + transform[2] * p[1] + transform[4], 6),
            round(transform[1] * p[0] + transform[3] * p[1] + transform[5], 6))


def walk(node, parent=IDENTITY):
    transform = multiply(parent, matrix(node.get("transform")))
    yield node, transform, parent
    for child in node:
        yield from walk(child, transform)


def close(a, b):
    # SVG outlines are serialized to 0.001 source units; this only absorbs
    # that rounding. It cannot excuse a cached pin displaced by 10 units.
    return abs(a[0] - b[0]) < .01 and abs(a[1] - b[1]) < .01


def direction(a, b):
    x, y = b[0] - a[0], b[1] - a[1]
    if abs(x) < .01 and abs(y) >= .01:
        return "down" if y > 0 else "up"
    if abs(y) < .01 and abs(x) >= .01:
        return "right" if x > 0 else "left"
    raise ValueError(f"noncardinal output lead: {a}, {b}")


def output_lead(group, parent, cached):
    bodies, lines = [], []
    for node, transform, _ in walk(group, parent):
        tag = node.tag.rsplit("}", 1)[-1]
        if tag == "path" and re.findall(r"[A-Za-z]", node.get("d", "")) == ["M", "L", "L", "Z"]:
            values = numbers(node.get("d"))
            if len(values) != 6:
                raise ValueError("triangle does not have three explicit vertices")
            bodies.append([point(transform, p) for p in zip(values[::2], values[1::2])])
        if tag == "line":
            lines.append([point(transform, (float(node.get("x1")), float(node.get("y1")))),
                          point(transform, (float(node.get("x2")), float(node.get("y2"))))])
    if len(bodies) == 1:
        body, tips = bodies[0], []
        for i in range(3):
            a, b = body[(i + 1) % 3], body[(i + 2) % 3]
            if abs(a[0] - b[0]) < .01 or abs(a[1] - b[1]) < .01:
                base = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
                tips.append((body[i], direction(base, body[i])))
        if len(tips) != 1:
            raise ValueError(f"ambiguous triangle apex: {tips}")
        apex, facing = tips[0]
        leads = []
        for a, b in lines:
            if close(a, apex) and direction(a, b) == facing:
                leads.append(b)
            if close(b, apex) and direction(b, a) == facing:
                leads.append(a)
        if len(leads) != 1:
            raise ValueError(f"ambiguous triangle output lead: {leads}")
        return body, apex, leads[0], facing
    if bodies:
        raise ValueError("multiple triangle bodies in one source symbol")
    leads = [(b, a) for a, b in lines if close(a, cached)]
    leads += [(a, b) for a, b in lines if close(b, cached)]
    if len(leads) != 1:
        raise ValueError(f"opaque output has no unique actual lead: {leads}")
    start, end = leads[0]
    return [], start, end, direction(start, end)


def select(text):
    """Unique main-path block/output tuples, using netlist topology only."""
    selected, coils = power.classify(text)
    groups, uses = [], collections.defaultdict(set)
    for coil, pair in coils.items():
        switches = [[name for name, row in selected.items() if row["selected"]
                     and net in (row["nets"][0], row["nets"][2])] for net in pair]
        if any(len(names) != 1 for names in switches) or switches[0] == switches[1]:
            continue  # This topology is outside the unique-series selector.
        mains = [names[0] for names in switches]
        groups.append((coil, mains))
        for main in mains:
            uses[main].add(coil)
    targets = collections.defaultdict(set)
    for coil, mains in groups:
        if any(len(uses[main]) != 1 for main in mains):
            continue
        for card, output, net in power.block_outputs(text):
            for main in mains:
                if selected[main]["nets"][1] == net:
                    targets[card].add((main, output))
    admitted = [(card, *next(iter(pairs))) for card, pairs in targets.items() if len(pairs) == 1]
    excluded = {card: sorted(pairs) for card, pairs in targets.items() if len(pairs) != 1}
    return sorted(admitted), excluded


def audit(human, svg, card, main, output):
    devices = {d["card"]: d for d in human["devices"]}
    device = devices[card]
    center = (device["x"], device["y"])
    candidates = []
    for group, _, parent in walk(ET.fromstring(svg)):
        if group.get("data-symbol-id") != device["type"]:
            continue
        if any(node.tag.endswith("g") and node.get("transform") and close(point(t, (0, 0)), center)
               for node, t, _ in walk(group, parent)):
            candidates.append((group, parent))
    if len(candidates) != 1:
        raise ValueError(f"{human['id']}:{card}: no unique SVG asset at authored origin")
    group, parent = candidates[0]
    cached = [p for name, p in device["terminals"].items() if name.lower() == output]
    if len(cached) != 1:
        raise ValueError(f"{human['id']}:{card}: ambiguous semantic output")
    body, apex, end, facing = output_lead(group, parent, cached[0])
    gate = devices[main]["terminals"]["G"]
    channel_y = sum(devices[main]["terminals"][pin][1] for pin in ("D", "S")) / 2
    return dict(id=human["id"], card=card, main=main, output=output,
                source_asset=device["type"], source_object=group.get("data-object-id"),
                origin=center, triangle=body, apex=apex, output_lead_end=end,
                svg_output_direction=facing, cached_output=cached[0],
                terminal_matches=close(end, cached[0]), cached_main_gate=gate,
                svg_output_below_channel=end[1] > channel_y,
                svg_output_at_or_below_gate=end[1] >= gate[1],
                cached_output_gate_same_x=abs(cached[0][0] - gate[0]) < .01,
                svg_output_gate_same_x=abs(end[0] - gate[0]) < .01)


def outer_graph(text, row):
    """Pin-labelled outer graph; hidden subcircuit implementations are excluded."""
    words = [line.split() for line in text.lower().splitlines() if line.split()]
    models = {w[1]: w[2] for w in words if w[0] == ".model"}
    ports = {w[1]: w[2:] for w in words if w[0] == ".subckt"}
    labels, edges = {}, collections.defaultdict(dict)
    for card, w in power.MOS.read_cards(text).items():
        kind = card[0]
        if kind == "m":
            family, pins, nets = models[w[5]], ["d", "g", "s", "b"], w[1:5]
        elif kind == "x":
            matched = [i for i, word in enumerate(w) if word in ports and i == len(ports[word]) + 1]
            if len(matched) != 1:
                raise ValueError(f"ambiguous graph subcircuit call: {w}")
            i = matched[0]
            family, pins, nets = w[i], ports[w[i]], w[1:i]
            if family in ("comp", "cmp", "comparator"):
                family = "comparator"
        elif kind in "rcl":
            family, pins, nets = kind, ["end", "end"], w[1:3]
        else:
            raise ValueError(f"unsupported outer-graph device: {w}")
        device = "device:" + card
        labels[device] = ("device", family, "main" if card == row["main"] else
                          "controller" if card == row["card"] else "")
        for pin, net in zip(pins, nets):
            node = "net:" + net
            labels[node] = ("net", power.MOS.rail(net) or "")
            edges[device].setdefault(node, []).append(pin)
            edges[node].setdefault(device, []).append(pin)
    return labels, {a: {b: tuple(sorted(pins)) for b, pins in adjacent.items()}
                    for a, adjacent in edges.items()}


def graph_colors(graph):
    labels, edges = graph
    digest = lambda value: hashlib.sha256(repr(value).encode()).hexdigest()
    colors = {node: digest(label) for node, label in labels.items()}
    # Refinement only prunes candidates. The final edge-by-edge certificate
    # below is exact and does not rely on hash equality as proof.
    for _ in range(20):
        colors = {node: digest((colors[node], sorted((pins, colors[other])
                  for other, pins in edges[node].items()))) for node in labels}
    return colors


def graph_mapping(first, second):
    left, le = first
    right, re = second
    if len(left) != len(right):
        return None
    lc, rc = graph_colors(first), graph_colors(second)
    if collections.Counter(lc.values()) != collections.Counter(rc.values()):
        return None
    choices = {a: [b for b in right if lc[a] == rc[b] and left[a] == right[b]] for a in left}
    order = sorted(left, key=lambda a: (len(choices[a]), -len(le[a]), a))
    found, used = {}, set()

    def visit(index):
        if index == len(order):
            return True
        a = order[index]
        for b in choices[a]:
            if b in used or any(le[a].get(c) != re[b].get(d) for c, d in found.items()):
                continue
            found[a] = b
            used.add(b)
            if visit(index + 1):
                return True
            used.remove(b)
            del found[a]
        return False

    if not visit(0):
        return None
    assert set(found) == set(left) and set(found.values()) == set(right)
    assert all(left[a] == right[b] and {found[c]: pins for c, pins in le[a].items()} == re[b]
               for a, b in found.items())
    return found


def topology_pairs(examples, rows):
    graphs = {row["id"]: outer_graph((examples / (row["id"] + ".cir")).read_text(), row)
              for row in rows}
    matches = []
    for right in rows:
        if right["svg_output_direction"] != "right":
            continue
        for up in rows:
            if up["svg_output_direction"] != "up":
                continue
            mapping = graph_mapping(graphs[right["id"]], graphs[up["id"]])
            if mapping is not None:
                matches.append(dict(right=right["id"], up=up["id"], mapping=mapping))
    return dict(scope="outer connectivity, MOS pin roles, rail roles and all declared block port names; "
                     "comp/cmp/comparator normalized; hidden bodies and component values excluded",
                pairs=matches, graphs=graphs)


def selfcheck():
    # Literal source geometry supplies direction; deliberately misplaced
    # cached pins cannot turn a right-facing triangle into an upward one.
    right = ET.fromstring('<g><path d="M -20 -20 L -20 20 L 20 0 Z"/>'
                          '<line x1="20" y1="0" x2="40" y2="0"/></g>')
    assert output_lead(right, IDENTITY, (0, -40))[2:] == ((40., 0.), "right")
    up = ET.fromstring('<g transform="translate(100 200) rotate(-90)">'
                       '<path d="M -20 -20 L -20 20 L 20 0 Z"/>'
                       '<line x1="20" y1="0" x2="40" y2="0"/></g>')
    assert output_lead(up, IDENTITY, (0, 0))[2:] == ((100., 160.), "up")
    box = ET.fromstring('<g><polygon points="-20,-20 20,-20 20,20 -20,20"/>'
                        '<line x1="0" y1="-20" x2="0" y2="-40"/></g>')
    assert output_lead(box, IDENTITY, (0, -40))[2:] == ((0., -40.), "up")
    try:
        output_lead(box, IDENTITY, (0, -50))
    except ValueError:
        pass
    else:
        raise AssertionError("a missing opaque output lead was silently accepted")
    left = ({"a": ("mos",), "b": ("net",)}, {"a": {"b": ("g",)}, "b": {"a": ("g",)}})
    right = ({"x": ("net",), "y": ("mos",)}, {"x": {"y": ("g",)}, "y": {"x": ("g",)}})
    assert graph_mapping(left, right) == {"a": "y", "b": "x"}
    right[1]["x"]["y"] = right[1]["y"]["x"] = ("d",)
    assert graph_mapping(left, right) is None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--topology", action="store_true", help="certify opposite-direction outer graphs")
    args = parser.parse_args()
    selfcheck()
    paths = sorted(args.examples.glob("*.human.json"))
    if not paths:
        parser.error("no paired source drawings")
    rows, excluded, ids = [], {}, []
    digest = hashlib.sha256()
    for hp in paths:
        cid = hp.name.removesuffix(".human.json")
        sources = {"human": hp, "deck": hp.with_name(cid + ".cir"), "svg": hp.with_name(cid + ".svg")}
        data, hashes = {}, {}
        for label, path in sources.items():
            content, name = path.read_bytes(), path.name.encode()
            digest.update(len(name).to_bytes(8, "big") + name + len(content).to_bytes(8, "big") + content)
            data[label] = content
            hashes[label] = hashlib.sha256(content).hexdigest()
        human = json.loads(data["human"])
        if human["id"] != cid:
            raise ValueError(f"source ID differs from filename: {cid}")
        ids.append(cid)
        candidates, ambiguous = select(data["deck"].decode())
        for card, pairs in ambiguous.items():
            excluded[cid + ":" + card] = pairs
        for card, target, output in candidates:
            row = audit(human, data["svg"], card, target, output)
            row["hashes"] = hashes
            rows.append(row)
    right = sorted(r["id"] + ":" + r["card"] for r in rows if r["svg_output_direction"] == "right")
    expected = sorted(RIGHT_FACING) if all(cid.startswith("ag-") for cid in ids) else []
    if right != expected:
        raise ValueError(f"right-facing source inventory changed: expected {expected}, observed {right}")
    unexpected = [r["id"] + ":" + r["card"] for r in rows if r["svg_output_direction"] not in ("up", "right")]
    if unexpected:
        raise ValueError(f"unreviewed source output directions: {unexpected}")
    result = dict(drawings=len(ids), ids=ids, corpus_sha256=digest.hexdigest(),
                  runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  selector_sha256=hashlib.sha256(Path(power.__file__).read_bytes()).hexdigest(),
                  summary=dict(instances=len(rows), triangles=sum(bool(r["triangle"]) for r in rows),
                               svg_directions=dict(collections.Counter(r["svg_output_direction"] for r in rows)),
                               terminal_matches=sum(r["terminal_matches"] for r in rows),
                               svg_output_below_channel=sum(r["svg_output_below_channel"] for r in rows),
                               svg_output_at_or_below_gate=sum(r["svg_output_at_or_below_gate"] for r in rows),
                               cached_output_gate_same_x=sum(r["cached_output_gate_same_x"] for r in rows),
                               svg_output_gate_same_x=sum(r["svg_output_gate_same_x"] for r in rows)),
                  upward_rule_mismatches=right, ambiguous_targets=excluded,
                  terminal_frame_mismatches=[r["id"] + ":" + r["card"] for r in rows if not r["terminal_matches"]],
                  selected=rows)
    if args.topology:
        result["outer_topology"] = topology_pairs(args.examples, rows)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in ("drawings", "corpus_sha256", "summary", "upward_rule_mismatches")}, indent=2))


if __name__ == "__main__":
    main()
