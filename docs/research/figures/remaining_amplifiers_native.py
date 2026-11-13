#!/usr/bin/env python3
"""Own-body native SVG proof for exact A1/EA1/AEA source contracts.

Usage: remaining_amplifiers_native.py EXAMPLES WORK_DIR OUTPUT
       --baseline-bin BIN --candidate-bin BIN
       [--baseline-corpus DIR --candidate-corpus DIR] ... [--check]

Both binaries are existing frozen artifacts; this script never builds them.
The source inventory is replayed against actual SVG ink and ordered SPICE
declarations. Native SVG body/sign/lead geometry is associated with each
named placement, independently of its class name. Optional complete corpus
directories prove every paired source drawing and the exact changed names.
This is canonical glyph recognition and electrical binding preservation,
not source facing, bias order, dimensions, routing or a netlist round trip.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import block_aliases_native as native
import remaining_amplifiers as source

NEGATIVES = [
    ("a1_extra_z", "A1", "VDD VSS INP INN OUT Z"),
    ("a1_extra_vz", "A1", "VDD VSS INN INP OUT VB1 VB2 VZ"),
    ("ea1_unsigned_controls", "EA1", "VDD VSS VFP1 VREF VX3 VCTRL"),
    ("ea1_eight_controls", "EA1", "VDD VSS VFP1 VREF VX2 VB1 VISR VX1"),
    ("a10_suffix", "A10", "VDD VSS INP INN OUT"),
    ("a1_prefix", "my_a1", "VDD VSS INP INN OUT"),
    ("ea1_suffix", "EA1_extra", "VDD VSS INP INN OUT"),
    ("aea_suffix", "AEA2", "VDD VSS INN OUT VB"),
    ("duplicate_bias_role", "A1", "VDD VSS INP INN OUT VB VB1"),
    ("missing_output", "EA1", "VDD VSS INP INN"),
    ("mixed_inputs", "A1", "VDD INP INN IN OUT"),
    ("aea_extra_control", "AEA", "VDD VSS INN OUT VB ENABLE"),
    ("unknown_ota", "OTA", "VDD VSS INP INN OUT"),
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def same(actual, expected, context):
    if json.loads(json.dumps(actual)) != json.loads(json.dumps(expected)):
        raise ValueError(context + " differs from the exact inventory")


def source_rows(examples):
    path = HERE / "remaining_amplifiers_cases.json"
    inventory = json.loads(path.read_text())
    for name, expected in inventory["audit_sha256"].items():
        same(digest(HERE / name), expected, "source audit dependency " + name)
    unknown, _, counts, hashes = source.census.scan(examples)
    same(counts, inventory["corpus_counts"], "source corpus names/counts")
    same(hashes, inventory["corpus_sha256"], "source corpus hashes")
    same(source.checks(), inventory["method_checks"], "source method names")
    current = [source.inspect(r, examples) for r in unknown if r["family"] in source.CANDIDATES]
    expected = [r for r in inventory["rows"] if r["family"] in source.CANDIDATES]
    # This compares every source field: actual ink, cached disagreements,
    # ordered card/declaration bindings and all three source content hashes.
    same(current, expected, "every exact-family source observation")
    same(sorted(source.key(r) for r in current if r["candidate"]),
         source.EXPECTED_COMPLETE, "complete source names")
    same(inventory["complete_candidates"], source.EXPECTED_COMPLETE, "frozen complete names")
    if len(current) != 108 or len({source.key(r) for r in current}) != 108:
        raise ValueError("exact-family source census is not 108 unique instances")
    return sorted(current, key=source.key), inventory


def adapter_row(row):
    proof = row["complete_signal_proof"]
    return dict(row, shape="triangle" if row["candidate"] else "box",
                expected_marks=proof["expected_marks"] if proof else [],
                missing_source_ports=row["absent_cached_ports"],
                signal_frame_mismatches=proof["signal_frame_mismatches"] if proof else row["cached_frame_mismatches"])


def render(binary, deck, prefix):
    result = subprocess.run([str(binary.resolve()), "--svg", str(prefix.with_suffix(".svg")),
                             str(deck), str(prefix.with_suffix(".json"))],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise ValueError(f"{deck.name}: native renderer failed: {result.stderr}")


def observe(prefix, row):
    jp, sp = prefix.with_suffix(".json"), prefix.with_suffix(".svg")
    try:
        result = native.inspect(json.loads(jp.read_text()), ET.parse(sp).getroot(), row)
    except ValueError as error:
        raise ValueError(f"{prefix.name}:{row['card']}: {error}") from error
    return dict(native=result, native_sha256={".json": digest(jp), ".svg": digest(sp)})


def accepted(observed):
    return (observed["shape"] == "triangle" and observed["signs_agree"]
            and observed["signal_geometry_agrees"] and not observed["interior_polylines"])


def literal_checks():
    native.selfcheck()
    row = dict(card="x1", family="aea", ports=["inn", "out"], bindings=["a", "b"],
               expected_marks=["negative"], shape="triangle", missing_source_ports=[], signal_frame_mismatches=[])
    device = dict(name="x1", pos=[0, 0], rot=0, mirror=False, **{"class": "untrusted-name"},
                  pins=[dict(term="inn", net="a", xy=[-60, 0]), dict(term="out", net="b", xy=[60, 0])])
    drawing = dict(devices=[device], wires=[dict(segments=[[[-100, -100], [-100, 100], [100, 100]]])])
    root = ET.fromstring('''<svg viewBox="-110 -110 220 220"><g>
      <polyline points="-100,-100 -100,100 100,100"/>
      <polyline points="-40,-40 40,0 -40,40 -40,-40"/>
      <polyline points="-60,0 -40,0"/><polyline points="40,0 60,0"/>
      <text x="-30" y="3" text-anchor="middle" font-size="11">-</text>
      </g><text x="50" y="-30" font-size="11">x1</text></svg>''')
    assert accepted(native.inspect(drawing, root, row))
    checks = ["literal_single_negative_triangle", "shared_adapter_own_body_transform_port_mutations"]
    for name, change in (
        ("missing_negative_mark_rejected", lambda r: r[0].remove(r[0][-1])),
        ("wrong_polarity_mark_rejected", lambda r: setattr(r[0][-1], "text", "+")),
        ("displaced_polarity_mark_rejected", lambda r: r[0][-1].set("y", "13")),
        ("interior_step_rejected", lambda r: r[0].append(ET.fromstring('<polyline points="-20,5 -10,5 -10,-5 0,-5"/>'))),
    ):
        mutated = copy.deepcopy(root)
        change(mutated)
        assert not accepted(native.inspect(drawing, mutated, row)), name
        checks.append(name)
    mutated = copy.deepcopy(drawing)
    mutated["devices"][0]["pins"][0]["net"] = "wrong"
    try:
        native.inspect(mutated, root, row)
    except ValueError as error:
        assert "ordered electrical port bindings changed" in str(error)
    else:
        raise AssertionError("wrong electrical binding accepted")
    return checks + ["wrong_ordered_electrical_binding_rejected"]


def snapshot(binary, directory, examples, rows):
    directory.mkdir(parents=True, exist_ok=True)
    for corpus, cid in sorted({(r["corpus"], r["id"]) for r in rows}):
        render(binary, examples / corpus / (cid + ".cir"), directory / cid)
    result = []
    for row in rows:
        result.append(dict(name=source.key(row), family=row["family"], complete=row["candidate"],
                           source_shape=row["shape"], source_sha256=row["source_sha256"],
                           **observe(directory / row["id"], adapter_row(row))))
    negatives = []
    for name, family, declaration in NEGATIVES:
        ports = declaration.lower().split()
        bindings = ["n" + str(i) for i in range(len(ports))]
        prefix = directory / ("literal-" + name)
        deck = prefix.with_suffix(".cir")
        deck.write_text(".subckt " + family + " " + declaration + "\n.ends\nX1 "
                        + " ".join(bindings) + " " + family
                        + "\nRframea fa fb 1k\nRframeb fb 0 1k\nVframe fa 0 1\n")
        render(binary, deck, prefix)
        row = dict(card="x1", family=family.lower(), ports=ports, bindings=bindings, shape="box",
                   expected_marks=[], missing_source_ports=[], signal_frame_mismatches=[])
        negatives.append(dict(name=name, family=family.lower(), ports=ports, deck_sha256=digest(deck),
                              **observe(prefix, row)))
    triangles = sorted(r["name"] for r in result if r["native"]["shape"] == "triangle")
    complete_failures = sorted(r["name"] for r in result if r["complete"] and not accepted(r["native"]))
    excluded_failures = sorted(r["name"] for r in result if not r["complete"] and r["native"]["shape"] != "box")
    negative_failures = sorted(r["name"] for r in negatives if r["native"]["shape"] != "box")
    same(excluded_failures, [], "excluded source contracts remain boxes")
    same(negative_failures, [], "literal incomplete/suffix controls remain boxes")
    return dict(renderer_sha256=digest(binary), rows=result, literal_negatives=negatives,
                summary=dict(instances=len(result), complete=sum(r["complete"] for r in result),
                             ordered_ports=sum(len(r["native"]["ordered_ports"]) for r in result),
                             triangles=triangles, complete_glyph_failures=complete_failures,
                             excluded_shape_failures=excluded_failures, literal_negative_failures=negative_failures))


def corpus_changes(before, after, binaries, examples, expected):
    if len(before) != len(after):
        raise ValueError("corpus directory pairs differ")
    rows, names, corpora = [], set(), []
    for bp, ap in zip(before, after):
        if not (bp / "scorecard.json").is_file() or not (ap / "scorecard.json").is_file():
            raise ValueError("whole corpus requires completed scorecards")
        # Parse completed scorecards; a partial write cannot certify a run.
        cards = [json.loads((p / "scorecard.json").read_text()) for p in (bp, ap)]
        paths = lambda p: {f.name: f for f in p.glob("*.json")
                           if f.name.startswith(("ag-", "amsnet-")) and not f.name.endswith(".report.json")}
        old, new = paths(bp), paths(ap)
        same(sorted(old), sorted(new), "full native drawing names")
        for p, card, files, binary in zip((bp, ap), cards, (old, new), binaries):
            same(sorted(card["ids"]), sorted(n.removesuffix(".json") for n in files),
                 "all completed scorecard drawing names")
            same(card["binary_sha256"], digest(binary), "scorecard frozen renderer")
            same(digest(p / "cktimg-json"), digest(binary), "corpus frozen renderer")
        if not old or names & set(old):
            raise ValueError("empty or repeated native corpus")
        names.update(old)
        corpora.append(dict(ids=sorted(cards[0]["ids"]),
                            baseline_scorecard_sha256=digest(bp / "scorecard.json"),
                            candidate_scorecard_sha256=digest(ap / "scorecard.json")))
        rows.extend(dict(name=name.removesuffix(".json"), baseline_sha256=digest(old[name]),
                         candidate_sha256=digest(new[name])) for name in sorted(old))
    expected_names = sorted(p.name.removesuffix(".human.json") + ".json"
                            for corpus in ("analoggenie", "amsnet")
                            for p in (examples / corpus).glob("*.human.json"))
    same(sorted(names), expected_names, "entire paired source corpus coverage")
    changed = sorted(r["name"] for r in rows if r["baseline_sha256"] != r["candidate_sha256"])
    same(changed, sorted({n.split(":")[0] for n in expected}), "entire native changed drawing names")
    return dict(corpora=corpora, drawings=sorted(rows, key=lambda r: r["name"]), changed=changed,
                count=len(rows), changed_count=len(changed))


def frozen(result):
    """Small inventory; the digest covers every full replay field exactly."""
    corpus = result.get("whole_native_corpus")
    if corpus is None:
        raise ValueError("frozen replay requires both complete corpus directory pairs")
    return dict(evidence_sha256=hashlib.sha256(json.dumps(result, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                source_inventory_sha256=result["source_inventory_sha256"],
                audit_sha256=result["audit_sha256"], method_checks=result["method_checks"],
                complete_names=result["complete_names"], excluded_names=result["excluded_names"],
                snapshots={name: dict(renderer_sha256=result[name]["renderer_sha256"], summary=result[name]["summary"],
                                      literal_negative_names=[r["name"] for r in result[name]["literal_negatives"]])
                           for name in ("baseline", "candidate")},
                whole_native_count=corpus["count"], changed_drawings=corpus["changed"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("examples", "work_dir", "output"):
        parser.add_argument(name, type=Path)
    for name in ("baseline", "candidate"):
        parser.add_argument("--" + name + "-bin", required=True, type=Path)
        parser.add_argument("--" + name + "-corpus", action="append", default=[], type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    checks = literal_checks()
    rows, inventory = source_rows(args.examples)
    baseline = snapshot(args.baseline_bin, args.work_dir / "baseline", args.examples, rows)
    candidate = snapshot(args.candidate_bin, args.work_dir / "candidate", args.examples, rows)
    same(baseline["summary"]["triangles"], [], "baseline exact-family boxes")
    same(baseline["summary"]["complete_glyph_failures"], source.EXPECTED_COMPLETE, "baseline named glyph gaps")
    same(candidate["summary"]["triangles"], source.EXPECTED_COMPLETE, "candidate named triangles")
    same(candidate["summary"]["complete_glyph_failures"], [], "candidate glyph/mark/signal failures")
    transitions = [dict(name=a["name"], before=a["native"]["shape"], after=b["native"]["shape"])
                   for a, b in zip(baseline["rows"], candidate["rows"]) if a["native"]["shape"] != b["native"]["shape"]]
    same([r["name"] for r in transitions], source.EXPECTED_COMPLETE, "exact native body transitions")
    deps = sorted(set(inventory["audit_sha256"]) | {Path(__file__).name, Path(native.__file__).name})
    result = dict(source_inventory_sha256=digest(HERE / "remaining_amplifiers_cases.json"),
                  audit_sha256={name: digest(HERE / name) for name in deps}, method_checks=checks,
                  complete_names=source.EXPECTED_COMPLETE,
                  excluded_names=sorted(source.key(r) for r in rows if not r["candidate"]),
                  baseline=baseline, candidate=candidate, transitions=transitions,
                  limits="Canonical own-body glyph/sign/apex and every ordered declared electrical binding only. Source facing, bias order, absent cached VSS geometry, routing and complete drawing equivalence are not inferred.")
    if args.baseline_corpus or args.candidate_corpus:
        result["whole_native_corpus"] = corpus_changes(args.baseline_corpus, args.candidate_corpus,
                                                       (args.baseline_bin, args.candidate_bin),
                                                       args.examples, source.EXPECTED_COMPLETE)
    if args.check:
        same(frozen(result), json.loads((HERE / "remaining_amplifiers_native_cases.json").read_text()),
             "every frozen source/native field")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(baseline=baseline["summary"], candidate=candidate["summary"],
                          whole_native_corpus=result.get("whole_native_corpus", {}).get("changed_count")), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
