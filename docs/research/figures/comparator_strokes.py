#!/usr/bin/env python3
"""Exact comparator-family occurrences -> actual source outlines and step ink.

Usage: comparator_strokes.py <examples-dir> <output.json>

This inspects every outer instance of comp, comparator, cmp and
ICM_IDEAL_COMPARATOR_VDD, independently of whether its port contract is
supported. Names select observations, never expected glyphs. The source's
own symbol group supplies a triangle/box, lead strokes, polarity marks and
an optional interior three-segment step. Unknown ink fails. Exact inventories
record all occurrences by observed style; source triples and audit inputs
are hashed. This does not certify electrical or cached-terminal geometry.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import block_aliases as aliases
import controller_glyphs as glyph
from mos_forms import read_cards

FAMILIES = ("cmp", "comp", "comparator", "icm_ideal_comparator_vdd")
STYLES = ("plain_triangle", "stepped_triangle", "box")


def select(text, cid):
    definitions = {}
    for line in text.lower().splitlines():
        words = line.split()
        if not words or words[0] != ".subckt":
            continue
        end = next((i for i, word in enumerate(words) if "=" in word or word == "params:"), len(words))
        if words[1] in definitions:
            raise ValueError(f"{cid}: duplicate definition {words[1]}")
        definitions[words[1]] = words[2:end]
    rows = []
    for card, words in read_cards(text).items():
        if not card.startswith("x"):
            continue
        end = next((i for i, word in enumerate(words) if "=" in word or word == "params:"), len(words))
        family = words[end - 1]
        if family not in FAMILIES:
            continue
        ports, bindings = definitions[family], words[1:end - 1]
        if len(ports) != len(bindings):
            raise ValueError(f"{cid}:{card}: incomplete call")
        rows.append(dict(id=cid, card=card, family=family, ports=ports, bindings=bindings))
    return rows


def ink(group, parent):
    # Separate a strictly parsed open step from the outline parser. It still
    # has to lie wholly inside its own triangle; a nearby circuit wire is not
    # evidence. Copying keeps the original source tree intact for other cards.
    drawing, steps = copy.deepcopy(group), []
    parents = {child: node for node in drawing.iter() for child in node}
    for node, transform, _ in list(glyph.walk(drawing, parent)):
        if node.tag.rsplit("}", 1)[-1] != "path":
            continue
        commands = re.findall(r"[A-Za-z]", node.get("d", ""))
        if commands == ["M", "L", "L", "Z"]:
            continue
        values = glyph.numbers(node.get("d", ""))
        if commands != ["M", "L", "L", "L"] or len(values) != 8:
            raise ValueError("unsupported non-outline path")
        points = [glyph.point(transform, p) for p in zip(values[::2], values[1::2])]
        directions = [glyph.direction(a, b) for a, b in zip(points, points[1:])]
        horizontal = [d in ("left", "right") for d in directions]
        if directions[0] != directions[2] or horizontal[0] == horizontal[1]:
            raise ValueError("open path is not an orthogonal step")
        steps.append(dict(path=node.get("d"), vertices=points, directions=directions))
        parents[node].remove(node)
    body, leads, interior = aliases.primitives(drawing, parent)
    if len(steps) > 1 or (steps and len(body) != 3):
        raise ValueError("step requires one unique triangle")
    if any(aliases.location(p, body) != "inside" for step in steps for p in step["vertices"]):
        raise ValueError("step does not lie strictly inside its triangle")
    return dict(style="box" if len(body) == 4 else "stepped_triangle" if steps else "plain_triangle",
                body=body, leads=leads, polarity_marks=aliases.polarity_marks(interior), steps=steps)


def audit(examples):
    files = sorted(examples.rglob("*.human.json"))
    if not files:
        raise ValueError("no paired human drawings")
    digest, hashes, rows = hashlib.sha256(), {}, []
    for hp in files:
        cid = hp.name.removesuffix(".human.json")
        deck, svg = hp.with_name(cid + ".cir"), hp.with_name(cid + ".svg")
        for path in (hp, deck, svg):
            data, name = path.read_bytes(), path.relative_to(examples).as_posix()
            encoded = name.encode()
            digest.update(len(encoded).to_bytes(8, "big") + encoded + len(data).to_bytes(8, "big") + data)
            hashes[name] = hashlib.sha256(data).hexdigest()
        selected = select(deck.read_text(), cid)
        if not selected:
            continue
        human, root = json.loads(hp.read_text()), ET.parse(svg).getroot()
        for row in selected:
            device, group, parent = aliases.source_group(human, root, row["card"])
            try:
                evidence = ink(group, parent)
            except ValueError as error:
                raise ValueError(f"{cid}:{row['card']}: {error}") from error
            rows.append(dict(**row, source_asset=device["type"], source_object=group.get("data-object-id"),
                             **evidence))
    inventory = {family: {style: sorted(r["id"] + ":" + r["card"] for r in rows
                                       if r["family"] == family and r["style"] == style)
                          for style in STYLES} for family in FAMILIES}
    dependencies = ("comparator_strokes.py", "block_aliases.py", "controller_glyphs.py",
                    "single_input_amplifiers.py", "biased_amplifiers.py", "mos_forms.py", "power_paths.py")
    return dict(corpus=examples.name, drawings=len(files), corpus_sha256=digest.hexdigest(),
                summary={family: {style: len(names) for style, names in styles.items()}
                         for family, styles in inventory.items()},
                inventories=inventory, instances=rows, source_sha256=hashes,
                audit_sha256={name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                              for name in dependencies},
                limits="All exact-family occurrences, not only supported port contracts. Plain means no interior step; polarity marks may differ from declared signal roles. No native or source terminal-geometry claim.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--inventory", type=Path, default=Path(__file__).with_name("comparator_strokes_cases.json"))
    args = parser.parse_args()
    selfcheck()
    result = audit(args.examples)
    expected = json.loads(args.inventory.read_text())["corpora"][args.examples.name]
    aliases.check_inventory(result["inventories"], expected, "comparator style inventory")
    result["inventory_sha256"] = hashlib.sha256(args.inventory.read_bytes()).hexdigest()
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({key: result[key] for key in ("corpus", "drawings", "corpus_sha256", "summary")},
                     indent=2, sort_keys=True))


def selfcheck():
    triangle = '<path d="M -30 -30 L -30 30 L 22 0 Z"/>'
    step = '<path d="M -18 7 L -10 7 L -10 -7 L -2 -7"/>'
    plain = ink(ET.fromstring('<g>' + triangle + '</g>'), glyph.IDENTITY)
    assert plain["style"] == "plain_triangle" and not plain["steps"]
    stepped = ink(ET.fromstring('<g transform="translate(100 50) rotate(90)">' + triangle + step + '</g>'), glyph.IDENTITY)
    assert stepped["style"] == "stepped_triangle"
    assert stepped["steps"][0]["vertices"] == [(93, 32), (93, 40), (107, 40), (107, 48)]
    for bad in (step.replace('-18 7', '-38 7'), step.replace('-2 -7', '-20 -7')):
        try:
            ink(ET.fromstring('<g>' + triangle + bad + '</g>'), glyph.IDENTITY)
        except ValueError:
            pass
        else:
            raise AssertionError("non-step or exterior path admitted")
    text = '.subckt comp inn out\n.ends\n.subckt cmp1 inn out\n.ends\n.subckt top a b\nx1 a b CoMp\nx2 a b cmp1\n.ends'
    assert [r["card"] for r in select(text, "literal")] == ["x1"]


if __name__ == "__main__":
    main()
