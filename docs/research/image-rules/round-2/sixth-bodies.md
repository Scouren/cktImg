# Sixth body study: hidden peers, crosses and caller glyph ink

The frozen CLI preserves every ordered electrical terminal in these 18
executions. Its native cross decision nevertheless treats a resistor terminal
with one or two unwired body peers like a terminal with no electrical peer.
The plugin has a separate naming and cross-suppression path. Neither result
alone proves the target circuit is wrong.

There is also a contrary visual control: caller terminals marked `hidden`
can retain their actual glyph leads. Two such B leads meet and visibly bridge
the pair even with no B routing record. Thus zero route count does not prove
an omitted visible relationship.

This research changes no engine code and runs no compiler, C ABI or plugin.
The executable remains `bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560`.
[The proof](sixth-bodies-proof.py) writes six literal decks under three caller
classes and checks [the exact evidence](sixth-bodies-evidence.json). All six
three-column sheets were actually viewed; [the view ledger](sixth-bodies-views.json)
records their artifact hashes and the extra full-panel view.

## Literal expectations

Each deck has explicit D/G/S/B node literals and a separately written exact
incidence list for internal node `b`. The three classes differ only by adding
an actual fourth terminal/lead, then setting its `hidden` property. The latter
does not remove its drawing stroke. All formals are declared explicitly.

| Case | Raw occurrences on b, before formals | Missing B geometry | Visible B | Hidden B |
|---|---|---|---|---|
| Lone resistor terminal; M1 has B=S elsewhere | R1.1 | R cross | R cross | R cross |
| One body peer | M1.B, R1.1 | R cross | No cross | R cross |
| Two bodies only | M1.B, M2.B | No cross, no B route | B route | No cross, no B route |
| Two bodies and resistor | M1.B, M2.B, R1.1 | R cross | No cross | R cross |
| Formal body and resistor | M1.B, R1.1, plus outer formal b | No cross | No cross | No cross |
| Actual source tie and resistor | M1.S, M1.B, R1.1 | No cross | No cross | No cross |

The body/formal distinction matters. The formal case has a displayed port
and a wire to the resistor in all three modes, but that does not add a
visible MOS body connection in the missing/hidden modes. The source-tie case
has an actual visible source peer in all modes. Repeated M1.S/M1.B occurrences
remain separate in the raw relation.

![One body peer, three caller routing contracts](figures/bodies/sixth-one-body-peer.png)

The absent-contact and hidden-contact modes both draw a resistor cross for
the internal body peer. The latter additionally draws the caller's B lead.
The visible-contact mode wires B to the resistor. These are different
presentation states with identical complete M1 and R1 electrical bindings.

The checker compares the complete literal pin arrays and exact cross
coordinates, not cross counts. Twenty-seven output mutations exercise that
same checker: body replaced by source where unequal, or the resistor cross
added/removed contrary to the literal expectation. These test the evidence
checker, not a claim that the production engine rejects edited JSON.

## Hidden does not mean invisible

![Two body peers, including a caller glyph bridge with no route](figures/bodies/sixth-two-body-peers.png)

The hidden-class pair has both actual B contacts at native coordinate
`[100,40]`. Its SVG contains two literal lead segments, from `[152,128]` and
`[225.6,128]` to `[188.8,128]`. Both starts lie on their own drawn channel;
their outer tips coincide. The proof independently reads these actual SVG
primitives, verifies both channel attachments and their shared tip, and
rejects deletion of either actual lead. There are no B routes or native
labels in this control. The visible bridge is supplied by the glyphs.

Independent peer attacks found that the first verifier ignored a per-stroke
transform/visibility attribute and truncated a finer-than-tenths coordinate.
Those attacks did not alter the saved positive SVG, but they could make the
verifier certify changed ink. The repaired verifier explicitly declines
transform/style/visibility authority outside the frozen renderer subset,
requires the actual stroke group and direct primitive scope, and checks exact
Decimal tenths before conversion. All three attacks are retained and rejected.
This remains a literal primitive certificate, not a general SVG renderer.

This is a counterexample to equating any of the following:

- Complete electrical terminal occurrence.
- Terminal geometry in a class or JSON pin row.
- A visible glyph lead or actual contact.
- Participation in ordinary routing.
- A target-valid named connection.

The current `Terminal.hidden` comment is precise: it counts for paths but
gets no wire. Caller hidden routing must not silently erase glyph strokes;
source omission is a separate presentation convention. The caller classes
here are literal expression controls, not proposed new default MOS symbols.

## Current owner boundaries

`sketch.noConnects` counts `s.pins`, the drawn/wired pin population, and adds a
cross when that population has one device pin on a net. It does not count
all raw electrical members. The relevant `hiddenPins` and `noConnects`
function bodies are byte-identical between the frozen and current sources;
the complete `sketch.zig` files differ elsewhere. The evidence records both
whole-file hashes and the identical function hashes.

`sketch.hiddenPins` and `Placed.Builder.device` use a class contact when
available, but otherwise fall back to the device origin. That origin already
affects hidden-pin routing obstacles before export. It cannot be repurposed
as evidence of a visible body contact in a late renderer patch.

The JSON writer includes every class terminal in `pins` whether its `hidden`
property is true or false, without serializing that property. The same fourth
role/net/coordinate schema therefore occurs for both routed and unwired B.
When B geometry is absent it appears in `bulk`, with the correct fourth net.
Source inspection also shows the C ABI returns every placed raw pin, with an
empty terminal name and the origin fallback for a missing class terminal.
This study does not execute the ABI or prescribe a new ABI flag.

The current plugin makes its own MOS-index-3 hidden decision twice: class
construction and placed-record translation. Translation adds a name at each
hidden pin and, if necessary, at the first visible peer on that net. It then
suppresses a native cross at a marked coordinate. Thus the body-plus-resistor
literal has a code path for joining the two by name and suppressing the
resistor cross. The two-body-only literal has a path for naming both bodies.
These are code-backed expectations, not executed Schemify artifacts or
round-trip certificates. The exact source versions are in the evidence.

## Conditional implementation and validation plan

Keep raw incidence immutable. Resolve the selected class's actual contacts,
caller routing policy and target presentation together before pin escape,
obstacles and reservations. A missing default B contact is a capability gap;
it is not evidence that the caller requested hidden routing. An explicit
hidden caller terminal retains its routing authority and its class strokes.

Pass that per-occurrence result through both plugin boundaries; the
family/index shortcut must not independently undo the resolved choice.
Derive no-connect disposition from the complete relation and target naming
contract. A genuinely lone visible pin, a visible pin with hidden peers and
a named physical island are separate outcomes. Merely suppressing every
cross on degree-two raw nets would leave the missing representation
unexplained; changing the native rule alone would not certify plugin export.

The eventual target regression must run these literals through the actual
plugin and host, netlist them back and compare all ordered bindings. It must
also inspect actual marks and contacts. Include a conflicting-name mutation,
missing visible-peer label, omitted hidden-body label, caller-hidden class
and identical-glyph-but-visible class. Preserve a true lone-terminal cross.
Resolve all required labels/contacts before committing marks or reservations;
unsupported target naming stays an explicit unresolved representation.

This narrows current `sketch.16`, preserves `sketch.17`'s contact-safety
purpose, and clarifies `sketch.19`'s present shown-pin scope. `checks.1` still
checks shown connectivity; it does not certify all hidden electrical pins.
The associated [plan review](cross-review-bodies-to-plan.md) led to a shared
final-frame dependency in the root plan, with selected-variant capability
checked before downstream geometric consumers.

Replay:

```sh
python3 -B docs/research/image-rules/round-2/sixth-bodies-proof.py \
  .objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/sixth-bodies-replay.json \
  --check docs/research/image-rules/round-2/sixth-bodies-evidence.json
```

The command reruns all 18 frozen native controls and compares their complete
named evidence exactly. SVG rendering/viewing remains recorded separately.
