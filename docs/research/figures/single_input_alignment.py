#!/usr/bin/env python3
"""Actual single-input lead alignment in the old 47-case cohort and AEA2423.

Usage: single_input_alignment.py EXAMPLES OUTPUT.json [--check]

Source SPICE selects complete contracts. Own-symbol transformed SVG bodies,
polarity strokes and external lead paths identify the input/output axes.
Where unsigned input and bias leads share the base, actual named markers
and outside pins connected through source ink identify the input. Cached
input coordinates never choose the lead. This script renders no native
drawing and changes no production rule.
"""

import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import block_aliases as aliases
import digital_symbols as digital
import reference_amplifiers as reference
import single_input_amplifiers as single
from cross_caps import conductor_ink
from converter_loops import wire_tree

EXPECTED_OLD = "ag-1363:x1 ag-1364:x1 ag-1366:x1 ag-1368:x1 ag-1369:x1 ag-1371:x1 ag-1391:x1 ag-1394:x1 ag-1395:x1 ag-1397:x1 ag-1400:x1 ag-1401:x1 ag-1402:x1 ag-1403:x1 ag-1406:x1 ag-1408:x1 ag-1413:x1 ag-1414:x1 ag-1416:x1 ag-1417:x1 ag-1421:x1 ag-1422:x1 ag-1424:x1 ag-1425:x1 ag-1426:x1 ag-1427:x1 ag-1429:x1 ag-1430:x1 ag-1432:x1 ag-1434:x1 ag-1436:x1 ag-1437:x1 ag-1438:x1 ag-1439:x1 ag-1441:x1 ag-1442:x1 ag-1444:x1 ag-1445:x1 ag-1446:x1 ag-1448:x1 ag-1449:x1 ag-1452:x1 ag-1453:x1 ag-1454:x1 ag-1455:x1 ag-1460:x1 ag-2418:x1".split()
EXPECTED_EXTRA = ["ag-2423:x1"]
EXPECTED_CHECKS = "centered_negative offset_negative offset_positive centered_unsigned rotate_and_reflect_same_alignment reject_wrong_polarity reject_missing_polarity reject_missing_apex_lead reject_ambiguous_signed_lead reject_unsigned_bias_ambiguity resolve_unsigned_by_connected_lead reject_disconnected_unsigned_proof".split()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def key(row):
    return row["id"] + ":" + row["card"]


def scan(examples):
    rows, counts, hashes = [], {}, {}
    for corpus in ("analoggenie", "amsnet"):
        paths = sorted((examples / corpus).glob("*.human.json"))
        counts[corpus] = len(paths)
        hashed = hashlib.sha256()
        for hp in paths:
            cid = hp.name.removesuffix(".human.json")
            cp = hp.with_suffix("").with_suffix(".cir")
            for p in (hp, cp):
                hashed.update(p.name.encode() + bytes.fromhex(digest(p)))
            text = cp.read_text()
            definitions = digital.declarations(text)
            for card, words in aliases.read_cards(text).items():
                if not card.startswith("x"):
                    continue
                end = next((i for i, word in enumerate(words) if "=" in word or word == "params:"), len(words))
                family = words[end - 1]
                ports = definitions[family]
                role = single.contract(family, ports)
                extra = family == "aea" and aliases.contract(ports) is not None and sum(single.role(p) in aliases.INPUTS for p in ports) == 1
                if role is None and not extra:
                    continue
                bindings = words[1:end - 1]
                if len(bindings) != len(ports):
                    raise ValueError("source declaration/call length mismatch")
                if extra:
                    role = next(single.role(p) for p in ports if single.role(p) in aliases.INPUTS)
                rows.append(dict(corpus=corpus, id=cid, card=card, family=family,
                                 ports=ports, bindings=bindings, input_role=role,
                                 cohort="added_aea" if extra else "old_single_input"))
        hashes[corpus] = hashed.hexdigest()
    if counts != dict(analoggenie=2202, amsnet=734):
        raise ValueError("complete paired source corpus changed")
    for cohort, expected in (("old_single_input", EXPECTED_OLD), ("added_aea", EXPECTED_EXTRA)):
        if sorted(key(r) for r in rows if r["cohort"] == cohort) != expected:
            raise ValueError(cohort + " exact-name inventory changed")
    return sorted(rows, key=key), counts, hashes


def geometry(body, leads, marks, role, connected=()):
    """Identify actual leads, then measure in the triangle's own axes."""
    if len(body) != 3:
        raise ValueError("expected one triangular body")
    bases = [(a, b) for a, b in zip(body, body[1:] + body[:1])
             if abs(a[0] - b[0]) < aliases.TOLERANCE or abs(a[1] - b[1]) < aliases.TOLERANCE]
    if len(bases) != 1:
        raise ValueError("no unique cardinal base")
    a, b = bases[0]
    axis = 0 if abs(a[1] - b[1]) < aliases.TOLERANCE else 1
    apex = next(p for p in body if p != a and p != b)
    outputs = [i for i, lead in enumerate(leads) if aliases.glyph.close(lead["attachment"], apex)]
    inputs = [i for i, lead in enumerate(leads) if aliases.on_segment(lead["attachment"], a, b)]
    if len(outputs) != 1:
        raise ValueError("no unique apex lead")
    if role == "unsigned":
        if marks:
            raise ValueError("unsigned input has polarity strokes")
        selected = inputs if len(inputs) == 1 else [i for i in inputs if i in connected]
    else:
        if len(marks) != 1 or marks[0]["role"] != role:
            raise ValueError("named input has no unique matching polarity mark")
        selected = [i for i in inputs if abs(leads[i]["endpoint"][axis] - marks[0]["center"][axis]) < aliases.TOLERANCE]
    if len(selected) != 1:
        raise ValueError("input lead is absent or ambiguous")
    inp, out = selected[0], outputs[0]
    midpoint = [(a[i] + b[i]) / 2 for i in range(2)]
    direction = aliases.glyph.direction(midpoint, apex)
    forward = {"right": [1, 0], "left": [-1, 0], "up": [0, -1], "down": [0, 1]}[direction]
    transverse = [-forward[1], forward[0]]
    if aliases.glyph.direction(apex, leads[out]["endpoint"]) != direction:
        raise ValueError("output does not continue outward from apex")
    project = lambda p, q: sum((p[i] - q[i]) * transverse[i] for i in range(2))
    endpoint = project(leads[inp]["endpoint"], leads[out]["endpoint"])
    attachment = project(leads[inp]["attachment"], apex)
    return dict(input_lead=inp, output_lead=out, base_leads=inputs,
                apex=apex, forward_axis=forward, transverse_axis=transverse,
                endpoint_offset=endpoint, attachment_offset=attachment,
                endpoint_aligned=abs(endpoint) < aliases.TOLERANCE,
                attachment_aligned=abs(attachment) < aliases.TOLERANCE)


def inspect(row, examples):
    prefix = examples / row["corpus"] / row["id"]
    human = json.loads(prefix.with_suffix(".human.json").read_text())
    root = ET.parse(prefix.with_suffix(".svg")).getroot()
    device, group, parent = aliases.source_group(human, root, row["card"])
    body, leads, interior = aliases.primitives(group, parent)
    marks = aliases.polarity_marks(interior)
    declared = dict(zip(row["ports"], row["bindings"]))
    if any(p.lower() not in declared or declared[p.lower()] != net.lower() for p, net in device["nets"].items()):
        raise ValueError("source device/declaration binding disagrees")
    proof = dict(method="polarity_mark" if row["input_role"] != "unsigned" else "sole_base_lead")
    connected = []
    if row["input_role"] == "unsigned":
        port = next(p for p in row["ports"] if single.role(p) == "unsigned")
        ink = conductor_ink(root)
        markers = []
        for marker in reference.markers(root):
            if marker["name"] != declared[port]:
                continue
            for i, lead in enumerate(leads):
                tree = wire_tree(ink, [lead["endpoint"], marker["terminal"]])
                if tree is not None:
                    markers.append(dict(marker, lead=i, wire_tree=tree))
        outside = reference.outside_pins(root, human, dict(declared_bindings=declared, external_leads=leads), port, ink)
        connected = sorted({p["lead"] for p in markers + outside})
        proof.update(markers=markers, outside_pins=outside, declared_net=declared[port])
    measured = geometry(body, leads, marks, row["input_role"], connected)
    if row["input_role"] == "unsigned" and len(measured["base_leads"]) > 1:
        proof["method"] = "named_marker_or_outside_pin_and_actual_wire"
    return dict(row, source_object=group.get("data-object-id"), body=body,
                external_leads=leads, source_marks=marks, input_evidence=proof,
                alignment=measured,
                source_sha256={s: digest(prefix.with_suffix(s)) for s in (".cir", ".human.json", ".svg")})


def checks():
    body = [[-40, -40], [40, 0], [-40, 40]]
    leads = [dict(attachment=[-40, 0], endpoint=[-60, 0]), dict(attachment=[40, 0], endpoint=[60, 0])]
    mark = [dict(role="negative", center=[-30, 0])]
    if not geometry(body, leads, mark, "negative")["endpoint_aligned"]:
        raise ValueError("centered_negative")
    names = ["centered_negative"]
    shifted = copy.deepcopy(leads)
    shifted[0] = dict(attachment=[-40, -20], endpoint=[-60, -20])
    for kind in ("negative", "positive"):
        if geometry(body, shifted, [dict(role=kind, center=[-30, -20])], kind)["endpoint_offset"] != -20:
            raise ValueError("offset_" + kind)
        names.append("offset_" + kind)
    if not geometry(body, leads, [], "unsigned")["endpoint_aligned"]:
        raise ValueError("centered_unsigned")
    names.append("centered_unsigned")
    for transform in (lambda p: [p[1], -p[0]], lambda p: [-p[0], p[1]]):
        rotated = [dict(attachment=transform(l["attachment"]), endpoint=transform(l["endpoint"])) for l in shifted]
        actual = geometry([transform(p) for p in body], rotated, [dict(role="negative", center=transform([-30, -20]))], "negative")
        if actual["endpoint_aligned"] or abs(actual["endpoint_offset"]) != 20:
            raise ValueError("rotate_and_reflect_same_alignment")
    names.append("rotate_and_reflect_same_alignment")
    bias = leads + [dict(attachment=[-40, 20], endpoint=[-60, 20])]
    bad = [
        ("reject_wrong_polarity", leads, [dict(role="positive", center=[-30, 0])], "negative", []),
        ("reject_missing_polarity", leads, [], "negative", []),
        ("reject_missing_apex_lead", leads[:1], mark, "negative", []),
        ("reject_ambiguous_signed_lead", leads + [leads[0]], mark, "negative", []),
        ("reject_unsigned_bias_ambiguity", bias, [], "unsigned", []),
    ]
    for name, ls, ms, role, connected in bad:
        try:
            geometry(body, ls, ms, role, connected)
        except ValueError:
            names.append(name)
        else:
            raise ValueError(name)
    if geometry(body, bias, [], "unsigned", [2])["input_lead"] != 2:
        raise ValueError("resolve_unsigned_by_connected_lead")
    names.append("resolve_unsigned_by_connected_lead")
    try:
        geometry(body, bias, [], "unsigned", [1])
    except ValueError:
        names.append("reject_disconnected_unsigned_proof")
    else:
        raise ValueError("reject_disconnected_unsigned_proof")
    if names != EXPECTED_CHECKS:
        raise ValueError("method-check exact names changed")
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    selected, counts, hashes = scan(args.examples)
    rows = [inspect(row, args.examples) for row in selected]
    cohorts = {}
    for cohort in ("old_single_input", "added_aea"):
        same = [r for r in rows if r["cohort"] == cohort]
        cohorts[cohort] = dict(names=[key(r) for r in same],
                              input_roles=dict(collections.Counter(r["input_role"] for r in same)),
                              endpoint_aligned=[key(r) for r in same if r["alignment"]["endpoint_aligned"]],
                              attachment_aligned=[key(r) for r in same if r["alignment"]["attachment_aligned"]],
                              endpoint_offsets=dict(collections.Counter(str(r["alignment"]["endpoint_offset"]) for r in same)))
    if cohorts["old_single_input"]["endpoint_aligned"] or cohorts["old_single_input"]["attachment_aligned"]:
        raise ValueError("old-cohort off-axis observation changed")
    if cohorts["added_aea"]["endpoint_aligned"] != EXPECTED_EXTRA or cohorts["added_aea"]["attachment_aligned"] != EXPECTED_EXTRA:
        raise ValueError("AEA2423 centered observation changed")
    files = ("single_input_alignment.py", "single_input_amplifiers.py", "block_aliases.py", "digital_symbols.py",
             "reference_amplifiers.py", "controller_glyphs.py", "cross_caps.py", "converter_loops.py", "converter_terminals.py")
    result = dict(corpus_counts=counts, corpus_sha256=hashes, method_checks=checks(),
                  cohorts=cohorts, rows=rows, audit_sha256={n: digest(HERE / n) for n in files})
    encoded = json.dumps(result, sort_keys=True, indent=2) + "\n"
    if args.check and encoded != (HERE / "single_input_alignment_cases.json").read_text():
        raise ValueError("durable source inventory differs")
    args.output.write_text(encoded)
    print(json.dumps(dict(cohorts=cohorts, method_checks=result["method_checks"]), sort_keys=True))


if __name__ == "__main__":
    main()
