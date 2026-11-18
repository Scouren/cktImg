# Fifth body round: actual external marker association

**The known AG1014 marker-text contradiction is now rejected by a separate, stronger certificate.** Changing the actual VI1 port label to VI2 while leaving the raw deck, source cache, body landing, and wires unchanged fails. The [fifth proof](fifth-bodies-evidence.json) binds ten body terminals to six exact actual port objects across AG1014, AG1026, AG1057, and AG1065. All four source/native pairs were actually re-viewed; [fresh view records](fifth-bodies-views.json) retain the images, hashes, and observations.

This closes the specific attached-marker gap for these examples. It does not retroactively expand the claims of the earlier scoped certificates or turn the checker into a general visual netlist extractor. No engine work was performed.

| Case | Raw body terminals | Raw formal | Actual attached text | Source port anchor |
|---|---|---|---|---|
| AG1014 | M1.B | vi1 | v with i1 subscript | `[60,110]` |
| AG1014 | M2.B | vi2 | v with i2 subscript | `[290,110]` |
| AG1026 | M1.B | vin- | v, minus superscript, in subscript | `[160,100]` |
| AG1026 | M2.B | vin+ | v, plus superscript, in subscript | `[340,100]` |
| AG1057 | MN5.B, MN6.B, MN7.B, MN8.B | pwell | PWELL | `[-240,130]` |
| AG1065 | MP0.B, MP1.B | nwell | NWELL | `[-80,70]` |

The actual port objects are retained by full ID in the evidence: AG1014 `instance-1130c5ea-9464-4ce8-811d-285c6f0a436d` and `instance-517852de-8bee-435e-a348-c5f61fee0b05`; AG1026 `instance-b906d2ba-d144-4ee2-8785-a718ca40401a` and `instance-d933d3e3-2ecc-4322-a6c0-70cccb395bb3`; AG1057 `instance-7c179dd6-6d91-4c15-b5ce-929ed8ae9914`; AG1065 `nw`. These are provenance, not an admission whitelist. Consistently renaming an actual port object and its attached label ID preserves the certificate.

## What associates the label with the body

The checker enumerates every supported actual source marker before filtering by desired text or net: 6 in AG1014, 12 in AG1026, 15 in AG1057, and 10 in AG1065. The total is 43, including ordinary ports, ground glyphs, supply-port glyphs, and full-width rails. It then tests actual conductor reachability from each supported own-glyph B landing to every marker anchor. Each studied body reaches exactly one actual marker object, and that object is a port. A second contradictory marker remains in this raw reachable set even if it is absent from the cache or has the wrong text.

For a port, the anchor is derived from its actual transformed circle and lead: the lead endpoint on the circle must meet the circumference, and the other actual endpoint is the circuit contact. The source cache must agree with this contact, but does not supply its geometry. The text is associated through the exact `instance-label-<port-object-id>` relation already present in the SVG, with `data-anchor-kind="object"`. Exactly one attached text object is required. The certificate records the actual text positions and run structure; it never chooses a nearby word by distance.

For exclusion of competing rail/ground markers, ground anchors come from the supported actual stem, supply-port stems must meet their actual filled bar polygon, and full-width rail labels must have the explicit label-owner/net-ID association and route pieces supported by actual conductor ink. Every candidate rail endpoint is considered. Ground is not renamed to VSS by guesswork: any reachable ground or rail would contradict this narrow external-input-port case and cause decline.

The selected body must have raw/cache D/G/S/B equality and a literal raw-card expectation, plus an actual supported own channel landing. Its complete body-net incidence and raw formal index are recorded. A named path uses only cache segments that also exist in actual SVG conductor ink. A separate all-actual-ink scan finds reachable markers without relying on the cache's net assignment. Both must reach the same actual port contact. The attached text token, raw formal, and cached marker name/net must then agree.

This checks the B-to-formal association. The general D/G/S role-frame problem remains separately scoped: prior endpoint membership alone is weaker than the actual-arrow frame added for the fourth study's upright PMOS family. This fifth checker does not claim a new general source-role extractor for every MOS orientation.

## Typography and aliases stay explicit

AG1026 demonstrates why concatenating text nodes is insufficient. Its label runs appear in XML order as `v-in` and `v+in`, while the raw formals are `vin-` and `vin+`. The narrow decoder requires the observed `v` base, one plus/minus superscript, and one `in` subscript, then produces the corresponding formal token. It retains the original text and role sequence. This is a verified typography mapping, not permission to reorder arbitrary names or infer signal direction from a sign.

AG1057 uses actual instance labels N5, N6, N7, N8 for raw MN5, MN6, MN7, MN8. AG1065 uses P0/P1 for raw MP0/MP1. Each alias is a literal case-specific expected row, checked against the actual instance label and the raw/cache binding. The checker does not strip prefixes or treat every N/P label as a transistor-card match. These ports are passive in the source cache; the proof establishes external identity and visible attachment, not a runtime input/output direction classification.

## Mutation results and remaining text boundary

Seventeen actual-source mutations are rejected:

- Changed attached body-port text in each of the four cases.
- An extra contradictory actual port object at the reachable body-port anchor in each case, even though it has no cached marker row.
- A second contradictory attached label object in each case.
- Swapped body-input labels in AG1014 and AG1026.
- The exact earlier AG1014 VI1-to-VI2 text mutation.
- Deletion of the actual AG1014 port stem while retaining source metadata.
- An extra actual ground glyph at the AG1014 body-port contact.

Reversing cached marker/device/wire record order and consistently renaming actual port object IDs are positive controls. Neither changes the ordered body-to-formal result. Every control calls the complete certificate, rather than comparing a mutated list to its original. Original cases have no unsupported body-marker association.

Seven existing free/route net-label objects in AG1057/AG1065 remain explicitly recorded under `unassociated_route_or_free_labels`, with their exact object IDs, text, anchor kind, optional net ID, and actual text position. Their positions do not establish electrical attachment. They are not used as graph edges or silently claimed to agree with the body nets. An additional free label without an explicit contact/owner relation would remain outside this marker certificate; this study does not prove that no contradictory annotation exists anywhere in the picture. The previous gap is closed for actual attached port labels and other supported reachable marker objects.

The proof still trusts the source format's explicit object-to-label association as a typed relation. It does not certify text legibility or perceived association if someone moves a label far from its owner while preserving that ID. A full importer needs a caller-owned source-association contract or a named uncertainty result for formats without those relations. Generic nearest-label inference is not a substitute.

## Planning consequence

Source evidence should distinguish three separate facts: an electrical terminal's identity, its supported actual contact, and an explicitly associated marker or annotation. Store these as typed witness references owned by the importer; preserve the original object IDs and text runs in cold provenance. The terminal-presentation resolver can consume a verified external-body association when choosing a visible fourth-terminal representation. It cannot manufacture an association from a cached coordinate on the right net or suppress the formal merely because the built-in glyph has only three leads.

Build the raw reachable-marker list before applying label normalization, permitted aliases, desired direction, or class eligibility. A conflicting reachable marker, duplicated owner relation, unsupported glyph, broken actual path, or raw/cache/text disagreement should return the exact device, body pin, marker object, and conflicting source fact. Only after those checks pass should the resolver request visible endpoint geometry. Keep the complete electrical node in every exporter even when presentation is declined. The same accepted presentation must feed placement, pin escape, routing, JSON/ABI, and plugin export; an SVG-only fix would leave their contracts inconsistent.

The source decoder owns typography interpretation. A caller owns the desired presentation and explicit aliases; a renderer consumes the resolved result. Neither a layout pass nor a plugin should reinterpret superscripts, rename wells, infer a rail from spelling, or introduce an external port absent from the raw interface. Formats with only free text should abstain from this narrow certificate and retain named unresolved associations until stronger source evidence is supplied.

```sh
python3 -B docs/research/image-rules/round-2/fifth-bodies-proof.py \
  docs/research/image-rules/round-2/fifth-bodies-evidence.json
python3 -B docs/research/image-rules/round-2/fifth-bodies-proof.py \
  .objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/fifth-bodies-replay.json \
  --check docs/research/image-rules/round-2/fifth-bodies-evidence.json
```

No C ABI execution, Schemify round trip, circuit-operating conclusion, engine edit, or compilation is claimed. The native omissions and preserved ordered bulk identities remain the earlier frozen-output observations; this round improves source-side proof and the future admission contract.
