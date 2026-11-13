#!/usr/bin/env python3
"""Sampling cells: netlist-only selection and actual SVG endpoint certificates.

Usage: sampling_cells.py <examples-dir> <output.json> [--native <json-dir>]

Four-switch cell: a nonrail capacitor has, at each endpoint, exactly one
same-body NMOS to ground and one NMOS to another nonrail net. Two distinct
control nets cross between the signal and opposite shunt; controls have no
DC incidence. The four nonrail path nets are distinct. Two-switch cell:
a grounded capacitor's nonrail end has exactly two same-body NMOS to distinct
nonrail nets and distinct controls with no DC incidence. The body is ground.
These selectors do not inspect names except the established rail vocabulary.

Broader two-switch candidates with additional DC incidence are retained as
named counterexamples. Actual transformed SVG lead strokes verify every
studied C and MOS terminal before source geometry is measured. Model names,
instance labels and cached rotation do not establish axes. Opaque blocks stay
opaque; unknown cards and missing/ambiguous primitives fail. This is research,
not an implemented placement rule. Related AG variants are correlated.
"""
import argparse
import collections
import hashlib
import itertools
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from channel_bridges import read_cards, rail
from cross_caps import actual_glyph
import mos_forms


def select(text):
    cards = read_cards(text)
    models = {w[1]: w[2] for line in text.lower().splitlines()
              if (w := line.split()) and w[0] == ".model"}
    dc = collections.defaultdict(set)
    for name, words in cards.items():
        if name[0] not in "rlmqdviefhgswjz":
            continue
        for net in (words[1], words[3] if name[0] in "mqjz" else words[2]):
            dc[net].add(name)
    mos = {}
    for name, words in cards.items():
        if name[0] != "m":
            continue
        if words[5] not in models:
            raise ValueError("unknown MOS model")
        if models[words[5]] == "nmos" and len(set(words[1:4])) == 3 and rail(words[4]) == "sink" and not rail(words[2]) and not dc[words[2]]:
            mos[name] = words
    def at(net):
        return sorted(name for name in dc[net] if name in mos)
    def other(name, net):
        words = cards[name]
        return words[3] if words[1] == net else words[1]
    rows = []
    for cap, words in sorted(cards.items()):
        if cap[0] != "c":
            continue
        a, b = words[1:3]
        if a == b:
            continue
        if not rail(a) and not rail(b):
            for p, q in itertools.product(at(a), at(b)):
                pa, pb = other(p, a), other(q, b)
                if rail(pa) or rail(pb) or len({a, b, pa, pb}) != 4:
                    continue
                shunts = [[m for m in at(net) if rail(other(m, net)) == "sink"] for net in (a, b)]
                for u, v in itertools.product(*shunts):
                    members = [p, q, u, v]
                    gates = [cards[m][2] for m in members]
                    if gates[0] != gates[3] or gates[1] != gates[2] or gates[0] == gates[1]:
                        continue
                    if len({cards[m][4] for m in members}) != 1:
                        continue
                    admitted = dc[a] == {p, u} and dc[b] == {q, v}
                    rows.append(dict(family="four_switch", cap=cap, signal=[p, q], shunt=[u, v],
                                     nets=[pa, a, b, pb], admitted=admitted,
                                     extra_dc=sorted((dc[a] | dc[b]) - set(members))))
        else:
            mid, ground = (a, b) if not rail(a) else (b, a)
            if rail(mid) or rail(ground) != "sink":
                continue
            for p, q in itertools.combinations(at(mid), 2):
                pa, pb = other(p, mid), other(q, mid)
                if rail(pa) or rail(pb) or len({mid, pa, pb}) != 3 or cards[p][2] == cards[q][2]:
                    continue
                if cards[p][4] != cards[q][4]:
                    continue
                rows.append(dict(family="two_switch", cap=cap, signal=[p, q], shunt=[],
                                 nets=[pa, mid, pb], admitted=dc[mid] == {p, q},
                                 extra_dc=sorted(dc[mid] - {p, q})))
    return cards, rows


def pin(device, net, native=False):
    if native:
        found = [p["xy"] for p in device["pins"] if p["net"].lower() == net]
    else:
        found = [device["terminals"][p] for p, n in device["nets"].items() if n.lower() == net]
    if not found or any(p != found[0] for p in found):
        raise ValueError("missing/ambiguous studied net terminal: " + net)
    return found[0]


def channel(device, native=False):
    if native:
        pairs = {p["term"]: p["xy"] for p in device["pins"]}
        return pairs["d"], pairs["s"], pairs["g"]
    return tuple(device["terminals"][p] for p in ("D", "S", "G"))


def geometry(row, devices, native=False):
    sig = [channel(devices[n], native) for n in row["signal"]]
    mid = [[(a[k] + b[k]) / 2 for k in (0, 1)] for a, b, _ in sig]
    ends = row["nets"][1:-1]
    cap = devices[row["cap"]]
    if row["family"] == "four_switch":
        cp = [pin(cap, net, native) for net in ends]
    else:
        cp = [pin(cap, row["nets"][1], native)]
        if native:
            cp.append(next(p["xy"] for p in cap["pins"] if rail(p["net"].lower()) == "sink"))
        else:
            cp.append(next(cap["terminals"][p] for p, n in cap["nets"].items() if rail(n.lower()) == "sink"))
    cx = (cp[0][0] + cp[1][0]) / 2
    result = dict(signal_horizontal=[a[1] == b[1] for a, b, _ in sig],
                  signal_same_row=mid[0][1] == mid[1][1],
                  signal_gates_above=[g[1] < a[1] == b[1] for a, b, g in sig],
                  capacitor_horizontal=cp[0][1] == cp[1][1],
                  capacitor_between=min(p[0] for p in mid) < cx < max(p[0] for p in mid))
    if row["family"] == "four_switch":
        shunts = [channel(devices[n], native) for n in row["shunt"]]
        sm = [[(a[k] + b[k]) / 2 for k in (0, 1)] for a, b, _ in shunts]
        result.update(capacitor_on_signal_row=cp[0][1] == cp[1][1] == mid[0][1] == mid[1][1],
                      shunt_vertical=[a[0] == b[0] for a, b, _ in shunts],
                      shunts_same_row=sm[0][1] == sm[1][1],
                      shunts_below=[s[1] > m[1] for s, m in zip(sm, mid)],
                      shunts_inside=[min(m[0], cx) < s[0] < max(m[0], cx) for s, m in zip(sm, mid)],
                      shunt_gates_outward=[(g[0] - s[0]) * (s[0] - cx) > 0 for (_, _, g), s in zip(shunts, sm)])
    else:
        result.update(capacitor_vertical=cp[0][0] == cp[1][0],
                      capacitor_below=cp[1][1] > cp[0][1] >= max(p[1] for p in mid))
    return result


def summarize(rows):
    groups = {}
    for family in ("four_switch", "two_switch"):
        subset = [r for r in rows if r["family"] == family]
        group = dict(cells=len(subset), circuits=len({r["id"] for r in subset}))
        for origin in ("source_geometry", "native_geometry"):
            selected = [r[origin] for r in subset if origin in r]
            totals = collections.Counter()
            for g in selected:
                for key, value in g.items():
                    totals[key] += sum(value) if isinstance(value, list) else value
            group[origin] = dict(totals)
        for kind in ("signal", "shunt", "cap"):
            names = sorted({r["id"] + ":" + n for r in subset for n in ([r["cap"]] if kind == "cap" else r[kind])})
            group[kind + "_names"] = names
        group["existing_forms_selected_names"] = sorted({r["id"] + ":" + n for r in subset for n in r["existing_forms_selected"]})
        group["source_axis_mismatches"] = sorted({r["id"] + ":" + n for r in subset for n in r.get("axis_mismatches", [])})
        groups[family] = group
    return groups


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path)
    args = parser.parse_args()
    selected, excluded, hashes, native_hashes = [], [], {}, {}
    paths = sorted(args.examples.glob("*.human.json"))
    if not paths:
        raise ValueError("no paired source drawings")
    digest = hashlib.sha256()
    for path in paths:
        ident = path.name.removesuffix(".human.json")
        deck, svg = [path.with_name(ident + suffix) for suffix in (".cir", ".svg")]
        for p in (path, deck):
            data, name = p.read_bytes(), p.name.encode()
            digest.update(len(name).to_bytes(8, "big") + name + len(data).to_bytes(8, "big") + data)
        text = deck.read_text()
        cards, rows = select(text)
        if not rows:
            continue
        human = json.loads(path.read_text())
        devices = {d["card"]: d for d in human["devices"]}
        actual = ET.parse(svg).getroot()
        targets = sorted({n for r in rows for n in [r["cap"]] + r["signal"] + r["shunt"]})
        verified = {n: actual_glyph(actual, devices[n]) for n in targets}
        for n, glyph in verified.items():
            devices[n]["terminals"].update(glyph["terminals"])
        for p in (path, deck, svg):
            hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
        existing = {r["card"]: r for r in mos_forms.inspect(human, cards, mos_forms.input_nets(text, cards))}
        generated = {}
        if args.native:
            p = args.native / (ident + ".json")
            native_hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
            generated = {d["name"].lower(): d for d in json.loads(p.read_text())["devices"]}
        for row in rows:
            names = [row["cap"]] + row["signal"] + row["shunt"]
            row.update(id=ident, split="holdout" if int(ident.rsplit("-", 1)[1]) % 5 == 0 else "discovery",
                       source_geometry=geometry(row, devices),
                       source_glyphs={n: verified[n] for n in names},
                       existing_forms_selected=[n for n in row["signal"] if existing[n]["families"]])
            if generated:
                row["native_geometry"] = geometry(row, generated, True)
                wrong = []
                for n in names:
                    if n[0] == "m":
                        sp, np = channel(devices[n])[:2], channel(generated[n], True)[:2]
                    else:
                        nets = cards[n][1:3]
                        sp, np = [pin(devices[n], net) for net in nets], [pin(generated[n], net, True) for net in nets]
                    if (sp[0][1] == sp[1][1]) != (np[0][1] == np[1][1]):
                        wrong.append(n)
                row["axis_mismatches"] = wrong
            (selected if row["admitted"] else excluded).append(row)
    result = dict(paired_corpus_sha256=digest.hexdigest(), corpus_drawings=len(paths),
                  source_sha256=hashes, native_sha256=native_hashes,
                  split="numeric ID modulo five; related textbook variants may cross this split",
                  scope="last converted SPICE cell; opaque blocks; DC controls; no orientation hints",
                  summary=summarize(selected),
                  holdout_summary=summarize([r for r in selected if r["split"] == "holdout"]),
                  selected=selected, excluded_extra_dc=excluded)
    result["study_sha256"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
                              [Path(__file__), Path(mos_forms.__file__), Path(__file__).with_name("cross_caps.py"),
                               Path(__file__).with_name("channel_bridges.py"), Path(__file__).with_name("converter_terminals.py")]}
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({family: {k: v for k, v in group.items() if not k.endswith("_names") and k != "source_axis_mismatches"}
                      for family, group in result["summary"].items()}, indent=2))


if __name__ == "__main__":
    main()
