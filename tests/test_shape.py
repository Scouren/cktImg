"""The drawing has the shape people give these circuits.

Oracle: spec examples. Each fact below is read off the textbook drawing of the circuit (a
cross-coupled pair swaps its two gate wires as an X; a latch is symmetric about one axis) and
is checked on the drawing itself, never on what the placer meant to do.
"""
import os, unittest
from cktintent import draw


HALVES = """* two half cells that are copies of each other
*@ stage a : m1 r1 c1
*@ stage b : m2 r2 c2
*@ match a b
.model nch nmos
.subckt halves vdd vss ina inb outa outb
M1 outa ina vss vss nch
R1 vdd outa 1k
C1 outa vss 1p
M2 outb inb vss vss nch
R2 vdd outb 1k
C2 outb vss 1p
.ends
"""

LANE = """* a shunt attenuator into an inverting amplifier
*@ flow vin -> r5 -> r1 -> x1 -> vout
.subckt amp inp inn out
E1 out 0 inp inn 1e6
.ends
.subckt agc vss vin vctl vout
J1 n0 vctl vss njf
.model njf njf
R5 vin va 1k
R6 va n0 1k
R1 va n1 1k
R2 n1 vout 1k
X1 vss n1 vout amp
.ends
"""


def deck(name):
    with open(os.path.join(os.path.dirname(__file__), "decks", name + ".sp")) as f:
        return f.read()


def diagonals(schema):
    return [(w["net"], a, b) for w in schema["wires"] for a, b in w["segments"] if a[0] != b[0] and a[1] != b[1]]


def drain_x(schema):
    """{transistor: x of its branch line} (the drain's, or the collector's)."""
    return {d["name"]: (d["terminals"].get("D") or d["terminals"]["C"])[0] for d in schema["devices"]
            if "D" in d["terminals"] or "C" in d["terminals"]}


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

    def test_a_pair_stands_over_the_half_of_the_pair_that_feeds_it(self):
        r = draw(deck("gilbert"))                     # textbook Gilbert cell: quad over the input pair
        x = drain_x(r.schema)
        at = {d["name"]: d for d in r.schema["devices"]}
        self.assertEqual(x["Q1"] + x["Q2"], 2 * x["Q5"])
        self.assertEqual(x["Q3"] + x["Q4"], 2 * x["Q6"])
        self.assertEqual(x["Q5"] + x["Q6"], 2 * at["Itail"]["x"])
        self.assertEqual(x["Q1"] + x["Q4"], x["Q2"] + x["Q3"])
        self.assertEqual((at["RL1"]["x"], at["RL2"]["x"]), (x["Q1"], x["Q4"]))   # each load over an outer device
        self.assertLess(at["Q1"]["y"], at["Q5"]["y"])
        self.assertEqual(r.findings, [])

    def test_an_undeclared_cross_pair_still_gets_its_x_and_its_tail(self):
        r = draw(deck("latch"))                       # no statement at all
        self.assertEqual(sorted(n for n, a, b in diagonals(r.schema)), ["q", "q", "qb", "qb"])
        x = drain_x(r.schema)
        self.assertEqual(x["MN1"] + x["MN2"], 2 * x["MTN"])
        self.assertEqual((x["MP1"], x["MP2"]), (x["MN1"], x["MN2"]))

    def test_a_matched_stage_is_the_mirror_image_of_its_copy(self):
        r = draw(HALVES)
        self.assertEqual(r.findings, [])
        at = {d["name"]: d for d in r.schema["devices"]}
        sums = {at[a]["x"] + at[b]["x"] for a, b in (("M1", "M2"), ("R1", "R2"), ("C1", "C2"))}
        self.assertEqual(len(sums), 1, sums)
        self.assertEqual((at["M1"]["gate_side"], at["M2"]["gate_side"]), ("left", "right"))
        self.assertTrue(all(shown is not False for rule, shown, text in r.outcome), r.outcome)

    def test_a_flow_reads_left_to_right_through_its_parts(self):
        r = draw(LANE)
        self.assertEqual(r.findings, [])
        at = {d["name"]: d for d in r.schema["devices"]}
        port = {m["name"]: m["at"][0] for m in r.schema["markers"] if m["kind"] == "port"}
        self.assertLess(port["vin"], at["R5"]["x"])
        self.assertLess(at["R5"]["x"], at["R1"]["x"])
        self.assertLess(at["R1"]["x"], at["X1"]["x"])
        self.assertLess(at["X1"]["x"], port["vout"])
        self.assertLess(at["R5"]["terminals"]["1"][0], at["R5"]["terminals"]["2"][0])   # its input end looks left
        self.assertEqual([r.schema["net_pieces"][n] for n in ("va", "n1")], [1, 1])       # the path is wire
        self.assertTrue(all(shown is not False for rule, shown, text in r.outcome), r.outcome)

    def test_with_no_statement_a_lead_part_stands_where_the_deck_names_it(self):
        r = draw(deck("csamp"))                       # source, coupling capacitor, bias divider, transistor
        d = {v["name"]: v["x"] for v in r.schema["devices"]}
        self.assertLess(d["Vs"], d["Cin"])
        self.assertLess(d["Cin"], d["Rb1"])
        self.assertLess(d["Rb1"], d["M1"])
        self.assertEqual(r.schema["crossings"], 0)


if __name__ == "__main__":
    unittest.main()
