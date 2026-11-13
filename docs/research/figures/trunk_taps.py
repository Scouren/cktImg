#!/usr/bin/env python3
"""Replay iteration15 interval evidence and named routing followups.

Uses the unchanged trunk_rungs source/native verifier. The supplied native
binary runs eight diagnostic probes: four high crossing budgets and four
explicit wire requests. Raising cross_max does not disable cut_max=2.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

from input_resistor_legs import connection
from trunk_rungs import audit, horizontal_rows, interval, pins, segments, source_loss

DEPENDENCIES = ("trunk_rungs.py", "channel_bridges.py", "cross_caps.py", "input_resistor_legs.py",
                "input_resistors.py", "converter_loops.py", "converter_terminals.py", "sampling_cells.py")
PROBES = ((2309, "vx", ("m11", "m12")), (2318, "vx", ("m11", "m12")),
          (2319, "vx", ("m11", "m12")), (2452, "vz", ("m34", "m40")))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def state(path, net, names):
    drawing = json.loads(path.read_text())
    actual = pins(drawing)
    targets = [actual[name, 1][1] for name in names]
    assert all(actual[name, 1][0] == net for name in names)
    wires = segments(drawing, net)
    return dict(native_sha256=digest(path), targets=targets, segments=wires,
                straight=interval(horizontal_rows(drawing).get((net, targets[0][1]), []), *targets),
                connection=connection(wires, targets),
                labels=[label for label in drawing["labels"] if label["net"] == net])


def crossings(tree, drawing, net):
    """Strict proper crossings; the three selected VX decks use these rails."""
    found = []
    for wire in drawing["wires"]:
        if wire["net"] in (net, "0", "vdd", "vss"):
            continue
        for poly in wire["segments"]:
            for c, d in zip(poly, poly[1:]):
                for a, b in tree:
                    h, v = ((a, b), (c, d)) if a[1] == b[1] else ((c, d), (a, b))
                    if h[0][1] != h[1][1] or v[0][0] != v[1][0]:
                        continue
                    x, y = v[0][0], h[0][1]
                    if min(h[0][0], h[1][0]) < x < max(h[0][0], h[1][0]) and min(v[0][1], v[1][1]) < y < max(v[0][1], v[1][1]):
                        found.append(dict(net=wire["net"], at=[x, y], target_segment=[a, b], other_segment=[c, d]))
    return sorted(found, key=lambda row: (row["net"], row["at"], row["target_segment"], row["other_segment"]))


def followups(examples, before, after, binary):
    frozen = json.loads(Path(__file__).with_name("trunk_rungs_cases.json").read_text())
    originals = []
    for row in frozen["analoggenie"]["source_losses"]:
        if row["id"] not in ("ag-981", "ag-984", "ag-986", "ag-2376"):
            continue
        old = json.loads((before / (row["id"] + ".json")).read_text())
        new = json.loads((after / (row["id"] + ".json")).read_text())
        names = [name for name, _ in row["pins"]]
        changed = {key: row[key] for key in ("id", "net", "pins")}
        changed.update(before=[pins(old)[name, 1][1] for name in names],
                       after=[pins(new)[name, 1][1] for name in names])
        verified = source_loss(examples, changed, old, new)
        verified["native_states"] = {label: state(directory / (row["id"] + ".json"), row["net"], names)
                                     for label, directory in (("baseline", before), ("candidate", after))}
        originals.append(verified)
    assert {row["id"] for row in originals} == {"ag-981", "ag-984", "ag-986", "ag-2376"}
    probes = []
    config_text = ".{ .layout = .{ .cross_max = 1000 } }\n"
    with tempfile.TemporaryDirectory(prefix="cktimg-trunk-taps-") as tmp:
        work = Path(tmp)
        config = work / "high-cross-budget.zon"
        config.write_text(config_text)
        for number, net, names in PROBES:
            ident = f"ag-{number}"
            source = examples / (ident + ".cir")
            original = source.read_text()
            assert original.lower().count(".ends dut") == 1
            edited = original.replace(".ends dut", f"*@ wire {net}\n.ends dut")
            assert edited != original
            deck = work / (ident + ".cir")
            deck.write_text(edited)
            row = dict(id=ident, net=net, pins=[[name, 1] for name in names],
                       source_sha256=digest(source), wire_deck_sha256=digest(deck),
                       wire_edit=dict(before=".ends dut", after=f"*@ wire {net}\n.ends dut"), probes={})
            for kind, source_path in (("high_cross_budget", source), ("explicit_wire", deck)):
                output, report = work / "drawing.json", work / "report.json"
                command = [str(binary)]
                template = ["{candidate_binary}"]
                if kind == "high_cross_budget":
                    command += ["--config", str(config)]
                    template += ["--config", "{high_cross_budget_config}"]
                command += ["--report", str(report), str(source_path), str(output)]
                template += ["--report", "{report}", "{source_deck}" if kind == "high_cross_budget" else "{wire_deck}", "{drawing}"]
                subprocess.run(command, check=True, capture_output=True, text=True)
                verdicts = json.loads(report.read_text())["requests"]
                if kind == "explicit_wire":
                    verdict = [v for v in verdicts if v["text"] == f"*@ wire {net}"]
                    assert len(verdict) == 1 and verdict[0]["state"] == "honoured"
                row["probes"][kind] = dict(command=template, report_sha256=digest(report), requests=verdicts,
                                           **state(output, net, names))
            if net == "vx":
                old = json.loads((before / (ident + ".json")).read_text())
                new = json.loads((after / (ident + ".json")).read_text())
                tree = segments(old, net)
                row["crossing_overlay"] = dict(excluded_rails=["0", "vdd", "vss"],
                    definition="unchanged baseline VX ink against baseline/candidate other-net ink; not a thinning-round trace",
                    baseline=crossings(tree, old, net), candidate=crossings(tree, new, net))
            probes.append(row)
    return dict(original_source_cases=originals, routing_probes=probes,
                high_cross_budget_config=config_text,
                candidate_executable_sha256=digest(binary))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    for name in ("ag-baseline", "ag-candidate", "ams-baseline", "ams-candidate", "binary"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = {}
    for corpus, before, after in (("analoggenie", args.ag_baseline, args.ag_candidate), ("amsnet", args.ams_baseline, args.ams_candidate)):
        result[corpus] = audit(args.examples / corpus, before, after)
        result[corpus]["dependency_sha256"] = {name: digest(Path(__file__).with_name(name)) for name in DEPENDENCIES}
    result["followups"] = followups(args.examples / "analoggenie", args.ag_baseline, args.ag_candidate, args.binary.resolve())
    result["companion_sha256"] = digest(Path(__file__))
    normalized = json.loads(json.dumps(result))
    if args.check:
        frozen = json.loads(Path(__file__).with_name("trunk_taps_cases.json").read_text())
        if normalized != frozen:
            raise ValueError("trunk tap evidence differs from the exact frozen inventory")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({corpus: {bucket: {key: len(value) if isinstance(value, list) else value for key, value in row.items()}
                       for bucket, row in result[corpus]["counts"].items()} for corpus in ("analoggenie", "amsnet")}, indent=2))


if __name__ == "__main__":
    main()
