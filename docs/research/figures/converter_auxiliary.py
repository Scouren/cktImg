#!/usr/bin/env python3
"""Converter auxiliary switches -> expanded mirror topology and actual ink.

Reuses the frozen converter bus/loop certificates. Selection reads only
declared transistor types and pin bindings; source SVG leads and conductor
paths independently measure placement and physical continuity. A disconnected
source also must remain disconnected in the complete actual conductor graph.
No label, cached segment without ink, or proper crossing supplies an edge.
"""
import argparse
import json
from pathlib import Path
from xml.etree import ElementTree as ET

import converter_bus as bus
import converter_loops as loops
import power_paths as power


ROLES = ("output", "reference", "controlled", "n_reference", "n_mirror", "bias")


def select(text, auxiliary, input_bus, coil_input):
    """Six-MOS load behind an already-certified auxiliary bus PMOS."""
    cards = power.MOS.read_cards(text)
    types, _ = power.classify(text)
    a = cards[auxiliary]
    if a[0][0] != "m" or types[auxiliary]["type"] != "pmos":
        return None
    if input_bus not in (a[1], a[3]) or not types[auxiliary]["gate_only"]:
        return None
    supply = a[3] if a[1] == input_bus else a[1]
    if power.MOS.rail(supply) or supply in (input_bus, coil_input):
        return None
    pm = [n for n, w in cards.items() if n != auxiliary and n[0] == "m" and
          types[n]["type"] == "pmos" and w[3] == supply]
    if len(pm) != 3:
        return None
    reference = [n for n in pm if cards[n][1] == cards[n][2]]
    if len(reference) != 1:
        return None
    reference = reference[0]
    output = [n for n in pm if n != reference and cards[n][1] == coil_input and
              cards[n][2] == cards[reference][2]]
    if len(output) != 1:
        return None
    output = output[0]
    controlled = next(n for n in pm if n not in (output, reference))
    ref_net, control_net = cards[reference][1], cards[controlled][1]
    if len({supply, ref_net, control_net, coil_input, input_bus}) != 5:
        return None
    nm = [n for n, w in cards.items() if n[0] == "m" and types[n]["type"] == "nmos" and
          power.MOS.rail(w[3]) == "sink"]
    n_reference = [n for n in nm if cards[n][1] == cards[n][2] == control_net]
    n_mirror = [n for n in nm if cards[n][1] == ref_net and cards[n][2] == control_net]
    bias = [n for n in nm if cards[n][1] == control_net and cards[n][2] != control_net and
            types[n]["gate_only"]]
    if not len(n_reference) == len(n_mirror) == len(bias) == 1:
        return None
    members = dict(zip(ROLES, [output, reference, controlled, n_reference[0], n_mirror[0], bias[0]]))
    assert len(set(members.values())) == 6
    return dict(auxiliary=auxiliary, members=members, supply=supply, reference_net=ref_net,
                control_net=control_net, input_bus=input_bus, coil_input=coil_input)


def geometry(group, terminals, auxiliary, main):
    t = {role: terminals[name] for role, name in group["members"].items()}
    pm, nm = [t[k] for k in ROLES[:3]], [t[k] for k in ROLES[3:]]
    o, r, c, nr, ng, nb = [t[k] for k in ROLES]
    return dict(all_pm_vertical=all(p["D"][0] == p["S"][0] and p["S"][1] < p["D"][1] for p in pm),
                all_nm_vertical=all(p["D"][0] == p["S"][0] and p["D"][1] < p["S"][1] for p in nm),
                pm_sources_same_y=len({p["S"][1] for p in pm}) == 1,
                output_left_reference=o["D"][0] < r["D"][0], reference_left_control=r["D"][0] < c["D"][0],
                controlled_over_ndiode=c["D"][0] == nr["D"][0] and c["D"][1] < nr["D"][1],
                reference_over_nmirror=r["D"][0] == ng["D"][0] and r["D"][1] < ng["D"][1],
                nm_bias_right=nb["D"][0] > nr["D"][0] and nb["D"][0] > ng["D"][0],
                auxiliary_above_pm_sources=auxiliary[1] <= min(p["S"][1] for p in pm),
                auxiliary_left_pm_sources=auxiliary[0] <= min(p["S"][0] for p in pm),
                six_above_main=max(p[k][1] for p in t.values() for k in ("D", "S")) < main[1],
                pm_above_main=max(p["D"][1] for p in pm) < main[1])


def connections(group, local, devices, drawing, ink, terminals):
    m = group["members"]
    main = local["main"][0]
    pin = lambda name, net: next(p for p in ("D", "S") if devices[name]["nets"][p] == net)
    pairs = dict(supply=[(group["auxiliary"], pin(group["auxiliary"], group["supply"]))] +
                       [(m[role], "S") for role in ROLES[:3]],
                 pm_mirror=[(m["output"], "G"), (m["reference"], "D"), (m["reference"], "G"), (m["n_mirror"], "D")],
                 nm_mirror=[(m["controlled"], "D"), (m["n_reference"], "D"), (m["n_reference"], "G"),
                            (m["n_mirror"], "G"), (m["bias"], "D")],
                 coil_return=[(m["output"], "D"), (main, pin(main, group["coil_input"]))])
    result = {}
    for role, ends in pairs.items():
        net = devices[ends[0][0]]["nets"][ends[0][1]]
        assert all(devices[name]["nets"][pin] == net for name, pin in ends)
        targets = [dict(card=name, pin=pin, xy=terminals[name][pin]) for name, pin in ends]
        segments = [[a, b] for w in drawing["wires"] if w["net"].lower() == net
                    for line in w["segments"] for a, b in zip(line, line[1:])]
        verified = [s for s in segments if any((loops.close(s[0], z[0]) and loops.close(s[1], z[1])) or
                    (loops.close(s[0], z[1]) and loops.close(s[1], z[0])) for z in ink)]
        tree = loops.wire_tree(verified, [p["xy"] for p in targets])
        if tree is None:
            assert loops.wire_tree(ink, [p["xy"] for p in targets]) is None, (group, role)
        result[role] = dict(net=net, targets=targets, continuous=tree is not None,
                            spanning_ink_segments=tree,
                            cache_segments_without_ink=[s for s in segments if s not in verified],
                            disconnected_in_complete_ink=tree is None)
    return result


def isomorphism(examples, rows):
    """Literal boundary: identical 28-pin local graph, different source use."""
    a, b = "ag-1193", "ag-1199"
    cards = [power.MOS.read_cards((examples / (name + ".cir")).read_text()) for name in (a, b)]
    maps = dict(net11="net8", vcont1="vcont1", vin="vin", vdd="vdd", vx1="vx1",
                net1="net0", net6="net4", vctrl="vctrl", vss="vss", vb3="vb5")
    by_id = {row["id"]: row for row in rows}
    ga, gb = [by_id[name]["group"] for name in (a, b)]
    names = [[g["auxiliary"], *g["members"].values()] for g in (ga, gb)]
    pins = []
    for da, db in zip(*names):
        for index, pin in enumerate(("D", "G", "S", "B"), 1):
            na, nb = cards[0][da][index], cards[1][db][index]
            assert maps[na] == nb
            pins.append(dict(left=dict(card=da, pin=pin, net=na), right=dict(card=db, pin=pin, net=nb)))
    assert by_id[a]["auxiliary_source"]["continuous"] and not by_id[b]["auxiliary_source"]["continuous"]
    assert by_id[a]["auxiliary_source"]["relation"]["horizontal"] and not by_id[b]["auxiliary_source"]["relation"]["horizontal"]
    return dict(left=a, right=b, net_map=maps, pins=pins,
                scope="Seven-device induced local graph only; outside circuit incidence and placement differ.")


def method_checks():
    text = """.model p pmos
.model n nmos
.subckt dut
MA supply ga bus vdd p
MO coil ref supply vdd p
MR ref ref supply vdd p
MC ctrl drive supply vdd p
MNREF ctrl ctrl 0 0 n
MNM ref ctrl 0 0 n
MNB ctrl bias 0 0 n
.ends dut
"""
    expected = dict(output="mo", reference="mr", controlled="mc", n_reference="mnref", n_mirror="mnm", bias="mnb")
    names = []
    def run(value):
        return select(value, "ma", "bus", "coil")
    assert run(text)["members"] == expected
    names.append("literal_six_role_contract")
    for name, changed in (
        ("wrong_auxiliary_polarity", text.replace("MA supply ga bus vdd p", "MA supply ga bus vdd n")),
        ("missing_pm_reference", text.replace("MR ref ref", "MR ref other")),
        ("wrong_mirror_output_net", text.replace("MO coil ref", "MO elsewhere ref")),
        ("wrong_bias_source", text.replace("MNB ctrl bias 0", "MNB ctrl bias remote")),
        ("duplicate_source_branch", text.replace(".ends dut", "MX x gx supply vdd p\n.ends dut")),
        ("duplicate_bias_branch", text.replace(".ends dut", "MX ctrl bx 0 0 n\n.ends dut")),
        ("non_gate_only_bias", text.replace(".ends dut", "R1 bias 0 1k\n.ends dut")),
    ):
        assert run(changed) is None, name
        names.append(name)
    assert run(text.replace("MA supply ga bus", "MA bus ga supply"))["members"] == expected
    names.append("auxiliary_ds_order_does_not_select_orientation")
    assert run(text.replace("MO coil ref supply vdd", "MO coil ref supply supply"))["members"] == expected
    names.append("source_tied_well_is_not_channel_incidence")
    lines = text.splitlines()
    assert run("\n".join(lines[:3] + list(reversed(lines[3:-1])) + lines[-1:]))["members"] == expected
    names.append("card_permutation_preserves_roles")
    assert loops.wire_tree([[[0, 0], [0, 20]], [[-10, 10], [10, 10]]], [[0, 0], [10, 10]]) is None
    names.append("proper_crossing_is_not_a_junction")
    assert loops.wire_tree([[[0, 0], [0, 20]], [[0, 10], [10, 10]]], [[0, 0], [10, 10]]) is not None
    names.append("endpoint_t_join_is_continuous")
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path, required=True)
    args = parser.parse_args()
    base = Path(__file__).parent
    bus_path, loop_path = [base / (name + "_cases.json") for name in ("converter_bus", "converter_loops")]
    buses, inventory = [json.loads(p.read_text()) for p in (bus_path, loop_path)]
    local = {g["id"]: g for g in inventory["analoggenie"]["selected"]}
    assert inventory["amsnet"]["selected"] == []
    for name, expected in buses["source_sha256"].items():
        assert bus.sha(args.examples / name) == expected, name
    rows, excluded, native_hashes = [], [], {}
    for branch in buses["rows"]:
        ident = branch["id"]
        g = local[ident]
        text = (args.examples / (ident + ".cir")).read_text()
        group = select(text, branch["card"], branch["net"], g["nets"]["input_near"])
        if group is None:
            excluded.append(ident + ":" + branch["card"])
            continue
        human = json.loads((args.examples / (ident + ".human.json")).read_text())
        devices = {d["card"]: d for d in human["devices"]}
        root = ET.parse(args.examples / (ident + ".svg")).getroot()
        glyphs = {n: loops.actual_glyph(root, devices[n]) for n in group["members"].values()}
        terminals = {n: p["terminals"] for n, p in {**glyphs, **g["source_glyphs"],
                     branch["card"]: branch["source_glyph"]}.items()}
        native_path = args.native / (ident + ".json")
        native_hashes[native_path.name] = bus.sha(native_path)
        assert native_hashes[native_path.name] == buses["native_sha256"]["final13"][native_path.name]
        native = json.loads(native_path.read_text())
        nt = {d["name"].lower(): {p["term"].upper(): p["xy"] for p in d["pins"]} for d in native["devices"]}
        auxiliary_pin = next(p for p in ("D", "S") if devices[branch["card"]]["nets"][p] == group["supply"])
        main_bus_pin = next(p for p in ("D", "S") if devices[g["main"][0]]["nets"][p] == branch["net"])
        row = dict(id=ident, card=branch["card"], group=group, source_glyphs=glyphs,
                   source_geometry=geometry(group, terminals, terminals[branch["card"]][auxiliary_pin],
                                            terminals[g["main"][0]][main_bus_pin]),
                   native_geometry=geometry(group, nt, nt[branch["card"]][auxiliary_pin], nt[g["main"][0]][main_bus_pin]),
                   source_connections=connections(group, g, devices, human, loops.conductor_ink(root), terminals),
                   auxiliary_source={k: v for k, v in branch["source"].items() if k not in ("segments", "spanning_segments")},
                   auxiliary_final13={k: v for k, v in branch["final13"].items() if k not in ("segments", "spanning_segments")})
        rows.append(row)
    name = lambda r: r["id"] + ":" + r["card"]
    all_names = [name(r) for r in rows]
    misses = buses["source_comparison"]["final13"]["source_connected_native_separate"]
    summary = dict(selected=all_names, excluded=excluded, source_connected_native_separate=misses,
                   expanded_misses=sorted(set(misses) & set(all_names)), other_misses=sorted(set(misses) - set(all_names)))
    for version in ("source_geometry", "native_geometry"):
        summary[version] = {k: dict(agree=[name(r) for r in rows if r[version][k]],
                                    exceptions=[name(r) for r in rows if not r[version][k]]) for k in rows[0][version]}
    summary["source_connections"] = {k: dict(continuous=[name(r) for r in rows if r["source_connections"][k]["continuous"]],
                                            separate=[name(r) for r in rows if not r["source_connections"][k]["continuous"]])
                                     for k in rows[0]["source_connections"]}
    result = dict(study="Expanded converter auxiliary branch placement", evidence={p.name: bus.sha(p) for p in (bus_path, loop_path)},
                  source_sha256=buses["source_sha256"], native_sha256=native_hashes, rows=rows, summary=summary,
                  local_graph_counterexample=isomorphism(args.examples, rows), method_checks=method_checks())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(selected=len(rows), excluded=len(excluded), expanded_misses=len(summary["expanded_misses"]),
                          other_misses=summary["other_misses"], source_connections={k: len(v["continuous"]) for k, v in summary["source_connections"].items()},
                          method_checks=result["method_checks"]), indent=2))


if __name__ == "__main__":
    main()
