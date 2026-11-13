#!/usr/bin/env python3
"""All complete generic comparator contracts plus explicit ICM: source/native ink.

Usage: comparator_strokes_native.py SOURCE_REPORT EXAMPLES NATIVE_DIR OUTPUT --bin BIN

Known source/native gaps remain named: AG1390 is a source box despite a
complete contract; AG1398 lacks a positive mark. These exceptions do not
waive ordered electrical bindings, semantic native signal geometry or steps.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import block_aliases as source
import block_aliases_native as native
import comparator_strokes as strokes


def roles(ports):
    values = [source.role(p) for p in ports]
    if "positive" in values:
        values = ["negative" if p == "vin" else value for p, value in zip(ports, values)]
    inputs = [v for v in values if v in source.INPUTS]
    if (not 2 <= len(ports) <= 8 or None in values or len(set(values)) != len(values)
            or values.count("output") != 1
            or not (len(inputs) == 1 or sorted(inputs) == ["negative", "positive"])):
        return None
    return values


def contextual_signs(observed, ports, values):
    if observed["shape"] != "triangle":
        return {p: False for p, value in zip(ports, values) if value in ("positive", "negative")}
    body = observed["body_local"]
    bases = [(a, b) for a, b in zip(body, body[1:] + body[:1])
             if abs(a[0] - b[0]) < .01 or abs(a[1] - b[1]) < .01]
    if len(bases) != 1:
        raise ValueError("no unique native input base")
    a, b = bases[0]
    axis = 0 if abs(a[1] - b[1]) < .01 else 1
    tolerance = native.PIXEL_TOLERANCE / observed["display_scale"]
    checks = {}
    for port, value in zip(ports, values):
        if value not in ("positive", "negative"):
            continue
        lead = next(p for p in observed["leads"] if p["term"] == port)
        wanted = "+" if value == "positive" else "-"
        checks[port] = (native.edge_point(lead["attachment"], a, b, tolerance)
                        and sum(sign["text"] == wanted and abs(sign["at"][axis] - lead["endpoint"][axis]) < tolerance
                                for sign in observed["signs"]) == 1)
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source_report", "examples", "native_dir", "output"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--bin", required=True, type=Path)
    args = parser.parse_args()
    native.selfcheck()
    assert roles(["vdd", "vip", "vin", "vout"]) == ["supply", "positive", "negative", "output"]
    assert roles(["vin", "out"]) == ["unsigned", "output"]
    assert roles(["vdd", "inn", "in", "out"]) is None
    assert roles(["vip", "inn", "vin", "out"]) is None
    literal = dict(shape="triangle", body_local=[[-40, -40], [40, 0], [-40, 40]], display_scale=1,
                   leads=[dict(term="vip", attachment=[-40, 20], endpoint=[-60, 20]),
                          dict(term="vin", attachment=[-40, -20], endpoint=[-60, -20])],
                   signs=[dict(text="+", at=[-30, 20]), dict(text="-", at=[-30, -20])])
    assert all(contextual_signs(literal, ["vip", "vin"], ["positive", "negative"]).values())
    literal["signs"][1]["at"] = [-30, 20]
    assert not contextual_signs(literal, ["vip", "vin"], ["positive", "negative"])["vin"]
    report = json.loads(args.source_report.read_text())
    inventory_path = Path(strokes.__file__).with_name("comparator_strokes_cases.json")
    inventories = json.loads(inventory_path.read_text())
    inventory = inventories["corpora"][args.examples.name]
    if report["inventory_sha256"] != hashlib.sha256(inventory_path.read_bytes()).hexdigest():
        raise ValueError("comparator inventory changed; rerun the source audit")
    actual = {f: {style: sorted(r["id"] + ":" + r["card"] for r in report["instances"]
                               if r["family"] == f and r["style"] == style)
                  for style in strokes.STYLES} for f in strokes.FAMILIES}
    source.check_inventory(actual, inventory, "all source comparator names/styles")
    for name, expected in report["audit_sha256"].items():
        if hashlib.sha256(Path(strokes.__file__).with_name(name).read_bytes()).hexdigest() != expected:
            raise ValueError("source audit dependency changed: " + name)
    rows, excluded = [], []
    for row in report["instances"]:
        cid, card = row["id"], row["card"]
        for suffix in (".cir", ".svg", ".human.json"):
            path = args.examples / (cid + suffix)
            if hashlib.sha256(path.read_bytes()).hexdigest() != report["source_sha256"][path.name]:
                raise ValueError("source changed: " + str(path))
        candidates = [r for r in strokes.select((args.examples / (cid + ".cir")).read_text(), cid) if r["card"] == card]
        if len(candidates) != 1 or any(candidates[0][key] != row[key] for key in ("family", "ports", "bindings")):
            raise ValueError("source contract changed: " + cid + ":" + card)
        values = roles(row["ports"])
        if values is None:
            excluded.append(dict(id=cid, card=card, family=row["family"], ports=row["ports"]))
            continue
        human = json.loads((args.examples / (cid + ".human.json")).read_text())
        device = next(d for d in human["devices"] if d["card"].lower() == card)
        cached = {p.lower(): xy for p, xy in device["terminals"].items()}
        actual_signals, assignment_error = {}, None
        try:
            actual_signals, _ = source.signal_leads(row["body"], row["leads"], row["polarity_marks"], values)
        except ValueError as error:
            assignment_error = str(error)
        if row["style"] == "box":
            assignment_error = "opaque source body: semantic signal leads not assigned"
        mismatches = [p for p, value in zip(row["ports"], values) if value in actual_signals
                      and (p not in cached or not source.glyph.close(cached[p], actual_signals[value]))]
        expected = dict(row, roles=values, shape="box" if row["style"] == "box" else "triangle",
                        expected_marks=sorted(m["role"] for m in row["polarity_marks"]),
                        missing_source_ports=sorted(set(row["ports"]) - set(cached)),
                        signal_frame_mismatches=mismatches,
                        source_signal_assignment_error=assignment_error)
        rows.append(expected)
    names = lambda instances: sorted(r["id"] + ":" + r["card"] for r in instances)
    source.check_inventory(dict(complete_contracts=names(rows), excluded_contracts=names(excluded)),
                           inventories["native_contracts"][args.examples.name], "native comparator contract inventory")
    args.native_dir.mkdir(parents=True, exist_ok=True)
    for cid in sorted({r["id"] for r in rows}):
        run = subprocess.run([str(args.bin.resolve()), "--svg", str(args.native_dir / (cid + ".svg")),
                              str(args.examples / (cid + ".cir")), str(args.native_dir / (cid + ".json"))],
                             capture_output=True, text=True, timeout=30)
        if run.returncode:
            raise ValueError(cid + ": native renderer failed: " + run.stderr)
    selected, body_gaps, mark_gaps, step_failures, signal_failures = [], [], [], [], []
    for row in rows:
        cid, card, name = row["id"], row["card"], row["id"] + ":" + row["card"]
        jp, sp = [args.native_dir / (cid + suffix) for suffix in (".json", ".svg")]
        observed = native.inspect(json.loads(jp.read_text()), ET.parse(sp).getroot(), row)
        signs = contextual_signs(observed, row["ports"], row["roles"])
        expected_steps = []
        for step in row["steps"]:
            values = source.glyph.numbers(step["path"])
            points = list(zip(values[::2], values[1::2]))
            expected_steps.append([source.glyph.direction(a, b) for a, b in zip(points, points[1:])])
        actual_steps = [[source.glyph.direction(a, b) for a, b in zip(path["points"], path["points"][1:])]
                        for path in observed["interior_polylines"]]
        if not observed["shape_agrees"]:
            body_gaps.append(name)
        if not observed["signs_agree"]:
            mark_gaps.append(name)
        if expected_steps != actual_steps:
            step_failures.append(name)
        if not observed["signal_geometry_agrees"] or not all(signs.values()):
            signal_failures.append(name)
        selected.append(dict(id=cid, card=card, family=row["family"], roles=row["roles"],
                             source_style=row["style"], source_marks=row["expected_marks"],
                             source_signal_assignment_error=row["source_signal_assignment_error"],
                             source_frame_mismatches=row["signal_frame_mismatches"],
                             native=observed, contextual_native_sign_bindings=signs,
                             source_step_directions=expected_steps, native_step_directions=actual_steps,
                             native_sha256={p.suffix: hashlib.sha256(p.read_bytes()).hexdigest() for p in (jp, sp)}))
    summary = dict(instances=len(selected), generic=sum(r["family"] != "icm_ideal_comparator_vdd" for r in selected),
                   icm=sum(r["family"] == "icm_ideal_comparator_vdd" for r in selected),
                   ordered_ports=sum(len(r["native"]["ordered_ports"]) for r in selected),
                   source_body_gaps=body_gaps, source_mark_gaps=mark_gaps,
                   source_signal_assignment_unresolved=[r["id"] + ":" + r["card"] for r in selected if r["source_signal_assignment_error"]],
                   step_failures=step_failures, native_signal_failures=signal_failures)
    result = dict(summary=summary, selected=selected, excluded_incomplete_contracts=excluded,
                  selected_names=sorted(r["id"] + ":" + r["card"] for r in selected),
                  renderer_sha256=hashlib.sha256(args.bin.read_bytes()).hexdigest(),
                  source_report_sha256=hashlib.sha256(args.source_report.read_bytes()).hexdigest(),
                  source_inventory_sha256=hashlib.sha256(inventory_path.read_bytes()).hexdigest(),
                  audit_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                  native_adapter_sha256=hashlib.sha256(Path(native.__file__).read_bytes()).hexdigest(),
                  limits="Known source body/polarity gaps remain explicit. Step count, four-vertex segment directions and native semantic signal bindings are checked independently. No complete stroke dimensions, source frame or routing parity claim.")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(summary, indent=2, sort_keys=True))
    known_body_gaps = ["ag-1390:x1"] if args.examples.name == "analoggenie" else []
    known_mark_gaps = ["ag-1390:x1", "ag-1398:x1"] if args.examples.name == "analoggenie" else []
    source.check_inventory(body_gaps, known_body_gaps, "known source body gaps")
    source.check_inventory(mark_gaps, known_mark_gaps, "known source mark gaps")
    source.check_inventory(step_failures, [], "interior step differences")
    source.check_inventory(signal_failures, [], "native semantic signal failures")


if __name__ == "__main__":
    main()
