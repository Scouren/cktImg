#!/usr/bin/env python3
"""Compare the public output of two cktimg-json binaries on the same source decks."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from hashlib import sha256
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory


def render(binary, deck, folder):
    folder.mkdir()
    report = folder / "report.json"
    svg = folder / "drawing.svg"
    result = subprocess.run(
        [binary, "--report", report, "--svg", svg, deck],
        check=True, stdout=subprocess.PIPE,
    )
    return result.stdout, svg.read_bytes(), json.loads(report.read_bytes())


def compare(deck, before, after):
    with TemporaryDirectory() as workspace:
        folder = Path(workspace)
        old, old_svg, old_report = render(before, deck, folder / "before")
        new, new_svg, new_report = render(after, deck, folder / "after")
    return {
        "deck": deck.name,
        "placement_changed": old != new,
        "svg_changed": old_svg != new_svg,
        "before": {"gates": old_report["gates"], "metrics": old_report["metrics"]},
        "after": {"gates": new_report["gates"], "metrics": new_report["metrics"]},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--decks", type=Path, default=Path("external/examples"),
                        help="directory of collections, each containing .cir files")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    decks = sorted(args.decks.glob("*/*.cir"))
    if not decks:
        parser.error(f"no decks under {args.decks}")
    before, after = args.before.resolve(), args.after.resolve()
    result = {
        "before_sha256": sha256(before.read_bytes()).hexdigest(),
        "after_sha256": sha256(after.read_bytes()).hexdigest(),
        "collections": {},
    }
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = pool.map(partial(compare, before=before, after=after), decks)
        for deck, row in zip(decks, results, strict=True):
            group = result["collections"].setdefault(deck.parent.name, {
                "checked": 0, "drawing_changes": [], "with_findings_before": {},
                "with_findings_after": {}, "report_only_changes": [],
            })
            group["checked"] += 1
            for side in ("before", "after"):
                if row[side]["gates"]:
                    group["with_findings_" + side][row["deck"]] = row[side]["gates"]
            if row["placement_changed"] or row["svg_changed"]:
                group["drawing_changes"].append(row)
            elif row["before"] != row["after"]:
                group["report_only_changes"].append(row)
    args.report.write_text(json.dumps(result, indent=2) + "\n")
    for name, group in result["collections"].items():
        print(f"{name}: {len(group['drawing_changes'])}/{group['checked']} changed drawings, "
              f"{len(group['with_findings_before'])} → {len(group['with_findings_after'])} "
              "drawings with gate findings")


if __name__ == "__main__":
    main()
