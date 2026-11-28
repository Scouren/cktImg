"""Placement: every device gets a position and an orientation.

    place(c, k) -> ({device name: (x, y, o)}, axis groups, notes)        px, on the 10 px grid

The spine: rows and columns for the upright devices (`rows`, `columns`), which way each gate
looks, then every other device (a part that lies flat, a block, a part with no rule of its
own) is attached next to the pin it serves. Nothing here reads a statement directly: it
reads the contract `k` that `contract.derive` made from them.
"""
import collections
from .rows import assign_rows
from .columns import assign_columns
from . import symbols

ROW = 80           # px between two rows
NEAR = 20          # px of wire between an attached part and the pin it serves
LANE = 120         # px between two lanes


def orient_gates(c, k, X, groups, rows):
    """{transistor name: 'left'|'right'} for the upright transistors: M2, then a cross-coupled
    pair looks inward, B6, a diode-connected device looks at the gates it feeds (97 of 97
    bias rows in the corpus), and two devices mirrored about an axis look opposite ways."""
    gate, twins = {}, []
    by_x = lambda a, b: (a, b) if X[a] <= X[b] else (b, a)
    for rule, kind, p, text in k.relations:
        if kind == "gates" and p[0].name in X and p[1].name in X:
            l, r = by_x(p[0].name, p[1].name)
            if p[2] == "inward":
                gate[l], gate[r] = "right", "left"
            elif p[2] == "outward":
                gate[l], gate[r] = "left", "right"
            else:
                twins.append((l, r))
        elif kind == "mirrored" and p[0].name in X and p[1].name in X and p[0].kind == "t":
            twins.append(by_x(p[0].name, p[1].name))
    for a, b in k.cross:
        if a in X and b in X and rows[a] == rows[b] and a not in gate and b not in gate and X[a] != X[b]:
            l, r = by_x(a, b)
            gate[l], gate[r] = "right", "left"
    for g in groups:                                # the same row of two mirrored columns
        twins += [(l, r) for L, R in g["cols"] for l in L for r in R
                  if rows[l] == rows[r] and c.by[l].kind == "t" and c.by[r].kind == "t"]
    for rule, kind, p, text in k.relations:
        if kind == "gate_toward_pins" and p[0].name in X and p[0].name not in gate:
            xs = [X[d.name] for d, q in p[1] if d.name in X]
            if xs and abs(sum(xs) / len(xs) - X[p[0].name]) > 20:
                gate[p[0].name] = "left" if sum(xs) / len(xs) < X[p[0].name] else "right"
    for v in c.devs:                                # a diode-connected device looks at the gates it feeds
        if v.kind == "t" and v.name in X and v.name not in gate and v.net("g") == v.net("d"):
            xs = [X[d.name] for d, q in c.net_pins.get(v.net("g"), ()) if q == "g" and d is not v and d.kind == "t" and d.name in X]
            if xs and abs(sum(xs) / len(xs) - X[v.name]) > 20:
                gate[v.name] = "left" if sum(xs) / len(xs) < X[v.name] else "right"
    other = {"left": "right", "right": "left"}
    for l, r in twins:                              # mirror images: opposite sides, outward unless one is set
        if l in gate and r not in gate:
            gate[r] = other[gate[l]]
        elif r in gate and l not in gate:
            gate[l] = other[gate[r]]
        elif l not in gate:
            gate[l], gate[r] = "left", "right"
    for g in groups:                                # a lone gate in a mirrored half looks outward
        for n in g["left"]:
            gate.setdefault(n, "left")
        for n in g["right"]:
            gate.setdefault(n, "right")
    for v in c.devs:
        if v.kind == "t" and v.name in X:
            gate.setdefault(v.name, "left")
    return gate


class Board:
    """The devices placed so far, for the parts still to attach."""

    def __init__(self, c, k):
        self.c, self.k, self.at, self.boxes = c, k, {}, []

    def add(self, v, x, y, o):
        """Place v at (x, y) with orientation o; the caller has checked it is clear."""
        self.at[v.name] = (x, y, o)
        b = symbols.body(v, o)
        self.boxes.append((x + b[0], y + b[1], x + b[2], y + b[3]))

    def keep_out(self, box):
        """Reserve the box (x0, y0, x1, y1) px: no part attached later may stand in it."""
        self.boxes.append(box)

    def free(self, v, x, y, o, pad=10):
        """True when v at (x, y) would stand `pad` px clear of everything placed and reserved."""
        b = symbols.body(v, o)
        x0, y0, x1, y1 = x + b[0] - pad, y + b[1] - pad, x + b[2] + pad, y + b[3] + pad
        return not any(x0 < bx1 and bx0 < x1 and y0 < by1 and by0 < y1 for bx0, by0, bx1, by1 in self.boxes)

    def settle(self, v, x, y, o, step):
        """Place v at (x, y), moved along `step` until it is clear of everything placed."""
        assert step != (0, 0)
        for _ in range(400):
            if self.free(v, x, y, o):
                break
            x, y = x + step[0], y + step[1]
        self.add(v, x, y, o)

    def anchors(self, v, pin):
        """Placed pins on the net of v's `pin`: [(x, y, ex, ey, device)], rails excluded."""
        net = v.net(pin)
        if net is None or net in self.k.view.rails:
            return []
        out = []
        for d, q in self.c.net_pins.get(net, ()):
            if d is not v and d.name in self.at:
                x, y, o = self.at[d.name]
                dx, dy, ex, ey = symbols.pins(d, o)[q]
                out.append((x + dx, y + dy, ex, ey, d))
        return out


def _flat(v, near, near_left):
    """Orientation of a flat part whose pin `near` must be its left (or right) pin."""
    if v.kind == "t":
        return {"upright": False, "gate": "up", "flip": (near == "d") == near_left}
    return {"upright": False, "flip": (near == "a") != near_left}


def _ends(v):
    return ("d", "s") if v.kind == "t" else ("a", "b")


def _beside(board, v, near, a):
    """Lay v flat with pin `near` one short wire from anchor a, on the side a's pin faces."""
    x, y, ex, ey, d = a
    if ex:
        board.settle(v, x + ex * (NEAR + 20), y, _flat(v, near, near_left=ex > 0), (ex * 20, 0))
    else:
        board.settle(v, x + NEAR + 20, y + ey * NEAR, _flat(v, near, near_left=True), (20, 0))


def _attach_around(board, parts, host):
    """B4 and D4: the parts from a device's output back to its input go round the device, in
    one row, the output's end first."""
    x, y, o = board.at[host.name]
    if host.kind == "t":
        up = host.pol == "n"                          # the drain end: above an NMOS, below a PMOS
        side = -1 if o["gate"] == "left" else 1       # on the gate's side of the channel
        channel, net = x + (10 if o["gate"] == "left" else -10), host.net("d")
        for i, v in enumerate(parts):
            near = "a" if v.net("a") == net else "b"
            board.settle(v, channel + side * 60 * (i + 1), y + (-40 if up else 40), _flat(v, near, near_left=side > 0), (side * 20, 0))
            net = v.net("b" if near == "a" else "a")
        return
    hw, hh = symbols.block_size(host)
    pins = symbols.pins(host, o)
    ends = {n for v in parts for n in (v.net("a"), v.net("b"))}
    outs = [q for q in host.nets if host.net(q) in ends and pins[q][2] > 0]
    ins = [q for q in host.nets if host.net(q) in ends and q not in outs]
    above = not ins or pins[ins[0]][1] <= 0           # on the side of the input pin it returns to
    net = host.net(outs[0]) if outs else None
    for i, v in enumerate(parts):
        near = "a" if v.net("a") == net else "b"
        at = x + (len(parts) - 1 - 2 * i) * 30        # the output's end on the right, like the block's output
        board.settle(v, at, y + (-(hh + 30) if above else hh + 30), _flat(v, near, near_left=False), (0, -30 if above else 30))
        net = v.net("b" if near == "a" else "a")


def _attach_block(board, v):
    o = {}
    pins = symbols.pins(v, o)
    hw, hh = symbols.block_size(v)
    drives = [(q, a) for q in v.nets if pins[q][2] > 0 for a in board.anchors(v, q) if a[2] < 0]
    if drives:                                        # stand left of the pin its output drives
        q, (x, y, ex, ey, d) = drives[0]
        board.settle(v, x - 40 - pins[q][0], y - pins[q][1], o, (-20, 0))
        return True
    fed = [(q, a) for q in v.nets if pins[q][2] < 0 for a in board.anchors(v, q)]
    fed.sort(key=lambda t: (t[1][2] <= 0, t[1][0]))   # prefer a pin that faces right, the leftmost
    if fed:
        q, (x, y, ex, ey, d) = fed[0]
        board.settle(v, x + (NEAR if ex > 0 else 60) - pins[q][0], y - pins[q][1], o, (20, 0))
        return True
    return False


def _attach_part(board, v):
    """A flat or unruled two-pin part, or a switch: beside the pin it serves."""
    p, q = _ends(v)
    A, B = board.anchors(v, p), board.anchors(v, q)
    if not A and not B:
        return False
    if v.name not in board.k.flat and A and B:        # no rule of its own: span its two nets the short way
        a, b = min(((a, b) for a in A for b in B), key=lambda t: abs(t[0][0] - t[1][0]) + abs(t[0][1] - t[1][1]))
        if abs(a[1] - b[1]) > abs(a[0] - b[0]) and abs(a[1] - b[1]) >= 60 and v.kind != "t":
            top = p if a[1] < b[1] else q
            x = a[0] if a[1] < b[1] else b[0]
            y = int(round((a[1] + b[1]) / 20.0)) * 10
            board.settle(v, x + 40, y, {"upright": True, "flip": top == "b"}, (20, 0))
            return True

    def rank(a):                                      # a gate or a block input first, then a flat part's end
        x, y, ex, ey, d = a
        return (0 if ex and d.kind in ("t", "blk") else 1 if ex else 2, x)
    cands = [(rank(a), p, a) for a in A] + [(rank(a), q, a) for a in B]
    r, near, a = min(cands, key=lambda t: t[0])
    _beside(board, v, near, a)
    return True


def _attach(c, k, board):
    """Place every device the rows and columns did not."""
    loop_of = {part: (c.by[host], [c.by[n] for n in parts]) for host, parts in k.loops for part in parts}
    flow_rank = {}
    for rule, kind, p, text in k.relations:
        if kind == "not_left":
            for d in list(p[0]) + list(p[1]):
                flow_rank.setdefault(d.name, len(flow_rank))
    deck = {v.name: i for i, v in enumerate(c.devs)}
    pending = sorted((v for v in c.devs if v.name not in board.at), key=lambda v: (flow_rank.get(v.name, 10 ** 6), deck[v.name]))
    for _ in range(len(pending) + 1):
        if not pending:
            break
        done = None
        for v in pending:
            host, parts = loop_of.get(v.name, (None, ()))
            if host is not None and host.name in board.at:
                _attach_around(board, parts, host)
                done = parts
            elif host is not None and len(pending) > len(parts) and host in pending:
                continue                              # wait for the device it goes round
            elif v.kind == "blk":
                done = [v] if _attach_block(board, v) else None
            else:
                done = [v] if _attach_part(board, v) else None
            if done is not None:
                break
        if done is None:                              # nothing placed touches what is left: start a new lane
            v = pending[0]
            x = max((b[2] for b in board.boxes), default=-120) + 120
            y = min((b[1] for b in board.boxes), default=0) + 40 if board.boxes else 0
            y = int(round(y / 10.0)) * 10
            o = {} if v.kind == "blk" else {"upright": False, "flip": False} if v.kind != "t" else {"upright": False, "gate": "up", "flip": False}
            board.settle(v, x, y, o, (20, 0))
            done = [v]
        pending = [v for v in pending if v not in done]
    assert not pending


def _lanes(c, k, board, lay):
    """Put each lane part at its x, on the level of the pin it serves; in flow order."""
    deck = {v.name: i for i, v in enumerate(c.devs)}
    todo = sorted((n for n in lay.lane if n not in board.at), key=lambda n: (lay.x[n], deck[n]))
    level = {}                                        # lane index -> y of the last part put on it
    ins = {p[0] for rule, kind, p, text in k.relations if kind == "port_in"}
    outs = {p[0] for rule, kind, p, text in k.relations if kind == "port_out"}

    def toward(v, net):
        """Where the rest of `net` stands along x: the mean of its other devices, the far left
        for an input the flow starts at, the far right for its output; None when unknown."""
        xs = [lay.x[w.name] for w, q in c.net_pins.get(net, ()) if w is not v and w.name in lay.x]
        return sum(xs) / float(len(xs)) if xs else -1e9 if net in ins else 1e9 if net in outs else None
    for name in todo:
        v, x, ln = c.by[name], lay.x[name], lay.lane[name]
        if v.kind == "blk":
            o, pins = {}, symbols.pins(v, {})
            feed = [(q, a) for q in v.nets if pins[q][2] < 0 for a in board.anchors(v, q) if a[2] > 0 and a[0] < x]
            drive = [(q, a) for q in v.nets if pins[q][2] > 0 for a in board.anchors(v, q) if a[2] < 0 and a[0] > x]
            if feed:                                  # an input pin level with what feeds it
                q, a = max(feed, key=lambda t: t[1][0])
                y = a[1] - pins[q][1]
            elif drive:
                q, a = min(drive, key=lambda t: t[1][0])
                y = a[1] - pins[q][1]
            else:
                y = level.get(ln, -ln * LANE)
            board.settle(v, x, y, o, (0, -20))
            level[ln] = board.at[name][1]
            continue
        p, q = _ends(v)
        A, B = board.anchors(v, p), board.anchors(v, q)
        sp, sq = toward(v, v.net(p)), toward(v, v.net(q))
        left = [(a, n) for n, L in ((p, A), (q, B)) for a in L if a[0] <= x]
        right = [(a, n) for n, L in ((p, A), (q, B)) for a in L if a[0] > x]
        y, near, near_left = None, None, True
        for a, n in sorted(right, key=lambda t: t[0][0]):          # the gate or input it leads into
            if a[2] < 0:
                y, near, near_left = a[1], n, False
                break
        if y is None:
            for a, n in sorted(left, key=lambda t: -t[0][0]):      # carry on from what came before
                y, near, near_left = (a[1] if a[2] else a[1] + a[3] * NEAR), n, True
                break
        if y is None and right:
            a, n = min(right, key=lambda t: t[0][0])
            y, near, near_left = (a[1] if a[2] else a[1] + a[3] * NEAR), n, False
        if y is None:
            y, near = level.get(ln, -ln * LANE), p
            near_left = True
            if v.net(q) is not None and v.net(p) is not None:      # the end toward the next flow part goes right
                after = {m for w in c.devs if w.name in lay.x and lay.x[w.name] > x for m in w.nets.values() if m}
                if v.net(p) in after and v.net(q) not in after:
                    near, near_left = p, False
                elif v.net(q) in after:
                    near, near_left = q, False
        if sp is not None and sq is not None and sp != sq:         # the end whose net stands further left looks left
            near, near_left = (p if sp < sq else q), True
        board.settle(v, x, y, _flat(v, near, near_left), (0, -20))
        level[ln] = board.at[name][1]


def _row_y(k, rows, height):
    """y of each row: 80 px apart, with 40 more where a cross-coupled pair draws its X."""
    extra = [0] * (height + 1)                        # extra[r]: added above row r
    for a, b in k.cross:
        if a in rows and rows[a] == rows.get(b):
            extra[rows[a] + (0 if k.view.c.by[a].pol == "n" else 1)] = 40
    ys, y = [], 0
    for r in range(height):
        y += extra[r]
        ys.append(y)
        y += ROW
    return ys


def _bridges(c, k, board, lay):
    """M4: a part bridging the two halves of a matched pair lies flat on the axis, clear of an X."""
    axis = {g["pair"]: g["axis"] for g in lay.groups}
    for rule, kind, p, text in k.relations:
        if kind != "on_axis" or p[0].name in board.at or p[0].kind in ("t", "blk"):
            continue
        v = p[0]
        ax = axis.get((p[1].name, p[2].name), axis.get((p[2].name, p[1].name)))
        A, B = board.anchors(v, "a"), board.anchors(v, "b")
        if ax is None or not A or not B:
            continue
        far = [a for a in A + B if a[3] > 0]          # a pin of the row beyond: stand just past it
        near = [a for a in A + B if a[3] < 0]
        if far:
            y = max(a[1] for a in far) + NEAR
        elif near:
            y = min(a[1] for a in near) - 60 - NEAR
        else:
            y = min(a[1] for a in A + B)
        left = "a" if sum(a[0] for a in A) / len(A) <= sum(b[0] for b in B) / len(B) else "b"
        board.settle(v, ax, y, _flat(v, left, near_left=True), (0, -20))


def _room(c, k, gate):
    """{transistor: (px, px)}: how much more clear space its column needs on the left and on
    the right: for a row of parts round it (B4, D4), and for a port or a net name at its gate."""
    need = collections.defaultdict(int)
    for host, parts in k.loops:
        if host in gate and len(parts) > 1:           # one part fits beside any column
            need[host] = max(need[host], 60 * len(parts) - 40)
    roles = k.view.k.roles
    for v in c.devs:
        g = v.net("g") if v.name in gate else None
        if g is None or g in k.view.rails:
            continue
        text = 7 * len(g)
        if roles.get(g) in ("bias", "clock"):
            need[v.name] = max(need[v.name], text - 20)             # a name on a 20 px stub
        elif g in c.port_nets and all(d.kind == "t" and q == "g" for d, q in c.net_pins[g]):
            need[v.name] = max(need[v.name], text + 10)             # a port on a 40 px wire
    out = {}
    for name, px in need.items():
        px = -(-px // 10) * 10
        if px > 0:
            out[name] = (px, 0) if gate[name] == "left" else (0, px)
    return out


def place(c, k):
    """-> (placement {name: (x, y, o)}, axis groups, notes). See the module header."""
    rows, height, notes = assign_rows(c, k)
    lay = assign_columns(c, k)
    X, groups = {n: x for n, x in lay.x.items() if n in k.upright}, lay.groups
    notes += lay.notes
    gate = orient_gates(c, k, X, groups, rows)
    room = _room(c, k, gate)
    if room:                                          # the same order, wider where something needs it
        lay = assign_columns(c, k, room)
        X, groups = {n: x for n, x in lay.x.items() if n in k.upright}, lay.groups
    row_y = _row_y(k, rows, height)
    board = Board(c, k)
    spans = collections.defaultdict(list)
    for v in c.devs:
        if v.name not in X:
            continue
        y = row_y[rows[v.name]]
        if v.kind == "t":
            x = X[v.name] - 10 if gate[v.name] == "left" else X[v.name] + 10
            o = {"upright": True, "gate": gate[v.name]}
        else:
            x, o = X[v.name], {"upright": True, "flip": k.top[v.name] == v.net("b")}
        if board.free(v, x, y, o, pad=0):
            board.add(v, x, y, o)
        else:                                         # never one symbol on another, whatever the rows said
            board.settle(v, x, y, o, (0, 20))
            notes.append("%s moved down: its row and column were taken" % v.name)
        spans[X[v.name]].append(board.at[v.name][1])
    for x, ys in spans.items():                       # the wire of a column: nothing may be laid across it
        if max(ys) - min(ys) > ROW:
            board.keep_out((x - 5, min(ys), x + 5, max(ys)))
    for a, b in k.cross:                              # where an X will be drawn: keep parts out of it
        if a in X and b in X and board.at[a][1] == board.at[b][1]:
            xa, xb = sorted((X[a], X[b]))
            y = board.at[a][1]
            board.keep_out((xa + 15, y - 65, xb - 15, y - 5) if c.by[a].pol == "n" else (xa + 15, y + 5, xb - 15, y + 65))
    _bridges(c, k, board, lay)
    _lanes(c, k, board, lay)
    _attach(c, k, board)
    placement = dict(board.at)
    x0 = min(x + symbols.body(c.by[n], o)[0] for n, (x, y, o) in placement.items())
    y0 = min(y + symbols.body(c.by[n], o)[1] for n, (x, y, o) in placement.items())
    dx, dy = 80 - x0, 80 - y0
    placement = {n: (x + dx, y + dy, o) for n, (x, y, o) in placement.items()}
    for g in groups:
        g["axis"] += dx
    assert len(placement) == len(c.devs)
    return placement, groups, notes
