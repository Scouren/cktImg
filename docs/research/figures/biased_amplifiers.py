#!/usr/bin/env python3
"""Known amplifier port contracts against independent source SVG outlines.

Usage: biased_amplifiers.py <examples-dir> <output.json>

Selection reads only the SPICE family and complete named port contract.
The source SVG, not a generated class or engine choice, supplies the oracle.
Opaque source asset IDs are matched by symbol type: exporter instance labels
can differ from converted SPICE card names. Every matching asset must contain
the triangular outline. Unknown controls and duplicate bias roles are excluded.
"""

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("mos_forms", Path(__file__).with_name("mos_forms.py"))
MOS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOS)


def contract(ports):
    aliases = {"vdd": "supply", "vss": "ground", "out": "output", "vout": "output",
               "inp": "positive", "vip": "positive", "in+": "positive",
               "inn": "negative", "vin": "negative", "in-": "negative",
               "vb": "bias1", "vb1": "bias1", "bias": "bias1", "vb2": "bias2", "vb3": "bias3"}
    roles = [aliases.get(p) for p in ports]
    return (None not in roles and len(set(roles)) == len(roles)
            and {"positive", "negative", "output"} <= set(roles)
            and any(r.startswith("bias") for r in roles))


def triangle(group):
    # An independently authored closed path with three vertices. Leads,
    # polarity marks and supply connections do not decide the body shape.
    return any(node.tag.rsplit("}", 1)[-1] == "path"
               and re.findall(r"[A-Za-z]", node.get("d", "")) == ["M", "L", "L", "Z"]
               for node in group.iter())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    files = sorted(args.examples.glob("*.human.json"))
    if not files:
        parser.error("no human drawings")
    rows = []
    digest = hashlib.sha256()
    for human_path in files:
        cid = human_path.name.removesuffix(".human.json")
        deck_path = human_path.with_name(cid + ".cir")
        svg_path = human_path.with_name(cid + ".svg")
        hashes = {}
        for path in (human_path, deck_path, svg_path):
            data = path.read_bytes()
            name = path.name.encode()
            digest.update(len(name).to_bytes(8, "big") + name + len(data).to_bytes(8, "big") + data)
            hashes[path.suffixes[-2] if path.name.endswith(".human.json") else path.suffix] = hashlib.sha256(data).hexdigest()
        source = deck_path.read_text()
        cards = MOS.read_cards(source)
        definitions = {}
        for line in source.lower().splitlines():
            words = line.split()
            if words and words[0] == ".subckt":
                end = next((i for i, word in enumerate(words) if "=" in word or word == "params:"), len(words))
                definitions[words[1]] = words[2:end]
        selected = []
        for name, words in cards.items():
            if name[0] != "x":
                continue
            end = next((i for i, word in enumerate(words) if "=" in word or word == "params:"), len(words))
            family = words[end - 1]
            if family != "opamp" or not contract(definitions[family]):
                continue
            assert len(words[1:end - 1]) == len(definitions[family]), (cid, name)
            selected.append((name, definitions[family]))
        if not selected:
            continue
        human = {d["card"].lower(): d for d in json.loads(human_path.read_text())["devices"]}
        groups = [g for g in ET.parse(svg_path).iter() if g.get("data-symbol-id")]
        for name, ports in selected:
            asset = human[name]["type"]
            matches = [g for g in groups if g.get("data-symbol-id") == asset]
            if not matches:
                raise ValueError(f"{cid}:{name}: source symbol has no SVG asset")
            rows.append(dict(id=cid, card=name, ports=ports, source_asset=asset,
                             triangular=all(triangle(g) for g in matches), hashes=hashes))
    result = dict(corpus_sha256=digest.hexdigest(), drawings=len(files), selected=rows,
                  exceptions=[f"{r['id']}:{r['card']}" for r in rows if not r["triangular"]])
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"{sum(r['triangular'] for r in rows)}/{len(rows)} selected source symbols triangular")


if __name__ == "__main__":
    main()
