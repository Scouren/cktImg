"""The deck reader. Oracle: hand-written decks whose devices and nets are known."""
import unittest
from cktintent.netlist import read_netlist


class Netlist(unittest.TestCase):
    def test_cards_models_and_continuation(self):
        schema, statements, notes = read_netlist(
            ".model pch pmos\n*@ match m1 m2\nM1 d g s\n+ b pch w=1\nM2 d2 g2 s b nfet\nR1 a b 1k ; load\nQ1 c bb e qp\n.model qp pnp\n")
        kinds = {d["name"]: d["type"] for d in schema["devices"]}
        self.assertEqual(kinds, {"M1": "pmos", "M2": "nmos", "R1": "resistor", "Q1": "pnp"})
        self.assertEqual(schema["devices"][0]["nets"], {"D": "d", "G": "g", "S": "s", "B": "b"})
        self.assertEqual(statements, "match m1 m2")
        self.assertEqual(notes, [])

    def test_the_last_cell_is_drawn_and_an_instance_is_one_block(self):
        schema, _, notes = read_netlist(
            ".subckt amp inp inn out vdd\nM1 out inp inn 0 nch\n.ends\n.subckt top a b y vdd\nX1 a b y vdd amp\nR1 y b 1k\n.ends\n")
        self.assertEqual([d["name"] for d in schema["devices"]], ["X1", "R1"])
        self.assertEqual(schema["devices"][0]["type"], "opamp")
        self.assertEqual(schema["devices"][0]["nets"], {"inp": "a", "inn": "b", "out": "y", "vdd": "vdd"})
        self.assertEqual(schema["ports"], ["a", "b", "y", "vdd"])

    def test_what_is_not_a_card_is_reported_not_guessed(self):
        schema, _, notes = read_netlist("Miller OTA\nR1 a b 1k\nZ9 a b\nM3 a b\n")
        self.assertEqual([d["name"] for d in schema["devices"]], ["R1"])
        self.assertEqual(len(notes), 3)


if __name__ == "__main__":
    unittest.main()
