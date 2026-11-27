# Resume the human schematic layout work

Stopped on November 17, 2026. **The last verified implementation commit is `cf4cf226`. PR #22 is open against `main`. The next checkpoint is AG517, already staged in the PR worktree.** Keep each layout change in its own commit so its native and Schemify drawings can be compared with the previous version and the hand layout. The user chose to keep the PR open. [PR #22](https://github.com/Scouren/cktImg/pull/22) · [Comparison gallery](https://github.com/Scouren/cktImg/tree/feat/human-pattern-series/docs/research/production-patterns)

## Pick up AG517 first

On the original workstation, open `.claude/worktrees/human-pattern-series` inside the cktImg checkout. The outer checkout is on `feat/analoggenie-mos-paths` and contains separate research edits. In the PR worktree, AG517 has 14 staged source, test and gallery files. Its rebuilt `netlist-import.wasm` is unstaged and measured 545,677 bytes. The cumulative test run was interrupted. The staged changes are the starting point.

On a fresh machine, fetch the implementation and recovery branches. The recovery snapshot preserves the exact uncommitted topic tree and the individual feature patches. To resume just AG517 from the pushed PR, use the following commands in a clean checkout.

```sh
git fetch origin feat/human-pattern-series checkpoint/pr22-handoff
git switch feat/human-pattern-series
git show origin/checkpoint/pr22-handoff:docs/research/production-patterns/recovery/patches/nested-bank.patch > /tmp/cktimg-ag517.patch
git apply --3way --index /tmp/cktimg-ag517.patch
git diff --cached --stat
```

Rebuild the guest and run the cumulative gates below. Compare AG517 with `cf4cf226`. Check the input pair is left of all four switches and the inner source columns remain between the outer columns. Export the actual editor drawing and round-trip its 15 devices and 12 nets. The isolated comparison changed only AG517 across 5,274 decks. The cumulative result, guest and gallery link still need to be committed together. [AG517 original redraw](https://github.com/Scouren/cktImg/blob/feat/human-pattern-series/external/examples/analoggenie/ag-517.svg) · [Saved patches and exact bases](https://github.com/Scouren/cktImg/tree/checkpoint/pr22-handoff/docs/research/production-patterns/recovery)

## What is already on the PR

| Checkpoint | Verified result |
|---|---|
| `4c7c3a12` → `13fa838a` | First 25 commits. Of 5,274 native drawings, 144 changed and 5,130 matched. The initial gallery and rule coverage document those endpoints. |
| `e1e924f4`, `329821ae` | Exact editor segment contacts and deterministic ordering. The size change saved 26,904 guest bytes with identical corpus drawings and 93 identical guest event transcripts. |
| `e723a5e2` | AG1079 and AG1080 gained preamplifier rows above the latch on both targets. Only those two corpus drawings changed. |
| `b0f36ed9`, `7dee840c` | Automatic MOS body contacts and a C query for a physical pin. Sixty-four drawings changed with zero new geometry findings. Ten editor DUTs retained 516 ordered MOS terminals. |
| `cf4cf226` | Shared amplifier frames. Eight real editor fixtures passed. All 5,274 existing native drawings matched the preceding step. Both renderer configurations passed, with 468 and 469 tests respectively. The guest measured 540,819 bytes. |

## Remaining checkpoints

The measurements below belong to individual experiments. Confirm them again on the combined branch and record both improvements and costs.

| Work | Where to resume |
|---|---|
| AG1093 folded switch bank and interleaved groups | After AG517, apply `folded-bank.patch`, then `interleaved-controls.patch`. AG1093 met all seven source placement relations on both targets. Native crossings fell from 12 to 9 and editor crossings rose from 5 to 7. Preserve the named overlaps in AG1016 and AG364. |
| P24 caller requests | `opamp-steering.patch` follows the interleaving tests. On AG762 a rejected row request used to move M1 and remove seven placement decisions. The fix preserves the ordinary drawing for rejected requests and still honors an accepted strong position. |
| AG493 capacitor orientation | `capacitor-frames.patch` adds eight oblique two-terminal symbols. Only AG493 changed in the isolated corpus. All 32 ordered contact coordinates matched the source within rounding. Bends fell from 21 to 14, and net0 became labelled pieces. The recovery directory includes the reference and four exported comparison images. |
| P21/P23 feedback wiring | `diagonals-in-progress.patch` is based on `329821ae`. The optional `--allow-45` variant changed AG90, AG600 and AMS-Net 244. On each, crossings stayed at one and bends rose from five to six. Both prototype renderer suites passed, and the actual AG90 host export preserved all five MOS devices. Reconcile the native and editor hooks, publish the four gallery SVGs with their source, and rerun the cumulative tests. |
| AG1146 grouped controls | Apply `control-bus.patch` for the host, followed by `native-control-bus.patch` for native `--bundles`. The editor went from eight to five visible varactor contacts with a byte-identical exported DUT. The native option retains the four scalar identities, slots and coordinates. Check the declined cases with extra consumers or permuted pins. |
| P04 amplifier facing | AG1237 and AG1349 are two conversions of the same published figure. Coordinating both neighbors produced straight 40-unit control links in native trials. AG1242 already has one. A production selector and actual-host proof for the coordinated placement remain open. The recovery snapshot contains the trial inputs and outputs. |
| Other boundaries | Mixed uses of one Schemify definition still share one editable symbol. Publication-only panel numbering, general four-device ownership ambiguity and a universal feedback orientation remain open questions. The rules and contrary cases are recorded in the original plan. |

## Verify and recover

```sh
nix develop -c zig fmt --check src tools tests build.zig build.zig.zon
nix develop -c zig build -Dschemify_plugin=true
nix develop -c zig build test -Dlatex_renderer=false
nix develop -c zig build test -Dlatex_renderer=true
nix develop -c zig build gallery -- --svgs /tmp/cktimg-gallery
wc -c netlist-import.wasm
```

The guest must be smaller than 1,048,576 bytes (1 MiB). Keep a copy of each native binary before advancing, then run `docs/research/production-patterns/compare_corpus.py BEFORE AFTER REPORT.json`. For actual Schemify round trips, use `python3 tests/roundtrip.py <directory-containing-schemify-and-spicecmp>`. GitHub Actions was disabled during these checkpoints, so use the recorded local gate results. [Detailed handoff and gallery evidence](https://github.com/Scouren/cktImg/blob/feat/human-pattern-series/docs/research/production-patterns/HANDOFF.md) · [Original rules and contrary cases](https://github.com/Scouren/cktImg/blob/checkpoint/pr22-handoff/docs/research/image-rules/round-2/proposed-human-rules.md)

The local recovery archive is under `$(git rev-parse --path-format=absolute --git-common-dir)/cktimg-pr22-handoff/latest`. It includes the complete original round-two study. The remote copy includes source patches, named validation artifacts and SHA-256 checksums. The original workstation gallery runs on port 8783. Reuse the existing worktrees. At merge, remove the finished task worktrees after confirming their work is included. [Portable recovery manifest](https://github.com/Scouren/cktImg/blob/checkpoint/pr22-handoff/docs/research/production-patterns/recovery/manifest.json) · [Open local gallery](http://127.0.0.1:8783/docs/research/production-patterns/)
