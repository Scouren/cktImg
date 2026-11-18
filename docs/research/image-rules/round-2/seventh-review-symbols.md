# Seventh round: independent symbol-proof attacks and class controls

The sixth symbol study's PFD/DAC side observations and complete scalar-bus
bindings hold. Three actual-source mutations exposed a verifier gap: moved
or hidden text and a hidden own lead were still accepted. The peer repaired
the bounded source certificate, and my retained attack inputs now all reject
while the four original positives pass.

Five additional frozen native gate literals extend the known supply-contact
mechanism beyond the corpus's XOR/XNOR instances: OR and NOR have the same
small inward supply-lead overshoot. A supply-less XOR has no such failing
contact. One contrary PFD caller fixture preserves explicit opposite sides.
No production file, compiler, C ABI, plugin or host was executed or changed.

The independently replayable results are in
[seventh-review-symbols.py](seventh-review-symbols.py) and
[seventh-review-symbols.json](seventh-review-symbols.json). The pre-fix peer
script snapshot and four mutated SVG files remain under
`image-rule-round-2/bodies/seventh-symbols/`; their original outcomes and
hashes are in [seventh-review-symbols-before.json](seventh-review-symbols-before.json).
Fresh view hashes are in [seventh-review-symbols-views.json](seventh-review-symbols-views.json).

## Actual text and lead evidence must stay actual

Using the actual AG439 PFD object, I made these isolated mutations:

| Mutation | Before peer repair | After peer repair |
|---|---|---|
| QA text gets `transform="translate(-72 0)"`; original x/y stay unchanged | Accepted original right-side label anchor | Rejected unsupported transformed literal label |
| QA text gets `visibility="hidden"` | Accepted invisible QA witness | Rejected |
| First own pin line gets `visibility="hidden"` | Accepted absent visible lead | Rejected |
| First own pin line gets `transform="translate(0 10)"` | Rejected missing own endpoint | Still rejected |

![Original PFD and actual mutated ink](figures/bodies/seventh-symbol-source-attacks.png)

The moved QA visibly overlays the left A region; hidden QA disappears;
hidden lead leaves a real gap between its incoming wire and box. These
are actual SVG changes, not changes to the cached human terminal table.
The original visible four-port source is unchanged. The peer now rejects
unsupported visibility/opacity/clipping authority and transformed label
anchors for this literal scope, including inherited hidden groups and moved
tspans. It does not claim a general SVG/CSS text renderer.

I freshly viewed source/native pairs AG439, AG516, AG438, AG1076 and AG1146,
then the mutated source crops, all five native class controls and the
contrary caller result. This is a separate focused review, not another claim
to have re-viewed the complete corpus or the peer's complete 33-case set.

## The contact issue belongs to rounded-gate supply generation

![Four rounded gate families under the frozen CLI](figures/bodies/seventh-symbol-rounded-gates.png)

The corpus has two XOR instances and one XNOR instance with six failing
first-contact endpoints. It has zero OR and zero NOR instances. My separate
literal executions declare the same ordered VDD/VSS/A/B/Y contract for OR,
NOR, XOR and XNOR; all twenty electrical bindings survive, and each class's
VDD/VSS lead has the same inward overshoot. The three-pin XOR control retains
A/B/Y and all three leads end at their first own-outline contact.

An independent exact rational calculation uses the actual canonical outline
edge `(-15,-40) → (4,-34)`. Its intersection with `x=0` is `y=-670/19`,
whereas the generated supply lead ends at `y=-35`. The penetration is exactly
`5/19` canonical units. The lower contact is symmetric. This calculation
does not call the peer's ray/polygon intersection code, and the actual SVG
outline/lead extractor must reproduce the literal vertices first.

This is a small centerline termination overshoot, not a detached lead or an
electrical break. The line crosses the outline before ending slightly
inside. A claim of exact endpoint termination fails; a claim of no visible
gap is different. Neither pixel appearance nor this geometric result
establishes target electrical connectivity.

`block_symbols` uses the same rounded outline and rounded supply attachment
branch for all four families. A future repair therefore needs the shared
class branch, supply-free control, bubble/extra-input-curve controls and
supported pitch/pose ranges. The five literal executions prove only their
default pitch and poses. They do not enlarge the original corpus denominator
or authorize rejecting every member of these recognizable gate families.

The first version of this independent script failed a literal comparison
because the imported geometry used tuples while my literal used JSON lists.
Normalizing that boundary to JSON-native rows fixed the verifier's comparison;
it did not change any geometry or asserted contact result. The exact replay
now passes.

## Bus and caller boundaries

AG1146 declares exactly
`Von Vop B_3_ B_2_ B_1_ B_0_ Vcn Vcp`, with those eight scalar bindings on X2.
Its source has five actual symbol leads and the single displayed bus label
`B<3:0>`. The native result retains eight scalar terminal leads. I separately
asserted the exact ordered arrays and actual source label list, then deleted
one scalar JSON pin and swapped two scalar binding values. Both mutations
are rejected by the complete native binding checker. This does not prove
host bus-expression expansion or source bit ordering; no source lead is
invented for a scalar merely because the raw deck has it.

The proposed PFD/DAC policy remains a graphical side choice on a box. It
must not infer timing, truth table, polarity or electrical port direction.
In a real frozen CLI fixture I changed admitted PFD side directives to put
A on the right and QA on the left, keeping B left and QB right. The final
canonical contacts obey all four explicit sides and every outer X call
retains its full ordered binding. An automatic A/B-left and QA/QB-right
default must yield to this caller result. The peer's pure `box_sides` helper
is an observational candidate function, not a complete caller-admission
implementation.

The existing native/PININFO and plugin-direction difference is still a
boundary to test in the actual target. A native CLI run that ignores
PININFO comments cannot certify plugin behavior, and an intentional box
with role-looking names is not permission to substitute an amplifier glyph.

Replay the saved artifacts, or add `--execute` to regenerate the six native
controls with the unchanged frozen executable:

```sh
python3 -B docs/research/image-rules/round-2/seventh-review-symbols.py \
  .objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/seventh-symbols-replay.json \
  --require-fixed --check docs/research/image-rules/round-2/seventh-review-symbols.json
```
