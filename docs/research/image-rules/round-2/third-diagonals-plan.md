# Third study: a bounded diagonal capability and its consumers

**Status: research only.** No engine, plugin, ABI, symbol, or routing change is
implemented. The executable [probe](third-diagonals-probe.py) and its
[result](third-diagonals-probe.json) contain an independent complete source-ink
census, exact arithmetic literals, current consumer hashes, and ten actual
enlarged image views. They do not execute Zig or the Schemify host. Allocation
failure tests, ABI tests, plugin imports, and SPICE round trips remain gates
for a future implementation.

The useful first capability is **cardinal terminal stubs with horizontal,
vertical, or 45-degree interior wire segments**, enabled explicitly by a caller
whose complete consumer path supports it. This does not decide which circuit
should use a diagonal. A source topology selector, a local placement owner,
glyph pose, and wire geometry each require separate evidence.

## What the source census does and does not establish

An independent reader parses the original SVG decimal text using `Decimal`,
without importing `wire_angles.py`, its path parser, or its float transforms.
It checks every original SVG hash and compares **every named diagram's
direction counts** with the parent census. All 2,894 tagged conductor elements
in the 2,202 diagrams are untransformed `path` elements containing explicit
`M`/`L` commands. Unknown element kinds, curves, incomplete points, missing
moves, and transforms fail this reader rather than disappearing.

The result agrees exactly: **187 named diagrams, 799 diagonal primitive
segments**, all with normalized slope magnitude one; 137,755 horizontal and
203,241 vertical primitives. No normalized zero segments occur. The smallest
nonzero normalized Chebyshev span is 0.848528. The largest raw violation of the
claimed direction is only **7e-14**: `dy` for a horizontal, `dx` for a vertical,
or `abs(dx)-abs(dy)` for a diagonal. This direction residue differs from the
largest error introduced by rounding a *span* to six decimals, 3.7626905e-7.
Seventy-one diagrams contain at least one direction whose exact decimal ratio
changes under the normalization. These names are retained in the result.

The 799 endpoint segments are distinct but form 538 normalized collinear ink
unions. For example, AG90 has four diagonal primitives along two collinear
unions; AG493 has 48 along 16. These are geometric unions without net identity:
neither 799 nor 538 is a count of electrical routes, independent feedback
edges, or connected nets. The normalization must not become a production
contact tolerance. A literal real segment of length 4e-7 would disappear under
it; that literal is retained as a scope counterexample.

The existing reader's tagged `<line>` literal would contribute no path, but
the exhaustive tag census shows no such element in this inventory. The present
named counts remain valid. Reusing the reader for new input needs an explicit
element-kind check. No universal SVG grammar claim follows from this census.

## Actual enlarged source/native comparisons

Each panel was rasterized separately from its original SVG, then actually
viewed. Paths, source/native hashes, PNG hashes, commands, and fresh notes are
in the probe JSON. The four cases belonging to shard 0 also have appended
details in its completed 734-row review ledger. AG1080's additional views are
recorded in this study. This five-case detailed scope is separate from both the
2,202-file census and the earlier full visual audit.

| Case | Source observation and native comparison | Planning consequence |
|---|---|---|
| AG90 | A small reciprocal PMOS X uses diagonal interiors and cardinal gate stubs. Native keeps the two columns with orthogonal reciprocal links. | A bounded interior-wire experiment has a real positive; the native orthogonal layout remains a valid fallback. |
| AG493 | Eight capacitor bodies and their leads lie diagonally between resistor rows. Native has cardinal capacitor poses in a broad interleaved row. | A wire-only capability cannot reproduce this family. Quarter-turn glyph orientation and row ownership are independent limitations. |
| AG1080 | Several clocked stages are separate; the bottom latch contains two diagonal X patterns. Native distributes the devices across broad rows. | Stage membership and local placement precede wire choice; a diagonal postprocessing rule alone is inadequate. |
| AG404 | The two-stage reciprocal return is orthogonal, including an outer bottom return. Native is orthogonal too. | Reciprocal topology cannot require diagonals universally. |
| AG647 | Adjacent source pairs, orthogonal crossed drain bars, and a level output capacitor. Native keeps adjacent source pairs and orthogonal bars. | Keep the orthogonal option for the mixer family; raw quad recognition grants no wire-pose authority. |

No new full terminal certificate is asserted for these five images. In
particular, the census never assigns diagonal strokes to a net from position
alone. A future automatic selector must bind its complete ordered terminals,
model/parameters, caller roles, and actual own-lead endpoints separately.

## Exact literals and additional failure classes

The Python literals are independent geometry expectations plus explicitly
labelled translations of current formulas. They are **not passing production
regression tests** and do not imply that today's Manhattan-only engine accepts
invalid diagonal input.

| Literal | Required result | Current assumption exposed |
|---|---|---|
| Segment `(0,0)-(10,10)`, point `(2,8)` | Point is off segment. | Bounding-box membership in Canvas/checks/plugin connectivity would invent contact. |
| That point-box, a diagonal tree, near-tree limit 5 | L1 distance to ink is 6, so decline. | `wires.nearTree` would use zero distance to the segment's bounding rectangle. |
| That segment and `(0,10)-(4,6)` | No segment intersection. | Their infinite lines cross beyond the second segment; overlapping boxes are insufficient. |
| Rays to `(-10,-10)` and `(10,-10)` at the origin | Two rays, no dot. | Four cardinal bits produce three occupied bits for these two rays. |
| Opposite diagonals in a 10-by-10 square | Proper crossing `(5,5)`; distinct nets stay separate. | Cardinal-only intersection counters miss it. |
| Add a third net `(0,5)-(10,5)` at the intended X | Initial bounded pair declines. | Three pairwise crossings coincide; two-route geometry alone does not establish a readable local result. This is a conservative policy boundary, not an electrical-invalidity claim. |
| The same X on one net | Dot plus endpoint splits at `(5,5)`. | Schemify joins nodes on wires, not an unsplit interior crossing. |
| Opposite diagonals in a 9-by-9 square | Exact crossing `(9/2,9/2)`. | Integer endpoints do not imply an integer junction. |
| Descending `(0,9)-(9,0)` | Integer label `(4,5)` is on wire; `(4,4)` is not. | Plugin `spot` floors both midpoint coordinates and would detach the label. |
| `(2^24,0)-(2^24+9,9)` through `f32` | Proposed exact delta `(9,9)` becomes `(8,9)`. | `Canvas.commit -> Route.pts -> Placed.poly` does not preserve every i32 point. |
| `i32::MAX` through `f32` | Becomes `2^31`, outside the later i32 conversion. | Input integer width is not a sufficient intermediate-storage contract. |
| Full i32-plane opposite diagonal directions | Determinant exceeds signed i64. | Widening the products to i64 is still insufficient for unrestricted cross products. |
| Duplicated/reversed collinear strokes | Exactly two rays at an interior point. | Primitive counts must not manufacture degree or extra junctions. |

The literal oracle also checks endpoint reversal, integer translation,
transpose, and reflection. The large-coordinate examples establish a
representation boundary for the proposed general capability; they are not
claims that the five drawings reach those coordinates or that a new regression
has been observed in current native output.

The first exact geometry kernel can use the closed direction set
`horizontal/vertical/rising45/falling45` with integer line constants and bounded
segment ranges. `x+y` and `x-y` require a wider type than i32; doubled
intersection coordinates fit a checked wider type. An alternative general
determinant oracle needs i128 arithmetic, widening **before** subtraction.
The adjacent Schemify host already uses i128 for its whole-i32-plane
`on_segment`. Do not silently replace a checked domain by a float epsilon.

For half-grid crossings, distinguish the cases explicitly. A crossing between
different nets need not become an exported point; it can remain an exact
doubled-coordinate event for clearance/reporting. A same-net crossing requires
a representable junction and endpoint split. The initial integer-output
capability should decline the whole candidate pair when that required junction
is nonintegral. Rounding either coordinate is forbidden. Expanding the output
coordinate domain is a separate ABI and host decision.

## Consumers that must agree before enabling the capability

| Owner | Necessary change or gate |
|---|---|
| `Canvas.fits`, `onNet`, `ways` | Exact point/segment and segment/body tests; foreign endpoint and wall rules; eight distinct rays rather than four projected cardinal bits. Retain terminal exit direction and cardinal lead stubs. |
| `maze.build` | Even with four-direction search moves, existing diagonal wires need exact own-net targets and obstacle/crossing treatment. Its current input asserts Manhattan and fills target bounding boxes. A point inside a diagonal's box is not a target. |
| `wires.nearTree` | It asserts axis-aligned existing trees; exact distance to actual diagonal ink must replace rectangle distance before removing that guard. The established L1 reach contract need not become Euclidean accidentally. |
| `trunk`, pair/part writers | All callers that inspect existing ink need the same geometry domain. A part certificate cannot use bounding-box membership or rectangle intersection as electrical contact. |
| `thin` | Recompute physical components and proper crossings with exact bounded geometry; retain coupled mate decisions and preserve caller-styled nets. No extra cut is justified by a new angle. |
| `dots`, `Placed.findCut`, `checks` | Deduplicate rays, discover same-net intersections, split required integral junctions, preserve visible pin endpoints, and reject foreign contact using the same declared geometric semantics. |
| `Schematic.Route` and `Placed.poly` | Either retain integer geometry throughout or admit only points whose complete current integer→f32→integer transport is exact. Recheck final actual endpoints and directions; do not assume small coordinates from the examples. |
| `report` | Current `report.1` counts only horizontal/vertical crossings and `report.2` defines right-angle corners. Decide and version the opt-in metric semantics; do not compare an expanded metric silently with the existing reference scorer. |
| C ABI and JSON consumers | Old `cktimg_parse_place`/`cktimg_run_json` retain the promised Manhattan output. New opt-in behavior needs explicit capability semantics and coordinate/range validation, including builds without ZON support. |
| C test oracle | `tests/abi_test.c:on_wire` also uses a bounding rectangle. The current helper would falsely certify `(2,8)` on a diagonal; an extended ABI test needs an independent exact contact oracle. |
| Schemify adapter `layout` | It currently asserts Manhattan, projects nonhorizontal segments to vertical in `merged`, uses boxes in `onPoly`/`onSeg`, and floors label midpoints in `spot`. Generalize normalization by line direction while retaining every original endpoint cut. |
| Schemify host | Verify actual node-on-wire semantics after adapter splitting, label placement, import, and netlisting. A renderer accepting two endpoints is insufficient. |

The host inspected is the adjacent `Schemify` checkout at commit
`92a48911f46f9d68961ae132154e8c03b3b4540a`; exact inspected file hashes are in the
JSON, so the commit alone is not used to hide possible worktree differences.
`crates/model/elab/src/connect.rs` searches the nodes on a diagonal using either
its lattice points or exact point-on-segment checks. Existing source tests in
`tests/connectivity.rs` cover diagonal attachment and noncontact. They were read,
not executed here. The host format stores i32 **milli-units** while this adapter
writes integer xschem units; validate the conversion range as well as the
engine's coordinate range. Supporting host decimals does not make the current
C ABI's integer junctions fractional.

## Collection, caller contract, and commit plan

1. **Collect facts without moving anything.** Input is the admitted local
   topology/ownership certificate, its complete pin/net binding, actual placed
   terminal frames, explicit caller requests, and immutable existing geometry.
   Raw topology enumeration precedes geometry eligibility. Keep ambiguous
   embeddings and overlaps visible; do not filter competitors until one
   diagonal happens to fit. AG404/647 stay orthogonal controls.
2. **Require an end-to-end capability permission.** A future caller-owned
   options argument might permit `Manhattan` or `allow_45_interiors`. This is
   proposed vocabulary, not a shipped symbol or a request to force diagonals.
   Old entry points select Manhattan. Unknown options or an unavailable
   required capability produce a named error, not an ABI reinterpretation.
   Frontends opt in only after their own consumer gates pass. A future explicit
   path request has a separate required/optional outcome and final geometry
   oracle; it cannot be reported honoured solely because the option was read.
3. **Apply precedence before candidate geometry.** Explicit class/port/face,
   route/via, label, wire, rail, pin, axis and symmetry constraints retain their
   shipped meaning. An automatic diagonal cannot move an explicit anchor,
   consume another owner's physical part, or grant local/global symmetry by
   implication. Conflicting automatic candidates decline locally. A hard caller
   request that cannot be satisfied is diagnosed, not silently rephrased.
4. **Enumerate a bounded pair of route alternatives.** Use actual cardinal
   stubs, then finite integer bend/diagonal candidates owned by the admitted
   local pattern. Each pair names both nets, every segment, intended crossing,
   attachment, and any generated symbols. No source-ID lookup or cached source
   coordinates enter production enumeration. Shape symmetry is a relation to
   prove against the local axis, not a demand to mirror the glyphs universally.
5. **Certify the whole pair.** Validate direction domain, exact f32 transport
   if retained, bounds, every actual endpoint, intended same-net connectivity,
   distinct-net noncontact, allowed crossings, body/lead clearance, label/port
   contact, physical part partition, and explicit caller geometry. Check the
   second route against the first staged route as well as preexisting ink.
   Parallel 45-degree line clearance must use a specified exact metric, not
   rectangular overlap or a guessed tolerance. Cardinal lead stubs remain
   protected even where an interior crossing is allowed.
6. **Commit once, or restore all appends.** `Canvas.save` alone records ink and
   asserts the node count is unchanged on restore. The existing
   `wire_parts.Checkpoint` also saves pins and xy, truncates generated nodes,
   and rebinds xy after allocation. Reuse that proven append boundary only if
   existing rows remain unchanged. Defer success/ownership/mate flags and
   anchor writes until both routes and generated symbols pass. Decline,
   collision on the second route, or OOM restores the pair, then ordinary
   routing receives the original state. Allocation capacity may grow; logical
   rows and final output must not change on failure.
7. **Recheck after downstream stages.** Keep the collector certificate and
   expected named physical components available to tests. Compaction, thinning,
   junction splitting, final Placed conversion, ABI export, and plugin merging
   must preserve its admitted relations. A success flag before these stages is
   insufficient. No later consumer may receive an unsupported diagonal merely
   because it did not create that route itself.

The six data questions are bounded here. Inputs are borrowed immutable
net/pin/placement facts plus candidate segment slices; outputs are appended
ordinary route/symbol rows and a small explicit admission result. Population
is bounded by named input candidate and total segment-reference capacities,
not by the observed 799 strokes. Handles remain existing typed u32 references;
point-width and arithmetic-width bounds are separate. Access is a cold scan
over candidate segments against the existing SoA geometry tables. Scratch
lives only through admission/commit; Canvas/Schematic remain output owners.
Independent candidates can be collected separately, but overlapping geometry
   must be resolved and committed in a deterministic serial order. No general
retained graph, callback framework, or new hot-path abstraction is justified.

Start the ABI design from this caller sequence, with **proposed names only**:
the caller queries supported geometry, chooses Manhattan unless its whole
consumer path supports the 45-degree option, and calls a new immediate
`parse_place_geometry(lib, src, zon, geometry, out_report)` entry point. The
geometry argument is a closed enum with two real cases; unknown numeric values
fail at that boundary. Existing entry points call the same spine with
Manhattan. Returned wire arrays keep their present borrowed lifetime and i32
endpoint representation. The permission may produce an entirely orthogonal
drawing when every automatic diagonal declines. A caller that requires a
particular path needs the separate path request and direct final-path oracle.
This adds no callback, retained caller options, or per-segment dynamic dispatch.
Any final public names, CLI/config vocabulary, and hint syntax must update the
shipped drawing skill and their caller examples together.

The cheapest shared seam is an exact free-function geometry vocabulary used by
the multiple existing consumers. Its independent oracle is this rational
reference and the host's separately implemented connectivity, not another call
to the same production predicate. Dispatch by the declared batch capability,
then use the closed direction domain. A later performance claim still needs a
measured benchmark/probe; none is made here.

Two caller boundaries remain deliberately unchanged in this first capability:
`netlines.read` rejects non-Manhattan exact `route` requests, and
`routes.mirrored` operates on a mate after the first net has already been drawn.
Neither silently becomes a new required-diagonal request or an atomic
two-net transaction. A new bounded pair owner needs its outer checkpoint and
separate final geometry assertion. Existing fallback semantics must remain
available for callers that do not opt into that owner.

## Acceptance gates before any production enablement

- Turn each literal above into a red-before-green production test, preserving
  the independent expected geometry. Add cardinal/diagonal mixes, collinear
  overlap and one-unit gaps, zero-length rejection, terminal lead intrusion,
  body-edge versus body-interior contact, and an attachment off the maze grid.
- Inject failure at every allocation/reservation and after the first route,
  first label, and second-route collision. Compare logical row contents,
  generated bindings, success flags, actual final output, and caller verdicts
  with the untouched fallback. Include an allocation that moves xy before
  failing. Test card-order and valid coordinate-transform controls.
- Preserve exact original Manhattan output names and bytes with the option
  absent, including old C callers and the current Schemify plugin. Add explicit
  unsupported/unknown capability outcomes and `-Dzon_config=false` coverage.
- Exercise the extended C API, JSON, SVG/LaTeX where applicable, plugin
  normalization, and actual Schemify import/netlist round trip. A diagonal X
  must remain two nets when unsplit; an admitted same-net X must join through
  exported endpoints. Verify descending odd-span labels on actual wire ink.
- Only after capability gates pass, run a separate source-bound policy study
  with complete terminal certificates and the exact positive/decline/keep name
  sets. AG493 remains outside a wire-only/cardinal-glyph experiment.

Affected human rules are `canvas.1–3,6–8`, `maze.1,2,4–6,8,9`,
`trunk.3,13,14`, `thin.1–7`, `dots.1–2`, `placed.1,8`, `checks.1–4`, and
`report.1–2`. Their existing Manhattan meanings remain in force. Extending a
geometry domain needs explicit amended contracts and downstream checks, not
an unannounced relaxation of those rules.

Reproduce the research result without a compiler:

```sh
python3 -B docs/research/image-rules/round-2/third-diagonals-probe.py \
  --check docs/research/image-rules/round-2/third-diagonals-probe.json \
  --output .objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/groups/diagonal-replay.json
```

The PNG render commands are retained per image in the result. Replaying the
probe checks their bindings; it does not count as another image view.
