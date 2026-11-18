# Ninth independent review: a label cannot join two wire pieces

The physical-partition verifier had a real false positive. Two undotted
orthogonal wires crossing at their interiors were correctly separate until
a same-net label was placed at the crossing. The verifier then joined them,
although neither conductor nor junction ink had changed. This was a defect
in the research checker, not an observed production routing defect.

The original checker bytes and the executed failing literal are retained in
the run directory under `root-partition-review/`. The old script has SHA-256
`8a445e54b8e3ffbb86a7acd98cf536dd12eec189528dec902a38376b5427e5fc`.
The [independent replay](ninth-partition-review.py) executes both versions
against the same literal; its [result](ninth-partition-review.json) records
the inputs, hashes and all nine controls.

| Unchanged or explicitly changed ink | Old checker | Repaired checker |
|---|---|---|
| Horizontal `(-10,0)–(10,0)`, vertical `(0,-10)–(0,10)`, no dot; one name at each outer tip | Two physical pieces | Two physical pieces |
| Add only a same-net label at `(0,0)` | Incorrectly one physical piece | Rejects ambiguous attachment to unjoined components |
| Instead add a label at `(-5,0)` | Not the failure witness | Two physical pieces |
| Add an actual dot at `(0,0)` | Not the failure witness | One physical piece |

The corrected order is to build conductor components from the declared
geometry/contact model first, then associate markers with those existing
components. A marker touching multiple unjoined components is ambiguous;
its coordinates are not permission to create a contact. Endpoint T contacts
and collinear overlap still join in the literal controls. A reachable marker
with a conflicting net name still fails even when another name is correct.

This supplements the [eighth partition study](eighth-partitions.md), whose
original eleven frozen runs remain unchanged. It does not establish a
complete SVG text association engine, arbitrary renderer support or target
netlisting behavior. Future production gates must separately prove actual
conductor contact, visible marker attachment and exported electrical identity.

```sh
python3 -B docs/research/image-rules/round-2/ninth-partition-review.py \
  --check docs/research/image-rules/round-2/ninth-partition-review.json \
  --output /tmp/cktimg-ninth-partition-review.json
```
