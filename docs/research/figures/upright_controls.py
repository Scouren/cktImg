#!/usr/bin/env python3
"""Evaluate upright control-facing hypotheses without changing placement.

Usage: upright_controls.py EXAMPLES GATE_STUDY SCORECARD OUTPUT

GATE_STUDY is gate_facing.py's source/native correspondence output. SCORECARD
is the frozen corpus_score.py result from the same native snapshot. Source
predicates use only source coordinates; native predicates use only generated
coordinates. Each oracle is the independently extracted source gate side.
The scorecard's single whole-drawing horizontal reflection is held fixed.

This distinction matters: 285/288 source-aligned unique drivers does not
prove that the same rule will improve native schematics. Native placement
creates different alignments. A local relation may also agree with the
source while disagreeing with its globally reflected absolute gate side.
The output retains both qualifications, every changed name, and hashes;
related textbook variants are not independent statistical observations.
It also reports the result when existing two-device pair/cross/mirror/bank
orientation overrides are preserved, using frozen report certificates.
No candidate in this exploratory study changes the engine.
"""

import argparse
import hashlib
import json
from pathlib import Path


RULES = ("unanimous", "unique", "unique_aligned", "all_aligned", "column_spans_gate")
FLIP = {"left": "right", "right": "left"}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def predict(rule, center, gate, drivers, tolerance):
    if not drivers:
        return None
    left = all(p[0] < center[0] - tolerance for p in drivers)
    right = all(p[0] > center[0] + tolerance for p in drivers)
    if not (left or right):
        return None
    aligned = all(abs(p[1] - gate[1]) <= tolerance for p in drivers)
    if rule in ("unique", "unique_aligned") and len(drivers) != 1:
        return None
    if rule in ("unique_aligned", "all_aligned") and not aligned:
        return None
    if rule == "column_spans_gate":
        xs, ys = zip(*drivers)
        if max(xs) - min(xs) > tolerance or not min(ys) - tolerance <= gate[1] <= max(ys) + tolerance:
            return None
    return "left" if left else "right"


def self_test():
    assert predict("unique_aligned", [100, 40], [70, 40], [[20, 40]], 2) == "left"
    assert predict("unique_aligned", [100, 40], [70, 40], [[20, 80]], 2) is None
    assert predict("unique_aligned", [100, 40], [70, 40], [[20, 40], [30, 40]], 2) is None
    assert predict("all_aligned", [100, 40], [70, 40], [[20, 40], [30, 40]], 2) == "left"
    assert predict("unanimous", [100, 40], [70, 40], [[20, 40], [120, 40]], 2) is None
    assert predict("column_spans_gate", [100, 40], [70, 40], [[20, 0], [20, 80]], 2) == "left"
    assert predict("column_spans_gate", [100, 40], [70, 40], [[20, 80], [20, 120]], 2) is None
    assert predict("unanimous", [100, 40], [70, 40], [], 2) is None


def evaluate(rule, rows, scorecard):
    output = []
    for row in rows:
        # Source units are recorded with the correspondence. The native
        # geometry uses unit40 and the scorecard's fixed tolerance2.
        source = predict(rule, row["center"], row["gate_point"],
                         [d["point"] for d in row["drivers"]], row["source_tolerance"])
        native = row["native"]
        prediction = None
        current = native.get("current")
        if "center" in native:
            prediction = predict(rule, native["center"], native["gate"], native["drivers"], 2)
        if scorecard[row["id"]]["structure"]["mirrored"]:
            current = FLIP.get(current)
            prediction = FLIP.get(prediction)
        output.append(dict(name=row["name"], source=row["gate"], source_prediction=source,
                           native_current=current, native_prediction=prediction))
    selected = [r for r in output if r["source_prediction"]]
    native = [r for r in output if r["native_prediction"]]
    changed = [r for r in native if r["native_prediction"] != r["native_current"]]
    return dict(source_selected=[r["name"] for r in selected],
                source_agrees=[r["name"] for r in selected if r["source_prediction"] == r["source"]],
                source_exceptions=[r["name"] for r in selected if r["source_prediction"] != r["source"]],
                native_selected=[r["name"] for r in native],
                qualification_intersection=[r["name"] for r in native if r["source_prediction"]],
                native_changes=[r["name"] for r in changed],
                native_fixes=[r["name"] for r in changed if r["native_prediction"] == r["source"]],
                native_regressions=[r["name"] for r in changed if r["native_current"] == r["source"]],
                rows=output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("gate_study", type=Path)
    parser.add_argument("scorecard", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    self_test()
    study = json.loads(args.gate_study.read_text())
    scores = json.loads(args.scorecard.read_text())
    if study["native_errors"]:
        raise ValueError("unresolved native terminal correspondences")
    if study["native_binary_sha256"] != scores["binary_sha256"]:
        raise ValueError("native binary hashes differ")
    rows = [r for r in study["rows"] if r["axis"] == 0]
    hashes = {s["id"]: s["human_sha256"] for s in study["sources"]}
    tolerances = {}
    for row in rows:
        cid = row["id"]
        if cid not in tolerances:
            path = args.examples / (cid + ".human.json")
            if digest(path) != hashes[cid]:
                raise ValueError("source hash differs: " + cid)
            tolerances[cid] = json.loads(path.read_text())["unit"] / 20
        row["source_tolerance"] = tolerances[cid]
    rules = {rule: evaluate(rule, rows, scores["results"]) for rule in RULES}
    protected = set()
    for cid, result in scores["results"].items():
        path = args.scorecard.parent / (cid + ".report.json")
        if digest(path) != result["report_sha256"]:
            raise ValueError("native report hash differs: " + cid)
        for line in json.loads(path.read_text())["decisions"]:
            words = line.split()
            if len(words) == 5 and words[:2] == ["*@", "group"] and words[2] in ("pair", "cross", "mirror", "bank"):
                protected.update(cid + ":" + name for name in words[3:])
    for rule in rules.values():
        rule["preserve_two_device_groups"] = {
            key: [name for name in rule[key] if name not in protected]
            for key in ("native_changes", "native_fixes", "native_regressions")}
    expected = ["ag-1702:m4", "ag-1738:m1", "ag-1738:m2"]
    if rules["unique_aligned"]["source_exceptions"] != expected:
        raise ValueError("unique-aligned source exception names changed")
    result = dict(schema=1, script_sha256=digest(Path(__file__)),
                  gate_study_sha256=digest(args.gate_study), scorecard_sha256=digest(args.scorecard),
                  source_corpus_sha256=study["corpus_sha256"], native_binary_sha256=scores["binary_sha256"],
                  sources=study["sources"], protected=sorted(protected), rules=rules)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({k: {field: len(value) if isinstance(value, list) else {f: len(ns) for f, ns in value.items()}
                         for field, value in v.items() if field != "rows"}
                      for k, v in rules.items()}, indent=2))


if __name__ == "__main__":
    main()
