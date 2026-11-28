"""What comes back to the agent, in circuit terms: verdicts, the read-back, the outcome."""
import collections


def read_back(result):
    """-> text: refused or adjusted lines, every relation the statements produced, then what
    the drawing does not show and what is illegal in it."""
    out = []
    lines = [l.strip() for l in result.statements.splitlines() if l.strip() and not l.strip().startswith("#")]
    out.append("%d devices, %d statement lines" % (len(result.schema["devices"]), len(lines)))
    for n in result.notes:
        out.append("  note      %s" % n)
    for n, role in sorted(result.contract.view.k.roles.items()):
        if n in result.circuit.net_pins:                  # a role for a net the deck does not have is a note above
            out.append("  N    net %s is %s" % (n, "a bias line" if role == "bias" else "a " + role))
    for rule, shown, text in result.outcome:
        if rule[0] in "MSFN" or rule in ("B1s", "B4", "B5"):
            out.append("  %-4s %s%s" % (rule, text, "" if shown is not False else "   [NOT SHOWN]"))
    missed = [(r, t) for r, s, t in result.outcome if s is False]
    tally = collections.Counter(r for r, s, t in result.outcome if s is not None)
    out.append("outcome: %d of %d relations shown" % (sum(tally.values()) - len(missed), sum(tally.values())))
    for r, t in missed:
        if r[0] == "B" and r not in ("B1s", "B4", "B5"):
            out.append("  %-4s %s   [NOT SHOWN]" % (r, t))
    named = sorted(n for n, k in result.schema["net_pieces"].items() if k > 1)
    if named:
        out.append("drawn by name or symbol: %s" % " ".join(named))
    if result.schema.get("boxes"):
        out.append("in a box of its own: %s" % " ".join(b["name"] for b in result.schema["boxes"]))
    out.append("wire crossings: %d, corners: %d" % (result.schema.get("crossings", 0), result.schema.get("bends", 0)))
    for gate, text in result.findings:
        out.append("ILLEGAL %-8s %s" % (gate, text))
    return "\n".join(out) + "\n"
