# Straight terminal intervals and trunk rungs

Iteration14 fixes an early exit in the bounded trunk search. A candidate
track on two opposed pins' own row needs no separate rung. That result used
to stop the entire rung search, even when a later track could preserve the
straight connection and reach another pin below it. The
[trunk owner](../../src/trunk.zig) now continues to the remaining tracks.
AMS401's complete input branch and a literal three-pin canvas went RED
before this change. Both pass afterward; the
[input-resistor study](input-resistors.md) records their source and test
provenance.

The broader [comparison script](figures/trunk_rungs.py) measures native
horizontal wire intervals between iteration13 and iteration14. Its
[frozen inventory](figures/trunk_rungs_cases.json) retains every named gain
and loss, the exact native drawing names and hashes, executable hashes,
and the actual source evidence for all six losses. This is a comparison of
the complete checkpoints, including placement changes. It does not identify
which routing implementation produced each interval.

## What the measurement means

An eligible pair has the same two named devices and card-pin indices in
both native snapshots, with unchanged terminal names and net bindings.
The two actual native terminals have a nonzero horizontal span in **both**
snapshots. Their coordinates may move. Generated port devices are excluded
as pair members. A straight connection requires the union of same-net
horizontal conductor segments to cover the entire interval. A detour,
matching labels, or an intervening wire on a different net cannot satisfy
that condition.

The output bucket requires an actual native output glyph (`opin`) on the
net in **both** snapshots. A semantic output role alone is insufficient,
and a glyph added or removed between snapshots does not put that net in
the output bucket. All other eligible pairs belong to the other bucket.
Several intervals can share a net or wire, so these counts are neither
independent circuits nor independent routing decisions.

| Corpus and bucket | Eligible intervals | Straight in 13 | Straight in 14 | Gains | Losses |
| --- | ---: | ---: | ---: | ---: | ---: |
| AG, output glyph in both | 2,552 | 67 | 113 | 46 | 0 |
| AMS, output glyph in both | 397 | 6 | 50 | 44 | 0 |
| AG, other | 37,333 | 3,089 | 4,322 | 1,239 | 6 |
| AMS, other | 1,920 | 220 | 236 | 16 | 0 |

Together these are **90 output-interval gains and no losses**, and **1,255
other-interval gains and six losses**. They are native geometry
observations, **not source-agreement rates**. Source geometry was audited
for every loss; the larger gained cohort has not received that source
comparison.

## The six losses against source ink

Each lost interval joins two MOS gates. The source audit first checks
both gate-net bindings against the SPICE deck and terminal cache, then
verifies all three transformed D/G/S leads of both transistors against the
SVG. This gives **36 verified actual source leads**. Source connectivity
uses only cached net segments that have matching transformed conductor
ink. No cache-only wire can close a gap. All six source nets have complete
agreement between their cached segments and the checked SVG conductor ink.

| Source drawing and named interval | Source ink | Iteration14 result | Interpretation |
| --- | --- | --- | --- |
| AG2274, `VN`, M5.G–M6.G | Separate labelled pieces | Separate labelled pieces | The lost native straight connection now matches the source separation. |
| AG2376, `net0`, M4.G–M5.G | Continuous straight gate line | Separate labelled pieces | Unresolved source regression. |
| AG2544, `VY`, M14.G–M21.G | Continuous path with bends | Continuous path with bends | The native straight loss does not lose a source straight-line relation. |
| AG981, `Vnbias2`, M1a.G–M3a.G | Continuous straight gate line | Continuous detour | Unresolved source regression. |
| AG984, `net8`, M5.G–M6.G | Continuous straight gate line | Continuous detour | Unresolved source regression. |
| AG986, `Vc3`, M8.G–M9.G | Continuous straight gate line | Continuous detour | Unresolved source regression. |

These are exact named cases, not six representative samples. The inventory
retains both native terminal coordinates, native physical connectivity and
labels, actual source leads and conductor segments, and the deck/cache/SVG
hashes for each case. A future loss involving a terminal kind outside this
MOS-gate verifier fails explicitly instead of silently leaving the study.

AG981, AG984 and AG986 expose a remaining limitation of the fixed middle
tap: its junction meets an existing wire of another net. A detour remains
electrically continuous but loses the source's straight gate line. Testing
a bounded set of alternative taps is a separate follow-up; iteration14
does not implement it.

AG2376 is a different case. Its two gate terminals retain the same
coordinates, but the final routing falls back to labels. A diagnostic route
with thinning disabled retains the straight gate line and introduces three
crossings on the full net. Preserving the local gate line while managing
those crossings needs a separate routing/partition study. The four source
regressions remain open at the iteration14 checkpoint; the aggregate gains
do not establish whole-drawing equivalence.

## Reproduction and oracle checks

The baseline executable SHA-256 is
`eaefa6ee157dd71f4ab2631b2a804dbf51180f24f15ab2334f6af8bef1f7f6cc`;
the candidate is
`ad704dbbbd5b03b66167a64fb1842a8ad3d83bbfb2f8fb78ccaae0c2d5b336d2`.
The script reads existing native JSON; it does not build or execute Zig.
When a directory contains the copied `cktimg-json` executable, its hash is
recorded as additional provenance. Replaying the frozen inventory includes
those copies.

```sh
python3 -B docs/research/figures/trunk_rungs.py external/examples/analoggenie /tmp/trunk-rungs-ag.json --baseline /tmp/cktimg-human-rules/all-ag-iteration13-final --candidate /tmp/cktimg-human-rules/all-ag-iteration14-rungs --check
python3 -B docs/research/figures/trunk_rungs.py external/examples/amsnet /tmp/trunk-rungs-ams.json --baseline /tmp/cktimg-human-rules/all-ams-iteration13-final --candidate /tmp/cktimg-human-rules/all-ams-iteration14-rungs --check
```

Both commands verify the exact source/native names and every frozen field,
including dependency hashes. Each also runs twelve literal or mutation
checks: touching intervals cover; wire ordering and direction do not
matter; labels cannot fill a gap; foreign-net ink cannot fill it; a
continuous detour is not straight; zero-span and off-row pairs are
ineligible; changed nets are ineligible; changed terminal identities are
rejected; an output glyph is required in both snapshots; a semantic output
role cannot substitute for it; and cache-only source wire cannot connect
the source terminals. Missing or extra native drawing names fail the
audit. All named results and source/native certificates reproduce the
initial diagnostic reports, with deterministic sorting of the records.
