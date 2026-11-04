# Steering the layout

Research, November 2026. The question: how can an AI agent get **full
freedom** over every decision cktImg's layout makes, from what the circuit
means down to where each wire runs, while the drawing stays **clean**? Four
research passes fed this: the engine's own decisions
([decisions.md](decisions.md)), constrained layout in other systems, LLMs and
schematics, and how to measure a clean drawing. Nothing below is built yet
except the `*@` grouping hints (#7); [skill/](skill/) drafts the agent skill
that uses it.

## The answer

1. **A ladder of six rungs**, from saying nothing to pinning a route. Every
   decision the engine makes can be stated on some rung, and an agent mixes
   rungs freely, device by device and net by net.

   | rung | the agent says | example |
   |---|---|---|
   | 0 | nothing; names carry the meaning | `Vdd vdd 0 1.8` |
   | 1 meaning | what the circuit is | `*@ group pair M1 M2`, `*@ role vb1 bias`, `*@ symmetric M3 M4` |
   | 2 relations | where things stand to each other | `*@ row M3 M4`, `*@ order M3 M5 M4`, `*@ gate M1 left`, `*@ label vb1` |
   | 3 cells | a device's lattice cell | `*@ cell M5 2 4` |
   | 4 geometry | exact coordinates and orientation | `*@ at M5 120 340 R90` |
   | 5 wires | a net's exact route | `*@ route tail 100,300 140,300` |

2. **The engine answers in the same language.** Its report lists each
   decision as the `*@` line that would force it, each request as honoured,
   relaxed, dropped or rejected (with the reason and the lines that blocked
   it), the hard gates, the quality scores, and a text grid of the placement.
   An agent copies a line, edits it, puts it in the deck. Feeding a deck its
   own decisions back draws the same picture: a free oracle at every rung.

3. **Clean has two tiers.** Hard guarantees (every net one piece, no wire on
   another net's point, no symbol on another, dots exactly where wires
   meet, ...) are
   never broken: an override that would break one is refused, never
   repaired. Quality (crossings, bends, detours, symmetry, flow, labels) is
   reported as separate scores, never summed, each finding with a location
   and a fix written as a `*@` line.

4. **Rank decides conflicts, never an average.** The hard guarantees are
   not negotiable; a `*@` line is strong; a `weak` line is a stay, kept
   unless something stronger needs the room; the engine's own decisions are
   tentative and lose every conflict. The project's style (`lint.zon`) sets
   costs, not constraints. Every line is honoured or reported; none is
   dropped in silence.

5. **The agent descends the ladder.** It starts at rung 0, reviews the
   report and the image against the book's look, and fixes each complaint on
   the highest rung that can: meaning before relations, relations before
   cells, cells before coordinates.

## 1. Why this shape

**LLMs state relations well and coordinates badly.** Every study that
compared the two found a solver placing relations beats a model writing
positions:

- Holodeck's relational constraints: 0.706 human preference against 0.364
  for LLM coordinates ([Yang et al.](https://arxiv.org/html/2312.09067)).
- R3L: 0 % collisions against 4.3 % ([R3L](https://arxiv.org/html/2605.06758v2)).
- SchGen: pin coordinates instead of pin names drop connectivity from 49 %
  to 15 % Jaccard ([SchGen](https://arxiv.org/html/2605.30345v1)).
- A deterministic layered layout with a connectivity check verified 100 % of
  Schemato's benchmark, where the fine-tuned LLM compiled 76 %
  ([Weave](https://arxiv.org/pdf/2607.03835)).

Rungs 1 and 2 are where an agent should live; rungs 3 to 5 are the escape
hatch, still checked.

**Feedback has to name the pin.** Localized feedback (error type plus
pin or net) reached 92.7 % against 58 % for pass/fail on medium tasks
([PCBSchemaGen](https://arxiv.org/html/2602.00510v1)). Self-correction
without an external checker does not help
([Huang et al.](https://arxiv.org/abs/2310.01798)); with one it does
([Kamoi et al.](https://aclanthology.org/2024.tacl-1.78/)). Hence the report's
per-request and per-finding records.

**Models are poor judges of drawings.** LLM judges agreed with humans on
schematic correctness at Cohen's κ ≈ 0
([MultModLM](https://arxiv.org/pdf/2606.27666)), the best LLM matched human
graph-drawing preferences 33 % of the time against 38 % between humans
([paper](https://arxiv.org/html/2604.03417)), and VLMs count line
intersections at 42–57 % ([paper](https://arxiv.org/html/2407.06581v6)).
"Clean" is computed, never judged by a model; the image is advisory.

**Loops degrade fast; keep them short.** Chained netlist edits fall from 80 %
at 3 steps to 26 % at 15 ([NetlistBench](https://arxiv.org/html/2608.12197));
even near-perfect feedback plateaus
([Feedback Friction](https://arxiv.org/abs/2506.11930)). The skill stops after
three rounds that fix nothing.

**Plain text and one CLI beat a large tool surface.** An agent editing KiCad
files directly got 18 of 18 single edits right against 3 of 18 through a
100-tool MCP server ([mcp-server-kicad](https://github.com/ProductOfAmerica/mcp-server-kicad)).
The `*@` lines live in the deck the agent already writes; one command draws
and reports.

**Text plus image beats image alone** for models reading graph drawings
([paper](https://arxiv.org/html/2505.03678)); the report carries a text grid
of the placement beside the SVG.

**Layout engines have answered "user constraints over automatic layout"
for decades, the same way.** Each gives a small vocabulary per stage of its
pipeline: ELK's layer constraints, in-layer predecessor and successor, port
constraints from `FREE` to `FIXED_POS`, and a fixed layout
([ELK options](https://eclipse.dev/elk/reference/options/org-eclipse-elk-layered-layering-layerConstraint.html));
Graphviz's `rank=same`, `group`, `ordering` and neato's `pos="x,y!"`
([rank](https://graphviz.org/docs/attrs/rank/)); yFiles' layer and sequence
constraints with a hint per node from free to exact coordinates
([IncrementalNodeHint](https://docs.yworks.com/yfiles-html/api/IncrementalNodeHint)).
What they share, and what cktImg takes:

- **The user's constraints beat the engine's own.** ELK reverses edges
  before it breaks a layer constraint
  ([source](https://github.com/eclipse/elk/blob/master/plugins/org.eclipse.elk.alg.layered/src/org/eclipse/elk/alg/layered/intermediate/EdgeAndLayerConstraintEdgeReverser.java));
  ACA marks the user's constraints definite and its own tentative, and on a
  conflict always gives up a tentative one
  ([Kieffer et al.](https://users.monash.edu/~mwybrow/papers/kieffer-gd-2013.pdf)).
- **Conflicts are settled by rank, never averaged.** A constraint of one
  strength completely dominates every weaker one
  ([Borning et al.](https://link.springer.com/article/10.1007/BF01807506),
  [Cassowary](https://constraints.cs.washington.edu/solvers/cassowary-tochi.pdf));
  yFiles discards lower-priority constraints
  ([LayerConstraintData](https://docs.yworks.com/yfiles-html/api/LayerConstraintData));
  Apple's Auto Layout breaks one constraint of a conflicting set and still
  lays out, and advises few, clustered priorities
  ([Apple](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/AutolayoutPG/ConflictingLayouts.html)).
- **Few systems say what they dropped.** libcola reports each unsatisfiable
  constraint and the compound constraint it came from
  ([UnsatisfiableConstraintInfo](https://www.adaptagrams.org/documentation/classcola_1_1UnsatisfiableConstraintInfo.html));
  ELK clamps an out-of-range layer without a word
  ([layerChoiceConstraint](https://eclipse.dev/elk/reference/options/org-eclipse-elk-layered-layering-layerChoiceConstraint.html)),
  and users of its interactive mode "wanted to have more information why this
  movement was not allowed" ([Petzold et al.](https://www.scitepress.org/Papers/2023/118030/118030.pdf)).
  The report is where cktImg can do better at little cost.
- **Round trips exist, but half.** ELK exports each node's layer and place in
  it and reads them back, recomputing coordinates
  ([generatePositionAndLayerIds](https://eclipse.dev/elk/reference/options/org-eclipse-elk-layered-generatePositionAndLayerIds.html));
  Graphviz replays coordinates with no intent
  ([neato -n2](https://graphviz.org/doc/info/command.html)). Exporting
  relations as constraints and geometry as *stays* ("things should stay where
  they were unless there is some reason for them to move": Cassowary) gives
  both.
- **Rules over sets are short.** SetCoLa's rules over node sets cut what
  users write by one to two orders of magnitude, each derived constraint
  keeping the rule it came from
  ([SetCoLa](https://jhoffswell.github.io/website/resources/papers/2018-SetCoLa-EuroVis.pdf)).
- **No analog schematic generator offers graded overrides.** tscircuit saves
  drags as positions ([manual edits](https://docs.tscircuit.com/guides/tscircuit-essentials/manual-edits));
  SKiDL's generator places by forces and says its schematics "still need
  improvement" ([skidl](https://github.com/devbisme/skidl/blob/master/docs/generating-editable-schematics-2023-07-14.html));
  ASG checks its xschem output netlists back identical
  ([ASG](https://woset-workshop.github.io/PDFs/2020/a13.pdf)), as
  `tests/roundtrip.py` does.

## 2. What the engine decides

[decisions.md](decisions.md) lists about 120 decisions across seven stages,
each with the data that holds it and its cheapest injection point. Today an
agent can steer only: net roles (the Zig API's editable `roles`, not the C
ABI or the plugin), `*@ group/nogroup/grouping off`, `*@ expand`, block port
sides, the symbol library, and the names it writes.

The seam to open first: `sketch.lay` builds the structure and the skeleton
itself, so nothing can stand between the stages. Split it into
`analyze → place → draw`, and give each stage's owner a **request table**
keyed by device and net name (never card index, so one picture per circuit
holds), validated at the edge so a bad request returns a refusal instead of
reaching an assert.

Overrides that need new algorithm work, not just a table
([algorithms.md](algorithms.md) has an algorithm for each, its guarantees,
cost and conflict report):

- a forced row order that closes a cycle with column links (a joint
  link-and-row pass with a conflict report);
- same-row requests that `levels.level()` refuses silently today;
- a one-sided override on a symmetric circuit (mirror it, or drop that
  pair's mate and report);
- collisions from forced cells (validate, or shift outward like bridges);
- more bridges between two columns than the seven slots (a variable spread
  per channel);
- off-lattice nudges (per-device offsets in `coordinates()`, checked);
- patterns that do not exist (a ground bar, a single port for an input net,
  a wired bias line with three gates);
- pinned routes on mirrored nets (`routes.mirrored` copies only its own
  segments);
- "always a wire, never a label": possible by growing channels between
  lattice rows and columns (in both directions; rows alone are not enough),
  which moves nothing to another row or column, except where pinned
  coordinates sit on both sides of every cut: there it is reported;
- per-instance `expand` and port sides;
- a driver drawn inside the circuit (R3 is recomputed at three sites).

## 3. The vocabulary

[vocabulary.md](vocabulary.md) has every line, what it decides, what it is
checked against, and how `--decisions` exports it, then maps each of the
~120 decisions in decisions.md to a line or to why it needs none: a style
setting, a guarantee, derived, or a search whose result the lines pin. In
brief, by rung:

| rung | lines |
|---|---|
| 1 meaning | `role`, `kind`, `class`, `group`, `nogroup`, `grouping off`, `symmetric`, `axis`, `symmetry off`, `driver`, `expand` |
| 2 relations | `row`, `above`, `order`, `group stack`, `upright`, `bridge`, `face`, `label`, `wire`, `port`, `rail`, `first` |
| 3 cells | `cell` |
| 4 geometry | `at`, `refdes` |
| 5 wires | `via`, `route` |
| any | `weak <line>`, a stay |

Lines sit at the deck's top level, or in a `.subckt` for the Schemify import
(which already carries group hints into a cell, and would keep editor edits
in a sidecar: [schemify.md](schemify.md)). [figures.md](figures.md) shows the
vocabulary reaching every golden figure.

**Style is not a hint.** How every drawing looks is the project's, set in
`lint.zon` beside the lint rules: the `.layout` lengths and router costs,
built in #9 (`stack`, `series`, `rail`, `terminal`, `label`, `tap`,
`clearance`, `bend_cost`, `cross_cost`), and later styles such as a ground
rail instead of a symbol per branch.

## 4. Semantics

- **The guarantees are not constraints.** A request that would break one is
  rejected, never weighed against anything. Labels can always connect a net,
  so the only request that can fail for want of room is "draw this net as a
  wire": it falls back to labels and says so.
- **Three strengths.** A `*@` line is *strong*: honoured unless it breaks a
  guarantee or loses to a stronger or later line. A line starting `weak`
  (`*@ weak cell M5 2 4`) is a *stay*: kept unless something stronger needs
  the room. The engine's own decisions (recognized blocks, the symmetry,
  pattern wires, every heuristic) are *tentative*, below `weak`, and lose
  every conflict. `lint.zon` preferences are costs, not constraints: they
  shape the engine's choices and never refuse a line.
- **Validate, then admit in a fixed order.** Unknown names, a cell off the
  lattice and a malformed route are *rejected* before layout, nothing
  changed. The rest are admitted strongest first, the later line first
  within a strength, each if it holds together with those already in and with
  the guarantees, else *dropped*. Rows, columns and order are difference
  constraints, so a conflict among them is a cycle in the order graph, and
  the cycle names the lines that block. A request met only in part (a row
  out of range, a cell taken) is *relaxed*, with its residual; nothing is
  clamped in silence.
- **Honoured or reported.** Every line ends in the report as `honoured`,
  `relaxed`, `dropped` or `rejected`, with a code, the residual, and
  `blocked_by`: the preferred conflict, the stronger lines (or the
  guarantee) that with this line cannot hold, no proper subset blocking it
  (Junker's; a line blocked by two separate cycles is admitted by no single
  removal, so "removing any one would let it in" cannot be promised). Each
  member is flagged `alone` when deleting it by itself would admit the line. An independent checker reads the finished
  `Placed` and tests every `honoured` line (`row a b`: the same y), so the
  engine cannot claim what it did not draw. This is the overrides' oracle,
  beside fuzzing random hints over random netlists with every guarantee
  checked.
- **Fixed point.** `--decisions <rung>` prints the drawing's decisions on
  that rung: meaning and relations (rungs 1 and 2) as strong lines, cells,
  coordinates and routes (rungs 3 to 5) as `weak` stays, so an edited line
  moves only what it must. The deck plus its own decisions draws the same
  picture and prints the same lines, every line honoured; shuffling the lines
  changes nothing. Run over the textbook, golden and fixture decks and the
  4000 random netlists.
- **Mates mirror.** A line on one of a mated pair applies to both,
  mirrored; two lines that contradict each other's mirror drop the pair's
  mate, reported. The mirror guarantee holds for the mates that remain: the
  symmetry is the engine's tentative decision, which a line outranks.
- **Complete by construction.** The decision kinds are one closed enum, and
  the export switches over it exhaustively: a new engine decision without a
  line to state it is a compile error. A stage whose decisions are all
  pinned searches nothing.
- **One picture per circuit.** Lines are keyed by name and admitted in a
  fixed order; nothing else steers the output. The card-order tests run with
  hints too.
- **Units are the engine's.** Cells are lattice cells, coordinates and
  routes are in symbol units, so a deck's lines mean the same with any symbol
  set.

## 5. The report

`cktimg-json --report r.json` (and the same record from the C ABI and the
plugin's log) carries:

- `gates`: the hard guarantees, each pass or the records that fail it;
- `requests`: each `*@` line by line number: its state (`honoured`,
  `relaxed`, `dropped`, `rejected`), code, residual, and `blocked_by` with
  each member's `alone` flag;
- `overridden`: the engine decisions and stays the lines displaced;
- `decisions`: per rung, the lines that would force today's drawing;
- `metrics` and `findings`: the scores, and one record per problem;
- `grid`: the placement as text, one row per lattice row.

Each finding is shaped like a SARIF 2.1.0 result
([spec](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)):
rule, tier, location (coordinates and lattice cell), the objects by name,
the measured value and its bound, a fix as a `*@` line, a fingerprint from
the rule and the names (stable when unrelated things move), and its state
against the previous report (new, unchanged, updated, absent). A text form,
one line per record, follows `lint.format`:

```text
hard symbol_overlap devs=M5,M6 at=(240,120) fix="*@ cell M6 6 4"
soft detour net=n3 at=(180,60) len=14g hpwl=6g ratio=2.33>1.5
soft symmetry pair=M3,M4 off_axis=2g fix="*@ symmetric M3 M4"
summary hard=0 crossings=3(+5 rail) bends/conn=1.2 detour.max=2.33[n3] sym=6/6 flow=14/15[M7] labels=+[]
```

## 6. Clean, measured

Measured on the finished `Placed`, independent of how it was drawn: a check
the drawing code disagrees with is a bug in one of them.

**Hard guarantees** (never emitted; an override that would emit one is
refused):

| id | guarantee | today |
|---|---|---|
| H1 | every net one piece, grouping pins as the netlist does | tests only (`support.expectConnected`, `tests/roundtrip.py`) |
| H2 | no wire on another net's point | while drawing (`Canvas.fits`), tests (`support.shorts`) |
| H3 | no two nets' wires overlapping along a line | while drawing |
| H4 | no wire through a symbol's body | while drawing only |
| H5 | no symbol overlapping another | **missing** (tests compare anchor points only) |
| H6 | dots exactly where a net has three or more arms, and where a net crosses itself (joined there) | checked on every drawing (`support.dots`, #9) |
| H7 | dropped: four-way junctions stay, with their dot. Horowitz and Hill forbid them and KiCad's ERC warns, but the owner's reference figures draw them (the two-stage op-amp's output node in the notes), and 93 points in 33 drawings are drawn so today | — |
| H8 | no dangling wire end or label | **missing** |
| H9 | Manhattan, well-formed segments; every pin with company touches its net | tests only |
| H10 | one picture per circuit, the same bytes for the same deck | tests |

**Scored qualities**, each scale-free (counts, ratios to a bound, fractions
of relations that hold), reported side by side so trading one for another
shows: S1 crossings (signal and rail apart), S2 bends per connection, S3
detour (length over the net's half-perimeter bound), S4 polarity and flow,
S5 symmetry (from the circuit's mirror map, not the picture's), S6 alignment
of recognized groups, S7 nets split into labels, S8 clearance (wires and
text), S9 compactness (reported, never rewarded), S10 the golden figure's
score where one exists.

Crossings matter most in graph drawings
([Purchase 1997](https://link.springer.com/chapter/10.1007/3-540-63938-1_67),
[2010](https://doi.org/10.1109/tvcg.2010.269)), then path length and
straightness ([Ware 2002](https://doi.org/10.1057/palgrave.ivs.9500013)); but
domain conventions beat generic aesthetics (an early schematic generator held
"regularity, symmetry, and tidiness are more important than the minimization
of crossovers, bends, and path length":
[Jehng et al. 1991](https://scholars.lib.ntu.edu.tw/server/api/core/bitstreams/3f42ecd5-fc48-4b38-b397-618156a8f351/content)),
so the textbook figures, not weights from the literature, set the bounds.
Drawings rank by hard findings first, then the scores, never a weighted sum
([Deb's feasibility rules](https://doi.org/10.1016/s0045-7825(99)00389-8)).

## 7. The skill

[skill/SKILL.md](skill/SKILL.md) is the agent's side, written first so the
interface fits it: write the deck so names carry meaning, draw at rung 0,
review against [skill/CHECKLIST.md](skill/CHECKLIST.md), fix each complaint
on the highest rung that can, read every refusal, stop after three rounds
that fix nothing. Its leading words are *ladder*, *rung*, *descend* and
*complaint*. It ships as `skills/cktimg/` with the slices that make its
commands real, and grows a rung at a time.

## 8. Slices

1. **Preferences**: the `lint.zon` `.layout` table and `place(gpa, cfg, ...)`
   again (keeps #8's promise that the `lint.zon` lengths stay). Built in #9.
2. **Dots** (H6): checked on every drawing, and a net crossing itself
   joined there with a dot. Done in #9 (d684634); four-way junctions stay,
   dotted, as the book draws them.
3. **The seam**: `analyze → place → draw`; one net-order table; one driver
   table; validators at the edge.
4. **The report**: the gates as checks on `Placed` (H1 to H10, the tests'
   checks moved into the library), the scores, `--report` and `--decisions`
   for rungs 1 and 2, the text grid; the fixed-point test.
5. **Rungs 1 and 2**: admission with preferred conflicts first
   (algorithms.md §1), then every verb, the honoured-or-reported checker,
   random hints in the fuzz, and the 30 lines of figures.md as the
   acceptance test. Built: every rung-1 and rung-2 verb, the report's
   `requests` checked against the drawing, `--decisions 2` with its fixed
   point, random lines in the fuzz; every golden figure in full with 21
   lines, none on rung 3 (`tests/steering.zig`).
6. **Rungs 3 to 5**: pinned coordinates and routes through `Canvas.commit`
   (§5), mirrored routing by the union of blockages (§6), forced cells with
   stays (§2), then channel growth for `wire` (§3), the largest change.
   Built: `cell` with stays, `at`, `refdes`, `route` and `via` through
   `Canvas.commit`, rung 3 and 4 exports with their fixed point, mirrored
   routing leaving pinned nets alone. Not built: the union of blockages
   (§6) and channel growth (§3). Measured first: of the 25 bias nets the
   golden and textbook decks draw as names, a `wire` line wires 1 by its
   patterns, and growing every stack and series length (×1.5, ×2.25) wires
   none, so the room a wire lacks is not spacing; §3's targeted cuts are
   the next step when a deck needs one.
7. **The plugin** (built): the designer's device names in the engine deck (ends its
   instance-order dependence), every hint and role carried through.
8. **The skill grows** a rung per slice: `skills/cktimg/` shipped in #9 for
   names, group hints and the `lint.zon` lengths, and grew with each slice
   to rungs 0 to 5, `requests` and `--decisions`; the draft in
   [skill/](skill/) stays as the research record.

## 9. How we will know

The engine tests (the fixed point, the honoured-or-reported checker, random
hints in the fuzz) show the lines work. Whether an agent can use them is a
separate experiment, with the golden figures as its tasks:

- **Task:** a golden deck, and its figure as text (each device's row,
  column and gate side) or as an image. An agent with the skill must reach
  the figure's full score, every relation agreeing, with no guarantee
  broken.
- **Measured per task:** rounds; lines written, and on which rungs; lines
  refused; the final score; guarantees broken (must be none).
- **Compared:** the engine alone (rung 0); the agent pinning every device's
  coordinates (`at` only: the "model writes positions" approach the
  literature finds worse); the agent descending the ladder.
- **Measured so far** ([figures.md](figures.md)): lines reach every golden
  figure's full score, 30 lines over the 14 figures (1 on rung 1, 25 on
  rung 2, 4 on rung 3; six figures need none), predicted by a transcription
  of the scorer and the row and gate rules that reproduces today's drawings
  exactly. No figure needs what a guarantee forbids. That settled seven
  semantics, now in vocabulary.md (`order` splits links, `symmetry off`
  drops every mate, bridges take `row` and `order`, `cell`'s frame, the
  ground drop yields, lines on mates mirror, a chained `above`).
- **What would falsify the design:**
  - the ladder taking more rounds than pinning coordinates;
  - a figure no line reaches (the vocabulary is incomplete: a new kind);
  - a refusal the agent cannot act on (the report lacks information).

## 10. Found on the way

Fixed in #9 (d84bc30): a symbol unit under four tripped the router's assert;
natural-order ties (`m01`, `m1`) fell back to card order; ALGORITHM.md had
device columns four lattice columns apart instead of eight.

Open:

- A net's trunk could cross one of its own pin's lines without a dot,
  reading as two nets crossing (the fuzz found it; fixed in #9, d684634).
- The Schemify import names devices `<letter><row>`, so its drawing depends
  on instance order.
- Mate equalities in `levels.rows` are accepted greedily in device-index
  order (no failing case found).
- Reference designators are placed in card order, and keep a colliding spot
  when every candidate collides.
- Model-name polarity (`symmetry.polarity`) and the drawn class
  (`library.className`) disagree on names like `lvtpch`.
- The ground drop looks at net 0, not every sink.
- Exported terminal symbols lose their stub's direction.
- Leads onto off-line pins and the driver islands' wires are drawn without
  `Canvas.fits`.
- Lint's `label_fallback` lists deliberate labels too (bias, drivers).
- A net standing in one column that does not fit there never tries a trunk.
- The C ABI cannot pass roles.

## 11. Open questions

- Do the preferences land in #9, before it merges, or first after it?
- Sets of devices in one line (`*@ row kind:pmos`, `*@ group mirror M3*`):
  SetCoLa's gain is large, but every selector is more grammar to keep. Add
  them when a deck needs one, after rung 2.
- Does the skill ship in this repository, in the skills collection, or both?

Settled by the research: no strict mode (a failed line still yields a clean
drawing, and the report says why; the agent decides), and engine units for
rungs 3 to 5.
