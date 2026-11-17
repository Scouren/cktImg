"""Check all AnalogGenie parent dispositions and members against the frozen source census.

Run from the checkout with `nix develop -c python3 tests/parent_corpus.py`.
For inspection, `zig build parent-census -- external/examples/analoggenie/ag-1080.cir`
writes the named devices, raw gate interfaces, reflection and dependency rows.

Oracle: independent ninth-study census 91ac6a834e061d4cdc7a501c44c928f31cd3cfcbc0621715c02a4bdee3155233.
The fixture retains every disposition, reason and membership. It includes the unique
net-moving reflection whenever complete enumeration found exactly one.
"""
import json
from pathlib import Path
import subprocess
import tempfile

from parent_output_routes import EXPECTED

ROOT = Path(__file__).resolve().parents[1]


def facts(row):
    # A local component handle stands for its members, independent of their order.
    channels = [tuple(sorted(members)) for members in row.get("channel_components", ())]
    parents = [tuple(sorted(members)) for members in row.get("proposed_groups", ())]
    result = {"disposition": row["disposition"], "reasons": sorted(row["reasons"])}
    if "channel_components" in row:
        result["channels"] = sorted(channels)
    if "proposed_groups" in row:
        result["parents"] = sorted(parents)
    if "complete_gate_interfaces" in row:
        result["gates"] = sorted(
            (pin["device"], pin["gate"], pin["kind"], channels[pin["consumer"]],
             None if pin["producer"] is None else channels[pin["producer"]])
            for pin in row["complete_gate_interfaces"]
        )
    if "group_dependencies" in row:
        result["dependencies"] = sorted(
            (parents[int(owner)], sorted(parents[int(dst)] for dst in targets))
            for owner, targets in row["group_dependencies"].items()
        )
    if "unique_reflection" in row:
        result["reflection"] = row["unique_reflection"]
    return result


def output_pairs(row):
    """Keep sibling grouping and the distinct PMOS, NMOS and remote gate roles."""
    return sorted(tuple(sorted((out["net"], out["pmos"], out["nmos"], out["gate"])
                               for out in pair)) for pair in row["output_pairs"])


def reference_pairs(name):
    pins = EXPECTED.get(name, {})
    siblings = (("fn1", "fp1"), ("rn", "rp"), ("net1", "net3"))
    return sorted(tuple((net, *pins[net]) for net in nets) for nets in siblings if nets[0] in pins)


# The eleventh source study changes one property of the complete AG1080 deck.
# Each entry gives the affected card field(s), or a complete SPICE directive.
# An unrelated RN/RP pair survives exactly three mutations.
MUTATIONS = {
    "extra_gate_consumers": ([("m1", 2, "fn1"), ("m2", 2, "fp1")], None, "raw_multigroup_candidate", None),
    "export_outputs": ([], "formals", "raw_multigroup_candidate", None),
    "nonrail_source": ([("m15", 3, "net0"), ("m16", 3, "net0")], None, "raw_multigroup_candidate", None),
    "extra_body_consumer": ([("m1", 4, "fn1")], None, "decline_input_boundary", "nonrail_body_or_source_body_tie"),
    "extra_passive": ([], "rx fn1 fp1 1k", "decline_input_boundary", "non_mos_attachment_or_component"),
    "wrong_model_identity": ([("m16", 5, "different")], ".model different pmos", "decline_involution", "no_nontrivial_involution"),
    "unknown_control": ([("m16", 2, "new_private_control")], None, "decline_control_boundary", "internal_gate_without_channel_owner"),
}


def write_mutations(original, directory):
    for name, (changes, extra, _, _) in MUTATIONS.items():
        lines = [line.split() for line in original.read_text().splitlines()]
        for who, index, value in changes:
            card, = (line for line in lines if line and line[0].lower() == who)
            card[index] = value
        if extra == "formals":
            header, = (line for line in lines if line[:1] == [".subckt"])
            header.extend(("fn1", "fp1"))
        elif extra:
            position = next(i for i, line in enumerate(lines) if line[:1] == [".ends"])
            lines.insert(position if extra[0] != "." else 1, extra.split())
        path = directory / (name + ".cir")
        path.write_text("\n".join(" ".join(line) for line in lines) + "\n")
        yield path


def main():
    oracle = json.loads((ROOT / "tests/fixtures/parent-census.json").read_text())
    expected = {}
    for group in oracle["sets"]:
        for number in group["ag_ids"]:
            name = f"ag-{number}"
            if name in expected:
                raise ValueError(f"duplicate expected case {name}")
            expected[name] = {"disposition": group["disposition"], "reasons": group["reasons"],
                              **oracle["witnesses"].get(name, {})}
    files = sorted((ROOT / "external/examples/analoggenie").glob("ag-*.cir"))
    with tempfile.TemporaryDirectory() as name:
        mutants = list(write_mutations(files[0].parent / "ag-1080.cir", Path(name)))
        result = subprocess.run(["zig", "build", "parent-census", "--", *files, *mutants],
                                cwd=ROOT, check=True, stdout=subprocess.PIPE, text=True)
    actual = {}
    for line in result.stdout.splitlines():
        row = json.loads(line)
        name = row["id"]
        if name in actual:
            raise ValueError(f"duplicate evaluated case {name}")
        actual[name] = row
    gate = EXPECTED["ag-1080"]
    for name, (_, _, disposition, reason) in MUTATIONS.items():
        row = actual.pop(name)
        surviving = [tuple((n, *gate[n]) for n in ("rn", "rp"))] if disposition == "raw_multigroup_candidate" else []
        if (row["disposition"], row["reasons"], output_pairs(row)) != (disposition, [reason] if reason else [], surviving):
            raise ValueError(f"{name} has unexpected parents, decline reason, or surviving output pairs")
    if expected.keys() != actual.keys():
        raise ValueError(f"missing {sorted(expected.keys()-actual.keys())}, extra {sorted(actual.keys()-expected.keys())}")
    for name, row in expected.items():
        if output_pairs(actual[name]) != reference_pairs(name):
            raise ValueError(f"{name} expected {reference_pairs(name)}, found {output_pairs(actual[name])}")
        want, got = facts(row), facts(actual[name])
        if want.keys() != got.keys():
            raise ValueError(f"{name} expected fields {sorted(want)}, found {sorted(got)}")
        for field, value in want.items():
            if got.get(field) != value:
                raise ValueError(f"{name} {field}: expected {value}, found {got.get(field)}")
    print(f"{len(expected)} named cases matched; {len(oracle['witnesses'])} sets of structural facts and {len(MUTATIONS)} source mutations checked")


if __name__ == "__main__":
    main()
