"""The gallery: what the tool draws for every fixture deck, kept in the tree as a golden.

usage: python3 tools/gallery.py            write docs/gallery/<deck>.svg for tests/decks/*.sp
       python3 tools/gallery.py --check    exit 1, naming the decks, when a kept drawing differs

Provenance of the golden: these bytes are this tool's own output, kept so that a change to
what it draws shows up in review as a changed picture. They prove nothing about quality:
the gates and the contract do that. After a change you mean, run this and commit the result.
"""
import glob, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from cktintent import draw, render_svg


def drawings():
    """{deck name: SVG text} for every fixture deck, as drawn now."""
    out = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "tests", "decks", "*.sp"))):
        with open(path) as f:
            r = draw(f.read())
        out[os.path.basename(path)[:-3]] = render_svg(r.schema, r.circuit)
    return out


def main(argv):
    """Write the gallery, or with --check compare it. -> the exit status."""
    folder = os.path.join(ROOT, "docs", "gallery")
    stale = []
    for name, svg in drawings().items():
        path = os.path.join(folder, name + ".svg")
        if "--check" in argv:
            kept = None
            if os.path.exists(path):
                with open(path) as f:
                    kept = f.read()
            if kept != svg:
                stale.append(name)
        else:
            os.makedirs(folder, exist_ok=True)
            with open(path, "w") as f:
                f.write(svg)
    extra = sorted(set(os.path.basename(p)[:-4] for p in glob.glob(os.path.join(folder, "*.svg"))) - set(drawings()))
    if stale or extra:
        print("gallery differs from what the tool draws now: %s\nrun: python3 tools/gallery.py" % " ".join(stale + extra))
    return 1 if stale or extra else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
