"""The circuit model: devices, their pins and nets, in the drawing schema.

One schema serves three things: a netlist with no geometry yet, a drawing this tool made,
and a drawing a person made (the corpus's `human.json`). `Ckt` reads any of them.
Lengths are in symbol units (`unit`, a MOS drain-to-source length, 40 px); y grows down.
Structure comes from connectivity only; geometry is measured, never used to decide what a
device is.
"""
import collections, re

MOS = {"nmos": "n", "pmos": "p", "depletion-nmos": "n", "depletion-pmos": "p", "njfet": "n", "pjfet": "p"}
BJT = {"npn": "n", "pnp": "p"}
TWO = {"resistor": "r", "capacitor": "c", "inductor": "l", "inductor-compact": "l", "diode": "d",
       "zener-diode": "d", "schottky-diode": "d", "led": "d", "current-source": "i", "voltage-source": "v",
       "battery": "v", "vccs": "i", "cccs": "i", "vcvs": "v", "ccvs": "v", "variable-capacitor": "c",
       "variable-resistor": "r", "ideal-switch": "sw", "simple-switch": "sw", "closed-switch": "sw",
       "crystal": "x", "microphone": "v", "speaker": "r"}
SUPPLY_RE = re.compile(r"^(vdd|vcc|avdd|dvdd|vddh|vddl|vdda|vddd|vpp|v\+|\+\d+v?|vin_?supply|vbat|vs\+)")
BLOCK_OUT = re.compile(r"^(v?o(ut)?[+\-pn12]?|y|q)$")
GROUND_RE = re.compile(r"^(0|gnd|vss|agnd|dgnd|vee|v-|vssa|vssd|ground)$")




class Dev:
    """One device. kind: t (transistor), blk (block), or a two-pin kind (r c l d i v sw x);
    pol: n or p for a transistor; nets and pins are keyed d g s (b) for a transistor, a b for
    a two-pin part, the lower-cased pin names for a block. x, y, pins are in symbol units;
    vertical says the channel or the part runs up and down (None: not drawn yet)."""
    __slots__ = ("name", "type", "card", "kind", "pol", "x", "y", "pins", "nets", "gate_side", "source_dir",
                 "rot", "mir", "vertical")

    def pin(self, p):
        """Where pin `p` is drawn, or None."""
        return self.pins.get(p)

    def net(self, p):
        """The net on pin `p`, or None for a pin the device does not have or that is open."""
        return self.nets.get(p)

    def __repr__(self):
        return "%s(%s)" % (self.name, self.kind + (self.pol or ""))


class Ckt:
    """A circuit read from the drawing schema `h` (see the module header). devs in deck order;
    by: name -> Dev; net_pins: net -> [(Dev, pin)]; rails, supply, ground: nets a marker or
    their name says are rails; port_nets: the cell's ports; ports: net -> where a port is drawn."""

    def __init__(self, h):
        u = float(h.get("unit") or 40.0)
        self.id, self.unit, self.h = h["id"], u, h
        self.title = (h.get("title") or "").split("·", 1)[-1].strip()
        self.devs = []
        for d in h["devices"]:
            v = Dev()
            v.name, v.type, v.card = d["name"], d["type"], (d.get("card") or d["name"]).lower()
            t = d["type"]
            v.pol = None
            raw_p = {k: (p[0] / u, p[1] / u) for k, p in d["terminals"].items()}
            raw_n = dict(d["nets"])
            if t in MOS or t in BJT:
                v.kind, v.pol = "t", (MOS.get(t) or BJT.get(t))
                m = {"D": "d", "G": "g", "S": "s", "B": "b"} if t in MOS else {"C": "d", "B": "g", "E": "s"}
                v.pins = {m[k]: p for k, p in raw_p.items() if k in m}
                v.nets = {m[k]: n for k, n in raw_n.items() if k in m}
            elif t in TWO:
                v.kind = TWO[t]
                ks = list(raw_p)
                v.pins = {"a": raw_p[ks[0]], "b": raw_p[ks[1]]}
                v.nets = {"a": raw_n.get(ks[0]), "b": raw_n.get(ks[1])}
            else:
                v.kind = "blk"
                v.pins = {k.lower(): p for k, p in raw_p.items()}
                v.nets = {k.lower(): n for k, n in raw_n.items()}
            v.x, v.y = d["x"] / u, d["y"] / u
            v.gate_side, v.source_dir = d.get("gate_side"), d.get("source_dir")
            v.rot, v.mir = d.get("rotation"), d.get("mirror")
            v.vertical = None
            if v.kind != "blk" and v.kind != "t":
                a, b = v.pins["a"], v.pins["b"]
                v.vertical = abs(a[1] - b[1]) > abs(a[0] - b[0])
            elif v.kind == "t":
                v.vertical = v.source_dir in ("up", "down")
            self.devs.append(v)
        self.by = {v.name: v for v in self.devs}
        # nets -> [(dev, pin)] (a MOS body is not a drawn pin)
        self.net_pins = collections.defaultdict(list)
        for v in self.devs:
            for p, n in v.nets.items():
                if n and not (v.kind == "t" and p == "b"):
                    self.net_pins[n].append((v, p))
        self.markers = [dict(m, at=(m["at"][0] / u, m["at"][1] / u)) for m in h["markers"] if m.get("at") and m["at"][0] is not None]
        self.supply, self.ground = set(), set()
        for m in self.markers:
            if m["net"]:
                if m["kind"] == "supply":
                    self.supply.add(m["net"])
                elif m["kind"] == "ground":
                    self.ground.add(m["net"])
        for n in self.net_pins:
            if n not in self.supply and n not in self.ground:
                if GROUND_RE.match(n):
                    self.ground.add(n)
                elif SUPPLY_RE.match(n):
                    self.supply.add(n)
        self.supply -= self.ground
        self.rails = self.supply | self.ground
        self.ports = collections.defaultdict(list)  # net -> [(direction, at)]: where a drawing shows a port
        for m in self.markers:
            if m["kind"] == "port" and m["net"]:
                self.ports[m["net"]].append((m["direction"], m["at"]))
        # the nets that are ports of the cell: stated by a netlist, else read off the drawing's markers
        self.port_nets = set(h["ports"]) if h.get("ports") is not None else set(self.ports)
        self.pieces = h.get("net_pieces", {})
        self.labels = collections.defaultdict(list)
        for l in h.get("labels", []):
            if l.get("net") and l["at"][0] is not None:
                self.labels[l["net"]].append((l["at"][0] / u, l["at"][1] / u))
        self.wires = h.get("wires", [])
        xs = [p[0] for v in self.devs for p in v.pins.values()]
        ys = [p[1] for v in self.devs for p in v.pins.values()]
        self.bbox = (min(xs), min(ys), max(xs), max(ys)) if xs else (0, 0, 0, 0)

    # ---- connectivity helpers
    def ts(self):
        """The transistors, in deck order."""
        return [v for v in self.devs if v.kind == "t"]

    def on(self, net, pin=None, kind=None):
        """The devices with a pin on `net`, optionally only that pin name or that device kind."""
        return [v for v, p in self.net_pins.get(net, []) if (pin is None or p == pin) and (kind is None or v.kind == kind)]

    def degree(self, net):
        """How many drawn pins the net has."""
        return len(self.net_pins.get(net, []))

    def is_rail(self, n):
        """True for a supply or a ground net."""
        return n in self.rails

    def wired(self, net):
        """True when every drawn pin of the net is on one wire piece."""
        return self.pieces.get(net, 1) == 1

    def clean(self):
        """True for a corpus drawing fit to measure: every device carded, no net conflict, two devices or more."""
        h = self.h
        return h.get("net_conflicts", 0) == 0 and not h.get("uncarded") and len(self.devs) >= 2


def diode_connected(v):
    """True for a transistor whose gate is on its own drain."""
    return v.kind == "t" and v.net("g") is not None and v.net("g") == v.net("d")


def same(a, b, tol=0.26):
    """True when two lengths (symbol units) differ by no more than `tol`: a quarter unit, the scatter of a hand drawing."""
    return abs(a - b) <= tol




def mates_from(c, a, b):
    """Extend the swap a<->b over the branch skeleton (channels and two-pin parts), from
    connectivity only. Returns {device name: mate name}; a device mapped to itself is fixed
    by the swap. Gates are followed only between two different image nets; rails and bias
    lines (a net that is its own image) are never walked through by a gate."""
    dm, nm = {}, {}

    def sig(n):
        out = []
        for v, p in c.net_pins.get(n, []):
            if v.kind == "t":
                if p in ("d", "s"):
                    out.append((v.type, p))
            elif v.kind == "blk":
                out.append((v.type, "out" if p.startswith(("out", "vout")) or p in ("y", "o") else "in" if p.startswith(("in", "vin", "vip")) or p in ("+", "-", "a") else "other"))
            else:
                out.append((v.type, "p"))
        return sorted(out)

    def ok_net(x, y):
        if x is None or y is None:
            return True
        if x != y and ((x in c.rails) or (y in c.rails) or sig(x) != sig(y)):
            return False
        return nm.get(x, y) == y and nm.get(y, x) == x

    def set_net(x, y):
        if x is not None and y is not None:
            nm[x], nm[y] = y, x

    def pins_of(u, w, swap):
        if u.kind == "t":
            return [("d", "d"), ("s", "s")]
        return [("a", "b"), ("b", "a")] if swap else [("a", "a"), ("b", "b")]

    def consistent(u, w, swap):
        return all(ok_net(u.net(p), w.net(q)) for p, q in pins_of(u, w, swap))

    def bind(u, w, swap):
        dm[u.name], dm[w.name] = w.name, u.name
        for p, q in pins_of(u, w, swap):
            set_net(u.net(p), w.net(q))
        if u.kind == "t" and ok_net(u.net("g"), w.net("g")):
            set_net(u.net("g"), w.net("g"))

    if a.kind != "t" or not consistent(a, b, False):
        return dm
    bind(a, b, False)
    for _ in range(4 * len(c.devs) + 4):
        changed = False
        for n, m in list(nm.items()):
            if n in c.rails:
                continue
            for u, p in c.net_pins.get(n, []):
                if u.name in dm or u.kind == "blk":
                    continue
                if u.kind == "t" and p == "g" and n == m:
                    continue
                cands = {}
                for w, q in c.net_pins.get(m, []):
                    if w.type != u.type or (w.name in dm and w is not u) or w.kind == "blk":
                        continue
                    if u.kind == "t":
                        if q == p and consistent(u, w, False) and (p != "g" or w is not u):
                            cands[w.name] = (w, False)
                    else:
                        for swap in (False, True):
                            if q == (("b" if p == "a" else "a") if swap else p) and consistent(u, w, swap):
                                if w is u and not swap and u.net("a") != u.net("b") and not (nm.get(u.net("a")) == u.net("a") and nm.get(u.net("b"), u.net("b")) == u.net("b")):
                                    continue
                                cands.setdefault(w.name, (w, swap))
                if len(cands) > 1 and u.kind == "t" and u.net("g") is not None:
                    # twins in parallel branches: the one on the same control line, or on its image
                    told = {n: t for n, t in cands.items() if t[0].net("g") in (u.net("g"), nm.get(u.net("g")))}
                    cands = told if len(told) == 1 else cands
                if len(cands) == 1:
                    w, swap = next(iter(cands.values()))
                    bind(u, w, swap)
                    changed = True
        if not changed:
            break
    return dm
