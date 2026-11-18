#!/usr/bin/env python3
"""AG80/82: literal complete DUT transport; different actual source-pair order.

This is an evidence certificate, not a production classifier. Object names and
source positions identify the two examples only. No electrical simulation is
claimed; the ordered cards, models and parameters are exactly transported.
"""

import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import sys

import bodies_census

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FIGURES = HERE.parent.parent / "figures"
sys.path.insert(0, str(FIGURES))
import thin_connectivity as ink

NETS = {"vdd": "vdd", "vss": "vss", "vin+": "vcont+", "vin-": "vcont-",
        "vcont1": "vin+", "vcont2": "vin-", "vout+": "vout1", "vout-": "vout2",
        "net0": "net1", "net1": "net2", "net2": "net0"}
ORDERS = {"ag-80": ["m1", "m2", "m3", "m4"],
          "ag-82": ["m1", "m3", "m4", "m2"]}
SOURCE_INTERVALS = {"ag-80": [[100, 160], [250, 310]],
                    "ag-82": [[10, 210], [70, 150]]}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dependencies():
    pending, found = [Path(__file__)], {}
    while pending:
        path = pending.pop()
        key = str(path.relative_to(ROOT))
        if key in found:
            continue
        found[key] = sha(path)
        for node in ast.walk(ast.parse(path.read_text())):
            names = [n.name for n in node.names] if isinstance(node, ast.Import) else []
            if isinstance(node, ast.ImportFrom):
                names = [node.module or ""]
            for name in names:
                for base in (HERE, FIGURES):
                    other = base / (name.split(".")[0] + ".py")
                    if other.is_file():
                        pending.append(other)
    return dict(sorted(found.items()))


def transport(a, b):
    af, ar = a
    bf, br = b
    assert set(NETS) == set(af) | {n for r in ar for n in r["nets"]}
    assert len(NETS) == len(set(NETS.values()))
    assert set(NETS.values()) == set(bf) | {n for r in br for n in r["nets"]}
    assert [NETS[n] for n in af] == bf
    assert {r["card"] for r in ar} == {r["card"] for r in br}
    right = {r["card"]: r for r in br}
    rows = []
    for r in ar:
        q = right[r["card"]]
        assert r["kind"] == q["kind"] and r["roles"] == q["roles"]
        assert r["nonterminal_tokens"] == q["nonterminal_tokens"]
        assert [NETS[n] for n in r["nets"]] == q["nets"]
        rows.append(dict(card=r["card"], roles=r["roles"], left=r["nets"],
                         right=q["nets"], nonterminal_tokens=r["nonterminal_tokens"]))
    return rows


def source_geometry(examples, ident):
    context = ink.load_source(examples, ident)
    actual = {}
    for card in ("m1", "m2", "m3", "m4", "m5", "m6"):
        source = context["devices"][card]
        raw = context["cards"][card]
        assert [source["nets"][r].lower() for r in ("D", "G", "S", "B")] == raw[1:5]
        actual[card] = ink.actual_glyph(context["root"], source)
    order = sorted(ORDERS[ident], key=lambda c: actual[c]["terminals"]["D"][0])
    assert order == ORDERS[ident]
    intervals = [sorted(actual[c]["terminals"]["S"][0] for c in pair)
                 for pair in (("m1", "m2"), ("m3", "m4"))]
    assert intervals == SOURCE_INTERVALS[ident]
    changed = copy.deepcopy(context["devices"]["m1"])
    changed["terminals"]["S"][0] += 1
    try:
        ink.actual_glyph(context["root"], changed)
    except (AssertionError, ValueError):
        rejected = True
    else:
        raise AssertionError("detached cached source tip accepted")
    return dict(source_sha256=context["source_sha256"], actual_six_MOS_leads=actual,
                quad_order=order, source_pair_intervals=intervals,
                detached_cached_tip_rejected=rejected)


def collect():
    examples = ROOT / "external/examples/analoggenie"
    texts = [(examples / (n + ".cir")).read_text() for n in ORDERS]
    parsed = [bodies_census.parse(t) for t in texts]
    models = [[line.lower().split() for line in t.splitlines()
               if line.lower().startswith(".model ")] for t in texts]
    assert models[0] == models[1] == [[".model", "nch", "nmos"]]
    rows = transport(*parsed)
    controls = []
    for mutation in ("gate", "bulk", "swap_D_S", "parameter", "formal_order", "drop_card"):
        changed = copy.deepcopy(parsed[1])
        m1 = next(r for r in changed[1] if r["card"] == "m1")
        if mutation == "gate": m1["nets"][1] = "vcont-"
        elif mutation == "bulk": m1["nets"][3] = "vdd"
        elif mutation == "swap_D_S": m1["nets"][0], m1["nets"][2] = m1["nets"][2], m1["nets"][0]
        elif mutation == "parameter": m1["nonterminal_tokens"][1] = "l=999"
        elif mutation == "formal_order": changed[0][2], changed[0][3] = changed[0][3], changed[0][2]
        else: changed[1].remove(m1)
        try:
            transport(parsed[0], changed)
        except AssertionError:
            controls.append(mutation + "_rejected")
        else:
            raise AssertionError(mutation + " accepted")
    reordered = (parsed[1][0], list(reversed(parsed[1][1])))
    assert transport(parsed[0], reordered) == rows
    return dict(scope=__doc__, dependencies=dependencies(), net_transport=NETS,
                ordered_formals={n: p[0] for n, p in zip(ORDERS, parsed)}, models=models,
                complete_DUT_transport=rows, controls=controls + ["card_order_invariant"],
                source={n: source_geometry(examples, n) for n in ORDERS})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    result = collect()
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(dict(cards=len(result["complete_DUT_transport"]),
                          bindings=sum(len(r["roles"]) for r in result["complete_DUT_transport"]),
                          controls=result["controls"],
                          orders={n: r["quad_order"] for n, r in result["source"].items()})))


if __name__ == "__main__":
    main()
