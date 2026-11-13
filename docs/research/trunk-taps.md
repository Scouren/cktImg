# Keeping straight gate lines around a blocked tap

Iteration15 extends the existing [trunk search](../../src/trunk.zig) with
bounded alternatives to a blocked midpoint junction. The three complete
source regressions now pass with compaction both off and on. Full-corpus
measurements retain 27 native straight-interval gains and four losses.
The losses remain named for separate investigation. These results do not
establish whole-drawing equivalence.

The [iteration14 interval study](trunk-rungs.md) recorded six named native
straight-line losses and checked every loss against actual source SVG leads
and conductor ink. Its [exact inventory](figures/trunk_rungs_cases.json)
retains source hashes and both native snapshots. Three losses have this
specific obstruction:

| Source gate pair | Actual source gate endpoints | Blocked midpoint in the compacted iteration14 drawing |
| --- | --- | --- |
| AG981, M1A.G–M3A.G, `VNBias2` | (490,380)–(530,380) | (600,370), on a `VNBias1` vertical wire |
| AG984, M5.G–M6.G, `net8` | (-100,60)–(100,60) | (180,150), on a `net0` vertical wire |
| AG986, M8.G–M9.G, `VC3` | (510,100)–(590,100) | (590,870), on a `net6` vertical wire |

Each source pair has a continuous horizontal conductor. Native detours
were electrically connected, but lost that local source relation. A wire
may cross another wire in their interiors. A branch endpoint on the other
wire would join the nets and must be rejected. Moving the branch junction
can preserve the straight gate line while leaving a legal proper crossing.
Neither device names nor source identifiers enter the production rule.

## Search policy and bounds

For each existing rung track, try the original midpoint first. Keep it if
its complete candidate passes the corner, obstacle and required-free-end
checks, even if moving the junction could shorten the wire. Otherwise score
both neighboring quarter-unit taps through those same checks. Every tap
must remain strictly inside its gate pair; a turn at a gate tip is invalid.
All alternatives use the existing length, bend and crossing costs.

The additional search is at most three complete rung candidates per track.
All paired rungs in one candidate share the same offset. This is a bounded
fallback, not an exhaustive search over independent junction positions.
It adds no retained state or allocation owner; existing temporary line
arrays hold each candidate. Failed candidates leave the canvas unchanged.

A displaced full-height candidate remains eligible to win, but does not
suppress the original half-height tracks. Only an accepted zero-offset
full-height candidate, with any required free end available, suppresses
those tracks. Cost pruning alone cannot reject a midpoint and trigger the
horizontal alternatives: rung candidates receive the full corner check.
Exact alternative-cost ties keep the fixed candidate order. Reflection is
proved for the asymmetric literal scene where the cheaper side reflects;
it is not claimed for every symmetric tie or quarter-grid rounding case.

## Regressions and corrections

The [literal Canvas tests](../../src/trunk_taps_test.zig) call the public
`trunk.draw` boundary. They cover a blocked midpoint with legal neighbors,
a legal midpoint that retains precedence over a shorter alternative, all
three taps blocked, foreign collinear ink, unchanged canvas on failure,
proper crossings without foreign endpoint contacts, pin permutations, and
reflection of an asymmetric scene. The initial blocked-midpoint and
reflection tests failed against iteration14; the blocked controls passed.

The [complete source tests](../../tests/trunk_taps.zig) preserve every DUT
card, model and subcircuit definition from AG981/984/986, plus the CLI's weak
boundary-role requests. AG981's target net is an output; the other two
are internal nets. Each test requires the actual named gate endpoints to
share a row, every integer point of their horizontal interval to have ink
of that net, physical endpoint connectivity, full electrical identity and
no shorts. All three failed before the implementation. Labels, other-net
ink and a connected U-shaped detour cannot satisfy the interval oracle.

The first alternative-tap version restored AG981 and AG984 in both modes,
and AG986 with compaction. AG986 without compaction exposed an interaction
with half-height tracks. Its gates remain at (300,1140) and (460,1140), and
iteration13 had a straight connection between them. A copied-source trace
showed every candidate on row 1180 blocked; displaced candidates on row 1300
fit with costs 970 and 910, then suppressed row 1170. A later level detour on
row 1170 cost 900 and won. Keeping the half-height rung candidates available
restored the source interval without widening the horizontal tap range.

An independent input-port regression also passed on iteration14 and failed
on the first alternative-tap version. A displaced full-height route fit,
but had no free end for its required input port; it incorrectly suppressed
a half-height route whose port fit. Acceptance now checks that required
free end before setting the suppression state. The literal test requires
the complete half-height wire and the actual connected input port.

All four named literal tests and all three complete source tests pass after
these corrections. The separate AG2376 label/thinning regression from the
iteration14 inventory remains disconnected in the final native measurement.

## Measured gains and remaining routing cases

The [companion audit](figures/trunk_taps.py) reuses the unchanged interval
and source verifier from the iteration14 study. Its new
[inventory](figures/trunk_taps_cases.json) preserves both complete corpus
results, exact native names and hashes, source certificates for every loss,
all three original recoveries, and the unchanged AG2376 case. It does not
replace the iteration14 inventory. The interval definition still requires
the same named card-pin pair to have a nonzero horizontal span in both
snapshots; the output bucket requires an actual output glyph in both.

| Corpus and bucket | Eligible intervals | Straight in 14 | Straight in 15 | Gains | Losses |
| --- | ---: | ---: | ---: | ---: | ---: |
| AG, output glyph in both | 2,557 | 116 | 117 | 1 | 0 |
| AG, other | 37,350 | 4,329 | 4,351 | 26 | 4 |
| AMS, output glyph in both | 404 | 52 | 52 | 0 | 0 |
| AMS, other | 1,940 | 246 | 246 | 0 | 0 |

These are native interval changes, not source-agreement rates. The wider
gained cohort has not received a complete source comparison. All four lost
pairs have unchanged native terminal coordinates and now occupy separate
labelled pieces:

| Drawing and pair | Actual source ink | Native change |
| --- | --- | --- |
| AG2309, `VX`, M11.G–M12.G | Continuous straight line | Connected to disconnected; three labels become eight. |
| AG2318, `VX`, M11.G–M12.G | Continuous straight line | Connected to disconnected; three labels become eight. |
| AG2319, `VX`, M11.G–M12.G | Continuous straight line | Connected to disconnected; three labels become eight. |
| AG2452, `VZ`, M34.G–M40.G | Continuous bent path between different source rows | Connected to disconnected; zero labels become six. |

The first three are new source straight-line regressions. AG2452 is a
broader source continuity regression even though its source gate pair is
not horizontal. None is hidden by the aggregate gains. The original
AG981/984/986 gate intervals are now straight and physically connected;
AG2376's earlier split remains a separate named limitation.

Eight bounded diagnostic runs distinguish the remaining failures from
an impossible gate corridor. An honoured explicit `*@ wire` request
restores each of the four target connections. Raising `cross_max` to 1000
also restores AG2452, but leaves the three `VX` failures unchanged. That
setting does not disable thinning of nets already cut between shelves:
their separate `cut_max` remains two.

Overlaying each unchanged baseline `VX` subgroup tree with the candidate's
other-net ink adds one proper crossing: AG2309 gains `VY` at (630,700),
AG2318 gains `net0` at (520,680), and AG2319 gains `VY` at (520,720).
Each overlay has three crossings instead of two. The inventory retains
both segments at every crossing and the two older crossings. This is an
explicit geometry overlay, not a trace of the thinning loop. Together with
the forced-wire probes and fixed cut budget, it supports a separate
grouping/thinning investigation. This change does not alter that policy.

The baseline native executable is
`ad704dbbbd5b03b66167a64fb1842a8ad3d83bbfb2f8fb78ccaae0c2d5b336d2`;
the candidate is
`0bb2a942947e5d2a602a2cb23695c56ef4da90f43e8521ff8b0a3976757738cb`.
The inventory includes exact probe command templates, source edits, the
high-cross-budget configuration, request verdicts, and drawing/report
hashes. The companion reruns all eight probes and the twelve existing
method checks per corpus. Reproduce and compare every frozen field with:

```sh
python3 -B docs/research/figures/trunk_taps.py external/examples /tmp/trunk-taps.json --ag-baseline /tmp/cktimg-human-rules/all-ag-iteration14-rungs --ag-candidate /tmp/cktimg-human-rules/all-ag-iteration15-corrected --ams-baseline /tmp/cktimg-human-rules/all-ams-iteration14-rungs --ams-candidate /tmp/cktimg-human-rules/all-ams-iteration15-corrected --binary /tmp/cktimg-human-rules/iteration15-corrected/cktimg-json --check
```

## Checkpoint validation

An independent replay reproduces every inventory field, including all eight
probes and the actual source leads and ink for the losses. All 2,936 corpus
drawings render with the same two source issues and no native findings.
The 112 changed drawings produce identical geometry and reports in serial
and four-job runs. All earlier named input, converter and reservoir cohorts
remain correct; whole-drawing crossing tradeoffs remain in the
[scorecard](corpus-scorecard.md).

Both test configurations pass (370 without LaTeX, 371 with it), along with
4,000 randomized circuits, formatting and style checks with the same five
legacy API findings. The exact 31 gallery SVGs are unchanged. Real Schemify
round trips retain 98 fixture comparisons and the same two capacity
refusals, 22 input comparisons, and 428 converter comparisons. Eight decks
covering the repaired and unresolved tap cases yield the same nine named
subcircuits through both the release and current hosts. Actual source and
final native views of AG986 and AG2309 confirm the local repair and the
remaining label and overall-placement differences.

The plugin is 562,718 bytes, SHA-256
`a37e5f03bf97f3940458aa1287ec774c7412eb1aa23c47e898714a1aacb98dec`.
Repeated native and plugin builds are byte-identical; the plugin remains
482 bytes below its strict 550 KiB cap.
