#!/usr/bin/env bash
# Captures what the scripts read, from the gallery built at the repository
# root (`zig build`): the golden scores, the skeleton's cells, one dump per
# golden deck. The files committed here were captured at c03c677.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
gallery="$root/zig-out/bin/gallery"
"$gallery" --score > "$here/score.txt"
"$gallery" --cells > "$here/cells.txt"
for f in "$root"/tests/golden/*.cir; do "$gallery" --dump "$f" > "$here/dump_$(basename "$f" .cir).txt"; done
