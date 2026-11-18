#!/usr/bin/env python3
"""Independently verify fresh round-two observations and their frozen inputs.

Default requires complete exact coverage. --partial reports unfinished names;
it never changes a reviewer's completion flag. Recorded viewing is testimony,
not a mechanical certificate that a human or agent inspected the pixels.
"""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = ROOT / ".objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2"
OWNERS = ("groups", "bodies", "ports")


def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def by_id(rows):
    result = {row["id"]: row for row in rows}
    assert len(result) == len(rows), "Duplicate circuit name"
    return result


def prior_reader():
    spec = importlib.util.spec_from_file_location("prior_review", HERE.parent / "collect_reviews.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def collect(partial=False):
    manifest_path = RUN / "manifest.json"
    manifest = read(manifest_path)
    assert digest(manifest_path) == digest(HERE / "manifest.json")
    audit = Path(manifest["prior_audit"])
    assert digest(audit / "all-images.json") == manifest["frozen_inventory_sha256"]
    inventory = by_id(read(audit / "all-images.json"))
    for field in ("frozen_rulebook", "current_rulebook", "rule_delta"):
        assert digest(Path(manifest[field])) == manifest[field + "_sha256"]
    for name, sha in manifest["worktree_rule_source_hashes"].items():
        assert digest(ROOT / name) == sha, (name, "Current worktree changed during research")
    previous = prior_reader()
    reviews, provenance, pending = {}, {}, {}
    for shard, owner in enumerate(OWNERS):
        assignment_path = audit / f"shard-{shard}.json"
        assert digest(assignment_path) == manifest["original_assignment_sha256"][str(shard)]
        assignment = read(assignment_path)
        assigned = by_id(assignment["images"])
        for name, sha in assignment["rule_source_hashes"].items():
            assert digest(Path(assignment["snapshot"]) / name) == sha
        ledger_path = RUN / owner / "reviews.json"
        if not ledger_path.exists():
            assert partial, (owner, "No fresh review ledger")
            pending[owner] = sorted(assigned)
            continue
        ledger = read(ledger_path)
        assert ledger["round"] == 2 and ledger["shard"] == shard
        assert ledger["round_manifest_sha256"] == digest(manifest_path)
        assert ledger["assignment_sha256"] == digest(assignment_path)
        rules = ledger["rulebooks_read"]
        assert rules["frozen_rulebook_sha256"] == manifest["frozen_rulebook_sha256"]
        assert rules["worktree_delta_sha256"] == manifest["rule_delta_sha256"]
        if shard < 2:
            render_path = audit / f"shard-{shard}/render-manifest.json"
            render = read(render_path)
            sheets = {name: (render_path.parent / row["sheet"], row["png_sha256"])
                      for row in render["sheets"] for name in row["ids"]}
        else:
            render_path = audit / "shard-2-images/index.json"
            render = read(render_path)
            sheets = {name: (ROOT / row["path"], row["sha256"])
                      for row in render["sheets"] for name in row["ids"]}
        assert sheets.keys() == assigned.keys()
        assert ledger["renderer_sha256"] == digest(render_path)
        pixel = previous.pixel_evidence(audit, shard, assigned, render_path)
        for path, sha in set(sheets.values()):
            assert digest(path) == sha
        rows = ledger["reviews"]
        assert rows.keys() <= assigned.keys() and not rows.keys() & reviews.keys()
        if not partial or ledger["complete"]:
            assert ledger["complete"] is True and rows.keys() == assigned.keys()
        pending[owner] = sorted(assigned.keys() - rows.keys())
        for name, row in rows.items():
            assert row["id"] == name and row["viewed"] is True
            assert row["observation"].strip()
            original = assigned[name]
            assert original == inventory[name]
            path, sha = sheets[name]
            assert ROOT / row["sheet"] == path and row["sheet_sha256"] == sha
            for field in ("source_svg", "native_svg", "netlist", "source_json"):
                assert row["artifact_sha256"][field] == original[field + "_sha256"]
                assert digest(Path(original[field])) == row["artifact_sha256"][field]
            for zoom in row.get("enlarged_views", []):
                assert zoom["observation"].strip()
                assert digest(ROOT / zoom["path"]) == zoom["sha256"]
            reviews[name] = {**row, "reviewer": owner}
        provenance[owner] = {"ledger_sha256": digest(ledger_path), "pixel_evidence": pixel,
                             "complete": ledger["complete"], "observed": len(rows)}
    complete = reviews.keys() == inventory.keys() and all(
        owner in provenance and provenance[owner]["complete"] for owner in OWNERS)
    if not partial:
        assert complete
    return {"scope": "Fresh round-two visual testimony, verified artifact bindings and exact coverage; no electrical or equivalence verdict.",
            "complete": complete, "manifest_sha256": digest(manifest_path),
            "provenance": provenance, "pending": pending,
            "reviews": sorted(reviews.values(), key=lambda row: int(row["id"].split("-")[1]))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--partial", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = collect(args.partial)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"complete": result["complete"], "observed": len(result["reviews"]),
                      "pending": {k: len(v) for k, v in result["pending"].items()}}))


if __name__ == "__main__":
    main()
