"""House rules a machine can check, over the tool's own source.

usage: python3 tools/check.py          exit 0 when clean, 1 with one line per finding

    size   a file holds at most 500 lines that are neither blank nor a comment
    doc    every module, and every function and class whose name does not start with `_`,
           says what it is for
"""
import ast, glob, os, sys

MAX_LINES = 500
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def findings(paths):
    """-> ["path:line: rule: message"] for every broken rule in the given files."""
    out = []
    for path in paths:
        with open(path) as f:
            text = f.read()
        name = os.path.relpath(path, ROOT)
        lines = sum(1 for l in text.splitlines() if l.strip() and not l.strip().startswith("#"))
        if lines > MAX_LINES:
            out.append("%s:1: size: %d lines, at most %d" % (name, lines, MAX_LINES))
        tree = ast.parse(text)
        if not ast.get_docstring(tree) and text.strip():
            out.append("%s:1: doc: the module does not say what it is for" % name)
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and not node.name.startswith("_") and not ast.get_docstring(node):
                nested = any(node in ast.walk(f) and f is not node for f in ast.walk(tree) if isinstance(f, ast.FunctionDef))
                if not nested:                    # a helper inside a function is that function's business
                    out.append("%s:%d: doc: %s has no docstring" % (name, node.lineno, node.name))
    return out


def main():
    """Check the package and the tools. -> the exit status."""
    paths = sorted(glob.glob(os.path.join(ROOT, "cktintent", "*.py")) + glob.glob(os.path.join(ROOT, "tools", "*.py")))
    found = findings(paths)
    print("\n".join(found) if found else "%d files clean" % len(paths))
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
