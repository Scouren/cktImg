# Sixth groups study: caller relations need final geometry certificates

Twenty-three executions of the unchanged frozen binary materialize caller
symmetry, axis, group, fixed and weak requests on one literal resistor-loaded
pair and one literal crossed-gate quad. The study finds a concrete axis
discrepancy and a contradictory stack-order contract. It also confirms useful
positive controls: complete mirrored pair frames, correct rejected requests,
later-line precedence between incompatible valid symmetries, preserved exact
placement and a compatible weak stay. No production fix or local-axis
replacement is implemented.

The [fixture runner](sixth-groups-fixtures.py) and
[execution manifest](sixth-groups-fixtures.json) record exact deck/model/card
bindings, commands, stdout/stderr, native JSON/SVG and reports. The
[literal verifier](sixth-groups-proof.py) and
[proof result](sixth-groups-proof.json) preserve **five exact known RED names**
rather than treating successful research replay as a native fix. Eleven
individually rasterized native SVGs were actually viewed and independently
hash-bound in the proof. These are synthetic controls, not additions to the
completed real-image ledger or selector cohorts. No build, plugin import,
host netlisting or intermediate-stage dump ran.

## Literal circuits and independent oracles

The pair has equal M1/M2 input devices, equal R1/R2 loads and tail M5. All
four ordered MOS terminals and `nch w=2u l=1u` are retained; M5 has
`w=4u l=1u`. The quad has four equal MOS devices on two private source nets,
two equal loads and two equal tail current sources. Its gate assignments are
crossed between the two source pairs. Both decks declare `nch nmos level=1`.
Every original MOS D/G/S/B, both R/I terminals, model token, parameter token
and outer formal is recorded. Native JSON preserves the complete drawn pins
and the separate bulk binding. This is an identity check at the native
export boundary, not a host round trip.

The proof gives complete ordered-card automorphisms independent of native
placement. In the quad, M1↔M2, M3↔M4 and R1↔R2 exchange INP/INN and
OUTP/OUTN while I1, I2, s1, s2, VDD and VSS stay fixed. This supports the
requested symmetry without guessing it from a picture. Layout symmetry may
map matching external input/output nets; actual exported formal order and
bindings never change.

Final geometry is checked directly:

- For each mirror pair, origins have equal y and one common x-sum. Every
  corresponding actual terminal has that same x-sum and equal y. Checking
  origins alone misses a moved gate endpoint.
- An axis device's origin has `2*x == axis2`. An asymmetric axis glyph, such
  as the single tail MOS, need not have every off-axis gate terminal on the
  axis. This is different from comparing two complete mirror frames.
- A literal written top-to-bottom stack uses equal origin x and increasing
  origin y. This oracle tests the published rule; see its implementation
  conflict below.
- Strong/weak requests are checked against literal final origin and pose,
  independently of the report state. Request authority is taken from the
  appropriate existing admission path, not from raw text alone.

## A requested axis survives in the report but not in the drawing

`quad-relations` explicitly asks for three symmetric pairs and axes through
I1 and I2. The native report marks all five requests honoured. Actual final
origins are:

| Relation | Final x coordinates | Common x-sum / requested axis |
|---|---|---|
| M1 / M2 | 150 / 330 | 480, axis x=240 |
| M3 / M4 | 220 / 260 | 480, axis x=240 |
| R1 / R2 | 150 / 330 | 480, axis x=240 |
| I1 | 240 | On that axis |
| I2 | 340 | Off that axis by 100 drawing units |

Every actual D/G/S pair and both R terminals also pass the common-frame
mirror check. Both I2 terminals lie at x=340. This is not merely an unclear
glyph center. The same failure remains with explicit pair-group requests,
reversed raw card order, and **only `axis I2`**. No fixed-coordinate request
explains it. The exact RED names are `quad-relations`, `quad-groups`,
`quad-groups-reversed` and `quad-axis-alone`.

![Nested pairs retain a common axis but I2 moves to its right](figures/groups/sixth-quad-relations.png)

Both current and frozen `structure.3` say an axis request puts its named
device on the mirror axis. Both `checks.drawnAs` versions return no geometry
answer for symmetry/grouping. `report.evaluate` only downgrades an honoured
request when that check returns false, so absence of an answer can leave the
early admission verdict visible as success. Separately, `skeleton.lay`
explicitly clears a self-mate whose column moved off the axis. These are
code-reading facts and plausible locations to instrument; this study did
not execute an internal trace and does not assign the observed move to one
unmeasured phase.

## Stack order has conflicting current contracts

`pair-stack` asks `group stack M5 M1` and reports honoured. Final M5 is at
(80,170), below M1 at (80,90). The compatible reverse request
`group stack M1 M5` produces the same final device geometry and is also
honoured. Thus the two outputs cannot both satisfy a literal written
top-to-bottom order.

This is more specific than an unexplained placement bug. `structure.5`
promises the written order, and the structure member table describes stacks
top to bottom. But `skeleton.choose` explicitly describes stack hints as
permitting either order and accepts `stacked[u] == l OR stacked[l] == u`
while selecting an electrically oriented column link. The implementation
has a conflicting contract. The proof keeps `pair-stack` RED against the
published rule and records this conflict explicitly. A future change must
decide whether to enforce the stated order, decline an incompatible request,
or correct the public meaning; it must not silently invert devices merely
to make this research oracle green.

## Existing priorities and positive controls remain distinct

The unmodified pair and explicitly related pair have common axis x=200:
M1/M2 at x=170/230, R1/R2 at the same columns, and M5 at x=200. Complete
actual terminal frames pass. Electrical card reversal leaves named device
geometry unchanged.

The true conflict control uses `symmetric M1 M2` and `symmetric M1 M3` on
the quad. Each is independently available, but M1 cannot have both mates.
The later equal-strength line is honoured and the earlier is dropped with
`conflict`; reversing the two request lines reverses that decision. The
selected pair's final complete terminal mirror relation holds. This differs
from `axis M1` on the simple pair, which is individually asymmetric and is
dropped irrespective of line order.

Unknown `axis absent`, malformed one-member `group pair M1` and
electrically incompatible `symmetric M1 R1` get their distinct rejected or
dropped codes. `nogroup M1` defeats an overlapping pair request, and a
later quad group takes an overlapping member from an earlier group. The
study verifies those exact verdicts but does not invent a universal
proximity-based oracle for arbitrary group membership. `symmetry off`
drops the explicit symmetry/axis requests; incidental mirrored geometry is
not evidence that the disabled relation remains admitted.

A strong `at M1 -20 -20 r0` or `at M3 -20 -20 r0` puts the requested device
at (-800,-800), rotation zero, no mirror. That final pose correctly wins
over the earlier automatic arrangement. The affected symmetric relation
still says honoured even though its actual mirror geometry is false. These
two controls are classified separately from the no-fixed axis discrepancy:
preserve stronger exact placement and make any superseded relation's final
meaning explicit. `report.placedBy` currently handles row/above/order/face
versus exact placement, but has no symmetry/axis/group counterpart.

The compatible weak stay `at M1 -20 -20 r270` is honoured and keeps all pair
and load terminals mirrored, with M5 on their translated axis. Weak r0 is
dropped with `guarantee`; final M1 remains r270 and the full symmetry still
holds. Weak hints can affect the layout while their complete requested pose
fails, so neither “all weak hints are ignored” nor “any at text vetoes all
local work” describes these observations.

## Consequences for the implementation plan

This study directly affects current `structure.3–6`, `skeleton.7`,
`checks.drawnAs`, report finalization and the `pinned.1/4` priority boundary.
For the proposed plan it sharpens P17/P18/P24/P25/P27 and packages R/O/G/V.

1. Keep topology admission, selected member relations, actual placement and
   final request verdicts separate. A topologically valid automorphism does
   not prove all axis devices can retain their positions after column
   selection, compaction or exact caller placement.
2. Add direct final oracles for a bounded supported relation set before
   replacing the global mate table. Certify actual terminal frames for
   symmetric pairs and the selected common axis for named axis devices.
   Keep a separate stage oracle for group membership/order that is not
   observable from final proximity. Name unsupported relation checks.
3. Reconcile stack order and exact-placement precedence explicitly. Preserve
   current admitted stronger poses; do not let a new local owner silently
   override them. A final verdict must distinguish a superseded relation,
   unsupported geometry proof and an actual retained relation.
4. Keep two locally mirrored groups compatible with the caller's global
   axis. The executable mutation shifts both M3/M4 frames by +40: each local
   pair remains perfectly mirrored, but their axes now differ and the common
   global oracle rejects. This is a **future-only mutation**, not execution
   of a local-axis replacement. Existing quad I2 failure is separately named.
5. Check the final artifact after all coordinate-changing stages. A second
   mutation changes only M2's actual gate endpoint, leaving every origin
   unchanged; the complete-frame oracle rejects it. Derived summaries and
   report success cannot substitute for actual pins.
6. Introduce a bounded cold relation request/certificate table only if the
   concrete collectors need it. Borrow typed member handles, index witnesses
   and caller request IDs; bound rows by admitted relations and raw candidate
   references. One final validator owns relation dispositions, with precise
   conflicts back to caller requests. No runtime rule language is needed.

These are pre-existing frozen discrepancies and planning gates, not fixes
made by this research. The exact five RED names must remain visible until a
deliberate contract or implementation change resolves them; an unexpected
pass fails the current research replay rather than silently removing a case.

```sh
python3 -B docs/research/image-rules/round-2/sixth-groups-fixtures.py \
  --execute --check docs/research/image-rules/round-2/sixth-groups-fixtures.json \
  --output /tmp/cktimg-sixth-groups-fixtures.json
python3 -B docs/research/image-rules/round-2/sixth-groups-proof.py \
  --check docs/research/image-rules/round-2/sixth-groups-proof.json \
  --output /tmp/cktimg-sixth-groups-proof.json
```
