# Reproducing the production comparison

The comparison starts at upstream production `4c7c3a12` and ends at `e717a617`. The [gallery](README.md) identifies the behavior and source for each before-and-after pair. The editor symbol comparison also identifies the exact guest at each endpoint. For an isolated comparison, render the same converted deck on consecutive commits. To check the cumulative result, compare the two endpoints.

| Collection | Converted decks | Changed native JSON or SVG | Byte-identical native JSON and SVG |
|---|---:|---:|---:|
| amsnet | 734 | 16 | 718 |
| analoggenie | 2,202 | 113 | 2,089 |
| analogretriever | 2,238 | 12 | 2,226 |
| circuitthink | 100 | 3 | 97 |
| **All** | **5,274** | **144** | **5,130** |

Each of the 144 changed decks is listed with its original and final wire metrics. [Complete table of changed native drawings](changed-drawings.tsv)

The built-in geometry gates reported zero findings on all 5,274 decks at both endpoints. Whole-sheet crossings decreased in 5 decks and increased in two. AG1079 goes from 10 to 12 as the input-stage branches move together. AG439 goes from 1 to 2 as its PFD gets the published port sides. Across all decks the change in reported crossings is -8 and the change in bends is -12. The human-stage and electrical tests measure different properties. [AG1079 branches in the editor](common-control/README.md) · [AG439 contact sides](README.md#named-contacts-on-pfd-and-dac-boxes)

The native comparison records the binary hashes and all changed filenames, before/after wire metrics and gate findings, including changes that affect only a gate or metric. Each public CLI invocation reads the original converted netlist. To repeat it, save the earlier and later `zig-out/bin/cktimg-json` from `nix develop -c zig build` in their respective worktrees, then run this command at the repository root. [Comparison script](compare_corpus.py)

```sh
python3 docs/research/production-patterns/compare_corpus.py /path/to/before/cktimg-json /path/to/after/cktimg-json /tmp/cktimg-comparison.json
```

## Verification of the shipped outputs

The pinned Zig toolchain passed both renderer configurations and 4,000 generated netlists. The C header compiled standalone and both freestanding library variants built. A fresh build cache reproduced the same 560,520-byte Schemify guest, SHA-256 `3b5db244d874dc5cf5a716e4a026ca354b4f6f930919e1231a96f07d326a97de`. Its cap is 563,200 bytes. [Build and test commands](../../../TESTING.md)

The actual Schemify host exercised all 91 named release fixtures with those exact guest bytes. Eighty-nine round-tripped through the editor and its SPICE comparator, covering 98 independently compared exported units. The two expected refusals were `rstring_ladder.spice` (279 element cards) and `write_dac.spice` (280). The guest limit is 200. Three large fixtures (`gain_cell_array.spice`, `weight_tile.spice` and `async_ctrl.spice`) were allowed up to 90 minutes per command in the local debug host. The same comparison and acceptance criteria applied to every case. [Round-trip harness](../../../tests/roundtrip.py)

Additional target tests trace complete ordered cards and visible pins in the affected real-world circuits. The native generator comparison covers 5,274 converted circuits. These are separate populations. [Editor symbol comparisons](editor-symbols/README.md) · [Editor stage comparisons](common-control/README.md)

## Implementation checkpoints

| Step | Git commit | Behavior or comparison |
|---:|---|---|
| 1 | `6b42a6a0` | [Reciprocal MOS loads](README.md#differential-stages-with-reciprocal-mos-loads) |
| 2 | `14b69d8a` | [Bias taps](README.md#a-visible-bias-feed-between-two-gates) |
| 3 | `19a4b7cc` | Full LTO for the size-limited guest |
| 4 | `ba7e0279` | [Passive ladders and bridged Ts](README.md#passive-ladders-and-bridged-t-filters) |
| 5 | `aa27db47` | [Sampling diode bridges](README.md#diode-bridges-in-sample-and-hold-circuits) |
| 6 | `0e5c5140` | [Bias taps after ordinary routing](README.md#a-visible-bias-feed-between-two-gates) |
| 7 | `1a89b6df` | [Driven parallel LC filters](README.md#driven-parallel-lc-filters) |
| 8 | `2ba366fd` | [Signed regulator input order](README.md#signed-inputs-on-a-regulators-error-amplifier) |
| 9 | `568de198` | [Raw local-stage membership](README.md#identifying-local-stages-from-a-netlist) |
| 10 | `b0bfbc92` | Pinned Binaryen optimization of the installed guest |
| 11 | `337509a5` | [Output conductor partitions](parent-outputs.md) |
| 12 | `781711e5` | [Two input branches around a common tail](common-control/README.md) |
| 13 | `fe56ba45` | [Hidden MOS bodies and visible terminals](README.md#a-hidden-body-still-connects-to-its-resistor) |
| 14 | `561324f8` | [Four-bias amplifiers and clocked comparators](README.md#four-bias-amplifiers-and-clocked-comparators) |
| 15 | `60540d2b` | [Exact rounded-gate lead attachment](README.md#where-a-rail-lead-meets-a-rounded-gate) |
| 16 | `f0ed3cc2` | [PFD and DAC contact sides](README.md#named-contacts-on-pfd-and-dac-boxes) |
| 17 | `cddbf160` | [Requested tail axes and final mirrors](caller-symmetry/README.md) |
| 18 | `669cd2bf` | [Written series-stack order](caller-symmetry/README.md#written-order-of-a-series-stack) |
| 19 | `3e58dcbb` | [Caller placement and stage selection](../../../tests/parent_stages.py) |
| 20 | `5bb16db3` | [Caller routing and output partition selection](parent-outputs.md) |
| 21 | `eaa43ac1` | [Ordered source-degeneration attachments](source-regions/README.md) |
| 22 | `5d01f3cf` | [Horizontal two-arm source bridge](two-arm-bridge/README.md) |
| 23 | `5599f086` | [LaTeX, SVG and native JSON cell selection](common-control/README.md#the-same-circuit-as-a-latex-figure) |
| 24 | `e717a617` | Placement file organization and checked output equivalence |
