"""The command line, the read-back and the house rules.

Oracles: the exit status the usage text promises (0 legal, 2 bad input); two processes with
different hash seeds give the same bytes (determinism that a single process cannot show,
since Python's set order changes between processes); `tools/check.py` finds nothing.
"""
import glob, json, os, subprocess, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DECKS = sorted(glob.glob(os.path.join(ROOT, "tests", "decks", "*.sp")))


def run(args, seed="0"):
    env = dict(os.environ, PYTHONHASHSEED=seed, PYTHONPATH=ROOT)
    return subprocess.run([sys.executable, "-m", "cktintent"] + args, env=env, cwd=ROOT, capture_output=True, text=True)


class CommandLine(unittest.TestCase):
    def test_a_legal_drawing_exits_0_and_writes_what_was_asked(self):
        with tempfile.TemporaryDirectory() as d:
            svg, js = os.path.join(d, "o.svg"), os.path.join(d, "o.json")
            p = run([os.path.join(ROOT, "tests", "decks", "ota5.sp"), "-o", svg, "--json", js])
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("outcome: 27 of 27 relations shown", p.stdout)
            with open(svg) as f:
                self.assertTrue(f.read().startswith("<svg"))
            with open(js) as f:
                self.assertEqual(len(json.load(f)["devices"]), 7)      # the deck's seven cards

    def test_bad_input_exits_2(self):
        with tempfile.TemporaryDirectory() as d:
            empty = os.path.join(d, "empty.sp")
            with open(empty, "w") as f:
                f.write("* nothing here\n")
            self.assertEqual(run([empty]).returncode, 2)
            self.assertEqual(run([os.path.join(d, "missing.sp")]).returncode, 2)
            self.assertEqual(run([]).returncode, 2)

    def test_a_line_that_cannot_be_kept_is_said_not_dropped(self):
        with tempfile.TemporaryDirectory() as d:
            ctl = os.path.join(d, "x.ctl")
            with open(ctl, "w") as f:
                f.write("match m1 m99\nnet nosuch : bias\nflop a -> b\n")
            out = run([os.path.join(ROOT, "tests", "decks", "ota5.sp"), ctl]).stdout
            for word in ("m99", "nosuch", "flop"):
                self.assertIn(word, out)

    def test_two_hash_seeds_give_the_same_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            for path in DECKS:
                with self.subTest(deck=os.path.basename(path)):
                    outs = []
                    for seed in ("1", "2"):
                        svg = os.path.join(d, seed + ".svg")
                        run([path, "-q", "-o", svg], seed)
                        with open(svg, "rb") as f:
                            outs.append(f.read())
                    self.assertEqual(outs[0], outs[1])


class HouseRules(unittest.TestCase):
    def test_the_source_passes_the_checker(self):
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "check.py")], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout)


if __name__ == "__main__":
    unittest.main()
