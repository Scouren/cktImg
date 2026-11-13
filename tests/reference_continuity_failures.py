#!/usr/bin/env python3
"""Check known manual source-continuity failures by exact name and assertion.

Success means the recorded failures recurred, not that source continuity passed.
A repaired case must leave this marker set and enter the ordinary positive gate.
This tool reads a saved Zig log; it never runs Zig or changes test expectations.
"""
import argparse
import re
from pathlib import Path

EXPECTED = [
    "reference continuity: AG2415 keeps the source VIN branch wire",
    "reference continuity: AG2428 keeps the source VIN branch wire",
]


def observed(log, exit_code):
    if exit_code != 1:
        raise ValueError("known failing run must exit 1; a pass or other failure needs review")
    starts = list(re.finditer(r"^\d+/\d+ \S*\.test\.(.*?)\.\.\.", log, re.M))
    names = [m[1] for m in starts]
    if names != EXPECTED:
        raise ValueError("exact manual test-name inventory changed: " + repr(names))
    for i, match in enumerate(starts):
        body = log[match.end():starts[i + 1].start() if i + 1 < len(starts) else len(log)]
        if not re.search(r"(?:^|\n)FAIL \(TestUnexpectedResult\)", body):
            raise ValueError(match[1] + ": expected physical-continuity failure did not recur")
        if "try testing.expect(try ink.connected(" not in body:
            raise ValueError(match[1] + ": failed outside the physical-wire oracle")
    return names


def checks():
    literal = "".join(str(i + 1) + "/2 reference_continuity.test." + name +
                      "...diagnostic\nFAIL (TestUnexpectedResult)\n" +
                      "try testing.expect(try ink.connected(gpa, &p, &pins));\n"
                      for i, name in enumerate(EXPECTED))
    assert observed(literal, 1) == EXPECTED
    mutations = {
        "unexpected_pass": (literal.replace("FAIL (TestUnexpectedResult)", "OK", 1), 1),
        "wrong_test_name": (literal.replace("AG2415", "AG0000", 1), 1),
        "missing_test": (literal[:literal.index("2/2")], 1),
        "different_failure": (literal.replace("TestUnexpectedResult", "OutOfMemory", 1), 1),
        "electrical_failure": (literal.replace("try testing.expect(try ink.connected(", "try support.expectConnected(", 1), 1),
        "successful_exit": (literal, 0),
    }
    for name, (log, status) in mutations.items():
        try:
            observed(log, status)
        except ValueError:
            continue
        raise AssertionError("mutation accepted: " + name)
    return ["literal_two_physical_failures", *mutations]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("log", type=Path)
    p.add_argument("--exit-code", type=int, required=True)
    a = p.parse_args()
    methods = checks()
    names = observed(a.log.read_text(), a.exit_code)
    print("Known failures reproduced; source preservation remains failing:")
    print("\n".join(names))
    print("Named parser checks: " + ", ".join(methods))


if __name__ == "__main__":
    main()
