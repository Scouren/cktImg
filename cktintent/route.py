"""Wiring: every net becomes rail symbols, a name at each pin, or one wire.

    route(c, k, schema) -> notes        fills schema's wires, markers, labels, junctions

How a net is drawn (the wiring defaults W1 to W3, and the `net` roles):
    ground, supply   a symbol at each pin
    bias, clock      its name at each pin
    anything else    one wire; a terminal the maze cannot reach falls back to the name
A net that is a port of the cell gets one port: where the flow enters or leaves (F2), else
beside one of its pins.
"""
import collections
from . import symbols
from .maze import Maze, CELL

STUB = 20          # px from a pin to its name or port
TEXT = 7           # px of width a character of a name takes


def _terminals(c, schema):
    """{net: [(x, y, ex, ey, device, pin)]} for every drawn pin, in px."""
    out = collections.defaultdict(list)
    for d, v in zip(schema["devices"], c.devs):
        for p, (dx, dy, ex, ey) in symbols.pins(v, d["orient"]).items():
            net = v.net(p)
            if net is not None:
                out[net].append((d["x"] + dx, d["y"] + dy, ex, ey, v, p))
    return out


def _text_box(x, y, ex, ey, name):
    """The box a name takes when it is written beyond (x, y) along (ex, ey)."""
    w = TEXT * len(name) + 6
    if ex > 0:
        return (x + CELL, y - CELL, x + w, y + CELL)
    if ex < 0:
        return (x - w, y - CELL, x - CELL, y + CELL)
    if ey < 0:
        return (x - w // 2, y - 20, x + w // 2, y - CELL)
    return (x - w // 2, y + CELL, x + w // 2, y + 20)


def _snap(box):
    return (box[0] // CELL * CELL, box[1] // CELL * CELL, -(-box[2] // CELL) * CELL, -(-box[3] // CELL) * CELL)


def _reach(maze, x, y, ex, ey, want):
    """The point up to `want` px from (x, y) along (ex, ey) that is still free."""
    px, py = x, y
    for _ in range(want // CELL):
        if not maze.free(px + ex * CELL, py + ey * CELL):
            break
        px, py = px + ex * CELL, py + ey * CELL
    return px, py


def _rails(c, k, schema, maze, terms):
    """W1/W2: a ground or supply symbol on a short stub at each rail pin."""
    for net in sorted(k.view.rails):
        ground = net in k.view.ground
        for x, y, ex, ey, v, p in terms.get(net, ()):
            natural = (ey == 1) if ground else (ey == -1)
            px, py = _reach(maze, x, y, ex, ey, CELL if natural else STUB)
            box = (px - CELL, py, px + CELL, py + 20) if ground else (px - CELL, py - 20, px + CELL, py)
            if (px, py) != (x, y):
                schema["wires"].append({"net": net, "segments": [[[x, y], [px, py]]]})
                maze.block(min(x + ex * CELL, px), min(y + ey * CELL, py), max(x + ex * CELL, px), max(y + ey * CELL, py))
            maze.block(*_snap(box))
            schema["markers"].append({"kind": "ground" if ground else "supply", "type": "ground" if ground else "vdd-port",
                                      "name": net, "direction": None, "at": [px, py], "net": net})


def _name_at(c, schema, maze, net, x, y, ex, ey):
    """Write the net's name on a stub at one pin: a port when the net is a port of the cell."""
    px, py = _reach(maze, x, y, ex, ey, STUB)
    if (px, py) != (x, y):
        schema["wires"].append({"net": net, "segments": [[[x, y], [px, py]]]})
        maze.block(min(x + ex * CELL, px), min(y + ey * CELL, py), max(x + ex * CELL, px), max(y + ey * CELL, py))
    maze.block(*_snap(_text_box(px, py, ex, ey, net)))
    if net in c.port_nets:
        schema["markers"].append({"kind": "port", "type": "port", "name": net, "direction": "passive", "at": [px, py], "net": net, "side": [ex, ey]})
    else:
        schema["labels"].append({"net": net, "name": net, "at": [px, py], "side": [ex, ey]})


def _flow_ends(k):
    """({input net: devices it feeds}, {output net: devices it leaves}) from the F2 relations."""
    ins, outs = {}, {}
    for rule, kind, p, text in k.relations:
        if kind == "port_in":
            ins.setdefault(p[0], p[1])
        elif kind == "port_out":
            outs.setdefault(p[0], p[1])
    return ins, outs


def _port(c, schema, maze, net, direction, pins, devs):
    """Place one port for `net` and register it as a terminal. -> its point."""
    mine = [t for t in pins if devs and t[4] in devs] or pins
    if direction == "output":
        x, y, ex, ey, v, p = max(mine, key=lambda t: (t[0], -t[1]))
        want = (max(t[0] for t in pins) + 40, y + ey * STUB if ey else y)
        step, face = (CELL, 0), (-1, 0)
    else:
        gates = [t for t in mine if t[2]] or mine
        x, y, ex, ey, v, p = min(gates, key=lambda t: (0 if t[5] == "g" else 1, t[0], t[1]))
        if ex > 0 and direction == "input":            # a gate that looks right: the input stays on its half
            want, step, face = (x + 40, y), (CELL, 0), (-1, 0)
        elif ex:
            want, step, face = (x + ex * 40, y), (ex * CELL, 0), (-ex, 0)
        else:
            want, step, face = (x - 40, y + ey * STUB), (-CELL, 0), (1, 0)
    px, py = want
    box = lambda: _snap(_text_box(px, py, -face[0], -face[1], net))
    for _ in range(200):
        b = box()
        clear = maze.free(px, py) and maze.free(px + face[0] * CELL, py) and all(
            maze.free(i, j) for i in range(b[0], b[2] + 1, CELL) for j in range(b[1], b[3] + 1, CELL))
        if clear:
            break
        px, py = px + step[0], py + step[1]
    maze.pin(net, px, py, face[0], face[1])
    maze.block(*box())
    schema["markers"].append({"kind": "port", "type": "port", "name": net, "direction": direction,
                              "at": [px, py], "net": net, "side": [-face[0], -face[1]]})
    return (px, py)


def route(c, k, schema):
    """Fill the stamped `schema` with wires, markers, labels and junctions. -> notes"""
    maze, notes = Maze(), []
    terms = _terminals(c, schema)
    for d, v in zip(schema["devices"], c.devs):
        b = symbols.body(v, d["orient"])
        maze.block(d["x"] + b[0], d["y"] + b[1], d["x"] + b[2], d["y"] + b[3])
    for net, pins in terms.items():
        for x, y, ex, ey, v, p in pins:
            maze.pin(net, x, y, ex, ey)
    _rails(c, k, schema, maze, terms)
    named = {n for n, r in k.view.k.roles.items() if r in ("bias", "clock")}
    for net in sorted(named):
        for x, y, ex, ey, v, p in terms.get(net, ()):
            _name_at(c, schema, maze, net, x, y, ex, ey)
    ins, outs = _flow_ends(k)
    points = {}
    wired = sorted(n for n in terms if n not in k.view.rails and n not in named)
    for net in wired:                                  # ports first: they are terminals of their nets
        points[net] = [(t[0], t[1]) for t in terms[net]]
        if net in ins or net in outs or net in c.port_nets:
            direction = "input" if net in ins else "output" if net in outs else "passive"
            points[net].append(_port(c, schema, maze, net, direction, terms[net], ins.get(net) or outs.get(net)))

    def span(net):
        xs, ys = [p[0] for p in points[net]], [p[1] for p in points[net]]
        return (max(xs) - min(xs)) + (max(ys) - min(ys))
    for net in sorted(wired, key=lambda n: (span(n), n)):
        if len(points[net]) < 2:
            continue
        groups = maze.connect(net, points[net])
        segs = maze.segments(net)
        if segs:
            schema["wires"].append({"net": net, "segments": segs})
        schema["junctions"] += maze.junctions(net)
        if len(groups) > 1:                            # W3's last resort: join the pieces by name
            lost = sum(len(g) for g in groups[1:])
            notes.append("net %s: %d of its %d terminals joined by name, no clear path for a wire" % (net, lost, len(points[net])))
            by_point = {(t[0], t[1]): t for t in terms[net]}
            for g in groups:
                x, y = next((p for p in g if p in by_point), g[0])
                t = by_point.get((x, y))
                if t is not None:
                    _name_at(c, schema, maze, net, x, y, t[2], t[3])
                else:
                    schema["labels"].append({"net": net, "name": net, "at": [x, y], "side": [0, -1]})
    schema["crossings"] = maze.crossings()
    return notes
