"""The connectivity view of a circuit under its statements: rails, clocks, stages, branch paths.

No geometry is read here. `contract.derive` builds one `View` and every later stage reads it
through `Contract.view`.
"""
import collections, re

GROUND_NAMES = re.compile(r"^(0|gnd|vss|vee|agnd|dgnd|gnda|gndd|vssa|vssd)$")
SUPPLY_NAMES = re.compile(r"^(vdd|vcc|avdd|dvdd|vdda|vddd|vddh|vddl)$")
BR = ("r", "l", "i", "v", "d", "sw", "x")
PAS = ("r", "c", "l", "d", "sw", "x")


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
        """The devices a statement names with `name`: a stage's devices, or one device; [] when unknown."""
        if name in self.k.stages:
            return [self.card[d] for d in self.k.stages[name] if d in self.card]
        v = self.card.get(name)
        return [v] if v is not None else []

    def is_net(self, name):
        """True when `name` is a net and neither a stage nor a device."""
        return name in self.c.net_pins and name not in self.k.stages and name not in self.card

    def branch_pins(self, net, skip=()):
        """[(Dev, pin)] on `net` that carry branch current: channel ends and two-pin parts, not gates."""
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
