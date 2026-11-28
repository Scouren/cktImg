"""The command line, the read-back, the manual and the house rules.

Oracles: the exit status the usage text promises (0 legal, 2 bad input); two processes with
different hash seeds give the same bytes (determinism that a single process cannot show,
since Python's set order changes between processes); `tools/check.py` finds nothing; the
gallery kept in docs/gallery is byte for byte what the tool draws now (a golden: it shows a
change, it does not judge one).
"""
import ast, glob, json, os, subprocess, sys, tempfile, unittest

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
            deck = os.path.join(ROOT, "tests", "decks", "ota5.sp")
            self.assertEqual(run([deck, "-o", os.path.join(d, "no", "such", "folder.svg")]).returncode, 2)

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


class Manual(unittest.TestCase):
    """CONTROLS.md is what an agent reads: what it shows must be what the tool does."""

    def setUp(self):
        with open(os.path.join(ROOT, "CONTROLS.md")) as f:
            self.manual = f.read()

    def block_after(self, marker):
        lines = self.manual[self.manual.index(marker):].splitlines()[1:]
        start = next(i for i, l in enumerate(lines) if l.startswith("    "))
        end = next(i for i in range(start, len(lines)) if lines[i].strip() and not lines[i].startswith("    "))
        return "\n".join(l[4:] for l in lines[start:end]).strip() + "\n"

    def test_the_read_back_it_shows_is_the_read_back_the_tool_prints(self):
        with tempfile.TemporaryDirectory() as d:
            ctl = os.path.join(d, "x.ctl")
            with open(ctl, "w") as f:
                f.write("flow vout -> in\n")
            out = run([os.path.join(ROOT, "tests", "decks", "miller.sp"), ctl]).stdout
        self.assertEqual(self.block_after("with one line too many"), out)

    def test_its_op_amp_example_is_the_fixture_s_statements(self):
        with open(os.path.join(ROOT, "tests", "decks", "miller.sp")) as f:
            inline = [" ".join(l[2:].split()) for l in f if l.startswith("*@")]
        shown = [" ".join(l.split()) for l in self.block_after("Two-stage op-amp").splitlines()]
        self.assertEqual(shown, inline)


class Readme(unittest.TestCase):
    def test_the_deck_it_shows_is_the_fixture_and_the_read_back_lines_are_real(self):
        with open(os.path.join(ROOT, "README.md")) as f:
            readme = f.read()
        with open(os.path.join(ROOT, "tests", "decks", "miller.sp")) as f:
            self.assertEqual(readme.split("```spice\n")[1].split("```")[0], f.read())
        out = run([os.path.join(ROOT, "tests", "decks", "miller.sp")]).stdout
        shown = readme.split("## What comes back")[1].split("\n\n")[1]
        self.assertEqual([l.strip() for l in shown.splitlines()], out.splitlines()[-4:])


class HouseRules(unittest.TestCase):
    def test_the_source_passes_the_checker(self):
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "check.py")], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout)

    def test_the_oracles_import_nothing_from_the_placer_or_the_router(self):
        makers = {"place", "rows", "columns", "axes", "route", "maze", "draw", "boxes", "render", "report"}
        for oracle, allowed in (("gates", {"symbols"}), ("judge", {"circuit", "geom", "controls", "contract"}),
                                ("contract", {"circuit", "view", "defaults"}), ("defaults", {"circuit"}), ("view", set())):
            with open(os.path.join(ROOT, "cktintent", oracle + ".py")) as f:
                tree = ast.parse(f.read())
            used = set()
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom) and node.level == 1:
                    used |= {node.module} if node.module else {a.name for a in node.names}
            self.assertEqual(used & makers, set(), oracle)
            self.assertLessEqual(used, allowed, oracle)

    def test_the_kept_gallery_is_what_the_tool_draws_now(self):
        p = subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gallery.py"), "--check"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stdout)


if __name__ == "__main__":
    unittest.main()
