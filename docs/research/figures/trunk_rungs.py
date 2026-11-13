#!/usr/bin/env python3
"""Compare native horizontal terminal intervals, then verify source losses.

Usage: trunk_rungs.py <examples-dir> <output.json>
                     --baseline <native-dir> --candidate <native-dir> [--check]

An eligible interval uses the same named device/card-pin pair on the same
net, with a nonzero horizontal span in both snapshots. Full same-net wire
coverage decides straightness; labels never connect. The output bucket
requires an actual `opin` class instance on that net in BOTH snapshots.
These are native observations, not source-agreement or trunk-origin counts.
Every lost interval is checked against source deck bindings, transformed
SVG leads and conductor ink. The current source verifier supports MOS gate
pairs; a new unsupported lost terminal fails rather than disappearing.
"""
import argparse
import copy
import hashlib
import itertools
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from channel_bridges import read_cards
from cross_caps import actual_glyph, conductor_ink
from input_resistor_legs import connection, verified_segments


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pins(drawing):
    """Card pin indices name terminals; generated ports are not pair members."""
    result = {}
    names = set()
    for d in drawing["devices"]:
        name = d["name"]
        if not name or name.startswith("_"):
            continue
        if name in names:
            raise ValueError("duplicate native device name: " + name)
        names.add(name)
        for index, p in enumerate(d["pins"]):
            result[name, index] = (p["net"], tuple(p["xy"]), p["term"])
    return result


def segments(drawing, net):
    return [[a, b] for w in drawing["wires"] if w["net"] == net
            for poly in w["segments"] for a, b in zip(poly, poly[1:])]


def horizontal_rows(drawing):
    result = {}
    for w in drawing["wires"]:
        for poly in w["segments"]:
            for a, b in zip(poly, poly[1:]):
                if a[1] == b[1] and a[0] != b[0]:
                    result.setdefault((w["net"], a[1]), []).append(tuple(sorted((a[0], b[0]))))
    return {key: sorted(value) for key, value in result.items()}


def interval(spans, a, b):
    """Union of sorted horizontal intervals covers the entire nonzero span."""
    if a[1] != b[1] or a[0] == b[0]:
        return False
    at, end = sorted((a[0], b[0]))
    for left, right in spans:
        if left > at:
            break
        at = max(at, right)
        if at >= end:
            return True
    return False


def compare(before, after):
    """All eligible pairs, including unchanged false/true observations."""
    pa, pb = pins(before), pins(after)
    ra, rb = horizontal_rows(before), horizontal_rows(after)
    outputs = [{p["net"] for d in drawing["devices"] if d["class"] == "opin" for p in d["pins"]}
               for drawing in (before, after)]
    nets = {}
    for key in sorted(pa.keys() & pb.keys()):
        if pa[key][2] != pb[key][2]:
            raise ValueError("native card-pin identity changed: " + str(key))
        if pa[key][0] == pb[key][0]:
            nets.setdefault(pa[key][0], []).append(key)
    rows = []
    for net, keys in sorted(nets.items()):
        for k, l in itertools.combinations(keys, 2):
            a, b = pa[k][1], pa[l][1]
            c, d = pb[k][1], pb[l][1]
            if a[1] != b[1] or c[1] != d[1] or a[0] == b[0] or c[0] == d[0]:
                continue
            rows.append(dict(net=net, pins=[k, l], before=[a, b], after=[c, d],
                             bucket="output" if net in outputs[0] & outputs[1] else "other",
                             baseline=interval(ra.get((net, a[1]), []), a, b),
                             candidate=interval(rb.get((net, c[1]), []), c, d)))
    return rows


def source_loss(examples, loss, before, after):
    """Actual source leads and ink, with both deck/cache/native pin bindings."""
    ident, net = loss["id"], loss["net"]
    paths = [examples / (ident + suffix) for suffix in (".cir", ".human.json", ".svg")]
    cards = read_cards(paths[0].read_text())
    human = json.loads(paths[1].read_text())
    root = ET.parse(paths[2]).getroot()
    devices = {d["card"]: d for d in human["devices"]}
    glyphs, targets = {}, []
    for name, index in loss["pins"]:
        if not name.startswith("m") or index != 1:
            raise ValueError("unsupported lost source terminal: " + ident + ":" + str((name, index)))
        if cards[name][2] != net or devices[name]["nets"]["G"].lower() != net:
            raise ValueError("source MOS gate binding disagrees: " + ident + ":" + name)
        for drawing in (before, after):
            native = pins(drawing)[name, index]
            if native[0] != net or native[2].lower() != "g":
                raise ValueError("native MOS gate binding disagrees: " + ident + ":" + name)
        glyphs[name] = actual_glyph(root, devices[name])
        targets.append(glyphs[name]["terminals"]["G"])
    ink, missing = verified_segments(human, net, conductor_ink(root))
    if missing:
        raise ValueError("source cache has conductor segments without SVG ink: " + ident)
    straight = [s for s in ink if s[0][1] == s[1][1] == targets[0][1]]
    native = {}
    for label, drawing in (("baseline", before), ("candidate", after)):
        points = [list(pins(drawing)[name, index][1]) for name, index in loss["pins"]]
        native[label] = dict(connection=connection(segments(drawing, net), points),
                             labels=[l for l in drawing["labels"] if l["net"] == net])
    return dict(**loss, source_glyphs=glyphs, source_targets=targets, source_segments=ink,
                source_connection=connection(ink, targets), source_straight=connection(straight, targets),
                source_sha256={p.name: digest(p) for p in paths}, native=native)


def method_checks():
    """Literal intervals, output glyphs and terminal identities are the oracle."""
    passed = []
    def device(name, at, net="n", cls="mos"):
        return dict(name=name, **{"class": cls}, pins=[dict(term="g", net=net, xy=at)])
    before = dict(devices=[device("m1", [0, 0]), device("m2", [10, 0])],
                  wires=[dict(net="n", segments=[[[0, 0], [4, 0]], [[4, 0], [10, 0]]])], labels=[])
    row, = compare(before, before)
    assert row["baseline"] and row["candidate"] and row["bucket"] == "other"
    passed.append("touching_intervals_cover")
    shuffled = copy.deepcopy(before)
    shuffled["wires"][0]["segments"] = [list(reversed(s)) for s in reversed(shuffled["wires"][0]["segments"])]
    assert compare(shuffled, shuffled) == [row]
    passed.append("wire_order_and_direction_independent")
    gap = copy.deepcopy(before)
    gap["wires"][0]["segments"][1][0] = [6, 0]
    gap["labels"] = [dict(net="n", at=[4, 0]), dict(net="n", at=[6, 0])]
    assert not compare(before, gap)[0]["candidate"]
    passed.append("named_gap_not_connected")
    gap["wires"].append(dict(net="other", segments=[[[4, 0], [6, 0]]]))
    assert not compare(before, gap)[0]["candidate"]
    passed.append("wrong_net_cannot_fill_gap")
    gap["wires"][0]["segments"].append([[4, 0], [4, 5], [6, 5], [6, 0]])
    assert connection(segments(gap, "n"), [[0, 0], [10, 0]])["continuous"]
    assert not compare(before, gap)[0]["candidate"]
    passed.append("continuous_detour_not_straight")
    for point, name in (([0, 0], "zero_span_ineligible"), ([10, 1], "off_row_ineligible")):
        changed = copy.deepcopy(before)
        changed["devices"][1]["pins"][0]["xy"] = point
        assert not compare(before, changed) and not compare(changed, before)
        passed.append(name)
    changed = copy.deepcopy(before)
    changed["devices"][1]["pins"][0]["net"] = "other"
    assert not compare(before, changed)
    passed.append("changed_net_ineligible")
    changed = copy.deepcopy(before)
    changed["devices"][1]["pins"][0]["term"] = "d"
    try:
        compare(before, changed)
    except ValueError:
        passed.append("changed_terminal_identity_rejected")
    else:
        raise AssertionError("changed terminal identity accepted")
    output = copy.deepcopy(before)
    output["devices"].append(device("_output", [20, 0], cls="opin"))
    assert compare(before, output)[0]["bucket"] == "other"
    assert compare(output, before)[0]["bucket"] == "other"
    assert compare(output, output)[0]["bucket"] == "output"
    passed.append("output_glyph_required_in_both_snapshots")
    output["devices"][-1]["class"] = "ipin"
    output["roles"] = {"n": "output"}
    assert compare(output, output)[0]["bucket"] == "other"
    passed.append("semantic_output_role_does_not_supply_glyph")
    verified, missing = verified_segments(before, "n", [])
    assert not verified and missing and not connection(verified, [[0, 0], [10, 0]])["continuous"]
    passed.append("cache_only_source_wire_cannot_connect")
    return passed


def audit(examples, baseline, candidate):
    names = sorted(p.name.removesuffix(".human.json") for p in examples.glob("*.human.json"))
    if not names:
        raise ValueError("no paired source drawings")
    expected = [name + ".json" for name in names]
    prefix = names[0].rsplit("-", 1)[0] + "-"
    for directory in (baseline, candidate):
        actual = sorted(p.name for p in directory.glob(prefix + "*.json") if not p.name.endswith(".report.json"))
        if actual != sorted(expected):
            raise ValueError("native drawing names differ from exact paired source inventory: " + str(directory))
    counts = {bucket: dict(eligible=0, before=0, after=0, gained=[], lost=[]) for bucket in ("output", "other")}
    hashes = {"baseline": {}, "candidate": {}}
    losses = []
    for ident in names:
        docs = []
        for label, directory in (("baseline", baseline), ("candidate", candidate)):
            path = directory / (ident + ".json")
            hashes[label][path.name] = digest(path)
            docs.append(json.loads(path.read_text()))
        for row in compare(*docs):
            bucket = counts[row["bucket"]]
            bucket["eligible"] += 1
            bucket["before"] += row["baseline"]
            bucket["after"] += row["candidate"]
            if row["baseline"] == row["candidate"]:
                continue
            changed = dict(id=ident, **{k: row[k] for k in ("net", "pins", "before", "after")})
            bucket["gained" if row["candidate"] else "lost"].append(changed)
            if not row["candidate"]:
                losses.append(source_loss(examples, changed, *docs))
    binaries = {label: digest(directory / "cktimg-json") if (directory / "cktimg-json").exists() else None
                for label, directory in (("baseline", baseline), ("candidate", candidate))}
    return dict(corpus=examples.name, native_names=expected, counts=counts, native_sha256=hashes,
                native_executable_sha256=binaries,
                source_losses=losses, method_checks=method_checks(),
                source_regressions=[r["id"] for r in losses if r["source_straight"]["continuous"]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = audit(args.examples, args.baseline, args.candidate)
    dependencies = ("trunk_rungs.py", "channel_bridges.py", "cross_caps.py", "input_resistor_legs.py",
                    "input_resistors.py", "converter_loops.py", "converter_terminals.py", "sampling_cells.py")
    result["dependency_sha256"] = {name: digest(Path(__file__).with_name(name)) for name in dependencies}
    if args.check:
        frozen = json.loads(Path(__file__).with_name("trunk_rungs_cases.json").read_text())
        # JSON normalizes tuple coordinates and pin keys to lists.
        if json.loads(json.dumps(result)) != frozen[result["corpus"]]:
            raise ValueError("rung evidence differs from the exact frozen inventory")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(corpus=result["corpus"], counts={bucket: {k: len(v) if isinstance(v, list) else v
                     for k, v in row.items()} for bucket, row in result["counts"].items()},
                     source_regressions=result["source_regressions"], method_checks=result["method_checks"]), indent=2))


if __name__ == "__main__":
    main()
