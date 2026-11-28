"""usage: python3 -m cktintent deck.sp [statements.ctl] [-o out.svg] [--json out.json] [-q]

Draws the deck. Statements come from `*@` lines in the deck and from the optional file.
Prints the read-back. Exit status: 0 legal drawing, 1 the drawing breaks a gate, 2 bad input."""
import json, sys
from . import draw, render_svg, read_back


def main(argv):
    """Run the command line on `argv` (without the program name). -> the exit status."""
    args, out, js, quiet = [], None, None, False
    it = iter(argv)
    for a in it:
        if a == "-o":
            out = next(it, None)
        elif a == "--json":
            js = next(it, None)
        elif a == "-q":
            quiet = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            args.append(a)
    if not 1 <= len(args) <= 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        texts = []
        for path in args:
            with open(path) as f:
                texts.append(f.read())
        r = draw(texts[0], texts[1] if len(texts) == 2 else "")
    except (OSError, ValueError) as e:
        print("cktintent: %s" % e, file=sys.stderr)
        return 2
    svg = render_svg(r.schema, r.circuit)
    if out:
        with open(out, "w") as f:
            f.write(svg)
    if js:
        with open(js, "w") as f:
            json.dump(r.schema, f, indent=1)
    if not quiet:
        sys.stdout.write(read_back(r))
    return 1 if r.findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
