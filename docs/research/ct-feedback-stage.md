# CT-linked NPN feedback stage

The exact source census selects one nine-member stage: AG1149's XLp,
Q1/Q2 drivers, Q3/Q4 antiparallel diode clamps, C1/C2 reciprocal feedback
capacitors and LB1A/LB1B private bias inductors. This is one correlated source
figure. It does not establish a general oscillator or common-bias layout.

The [portable reader](figures/ct_feedback_stage.py) and
[frozen inventory](figures/ct_feedback_stage_cases.json) retain all 2,936
source deck/SVG/human-cache names and hashes, both corpus index hashes and
transitive local reader dependencies. The census validates 25,103 primitive
transistor path/control bindings and types. Selection uses complete declared
pin incidence, model polarity and CT port contracts, without source geometry
or figure/device identifiers.

The broader reciprocal-capacitor/private-bias pattern selects AG1114,
AG1131 and AG1149. Its bias branches differ: AG1114's resistors extend below
the base row, AG1131's resistors extend above it, and AG1149's inductors are
horizontal below the bases. AG1114's two common VREF terminals are physically
separated in both named-net and whole actual conductor ink. That negative
prevents treating a shared bias net as evidence for a local wire join.

The complete boundary requires two known NPN drivers with distinct emitters,
a common ground substrate, reciprocal capacitors, exactly three incidences
on each base and exactly two on the private shared bias net. Two known NPN
diode clamps oppose each other across the CT outer nets. Each outer net has
exactly six incidences. The CT tap is supply, the eight stage nets are distinct,
and matching complete CTs and raw competing devices count before eligibility
filters. The engine can use its existing Role projection; a flattened deck
does not recover a lost external DUT declaration.

Actual transformed SVG primitives independently supply all 23 visible leads.
The CT declaration and call bindings are checked against the frozen symbol
certificate; resistor/inductor paths use their actual SVG endpoints. Five
local trees contain respectively 6, 6, 3, 3 and 2 terminals on net10, net8,
net7, net6 and VB1. Every tree is continuous in verified conductor ink.
Cached strokes absent from actual ink are excluded and recorded.

The observed world frame has a horizontal CT with its tap above, upright NPN
drivers with emitters below, and inward bases on one row. The clamp leads lie
below the coil and above the horizontal feedback capacitors. The capacitor
row precedes the collectors; horizontal bias inductors lie below the bases.
The driver paths lie outside the winding ends. The two clamp paths occupy
different rows. Sixteen relative predicates and three world-frame predicates
record this geometry without copying absolute source distances.

The actual left-side columns also order Q1.B (x20), C1's inner endpoint
(x60), LB1A's control endpoint (x80), LB1A's common endpoint (x120), and
the winding midpoint (x180). The right side reverses this order at
x340, x300, x280 and x240. Thus the bias-control column lies inward of
the feedback-capacitor endpoint; it does not share the driver-base column.
The same predicate is false in both broader related stages, so it remains
part of the complete nine-member case. These coordinates come from the
same independently checked actual SVG leads, with unchanged input hashes.

Twenty-one named method checks challenge raw ambiguity, full incidences,
unknown models, aliases, substrate changes, declaration/card order and
literal geometry errors, including both bias columns moving outside the
feedback endpoints while their individual frames remain valid. Eight rigid
poses validate the relative oracle;
they do not erase the separately recorded source world orientation.

The implemented owner is cold and bounded to the nine devices. It retains
actual caller classes and all port bindings, honors admitted placement/group/
routing requests, and commits only after checking all member and foreign
body collisions. Unsupported mate/block contexts abstain. It uses actual
frames and existing spacing for one candidate above the foreign body band;
this is a placement choice, not an observed source distance. The bias control
lies one existing body gap inward of the feedback endpoint. The stage widens
enough to keep each complete bias body before the center track. Twelve x and
fifteen y inequalities preserve the initially true source relations through
the existing single compaction pass. No search or routing exception was added.

A read-only structural probe records no exact or private mates for any of
the nine members in either skeleton pass, no blocks, no reflection axis,
and one shelf. The owner can decline unsupported mate/group contexts
without deleting relationships. The initial prototype passes the earlier
world-frame and collision checks, but places the bias controls on the base
columns and leaves net6's source tree disconnected. The strengthened column
oracle exposes that geometric difference.

The resumed baseline fails five of ten public tests. The inward-column
correction passes all ten, including all five physical trees in both
compaction modes, declaration/card reversals, shifted caller frames,
collision checks, caller controls and topology exclusions. The private run
passes both tests, including the successful shifted-frame transaction,
whole-nine rollback after late failures, and allocation-failure sweep.
These results are recorded under
`.objective/human-schematic-equivalence/runs/iteration21-resume1/` in
`feedback-before-test-only.log`, `feedback-after-test-only.log` and
`feedback-after-private.log`; exact inputs and command hashes accompany them.

Two test-boundary corrections are explicit. Four-binding BJT cards retain
their substrate even when their class has only three visible terminals;
the oracle requires all 23 actual leads and checks the substrate separately.
After net6 was repaired, the VB1 check reached a generated input-port pin.
Generated rail/port devices have empty reference names and are not source
card incidences. The corrected incidence oracle compares every raw pin of
every named card, including hidden pins, and rejects literal added named
pins while allowing the same unnamed generated symbol. All 23 source
bindings, five physical target lists and ink-continuity assertions remain
unchanged. The corrected suite was rerun against both implementations and
still fails on the earlier geometry. Full-corpus physical parity remains a
separate pending gate.

```sh
python3 -B docs/research/figures/ct_feedback_stage.py \
  external/examples /tmp/ct-feedback-stage.json --check
```

The check compares every frozen field, including the named counterexample,
actual source proofs, exact selected list and input/dependency hashes.
