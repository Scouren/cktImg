# Final saved-route review: compact stages and physical parts

The forced AG1080 reconstruction passes both twelfth local organization gates,
but fails all four AG1080 physical-part obligations from the eleventh study.
The apparent FN/FP and RN1/RP1 shorts are **undotted crossings**, not demonstrated
electrical joins. This distinction comes from the saved actual JSON and SVG,
checked after independently viewing the reconstructed raster.

This review runs no native producer, compiler or host. The artifact is the
twelfth study's saved `ag-1080-reconstruct` output from frozen native
`bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560`.
The executable [review](twelfth-ports-route-review.py) and
[evidence](twelfth-ports-route-review.json) bind every input by content hash.
The current worktree is not that frozen build.

## The apparent joins

| Nets | Native crossing | Actual dot relevant to the visual impression |
|---|---|---|
| FN / FP | (570,630) | FP has a dot at (570,635), five units below |
| RN1 / RP1 | (1370,710) | RP1 has a dot at (1370,720), ten units below |
| RN1 / RP1 | (1230,720) | RN1 has a dot at (1230,710), ten units above |

Each listed crossing lies strictly inside both participating straight
segments and has no junction dot. No endpoint or T contact is present there.
In the actual SVG, FN/FP crosses at (380.8,1099.2), while the FP dot is centered
at (380.8,1107.2). Its radius is 3.8 and the conductor half-width is 0.8;
there is a 3.4-unit painted gap between that disk and the FN stroke. The small
raster view makes this near junction easy to misread.

The independent axis-aligned segment reader examines all **136 route
segments**, not just these three locations. It finds fifteen undotted
cross-net crossings, **zero** cross-net collinear overlaps, endpoint/T
contacts or dotted crossings, and **zero** foreign route contacts at any
exported device pin. All 129 route polylines and all 31 junction circles are
matched to their actual SVG coordinates, using exact rational arithmetic.

This is a bounded route/contact result. It does not certify glyph interiors,
every own lead, text clearance, arbitrary SVG paint behavior, target import
or whole-page quality. In particular, it does not turn absence of these
contact failures into full A/F/W acceptance.

## Four exact N0 failures remain

The expected partitions are literals from the already viewed and independently
reviewed [eleventh source evidence](eleventh-partition-candidates.md). All
twelve source pair relations are checked against those literals, with the
original source SVG, deck and binding-file hashes retained. This review does
not infer the source's physical partition from the native routes.

| Net | Required source physical pieces | Actual reconstructed pieces |
|---|---|---|
| RN | `{M7.D, M9.D}` + `{M27.G}` | One continuous piece containing all three |
| RP | `{M6.D, M8.D}` + `{M28.G}` | One continuous piece containing all three |
| FN1 | `{M16.D, M18.D}` + `{M29.G}` | Three separately named single-pin pieces |
| FP1 | `{M15.D, M17.D}` + `{M31.G}` | One continuous piece containing all three |

The new native component reader uses conductor segments as its graph
vertices. Endpoint/T contacts, overlaps and actual dots join them; undotted
proper crossings do not. Pin and marker association happens afterward.
Labels never add union vertices. Every selected raw occurrence must belong
to exactly one component, reachable markers must agree with its net, and
each disconnected piece must have a name. The three FN1 pieces do have
correct FN1 names: the failure is the missing local D/D tree, not missing
electrical identity. RN, RP and FP1 instead retain forbidden continuous
connections to their remote gates under the proposed N0 contract.

The actual inventory remains all thirty-two original MOS devices. The review
compares both the untouched original deck and forced-pose deck against
every selected model/class, parameter token and ordered D/G/S/B binding:
128 raw terminal occurrences. Generated terminal records are checked
separately. Actual selected-frame correctness remains the independent
twelfth organization review's obligation, rather than being inferred from
this route graph.

Five offline controls add a crossing dot, create a foreign endpoint/T,
add a collinear foreign stroke, contact a raw pin with a foreign route, and
place a label at the undotted crossing. The first four produce the expected
contact failures; the last leaves the conductor scan unchanged. These are
research-oracle controls, not additional engine executions.

The useful counterexample is therefore exact: **two compact, directed local
stage passes coexist with four failed N0 partitions in one actual saved
output**. These strong caller poses were not promised automatic N0 admission,
so this is not a new production regression claim. It demonstrates why a
future G1 proposal cannot be published using only its local organization
score when N0 parts are mandatory. Full selected-frame, contact, routing,
thinning and original-caller gates remain separate. Native and actual
same-build target completion also remain separate.

Replay from the repository root:

```sh
python3 -B docs/research/image-rules/round-2/twelfth-ports-route-review.py --check docs/research/image-rules/round-2/twelfth-ports-route-review.json --output /tmp/twelfth-ports-route-review.json
```
