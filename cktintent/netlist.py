"""SPICE deck in, circuit schema out (no geometry yet).

    read_netlist(text) -> (schema dict, statement text, notes)

The schema is the drawing schema of `circuit.Ckt` with every terminal at (0, 0): devices with
their type, pins and nets, plus `ports` (the top cell's port nets). Lines starting `*@` are
statements for `controls.parse`; they come back as text, in deck order.

Read: `R C L D V I E F G H B S M Q J X` cards, `.subckt/.ends`, `.model`, `+` continuation,
`*` and `;` comments. The circuit drawn is the top level when it holds a device card, else
the last `.subckt`. An `X` instance is one block; its pins take the child cell's port names.
Anything else is skipped and reported in `notes`. Net names fold to lower case.
"""
import re

# card letter -> (schema type, node count, schema pin names)
TWO_PIN = {
    "R": ("resistor", ("1", "2")), "C": ("capacitor", ("1", "2")), "L": ("inductor", ("1", "2")),
    "D": ("diode", ("A", "K")), "V": ("voltage-source", ("+", "-")), "I": ("current-source", ("+", "-")),
    "E": ("vcvs", ("+", "-")), "G": ("vccs", ("+", "-")), "F": ("cccs", ("+", "-")),
    "H": ("ccvs", ("+", "-")), "B": ("voltage-source", ("+", "-")), "S": ("ideal-switch", ("1", "2")),
}
P_TYPES = ("pmos", "pnp", "pjf", "pfet")
AMP_IN = re.compile(r"^(v?in[+\-pn]?|v?i[pn]|inp|inn|in_[pn]|vp|vn|\+|-)$")
AMP_OUT = re.compile(r"^(v?o(ut)?[+\-pn]?)$")
RAIL = re.compile(r"^(vdd|vcc|avdd|dvdd|vss|gnd|vee|0|agnd|dgnd)")


def _join(text):
    """Deck lines with `+` continuations joined and trailing `;` comments cut."""
    lines = []
    for raw in text.splitlines():
        line = raw.split(";", 1)[0].rstrip()
        if line.lstrip().startswith("+") and lines:
            lines[-1] += " " + line.lstrip()[1:]
        else:
            lines.append(line)
    return lines


def _polarity(model, models):
    """'p' or 'n' for a transistor's model name: from its `.model` line, else from the name."""
    kind = models.get(model.lower(), "")
    name = model.lower()
    if any(kind.startswith(p) for p in P_TYPES):
        return "p"
    if kind:
        return "n"
    return "p" if name.startswith("p") or "pch" in name or "pmos" in name or "pfet" in name or "pnp" in name else "n"


def _device(tokens, models, cells, notes):
    """One card -> a schema device, or None when the card is not a device."""
    name, letter = tokens[0], tokens[0][0].upper()
    args = [t for t in tokens[1:] if "=" not in t]
    dev = {"name": name, "card": name.lower(), "x": 0, "y": 0, "rotation": 0, "mirror": "none",
           "gate_side": None, "source_dir": None}

    def finish(kind, pins, nodes):
        dev["type"] = kind
        dev["nets"] = {p: n.lower() for p, n in zip(pins, nodes)}
        dev["terminals"] = {p: [0, 0] for p in pins}
        return dev

    if letter in TWO_PIN:
        kind, pins = TWO_PIN[letter]
        if len(args) < 2:
            notes.append("skipped `%s`: a %s needs two nodes" % (" ".join(tokens), kind))
            return None
        if letter == "B" and any(t.lower().startswith("i=") for t in tokens):
            kind = "current-source"
        return finish(kind, pins, args[:2])
    if letter == "M":
        if len(args) < 5:
            notes.append("skipped `%s`: a MOS card is `M d g s b model`" % " ".join(tokens))
            return None
        return finish("pmos" if _polarity(args[4], models) == "p" else "nmos", ("D", "G", "S", "B"), args[:4])
    if letter == "J":
        if len(args) < 4:
            notes.append("skipped `%s`: a JFET card is `J d g s model`" % " ".join(tokens))
            return None
        return finish("pjfet" if _polarity(args[3], models) == "p" else "njfet", ("D", "G", "S"), args[:3])
    if letter == "Q":
        if len(args) < 4:
            notes.append("skipped `%s`: a BJT card is `Q c b e model`" % " ".join(tokens))
            return None
        return finish("pnp" if _polarity(args[-1], models) == "p" else "npn", ("C", "B", "E"), args[:3])
    if letter == "X":
        if len(args) < 2:
            notes.append("skipped `%s`: an instance needs nodes and a cell name" % " ".join(tokens))
            return None
        nodes, cell = args[:-1], args[-1].lower()
        ports = cells.get(cell)
        if ports is None or len(ports) != len(nodes):
            if ports is not None:
                notes.append("`%s`: %d nodes for the %d ports of %s; pins named by position" % (name, len(nodes), len(ports), cell))
            ports = ["p%d" % (i + 1) for i in range(len(nodes))]
        low = [p.lower() for p in ports]
        signal = [p for p in low if not RAIL.match(p)]
        ins = [p for p in signal if AMP_IN.match(p)]
        outs = [p for p in signal if AMP_OUT.match(p)]
        amp = len(outs) == 1 and 1 <= len(ins) <= 2 and len(ins) + len(outs) == len(signal)
        dev["cell"] = cell
        return finish("opamp" if amp else "hierarchical-symbol-" + cell, ports, nodes)
    if letter != "K":
        notes.append("skipped `%s`: no such card letter" % " ".join(tokens))
    return None


def read_netlist(text, name="circuit"):
    """-> (schema, statements, notes). See the module header for what is read."""
    assert isinstance(text, str)
    models, cells, statements, notes = {}, {}, [], []
    top_cards, cell_cards, order, cur = [], {}, [], None
    lines = _join(text)
    for line in lines:                     # first pass: models and cell ports, so order does not matter
        t = line.split()
        if len(t) >= 3 and t[0].lower() == ".model":
            models[t[1].lower()] = t[2].lower().split("(")[0]
        elif len(t) >= 2 and t[0].lower() == ".subckt":
            ports = []
            for p in t[2:]:
                if p.lower().startswith("params:") or "=" in p:
                    break
                ports.append(p)
            cells[t[1].lower()] = ports
    for line in lines:
        s = line.strip()
        if s.startswith("*@"):
            statements.append(s[2:].strip())
            continue
        if not s or s[0] == "*":
            continue
        t = s.split()
        head = t[0].lower()
        if head == ".subckt" and len(t) >= 2:
            cur = t[1].lower()
            cell_cards[cur] = []
            order.append(cur)
        elif head == ".ends":
            cur = None
        elif head[0] == ".":
            continue
        elif cur is None:
            top_cards.append(t)
        else:
            cell_cards[cur].append(t)
    if top_cards and not any(c[0][0].upper() in "RCLDVIEFGHBSMQJX" and len(c) >= 3 for c in top_cards):
        notes += ["skipped `%s`: not a card" % " ".join(c) for c in top_cards]
        top_cards = []
    if top_cards:
        cards, ports, title = top_cards, [], name
    elif order:
        cards, ports, title = cell_cards[order[-1]], cells[order[-1]], order[-1]
    else:
        cards, ports, title = [], [], name
    devices, seen = [], set()
    for t in cards:
        d = _device(t, models, cells, notes)
        if d is None:
            continue
        if d["card"] in seen:
            notes.append("skipped `%s`: a second device named %s" % (" ".join(t), d["name"]))
            continue
        seen.add(d["card"])
        devices.append(d)
    schema = {"id": title, "title": title, "unit": 40.0, "devices": devices, "markers": [], "wires": [],
              "junctions": [], "labels": [], "net_pieces": {}, "ports": [p.lower() for p in ports]}
    return schema, "\n".join(statements), notes
