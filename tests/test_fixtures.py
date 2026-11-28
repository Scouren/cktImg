"""Every fixture deck draws, and the drawing is legal, repeatable and name-independent.

Oracles: the gates (`gates.check`: nets read back from geometry equal the deck's nets, no
symbol overlap, no wire in a symbol), which share no code with the placer or the router;
byte equality of two runs; and a metamorphic relation: renaming a net changes no position.
"""
import glob, os, re, unittest
from cktintent import draw, render_svg

DECKS = sorted(glob.glob(os.path.join(os.path.dirname(__file__), "decks", "*.sp")))


def read(path):
    with open(path) as f:
        return f.read()


class Fixtures(unittest.TestCase):
    def test_there_are_fixtures(self):
        self.assertGreaterEqual(len(DECKS), 12)

    def test_each_drawing_is_legal(self):
        for path in DECKS:
            with self.subTest(deck=os.path.basename(path)):
                r = draw(read(path))
                self.assertEqual(r.findings, [])
                self.assertEqual(len(r.schema["devices"]), len(r.circuit.devs))

    def test_two_runs_give_the_same_bytes(self):
        for path in DECKS:
            with self.subTest(deck=os.path.basename(path)):
                text = read(path)
                a, b = draw(text), draw(text)
                self.assertEqual(render_svg(a.schema, a.circuit), render_svg(b.schema, b.circuit))

    def test_renaming_an_inner_net_moves_nothing(self):
        text = read(os.path.join(os.path.dirname(__file__), "decks", "ota5.sp"))
        a = draw(text)
        b = draw(re.sub(r"\btail\b", "tail_node", text))
        place = lambda r: [(d["name"], d["x"], d["y"], sorted(d["terminals"].items())) for d in r.schema["devices"]]
        self.assertEqual(place(a), place(b))


if __name__ == "__main__":
    unittest.main()
