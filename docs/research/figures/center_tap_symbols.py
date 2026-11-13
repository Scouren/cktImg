#!/usr/bin/env python3
"""Observed center-tapped-inductor contracts and own-symbol SVG ink.

Usage: center_tap_symbols.py <examples-root> <output.json>
       --native-dir DIR --baseline-dir DIR [--bin cktimg-json]

The exact CT_INDUCTOR/N1/N2/N3 contract is compared with each own source
glyph and a native box baseline. The baseline JSON must reproduce exactly.
No build is performed. This finite audit infers no arbitrary SPICE bodies.
"""

import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
RESEARCH = Path(__file__).resolve().parent
sys.path.insert(0, str(RESEARCH.resolve()))
import block_aliases as aliases
import block_aliases_native as native
import controller_glyphs as glyph
import digital_symbols as digital

KNOWN = frozenset("opamp icm_opamp_vdd_vss voltage_amplifier amp amp1 ea cmp comp comparator opamp_differential icm_ideal_comparator_vdd buffer buf inverter inv and_gate and nand_gate nand or_gate or nor_gate nor xor_gate xor xnor_gate xnor".split())
EXPECTED = "ag-1103:xl1 ag-1114:x1 ag-1131:x1 ag-1146:x1 ag-1147:x1 ag-1149:xlp ag-1151:xl ag-1152:xl1 ag-1152:xl2 ag-1153:xl1 ag-1153:xl2 ag-1168:x1 ag-1168:x2 ag-1180:xle1 ag-1180:xle2 ag-1180:xlo1 ag-1180:xlo2 ag-1187:xtb ag-1190:x1".split()
EXPECTED_CHECKS = "reject_tcoil reject_xfmr reject_family_suffix reject_duplicate_port reject_extra_supply reject_unknown_ports accept_case_and_port_permutation reject_missing_dot reject_missing_coils reject_hollow_dot reject_displaced_tap".split()
BODY = [["l1", "n1", "n3", "{l1}"], ["l2", "n3", "n2", "{l2}"], ["k12", "l1", "l2", "{k}"]]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def candidate(family, ports):
    return family.lower() == "ct_inductor" and sorted(p.lower() for p in ports) == ["n1", "n2", "n3"]


def scan(examples):
    unknown, selected, counts, corpus_hashes = [], [], {}, {}
    for corpus in ("analoggenie", "amsnet"):
        directory = examples / corpus
        paths = sorted(directory.glob("*.human.json"))
        if not paths:
            raise ValueError(f"missing corpus {corpus}")
        counts[corpus] = len(paths)
        hashed = hashlib.sha256()
        for hp in paths:
            cid = hp.name.removesuffix(".human.json")
            cp = directory / (cid + ".cir")
            for p in (hp, cp):
                hashed.update(p.name.encode() + bytes.fromhex(digest(p)))
            human, text = json.loads(hp.read_text()), cp.read_text()
            definitions, cards = digital.declarations(text), aliases.read_cards(text)
            for name, words in cards.items():
                if not name.startswith("x"):
                    continue
                index = next((i for i, w in enumerate(words) if "=" in w or w == "params:"), len(words)) - 1
                family = words[index]
                if family not in definitions:
                    raise ValueError(f"unresolved outer family {cid}:{name}:{family}")
                ports = definitions[family]
                if len(ports) != index - 1:
                    raise ValueError("declared port count disagrees with call")
                devices = [d for d in human["devices"] if d["card"].lower() == name]
                if len(devices) != 1:
                    raise ValueError("no unique source device")
                row = dict(corpus=corpus, id=cid, card=name, family=family, ports=ports,
                           bindings=words[1:index], params=words[index + 1:], asset=devices[0]["type"])
                if family not in KNOWN:
                    unknown.append(row)
                if candidate(family, ports):
                    selected.append(row)
        corpus_hashes[corpus] = hashed.hexdigest()
    if sorted(r["id"] + ":" + r["card"] for r in selected) != EXPECTED:
        raise ValueError("center-tap exact inventory changed")
    return unknown, selected, counts, corpus_hashes


def primitives(group, parent):
    result = []
    for node, transform, _ in glyph.walk(group, parent):
        tag = native.tag(node)
        if tag in ("g", "text", "tspan"):
            continue
        row = dict(tag=tag, attributes=dict(node.attrib), transform=transform)
        if tag == "path":
            row.update(digital.path_data(node, transform))
        elif tag == "line":
            local = [[float(node.get(x)), float(node.get(y))] for x, y in (("x1", "y1"), ("x2", "y2"))]
            row.update(local=local, world=[glyph.point(transform, p) for p in local])
        elif tag in ("polyline", "polygon"):
            values = glyph.numbers(node.get("points", ""))
            row["world"] = [glyph.point(transform, p) for p in zip(values[::2], values[1::2])]
        elif tag == "circle":
            row["world"] = glyph.point(transform, (float(node.get("cx")), float(node.get("cy"))))
        else:
            raise ValueError(f"unsupported glyph primitive {tag}")
        result.append(row)
    return result


def center_tap_ink(parts):
    if collections.Counter(p["tag"] for p in parts) != dict(path=2, line=4, circle=1):
        raise ValueError("center-tap body requires two coils, four lines and one dot")
    lines = [p for p in parts if p["tag"] == "line"]
    paths = [p for p in parts if p["tag"] == "path"]
    circles = [p for p in parts if p["tag"] == "circle"]
    transform = lines[0]["transform"]
    if any(p["transform"] != transform for p in parts):
        raise ValueError("unexpected mixed canonical frames")
    for path, first, last in zip(paths, ((-45, 0), (5, 0)), ((-5, 0), (45, 0))):
        if (path["closed"] or "C" not in path["commands"]
                or not glyph.close(path["control_vertices"][0], glyph.point(transform, first))
                or not glyph.close(path["control_vertices"][-1], glyph.point(transform, last))):
            raise ValueError("unexpected coil path endpoints or commands")
    left = [p for p in lines if p["local"][0][0] < -45 and p["local"][1] == [-44.5, 0]]
    right = [p for p in lines if p["local"][0] == [44.5, 0] and p["local"][1][0] > 45]
    bridge = [p for p in lines if p["local"] == [[-5.5, 0], [5.5, 0]]]
    tap = [p for p in lines if p["local"] == [[0, -.5], [0, 20]]]
    dot = circles[0]["attributes"]
    if not (len(left) == len(right) == len(bridge) == len(tap) == 1
            and left[0]["local"][0][1] == right[0]["local"][1][1] == 0
            and float(dot["cx"]) == float(dot["cy"]) == 0
            and float(dot["r"]) > 0 and dot["fill"] == "#000" and dot["stroke"] == "none"):
        raise ValueError("missing outer leads, central bridge or filled tap junction")
    return dict(n1=left[0]["world"][0], n2=right[0]["world"][1], n3=tap[0]["world"][1])


def inspect(row, examples, native_dir, baseline_dir):
    prefix = examples / row["corpus"] / row["id"]
    human = json.loads(prefix.with_suffix(".human.json").read_text())
    root = ET.parse(prefix.with_suffix(".svg")).getroot()
    device, group, parent = aliases.source_group(human, root, row["card"])
    parts = primitives(group, parent)
    actual = center_tap_ink(parts)
    cached = {"n" + p: xy for p, xy in device["terminals"].items()}
    bound = {"n" + p: net.lower() for p, net in device["nets"].items()}
    if bound != dict(zip(row["ports"], row["bindings"])):
        raise ValueError("declared port bindings differ from source pin mapping")
    mismatches = [p for p in row["ports"] if p not in cached or not glyph.close(cached[p], actual[p])]
    if mismatches:
        raise ValueError(f"actual pin mismatch {row['id']}:{row['card']}:{mismatches}")
    text = prefix.with_suffix(".cir").read_text().lower()
    header, remainder = text.split(".subckt ct_inductor ", 1)[1].split("\n", 1)
    body = [line.split() for line in remainder.split(".ends", 1)[0].splitlines() if line.strip()]
    if body != BODY:
        raise ValueError("observed center-tap body changed")
    np = native_dir / row["id"]
    frozen = baseline_dir / (row["id"] + ".json")
    drawing = json.loads(np.with_suffix(".json").read_text())
    if drawing != json.loads(frozen.read_text()):
        raise ValueError("rendered native JSON differs from frozen corpus")
    baseline = native.inspect(drawing, ET.parse(np.with_suffix(".svg")).getroot(),
                              dict(row, expected_marks=[], shape="center-tap", missing_source_ports=[], signal_frame_mismatches=[]))
    return dict(row, source_object=group.get("data-object-id"), actual_terminals=actual,
                cached_terminals=cached, bindings_by_port=bound, pin_mapping_verified=True,
                horizontal=actual["n1"][1] == actual["n2"][1],
                tap_direction=glyph.direction(glyph.point(parts[0]["transform"], (0, 0)), actual["n3"]),
                primitives=parts, subcircuit_header=header, subcircuit_body=body,
                source_sha256={suffix: digest(prefix.with_suffix(suffix)) for suffix in (".cir", ".human.json", ".svg")},
                native=baseline, native_sha256={suffix: digest(np.with_suffix(suffix)) for suffix in (".json", ".svg")})


def checks(parts):
    tests = []
    for name, family, ports in (("reject_tcoil", "tcoil", ["n1", "n2", "n3"]),
                                ("reject_xfmr", "xfmr", ["n1", "n2", "n3"]),
                                ("reject_family_suffix", "ct_inductor_extra", ["n1", "n2", "n3"]),
                                ("reject_duplicate_port", "ct_inductor", ["n1", "n2", "n2"]),
                                ("reject_extra_supply", "ct_inductor", ["n1", "n2", "n3", "vdd"]),
                                ("reject_unknown_ports", "ct_inductor", ["a", "b", "c"])):
        assert not candidate(family, ports)
        tests.append(name)
    assert candidate("CT_INDUCTOR", ["N3", "N1", "N2"])
    tests.append("accept_case_and_port_permutation")
    variants = [("reject_missing_dot", [p for p in parts if p["tag"] != "circle"]),
                ("reject_missing_coils", [p for p in parts if p["tag"] != "path"])]
    wrong = copy.deepcopy(parts)
    next(p for p in wrong if p["tag"] == "circle")["attributes"]["fill"] = "none"
    variants.append(("reject_hollow_dot", wrong))
    wrong = copy.deepcopy(parts)
    next(p for p in wrong if p["tag"] == "line" and p["local"][1] == [0, 20])["local"][1] = [1, 20]
    variants.append(("reject_displaced_tap", wrong))
    for name, variant in variants:
        try:
            center_tap_ink(variant)
        except ValueError:
            tests.append(name)
        else:
            raise ValueError(f"{name}: mutated source ink escaped the independent shape certificate")
    if tests != EXPECTED_CHECKS:
        raise ValueError("exact method-check inventory changed")
    return tests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native-dir", type=Path, required=True)
    parser.add_argument("--baseline-dir", type=Path, required=True)
    parser.add_argument("--bin", type=Path)
    args = parser.parse_args()
    examples = args.examples
    unknown, selected, counts, corpus_hashes = scan(examples)
    if args.bin:
        args.native_dir.mkdir(parents=True, exist_ok=True)
        for cid in sorted({r["id"] for r in selected}):
            run = subprocess.run([str(args.bin.resolve()), "--svg", str(args.native_dir / (cid + ".svg")),
                                  str(examples / "analoggenie" / (cid + ".cir")),
                                  str(args.native_dir / (cid + ".json"))], capture_output=True, text=True, timeout=60)
            if run.returncode:
                raise ValueError(f"{cid}: native renderer failed: {run.stderr}")
    rows = [inspect(row, examples, args.native_dir, args.baseline_dir) for row in selected]
    comparisons = []
    for row in unknown:
        if row["family"] not in ("tcoil", "xfmr", "crystal"):
            continue
        prefix = examples / row["corpus"] / row["id"]
        human, root = json.loads(prefix.with_suffix(".human.json").read_text()), ET.parse(prefix.with_suffix(".svg")).getroot()
        device, group, parent = aliases.source_group(human, root, row["card"])
        comparisons.append(dict(row, source_object=group.get("data-object-id"), primitives=primitives(group, parent),
                                cached_terminals=device["terminals"], cached_binding=device["nets"],
                                source_sha256={s: digest(prefix.with_suffix(s)) for s in (".cir", ".human.json", ".svg")}))
    method_checks = checks(rows[0]["primitives"])
    paths = {}
    for row in rows + comparisons:
        for part in row["primitives"]:
            if part["tag"] != "path":
                continue
            data = part.pop("path")
            key = hashlib.sha256(data.encode()).hexdigest()
            paths[key] = dict(path=data, commands=part.pop("commands"))
            vertices = part.pop("control_vertices")
            part["actual_endpoints"] = [vertices[0], vertices[-1]]
            part["path_sha256"] = key
            del part["attributes"]["d"]
    result = dict(selected=rows, comparisons=comparisons, unknown_outer_families=unknown, source_paths=paths,
                  corpus_drawings=counts, corpus_contract_sha256=corpus_hashes,
                  source_notes="Finite shape/port evidence, no new electrical primitive, no axis policy, no routing equivalence claim. Actual SVG endpoints are compared separately with cached geometry. Coil/line overlaps are deliberate source ink; cubic paths are not wire segments.",
                  summary=dict(instances=len(rows), circuits=len({r["id"] for r in rows}),
                               horizontal=sum(r["horizontal"] for r in rows), vertical=sum(not r["horizontal"] for r in rows),
                               native_boxes=sum(r["native"]["shape"] == "box" for r in rows),
                               actual_source_terminals=sum(len(r["actual_terminals"]) for r in rows),
                               native_preserved_leads=sum(len(r["native"]["leads"]) for r in rows),
                               source_cache_mismatches=[], method_checks=method_checks, method_check_count=len(method_checks)),
                  audit_sha256={p.name: digest(p) for p in (Path(__file__), *(RESEARCH / f for f in ("block_aliases.py", "block_aliases_native.py", "controller_glyphs.py", "digital_symbols.py", "mos_forms.py", "single_input_amplifiers.py")))},
                  renderer_sha256=digest(args.bin) if args.bin else None)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result["summary"], sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
