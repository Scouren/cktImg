"""Symbol geometry: where a device's pins are, which way a wire leaves each, what it covers.

Everything is in pixels on a 10 px grid; one symbol unit is 40 px (a MOS drain-to-source
length), the corpus's own scale. An orientation `o` is a dict:

    transistor   {"upright": bool, "gate": "left"|"right"|"up"|"down", "flip": bool}
    two-pin part {"upright": bool, "flip": bool}        flip: pin a at the bottom / right
    block        {}                                     inputs left, outputs right

`pins(dev, o)` gives {pin: (dx, dy, ex, ey)} with (ex, ey) the direction a wire leaves the
pin; `body(dev, o)` the box (x0, y0, x1, y1) no wire or other symbol may enter. Pins lie on
the edge of the box. `stamp` writes a placement into the drawing schema.
"""
import re
from .circuit import BLOCK_OUT

UNIT, GRID = 40, 10
SUPPLY_PIN = re.compile(r"^(vdd|vcc|avdd|dvdd|v\+|vp$|vpp)")
GROUND_PIN = re.compile(r"^(vss|gnd|vee|agnd|dgnd|0$|v-)")
BIAS_PIN = re.compile(r"^(vb|bias|ib|vcas|vcm|vc$|su$)")
INVERTING = re.compile(r"(-|n|m)$")


def block_sides(dev):
    """{'left': [pins], 'right': [...], 'top': [...], 'bottom': [...]} for a block."""
    sides = {"left": [], "right": [], "top": [], "bottom": []}
    for p in dev.nets:
        if BLOCK_OUT.match(p):
            sides["right"].append(p)
        elif SUPPLY_PIN.match(p):
            sides["top"].append(p)
        elif GROUND_PIN.match(p) or BIAS_PIN.match(p):
            sides["bottom"].append(p)
        else:
            sides["left"].append(p)
    if dev.type == "opamp" and len(sides["left"]) == 2:      # the inverting input is drawn on top
        sides["left"].sort(key=lambda p: 0 if INVERTING.search(p) else 1)
    return sides


def block_size(dev):
    """(half width, half height) of a block's box, in px."""
    s = block_sides(dev)
    hw = max(40, 10 * max(len(s["top"]), len(s["bottom"])) + 20)
    hh = max(20, 10 * max(len(s["left"]), len(s["right"])) + 10)
    return hw, hh


def _spread(n):
    """n pin offsets 20 px apart, centred on 0 (on the 10 px grid for any n)."""
    return [int((i - (n - 1) / 2.0) * 20) for i in range(n)]


def pins(dev, o):
    """{pin: (dx, dy, ex, ey)}: offset from the device origin and the way a wire leaves."""
    if dev.kind == "t":
        if o["upright"]:
            sx = 1 if o["gate"] == "left" else -1
            top, bot = ("d", "s") if dev.pol == "n" else ("s", "d")
            return {top: (10 * sx, -20, 0, -1), "g": (-20 * sx, 0, -sx, 0), bot: (10 * sx, 20, 0, 1)}
        sy = -1 if o["gate"] == "up" else 1
        left, right = ("d", "s") if o.get("flip") else ("s", "d")
        return {left: (-20, 0, -1, 0), "g": (0, 20 * sy, 0, sy), right: (20, 0, 1, 0)}
    if dev.kind == "blk":
        hw, hh = block_size(dev)
        s, out = block_sides(dev), {}
        for p, y in zip(s["left"], _spread(len(s["left"]))):
            out[p] = (-hw, y, -1, 0)
        for p, y in zip(s["right"], _spread(len(s["right"]))):
            out[p] = (hw, y, 1, 0)
        for p, x in zip(s["top"], _spread(len(s["top"]))):
            out[p] = (x, -hh, 0, -1)
        for p, x in zip(s["bottom"], _spread(len(s["bottom"]))):
            out[p] = (x, hh, 0, 1)
        return out
    first, second = ("b", "a") if o.get("flip") else ("a", "b")
    if o["upright"]:
        return {first: (0, -20, 0, -1), second: (0, 20, 0, 1)}
    return {first: (-20, 0, -1, 0), second: (20, 0, 1, 0)}


def body(dev, o):
    """(x0, y0, x1, y1): the closed box the symbol covers, as offsets from its origin."""
    if dev.kind == "t":
        if o["upright"]:
            return (-20, -20, 10, 20) if o["gate"] == "left" else (-10, -20, 20, 20)
        return (-20, -20, 20, 0) if o["gate"] == "up" else (-20, 0, 20, 20)
    if dev.kind == "blk":
        hw, hh = block_size(dev)
        return (-hw, -hh, hw, hh)
    return (-10, -20, 10, 20) if o["upright"] else (-20, -10, 20, 10)


def _side(dx, dy):
    if dx == 0 and dy == 0:
        return None
    if abs(dx) >= abs(dy):
        return "right" if dx > 0 else "left"
    return "down" if dy > 0 else "up"


def stamp(schema, c, placement):
    """Write `placement` {device name: (x, y, o)} into the schema's devices, in place.
    Pins take page coordinates; gate_side and source_dir are read off them the way the
    corpus's converter reads a hand drawing."""
    names = {"d": "D", "g": "G", "s": "S"}
    for d, v in zip(schema["devices"], c.devs):
        x, y, o = placement[v.name]
        assert x % GRID == 0 and y % GRID == 0, (v.name, x, y)
        at = {p: (x + dx, y + dy) for p, (dx, dy, ex, ey) in pins(v, o).items()}
        if v.kind == "t":
            keys = names if d["type"] not in ("npn", "pnp") else {"d": "C", "g": "B", "s": "E"}
            d["terminals"] = {keys[p]: list(at[p]) for p in ("d", "g", "s")}
            if "B" in d["nets"] and d["type"] not in ("npn", "pnp"):
                d["terminals"]["B"] = [x, y]
            g, dr, sr = at["g"], at["d"], at["s"]
            d["gate_side"] = _side(g[0] - (dr[0] + sr[0]) / 2.0, g[1] - (dr[1] + sr[1]) / 2.0)
            d["source_dir"] = _side(sr[0] - dr[0], sr[1] - dr[1])
        elif v.kind == "blk":
            d["terminals"] = {k: list(at[k.lower()]) for k in d["nets"]}
        else:
            ka, kb = list(d["nets"])[:2]
            d["terminals"] = {ka: list(at["a"]), kb: list(at["b"])}
        d["x"], d["y"] = x, y
        d["orient"] = dict(o)
    return schema
