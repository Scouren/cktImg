"""Boxes: a stage that stands alone is drawn in a labelled box.

    boxes(schema, c, k) -> [{"name": label, "box": [x0, y0, x1, y1]}]        px

A stage stands alone when only names, ports and rail symbols join it to the rest: no wire
runs from one of its pins to a pin of a device outside it (a rail is not followed: it joins
everything). Its box takes in its symbols, their names, its wires, and the names, ports and
rail symbols on them, with PAD px of air. The label is the stage's name as the user wrote it.
A box is left out when anything foreign would stand inside it or another box would overlap
it: a box that held a stranger would say something false.

Reads the finished drawing only; it places and routes nothing.
"""
from . import symbols
from .gates import on, overlap

PAD = 20           # px of air between a stage's outermost mark and its box
STUB = 20          # px: a rail wire no longer than this, from a pin, is that pin's own stub


def _meets(a, b):
    """True when rectangles a and b (x0, y0, x1, y1) share any area or edge."""
    return a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]


def _extent(mark, kind):
    """(x0, y0, x1, y1) of a marker or a label as it is drawn."""
    x, y = mark["at"]
    if kind == "ground":
        return (x - 10, y, x + 10, y + 20)
    if kind == "supply":
        half = max(10, 3 * len(mark["name"]))
        return (x - half, y - 20, x + half, y)
    ex, ey = mark.get("side", [0, -1])
    b = symbols.text_box(x, y, ex, ey, mark["name"])
    return (min(b[0], x - 4), min(b[1], y - 4), max(b[2], x + 4), max(b[3], y + 4))


def boxes(schema, c, k):
    """-> the boxes to draw, in the order the stages were stated. See the module header."""
    rails = k.view.rails
    segs = [(tuple(a), tuple(b), w["net"]) for w in schema["wires"] for a, b in w["segments"]]
    live = [i for i, s in enumerate(segs) if s[2] not in rails]
    touch = {i: [] for i in live}
    for n, i in enumerate(live):
        for j in live[n + 1:]:
            s, t = segs[i][:2], segs[j][:2]
            if on(s[0], t) or on(s[1], t) or on(t[0], s) or on(t[1], s) or overlap(s, t):
                touch[i].append(j)
                touch[j].append(i)
    pins, bodies = {}, {}
    for d, v in zip(schema["devices"], c.devs):
        pins[v.name] = [(tuple(at), d["nets"].get(p)) for p, at in d["terminals"].items()
                        if d["nets"].get(p) is not None and not (p == "B" and "G" in d["terminals"])]
        b, t = symbols.body(v, d["orient"]), symbols.label_box(v, d["orient"])
        box = [d["x"] + b[0], d["y"] + b[1], d["x"] + b[2], d["y"] + b[3]]
        if t:
            box = [min(box[0], d["x"] + t[0]), min(box[1], d["y"] + t[1]), max(box[2], d["x"] + t[2]), max(box[3], d["y"] + t[3])]
        bodies[v.name] = box
    marks = [(m, m["kind"]) for m in schema["markers"]] + [(l, "label") for l in schema["labels"]]
    out = []
    for name in k.view.k.stages:
        mine = {v.name for v in k.view.devs_of(name)}
        if not mine:
            continue
        points = {p for n in mine for p, net in pins[n]}
        seen = {i for i in live if any(on(p, segs[i][:2]) for n in mine for p, net in pins[n] if net not in rails)}
        todo = list(seen)
        while todo:                                    # every wire that reaches one of its pins
            for j in touch[todo.pop()]:
                if j not in seen:
                    seen.add(j)
                    todo.append(j)
        if any(on(p, segs[i][:2]) for n in pins if n not in mine for p, net in pins[n] for i in seen):
            continue                                   # a wire joins it to a device outside: not alone
        stubs = [s for s in segs if s[2] in rails and (s[0] in points or s[1] in points)
                 and abs(s[0][0] - s[1][0]) + abs(s[0][1] - s[1][1]) <= STUB]
        wires = [segs[i] for i in seen] + stubs
        points |= {p for s in wires for p in s[:2]}
        own = [m for m, kind in marks if tuple(m["at"]) in points or any(on(tuple(m["at"]), s[:2]) for s in wires)]
        rects = [bodies[n] for n in mine] + [(min(s[0][0], s[1][0]), min(s[0][1], s[1][1]), max(s[0][0], s[1][0]), max(s[0][1], s[1][1])) for s in wires]
        rects += [_extent(m, kind) for m, kind in marks if any(m is o for o in own)]
        box = [min(r[0] for r in rects) - PAD, min(r[1] for r in rects) - PAD, max(r[2] for r in rects) + PAD, max(r[3] for r in rects) + PAD]
        strangers = [bodies[n] for n in bodies if n not in mine]
        strangers += [(min(s[0][0], s[1][0]), min(s[0][1], s[1][1]), max(s[0][0], s[1][0]), max(s[0][1], s[1][1]))
                      for i, s in enumerate(segs) if s[2] not in rails and i not in seen]
        strangers += [_extent(m, kind) for m, kind in marks if not any(m is o for o in own)]
        strangers += [b["box"] for b in out]
        if not any(_meets(box, r) for r in strangers):
            out.append({"name": k.view.k.labels.get(name, name), "box": box})
    return out
