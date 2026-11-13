#!/usr/bin/env python3
"""Unsigned reference amplifiers: exact contracts and named actual SVG leads.

Usage: reference_amplifiers.py <examples-dir> <output.json>

The previous remaining-amplifier inventory stays frozen. This companion
selects from all outer declarations and repeats their actual-ink inspection.
Stale coordinates require a named external marker, verified outside pin or
an explicitly reviewed literal label/stub certificate. SVG element order
and nearest-label matching never assign a port.
"""

import argparse
import copy
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import center_tap_symbols as census
import controller_glyphs as glyph
import remaining_amplifiers as remaining
from cross_caps import actual_glyph, conductor_ink
from converter_loops import wire_tree

FAMILIES = frozenset(("aea", "erroramp", "error_amplifier", "error_amp"))
EXPECTED = "ag-2415:x1 ag-2420:x1 ag-2421:x1 ag-2422:x1 ag-2425:x1 ag-2427:x1 ag-2428:x1 ag-2434:x1 ag-2435:x1 ag-2436:x1 ag-2440:x2 ag-2441:x1 ag-2443:x1 ag-2444:x2 ag-2447:x1".split()
EXPECTED_CHECKS = "accept_case_and_permutation accept_no_vdd accept_reference_and_output_only reject_erramp_box reject_family_suffix reject_ea1 reject_second_input reject_extra_control reject_duplicate_bias reject_duplicate_output reject_missing_reference reject_signed_ink reject_missing_base_lead reject_changed_literal_label reject_disconnected_label_stub".split()

# Literal source-label associations reviewed in their full rendered sheets.
# These labels identify a connected stub, not a physical connection to any
# remote same-named label. The positions are assertions, never search radii.
LABELS = {
    ("ag-2421", "vdd"): ("label-ff8ddaf5-3f1a-4ab7-9cc9-03035ed127fe", [240, 160], [250, 160], "vdd"),
    ("ag-2427", "vref"): ("label-da6754ef-805c-4b0b-ae63-65dde46536dd", [-80, 60], [-80, 70], "vref"),
    ("ag-2435", "vref"): ("label-9a1560f9-4ef2-4960-a428-af06e155f467", [-90, 40], [-90, 50], "vref"),
    ("ag-2440", "vbn"): ("label-a5f1e066-2177-4f82-99b1-fe3d8f08792d", [198, 350], [190, 350], "vbn"),
}


def roles(family, ports):
    if family.lower() not in FAMILIES:
        return None
    known = dict(vdd="supply", vss="ground", vref="input", out="output", vea="output",
                 vb1="bias", vbn="bias", nb="bias")
    assigned = [known.get(p.lower()) for p in ports]
    if (None in assigned or len(set(assigned)) != len(assigned)
            or not {"input", "output"} <= set(assigned)):
        return None
    return assigned


def shape(row):
    t = row["triangle"]
    if (row["shape"] != "triangle" or t is None or row["source_marks"]
            or len(t["base_leads"]) != 1 or len(row["external_leads"]) != len(row["ports"]) - 1
            or row["absent_cached_ports"] != ["vss"]):
        raise ValueError("source is not a complete unsigned one-base-lead triangle with omitted VSS")
    return t


def text(node):
    return "".join(node.itertext()).replace(" ", "").lower()


def markers(root):
    result = []
    labels = {n.get("data-object-id").lower(): n for n in root.iter()
              if n.get("data-kind") in ("instance-label", "power-label")}
    for group, transform, _ in glyph.walk(root):
        kind, obj = group.get("data-symbol-id"), group.get("data-object-id")
        if kind not in ("port", "vdd-port"):
            continue
        label = labels.get((("power-label-" if kind == "vdd-port" else "instance-label-") + obj).lower())
        if label is None:
            continue
        target = (0, 20) if kind == "vdd-port" else (0, 0)
        points = [glyph.point(t, target) for n, t, _ in glyph.walk(group, transform)
                  if n.tag.endswith("line") and any(
                      glyph.close(target, (float(n.get(x)), float(n.get(y))))
                      for x, y in (("x1", "y1"), ("x2", "y2")))]
        if len(points) != 1:
            raise ValueError("unsupported or ambiguous actual marker terminal")
        result.append(dict(name=text(label), object=obj, terminal=points[0],
                           label=label.get("data-object-id"), symbol=kind))
    return result


def label_proof(root, ink, row, port):
    literal = LABELS.get((row["id"], port))
    if literal is None:
        return None
    ident, position, anchor, name = literal
    labels = [n for n in root.iter() if n.get("data-object-id") == ident]
    if (len(labels) != 1 or labels[0].get("data-kind") != "net-label"
            or text(labels[0]) != name or [float(labels[0].get(k)) for k in ("x", "y")] != position):
        raise ValueError("reviewed literal source label changed")
    paths = [(i, wire_tree(ink, [lead["endpoint"], anchor])) for i, lead in enumerate(row["external_leads"])]
    matches = [(i, tree) for i, tree in paths if tree is not None]
    if len(matches) != 1 or not matches[0][1]:
        raise ValueError("reviewed label does not identify one actual external lead through its wire stub")
    i, tree = matches[0]
    return dict(lead=i, method="reviewed_literal_label_and_stub", label=ident,
                label_text=name, label_position=position, stub_endpoint=anchor,
                anchor_kind=labels[0].get("data-anchor-kind"), wire_tree=tree)


def outside_pins(root, human, row, port, ink):
    net = row["declared_bindings"][port]
    found = []
    for device in human["devices"]:
        if device["card"][0].lower() not in "mqrc" or net not in [n.lower() for n in device["nets"].values()]:
            continue
        actual = actual_glyph(root, device)["terminals"]
        for pin, at in actual.items():
            if device["nets"][pin].lower() != net:
                continue
            for i, lead in enumerate(row["external_leads"]):
                tree = wire_tree(ink, [lead["endpoint"], at])
                if tree is not None:
                    found.append(dict(lead=i, card=device["card"].lower(), pin=pin,
                                      terminal=at, declared_net=net, wire_tree=tree))
    return found


def inspect(raw, examples):
    row = remaining.inspect(raw, examples)
    triangle = shape(row)
    prefix = examples / row["corpus"] / row["id"]
    human = json.loads(prefix.with_suffix(".human.json").read_text())
    root = ET.parse(prefix.with_suffix(".svg")).getroot()
    ink, points = conductor_ink(root), markers(root)
    mapping = {}
    for port, role in zip(row["ports"], roles(row["family"], row["ports"])):
        if role == "ground":
            continue
        proof = None
        if role == "output":
            matches = outside_pins(root, human, row, port, ink)
            if not matches or {m["lead"] for m in matches} != {triangle["apex_lead"]}:
                raise ValueError("named output is not independently connected to its unique apex")
            proof = dict(lead=triangle["apex_lead"], method="declared_outside_pin_and_actual_wire",
                         outside_pins=matches)
        else:
            named = [m for m in points if m["name"] == row["declared_bindings"][port]]
            matches = [(i, m, wire_tree(ink, [lead["endpoint"], m["terminal"]]))
                       for i, lead in enumerate(row["external_leads"]) for m in named]
            connected = [(i, m, tree) for i, m, tree in matches if tree is not None]
            if connected:
                if len({i for i, _, _ in connected}) != 1:
                    raise ValueError("named marker reaches more than one source lead")
                proof = dict(lead=connected[0][0], method="named_actual_marker_and_wire",
                             markers=[dict(m, wire_tree=tree) for _, m, tree in connected])
            if proof is None:
                proof = label_proof(root, ink, row, port)
            if proof is None and port in row["cached_port_leads"]:
                proof = dict(lead=row["cached_port_leads"][port], method="declared_cached_pin_matches_actual_lead",
                             cached_terminal=row["cached_terminals"][port], declared_net=row["declared_bindings"][port])
        if proof is None:
            raise ValueError(f"unmapped actual source terminal {row['id']}:{port}")
        if role == "input" and proof["lead"] != triangle["base_leads"][0]:
            raise ValueError("named VREF does not match the unique triangle base lead")
        lead = row["external_leads"][proof["lead"]]
        mapping[port] = dict(proof, role=role, endpoint=lead["endpoint"],
                             outward_direction=lead["outward_direction"], path=lead["path"])
    if sorted(p["lead"] for p in mapping.values()) != list(range(len(row["external_leads"]))):
        raise ValueError("declared visible ports do not bijectively cover every actual source lead")
    # Keep source ink once in the original frozen inventory; this companion
    # records the source hashes and the additional named mapping certificates.
    return dict(id=row["id"], card=row["card"], family=row["family"], ports=row["ports"],
                bindings=row["bindings"], source_object=row["source_object"],
                source_sha256=row["source_sha256"], visible_port_mapping=mapping,
                missing_geometry=["vss"], polarity="unsigned", output_direction=triangle["output_direction"],
                cached_frame_mismatches=row["cached_frame_mismatches"])


def checks(first, label_row, label_root):
    cases = [
        ("accept_case_and_permutation", True, "AeA", ["OUT", "VREF", "VSS", "VBN", "VDD"]),
        ("accept_no_vdd", True, "error_amplifier", ["vss", "vref", "vea"]),
        ("accept_reference_and_output_only", True, "aea", ["vref", "out"]),
        ("reject_erramp_box", False, "erramp", ["vdd", "vss", "vref", "vbn", "out"]),
        ("reject_family_suffix", False, "aea1", ["vdd", "vss", "vref", "out"]),
        ("reject_ea1", False, "ea1", ["vdd", "vss", "vref", "out"]),
        ("reject_second_input", False, "aea", ["vdd", "vss", "vref", "inp", "out"]),
        ("reject_extra_control", False, "aea", ["vdd", "vss", "vref", "out", "vx"]),
        ("reject_duplicate_bias", False, "aea", ["vdd", "vss", "vref", "out", "nb", "vbn"]),
        ("reject_duplicate_output", False, "aea", ["vdd", "vss", "vref", "out", "vea"]),
        ("reject_missing_reference", False, "aea", ["vdd", "vss", "out"]),
    ]
    for name, expected, family, ports in cases:
        if (roles(family, ports) is not None) != expected:
            raise ValueError(name)
    names = [c[0] for c in cases]
    signed, baseless = copy.deepcopy(first), copy.deepcopy(first)
    signed["source_marks"] = [dict(role="negative")]
    baseless["triangle"]["base_leads"] = []
    for name, value in (("reject_signed_ink", signed), ("reject_missing_base_lead", baseless)):
        try:
            shape(value)
        except ValueError:
            names.append(name)
        else:
            raise ValueError(name)
    changed = copy.deepcopy(label_root)
    ident = LABELS[(label_row["id"], "vdd")][0]
    next(n for n in changed.iter() if n.get("data-object-id") == ident).text = "WRONG"
    for name, root, ink in (("reject_changed_literal_label", changed, conductor_ink(label_root)),
                            ("reject_disconnected_label_stub", label_root, [])):
        try:
            label_proof(root, ink, label_row, "vdd")
        except ValueError:
            names.append(name)
        else:
            raise ValueError(name)
    if names != EXPECTED_CHECKS:
        raise ValueError("exact method-check inventory changed")
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    unknown, _, counts, hashes = census.scan(args.examples)
    selected = [r for r in unknown if roles(r["family"], r["ports"]) is not None]
    names = [remaining.key(r) for r in selected]
    if names != EXPECTED:
        raise ValueError("exact unsigned reference-amplifier inventory changed")
    rows = [inspect(r, args.examples) for r in selected]
    excluded = [dict(name=remaining.key(r), family=r["family"], ports=r["ports"])
                for r in unknown if r["family"] in FAMILIES | {"erramp"} and r not in selected]
    first = remaining.inspect(selected[0], args.examples)
    label_row = remaining.inspect(next(r for r in selected if r["id"] == "ag-2421"), args.examples)
    label_root = ET.parse(args.examples / "analoggenie" / "ag-2421.svg").getroot()
    directory = Path(__file__).resolve().parent
    files = ("reference_amplifiers.py", "remaining_amplifiers.py", "remaining_amplifiers_cases.json",
             "block_aliases.py", "center_tap_symbols.py", "controller_glyphs.py", "cross_caps.py",
             "converter_loops.py", "converter_terminals.py", "digital_symbols.py", "mos_forms.py", "single_input_amplifiers.py")
    result = dict(corpus_counts=counts, corpus_sha256=hashes, selected=names, excluded=excluded,
                  method_checks=checks(first, label_row, label_root), rows=rows,
                  audit_sha256={n: remaining.digest(directory / n) for n in files})
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    print(json.dumps(dict(selected=names, method_checks=result["method_checks"])))


if __name__ == "__main__":
    main()
