#!/usr/bin/env python3
"""Fill external/examples from the Analog Canvas gallery, downloading only what is missing.

usage: python3 -I tools/site/fetch.py external/examples [raw-dir]

Run by hand, never in CI. Per source (one directory each):
  index.json   the gallery's listing of the source (name, author, description, previewRevision);
               listed only when missing: delete it to list again.
  <id>.svg     the gallery's own preview of the person's drawing, fetched once; previews.json
               maps each id to the revision fetched, and a changed revision is fetched again.
  <id>.cir, <id>.human.json   the deck and the drawing (convert.py). An entry without them has its
               raw entry and the source's netlists downloaded into raw-dir and converted there.
At most 4 requests at a time, a generic User-Agent, nothing personal sent. Failures are listed
in <examples>/fetch-failures.txt and retried on the next run.
"""
import json, os, shutil, subprocess, sys, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor

SITE = "https://analog-canvas.tokenzhang.com"
SOURCES = ["circuitthink", "analoggenie", "amsnet", "analogretriever"]
UA = {"User-Agent": "Mozilla/5.0 (compatible)"}
KEEP = ("id", "name", "author", "description", "createdAt", "previewRevision", "previewWidth", "previewHeight")


def get(url):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.read()
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def pages(path, query):
    """Every entry of a cursor-paged listing."""
    cursor, out = None, []
    for _ in range(1000):  # bound: 1000 pages of 200 is past any source's size
        q = dict(query, **({"cursor": cursor} if cursor else {}))
        page = json.loads(get(SITE + path + "?" + urllib.parse.urlencode(q)))
        out += page["entries"]
        cursor = page.get("nextCursor")
        if not cursor or not page["entries"]:
            return out
    raise RuntimeError("listing did not end: " + path)


def preview(job):
    path, cid, rev, _ = job
    q = "?" + urllib.parse.urlencode({"v": rev, "render": "formula-label-v5"}) if rev else ""
    body = get("%s/api/gallery/%s/preview.svg%s" % (SITE, urllib.parse.quote(cid), q))
    assert body.lstrip().startswith(b"<svg") or body.lstrip().startswith(b"<?xml"), cid
    with open(path + ".tmp", "wb") as f:
        f.write(body)
    os.replace(path + ".tmp", path)


def main(examples, raw):
    jobs, unconverted, revs = [], {}, {}
    for source in SOURCES:
        d = os.path.join(examples, source)
        os.makedirs(d, exist_ok=True)
        index = os.path.join(d, "index.json")
        if not os.path.exists(index):
            listed = pages("/api/gallery", {"source": source, "limit": "200"})
            with open(index, "w") as f:
                json.dump([{k: e.get(k) for k in KEEP} for e in listed], f, indent=0)
        rp = os.path.join(d, "previews.json")
        revs[rp] = json.load(open(rp)) if os.path.exists(rp) else {}
        for e in json.load(open(index)):
            cid, rev = e["id"], e.get("previewRevision") or ""
            if not os.path.exists(os.path.join(d, cid + ".cir")):
                unconverted.setdefault(source, []).append(cid)
            svg = os.path.join(d, cid + ".svg")
            if revs[rp].get(cid) != rev or not os.path.exists(svg):
                jobs.append((svg, cid, rev, rp))
    failed = []
    with ThreadPoolExecutor(4) as ex:
        for job, err in zip(jobs, ex.map(lambda j: try_(preview, j), jobs)):
            if err:
                failed.append("%s preview: %s" % (job[1], err))
            else:
                revs[job[3]][job[1]] = job[2]
    for rp, m in revs.items():
        with open(rp, "w") as f:
            json.dump(dict(sorted(m.items())), f, indent=0)
    print("previews: %d fetched, %d failed" % (len(jobs) - len(failed), len(failed)))
    if unconverted and raw:
        failed += convert(examples, raw, unconverted)
    elif unconverted:
        print("%d entries have no deck; pass a raw-dir to download and convert them" % sum(map(len, unconverted.values())))
    with open(os.path.join(examples, "fetch-failures.txt"), "w") as f:
        f.writelines(x + "\n" for x in failed)


def convert(examples, raw, unconverted):
    """Raw entries and the source's netlists into raw-dir, then convert.py, then copy the cases over."""
    failed = []
    for source, ids in unconverted.items():
        nd, ed = os.path.join(raw, "netlists", source), os.path.join(raw, source, "entries")
        os.makedirs(nd, exist_ok=True), os.makedirs(ed, exist_ok=True)
        with open(os.path.join(nd, "page-0000.json"), "w") as f:
            json.dump({"entries": pages("/api/gallery/maintenance/netlists", {"format": "spice", "source": source, "limit": "200"})}, f)
        for cid in ids:
            p = os.path.join(ed, cid + ".json")
            err = None if os.path.exists(p) else try_(lambda: open(p, "wb").write(get("%s/api/gallery/%s" % (SITE, urllib.parse.quote(cid)))))
            if err:
                failed.append("%s entry: %s" % (cid, err))
    for s in SOURCES:  # convert.py walks every source
        os.makedirs(os.path.join(raw, "netlists", s), exist_ok=True), os.makedirs(os.path.join(raw, s, "entries"), exist_ok=True)
    out = os.path.join(raw, "out")
    ids = [i for v in unconverted.values() for i in v]
    subprocess.run([sys.executable, "-I", os.path.join(os.path.dirname(os.path.abspath(__file__)), "convert.py"), raw, out] + ids, check=True)
    for source, v in unconverted.items():
        for cid in v:
            for ext in (".cir", ".human.json"):
                src = os.path.join(out, "cases", cid + ext)
                if os.path.exists(src):
                    shutil.copy(src, os.path.join(examples, source, cid + ext))
                elif ext == ".cir":
                    failed.append("%s: convert.py made no deck" % cid)
    return failed


def try_(fn, *args):
    try:
        fn(*args)
        return None
    except Exception as e:
        return repr(e)[:200]


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
