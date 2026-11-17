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
    result = subprocess.run(["zig", "build", "parent-census", "--", *files],
                            cwd=ROOT, check=True, stdout=subprocess.PIPE, text=True)
    actual = {}
    for line in result.stdout.splitlines():
        row = json.loads(line)
        name = row["id"]
        if name in actual:
            raise ValueError(f"duplicate evaluated case {name}")
        actual[name] = row
    if expected.keys() != actual.keys():
        raise ValueError(f"missing {sorted(expected.keys()-actual.keys())}, extra {sorted(actual.keys()-expected.keys())}")
    for name, row in expected.items():
        want, got = facts(row), facts(actual[name])
        if want.keys() != got.keys():
            raise ValueError(f"{name} expected fields {sorted(want)}, found {sorted(got)}")
        for field, value in want.items():
            if got.get(field) != value:
                raise ValueError(f"{name} {field}: expected {value}, found {got.get(field)}")
    print(f"{len(expected)} named cases matched; {len(oracle['witnesses'])} sets of structural facts checked")


if __name__ == "__main__":
    main()
