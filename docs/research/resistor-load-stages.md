# Resistor-loaded differential stages

This is a bounded source study with placement and local load-tree implementations
under validation. A full
census of 2,202 AnalogGenie and 734 AMSNet drawings selects exactly three stages:
AG1048/M19, AG1052/M8 and AG1052/M12. These are correlated examples in two
figures, not evidence for every resistor load or differential amplifier.

The selector follows electrical incidence before looking at source geometry:

- A known four-terminal PMOS has D=G, S=B on a supply, and a nonrail load net.
  That net has exactly the two PMOS incidences and two distinct resistors.
- Each resistor's other end reaches one unambiguous known NMOS drain. Raw
  competing channel devices count before model filtering. The two NMOS have
  distinct D/G/S nets, different gates, a shared nonrail source, and the same
  ground body net.
- The common source has exactly three incidences: both source terminals and
  one known NMOS tail drain. The tail returns S=B to the same ground.
- All six devices are distinct. Output nets may have remote gate incidences;
  their full lists are retained. Names, values, source coordinates and figure
  IDs do not select a stage.

The portable [reader](figures/resistor_load_stages.py) replays actual transformed
SVG leads and primitives, verifies every declared terminal binding, and retains
source hashes and the entire local Python import closure. The frozen
[inventory](figures/resistor_load_stages_cases.json) contains the complete census,
all three frames, every selected local tree, and the full visible-terminal
physical partitions of both figures.

## Source observations

All three stages have the same 13 relative predicates: the diode load's source
is above its drain; both resistors stand vertically downward on matching rows;
each resistor output is above and collinear with its own NMOS drain; the two
NMOS channels point down on matching rows and their gates face outward; the
load drain lies between their channel columns at or above the resistor tops;
and the downward tail lies below their sources and between their columns.

Those predicates alone do not express locality. The nominal occupied envelope
of each six-device source group is disjoint from every foreign source glyph's
nominal envelope. The source group bounds are `[190,-20,330,240]` for AG1048/M19,
`[220,-140,340,90]` for AG1052/M8 and `[450,-140,570,90]` for AG1052/M12. These
numbers record evidence; they are not proposed engine spacing constants.

Every group has three literal straight conductor intervals: the common
resistor top bar, and each resistor output to its own NMOS drain. Each of the
six output endpoints also has its own drain as the unique nearest actual
same-net terminal by Manhattan distance. The inventory retains every competing
terminal, distance and physical connection independently; this observation does
not prescribe a routing distance threshold. The common-source/tail tree bends
in the source. It must be connected, but no straight source-tip bar is required.

There are twelve positive **local** trees: four per group, with exact terminal
sets of sizes 4, 2, 2 and 3. The source reader proves them using actual conductor
ink and actual junction dots. Labels do not connect pieces. A negative named-net
result is accepted only if the whole actual conductor scene also has no path;
a missing cached stroke cannot manufacture a separation.

Full output incidence is deliberately separate:

| Stage | Output | Source physical pieces |
|---|---|---|
| AG1048/M19 | Vout1 | R1.2, M15.D |
| AG1048/M19 | Vout2 | R2.2, M16.D |
| AG1052/M8 | net9 | R1.2, M9.D, M13.G |
| AG1052/M8 | net15 | R2.2, M10.D, M14.G |
| AG1052/M12 | vM2 | R3.2, M13.D; separately M16.G |
| AG1052/M12 | vP2 | R4.2, M14.D; separately M17.G |

The complete scene certificate also retains intentional VDD, VOP and VON
partitions. Joining every terminal with the same electrical name is not the
source oracle. MOS body leads absent from the actual source and the four
unshown inverter VDD/VSS leads remain explicitly named unknown geometries;
their electrical card bindings are preserved, but no physical position is
invented.

Envelopes cover nominal actual symbol primitives, including transformed circle
extrema. They are not stroked pixel extents, font bounds, labels or an assertion
about arbitrary caller typography. All selected source symbol primitives are
supported; an unknown primitive fails the reader.

## Linked-stage boundary

AG1052's M8 stage feeds its two outputs into the M12 stage's two gates, while
M11 and M15 share the VB2 bias net. The engine recognizes a generic automatic
bank of those two tails. The actual source instead gives the two complete
stages separate local reflection axes (x=280 and x=510), matching D/G/S tail
rows, and both tail gates facing left. The union of all twelve source bodies
is also free of foreign glyphs. M11.G and M15.G remain two separate physical
VB2 pieces. These observations are recorded separately in `linked_stages`;
no common wire follows from common bias or row equality.

The approved placement plan therefore distinguishes a six-member single owner
from a coordinated twelve-member linked owner. A source-specific layout may
refine the generic automatic bank and single-axis arrangement while retaining
the graph mate identities. Honoured caller symmetry/group/pose constraints,
external mates and unsupported crossing blocks still prevent the whole owner.
The existing drawing mirror check must validate actual physical axes; no mate
mapping is silently deleted to force admission.

## Independent tests and current status

[tests/resistor_load_stages.zig](../../tests/resistor_load_stages.zig) is currently
unimported. It uses complete literal DUTs, with the same weak external-role
projection as the corpus runner. Its public `np.place` checks use actual
transformed terminals and full class bounds, with separate geometry/locality,
local-tree and straight-corridor tests. Generated Placed rail/port symbols have
empty device names; only those non-source symbols are omitted from the foreign
glyph envelope check. Real device names are not filtered by prefix.

The first trusted resumed run is saved under
`.objective/human-schematic-equivalence/runs/iteration21-resume1/resistor-load-red.log`.
Two literal-method tests pass; three public tests fail on AG1048/M19: M1 lies
inside the stage envelope, net3 has disconnected physical pieces, and the
resistor top-bar interval is absent. This separates locality from coarse axis
checks. Gap, wrong-net and bent-tail controls verify that labels cannot pass the
physical oracle and that connectivity does not imply straightness.

The initial six/twelve-member prototype passes six of seven focused public
tests: source geometry and clear nominal envelopes, all twelve local trees,
linked axes/shared rows, and separate VB2 pieces. The remaining test requires
the literal resistor-top bar. Its actual tips are on one row, but the generic
trunk places the bar ten units above them. Generic trunk.13 deliberately
forbids perpendicular branching at a pin tip. This source exception requires
a separately reviewed complete-stage tree request. A literal four-tip test
first proved that the source paths fit ordinary Canvas contact checks, then
failed its straight-bar assertion after ordinary trunk routing. Its independent
foreign-endpoint/proper-crossing controls passed on all four segments.

The new `resistor_load_wires` consumer uses only successful placement owners,
current automatic internal nets, and exactly the four declared actual tips.
It rejects projected, hidden, absent, duplicated or extra pins and caller
styles, ports, routes or first-net sequencing. The bar, drain branch and
outward gate branch are checked through Canvas and committed atomically.
Ordinary thinning still applies; later cut/label rounds do not seed this tree.
Generic trunk rules and ranking remain unchanged. Focused consumer, expanded
public/custom-frame and full-corpus validation remain pending.

The private placement safety suite now passes both tests, including six/twelve
rollback and collection allocation failures. Valid registered hidden body
terminals are accepted; visible unsupported extras abstain. A valid long-lead
class at an extreme representable origin abstains before coordinate overflow.
The zero-terminal case is explicitly defensive private-table corruption after
proving that `Library.register` rejects such a public class; its trusted RED
was an early terminal read, now guarded before access. Clamp-anchor members and
read-only stage anchors are electrically adjacent but device-disjoint from all
three selected resistor-load stages; this is not permission to move the clamps.

## Data and replay

The six data answers for this research transform are:

1. Borrowed source decks, actual SVG geometry and terminal schemas become a
   topology census, coordinate predicates and physical-ink certificates.
2. The input census contains 2,936 drawings. Only two scenes need full glyph
   and pairwise physical evidence; three selected six-device rows result.
3. Python stores exact indices without a new fixed-width engine contract.
   SVG decimal coordinates are retained with the source readers' explicit
   numerical tolerance. No new runtime layout type is introduced here.
4. Decks are scanned in fixed corpus/name order; complete actual SVG scenes
   are read only after topology selection. All fields of each cold evidence
   row are consumed together when serializing its certificate.
5. Data lives for one script run. The output is review evidence, not retained
   engine state or a runtime lookup table.
6. Different scenes could be replayed independently; this reader deliberately
   uses fixed sequential order. No speed or runtime-residue claim is made.

Run from the repository root:

```sh
python3 -B docs/research/figures/resistor_load_stages.py external/examples \
  .objective/human-schematic-equivalence/runs/iteration21-resume1/resistor-load-replay.json --check
```

The frozen source replay has 22 named method checks. It compares every evidence
field and every census name, not just counts. The earlier `/tmp` native studies
were lost at restart; their numerical descriptions are historical leads only.
A fresh checkpoint20/current native comparison is required before claiming any
new native improvement or regression measurement.
