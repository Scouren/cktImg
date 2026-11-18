# Third study: the 23 internal body-only circuits

**The same raw body topology has two source presentations.** Twenty-two of the 23 named circuits draw a dashed shared-body bridge; AG1236 omits it. All 23 frozen native drawings omit it. A default that exposes a meaningful shared well and a request to reproduce the author's omission are therefore different policies. Neither policy may change the electrical node, collapse B into S, or discard the fourth ordered terminal.

This study adds 23 actual enlarged source/native pair views and three actual source crop views. The [view ledger](third-bodies-views.json) records every ID, observation, pair hash, four original artifact hashes, presentation category, and exact physical-proof boundary. The examples are related circuit families, not 23 independent replications. The [proof](third-bodies-evidence.json) checks all 46 raw/cache/native D/G/S/B bindings and limits actual glyph/ink certificates to AG1236, AG1294, and AG2490. No engine change or compiler run was made.

## Exact observed census

Every listed net has exactly two raw incidences, both MOS B at ordered index 3. It is not a DUT formal and differs from each device's D, G, and S. All 46 selected devices use the declared `pch` model and source `pmos` glyph type. Their source sharing is separate from their body sharing. The raw census is complete over the DUT; the shared net is not declared floating merely because only bodies use it.

| Circuit | Ordered body owners | Body net | Source presentation |
|---|---|---|---|
| AG1236 | MP2, MP3 | net8 | Omitted |
| AG1294 | MP7, MP8 | net4 | Shared dashed bridge |
| AG1296 | MP4, MP5 | net6 | Shared dashed bridge |
| AG1297 | MP7, MP8 | net0 | Shared dashed bridge |
| AG1299 | MP7, MP8 | net6 | Shared dashed bridge |
| AG1307 | M15, M16 | net7 | Shared dashed bridge |
| AG1313 | MP7, MP8 | net7 | Shared dashed bridge |
| AG1319 | MP4, MP5 | net0 | Shared dashed bridge |
| AG1329 | M8, M9 | net1 | Shared dashed bridge |
| AG1335 | MP7, MP8 | net5 | Shared dashed bridge |
| AG1337 | M4, M5 | net3 | Shared dashed bridge |
| AG1343 | M13, M14 | net2 | Shared dashed bridge |
| AG1399 | M2, M3 | net5 | Shared dashed bridge |
| AG1404 | M10, M11 | net4 | Shared dashed bridge |
| AG2193 | M2, M3 | net3 | Shared dashed bridge |
| AG2285 | M3, M4 | net11 | Shared dashed bridge |
| AG2287 | M3, M4 | net4 | Shared dashed bridge |
| AG2315 | M3, M4 | net3 | Shared dashed bridge |
| AG2397 | M5, M6 | net1 | Shared dashed bridge |
| AG2463 | M12, M13 | net5 | Shared dashed bridge |
| AG2464 | M12, M13 | net5 | Shared dashed bridge |
| AG2490 | M12, M13 | net10 | Shared dashed bridge |
| AG2498 | M12, M13 | net2 | Shared dashed bridge |

No named-only or solid shared-body presentation was observed in this 23-case set. That is a bounded observation, not a ban on either representation. Actual own fourth leads were not certified for the other 20 cases. For the three representatives, both B points lie within actual filled channel polygons; none is an own line/polyline endpoint. The dashed bridge is a source-specific landing convention on the channel, not proof that the underlying generic glyph has four lead endpoints.

## The contrary source pair

AG1236's raw cards are `MP2 net2 VREF net1 net8 pch` and `MP3 net7 VFP1 net1 net8 pch`. AG1294's are `MP7 VX2 VREF net2 net4 pch` and `MP8 VA VFP1 net2 net4 pch`. Both have a separate shared-source net and a distinct shared body-only net. Swapping anonymous node names cannot choose the source style.

![AG1236 source crop: shared source, absent body bridge](figures/bodies/third-ag-1236-source-crop.png)

AG1236 has actual D/G/S endpoints matching the literal cards and source cache. Its cached B points are `[46,410]` and `[134,410]`, within the respective channel polygons. There is no actual conductor segment through either B point, no cached net8 wire segment, no literal net8 label, and no actual-ink path joining the B points. The solid arch above them is the separate source net1. This is source omission, not a cache route claiming ink that failed to render. The source author’s reason is unknown; the evidence does not establish that omission was intended or electrically conventional.

![AG1294 source crop: separate dashed body bridge](figures/bodies/third-ag-1294-source-crop.png)

AG1294 has actual channel-supported B points `[606,100]` and `[714,100]`. The source's `stroke-dasharray="3 3"` conductor contains the exact segment between those points, and the cache assigns that segment to net4. The source connection exists independently of the solid net2 source arch. AG2490 M12/M13 repeats the explicit presentation in a different large amplifier drawing, with B points `[106,190]` and `[234,190]` on net10. Its [enlarged crop](figures/bodies/third-ag-2490-source-crop.png) resolves the small bridge in the broad overview.

All 23 frozen CLI replays match the existing native gallery SVGs byte for byte. All 46 native device records retain the exact fourth body node in `bulk`; each visible glyph has three pins and no body-net wire record. This establishes a visual omission with preserved JSON identity. No C ABI execution or Schemify re-netlisting is claimed here, and no operating-circuit error follows from a no-connect mark or an unshown body.

## Conditional representation plan

The immutable terminal table remains authoritative: `(device, ordered terminal index, typed role, net)`, including every repeated occurrence. Presentation is a separate table resolved before pin escape, group boundary contacts, obstacle reservation, and routing. A missing class terminal is a capability failure, not an electrical absence and not a coordinate at the device origin.

Use the following caller precedence, with explicit rejection of contradictory requests:

1. A caller's electrical netlist and ordered terminal identities are fixed. A presentation request cannot retie the body or reduce device arity.
2. Explicit per-terminal or per-net presentation requests override defaults when the selected class and exporter support them. The request also identifies which source policy is desired: complete representation or reproduction of a recorded source convention. An explicit omit request is retained as an omission record, not called a visible connection.
3. A verified imported source presentation can request its observed bridge or omission. AG1236 proves that a topology selector cannot reconstruct this style choice. Absence of ink alone must not silently authorize B=S, a rail tie, or a new external port. A source-frame contradiction stays unresolved; it does not become an inferred source request.
4. Without an explicit convention, represent a distinct shared body net meaningfully. For this two-body class, prefer a direct B-to-B connection when both actual body contact geometries are available and the local route is feasible. A shared well name at both represented contacts is a permitted alternative if the caller accepts named nets and the exporter carries the same exact internal node. The name must not promote the internal net to a formal port.
5. If the selected class cannot represent B, preserve all raw pins and report the exact unrepresented terminal IDs. A built-in visible-body variant may be selected only through an explicit, compatible capability mapping. A caller's custom three-lead class cannot be overwritten merely to make a drawing look complete. No invented origin coordinate, unrelated correct-net marker, or guessed channel landing supplies the missing contact.

The condition is per terminal. AG1181 from the broader body study has a common Vb net that is self-source for some devices and distinct body input for others. A blanket net-level hide decision is insufficient. The B=S convention can remain compact when caller policy permits; B=D, B=G, and a distinct shared well retain their different identities even when some voltage relationships might coincide in use. All equality bits remain available, including D=S=B.

For a shared-body route, collect the complete raw net incidence before testing classes, models, orientations, or visibility. Retain the exact owner pin list, including every third or hidden occurrence. The 23-case two-owner shape is admitted only when that raw list has exactly the two named B occurrences. A third body, external formal, rail policy, non-MOS terminal, or ordinary D/G/S occurrence changes the candidate; filtering an inconvenient member is not allowed. Other topologies can use the generic representation policy, but cannot enter this narrow two-owner bridge rule.

This body relation does not by itself merge placement groups. If both owners belong to one validated source region, the local route can contribute a boundary contact or extent request to that region. If owners have different groups, the well is an inter-group interface; neither group may claim the other owner or erase the crossing relationship. Caller symmetry still owns the requested mate/axis geometry. Choosing a body side or class pose is a later local admission step that must satisfy those requests. On conflict, return the first exact conflicting pin, class capability, and caller request; preserve the previous placement and complete netlist.

## Data ownership and bounded admission

The parser owns ordered terminal rows; incidence construction owns the net-to-terminal CSR. A presentation resolver reads both and appends requests keyed by stable terminal handle. It alone writes accepted presentation state. The library owner supplies actual contact geometry and named terminal-role mapping; renderers consume those facts. The group owner consumes resolved visible boundary contacts but cannot alter raw membership. Exporters retain every electrical terminal and consume the same presentation result. The plugin must not independently decide that every fourth pin is hidden.

Use a bounded per-net CSR scan: total work is linear in all terminal occurrences plus accepted representation requests. Store raw incidence once. A compact accepted-mode column is cold metadata until visible endpoint generation; keep hot route coordinates only for accepted endpoints. The two-body local candidate stores two terminal handles, a net handle, a mode, and a witness reference. Capacity is bounded by the existing terminal and net counts; no unbounded pair enumeration or name search is needed. Instance/model/net names remain provenance or caller-facing diagnostics, never selection shortcuts.

Complete fallible geometry and route-capability checks before committing new endpoint rows. The request result includes exact accepted/declined terminal names, a typed reason, and its owning policy. An exporter needs both complete ordered pins and optional actual visible endpoints. The JSON `bulk` field currently demonstrates preservation but does not satisfy a future visible-endpoint contract; a coordinate for a hidden fourth class terminal likewise does not certify that it is routed. The prior absent/visible/hidden caller-class experiment remains the relevant counterexample.

## Oracles, limits, and replay

The executed oracles are exact names and hashes; manually written D/G/S/B literals for three representatives; actual D/G/S glyph endpoints; channel-polygon B support; cached named segments verified against actual source ink; actual contact-aware path certificates; and frozen native ordered-binding/byte-identity checks for all 23 cases. Deleting only AG1294's actual `M 606 100 L 714 100` segment leaves the cache untouched and correctly changes both named and all-ink connectivity to false. Consistent net renaming and record reordering retain connectivity. Rebinding cached B to S is rejected by the ordered-binding check.

The future implementation oracle should compare exact accepted terminal-mode requests, exact visible contact sets, and complete exported node identities before image scores. Mutations must cover a third hidden B, a nonbody incidence, a formal body, a rail-role change, one unsupported class, one detached cached landing, a wrong fourth role, and an overlapping group claim. A named-well fallback needs a host round trip proving both labels preserve the same internal node without inventing a port. Caller symmetry tests must compare the actual transformed body contacts and requested axes. These new admission and exporter behaviors are plans, not executed engine tests.

Actual source external-marker text-to-formal binding remains unproved. The earlier peer mutation changing AG1014's VI1 label text to VI2 still passes a named-stroke/raw-cache certificate. This study does not promote that certificate into a complete independent visual electrical netlist. All three new physical examples have matching literal instance labels, but their semantic node names still come from raw/cache correspondence. The exact remaining physical-source names are AG1296, AG1297, AG1299, AG1307, AG1313, AG1319, AG1329, AG1335, AG1337, AG1343, AG1399, AG1404, AG2193, AG2285, AG2287, AG2315, AG2397, AG2463, AG2464, and AG2498. They were actually viewed and their raw/native identities checked; no individual actual-glyph connection certificate is claimed for them.

```sh
R=.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/third-bodies
python3 -B docs/research/image-rules/round-2/third-bodies-render.py "$R"
python3 -B docs/research/image-rules/round-2/third-bodies-proof.py \
  docs/research/image-rules/round-2/third-bodies-evidence.json --replay-native --render-crops
python3 -B docs/research/image-rules/round-2/third-bodies-proof.py \
  "$R/evidence-replay.json" --check docs/research/image-rules/round-2/third-bodies-evidence.json
```

Run the producing commands sequentially; the manifest hashes the completed raster batch. Rendering creates no viewing claim. The 23 manually recorded observations and three crop-view records are retained separately. The complete current 84-owner crosswalk remains [bodies_rule_crosswalk.json](bodies_rule_crosswalk.json); this third study refines the presentation resolver, glyph/contact capability, group interface, JSON/ABI, and plugin export requirements without changing any current source rule.
