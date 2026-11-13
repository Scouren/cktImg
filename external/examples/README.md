# external/examples

The reference circuits of the [Analog Canvas](https://analog-canvas.tokenzhang.com)
gallery, cached here so the site (`tools/site/build.py`, `.github/workflows/site.yml`)
never fetches from Analog Canvas. Third-party data: read it as untrusted
(`python3 -I`, paths as arguments).

| Source | Circuits | Author as the entries give it | Origin as the descriptions give it |
|---|---|---|---|
| `circuitthink/` | 100 | CircuitThink (redrawn) | CircuitThink figures (Apache-2.0), redrawn number for number |
| `analoggenie/` | 2,202 | AnalogGenie (redrawn) | AnalogGenie figures (MIT) and dataset circuits, each entry citing its textbook or paper |
| `amsnet/` | 734 | AMS-Net (redrawn) | AMS-Net figures, redrawn number for number |
| `analogretriever/` | 2,238 | AnalogRetriever (redrawn) | AnalogRetriever figures, drawn from the figure |

5,274 circuits in all. Each source directory holds:

- `index.json`: the gallery's listing (`GET /api/gallery?source=<source>`): id,
  name, author, description, creation date, preview revision and size.
- `<id>.svg`: the gallery's own preview of the person's drawing
  (`GET /api/gallery/<id>/preview.svg?v=<previewRevision>&render=formula-label-v5`),
  shown on the site in an `<img>`, never inlined. `previews.json` maps each id to
  the revision fetched.
- `<id>.cir`: the gallery's official SPICE netlist
  (`GET /api/gallery/maintenance/netlists?format=spice&source=<source>`), PDK
  subcircuits rewritten to `M`/`Q` cards, by `tools/site/convert.py`.
- `<id>.human.json`: the person's drawing reduced to devices, pins, wires and
  labels (`convert.py`, from the entry's project, `GET /api/gallery/<id>`); the
  site measures its crossings, corners and wire length from it.

Listings, entries and netlists fetched 2026-11-11; previews 2026-11-12. Each entry's
page is `https://analog-canvas.tokenzhang.com/g/<id>`; the drawings remain their
authors', credited as above on every page of the site.

## Refresh

Run by hand, never in CI:

    python3 -I tools/site/fetch.py external/examples [raw-dir]

It downloads only what is missing: a source's `index.json` when absent (delete it
to list again), each preview not yet fetched or whose revision changed, and, given
a `raw-dir`, the raw entry and netlists of each listed circuit without a deck,
converted by `convert.py`. At most 4 requests at a time, a generic User-Agent.
Failures go to `fetch-failures.txt` and are retried on the next run.
