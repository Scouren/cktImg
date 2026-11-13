#!/usr/bin/env python3
"""Paired circuit decks and human terminal geometry -> converter-path evidence.

Usage: power_paths.py <examples-dir> <output.json>

Topology selects PMOS/coil paths without consulting drawing coordinates.
The independent oracle is the human drawing's D/S or coil coordinates.
A nonrail inductor with an NMOS shunt to ground supplies the switching
nodes. A selected PMOS connects one to a ground-capacitor reservoir, or
belongs to a gate-only-controlled PMOS input bus and itself ends at a
switching node or a nonparasitic capacitor. Auxiliary bias supply branches
remain unresolved. Gates and bodies are not current paths.

The output retains selected names, exceptions, unresolved horizontal devices
and input hashes. Repeated converter variants are correlated evidence.
Ground shunts are also compared with the horizontal wire interval between
their connected coil and main-MOS terminals. A unique eligible shunt at an
endpoint is a topology-only refinement; amplifier tails can share that net.
"""

import argparse
import collections
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("mos_forms", Path(__file__).with_name("mos_forms.py"))
MOS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOS)


def classify(text):
    """The topology-only predicate; no human coordinates or names select parts."""
    cards = MOS.read_cards(text)
    models = {}
    ports = {}
    for line in text.lower().splitlines():
        words = line.split()
        if not words:
            continue
        if words[0] == ".model":
            models[words[1]] = words[2]
        if words[0] == ".subckt":
            ports[words[1]] = []
            for word in words[2:]:
                if word == "params:" or "=" in word:
                    break
                ports[words[1]].append(word)
    types = {name: models[words[5]] for name, words in cards.items() if name[0] == "m"}
    ends = {
        name: (words[1], words[3] if name[0] in "mqjz" else words[2])
        for name, words in cards.items() if name[0] in MOS.PATH_NODES
    }
    incident = collections.defaultdict(set)
    pin_incident = collections.defaultdict(list)
    for name, words in cards.items():
        if name in ends:
            for net in ends[name]:
                incident[net].add(name)
        kind = name[0]
        if kind == "k":
            nodes = []
        elif kind == "x":
            # The converted deck spells the declared cell after all its ports.
            matches = [i for i, word in enumerate(words[1:], 1)
                       if word in ports and i == len(ports[word]) + 1]
            if len(matches) != 1:
                raise ValueError(f"ambiguous subcircuit call: {words}")
            nodes = words[1:matches[0]]
        else:
            count = 4 if kind in "megsto" else 3 if kind in "qjzu" else 2
            nodes = words[1:1 + count]
        for terminal, net in enumerate(nodes):
            pin_incident[net].append((kind, terminal))

    def eligible(name):
        words = cards[name]
        return (name[0] == "m" and types[name] == "pmos" and
                len(set(words[1:4])) == 3 and
                not MOS.rail(words[1]) and not MOS.rail(words[3]))

    def gate_only(name):
        return all(kind == "m" and pin == 1
                   for kind, pin in pin_incident[cards[name][2]])

    def capacitor(net, gate, opposite, grounded):
        for name in incident[net]:
            if name[0] != "c":
                continue
            a, b = ends[name]
            other = b if a == net else a
            if other in (net, gate, opposite):
                continue
            if not grounded or MOS.rail(other) == "sink":
                return True
        return False

    shunts = {
        other for name, words in cards.items()
        if name[0] == "m" and types[name] == "nmos" and len(set(words[1:4])) == 3
        for sink, other in ((words[1], words[3]), (words[3], words[1]))
        if MOS.rail(sink) == "sink"
    }
    coils = {
        name: (a, b) for name, (a, b) in ends.items()
        if name[0] == "l" and a != b and not MOS.rail(a) and not MOS.rail(b)
        and {a, b} & shunts
    }
    coil_nodes = {net for pair in coils.values() for net in pair}
    buses = {
        net for net, names in incident.items()
        if all(eligible(name) and gate_only(name) for name in names)
        and any(set(ends[name]) & coil_nodes for name in names)
    }
    selected = {}
    for name, words in cards.items():
        if name[0] != "m":
            continue
        a, gate, b = words[1:4]
        pairs = ((a, b), (b, a))
        reservoir = eligible(name) and any(
            node in coil_nodes and capacitor(other, gate, node, True)
            for node, other in pairs)
        bus = eligible(name) and bool({a, b} & buses)
        core = bus and any(
            node in buses and (other in coil_nodes or capacitor(other, gate, node, False))
            for node, other in pairs)
        selected[name] = dict(type=types[name], selected=reservoir or core,
                              reservoir=reservoir, input_bus=core,
                              unrestricted_bus=bus, gate_only=gate_only(name), nets=words[1:5])
    path_coils = {
        name: pair for name, pair in coils.items()
        if any(row["selected"] and {row["nets"][0], row["nets"][2]} & set(pair)
               for row in selected.values())
    }
    return selected, path_coils


def horizontal(terminals):
    a, b = terminals
    if (a[0] == b[0]) == (a[1] == b[1]):
        raise ValueError(f"nonorthogonal or zero-length source path: {terminals}")
    return a[1] == b[1]


def summarize(rows):
    return dict(devices=len(rows), circuits=len({row["id"] for row in rows}),
                horizontal=sum(row["horizontal"] for row in rows),
                exceptions=[row["id"] + ":" + row["card"] for row in rows
                            if not row["horizontal"]])


def chain(human, drawn, selected, coil, pair):
    """Source row/order oracle for the independently selected main switches."""
    switches = [[name for name, row in selected.items() if row["selected"] and
                 net in (row["nets"][0], row["nets"][2])] for net in pair]
    result = dict(id=human["id"], coil=coil, endpoint_switches=switches)
    if any(len(names) != 1 for names in switches):
        result["ambiguous"] = True
        return result
    centers = []
    for name in (switches[0][0], coil, switches[1][0]):
        terms = drawn[name]["terminals"]
        a, b = [terms[term] for term in "DS"] if name[0] == "m" else list(terms.values())
        centers.append([(a[i] + b[i]) / 2 for i in (0, 1)])
    a, b, c = centers
    result.update(ambiguous=False, centers=centers, same_row=a[1] == b[1] == c[1],
                  coil_between=min(a[0], c[0]) < b[0] < max(a[0], c[0]))
    return result


def block_outputs(text):
    """Named output pins from the deck's port declarations, without geometry."""
    ports = {}
    for line in text.lower().splitlines():
        words = line.split()
        if words and words[0] == ".subckt":
            ports[words[1]] = words[2:]
    outputs = []
    for name, words in MOS.read_cards(text).items():
        if not name.startswith("x"):
            continue
        matches = [i for i, word in enumerate(words[1:], 1)
                   if word in ports and i == len(ports[word]) + 1]
        if len(matches) != 1:
            raise ValueError(f"ambiguous subcircuit call: {words}")
        index = matches[0]
        for pin, net in zip(ports[words[index]], words[1:index]):
            if pin in ("out", "vout", "vo", "output"):
                outputs.append((name, pin, net))
    return outputs


def shunt_interval(coil, main, shunt):
    """Literal terminal geometry, invariant under horizontal reflection."""
    low, high = sorted((coil[0], main[0]))
    return dict(coil_xy=coil, main_xy=main, shunt_xy=shunt,
                inside=low <= shunt[0] <= high, strict=low < shunt[0] < high,
                below=shunt[1] > max(coil[1], main[1]))


def path_pin(device, net, native=False):
    """One electrical path terminal on net; a gate or body cannot match."""
    mos = device.get("card", device.get("name", "")).startswith("m")
    pins = ([(p["term"], p["net"], p["xy"]) for p in device["pins"]] if native else
            [(pin, device["nets"][pin], xy) for pin, xy in device["terminals"].items()])
    matched = [xy for pin, on, xy in pins if on == net and (not mos or pin.lower() in ("d", "s"))]
    if len(matched) != 1:
        raise ValueError(f"{device.get('card', device.get('name'))}:{net}: ambiguous path pin")
    return matched[0]


def interval_summary(rows):
    """Retain exact eligible names and counterexamples, not counts alone."""
    result = {}
    for name, selected in (("all", rows), ("unique_endpoint", [r for r in rows if r["unique_endpoint"]])):
        result[name] = dict(devices=len(selected), circuits=len({r["id"] for r in selected}),
                            inside=sum(r["interval"]["inside"] for r in selected),
                            strict=sum(r["interval"]["strict"] for r in selected),
                            below=sum(r["interval"]["below"] for r in selected),
                            names=[r["id"] + ":" + r["card"] for r in selected],
                            exceptions=[r for r in selected if not r["interval"]["inside"]])
    result["ambiguous_endpoints"] = [r["id"] + ":" + r["card"] for r in rows if not r["unique_endpoint"]]
    return result


def controls(human, drawn, selected, outputs, pair, group):
    """Check independently selected power-path controls against source pins.

    The main switch's gate net selects an active transistor channel driver
    or a named block output. Grounded shunts need gate-only external control;
    a bias transistor merely touching the coil is deliberately not selected.
    """
    if group["ambiguous"]:
        return [], [], [], []
    power_y = group["centers"][1][1]
    drivers, blocks, shunts, gates = [], [], [], []
    main_switches = [names[0] for names in group["endpoint_switches"]]
    for main in main_switches:
        gate = selected[main]["nets"][1]
        terminal = drawn[main]["terminals"]["G"]
        ends = [drawn[main]["terminals"][key] for key in "DS"]
        gates.append(dict(id=human["id"], card=main,
                          reservoir_only=all(selected[m]["reservoir"] for m in main_switches),
                          external=selected[main]["gate_only"],
                          gate_down=terminal[1] > sum(pt[1] for pt in ends) / 2))
        for name, row in selected.items():
            if name == main or gate not in (row["nets"][0], row["nets"][2]):
                continue
            ends = [drawn[name]["terminals"][key] for key in "DS"]
            drivers.append(dict(id=human["id"], coil=group["coil"], main=main, card=name, terminals=ends,
                                power_y=power_y, below=min(pt[1] for pt in ends) > power_y))
        for name, output, net in outputs:
            if net != gate:
                continue
            device = drawn[name]
            source_pin = next(pin for pin in device["nets"] if pin.lower() == output)
            if device["nets"][source_pin] != net:
                raise ValueError(f"{human['id']}:{name}:{output}: block output net mismatch")
            pt = device["terminals"][source_pin]
            blocks.append(dict(id=human["id"], coil=group["coil"], main=main, card=name, output=output,
                               gate_xy=terminal, output_xy=pt, power_y=power_y,
                               below=pt[1] > power_y, same_x=pt[0] == terminal[0],
                               at_or_below_gate=pt[1] >= terminal[1]))
    for name, row in selected.items():
        a, gate, b, _ = row["nets"]
        if (row["type"] != "nmos" or len({a, gate, b}) != 3 or not row["gate_only"] or
                not any(MOS.rail(sink) == "sink" and other in pair
                        for sink, other in ((a, b), (b, a)))):
            continue
        ends = [drawn[name]["terminals"][key] for key in "DS"]
        net = a if a in pair else b
        main = next(m for m in main_switches if net in (selected[m]["nets"][0], selected[m]["nets"][2]))
        interval = shunt_interval(path_pin(drawn[group["coil"]], net), path_pin(drawn[main], net),
                                  path_pin(drawn[name], net))
        shunts.append(dict(id=human["id"], coil=group["coil"], card=name, main=main, endpoint_net=net,
                           interval=interval, terminals=ends, power_y=power_y,
                           below=min(pt[1] for pt in ends) > power_y))
    counts = collections.Counter(r["endpoint_net"] for r in shunts)
    for row in shunts:
        row["unique_endpoint"] = counts[row["endpoint_net"]] == 1
    return drivers, blocks, shunts, gates


def native_controls(directory, groups, chains, gates):
    """Check the same named terminal relations in retained native drawings."""
    drawings, inputs, summary = {}, {}, {}
    intervals = []

    def devices_for(name):
        if name not in drawings:
            path = directory / (name + ".json")
            content = path.read_bytes()  # A missing drawing is a failure.
            inputs[name] = hashlib.sha256(content).hexdigest()
            devices = json.loads(content)["devices"]
            drawings[name] = {device["name"]: device for device in devices}
        return drawings[name]

    for key, rows in groups.items():
        observed = []
        for row in rows:
            name = row["id"]
            devices = devices_for(name)
            coil = devices[row["coil"]]
            a, b = [pin["xy"] for pin in coil["pins"]]
            power_y = (a[1] + b[1]) / 2
            pins = {pin["term"].lower(): pin["xy"] for pin in devices[row["card"]]["pins"]}
            actual = dict(id=name, card=row["card"], coil=row["coil"], power_y=power_y)
            if key == "block_outputs":
                output = pins[row["output"]]
                main_pins = {pin["term"].lower(): pin["xy"] for pin in devices[row["main"]]["pins"]}
                actual.update(below=output[1] > power_y, same_x=output[0] == main_pins["g"][0],
                              at_or_below_gate=output[1] >= main_pins["g"][1], output_xy=output)
            else:
                actual.update(below=min(pins["d"][1], pins["s"][1]) > power_y,
                              terminals=[pins["d"], pins["s"]])
            if key == "ground_shunts":
                net = row["endpoint_net"]
                points = [path_pin(devices[d], net, True) for d in (row["coil"], row["main"], row["card"])]
                actual.update(main=row["main"], endpoint_net=net, unique_endpoint=row["unique_endpoint"],
                              interval=shunt_interval(*points))
                intervals.append(actual)
            observed.append(actual)
        summary[key] = dict(devices=len(observed), below=sum(row["below"] for row in observed),
                            exceptions=[row for row in observed if not row["below"]])
        if key == "block_outputs":
            summary[key].update(same_x=sum(row["same_x"] for row in observed),
                                at_or_below_gate=sum(row["at_or_below_gate"] for row in observed))
    observed = []
    for group in chains:
        if group["ambiguous"]:
            raise ValueError(f"{group['id']}:{group['coil']}: ambiguous source series group")
        devices = devices_for(group["id"])
        names = [group["endpoint_switches"][0][0], group["coil"], group["endpoint_switches"][1][0]]
        centers = []
        for i, name in enumerate(names):
            pins = {pin["term"].lower(): pin["xy"] for pin in devices[name]["pins"]}
            a, b = list(pins.values()) if i == 1 else [pins[term] for term in ("d", "s")]
            centers.append([(a[k] + b[k]) / 2 for k in (0, 1)])
        a, b, c = centers
        observed.append(dict(id=group["id"], members=names, centers=centers,
                             same_row=a[1] == b[1] == c[1],
                             coil_between=min(a[0], c[0]) < b[0] < max(a[0], c[0])))
    summary["chains"] = dict(devices=len(observed), same_row=sum(r["same_row"] for r in observed),
                             coil_between=sum(r["coil_between"] for r in observed),
                             exceptions=[r for r in observed if not r["same_row"] or not r["coil_between"]])
    for key, external in (("reservoir_external_gates", True), ("reservoir_active_gates", False)):
        observed = []
        for row in gates:
            if not row["reservoir_only"] or row["external"] != external:
                continue
            devices = devices_for(row["id"])
            pins = {pin["term"].lower(): pin["xy"] for pin in devices[row["card"]]["pins"]}
            down = pins["g"][1] > (pins["d"][1] + pins["s"][1]) / 2
            observed.append(dict(id=row["id"], card=row["card"], source_down=row["gate_down"],
                                 native_down=down, agrees=down == row["gate_down"]))
        summary[key] = dict(devices=len(observed), agrees=sum(row["agrees"] for row in observed),
                            exceptions=[row for row in observed if not row["agrees"]])
    summary["shunt_intervals"] = interval_summary(intervals)
    return dict(input_sha256=inputs, summary=summary, ground_shunt_intervals=intervals)


def main():
    # Literal geometry oracle, including endpoint equality and reflection.
    assert shunt_interval([0, 0], [100, 0], [30, 40])["strict"]
    assert shunt_interval([0, 0], [-100, 0], [-30, 40])["strict"]
    assert not shunt_interval([0, 0], [100, 0], [110, 40])["inside"]
    assert shunt_interval([0, 0], [100, 0], [0, 40])["inside"]
    assert not shunt_interval([0, 0], [100, 0], [0, 40])["strict"]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path, help="Retained native JSON directory; check the same named control relations")
    args = parser.parse_args()
    rows, coils, chains = [], [], []
    drivers, blocks, shunts, gates = [], [], [], []
    digest = hashlib.sha256()
    source_svgs = {}
    paths = sorted(args.examples.glob("*.human.json"))
    if not paths:
        parser.error("no *.human.json files")
    for path in paths:
        human = json.loads(path.read_text())
        deck = path.with_name(human["id"] + ".cir")
        try:
            selected, path_coils = classify(deck.read_text())
        except (ValueError, KeyError) as error:
            raise ValueError(f"{human['id']}: unsupported deck: {error}") from error
        for source in (path, deck):
            digest.update(source.name.encode() + b"\0" + source.read_bytes() + b"\0")
        drawn = {device["card"]: device for device in human["devices"]}
        outputs = block_outputs(deck.read_text()) if path_coils else []
        if path_coils:
            svg = path.with_name(human["id"] + ".svg")
            source_svgs[human["id"]] = hashlib.sha256(svg.read_bytes()).hexdigest()
        for name, row in selected.items():
            device = drawn[name]
            # Depletion is a threshold variant of the same channel polarity.
            if device["type"].removeprefix("depletion-") != row["type"]:
                raise ValueError(f"{human['id']}:{name}: deck/source model mismatch")
            for term, net in zip("DGSB", row["nets"]):
                if device["nets"][term] != net:
                    raise ValueError(f"{human['id']}:{name}:{term}: deck/source net mismatch")
            row.update(id=human["id"], card=name, title=human["title"],
                       horizontal=horizontal([device["terminals"][term] for term in "DS"]))
            rows.append(row)
        for name, pair in path_coils.items():
            device = drawn[name]
            if tuple(device["nets"].values()) != pair:
                raise ValueError(f"{human['id']}:{name}: coil endpoint mismatch")
            coils.append(dict(id=human["id"], card=name, nets=pair,
                              horizontal=horizontal(list(device["terminals"].values()))))
            group = chain(human, drawn, selected, name, pair)
            chains.append(group)
            observed = controls(human, drawn, selected, outputs, pair, group)
            for output, found in zip((drivers, blocks, shunts, gates), observed):
                output.extend(found)
    summary = {key: summarize([row for row in rows if row[key]])
               for key in ("reservoir", "input_bus", "selected", "unrestricted_bus")}
    summary["inductors"] = summarize(coils)
    summary["chains"] = dict(
        total=len(chains), unique=sum(not row["ambiguous"] for row in chains),
        same_row=sum(row.get("same_row", False) for row in chains),
        coil_between=sum(row.get("coil_between", False) for row in chains),
        exceptions=[row for row in chains if row["ambiguous"] or
                    not row["same_row"] or not row["coil_between"]])
    for key, observed in (("gate_drivers", drivers), ("block_outputs", blocks), ("ground_shunts", shunts)):
        summary[key] = dict(devices=len(observed), circuits=len({r["id"] for r in observed}),
                            below=sum(r["below"] for r in observed),
                            exceptions=[r for r in observed if not r["below"]])
    summary["block_outputs"].update(same_x=sum(r["same_x"] for r in blocks),
                                    at_or_below_gate=sum(r["at_or_below_gate"] for r in blocks))
    summary["shunt_intervals"] = interval_summary(shunts)
    summary["gate_directions"] = {
        family: dict(devices=sum(r["reservoir_only"] == reservoir for r in gates),
                     down=sum(r["reservoir_only"] == reservoir and r["gate_down"] for r in gates),
                     external=sum(r["reservoir_only"] == reservoir and r["external"] for r in gates),
                     external_down=sum(r["reservoir_only"] == reservoir and r["external"] and r["gate_down"] for r in gates))
        for family, reservoir in (("reservoir_only", True), ("input_bus", False))}
    result = dict(corpus_sha256=digest.hexdigest(), source_svg_sha256=source_svgs, drawings=len(paths), summary=summary,
                  selected=[row for row in rows if row["selected"]], inductors=coils, chains=chains,
                  gate_drivers=drivers, block_outputs=blocks, ground_shunts=shunts, gate_directions=gates,
                  unselected_horizontal=[row for row in rows if not row["selected"] and row["horizontal"]],
                  unrestricted_exceptions=[row for row in rows if row["unrestricted_bus"] and not row["horizontal"]])
    if args.native:
        result["native_controls"] = native_controls(args.native, dict(
            gate_drivers=drivers, block_outputs=blocks, ground_shunts=shunts), chains, gates)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in ("corpus_sha256", "drawings", "summary")}, indent=2))


if __name__ == "__main__":
    main()
