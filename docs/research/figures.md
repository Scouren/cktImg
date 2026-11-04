# Every golden figure, reached by lines

The empirical test of full freedom ([steering.md](steering.md) §9): can
`*@` lines make cktImg draw each of the 14 golden figures exactly, as
`tests/golden.zig` scores them, without breaking a guarantee? Yes. 30 lines
in all: 1 on rung 1, 25 on rung 2, 4 on rung 3. No figure needs something
the guarantees forbid.

The verbs are not built, so the effect of each line is predicted, not
measured. The prediction is a Python transcription, in [figures/](figures),
of the golden scorer (`tests/golden.zig`) and of the rules for rows, mates
and gate sides (`levels.rows`, `skeleton.mates`, `skeleton.gates`). Both
transcriptions reproduce what the engine draws today exactly: all 14 score
lines, from the skeleton's cells and from each layout's dump, and every
deck's rows and gate sides. Each set below was run through them, scored, and
checked against the invariants. Removing any one line breaks the score or an
invariant, so none is redundant.

## The lines

Six decks already match their figure: `ota_5t`, `fd_two_stage`,
`telescopic_fd`, `cascode_mirror`, `diff_pair_resistive`, `telescopic_se`.

| deck | today | lines | why |
|---|---|---|---|
| two_stage_pmos | rows 6+0-4 | `cell Rc 19 2`, `cell Cc 21 2` | the figure sets the compensation network level with the input pair; the engine puts bridges on channel rows |
| folded_cascode | y 44/50, gates 2/10 | `above M9 Iss`, `above Iss M7`, `above M7 M1`, `above M1 M3`, `face M3 g left`, `face M4 g right`, `face M5 g left`, `face M6 g right`, `face M7 g left`, `face M8 g right`, `face M9 g left`, `face M10 g right` | the tail current source below the top mirror; every outer gate facing out, where the bank rule turns pairs inward |
| strongarm | y 38/46 | `above M3 S3`, `above S3 M5` | the reset switches between the latch's two rows |
| gilbert | x 34/36, y 28/29, gates 4/6 | `symmetry off`, `order RD1 M1 M5 M2 Iss M3 M6 M4 RD2`, `above RD1 RD2`, `face M2 g left`, `face M4 g left` | the figure's own asymmetries: RD2 drawn lower, all four gates left |
| cmfb_two_stage | x 70/74 | `cell R3 4 5`, `cell R4 28 5` | the sense resistors between the stages, where the engine spreads them inside the pair |
| bandgap_ptat | gates 5/6 | `face Q3 b left` | Q3's base, on ground, turned away from the middle |
| wide_swing | y 16/19, gates 4/5 | `above Iin Ibias`, `above Ibias M4`, `above M4 M5`, `above M5 M3`, `face M5 g right` | the bias device between the mirror's rows |
| beta_multiplier | gates 4/5 | `face M5 g left` | M5 turned toward its gate net's mean column |

Each predicted score is the figure's full one, for instance
`folded_cascode x 43/43 y 50/50 rows 5+0-0 cols 12+0-0 sym 6/6 gates 10/10`.

## What the lines need from the vocabulary

No new verb, but these semantics, now in [vocabulary.md](vocabulary.md):

1. **`order` splits links.** Devices one `order` line names stand in
   different columns, so a column link the engine chose between them is
   dropped (gilbert: RD1 is linked into M1's column today).
2. **`symmetry off` drops every mate**, the blocks' as well as the
   symmetry's (gilbert: keeping the blocks' mates puts them about three
   axes, which the mirror guarantee refuses).
3. **Bridges take relations.** `row` puts a named bridge on that device row;
   `order` puts it in the channel between its neighbours. Then
   `row M1 Rc Cc` and `order M7 R3 M1` reach two_stage_pmos and
   cmfb_two_stage on rung 2 instead of rung 3.
4. **`cell` takes any row for a bridge**, and its frame is fixed: the
   skeleton's own, before it shifts the drawing to start at 0, so moving the
   leftmost device does not renumber the rest.
5. **The ground drop yields** to a strong `above` or `row` (wide_swing: the
   drop as built lowers M5 onto M3's row and breaks `above M5 M3`).
6. **A line on one mate mirrors onto the other.** `face M3 g left` on a
   mated pair also turns M4's gate right; two lines that contradict each
   other's mirror drop the pair's mate, reported. That cuts folded_cascode
   to 8 lines, and settles how the tentative symmetry meets the guarantee
   that mates mirror exactly: the guarantee holds for the mates that remain.
7. **Optional:** a chained `above a b c ...`, one line for folded_cascode's
   four.

## What lines cannot reach

Proportions. Lattice rows are uniform, so a figure's small offsets (RD2 0.3
cm below RD1, Iss 0.48 cm below M9 and M10) become whole rows. The score is
scale-free, so it does not see this; only rung 4 (`at`) reproduces a
figure's spacing.

## Rerun it

From `docs/research/figures/`: `./capture.sh` refreshes the engine's
scores, cells and dumps from the gallery built at the repository root (the
files committed were captured at c03c677); `python3 score.py` checks the
scorer transcription against them (mismatches 0); `python3 hints.py` scores
each set (decks failing 0); `python3 negative.py` removes each line in turn
and shows the ground drop as built; `python3 checks.py` checks every
orientation edge (83, none reversed by a figure). When the verbs land, these
30 lines become the acceptance test against the engine itself, and the
transcriptions go.
