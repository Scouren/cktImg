# Adversarial cross-review: ports to body presentation

This review found two reproducible holes in the research certificate, and the body author repaired both. Moving AG1014 M1's cached B to a remote point on the correct body wire no longer counts as attachment to M1. A four-visible-terminal native record with its fourth role incorrectly named G no longer passes the typed D/G/S/B binding check. The unchanged native artifact still has the body-presentation failures described by the body study; these repairs strengthen the evidence, not the engine.

The retained [pre-fix results](ports_review_failures.json) record the exact reviewed script hash, mutation and observed incorrect acceptance. The independent [cross-review script](ports_review_bodies.py) now passes against the fixed author code, with [replay output](ports_review_bodies.json). No peer-owned file was edited by this reviewer.

## Actual-image review

I independently rasterized and actually viewed source/native pairs for AG1014, AG1021, AG1130, AG1167, AG1177 and AG1294. [Renderer commands and hashes](ports_review_rendered.json) record all 12 images. This is targeted adversarial review, separate from the original 734-pair ports overview.

| Case | Fresh observation and implication |
|---|---|
| AG1014 | Source VI1/VI2 dotted inputs enter the two transistor bodies while their gates share VDD. Native shows the VDD gates but loses the visible body inputs. Correct raw `bulk` fields alone cannot explain those inputs to a reader. |
| AG1021 | Source M1's drain/body relationship drives M2's body through the dotted branch. Native retains a current-source/M1/output-M2 arrangement without that readable body relationship. B=D on M1 and B distinct on M2 must both survive. |
| AG1130 | Source MOS capacitors deliberately show crosses at D and S; the native also has those crosses. The missing visible connection is VTUNE to the bodies, not an invented D/S connection. Preserve NC0001–4 as separate raw nets. |
| AG1167 | The source shows several explicit body-resistor branches. Native displays the corresponding resistors with detached-looking crosses. This is a presentation discrepancy; the retained body net and plugin hidden labels prevent inferring electrical loss from the native picture alone. |
| AG1177 | The varactor devices tie D, S and B to VCTRL, with a separate gate net. The native unfolds these devices into switch-like forms. An exclusive B=S census bucket must not erase the simultaneous B=D and D=S facts. |
| AG1294 | The paired PMOS stage and converter topology are materially different from an externally body-driven pair. The author's actual SVG path connects the two body landings on internal net4; native stores that well only as two bulk bindings. Lack of a DUT formal or nonbody consumer cannot justify omitting the shared-well representation. |

## Failure 1: correct wire, wrong symbol attachment

The actual AG1014 M1 channel landing is `(124,110)`. The source VI1 terminal at `(60,110)` lies on the other end of its real dotted conductor. The mutation changes only cached M1.B to `(60,110)` and leaves the raw card, source net map, actual SVG, and D/G/S geometry unchanged.

Before repair, full `bodies_examples.inspect('ag-1014')` returned `supported_body_landing`, despite simultaneously reporting `B_is_own_lead_endpoint=false` and `containing_filled_polygons=[]`. The status used only named ink touching the cached point. Thus a point on the right net could masquerade as a contact on the right symbol.

The repair requires supported own-symbol geometry **and** named ink. The independent replay patches the actual JSON read in memory and calls the full inspect path again. It now reports `detached_cached_body_landing`. This is stronger than testing a replacement helper with hand-fed booleans; it exercises the real association, SVG geometry, named-wire check and status path together. The unmodified AG1014 positive remains supported.

## Failure 2: fourth visible role unchecked

The previous native binding checker compared all net values but checked role names only for the first three visible pins. A literal four-pin record `d=d, g=g, s=s, g=b` therefore passed an expected D/G/S/B tuple. Its fourth net happened to be correct, but its typed role was wrong.

The fixed typed proof now requires role `b` on the fourth visible pin. Two positive representations remain: four visible D/G/S/B pins, and three visible D/G/S pins plus `bulk=b`. Four independent mutations reject: wrong fourth role, wrong bulk net, deletion of the visible fourth pin, and exchange of gate/body nets. A custom caller's alternative pin names require an explicit ordered schema; these tests do not impose builtin names on arbitrary registered symbols.

## Boundaries that survived the attack

The census retains all 15 equality partitions of four ordered terminals. The review supplies literal expected values for B=D, B=G, B=S and D=S, including B=D=G, B=G=S, D=S=B and all four equal. All pass. Its primary relation priority is a reporting bucket, not a complete semantic contract. Future selectors must consume the equality facts they need rather than mistake mutually exclusive bucket names for mutually exclusive electrical ties.

Six complete raw deck controls distinguish an internal body-only shared net, the same net exported as a DUT formal, the same net consumed by a resistor, by another MOS gate, or by an X formal, and an internal body-only net merely renamed `vdd`. Every body occurrence survives; the new nonbody consumer is counted in the correct ordered position. A rail-like spelling does not change the internal-body-only result. Source rail annotations remain separately scoped evidence, not inferred truth.

The source proof still uses cached net names to associate actual conductor segments with raw nets. An additional in-memory mutation changing AG1014's actual VI1 marker text to VI2 leaves its body landing supported and its `source_metadata_binding` successful. This is a scope limit: actual attachment and SVG-backed named routes are proved, while external marker text-to-formal binding is not independently certified by this body script. The author was notified. A future fully ink-certified external binding must either reject a contradictory reachable marker or explicitly report that label association unresolved. A whole-figure visual review cannot silently fill this gap for mutated inputs.

## Export and ownership implications

The source body's filled-channel landing is not a fourth explicit own-symbol lead. The study correctly distinguishes those conventions: all studied cached B points lie in a filled channel polygon, while the source MOS assets have only three explicit leads. A future visible engine body pin needs either a certified class contact or a declared attachment convention. A point at origin returned for missing geometry is not a physical terminal.

The code trace supports the author's caution about connectivity claims. `src/json.zig` emits class terminals in `pins` and one extra electrical pin in `bulk`; that extra value has no coordinate. `tools/schemify/layout.zig` currently marks pin index three of every nMOS/pMOS family hidden. Later it emits a name at the hidden contact and, when needed, at an otherwise unnamed visible peer. Therefore an isolated-looking resistor in native SVG is not enough to prove that Schemify's netlist loses the body connection. An executed target-netlist round trip remains necessary.

That same trace creates a concrete dependency for implementation: adding a fourth visible native terminal alone will not change the plugin's hardcoded family/index hidden policy. Both the engine library construction and plugin's pin-to-wire/label emission must consume the resolved presentation decision. The raw D/G/S/B tuple remains owned by the netlist. The class owns geometry. A single presentation owner resolves whether each ordered occurrence has a routable contact, hidden name attachment, local self-tie, or unresolved geometry. Routing and exporters consume that decision; they must not independently infer body visibility.

The minimum change-radius plan is therefore:

1. Preserve ordered raw identity and every equality bit before presentation. A B=S drawing simplification never deletes the B row.
2. Resolve caller class and explicit visibility policy before producing pin coordinates, reservations, local groups or routes. A body-only well remains a net with obligations.
3. Produce one complete contact/name obligation per required body occurrence, plus the named visible peer when a target requires one to join islands.
4. Have native, JSON/ABI and plugin consumers read the same outcome. Caller-hidden classes and caller-visible four-pin classes are positive controls, not automatic overrides.
5. Run host importer/netlister round trips comparing exact named cards and ordered terminals. Include label deletion, wrong-net labels, off-contact labels, missing visible-peer labels, and G/B exchanges. Correct JSON values are necessary but insufficient.

The author's [body plan](bodies.md) now states these ownership and fallback boundaries. This review does not establish a universal body resistor pose, a global rule to reveal all nonrail bodies, or a successful Schemify round trip.

## Replay

```sh
python3 -B docs/research/image-rules/round-2/ports_review_bodies.py --check docs/research/image-rules/round-2/ports_review_bodies.json --output /tmp/ports-body-review-replay.json
```

The check verifies 15 literal equality partitions, six raw interface cases, the actual-source detached-cache regression, two positive native representations and four native mutation rejections. It binds the reviewed author scripts and the retained historical failure record. No compiler or production edit is required.
