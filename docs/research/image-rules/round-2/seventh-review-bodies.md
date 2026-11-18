# Seventh cross-review: hidden body ink and actual no-connect marks

The sixth body study's substantive observations survive independent review.
All 18 exact case/mode pairs retain their complete ordered bindings and
expected no-connect coordinates. Six three-panel sheets and an enlarged
hidden-body pair were actually viewed again. An independent SVG check also
binds every native no-connect point to its two actual cross strokes, using
all external port circles to establish the renderer's coordinate mapping.
This is additional artifact evidence, not a plugin or host round trip.

The [probe](seventh-review-bodies-probe.py) and
[result](seventh-review-bodies-probe.json) preserve complete raw peer lists,
literal native cross coordinates, actual SVG cross centers, new view hashes
and three rejected attacks on the repaired hidden-lead checker. The exact
pre-repair checker is archived with hash
`8f7f8333089c43b800ed8a0fd524fc10f1a72c3a08cc28dced37b60cbe799dba`.

## Actual peer incidence and actual marks agree with the study

The independent reader reconstructs all M D/G/S/B and resistor occurrences
directly from the six literal decks; it does not import the peer's incidence
routine. It preserves the repeated source/body occurrences when S=B and
checks outer formal membership separately. The following outcomes remain
exact:

| Case | Electrical occurrences on b | Missing/hidden class behavior | Visible class behavior |
|---|---|---|---|
| Lone resistor | R1[0] only | Resistor cross | Resistor cross |
| One body peer | M1[3], R1[0] | Resistor cross despite a raw body peer | No cross; B route present |
| Two bodies only | M1[3], M2[3] | No cross; no B route | B route present |
| Two bodies and resistor | M1[3], M2[3], R1[0] | Resistor cross despite two raw body peers | No cross; B route present |
| Formal body and resistor | M1[3], R1[0], plus outer formal b | No cross; formal-to-resistor route | No cross |
| Source tie and resistor | M1[2], M1[3], R1[0] | No cross; actual visible source peer | No cross |

For example, hidden one-body-peer R1[0] is actually `[90,100]`, and its
native no-connect list is exactly `[[90,100]]`. The SVG contains both cross
diagonals centered at `[172.8,224]`. The independent coordinate mapping is
fixed by all three external terminal circles, rather than by choosing a
cross and assuming its location. Hidden two-bodies-plus-resistor instead
marks `[240,120]`; that exact coordinate is retained separately. The verifier
compares names and coordinates, not just seven marked outputs or a total
cross count. Every one of the 18 drawings gets an exact ink check, including
the cases that must contain no cross strokes.

The SVG checker deliberately supports the observed frozen renderer's one
untransformed visible stroke group and direct polyline grammar. Unexpected
transform, style, visibility, clipping or stroke authority is unsupported,
not silently ignored. It is a bounded artifact certificate, not a general
SVG visibility interpreter.

## Three attacks exposed a geometric proof gap

The original `actual_hidden_bridge` read raw `points` and truncated decimal
coordinates to tenths. Each of the following mutations of the **right B
lead only** still passed its coincident-tip and own-channel assertions:

1. Add `transform="translate(0 10)"`. Raw coordinates remain the same, but
   the actual stroke moves away from its certified attachment and other tip.
2. Add `visibility="hidden"`. The asserted visible bridge loses one lead.
3. Change endpoint x=188.8 to 188.89. Truncation made distinct exact tips
   appear equal. The original drawing had no such extra precision.

The review retained the old script and exact mutated SVG files before the
owner repaired it. The repaired checker explicitly rejects unsupported
authority and requires exact tenths. Independently replaying those same
three files now rejects all three, while the original frozen SVG still
passes. This is a research-verifier repair; the existing native hidden-body
drawing and the study's no-route observation were already correct.

## Hidden routing does not erase class drawing operations

The enlarged two-body hidden-class control shows an uninterrupted line
between the actual transistor channels. Both B contacts are native
`[100,40]`; the two class strokes meet at SVG `[188.8,128]`. There is no net-b
route record and no native label. Counting routes alone would incorrectly
describe this as an omitted visible relationship.

The two-bodies-plus-resistor hidden control makes the distinction sharper:
the two glyphs visibly connect to each other, while the resistor is separate
and carries a cross. One blanket visibility description for net b cannot
represent both facts. In the formal-body control, the external b marker
connects to the resistor but does not certify a physical MOS-body join in
missing/hidden modes. The source-tie control instead has a real visible
source connection and preserves B as a separate raw occurrence.

These are presentation observations. Native JSON retains every electrical
body binding. Source inspection confirms the plugin separately adds hidden
pin names, adds a visible-peer name when needed and suppresses crosses at
marked coordinates. That path was not executed here. No result in this
review establishes a lost electrical connection in Schemify, and no result
certifies that target naming works until the actual importer/netlister round
trip runs.

## Planning refinements

P07/P08/P10/P11/P25/P27 and package B should keep four inputs independent:
complete occurrence identity, class terminal geometry, class drawing ink,
and the selected routing/naming convention. A hidden terminal is an explicit
routing capability; its glyph operations may still be visible. A missing
terminal has no certified contact and cannot borrow a device origin as a
visible attachment. Native route counts and cross decisions are consequences
of the chosen population, not substitutes for the raw relation.

The first production gate should materialize these same six circuits across
missing, visible and caller-hidden terminal capabilities, then inspect
actual exported contacts and labels and run the target electrical round trip.
The same pin-level policy must cross both plugin class construction and
translation; family/index shortcuts cannot independently override it.
Before changing no-connect disposition, specify what happens to a visible
pin with hidden peers and unresolved naming. Merely deleting its cross would
not explain its missing representation. Keep the truly lone resistor as a
positive cross control.

For every own-lead certificate, unsupported renderer transforms or visibility
must decline, or be handled by an actual transform/visibility evaluator.
Exact coordinate claims must not introduce an unmentioned truncation
tolerance. This generalizes the three attacks without requiring a broad SVG
framework for a deliberately bounded frozen-renderer proof.

```sh
python3 -B docs/research/image-rules/round-2/seventh-review-bodies-probe.py \
  --check docs/research/image-rules/round-2/seventh-review-bodies-probe.json \
  --output /tmp/cktimg-seventh-review-bodies-probe.json
```

This replay reads saved artifacts and reproduces the archived checker attacks.
It runs neither a compiler nor a plugin and changes no production file.
