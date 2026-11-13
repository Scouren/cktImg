#!/usr/bin/env python3
"""Source decks and independent drawings -> local switched-feedback geometry.

Usage: opamp_feedback.py <examples-dir> <output.json> [--native <json-dir>]

Select a named amplifier input/output joined by exactly a capacitor and MOS,
with one ground-shunt MOS at their otherwise isolated junction. The selection
reads SPICE only. It admits either ordering of the capacitor and channel.
Human terminal coordinates independently test axes, shared rows/columns and
feedback-branch order. A direct capacitor takes the outer row and keeps the
switched branch straight; without one, the signal switch returns vertically
and the capacitor shares a row with the horizontal ground switch.
The vertical return's gate faces away from the amplifier in all seven
observed rectangles; this adds a separate gate-side geometry assertion.

All selected cells are reported, including circuits the engine's switched
amplifier admission currently rejects. Native output is optional and never
selects examples or supplies the expected geometry. Missing pairs, unknown
SPICE cards, missing block definitions and malformed geometry fail explicitly.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path

from mos_forms import NO_PATH, rail, read_cards


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path)
    args = parser.parse_args()
    files = sorted(args.examples.rglob("*.human.json"))
    if not files:
        parser.error("examples directory contains no human drawings")
    digest = hashlib.sha256()
    rows, pairs = [], []
    for path in files:
        deck = path.with_name(path.name.replace(".human.json", ".cir"))
        for source in (path, deck):
            data, name = source.read_bytes(), source.relative_to(args.examples).as_posix().encode()
            digest.update(len(name).to_bytes(8, "big") + name)
            digest.update(len(data).to_bytes(8, "big") + data)
        text = deck.read_text()
        cards = read_cards(text)
        amplifiers = blocks(text, cards)
        selected = select(cards, amplifiers)
        if not selected:
            continue
        selfcheck(cards, amplifiers, selected)
        human = json.loads(path.read_text())
        drawings = {"human": drawing(human, True)}
        if args.native:
            drawings["native"] = drawing(json.loads((args.native / (human["id"] + ".json")).read_text()), False)
        for row in selected:
            row.update(id=human["id"], split="holdout" if int(human["id"].split("-")[-1]) % 5 == 0 else "discovery")
            for name, geometry in drawings.items():
                row[name] = checks(row, geometry)
            rows.append(row)
        if len(selected) == 2 and len({row["block"] for row in selected}) == 1:
            first = next((r for r in selected if r["cap_at_input"]), None)
            last = next((r for r in selected if not r["cap_at_input"]), None)
            if first is not None and last is not None:
                pair = {"id": human["id"], "caps": [first["cap"], last["cap"]]}
                for name, geometry in drawings.items():
                    a, b = midpoint(geometry, first["cap"]), midpoint(geometry, last["cap"])
                    pair[name] = {"capacitor_columns_shared": a[0] == b[0],
                                  "input_cap_branch_nearest_amplifier": a[1] > b[1]}
                pairs.append(pair)
    result = {"corpus_sha256": digest.hexdigest(), "drawings": len(files),
              "oracle": "source human terminal coordinates; selection reads only SPICE",
              "scope": "last source cell; named input/single-output blocks; no engine admission assumption",
              "selector_selfchecks": "selected cells retain card/D-S reversal; removing ground MOS or adding a junction path rejects that cell",
              "split": "numeric source ID modulo five: zero holdout; correlated variants may cross split",
              "summary": {name: summary([r for r in rows if name == "all" or r["split"] == name])
                          for name in ("all", "discovery", "holdout")},
              "selected": rows, "paired_branches": pairs}
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({k: result[k] for k in ("corpus_sha256", "drawings", "summary")}, indent=2))


def blocks(text, cards):
    """Bind actual nets to declared semantic amplifier ports, without glyphs."""
    definitions = {}
    for line in text.lower().splitlines():
        words = line.split()
        if not words or words[0] != ".subckt":
            continue
        if words[1] in definitions:
            raise ValueError("duplicate block declaration: " + words[1])
        end = next((i for i, word in enumerate(words) if word == "params:" or "=" in word), len(words))
        definitions[words[1]] = words[2:end]
    found = []
    for name, words in cards.items():
        if name[0] != "x":
            continue
        end = next((i for i, word in enumerate(words) if word == "params:" or "=" in word), len(words))
        ports, nets = definitions[words[end - 1]], words[1:end - 1]
        if len(ports) != len(nets):
            raise ValueError("block arity: " + name)
        outputs = [n for p, n in zip(ports, nets) if p in ("out", "vout", "vo", "o", "y")]
        inputs = [n for p, n in zip(ports, nets) if p in "vin in a vip inp in+ vp vin+ inn in- vn vin-".split()]
        if len(outputs) == 1:
            found.append((name, sorted(set(inputs)), outputs[0], set(nets)))
    return found


def select(cards, amplifiers):
    """Topology only: a two-part feedback path with one isolated ground shunt."""
    paths = {name: (w[1], w[3] if name[0] in "mqjz" else w[2])
             for name, w in cards.items() if name[0] not in NO_PATH}
    incident = collections.defaultdict(set)
    for name, ends in paths.items():
        for net in ends:
            incident[net].add(name)
    block_pins = set().union(*(a[3] for a in amplifiers)) if amplifiers else set()
    gates = {w[2] for n, w in cards.items() if n[0] in "mqjz"}
    rows = []
    for name, inputs, output, _ in amplifiers:
        if rail(output):
            continue
        for inp in inputs:
            if rail(inp) or inp == output:
                continue
            direct = sorted(n for n, ends in paths.items() if set(ends) == {inp, output})
            for cap, ends in sorted(paths.items()):
                if cap[0] != "c" or ends[0] == ends[1]:
                    continue
                for anchor, remote in ((inp, output), (output, inp)):
                    if anchor not in ends:
                        continue
                    leaf = ends[1] if ends[0] == anchor else ends[0]
                    if rail(leaf) or leaf in block_pins or leaf in gates or len(incident[leaf]) != 3:
                        continue
                    signal = [n for n in incident[leaf] if n[0] == "m" and set(paths[n]) == {leaf, remote}]
                    shunt = [n for n in incident[leaf] if n[0] == "m" and any(rail(x) == "sink" for x in paths[n])]
                    if len(signal) != 1 or len(shunt) != 1:
                        continue
                    if any(len(set(cards[n][1:4])) != 3 for n in signal + shunt):
                        continue
                    rows.append({"block": name, "input": inp, "output": output, "leaf": leaf,
                                 "cap": cap, "signal": signal[0], "shunt": shunt[0],
                                 "cap_at_input": anchor == inp, "direct": direct,
                                 "direct_cap": any(n[0] == "c" for n in direct)})
    return rows


def drawing(data, human):
    """Normalize coordinate records only; never infer connectivity from wires."""
    if human:
        return {d["card"]: [(t.lower(), d["nets"][t], xy) for t, xy in d["terminals"].items()]
                for d in data["devices"]}
    return {d["name"]: [(p["term"], p["net"], p["xy"]) for p in d["pins"]] for d in data["devices"]}


def selfcheck(cards, amplifiers, selected):
    """Topology metamorphisms and ablations; source coordinates are untouched."""
    reordered = dict(reversed(list(cards.items())))
    for name, words in list(reordered.items()):
        if name[0] == "m":
            swapped = words.copy()
            swapped[1], swapped[3] = swapped[3], swapped[1]
            reordered[name] = swapped
    assert select(reordered, amplifiers) == selected
    for row in selected:
        missing = cards.copy()
        del missing[row["shunt"]]
        assert row not in select(missing, amplifiers)
        extra = cards.copy()
        assert "r_oracle_guard" not in extra
        extra["r_oracle_guard"] = ["r_oracle_guard", row["leaf"], "oracle_external", "1k"]
        assert row not in select(extra, amplifiers)


def channel(ds, card):
    pins = [xy for t, _, xy in ds[card] if card[0] != "m" or t in ("d", "s")]
    if len(pins) != 2 or pins[0] == pins[1] or (pins[0][0] != pins[1][0] and pins[0][1] != pins[1][1]):
        raise ValueError("nonorthogonal or missing channel: " + card)
    return pins


def on(ds, card, net):
    return next(xy for term, n, xy in ds[card] if n == net and (card[0] != "m" or term in ("d", "s")))


def midpoint(ds, card):
    a, b = channel(ds, card)
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


def horizontal(ds, card):
    a, b = channel(ds, card)
    return a[1] == b[1]


def checks(row, ds):
    """Independent source-derived relative geometry, without absolute units."""
    c, s, z = row["cap"], row["signal"], row["shunt"]
    leaf = row["leaf"]
    near = on(ds, row["block"], row["output"] if row["cap_at_input"] else row["input"])
    cm = midpoint(ds, c)
    result = {"capacitor_horizontal": horizontal(ds, c)}
    if row["direct_cap"]:
        result.update(signal_horizontal=horizontal(ds, s), shunt_vertical=not horizontal(ds, z),
                      capacitor_signal_same_row=cm[1] == midpoint(ds, s)[1],
                      direct_cap_outside_cell=all(midpoint(ds, d)[1] < cm[1] < near[1]
                                                 for d in row["direct"] if d[0] == "c"))
    else:
        sig = channel(ds, s)
        junction = [on(ds, c, leaf)[0], on(ds, z, leaf)[0]]
        gate = next(xy for term, _, xy in ds[s] if term == "g")
        outward_gate = gate[0] > midpoint(ds, s)[0] if row["cap_at_input"] else gate[0] < midpoint(ds, s)[0]
        result.update(signal_vertical=not horizontal(ds, s), shunt_horizontal=horizontal(ds, z),
                      return_gate_faces_outward=outward_gate,
                      capacitor_shunt_same_row=cm[1] == midpoint(ds, z)[1],
                      signal_column_on_junction=min(junction) <= on(ds, s, leaf)[0] <= max(junction),
                      signal_outside_amplifier=(midpoint(ds, s)[0] > near[0] if row["cap_at_input"]
                                                else midpoint(ds, s)[0] < near[0]),
                      signal_between_cap_and_amplifier=cm[1] <= min(p[1] for p in sig) < max(p[1] for p in sig) <= near[1])
        resets = [d for d in row["direct"] if d[0] == "m"]
        if resets:
            result["reset_between_cap_and_amplifier"] = all(cm[1] < midpoint(ds, d)[1] < near[1] for d in resets)
    return result


def summary(rows):
    out = {"cells": len(rows), "circuits": sorted({r["id"] for r in rows})}
    for kind in ("human", "native"):
        selected = [r for r in rows if kind in r]
        if selected:
            out[kind] = {"passing_checks": sum(sum(r[kind].values()) for r in selected),
                         "checks": sum(len(r[kind]) for r in selected),
                         "fully_passing_cells": sum(all(r[kind].values()) for r in selected),
                         "exceptions": [{"id": r["id"], "cap": r["cap"],
                                         "failed": [k for k, v in r[kind].items() if not v]}
                                        for r in selected if not all(r[kind].values())]}
    return out


if __name__ == "__main__":
    main()
