"""SVG out of a drawing.

    render_svg(schema, c) -> str

Draws what the schema holds and decides nothing: device symbols at their pins, wires,
junction dots, rail symbols, ports and names. A symbol is a list of strokes in its own
frame: ("L", x0, y0, x1, y1), ("C", cx, cy, r, filled), ("P", [points], closed, filled),
("T", x, y, text, anchor).
"""
from . import symbols

STROKE = 'stroke="#111" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"'


def _transistor(v, o):
    bjt = v.type in ("npn", "pnp")
    p = v.pol == "p"
    if o["upright"]:
        if bjt:
            s = [("L", -20, 0, -5, 0), ("L", -5, -10, -5, 10), ("L", -5, -4, 10, -14), ("L", 10, -14, 10, -20),
                 ("L", -5, 4, 10, 14), ("L", 10, 14, 10, 20)]
            s.append(("P", [(1, -12), (6, -11.3), (3, -7)], True, True) if p else ("P", [(9, 13.3), (4, 13.5), (7, 9)], True, True))
        else:
            s = [("L", -8, -10, -8, 10), ("L", -3, -12, -3, 12), ("L", -3, -8, 10, -8), ("L", 10, -8, 10, -20),
                 ("L", -3, 8, 10, 8), ("L", 10, 8, 10, 20)]
            s += [("L", -20, 0, -14, 0), ("C", -11, 0, 2.6, False)] if p else [("L", -20, 0, -8, 0)]
            s.append(("P", [(7, -11), (2, -8), (7, -5)], True, True) if p else ("P", [(2, 5), (7, 8), (2, 11)], True, True))
        if o["gate"] == "right":
            s = _map(s, lambda x, y: (-x, y))
        return s + [_label(v, o)]
    s = [("L", -10, -12, 10, -12), ("L", -12, -7, 12, -7), ("L", -8, -7, -8, 0), ("L", -8, 0, -20, 0),
         ("L", 8, -7, 8, 0), ("L", 8, 0, 20, 0)]
    s += [("L", 0, -20, 0, -17.5), ("C", 0, -15, 2.5, False)] if p else [("L", 0, -20, 0, -12)]
    if o["gate"] == "down":
        s = _map(s, lambda x, y: (x, -y))
    return s + [_label(v, o)]


def _label(v, o):
    dx, dy, anchor = symbols.label(v, o)
    return ("T", dx, dy, v.name, anchor)


def _two_pin(v, o):
    k = v.kind
    if k == "r":
        s = [("L", 0, -20, 0, -12), ("P", [(0, -12), (5, -9), (-5, -3), (5, 3), (-5, 9), (0, 12)], False, False), ("L", 0, 12, 0, 20)]
    elif k == "c":
        s = [("L", 0, -20, 0, -3), ("L", -8, -3, 8, -3), ("L", -8, 3, 8, 3), ("L", 0, 3, 0, 20)]
    elif k == "l":
        bumps = []
        for i in range(3):
            y = -12 + 8 * i
            bumps += [(0, y), (4, y + 1.5), (5.5, y + 4), (4, y + 6.5), (0, y + 8)]
        s = [("L", 0, -20, 0, -12), ("P", bumps, False, False), ("L", 0, 12, 0, 20)]
    elif k == "d":
        s = [("L", 0, -20, 0, -6), ("P", [(-7, -6), (7, -6), (0, 6)], True, False), ("L", -7, 6, 7, 6), ("L", 0, 6, 0, 20)]
    elif k == "sw":
        s = [("L", 0, -20, 0, -8), ("C", 0, -8, 2, False), ("C", 0, 8, 2, False), ("L", 0, 20, 0, 8), ("L", 0, 8, 8, -6)]
    else:
        controlled = v.type in ("vcvs", "vccs", "cccs", "ccvs")
        s = [("L", 0, -20, 0, -11), ("L", 0, 11, 0, 20)]
        s.append(("P", [(0, -11), (9, 0), (0, 11), (-9, 0)], True, False) if controlled else ("C", 0, 0, 11, False))
        if k == "i":
            s += [("L", 0, -6, 0, 6), ("P", [(-3, 2), (0, 7), (3, 2)], True, True)]
        else:
            s += [("L", -3, -5, 3, -5), ("L", 0, -8, 0, -2), ("L", -3, 5, 3, 5)]
    if o.get("flip"):
        s = _map(s, lambda x, y: (x, -y))
    if not o["upright"]:
        s = _map(s, lambda x, y: (y, x))
    return s + [_label(v, o)]


def _block(v, o):
    hw, hh = symbols.block_size(v)
    pins = symbols.pins(v, o)
    if v.type == "opamp":
        s = [("P", [(-hw, -hh), (-hw, hh), (hw, 0)], True, False)]
        for p, (x, y, ex, ey) in pins.items():
            if ex < 0 and len([q for q in pins.values() if q[2] < 0]) == 2:
                s.append(("T", x + 8, y + 4, "−" if symbols.INVERTING.search(p) else "+", "middle"))
            if ey:
                edge = hh * (1 - (x + hw) / float(2 * hw)) * (1 if ey > 0 else -1)
                s.append(("L", x, y, x, edge))
        return s + [("T", -hw + 22, 4, v.name, "start")]
    s = [("P", [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)], True, False), ("T", 0, 4, v.name, "middle")]
    for p, (x, y, ex, ey) in pins.items():
        if ex:
            s.append(("t", x - ex * 4, y + 3, p, "start" if ex < 0 else "end"))
        else:
            s.append(("t", x, y - ey * 5 + 3, p, "middle"))
    return s


def _map(shape, f):
    out = []
    for s in shape:
        if s[0] == "L":
            out.append(("L",) + f(s[1], s[2]) + f(s[3], s[4]))
        elif s[0] == "C":
            out.append(("C",) + f(s[1], s[2]) + s[3:])
        elif s[0] == "P":
            out.append(("P", [f(x, y) for x, y in s[1]]) + s[2:])
        else:
            out.append((s[0],) + f(s[1], s[2]) + s[3:])
    return out


def _emit(shape, x, y, out):
    for s in shape:
        if s[0] == "L":
            out.append('<line x1="%g" y1="%g" x2="%g" y2="%g"/>' % (x + s[1], y + s[2], x + s[3], y + s[4]))
        elif s[0] == "C":
            out.append('<circle cx="%g" cy="%g" r="%g"%s/>' % (x + s[1], y + s[2], s[3], ' fill="#111"' if s[4] else ""))
        elif s[0] == "P":
            pts = " ".join("%g,%g" % (x + px, y + py) for px, py in s[1])
            out.append('<%s points="%s"%s/>' % ("polygon" if s[2] else "polyline", pts, ' fill="#111"' if s[3] else ""))
        else:
            size = 11 if s[0] == "T" else 8
            out.append('<text x="%g" y="%g" text-anchor="%s" font-size="%d" stroke="none" fill="#111" font-family="Helvetica,Arial,sans-serif"%s>%s</text>'
                       % (x + s[1], y + s[2], s[4], size, ' font-style="italic"' if s[0] == "T" else "", _esc(s[3])))


def _esc(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _marker(m, out):
    x, y = m["at"]
    if m["kind"] == "ground":
        _emit([("L", 0, 0, 0, 5), ("L", -8, 5, 8, 5), ("L", -5, 9, 5, 9), ("L", -2, 13, 2, 13)], x, y, out)
    elif m["kind"] == "supply":
        _emit([("L", 0, 0, 0, -5), ("L", -8, -5, 8, -5), ("t", 0, -9, m["name"], "middle")], x, y, out)
    else:
        out.append('<circle cx="%g" cy="%g" r="3" fill="#fff"/>' % (x, y))
        _name(m["name"], x, y, m.get("side", [-1, 0]), out)


def _name(name, x, y, side, out):
    ex, ey = side
    if ex:
        _emit([("T", ex * 7, 4, name, "start" if ex > 0 else "end")], x, y, out)
    else:
        _emit([("T", 0, -7 if ey < 0 else 16, name, "middle")], x, y, out)


def render_svg(schema, c):
    """-> the drawing as an SVG document."""
    body, xs, ys = [], [], []
    for b in schema.get("boxes", ()):                 # a stage that stands alone, in its labelled box
        x0, y0, x1, y1 = b["box"]
        body.append('<rect x="%g" y="%g" width="%g" height="%g" stroke-dasharray="6 4" stroke-width="1"/>' % (x0, y0, x1 - x0, y1 - y0))
        _emit([("T", 2, 13, b["name"], "start")], x0, y1, body)     # under the box: the rails run over it
        xs += [x0, x1]
        ys += [y0, y1 + 16]
    for w in schema["wires"]:
        for (x0, y0), (x1, y1) in w["segments"]:
            body.append('<line x1="%g" y1="%g" x2="%g" y2="%g"/>' % (x0, y0, x1, y1))
    for d, v in zip(schema["devices"], c.devs):
        o = d["orient"]
        shape = _transistor(v, o) if v.kind == "t" else _block(v, o) if v.kind == "blk" else _two_pin(v, o)
        _emit(shape, d["x"], d["y"], body)
    for x, y in schema["junctions"]:
        body.append('<circle cx="%g" cy="%g" r="2.6" fill="#111"/>' % (x, y))
    for m in schema["markers"]:
        _marker(m, body)
    for l in schema["labels"]:
        _name(l["name"], l["at"][0], l["at"][1], l.get("side", [0, -1]), body)
    xs += [p[0] for d in schema["devices"] for p in d["terminals"].values()] + [m["at"][0] for m in schema["markers"]] + [l["at"][0] for l in schema["labels"]]
    ys += [p[1] for d in schema["devices"] for p in d["terminals"].values()] + [m["at"][1] for m in schema["markers"]] + [l["at"][1] for l in schema["labels"]]
    for w in schema["wires"]:
        for a, b in w["segments"]:
            xs += [a[0], b[0]]
            ys += [a[1], b[1]]
    x0, y0 = min(xs, default=0) - 70, min(ys, default=0) - 50
    x1, y1 = max(xs, default=0) + 70, max(ys, default=0) + 50
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%g %g %g %g" width="%g" height="%g">\n'
            '<rect x="%g" y="%g" width="%g" height="%g" fill="#fff"/>\n<g %s>\n%s\n</g>\n</svg>\n'
            % (x0, y0, x1 - x0, y1 - y0, x1 - x0, y1 - y0, x0, y0, x1 - x0, y1 - y0, STROKE, "\n".join(body)))
