# Round 2: exact ports, signed input order, and local admission

The fresh audit resolves the five assigned four-bias/clocked contracts at the raw-binding level and certifies all 30 visible own-symbol leads. Their five declared VSS terminals are not drawn in the source, so their eventual canonical positions remain design choices. Actual SVG conductor paths resolve several connections that stale cached terminal and wire coordinates could not resolve in round 1. The complete corpus adds two further raw contract matches, AG808 and AG1242; both were enlarged and viewed, but are outside the five-instance detailed geometry certificate.

This is research and a concrete implementation plan. No engine, plugin, renderer, or committed binary was changed. Native comparisons use the frozen round-1 experiment, not the dirty current worktree. Current rules were read independently: all 81 frozen headers and all 84 current headers through the complete worktree delta. The overview ledger records a new actual view of all 734 assigned source/native pairs across 62 sheets. Detailed proof scope is deliberately smaller than image-view coverage.

Artifacts:

- [Fresh overview notes](ports_overview_notes.json), [enlarged notes](ports_enlarged_notes.json), and [extra global views](ports_extra_views.json).
- [Independent raster provenance](ports_rendered.json): 30 enlarged PNGs, SVG/PNG hashes and exact renderer commands. Source SVGs were rasterized individually, never nested together.
- [Source-ink contract certificate](ports_contracts.py) and [all bindings, paths, mutations and census](ports_contracts.json).
- [Stricter raw-incidence proposal](ports_predicates.py) and [positive names and adversarial cards](ports_predicates.json).
- [Nine-port pose feasibility witness](ports_pose.py) and [96 checked frames](ports_pose.json).

## What changed from round 1

The earlier unresolved geometry was not evidence that the actual source drawings lacked those ports. In AG1674, cached VB2/VB3/VB4 tips are respectively `(290,210)`, `(330,210)`, `(360,210)`; the visible strokes end at `(280,210)`, `(300,210)`, `(320,210)`. The actual conductor ink reaches the correspondingly labelled markers. Cached output `(390,140)` is also displaced from actual `(350,140)`. The certificate now follows actual transformed strokes, preserving the stale values only as diagnostics.

AG2212 has the same distinction: actual VDD attaches at `(-40,-70)` and actual output ends at `(50,0)`; the latter reaches the actual MNP gate. Its VB4 lead genuinely bends from the triangle to `(60,70)`. A simple match against the cached pin position misses correct source geometry. AG3492's actual clock tip is `(490,620)`, not cached `(490,640)`, and its actual output is `(510,600)`, not `(490,600)`.

The new control deletes all cached wires and corrupts all cached target-symbol terminals to `(9999,9999)`; actual binding still succeeds. Deleting or shifting the real VB2 conductor, deleting or swapping actual marker labels, or changing the target object's actual identity fails. Thus a cached map cannot stand in for visible ink.

## Exact raw contracts and every binding

These rows preserve declaration order. A pair `formal=net` never changes position because a drawing slot changes. The JSON stores the original call, index, formal, net, role, and visible geometry status for every one of the 35 declared ports.

| Case / call | All raw bindings in declaration order |
|---|---|
| AG1674 X1 / A1 | `vdd=vdd, vss=vss, vb1=vb1, vb3=vb3, inn=y, inp=x, vb2=vb2, out=vout, vb4=vb4` |
| AG2212 X1 / opamp | `vdd=vdd, vss=vss, inn=fb, inp=vref, vb2=vb2, out=net0, vb1=vb1, vb3=vb3, vb4=vb4` |
| AG3492 X2 / Comparator | `vdd=vdd, vss=vss, clk=clk, inn=vx, inp=vss, out=vout` |
| AG3493 X2 / comparator | `vdd=vdd, vss=vss, inp=vss, inn=vx, clk=phic, out=vout` |
| AG3495 X2 / Comparator | `vss=vss, vn=vx, vp=vss, vo=vout, phi3=phi3` |

AG3495 declares no VDD formal. Its `.global VDD` cannot justify inventing a sixth terminal. Its source φ3 marker meets the actual clock lead despite a null cached net. The certificate uses an explicit literal label-transcription table (`φ3` to `phi3`, `φc` to `phic`); this is not permission to normalize arbitrary circuit labels or infer phase semantics globally.

The proposed four-bias contract requires exactly one each of supply, ground, negative, positive, output, bias1, bias2, bias3, bias4 and an already established exact family name. The clocked contract requires the exact comparator family, one signed pair, output, ground, one clock, and optional supply. Unknown or duplicate roles and missing/extra raw bindings reject the whole contract. Binding net names do not select shape. The narrow clock formal spellings currently evidenced are `clk` and `phi3`; broader aliases require their own evidence.

A distinct full-2202 scan gives seven raw matches:

| Contract | Exact full-corpus names | Extra declarations outside shard 2 |
|---|---|---|
| Four-bias signed | AG1242, AG1674, AG2212 | AG1242 X1 EA: `vdd=vdd, vss=vss, vb1=vb1, vb3=vb3, vb2=vb2, inp=vref, inn=vfp1, out=vctrl, vb4=vb4` |
| Clocked signed | AG808, AG3492, AG3493, AG3495 | AG808 X2 comparator: `vdd=vdd, vss=vss, out=vout, inn=vx, inp=vss, clk=phic` |

The seven-name result is a complete raw census for this predicate over these 2202 decks, not a global truth about amplifier families. All seven source bodies were viewed. AG1242 is left-facing, with positive above negative and a bent fourth bias; AG808 has a bottom clock. Neither observation authorizes broader circuit placement. AG808's separate opamp has `IB` in addition to VB1/VB2/VB3, so it remains outside the exact four-VB contract.

## Actual own-lead geometry

The certificate locates the target body using its source association and independently checks its literal SVG object identity. It derives input roles from actual internal signs, output from the actual apex, and auxiliary bindings through actual marker ink plus conductor paths. Every own-symbol lead must be used exactly once. All reachable markers must agree with the raw bound net, including signals independently witnessed by a neighbouring device. No marker is required where a non-marker neighbour proves the connection; a contradictory reachable marker is never acceptable.

| Source | Actual visible tips, keyed by formal |
|---|---|
| AG1674 | `vdd(310,70), vb1(260,210), vb2(280,210), vb3(300,210), vb4(320,210), inn(230,120), inp(230,160), out(350,140)` |
| AG2212 | `vdd(-40,-70), vb1(-60,70), vb2(-30,70), vb3(0,70), vb4(60,70), inn(-90,20), inp(-90,-20), out(50,0)` |
| AG3492 | `vdd(440,530), clk(490,620), inn(390,580), inp(390,620), out(510,600)` |
| AG3493 | `vdd(480,510), clk(520,510), inn(450,560), inp(450,600), out(550,580)` |
| AG3495 | `phi3(420,500), vn(380,550), vp(380,610), vo(500,580)` |

For example, AG1674's actual VB2 path is `(280,210) → (280,300) → (400,300)`, ending at the marker whose actual label reads VB2. The source output reaches Vout through actual conductor ink; its signed inputs separately meet the correct raw R1/R2 terminals. AG2212's output reaches actual MNP.G and its negative input reaches R1.2. The comparators' negative leads reach the other amplifier's actual output, whose raw output binding is VX. These neighbour witnesses are retained in the JSON.

Own-lead checks independently require a first attachment on the body boundary, first segment directed outside, a cardinal final direction, and a unique tip. Every segment is split at body-edge intersections and checked for re-entry; only an initial attachment sliver within the existing 0.01 source-coordinate tolerance is allowed, because source coordinates are rounded to 0.001. A literal bent lead that exits and then passes back through the triangle is rejected. The stronger global body-support test is separately recorded. AG3492's clock fails that stronger test: its downward tip at y620 is above another body vertex at y657.735. The raw clock contract remains valid, but this exact source pose is unsuitable for a rule requiring the entire body behind every tip's outward plane. A canonical clock placement must resolve that boundary explicitly.

VSS is declared and bound in all five cases but has no drawn own lead. The proof does not invent a source coordinate or pretend that visual omission removes the terminal. Future engine geometry must retain it, with a clearly documented canonical position.

![AG2212 source, independently rasterized](figures/ports/ag-2212-source.png)

## Positive fallbacks and unknown controls

The actual-outline keep census has 12 rectangular instances in 11 named images: AG1730, AG1746, AG1751, AG1752, AG1760, AG1764, AG1773, AG1778, AG2407, AG2442 (two), AG2469. These are positive controls for preserving genuine source boxes, not merely failed triangle recognitions. AG1730 is an actual OTA rectangle; AG1752's A1 has an extra Z; AG2407 has four VX controls. A caption or family prefix must not erase the distinction.

The named unknown-control inventory is AG1677, AG2190, AG2586, AG2699, AG2713, AG2838, AG2905, AG3177, AG3265, AG3286. The JSON enumerates every call and raw binding in these cases. AG2586 has four bias names **and TAIL**, not the exact nine-port contract. AG2905's VX touches the sample junction while VB1 is separate, so interpreting every auxiliary input as an independent bias is electrically unsupported. This study assigns no guessed meaning to VX, VCX, Z, VA, IB, or TAIL.

## New counterexamples against the 39/35 selectors

The prior certificates remain intact. The new script imports the earlier raw selector and records both old and strengthened verdicts on each complete mutated deck. It does not rewrite old evidence or broaden the old recognized contract. Twenty-one mutations are accepted by the earlier selector and rejected by the stronger necessary conditions:

| Counterexample class | Why automatic local placement must reject |
|---|---|
| Supply bound to a private signal, in either topology | A formal role alone does not prove a separate rail |
| Unknown MOS model, in either topology | Gate/channel pattern alone does not establish the selected nMOS device family |
| Additional resistor touching regulator feedback | The previously inferred private three-incidence feedback node has another consumer |
| Additional capacitor touching regulator gate | The presumed two-incidence amplifier-output/pass-gate net is no longer private |
| Pass-device body connected to feedback | A fourth electrical terminal consumes the feedback net |
| Reference reused as pass-device input | The reference is no longer the separate externally supplied input used by the pose |
| Regulator supply bound to regulated output | The evidenced separate supply/output role boundary no longer holds |
| Protected FB or gate NET0 exported as a DUT formal | Internal incidence is insufficient to claim privacy when the external interface can consume the net |
| Sampling bias bound to junction or output | The auxiliary terminal consumes a protected signal node |
| Two sampling biases aliased | Two independently drawn bias roles share the presumed separate control |
| Sampling bias not an outer formal | An internal dangling net is not a certified external bias |
| Sampling body bound to the junction | Visible D/S topology hides an additional incidence |
| Sampling output bound to junction or ground | The claimed feedback topology collapses |
| Clock gate removed from outer formals | Single incidence alone does not establish external control |
| Sampling junction or negative input exported as a DUT formal | The local sampling owner no longer owns the complete protected interface |

Positive metamorphic controls rename every net consistently and permute declaration/binding pairs together. Both preserve selection. Replacing an input formal with an unknown role rejects in both versions. The script records all MOS D/G/S/B incidences, all R/C pins and every X formal; none are silently omitted because a renderer hides them.

The strengthened predicate preserves the exact original shard name lists: 39 regulators and 35 sampling cells. A separate complete-corpus run preserves 39 regulators and **36** sampling cells, adding AG789 outside this shard. The full JSON compares names, not counts. The three biased sampling cases remain exactly AG2637, AG2657, AG2757. AG789's enlarged source/native pair confirms it is a positive keep, with two series switches, a shunt junction capacitor and upper feedback.

The adversarial groups review supplied the arity/re-entry and exported-net counterexamples. The new regulator and sampling interface boundaries are conservative pose exclusions; they do not declare those circuits electrically invalid.

This stricter proposal is still a necessary-condition screen, not a complete implementation or an assertion that every allowed circuit is fully owned. It leaves unrelated outer R/C structure outside the protected nets alone. It does not require every supply binding to be an outer formal: the unchanged AG2225 positive uses a local VDD binding. No semantic property is inferred from a net's spelling.

There are also eight literal planning controls for caller precedence and candidate cardinality. One raw eligible candidate can proceed. Caller symbol, explicit sides, absolute placement or existing group ownership suppress the automatic pose. Two raw candidates suppress it even when one is hidden or later ineligible. The cardinality check happens **before** eligibility filtering; enumeration order must not make one candidate appear unique.

The expanded four-bias contract is deliberately separate from the tightened old selectors. Composing them may admit AG2212 as an additional regulator. The root's independent [interaction study](interaction_candidates.py) owns that composition census. Changing glyph recognition alone must not silently broaden a placement owner.

## Concrete plan and dependency order

1. **Bind semantic roles without moving raw terminals.** Keep one complete per-definition role certificate that includes all declared formals and their original indices. Reject missing, duplicate and unknown roles at this boundary. Do not inspect labels, captions, instance IDs or net spelling to choose the glyph. Preserve exact-name family handling, registered caller symbols and explicit side directives.
2. **Expand the bounded representation deliberately.** `block_symbols.zig` currently caps ports at eight and returns an output index as `?u3`. A nine-port contract can put output at index eight after a paired declaration permutation; merely adding `bias4` is insufficient. The bound, casts, assertions, public documentation and `analogOutput` callers in `skeleton.zig` and `bridges.zig` must agree on indices 0–8. The adversarial groups review also found `bias_neighbors.Pair.pins: [2]u3`, `find`'s amplifier-index cast, and its `turn`/`tip` consumers. A valid private BIAS peer can target amplifier VB1 at index eight even when output is at index four; the [combined fixture](third-ports-width.cir) and [capacity proof](third-ports-width.json) preserve that case. The peer's separate index remains bounded by four, so do not widen both domains without considering their ranges. Two extra roles fit the current four-bit role enum (13 becomes 15); port index width must still grow. Do not widen unrelated hot device handles.
3. **Choose signed input order as geometry policy.** A regulator may request positive above negative; a sampling cell keeps negative above grounded positive. This swaps the signed slots and their internal marks while keeping every original formal index/net binding unchanged. It is distinct from rotating or reflecting the whole symbol. AG1674 and AG2212 share the four-bias contract but need opposite signed orders; AG1242 adds a left-facing control. Do not use whole-symbol reflection as a shortcut: it also moves supply/bias/clock leads.
4. **Represent that choice before class/frame reservation.** `Library.blockFor` caches a class as `block:<family>` and class IDs are append-only. Per-instance signed order cannot mutate a shared class. The implementation must choose a bounded glyph variant keyed by complete contract plus signed-order policy, or an equivalently explicit per-instance geometry request owned by the same drawing pipeline. The exact API should be chosen from native and plugin caller code together, with the second actual case present. This plan does not prescribe a second ad hoc renderer.
5. **Prove the complete actual frame.** Resolve each role to an actual own lead and normal after the signed-slot choice and world transform. Retain undrawn source VSS as an explicit canonical choice. Check all nine tips, body support, lead crossings, marks, labels and bounds. A clock is a control, not a rail; the body-support exception of AG3492 and top/bottom source clock variation forbid deriving one canonical side from that single image.
6. **Select raw candidates, then apply caller eligibility.** Count complete candidates over the unfiltered electrical graph. Check external control, all-pin incidence, body connections and protected private nodes. Only then apply symbol, side, position and group ownership constraints. Keep a tuple containing the exact consumed device and net handles; avoid global name-based rules.
7. **Admit the local topology explicitly.** `opamp.amplifier` separately rejects `.other` ports, so recognizing a biased triangle is insufficient to restore AG2637/2657/2757's local layout. Supply the complete bias contract to that admission owner only after the three cases' external/private controls pass. Do not relabel every unknown auxiliary port as a rail. Whole-circuit admission must still reject AG1674's BJTs and AG1242's larger converter network.
8. **Reserve, place, route and export from one final geometry.** Candidate ownership precedes reservations; reservations precede placement; routing and both exporters consume the same transformed terminals. No exporter should rediscover roles or mirror only strokes. Shared glyph drawing and ordered terminal tables must remain the common native/plugin source of truth. Retain every logical MOS body/X formal for netlisting even when an electrical merge hides a redundant visible lead.

The [pose witness](ports_pose.py) proves a roomy integer construction exists. In normalized units the triangle is `(-6,-6), (-6,6), (6,0)`. Signed tips are `(-8,±2)`, output `(8,0)`, supply `(0,-8)`, and ground/bias1–4 occupy `(-4,8), (-2,8), (0,8), (2,8), (4,8)`. Each auxiliary lead starts on its own sloped-body attachment. Across pitches 1/2/3/4/5/20, four rotations, two reflections and two signed orders, all 96 frames have nine distinct tips, nonintersecting leads and body-behind-tip support. This proves feasibility, not preferred dimensions or final label spacing. It does not claim those VSS coordinates were present in source ink.

## Required RED tests and change radius

| Independent oracle / named case | Current failure or forbidden mutation | Future owner and keep controls |
|---|---|---|
| Exact raw tuple + source body, AG1674/2212 and extra AG1242 | Four-bias contracts remain boxes under the eight-port cap | Shared glyph contract; ordered nine terminals in both front ends; keep all genuine boxes |
| Actual clock strokes, AG3492/3493/3495 and extra AG808 | Complete clocked comparators remain boxes | Shared role/lead drawing; reject unknown clock-like controls and preserve AG3495's five-port count |
| Paired permutation moving output to index eight | `?u3` cannot represent the valid output index | Bounded port-index API and compiler-listed callers; unrelated index widths unchanged |
| Literal semantic-order coordinates | Whole y-reflection moves supply and bias4 | Glyph variant/geometry policy; both signed marks and corresponding tips move, raw bindings never swap |
| Source regulator input order, original exact 39 | Default negative-above does not match positive-above regulator pose | Local regulator owner; sampling negative-above keeps AG2658/2665/789 |
| Source biased sample geometry, AG2637/2657/2757 | Existing separate amplifier admission rejects bias roles | Local admission plus actual-frame reservations; keep the 32 plain shard positives and extra AG789 |
| All-pin incidence mutations listed above | Old necessary selector accepts 21 unsafe variants | Raw candidate owner; exact old positive name sets remain checked |
| Literal two raw candidates / one eligible | Eligibility-first filtering creates false uniqueness | Candidate collection before caller filtering; order permutations agree |
| Wrong SVG object, swapped marker labels, moved real conductor | Cached association could certify another body or wrong auxiliary binding | Research provenance boundary; source bytes and literal expected body identity checked |
| Native/plugin round trip against raw tuple | Stroke-only edits or dropped VSS/body terminals alter connectivity | Shared terminal/export ownership; independent netlist-back comparison, not visual similarity |

Three likely future changes should remain local: adding an evidenced exact family alias changes only the role/family boundary; choosing a different signed-order policy changes only candidate policy/variant selection; changing a canonical control lead changes only shared glyph geometry and its frame certificate. Compiler-listed callers handle the deliberate index-width change. A policy change must not require duplicated exporter geometry or another raw-net parser.

The research proofs themselves run green against fixed literal/mutation oracles. Production RED cases above remain planned failures against the unchanged native artifact; this study does not claim they passed an implementation test.

## Reproduction and limits

From the repository root:

```sh
python3 -B docs/research/image-rules/round-2/ports_contracts.py --check docs/research/image-rules/round-2/ports_contracts.json --output /tmp/ports-contracts-replay.json
python3 -B docs/research/image-rules/round-2/ports_predicates.py --check docs/research/image-rules/round-2/ports_predicates.json --output /tmp/ports-predicates-replay.json
python3 -B docs/research/image-rules/round-2/ports_pose.py --check docs/research/image-rules/round-2/ports_pose.json --output /tmp/ports-pose-replay.json
```

The source contract proof binds all 2202 raw decks, relevant source SVG/JSON inputs, transitive helper scripts and its own bytes. Its graph joins actual segment endpoints and T junctions, with a literal proper-crossing negative control. It is a bounded certificate for these source assets, not a general-purpose electrical extractor. The actual label spelling dictionary is explicit. It preserves the source cache disagreement as data and the AG3492 support failure as a pose boundary.

The full-corpus extension names are seven; detailed own-lead contracts are five; assigned fresh image coverage is 734 pairs; enlarged extra-corpus review is three more pairs. Keeping these scopes separate prevents a visual overview, a raw match, or one successful source certificate from being mistaken for universal layout admission.
