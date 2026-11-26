#!/usr/bin/env python3
"""Source-only second-stage clamp placement certificate, using actual tips.

Usage: antiparallel_anchors.py EXAMPLES OUTPUT [--check]

Three MOS clamps sit between complementary drain-ended stacks. Count every
other transistor channel endpoint first; gates, bodies, visibility and source
orientation cannot hide another channel anchor. Source evidence then checks
the actual upright frames, strict channel-tip bounds and twelve wire paths.
"""
import argparse
import ast
import copy
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import antiparallel_clamps as clamps
import channel_bridges as channels
from cross_caps import actual_glyph
import thin_connectivity as ink

EXPECTED = ["ag-1048:m5--m6", "ag-1052:m6--m7", "ag-739:md1--md2"]
EXCLUDED = ["ag-1149:q3--q4"]


def select(cards, models, pair):
    """A literal netlist certificate; no source/native coordinates participate."""
    ends = [cards[name][1] for name in pair]
    incidence = [[name for name, c in cards.items() if name not in pair and name[0] in "mqjz"
                  and net in (c[1], c[3])] for net in ends]
    if any(len(a) != 2 for a in incidence) or len(set(sum(incidence, []))) != 4:
        return None, incidence
    upper, lower = [], []
    for net, names in zip(ends, incidence):
        by_polarity = {}
        for name in names:
            c = cards[name]
            if name[0] != "m" or c[1] != net or c[3] in ends:
                return None, incidence
            model = models.get(c[5])
            if model not in ("pmos", "nmos") or model in by_polarity:
                return None, incidence
            by_polarity[model] = name
        upper.append(by_polarity["pmos"])
        lower.append(by_polarity["nmos"])
    top, bottom = cards[upper[0]][3], cards[lower[0]][3]
    if cards[upper[1]][3] != top or cards[lower[1]][3] != bottom or len(set(ends + [top, bottom])) != 4:
        return None, incidence
    return dict(upper=upper, lower=lower, end_nets=ends, shared_source_nets=[top, bottom]), incidence


def geometry(pair, upper, lower):
    points = [p[k] for p in pair for k in ("D", "S")]
    left = min(p["D"][0] for p in upper + lower)
    right = max(p["D"][0] for p in upper + lower)
    top = max(p["D"][1] for p in upper)
    bottom = min(p["D"][1] for p in lower)
    return dict(bounds=dict(left=left, right=right, top=top, bottom=bottom),
                upright_anchors=all(p["D"][0] == p["S"][0] and p["D"][1] != p["S"][1] for p in upper + lower),
                facing_anchor_drains=all(p["D"][1] > p["S"][1] for p in upper) and
                all(p["D"][1] < p["S"][1] for p in lower),
                strict_between_rows=all(top < y < bottom for _, y in points),
                strict_between_columns=all(left < x < right for x, _ in points))


def methods():
    cards = {r[0]: r for r in [
        "m0 a a b z n".split(), "m1 b b a z n".split(),
        "m2 a ga high z p".split(), "m3 b gb high z p".split(),
        "m4 a gc low z n".split(), "m5 b gd low z n".split()]}
    models = dict(n="nmos", p="pmos")
    want = dict(upper=["m2", "m3"], lower=["m4", "m5"], end_nets=["a", "b"], shared_source_nets=["high", "low"])
    clamps.same(select(cards, models, ["m0", "m1"])[0], want, "literal four anchors")
    names = ["literal_four_channel_end_anchors"]
    for name, replacement, removal in (
        ("third_unknown_model_anchor_rejected", "m6 a g outside z unknown", None),
        ("third_source_end_anchor_rejected", "m6 outside g a z n", None),
        ("third_unknown_bjt_anchor_rejected", "q6 a g outside z unknown", None),
        ("third_jfet_channel_anchor_rejected", "j6 a g outside unknown", None),
        ("third_mesfet_channel_anchor_rejected", "z6 a g outside unknown", None),
        ("one_missing_anchor_rejected", None, "m3"),
        ("anchor_spanning_both_clamp_nets_rejected", "m2 a ga b z p", None),
        ("same_polarity_anchors_rejected", "m2 a ga high z n", None),
        ("source_ended_anchor_rejected", "m2 high ga a z p", None),
        ("unequal_upper_common_net_rejected", "m3 b gb another z p", None),
    ):
        changed = copy.deepcopy(cards)
        if removal:
            del changed[removal]
        if replacement:
            words = replacement.split()
            changed[words[0]] = words
        assert select(changed, models, ["m0", "m1"])[0] is None, name
        names.append(name)
    tied = {name: ["high" if word == "low" else word for word in card] for name, card in cards.items()}
    assert select(tied, models, ["m0", "m1"])[0] is None
    names.append("tied_upper_lower_common_net_rejected")
    changed = copy.deepcopy(cards)
    changed["m6"] = "m6 elsewhere a other b n".split()
    clamps.same(select(changed, models, ["m0", "m1"])[0], want, "gate/body incidences are not anchors")
    names.append("remote_gate_and_body_incidences_excluded")
    clamps.same(select(dict(reversed(list(cards.items()))), models, ["m0", "m1"])[0], want, "card order")
    names.append("card_permutation")
    pair = [dict(D=[20, 40], S=[80, 40]), dict(D=[80, 60], S=[20, 60])]
    up = [dict(D=[0, 10], S=[0, -30]), dict(D=[100, 10], S=[100, -30])]
    down = [dict(D=[0, 90], S=[0, 130]), dict(D=[100, 90], S=[100, 130])]
    good = geometry(pair, up, down)
    assert all(v for k, v in good.items() if k != "bounds")
    names.append("literal_strict_actual_tip_rectangle")
    for label, point in (("on_upper_boundary_rejected", [20, 10]), ("on_left_boundary_rejected", [0, 40]),
                         ("below_lower_boundary_rejected", [20, 100])):
        altered = copy.deepcopy(pair)
        altered[0]["D"] = point
        observation = geometry(altered, up, down)
        assert not all(v for k, v in observation.items() if k != "bounds"), label
        names.append(label)
    return names


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = clamps.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or "").split(".")[0] + ".py"
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    return dict(sorted(found.items()))


def audit(examples):
    scans = {name: channels.study(examples / name, None) for name in ("analoggenie", "amsnet")}
    selected = {corpus: [r for r in scan["selected"] if "antiparallel_diode_connected" in r["families"]]
                for corpus, scan in scans.items()}
    clamps.same([r["id"] + ":" + r["card"] for r in selected["analoggenie"]], clamps.EXPECTED, "full clamp inventory")
    clamps.same(selected["amsnet"], [], "AMS clamp exclusion")
    rows, excluded = [], []
    for ident in sorted({r["id"] for r in selected["analoggenie"]}):
        pair = [r["card"] for r in selected["analoggenie"] if r["id"] == ident]
        name = ident + ":" + "--".join(pair)
        context = ink.load_source(examples / "analoggenie", ident)
        text = (examples / "analoggenie" / (ident + ".cir")).read_text().lower()
        models = {w[1]: w[2] for line in text.splitlines() if (w := line.split()) and w[0] == ".model"}
        anchors, incidence = select(context["cards"], models, pair)
        if anchors is None:
            excluded.append(dict(name=name, pair=pair, channel_end_incidence=incidence, source_sha256=context["source_sha256"]))
            continue
        names = pair + anchors["upper"] + anchors["lower"]
        glyphs = {n: actual_glyph(context["root"], context["devices"][n]) for n in names}
        observation = geometry([glyphs[n]["terminals"] for n in pair],
                               [glyphs[n]["terminals"] for n in anchors["upper"]],
                               [glyphs[n]["terminals"] for n in anchors["lower"]])
        if not all(v for k, v in observation.items() if k != "bounds"):
            raise ValueError("actual source anchor bounds changed: " + name)
        paths = [clamps.path_proof(context, [pair[i], n], [0, 0])
                 for anchor_set in (anchors["upper"], anchors["lower"]) for i, n in enumerate(anchor_set)]
        rows.append(dict(name=name, pair=pair, anchors=anchors, channel_end_incidence=incidence,
                         cards={n: context["cards"][n] for n in names}, actual_glyphs=glyphs,
                         geometry=observation, source_paths=paths, source_sha256=context["source_sha256"]))
    clamps.same([r["name"] for r in rows], EXPECTED, "exact anchor cohort")
    clamps.same([r["name"] for r in excluded], EXCLUDED, "exact excluded clamp cohort")
    return dict(names=EXPECTED, excluded_names=EXCLUDED, ams_names=[], rows=rows, excluded=excluded,
                methods=methods(), dependency_sha256=dependencies(),
                corpus_sha256={n: r["corpus_sha256"] for n, r in scans.items()},
                corpus_names={n: sorted(p.name.removesuffix(".human.json") for p in (examples / n).glob("*.human.json")) for n in scans},
                limits="Three correlated source MOS clamps. Shared source nets and opposite known anchor polarities are part of this narrower observed contract. No fixed gap, pair center column, source-coordinate target, custom-frame projection or global routing exception is authorized.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.check:
        clamps.same(result, json.loads((HERE / "antiparallel_anchors_cases.json").read_text()), "every frozen anchor field")
    print(json.dumps(dict(names=result["names"], excluded=result["excluded_names"], methods=result["methods"]), sort_keys=True))


if __name__ == "__main__":
    main()
