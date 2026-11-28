"""The wire maze: a grid on which nets are wired one terminal at a time.

A cell is 10 px. A wire of one net may cross another's only straight through, where neither
bends, ends or branches; it may never run along another net's wire, enter a symbol, or touch
another net's pin. Under those rules two nets cannot be joined by accident, which
`gates.extract` then checks from the finished geometry alone.

    m = Maze(); m.block(x0, y0, x1, y1); m.pin(net, x, y, ex, ey)
    m.connect(net, [(x, y), ...]) -> the terminals it could not reach
    m.segments(net), m.junctions(net)
"""
import heapq

CELL = 10
BEND, CROSS, LIMIT = 3, 12, 40000


class Maze:
    def __init__(self):
        self.blocked = set()       # cells no wire may enter
        self.pins = {}             # cell -> (net, (ex, ey)): a pin and the way a wire leaves it
        self.h, self.v = {}, {}    # cell -> net of the wire running through it horizontally / vertically
        self.node = {}             # cell -> net: a bend, an end or a branch (no other wire may cross here)
        self.edges = {}            # net -> set of ((i, j), (i2, j2)) unit steps, ordered low to high
        self.tree = {}             # net -> set of cells already joined
        self.lo, self.hi = [0, 0], [0, 0]

    # ---------------------------------------------------------------- building
    def _grow(self, i, j):
        self.lo = [min(self.lo[0], i - 8), min(self.lo[1], j - 8)]
        self.hi = [max(self.hi[0], i + 8), max(self.hi[1], j + 8)]

    def block(self, x0, y0, x1, y1):
        """No wire enters the closed box (px). Pins registered later stay reachable."""
        for i in range(x0 // CELL, x1 // CELL + 1):
            for j in range(y0 // CELL, y1 // CELL + 1):
                self.blocked.add((i, j))
        self._grow(x0 // CELL, y0 // CELL)
        self._grow(x1 // CELL, y1 // CELL)

    def pin(self, net, x, y, ex, ey):
        """A terminal of `net` at (x, y) px; a wire leaves it along (ex, ey)."""
        assert x % CELL == 0 and y % CELL == 0 and (abs(ex) + abs(ey) == 1), (net, x, y, ex, ey)
        cell = (x // CELL, y // CELL)
        assert cell not in self.pins or self.pins[cell][0] == net, "two nets share the pin point %r" % (cell,)
        self.pins[cell] = (net, (ex, ey))
        self._grow(*cell)

    def free(self, x, y):
        """True when nothing stands or runs at (x, y) px."""
        cell = (x // CELL, y // CELL)
        return cell not in self.blocked and cell not in self.pins and cell not in self.h and cell not in self.v

    # ---------------------------------------------------------------- one connection
    def _enter(self, net, cell, d):
        """Cost of stepping into `cell` along d for `net`, or None when it may not."""
        if not (self.lo[0] <= cell[0] <= self.hi[0] and self.lo[1] <= cell[1] <= self.hi[1]):
            return None
        p = self.pins.get(cell)
        if p is not None:
            return 1 if p[0] == net and (-d[0], -d[1]) == p[1] else None
        if cell in self.blocked:
            return None
        along, across = (self.h, self.v) if d[0] else (self.v, self.h)
        if along.get(cell, net) != net:
            return None
        if across.get(cell, net) != net:
            return None if cell in self.node else 1 + CROSS
        if self.node.get(cell, net) != net:
            return None
        return 1

    def _crossing(self, net, cell, d):
        across = self.v if d[0] else self.h
        return across.get(cell, net) != net

    def _path(self, net, start, targets):
        """Cheapest legal path from pin cell `start` to any cell of `targets`, or None."""
        s_net, e = self.pins[start]
        tx = [t for t in targets]
        if not tx:
            return None
        cx = sum(t[0] for t in tx) / float(len(tx))
        cy = sum(t[1] for t in tx) / float(len(tx))
        spread = max(abs(t[0] - cx) + abs(t[1] - cy) for t in tx)

        def guess(cell):
            return max(0.0, abs(cell[0] - cx) + abs(cell[1] - cy) - spread)
        best = {(start, e): 0}
        heap = [(guess(start), 0, start, e, None)]
        came = {}
        seen = 0
        while heap and seen < LIMIT:
            f, g, cell, d, prev = heapq.heappop(heap)
            if best.get((cell, d), 1e18) < g:
                continue
            seen += 1
            if cell in targets and cell != start and not self._crossing(net, cell, d):
                path = [cell]
                key = (cell, d)
                while key in came:
                    key = came[key]
                    path.append(key[0])
                return path[::-1]
            if cell == start:
                moves = [e]
            elif self._crossing(net, cell, d):
                moves = [d]                        # straight through another net's wire
            else:
                moves = [d, (d[1], d[0]), (-d[1], -d[0])]
            for m in moves:
                nxt = (cell[0] + m[0], cell[1] + m[1])
                step = self._enter(net, nxt, m)
                if step is None:
                    continue
                ng = g + step + (BEND if m != d else 0)
                if ng < best.get((nxt, m), 1e18):
                    best[(nxt, m)] = ng
                    came[(nxt, m)] = (cell, d)
                    heapq.heappush(heap, (ng + guess(nxt), ng, nxt, m, cell))
        return None

    def _commit(self, net, path):
        edges = self.edges.setdefault(net, set())
        tree = self.tree.setdefault(net, set())
        for a, b in zip(path, path[1:]):
            d = (b[0] - a[0], b[1] - a[1])
            grid = self.h if d[0] else self.v
            grid[a] = grid[b] = net
            edges.add((min(a, b), max(a, b)))
        for i, cell in enumerate(path):
            turn = 0 < i < len(path) - 1 and (path[i + 1][0] - cell[0], path[i + 1][1] - cell[1]) != (cell[0] - path[i - 1][0], cell[1] - path[i - 1][1])
            if i in (0, len(path) - 1) or turn:
                self.node[cell] = net
            tree.add(cell)

    def connect(self, net, points):
        """Wire the terminals of `net` (px points, each registered with `pin`) into one tree.
        -> the points that could not be reached; they stay unwired."""
        cells = [(x // CELL, y // CELL) for x, y in points]
        assert all(c in self.pins and self.pins[c][0] == net for c in cells), net
        if not cells:
            return []
        tree = self.tree.setdefault(net, set())
        if not tree:
            tree.add(min(cells))
        todo = [c for c in cells if c not in tree]
        lost = []
        for _ in range(len(todo)):
            cell = min(todo, key=lambda c: min(abs(c[0] - t[0]) + abs(c[1] - t[1]) for t in tree))
            todo.remove(cell)
            path = self._path(net, cell, tree)
            if path is None:                      # the tree may be reachable only from its own side
                for t in sorted(tree & set(self.pins), key=lambda t: abs(t[0] - cell[0]) + abs(t[1] - cell[1])):
                    back = self._path(net, t, {cell})
                    if back is not None:
                        path = back
                        break
            if path is None:
                lost.append((cell[0] * CELL, cell[1] * CELL))
            else:
                self._commit(net, path)
        return lost

    # ---------------------------------------------------------------- reading the result
    def segments(self, net):
        """The net's wires as maximal straight runs [[x0, y0], [x1, y1]] in px, split at its branches."""
        edges = self.edges.get(net, set())
        deg = {}
        for a, b in edges:
            deg[a] = deg.get(a, 0) + 1
            deg[b] = deg.get(b, 0) + 1
        out = []
        for horizontal in (True, False):
            runs = sorted((a, b) for a, b in edges if (a[1] == b[1]) == horizontal)
            runs.sort(key=(lambda e: (e[0][1], e[0][0])) if horizontal else (lambda e: (e[0][0], e[0][1])))
            cur = None
            for a, b in runs:
                if cur is not None and cur[1] == a and deg.get(a, 0) == 2:
                    cur[1] = b
                else:
                    if cur is not None:
                        out.append(cur)
                    cur = [a, b]
            if cur is not None:
                out.append(cur)
        return [[[a[0] * CELL, a[1] * CELL], [b[0] * CELL, b[1] * CELL]] for a, b in out]

    def junctions(self, net):
        """Points (px) where three or more arms of the net meet."""
        deg = {}
        for a, b in self.edges.get(net, set()):
            deg[a] = deg.get(a, 0) + 1
            deg[b] = deg.get(b, 0) + 1
        return [[c[0] * CELL, c[1] * CELL] for c, n in sorted(deg.items()) if n >= 3]

    def crossings(self):
        """How many times two different nets' wires cross."""
        return sum(1 for cell, net in self.h.items() if self.v.get(cell, net) != net)
