#!/usr/bin/env python3
"""Reduce each gallery entry to a SPICE deck cktImg can read and the human drawing.

usage: convert.py <corpus-dir> <out-dir> [id ...]
reads  <corpus-dir>/<source>/entries/<id>.json   (Analog Canvas Project, untrusted data)
       <corpus-dir>/netlists/<source>/page-*.json (the site's official netlists)
writes <out-dir>/cases/<id>.cir         the official netlist, PDK X cards rewritten to M/Q cards
       <out-dir>/cases/<id>.human.json  the human drawing (devices, markers, wires, labels)
       <out-dir>/convert_stats.json     every construct that could not be mapped, with counts

Geometry follows the Analog Canvas source (packages/model/src/geometry.ts transformPoint:
rotate, then mirror, then translate; packages/derived/src/resolved-route-geometry.ts: a
Route's centerline is start contact, bend coordinates, end contact).
"""
import collections, json, math, os, re, sys, unicodedata

SOURCES = ["circuitthink", "analoggenie", "amsnet", "analogretriever"]
# PDK subcircuit prefix -> (SPICE letter, model name, model type)
PDK = [
    ("sky130_fd_pr__nfet", "M", "nch", "nmos"),
    ("sky130_fd_pr__pfet", "M", "pch", "pmos"),
    ("sky130_fd_pr__npn", "Q", "qnpn", "npn"),
    ("sky130_fd_pr__pnp", "Q", "qpnp", "pnp"),
]
# node count of a primitive card by its letter (K couples two inductors: no nodes)
NODES = dict(R=2, C=2, L=2, V=2, I=2, D=2, B=2, F=2, H=2, E=4, G=4, S=4, J=3, M=4, Q=3, K=0)
MARKERS = {"ground": "ground", "vdd-port": "supply", "port": "port", "port-filled": "port"}


def transform(pt, origin, rot, mir):
    """Symbol-local point -> document point: rotate, mirror, translate (y grows down)."""
    x, y = pt
    if rot == 90:
        x, y = -y, x
    elif rot == 180:
        x, y = -x, -y
    elif rot == 270:
        x, y = y, -x
    elif rot:
        a = math.radians(rot)
        x, y = x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
    if mir in ("horizontal", "both"):
        x = -x
    if mir in ("vertical", "both"):
        y = -y
    return [round(origin[0] + x, 3), round(origin[1] + y, 3)]


def side(dx, dy):
    """Dominant screen direction of a vector (y grows down)."""
    if dx == 0 and dy == 0:
        return None
    if abs(dx) >= abs(dy):
        return "right" if dx > 0 else "left"
    return "down" if dy > 0 else "up"


def three_terminal(pins):
    """(control, a, b) pin positions of a MOS/JFET (g, d, s) or BJT (b, c, e), else None.
    `pins` maps lower-case pin names to points."""
    for ctl, a, b in (("g", "d", "s"), ("b", "c", "e")):
        if ctl in pins and a in pins and b in pins:
            return pins[ctl], pins[a], pins[b]
    return None


def gate_side(pins):
    """Side of the channel the gate/base is on: left/right/up/down."""
    t = three_terminal(pins)
    if not t:
        return None
    g, a, b = t
    return side(g[0] - (a[0] + b[0]) / 2, g[1] - (a[1] + b[1]) / 2)


def source_dir(pins):
    """Direction from drain to source (collector to emitter): down/up/left/right."""
    t = three_terminal(pins)
    return side(t[2][0] - t[1][0], t[2][1] - t[1][1]) if t else None


def greek(ch):
    """A Greek letter as the exporter spells it (\u03c0 -> pi); other characters unchanged."""
    name = unicodedata.name(ch, "") if ord(ch) > 127 else ""
    return name.split()[-1].lower() if name.startswith("GREEK") else ch


# ---------------------------------------------------------------- the deck

def join_lines(text):
    lines = []
    for raw in text.split("\n"):
        if raw.startswith("+") and lines:
            lines[-1] += " " + raw[1:]
        else:
            lines.append(raw.rstrip())
    return lines


def rewrite_deck(text, top_name, stats):
    """-> (deck text, top cell {name, ports, cards}, all cells).
    A card is {orig, name, letter, nodes, master, kind}; `name` is the name in the
    written deck (lower case), `orig` the official one."""
    lines = join_lines(text)
    defined = {l.split()[1].lower() for l in lines if l.lower().startswith(".subckt ") and len(l.split()) > 1}
    cells, order, cur, out, models = {}, [], None, [], {}
    for line in lines:
        t = line.split()
        if not t or t[0][0] == "*":
            out.append(line)
            continue
        head = t[0].lower()
        if head == ".subckt":
            ports = []
            for p in t[2:]:
                if p.lower().startswith("params:") or "=" in p:
                    break
                ports.append(p)
            cur = {"name": t[1], "ports": ports, "cards": [], "first": len(out), "taken": set()}
            cells[t[1].lower()] = cur
            order.append(cur)
        elif head == ".ends":
            if cur:
                cur["last"] = len(out)
            cur = None
        elif head[0] != "." and cur is not None:
            card = {"orig": t[0], "name": t[0].lower(), "letter": t[0][0].upper(), "master": None, "kind": None, "at": len(out)}
            if card["letter"] == "X":
                k = next((i for i, x in enumerate(t) if "=" in x), len(t))
                card["nodes"], card["master"], params = t[1:k - 1], t[k - 1], t[k:]
                pdk = next((p for p in PDK if card["master"].lower().startswith(p[0])), None)
                if pdk and card["master"].lower() not in defined:
                    card["pdk"] = pdk, params
                    card["kind"] = pdk[3]
                elif card["master"].lower() not in defined:
                    stats["unmapped X master: " + card["master"]] += 1
            elif card["letter"] in NODES:
                card["nodes"] = t[1:1 + NODES[card["letter"]]]
            else:
                card["nodes"] = []
                stats["unmapped card letter: " + card["letter"]] += 1
            cur["cards"].append(card)
        out.append(line)
    # second pass: rename PDK cards without colliding with a name already in the cell
    for cell in order:
        taken = {c["name"] for c in cell["cards"] if "pdk" not in c}
        for c in cell["cards"]:
            if "pdk" not in c:
                continue
            (_, letter, model, mtype), params = c.pop("pdk")
            name = c["orig"][1:] if c["orig"][1:2].upper() == letter else letter + c["orig"]
            while name.lower() in taken:
                name = letter + name
                stats["renamed PDK card (name collision)"] += 1
            taken.add(name.lower())
            c["name"], c["letter"] = name.lower(), letter
            models[model] = mtype
            out[c["at"]] = " ".join([name] + c["nodes"] + [model] + params)
    top = cells.get((top_name or "").lower())
    if top is None:
        top = order[-1]
        stats["top cell not found by name, used the last .subckt"] += 1
    if top is not order[-1]:  # cktImg draws the last .subckt of a file
        block = out[top["first"]:top["last"] + 1]
        del out[top["first"]:top["last"] + 1]
        out += block
        stats["top cell moved last"] += 1
    # line 1 of a SPICE deck is its title: a .model there would be read as the title and lost
    head = ["* official Analog Canvas netlist; PDK X cards rewritten by convert.py"]
    head += [".model %s %s" % kv for kv in sorted(models.items())]
    return "\n".join(head + out).strip("\n") + "\n", top, cells


# ---------------------------------------------------------------- the drawing

def reduce_project(project, deck_text, stats):
    """-> (deck, human) for one Project and its official netlist."""
    doc = next(d for d in project["documents"] if d["id"] == project["topDocumentId"])
    deck, top, cells = rewrite_deck(deck_text, doc["netlist"]["name"], stats)
    defs = {c["symbol"]["id"]: c for c in project["componentDefinitions"]}
    dflt = project.get("defaults", {})
    by_type = dflt.get("instancesByType", {})
    d_inst = dflt.get("instance", {})
    # cell terminal (name, direction) by the marker instance or rail label that declares it
    term_of = {}
    for t in doc["netlist"]["terminals"]:
        for iid in t.get("interfaceInstanceIds", []) + [t.get("interfaceAnnotationId")]:
            term_of[iid] = t
    claim = {e["owner"]["objectId"]: e for e in doc["connectivityEvidence"] if e.get("owner", {}).get("objectId")}

    insts, pin_at = {}, {}
    for inst in doc["instances"]:
        cdef = defs.get(inst["type"])
        if cdef is None or inst.get("coordinate") is None:
            stats["instance skipped (no definition or unplaced): " + inst["type"]] += 1
            continue
        sym = cdef["symbol"]
        shared = by_type.get(inst["type"], {})
        rot = inst.get("rotation", shared.get("rotation", d_inst.get("rotation", 0)))
        mir = inst.get("mirror", shared.get("mirror", d_inst.get("mirror", "none")))
        vid = inst.get("variant", shared.get("variant", sym.get("defaultVariantId")))
        variant = next((v for v in sym.get("variants", []) if v["id"] == vid), {})
        aux = {a["name"]: a for a in variant.get("auxiliaryPins", [])}
        # ponytail: signal-flow blocks may move a pin with their text (resolveSignalFlowPinAt); not modelled
        terms = {}
        for pin in sym["pins"]:
            at = aux.get(pin["name"], pin)["at"]
            terms[pin["name"]] = transform((at["x"], at["y"]), inst["coordinate"], rot, mir)
            pin_at[(inst["id"], pin["name"])] = terms[pin["name"]]
        insts[inst["id"]] = dict(inst=inst, cdef=cdef, rot=rot, mir=mir, terms=terms)

    # match the top cell's cards to named instances (SPICE adds X to subcircuit-bound parts)
    by_name = collections.defaultdict(list)
    for iid, r in insts.items():
        if r["inst"].get("name") and r["inst"]["type"] not in MARKERS:
            by_name[r["inst"]["name"].lower()].append(iid)
            spelled = "".join(greek(ch) for ch in r["inst"]["name"]).lower()  # C\u03c0 exports as Cpi
            if spelled != r["inst"]["name"].lower():
                by_name[spelled].append(iid)
    extra_cards, card_of, loose = [], {}, []
    for card in top["cards"]:
        o = card["orig"].lower()
        if card["letter"] == "K":
            stats["K card (inductor coupling, not a device)"] += 1
        elif o.startswith("v__icm_sense"):
            stats["synthetic current-sense source"] += 1
            extra_cards.append({"card": card["name"], "why": "synthetic current-sense source"})
        else:
            # the exporter may add the SPICE letter (M1 -> XM1, battery B1 -> VB1) or a _2 suffix
            cands = [o, o[1:], re.sub(r"_\d+$", "", o), re.sub(r"_\d+$", "", o[1:])]
            iid = next((i for n in cands for i in by_name.get(n, []) if i not in card_of), None)
            if iid is None:
                loose.append(card)
            else:
                card_of[iid] = card
    # names the exporter respelled (r\u03c0 -> Rpi): pair what is left when the letter leaves one choice
    free = collections.defaultdict(list)
    for name, ids in by_name.items():
        for iid in ids:
            if iid not in card_of:
                e = insts[iid]["cdef"].get("electrical") or {}
                free[(e.get("referencePrefix") or "X")[0].upper()].append(iid)
    for card in loose:
        same = [c for c in loose if c["orig"][0].upper() == card["orig"][0].upper()]
        ids = free.get(card["orig"][0].upper(), [])
        if len(same) == 1 and len(ids) == 1:
            card_of[ids[0]] = card
            stats["card matched to the only unmatched instance of its letter"] += 1
        else:
            stats["card with no instance"] += 1
            extra_cards.append({"card": card["name"], "why": "card with no instance"})

    nets_of = {}  # (instance id, pin) -> deck net (lower case)
    dot_pin = {m["instanceId"]: m["dotPin"] for k in doc.get("inductorCouplings", []) for m in k["members"]}
    devices, uncarded = [], []
    for iid, r in insts.items():
        inst, cdef = r["inst"], r["cdef"]
        if inst["type"] in MARKERS:
            continue
        card = card_of.get(iid)
        if card is None:
            uncarded.append(inst.get("name") or inst["type"])
            stats["instance with no card: " + re.sub(r"-[0-9a-f]{16}$", "", inst["type"])] += 1
            continue
        master = cells.get((card["master"] or "").lower())
        order = list((cdef.get("electrical") or {}).get("pinOrder") or [])
        if master and not card["kind"]:  # a call of a cell in the deck: ports by name
            node = {p.lower(): n for p, n in zip(master["ports"], card["nodes"])}
            port_pin = {p["pinName"].lower(): p["name"].lower() for p in (cdef.get("subcircuit") or {}).get("ports", []) if "pinName" in p}
            nets = {pin: node.get(port_pin.get(pin.lower(), pin.lower())) for pin in r["terms"]}
            if not any(nets.values()) and len(order) == len(card["nodes"]):
                nets = dict(zip(order, card["nodes"]))  # a generated body (ct_inductor, xfmr): by position
        else:
            if dot_pin.get(iid) and order[:1] != [dot_pin[iid]]:
                order = order[::-1]  # a coupled inductor's card starts at its dot pin
            nets = dict(zip(order, card["nodes"]))
        for pin in r["terms"]:
            n = nets.get(pin)
            nets_of[(iid, pin)] = n.lower() if n else None
            if n is None and pin != "B":
                stats["pin with no net from the card: %s.%s" % (re.sub(r"-[0-9a-f]{16}$", "", inst["type"]), pin)] += 1
        low = {k.lower(): v for k, v in r["terms"].items()}
        devices.append({
            "name": inst["name"], "card": card["name"], "type": inst["type"],
            "x": inst["coordinate"][0], "y": inst["coordinate"][1], "rotation": r["rot"], "mirror": r["mir"],
            "gate_side": gate_side(low), "source_dir": source_dir(low),
            "terminals": r["terms"], "nets": {p: nets_of[(iid, p)] for p in r["terms"]},
        })

    # wires: one polyline per Route; physical components by union-find over endpoints
    junction_at = {j["id"]: j["coordinate"] for j in doc["junctions"]}
    parent = {}

    def find(k):
        parent.setdefault(k, k)
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    def key_point(ep):
        if "terminal" in ep:
            k = ("t",) + tuple(ep["terminal"])
            return k, pin_at.get(tuple(ep["terminal"]))
        return ("j", ep["junction"]), junction_at.get(ep["junction"])

    lines = []
    for route in doc["routes"]:
        k0, p0 = key_point(route["start"])
        pts, k1 = [p0], None
        if "legs" in route:
            for leg in route["legs"]:
                if "coordinate" in leg:
                    pts.append(leg["coordinate"])
                else:
                    k1, p1 = key_point(leg)
                    pts.append(p1)
        else:
            k1, p1 = key_point(route["end"])
            pts.append(p1)
        if k1 is None or any(p is None for p in pts):
            stats["route skipped (unresolved endpoint)"] += 1
            continue
        parent[find(k0)] = find(k1)
        lines.append((k0, [[a, b] for a, b in zip(pts, pts[1:]) if a != b]))
    for group in doc["connections"].get("contacts", []):
        keys = [key_point(ep)[0] for ep in group]
        for k in keys[1:]:
            parent[find(keys[0])] = find(k)

    comp_nets = collections.defaultdict(set)
    for (iid, pin), net in nets_of.items():
        if net:
            comp_nets[find(("t", iid, pin))].add(net)
    conflicts = sum(1 for s in comp_nets.values() if len(s) > 1)
    if conflicts:
        stats["circuits where one drawn wire group carries two deck nets"] += 1

    def net_at(key):
        s = comp_nets.get(find(key), ())
        return sorted(s)[0] if len(s) == 1 else None

    markers = []
    for iid, r in insts.items():
        inst = r["inst"]
        if inst["type"] not in MARKERS:
            continue
        pin, at = next(iter(r["terms"].items()))
        t = term_of.get(iid, {})
        ev = claim.get(iid, {})
        name = t.get("name") or ev.get("name") or inst.get("name")
        net = net_at(("t", iid, pin)) or (name.lower() if name and MARKERS[inst["type"]] == "port" else None)
        markers.append({"kind": MARKERS[inst["type"]], "type": inst["type"], "name": name,
                        "direction": t.get("direction"), "at": at, "net": net})
    labels = []
    for a in doc["annotations"]:
        anchor = a.get("anchor", {})
        at = anchor.get("fallbackPosition") or {}
        at = [at.get("x"), at.get("y")]
        obj = anchor.get("objectId")
        name = (claim.get(a["id"]) or {}).get("name") or (term_of.get(a["id"]) or {}).get("name")
        if a.get("kind") == "power-label":  # a drawn supply rail: marker at the rail end the label sits on
            if obj in junction_at:
                at = junction_at[obj]
            markers.append({"kind": "supply", "type": "rail", "name": name, "direction": None, "at": at,
                            "net": net_at(("j", obj)) or (name.lower() if name else None)})
        elif a.get("kind") == "net-label":
            net = name.lower() if name else None
            labels.append({"net": net, "name": name, "at": at})
        else:
            stats["annotation kind ignored: %s" % a.get("kind")] += 1

    # Analog Canvas draws a VSS rail with the supply-rail tool: on the ground symbols' net, or named
    # like a ground, it is a ground marker (the name rule is cktImg's R1 list: inferred, not authored)
    ground_nets = {m["net"] for m in markers if m["kind"] == "ground" and m["net"]}
    for m in markers:
        if m["kind"] == "supply" and (m["net"] in ground_nets or re.match(r"(vss|gnd|vee|agnd|dgnd|0$)", (m["net"] or m["name"] or "").lower())):
            m["kind"] = "ground"
            stats["supply rail/marker on a ground net, counted as ground"] += 1
    # islands: groups of devices joined by drawn wires (labels and repeated symbols do not join)
    isl = {}

    def root(k):
        isl.setdefault(k, k)
        while isl[k] != k:
            isl[k] = isl[isl[k]]
            k = isl[k]
        return k
    for (iid, pin), net in nets_of.items():
        if iid in card_of and not (pin == "B" and "G" in insts[iid]["terms"]):
            isl[root(("dev", iid))] = root(find(("t", iid, pin)))
    islands = len({root(("dev", iid)) for iid in card_of})
    by_comp = collections.defaultdict(list)
    for k0, segs in lines:
        by_comp[find(k0)] += segs
    wires = [{"net": (sorted(comp_nets[c])[0] if len(comp_nets.get(c, ())) == 1 else None), "segments": segs}
             for c, segs in by_comp.items()]

    # how many separate drawn pieces carry each deck net's device pins (1 = wired through)
    pieces = collections.defaultdict(set)
    for (iid, pin), net in nets_of.items():
        if net and not (pin == "B" and "G" in insts[iid]["terms"]):  # a MOS body is not a drawn pin
            pieces[net].add(find(("t", iid, pin)))
    unit = 40.0
    for sid in ("nmos", "pmos"):
        if sid in defs:
            at = {p["name"]: p["at"] for p in defs[sid]["symbol"]["pins"]}
            unit = math.hypot(at["D"]["x"] - at["S"]["x"], at["D"]["y"] - at["S"]["y"])
            break
    human = {
        "unit": unit, "devices": devices, "markers": markers, "wires": wires,
        "junctions": [j["coordinate"] for j in doc["junctions"] if j.get("role", "branch") == "branch"],
        "labels": labels, "net_pieces": {n: len(c) for n, c in sorted(pieces.items())}, "islands": islands,
        "extra_cards": extra_cards, "uncarded": uncarded, "net_conflicts": conflicts,
        "no_connects": len(doc.get("noConnects", [])), "documents": len(project["documents"]),
    }
    return deck, human


def load_netlists(corpus, source):
    d = os.path.join(corpus, "netlists", source)
    out = {}
    for fn in sorted(os.listdir(d)):
        if fn.startswith("page-") and fn.endswith(".json"):
            for e in json.load(open(os.path.join(d, fn)))["entries"]:
                out[e["id"]] = e
    return out


def main(corpus, out, only):
    cases = os.path.join(out, "cases")
    os.makedirs(cases, exist_ok=True)
    stats, per_source = collections.Counter(), collections.Counter()
    for source in SOURCES:
        netlists = load_netlists(corpus, source)
        edir = os.path.join(corpus, source, "entries")
        for fn in sorted(os.listdir(edir)):
            cid = fn[:-5]
            if only and cid not in only:
                continue
            entry = json.load(open(os.path.join(edir, fn)))
            nl = netlists.get(cid)
            if not nl or not nl.get("netlist"):
                stats["entry without an official netlist"] += 1
                per_source[source + ": no netlist"] += 1
                continue
            before = stats.copy()
            try:
                deck, human = reduce_project(json.loads(entry["projectText"]), nl["netlist"], stats)
            except Exception as e:  # a malformed entry is recorded, never fatal
                stats["entry failed to convert: %s" % type(e).__name__] += 1
                per_source[source + ": failed"] += 1
                print("FAILED", cid, repr(e), file=sys.stderr)
                continue
            human = dict(id=cid, source=source, title=entry["entry"].get("name"), **human)
            human["notes"] = sorted(k for k in stats if stats[k] != before.get(k, 0))
            with open(os.path.join(cases, cid + ".cir"), "w") as f:
                f.write(deck)
            with open(os.path.join(cases, cid + ".human.json"), "w") as f:
                json.dump(human, f, separators=(",", ":"))
            per_source[source + ": converted"] += 1
    if not only:
        with open(os.path.join(out, "convert_stats.json"), "w") as f:
            json.dump({"per_source": dict(sorted(per_source.items())), "constructs": dict(stats.most_common())}, f, indent=1)
    for k, v in sorted(per_source.items()):
        print("%6d  %s" % (v, k))
    for k, v in stats.most_common():
        print("%6d  %s" % (v, k))


def demo():
    """Self-check: pin geometry of a mirrored/rotated NMOS, and the PDK rewrite."""
    pins = {"d": (10, -20), "g": (-20, 0), "s": (10, 20)}
    at = lambda rot, mir: {k: transform(v, (100, 100), rot, mir) for k, v in pins.items()}
    assert gate_side(at(0, "none")) == "left" and source_dir(at(0, "none")) == "down"
    assert gate_side(at(0, "horizontal")) == "right" and source_dir(at(0, "horizontal")) == "down"
    assert gate_side(at(90, "none")) == "up" and source_dir(at(90, "none")) == "left"
    assert gate_side(at(180, "none")) == "right" and source_dir(at(180, "none")) == "up"
    assert at(270, "horizontal")["g"] == [100, 120]  # rotate first, then mirror
    s = collections.Counter()
    deck, top, _ = rewrite_deck(
        ".subckt dut a b\nXM1 a b c c sky130_fd_pr__nfet_01v8 l=1\nXT2 a b c sky130_fd_pr__pnp_05v5_W0p68L0p68 m=1\n"
        "M1 a b c c foo\nX9 a b\n+ zzz\n.ends dut\n", "dut", s)
    assert deck.startswith("* ") and "MM1 a b c c nch l=1" in deck and "QXT2 a b c qpnp m=1" in deck and ".model qpnp pnp" in deck, deck
    assert [c["name"] for c in top["cards"]] == ["mm1", "qxt2", "m1", "x9"] and s["unmapped X master: zzz"] == 1


if __name__ == "__main__":
    demo()
    main(sys.argv[1], sys.argv[2], set(sys.argv[3:]))
