# Same-row trunk endpoints after thinning

AG2365 exposes an interaction between preserving a legitimate wire part and
routing another net. Its source M1.G and MSEN.G terminals are physically
connected by bent ink. They are at `(280,80)` and `(470,150)`; the path goes
through `(260,80)` and `(260,150)`. This is a continuity oracle, not a claim
that the human drew a straight or horizontal gate interval.

The [inventory](figures/thin_row_cases.json) retains actual transformed source
lead endpoints, SVG conductor support, and four byte-verified diagnostic
runs: committed16 and the initial17 candidate, each with and without
compaction. The [eleven named checks](figures/thin_row.py) compare exact case
names, actual routing rounds, complete crossing multisets, candidate vertices
and obstacle geometry. They do not infer decisions from final overlays.

With compaction, both versions first produce the same raw ink and pins.
VCTRL consists of four physical parts with crossing counts `[0,0,1,2]`.
Committed16 labels the entire net for its total of three crossings. That
removes the vertical segment `(270,380)–(270,720)` in the next round, allowing
the VEAOUT pair to connect. Initial17 correctly retains VCTRL under the
per-part cutoff, but the VEAOUT pair remains disconnected in every round.
Neither version disconnects this pair without compaction.

The actual rejected candidate supplies three horizontal chunks:

- `(250,570)–(270,570)` from M1.G;
- `(320,570)–(300,570)` from MSEN.G;
- `(270,570)–(300,570)` between the artificial approach points.

The first artificial endpoint lies on the VCTRL segment. The routing
contact checker rejects that endpoint, although a continuous horizontal
segment from `(250,570)` to `(320,570)` would make a proper crossing. Traced
`linesFit` decisions change from false to true only when the baseline later
round removes the obstacle. The original off-row candidates also fail; this
is not a missing first-choice preference.

The regression tests use the complete 33-card source DUT and its models:
[public continuity test](../../tests/trunk_row.zig) and
[literal route tests](../../src/trunk_row_test.zig). Both compaction settings
require electrical correctness and actual gate-pin continuity. The literal
case separately checks reflection, pin permutation, foreign endpoint and
collinear-overlap rejection, rollback, and valid outward-facing departures.
No label identity can satisfy physical continuity.

An unconditional change to same-row approaches was rejected after broader
validation found existing output-port and source-continuity regressions.
The narrower candidate preserves every original legal candidate and only
tries the continuous on-row approach after all original candidates fail in
`End.name` mode. Its validation is separate from this frozen causal trace;
the trace does not claim that every final routing decision remains unchanged.

## Provenance and replay

The original16 diagnostic sources match committed `450e4cd0`. The initial17
copy was an uncommitted candidate, not that commit and not the later routing
fix. [Its snapshot](figures/thin_row_snapshot.json) retains exact contents of
the only two changed source files, `src/thin.zig` and
`src/thin_parts_test.zig`, plus every source hash. The preparer reconstructs
the copy from16 plus those overrides and adds printing only in `sketch.zig`,
`thin.zig`, `wires.zig` and `trunk.zig`. Reconstructing both copies reproduced
every source and instrumented-file hash of the original captures.

Prepare copies and ask the serialized build owner to build them:

```sh
python3 -B docs/research/figures/thin_row_trace_prepare.py /tmp/thin-row16 --version 16
python3 -B docs/research/figures/thin_row_trace_prepare.py /tmp/thin-row-pre17 --version pre17
nix develop -c zig build --build-file /tmp/thin-row16/build.zig -Doptimize=ReleaseSafe --prefix /tmp/thin-row16/out
nix develop -c zig build --build-file /tmp/thin-row-pre17/build.zig -Doptimize=ReleaseSafe --prefix /tmp/thin-row-pre17/out
```

The runner consumes existing binaries; it never builds or replaces the
shipping executable. Each diagnostic must produce geometry and report bytes
identical to its supplied frozen shipping counterpart before any trace is
accepted. Replay the original captures with:

```sh
python3 -B docs/research/figures/thin_row.py /tmp/cktimg-thin-trace16-2365 /tmp/cktimg-thin-trace17-2365 /tmp/cktimg-human-rules/iteration16-aliases/cktimg-json /tmp/cktimg-human-rules/all-ag-iteration17-parts/cktimg-json /tmp/thin-row-replay /tmp/thin-row-replay.json --check
```

`--check` compares every retained evidence field, including binary and log
hashes. Different build paths or toolchains may change diagnostic binary
hashes; those require an explicit provenance update, never silently dropping
the comparison. The earlier [iteration15 study](thin-parts.md) and its
inventory remain unchanged by this companion.
