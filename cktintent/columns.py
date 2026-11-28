"""Left to right: where each branch runs and where each lane part sits.

    assign_columns(c, k) -> Layout

Reads the contract only. A *unit* is what moves as one thing along x:
    a column   upright devices the contract puts in one column (B3), plus two joints people
               draw as a column and the contract does not promise: the same-polarity pair
               at a fold node, and an inverter's two devices
    a lane     a part that lies flat on a flow, a switch, or a block
Units gather into clusters: a declared stage, what is joined to it by branch current, or
each joined group on its own. Clusters stand in flow order (F1); inside one, a matched pair
and its images stand mirrored about one axis (M3x), with what the contract puts on the axis
(M4). A part hanging on a rail goes next to the unit that holds its other end. Lane parts on
different flow lines may share x: each line is a lane of its own.
"""
import collections
from . import symbols

PAIR_OUT, PAIR_IN, PITCH, MARGIN = 40, 60, 120, 60     # half pitch of a pair (gates out / in), unit pitch, edge


class Layout:
    """x: {device: px} (a column's branch line, a lane part's centre); lane: {device: lane index}
    for lane parts; groups: the axis groups; notes."""
    __slots__ = ("x", "lane", "groups", "notes")


def _units(c, k, flow_devs):
    """-> ({name: unit root}, {root: [names in deck order]}, set of lane unit roots)"""
    lane = {v.name for v in c.devs if v.name not in k.upright and (v.kind == "blk" or v.name in flow_devs) and v.name not in k.around}
    parent = {v.name: v.name for v in c.devs if v.name in k.upright or v.name in lane}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    used = set()                                       # (device, 'top'|'bot'): that end already continues a column
    for rule, kind, p, text in k.relations:
        if kind == "same_col" and p[0].name in k.upright and p[2].name in k.upright:
            parent[find(p[0].name)] = find(p[2].name)
            net = p[0].net(p[1])
            for d in (p[0], p[2]):
                used.add((d.name, "top" if k.top.get(d.name) == net else "bot"))
    for net, pins in c.net_pins.items():               # a column people draw at a node of three or more
        if net in k.view.rails:
            continue
        ts = [v for v, p in pins if v.kind == "t" and p in ("d", "s") and v.name in k.upright]
        tops = [v for v in ts if k.top.get(v.name) == net]
        bots = [v for v in ts if k.bot.get(v.name) == net]
        if len(tops) + len(bots) < 3:
            continue
        same = [(b, t) for b in bots for t in tops if b.pol == t.pol and b is not t]
        gate = [(b, t) for b in bots for t in tops if b.pol != t.pol and b.net("g") == t.net("g") and b.net("g") != net]
        for cands in (same, gate):
            if len(cands) == 1:
                b, t = cands[0]
                if (b.name, "bot") not in used and (t.name, "top") not in used and find(b.name) != find(t.name):
                    parent[find(b.name)] = find(t.name)
                    used.update(((b.name, "bot"), (t.name, "top")))
    members = collections.defaultdict(list)
    for v in c.devs:
        if v.name in parent:
            members[find(v.name)].append(v.name)
    return {n: find(n) for n in parent}, members, {find(n) for n in lane}


def _clusters(c, k, unit_of, members):
    """{unit root: cluster name}: its stage, else the stage it is joined to by branch current,
    else a cluster of its own with everything joined to it."""
    stage = dict(k.view.stage_of)
    cluster = {}
    for u, ms in members.items():
        named = [stage[m] for m in ms if m in stage]
        if named:
            cluster[u] = named[0]
    adj = collections.defaultdict(set)
    for net, pins in c.net_pins.items():
        if net in k.view.rails:
            continue
        us = sorted({unit_of[v.name] for v, p in pins if v.name in unit_of and not (v.kind == "t" and p == "g") and v.kind != "blk"})
        for a in us:
            adj[a].update(x for x in us if x != a)
    order = {v.name: i for i, v in enumerate(c.devs)}
    todo = collections.deque(sorted(cluster, key=lambda u: order[members[u][0]]))
    while todo:                                    # a stage spreads over what is joined to it
        u = todo.popleft()
        for w in sorted(adj[u], key=lambda x: order[members[x][0]]):
            if w not in cluster:
                cluster[w] = cluster[u]
                todo.append(w)
    for u in sorted(members, key=lambda u: order[members[u][0]]):
        if u in cluster:
            continue
        cluster[u] = "~" + c.by[members[u][0]].card
        todo = collections.deque([u])
        while todo:
            x = todo.popleft()
            for w in adj[x]:
                if w not in cluster:
                    cluster[w] = cluster[u]
                    todo.append(w)
    return cluster


def _topo(items, before, key):
    """Order `items` so that a comes before every b in before[a], the smallest key first among
    those free to go; a cycle is cut at its smallest member. -> (order, cut members)"""
    items = list(items)
    inside = set(items)
    indeg = collections.Counter()
    for a in items:
        for b in before.get(a, ()):
            if b in inside and b != a:
                indeg[b] += 1
    out, done, cut = [], set(), []
    pending = sorted(items, key=key)
    for _ in range(len(items)):
        pick = next((x for x in pending if x not in done and indeg[x] == 0), None)
        if pick is None:
            pick = next(x for x in pending if x not in done)
            cut.append(pick)
        done.add(pick)
        out.append(pick)
        for b in before.get(pick, ()):
            if b in inside and b != pick:
                indeg[b] -= 1
    return out, cut


def _distance(c, k, start):
    """Fewest shared off-rail nets from device `start` to every other device."""
    dist, todo = {start: 0}, collections.deque([start])
    while todo:
        x = todo.popleft()
        for p, net in c.by[x].nets.items():
            if net is None or net in k.view.rails:
                continue
            for v, q in c.net_pins.get(net, ()):
                if v.name not in dist:
                    dist[v.name] = dist[x] + 1
                    todo.append(v.name)
    return dist


def _flow(c, k):
    """-> (devices named on a flow, lane index of each, [(devices, devices)] arrows, input nets)"""
    devs, lane, arrows, inputs = set(), {}, [], {}
    for rule, kind, p, text in k.relations:
        if kind == "not_left":
            arrows.append(([d.name for d in p[0]], [d.name for d in p[1]]))
            for d in list(p[0]) + list(p[1]):
                devs.add(d.name)
        elif kind == "port_in":
            inputs.setdefault(p[0], [d.name for d in p[1]])
    for i, chain in enumerate(k.view.k.flows):         # the lane of a part is the first flow line naming it
        for names in chain:
            for n in names:
                v = k.view.card.get(n)
                if v is not None and n not in k.view.k.stages:
                    lane.setdefault(v.name, i)
                    devs.add(v.name)
    return devs, lane, arrows, inputs


def _half(c, u, members, lane_units):
    """Half the width a unit takes along x, in px."""
    if u not in lane_units:
        return MARGIN
    v = c.by[members[u][0]]
    return (symbols.block_size(v)[0] if v.kind == "blk" else 20) + 30


def assign_columns(c, k):
    """-> Layout. See the module header."""
    flow_devs, lane_of, arrows, inputs = _flow(c, k)
    unit_of, members, lane_units = _units(c, k, flow_devs)
    cluster = _clusters(c, k, unit_of, members)
    order = {v.name: i for i, v in enumerate(c.devs)}
    notes = []
    first = lambda u: order[members[u][0]]
    # ---- must-stand-left-of, between clusters and between units of one cluster
    c_before, u_before = collections.defaultdict(set), collections.defaultdict(set)

    def before(a, b):
        if a not in unit_of or b not in unit_of:
            return
        ua, ub = unit_of[a], unit_of[b]
        if cluster[ua] != cluster[ub]:
            c_before[cluster[ua]].add(cluster[ub])
        elif ua != ub:
            u_before[ua].add(ub)
    for A, B in arrows:
        for a in A:
            for b in B:
                before(a, b)
    rank = {}                                          # how far along the flow a device is named
    for A, B in arrows:
        for n in A:
            rank.setdefault(n, len(rank))
        for n in B:
            rank.setdefault(n, len(rank))
    host = {}                                          # a hanging part's unit -> the unit it stands next to
    for u, ms in members.items():
        v = c.by[ms[0]]
        if len(ms) != 1 or u in lane_units or v.name in flow_devs:
            continue
        nets = [n for n in (k.top.get(v.name), k.bot.get(v.name)) if n is not None and n not in k.view.rails]
        if len(nets) != 1:
            continue
        net = nets[0]
        others = [w for w, p in c.net_pins.get(net, ()) if w is not v and w.name in unit_of]
        if not others:
            continue
        source = v.kind in ("v", "i") and net in inputs
        if source:                                     # the source of an input stands before what it feeds
            for w in others:
                before(v.name, w.name)
            continue
        on_flow = sorted((w for w in others if w.name in rank), key=lambda w: rank[w.name])
        if on_flow:                                    # between the flow part that makes its node and the next
            before(on_flow[0].name, v.name)
            for w in on_flow[1:]:
                before(v.name, w.name)
        host[u] = unit_of[min(others, key=lambda w: (w.kind != "t", order[w.name])).name]
    names = sorted(set(cluster.values()), key=lambda n: min(first(u) for u in members if cluster[u] == n))
    c_order, cut = _topo(names, c_before, key=names.index)
    notes += ["flow order of stage %s could not be kept: the stages form a loop" % x for x in cut]
    # ---- axis groups: a matched pair, its images, what stands on the axis
    side, axis_of, groups = {}, {}, []
    inward = {frozenset((p[0].name, p[1].name)) for r, kind, p, t in k.relations if kind == "gates" and p[2] == "inward"}
    for a, b in k.axes:
        if a not in unit_of or b not in unit_of:
            continue
        ua, ub = unit_of[a], unit_of[b]
        if ua == ub or ua in axis_of or ub in axis_of or cluster[ua] != cluster[ub] or ua in lane_units or ub in lane_units:
            continue
        if order[a] > order[b]:
            a, b, ua, ub = b, a, ub, ua
        g = {"pair": (a, b), "left": [ua], "right": [ub], "on": [], "half0": PAIR_IN if frozenset((a, b)) in inward else PAIR_OUT}
        axis_of[ua] = axis_of[ub] = len(groups)
        da, db = _distance(c, k, a), _distance(c, k, b)
        images = []
        for rule, kind, p, text in k.relations:
            if kind == "mirrored" and {p[2].name, p[3].name} == {a, b}:
                u, w = p[0].name, p[1].name
                if u not in unit_of or w not in unit_of:
                    continue
                uu, uw = unit_of[u], unit_of[w]
                if uu == uw or uu in axis_of or uw in axis_of or cluster[uu] != cluster[ua] or cluster[uw] != cluster[ua]:
                    continue
                near_a = (da.get(u, 99), order[u]) < (db.get(u, 99), order[w])
                l, r = (uu, uw) if near_a else (uw, uu)
                images.append((min(da.get(u, 99), db.get(u, 99)), order[u], l, r))
                axis_of[uu] = axis_of[uw] = len(groups)
        for dist, o, l, r in sorted(images):
            g["left"].append(l)
            g["right"].append(r)
        for rule, kind, p, text in k.relations:
            if kind == "on_axis" and {p[1].name, p[2].name} == {a, b} and p[0].name in unit_of:
                u = unit_of[p[0].name]
                if u not in axis_of:
                    axis_of[u] = len(groups)
                    g["on"].append(u)
        groups.append(g)
    # ---- order the blocks of each cluster, then lay everything out left to right
    out = Layout()
    out.x, out.lane, out.groups, out.notes = {}, {}, [], notes
    ends = collections.defaultdict(int)                # lane index (None: every column) -> right edge so far
    edge_of = {}                                       # unit -> its right edge, for flow predecessors
    preds = collections.defaultdict(set)
    for A, B in arrows:
        for a in A:
            for b in B:
                if a in unit_of and b in unit_of and unit_of[a] != unit_of[b]:
                    preds[unit_of[b]].add(unit_of[a])
    for cname in c_order:
        blocks, seen = [], set()
        for u in sorted((u for u in members if cluster[u] == cname), key=first):
            gi = axis_of.get(u)
            key = ("g", gi) if gi is not None else ("u", u)
            if key not in seen:
                seen.add(key)
                blocks.append(key)
        rep = {}
        for key in blocks:
            for u in ([key[1]] if key[0] == "u" else groups[key[1]]["left"] + groups[key[1]]["right"] + groups[key[1]]["on"]):
                rep[u] = key
        b_before = collections.defaultdict(set)
        for ua, ubs in u_before.items():
            for ub in ubs:
                if ua in rep and ub in rep and rep[ua] != rep[ub]:
                    b_before[rep[ua]].add(rep[ub])

        def key_of(key):                               # a hanging part sorts right after its host
            if key[0] == "u" and key[1] in host and host[key[1]] in rep:
                h = rep[host[key[1]]]
                return (blocks.index(h), 1, blocks.index(key))
            return (blocks.index(key), 0, 0)
        b_order, cut = _topo(blocks, b_before, key=key_of)
        for key in b_order:
            wall = max(ends.values(), default=0)
            if key[0] == "u":
                u = key[1]
                half = _half(c, u, members, lane_units)
                if u in lane_units:
                    ln = lane_of.get(members[u][0], 0)
                    left = max([ends[None], ends[ln]] + [edge_of[p] for p in preds[u] if p in edge_of])
                    x = left + half
                    ends[ln] = x + half
                    out.lane[members[u][0]] = ln
                else:
                    x = wall + half
                    for ln in list(ends) + [None]:
                        ends[ln] = x + half
                for m in members[u]:
                    out.x[m] = x
                edge_of[u] = x + half
                continue
            g = groups[key[1]]
            halves = [g["half0"] + i * PITCH for i in range(len(g["left"]))]
            axis = wall + MARGIN + halves[-1]
            for h, l, r in zip(halves, g["left"], g["right"]):
                for m in members[l]:
                    out.x[m] = axis - h
                for m in members[r]:
                    out.x[m] = axis + h
            for u in g["on"]:
                for m in members[u]:
                    out.x[m] = axis
            for ln in list(ends) + [None]:
                ends[ln] = axis + halves[-1] + MARGIN
            for u in g["left"] + g["right"] + g["on"]:
                edge_of[u] = ends[None]
            out.groups.append({"axis": axis, "pair": g["pair"],
                               "left": [m for u in g["left"] for m in members[u]],
                               "right": [m for u in g["right"] for m in members[u]]})
        if any(u not in lane_units for u in members if cluster[u] == cname):
            wall = max(ends.values(), default=0) + 40  # air after a cluster that holds a column
            for ln in list(ends) + [None]:
                ends[ln] = wall
    assert set(out.x) == set(unit_of), sorted(set(unit_of) - set(out.x))
    return out
