"""The spine: a deck and its statements in, a judged drawing out.

    result = draw(deck_text, statements_text)

Each line below is one stage; every stage is importable on its own and takes plain data.
"""
from .netlist import read_netlist
from .controls import parse
from .circuit import Ckt
from .contract import derive
from .place import place
from .symbols import stamp
from .route import route
from . import gates, judge


class Result:
    """What `draw` returns.
    schema    the drawing, in the corpus's schema (devices, wires, markers, labels), px
    circuit   `Ckt` of the finished drawing
    contract  the relations the statements and the baseline ask for, and the notes on refused lines
    notes     what the reader, the placer and the router had to adjust, as sentences
    outcome   [(rule, shown, sentence)]: does the drawing show each relation (None: cannot be judged)
    findings  [(gate, sentence)]: what makes the drawing illegal; empty for a legal drawing"""
    __slots__ = ("schema", "circuit", "contract", "notes", "outcome", "findings", "statements")


def draw(deck_text, statements_text=""):
    """Draw a SPICE deck under its statements. Raises ValueError when the deck holds no device."""
    schema, inline, notes = read_netlist(deck_text)
    if not schema["devices"]:
        raise ValueError("no device card in the deck" + ("; " + notes[0] if notes else ""))
    text = "\n".join(t for t in (inline, statements_text) if t)
    c = Ckt(schema)
    k = derive(c, parse(text))
    placement, groups, more = place(c, k)
    stamp(schema, c, placement)
    notes = notes + more + route(c, k, schema)
    schema["net_pieces"] = gates.pieces(schema)
    r = Result()
    r.schema, r.contract, r.statements = schema, k, text
    r.circuit = Ckt(schema)
    r.outcome, _ = judge.check(r.circuit, text)
    r.findings = gates.check(schema, r.circuit)
    r.notes = k.notes + notes
    return r
