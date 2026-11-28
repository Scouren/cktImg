"""cktintent: draw a SPICE netlist from four statements of intent.

    from cktintent import draw, render_svg, read_back
    r = draw(deck_text, statements_text)
    svg = render_svg(r.schema, r.circuit)
    print(read_back(r))
"""
from .draw import draw, Result
from .render import render_svg
from .report import read_back

__all__ = ["draw", "Result", "render_svg", "read_back"]
