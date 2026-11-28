"""Rows: which level each upright device stands on.

    assign_rows(c, k) -> ({device name: row}, row count, notes)

Reads the contract only. Two facts order rows: a device whose lower net is another's upper
net stands above it (current flows down the page), and devices the contract puts in one row
(M1, M3) share one. Within that order a device hugs its rail: PMOS and supply-side parts take
the earliest row they may, NMOS and ground-side parts the latest. The gap a short column
leaves is in its middle, as people draw it.
"""
import collections


def _same_row_sets(k):
    for rule, kind, p, text in k.relations:
        if kind == "same_row":
            yield [d.name for d in p], text
        elif kind == "mirrored":
            yield [p[0].name, p[1].name], text
    for a, b in k.cross:
        yield [a, b], "%s and %s are cross-coupled: one row" % (a, b)


def assign_rows(c, k):
    """-> (row of each upright device, number of rows, notes on relations it had to drop)."""
    names = [v.name for v in c.devs if v.name in k.upright]
    notes = []
    parent = {n: n for n in names}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    # a device stands above another when its lower net is the other's upper net
    below = collections.defaultdict(set)          # name -> names that must stand lower
    by_top = collections.defaultdict(list)
    for n in names:
        by_top[k.top[n]].append(n)
    for n in names:
        net = k.bot.get(n)
        if net is None or net in k.view.rails:
            continue
        for m in by_top.get(net, ()):
            if m != n:
                below[n].add(m)

    def reaches(a, b):
        """True when some member of a's class must stand above some member of b's class."""
        target, seen = find(b), set()
        todo = [x for x in names if find(x) == find(a)]
        while todo:
            x = todo.pop()
            for y in below[x]:
                r = find(y)
                if r == target:
                    return True
                if r not in seen:
                    seen.add(r)
                    todo += [z for z in names if find(z) == r]
        return False

    for members, text in _same_row_sets(k):
        members = [m for m in members if m in parent]
        for m in members[1:]:
            a, b = find(members[0]), find(m)
            if a == b:
                continue
            if reaches(a, b) or reaches(b, a):
                notes.append("adjusted `%s`: one of them is in series above the other, so no shared row" % text)
                continue
            parent[b] = a
    classes = collections.defaultdict(list)
    for n in names:
        classes[find(n)].append(n)
    edges = collections.defaultdict(set)
    for n in names:
        for m in below[n]:
            if find(n) != find(m):
                edges[find(n)].add(find(m))
    # a loop of series parts (two diodes back to back) has no top: cut the edge that closes it
    deck = {n: i for i, n in enumerate(names)}
    first = lambda r: min(deck[m] for m in classes[r])
    state = {}                                      # class -> 1 while its descendants are being walked, 2 after
    for start in sorted(classes, key=first):
        if start in state:
            continue
        state[start], stack = 1, [(start, iter(sorted(edges[start], key=first)))]
        while stack:
            r, it = stack[-1]
            s = next(it, None)
            if s is None:
                state[r] = 2
                stack.pop()
            elif state.get(s) == 1:
                edges[r].discard(s)
                notes.append("a loop of series parts through %s: its row order is cut there" % classes[s][0])
            elif s not in state:
                state[s] = 1
                stack.append((s, iter(sorted(edges[s], key=first))))
    indeg = collections.Counter(s for r in classes for s in edges[r])
    # longest path from the top (asap)
    asap = {r: 0 for r in classes}
    order, ready, left = [], sorted((r for r in classes if indeg[r] == 0), key=first), dict(indeg)
    while ready:
        r = ready.pop(0)
        order.append(r)
        for s in sorted(edges[r], key=first):
            asap[s] = max(asap[s], asap[r] + 1)
            left[s] -= 1
            if left[s] == 0:
                ready.append(s)
    assert len(order) == len(classes), "the row order still holds a loop"
    rank = {r: i for i, r in enumerate(order)}
    height = max(asap.values(), default=0) + 1
    tail = {r: 0 for r in classes}                  # longest path down to a sink
    for r in reversed(order):
        for s in edges[r]:
            if rank[s] > rank[r]:
                tail[r] = max(tail[r], tail[s] + 1)
    alap = {r: height - 1 - tail[r] for r in classes}

    def pull(n):
        v = c.by[n]
        if v.kind == "t":
            return "up" if v.pol == "p" else "down"
        if k.top.get(n) in k.view.supply:
            return "up"
        if k.bot.get(n) in k.view.ground:
            return "down"
        return None

    row = {}
    for r, members in classes.items():
        votes = collections.Counter(p for p in map(pull, members) if p)
        if votes["up"] > votes["down"]:
            row[r] = asap[r]
        elif votes["down"]:
            row[r] = alap[r]
        else:
            row[r] = None
    for r in order:                                 # a part with no rail of its own follows what it hangs under
        if row[r] is None:
            above = [row[q] for q in order if r in edges[q] and row[q] is not None]
            row[r] = (max(above) + 1) if above else asap[r]
    for _ in range(len(classes) + 1):               # a ground-side part above a supply-side one: push down
        moved = False
        for r in order:
            for s in edges[r]:
                if rank[s] > rank[r] and row[s] <= row[r]:
                    row[s] = row[r] + 1
                    moved = True
        if not moved:
            break
    height = max(row.values(), default=0) + 1
    out = {n: row[find(n)] for n in names}
    assert all(0 <= r < height for r in out.values())
    return out, height, notes
