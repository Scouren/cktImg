"""Corpus loading and stand-in statements, for the sweep only (`tools/corpus.py`).
The corpus is untrusted third-party data: run with `python3 -I`, pass its path as an argument."""
import collections, glob, hashlib, json, os, re
from cktintent.circuit import Ckt, BLOCK_OUT, diode_connected

SOURCES = ["analoggenie", "amsnet", "analogretriever", "circuitthink"]


def held_out(cid):
    """Deterministic 20% hold-out by id: rules are derived on the other 80%."""
    return int(hashlib.sha1(cid.encode()).hexdigest(), 16) % 5 == 0


def load_all(root, split=None, ids=None):
    """Yield Ckt for every drawing. split: None (all), 'train' or 'test'."""
    for src in SOURCES:
        for fn in sorted(glob.glob(os.path.join(root, src, "*.human.json"))):
            cid = os.path.basename(fn)[:-11]
            if ids is not None and cid not in ids:
                continue
            if split == "train" and held_out(cid):
                continue
            if split == "test" and not held_out(cid):
                continue
            try:
                yield Ckt(json.load(open(fn)))
            except (KeyError, ValueError, IndexError, TypeError):
                continue


def find_structs(c):
    """Motifs a netlist states. Returns dict of lists; each device may appear in several."""
    T = c.ts()
    out = collections.defaultdict(list)
    n = len(T)
    cross, pairs, mirrors = [], [], collections.defaultdict(list)
    for i in range(n):
        a = T[i]
        for j in range(i + 1, n):
            b = T[j]
            if a.pol != b.pol or a.type != b.type:
                continue
            ag, ad, as_ = a.net("g"), a.net("d"), a.net("s")
            bg, bd, bs = b.net("g"), b.net("d"), b.net("s")
            if None in (ag, ad, as_, bg, bd, bs):
                continue
            if ag == bd and bg == ad and ad != bd:
                cross.append((a, b))
            elif as_ == bs and not c.is_rail(as_) and ag != bg and ad != bd and ag != ad and bg != bd:
                pairs.append((a, b))
    # a shared-source net with more than two same-type sources is a bank of pairs; keep pairs
    # whose source net has exactly two transistor sources of this kind (the classic pair)
    for a, b in pairs:
        srcs = [v for v in c.on(a.net("s"), "s") if v.kind == "t"]
        if len(srcs) == 2:
            out["pair"].append((a, b))
        else:
            out["pair_multi"].append((a, b))
    out["cross"] = cross
    # mirrors: same type, same gate net, same source net, at least one diode-connected
    for v in T:
        if v.net("g") and v.net("s"):
            mirrors[(v.type, v.net("g"), v.net("s"))].append(v)
    for key, ms in mirrors.items():
        if len(ms) < 2:
            continue
        refs = [v for v in ms if diode_connected(v)]
        if refs:
            out["mirror"].append((refs, [v for v in ms if not diode_connected(v)], ms))
        else:
            out["bank"].append(ms)
    # cascode: same polarity, upper.s == lower.d on a net with exactly these two channel pins
    for lo in T:
        dn = lo.net("d")
        if not dn or c.is_rail(dn):
            continue
        ch = [(v, p) for v, p in c.net_pins[dn] if v.kind == "t" and p in ("d", "s")]
        if len(ch) != 2:
            continue
        up = [v for v, p in ch if p == "s" and v is not lo and v.pol == lo.pol]
        if up and lo.net("g") != up[0].net("g"):
            out["cascode"].append((up[0], lo))
    # complementary inverter: n and p sharing gate and drain
    for a in T:
        for b in T:
            if a.pol == "n" and b.pol == "p" and a.net("g") == b.net("g") and a.net("d") == b.net("d") and a.net("g") != a.net("d") and a.net("d"):
                out["inv"].append((b, a))
            if a.pol == "n" and b.pol == "p" and a.net("d") and a.net("s") and {a.net("d"), a.net("s")} == {b.net("d"), b.net("s")} and a.net("d") != a.net("s"):
                out["tgate"].append((b, a))
    return out


def pct(k, n):
    """'k of n (p%)' for a report line."""
    return "%d of %d (%.0f%%)" % (k, n, 100.0 * k / n) if n else "0 of 0"


def signal_depth(c, inputs):
    """BFS depth of every net from the input nets, along signal edges:
    gate->drain, gate->source, source->drain; two-pin parts both ways off the rails; blocks in->out."""
    depth = {n: 0 for n in inputs if n in c.net_pins}
    via = {}
    q = collections.deque(depth)
    while q:
        n = q.popleft()
        for v, p in c.net_pins.get(n, []):
            outs = []
            if v.kind == "t":
                if p == "g":
                    outs = [v.net("d"), v.net("s")]
                elif p == "s":
                    outs = [v.net("d")]
                elif p == "d" and not v.vertical:
                    outs = [v.net("s")]
            elif v.kind == "blk":
                if not BLOCK_OUT.match(p):
                    outs = [m for q2, m in v.nets.items() if BLOCK_OUT.match(q2)]
            elif v.kind in ("r", "c", "l", "d", "sw", "x"):
                outs = [v.net("b" if p == "a" else "a")]
            for m in outs:
                if m and m not in depth and m not in c.rails:
                    depth[m] = depth[n] + 1
                    via[m] = (v, n)
                    q.append(m)
    return depth, via
