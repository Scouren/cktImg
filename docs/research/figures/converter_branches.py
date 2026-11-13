#!/usr/bin/env python3
"""Audited converter loops -> exact branch orders and bounded hypotheses.

Usage: converter_branches.py <examples-dir> <output.json> --native <json-dir>
       [--loops converter_loops_cases.json]

The existing loop inventory supplies topology and all three branch glyph
proofs. Its source hashes must still match. Only remote feedback terminals
need another SVG audit. Names identify evidence, never select a preference.
Graph equivalence preserves pin roles and values, and returns exact maps;
hash refinement only reduces the search. This is research, not an engine
rule or an assertion that the common order explains every drawing.
"""
import argparse
import collections
import hashlib
import itertools
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from channel_bridges import read_cards, rail
from controller_glyphs import graph_colors, graph_mapping
from converter_loops import path_pin, wire_tree
from cross_caps import actual_glyph


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def order(xs):
    if len(set(xs.values())) != len(xs):
        raise ValueError("branch columns are not distinct")
    return "-".join(sorted(xs, key=xs.get))


def branches(row, devices):
    """References the existing actual-ink proof, not cached orientations."""
    names = dict(R=row["divider"]["resistors"][0], CO=row["output_cap"], CG=row["grounded_cap"])
    result = {}
    for role, name in names.items():
        device = devices[name]
        proof = row["source_glyphs"][name]
        if proof["terminals"] != device["terminals"]:
            raise ValueError(f"{row['id']}:{name}: stale lead certificate")
        output_pins = [p for p, net in device["nets"].items() if net.lower() == row["nets"]["output"]]
        if len(output_pins) != 1 or len({p[0] for p in proof["terminals"].values()}) != 1:
            raise ValueError(f"{row['id']}:{name}: missing vertical branch proof")
        result[role] = dict(card=name, output_pin=output_pins[0], x=proof["terminals"][output_pins[0]][0],
                            proof=f"analoggenie.selected[id={row['id']}].source_glyphs[{name}]")
    return result


def remote_feedback(root, row, devices, xs):
    feedback = row["divider"]["feedback"]
    start = path_pin(devices[row["divider"]["resistors"][0]], feedback)
    segments = row["source_connections"]["feedback"]["verified_ink_segments"]
    result = []
    for name, device in sorted(devices.items()):
        if name in row["divider"]["resistors"]:
            continue
        pins = [p for p, net in device["nets"].items() if net.lower() == feedback]
        if not pins:
            continue
        studied = {**device, "terminals": {p: device["terminals"][p] for p in pins}} if name[0] == "x" else device
        try:
            verified = actual_glyph(root, studied)
        except ValueError as error:
            result.extend(dict(card=name, pin=p, cached_xy=device["terminals"][p], unverified=str(error)) for p in pins)
            continue
        for pin in pins:
            xy = verified["terminals"][pin]
            path = wire_tree(segments, [start, xy])
            distance = min(abs(x - xy[0]) for x in xs.values())
            result.append(dict(card=name, pin=pin, xy=xy, glyph=verified, continuous=path is not None,
                               path=path, side="left" if xy[0] < xs["R"] else "right" if xy[0] > xs["R"] else "aligned",
                               nearest=sorted(k for k, x in xs.items() if abs(x - xy[0]) == distance)))
    return result


def features(text, row, remotes):
    cards = read_cards(text)
    models = {w[1]: w[2].split("(")[0] for w in (s.lower().split() for s in text.splitlines()) if w and w[0] == ".model"}
    selected = [row["main"][0], row["low"], row["main"][1]]
    bulk = []
    for name in selected:
        w = cards[name]
        bulk.append("source" if w[4] == w[3] else "drain" if w[4] == w[1] else rail(w[4]) or "other")
    negative = row["nets"]["negative"]
    outside = []
    for name, w in sorted(cards.items()):
        if name in (row["output_cap"], row["diode"]):
            continue
        ends = w[1:5] if name[0] == "m" else w[1:3] if name[0] in "rcld" else w[1:-1]
        outside.extend(dict(card=name, pin_index=i) for i, net in enumerate(ends) if net == negative)
    return dict(bulk=bulk, blocks=sum(n[0] == "x" for n in cards), negative_remotes=outside,
                feedback_kinds=sorted(models[cards[r["card"]][5]] if r["card"][0] == "m" else "block" for r in remotes))


def graph(text, row, flatten=False):
    """Name-free graph labels plus named terminal rows for a reviewable map."""
    lines = [s.lower().split() for s in text.splitlines() if s.split() and not s.lstrip().startswith("*")]
    models = {w[1]: w[2].split("(")[0] for w in lines if w[0] == ".model"}
    subs, current = {}, None
    for w in lines:
        if w[0] == ".subckt":
            current = w[1]
            subs[current] = (w[2:], [])
        elif w[0] == ".ends":
            current = None
        elif current and not w[0].startswith("."):
            subs[current][1].append(w)
    ports, body = subs["dut"]
    selected = {row[k]: k for k in ("coil", "fly", "low", "diode", "output_cap", "grounded_cap")}
    selected.update(zip(row["main"], ("incoming", "outgoing")))
    selected.update(zip(row["divider"]["resistors"], ("upper_r", "lower_r")))
    selected_nets = {net: role for role, net in row["nets"].items()}
    selected_nets[row["divider"]["feedback"]] = "feedback"
    labels, edges, terminals = {}, collections.defaultdict(dict), {}

    def add(cards, bindings, prefix, depth=0):
        if depth >= 20:
            raise ValueError("recursive subcircuit graph exceeds scope")
        for w in cards:
            card, kind = w[0], w[0][0]
            if kind == "x":
                matches = [i for i, word in enumerate(w) if word in subs and i == len(subs[word][0]) + 1]
                if len(matches) != 1:
                    raise ValueError(f"ambiguous block call: {w}")
                i = matches[0]
                declared, inner = subs[w[i]]
                names, family, attributes = w[1:i], ("block", len(declared)), ()
                roles = [str(i) for i in range(len(names))]
            elif kind == "m":
                names, roles, declared = w[1:5], ["d", "g", "s", "b"], ["D", "G", "S", "B"]
                family, attributes = ("mos", models[w[5]]), tuple(w[6:])
            elif kind in "rcld":
                names = w[1:3]
                roles = ["a", "k"] if kind == "d" else ["end", "end"]
                declared = ["A", "K"] if kind == "d" else ["1", "2"]
                family = ("diode", models[w[3]]) if kind == "d" else (kind,)
                attributes = tuple(w[4:] if kind == "d" else w[3:])
            else:
                raise ValueError(f"unsupported graph device: {w}")
            nets = [bindings.get(n, n if n == "0" else prefix + n) for n in names]
            if kind == "x" and flatten:
                add(inner, dict(zip(declared, nets)), prefix + card + "/", depth + 1)
                continue
            device = "device:" + prefix + card
            labels[device] = ("device", family, selected.get(card, "") if not prefix else "", attributes)
            terminals[device] = [dict(index=i, pin=p, role=r, net=n) for i, (p, r, n) in enumerate(zip(declared, roles, nets))]
            for pin, net in zip(roles, nets):
                node = "net:" + net
                labels[node] = ("net", rail(net) or "", net in ports, selected_nets.get(net, ""))
                edges[device].setdefault(node, []).append(pin)
                edges[node].setdefault(device, []).append(pin)
    add(body, {n: n for n in ports}, "")
    return (labels, {a: {b: tuple(sorted(pins)) for b, pins in adjacent.items()} for a, adjacent in edges.items()}), terminals


def pin_map(left, right, mapping):
    """Every physical pin index gets a corresponding right pin and net."""
    result = []
    for device, pins in sorted(left.items()):
        target = mapping[device]
        remaining = list(right[target])
        mapped = []
        for pin in pins:
            net = mapping["net:" + pin["net"]].removeprefix("net:")
            match = next((p for p in remaining if p["role"] == pin["role"] and p["net"] == net), None)
            if match is None:
                raise ValueError("graph certificate does not cover terminal")
            remaining.remove(match)
            mapped.append(dict(left=pin, right=match))
        if remaining:
            raise ValueError("graph certificate leaves unmatched terminals")
        result.append(dict(left=device.removeprefix("device:"), right=target.removeprefix("device:"), pins=mapped))
    return result


def equivalence(examples, rows, orders):
    modes = {}
    for mode in ("outer", "flattened"):
        graphs = {r["id"]: graph((examples / (r["id"] + ".cir")).read_text(), r, mode == "flattened") for r in rows}
        buckets = collections.defaultdict(list)
        for name, (g, _) in graphs.items():
            buckets[tuple(sorted(collections.Counter(graph_colors(g).values()).items()))].append(name)
        classes = []
        for candidates in buckets.values():
            groups = []
            for name in candidates:
                for group in groups:
                    if graph_mapping(graphs[group[0]][0], graphs[name][0]) is not None:
                        group.append(name)
                        break
                else:
                    groups.append([name])
            classes.extend(groups)
        pairs = []
        for group in classes:
            for left, right in itertools.combinations(group, 2):
                if orders[left] == orders[right]:
                    continue
                mapping = graph_mapping(graphs[left][0], graphs[right][0])
                pairs.append(dict(left=left, right=right, left_order=orders[left], right_order=orders[right], mapping=mapping,
                                  pin_map=pin_map(graphs[left][1], graphs[right][1], mapping)))
        modes[mode] = dict(classes=sorted(classes), cross_order_pairs=pairs)
    return modes


def summarize(rows):
    groups = collections.defaultdict(list)
    matrix = collections.defaultdict(list)
    features = {key: collections.defaultdict(list) for key in ("bulk", "blocks", "feedback_kinds", "negative_remotes", "remote_side", "nearest")}
    for row in rows:
        ident, source = row["id"], row["source_order"]
        groups[source].append(ident)
        matrix[source + " -> " + row["native_order"]].append(ident)
        for key, groups_by_feature in features.items():
            if key in ("remote_side", "nearest"):
                value = [r.get("side" if key == "remote_side" else "nearest", "unknown") for r in row["feedback"]]
            else:
                value = row["features"][key]
                if key == "negative_remotes":
                    value = bool(value)
            groups_by_feature[source + " | " + json.dumps(value, sort_keys=True)].append(ident)
    return dict(orders=dict(groups), source_to_native=dict(matrix), feature_names={k: dict(v) for k, v in features.items()},
                exact_native_agreement=[r["id"] for r in rows if r["source_order"] == r["native_order"]],
                divider_between_agreement=[r["id"] for r in rows if r["source_between"] == r["native_between"]],
                unverified_feedback=[r["id"] for r in rows if any("unverified" in f for f in r["feedback"])],
                all_remote_feedback_continuous=[r["id"] for r in rows if r["feedback"] and all(f.get("continuous") for f in r["feedback"])])


def method_checks():
    assert order(dict(R=2, CO=4, CG=8)) == "R-CO-CG"
    assert order(dict(R=8, CO=4, CG=2)) == "CG-CO-R"
    try:
        order(dict(R=2, CO=2, CG=8))
    except ValueError:
        pass
    else:
        raise AssertionError("tied columns were reported as ordered")
    first = ({"m": ("mos",), "a": ("net",), "b": ("net",)},
             {"m": {"a": ("d", "s"), "b": ("g",)}, "a": {"m": ("d", "s")}, "b": {"m": ("g",)}})
    second = (first[0], {"m": {"a": ("d", "g"), "b": ("s",)}, "a": {"m": ("d", "g")}, "b": {"m": ("s",)}})
    assert graph_mapping(first, first) is not None
    assert graph_mapping(first, second) is None
    return ["literal_branch_orders", "tied_columns_rejected", "identity_graph_certificate", "gate_channel_role_mutation_rejected"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--loops", type=Path, default=Path(__file__).with_name("converter_loops_cases.json"))
    args = parser.parse_args()
    loops = json.loads(args.loops.read_text())
    corpus = loops["analoggenie"]
    rows, source_hashes, native_hashes = [], {}, {}
    for row in corpus["selected"]:
        ident = row["id"]
        for suffix in (".cir", ".svg", ".human.json"):
            name = ident + suffix
            source_hashes[name] = sha(args.examples / name)
            if source_hashes[name] != corpus["source_sha256"][name]:
                raise ValueError("stale source certificate: " + name)
        text = (args.examples / (ident + ".cir")).read_text()
        human = json.loads((args.examples / (ident + ".human.json")).read_text())
        devices = {d["card"]: d for d in human["devices"]}
        branch = branches(row, devices)
        xs = {role: b["x"] for role, b in branch.items()}
        remotes = remote_feedback(ET.parse(args.examples / (ident + ".svg")).getroot(), row, devices, xs)
        native_path = args.native / (ident + ".json")
        native_hashes[native_path.name] = sha(native_path)
        native = {d["name"].lower(): d for d in json.loads(native_path.read_text())["devices"]}
        nx = {role: path_pin(native[b["card"]], row["nets"]["output"], True)[0] for role, b in branch.items()}
        outer = path_pin(native[row["main"][1]], row["nets"]["output"], True)[0]
        rows.append(dict(id=ident, branches=branch, source_order=order(xs), native_order=order(nx), native_x=nx,
                         source_between=row["source_geometry"]["divider_between_main_and_outputcap"],
                         native_between=min(outer, nx["CO"]) <= nx["R"] <= max(outer, nx["CO"]),
                         feedback=remotes, features=features(text, row, remotes)))
    result = dict(study="converter output branch order", status="observational source evidence; native snapshot measured separately",
                  loop_inventory=dict(file=args.loops.name, sha256=sha(args.loops), selected=[r["id"] for r in corpus["selected"]],
                                      branch_glyphs=3 * len(rows), branch_leads=6 * len(rows),
                                      ams_selected=[r["id"] for r in loops["amsnet"]["selected"]]),
                  native_snapshot=args.native.name, source_sha256=source_hashes, native_sha256=native_hashes,
                  method_checks=method_checks(), rows=rows, summary=summarize(rows),
                  topology=equivalence(args.examples, corpus["selected"], {r["id"]: r["source_order"] for r in rows}))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(drawings=len(rows), orders={k: len(v) for k, v in result["summary"]["orders"].items()},
                          exact_native_agreement=len(result["summary"]["exact_native_agreement"]),
                          divider_between_agreement=len(result["summary"]["divider_between_agreement"]),
                          unverified_feedback=len(result["summary"]["unverified_feedback"]),
                          topology_classes={k: len(v["classes"]) for k, v in result["topology"].items()}), indent=2))


if __name__ == "__main__":
    main()
