#!/usr/bin/env python3
"""Replay frozen native sampling cells, then request only mismatching C axes.

Usage: sampling_cells_probe.py <study.json> <examples> <frozen-native-dir>
       <work-dir> <output.json>

This is deliberately a capacitor-only probe. Public `bridge` does not admit
MOS; `at` would also change the placement pipeline and is not used. Full
baseline JSON and reports must replay byte-for-byte with the frozen executable.
All selected group geometry and every explicit-hint verdict are retained.
No production source is changed and no builds are performed.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import subprocess

from sampling_cells import geometry


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(binary, deck, stem):
    geom, report = stem.with_suffix(".json"), stem.with_suffix(".report.json")
    subprocess.run([str(binary), "--report", str(report), str(deck), str(geom)], check=True, capture_output=True)
    return geom, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("study", "examples", "frozen", "work", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    study = json.loads(args.study.read_text())
    groups = collections.defaultdict(list)
    for row in study["selected"]:
        groups[row["id"]].append(row)
    args.work.mkdir(exist_ok=True, parents=True)
    binary = args.frozen / "cktimg-json"
    rows = []
    for ident, cells in sorted(groups.items()):
        caps = sorted({r["cap"] for r in cells if r["cap"] in r.get("axis_mismatches", [])})
        if not caps:
            continue
        source = args.examples / (ident + ".cir")
        baseline, before_report = run(binary, source, args.work / (ident + "-baseline"))
        if baseline.read_bytes() != (args.frozen / (ident + ".json")).read_bytes() or before_report.read_bytes() != (args.frozen / (ident + ".report.json")).read_bytes():
            raise ValueError("frozen baseline did not replay exactly: " + ident)
        hints = ["*@ bridge " + " ".join(caps)]
        text = source.read_text()
        at = text.lower().rfind("\n.ends") + 1
        if at <= 0:
            raise ValueError("no final cell terminator")
        deck = args.work / (ident + "-cap-bridge.cir")
        deck.write_text(text[:at] + "\n".join(hints) + "\n" + text[at:])
        after, after_report = run(binary, deck, deck.with_suffix(""))
        reports = [json.loads(p.read_text()) for p in (before_report, after_report)]
        devices = [{d["name"].lower(): d for d in json.loads(p.read_text())["devices"]} for p in (baseline, after)]
        rows.append(dict(id=ident, source_sha256=sha(source), probe_deck_sha256=sha(deck), hints=hints,
                         baseline_json_sha256=sha(baseline), baseline_report_sha256=sha(before_report),
                         probe_json_sha256=sha(after), probe_report_sha256=sha(after_report),
                         before_metrics=reports[0]["metrics"], after_metrics=reports[1]["metrics"],
                         requests=[r for r in reports[1]["requests"] if r["text"] in hints],
                         cells=[dict(cap=r["cap"], family=r["family"], source=r["source_geometry"],
                                     before=geometry(r, devices[0], True), after=geometry(r, devices[1], True)) for r in cells]))
    result = dict(probe="capacitor_bridge_only", limitation="No MOS form changes; bridge rejects transistors. A later classifier/group-placement experiment remains necessary.",
                  binary_sha256=sha(binary), study_sha256=sha(args.study), script_sha256=sha(Path(__file__)),
                  baseline_replay="Every generated JSON and report matched frozen files byte-for-byte.", runs=rows)
    result["totals"] = {origin: {key: sum(r[origin + "_metrics"][key] for r in rows) for key in ("crossings", "bends")} for origin in ("before", "after")}
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(circuits=len(rows), caps=sum(len(r["hints"][0].split()) - 2 for r in rows), totals=result["totals"],
                          verdicts=dict(collections.Counter(v["state"] for r in rows for v in r["requests"]))), indent=2))


if __name__ == "__main__":
    main()
