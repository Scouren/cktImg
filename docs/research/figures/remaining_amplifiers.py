#!/usr/bin/env python3
"""Remaining amplifier glyph contracts against their own source SVG ink.

Usage: remaining_amplifiers.py <examples-dir> <output.json>

This is a source-only candidate audit, not a production recognizer. It reuses
the whole-corpus outer-call census and independent triangle/lead parser.
Known signal names and actual polarity strokes can identify signals even
when cached coordinates are stale. Other source leads remain explicitly
unmapped unless a cached declared pin actually meets that ink. Missing VSS
geometry is never synthesized. AG1316 has an additional literal ink proof.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import block_aliases as aliases
import center_tap_symbols as census
import controller_glyphs as glyph
from cross_caps import actual_glyph, conductor_ink
from converter_loops import wire_tree

FAMILIES = frozenset("a1 ea1 aea error_amplifier erroramp error_amp erramp ota lpf a analog_circuit dda da pa stage1 cmfb preamp gm cm_detect".split())
CANDIDATES = frozenset(("a1", "ea1", "aea"))
EXPECTED_COMPLETE = "ag-1233:x1 ag-1464:x1 ag-1486:x1 ag-1504:x1 ag-1505:x1 ag-1551:x1 ag-1557:x1 ag-1565:x1 ag-1570:x1 ag-1574:x1 ag-1579:x1 ag-1586:x1 ag-1591:x1 ag-1593:x1 ag-1597:x1 ag-1600:x1 ag-1609:x1 ag-1610:x1 ag-1614:x1 ag-1617:x1 ag-1626:x1 ag-1629:x1 ag-1630:x1 ag-1631:x1 ag-1634:x1 ag-1636:x1 ag-1637:x1 ag-1675:x1 ag-1704:x1 ag-1705:x1 ag-1708:x1 ag-1711:x1 ag-1713:x1 ag-1715:x1 ag-1722:x1 ag-1724:x1 ag-1726:x1 ag-1727:x1 ag-2423:x1".split()
EXPECTED_UNSIGNED_FOLLOWUP = "ag-2415:x1 ag-2420:x1 ag-2421:x1 ag-2422:x1 ag-2425:x1 ag-2427:x1 ag-2428:x1 ag-2434:x1 ag-2435:x1 ag-2436:x1 ag-2440:x2 ag-2441:x1 ag-2443:x1 ag-2444:x2 ag-2447:x1".split()
EXPECTED_CHECKS = "accept_a1_case_and_permutation accept_ea1_complete accept_aea_single_negative reject_unknown_family reject_suffix reject_extra_control reject_duplicate_role reject_missing_output reject_mixed_inputs reject_ea1_unsigned_controls reject_same_signature_a1_box reject_unsigned_alias_guess".split()


def key(row):
    return row["id"] + ":" + row["card"]


def candidate(family, ports):
    return family.lower() in CANDIDATES and aliases.contract(ports) is not None


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def structure(body, leads, marks):
    if len(body) != 3:
        return None
    bases = [(a, b) for a, b in zip(body, body[1:] + body[:1])
             if abs(a[0] - b[0]) < .01 or abs(a[1] - b[1]) < .01]
    if len(bases) != 1:
        raise ValueError("no unique cardinal triangle base")
    a, b = bases[0]
    apex = next(p for p in body if p not in (a, b))
    outputs = [i for i, lead in enumerate(leads) if glyph.close(lead["attachment"], apex)]
    inputs = [i for i, lead in enumerate(leads) if aliases.on_segment(lead["attachment"], a, b)]
    if len(outputs) != 1:
        raise ValueError("no unique apex lead")
    axis = 0 if abs(a[1] - b[1]) < .01 else 1
    signed = {}
    for mark in marks:
        matches = [i for i in inputs if abs(leads[i]["endpoint"][axis] - mark["center"][axis]) < .01]
        if len(matches) != 1 or mark["role"] in signed:
            raise ValueError("polarity mark has no unique base lead")
        signed[mark["role"]] = matches[0]
    return dict(apex_lead=outputs[0], base_leads=inputs, signed_leads=signed,
                output_direction=glyph.direction(apex, leads[outputs[0]]["endpoint"]))


def inspect(row, examples):
    prefix = examples / row["corpus"] / row["id"]
    human = json.loads(prefix.with_suffix(".human.json").read_text())
    root = ET.parse(prefix.with_suffix(".svg")).getroot()
    device, group, parent = aliases.source_group(human, root, row["card"])
    body, leads, interior = aliases.primitives(group, parent)
    marks = aliases.polarity_marks(interior)
    triangle = structure(body, leads, marks)
    cached = {p.lower(): xy for p, xy in device["terminals"].items()}
    bindings = {p.lower(): n.lower() for p, n in device["nets"].items()}
    declared = dict(zip(row["ports"], row["bindings"]))
    if any(p not in declared or declared[p] != n for p, n in bindings.items()):
        raise ValueError("cached declared pin identity disagrees with the SPICE call")
    matched = {}
    for port, point in cached.items():
        indices = [i for i, lead in enumerate(leads) if glyph.close(point, lead["endpoint"])]
        if len(indices) > 1:
            raise ValueError("cached pin matches multiple actual leads")
        if indices:
            matched[port] = indices[0]
    for lead in leads:
        lead["outward_direction"] = glyph.direction(lead["path"][-2], lead["path"][-1])
    complete = candidate(row["family"], row["ports"])
    proof = None
    if complete:
        inspected = aliases.inspect(human, root, row["card"], row["ports"])
        if inspected["shape"] != "triangle" or not inspected["marks_agree"]:
            raise ValueError("complete candidate disagrees with independent outline/polarity")
        proof = {k: inspected[k] for k in ("actual_signal_leads", "signal_frame_matches",
                                          "signal_frame_mismatches", "expected_marks", "marks_agree")}
        if set(row["ports"]) - set(cached) != {"vss"} or len(leads) != len(row["ports"]) - 1:
            raise ValueError("observed omitted-ground geometry changed")
    return dict(row, candidate=complete, source_object=group.get("data-object-id"),
                shape="triangle" if triangle else "box", body=body, external_leads=leads,
                source_marks=marks, triangle=triangle, cached_terminals=cached,
                declared_bindings=declared, cached_port_leads=matched,
                cached_frame_mismatches=sorted(set(cached) - set(matched)),
                absent_cached_ports=sorted(set(row["ports"]) - set(cached)),
                complete_signal_proof=proof,
                source_sha256={s: digest(prefix.with_suffix(s)) for s in (".cir", ".human.json", ".svg")})


def ag1316(examples, row):
    """Literal named external references identify all seven visible ports.

    Cached coordinates do not identify VDD, VREF, VB1 or VISR here. The
    actual port/supply labels and M5's declared D binding do. No source
    declaration/line ordering supplies a mapping.
    """
    prefix = examples / "analoggenie" / "ag-1316"
    human = json.loads(prefix.with_suffix(".human.json").read_text())
    root = ET.parse(prefix.with_suffix(".svg")).getroot()
    ink = conductor_ink(root)
    expected = dict(vdd=[220, -100], vfp1=[250, -30], vref=[250, -70],
                    vx2=[210, 20], vb1=[190, -100], visr=[160, -50], vx1=[140, 20])
    if row["source_marks"] or set(row["declared_bindings"]) != set(expected) | {"vss"}:
        raise ValueError("AG1316 exact unsigned contract changed")
    if sorted(expected.values()) != sorted([list(l["endpoint"]) for l in row["external_leads"]]):
        raise ValueError("AG1316 literal seven-terminal ink changed")
    labels = {n.get("data-object-id"): "".join(n.itertext()).replace(" ", "").lower()
              for n in root.iter() if n.get("data-kind") in ("instance-label", "power-label")}
    evidence = {}
    for port, obj, at, label in (("vdd", "vdd1", [220, -110], "power-label-vdd1"),
                               ("vref", "pVREF1", [260, -70], "instance-label-pVREF1"),
                               ("vb1", "pVB1", [190, -100], "instance-label-pVB1")):
        groups = [(n, t) for n, t, _ in glyph.walk(root) if n.get("data-object-id") == obj]
        if len(groups) != 1 or labels.get(label) != port:
            raise ValueError("AG1316 named external marker changed")
        points = [glyph.point(t, (float(n.get(x)), float(n.get(y))))
                  for n, t, _ in glyph.walk(*groups[0]) if n.tag.endswith("line")
                  for x, y in (("x1", "y1"), ("x2", "y2"))]
        if not any(glyph.close(at, p) for p in points):
            raise ValueError("named reference is not an actual marker terminal")
        tree = wire_tree(ink, [expected[port], at])
        if tree is None:
            raise ValueError("named reference is not physically connected")
        evidence[port] = dict(endpoint=expected[port], marker=obj, label=label,
                              label_text=labels[label], actual_marker_terminal=at, wire_tree=tree)
    m5 = next(d for d in human["devices"] if d["card"].lower() == "m5")
    actual = actual_glyph(root, m5)["terminals"]["D"]
    tree = wire_tree(ink, [expected["visr"], actual])
    if tree is None or m5["nets"]["D"] != row["declared_bindings"]["visr"]:
        raise ValueError("apex no longer joins the declared VISR binding through M5.D")
    evidence["visr"] = dict(endpoint=expected["visr"], other="m5:D", actual_other_terminal=actual,
                            declared_net=m5["nets"]["D"], wire_tree=tree)
    for port in ("vfp1", "vx2", "vx1"):
        index = row["cached_port_leads"].get(port)
        if index is None or not glyph.close(expected[port], row["external_leads"][index]["endpoint"]):
            raise ValueError("cached/actual pin agreement changed")
        evidence[port] = dict(endpoint=expected[port], matched_declared_cached_port=port,
                              declared_net=row["declared_bindings"][port])
    cap = next(d for d in human["devices"] if d["card"].lower() == "cfly")
    cap_terminal = actual_glyph(root, cap)["terminals"]["1"]
    tree = wire_tree(ink, [expected["vx1"], cap_terminal])
    if tree is None or cap["nets"]["1"] != row["declared_bindings"]["vx1"]:
        raise ValueError("VX1 bent lead no longer reaches the declared flying-cap node")
    evidence["vx1"].update(other="cfly:1", actual_other_terminal=cap_terminal, wire_tree=tree)
    return dict(visible_ports=evidence, absent_port="vss", polarity="unsigned",
                source_side_groups=dict(left=["visr"], right=["vref", "vfp1"],
                                        up=["vb1", "vdd"], down=["vx1", "vx2"]),
                limit="Lead placement is proved; direction/current-transfer semantics and a hidden VSS coordinate are not inferred.")


def checks():
    cases = [
        ("accept_a1_case_and_permutation", True, "A1", ["OUT", "INP", "VSS", "INN", "VDD"]),
        ("accept_ea1_complete", True, "EA1", ["vdd", "vss", "inp", "inn", "out"]),
        ("accept_aea_single_negative", True, "AEA", ["vdd", "vss", "inn", "out", "vb"]),
        ("reject_unknown_family", False, "OTA", ["vdd", "vss", "inp", "inn", "out"]),
        ("reject_suffix", False, "A1_extra", ["inp", "inn", "out"]),
        ("reject_extra_control", False, "A1", ["inp", "inn", "out", "va"]),
        ("reject_duplicate_role", False, "A1", ["inp", "in+", "inn", "out"]),
        ("reject_missing_output", False, "EA1", ["vdd", "vss", "inp", "inn"]),
        ("reject_mixed_inputs", False, "A1", ["inp", "inn", "in", "out"]),
        ("reject_ea1_unsigned_controls", False, "EA1", ["vdd", "vss", "vfp1", "vref", "vx3", "vctrl"]),
        ("reject_same_signature_a1_box", False, "A1", ["vdd", "vss", "inp", "inn", "out", "z"]),
        ("reject_unsigned_alias_guess", False, "error_amp", ["vdd", "vss", "vref", "vbn", "out"]),
    ]
    for name, expected, family, ports in cases:
        if candidate(family, ports) != expected:
            raise ValueError(name)
    names = [c[0] for c in cases]
    if names != EXPECTED_CHECKS:
        raise ValueError("exact method-check inventory changed")
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    unknown, _, counts, hashes = census.scan(args.examples)
    selected = [r for r in unknown if r["family"] in FAMILIES]
    rows = [inspect(r, args.examples) for r in selected]
    complete = sorted(key(r) for r in rows if r["candidate"])
    if complete != EXPECTED_COMPLETE:
        raise ValueError("complete candidate exact-name inventory changed")
    families = {}
    for family in sorted(FAMILIES):
        same = [r for r in rows if r["family"] == family]
        families[family] = dict(all=[key(r) for r in same],
                                triangles=[key(r) for r in same if r["shape"] == "triangle"],
                                boxes=[key(r) for r in same if r["shape"] == "box"],
                                complete=[key(r) for r in same if r["candidate"]])
    collisions = collections.defaultdict(list)
    for row in rows:
        collisions[(row["family"], tuple(sorted(row["ports"])))].append(row)
    conflicts = [dict(family=f, unordered_ports=ports,
                      rows=[dict(name=key(r), shape=r["shape"], ordered_ports=r["ports"]) for r in rs])
                 for (f, ports), rs in sorted(collisions.items()) if len({r["shape"] for r in rs}) > 1]
    followup = [r for r in rows if r["family"] in ("aea", "erroramp", "error_amplifier", "error_amp")
                and "vref" in r["ports"]
                and set(r["ports"]) <= set("vdd vss vref out vea vbn nb vb1".split())]
    if [key(r) for r in followup] != EXPECTED_UNSIGNED_FOLLOWUP:
        raise ValueError("unsigned reference followup exact-name inventory changed")
    if any(r["source_marks"] or not r["triangle"] or len(r["triangle"]["base_leads"]) != 1 for r in followup):
        raise ValueError("unsigned reference followup is not a one-base-lead plain triangle")
    script = Path(__file__).resolve()
    deps = [script, Path(aliases.__file__), Path(census.__file__), Path(glyph.__file__),
            script.with_name("cross_caps.py"), script.with_name("converter_loops.py"),
            script.with_name("converter_terminals.py"),
            script.with_name("single_input_amplifiers.py"), script.with_name("digital_symbols.py"),
            script.with_name("mos_forms.py")]
    result = dict(corpus_counts=counts, corpus_sha256=hashes,
                  audit_sha256={p.name: digest(p) for p in deps},
                  families=families, complete_candidates=complete, method_checks=checks(),
                  signature_shape_conflicts=conflicts,
                  unsigned_reference_followup=[key(r) for r in followup],
                  ag1316_extra_control_proof=ag1316(args.examples, next(r for r in rows if key(r) == "ag-1316:x1")),
                  rows=rows)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(rows=len(rows), complete=complete, method_checks=result["method_checks"],
                         signature_shape_conflicts=conflicts)))


if __name__ == "__main__":
    main()
