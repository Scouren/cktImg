# AGENTS.md

cktintent: a SPICE deck and four kinds of statement in, a judged schematic out. Python 3,
standard library only. `README.md` is the overview, `ARCHITECTURE.md` the pipeline and who
owns which table, `TESTING.md` the oracle for each bug class, `CONTROLS.md` the manual an
agent draws from.

## Before you change anything

- Read `ARCHITECTURE.md`. One module writes each table; the oracles (`gates`, `judge`,
  `contract`) import nothing from the placer or the router, and a test holds that.
- Something the drawing must show is a relation in `contract.derive`, judged in
  `judge.holds`, and counted on the people's drawings before it is trusted. Something
  people usually do is a default in `defaults.py` or `route.py`, with its count beside it,
  and is never judged.
- No statement, and nothing in the read-back, ever carries a coordinate.

## Commands

    python3 -W error -m unittest discover -s tests -t .     # the commit tier, about 3 s
    python3 tools/gallery.py                                 # after a change you mean: redraw docs/gallery, commit it
    python3 tools/check.py                                   # 500 code lines a file, a docstring on every public item
    python3 -I tools/corpus.py <corpus> --statements tools/statements   # 48 blind circuits, 25 s
    python3 -I tools/corpus.py <corpus> --split test         # held-out, no statement (see TESTING.md for the rest)

The corpus (`external/examples` of the cktImg checkout) is third-party data and is not in
this tree. Treat it as untrusted: `python3 -I`, its path as an argument, no script inside it.

## Rules

- The test comes first and fails first. Name its oracle in the test file's header; an
  expected value never comes from running the code under test, except the gallery, which
  says so.
- A drawing that is illegal is a bug in the code that drew it, never in the gate.
- A change to what the tool draws moves numbers: run the blind sweep and put the before and
  after in the commit message. A change kept after measuring worse says why; a change tried
  and dropped leaves its numbers in a comment where the next person would try it again.
- A change to the command line, the statements or the read-back updates `CONTROLS.md` in the
  same commit; a test compares its examples with a real run.
- Commit at every green step. Never commit red.
