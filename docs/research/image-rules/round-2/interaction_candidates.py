#!/usr/bin/env python3
"""Measure composition of proposed symbol contracts and topology selectors.

Research only: this runs the prior Python selectors, not engine layout. Input
is the frozen exact corpus; output is its named candidate sets and raw witnesses.
The hypothetical extension changes only the complete nine-port signed contract.
It does not grant that contract whole-circuit layout or geometry authority.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(HERE.parent.parent / "figures"))
import block_aliases as aliases
import converter_symbol_cases as prior
import digital_symbols as digital

ORIGINAL_SIGNED = prior.signed
FOUR_BIAS = {
    "vdd": "supply", "vss": "ground", "inn": "negative", "inp": "positive",
    "out": "output", "vb1": "bias1", "vb2": "bias2", "vb3": "bias3", "vb4": "bias4",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def extended_signed(call):
    original = ORIGINAL_SIGNED(call)
    if original is not None:
        return original
    ports = call["ports"]
    if (call["family"] in prior.KNOWN and len(ports) == len(FOUR_BIAS)
            and set(ports) == FOUR_BIAS.keys() and len(call["bindings"]) == len(ports)):
        return {FOUR_BIAS[p]: n for p, n in zip(ports, call["bindings"])}
    return None


def select(cards, definitions, contract):
    # The imported reference selectors look up this function at call time.
    # Process-local substitution leaves their topology predicates unchanged.
    prior.signed = contract
    try:
        return {"regulator": prior.pass_divider(cards, definitions),
                "sampling": prior.sample_cell(cards, definitions)}
    finally:
        prior.signed = ORIGINAL_SIGNED


def controls(call):
    assert ORIGINAL_SIGNED(call) is None and extended_signed(call) is not None
    checks = ["old_rejects_and_complete_nine_port_extension_accepts"]
    for name, edit in (
        ("unknown_control", lambda c: c["ports"].__setitem__(-1, "vx")),
        ("duplicate_bias", lambda c: c["ports"].__setitem__(-1, "vb3")),
        ("unknown_family", lambda c: c.__setitem__("family", "opamp_extra")),
        ("missing_binding", lambda c: c["bindings"].pop()),
    ):
        changed = copy.deepcopy(call)
        edit(changed)
        assert extended_signed(changed) is None, name
        checks.append(name + "_declines")
    changed = copy.deepcopy(call)
    changed["ports"].reverse()
    changed["bindings"].reverse()
    assert extended_signed(changed) == extended_signed(call)
    return checks + ["formal_binding_permutation_preserves_roles"]


def collect():
    manifest = read(HERE / "manifest.json")
    audit = Path(manifest["prior_audit"])
    assert digest(audit / "all-images.json") == manifest["frozen_inventory_sha256"]
    inventory = read(audit / "all-images.json")
    assert {r["id"] for r in inventory} == {p.stem for p in (ROOT / "external/examples/analoggenie").glob("ag-*.cir")}
    earlier_path = HERE.parent / "converters_cases.json"
    earlier = read(earlier_path)
    old, extended = {"regulator": {}, "sampling": {}}, {"regulator": {}, "sampling": {}}
    hashes, witnesses = {}, {}
    for row in inventory:
        name, path = row["id"], Path(row["netlist"])
        assert digest(path) == row["netlist_sha256"]
        text = path.read_text()
        cards, definitions = aliases.read_cards(text), digital.declarations(text)
        hashes[name] = digest(path)
        for target, contract in ((old, ORIGINAL_SIGNED), (extended, extended_signed)):
            for kind, hit in select(cards, definitions, contract).items():
                if hit is not None:
                    target[kind][name] = hit
        if name in ("ag-789", "ag-2212"):
            witnesses[name] = {"dut_cards": cards, "calls": prior.calls(cards, definitions),
                               "artifact_sha256": {k: row[k + "_sha256"] for k in
                                                   ("netlist", "source_svg", "source_json", "native_svg")}}
    prior_regulators = {r["id"] for r in earlier["pass_divider"]}
    prior_sampling = {r["id"] for r in earlier["sampling_cells"]}
    assert old["regulator"].keys() == prior_regulators
    assert old["sampling"].keys() == prior_sampling | {"ag-789"}
    assert extended["regulator"].keys() == prior_regulators | {"ag-2212"}
    assert extended["sampling"] == old["sampling"]
    for kind in old:
        for name, row in old[kind].items():
            assert extended[kind][name] == row
    call = witnesses["ag-2212"]["calls"][0]
    assert dict(zip(call["ports"], call["bindings"])) == {
        "vdd": "vdd", "vss": "vss", "inn": "fb", "inp": "vref", "vb2": "vb2",
        "out": "net0", "vb1": "vb1", "vb3": "vb3", "vb4": "vb4"}
    return {"scope": __doc__, "manifest_sha256": digest(HERE / "manifest.json"),
            "script_sha256": digest(Path(__file__)), "dependencies": prior.dependencies(),
            "prior_evidence_sha256": digest(earlier_path), "deck_sha256": hashes,
            "prior_shard": {"regulator": sorted(prior_regulators), "sampling": sorted(prior_sampling)},
            "full_corpus_old": old, "full_corpus_four_bias_extension": extended,
            "added_regulator": ["ag-2212"], "added_sampling_outside_prior_shard": ["ag-789"],
            "controls": controls(call), "witnesses": witnesses}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    result = collect()
    if args.check:
        assert result == read(args.check), "Composition evidence changed"
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"prior_global": {k: len(v) for k, v in result["full_corpus_old"].items()},
                      "four_bias_extension": {k: len(v) for k, v in result["full_corpus_four_bias_extension"].items()},
                      "added_regulator": result["added_regulator"], "controls": result["controls"]}))


if __name__ == "__main__":
    main()
