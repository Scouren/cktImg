# Routing interactions after unsigned amplifier glyphs

The initial unsigned-amplifier candidate changes fifteen recognized blocks
from rectangles to triangles. Its local glyph and port contracts pass, but
the full source comparison finds **nine lost source-connected pin pairs**:
three VIN pairs in each of AG2415 and AG2428, and the three pairs among
AG2436's amplifier output and its two driven gates. Three additional VIN
splits in AG2434 agree with the actual source. This is recorded regression
evidence, not a source-preservation pass.

The [full connectivity companion](figures/reference_amplifiers_connectivity.py)
compares all stable pin pairs on changed drawings. This narrower
[trace inventory](figures/reference_routing_cases.json) preserves every raw
routing round for these four circuits, with and without compaction, under
both committed17 and initial18. All sixteen diagnostic geometry and report
outputs match their frozen executable counterparts byte for byte. Labels
with matching text never establish physical continuity.

## VIN proximity and the contradictory source control

With compaction, the actual `near` decisions are:

| Source |17 pin-box width + height|18 width + height|Limit|Actual source VIN|
|---|---:|---:|---:|---|
|AG2415|240|270|240|One continuous conductor|
|AG2428|230|260|240|One continuous conductor|
|AG2434|240|270|240|Separate named terminals|

The candidate rejects each net before attempting a trunk. Each circuit has
one routing round and no thinning transition. Without compaction, all three
VIN nets were already physically separated in17. Those older gaps remain
observations; the positive public regressions assert physical continuity
only with compaction and electrical correctness in both modes.

The [outer graph certificate](figures/reference_routing_source.py) compares
every ordered terminal of all eleven DUT cards in AG2415 and AG2434. Device
kinds, model parameters and the AEA declaration `VDD VSS VREF OUT` match.
The literal substitution is `net0→net1`, `net1→net4`, `net2→net0`,
`net3→net3`, `net4→net2`; other net names remain unchanged. VIN's three
native terminal coordinates are identical between these two circuits in
both versions. Their AEA **internal implementations differ**: the
certificate concerns the opaque instance graph and declared ports used by
the layout engine, not equivalence of the entire hierarchical netlists.
An outer-topology rule cannot infer both source partition choices from this
identical visible contract alone.

Actual source SVG leads, assigned conductor ink, junctions and label
locations are retained for all twelve changed pairs. AG2415 connects
M1.S `(110,20)`, MCHG.S `(230,20)` and MRES.S `(390,20)` on its `y=0` bus.
AG2434 has no actual conductor joining its corresponding source terminals;
the source-disconnected result also checks the complete SVG conductor set,
not just the cached net assignment.

## AG2436: two parts and an obstructed approach

In both compaction modes,17 keeps the entire amplifier-output net wired.
Initial18's first round also connects X1.OUT, M1.G and MSEN.G, but it crosses
`net0` twice, `VERR` once and `VOUT` once. The total of four changes `net4`
from `auto` to `cut`.

The second round contains **two named groups**, `{X1.OUT, M1.G}` and
`{MSEN.G}`. This is not the all-pins-in-one-part collapse. The first group's
trunk fails and each of its pins receives a label; the singleton receives
its own label. The two finite-cost upper/lower candidates both approach
M1.G through `x=260`, touching and then overlapping the already drawn
foreign `net0` vertical conductor. The continuous same-row fallback is
invalid because M1's gate faces right while X1 stands to its left. The
trace records the actual candidate vertices, obstacle segments and false
fit verdicts; it does not infer rejection merely from the final drawing.

The source has X1.OUT `(240,100)`, M1.G `(270,40)` and MSEN.G `(390,100)`
connected through `(260,40)–(260,100)`. Both source gates face left toward
the amplifier. The engine's actual decision report classifies M1/MSEN as a
two-device bank and turns their gates inward. Gate-facing research is a
separate proposed rule; this trace makes no production change.

## Regression status and replay

The unimported [complete-DUT tests](../../tests/reference_continuity.zig)
retain all source declarations/cards plus the command-line converter's weak
port roles. Each requires actual same-net wire ink joining its three
literal terminals, and electrical correctness with no shorts in both
compaction modes. All three failed at the physical continuity assertion
against initial18; their electrical checks passed. The exact failure names and
standalone command are mapped in [TESTING.md](../../TESTING.md#manual-reference-amplifier-continuity-gate);
its saved-log checker rejects unexpected passes and failures at other assertions.
They remain failing
regressions awaiting an owned repair, not weakened desired behavior.
The full connectivity companion's exact inventory keeps the nine named
source disagreements and three correct splits. Its `--require-preserved`
gate still rejects the nine disagreements; an unexpected change to the
recorded mismatch set fails its exact replay until reviewed.

Committed17 is `dea4c305537a1c3ca4b067c753b9632b8ec80040`. Initial18 is an
uncommitted snapshot, identified by exact source hashes. The
[snapshot](figures/reference_routing_snapshot.json) contains the sole source
override, `src/block_symbols.zig`. It never calls that dirty state the17
commit. The preparer reuses the frozen earlier printing statements and
adds only VIN proximity and targeted trunk-fit diagnostics. Repreparing
both copies reproduces every original source and instrumented-file hash.
No diagnostic code enters the shipping engine.

Prepare copies; the build owner alone runs the two build commands serially:

```sh
python3 -B docs/research/figures/reference_routing_prepare.py /tmp/cktimg-trace17-reference --version 17
python3 -B docs/research/figures/reference_routing_prepare.py /tmp/cktimg-trace18-reference --version 18
nix develop -c zig build --build-file /tmp/cktimg-trace17-reference/build.zig -Doptimize=ReleaseFast --prefix /tmp/cktimg-trace17-reference/out
nix develop -c zig build --build-file /tmp/cktimg-trace18-reference/build.zig -Doptimize=ReleaseFast --prefix /tmp/cktimg-trace18-reference/out
```

Replay the existing diagnostic binaries and every retained evidence field:

```sh
python3 -B docs/research/figures/reference_routing_run.py \
  /tmp/cktimg-trace17-reference /tmp/cktimg-trace18-reference \
  /tmp/cktimg-human-rules/all-ag-iteration17-bounded \
  /tmp/cktimg-human-rules/all-ag-iteration18-reference \
  /tmp/reference-routing-replay /tmp/reference-routing-replay.json --check
```

The runner revalidates all twelve source proofs, the exact native pin
bindings and losses, all sixteen geometry/report identities, independently
recomputed crossing multisets, the named causal checks and the outer graph
certificate. Binary or log hash changes need an explicit provenance review;
`--check` does not silently omit them. The historical `source_audit_sha256`
identifies the original full audit used to select these cases; current
source proof is independently replayed through the durable companion.
Earlier15/16/17 thinning studies and their inventories remain unchanged.
