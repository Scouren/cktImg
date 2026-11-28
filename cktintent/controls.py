"""The four statements: text in, a `Controls` table out.

    net <nets> : supply | ground | bias | clock | signal
    stage <name> : <devices>
    match <a> <b> [<c> ...]        devices, or stages
    flow <e> -> <e> -> ...         e = one or more devices or stages; the two ends may be nets

One statement per line, `#` starts a comment, names as in the deck, case-insensitive. A line
may also carry the `*@` prefix a SPICE deck needs to hide it from a simulator.
"""
import collections

ROLES = ("supply", "ground", "bias", "clock", "signal")


class Controls:
    """The statements as tables. roles: {net: role}; stages: {name: [device names]} in the
    order stated; matches: [[names]]; flows: [[[names] per element]]; errors: sentences for
    the lines that could not be read. Names are lower case; `labels` keeps each stage's name
    as written, for the box drawn round it."""

    def __init__(self):
        self.roles, self.stages, self.matches, self.flows, self.errors = {}, collections.OrderedDict(), [], [], []
        self.labels = {}                               # stage name -> the name as the user wrote it


def parse(text):
    """Read statements from `text`. Never raises: a line it cannot read becomes an entry in `errors`."""
    k = Controls()
    for raw in text.splitlines():
        line = raw.split("#", 1)[0].strip().lower()
        if line.startswith("*@"):
            line = line[2:].strip()
        if not line:
            continue
        verb, _, rest = line.partition(" ")
        rest = rest.strip()
        if verb == "net":
            toks = rest.replace(":", " ").replace(",", " ").split()
            if len(toks) < 2 or toks[-1] not in ROLES:
                k.errors.append("refused `%s`: a net line ends with one of %s" % (raw.strip(), ", ".join(ROLES)))
                continue
            for n in toks[:-1]:
                k.roles[n] = toks[-1]
        elif verb == "stage":
            toks = rest.replace(":", " ").replace(",", " ").split()
            if len(toks) < 2:
                k.errors.append("refused `%s`: a stage needs a name and its devices" % raw.strip())
                continue
            k.stages[toks[0]] = toks[1:]
            written = raw.split("#", 1)[0].replace("*@", " ", 1).replace(":", " ").split()
            k.labels[toks[0]] = written[1] if len(written) > 1 and written[1].lower() == toks[0] else toks[0]
        elif verb == "match":
            toks = rest.replace(",", " ").replace(":", " ").split()
            if len(toks) < 2:
                k.errors.append("refused `%s`: match needs two names or more" % raw.strip())
                continue
            k.matches.append(toks)
        elif verb == "flow":
            chain = [e.replace(",", " ").split() for e in rest.split("->")]
            if len(chain) < 2 or any(not e for e in chain):
                k.errors.append("refused `%s`: flow needs a -> b" % raw.strip())
                continue
            k.flows.append(chain)
        else:
            k.errors.append("refused `%s`: unknown statement" % raw.strip())
    return k
