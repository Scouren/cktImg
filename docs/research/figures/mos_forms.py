#!/usr/bin/env python3
"""Paired corpus decks and human drawings -> evidence for horizontal MOS channels.

Usage: mos_forms.py <examples-dir> <output.json>

The independent oracle is the human drawing's D/S coordinates. Connectivity
comes from the converted SPICE deck's last subcircuit, as in netlist.zig; no
engine code is imported. The explicit path table follows SPICE terminals and
device.zig. Subcircuit calls remain opaque, as they do in the layout engine.

Study predicate: distinct D/S/G, neither channel end a rail, and a capacitor
at an end whose DC component reaches no rail; or whose DC degree is one
while the opposite channel end drives another transistor's gate/base or
a named block input. Port roles use the library's whole input spellings;
the block's family name and chosen glyph do not affect that role.
The capacitor's other end must not be this MOS's gate or opposite channel
end: its own terminal capacitance does not establish a series signal path.
Capacitors do not conduct DC; gates, bodies and control pins are not paths.
Cell voltage sources stay inline, as in tools/json.zig's deckSources.
Names never select a MOS, except the engine's rail vocabulary.

Unknown cards, unsupported steering, missing pairs and ambiguous MOS geometry
fail. The modulo-five split is reproducible stratification, not proof against
correlated textbook variants. Counts describe habits, not electrical laws.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path


# Node counts are minima; paths use SPICE's first two or first/third nodes.
PATH_NODES = {**dict.fromkeys("rclviefhgdws", 2), **dict.fromkeys("qjzm", 3)}
NO_PATH = frozenset("kxbtou")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    paths = sorted(args.examples.rglob("*.human.json"))
    if not paths:
        parser.error("examples directory contains no *.human.json files")
    digest = hashlib.sha256()
    orientation = collections.Counter()
    horizontal_circuits = set()
    selected = []
    for human_path in paths:
        deck_path = human_path.with_name(human_path.name.removesuffix(".human.json") + ".cir")
        for path in (human_path, deck_path):
            data = path.read_bytes()
            name = path.relative_to(args.examples).as_posix().encode()
            digest.update(len(name).to_bytes(8, "big") + name)
            digest.update(len(data).to_bytes(8, "big") + data)
        human = json.loads(human_path.read_text())
        source = deck_path.read_text()
        cards = read_cards(source)
        rows = inspect(human, cards, input_nets(source, cards))
        for row in rows:
            orientation[row["human_orientation"]] += 1
            if row["human_orientation"] == "horizontal":
                horizontal_circuits.add(human["id"])
            if row["families"]:
                selected.append(row)
    selected.sort(key=lambda row: (row["id"], row["card"]))
    groups = {"all": selected}
    for split in ("discovery", "holdout"):
        groups[split] = [row for row in selected if row["split"] == split]
    for family in ("compensation", "floating_capacitor", "block_input"):
        groups[family] = [row for row in selected if family in row["families"]]
    result = {
        "predicate": "MOS: distinct D/S/G, no D/S rail; nonparasitic capacitor at an endpoint with no rail-reachable DC component, or DC degree 1 and opposite end driving another gate/base or named block input",
        "oracle": "D/S endpoint coordinates in the independent human drawing",
        "corpus_sha256": digest.hexdigest(),
        "split": "numeric source ID modulo 5: zero = holdout, others = discovery; related variants may cross the split",
        "scope": "last SPICE subcircuit; named rails; opaque X blocks; cell voltage sources inline; unknown cards and steering fail",
        "raw": {
            "drawings": len(paths),
            "mos_devices": sum(orientation.values()),
            "horizontal": orientation["horizontal"],
            "vertical": orientation["vertical"],
            "drawings_with_horizontal_mos": len(horizontal_circuits),
        },
        "summary": {name: summarize(rows) for name, rows in groups.items()},
        "selected": selected,
    }
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in ("corpus_sha256", "raw", "summary")}, indent=2))


def read_cards(text):
    """Reads the converted deck's last cell; unsupported syntax fails explicitly."""
    lines = []
    for raw in text.splitlines():
        if raw.lstrip().startswith("*@"):
            raise ValueError("steered deck outside this observational study")
        if raw.startswith("+"):
            if not lines:
                raise ValueError("continuation without a preceding card")
            lines[-1] += " " + raw[1:]
        else:
            lines.append(raw)
    cards = {}
    inside = False
    found = False
    for raw in lines:
        words = raw.lower().split()
        if not words or words[0].startswith("*"):
            continue
        if words[0] == ".subckt":
            if inside:
                raise ValueError("nested subcircuit declaration")
            cards = {}
            inside = found = True
        elif words[0] == ".ends":
            inside = False
        elif inside and not words[0].startswith("."):
            name = words[0]
            kind = name[0]
            if kind not in PATH_NODES and kind not in NO_PATH:
                raise ValueError(f"unsupported SPICE card: {raw}")
            if len(words) < PATH_NODES.get(kind, 0) + 2 or name in cards:
                raise ValueError(f"malformed or duplicate SPICE card: {raw}")
            cards[name] = words
    if not found or inside:
        raise ValueError("missing or unterminated top subcircuit")
    return cards


def input_nets(text, cards):
    """Binds declared X ports to nets; matches library.portRole input spellings."""
    definitions = {}
    for raw in text.lower().splitlines():
        words = raw.split()
        if not words or words[0] != ".subckt":
            continue
        if words[1] in definitions:
            raise ValueError("duplicate subcircuit: " + words[1])
        ports = []
        for word in words[2:]:
            if "=" in word or word == "params:":
                break
            ports.append(word)
        definitions[words[1]] = ports
    inputs = set()
    spellings = set("vin in a vip inp in+ vp vin+ inn in- vn vin-".split())
    for name, words in cards.items():
        if name[0] != "x":
            continue
        tail = next((i for i, word in enumerate(words) if "=" in word or word == "params:"), len(words))
        model = words[tail - 1]
        if model not in definitions:
            raise ValueError("missing block definition: " + model)
        ports = definitions[model]
        nets = words[1:tail - 1]
        if len(nets) != len(ports):
            raise ValueError("block port count mismatch: " + name)
        inputs.update(net for net, port in zip(nets, ports) if port in spellings)
    return inputs


def inspect(human, cards, block_inputs=()):
    """Separates the topology predicate from the coordinate oracle."""
    paths = {}
    capacitors = []
    gates = {words[2] for words in cards.values() if words[0][0] in "mqjz"}
    for name, words in cards.items():
        kind = name[0]
        if kind in NO_PATH:
            continue
        ends = (words[1], words[3] if kind in "mqjz" else words[2])
        if kind == "c":
            capacitors.append(ends)
            continue
        if kind == "e":
            # A large-gain grounded E is the engine's ideal amplifier box.
            if len(words) < 6:
                raise ValueError(f"unsupported E card: {words}")
            try:
                gain = float(words[5])
            except ValueError as error:
                raise ValueError(f"nonliteral E gain outside study scope: {words}") from error
            if rail(ends[1]) == "sink" and abs(gain) >= 1000:
                continue
        paths[name] = ends
    adjacency = collections.defaultdict(list)
    for name, (a, b) in paths.items():
        adjacency[a].append((b, name))
        adjacency[b].append((a, name))
    reached = {net for net in adjacency if rail(net)}
    queue = list(sorted(reached))
    for net in queue:
        for other, _ in adjacency[net]:
            if other not in reached:
                reached.add(other)
                queue.append(other)
    drawn = {device["card"]: device for device in human["devices"]}
    if len(drawn) != len(human["devices"]):
        raise ValueError(f"{human['id']}: duplicate drawn cards")
    rows = []
    for name, words in cards.items():
        if name[0] != "m":
            continue
        device = drawn[name]
        if device["type"] not in ("nmos", "pmos"):
            raise ValueError(f"{human['id']}.{name}: unsupported MOS symbol")
        drain, gate, source = words[1:4]
        for terminal, net in (("D", drain), ("G", gate), ("S", source)):
            if device["nets"][terminal] != net:
                raise ValueError(f"{human['id']}.{name}: deck and drawing disagree at {terminal}")
        a, b = device["terminals"]["D"], device["terminals"]["S"]
        if (a[0] == b[0]) == (a[1] == b[1]):
            raise ValueError(f"{human['id']}.{name}: nonorthogonal or zero-length channel")
        families = []
        eligible = len({drain, gate, source}) == 3 and not rail(drain) and not rail(source)
        if eligible:
            ends_with_cap = set()
            for net, opposite in ((drain, source), (source, drain)):
                for first, second in capacitors:
                    other = second if first == net else first if second == net else None
                    if other is not None and other not in (net, gate, opposite):
                        ends_with_cap.add(net)
            leaves = [(net, opposite) for net, opposite in ((drain, source), (source, drain))
                      if net in ends_with_cap and len(adjacency[net]) == 1]
            if any(opposite in gates or opposite in block_inputs for _, opposite in leaves):
                families.append("compensation")
            if any(opposite in block_inputs for _, opposite in leaves):
                families.append("block_input")
            if drain not in reached and source not in reached and ends_with_cap:
                families.append("floating_capacitor")
        numeric_id = int(human["id"].rsplit("-", 1)[1])
        rows.append({
            "id": human["id"], "card": name, "name": device["name"],
            "title": human["title"], "families": families,
            "split": "holdout" if numeric_id % 5 == 0 else "discovery",
            "human_orientation": "horizontal" if a[1] == b[1] else "vertical",
        })
    return rows


def rail(name):
    """The existing engine's rail spellings, case folded by the deck reader."""
    if name == "0" or name == "v-" or name.startswith(("gnd", "vss", "vee", "agnd", "dgnd")):
        return "sink"
    if name == "v+" or name.startswith(("vdd", "vcc", "avdd", "dvdd", "vpp")):
        return "supply"
    return None


def summarize(rows):
    horizontal = sum(row["human_orientation"] == "horizontal" for row in rows)
    return {
        "devices": len(rows), "horizontal": horizontal,
        "vertical": len(rows) - horizontal,
        "circuits": len({row["id"] for row in rows}),
        "horizontal_percent": round(100 * horizontal / len(rows), 3) if rows else None,
        "exceptions": [row["id"] + ":" + row["card"] for row in rows if row["human_orientation"] == "vertical"],
    }


if __name__ == "__main__":
    main()
