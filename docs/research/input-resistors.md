# Grounded-source input resistors

This source-backed local placement habit is implemented in iteration14. The
[selector and SVG auditor](figures/input_resistors.py) examines every paired
AG and AMS deck. The [exact inventory](figures/input_resistors_cases.json)
records selected names, actual primitive endpoints, per-case geometry,
source hashes, native hashes and the frozen executable hash. It also retains
broader source/resistor branches as named counterexamples.

The topology certificate is a resistor between two distinct nonrail nets.
Exactly that resistor and one independent voltage source have **any pins**
on one endpoint; the source's other terminal is ground. The resistor's other
endpoint drives the gate of at least one MOS with distinct D/G/S. Extra
capacitor pins, transistor gates or body pins on the source-side junction
invalidate its private-junction condition. A BJT base is deliberately not
substituted for a MOS gate. Values, device labels and input-net spellings do
not select the branch.

The actual source SVGs satisfy every measured condition in **22/22 cases**:

- The resistor is horizontal, on the same row as at least one driven MOS gate.
- Its center lies horizontally between the voltage source's signal pin and
  that gate.
- The voltage source is upright with ground below; its signal pin is at or
  below the resistor row.

The ten AG resistors are **1082:RS, 1083:RS, 1084:RS, 161:RS, 265:R1, 341:RS,
342:RS, 461:RS, 477:RS, 478:RS**. The twelve AMS resistors are **361:RS,
362:RS, 364:RS, 368:RS, 374:RS, 398:RS, 401:RS, 580:RS, 585:RS, 604:R1,
722:RS, 724:RS**. Each occurs in a different drawing. The modulo-five holdout
contains AG265:R1 and AMS580:RS/585:RS. Related textbook variants are
correlated, so this split is not independent statistical validation.

All **22 native resistors are upright**, and none is at a driven gate's row.
The comparison uses the frozen iteration8-before-sort executable. AG geometry
comes from the existing full-corpus run; the twelve AMS source decks were
run unchanged through that same executable. Source orientation and position
are independently checked against transformed SVG ink: the resistor's actual
zigzag `M/L` path endpoints, both voltage-source leads, and each selected
MOS's D/G/S leads. **160 source terminals** were checked. Cached rotation is
not the orientation oracle.

The [companion conductor audit](figures/input_resistor_legs.py) independently
checks the two local wire legs against actual transformed SVG conductor
paths. Its [exact inventory](figures/input_resistor_legs_cases.json) retains
all 22 named branches, every driven-gate candidate, both nets' verified
segments, actual lead endpoints, and source hashes. All **22/22** have a
continuous source-to-resistor leg and a completely horizontal resistor-to-gate
path. The same gate must satisfy the row, horizontal interval and physical
wire conditions together. No source cache segment lacking matching SVG ink
can supply connectivity; the measured cohort has none of those disagreements.

AG477 illustrates why that last condition matters. Its M1 gate supplies the
complete straight anchor. M2 is also on the resistor row, but uses a separate
labelled wire piece and has no continuous path from the resistor. M4 connects
through a vertical branch and lies on a different row. The audit retains
those two named failed anchors instead of requiring every electrically
driven gate to be the local geometric anchor. The inventory rechecks all
**160 actual symbol leads**; the original axis inventory remains unchanged.

## Boundary cases and owner

The broader private source/resistor branch selects 32 AG resistors and 38
AMS resistors. **AG637:R1**, which feeds a BJT base, is upright in the source.
Among AMS branches that fail the MOS-gate condition, **114:RS, 121:RS,
136:RO1, 328:R1, 405:RS, 649:R1 and 650:R1** are also upright. Thus “a resistor
next to a grounded voltage source lies flat” is not supported. The first
three AMS examples feed MOS source/model branches, not gates. Their source
SVG endpoints were audited alongside the selected cases. AMS32:R1 is also
excluded: its voltage-source junction itself has a MOS gate pin and is not
private.

There are two existing causes of the upright native result. Six of the ten
AG cases meet forms.6's series criterion (both resistor endpoints have two DC
path incidences); three also meet forms.7's opposed rail-distance criterion.
The other four, **AG1082/1083/1084:RS and AG341:RS**, start horizontal but are
eligible for forms.15's `crooked` pass because both endpoint nets meet upright
devices. In AMS, five meet the series criterion (three also meet the distance
criterion), while seven do not. The source branch attaches to a **side gate**
of the signal-stage transistor: DC path counts alone do not express this
horizontal input relationship. The criterion explanation in the script is
not used as the independent source-axis oracle.

The implementation keeps the resistor at one driven gate's
row, put the upright source on its outer side, and reserve the grounded source leg
below. The shared [topology query](../../src/input_resistors.zig) selects the
branch from existing graph incidences; it does not select a gate. The
placement owner checks space and chooses one settled anchor when several
MOS gates share the net. Forms and `crooked` use the same local certificate
to preserve the resistor's horizontal form.
Explicit `upright`, `cell`, `at` and `face` requests keep priority according
to their existing owners. No global feedback, series-path or bias-resistor
orientation rule should be relaxed on this evidence.

The older bridge owner first tries a tapped path row at the source
junction. Its gate-row helper also declines multiple gates and gate nets
with channel incidences, although AG477 and AG1082 demonstrate those valid
cases. A resistor-axis change alone therefore cannot establish the measured
branch. The new placement request runs after ordinary bridge placement and
caller relation admission, keeps the chosen MOS fixed, and reserves space
for both the resistor and the outer grounded source. Actual terminal
positions are the certificate; grid origins alone do not establish a custom symbol's gate
row. This study does not establish a universal choice between several valid
gate anchors or justify changing unrelated branch routing.

Negative research checks rejected a gate/channel short, a supply or floating
voltage-source return, an extra capacitor pin or MOS gate on the private
junction, and substitution of a BJT for the driven MOS. Reversing resistor
and voltage-source pin order preserved membership. Shifting a cached
resistor endpoint by one source unit was rejected by the actual path-endpoint
audit. Production query tests also cover these research exclusions,
including hidden third-device incidences that must still break
the private-junction condition.

The imported [input-resistor tests](../../tests/input_resistors.zig)
retain nine complete source DUTs and the BJT/MOS-source counterexamples.
They cover both compaction modes, semantic resistor/source pin reversal,
private-junction exclusions, caller forms/faces/cells/origins, and actual
wire connectivity. Fixtures retain the CLI's weak inline-source requests;
otherwise the API can exercise a detached driver island rather than the
source drawing's branch. A caller-frame regression shifts the R/V/MOS leads
away from their origins and doubles the principal resistor/source spans;
it applies the same actual-terminal and physical-wire oracle under both
compaction modes.

The AMS401 fixture also retains the CLI's weak output roles for A and B,
which come from its source declaration `.subckt dut VDD VSS A B`. Removing
that declaration without carrying its roles into the API fixture makes
those nets internal. Internal nets can try an upright trunk, whereas an
output needs a trunk with a port. The role-free extraction happened to
keep AMS401's resistor-to-gate segment straight and masked the native
output-net failure. The regression uses the declared source roles.

The custom MOS fixture supplies explicit body strokes inside its terminals.
Its initial implicit fallback box enclosed the side gate, making a wire
from that terminal cross the symbol body. That fixture defect was corrected
without changing any terminal coordinate or weakening the branch oracle.
The corrected test still goes RED against the iteration13 source, with
resistor endpoint rows differing by 80 units, and passes the focused
iteration14 run with compaction both off and on. Existing settled terminal
lines already provide the alignment; this case required no routing change.

Two regressions found during implementation have separate oracles. The
[card-permutation test](../../tests/input_order.zig) gives two private
grounded R/V branches the same MOS gate. Placement originally scanned raw
card order, allowing the first branch to occupy the only clear corridor
and change the named drawing when the cards were reversed. The public
test passed on iteration13 and failed on the first iteration14 version;
a direct placement test also changed the winning resistor under identical
named initial coordinates. [Placement](../../src/input_place.zig) now
consumes the existing canonical device order. Both focused regressions
pass without a new retained table.

AMS401 exposed a separate [trunk search](../../src/trunk.zig) defect after
its resistor and gate had been aligned. The two opposed pins shared row
100, while a feedback-capacitor pin below them needed a lower trunk. The
first candidate track used the opposed pins' own row and needed no separate
rung. That result incorrectly stopped the whole rung search, so the router
kept a U-shaped detour between those pins. Continuing to the remaining
bounded tracks allows a straight gate line with a branch to the lower
trunk. The complete AMS401 DUT and a literal three-pin canvas both went
RED before this change and pass the focused tests afterward. The canvas
oracle requires the entire horizontal interval between the opposed pins;
electrical connectivity alone cannot accept the detour. The generic router change and its wider effects are measured in the
[trunk-rung study](trunk-rungs.md), including four remaining source-backed
straight-wire regressions.

The restored rung search also exposed an incidental assumption in the
existing Sallen-Key crossing-budget test. Its first labelled net was A in
iteration13, with two labels; the new route keeps A fully wired. The
changed scaffolding then permits tighter compaction: B's capacitor-to-input
distance falls from 250 to 200 units, inside the existing 220-unit proximity
bound. All three B pins become one near group, for which the existing cut
fallback uses a label at every pin. Neither a rejected subgroup route nor
a change to thinning caused the result. The test now fixes literal near
and far device positions, selects B by name, retains the two-label
requirement, and additionally checks that the near pair shares physical
ink while the far capacitor joins only by name. It passes unchanged
production and fails an isolated mutation that replaces grouped wires
with individual pin labels. The production grouping rule is unchanged.

The preimplementation RED run failed the complete-branch and R/V-reversal
tests on unequal resistor endpoint rows. A separate RED run also failed the
custom-frame case on its actual resistor leads. The negative cases, explicit
requests and literal wire-oracle checks passed in those runs. The final native replay improves the complete branch certificate from
**0/22 to 22/22**, including actual source-leg continuity and a straight
resistor-to-gate wire at the same gate witness. All 22 source legs were
already continuous in iteration13; horizontal placement and the straight
gate approach are the gains. The [frozen native inventory](figures/input_branch_native_cases.json)
records exact names, terminal coordinates, conductor segments and hashes
for both versions. The complete branch now agrees with the measured source
pattern; that does not establish whole-drawing equivalence.

The [native companion](figures/input_branch_native.py) rechecks every source
row against the frozen actual-ink inventory before measuring native output.
Its frozen iteration13 baseline has all 22 resistors upright and no complete
branch certificates; iteration14 satisfies every selected relation in all 22. It retains each gate candidate separately, so a row
match at one gate cannot combine with a straight connection to another.

Reproduce source evidence and the existing AG native comparison:

```sh
python3 -B docs/research/figures/input_resistors.py external/examples/analoggenie /tmp/input-r-ag.json --native /tmp/cktimg-human-rules/all-ag-iteration8-before-sort
python3 -B docs/research/figures/input_resistors.py external/examples/amsnet /tmp/input-r-ams.json
```

The retained AMS native output is in
`/tmp/cktimg-passive-patterns/input-r-ams-native`; passing that directory as
`--native` reproduces the twelve-case native comparison without rebuilding.

Replay the companion's exact named evidence and literal/mutation checks:

```sh
python3 -B docs/research/figures/input_resistor_legs.py external/examples/analoggenie /tmp/input-r-legs-ag.json --check
python3 -B docs/research/figures/input_resistor_legs.py external/examples/amsnet /tmp/input-r-legs-ams.json --check
python3 -B docs/research/figures/input_resistor_legs_checks.py
```

Replay the complete native comparison without a Zig rebuild:

```sh
python3 -B docs/research/figures/input_branch_native.py external/examples/analoggenie /tmp/input-branch-ag.json --native iteration13=/tmp/cktimg-human-rules/all-ag-iteration13-final --native iteration14=/tmp/cktimg-human-rules/all-ag-iteration14-rungs
python3 -B docs/research/figures/input_branch_native.py external/examples/amsnet /tmp/input-branch-ams.json --native iteration13=/tmp/cktimg-human-rules/all-ams-iteration13-final --native iteration14=/tmp/cktimg-human-rules/all-ams-iteration14-rungs
```

The method checks distinguish touching horizontal pieces from gaps, wrong-net
ink, vertical detours, and different-gate witnesses. Source mutations also
remove real AG477 conductor strokes, forge a cached remote-gate connection,
and move a cached resistor endpoint; each loses the relevant certificate.

Validation passes 362 tests without LaTeX and 363 with it, 4,000 fuzz cases,
global formatting, and style checks with the same five legacy API findings.
The source auditor has 17 named method checks, and its native companion has
seven. All 22 decks round-trip through Schemify with the exact 22 DUT names.
The full fixture suite retains its exact 98 comparisons and two named
capacity refusals, and all 252 converter decks retain 428 exact subcircuits.
Eight selected decks also pass the current host with nine exact comparisons.
All earlier measured converter cohorts remain correct.

All 2,956 corpus drawings render with the same two source issues. The native
executable SHA-256 is
`ad704dbbbd5b03b66167a64fb1842a8ad3d83bbfb2f8fb78ccaae0c2d5b336d2`.
All 1,315 changed drawings reproduce identical JSON geometry and reports
in one-job and four-job runs. Wider changes, crossing regressions, source
gate-line losses and the remaining equivalence gap are retained in the
[scorecard](corpus-scorecard.md#fourteenth-measured-pass-private-input-branches-and-rung-search).
