# Grounded-source input resistors

This is a proposed local placement habit. The
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

A future bounded request should keep the resistor at its driven gate's row,
put the upright source on its outer side, and reserve the grounded source
leg below. The topology selects the branch; settled geometry must still
check space and choose a gate anchor if several MOS gates share the net.
Its axis request must survive `crooked` under the same local certificate.
Explicit `upright`, `cell`, `at` and `face` requests keep priority according
to their existing owners. No global feedback, series-path or bias-resistor
orientation rule should be relaxed on this evidence.

Negative research checks rejected a gate/channel short, a supply or floating
voltage-source return, an extra capacitor pin or MOS gate on the private
junction, and substitution of a BJT for the driven MOS. Reversing resistor
and voltage-source pin order preserved membership. Shifting a cached
resistor endpoint by one source unit was rejected by the actual path-endpoint
audit. No production code, production tests or Zig build changed.

Reproduce source evidence and the existing AG native comparison:

```sh
python3 -B docs/research/figures/input_resistors.py external/examples/analoggenie /tmp/input-r-ag.json --native /tmp/cktimg-human-rules/all-ag-iteration8-before-sort
python3 -B docs/research/figures/input_resistors.py external/examples/amsnet /tmp/input-r-ams.json
```

The retained AMS native output is in
`/tmp/cktimg-passive-patterns/input-r-ams-native`; passing that directory as
`--native` reproduces the twelve-case native comparison without rebuilding.
