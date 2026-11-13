# Sampling-cell axes and conditional rows

This is proposed work. The native comparison uses the frozen executable and
outputs in `/tmp/cktimg-human-rules/all-ag-iteration8-before-sort`; no production
code or Zig build was changed for the study.

The [selector and SVG auditor](figures/sampling_cells.py) finds two local
sampling cells using the final SPICE subcircuit. Models determine polarity;
only the existing rail vocabulary depends on net names. Instance names,
clock spellings, symbol orientation and drawing coordinates do not select a
cell. Opaque blocks remain opaque.

The [exact case inventory](figures/sampling_cells_cases.json) records all
selected instance names, actual SVG lead endpoints, geometry conditions,
existing forms.19 membership, named native axis mismatches and the broader
excluded candidates. Its AG and AMS inventories are separate. The source
corpora contain many related variants; these are not independent samples.

## Four-switch floating capacitor

For a capacitor between distinct nonrail nets A and B:

- At each endpoint, exactly two DC paths occur: one NMOS to ground and one
  NMOS to another nonrail net. The two outer nets, A and B are all distinct.
- All four NMOS have distinct D/G/S and the same grounded body net.
- Their two distinct nonrail controls have no incident DC path. The signal
  switch on A shares its gate with the ground switch on B, and vice versa.

This selects **72 cells in 71 AG drawings**. All **144 signal MOS are
horizontal**, all **144 shunts are vertical**, and all **72 capacitors are
horizontal** in the actual SVGs. AMS selects none. Nineteen cells fall in
numeric-ID-modulo-five holdout; correlated variants cross this split.

The simple row is a conditional group habit. In **70/72 cells**, the two
signal switches and capacitor share one horizontal channel row, the capacitor
lies between the switches, both signal gates point upward, and the shunts
share a lower row with their gates outward. Each shunt stands between its
signal switch and the capacitor. The capacitor is between the signal-switch
centers in all 72 cells.

[AG794](../../external/examples/analoggenie/ag-794.svg) supplies the two named
row exceptions, `C3`/`C3B` with signal switches `M4/M6` and `M10/M12`. These
are portions of a larger differential switched-feedback network. Their axes
still agree, but the source folds each capacitor into an outer feedback row;
neighboring capacitors share the internal nets. The upper group reflects the
signal and ground directions. A local row request must compose with that
larger network. The current selector certifies the axes, not an unconditional
row, gate direction or grounding direction.

The frozen native output has **62/144** horizontal signal switches and
**35/72** horizontal capacitors. Shunts already have all 144 vertical axes.
It has 28/72 common signal/capacitor rows, 56/72 common shunt rows and 39/144
outward shunt gates. The exact **119 axis mismatches** are 82 signal MOS and
37 capacitors, named in the inventory.

## Two-switch grounded capacitor

For a capacitor from a nonrail net A to ground:

- Exactly two DC paths touch A, both NMOS to distinct nonrail outer nets.
- Both MOS have distinct D/G/S, the same grounded body, and distinct
  nonrail control nets with no incident DC path.

This selects **75 cells in 74 AG drawings**: all **150 signal MOS are
horizontal**, and all **75 capacitors are vertical**. It also selects
[AMS796](../../external/examples/amsnet/amsnet-796.svg), `C1` and `M1/M2`, with
the same three axes. Thirteen AG cells fall in modulo-five holdout; again,
related variants are correlated.

The simple layout has both signal channels on one row, the capacitor between
both switches and descending toward ground, and the two gates upward.
**73/75 AG cells** satisfy that full template. The two exceptions are
[AG514](../../external/examples/analoggenie/ag-514.svg), `CX` with `M1/M3` and
`CY` with `M2/M4`. Its four horizontal channels form a commutating mixer ring
with shared outer nets and crossed output wires. The source puts the upper
capacitor above its branch, the lower one below; the axes remain valid. This
ring should retain its larger group instead of being collapsed into two
independent series rows. AMS796 satisfies the simple template.

The native drawing has **132/150** horizontal signal MOS. All 75 capacitors
already stand upright. Exactly these nine AG circuits account for the
remaining 18 MOS mismatches, `M1/M2` in each: **2652, 2661, 2808, 3008, 3060,
3061, 3079, 3121, 3145**. Their later analog stages are expanded into
transistors. They have 66/75 shared signal rows and 46/75 capacitors between
the two switch centers.

The exact-DC-degree guard is substantive. Dropping it admits 24 more AG
cells. Twelve of their 48 signal MOS stand upright: `M1A/M2A` and `M1B/M2B`
in **AG1091**, `M3/M6` and `M4/M5` in **AG572**, and `M1/M3` and `M2/M4`
in **AG584**. Their capacitor nodes also touch gain/current branches,
inductive loads or resistive loads. Six of the broader candidates therefore
contradict the horizontal-channel rule. The remaining extra-incidence cases
are not automatically promoted merely because their source axes happen to
match.

## Existing owner and missing request

`forms.zig` forms.19 already recognizes a capacitor-bearing MOS when its DC
component reaches no rail, or when the capacitor endpoint has DC degree one
and its opposite endpoint drives a gate/base/named block input. Its global
315/319 AG habit is a different selector.

None of the **144 four-switch signal MOS** passes that existing predicate:
the ground shunts establish rail reachability and both capacitor endpoints
have DC degree two. They start upright in `forms.classify`; this is a missing
local classification case, not MOS uprighting by `crooked`. The 62 native
horizontal exceptions come from the later, globally admitted amplifier-block
placement in `opamp.place`, which supplies explicit placements to
`sketch.drawValid`.

For the two-switch cohort, **132/150** already pass forms.19. The remaining
18 are exactly the native mismatches. Their shared grounded-capacitor node
has degree two, and the expanded analog stage at the far endpoint establishes
a DC path to a rail. One switch's capacitor is also separated from the
stage by the other switch. The local two-switch certificate supplies evidence
that forms.19's single-MOS test cannot express.

Capacitor uprighting is a distinct downstream issue. Nonrail capacitors start
horizontal under forms.10. `forms.crooked` then stands up a two-ended passive
between upright devices when the first skeleton cannot give it straight leads.
The four-switch capacitor is eligible for this pass. Classifying the signal
switches correctly does not itself reserve their common row or prevent a
nearby ground shunt from triggering the same geometric heuristic.

A future change should first produce one bounded, topology-derived cell
request with its members, phase relations and path endpoints. `forms` can
consume its axis requests before the existing explicit `relations.forms`
overrides, so an explicit `upright` keeps priority. Placement should consume
conditional row/order requests from the same certificate, preserving a
larger feedback/ring group's ownership and shelf constraints. Routing should
then verify continuous row wires and separate grounded branches. Neither
axis agreement alone nor a blanket `crooked` exemption proves the human
layout. No diagonal routing is needed for the simple cells.

## Capacitor-only probe, retained as a failed partial experiment

The public `bridge` request rejects a transistor in `relations.forms`; only
`upright` is supported there for MOS. Forcing a horizontal MOS with `at`
would also pin its origin and change placement admission. No such experiment
was presented as a pure classification change.

The [probe script](figures/sampling_cells_probe.py) instead requests only the
37 mismatching capacitor axes in **36 circuits** with `bridge`. Before each
run it replays the original source through the frozen executable and requires
both native geometry and report to match the frozen files byte-for-byte.
The [probe record](figures/sampling_cells_probes.json) preserves the exact
hints, executable/deck/output hashes, all verdicts, before/after metrics and
source/group geometry.

All **36 requests are honoured** and all **37 capacitor axes become
horizontal**. The 74 selected signal MOS remain upright. Crossings worsen
**97 → 104**, bends **631 → 632**, and shared shunt rows fall **25 → 0**.
Capacitors between signal-switch centers fall **35 → 33**. Shunts inside the
local switch/capacitor intervals improve **0 → 33**, but no cell gains the
source's common signal/capacitor row. This rejects a capacitor-only repair;
it does not evaluate the unimplemented grouped signal-switch rule.

## Oracle and reproducibility

The actual transformed SVG `line`/`polyline` endpoints verify **1,608 AG**
selected terminals and **8 AMS** terminals before geometry is measured. The
source glyph's origin associates an instance; cached rotation never decides
an axis. Exact source endpoint records remain in the inventory. The larger
excluded candidates are audited by the same code.

Negative checks rejected a copied capacitor terminal shifted by one source
unit, a phase assignment made identical to the other phase, a signal endpoint
changed to a rail, an additional DC path on a capacitor endpoint, and a
resistor loading a phase gate. Reversing all studied capacitor terminals and
MOS channel terminal order retained the same four-switch membership. These
checks exercised the research selector and SVG oracle; no production test or
build was run.

Reproduce the study and the frozen native experiment:

```sh
python3 -B docs/research/figures/sampling_cells.py external/examples/analoggenie /tmp/sampling-ag.json --native /tmp/cktimg-human-rules/all-ag-iteration8-before-sort
python3 -B docs/research/figures/sampling_cells.py external/examples/amsnet /tmp/sampling-ams.json
python3 -B docs/research/figures/sampling_cells_probe.py /tmp/sampling-ag.json external/examples/analoggenie /tmp/cktimg-human-rules/all-ag-iteration8-before-sort /tmp/sampling-cap-probes /tmp/sampling-cap-probes.json
```

The paired corpus hashes in this script hash each sorted human cache followed
by its converted deck, with length-delimited filenames and bytes. Source SVG
hashes are also recorded for every audited circuit. This digest ordering is
explicitly different from earlier studies' paired-corpus hashing order.

A separate broad capacitor idea was rejected during discovery: an off-rail
capacitor between a transistor's distinct gate/base and drain/collector selects
241 AG capacitors, with cached axes 135 horizontal and 106 vertical, and
45 AMS capacitors, with 33 horizontal and 12 vertical. Direct inspection of
AG2451–2454 shows `CM2` changing axis as labels and stage groups change. That
broad predicate is not sufficient to infer a universal Miller-capacitor axis.
Its full corpus count is cached-geometry discovery, not the actual SVG audit
claimed above for sampling cells.
