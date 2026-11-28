"""Does a drawing show a relation?  The judge reads geometry only; it places nothing.

`holds` was validated against 5,232 hand drawings before this tool existed, so it is the
oracle for the tool's own drawings: `check` derives the relations of a circuit under its
statements and asks whether the drawing shows each one.
"""
from .circuit import same
from .geom import col, gate_dir
from .controls import parse
from .contract import derive, TOL


def holds(c, rel):
    """Does the drawing show this relation?  -> True / False / None (cannot be judged)."""
    rule, kind, p, _ = rel
    if kind == "upright_t":
        return bool(p.vertical) and ((p.source_dir == "down") == (p.pol == "n"))
    if kind == "flat":
        return p.vertical is False
    if kind == "upright_rail":
        v, end, is_supply = p
        other = "b" if end == "a" else "a"
        return bool(v.vertical) and ((v.pins[end][1] < v.pins[other][1]) == is_supply)
    if kind == "same_col":
        a, pa, b, pb = p
        return same(a.pins[pa][0], b.pins[pb][0], TOL)
    if kind == "same_row":
        return all(same(d.y, p[0].y, TOL) for d in p)
    if kind == "gates":
        a, b, want = p
        g = gate_dir(a, b)
        if want == "flipped":
            return None if g is None else g != "same"
        return None if g is None else g == want
    if kind == "mirrored":
        u, w, a, b = p
        axis = (col(a) + col(b)) / 2.0
        return same(u.y, w.y, TOL) and (abs((u.x + w.x) / 2.0 - axis) <= TOL or abs((col(u) + col(w)) / 2.0 - axis) <= TOL)
    if kind == "on_axis":
        u, a, b = p
        axis = (col(a) + col(b)) / 2.0
        return any(abs(x - axis) <= TOL for x in [q[0] for q in u.pins.values()] + [u.x])
    if kind == "apart":
        a, b = p
        ax = (min(d.x for d in a), max(d.x for d in a)); bx = (min(d.x for d in b), max(d.x for d in b))
        ay = (min(d.y for d in a), max(d.y for d in a)); by = (min(d.y for d in b), max(d.y for d in b))
        return not (min(ax[1], bx[1]) - max(ax[0], bx[0]) > TOL and min(ay[1], by[1]) - max(ay[0], by[0]) > TOL)
    if kind == "not_left":
        a, b = p
        return sum(d.x for d in b) / len(b) >= sum(d.x for d in a) / len(a) - TOL
    if kind == "gate_toward":
        v, src = p
        if v.gate_side not in ("left", "right"):
            return False
        sx = sum(d.x for d in src) / len(src)
        if abs(sx - col(v)) <= 0.5:
            return None
        return (sx < col(v)) == (v.gate_side == "left")
    if kind == "gate_toward_pins":
        v, drivers = p
        if v.gate_side not in ("left", "right"):
            return None
        mx = sum(d.pins[q][0] for d, q in drivers) / len(drivers)
        if abs(mx - col(v)) <= 0.5:
            return None
        return (mx < col(v)) == (v.gate_side == "left")
    if kind == "gate_toward_port":
        v, g = p
        ps = [at for d, at in c.ports.get(g, [])]
        if not ps or v.gate_side not in ("left", "right"):
            return None
        px = min(ps, key=lambda q: abs(q[0] - v.pins["g"][0]) + abs(q[1] - v.pins["g"][1]))[0]
        if abs(px - col(v)) <= 0.3:
            return None
        return (px < col(v)) == (v.gate_side == "left")
    if kind in ("port_in", "port_out"):
        n, devs, ax = p
        ps = [at for d, at in c.ports.get(n, [])]
        if not ps:
            return None
        if ax:
            # a mirrored element: the port stays on its own net's side of the axis;
            # an input may also come in from the left
            axis = (col(ax[0]) + col(ax[1])) / 2.0
            pins = [d.pins[q][0] for d, q in c.net_pins.get(n, [])]
            px = sum(q[0] for q in ps) / len(ps)
            if pins and abs(sum(pins) / len(pins) - axis) > TOL:
                own = (px < axis) == (sum(pins) / len(pins) < axis)
                return own or (px < min(pins) if kind == "port_in" else px > max(pins))
        cx = sum(d.x for d in devs) / len(devs)
        return (min(q[0] for q in ps) < cx) if kind == "port_in" else (max(q[0] for q in ps) > cx)
    if kind == "outside_lane":
        v, around = p
        ys = [q[1] for d in around for pn, q in d.pins.items() if not (d.kind == "t" and pn in ("b", "g"))]
        return v.y <= min(ys) + 0.01 or v.y >= max(ys) - 0.01
    if kind == "wired":
        return c.wired(p)
    raise ValueError(kind)


def check(c, text):
    """-> ([(rule, ok, text)], notes)."""
    k = derive(c, parse(text))
    return [(r[0], holds(c, r), r[3]) for r in k.relations], k.notes
