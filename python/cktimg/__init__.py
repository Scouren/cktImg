"""cktImg from Python: place and draw a SPICE netlist as a schematic.

    import cktimg
    placement, report = cktimg.place(deck, symbols="set.zon", target=manifest, start=previous)
    svg, report = cktimg.draw(deck, start=previous)

`deck` is netlist text, or any object with a `netlist("cktimg")` method (a
`sprack.Circuit`), so this package imports nothing of SPRack's. Hints are
the deck's own `*@` lines.

Every input that is a file can also be given in memory:

- `symbols`: a symbol set, as a path or `.zon` text (`--symbols`).
- `target`: a target manifest, as a path, JSON text or a dict (`--target`).
- `config`: a `lint.zon`, as a path or text (`--config`).
- `start`: an earlier placement, as a path, JSON text or the dict `place`
  returned (`--from`). Devices stay where it has them.

The placement is the JSON document cktImg writes, and `docs/PYTHON.md`
documents it. The report is the decision report: `requests` holds each
`*@` line's verdict.

This version runs the `cktimg-json` command line in a temporary directory.
Which binary runs: the `exe` argument, else `$CKTIMG_JSON`, else
`cktimg-json` on `PATH`.
"""
import json
import os
import shutil
import subprocess
import tempfile

__all__ = ["place", "draw", "CktimgError"]


class CktimgError(RuntimeError):
    """The command refused the deck, symbols, manifest or config, or could not run.

    The message is cktImg's own diagnostic."""


def place(deck, *, symbols=None, target=None, start=None, config=None, exe=None):
    """The deck laid out: `(placement, report)`, both dicts."""
    out = _run(deck, symbols, target, start, config, exe, svg=False)
    return out["placement"], out["report"]


def draw(deck, *, symbols=None, target=None, start=None, config=None, exe=None):
    """The deck drawn: `(svg, report)`, the SVG as text."""
    out = _run(deck, symbols, target, start, config, exe, svg=True)
    return out["svg"], out["report"]


def _run(deck, symbols, target, start, config, exe, svg):
    binary = exe or os.environ.get("CKTIMG_JSON") or shutil.which("cktimg-json")
    if not binary:
        raise CktimgError("cktimg-json not found: pass exe=, set $CKTIMG_JSON, or put it on PATH")
    text = deck.netlist("cktimg") if hasattr(deck, "netlist") else deck
    if not isinstance(text, str):
        raise TypeError("deck must be netlist text or have a netlist('cktimg') method")
    with tempfile.TemporaryDirectory(prefix="cktimg-") as d:
        def put(name, value):
            path = os.path.join(d, name)
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(value)
            return path

        argv = [binary]
        for flag, value, name in (("--symbols", symbols, "set.zon"), ("--config", config, "lint.zon"),
                                  ("--target", target, "manifest.json"), ("--from", start, "start.json")):
            if value is not None:
                argv += [flag, _file(value, name, put)]
        report, placement = os.path.join(d, "r.json"), os.path.join(d, "d.json")
        argv += ["--report", report]
        if svg:
            argv += ["--svg", os.path.join(d, "d.svg")]
        argv += [put("deck.sp", text), placement]
        done = subprocess.run(argv, capture_output=True, text=True)
        if done.returncode != 0:
            raise CktimgError(done.stderr.strip() or f"{binary} exited {done.returncode}")
        out = {"report": _load(report), "placement": _load(placement)}
        if svg:
            with open(os.path.join(d, "d.svg"), encoding="utf-8") as f:
                out["svg"] = f.read()
        return out


def _file(value, name, put):
    """A path for `value`: itself when it names a file, else a temp file of its text."""
    if isinstance(value, os.PathLike):
        return os.fspath(value)
    if isinstance(value, dict):
        return put(name, json.dumps(value))
    # ponytail: a one-line string naming an existing file is a path; anything else is content.
    if isinstance(value, str) and "\n" not in value and os.path.isfile(value):
        return value
    return put(name, value)


def _load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)
