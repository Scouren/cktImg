"""Columns: where each upright device's branch runs, left to right.

    assign_columns(c, k) -> ({device name: x of its branch, px}, [axis groups], notes)

Reads the contract only. Devices the contract puts in one column (B3) are one unit. Units
gather into clusters: a declared stage, or the parts joined to it by branch current, or else
each joined group on its own. Clusters stand in flow order (F1), ties in deck order. Inside a
cluster a matched pair and its images stand mirrored about one axis (M3x), the nearest image
innermost, and what the contract puts on the axis (M4) stands on it.
"""
import collections

PAIR_OUT, PAIR_IN, PITCH, MARGIN = 40, 60, 120, 60     # half pitch of a pair (gates out / in), unit pitch, edge


def _units(c, k):
    """Union the devices of each B3 column. -> ({name: unit root}, {root: [names in deck order]})"""
    parent = {v.name: v.name for v in c.devs if v.name in k.upright}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for rule, kind, p, text in k.relations:
        if kind == "same_col" and p[0].name in parent and p[2].name in parent:
            parent[find(p[0].name)] = find(p[2].name)
    members = collections.defaultdict(list)
    for v in c.devs:
        if v.name in parent:
            members[find(v.name)].append(v.name)
    return {n: find(n) for n in parent}, members


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
        us = sorted({unit_of[v.name] for v, p in pins if v.name in unit_of and not (v.kind == "t" and p == "g")})
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
    """Stable topological order of `items` under `before` {a: {b, ...}}; a cycle is cut at its
    earliest member. -> (order, cut edges)"""
    indeg = collections.Counter()
    for a in items:
        for b in before.get(a, ()):
            if b in items and b != a:
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
            if b in items and b != pick:
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


def assign_columns(c, k):
    """-> (x of each upright device's branch, axis groups, notes).
    An axis group is {'axis': x, 'pair': (a, b), 'left': [...], 'right': [...]} in px."""
    unit_of, members = _units(c, k)
    cluster = _clusters(c, k, unit_of, members)
    order = {v.name: i for i, v in enumerate(c.devs)}
    notes = []
    first = lambda u: order[members[u][0]]
    # ---- flow: cluster before cluster, unit before unit
    c_before, u_before = collections.defaultdict(set), collections.defaultdict(set)
    for rule, kind, p, text in k.relations:
        if kind != "not_left":
            continue
        for a in p[0]:
            for b in p[1]:
                if a.name not in unit_of or b.name not in unit_of:
                    continue
                ua, ub = unit_of[a.name], unit_of[b.name]
                if cluster[ua] != cluster[ub]:
                    c_before[cluster[ua]].add(cluster[ub])
                elif ua != ub:
                    u_before[ua].add(ub)
    names = sorted(set(cluster.values()), key=lambda n: min(first(u) for u in members if cluster[u] == n))
    c_order, cut = _topo(names, c_before, key=names.index)
    notes += ["flow order of stage %s could not be kept: the stages form a loop" % x for x in cut]
    # ---- axis groups: a matched pair, its images, what stands on the axis
    side, axis_of, groups = {}, {}, []              # unit -> 'L'/'R'/'A', unit -> group index
    inward = {frozenset((p[0].name, p[1].name)) for r, kind, p, t in k.relations if kind == "gates" and p[2] == "inward"}
    for a, b in k.axes:
        if a not in unit_of or b not in unit_of:
            continue
        ua, ub = unit_of[a], unit_of[b]
        if ua == ub or ua in axis_of or ub in axis_of or cluster[ua] != cluster[ub]:
            continue
        if order[a] > order[b]:
            a, b, ua, ub = b, a, ub, ua
        g = {"pair": (a, b), "left": [ua], "right": [ub], "on": [], "half0": PAIR_IN if frozenset((a, b)) in inward else PAIR_OUT}
        axis_of[ua] = axis_of[ub] = len(groups)
        side[ua], side[ub] = "L", "R"
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
            side[l], side[r] = "L", "R"
        for rule, kind, p, text in k.relations:
            if kind == "on_axis" and {p[1].name, p[2].name} == {a, b} and p[0].name in unit_of:
                u = unit_of[p[0].name]
                if u not in axis_of:
                    axis_of[u] = len(groups)
                    side[u] = "A"
                    g["on"].append(u)
        groups.append(g)
    # ---- order blocks inside each cluster, then lay them out left to right
    X, cursor, out_groups = {}, 0, []
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
        b_order, cut = _topo(blocks, b_before, key=blocks.index)
        for key in b_order:
            if key[0] == "u":
                x = cursor + MARGIN
                for m in members[key[1]]:
                    X[m] = x
                cursor = x + MARGIN
                continue
            g = groups[key[1]]
            halves = [g["half0"] + i * PITCH for i in range(len(g["left"]))]
            axis = cursor + MARGIN + halves[-1]
            for h, l, r in zip(halves, g["left"], g["right"]):
                for m in members[l]:
                    X[m] = axis - h
                for m in members[r]:
                    X[m] = axis + h
            for u in g["on"]:
                for m in members[u]:
                    X[m] = axis
            cursor = axis + halves[-1] + MARGIN
            out_groups.append({"axis": axis, "pair": g["pair"],
                               "left": [m for u in g["left"] for m in members[u]],
                               "right": [m for u in g["right"] for m in members[u]]})
        cursor += 40                                # air between clusters
    assert set(X) == set(unit_of), sorted(set(unit_of) - set(X))
    return X, out_groups, notes
