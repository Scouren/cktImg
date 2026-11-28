"""Wiring: every net becomes rail symbols, a name at each pin, or wire.

    route(c, k, schema, groups) -> notes     fills schema's wires, markers, labels, junctions

How a net is drawn (the `net` roles, then the wiring defaults W1 to W4):
    ground           a symbol at each pin (W1)
    supply           one bar over up to four pins, a symbol at each pin beyond (W2)
    bias, clock      its name at each pin
    signal           one wire
    anything else    one wire while its pins stand near each other; a net that spans far is
                     cut where its pins stand apart, each group wired, the groups joined by
                     name (W3). A terminal the maze cannot reach falls back to the name too.
A cross-coupled pair's two gate wires swap sides as a 45-degree X (W4).
A net that is a port of the cell gets one port: where the flow enters or leaves (F2), else
beside one of its pins.

W3's distances are people's, from the corpus (x-span of a net's pins, in MOS lengths):
wired in 98% of nets spanning 4 or less, 67% from 4 to 8, 22% from 8 to 16; a net that only
feeds gates is wired in 59% up to 4 and 11% beyond.
"""
import collections
from . import symbols
from .maze import Maze, CELL

STUB = 20          # px from a pin to its name or port
TEXT = 7           # px of width a character of a name takes
BEHIND = 3         # extra cost per cell of a wire that runs just behind a rail symbol
OVER_TEXT = 4      # extra cost per cell of a wire that runs through a device's name
NEAR, FAR = 190, 380   # px: 4 and 8 MOS lengths at this tool's column pitch (people's is 2.5 lengths, ours 3)
SEP = "\x1f"       # joins a net's name and a piece number into a piece key


def _terminals(c, schema):
    """{net: [(x, y, ex, ey, device, pin)]} for every drawn pin, in px."""
    out = collections.defaultdict(list)
    for d, v in zip(schema["devices"], c.devs):
        for p, (dx, dy, ex, ey) in symbols.pins(v, d["orient"]).items():
            net = v.net(p)
            if net is not None:
                out[net].append((d["x"] + dx, d["y"] + dy, ex, ey, v, p))
    return out


def _split(c, k, terms, named, band):
    """W3: cut a net whose pins stand far apart, or in different bands of the page, into the
    groups a wire joins. -> ({piece key: terminals}, {piece key: net}); a net in one piece
    keeps its name as key."""
    roles, pieces, net_of = k.view.k.roles, {}, {}
    whole = {n for n, r in roles.items() if r == "signal"}
    for rule, kind, p, text in k.relations:            # a flow through single parts is a wire: what one hands the next
        if kind == "not_left" and 1 in (len(p[0]), len(p[1])):
            out = {d.net(q) for d in p[0] for q in d.nets if not (d.kind == "t" and q in ("g", "b"))}
            whole |= {d.net(q) for d in p[1] for q in d.nets if q != "b"} & out
    for net in sorted(terms):
        groups = [terms[net]]
        if net not in k.view.rails and net not in named and net not in whole and len(terms[net]) > 1:
            gates_only = all(t[4].kind == "t" and t[5] == "g" for t in terms[net])
            groups = []
            for b in sorted({band[t[4].name] for t in terms[net]}):       # never a wire from one band to another
                pins = sorted((t for t in terms[net] if band[t[4].name] == b), key=lambda t: (t[0], t[1], t[4].name, t[5]))
                span = pins[-1][0] - pins[0][0]
                if gates_only and span > NEAR:         # a line that only feeds gates: a name at each
                    groups += [[t] for t in pins]
                elif not gates_only and span > FAR:
                    groups.append([pins[0]])
                    for a, t in zip(pins, pins[1:]):
                        if t[0] - a[0] > NEAR:
                            groups.append([])
                        groups[-1].append(t)
                else:
                    groups.append(pins)
        for i, g in enumerate(groups):
            key = net if i == 0 else "%s%s%d" % (net, SEP, i)
            pieces[key], net_of[key] = g, net
    return pieces, net_of


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


def _symbol(schema, maze, net, ground, x, y):
    """A ground or supply symbol at (x, y); nothing is wired just behind it."""
    box = (x - CELL, y, x + CELL, y + 20) if ground else (x - CELL, y - 20, x + CELL, y)
    maze.block(*_snap(box))
    maze.discourage(x - 30, y + 30, x + 30, y + 60, BEHIND) if ground else maze.discourage(x - 30, y - 60, x + 30, y - 30, BEHIND)
    schema["markers"].append({"kind": "ground" if ground else "supply", "type": "ground" if ground else "vdd-port",
                              "name": net, "direction": None, "at": [x, y], "net": net})


def _bar(schema, maze, net, pins):
    """W2: join the supply pins that can rise to one level above them all by one bar. -> the pins joined"""
    top = min(t[1] for t in pins) - 30
    ups = [t for t in pins if t[3] == -1 and all(maze.free(t[0], y) for y in range(top, t[1], CELL))]
    xs = sorted({t[0] for t in ups})
    if len(xs) < 2 or not all(maze.free(x, top) for x in range(xs[0], xs[-1] + 1, CELL)):
        return []
    for x, y, ex, ey, v, p in ups:
        maze.lay(net, [(x, y), (x, top)])
    maze.lay(net, [(xs[0], top), (xs[-1], top)])
    schema["wires"].append({"net": net, "segments": maze.segments(net)})
    schema["junctions"] += maze.junctions(net)
    _symbol(schema, maze, net, False, xs[-1], top)
    return ups


def _rails(c, k, schema, maze, terms, band):
    """W1, W2: a supply of up to four pins, all in one band of the page, is one bar; every
    other rail pin gets its own symbol on a short stub."""
    for net in sorted(k.view.rails):
        ground = net in k.view.ground
        pins = list(terms.get(net, ()))
        one = len({band[t[4].name] for t in pins}) == 1
        done = _bar(schema, maze, net, pins) if not ground and one and 2 <= len(pins) <= 4 else []
        for x, y, ex, ey, v, p in pins:
            if (x, y, ex, ey, v, p) in done:
                continue
            natural = (ey == 1) if ground else (ey == -1)
            px, py = _reach(maze, x, y, ex, ey, CELL if natural else STUB)
            if (px, py) != (x, y):
                schema["wires"].append({"net": net, "segments": [[[x, y], [px, py]]]})
                maze.block(min(x + ex * CELL, px), min(y + ey * CELL, py), max(x + ex * CELL, px), max(y + ey * CELL, py))
            _symbol(schema, maze, net, ground, px, py)


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


def _half(groups, pins):
    """'L' or 'R' when every pin of the net stands in that half of one axis group, else None."""
    names = {t[4].name for t in pins if t[5] != "g"}      # a gate does not say which half a net is in
    for g in groups:
        if names & set(g["left"]) and not names & set(g["right"]):
            return "L"
        if names & set(g["right"]) and not names & set(g["left"]):
            return "R"
    return None


def _port(c, schema, maze, key, net, direction, pins, devs, groups):
    """Place one port for `net` on its piece `key` and register it as a terminal. -> its point."""
    mine = [t for t in pins if devs and t[4] in devs] or pins
    half = _half(groups, pins)
    branch = [t for t in mine if t[5] != "g"] or mine
    at = {d["name"]: d["x"] for d in schema["devices"]}
    beyond = max([at[d.name] for d in devs or ()] + [t[0] for t in pins])     # F2: right of all it leaves

    def spot(at, face):
        """True when the port, the cell its wire leaves through and its name are all clear."""
        b = _snap(_text_box(at[0], at[1], -face[0], -face[1], net))
        return (maze.free(*at) and maze.free(at[0] + face[0] * CELL, at[1] + face[1] * CELL)
                and all(maze.free(i, j) for i in range(b[0], b[2] + 1, CELL) for j in range(b[1], b[3] + 1, CELL)))
    if direction != "input" and half == "L":           # a mirrored left half: the port leaves to the left
        x, y, ex, ey, v, p = min(branch, key=lambda t: (t[0], t[1]))
        want = (min(t[0] for t in branch) - 60, y + ey * STUB if ey else y)
        step, face = (-CELL, 0), (1, 0)
    elif direction == "output" or (direction != "input" and half == "R"):
        x, y, ex, ey, v, p = max(branch, key=lambda t: (t[0], -t[1]))
        want = ((max(t[0] for t in branch) if half else beyond) + 60, y + ey * STUB if ey else y)
        step, face = (CELL, 0), (-1, 0)
    else:                                              # beside a pin: a gate first, the leftmost
        gates = sorted([t for t in mine if t[2]] or mine, key=lambda t: (0 if t[5] == "g" else 1, t[0], t[1]))
        tries = [((x + ex * 40, y), (ex * CELL, 0), (-ex, 0)) if ex else ((x - 40, y + ey * STUB), (-CELL, 0), (1, 0))
                 for x, y, ex, ey, v, p in (gates if direction == "passive" else gates[:1])]
        if direction == "passive" and gates[0][2]:     # no side is promised: under or over the pin when beside is taken
            x, y, ex = gates[0][:3]
            tries += [((x + ex * 20, y + 40), (0, CELL), (0, -1)), ((x + ex * 20, y - 40), (0, -CELL), (0, 1))]
        want, step, face = next((t for t in tries if spot(t[0], t[2])), tries[0])
    px, py = want
    for _ in range(200):
        if spot((px, py), face):
            break
        px, py = px + step[0], py + step[1]
    maze.pin(key, px, py, face[0], face[1])
    maze.block(*_snap(_text_box(px, py, -face[0], -face[1], net)))
    schema["markers"].append({"kind": "port", "type": "port", "name": net, "direction": direction,
                              "at": [px, py], "net": net, "side": [-face[0], -face[1]]})
    return (px, py)


def _cross_pairs(c, k, schema, maze, terms, key_at):
    """W4: a cross-coupled pair's two gate wires swap sides as a 45-degree X, drawn between
    the gates and the level 60 px toward the drains. Two pairs facing each other (a latch of
    two inverters) share that level, and their two Xs meet on it. -> how many Xs were drawn"""
    at = {(t[4].name, t[5]): t for pins in terms.values() for t in pins}
    corners = collections.Counter()
    for a, b in k.cross:
        ga, gb = at.get((a, "g")), at.get((b, "g"))
        if ga is None or gb is None:
            continue
        if ga[0] > gb[0]:
            a, b, ga, gb = b, a, gb, ga
        da, db = at[(a, "d")], at[(b, "d")]
        if ga[1] != gb[1] or gb[0] - ga[0] != 60 or ga[2] != 1 or gb[2] != -1 or da[3] != db[3] or not da[3]:
            continue
        up = da[3]                                     # -1: drains on top, the X stands above the gates
        y, yx = ga[1], ga[1] + up * 60
        inner = [(ga[0] + 10 * i, y + up * 10 * i) for i in range(1, 6)] + [(gb[0] - 10 * i, y + up * 10 * i) for i in range(1, 6)]
        legs = []                                      # (gate, piece key, the wire from the drain to the X's corner)
        for gate, drain, corner in ((ga, db, gb[0]), (gb, da, ga[0])):
            if key_at[(gate[4].name, "g")] != key_at[(drain[4].name, "d")]:
                break                                  # W3 cut the net between this gate and that drain
            legs.append((gate, key_at[(drain[4].name, "d")], [(drain[0], drain[1]), (drain[0], yx), (corner, yx)]))
        if len(legs) != 2:
            continue
        clear = all(maze.free(x, yy) for x, yy in inner)
        for gate, net, (p0, p1, p2) in legs:
            cells = [(p0[0], yy) for yy in range(min(p0[1], yx), max(p0[1], yx) + 1, CELL)]
            cells += [(x, yx) for x in range(min(p1[0], p2[0]), max(p1[0], p2[0]) + 1, CELL)]
            clear = clear and all(maze.open(net, x, yy) for x, yy in cells)
        if not clear:
            continue
        for gate, net, path in legs:
            maze.lay(net, path)
            maze.claim(net, gate[0], gate[1], path[-1])
            schema["wires"].append({"net": net.split(SEP)[0], "segments": [[[gate[0], gate[1]], list(path[-1])]]})
            corners[path[-1]] += 1
        for x, yy in inner:
            maze.block(x, yy, x, yy)
    schema["junctions"] += [list(p) for p, n in sorted(corners.items()) if n > 1]   # two Xs meet a wire
    return sum(corners.values()) // 2


def _name_piece(c, schema, maze, key, net, points, by_point):
    """Write `net`'s name on a wired piece: on a stub at one of its terminals (a gate first)
    when the stub and the name are clear there, else on a stub off a corner of its wire."""
    ts = sorted((by_point[p] for p in points if p in by_point), key=lambda t: (t[5] != "g", t[0], t[1]))

    def clear(x, y, ex, ey):
        b = _snap(_text_box(x + ex * STUB, y + ey * STUB, ex, ey, net))
        return (all(maze.free(x + ex * d, y + ey * d) for d in range(CELL, STUB + 1, CELL))
                and all(maze.free(i, j) for i in range(b[0], b[2] + 1, CELL) for j in range(b[1], b[3] + 1, CELL)))
    if not ts:
        return
    spot = next((t[:4] for t in ts if clear(*t[:4])), None)
    if spot is None:
        pins = {(t[0], t[1]) for t in ts}
        for x, y in maze.corners(key, ts[0][0], ts[0][1]):
            ways = [d for d in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (x, y) not in pins and clear(x, y, *d)]
            if ways:
                spot = (x, y) + ways[0]
                schema["junctions"].append([x, y])
                break
    _name_at(c, schema, maze, net, *(spot or ts[0][:4]))


def route(c, k, schema, groups=()):
    """Fill the stamped `schema` with wires, markers, labels and junctions. -> notes"""
    maze, notes = Maze(), []
    terms = _terminals(c, schema)
    for d, v in zip(schema["devices"], c.devs):
        b, t = symbols.body(v, d["orient"]), symbols.label_box(v, d["orient"], TEXT)
        maze.block(d["x"] + b[0], d["y"] + b[1], d["x"] + b[2], d["y"] + b[3])
        if t:                                          # round inward: a name does not close the track beside it
            maze.text(-(-(d["x"] + t[0]) // CELL) * CELL, -(-(d["y"] + t[1]) // CELL) * CELL,
                      (d["x"] + t[2]) // CELL * CELL, (d["y"] + t[3]) // CELL * CELL, OVER_TEXT)
    named = {n for n, r in k.view.k.roles.items() if r in ("bias", "clock")}
    band = {d["name"]: d.get("band", 0) for d in schema["devices"]}
    pieces, net_of = _split(c, k, terms, named, band)
    for key, pins in pieces.items():
        for x, y, ex, ey, v, p in pins:
            maze.pin(key, x, y, ex, ey)
    key_at = {(t[4].name, t[5]): key for key, pins in pieces.items() for t in pins}
    _rails(c, k, schema, maze, terms, band)
    drawn = _cross_pairs(c, k, schema, maze, terms, key_at)   # each X is one crossing the maze does not see
    for net in sorted(named):
        for x, y, ex, ey, v, p in terms.get(net, ()):
            _name_at(c, schema, maze, net, x, y, ex, ey)
    ins, outs = _flow_ends(k)
    wired = sorted(key for key in pieces if net_of[key] not in k.view.rails and net_of[key] not in named)
    cut = collections.Counter(net_of[key] for key in wired)
    ported = {}                                        # net -> the piece its port goes on: the flow's devices, else the most pins
    for key in wired:
        net = net_of[key]
        if net in ins or net in outs or net in c.port_nets:
            devs = ins.get(net) or outs.get(net) or ()
            score = (sum(t[4] in devs for t in pieces[key]), len(pieces[key]))
            if net not in ported or score > ported[net][0]:
                ported[net] = (score, key)
    points, port_at = {}, {}
    for key in wired:                                  # ports first: they are terminals of their nets
        net = net_of[key]
        points[key] = [(t[0], t[1]) for t in pieces[key]]
        if net in ported and ported[net][1] == key:
            direction = "input" if net in ins else "output" if net in outs else "passive"
            port_at[key] = _port(c, schema, maze, key, net, direction, pieces[key], ins.get(net) or outs.get(net), groups)
            points[key].append(port_at[key])

    def span(key):
        xs, ys = [p[0] for p in points[key]], [p[1] for p in points[key]]
        return (max(xs) - min(xs)) + (max(ys) - min(ys))
    for key in sorted(wired, key=lambda q: (span(q), q)):
        net = net_of[key]
        parts = maze.connect(key, points[key]) if len(points[key]) > 1 else [points[key]]
        segs = maze.segments(key)
        if segs:
            schema["wires"].append({"net": net, "segments": segs})
        schema["junctions"] += maze.junctions(key)
        by_point = {(t[0], t[1]): t for t in pieces[key]}
        if len(parts) > 1:                             # the maze's last resort: join the pieces by name
            lost = [by_point[p] for g in parts[1:] for p in g if p in by_point]
            where = ", ".join("%s.%s" % (t[4].name, t[5]) for t in lost) or "its port"
            notes.append("net %s: %d of its %d terminals joined by name, no clear path for a wire (%s)"
                         % (net, sum(len(g) for g in parts[1:]), len(points[key]), where))
        if len(parts) > 1 or cut[net] > 1:
            for g in parts:
                if port_at.get(key) not in g:          # the port already names its piece
                    _name_piece(c, schema, maze, key, net, g, by_point)
    schema["crossings"] = maze.crossings() + drawn
    return notes
