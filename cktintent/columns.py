"""Left to right: where each branch runs and where each lane part sits.

    assign_columns(c, k) -> Layout

Reads the contract only. A *unit* is what moves as one thing along x:
    a column   upright devices the contract puts in one column (B3), plus the joints people
               draw as a column and the contract does not promise: the same-polarity pair
               at a fold node, an inverter's two devices, a string on a rail, and a load
               on a rail over one of the devices it loads
    a lane     a part that lies flat (a lead, a switch, a part named on a flow), or a block
Units gather into clusters: a declared stage, what is joined to it by branch current, or
each joined group on its own. Clusters stand in flow order (F1); inside one, a matched pair
and its images stand mirrored about one axis (M3x), with what the contract puts on the axis
(M4): see `axes`. A part hanging on a rail goes next to the unit that holds its other end. Lane parts on
different flow lines may share x: each line is a lane of its own.
"""
import collections
from . import symbols
from .axes import Axes, MARGIN


class Layout:
    """x: {device: px} (a column's branch line, a lane part's centre); lane: {device: lane index}
    for lane parts; groups: the axis groups; notes."""
    __slots__ = ("x", "lane", "groups", "notes")


def _units(c, k, flow_devs):
    """-> ({name: unit root}, {root: [names in deck order]}, set of lane unit roots)"""
    lane = {v.name for v in c.devs if v.name not in k.upright and v.name not in k.around
            and (v.kind == "blk" or v.name in flow_devs or v.name in k.flat)}
    parent = {v.name: v.name for v in c.devs if v.name in k.upright or v.name in lane}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    stage = k.view.stage_of
    used = set()                                       # (device, 'top'|'bot'): that end already continues a column
    for rule, kind, p, text in k.relations:
        if kind == "same_col" and p[0].name in k.upright and p[2].name in k.upright:
            parent[find(p[0].name)] = find(p[2].name)
            net = p[0].net(p[1])
            for d in (p[0], p[2]):
                used.add((d.name, "top" if k.top.get(d.name) == net else "bot"))
    for a, b in k.joints:                              # a series string on a rail is one column
        parent[find(a)] = find(b)
    for net, pins in c.net_pins.items():               # a column people draw at a node of three or more
        if net in k.view.rails:
            continue
        ts = [v for v, p in pins if v.kind == "t" and p in ("d", "s") and v.name in k.upright]
        tops = [v for v in ts if k.top.get(v.name) == net]
        bots = [v for v in ts if k.bot.get(v.name) == net]
        if not tops or not bots:
            continue
        mates = lambda b, t: b is not t and stage.get(b.name) == stage.get(t.name)   # never across two stages
        same = [(b, t) for b in bots for t in tops if b.pol == t.pol and mates(b, t)]
        gate = [(b, t) for b in bots for t in tops if b.pol != t.pol and b.net("g") == t.net("g") and b.net("g") != net and mates(b, t)]
        for cands in (gate, same):                     # an inverter first: a pass device on its output stands aside
            if len(cands) == 1:
                b, t = cands[0]
                if (b.name, "bot") not in used and (t.name, "top") not in used and find(b.name) != find(t.name):
                    parent[find(b.name)] = find(t.name)
                    used.update(((b.name, "bot"), (t.name, "top")))
    image, stands = {}, {}                             # a part on a rail stands in the column of a device it loads
    for u, w, a, b in k.images:
        image.setdefault(u, w)
        image.setdefault(w, u)
    for v in c.devs:
        if v.kind not in ("r", "l", "i", "d") or v.name not in k.upright:
            continue
        t, b = k.top[v.name], k.bot[v.name]
        if (t in k.view.rails) == (b in k.view.rails):
            continue
        net, mine, theirs, ends = (b, "bot", "top", k.top) if t in k.view.rails else (t, "top", "bot", k.bot)
        cands = [d.name for d, p in c.net_pins.get(net, ()) if d.kind == "t" and d.name in k.upright
                 and ends.get(d.name) == net and (d.name, theirs) not in used and stage.get(d.name) == stage.get(v.name)]
        if (v.name, mine) in used or not cands or sum(c.by[n].net("s") == net for n in cands) > 1:
            continue                                   # under two sources it is a tail: it stands between them
        twin = image.get(stands.get(image.get(v.name)))            # where its image stands, mirrored
        pick = twin if twin in cands else cands[0]
        parent[find(v.name)] = find(pick)
        used.update(((v.name, mine), (pick, theirs)))
        stands[v.name] = pick
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


def assign_columns(c, k, room=None):
    """-> Layout. See the module header. `room` {device: (px, px)} asks for that much more
    clear space on the left and on the right of the device's column."""
    room = room or {}
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
    paired = {unit_of[n] for pair in k.axes for n in pair if n in unit_of}
    host = {}                                          # a hanging part's unit -> the unit it stands next to
    for u, ms in members.items():
        if u in lane_units or u in paired or any(c.by[m].kind == "blk" or m in flow_devs for m in ms):
            continue
        ends = collections.Counter(n for m in ms for n in (k.top.get(m), k.bot.get(m)) if n is not None and n not in k.view.rails)
        free = [n for n, times in ends.items() if times == 1]    # a net two members share is inside the string
        if len(free) != 1:
            continue
        net = free[0]
        v = c.by[next(m for m in ms if net in (k.top.get(m), k.bot.get(m)))]
        others = [w for w, p in c.net_pins.get(net, ()) if w.name not in ms and w.name in unit_of]
        if not others:
            continue
        source = v.kind == "v" or (v.kind == "i" and net in inputs)
        if source:                                     # a signal's source stands before what it feeds
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
    ax = Axes(c, k, unit_of, members, cluster, lane_units, room)
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
    twin, stage = {}, k.view.stage_of                  # `match stage stage`: a device -> its copy in the other stage
    for r, kind, p, t in k.relations:
        if kind == "mirrored" and stage.get(p[0].name) != stage.get(p[1].name):
            for u, w in ((p[0].name, p[1].name), (p[2].name, p[3].name)):
                twin[u], twin[w] = w, u
    placed = set()
    for cname in c_order:
        blocks, rep = [], {}
        for u in sorted((u for u in members if cluster[u] == cname), key=first):
            key = ("g", ax.root(ax.of[u])) if u in ax.of else ("u", u)
            if key not in blocks and key not in placed:
                blocks.append(key)
        for key in blocks:
            for u in ([key[1]] if key[0] == "u" else ax.units(key[1])):
                rep[u] = key
        copies = [key for key in blocks if all(twin.get(members[u][0]) in out.x for u in rep if rep[u] == key)]
        if copies:                                     # the other stage stands already: this one is its mirror image
            us = [u for key in copies for u in rep if rep[u] == key]
            xs = [out.x[twin[members[u][0]]] for u in us]
            axis = -(-(max(ends.values(), default=0) + MARGIN + max(xs)) // 20) * 10
            for u in us:
                t = twin[members[u][0]]
                out.x.update((m, 2 * axis - out.x[t]) for m in members[u])
                if t in out.lane:
                    out.lane[members[u][0]] = out.lane[t]
            for ln in list(ends) + [None]:
                ends[ln] = 2 * axis - min(xs) + MARGIN
            for u in us:
                edge_of[u] = ends[None]
            for key in copies:
                if key[0] == "g":
                    ax.record(key[1], out.x, out.groups)
            mine = [m for u in us for m in members[u]]
            a0 = min(mine, key=lambda m: order[twin[m]] if m in twin else len(order))
            out.groups.append({"axis": axis, "pair": (twin[a0], a0), "left": [twin[m] for m in mine if m in twin],
                               "right": mine, "cols": []})
            placed.update(copies)
            blocks = [key for key in blocks if key not in copies]
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
        placed.update(b_order)
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
                    more = [max(room.get(m, (0, 0))[side] for m in members[u]) for side in (0, 1)]
                    x = wall + half + more[0]
                    for ln in list(ends) + [None]:
                        ends[ln] = x + half + more[1]
                for m in members[u]:
                    out.x[m] = x
                edge_of[u] = max(ends[None], x + half)
                continue
            axis = wall + ax.width(key[1])             # a matched pair with all that mirrors about it
            ax.lay(key[1], axis, out.x, out.groups)
            for ln in list(ends) + [None]:
                ends[ln] = axis + ax.width(key[1])
            for u in ax.units(key[1]):
                edge_of[u] = ends[None]
        if any(u not in lane_units for u in members if cluster[u] == cname):
            wall = max(ends.values(), default=0) + 40  # air after a cluster that holds a column
            for ln in list(ends) + [None]:
                ends[ln] = wall
    assert set(out.x) == set(unit_of), sorted(set(unit_of) - set(out.x))
    return out
