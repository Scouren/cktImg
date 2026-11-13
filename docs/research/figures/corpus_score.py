#!/usr/bin/env python3
"""Freeze a named corpus run and compare its geometry using existing scorers.

The oracle is the cached human drawing, never the engine's layout choices.
Wire metrics reuse tools/site/build.py; geometric relations reuse the validated
docs/research/figures/score.py transcription of tests/golden.zig. Source/native
coordinates are normalized to 40 units per symbol. Tolerance is 2/40 of a
symbol, matching the native drawing tolerance, and is recorded in the result.
Missing/unsupported devices and engine failures remain named inventory entries.
This is a structural scorecard, not a proof of visual or electrical equivalence.
Glyph strokes and block grouping are not exposed by native JSON and are not scored.
"""
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def midpoint(points):
    return [sum(p[k] for p in points) / len(points) for k in (0, 1)]


def direction(a, b):
    dx, dy = a[0] - b[0], a[1] - b[1]
    if dx == 0 and dy == 0:
        return "coincident"
    if abs(dx) > abs(dy):
        return "right" if dx > 0 else "left"
    return "down" if dy > 0 else "up"


def axis(a, b):
    if a == b:
        return "coincident"
    if a[1] == b[1]:
        return "horizontal"
    if a[0] == b[0]:
        return "vertical"
    return "diagonal"


PASSIVES = {"resistor", "capacitor", "inductor", "inductor-compact",
            "variable-resistor", "variable-capacitor", "current-source",
            "voltage-source", "battery", "diode", "vccs", "vcvs", "crystal",
            "ideal-switch", "simple-switch", "closed-switch"}
ALIASES = {"in+": ("vip", "inp"), "in-": ("vin", "inn"),
           "out+": ("vop",), "out-": ("von",),
           "in": ("vin",), "out": ("vout",),
           "p-": ("p_minus",), "p+": ("p_plus",),
           "s-": ("s_minus",), "s+": ("s_plus",)}
GATES = {"inverter", "buffer", "and-gate", "nand-gate", "or-gate",
         "nor-gate", "xor-gate", "xnor-gate"}


def geometry(h, d):
    """Same electrical anchor in both drawings, independent of symbol origin."""
    hp = {k.lower(): v for k, v in h["terminals"].items()}
    dp = {p["term"].lower(): p["xy"] for p in d["pins"]}
    for pair, gate in ((('d', 's'), 'g'), (('c', 'e'), 'b')):
        if all(k in hp and k in dp for k in (*pair, gate)):
            ha, da = midpoint([hp[k] for k in pair]), midpoint([dp[k] for k in pair])
            return ha, da, axis(*[hp[k] for k in pair]), axis(*[dp[k] for k in pair]), direction(hp[gate], ha), direction(dp[gate], da), None, None
    if h["type"] in PASSIVES and len(hp) == 2 and len(d["pins"]) >= 2:
        hs, ds = list(hp.values()), [p["xy"] for p in d["pins"][:2]]
        return midpoint(hs), midpoint(ds), axis(*hs), axis(*ds), None, None, None, None
    if h["type"] == "externally-controlled-switch" and all(k in hp for k in ('p','n')) and all(k in dp for k in ('a','b')):
        hs,ds=[hp[k] for k in ('p','n')],[dp[k] for k in ('a','b')]
        return midpoint(hs),midpoint(ds),axis(*hs),axis(*ds),None,None,None,None
    # Blocks: only the same authored terminals participate. In particular,
    # native supply pins absent from a human inverter symbol do not shift it.
    hn = {k.lower(): v for k, v in h["nets"].items()}
    dn = {p["term"].lower(): p["net"] for p in d["pins"]}
    hs, ds, used, matched = [], [], set(), {}
    for name, p in hp.items():
        if hn.get(name) is None:
            raise ValueError("source terminal has no electrical net: " + name)
        candidates = [k for k in (name, *ALIASES.get(name, ())) if k in dp and dn[k] == hn[name] and k not in used]
        if len(candidates) != 1:
            candidates = [k for k in dp if dn[k] == hn[name] and k not in used]
        if len(candidates) != 1:
            raise ValueError("terminal correspondence is ambiguous: " + name)
        used.add(candidates[0]); hs.append(p); ds.append(dp[candidates[0]])
        matched[name] = dp[candidates[0]]
    if not hs:
        raise ValueError("no corresponding electrical terminal")
    ins, outs = [], []
    if h["type"] in GATES:
        ins, outs = [k for k in ('a', 'b') if k in hp], ['y']
    elif h["type"].startswith('opamp') or h["type"] == 'comparator':
        ins, outs = ['in+', 'in-'], [k for k in ('out', 'out+', 'out-') if k in hp]
    elif h["type"] == 'voltage-amplifier':
        ins, outs = ['in'], ['out']
    elif h["type"].startswith('hierarchical-symbol-'):
        # Authored port names measure geometry even when the source's symbol
        # type is an opaque asset ID. No generated family/class participates.
        ins = [k for k in ('in', 'inp', 'inn', 'in+', 'in-', 'vip', 'vin') if k in hp]
        outs = [k for k in ('out', 'out+', 'out-', 'vout', 'vo', 'vop', 'von') if k in hp]
    hf = df = None
    if ins and outs and all(k in matched for k in ins + outs):
        hf = direction(midpoint([hp[k] for k in outs]), midpoint([hp[k] for k in ins]))
        df = direction(midpoint([matched[k] for k in outs]), midpoint([matched[k] for k in ins]))
    return midpoint(hs), midpoint(ds), None, None, None, None, hf, df


def structural(h, j, score):
    native = {d["name"].lower(): d for d in j["devices"] if not d["name"].startswith('_')}
    fig = dict(names=[], x=[], y=[], gate=[])
    at = dict(x=[], y=[], gate=[])
    details, unsupported = [], []
    scale = 40 / (h["unit"] or 40)
    for human in sorted(h["devices"], key=lambda d: d["card"].lower()):
        name = human["card"].lower()
        if name not in native:
            unsupported.append(dict(card=name, reason="missing native device")); continue
        try:
            ha, da, ho, do, hg, dg, hf, df = geometry(human, native[name])
        except ValueError as e:
            unsupported.append(dict(card=name, reason=str(e))); continue
        fig["names"].append(name); fig["x"].append(ha[0] * scale); fig["y"].append(-ha[1] * scale)
        at["x"].append(da[0]); at["y"].append(-da[1])
        # Existing score supports horizontal gate directions. Score all four
        # directions below, using the same whole-drawing mirror it selects.
        fig["gate"].append(hg if hg in ("left", "right") else "none")
        at["gate"].append(dg if dg in ("left", "right") else "none")
        details.append(dict(card=name, source_anchor=ha, native_anchor=da,
                            source_orientation=ho, native_orientation=do,
                            source_gate=hg, native_gate=dg, source_flow=hf, native_flow=df))
    result = score.compare(fig, at)
    result.pop("sym_items")
    result["unsupported"] = unsupported
    result["anchors"] = details
    result["orientations"] = [0, 0]; result["bad_orientation"] = []
    result["gate_directions"] = [0, 0]; result["bad_gate_direction"] = []
    result["block_flow"] = [0, 0]; result["bad_block_flow"] = []
    for d in details:
        if d["source_orientation"]:
            ok = d["source_orientation"] == d["native_orientation"]
            result["orientations"][0] += ok; result["orientations"][1] += 1
            if not ok: result["bad_orientation"].append(d["card"])
        if d["source_gate"]:
            got = d["native_gate"]
            if result["mirrored"]: got = {"left": "right", "right": "left"}.get(got, got)
            ok = d["source_gate"] == got
            result["gate_directions"][0] += ok; result["gate_directions"][1] += 1
            if not ok: result["bad_gate_direction"].append(d["card"])
        if d["source_flow"]:
            got = d["native_flow"]
            if result["mirrored"]: got = {"left": "right", "right": "left"}.get(got, got)
            ok = d["source_flow"] == got
            result["block_flow"][0] += ok; result["block_flow"][1] += 1
            if not ok: result["bad_block_flow"].append(d["card"])
    result["equivalent_relations"] = not unsupported and all(not result[k] for k in
        ("bad_x", "bad_y", "rows_f", "rows_d", "cols_f", "cols_d", "bad_orientation", "bad_gate_direction", "bad_block_flow"))
    return result


def self_test(score):
    # Independent coordinates: a vertical MOS, horizontal MOS, resistor,
    # and inverter whose native symbol has extra power pins. Symbol origins
    # deliberately disagree and are unused. Translation/mirror must preserve
    # every relation, and rotating one MOS must break orientation.
    human = dict(unit=40, devices=[
        dict(card="m1", type="nmos", terminals=dict(D=[0,-20], G=[-20,0], S=[0,20], B=[0,0]), nets=dict(D="a",G="b",S="c",B="0")),
        dict(card="m2", type="nmos", terminals=dict(D=[100,0], G=[80,-20], S=[60,0], B=[80,0]), nets=dict(D="d",G="e",S="f",B="0")),
        dict(card="r1", type="resistor", terminals={"1":[-20,80],"2":[20,80]}, nets={"1":"a","2":"b"}),
        dict(card="x1", type="inverter", terminals=dict(A=[60,80],Y=[100,80]),nets=dict(A="g",Y="h"))])
    def native(mirror=False):
        devices=[]
        for d in human["devices"]:
            pins=[]
            for k,p in d["terminals"].items():
                if k=="B" and d["type"]=="nmos":continue
                pins.append(dict(term=k.lower(),net=d["nets"][k],xy=[200+(-p[0] if mirror else p[0]),300+p[1]]))
            if d["card"]=="x1":pins += [dict(term="vdd",net="vdd",xy=[280,330]),dict(term="vss",net="0",xy=[280,410])]
            devices.append(dict(name=d["card"],pins=pins,pos=[999,999]))
        return dict(devices=devices)
    for reflected in (False,True):
        r=structural(human,native(reflected),score)
        assert r["equivalent_relations"],r
        assert r["mirrored"]==reflected,r
    changed=native();changed["devices"][0]["pins"][0]["xy"]=[180,300]
    changed["devices"][0]["pins"][2]["xy"]=[220,300]
    assert structural(human,changed,score)["bad_orientation"]==["m1"]
    changed = native()
    changed["devices"][0]["pins"][1]["xy"] = [220, 300]
    assert structural(human, changed, score)["bad_gate_direction"] == ["m1"]
    changed = native()
    for pin in changed["devices"][2]["pins"]:
        pin["xy"][1] += 40
    assert ("r1", "x1") in structural(human, changed, score)["rows_f"]
    missing = native()
    missing["devices"].pop()
    assert structural(human, missing, score)["unsupported"] == [{"card": "x1", "reason": "missing native device"}]
    amp = dict(type="opamp", terminals={"IN+": [-60, 10], "IN-": [-60, -10], "OUT": [60, 0]},
               nets={"IN+": "ip", "IN-": "im", "OUT": "o"})
    pins = [dict(term=n, net=net, xy=xy) for n, net, xy in
            (("vip", "ip", [-60, 10]), ("vin", "im", [-60, -10]), ("vout", "o", [60, 0]),
             ("vdd", "vdd", [0, -100]), ("vss", "0", [0, 200]))]
    got = geometry(amp, dict(pins=pins))
    assert got[:2] == ([-20.0, 0.0], [-20.0, 0.0]), got
    assert got[-2:] == ("right", "right"), got
    # The source may name a custom triangular symbol by an opaque asset ID.
    # Its authored INN/OUT terminals still define a measurable flow axis.
    custom = dict(type="hierarchical-symbol-example", terminals={"INN": [0, 20], "OUT": [0, -20]},
                  nets={"INN": "i", "OUT": "o"})
    custom_native = dict(pins=[dict(term="inn", net="i", xy=[-20, 0]),
                              dict(term="out", net="o", xy=[20, 0])])
    assert geometry(custom, custom_native)[-2:] == ("up", "right")
    # Arbitrary port names carry no input/output assertion.
    opaque = dict(type="hierarchical-symbol-example", terminals={"p": [0, 20], "q": [0, -20]},
                  nets={"p": "i", "q": "o"})
    assert geometry(opaque, custom_native)[-2:] == (None, None)


def issues(results):
    """Named failures are compared as sets/maps, never only as totals."""
    return dict(
        engine_errors=sorted(k for k, v in results.items() if v.get("returncode", 0) != 0),
        processing_errors=sorted(k for k, v in results.items() if "error" in v and not v.get("returncode")),
        metric_disagreements=sorted(k for k, v in results.items() if v.get("metric_oracle_agrees") is False),
        gate_findings=sorted(k for k, v in results.items() if v.get("gates")),
        device_mismatches=sorted(k for k, v in results.items() if v.get("missing_devices") or v.get("extra_devices")),
        source_issues=sorted(k for k, v in results.items() if v.get("source_issues")),
        unsupported_geometry={k + ":" + d["card"]: d["reason"]
                              for k, v in results.items()
                              for d in v.get("structure", {}).get("unsupported", [])})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--examples", type=Path, required=True, help="one cached corpus directory, including index.json")
    parser.add_argument("--bin", type=Path, help="native cktimg-json executable, copied into the checkpoint")
    parser.add_argument("--out", type=Path, required=True, help="new checkpoint directory, or an existing one with --reuse")
    parser.add_argument("--label", required=True, help="checkpoint description recorded with its hashes")
    parser.add_argument("--result-name", default="scorecard.json", help="output JSON basename; rescore old checkpoints without overwriting their scorecard")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--reuse", action="store_true", help="rescore retained geometry; verify recorded input and binary hashes")
    parser.add_argument("--expect-issues", type=Path, help="named known input/engine failures; an unexpected pass also fails")
    args = parser.parse_args()
    if args.jobs < 1 or args.timeout < 1:
        parser.error("jobs and timeout must be positive")
    if Path(args.result_name).name != args.result_name or not args.result_name.endswith(".json"):
        parser.error("result-name must be a JSON basename")
    if args.reuse and args.bin:
        parser.error("--reuse uses the retained executable; omit --bin")
    score_path = args.repo / "docs/research/figures/score.py"
    measure_path = args.repo / "tools/site/build.py"
    score = module(score_path, "reference_score")
    measure = module(measure_path, "reference_metrics")
    score.FIG_TOL = score.DRAW_TOL = 2.0
    self_test(score)
    files = sorted(args.examples.glob("*.human.json"))
    if not files:
        parser.error("no human drawings found")
    ids = sorted(f.name.removesuffix(".human.json") for f in files)
    index_path = args.examples / "index.json"
    index = json.loads(index_path.read_text())
    if sorted(e["id"] for e in index) != ids:
        parser.error("index.json and human drawing IDs differ; no source may silently disappear")
    binary = args.out / "cktimg-json"
    previous = None
    if args.reuse:
        previous_path = args.out / "scorecard.json"
        if not previous_path.exists():
            previous_path = args.out / "inventory.json"
        previous = json.loads(previous_path.read_text())
        if previous["binary_sha256"] != digest(binary) or previous["ids"] != ids:
            parser.error("retained binary or input ID set changed")
    else:
        if args.bin is None:
            parser.error("--bin is required unless --reuse")
        if args.out.exists() and any(args.out.iterdir()):
            parser.error("checkpoint directory is not empty; use a new directory")
        args.out.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.bin, binary)
    expected = json.loads(args.expect_issues.read_text()) if args.expect_issues else issues({})

    def one(path):
        human = json.loads(path.read_text())
        cid = path.name.removesuffix(".human.json")
        deck = path.with_name(cid + ".cir")
        svg = path.with_name(cid + ".svg")
        row = dict(id=cid, source_sha256=digest(path), deck_sha256=digest(deck),
                   preview_sha256=digest(svg), devices=len(human["devices"]),
                   source_issues={k: human[k] for k in ("uncarded", "extra_cards", "net_conflicts") if human.get(k)})
        geom = args.out / (cid + ".json")
        report = args.out / (cid + ".report.json")
        try:
            if human["id"] != cid:
                raise ValueError("human drawing ID disagrees with its filename")
            if previous:
                old = previous["results"][cid]
                for key in ("source_sha256", "deck_sha256", "preview_sha256"):
                    if key in old and row[key] != old[key]:
                        raise ValueError("input changed: " + key)
                if "error" in old:
                    return {**row, "error": old["error"], "returncode": old.get("returncode", 0)}
                for key, artifact in (("geometry_sha256", geom), ("report_sha256", report)):
                    if key in old and old[key] != digest(artifact):
                        raise ValueError("retained output changed: " + key)
                row["returncode"] = 0
            else:
                run = subprocess.run([str(binary.resolve()), "--report", str(report), str(deck), str(geom)],
                                     capture_output=True, text=True, timeout=args.timeout)
                row["returncode"] = run.returncode
                if run.returncode:
                    return {**row, "error": (run.stderr or run.stdout)[-2000:]}
            native = json.loads(geom.read_text())
            report_doc = json.loads(report.read_text())
            _, agree = measure.our_metrics(native, report_doc)
            row.update(geometry_sha256=digest(geom), report_sha256=digest(report),
                       metrics=report_doc["metrics"], gates=report_doc["gates"],
                       metric_oracle_agrees=agree, human_metrics=measure.human_metrics(human))
            hn = {d["card"].lower() for d in human["devices"]}
            dn = {d["name"].lower() for d in native["devices"] if not d["name"].startswith("_")}
            row.update(missing_devices=sorted(hn - dn), extra_devices=sorted(dn - hn))
            # Class names are provenance, not glyph observations: a block:
            # class can now contain an amplifier triangle or a logic gate.
            row["generated_classes"] = {d["name"]: d["class"] for d in native["devices"]
                                        if d["class"].startswith(("block:", "generic"))}
            row["structure"] = structural(human, native, score)
        except Exception as error:
            row["error"] = type(error).__name__ + ": " + str(error)
        return row

    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for i, row in enumerate(pool.map(one, files), 1):
            results[row["id"]] = row
            if i % 100 == 0:
                print(i, "/", len(files), flush=True)
    observed = issues(results)
    corpus_hash = hashlib.sha256()
    for cid in ids:
        row = results[cid]
        corpus_hash.update((cid + row["source_sha256"] + row["deck_sha256"] + row["preview_sha256"]).encode())
    output = dict(schema=1, label=args.label, binary_sha256=digest(binary),
                  corpus_sha256=corpus_hash.hexdigest(), index_sha256=digest(index_path),
                  scorer_sha256=digest(score_path), measure_sha256=digest(measure_path),
                  runner_sha256=digest(Path(__file__)), normalized_unit=40, coordinate_tolerance=2,
                  unscored_features=["glyph strokes", "block membership", "wire topology equivalence", "label placement"],
                  ids=ids, issues=observed, results=results)
    (args.out / args.result_name).write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    print(json.dumps(observed, indent=2, sort_keys=True))
    print("all scored relations match", sum(v.get("structure", {}).get("equivalent_relations", False)
                                            for v in results.values()), "/", len(results))
    if observed != expected:
        print("named issues differ from expectation (including unexpected passes)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
