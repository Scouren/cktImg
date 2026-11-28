"""Each gate catches the violation it is named for, and passes the clean drawing.

Oracle: seeded violations. A legal drawing is damaged in one known way; the gate must report
that damage and only that kind.
"""
import copy, os, unittest
from cktintent import draw, gates
from cktintent.circuit import Ckt

with open(os.path.join(os.path.dirname(__file__), "decks", "ota5.sp")) as _f:
    DECK = _f.read()


class Gates(unittest.TestCase):
    def setUp(self):
        self.clean = draw(DECK).schema

    def kinds(self, schema):
        return sorted({g for g, text in gates.check(schema, Ckt(schema))})

    def test_clean_drawing_passes(self):
        self.assertEqual(self.kinds(self.clean), [])

    def test_removing_a_wire_opens_its_net(self):
        s = copy.deepcopy(self.clean)
        wire = next(w for w in s["wires"] if w["net"] == "tail")
        s["wires"].remove(wire)
        found = gates.check(s, Ckt(s))
        self.assertEqual(sorted({g for g, t in found}), ["lvs"])
        self.assertTrue(any("open" in t and "tail" in t for g, t in found), found)

    def test_a_wire_between_two_nets_shorts_them(self):
        s = copy.deepcopy(self.clean)
        at = {(d["name"], p): xy for d in s["devices"] for p, xy in d["terminals"].items()}
        a, b = at[("M1", "G")], at[("M2", "G")]
        s["wires"].append({"net": "vinp", "segments": [[[a[0] - 10, a[1] - 100], [b[0] + 10, b[1] - 100]]]})
        s["wires"].append({"net": "vinp", "segments": [[a, [a[0] - 10, a[1]]], [[a[0] - 10, a[1]], [a[0] - 10, a[1] - 100]]]})
        s["wires"].append({"net": "vinp", "segments": [[b, [b[0] + 10, b[1]]], [[b[0] + 10, b[1]], [b[0] + 10, b[1] - 100]]]})
        found = gates.check(s, Ckt(s))
        self.assertTrue(any(g == "lvs" and "short" in t and "vinn" in t and "vinp" in t for g, t in found), found)

    def test_a_crossing_does_not_join(self):
        s = copy.deepcopy(self.clean)
        s["wires"].append({"net": "x", "segments": [[[0, 0], [2000, 0]]]})
        s["wires"].append({"net": "y", "segments": [[[1000, -500], [1000, 500]]]})
        self.assertEqual(self.kinds(s), [])

    def test_a_device_moved_onto_another_overlaps(self):
        s = copy.deepcopy(self.clean)
        m1, m2 = (next(d for d in s["devices"] if d["name"] == n) for n in ("M1", "M2"))
        dx, dy = m1["x"] - m2["x"], m1["y"] - m2["y"]
        m2["x"], m2["y"] = m1["x"], m1["y"]
        m2["terminals"] = {p: [x + dx, y + dy] for p, (x, y) in m2["terminals"].items()}
        self.assertIn("overlap", self.kinds(s))

    def test_a_wire_through_a_symbol_pierces_it(self):
        s = copy.deepcopy(self.clean)
        m5 = next(d for d in s["devices"] if d["name"] == "M5")
        s["wires"].append({"net": "loose", "segments": [[[m5["x"] - 60, m5["y"]], [m5["x"] + 60, m5["y"]]]]})
        self.assertIn("pierce", self.kinds(s))


if __name__ == "__main__":
    unittest.main()
