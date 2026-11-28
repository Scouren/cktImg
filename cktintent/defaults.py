"""Defaults: what the placer does where the contract promises nothing.

The contract (`contract.derive`) holds what a drawing must show and is judged. A default is a
choice people make often enough to follow but not often enough to promise; the judge never
checks one. Counts are from the corpus's training drawings.

    D1  a cross-coupled pair looks inward and swaps its gate wires as an X
        (its two branch lines stand 3.0 units apart at the median; 476 of 546 slanted wires are in an X)
    D2  every upright image of a matched pair mirrors about the pair's axis when it hangs on
        the pair's own cluster (the contract promises this only in the pair's columns or stage)
    D3  a series string of two-pin parts with one end on a rail stands as one column
        (160 of 229, 70%)
    D4  a series string from a device's output back to its own input lies in one row on the
        input's side, like a single part does under B4 (35 of 38 strings from a drain to its gate, 92%)

    D5  a two-pin part between a supply and a ground stands upright, the supply's end up
        (7 of 12: rare in the corpus, and the only way both rail symbols fit)

`add` writes them onto the Contract as facts for the placer: `cross`, `loops`, `joints`, and
the stance (`upright`, `top`, `bot`) of string parts. `images` (D2) is collected by `derive`.
"""
import collections
from .circuit import BLOCK_OUT

PASSIVE = ("r", "c", "l")


def strings(c, k):
    """Series strings: [(parts, nets)], two or more two-pin parts joined at nodes nothing else
    touches; nets[i] and nets[i + 1] are the two ends of parts[i]."""
    rails = k.view.rails

    def private(net):
        pins = c.net_pins.get(net, ())
        return (len(pins) == 2 and net not in rails and net not in c.port_nets
                and pins[0][0] is not pins[1][0] and all(v.kind in PASSIVE for v, p in pins))

    def other(v, net):
        (a, pa), (b, pb) = c.net_pins[net]
        return b if a is v else a

    def far(v, net):
        return v.net("b") if v.net("a") == net else v.net("a")
    seen, out = set(), []
    for v in c.devs:
        if v.kind not in PASSIVE or v.name in seen or v.net("a") == v.net("b"):
            continue
        if not (private(v.net("a")) or private(v.net("b"))):
            continue
        first, net = v, v.net("a")
        for _ in range(len(c.devs)):               # walk back to the string's first part
            if not private(net) or other(first, net) is v:
                break
            first = other(first, net)
            net = far(first, net)
        parts, nets, nxt = [first], [net], far(first, net)
        for _ in range(len(c.devs)):
            nets.append(nxt)
            if not private(nxt) or other(parts[-1], nxt) in parts:
                break
            parts.append(other(parts[-1], nxt))
            nxt = far(parts[-1], nxt)
        seen.update(p.name for p in parts)
        if len(parts) >= 2:
            out.append((parts, nets))
    return out


def _host(c, k, ends):
    """The device whose output and own input are the two nets `ends`: (device, output net) or None."""
    for d in c.devs:
        if d.kind == "t" and d.name in k.upright and {d.net("g"), d.net("d")} == ends:
            return d, d.net("d")
        if d.kind == "blk":
            outs = [d.net(q) for q in d.pins if BLOCK_OUT.match(q)]
            ins = [d.net(q) for q in d.pins if not BLOCK_OUT.match(q) and d.net(q) not in k.view.rails]
            hit = [n for n in outs if n in ends]
            if hit and any(n in ends for n in ins):
                return d, hit[0]
    return None


def add(c, k):
    """Write the defaults onto Contract `k` (see the module header). Call after the relations exist."""
    rails, supply = k.view.rails, k.view.supply
    by_gd = collections.defaultdict(list)             # D1: each one's gate on the other's drain
    for v in c.devs:
        if v.kind == "t" and v.name in k.upright and v.net("g") and v.net("d") and v.net("g") != v.net("d"):
            by_gd[(v.pol, v.net("g"), v.net("d"))].append(v.name)
    k.cross = sorted((a, b) for (pol, g, d), names in by_gd.items() for a in names
                     for b in by_gd.get((pol, d, g), ()) if a < b)
    for v in c.devs:                                  # D5
        a, b = v.net("a"), v.net("b")
        if v.kind not in ("t", "blk") and v.name not in k.upright and {a, b} & supply and {a, b} & k.view.ground:
            k.upright.add(v.name)
            k.top[v.name], k.bot[v.name] = (a, b) if a in supply else (b, a)
    k.loops = [(host, [part]) for part, (_, host) in k.around.items()]
    k.joints = []
    on_flow = {r[2].name for r in k.relations if r[0] == "F3"}
    for parts, nets in strings(c, k):
        names = [p.name for p in parts]
        if any(n in on_flow or n in k.around for n in names):
            continue
        ends = {nets[0], nets[-1]}
        if len(ends) == 2 and not ends & rails and not any(n in k.upright for n in names):
            found = _host(c, k, ends)                 # D4
            if found:
                host, out_net = found
                if nets[0] != out_net:
                    names.reverse()
                k.loops.append((host.name, names))
                k.around.update((n, (n, host.name)) for n in names)
            continue
        if len(ends) != 2 or not ends & rails or any(n in k.flat for n in names):
            continue
        if nets[-1] in supply or (nets[0] not in supply and nets[0] in rails):   # D3: top of the page first
            parts, nets, names = parts[::-1], nets[::-1], names[::-1]
        stance = [(n, nets[i], nets[i + 1]) for i, n in enumerate(names)]
        if any(n in k.top and (k.top[n], k.bot[n]) != (t, b) for n, t, b in stance):
            continue                                  # a rule already stands one of them another way
        for n, t, b in stance:
            k.upright.add(n)
            k.top[n], k.bot[n] = t, b
        k.joints += list(zip(names, names[1:]))
