"""The solver contract: statements + netlist -> the relations a drawing must show.

`derive` reads connectivity and the statements only, never a position. It returns a
`Contract`: the relations (each with its rule id and a sentence in circuit terms), the notes
on refused lines, and the facts a placer needs (which parts stand upright or lie flat, which
net is the upper end of each upright part, which stage a device is in).
"""
import collections, re
from .circuit import BLOCK_OUT, diode_connected, mates_from
from .controls import ROLES

GROUND_NAMES = re.compile(r"^(0|gnd|vss|vee|agnd|dgnd|gnda|gndd|vssa|vssd)$")
SUPPLY_NAMES = re.compile(r"^(vdd|vcc|avdd|dvdd|vdda|vddd|vddh|vddl)$")
BR = ("r", "l", "i", "v", "d", "sw", "x")
PAS = ("r", "c", "l", "d", "sw", "x")
TOL = 0.3
SCOPE = "column"   # "column": a match mirrors the pair's own columns and its declared stage; "stage": everything in its stage (undeclared = the whole circuit)
RULES = collections.OrderedDict([
    ("B1", "a transistor stands upright, source toward its rail"),
    ("B1s", "a switch lies flat: no rail current through its channel, or clocked with a channel end on a capacitor, inductor, port or block"),
    ("B2", "a part with one end on a rail stands upright, that end toward the rail"),
    ("B3", "a transistor and the part in series with it (or a tapped divider) share a column"),
    ("B4", "a part between a device's output and its own input runs outside the device's lane"),
    ("B5", "a part with an end that feeds only gates, ports or capacitors lies flat"),
    ("B6", "a gate faces what drives it (an input gate faces its port)"),
    ("N1", "a signal net is one wire"),
    ("M1", "matched devices share a row"),
    ("M2", "matched gates: inward on a shared gate line or a cross pair, outward for a pair on one source node, else on opposite sides"),
    ("M3", "an upright image of a matched pair shares a row with its twin"),
    ("M3x", "upright images in the pair's own columns, or in its stage, mirror about the pair's axis"),
    ("M4", "what joins the two halves sits on the axis"),
    ("S1", "two stages do not interleave"),
    ("F1", "flow a -> b: b is not left of a"),
    ("F2", "flow ends: inputs enter on the left, outputs leave on the right (each on its own side of a matched pair)"),
    ("F3", "a two-pin part named on the flow lies flat"),
])


class View:
    """Connectivity view of a circuit under a set of controls (no geometry is read here)."""

    def __init__(self, c, k):
        self.c, self.k = c, k
        self.card = {}
        for v, d in zip(c.devs, c.h["devices"]):
            self.card[(d.get("card") or v.name).lower()] = v
        for v in c.devs:
            self.card.setdefault(v.name.lower(), v)
        role = k.roles
        self.ground = {n for n in c.net_pins if GROUND_NAMES.match(n) and n not in role} | {n for n, r in role.items() if r == "ground"}
        self.supply = {n for n in c.net_pins if SUPPLY_NAMES.match(n) and n not in role} | {n for n, r in role.items() if r == "supply"}
        self.rails = self.ground | self.supply
        self.clock = {n for n, r in role.items() if r == "clock"}
        self.stage_of = {}
        self.notes = list(k.errors)
        for name, devs in k.stages.items():
            for d in devs:
                v = self.card.get(d)
                if v is None:
                    self.notes.append("stage %s: no device named %s" % (name, d))
                elif v.name in self.stage_of:
                    self.notes.append("stage %s: %s is already in stage %s" % (name, d, self.stage_of[v.name]))
                else:
                    self.stage_of[v.name] = name
        for n in role:
            if n not in c.net_pins:
                self.notes.append("net %s: no such net" % n)
        self.adj = collections.defaultdict(list)
        for v in c.devs:
            if v.kind == "t":
                a, b = v.net("d"), v.net("s")
            elif v.kind in BR:
                a, b = v.net("a"), v.net("b")
            else:
                continue
            if a and b and a != b:
                self.adj[a].append((b, v)); self.adj[b].append((a, v))

    def devs_of(self, name):
        if name in self.k.stages:
            return [self.card[d] for d in self.k.stages[name] if d in self.card]
        v = self.card.get(name)
        return [v] if v is not None else []

    def is_net(self, name):
        return name in self.c.net_pins and name not in self.k.stages and name not in self.card

    def branch_pins(self, net, skip=()):
        return [(v, p) for v, p in self.c.net_pins.get(net, []) if v not in skip and ((v.kind == "t" and p in ("d", "s")) or v.kind in BR)]

    def reach(self, start, without):
        """Fewest branch parts from a net to a rail, not going through `without` (None: no route)."""
        seen = {start: 0}
        q = collections.deque([start])
        while q:
            u = q.popleft()
            if u in self.rails:
                return seen[u]
            for w, dev in self.adj[u]:
                if dev is without or w in seen:
                    continue
                seen[w] = seen[u] + 1
                q.append(w)
        return None

    def part_class(self, v, n1, n2):
        """lead: an end has no other branch route to a rail; stack: ends at different rail
        distances; bridge: ends at the same rail distance."""
        d1, d2 = self.reach(n1, v), self.reach(n2, v)
        if d1 is None or d2 is None:
            return "lead"
        return "bridge" if d1 == d2 else "stack"


class Contract:
    """What `derive` returns. A relation is (rule id, kind, payload, sentence)."""
    __slots__ = ("relations", "notes", "view", "upright", "flat", "top", "bot", "around", "axes")

    def __iter__(self):                    # (relations, notes) = derive(...) still unpacks
        return iter((self.relations, self.notes))


def derive(c, k):
    """-> Contract. Reads connectivity and the statements `k` only; no geometry."""
    V = View(c, k)
    R = []
    # ---------------------------------------------------------------- flow chains
    chains = []
    for chain in k.flows:
        row = []
        for names in chain:
            devs, nets = [], []
            for n in names:
                d = V.devs_of(n)
                if d:
                    devs += d
                elif V.is_net(n):
                    nets.append(n)
                else:
                    V.notes.append("flow: nothing named %s" % n)
            row.append((" ".join(names), devs, nets, names))
        chains.append(row)
    succ, arrows = collections.defaultdict(set), []

    def reaches(x, y):
        seen, todo = {x}, [x]
        while todo:
            u = todo.pop()
            if u == y:
                return True
            for w in succ[u]:
                if w not in seen:
                    seen.add(w); todo.append(w)
        return False
    for row in chains:
        for a, b in zip(row, row[1:]):
            if a[0] == b[0] or reaches(b[0], a[0]):
                V.notes.append("flow %s -> %s: refused, an earlier flow line already puts %s before %s" % (a[0], b[0], b[0], a[0]))
                continue
            succ[a[0]].add(b[0])
            arrows.append((a, b))
    named_on_flow = set()   # two-pin parts the flow passes through: one end on each neighbour
    for row in chains:
        for i, (label, devs, nets, names) in enumerate(row):
            if not (0 < i < len(row) - 1):
                continue
            def touch(e):
                out = set(e[2])
                for d in e[1]:
                    out.update(x for p, x in d.nets.items() if x and not (d.kind == "t" and p == "b"))
                return out
            before, after = touch(row[i - 1]), touch(row[i + 1])
            for n in names:
                v = V.card.get(n)
                if v is None or n in k.stages or v.kind not in PAS:
                    continue
                ea, eb = v.net("a"), v.net("b")
                if (ea in before and eb in after) or (eb in before and ea in after):
                    named_on_flow.add(v.name)
    # ---------------------------------------------------------------- baseline: how each part stands
    TWOPIN = ("r", "c", "l", "d", "sw", "x", "i", "v")
    upright, flat, top, bot = set(), set(), {}, {}
    # transistors named on a flow between the things at their two channel ends
    flow_through = set()
    for row in chains:
        for i, (label, devs, nets, names) in enumerate(row):
            if not (0 < i < len(row) - 1):
                continue
            def touch(e):
                out = set(e[2])
                for d in e[1]:
                    out.update(x for q, x in d.nets.items() if x and not (d.kind == "t" and q == "b"))
                return out
            before, after = touch(row[i - 1]), touch(row[i + 1])
            for n in names:
                v = V.card.get(n)
                if v is not None and n not in k.stages and v.kind == "t":
                    d, s = v.net("d"), v.net("s")
                    if (d in before and s in after) or (s in before and d in after):
                        flow_through.add(v.name)
    for v in c.devs:
        if v.kind != "t":
            continue
        d, s, g = v.net("d"), v.net("s"), v.net("g")
        if d and s and d != s and d not in V.rails and s not in V.rails:
            # with no rail known at all, nothing can be said about rail current
            rd, rs = (V.reach(d, v) is not None, V.reach(s, v) is not None) if V.rails else (True, True)
            clock = g in V.clock
            why = None
            def passive_end(n):
                return n in c.port_nets or any(x.kind in ("c", "l", "blk") for x, q in c.net_pins.get(n, []))
            if not rd and not rs:
                why = "neither channel end carries current to a rail"
            elif clock and (passive_end(d) or passive_end(s)):
                why = "clock %s switches it and a channel end carries a capacitor, an inductor, a port or a block" % g
            elif clock and v.name in flow_through:
                why = "clock %s switches it and the flow passes through its channel" % g
            if why:
                flat.add(v.name)
                R.append(("B1s", "flat", v, "%s is a switch (%s): it lies flat" % (v.name, why)))
                continue
        upright.add(v.name)
        if d and s:
            top[v.name], bot[v.name] = (d, s) if v.pol == "n" else (s, d)
        R.append(("B1", "upright_t", v, "%s stands upright, source toward its rail" % v.name))
    # two-pin parts: on a rail -> upright; an end that only feeds gates/ports/caps -> flat (a lead)
    def open_end(v, n):
        """True when nothing else on net n carries branch current (a rail-bound source counts as a signal origin)."""
        if n in V.rails or k.roles.get(n) in ("bias", "clock"):
            return False
        for d, q in c.net_pins.get(n, []):
            if d is v:
                continue
            if d.kind == "t" and q in ("d", "s"):
                return False
            if d.kind in ("r", "l", "i", "d", "sw", "x"):
                return False
            if d.kind == "v" and not (d.net("a") in V.rails or d.net("b") in V.rails):
                return False
        return True

    for v in c.devs:
        if v.kind == "t" or v.kind == "blk":
            continue
        na, nb = v.net("a"), v.net("b")
        if na is None or nb is None or na == nb:
            continue
        ra, rb = na in V.rails, nb in V.rails
        if ra != rb:
            end = "a" if ra else "b"
            is_supply = v.net(end) in V.supply
            upright.add(v.name)
            far = nb if ra else na
            top[v.name], bot[v.name] = (v.net(end), far) if is_supply else (far, v.net(end))
            R.append(("B2", "upright_rail", (v, end, is_supply), "%s has one end on rail %s: upright, that end toward the rail" % (v.name, v.net(end))))
        elif not ra and v.kind in PAS:
            if v.name in named_on_flow:
                flat.add(v.name)
                R.append(("F3", "flat", v, "%s is named on the flow, between its two neighbours: it lies flat, in line" % v.name))
            elif k.roles.get(na) in ("bias", "clock") or k.roles.get(nb) in ("bias", "clock"):
                pass
            elif open_end(v, na) or open_end(v, nb):
                flat.add(v.name)
                R.append(("B5", "flat", v, "%s has an end that feeds only gates, ports or capacitors: it lies flat, in line with the signal" % v.name))
    def block_out_on(net):
        return any(d.kind == "blk" and BLOCK_OUT.match(q) for d, q in c.net_pins.get(net, []))

    def leads_to_transistor(v):
        """True when the part is in series, through nets with no third branch pin, with a transistor's channel."""
        seen, todo = {v.name}, [v]
        while todo:
            x = todo.pop()
            for q in ("a", "b"):
                n = x.net(q)
                if n is None or n in V.rails:
                    continue
                br = V.branch_pins(n)
                if len(br) != 2 or x not in (br[0][0], br[1][0]) or br[0][0] is br[1][0]:
                    continue
                other = br[0][0] if br[1][0] is x else br[1][0]
                if other.kind == "t":
                    return True
                if other.name not in seen and other.kind in ("r", "l", "i", "d"):
                    seen.add(other.name); todo.append(other)
        return False

    # a part from a device's output back to its own input goes around the device, unless it is a branch part
    around = {}
    for v in c.devs:
        if v.kind not in PAS:
            continue
        na, nb = v.net("a"), v.net("b")
        if na in V.rails or nb in V.rails or na is None or nb is None or na == nb or v.name in named_on_flow:
            continue
        if leads_to_transistor(v):
            continue
        for d in c.devs:
            if d.kind == "t" and d.name in upright and {d.net("g"), d.net("d")} == {na, nb}:
                around[v.name] = (v, d, "the drain of %s to its gate" % d.name)
                break
            if d.kind == "blk":
                outs = [q for q in d.pins if BLOCK_OUT.match(q)]
                ins = [q for q in d.pins if q not in outs and d.net(q) not in V.rails]
                if any(d.net(o) in (na, nb) for o in outs) and any(d.net(i) in (na, nb) for i in ins) and {na, nb} <= {d.net(q) for q in d.pins}:
                    around[v.name] = (v, d, "the output of %s to its input" % d.name)
                    break
    for v, d, why in around.values():
        R.append(("B4", "outside_lane", (v, [d]), "%s joins %s: drawn outside its lane" % (v.name, why)))

    # series joints: an upright transistor's channel end meeting the opposite end of another upright part
    for _ in range(len(c.devs) + 2):
        changed = False
        for net in c.net_pins:
            if net in V.rails:
                continue
            br = V.branch_pins(net)
            if len(br) != 2 or br[0][0] is br[1][0]:
                continue
            (a, pa), (b, pb) = br
            if a.name in flat or b.name in flat:
                continue
            tap = any(d.kind == "blk" or (d.kind == "t" and q == "g") for d, q in c.net_pins[net] if d is not a and d is not b)
            divider = a.kind == "r" and b.kind == "r" and tap and not block_out_on(net) and a.name not in around and b.name not in around
            if not (a.kind == "t" or b.kind == "t" or divider):
                continue
            if "d" in (a.kind, b.kind) or "v" in (a.kind, b.kind) or "sw" in (a.kind, b.kind) or "x" in (a.kind, b.kind):
                continue
            for x, px, y, py in ((a, pa, b, pb), (b, pb, a, pa)):
                if x.name in top and y.name not in top and y.kind in ("r", "l", "i"):
                    other = y.net("b" if py == "a" else "a")
                    if top[x.name] == net:
                        top[y.name], bot[y.name] = other, net
                    else:
                        top[y.name], bot[y.name] = net, other
                    upright.add(y.name)
                    changed = True
        if not changed:
            break
    for net in c.net_pins:
        if net in V.rails:
            continue
        br = V.branch_pins(net)
        if len(br) > 2:
            # two transistor channel ends still form a column when only resistors tap their node
            ts_ = [(v, q) for v, q in br if v.kind == "t"]
            rest = [(v, q) for v, q in br if v.kind != "t"]
            if len(ts_) == 2 and all(v.kind == "r" and v.name not in top for v, q in rest):
                br = ts_
        if len(br) != 2 or br[0][0] is br[1][0]:
            continue
        (a, pa), (b, pb) = br
        if a.name in flat or b.name in flat or a.name not in top or b.name not in top:
            continue
        tap = any(d.kind == "blk" or (d.kind == "t" and q == "g") for d, q in c.net_pins[net] if d is not a and d is not b)
        if not (a.kind == "t" or b.kind == "t" or (a.kind == "r" and b.kind == "r" and tap and not block_out_on(net) and a.name not in around and b.name not in around)):
            continue
        if {a.kind, b.kind} & {"d", "v", "sw", "x"}:
            continue
        if (top[a.name] == net and bot[b.name] == net) or (bot[a.name] == net and top[b.name] == net):
            R.append(("B3", "same_col", (a, pa, b, pb), "%s and %s meet in series on %s: one column" % (a.name, b.name, net)))
    # ---------------------------------------------------------------- gates
    matched = set()
    for names in k.matches:
        for n in names:
            for d in V.devs_of(n):
                matched.add(d.name)
    for v in c.devs:
        if v.kind != "t" or v.name not in upright or v.name in matched:
            continue
        g = v.net("g")
        if not g or g == v.net("d") or g in V.rails or k.roles.get(g) in ("bias", "clock"):
            continue
        drivers = [(d, q) for d, q in c.net_pins.get(g, []) if d is not v and not (d.kind == "t" and q == "g")]
        if drivers:
            R.append(("B6", "gate_toward_pins", (v, drivers), "the gate of %s faces what drives net %s" % (v.name, g)))
        elif g in c.port_nets:
            R.append(("B6", "gate_toward_port", (v, g), "the gate of %s faces its port %s" % (v.name, g)))
    # ---------------------------------------------------------------- nets
    for n, r in k.roles.items():
        if r == "signal" and n in c.net_pins and len(c.net_pins[n]) >= 2:
            R.append(("N1", "wired", n, "net %s is a signal: one wire" % n))
    # ---------------------------------------------------------------- match
    axes = []   # (a, b) matched device pairs, for port sides
    image_axis = {}   # device name -> the matched pair whose swap moves it
    for names in k.matches:
        groups = [V.devs_of(n) for n in names]
        label = " ".join(names)
        if any(not g for g in groups):
            V.notes.append("match %s: refused, unknown name" % label)
            continue
        if all(n in k.stages for n in names):
            if len({len(g) for g in groups}) != 1:
                V.notes.append("match %s: refused, the stages hold different numbers of devices" % label)
                continue
            for tup in zip(*groups):
                if len({d.type for d in tup}) != 1:
                    V.notes.append("match %s: %s are different kinds of device" % (label, " ".join(d.name for d in tup)))
                    continue
                R.append(("M1", "same_row", list(tup), "%s are copies: one row" % " ".join(d.name for d in tup)))
            if len(groups) == 2:
                a0, b0 = groups[0][0], groups[1][0]
                axes.append((a0, b0))
                for u, w in list(zip(*groups))[1:]:
                    R.append(("M3", "mirrored", (u, w, a0, b0), "%s and %s mirror about the axis of %s and %s" % (u.name, w.name, a0.name, b0.name)))
            continue
        devs = [g[0] for g in groups]
        if len({d.type for d in devs}) != 1:
            V.notes.append("match %s: refused, different kinds of device (%s)" % (label, ", ".join(sorted({d.type for d in devs}))))
            continue
        R.append(("M1", "same_row", devs, "%s are matched: one row" % " ".join(d.name for d in devs)))
        if len(devs) != 2:
            continue
        a, b = devs
        axes.append((a, b))
        if a.kind == "t" and a.name in upright and b.name in upright:
            diode = diode_connected(a) or diode_connected(b)      # a diode-connected device has no gate to turn on its own
            cross = a.net("g") == b.net("d") and b.net("g") == a.net("d") and a.net("d") != b.net("d")
            shared = a.net("g") == b.net("g") and a.net("g") is not None
            if cross or (shared and k.roles.get(a.net("g")) not in ("bias", "clock") and a.net("g") not in V.rails):
                R.append(("M2", "gates", (a, b, "inward"), "%s and %s %s: gates face each other" % (a.name, b.name, "are cross-coupled" if cross else "share a gate line")))
            elif not shared and not diode and k.roles.get(a.net("g")) not in ("bias", "clock") and k.roles.get(b.net("g")) not in ("bias", "clock"):
                if a.net("s") == b.net("s") and a.net("s") not in V.rails:
                    R.append(("M2", "gates", (a, b, "outward"), "%s and %s are a pair on one source node with their own gate nets: gates face outward" % (a.name, b.name)))
                else:
                    R.append(("M2", "gates", (a, b, "flipped"), "%s and %s are mirror images: their gates are on opposite sides" % (a.name, b.name)))
        st = V.stage_of.get(a.name)
        if a.kind != "t":
            continue
        tail_dev = None
        if a.net("s") == b.net("s") and a.net("s") not in V.rails and a.net("s") is not None:
            tl = V.branch_pins(a.net("s"), skip=(a, b))
            if len(tl) == 1:
                tail_dev = tl[0][0]
                R.append(("M4", "on_axis", (tail_dev, a, b), "%s is the one part under both %s and %s: on their axis" % (tail_dev.name, a.name, b.name)))
        if st != V.stage_of.get(b.name):
            continue
        dm = mates_from(c, a, b)
        # the pair's own columns: what is reached from a or b through series joints
        joint = collections.defaultdict(set)
        for r in R:
            if r[1] == "same_col":
                joint[r[2][0].name].add(r[2][2].name); joint[r[2][2].name].add(r[2][0].name)
        colset, todo = {a.name, b.name}, [a.name, b.name]
        while todo:
            x0 = todo.pop()
            for y0 in joint[x0]:
                if y0 not in colset:
                    colset.add(y0); todo.append(y0)
        mate_nets = set()
        for x, y in dm.items():
            if x != y and x in c.by:
                d2 = c.by[x]
                mate_nets.update(d2.net(p) for p in (("d", "s", "g") if d2.kind == "t" else ("a", "b")))
        colnets = set()
        for x0 in colset:
            d2 = c.by[x0]
            colnets.update(d2.net(p) for p in (("d", "s") if d2.kind == "t" else ("a", "b")))
        for x, y in dm.items():
            if x not in c.by or y not in c.by:
                continue
            u, w = c.by[x], c.by[y]
            in_cols = x in colset and y in colset
            in_stage = st is not None and V.stage_of.get(u.name) == st and V.stage_of.get(w.name) == st
            if SCOPE == "stage":
                shared = V.stage_of.get(u.name) == st and V.stage_of.get(w.name) == st
            else:
                shared = in_cols or in_stage
            if x != y and shared:
                image_axis[u.name] = (a, b)
            if x < y and {x, y} != {a.name, b.name}:
                if SCOPE != "stage" and u.name in upright and w.name in upright:
                    # the row is promised for upright images only: flat twins follow the pins they feed
                    R.append(("M3", "same_row", [u, w], "%s and %s are images under %s<->%s: one row" % (u.name, w.name, a.name, b.name)))
                if shared and u.name in upright and w.name in upright:
                    R.append(("M3x", "mirrored", (u, w, a, b), "%s and %s are images under %s<->%s%s: mirrored about that axis" % (u.name, w.name, a.name, b.name, " in its columns" if in_cols else " in stage " + str(st))))
            elif x == y and (shared or SCOPE == "stage" or x in colset or True):
                ends = [u.net(p) for p in (("d", "s") if u.kind == "t" else ("a", "b"))]
                tail = False        # the tail is already placed above
                bridge = u.kind != "t" and ends[0] != ends[1] and all(e in mate_nets and e not in V.rails for e in ends)
                if bridge and SCOPE != "stage" and not (in_stage or all(e in colnets for e in ends)):
                    bridge = False
                if tail or bridge:
                    R.append(("M4", "on_axis", (u, a, b), "%s joins the two halves of %s/%s: on their axis" % (u.name, a.name, b.name)))
    # ---------------------------------------------------------------- stage
    names = list(k.stages)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = V.devs_of(names[i]), V.devs_of(names[j])
            if a and b:
                R.append(("S1", "apart", (a, b), "stages %s and %s do not interleave" % (names[i], names[j])))
    # ---------------------------------------------------------------- flow
    def axis_for(devs):
        for a, b in axes:
            if a in devs and b in devs:
                return (a, b)
        for d in devs:
            if d.name in image_axis:
                return image_axis[d.name]
        return None

    for a, b in arrows:
        if a[1] and b[1]:
            R.append(("F1", "not_left", (a[1], b[1]), "flow %s -> %s: %s is not left of %s" % (a[0], b[0], b[0], a[0])))
    for row in chains:
        first, last = row[0], row[-1]
        if first[2] and not first[1]:
            nxt = next((e[1] for e in row[1:] if e[1]), None)
            for n in first[2]:
                if nxt:
                    R.append(("F2", "port_in", (n, nxt, axis_for(nxt)), "input %s enters from the left%s" % (n, " or on its own half" if axis_for(nxt) else "")))
        if last[2] and not last[1]:
            prv = next((e[1] for e in reversed(row[:-1]) if e[1]), None)
            for n in last[2]:
                if prv:
                    R.append(("F2", "port_out", (n, prv, axis_for(prv)), "output %s leaves to the right%s" % (n, " or on its own half" if axis_for(prv) else "")))
    out = Contract()
    out.relations, out.notes, out.view = R, V.notes, V
    out.upright, out.flat, out.top, out.bot = upright, flat, top, bot
    out.around = {name: (v.name, d.name) for name, (v, d, why) in around.items()}
    out.axes = [(a.name, b.name) for a, b in axes]
    return out
