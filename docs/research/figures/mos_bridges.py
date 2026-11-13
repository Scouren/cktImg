#!/usr/bin/env python3
"""Study two conservative MOS bridge candidates, independently of the engine.

Usage: mos_bridges.py <examples-dir> <output.json>

Source-degeneration bridge: a MOS joins two other, same-polarity MOS source
nodes. The three bodies share a named rail, both channel ends have a direct
DC path to that rail, the two driving MOS have distinct drains and gates,
and the bridge gate has no incident DC path.

External switch ring: a rail-free DC component contains exactly four MOS
of one polarity. Their channels form a four-node cycle, with two alternating
gate nets outside the cycle; both controls are declared subcircuit ports.

These are observational candidates, not electrical laws. Model polarities,
ports and connectivity come from SPICE; only the orientation oracle comes
from the human drawing. Ablations retain the known counterexamples. AMSNet
currently contains no eligible instance of either conservative candidate.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path
import re

from mos_forms import NO_PATH, input_nets, inspect, rail, read_cards, summarize


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    paths = sorted(args.examples.rglob("*.human.json"))
    if not paths:
        parser.error("examples directory contains no paired human drawings")
    digest = hashlib.sha256()
    selected = []
    for human_path in paths:
        deck_path = human_path.with_name(human_path.name.replace(".human.json", ".cir"))
        for path in (human_path, deck_path):
            data = path.read_bytes()
            name = path.relative_to(args.examples).as_posix().encode()
            digest.update(len(name).to_bytes(8, "big") + name)
            digest.update(len(data).to_bytes(8, "big") + data)
        text = deck_path.read_text()
        cards = read_cards(text)
        families, evidence = select(cards, *declarations(text))
        human = json.loads(human_path.read_text())
        for row in inspect(human, cards, input_nets(text, cards)):
            if row["card"] not in families:
                continue
            row["covered_by_cap_rule"] = bool(row.pop("families"))
            row["families"] = families[row["card"]]
            row["evidence"] = evidence[row["card"]]
            selected.append(row)
    selected.sort(key=lambda row: (row["id"], row["card"]))
    groups = {}
    for family in ("degeneration", "external_ring", "degeneration_without_gate_guard",
                   "ring_without_external_controls"):
        rows = [row for row in selected if family in row["families"]]
        groups[family] = {"all": summarize(rows)}
        for split in ("discovery", "holdout"):
            groups[family][split] = summarize([r for r in rows if r["split"] == split])
        groups[family]["beyond_cap_rule"] = summarize(
            [row for row in rows if not row["covered_by_cap_rule"]])
    result = {"corpus_sha256": digest.hexdigest(), "drawings": len(paths),
              "oracle": "independent human drawing D/S coordinates",
              "split": "numeric ID modulo 5; zero holdout; variants may cross splits",
              "scope": "last subcircuit; explicit MOS models and ports; same DC path table as mos_forms.py",
              "summary": groups, "selected": selected}
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({k: result[k] for k in ("corpus_sha256", "drawings", "summary")}, indent=2))


def declarations(text):
    """MOS polarity and selected-cell boundary, from source declarations only."""
    models = {}
    for name, kind in re.findall(r"(?im)^\s*\.model\s+(\S+)\s+([^\s(]+)", text):
        name, kind = name.lower(), kind.lower()
        if name in models and models[name] != kind:
            raise ValueError("ambiguous model scope: " + name)
        models[name] = kind
    headers = re.findall(r"(?im)^\s*\.subckt\s+\S+([^\n]*)", text)
    if not headers:
        raise ValueError("no selected subcircuit")
    ports = set()
    for word in headers[-1].lower().split():
        if "=" in word or word == "params:":
            break
        ports.add(word)
    return models, ports


def select(cards, models, ports):
    """Topology-only selection; no drawing coordinates or orientation enter here."""
    paths = {}
    adjacency = collections.defaultdict(list)
    mos = {name: words for name, words in cards.items() if name[0] == "m"}
    kinds = {}
    for name, words in mos.items():
        if len(words) < 6 or models.get(words[5]) not in ("nmos", "pmos"):
            raise ValueError("missing or unsupported MOS model: " + name)
        kinds[name] = models[words[5]]
    for name, words in cards.items():
        kind = name[0]
        if kind in NO_PATH or kind == "c":
            continue
        a, b = words[1], words[3] if kind in "mqjz" else words[2]
        if kind == "e" and rail(b) == "sink" and abs(float(words[5])) >= 1000:
            continue
        paths[name] = (a, b)
        adjacency[a].append((b, name))
        adjacency[b].append((a, name))
    families = collections.defaultdict(list)
    evidence = collections.defaultdict(dict)
    sources = collections.defaultdict(list)
    for name, words in mos.items():
        sources[words[3]].append(name)
    for name, words in mos.items():
        a, gate, b, body = words[1:5]
        if len({a, gate, b}) != 3 or rail(a) or rail(b) or not rail(body):
            continue
        if not all(any(other == body for other, _ in adjacency[net]) for net in (a, b)):
            continue
        pairs = []
        for p in sources[a]:
            for q in sources[b]:
                x, y = mos[p], mos[q]
                if name in (p, q) or p == q or not (kinds[p] == kinds[q] == kinds[name]):
                    continue
                if x[4] != body or y[4] != body or x[1] == y[1] or x[2] == y[2]:
                    continue
                if any(d[1] in (a, b) or len(set(d[1:4])) != 3 for d in (x, y)):
                    continue
                pairs.append([p, q])
        if pairs:
            families[name].append("degeneration_without_gate_guard")
            evidence[name]["source_pairs"] = sorted(pairs)
            evidence[name]["body_rail"] = body
            if gate not in adjacency:
                families[name].append("degeneration")
    seen = set()
    for start in list(adjacency):
        if start in seen:
            continue
        nodes, edges, queue = {start}, set(), [start]
        for net in queue:
            for other, name in adjacency[net]:
                edges.add(name)
                if other not in nodes:
                    nodes.add(other)
                    queue.append(other)
        seen.update(nodes)
        switches = sorted(name for name in edges if name in mos)
        if len(switches) != 4 or any(rail(net) for net in nodes):
            continue
        if len({kinds[name] for name in switches}) != 1:
            continue
        channels = collections.defaultdict(list)
        controls = {mos[name][2] for name in switches}
        for name in switches:
            a, gate, b = mos[name][1:4]
            channels[a].append(gate)
            channels[b].append(gate)
        if len(channels) != 4 or len(controls) != 2 or controls & channels.keys():
            continue
        if any(len(gates) != 2 or len(set(gates)) != 2 for gates in channels.values()):
            continue
        for name in switches:
            families[name].append("ring_without_external_controls")
            evidence[name]["ring"] = switches
            evidence[name]["controls"] = sorted(controls)
            if controls <= ports:
                families[name].append("external_ring")
    return families, evidence


if __name__ == "__main__":
    main()
