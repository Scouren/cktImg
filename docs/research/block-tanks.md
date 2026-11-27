# A center-tapped tank beside paired block outputs

AG1103 contains one unique center-tapped coil and parallel capacitor across
one block's declared `OUTP`/`OUTN` terminals. The actual source block is a
rectangle. Its attached output leads face right at `(460,30)` and
`(460,70)`; the capacitor terminals are `(480,30)` and `(480,70)`; the coil
ends are `(520,0)` and `(520,100)`, with its tap at `(540,50)`. The three
actual midpoint rows agree. The capacitor lies between the block and coil,
the named net order agrees, and the tap points away from the block.
The output-terminal separation need not equal the winding length.

[The source audit](figures/block_tanks.py) reselects all nineteen complete
center-tap contracts over the complete source corpora. It freshly replays
the existing actual coil/tank and DA/PA box-lead certificates. The exact
selected name is `ag-1103:x1:xl1--c1`; every other CT selection result is
retained in the [inventory](figures/block_tanks_cases.json). The two block-to-
coil paths and the two capacitor-to-coil paths use verified actual SVG
conductors and actual contact dots. Equal labels cannot establish a path.
VSS remains an explicitly unobserved source terminal, and DA/PA remain
rectangular blocks. No new amplifier glyph follows from this study.

The candidate selector does not use a circuit ID, family name or device
name. A complete CT has distinct nonrail outer nets and a distinct tap.
Exactly one CT and one capacitor occupy that outer pair. Exactly one other
block touches both nets, counted before testing its named roles; both nets
occur once on that block and bind its unique `OUTP` and `OUTN` declarations.
Other outer-net incidences must be capacitors. Thus a duplicate block with
unknown pin roles, another CT or capacitor, a tied output, an extra active
load, or an input pair excludes the candidate. AG1146 has another block on
both CT outer nets but lacks the required parallel capacitor.

Names only select a candidate. Geometry must independently prove two
visible, attached, cardinal, same-side output leads that exit their own
body and agree with the actual terminal-side metadata. The block's body
must remain behind both tips. A different caller frame may be supported
only if it passes these actual-frame conditions. The nineteen named method
checks include topology mutations, wrong output sides, wrong named end
order, a skewed coil, a displaced midpoint, a capacitor beyond the coil,
a tap toward the block, and all eight rigid poses plus translation.

This is one correlated source observation. It supports relative geometry,
not a universal block-load convention, a particular distance, or a routing
exemption. In frozen placement-c the block's output tips are `(1770,50)` /
`(1770,90)`, while the coil ends are `(2400,240)` / `(2500,240)` and the
capacitor is centered at `(2450,200)`. The existing tank owner correctly
relates capacitor to coil but deliberately retains the coil's world pose.
The missing relation is to the actual output frame. Several remote
coupling-branch paths also regress; this source certificate does not claim
that moving the tank repairs them.

## Implemented ownership and current validation

A separate cold `block_tanks` owner borrows `coil_tanks.find` for the
unique passive pair. The block stays a read-only anchor. It owns the coil
and capacitor as a two-row transaction: orient the outer ends along the
actual output-tip span, match each named net, point the tap outward, and
center both passive parts on the output midpoint. A single body-derived
nearest placement, followed by quarter-unit steps through one additional
symbol unit if
occupied, must clear both bodies against the whole visible scene. No
coordinate or device row commits before all frame and collision checks
pass. A failure restores the original two rows and coordinates.

Collection belongs before relay, using admitted caller verdicts and fixed
coordinates. Explicit placement, grouping, orientation, shelf, net style,
port and route constraints retain ownership. Dropped or rejected hints do
not suppress the inferred group. Any existing mate or other active owner
must have a documented compatibility rule; blanket removal is not allowed.
The generic tank placement supplies the fallback. The specific owner runs
first and removes only its successful pairs from the generic request list.
Both passives keep the anchor block's transverse grid coordinate, while
their local midpoint offsets match the actual block-output midpoint offset.
Thus equal compactor tracks preserve three actual midpoint coordinates even
for shifted classes, without changing the block's device row. Three initially
strict actual output/capacitor/coil/tap orders use the existing compactor.

The first bounded placement declined the real source fixture: the next
ordinary PA block occupied every attempted position. A printing-only
public-test trace found X1 output tips at `(2120,50)` / `(2120,90)`,
X2's actual body at `x=2160..2260, y=0..140`, and the nearest grown coil
box at `x=2166..2213, y=10..130`. All four further quarter-unit attempts
still intersected X2. This is a recorded failed placement, not a repaired
physical path. The source puts X2 and reflected X3 on a lower folded row;
that separate global arrangement is not inferred by the local tank rule.

The fresh-lattice path now requests the nearest complete passive envelope
at the block's existing cell. `lattice_geometry` merges its numeric bounds
into the ordinary column/row room before symmetry equalization; it does
not insert cells or change signal ordering. All candidate frames are
restored after preflight, and future candidate boxes replace their stale
passive positions when checking the whole scene. Only an entirely clear
proposal commits. Otherwise the ordinary coordinates are used exactly and
the generic tank fallback remains. Both coordinate alternatives allocate
before any coordinate or pose write. Admitted fixed coordinates, relay
stays, and direct amplifier placement bypass this reservation. Empty
requests execute the original coordinate loops. The ordinary bounded
local attempt remains the non-reservation path.

Private oracles include a literal shifted-frame envelope
`(70,-51)..(130,69)`, rejection by a caller body extending beyond its lead
reaches, exact equality to ordinary coordinates after rejection, and every
coordinate-allocation failure. Two independent groups exercise both stale
passive overlap that must be ignored and future-peer overlap that must be
rejected, in both group orders. The root-run private suite passes all three
named tests (plus the imported module test). The complete source-frame test
and caller-precedence test also pass in both compaction modes.

The actual-attached-lead proof formerly in `bias_neighbors.leadSide` now
has its second consumer in `actual_lead.leadSide`. The extraction preserves its
first-body-intersection, filled/hollow disk, explicit-side and hidden-pin
checks; it must not merely expose `pinSide` or infer output direction from
a name. This cold geometry helper needs a pin-index width covering the
existing `u8` device-pin count, rather than the bias owner's smaller `u3`.
The extracted proof body matches the previous body exactly. No C ABI or
symbol-class change is made.

The six data questions for this owner are:

1. Inputs are the complete netlist/CSR, unique tank certificate, declared
   block bindings, actual class strokes, admitted requests, current poses
   and successful shelf/ownership state. Outputs are two device poses and
   immediate compactor-order requests.
2. At most one record per qualifying CT bounds collection. A record needs
   three typed device handles, three CT pin indices, two block pin indices
   and one capacitor end index. The cold record is asserted to occupy
   twenty bytes. A separate twenty-byte numeric room request holds a typed
   anchor and actual bounds; both have compile-time size checks.
3. No copied net, active flag, retained cache or per-route allocation is
   needed. Requests are cold and every record's fields are read together.
4. The draw caller owns allocation, placement order and freeing. Collection
   and all scratch reservation precede mutation; two original device rows
   and two proposed coordinates provide transactional stack scratch.
5. A failed frame, collision or allocation returns the fallback unchanged.
   Actual midpoint and strict outward ordering need existing-compactor
   requests; custom offset frames must test those relations after compaction.
6. The work stays outside routing-cost loops and makes no speed claim.
   Final WASM size, exact whole-corpus changes, physical source continuity
   and caller precedence still require measurement. The source-only audit
   is not evidence that a production implementation is green.

Independent tests are full literal AG1103 geometry in both
compaction modes; all five named placement-c source-connected losses as a
separate physical-ink gate; shifted/rotated caller classes and actual
ordered pin bindings; one held member holding the entire pair; literal
ambiguity controls; and whole-two-row rollback/OOM. The public suite's
literal source-oracle mutations and caller-precedence controls passed on
the pre-change implementation; actual geometry and local physical ink
failed. The full source frame and physical preservation expectations remain
unchanged. Private tests exercise eight transformed shifted frames, an
unsupported attached lead, a broad collision covering the bounded search,
and every collection allocation. Complete all-corpus validation remains a
separate gate; local geometry does not establish physical preservation.

The restarted frozen native and copied public diagnostic agree on every
actual terminal coordinate and every same-net declared card-pin pair in
both compaction modes. Both local block/cap/coil trees are continuous, and
the old `C1.0--Cblk3.0` source-connected loss is repaired. Four remote pairs
remain disconnected relative to checkpoint20 in both modes:

- `ag-1103:net19:cblk4.1--x2.4`
- `ag-1103:net6:cblk5.0--r5.0`
- `ag-1103:net6:cblk5.0--x3.3`
- `ag-1103:net6:r5.0--x3.3`

Fresh actual SVG lead/ink proofs confirm all four are source-connected.
The physical-preservation test remains red, while the other three public
tests pass. The complete pair audit also retains unchanged source
mismatches and unsupported source terminals; it makes no full-equivalence
claim. Raising only the crossing budget diagnostically reconnects all four,
which establishes thinning dependence without identifying a particular
greedy round or justifying a budget change. The remaining paths belong to
remote paired RC input branches whose source geometry is a separate study.

Replay without a build:

```sh
python3 -B docs/research/figures/block_tanks.py external/examples /tmp/block-tanks.json --check
```
