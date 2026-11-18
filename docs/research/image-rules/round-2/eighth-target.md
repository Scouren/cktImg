# Eighth round: existing-host body and PFD round trips

Five actual imports and nine named component comparisons pass on an existing,
hash-bound Schemify host/plugin pair. The generated body labels preserve the three
tested private-body nets. The PFD exports preserve the declared formal and call
order with and without `PININFO`, while the generated symbol sides differ.
`spicecmp` alone does not certify the ordered interface of this empty PFD:
swapping its inputs or outputs still compares equivalent. The independent proof
therefore checks complete ordered exported cards and formal declarations too.

This is a bounded target execution, not a native/plugin geometry equivalence or
an engine implementation. It supplements the previously source-only plugin
boundaries in `sixth-bodies.md`, `seventh-review-bodies.md`, and
`sixth-symbols.md`. Relevant current rules are the existing ordered terminal,
body ownership, no-connect, explicit pin-side and caller-precedence contracts;
the proposed implementation packages must keep their electrical, geometry and
presentation oracles separate.

## Executed artifacts and version boundary

The binaries under `iteration21-resume1/host-target/debug` match the hashes in
the successful recorded `feedback-host-all-command.json` (104 earlier decks,
exit 0). This study executes those existing files; it does not rerun that old
suite or compile anything.

| Artifact | SHA-256 |
| --- | --- |
| `schemify` | `9e400edd678b5423f779e4a5a9c33fe443a0c23882f24798f3e55739ede05bc9` |
| `spicecmp` | `5d97d5d6318667061fe0eecb853bc624baa29d01aa2bf2f13346f19f74e32018` |
| `feedback-native/cktimg.wasm` (578948 bytes) | `843fa0c9c916d6357bff40b9b3e3e2714134274465568c790345a63415863c4d` |
| plugin manifest | `133e2e663e4e4d3d49b9cbaba22e024c6e7c66083971e4b070fa8b9e32576e73` |

The module is the older **feedback-native** artifact. The native study uses the
different `bf7b0749...` executable. A module also exists in that native snapshot
(`8dd54881...`), but this study does not infer a matching build from directory
co-location. `layout.zig` and `recognize.zig` have identical full bytes between
the feedback and frozen native source snapshots; that supports the inspected
mapping explanation, not universal compiled equivalence. The input manifest
retains both snapshots' relevant source hashes and the original host build/source
provenance. The host's inspected XDG-directory implementation matches the recorded
host source-manifest entry.

Every host command ran under a fresh `/tmp/cktimg-eighth-target-*` project with
isolated XDG config, cache, data, state and runtime directories and a copied plugin
manifest/module. No current project or user package store was used. The exact
command argv, exit codes, stdout/stderr, full input hashes, original decks,
generated records and raw exported netlists are archived under
`.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/groups/eighth-target`.

## Exact scope and actual result

| Imported source | Named comparisons, all exit 0 | Additional direct certificate |
| --- | --- | --- |
| `one_body_peer.cir` | `dut` | `M1 d g s b nm`; `R1 b 0 1k m=1` |
| `two_body_peers.cir` | `dut` | M1/M2 both retain distinct D/G/S and shared B=`b` |
| `two_bodies_and_resistor.cir` | `dut` | Both MOS bodies and R1's first terminal remain `b` |
| `sixth-symbols-pfd-base.cir` | `pfd`, `dut`, `inverter` | Exact XPFD/formals; all four symbol pins right |
| `sixth-symbols-pfd-pininfo.cir` | `pfd`, `dut`, `inverter` | Same exact XPFD/formals; A/B left, QA/QB right |

The 29 executed commands comprise one package sync, five imports, five model-bench
netlists, nine component netlists and nine `spicecmp` calls. Model declarations
used for comparison come from the actual host-exported bench. The original source
decks are copied unchanged. Complete original and exported rows, including model,
behavioral expressions, values, parameters and ordered terminals, are retained.

All three body cases produce the actual four-pin `spice_nmos4.shprim`: D at
`(20,-30)`, G at `(-20,0)`, S at `(20,30)`, B at `(20,0)`. The generated primitive
contains the visible body stroke from `(0,0)` to `(20,0)`. Its hidden routing policy
does not erase that primitive ink. In the two-body case the actual B contacts are
`(40,30)` and `(100,30)`, with a `b` label at each. These are separate from the
coincident native custom-library contacts in the sixth-round figure. No serialized
`nc` appears in these three component records. Actual host netlisting preserves
the body connectivity, so these examples do not support an electrical-failure
claim.

The base PFD's actual symbol declaration is ordered A/B/QA/QB, each `inout`, at
`(60,-30)`, `(60,-10)`, `(60,10)`, `(60,30)`. With explicit `PININFO`, A/B are `in`
at `(-60,-10)`, `(-60,10)` and QA/QB are `out` at `(60,-10)`, `(60,10)`. Both raw DUT
exports are byte-identical and contain `XPFD A B QA QB PFD` plus
`.subckt PFD A B QA QB`. This proves a presentation difference on this target,
without assigning direction semantics to the unannotated source.

## Executed controls and proof boundary

| Mutation or control | Actual result |
| --- | --- |
| Change exported M1 B from `b` to `s` | `spicecmp` exit 1 |
| Delete the resistor-side `b` label in an isolated copied host project; netlist again | Netlist exit 0; R1 first net becomes `net_6z6bns_0`; comparison exit 1 |
| Swap XPFD A/B in the actual export | `spicecmp` exit 0; ordered raw-card proof rejects |
| Swap XPFD QA/QB in the actual export | `spicecmp` exit 0; ordered raw-card proof rejects |
| Delete XPFD from the actual export | `spicecmp` exit 1 |

The empty PFD's successful comparisons are therefore insufficient alone. A future
interface change must pass both the target round trip and complete ordered
call/formal preservation. Do not replace the target comparator with a geometric
pin-side check or infer interface identity solely from its equivalence verdict.

`eighth-target-proof.py` independently enforces pass status, every command and
comparison exit code, exact ordered command/component name inventories, exact
artifact inventory, file hashes, actual exported model context, independently
reconstructed comparison probes, literal complete raw export rows and the actual
symbol pin rows. It rejects eight saved-status/inventory mutations and two changed
actual exports even after those changed bytes are rehashed. The original five
cases and exact six comparator/host-control outcomes remain required. Unsupported
cases do not silently disappear from the named inventory.

The initial runner stopped after its first successful import because the old
helper classified the plain-text SPICE title as a device in the model bench.
That failed research guard and its logs are preserved under
`groups/eighth-target-initial-title-guard`. The corrected runner retains the whole
bench and copies only actual exported declaration lines into component comparisons.
This is a study-runner correction, not a host/plugin defect or an unreported retry.

## Replay

Saved execution and independent proof checks (no host writes):

```sh
python3 -B docs/research/image-rules/round-2/eighth-target-run.py
python3 -B docs/research/image-rules/round-2/eighth-target-proof.py \
  --check docs/research/image-rules/round-2/eighth-target-proof.json \
  --output /tmp/cktimg-eighth-target-proof.json
```

The independent proof is the saved-evidence gate. The runner's read-only mode
checks bindings and reports status; its exit code alone is not that gate.
The executed provenance records the original `--execute` and `--execute-controls`
paths. Those modes require unused archive directories and refuse to overwrite
prior evidence. The current artifacts remain unimplemented research evidence;
no source, plugin module, production test or build was changed.
