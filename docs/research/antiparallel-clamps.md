# Antiparallel diode-connected channel pairs

Four source circuits contain a unique pair of same-kind, same-polarity
transistors with reversed channel ends and each control tied to its own
drain or collector. Both ends are distinct nonrail nets. The exact pairs are
AG739 MD1/MD2, AG1048 M5/M6, AG1052 M6/M7 and AG1149 Q3/Q4. No AMS source
matches this predicate. These are four correlated circuit examples, not
eight independent observations.

All eight actual source symbols have horizontal channels. Each pair lies
on distinct rows, its controls face outward, and corresponding electrical
ends have matching left/right order. AG1149 deliberately staggers the
columns; the other three pairs share a channel midpoint column. Neither
equal columns, a fixed gap nor an absolute row is a universal source fact.

[The source audit](figures/antiparallel_clamps.py) reruns the existing
channel-bridge selector over both complete corpora and compares exact names.
It then reads the actual three-terminal SVG glyph for every device, verifies
card bindings, and proves sixteen named local conductor paths: each own
control short and both inter-device end connections. Two additional AG1149
paths, C2.2–Q1.B and Q3.C–XLp.N2, preserve the source-connected regression
that motivated this placement study. All eighteen paths use actual source
ink, with explicit junction dots where needed. Label text and cache-only
strokes cannot establish continuity. The
[inventory](figures/antiparallel_clamps_cases.json) retains all actual
terminals, conductor proofs, source hashes, the complete local Python import
closure and exact source-corpus names. Its 27 named checks include inward,
skewed, collapsed and reordered channels; staggered columns, reflection and
member permutation; wire gaps, wrong nets, labels and dotted crossings.

The engine selector counts all same-kind channels on the unordered end pair
before testing a candidate's polarity, control, visibility or form. A third
channel therefore blocks the rule even if its model is unknown or its
control is not shorted. Tied ends, rails, unknown polarity, mixed kinds,
opposite polarity, an independent control, and equal channel direction are
outside the certificate. Ordinary diode-connected transistors and arbitrary
cross-coupled pairs do not satisfy this selector.

The prototype has three owners. `forms.zig` requests flat channels;
`bridges.zig` reuses the existing two-member joint collision search for two
rows; `sketch.zig` turns supported actual frames so controls face outward
and matching nets occupy the same spatial end. A shared column is an engine
placement choice. The orientation step abstains for the whole pair when
either member has an admitted origin/relation override or an unsupported
actual terminal frame. Existing valid standalone gate/base `face left/right`
requests retain upright classification, preserving their earlier caller
contract. Invalid pins, malformed lines and unsupported directions cannot
suppress the inferred pair. Explicit form requests still run in the existing
relations owner.

The public tests retain complete literal source decks and the CLI's
weak port roles. Their geometry and physical-ink oracles are separate from
the selector; renamed and permuted literal fixtures exercise the same
relations. Private truth-table tests cover topology exclusions and malformed
caller frames. The current focused suite passes five of its seven named tests: the three
MOS cases pass their strict actual-anchor bounds in both compaction states,
and the local-wire test passes those three circuits before reaching AG1149.
The complete-source suite remains RED on AG1149's own Q3/Q4 collector/base
shorts and C2.2–Q1.B feed. The rename, caller-pose, standalone-face and
invalid-face controls pass. This is not a completed routing repair or a
claim of source-equivalent placement. The separate historical native
diagnostic records every relation and path without stopping at the first
failure; a fresh whole-corpus native audit is still required.

The complete placement-a diagnostic finds additional paths hidden by that
first test failure. AG1048 compact also disconnects M5.D–M6.S. AG1149 without
compaction disconnects Q3.C–Q3.B, Q3.C–Q4.E and Q3.C–XLp.N2 as well as the
base feed. All sixteen diagnostic states, including separately labelled
high-crossing-budget probes, match a printing-only trace's JSON, report and
SVG bytes exactly. The trace shows AG1048 VP1 and net4 cut and then collapse
to per-pin labels because each entire net is one proximity component.
AG1052 net2 and AG1149 net7 instead cut into singleton parts. These are
different failures; raising the global crossing budget is not a repair.

A narrower second-stage source relation is now certified for the three MOS
cases. Each clamp endpoint has exactly two other transistor channel-end
anchors: one PMOS drain and one NMOS drain. The two PMOS devices share a
source net, as do the two NMOS devices; all four net roles are distinct.
Remote gate and body uses do not become anchors. Every clamp channel tip
lies strictly between the actual PMOS/NMOS drain rows and inside their
actual drain-column span. AG1149 has only one external transistor channel
on each end and is explicitly excluded. The independent
[anchor audit](figures/antiparallel_anchors.py) retains the exact three names,
all actual glyphs and twelve continuous anchor paths in its
[inventory](figures/antiparallel_anchors_cases.json). Its named checks
include third unknown-model or source-ended competitors, missing anchors,
wrong polarity, unequal shared nets, gate/body exclusions, card permutation
and equality at a supposedly strict geometric boundary. This stronger
placement request has a trusted public RED oracle: the original lattice
places AG739's clamp channels outside the actual anchor-drain rows.

The second-stage owner is `clamp_anchors.zig`. Its focused actual-frame,
allocation-failure and caller-ownership tests pass.
All three existing native layouts already have room inside their anchor
rectangles. The owner therefore leaves the lattice and all anchors unchanged,
tries one midpoint position with body-derived row spacing, and commits both
positions only after actual-frame and whole-scene collision checks. An
unsupported or crowded frame keeps both original positions. Caller origins,
admitted relations, ownership, shelves and explicit net styles retain
precedence. Successful actual tip inequalities become requests to the same
generic compaction pass; there is no routing or crossing-budget exemption.
AG739 and AG1048 already place their diode references in inferred mirror
blocks. Those inferred gate groups do not veto the narrower, independently
certified channel-anchor placement. An honoured explicit caller mirror
still vetoes it, as do other block owners. A literal collection regression
retains the inferred block table and distinguishes these three cases.
AG1048 and AG1052 also have reciprocal inferred structural mates inside
the clamp pair. The original coupled-row owner already places those two
members together on different rows. The local owner accepts that closed
pair, or two unmated members; outside mates, self mates and an incomplete
mapping remain excluded. It neither changes mate tables nor overrides an
honoured caller symmetry. A separate literal automorphism regression
checks inferred admission and explicit caller precedence.

The [historical diagnostic audit](figures/antiparallel_diagnostics.py) and
[retained inventory](figures/antiparallel_diagnostics_cases.json) preserve
placement-a and placement-b separately. Each has sixteen exactly named
normal/high-budget and compact/uncompacted states. All JSON, report and SVG
bytes match their printing-only trace twins. The audit checks every frozen
source, instrumented source, binary and raw trace hash before interpreting
round decisions or guards. Placement-b directly records AG1048 and AG1052
rejected only by the former mate guard, with both handles independently
bound to the other clamp member's native device name. Neither dirty source
snapshot is mislabelled as a Git revision. Placement-a predates retained
generated inputs: its extra trace symbol input is recorded as trace-only,
with the sixteen exact drawings establishing the scope of equivalence.
These snapshots diagnose earlier failures; they do not stand in for final
validation of the later local-mate admission fix.

No circuit IDs or device names enter either engine predicate. The original
pair selector uses existing CSR/model/role rows without allocation. The
narrower placement owner holds six typed device handles per cold group and
sixteen coordinate-order slots, allocated before mutation and freed after
the drawing. It adds no retained flags or routing data. Actual frame and
collision tests, plus injected collection-allocation failures, independently
check its boundary. Caller constraints keep their existing admission and
final-placement owners. Source-family and frame changes remain local to the
selector and placement owner, respectively.

Replay the source certificate with:

```sh
python3 -B docs/research/figures/antiparallel_clamps.py external/examples /tmp/antiparallel-clamps.json --check
python3 -B docs/research/figures/antiparallel_anchors.py external/examples /tmp/antiparallel-anchors.json --check
```

Replay the retained trace archive (the two copied-source builds live below
`/tmp`; the original native, observation and raw trace files below
`/tmp/cktimg-human-rules`) with:

```sh
python3 -B docs/research/figures/antiparallel_diagnostics.py /tmp/cktimg-human-rules /tmp /tmp/antiparallel-diagnostics.json --check
```

This historical check requires those archived artifacts and fails when any
is absent or changed. It does not rebuild or run Zig.
