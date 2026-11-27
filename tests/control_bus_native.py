"""Exercise the opt-in renderer and reverse its presentation against the original drawing."""

import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CASE = ROOT / "external/examples/analoggenie/ag-1146.cir"


def main(cli, out):
    out.mkdir(parents=True, exist_ok=True)
    raw = CASE.read_text()
    for name, text, expected in (
        ("original", raw, True),
        ("extra", raw.replace(".ends dut", "Rextra B_2_ Vcn 1k\n.ends dut"), False),
        (
            "permuted",
            raw.replace("X2 Von Vop B_3_ B_2_", "X2 Von Vop B_2_ B_3_"),
            False,
        ),
        ("called", raw + "Xtop dd ss cm n p a b c3 c2 c1 c0 dut\n", False),
        (
            "directed",
            raw.replace(
                ".ends Varactor_Switched_caps",
                "*@ right B_2_\n.ends Varactor_Switched_caps",
            ),
            False,
        ),
        ("caller", raw.replace(".ends dut", "*@ label B_2_\n.ends dut"), False),
        (
            "invalid",
            raw.replace(".ends dut", "*@ port B_2_ unknown-side\n.ends dut"),
            True,
        ),
    ):
        path = out / (name + ".cir")
        path.write_text(text)
        ordinary = json.loads(
            subprocess.check_output(
                [cli, "--svg", out / (name + "-ordinary.svg"), path]
            )
        )
        grouped = json.loads(
            subprocess.check_output(
                [cli, "--bundles", "--svg", out / (name + "-grouped.svg"), path]
            )
        )
        annotations = grouped.pop("port_bundles")
        assert ordinary == grouped and len(annotations) == (1 if expected else 0), name
        before, after = [
            (out / (name + suffix)).read_text()
            for suffix in ("-ordinary.svg", "-grouped.svg")
        ]
        if not expected:
            assert before == after, name
            continue
        (bundle,) = annotations
        dev = next(d for d in grouped["devices"] if d["name"] == "x2")
        assert (bundle["device"], bundle["label"], bundle["contact"]) == (
            "x2",
            "B<3:0>",
            dev["pins"][2]["xy"],
        )
        for i, atom in enumerate(bundle["atoms"], 2):
            pin = dev["pins"][i]
            assert atom == {"slot": i, **pin} and pin["term"] == f"b_{5 - i}_", atom
        assert len(bundle["atoms"]) == 4
        assert ">B&lt;3:0&gt;<" in after and all(
            f">b_{i}_<" not in after for i in range(4)
        )
        assert all(f">b_{i}_<" in before for i in range(4))
        assert before.count("<polyline ") > after.count("<polyline ")
        print(name, bundle, flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ("cli", "out"):
        p.add_argument(arg, type=lambda s: Path(s).resolve())
    args = p.parse_args()
    main(args.cli, args.out)
