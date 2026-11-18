#!/usr/bin/env python3
"""Append fresh manual image observations with frozen artifact provenance.

Usage: record_reviews.py --shard 0 [--rules-read] [--complete] < observations.json
Input is a JSON array of {id, observation, ...}. Optional enlarged_views contain
path and observation; optional aliases map source/native to a viewed identical
representative. This records a reviewer's testimony, not an automated view.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = ROOT / ".objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2"
OWNERS = ["groups", "bodies", "ports"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text())


def sheets_for(audit, shard):
    if shard < 2:
        base = audit / f"shard-{shard}"
        manifest = base / "render-manifest.json"
        data = read(manifest)
        sheets = [(base / row["sheet"], row["png_sha256"], row["ids"]) for row in data["sheets"]]
    else:
        manifest = audit / "shard-2-images/index.json"
        data = read(manifest)
        sheets = [(ROOT / row["path"], row["sha256"], row["ids"]) for row in data["sheets"]]
    return manifest, {name: (path, sha) for path, sha, names in sheets for name in names}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shard", type=int, choices=range(3), required=True)
    parser.add_argument("--rules-read", action="store_true")
    parser.add_argument("--complete", action="store_true")
    parser.add_argument("--details", action="store_true", help="Append enlarged views to existing observations")
    args = parser.parse_args()
    manifest = read(RUN / "manifest.json")
    audit = Path(manifest["prior_audit"])
    assignment_path = audit / f"shard-{args.shard}.json"
    assert digest(assignment_path) == manifest["original_assignment_sha256"][str(args.shard)]
    assignment = {row["id"]: row for row in read(assignment_path)["images"]}
    render_path, sheets = sheets_for(audit, args.shard)
    output = RUN / OWNERS[args.shard] / "reviews.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    result = read(output) if output.exists() else {
        "scope": "Fresh second visual pass; notes are manual observations, not electrical certificates.",
        "round": 2, "shard": args.shard, "complete": False, "rulebooks_read": False,
        "assignment_sha256": digest(assignment_path), "renderer_sha256": digest(render_path),
        "round_manifest_sha256": digest(RUN / "manifest.json"), "reviews": {},
    }
    assert result["round_manifest_sha256"] == digest(RUN / "manifest.json")
    assert result["renderer_sha256"] == digest(render_path)
    if args.rules_read:
        for field in ("frozen_rulebook", "rule_delta", "current_rulebook"):
            assert digest(Path(manifest[field])) == manifest[field + "_sha256"]
        result["rulebooks_read"] = {
            "frozen_rulebook_sha256": manifest["frozen_rulebook_sha256"],
            "worktree_delta_sha256": manifest["rule_delta_sha256"],
            "scope": "Reviewer read all frozen headers plus every current-worktree header difference.",
        }
    incoming = json.load(sys.stdin)
    assert isinstance(incoming, list)
    for row in incoming:
        name = row["id"]
        if args.details:
            assert name in result["reviews"], (name, "Overview not yet recorded")
            assert row.get("enlarged_views"), "No enlarged views supplied"
            for zoom in row["enlarged_views"]:
                assert zoom["observation"].strip()
                zoom["sha256"] = digest(ROOT / zoom["path"])
            result["reviews"][name].setdefault("enlarged_views", []).extend(row["enlarged_views"])
            continue
        assert name in assignment and name not in result["reviews"], (name, "unassigned or duplicate")
        assert row["observation"].strip()
        original = assignment[name]
        path, sha = sheets[name]
        assert digest(path) == sha
        hashes = {}
        for field in ("source_svg", "native_svg", "source_json", "netlist"):
            hashes[field] = original[field + "_sha256"]
            assert digest(Path(original[field])) == hashes[field]
        for zoom in row.get("enlarged_views", []):
            assert zoom["observation"].strip()
            zoom["sha256"] = digest(ROOT / zoom["path"])
        result["reviews"][name] = {
            **row, "viewed": True, "artifact_sha256": hashes,
            "sheet": str(path.relative_to(ROOT)), "sheet_sha256": sha,
        }
    if args.complete:
        assert result["reviews"].keys() == assignment.keys(), "Incomplete exact name set"
        assert result["rulebooks_read"], "Rulebook reading not recorded"
        result["complete"] = True
    temporary = output.with_suffix(".tmp")
    temporary.write_text(json.dumps(result, indent=2) + "\n")
    temporary.replace(output)
    print(f"Recorded {len(result['reviews'])}/{len(assignment)} fresh observations; complete={result['complete']}")


if __name__ == "__main__":
    main()
