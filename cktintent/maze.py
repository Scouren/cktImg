"""The wire maze: a grid on which nets are wired one terminal at a time.

A cell is 10 px. A wire of one net may cross another's only straight through, where neither
bends, ends or branches; it may never run along another net's wire, enter a symbol, or touch
another net's pin. Under those rules two nets cannot be joined by accident, which
`gates.extract` then checks from the finished geometry alone.

    m = Maze(); m.block(x0, y0, x1, y1); m.pin(net, x, y, ex, ey)
    m.connect(net, [(x, y), ...]) -> the wired pieces, as groups of terminals
    m.segments(net), m.junctions(net)
"""
import heapq

CELL = 10
BEND, CROSS, LIMIT = 3, 12, 40000


class Maze:
    def __init__(self):
        self.blocked = set()       # cells no wire may enter
        self.dear = {}             # cell -> extra cost of a wire through it
        self.written = set()       # cells a device's name covers
        self.pins = {}             # cell -> (net, (ex, ey)): a pin and the way a wire leaves it
        self.h, self.v = {}, {}    # cell -> net of the wire running through it horizontally / vertically
        self.node = {}             # cell -> net: a bend, an end or a branch (no other wire may cross here)
        self.edges = {}            # net -> set of ((i, j), (i2, j2)) unit steps, ordered low to high
        self.tree = {}             # net -> set of cells a wire of the net already reaches
        self.links = {}            # net -> [(cell, cell)] joined by a wire drawn outside the grid (a slanted one)
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

    def text(self, x0, y0, x1, y1, cost):
        """Writing stands in the closed box (px): no other writing or stub goes there (`free`
        says no), and a wire through it pays `cost` more per cell."""
        self.discourage(x0, y0, x1, y1, cost)
        self.written.update((i, j) for i in range(x0 // CELL, x1 // CELL + 1) for j in range(y0 // CELL, y1 // CELL + 1))

    def discourage(self, x0, y0, x1, y1, cost):
        """A wire through the closed box (px) pays `cost` more per cell."""
        for i in range(x0 // CELL, x1 // CELL + 1):
            for j in range(y0 // CELL, y1 // CELL + 1):
                self.dear[(i, j)] = max(self.dear.get((i, j), 0), cost)

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
        return (cell not in self.blocked and cell not in self.pins and cell not in self.h and cell not in self.v
                and cell not in self.written)

    def open(self, net, x, y):
        """True when a wire of `net` may be laid at (x, y) px: free, or its own pin or wire."""
        cell = (x // CELL, y // CELL)
        if cell in self.pins:
            return self.pins[cell][0] == net
        return cell not in self.blocked and self.h.get(cell, net) == net and self.v.get(cell, net) == net

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
        return 1 + self.dear.get(cell, 0)

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

    def _link(self, net, cell, group):
        """A path joining pin `cell` to `group` (a set of cells), searched from either side."""
        path = self._path(net, cell, group)
        if path is None:                          # the group may be reachable only from its own side
            for t in sorted(group & set(self.pins), key=lambda t: abs(t[0] - cell[0]) + abs(t[1] - cell[1]))[:4]:
                path = self._path(net, t, {cell})
                if path is not None:
                    break
        return path

    def _laid(self, net):
        """The pieces already laid for `net`, as sets of cells: what `lay` and `claim` drew."""
        adj = {}
        for a, b in list(self.edges.get(net, ())) + self.links.get(net, []):
            adj.setdefault(a, set()).add(b)
            adj.setdefault(b, set()).add(a)
        seen, out = set(), []
        for cell in sorted(self.tree.get(net, ())):
            if cell in seen:
                continue
            piece, todo = {cell}, [cell]
            while todo:
                for nxt in adj.get(todo.pop(), ()):
                    if nxt not in piece:
                        piece.add(nxt)
                        todo.append(nxt)
            seen |= piece
            out.append(piece)
        return out

    def connect(self, net, points):
        """Wire the terminals of `net` (px points, each registered with `pin`).
        -> groups of points, the largest first: one group when the net is one wire; each
        further group is a piece the maze could not join and that a name must."""
        cells = []
        for x, y in points:
            c = (x // CELL, y // CELL)
            assert c in self.pins and self.pins[c][0] == net, (net, x, y)
            if c not in cells:
                cells.append(c)
        groups = self._laid(net)                   # pieces laid before count, each on its own
        for cell in sorted(cells):
            if any(cell in g for g in groups):
                continue
            for g in sorted(groups, key=len, reverse=True):
                path = self._link(net, cell, g)
                if path is not None:
                    self._commit(net, path)
                    g.update(path)
                    break
            else:
                groups.append({cell})
        for _ in range(len(groups)):               # pieces that can now reach each other
            merged = False
            groups.sort(key=len, reverse=True)
            for g in groups[1:]:
                for cell in sorted(g & set(self.pins)):
                    path = self._link(net, cell, groups[0])
                    if path is not None:
                        self._commit(net, path)
                        groups[0].update(path)
                        groups[0].update(g)
                        groups.remove(g)
                        merged = True
                        break
                if merged:
                    break
            if not merged:
                break
        groups.sort(key=len, reverse=True)
        self.tree[net] = set().union(*groups) if groups else set()
        mine = set(cells)
        return [[(c[0] * CELL, c[1] * CELL) for c in sorted(g & mine)] for g in groups if g & mine]

    def lay(self, net, points):
        """Lay a wire of `net` along the given px points (each step straight, on the grid),
        outside the search. The points become part of the net's tree."""
        path = []
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            a, b = (x0 // CELL, y0 // CELL), (x1 // CELL, y1 // CELL)
            assert a[0] == b[0] or a[1] == b[1], (net, points)
            d = ((b[0] > a[0]) - (b[0] < a[0]), (b[1] > a[1]) - (b[1] < a[1]))
            cell = a
            while cell != b:
                if not path or path[-1] != cell:
                    path.append(cell)
                cell = (cell[0] + d[0], cell[1] + d[1])
            path.append(b)
        self._commit(net, path)

    def claim(self, net, x, y, to):
        """Count the pin at (x, y) px as joined to the net's laid wire at `to` px: a slanted
        wire, drawn outside the grid, runs between them."""
        a, b = (x // CELL, y // CELL), (to[0] // CELL, to[1] // CELL)
        self.tree.setdefault(net, set()).update((a, b))
        self.links.setdefault(net, []).append((a, b))

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
