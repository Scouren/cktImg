"""Gates: is the drawing legal?  Each check reads the finished drawing and nothing else.

    extract(schema)  -> the nets the drawing shows, as sets of (device, pin)
    check(schema, c) -> findings: [(gate, sentence)]; empty means legal

    lvs      the nets read back from wires, names and rail symbols are the deck's nets:
             nothing open, nothing shorted
    overlap  no two symbols overlap
    pierce   no wire enters a symbol

`extract` shares no code with the router: it joins segments that touch, joins a pin to a
segment it lies on, and joins everything that carries one name. A wire crossing another
without ending on it does not join it.
"""
import collections
from . import symbols


def _on(p, s):
    """True when point p lies on segment s (ends included); segments may be slanted."""
    (x0, y0), (x1, y1) = s
    cross = (x1 - x0) * (p[1] - y0) - (y1 - y0) * (p[0] - x0)
    if cross != 0:
        return False
    return min(x0, x1) <= p[0] <= max(x0, x1) and min(y0, y1) <= p[1] <= max(y0, y1)


def _overlap(s, t):
    """True when two collinear segments share more than a point."""
    (ax, ay), (bx, by) = s
    (cx, cy), (dx, dy) = t
    if (bx - ax) * (dy - cy) - (by - ay) * (dx - cx) != 0:
        return False
    if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) != 0:
        return False
    key = (lambda p: p[0]) if ax != bx else (lambda p: p[1])
    lo, hi = max(min(key(s[0]), key(s[1])), min(key(t[0]), key(t[1]))), min(max(key(s[0]), key(s[1])), max(key(t[0]), key(t[1])))
    return hi > lo


def extract(schema):
    """-> ([set of (device name, pin)], {deck net: number of drawn pieces}).
    The nets of the drawing, read from geometry and names only."""
    segs = [(tuple(a), tuple(b)) for w in schema["wires"] for a, b in w["segments"]]
    parent = list(range(len(segs)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def join(i, j):
        parent[find(i)] = find(j)
    for i, s in enumerate(segs):
        for j in range(i + 1, len(segs)):
            t = segs[j]
            if _on(s[0], t) or _on(s[1], t) or _on(t[0], s) or _on(t[1], s) or _overlap(s, t):
                join(i, j)
    # every other thing is a point: a pin, a rail symbol, a port, a name
    points = []                                    # (point, key, name or None)
    for d in schema["devices"]:
        for pin, at in d["terminals"].items():
            if d["nets"].get(pin) is None or (pin == "B" and "G" in d["terminals"]):
                continue
            points.append((tuple(at), ("pin", d["name"], pin), None))
    for m in schema["markers"]:
        points.append((tuple(m["at"]), ("mark", len(points)), m["net"]))
    for l in schema["labels"]:
        points.append((tuple(l["at"]), ("name", len(points)), l["net"]))
    group = {}                                     # key -> union-find id beyond the segments

    def gid(key):
        if key not in group:
            group[key] = len(parent)
            parent.append(len(parent))
        return group[key]
    at_point, by_name = collections.defaultdict(list), collections.defaultdict(list)
    for p, key, name in points:
        g = gid(key)
        for i, s in enumerate(segs):
            if _on(p, s):
                join(g, i)
        at_point[p].append(g)
        if name is not None:
            by_name[name].append(g)
    for gs in list(at_point.values()) + list(by_name.values()):
        for g in gs[1:]:
            join(gs[0], g)
    nets = collections.defaultdict(set)
    for p, key, name in points:
        if key[0] == "pin":
            nets[find(gid(key))].add((key[1], key[2]))
    # pieces: how many wire-joined groups carry each deck net, before names join them
    return list(nets.values()), group, find


def check(schema, c):
    """-> [(gate, sentence)] for everything illegal in the drawing."""
    findings = []
    drawn, group, find = extract(schema)
    deck = collections.defaultdict(set)
    for d in schema["devices"]:
        for pin, net in d["nets"].items():
            if net is not None and not (pin == "B" and "G" in d["terminals"]):
                deck[net].add((d["name"], pin))
    where = {}
    for i, g in enumerate(drawn):
        for t in g:
            where[t] = i
    for net, pins in sorted(deck.items()):
        ids = {where[t] for t in pins}
        if len(ids) > 1:
            findings.append(("lvs", "open: net %s is drawn in %d pieces that nothing joins" % (net, len(ids))))
    net_of = {t: net for net, pins in deck.items() for t in pins}
    for g in drawn:
        names = sorted({net_of[t] for t in g})
        if len(names) > 1:
            findings.append(("lvs", "short: nets %s are joined in the drawing" % " and ".join(names)))
    boxes = []
    for d, v in zip(schema["devices"], c.devs):
        b = symbols.body(v, d["orient"])
        boxes.append((d["x"] + b[0], d["y"] + b[1], d["x"] + b[2], d["y"] + b[3], d["name"]))
    for i, a in enumerate(boxes):
        for b in boxes[i + 1:]:
            if a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]:
                findings.append(("overlap", "%s and %s overlap" % (a[4], b[4])))
    for w in schema["wires"]:
        for (x0, y0), (x1, y1) in w["segments"]:
            n = max(abs(x1 - x0), abs(y1 - y0)) // 5
            inner = [(x0 + (x1 - x0) * i / float(n), y0 + (y1 - y0) * i / float(n)) for i in range(1, n)]
            for bx0, by0, bx1, by1, name in boxes:
                if any(bx0 <= x <= bx1 and by0 <= y <= by1 for x, y in inner):
                    findings.append(("pierce", "a wire of net %s enters %s" % (w["net"], name)))
                    break
    return findings


def pieces(schema):
    """{deck net: how many separate wire groups carry its pins} (1 = wired through)."""
    segs = [(tuple(a), tuple(b)) for w in schema["wires"] for a, b in w["segments"]]
    parent = list(range(len(segs)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for i, s in enumerate(segs):
        for j in range(i + 1, len(segs)):
            t = segs[j]
            if _on(s[0], t) or _on(s[1], t) or _on(t[0], s) or _on(t[1], s) or _overlap(s, t):
                parent[find(i)] = find(j)
    out = collections.defaultdict(set)
    for d in schema["devices"]:
        for pin, at in d["terminals"].items():
            net = d["nets"].get(pin)
            if net is None or (pin == "B" and "G" in d["terminals"]):
                continue
            hit = [find(i) for i, s in enumerate(segs) if _on(tuple(at), s)]
            out[net].add(("w", hit[0]) if hit else ("p", tuple(at)))
    return {net: len(ids) for net, ids in out.items()}
