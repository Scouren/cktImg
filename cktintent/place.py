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


def orient_gates(c, k, X, groups):
    """{transistor name: 'left'|'right'} for the upright transistors, from M2, B6 and the axes."""
    gate, twins = {}, []
    for rule, kind, p, text in k.relations:
        if kind == "gates" and p[0].name in X and p[1].name in X:
            l, r = (p[0], p[1]) if X[p[0].name] <= X[p[1].name] else (p[1], p[0])
            if p[2] == "inward":
                gate[l.name], gate[r.name] = "right", "left"
            elif p[2] == "outward":
                gate[l.name], gate[r.name] = "left", "right"
            else:
                twins.append((l.name, r.name))
        elif kind == "mirrored" and p[0].name in X and p[1].name in X and p[0].kind == "t":
            l, r = (p[0], p[1]) if X[p[0].name] <= X[p[1].name] else (p[1], p[0])
            twins.append((l.name, r.name))
    for rule, kind, p, text in k.relations:
        if kind == "gate_toward_pins" and p[0].name in X and p[0].name not in gate:
            xs = [X[d.name] for d, q in p[1] if d.name in X]
            if xs and abs(sum(xs) / len(xs) - X[p[0].name]) > 20:
                gate[p[0].name] = "left" if sum(xs) / len(xs) < X[p[0].name] else "right"
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
        self.at[v.name] = (x, y, o)
        b = symbols.body(v, o)
        self.boxes.append((x + b[0], y + b[1], x + b[2], y + b[3]))

    def keep_out(self, box):
        self.boxes.append(box)

    def free(self, v, x, y, o, pad=10):
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


def _attach_around(board, v, host):
    """B4: a part from a device's output back to its input goes round the device."""
    x, y, o = board.at[host.name]
    if host.kind == "t":
        up = host.pol == "n"                          # the drain end: above an NMOS, below a PMOS
        side = -1 if o["gate"] == "left" else 1       # on the gate's side of the channel
        near = "a" if v.net("a") == host.net("d") else "b"
        channel = x + (10 if o["gate"] == "left" else -10)
        board.settle(v, channel + side * 60, y + (-40 if up else 40), _flat(v, near, near_left=side > 0), (side * 20, 0))
        return
    hw, hh = symbols.block_size(host)
    pins = symbols.pins(host, o)
    outs = [q for q in host.nets if host.net(q) in (v.net("a"), v.net("b")) and pins[q][2] > 0]
    ins = [q for q in host.nets if host.net(q) in (v.net("a"), v.net("b")) and q not in outs]
    above = not ins or pins[ins[0]][1] <= 0           # on the side of the input pin it returns to
    near = "a" if outs and v.net("a") == host.net(outs[0]) else "b"
    board.settle(v, x, y + (-(hh + 30) if above else hh + 30), _flat(v, near, near_left=False), (0, -30 if above else 30))


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
    host_of = {part: c.by[dev] for part, (_, dev) in k.around.items()}
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
            host = host_of.get(v.name)
            if host is not None and host.name in board.at:
                _attach_around(board, v, host)
                done = v
            elif host is not None and host.name not in board.at and len(pending) > 1 and any(w is host for w in pending):
                continue                              # wait for the device it goes round
            elif v.kind == "blk":
                done = v if _attach_block(board, v) else None
            else:
                done = v if _attach_part(board, v) else None
            if done is not None:
                break
        if done is None:                              # nothing placed touches what is left: start a new lane
            done = pending[0]
            x = max((b[2] for b in board.boxes), default=-120) + 120
            y = min((b[1] for b in board.boxes), default=0) + 40 if board.boxes else 0
            y = int(round(y / 10.0)) * 10
            o = {} if done.kind == "blk" else {"upright": False, "flip": False} if done.kind != "t" else {"upright": False, "gate": "up", "flip": False}
            board.settle(done, x, y, o, (20, 0))
        pending.remove(done)
    assert not pending


def place(c, k):
    """-> (placement {name: (x, y, o)}, axis groups, notes). See the module header."""
    rows, height, notes = assign_rows(c, k)
    X, groups, more = assign_columns(c, k)
    notes += more
    gate = orient_gates(c, k, X, groups)
    board = Board(c, k)
    spans = collections.defaultdict(list)
    for v in c.devs:
        if v.name not in X:
            continue
        y = rows[v.name] * ROW
        if v.kind == "t":
            x = X[v.name] - 10 if gate[v.name] == "left" else X[v.name] + 10
            o = {"upright": True, "gate": gate[v.name]}
        else:
            x, o = X[v.name], {"upright": True, "flip": k.top[v.name] == v.net("b")}
        board.add(v, x, y, o)
        spans[X[v.name]].append(y)
    for x, ys in spans.items():                       # the wire of a column: nothing may be laid across it
        if max(ys) - min(ys) > ROW:
            board.keep_out((x - 5, min(ys), x + 5, max(ys)))
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
