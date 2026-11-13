#!/usr/bin/env python3
"""Flying-capacitor converter loops: topology, actual ink and native geometry.

Usage: converter_loops.py <examples-dir> <output.json> [--native <json-dir>]

The existing unique PMOS/coil/PMOS path has an input-bus end and an output
reservoir end. A second selected input-bus PMOS joins the lower flying-cap
node; the flying cap returns to the input-side coil node. A diode joins that
lower node to the negative side of a floating output capacitor. All six
path nets are distinct and nonrail. Exactly one such loop, one grounded
output capacitor, and one output-to-ground resistor divider qualify.
The observed diode has its anode on the floating output's negative net.

Selection reads only the deck, including existing model/rail rules. Every
studied lead is checked against actual SVG primitives; cached rotations
are not an oracle. Actual conductor ink verifies source wires before
continuity is measured. Names, exact exceptions and hashes are retained.
This is research, not an implemented group or evidence of routing success.
Related converter variants are correlated, including the numeric holdout.
"""
import argparse
import collections
import hashlib
import itertools
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from channel_bridges import read_cards, rail
from converter_terminals import close, glyphs
from cross_caps import actual_glyph, conductor_ink, crossings
from input_resistors import actual_resistor
from sampling_cells import channel, pin
import power_paths as power


def select(text):
    cards = read_cards(text)
    selected, coils = power.classify(text)
    groups = []
    pairs = {coil: [[n for n, r in selected.items() if r["selected"] and net in (r["nets"][0], r["nets"][2])]
                    for net in ends] for coil, ends in coils.items()}
    def other(name, net):
        w = cards[name]
        ends = [w[1], w[3] if name[0] == "m" else w[2]]
        return ends[1] if ends[0] == net else ends[0]
    for coil, ends in sorted(coils.items()):
        mains = pairs[coil]
        group = dict(coil=coil, endpoint_switches=mains, admitted=False)
        groups.append(group)
        if any(len(ns) != 1 for ns in mains) or mains[0] == mains[1]:
            group["reason"] = "ambiguous_main"
            continue
        if any(other != coil and all(len(ns) == 1 for ns in pair) and
               any(name in pair[0] + pair[1] for name in mains[0] + mains[1]) for other, pair in pairs.items()):
            group["reason"] = "ambiguous_coil"
            continue
        orientations = [(mains[i][0], mains[1-i][0], ends[i], ends[1-i]) for i in (0, 1)
                        if selected[mains[i][0]]["input_bus"] and selected[mains[1-i][0]]["reservoir"]]
        if len(orientations) != 1:
            group["reason"] = "no_unique_input_bus_to_reservoir_direction"
            continue
        incoming, outgoing, ia, ib = orientations[0]
        bus, out = other(incoming, ia), other(outgoing, ib)
        candidates = []
        for low, row in sorted(selected.items()):
            if low in (incoming, outgoing) or not row["input_bus"] or bus not in (row["nets"][0], row["nets"][2]):
                continue
            bottom = other(low, bus)
            for fly, wf in cards.items():
                if fly[0] != "c" or set(wf[1:3]) != {ia, bottom}:
                    continue
                for diode, wd in cards.items():
                    if diode[0] != "d" or bottom not in wd[1:3]:
                        continue
                    negative = other(diode, bottom)
                    nets = dict(bus=bus, input_near=ia, output_near=ib, output=out, bottom=bottom, negative=negative)
                    if len(set(nets.values())) != 6 or any(rail(n) for n in nets.values()):
                        continue
                    for cap, wc in cards.items():
                        if cap[0] == "c" and set(wc[1:3]) == {out, negative}:
                            candidates.append(dict(main=[incoming, outgoing], low=low, fly=fly, diode=diode,
                                                   output_cap=cap, nets=nets, diode_anode_negative=wd[1] == negative))
        group["loop_candidates"] = candidates
        if len(candidates) != 1:
            group["reason"] = "missing_or_ambiguous_loop"
            continue
        group.update(candidates[0])
        caps = [n for n, w in cards.items() if n[0] == "c" and out in w[1:3] and rail(other(n, out)) == "sink"]
        dividers = []
        for r1, w in cards.items():
            if r1[0] != "r" or out not in w[1:3]:
                continue
            feedback = other(r1, out)
            if rail(feedback) or feedback in group["nets"].values():
                continue
            for r2, w2 in cards.items():
                if r2[0] == "r" and feedback in w2[1:3] and rail(other(r2, feedback)) == "sink":
                    dividers.append(dict(resistors=[r1, r2], feedback=feedback, ground=other(r2, feedback)))
        group.update(grounded_candidates=caps, divider_candidates=dividers)
        if len(caps) != 1 or len(dividers) != 1:
            group["reason"] = "missing_or_ambiguous_output_branches"
        elif not group["diode_anode_negative"]:
            group["reason"] = "opposite_diode_polarity_unobserved"
        else:
            group.update(admitted=True, grounded_cap=caps[0], divider=dividers[0])
    owners = collections.Counter(name for row in groups if row["admitted"] for name in members(row))
    for row in groups:
        if row["admitted"] and any(owners[name] > 1 for name in members(row)):
            row.update(admitted=False, reason="overlapping_loop_groups")
    return groups


def members(row):
    return [row[k] for k in ("coil", "fly", "low", "diode", "output_cap", "grounded_cap")] + row["main"] + row["divider"]["resistors"]


def path_pin(device, net, native=False):
    """A channel terminal is selected by D/S, even when body shares its net."""
    name = device.get("card", device.get("name", "")).lower()
    if name[0] != "m":
        return pin(device, net, native)
    pairs = ([(p["term"].upper(), p["net"].lower(), p["xy"]) for p in device["pins"]] if native else
             [(p, device["nets"][p].lower(), device["terminals"][p]) for p in ("D", "S")])
    found = [xy for p, on, xy in pairs if p in ("D", "S") and on == net]
    if len(found) != 1:
        raise ValueError("missing or ambiguous channel terminal: " + name + ":" + net)
    return found[0]


def geometry(row, devices, native=False):
    n = row["nets"]
    def p(name, net):
        return path_pin(devices[name], net, native)
    def mid(a, b):
        return [(a[k] + b[k]) / 2 for k in (0, 1)]
    def between(x, a, b):
        return min(a, b) <= x <= max(a, b)
    incoming, outgoing = row["main"]
    low = channel(devices[row["low"]], native)
    first, last = [channel(devices[name], native) for name in row["main"]]
    mc, oc, lc = [mid(*pair[:2]) for pair in (first, last, low)]
    ci, co = [p(row["coil"], n[k]) for k in ("input_near", "output_near")]
    fa, fb = [p(row["fly"], n[k]) for k in ("input_near", "bottom")]
    oa, ob = [p(row["output_cap"], n[k]) for k in ("output", "negative")]
    da, db = [p(row["diode"], n[k]) for k in ("negative", "bottom")]
    dy, ly = min(da[1], db[1]), min(p[1] for p in low[:2])
    main_y = [p[1] for p in (*first[:2], ci, co, *last[:2])]
    direction = 1 if oc[0] > mc[0] else -1
    divider = row["divider"]
    r1, r2 = divider["resistors"]
    ra, rb = [p(r1, net) for net in (n["output"], divider["feedback"])]
    rc, rd = [p(r2, net) for net in (divider["feedback"], divider["ground"])]
    gp = p(row["grounded_cap"], n["output"])
    outer = p(outgoing, n["output"])
    return dict(main_same_row=min(main_y) == max(main_y),
                fly_vertical=fa[0] == fb[0], fly_input_above_bottom=fa[1] < fb[1],
                output_cap_vertical=oa[0] == ob[0], output_above_negative=oa[1] < ob[1],
                low_horizontal=low[0][1] == low[1][1], diode_horizontal=da[1] == db[1],
                low_below_main=ly > max(main_y), low_under_input_main=lc[0] == mc[0],
                fly_within_input_wire=between(fa[0], p(incoming, n["input_near"])[0], ci[0]),
                fly_body_below_main=fa[1] >= max(main_y), fly_above_low=fb[1] <= ly,
                low_before_fly=(fa[0] - p(row["low"], n["bottom"])[0]) * direction >= 0,
                diode_same_row_as_low=da[1] == db[1] == low[0][1] == low[1][1],
                diode_below_main=dy > max(main_y), diode_below_both_caps=dy >= max(fb[1], ob[1]),
                diode_between_caps=between(mid(da, db)[0], fa[0], oa[0]),
                diode_anode_toward_output=(da[0] - db[0]) * direction > 0,
                output_cap_outside=(oa[0] - outer[0]) * direction >= 0,
                output_cap_below_main=oa[1] >= max(main_y), low_gate_up=low[2][1] < ly,
                divider_vertical=ra[0] == rb[0] and rc[0] == rd[0],
                divider_same_column=ra[0] == rb[0] == rc[0] == rd[0],
                divider_beyond_output=(ra[0] - outer[0]) * direction >= 0,
                divider_between_main_and_outputcap=between(ra[0], outer[0], oa[0]),
                divider_down=ra[1] < rb[1] <= rc[1] < rd[1], divider_above_diode=rd[1] <= dy,
                grounded_cap_beyond_floating=(gp[0] - oa[0]) * direction > 0)


def actual(root, device, coils):
    if device["card"][0] == "r":
        return actual_resistor(root, device)
    if device["card"][0] != "l":
        return actual_glyph(root, device)
    matches = [s for s in coils if s["type"] == device["type"] and close(s["origin"], [device["x"], device["y"]])]
    if len(matches) != 1:
        raise ValueError("missing or ambiguous coil primitive")
    s = matches[0]
    points = {}
    for terminal, cached in device["terminals"].items():
        found = [p for p in s["endpoints"] if close(p, cached)]
        if not found:
            raise ValueError("cached coil terminal has no actual lead")
        points[terminal] = [round(v, 6) for v in found[0]]
    return dict(object=s["object"], terminals=points)


def wire_tree(segments, targets):
    """Wire endpoints and T-junctions form a graph; labels never join pieces."""
    points = {tuple(p) for segment in segments for p in segment} | {tuple(p) for p in targets}
    graph = collections.defaultdict(set)
    for a, b in segments:
        vx, vy = b[0] - a[0], b[1] - a[1]
        if vx == vy == 0:
            raise ValueError("zero-length conductor")
        on = [p for p in points if (p[0]-a[0])*vy == (p[1]-a[1])*vx and
              min(a[0], b[0]) <= p[0] <= max(a[0], b[0]) and min(a[1], b[1]) <= p[1] <= max(a[1], b[1])]
        on.sort(key=lambda p: (p[0]-a[0])*vx + (p[1]-a[1])*vy)
        for u, v in zip(on, on[1:]):
            graph[u].add(v)
            graph[v].add(u)
    parents = {tuple(targets[0]): None}
    queue = list(parents)
    for point in queue:
        for following in sorted(graph[point]):
            if following in parents:
                continue
            parents[following] = point
            queue.append(following)
    if any(tuple(p) not in parents for p in targets):
        return None
    tree = set()
    for target in targets[1:]:
        point = tuple(target)
        while parents[point] is not None:
            previous = parents[point]
            tree.add(tuple(sorted((point, previous))))
            point = previous
    return [[list(a), list(b)] for a, b in sorted(tree)]


def connections(row, drawing, devices, ink=None, native=False):
    n = row["nets"]
    incoming, outgoing = row["main"]
    r1, r2 = row["divider"]["resistors"]
    ends = dict(bus=[incoming, row["low"]], input_near=[incoming, row["coil"], row["fly"]],
                output_near=[row["coil"], outgoing], output=[outgoing, row["output_cap"], row["grounded_cap"], r1],
                bottom=[row["low"], row["fly"], row["diode"]], negative=[row["output_cap"], row["diode"]], feedback=[r1, r2])
    result = {}
    for role, names in ends.items():
        net = row["divider"]["feedback"] if role == "feedback" else n[role]
        targets = [dict(card=name, xy=path_pin(devices[name], net, native)) for name in names]
        segments = [[a, b] for w in drawing["wires"] if w["net"].lower() == net
                    for line in w["segments"] for a, b in zip(line, line[1:])]
        missing = []
        if ink is not None:
            for a, b in segments:
                if not any((close(a, c) and close(b, d)) or (close(a, d) and close(b, c)) for c, d in ink):
                    missing.append([a, b])
            # Detached custom-block pieces in the cache can have no SVG ink.
            # Retain every disagreement by name; none supplies connectivity.
            segments = [s for s in segments if s not in missing]
        tree = wire_tree(segments, [p["xy"] for p in targets])
        result[role] = dict(net=net, targets=targets, continuous=tree is not None,
                            diagonal_segments=sum(a[0] != b[0] and a[1] != b[1] for a, b in segments))
        if not native:
            result[role]["verified_ink_segments"] = segments
            result[role]["cache_segments_without_ink"] = missing
            result[role]["spanning_ink_segments"] = tree
    return result


def summarize(rows):
    result = dict(cells=len(rows), circuits=len({r["id"] for r in rows}),
                  holdout=[r["id"] + ":" + r["coil"] for r in rows if r["split"] == "holdout"])
    for field in ("source_geometry", "native_geometry"):
        values = [r for r in rows if field in r]
        result[field] = {key: dict(agree=sum(r[field][key] for r in values),
                                  exceptions=[r["id"] + ":" + r["coil"] for r in values if not r[field][key]])
                         for key in values[0][field]} if values else {}
    for field in ("source_connections", "native_connections"):
        values = [r for r in rows if field in r]
        result[field] = {key: dict(continuous=sum(r[field][key]["continuous"] for r in values),
                                   exceptions=[r["id"] + ":" + r[field][key]["net"] for r in values if not r[field][key]["continuous"]])
                         for key in values[0][field]} if values else {}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path)
    args = parser.parse_args()
    paths = sorted(args.examples.glob("*.human.json"))
    if not paths:
        raise ValueError("no paired source drawings")
    paired = hashlib.sha256()
    selected, excluded, hashes, native_hashes = [], [], {}, {}
    for hp in paths:
        ident = hp.name.removesuffix(".human.json")
        deck, svg = [hp.with_name(ident + suffix) for suffix in (".cir", ".svg")]
        for p in (hp, deck):
            data = p.read_bytes()
            paired.update(len(data).to_bytes(8, "little"))
            paired.update(data)
        rows = select(deck.read_text())
        if not rows:
            continue
        human = json.loads(hp.read_text())
        devices = {d["card"]: d for d in human["devices"]}
        accepted = [r for r in rows if r["admitted"]]
        if accepted:
            root = ET.parse(svg).getroot()
            coils, ink = list(glyphs(root)), conductor_ink(root)
        for p in (hp, deck, svg):
            hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
        native = None
        if args.native and accepted:
            p = args.native / (ident + ".json")
            native_hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
            native = json.loads(p.read_text())
            nd = {d["name"].lower(): d for d in native["devices"]}
        for row in rows:
            row.update(id=ident, split="holdout" if int(ident.rsplit("-", 1)[1]) % 5 == 0 else "discovery")
            if not row["admitted"]:
                excluded.append(row)
                continue
            names = members(row)
            row["source_glyphs"] = {n: actual(root, devices[n], coils) for n in sorted(names)}
            for name, verified in row["source_glyphs"].items():
                devices[name]["terminals"].update(verified["terminals"])
            row["source_geometry"] = geometry(row, devices)
            row["source_connections"] = connections(row, human, devices, ink)
            connections_ = row["source_connections"]
            row["source_local_crossings"] = ({a + "/" + b: crossings(connections_[a]["spanning_ink_segments"], connections_[b]["spanning_ink_segments"])
                                               for a, b in itertools.combinations(sorted(connections_), 2)}
                                              if all(v["continuous"] for v in connections_.values()) else None)
            if native:
                row["native_geometry"] = geometry(row, nd, True)
                row["native_connections"] = connections(row, native, nd, native=True)
            selected.append(row)
    output = dict(corpus=args.examples.name, paired_circuits=len(paths), paired_sha256=paired.hexdigest(), summary=summarize(selected),
                  verified_terminals=sum(len(g["terminals"]) for r in selected for g in r["source_glyphs"].values()),
                  selected=selected, excluded=excluded, source_sha256=hashes, native_sha256=native_hashes)
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(json.dumps({k: output[k] for k in ("corpus", "paired_circuits", "verified_terminals")} | {"cells": len(selected), "excluded": len(excluded)}))


if __name__ == "__main__":
    main()
