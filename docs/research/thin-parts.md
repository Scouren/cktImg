# Keeping the crossing budget local to each wired part

Iteration15 disconnects three source gate lines because thinning adds the
crossings of separate physical parts of a named net. A copied-source trace
proves the decision for AG2309, AG2318 and AG2319 with compaction enabled:
`VX` starts `cut`, its three physical parts cross respectively two, one and
zero nonrail wires, and `thin.name` promotes the whole net to `label` on the
sum of three. The next routing round replaces eight device terminals with
separate labels. No physical part exceeded the existing budget of two.

This is a bounded correction to the meaning of the `cut` budget. It does
not establish whole-drawing equivalence or justify retaining every gate
connection. The [exact inventory](figures/thin_parts_cases.json) retains
fourteen named runs, all actual thinning rounds, source terminal and ink
certificates, per-round physical parts, crossing multiplicity, greedy
choices, and unresolved cases. The activated tests have meaningful RED:
three literal cases fail and four pass; all three complete source fixtures
fail the compacted horizontal-interval requirement.

## Actual source and native evidence

The source verifier reads transformed SVG glyph leads, checks their declared
D/G/S/B bindings, and admits cached conductor segments only when actual SVG
ink supports them. It reuses the [interval study's source verifier](figures/trunk_rungs.py).
Labels never supply connectivity. Both deliberately disconnected sources
also remain disconnected in the complete SVG conductor graph.

| Source pair | Actual gate endpoints | Source ink | Iteration15 compacted decision |
| --- | --- | --- | --- |
| AG2309 `VX`, M11.G–M12.G | (280,20)–(320,20) | Straight, connected | `cut` → `label`, total 3; largest part 2 |
| AG2318 `VX`, M11.G–M12.G | (260,40)–(300,40) | Straight, connected | `cut` → `label`, total 3; largest part 2 |
| AG2319 `VX`, M11.G–M12.G | (250,40)–(290,40) | Straight, connected | `cut` → `label`, total 3; largest part 2 |
| AG2452 `VZ`, M34.G–M40.G | (200,220)–(170,160) | Bent, connected | `auto` → `cut`, then all six pins in one partition become labels |
| AG2376 `net0`, M4.G–M5.G | (70,600)–(130,600) | Straight, connected | `auto` → `cut`, then all four pins in one partition become labels |
| AG2274 `VN`, M5.G–M6.G | (30,200)–(360,200) | Disconnected | `auto` → `cut`, then the complete partition becomes labels |
| AG1411 `VB1`, M11.G–M14.G | (110,470)–(290,470) | Disconnected | Bias role; separate ports from round zero, never thinned |

In each compacted `VX` case the larger part contains M11.G, M12.G, M15.D,
M15.G and M9.D; the second contains M14.D and M16.G; the third contains
M7.D. Generated label pins are retained separately in the inventory and
are not counted as device terminals. The actual crossing points are:

| Drawing | Larger part, two crossings | Second part, one crossing |
| --- | --- | --- |
| AG2309 | `VY` (630,700), `VB2` (630,730) | `GATE` (800,500) |
| AG2318 | `net0` (520,680), `VB3` (520,710) | `GATE` (680,480) |
| AG2319 | `VY` (520,720), `VB3` (520,750) | `GATE` (680,520) |

Without compaction those three gate pairs are 160 units apart, beyond the
existing 120-unit gate/gate grouping limit. M12.G is already a singleton in
round zero; no thinning promotion occurs. Their exact named unresolved
status is retained. The public tests require electrical identity and no
shorts in both modes, but require this source interval only with
compaction. A separate placement/grouping change is needed for the other
mode; disconnection is not encoded as a desired test result.

AG2452 and AG2376 are also separate problems. Their connected automatic
net is first cut, then `wires.parts` treats a partition containing every
pin as a reason to label every pin. A per-part budget does not change that
routing branch. In AG2376, `V1` is removed first, reducing `net0` from five
crossings to four before its promotion. The recorded greedy sequence
matters; an overlay alone does not prove it.

A broad local mirror exception would be unsafe. The inventory proves a
literal mapping of six MOS devices and all 24 D/G/S/B bindings from AG2376
to AG2274 under uniform n/p and rail exchange. Their source gate pairs have
opposite continuity. This is a local counterexample only: neither a
whole-circuit isomorphism nor equal placement constraints is claimed.

## Policy and ownership

`thin.name` remains the sole owner of thinning styles. Automatic nets keep
the existing whole-net crossing budget. A cut net is eligible for further
thinning only when one physical connected component exceeds two nonrail
crossings. Among eligible nets, the existing **total** crossing count still
chooses the worst net, with the canonical rank breaking ties. Choosing a
net removes its whole contribution before recounting; eligible mirror
partners still advance with it. Rails, ports and explicit styles retain
their existing protection. No partial style or new routing API is needed.

Components come from actual same-net Manhattan segment contacts, not pin
partition numbers or Route array boundaries. Endpoint contact, T junctions,
collinear overlap and proper same-net X crossings all join. The last case
follows `dots.2`: the engine places a junction dot at every same-net proper
crossing before `Placed` splits the wire there. Foreign-net crossings do
not join. Exact closed interval overlap in both coordinates represents
these contacts; arbitrary tolerance is unnecessary. Route chunks connected
through any transitive chain must share the budget.

The data questions answered before production implementation, now reflected
in the candidate code:

1. **Transformation:** existing routes, net roles, canonical ranks, mirror
   handles and input styles become updated styles plus the existing changed
   result. Physical-component and crossing scratch are private to this call.
2. **Cardinality:** let R be route count, N net count and C the existing
   number of crossing records. Components are bounded by R. Segment pairs
   retain the current bounded nested route/segment scan; no per-pin graph
   or unbounded search is introduced.
3. **Widths:** net handles and total crossing counts keep their existing
   `u32` contract. Route indices use `usize`: the public Route slice has no
   `u32` length bound. A component eligibility counter needs only 0–3 and
   saturates at three in a `u2` array; it never replaces the full total used
   for ranking.
   Coordinates remain existing exact `f32` values. No shipped struct widens.
4. **Access:** route geometry supplies connectivity once; crossing records
   supply total and component counts during each existing greedy recount.
   Crossing records hold two `usize` route indices and derive net IDs from
   the routes. Separate dense scratch arrays hold `usize` parents, `u2`
   component counts and `u2` per-net peaks. Parent and component arrays are
   empty when no input style is `cut`. Native crossing records widen from
   two `u32` fields to two `usize` fields; WASM widths remain 32 bits.
5. **Lifetime:** caller allocator, one `name` call. All fallible collection
   and allocation precedes style mutation; failure frees every successful
   scratch allocation. No retained component graph or editor state exists.
6. **Parallelism:** geometry comparisons are independent, but union and
   canonical greedy selection have ordered dependencies. Keep a scalar
   implementation for this bounded change. No SIMD, speed or zero-residue
   claim is made; code-size change requires the actual release build.

The measured iteration16 WASM headroom before this change is only 474 bytes
under the strict 563,200-byte limit. An isolated equivalent sort change may
be measured separately if necessary; it must not be silently bundled with
this policy or presented as an unmeasured saving.

## Tests and provenance

The [literal unit tests](../../src/thin_parts_test.zig) distinguish separate
2+1 parts from one connected three-crossing part; exercise endpoint, T,
overlap, X and transitive X joins; reject a one-unit gap and a foreign-net
bridge; reverse vertices and route order; preserve total-count greedy
ranking, canonical tie order, rail exclusions, explicit wire styles and
mirror behavior. The total-ranking diagram has one eligible net with total
six/largest part three and another with total five/largest part five;
component-based ranking would incorrectly label both.

The [complete source tests](../../tests/thin_parts.zig) retain all source
models and 34/34/35 DUT cards, remove only the DUT wrapper, and add exactly
the CLI's weak `IBUF output` request. Every point of the named compacted
gate interval must have that net's horizontal ink, and the actual terminals
must physically connect. Labels, a U detour and foreign-net ink cannot pass.

The original diagnostic capture had HEAD `04ed02e6` plus uncommitted
iteration15 changes. Every one of its 57 copied source-file hashes has now
been verified against committed iteration15 `10def3a7`; the inventory states
both facts rather than identifying the dirty capture as clean HEAD14.
Only the copied `sketch.zig`, `thin.zig` and `wires.zig` receive printing
instrumentation. The baseline and trace executables produce byte-identical
geometry **and reports** in every one of the fourteen named cases. An
independent integer segment oracle reproduces the complete proper-crossing
multiset in every one of the 26 named actual routing rounds. A second
reviewer independently recovered the compacted VX parts and their 0/1/2
crossing counts from the raw segments.

Prepare a source-pinned copy outside the repository, then have the build
owner compile it. Preparation never builds or edits shipping source:

```sh
python3 -B docs/research/figures/thin_trace_prepare.py /tmp/cktimg-thin-trace15
nix develop -c zig build --build-file /tmp/cktimg-thin-trace15/build.zig -Doptimize=ReleaseSafe --prefix /tmp/cktimg-thin-trace15/out
python3 -B docs/research/figures/thin_parts.py /tmp/cktimg-thin-trace15 /tmp/cktimg-human-rules/iteration15-corrected/cktimg-json /tmp/thin-parts.json --check
```

The runner requires the frozen baseline binary; it never substitutes the
current shipping executable. It compares exact named evidence, source
hashes, trace-log hashes and both binary hashes. An artifact rebuilt with a
different compiler or debug path needs an explicit provenance update even
if all geometry and decision evidence agrees. The inventory retains source
SVG paths and hashes, every target terminal, actual source conductor paths,
per-round changes and greedy counts, physical parts, and the named negative
and unresolved cases. Seven named literal audit checks independently cover
the physical-contact flood fill; the Zig tests are its separate production oracle.
