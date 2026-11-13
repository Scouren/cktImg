#!/usr/bin/env python3
"""Study an internal return bank beside a two-capacitor chain; research only.

Usage: opamp_returns.py <examples-dir> <output.json> [--native <json-dir>]

No electrical rail is inferred. Select exactly three same-polarity MOS whose
only common-source token incidences are those source fields; the node is not
a rail or selected-cell port. Their distinct drains form a two-capacitor
chain; they share an external gate-only control and rail body. One further
MOS, with a different external control and the same body, joins the chain's
middle drain to a separate nonrail node. Source coordinates independently
measure the capacitor row, return bank and vertical inter-row channel.

The token-incidence guard is deliberately conservative: even a matching
model/value token rejects a candidate. The study does not change the node's
electrical role or the engine's admission, and imports no engine code.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path

from mos_forms import rail, read_cards
from mos_bridges import declarations
from opamp_feedback import drawing, horizontal, midpoint


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path)
    args = parser.parse_args()
    files = sorted(args.examples.rglob("*.human.json"))
    if not files:
        parser.error("examples directory contains no human drawings")
    digest, rows = hashlib.sha256(), []
    for path in files:
        deck = path.with_name(path.name.replace(".human.json", ".cir"))
        for source in (path, deck):
            data, name = source.read_bytes(), source.relative_to(args.examples).as_posix().encode()
            digest.update(len(name).to_bytes(8, "big") + name)
            digest.update(len(data).to_bytes(8, "big") + data)
        text = deck.read_text()
        cards = read_cards(text)
        models, ports = declarations(text)
        selected = select(cards, models, ports)
        if not selected:
            continue
        assert select(dict(reversed(list(cards.items()))), models, ports) == selected
        human = json.loads(path.read_text())
        ds = drawing(human, True)
        for row in selected:
            removed = cards.copy()
            del removed[row["caps"][0]]
            assert row not in select(removed, models, ports)
            assert row not in select(cards, models, ports | {row["return"]})
            row.update(id=human["id"], split="holdout" if int(human["id"].split("-")[-1]) % 5 == 0 else "discovery")
            row["human"] = checks(row, ds)
            if args.native:
                native = json.loads((args.native / (human["id"] + ".json")).read_text())
                row["native"] = checks(row, drawing(native, False))
            rows.append(row)
    summary = {"banks": len(rows), "mos": sum(len(r["bank"]) for r in rows),
               "ids": [r["id"] for r in rows], "holdout": sum(r["split"] == "holdout" for r in rows)}
    for kind in ("human", "native"):
        if rows and kind in rows[0]:
            summary[kind] = {"passing": sum(sum(r[kind].values()) for r in rows),
                             "checks": sum(len(r[kind]) for r in rows)}
    result = {"corpus_sha256": digest.hexdigest(), "drawings": len(files),
              "oracle": "human terminal coordinates; topology never reads coordinates",
              "status": "research only; internal return bank is not an inferred electrical rail",
              "selfchecks": "card reversal, missing chain capacitor, declared-port ablation",
              "summary": summary, "selected": rows}
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({k: result[k] for k in ("corpus_sha256", "drawings", "summary")}, indent=2))


def select(cards, models, ports):
    """Conservative token incidences keep hidden loads out of the local bank."""
    tokens = collections.defaultdict(list)
    for name, words in cards.items():
        for position, token in enumerate(words[1:], 1):
            tokens[token].append((name, position))

    def external(gate):
        return not rail(gate) and all(n[0] == "m" and p == 2 for n, p in tokens[gate])

    result = []
    for net, pins in sorted(tokens.items()):
        if rail(net) or net in ports or len(pins) != 3 or not all(n[0] == "m" and p == 3 for n, p in pins):
            continue
        names = sorted(n for n, _ in pins)
        words = [cards[n] for n in names]
        if any(len(w) < 6 or len(set(w[1:4])) != 3 for w in words):
            continue
        gate, body = words[0][2], words[0][4]
        polarity = models.get(words[0][5])
        if not external(gate) or not rail(body) or polarity not in ("nmos", "pmos"):
            continue
        if any(w[2] != gate or w[4] != body or models.get(w[5]) != polarity for w in words):
            continue
        drains = {w[1] for w in words}
        if len(drains) != 3 or any(rail(n) for n in drains):
            continue
        caps = sorted(n for n, w in cards.items() if n[0] == "c" and w[1] != w[2] and set(w[1:3]) <= drains)
        degree = collections.Counter(node for n in caps for node in cards[n][1:3])
        if len(caps) != 2 or sorted(degree.values()) != [1, 1, 2]:
            continue
        middle = next(n for n, count in degree.items() if count == 2)
        bridge = []
        for name, w in cards.items():
            if name in names or name[0] != "m" or len(w) < 6 or w[4] != body or models.get(w[5]) != polarity or w[2] == gate or not external(w[2]):
                continue
            if middle not in (w[1], w[3]) or len(set(w[1:4])) != 3:
                continue
            other = w[3] if w[1] == middle else w[1]
            if other not in drains and not rail(other):
                bridge.append(name)
        if len(bridge) != 1:
            continue
        result.append({"return": net, "control": gate, "bank": names, "caps": caps,
                       "middle": middle, "bridge": bridge[0],
                       "drains": {n: cards[n][1] for n in names},
                       "cap_nets": {n: cards[n][1:3] for n in caps}})
    return result


def checks(row, ds):
    """Rows, columns and branch roles, independent of absolute drawing units."""
    bank, caps = row["bank"], row["caps"]
    terminals = {n: {t: xy for t, _, xy in ds[n]} for n in bank}
    columns = {row["drains"][n]: midpoint(ds, n)[0] for n in bank}
    cap_row = midpoint(ds, caps[0])[1]
    bridge = row["bridge"]
    bx, by = midpoint(ds, bridge)
    neighbors = [columns[n] for n in columns if n != row["middle"]]
    return {"bank_vertical": all(not horizontal(ds, n) for n in bank),
            "bank_drains_same_row": len({terminals[n]["d"][1] for n in bank}) == 1,
            "bank_sources_same_row": len({terminals[n]["s"][1] for n in bank}) == 1,
            "bank_below_capacitors": all(terminals[n]["s"][1] > terminals[n]["d"][1] > cap_row for n in bank),
            "capacitors_horizontal_same_row": all(horizontal(ds, n) and midpoint(ds, n)[1] == cap_row for n in caps),
            "each_cap_between_adjacent_returns": all(min(columns[v] for v in row["cap_nets"][n]) < midpoint(ds, n)[0] < max(columns[v] for v in row["cap_nets"][n]) for n in caps),
            "middle_return_between_outer_returns": min(neighbors) < columns[row["middle"]] < max(neighbors),
            "bridge_vertical_above_chain": not horizontal(ds, bridge) and by < cap_row,
            "bridge_inside_return_columns": min(neighbors) < bx < max(neighbors)}


if __name__ == "__main__":
    main()
