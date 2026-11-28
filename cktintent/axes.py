"""Axis groups: a matched pair, its images and what stands on its axis, as mirrored columns.

    ax = Axes(c, k, unit_of, members, cluster, lane_units, room)
    ax.of[unit] -> group index;  ax.root(gi), ax.units(gi), ax.width(gi)
    ax.lay(gi, axis, x, out)     place the group about `axis`;  ax.record(gi, x, out)  describe it as placed

A group is {pair, left, right, on, half0, sub, parent}: `left[i]` and `right[i]` are the two
units of mirrored column i (0 is the pair itself), `on` the units on the axis. A pair whose
on-axis part is itself half of another pair stands over that half: it becomes that group's
`sub` on that side (a Gilbert cell's two switching pairs over its input pair), and the outer
pair's two halves then stand far enough apart for both.
"""
import collections

PAIR_OUT, PAIR_IN, PITCH, MARGIN = 40, 60, 120, 60     # half pitch of a pair (gates out / in), unit pitch, edge


def _distance(c, k, start, branch=False):
    """Fewest shared off-rail nets from device `start` to every other device; with `branch`,
    counted through channels and two-pin parts only (a gate carries no current)."""
    def pins(v):
        return [n for p, n in v.nets.items() if n and not (branch and v.kind == "t" and p not in ("d", "s"))]
    dist, todo = {start: 0}, collections.deque([start])
    while todo:
        x = todo.popleft()
        for net in pins(c.by[x]):
            if net in k.view.rails:
                continue
            for v, q in c.net_pins.get(net, ()):
                if v.name not in dist and net in pins(v):
                    dist[v.name] = dist[x] + 1
                    todo.append(v.name)
    return dist


class Axes:
    """The axis groups of one circuit: `groups` (see the module header) and `of`, the group
    index of every unit that stands in one. Built once; `room` is {device: (px, px)} of extra
    clear space wanted left and right of its column."""

    def __init__(self, c, k, unit_of, members, cluster, lane_units, room):
        self.members, self.room, self.groups, self.of = members, room, [], {}
        order = {v.name: i for i, v in enumerate(c.devs)}
        inward = {frozenset((p[0].name, p[1].name)) for r, kind, p, t in k.relations if kind == "gates" and p[2] == "inward"}
        inward |= {frozenset(p) for p in k.cross}
        mirrors = [(p[0].name, p[1].name, p[2].name, p[3].name) for r, kind, p, t in k.relations if kind == "mirrored"]
        on_axis = [(p[0].name, p[1].name, p[2].name) for r, kind, p, t in k.relations if kind == "on_axis"] + k.tails
        own = {frozenset((pa, pb)) for tail, pa, pb in on_axis if c.by[tail].kind in ("t", "i", "r")}   # pairs with a tail of their own
        of, under = self.of, {}
        paired = {n for a, b in k.axes if a in unit_of and b in unit_of and cluster[unit_of[a]] == cluster[unit_of[b]]
                  for n in (a, b)}                     # the pairs that can stand about an axis of their own
        over = {frozenset((pa, pb)) for tail, pa, pb in on_axis if tail in paired}   # pairs that stand over half of another
        for a, b in sorted(k.axes, key=lambda pair: frozenset(pair) not in over):     # those first: they keep their columns
            if a not in unit_of or b not in unit_of:
                continue
            ua, ub = unit_of[a], unit_of[b]
            if ua == ub or ua in of or ub in of or cluster[ua] != cluster[ub] or ua in lane_units or ub in lane_units:
                continue
            if order[a] > order[b]:
                a, b, ua, ub = b, a, ub, ua
            tight = any(frozenset((m, n)) in inward for m in members[ua] for n in members[ub])   # gates between the two columns
            gi = len(self.groups)
            g = {"pair": (a, b), "left": [ua], "right": [ub], "on": [], "half0": PAIR_IN if tight else PAIR_OUT,
                 "sub": [None, None], "parent": None}
            of[ua] = of[ub] = gi
            near = [(_distance(c, k, n, True), _distance(c, k, n)) for n in (a, b)]
            images = []
            for u, w, pa, pb in mirrors + k.images:    # the contract's mirrors, then every other image in the cluster
                if {pa, pb} != {a, b} or u not in unit_of or w not in unit_of or frozenset((u, w)) in own:
                    continue                           # a pair with its own tail stands as its own group
                uu, uw = unit_of[u], unit_of[w]
                if uu == uw or uu in of or uw in of or cluster[uu] != cluster[ua] or cluster[uw] != cluster[ua]:
                    continue
                if uu in lane_units or uw in lane_units:
                    continue
                da, db = [tuple(d.get(u, 99) for d in side) + (o,) for side, o in zip(near, (order[u], order[w]))]
                l, r = (uu, uw) if da < db else (uw, uu)
                images.append((min(da[:2], db[:2]), order[u], l, r))
                of[uu] = of[uw] = gi
            for dist, o, l, r in sorted(images):
                g["left"].append(l)
                g["right"].append(r)
            for tail, pa, pb in on_axis:
                if {pa, pb} == {a, b} and tail in unit_of:
                    u = unit_of[tail]
                    if tail in paired:
                        under[gi] = u                  # its on-axis part is half of another pair
                    elif u not in of:
                        of[u] = gi
                        g["on"].append(u)
            self.groups.append(g)
        for gi in sorted(under):                       # stand each such pair over that half
            u, g = under[gi], self.groups[gi]
            pi = of.get(u)
            if pi is None or pi == gi:
                continue
            p = self.groups[pi]
            side = 0 if p["left"][0] == u else 1 if p["right"][0] == u else None
            if side is None or p["sub"][side] is not None or self.root(pi) == gi:
                continue
            p["sub"][side], g["parent"] = gi, pi

    def root(self, gi):
        """The outermost group that `gi` stands in."""
        for _ in range(len(self.groups)):
            if self.groups[gi]["parent"] is None:
                break
            gi = self.groups[gi]["parent"]
        return gi

    def units(self, gi):
        """Every unit of the group and of the groups standing over its halves."""
        g = self.groups[gi]
        out = g["left"] + g["right"] + g["on"]
        for s in g["sub"]:
            if s is not None:
                out = out + self.units(s)
        return out

    def _more(self, units, side):
        """The most room any member of these units asks for on `side` (0 left, 1 right)."""
        return max([self.room.get(m, (0, 0))[side] for u in units for m in self.members[u]] + [0])

    def _halves(self, gi):
        """[px]: mirrored column i stands this far from the axis."""
        g, out = self.groups[gi], []
        over = [self._reach(s) if s is not None else 0 for s in g["sub"]]
        for i, (l, r) in enumerate(zip(g["left"], g["right"])):
            inner = max(self._more([l], 1), self._more([r], 0))
            if i == 0:
                h = g["half0"] + inner
                if any(s is not None for s in g["sub"]):       # the pairs over its halves clear each other
                    h = max(h, -(-(over[0] + over[1] + PITCH) // 20) * 10)
            else:
                outer = max(self._more([g["left"][i - 1]], 0), self._more([g["right"][i - 1]], 1))
                h = out[-1] + (max(over) if i == 1 else 0) + PITCH + inner + outer
            out.append(h)
        return out

    def _reach(self, gi):
        """px from the group's axis to its outermost branch line."""
        g, hs = self.groups[gi], self._halves(gi)
        over = max([self._reach(s) for s in g["sub"] if s is not None] + [0])
        return hs[-1] + (over if len(hs) == 1 else 0)

    def width(self, gi):
        """px from the group's axis to the edge of the space it takes."""
        g = self.groups[gi]
        return self._reach(gi) + MARGIN + max(self._more([g["left"][-1]], 0), self._more([g["right"][-1]], 1))

    def lay(self, gi, axis, x, out):
        """Write the x of every member into `x`, then `record` the group."""
        g, hs, names = self.groups[gi], self._halves(gi), self.members
        for h, l, r in zip(hs, g["left"], g["right"]):
            x.update((m, axis - h) for m in names[l])
            x.update((m, axis + h) for m in names[r])
        for u in g["on"]:
            x.update((m, axis) for m in names[u])
        for side, s in enumerate(g["sub"]):
            if s is not None:
                self.lay(s, axis + (hs[0] if side else -hs[0]), x, None)
        if out is not None:
            self.record(gi, x, out)

    def record(self, gi, x, out):
        """Append the group, and first those standing over its halves, to `out` as the placer
        and the router read them: {axis, pair, left, right, cols}, sides as the x in `x` say.
        -> the names of everything in the group"""
        g, names = self.groups[gi], self.members
        a, b = g["pair"]
        axis = (x[a] + x[b]) // 2
        cols = [(names[l], names[r]) if x[names[l][0]] <= x[names[r][0]] else (names[r], names[l])
                for l, r in zip(g["left"], g["right"])]
        mine = [m for L, R in cols for m in L + R]
        for s in g["sub"]:
            if s is not None:
                mine += self.record(s, x, out)
        out.append({"axis": axis, "pair": (a, b), "left": [m for m in mine if x[m] < axis],
                    "right": [m for m in mine if x[m] > axis], "cols": cols})
        return mine + [m for u in g["on"] for m in names[u]]
