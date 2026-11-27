#!/usr/bin/env python3
"""Gallery label-count oracles: literal known, missing, and mixed bindings."""

import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location(
    "gallery_site", Path(__file__).resolve().parents[1] / "tools/site/build.py")
SITE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SITE)


def drawing(labels):
    return {"devices": [], "markers": [], "wires": [], "unit": 40,
            "labels": [{"net": net} for net in labels]}


class LabelMetrics(unittest.TestCase):
    def test_unresolved_annotations_are_unknown(self):
        """Oracle: 34 unidentified annotations do not identify one named net."""
        self.assertIsNone(SITE.human_metrics(drawing([None] * 34))["names"])

    def test_mixed_bindings_are_not_a_complete_count(self):
        """Oracle: a partial annotation mapping cannot determine the total."""
        self.assertIsNone(SITE.human_metrics(drawing(["a", None, "a"]))["names"])

    def test_known_labels_count_distinct_nets(self):
        """Oracle: literal labels a,a,b identify exactly two nets."""
        self.assertEqual(SITE.human_metrics(drawing(["a", "a", "b"]))["names"], 2)

    def test_no_label_records_count_zero(self):
        """Oracle: the empty annotation set contains zero labelled nets."""
        self.assertEqual(SITE.human_metrics(drawing([]))["names"], 0)

    def test_table_distinguishes_unknown_from_zero(self):
        """Oracle: missing evidence is shown as unknown, not a numeral."""
        metrics = {"crossings": 2, "corners": 13, "wire_len": 53.2, "names": None}
        native = dict(metrics, names=4)
        table = SITE.metrics_table(metrics, native)
        self.assertIn("<td>nets with wire labels</td><td>unknown</td><td>4</td>", table)
        self.assertIn("<td>crossings</td><td>2</td><td>2</td>", table)


if __name__ == "__main__":
    unittest.main()
