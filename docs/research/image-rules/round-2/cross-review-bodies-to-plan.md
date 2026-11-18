# Body review of the implementation packages and proposed rules

This independent review read the complete `implementation-packages.md` and
`proposed-human-rules.md`, the completed second through fifth body studies,
and the current native and plugin code. It changes neither proposal nor
production code. File hashes in `sixth-bodies-evidence.json` identify the
reviewed code; root documents can change after this review.

## Required dependency correction

The package diagram has only `R → B → V` for body presentation. That permits
geometry consumers to run without a resolved body contact/presentation even
though package B's prose and P25 correctly require the opposite. The diagram
should express the same dependency as the prose.

Body presentation needs the admitted caller policy, selected class contact
capability and target transport. It must reach the final terminal frame before
pin escape, reservations, group/interface extents and local crossover stubs
are consumed. Class selection for signed-order policy and for body capability
must have one compatible final result. Raw ownership collection can run first;
committing a geometric group arrangement cannot assume its interface frame is
final before body presentation is resolved. There need not be a global order
between unrelated collectors.

This is already a concrete code dependency: `sketch.hiddenPins` constructs
maze exclusion marks from every unwired raw pin, with a device-origin fallback
when a class lacks that terminal. `Placed.Builder.device` repeats the origin
fallback. A late SVG body repair would leave the earlier obstacle/escape and
reservation decisions based on another frame. The fourth study's source
channel-polygon landing is evidence about a source drawing, not permission to
reuse a generated class origin as a target contact.

## Authority and transport distinctions to retain

P08–P10 and package B correctly preserve caller authority, all ordered pins,
and the distinction between source omission and electrical identity. Make the
following implementation distinction explicit: a default three-terminal class
that lacks B geometry is a missing capability; an admitted caller class with
an explicit hidden fourth terminal is an intentional routing-participation
contract. Its actual glyph lead can remain drawn: `Terminal.hidden` means
no ordinary wire, not erased glyph ink, as the sixth controls demonstrate.
Neither the 22 source bridges nor the proposed default policy authorizes
overriding that caller contract. Conversely, absent default geometry alone
does not prove that a caller asked to hide the body.

`tools/schemify/layout.zig` calls the same family/index `hiddenPin` predicate
when building class terminals and again when translating placed pins. A new
per-occurrence policy that changes only the native class will therefore not
automatically survive plugin translation. Its selected geometry and
presentation must reach `Parts.sym`, class registration, emission, naming and
the target round trip together. Package T already identifies geometry
authority for generated blocks; body policy requires the corresponding
transport even for primitive MOS families.

P11's wording that the plugin attaches hidden names is supported by source
inspection, not an executed host result in these body studies. In the current
code, each hidden body receives a mark; when its net has visible peers but no
mark yet, the first visible peer also receives one. A mark suppresses the
engine cross at that coordinate during translation. The final Schemify
netlisting and physical naming behavior remain required gates. The sixth
study separates this code trace from executed native behavior.

## Evidence boundaries correctly retained

P09 properly limits the shared-well inference to exact raw owner lists. All
23 internal body-only source cases now have actual-source certificates:
22 dashed bridges, AG1236's omitted bridge, and no unresolved member of that
denominator. AG1236 does not establish author intent or an electrical tie.
The native comparison preserves every fourth node while omitting the bridge.

The fourth study's independently derived D/S frame proof applies to its
upright PMOS frames. It does not upgrade every second-round cached D/S role
check into an independent polarity proof. The fifth study closes the changed
and swapped attached-marker text gap for ten body occurrences and six actual
external port objects in four circuits. Its seven explicitly unassociated
free/route labels remain outside that certificate; it is not a general label
recognizer. The proposed rules preserve both limits.

No body finding establishes an electrical defect from a native cross or
missing route. The remaining required oracle is the actual target round trip
with full ordered pins, class contacts and selected presentation checked
separately. The four independent finish lines in package V are appropriate.

## Suggested acceptance additions

Use the same small literal under absent B geometry, explicit visible B and
explicit hidden B, keeping its four raw bindings unchanged. Include a truly
lone visible terminal, one visible terminal with a hidden B peer, two hidden
B peers and a visible terminal with two hidden B peers. Check the native
mark/route decision, JSON/ABI terminal identity, plugin mark placement and
target netlisting separately. A four-entry JSON `pins` list alone cannot
establish that the fourth terminal was visible: the current JSON writer does
not serialize the class terminal's `hidden` field.

Do not turn this into a requirement to add a public ABI flag before writing
the callers. First determine which existing typed class/presentation input
the native and plugin paths can share. An unknown contact must remain unknown
through that seam rather than being treated as the origin of a valid lead.

## Follow-up resolution and named-rule review

After this review, the root plan added `S → B`, `T → B` and a common
final-frame-resolution F node after signed-variant and body-presentation
selection. F precedes group geometry and crossover stubs, and validates the
selected variant's actual contact capability. I reread that change: it
resolves the dependency omission and does not create a logical cycle.
This is a proposed contract, not a claim that current code already implements
the shared resolver. A moved/changed proposal still needs its own resolved
frame before a consumer uses it.

The body/visible-contact rows in `rule-amendments.md` correctly retain the
source and target proof boundaries. I requested the directly implicated
named rules `sketch.16`, `.17` and `.19` in addition to its unnamed convention
row. The current shown-pin scope of `.19` must be explicit; `.17`'s contact
safety must survive without promoting an unproved origin fallback into a
visible lead. The root applied those amendments and the hidden-routing versus
glyph-ink distinction after the sixth actual-image controls were reported.
