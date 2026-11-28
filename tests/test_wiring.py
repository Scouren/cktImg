"""The wiring defaults W1 to W3: how a net is drawn when no statement says.

Oracle: the convention itself, as counted on the hand-drawn corpus (see `route`'s header and
the README), checked through `net_pieces`: how many wired pieces carry a net's pins, read
back from the finished geometry by `gates.pieces`, which shares no code with the router.
Every drawing here must also pass the LVS gate: pieces joined by name are still one net.
"""
import os, unittest
from cktintent import draw

RAILS = """* %d resistors from one supply to ground
.subckt bank vdd gnd
%s
.ends
"""


def deck(name):
    with open(os.path.join(os.path.dirname(__file__), "decks", name + ".sp")) as f:
        return f.read()


def bank(n):
    return RAILS % (n, "\n".join("R%d vdd gnd 1k" % i for i in range(1, n + 1)))


class Wiring(unittest.TestCase):
    def test_ground_is_a_symbol_at_each_pin(self):
        r = draw(bank(3))
        self.assertEqual(r.findings, [])
        self.assertEqual(r.schema["net_pieces"]["gnd"], 3)
        self.assertEqual(sum(m["kind"] == "ground" for m in r.schema["markers"]), 3)

    def test_a_supply_of_up_to_four_pins_is_one_bar(self):
        for n in (2, 3, 4):
            with self.subTest(pins=n):
                r = draw(bank(n))
                self.assertEqual(r.findings, [])
                self.assertEqual(r.schema["net_pieces"]["vdd"], 1)
                self.assertEqual(sum(m["kind"] == "supply" for m in r.schema["markers"]), 1)

    def test_a_supply_of_five_pins_is_a_symbol_at_each(self):
        r = draw(bank(5))
        self.assertEqual(r.findings, [])
        self.assertEqual(r.schema["net_pieces"]["vdd"], 5)

    def test_a_net_that_spans_the_drawing_is_joined_by_name(self):
        r = draw(deck("miller"))                      # the bias line runs under both stages
        self.assertEqual(r.findings, [])
        self.assertGreater(r.schema["net_pieces"]["vb"], 1)
        self.assertEqual(r.schema["net_pieces"]["n1"], 1)   # the mirror's gate line is short: one wire

    def test_a_declared_signal_is_one_wire_however_far_it_spans(self):
        r = draw(deck("miller"), "net vb : signal")
        self.assertEqual(r.findings, [])
        self.assertEqual(r.schema["net_pieces"]["vb"], 1)


if __name__ == "__main__":
    unittest.main()
