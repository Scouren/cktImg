"""The drawing has the shape people give these circuits.

Oracle: spec examples. Each fact below is read off the textbook drawing of the circuit (a
cross-coupled pair swaps its two gate wires as an X; a latch is symmetric about one axis) and
is checked on the drawing itself, never on what the placer meant to do.
"""
import os, unittest
from cktintent import draw


def deck(name):
    with open(os.path.join(os.path.dirname(__file__), "decks", name + ".sp")) as f:
        return f.read()


def diagonals(schema):
    return [(w["net"], a, b) for w in schema["wires"] for a, b in w["segments"] if a[0] != b[0] and a[1] != b[1]]


def drain_x(schema):
    return {d["name"]: d["terminals"]["D"][0] for d in schema["devices"] if "D" in d["terminals"]}


class Shape(unittest.TestCase):
    def test_a_cross_coupled_pair_swaps_its_gate_wires_as_an_x(self):
        r = draw(deck("lcvco"))
        self.assertEqual(sorted(n for n, a, b in diagonals(r.schema)), ["outn", "outp"])
        self.assertEqual(r.schema["net_pieces"]["outn"], 1)
        self.assertEqual(r.schema["net_pieces"]["outp"], 1)

    def test_a_latch_of_two_inverters_draws_two_xs_about_one_axis(self):
        r = draw(deck("strongarm"))
        self.assertEqual(sorted(n for n, a, b in diagonals(r.schema)), ["outn", "outn", "outp", "outp"])
        x = drain_x(r.schema)
        axes = {x[a] + x[b] for a, b in (("M1", "M2"), ("M3", "M4"), ("M5", "M6"), ("M7", "M8"))}
        self.assertEqual(len(axes), 1, x)
        self.assertEqual(x["M0"] * 2, axes.pop())
        self.assertEqual([r.schema["net_pieces"][n] for n in ("outn", "outp")], [1, 1])
        self.assertTrue(all(shown is not False for rule, shown, text in r.outcome))

    def test_a_crossing_made_by_an_x_is_counted(self):
        self.assertEqual(draw(deck("lcvco")).schema["crossings"], 1)

    def test_two_cross_pairs_on_the_same_nodes_stay_one_net(self):
        r = draw(deck("latch"))                       # each pair draws its own X: the two must still be joined
        self.assertEqual(r.findings, [])

    def test_miller_compensation_lies_in_a_row_between_the_two_stages(self):
        r = draw(deck("miller"))                      # textbook: first-stage output, Cc, Rz, second-stage output
        d = {v["name"]: v for v in r.schema["devices"]}
        self.assertFalse(d["Cc"]["orient"]["upright"] or d["Rz"]["orient"]["upright"])
        self.assertEqual(d["Cc"]["y"], d["Rz"]["y"])
        x = drain_x(r.schema)
        self.assertLess(x["M4"], d["Cc"]["x"])
        self.assertLess(d["Cc"]["x"], d["Rz"]["x"])
        self.assertLess(d["Rz"]["x"], x["M6"])
        self.assertEqual(d["Rz"]["y"], d["M6"]["terminals"]["D"][1] + 20)   # level with the output node

    def test_a_diode_connected_reference_faces_the_gates_it_feeds(self):
        d = {v["name"]: v for v in draw(deck("miller")).schema["devices"]}
        self.assertEqual((d["M8"]["gate_side"], d["M5"]["gate_side"], d["M7"]["gate_side"]), ("right", "left", "left"))

    def test_with_no_statement_a_lead_part_stands_where_the_deck_names_it(self):
        r = draw(deck("csamp"))                       # source, coupling capacitor, bias divider, transistor
        d = {v["name"]: v["x"] for v in r.schema["devices"]}
        self.assertLess(d["Vs"], d["Cin"])
        self.assertLess(d["Cin"], d["Rb1"])
        self.assertLess(d["Rb1"], d["M1"])
        self.assertEqual(r.schema["crossings"], 0)


if __name__ == "__main__":
    unittest.main()
