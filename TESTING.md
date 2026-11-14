# Testing cktImg

The engine translates SPICE connectivity into placed symbols, wires and
names. Electrical correctness, valid geometry and agreement with a human
source drawing have separate oracles. A schematic can preserve every net
through labels while differing from the source's physical wire groups.

Run local builds inside `nix develop -c` for the pinned toolchain. Serialize
Zig processes and keep at least 6 GB available memory, as required by
[AGENTS.md](AGENTS.md). Check command exit codes; output alone is not a pass.

## Commands and coverage

| Check | Command or entry point | Independent oracle |
| --- | --- | --- |
| Format | `nix develop -c zig fmt --check src tests tools build.zig build.zig.zon` | Zig formatter. |
| Engine, API, C ABI, plugin and JSON tests | `nix develop -c zig build test -Dlatex_renderer=false --summary all` | Literal geometry, electrical connectivity, no shorts, parser examples, caller contracts and recorded source relations. |
| TikZ option enabled | `nix develop -c zig build test -Dlatex_renderer=true --summary all` | The same contracts with renderer code included. |
| Shared-query codegen | `nix develop -c zig build test-codegen` (also in `test`) | Runtime-input helper/direct assembly on fixed x86_64_v3 ReleaseFast; identical direct callees, no hidden tail wrappers, accepted static comparison and literal residue mutations. |
| Random netlists | `nix develop -c zig build fuzz` | 4,000 deterministic cases checking electrical connectivity, shorts, dots, honoured hints and reversed-card determinism. |
| Gallery | `nix develop -c zig build gallery -- --svgs out/` | Exact example names, reviewed SVG changes and the corresponding source figures. |
| Plugin | `nix develop -c zig build -Dschemify_plugin=true` | Rebuild matches committed `cktimg.wasm`; size is strictly below 563,200 bytes. |
| Real editor round trip | `python3 tests/roundtrip.py <schemify-bin-dir> [deck ...]` | Schemify imports, netlists back and compares with `spicecmp`; omitted decks mean the complete fixture list. |
| Full source corpus | [corpus-scorecard.md](docs/research/corpus-scorecard.md) | Exact source names and hashes, independently measured wire metrics and named structural relations. |
| Rule-specific source evidence | Each research companion's documented `--check` command | Actual transformed SVG leads and conductor ink, complete named inventories and literal method mutations. |
| Driven-bank physical continuity | [driven_banks_connectivity.py](docs/research/figures/driven_banks_connectivity.py), with the explicit inputs documented in [driven-banks.md](docs/research/driven-banks.md) | Every stable terminal pair on changed nets across both complete corpora, compared with actual source conductor ink; every historical mismatch is checked by name. |
| Private bias peers | [bias_block_neighbors.zig](tests/bias_block_neighbors.zig) and the source/native/continuity companions in [bias-block-neighbors.md](docs/research/bias-block-neighbors.md) | Actual own-body leads, outward peer body, opposing collinear terminals, full pin incidences, caller precedence and source-supported physical wire groups. |

`zig build test` includes allocation-failure sweeps where the operation's
contract requires rollback or unchanged caller state. Its consumer suites
are wired explicitly in [build.zig](build.zig); a test file must be imported
before it contributes to the gate. Prospective unimported studies do not
count as passing tests.

The bias-peer allocation sweep forces growth through allocation/free so
opportunistic in-place resizing cannot change the set of failure points.
Its successful minimal circuit must independently satisfy the placement
oracle. The canvas sweep also checks that an allocation failure preserves
the existing route, segment and point rows, including their contents.

## Automated gates and checkpoint work

[ci.yml](.github/workflows/ci.yml) currently runs formatting, both test
configurations, gallery generation, the random-netlist suite, the
freestanding WASM library builds, C header validation and a real LaTeX
figure. Its separate Nix plugin job checks the committed artifact and size.
The workflow is the authority for what CI actually runs.

Full AnalogGenie/AMSNet comparisons, one-job versus four-job corpus replay,
research evidence replays, visual inspection and real Schemify round trips
are additional checkpoint checks. They are not currently CI jobs. Source
studies require the cached external examples; editor round trips require a
compatible local Schemify build. Record missing prerequisites as missing
validation, never a successful skip. No nightly coverage or performance
gate is claimed here.

Before accepting a layout change, reproduce its failing oracle, preserve
electrical and caller contracts, inspect whole-drawing effects and publish
the exact changed-name inventories. Run both test configurations, fuzz,
formatting, plugin rebuild and size checks. Compare affected corpus outputs
and reports with one and multiple jobs. Review gallery changes and exercise
the affected decks through the real editor when available. Checkpoint
measurements and remaining limitations belong in the
[corpus scorecard](docs/research/corpus-scorecard.md).

## Expected mismatches

Keep the source expectation separate from observed native behavior. A known
missing physical connection still expects source continuity; its exception
marker records that the current implementation disagrees. It does not turn
disconnection into the desired result.

Compare exact sorted names or maps, never only failure counts. Stable keys
identify the corpus, drawing, net and actual device-terminal pair. New
failures, missing inputs, unsupported correspondences and unexpected
resolutions all require review. A resolved marker is removed only after
the source oracle passes. Positive and negative source controls remain
separate from expected mismatches.

The corpus runner's `--expect-issues` checks invalid or unsupported source
data and engine findings. Physical source disagreements belong in their
own rule inventory, such as the
[wire-part connectivity study](docs/research/thin-connectivity.md), rather
than being hidden among source-input errors. Frozen research `--check`
commands compare provenance and evidence fields as well as names. Replacing
their expected files without checking the independent oracle is not a fix.

Aggregate improvement may justify a documented heuristic tradeoff, but it
does not remove individual regressions. Report source-agreeing and
source-disagreeing changes, their exact names, repeated-family dependence
and changes to other readability measures. Electrical equivalence and a
passing structural score do not certify human schematic equivalence.

The driven-bank continuity check replays the source readers and verifies the
complete input and reader hashes. It follows all 129 historical physical
mismatch markers and requires the three reviewed AG2436 repairs explicitly
through `--accept-resolved`; the other 126 remain recorded disagreements.
Unknown source correspondences and new source regressions fail the check.
Its nine source-supported joins do not certify symbol facing: the separate
native-facing inventory retains the exact three unmatched gate directions.

## Manual reference-amplifier continuity gate

[reference_continuity.zig](tests/reference_continuity.zig) is deliberately
unimported while these two recorded source regressions remain unresolved.
The repaired AG2436 gate tree now lives in the imported positive regression
[reference_gate_tree.zig](tests/reference_gate_tree.zig); it retains the complete
source DUT and requires one ink component joining X1.OUT, M1.G and MSEN.G.
The ordinary green test suites do **not** cover the two remaining failures.
The expected failure markers are the exact names in
[reference_continuity_failures.py](tests/reference_continuity_failures.py):

| Exact test name | Positive physical-source oracle |
| --- | --- |
| `reference continuity: AG2415 keeps the source VIN branch wire` | One ink component joins M1.S, MCHG.S and MRES.S. |
| `reference continuity: AG2428 keeps the source VIN branch wire` | One ink component joins M1.S, M4.S and M8.S. |

Both currently fail the `ink.connected` assertion with compaction;
electrical correctness and no-short checks pass in both compaction modes.
[The routing study](docs/research/reference-routing.md) records the source
ink and actual decisions. AG2434's source-separated VIN terminals remain a
negative research control, not a blanket positive bus expectation.

Run this separately, with no other Zig process active. The log checker
requires these exact failures at the physical-wire assertion. An unexpected
pass, missing case, unrelated failure or changed name fails the manual gate.
A successful **log check** means the known disagreements were reproduced;
it is not a source-continuity pass. Repair each case, remove its marker and
activate its positive test before claiming that source relation is covered.

```sh
cat > /tmp/reference-continuity-options.zig <<'EOF'
pub const latex_renderer = false;
pub const zon_config = false;
pub const c_abi = false;
EOF
if nix develop -c zig test --dep NetlistParser \
  -Mroot=tests/reference_continuity.zig --dep build_options \
  -MNetlistParser=src/root.zig \
  -Mbuild_options=/tmp/reference-continuity-options.zig \
  --test-filter 'reference continuity:' \
  > /tmp/reference-continuity.log 2>&1; then
  reference_status=0
else
  reference_status=$?
fi
python3 -B tests/reference_continuity_failures.py \
  /tmp/reference-continuity.log --exit-code "$reference_status"
```
