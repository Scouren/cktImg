"""Geometry measures on a `Ckt` (symbol units, y down)."""
from .circuit import same


def col(v):
    """The x of the column a device's branch runs in (a transistor's channel, a part's first pin)."""
    if v.kind == "t":
        return v.pins["d"][0] if v.vertical else v.x
    if v.kind == "blk":
        return v.x
    return v.pins["a"][0] if v.vertical else v.x


def row(v):
    """The y of the row a device stands in: its centre."""
    return v.y


def gate_dir(a, b):
    """How two upright transistors' gates look at each other: inward, outward, same, or None."""
    if a.gate_side not in ("left", "right") or b.gate_side not in ("left", "right"):
        return None
    l, r = (a, b) if col(a) <= col(b) else (b, a)
    if l.gate_side == "right" and r.gate_side == "left":
        return "inward"
    if l.gate_side == "left" and r.gate_side == "right":
        return "outward"
    return "same"
