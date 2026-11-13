#!/usr/bin/env python3
"""SPICE channel bridges -> exact source SVG evidence and native comparisons.

Usage: channel_bridges.py <examples-dir> <output.json> [--native <json-dir>]

Two candidate habits: a unique complementary MOS pair sharing off-rail channel
nets, NMOS gate on supply and PMOS gate on sink; or two same-polarity transistors
with reversed channels and each gate/base tied to its own drain/collector.
The latter is an antiparallel diode-connected pair, not an arbitrary latch.
The last subcircuit is the observed cell. Unknown cards/models, ambiguous SVG
primitives, missing native devices and disagreement between actual lead ink and
cached terminals fail. No engine or other research module is imported.

The oracle reads the two channel lead polylines and SVG transforms. Cached
centers associate instances; cached rotation does not determine orientation.
The broader diode-connected comparison uses cached terminals and is labelled
as such. Base/emitter shorts are retained as a separate sparse research group.
Numeric source ID modulo five is deterministic stratification, not a guarantee
that related textbook variants are statistically independent.
"""
import argparse
import collections
import hashlib
import json
import math
import re
from pathlib import Path
import xml.etree.ElementTree as ET


def read_cards(text):
    """Reads the final converted subcircuit, refusing unsupported study syntax."""
    lines = []
    for raw in text.lower().splitlines():
        if raw.lstrip().startswith("*@"):
            raise ValueError("steered deck outside observational study")
        if raw.startswith("+"):
            if not lines:
                raise ValueError("orphan continuation")
            lines[-1] += " " + raw[1:]
        else:
            lines.append(raw)
    cards = {}; inside = found = False
    for raw in lines:
        words = raw.split()
        if not words or words[0].startswith("*"):
            continue
        if words[0] == ".subckt":
            if inside:
                raise ValueError("nested subcircuit")
            cards = {}; inside = found = True
        elif words[0] == ".ends":
            inside = False
        elif inside and not words[0].startswith("."):
            name = words[0]
            if name in cards or name[0] not in "rclviefhgdwsqjzmkxbtou":
                raise ValueError("duplicate or unsupported card: " + raw)
            if name[0] in "mq" and len(words) < (6 if name[0] == "m" else 5):
                raise ValueError("malformed transistor: " + raw)
            cards[name] = words
    if not found or inside:
        raise ValueError("missing or unterminated final subcircuit")
    return cards


def rail(name):
    """Existing named-rail vocabulary; no bias/control name becomes a rail."""
    if name in ("0", "v-") or name.startswith(("gnd", "vss", "vee", "agnd", "dgnd")):
        return "sink"
    if name == "v+" or name.startswith(("vdd", "vcc", "avdd", "dvdd", "vpp")):
        return "supply"
    return None



def svg_channel(svg, device):
    root = ET.parse(svg).getroot()
    parents = {child: parent for parent in root.iter() for child in parent}
    matches = []
    for group in root.iter():
        if group.get("data-symbol-id") != device["type"]:
            continue
        inner = list(group)[0]
        transform = inner.get("transform", "")
        steps = re.findall(r"(translate|scale|rotate)\(([^)]+)\)", transform)
        if re.sub(r"(translate|scale|rotate)\([^)]+\)", "", transform).strip():
            raise ValueError("unsupported SVG transform: " + transform)
        if not steps or steps[0][0] != "translate":
            raise ValueError("missing position on primitive SVG")
        center = [float(v) for v in re.split(r"[ ,]+", steps[0][1])]
        if center != [device["x"], device["y"]]:
            continue
        ancestor = group
        while ancestor in parents:
            if ancestor.get("transform"):
                raise ValueError("unexpected enclosing SVG transform")
            ancestor = parents[ancestor]
        if any(e is not inner and e.get("transform") for e in inner.iter()):
            raise ValueError("unexpected nested SVG transform")
        ends = []
        # Actual exported channel stubs terminate the two polylines at y=+/-20.
        # Read the ink vertices; do not use cached rotation or pin coordinates.
        for element in inner.iter():
            if element.tag.rsplit("}", 1)[-1] != "polyline":
                continue
            numbers = [float(v) for v in re.split(r"[ ,]+", element.attrib["points"].strip())]
            x, y = numbers[-2:]
            if abs(y) != 20:
                continue
            for operation, values in reversed(steps):
                args = [float(v) for v in re.split(r"[ ,]+", values)]
                if operation == "translate":
                    x, y = x + args[0], y + args[1]
                elif operation == "scale":
                    x, y = x * args[0], y * args[1]
                elif operation == "rotate":
                    if len(args) != 1 or args[0] % 90:
                        raise ValueError("unsupported primitive rotation")
                    angle = math.radians(args[0]); co, si = round(math.cos(angle)), round(math.sin(angle))
                    x, y = co*x-si*y, si*x+co*y
            ends.append([x, y])
        if len(ends) != 2 or ends[0] == ends[1]:
            raise ValueError("ambiguous SVG channel stubs")
        matches.append(ends)
    if len(matches) != 1:
        raise ValueError("ambiguous SVG primitive for " + device["card"])
    ends = matches[0]
    axis = "horizontal" if ends[0][1] == ends[1][1] else "vertical" if ends[0][0] == ends[1][0] else "diagonal"
    if axis == "diagonal":
        raise ValueError("unexpected diagonal channel")
    pair = ("D", "S") if device["card"][0] == "m" else ("C", "E")
    if sorted(ends) != sorted(device["terminals"][p] for p in pair):
        raise ValueError("SVG/cached terminal disagreement: " + device["card"])
    return axis, ends


def summarize(rows):
    return dict(devices=len(rows), circuits=len({r["id"] for r in rows}),
                horizontal=sum(r["svg_axis"] == "horizontal" for r in rows),
                native_horizontal=sum(r["native_axis"] == "horizontal" for r in rows),
                exceptions=[r["id"]+":"+r["card"] for r in rows if r["svg_axis"] != "horizontal"])


def study(examples, native):
    selected = []; digest = hashlib.sha256(); broader = collections.defaultdict(list)
    paths = sorted(examples.glob("*.human.json"))
    if not paths:
        raise ValueError("no paired human drawings")
    for path in paths:
        identifier = path.name.removesuffix(".human.json")
        deck = path.with_name(identifier+".cir"); svg = path.with_name(identifier+".svg")
        h = json.loads(path.read_text()); text = deck.read_text(); cards = read_cards(text)
        devices = {d["card"]: d for d in h["devices"]}
        models = {w[1]:w[2] for line in text.lower().splitlines() if (w:=line.split()) and w[0]==".model"}
        transistors = {}
        for name, words in cards.items():
            if name[0] not in "mq": continue
            model = words[5] if name[0]=="m" else next((w for w in words[4:] if w in models), None)
            if model not in models: raise ValueError("unknown transistor model")
            polarity = models[model]
            if polarity != devices[name]["type"]: raise ValueError("deck/drawing type disagreement")
            transistors[name] = (words, polarity)
        generated = {}
        if native and (native/(identifier+".json")).exists():
            generated = {d["name"].lower(): d for d in json.loads((native/(identifier+".json")).read_text())["devices"]}
        for name, (words, polarity) in transistors.items():
            d,g,s = words[1:4]; families = []; mates = []
            if d == s or rail(d) or rail(s): continue
            if d == g:
                pair = ("D", "S") if name[0] == "m" else ("C", "E")
                a, b = [devices[name]["terminals"][k] for k in pair]
                broader["diode_connected_cached"].append(dict(id=identifier, card=name,
                    axis="horizontal" if a[1] == b[1] else "vertical"))
            parallel = [n for n, (w, _) in transistors.items()
                        if n != name and n[0] == name[0] and {w[1], w[3]} == {d, s}]
            for other, (peer, pp) in transistors.items():
                if other == name: continue
                if len(parallel) == 1 and d == g and peer[1] == peer[2] == s and peer[3] == d and polarity == pp:
                    families.append("antiparallel_diode_connected"); mates.append(other)
                if name[0]==other[0]=="m" and {d,s}=={peer[1],peer[3]} and polarity!=pp and g not in (d,s) and peer[2] not in (d,s):
                    axis, _ = svg_channel(svg, devices[name])
                    broader["complementary_channel"].append(dict(id=identifier, card=name, axis=axis))
                    desired = "supply" if polarity=="nmos" else "sink"
                    peer_desired = "supply" if pp=="nmos" else "sink"
                    if len(parallel) == 1 and rail(g)==desired and rail(peer[2])==peer_desired:
                        families.append("always_on_transmission"); mates.append(other)
            if name[0]=="q" and g==s:
                families.append("base_emitter_short")
            if not families: continue
            axis, ends = svg_channel(svg, devices[name]); native_axis = None
            if native and name not in generated:
                raise ValueError("missing native device: " + identifier + ":" + name)
            if name in generated:
                pins = {p["term"].upper():p["xy"] for p in generated[name]["pins"]}
                pair=("D","S") if name[0]=="m" else ("C","E")
                a,b=[pins[k] for k in pair]
                native_axis="horizontal" if a[1]==b[1] else "vertical" if a[0]==b[0] else "diagonal"
            selected.append(dict(id=identifier,card=name,families=sorted(set(families)),mates=sorted(set(mates)),
                svg_axis=axis,svg_channel=ends,native_axis=native_axis,polarity=polarity,
                split="holdout" if int(identifier.rsplit("-",1)[1])%5==0 else "discovery",
                source_sha256={p.suffix:hashlib.sha256(p.read_bytes()).hexdigest() for p in (deck,svg,path)}))
        for p in (path, deck, svg):
            content=p.read_bytes();relative=p.name.encode()
            digest.update(len(relative).to_bytes(8,"big")+relative+len(content).to_bytes(8,"big")+content)
    groups={f:[r for r in selected if f in r["families"]] for f in ("antiparallel_diode_connected","always_on_transmission","base_emitter_short")}
    contrast = {}
    for label, entries in broader.items():
        rows = {r["id"]+":"+r["card"]:r for r in entries}
        contrast[label] = dict(devices=len(rows),
            horizontal=sum(r["axis"] == "horizontal" for r in rows.values()),
            vertical=sum(r["axis"] == "vertical" for r in rows.values()),
            names={axis:sorted(n for n,r in rows.items() if r["axis"] == axis)
                   for axis in ("horizontal", "vertical") if label != "diode_connected_cached" or axis == "horizontal"})
    binary = native/"cktimg-json" if native else None
    return dict(corpus_sha256=digest.hexdigest(), drawings=len(paths),
        script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        native_binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest() if binary and binary.exists() else None,
        oracle="transformed source SVG channel lead vertices; cached centers only associate instances",
        split="source numeric ID modulo 5 == 0 is holdout; correlated variants may cross groups",
        selected=selected, broader=contrast,
        summary={f:{s:summarize([r for r in rs if s=="all" or r["split"]==s])
                    for s in ("all","discovery","holdout")} for f,rs in groups.items()})

if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("examples",type=Path);parser.add_argument("output",type=Path);parser.add_argument("--native",type=Path)
    args=parser.parse_args();result=study(args.examples,args.native);args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n");print(json.dumps(result["summary"],indent=2))
