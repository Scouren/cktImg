#!/usr/bin/env python3
"""The static site: every Analog Canvas reference circuit, the person's drawing beside cktImg's.

usage: python3 -I tools/site/build.py <examples-dir> <bin-dir> <out-dir>
reads  <examples-dir>/<source>/index.json, <id>.cir, <id>.human.json, <id>.svg (fetch.py)
runs   <bin-dir>/cktimg-json --svg --report on every deck, <bin-dir>/gallery --svgs
writes <out-dir>/index.html, c/<id>.html, img/<id>.{human,ours}.svg, textbook/

Both drawings are measured the way src/report.zig measures ours (report.1, report.2), see
`measure`. Ours come from --report; the person's are recomputed here from human.json, and the
same function run on our JSON must agree with --report: a disagreement fails the build.
"""
import html, json, math, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

SOURCES = ["circuitthink", "analoggenie", "amsnet", "analogretriever"]
SITE = "https://analog-canvas.tokenzhang.com"
TRANSISTORS = {"nmos", "pmos", "npn", "pnp", "njfet", "pjfet", "depletion-nmos", "depletion-pmos"}
PARTS = {"resistor", "capacitor", "inductor", "inductor-compact", "variable-capacitor", "variable-resistor",
         "current-source", "voltage-source", "battery", "vccs", "vcvs", "cccs", "ccvs", "diode", "zener-diode",
         "schottky-diode", "led", "ideal-switch", "simple-switch", "externally-controlled-switch", "microphone", "speaker"}
CLASSES = {"t": "transistors", "p": "parts", "bt": "blocks + transistors", "bp": "blocks + parts"}
CSS = """body{font:15px/1.45 system-ui,sans-serif;margin:0 auto;max-width:1400px;padding:0 16px;color:#1d2330;background:#fff}
a{color:#2357a6}h1{font-size:1.4em}table{border-collapse:collapse;width:100%}td,th{padding:3px 6px;border-bottom:1px solid #e3e6ec;text-align:left}
th{cursor:pointer;white-space:nowrap}.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}.pair figure{margin:0;border:1px solid #e3e6ec;padding:8px}
.pair img{width:100%;height:auto;max-height:75vh;object-fit:contain;background:#fff}figcaption{font-weight:600;margin-bottom:6px}
.muted{color:#68707d}input,select{font:inherit;margin:0 6px 6px 0}.tb{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px}
.tb figure{margin:0;border:1px solid #e3e6ec;padding:6px}.tb img{width:100%;height:auto}
@media(max-width:800px){.pair{grid-template-columns:1fr}}
:root{color-scheme:light}html.dark{color-scheme:dark}html.dark body{color:#e3e6ec;background:#16181d}
html.dark a{color:#8fb4ff}html.dark td,html.dark th,html.dark .pair figure,html.dark .tb figure{border-color:#3a3f4b}
html.dark .muted{color:#9aa2b1}html.dark input,html.dark select{background:#22252c;color:#e3e6ec;border:1px solid #3a3f4b}
html.dark .pair img,html.dark .tb img{filter:invert(1) hue-rotate(180deg)}
#invert{position:fixed;top:10px;right:16px;font:inherit;padding:4px 10px;cursor:pointer;border:1px solid #9aa2b1;border-radius:6px;background:inherit;color:inherit}"""


def segments(doc):
    """Each net's wires as two-point segments, from either drawing's wires[] (polylines)."""
    out = {}
    for w in doc["wires"]:
        for poly in w["segments"]:
            out.setdefault(w["net"], []).extend(zip(map(tuple, poly), map(tuple, poly[1:])))
    return out


def measure(segs, pins, unit):
    """crossings, corners, wire length in units (report.1, report.2). pins: {(net, (x, y))}.
    A person may draw a wire on a slant, so both hold at any slope: two nets' wires crossing strictly
    inside both, and a point with no pin a net leaves exactly two ways not in one line. On level and
    upright wires (all of ours) these are report.1 and report.2."""
    side = lambda p, q, r: (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])  # noqa: E731
    flat = [(n, a, b) for n, s in segs.items() for a, b in s if a != b]
    crossings = sum(1 for i, (n, a, b) in enumerate(flat) for m, c, d in flat[i + 1:] if m != n
                    and side(a, b, c) * side(a, b, d) < 0 and side(c, d, a) * side(c, d, b) < 0)
    way = lambda p, q: (round((q[0] - p[0]) / math.dist(p, q), 6), round((q[1] - p[1]) / math.dist(p, q), 6))  # noqa: E731
    corners = 0
    for n, s in segs.items():
        s = [(a, b) for a, b in s if a != b]
        for at in {p for seg in s for p in seg}:
            ways = set()  # the directions the net's wire leaves `at` in
            for a, b in s:
                on = at in (a, b) or (side(a, b, at) == 0 and min(a[0], b[0]) <= at[0] <= max(a[0], b[0])
                                      and min(a[1], b[1]) <= at[1] <= max(a[1], b[1]))
                ways |= {way(at, q) for q in (a, b) if on and q != at}
            if (n, at) not in pins and len(ways) == 2:
                (x1, y1), (x2, y2) = ways
                corners += abs(x1 + x2) > 1e-6 or abs(y1 + y2) > 1e-6  # not a straight joint
    length = sum(math.dist(a, b) for s in segs.values() for a, b in s)
    return crossings, corners, round(length / unit, 1)


def human_metrics(h):
    pins = {(n, tuple(d["terminals"][t])) for d in h["devices"] for t, n in d["nets"].items() if n and t in d["terminals"]}
    pins |= {(m["net"], tuple(m["at"])) for m in h["markers"]}
    c, b, length = measure(segments(h), pins, h["unit"] or 40.0)
    return dict(crossings=c, corners=b, wire_len=length, names=len({l["net"] for l in h["labels"]}))


def our_metrics(j, report):
    pins = {(p["net"], tuple(p["xy"])) for d in j["devices"] for p in d["pins"]}
    unit = next((abs(q["d"][1] - q["s"][1]) + abs(q["d"][0] - q["s"][0]) for d in j["devices"]
                 for q in [{p["term"]: p["xy"] for p in d["pins"]}] if "d" in q and "s" in q), 40.0) or 40.0
    c, b, length = measure(segments(j), pins, unit)
    m = report["metrics"]
    agree = (c, b) == (m["crossings"], m["bends"])
    return dict(crossings=m["crossings"], corners=m["bends"], wire_len=length, names=len(m["labelled"])), agree


def klass(h):
    types = {d["type"] for d in h["devices"]}
    blocks = bool(types - TRANSISTORS - PARTS)
    return ("b" if blocks else "") + ("t" if types & TRANSISTORS else "p")


def draw(job):
    """Run the engine on one deck; (metrics, report agrees, error)."""
    cir, img, tmp = job
    try:
        r = subprocess.run([BIN + "/cktimg-json", "--svg", img, "--report", tmp + ".r.json", cir, tmp + ".json"],
                           capture_output=True, text=True, timeout=60)
        if r.returncode != 0:
            return None, True, (r.stderr or r.stdout).strip()[-500:] or "exit %d" % r.returncode
        m, agree = our_metrics(json.load(open(tmp + ".json")), json.load(open(tmp + ".r.json")))
        return m, agree, None
    except Exception as e:
        return None, True, repr(e)[:500]
    finally:
        for ext in (".json", ".r.json"):
            if os.path.exists(tmp + ext):
                os.remove(tmp + ext)


# The colour inverter: a dark page with every drawing inverted (black lines on white become white on dark), chosen
# by the button, else by the viewer's system setting; the choice is kept in localStorage, which may be unavailable.
# `color-scheme` stops a browser's own forced dark mode from repainting the drawings' strokes.
THEME = ("<script>(function(){var d;try{d=localStorage.getItem('dark')}catch(e){}"
         "if(d===null)d=matchMedia('(prefers-color-scheme: dark)').matches?'1':'0';"
         "if(d==='1')document.documentElement.classList.add('dark')})()</script>")
TOGGLE = ("<button id=\"invert\" title=\"invert the colours\" onclick=\"var c=document.documentElement.classList;"
          "c.toggle('dark');try{localStorage.setItem('dark',c.contains('dark')?'1':'0')}catch(e){}\">&#9681; invert</button>")


def page(title, body, root=""):
    return ('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            '<meta name="color-scheme" content="light only"><title>%s</title><link rel="stylesheet" href="%sstyle.css">%s</head>'
            '<body>%s%s</body></html>' % (html.escape(title), root, THEME, TOGGLE, body))


def metrics_table(h, o):
    rows = [("crossings", "crossings"), ("corners", "corners"), ("wire length (units)", "wire_len"), ("written net names", "names")]
    cell = lambda m, k: "&ndash;" if m is None else html.escape(str(m[k]))  # noqa: E731
    return "<table><tr><th></th><th>person</th><th>cktImg</th></tr>%s</table>" % "".join(
        "<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (label, cell(h, k), cell(o, k)) for label, k in rows)


def circuit_page(e, row, h, o, err):
    esc = html.escape
    cid = e["id"]
    ours = ('<img src="../img/%s.ours.svg" alt="cktImg drawing" loading="lazy">' % cid) if o else \
        "<p>cktImg did not draw this deck:</p><pre>%s</pre>" % esc(err or "")
    human = ('<img src="../img/%s.human.svg" alt="the person\'s drawing" loading="lazy">' % cid) if row["preview"] else \
        "<p>The gallery's preview of this drawing was not fetched.</p>"
    body = ('<p><a href="../index.html">&larr; all circuits</a></p><h1>%s</h1><p>%s</p>'
            '<p class="muted">%s &middot; source %s &middot; %s &middot; <a href="%s/g/%s">open on Analog Canvas</a> &middot; '
            '<a href="../deck/%s.cir">SPICE deck</a></p>'
            '<div class="pair"><figure><figcaption>Drawn by a person (Analog Canvas preview)</figcaption>%s</figure>'
            '<figure><figcaption>Drawn by cktImg from the netlist</figcaption>%s</figure></div>%s'
            '<p class="muted">Corners and crossings are counted the way <code>src/report.zig</code> counts them, on both drawings; '
            'wire length is in symbol lengths. The person&rsquo;s drawing is &copy; its author as credited above, shown from the '
            'Analog Canvas gallery.</p>') % (
        esc(e.get("name") or cid), esc(e.get("description") or ""), esc(e.get("author") or ""), esc(row["source"]),
        esc(CLASSES[row["class"]]), SITE, esc(cid), esc(cid), human, ours, metrics_table(h, o))
    return page(e.get("name") or cid, body, "../")


INDEX_JS = """const D=JSON.parse(document.getElementById('d').textContent),P=100;let page=0,key='dx',dir=-1,rows=D;
const $=id=>document.getElementById(id),esc=s=>String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function run(){const q=$('q').value.toLowerCase(),c=$('c').value,s=$('s').value;
rows=D.filter(r=>(!q||r.id.includes(q)||r.name.toLowerCase().includes(q))&&(!c||r.class==c)&&(!s||r.source==s));
rows.sort((a,b)=>{const x=a[key],y=b[key];return (x==null)-(y==null)||(x<y?-1:x>y?1:0)*dir});page=Math.min(page,Math.max(0,Math.ceil(rows.length/P)-1));show()}
function show(){const v=rows.slice(page*P,page*P+P);$('n').textContent=rows.length+' circuits, page '+(page+1)+' of '+Math.max(1,Math.ceil(rows.length/P));
$('t').innerHTML=v.map(r=>'<tr><td><a href="c/'+r.id+'.html">'+esc(r.id)+'</a></td><td>'+esc(r.name)+'</td><td>'+r.source+'</td><td>'+r.class+'</td><td>'+r.hx+'</td><td>'+(r.ox??'failed')+'</td><td>'+(r.dx??'')+'</td><td>'+r.hb+'</td><td>'+(r.ob??'')+'</td></tr>').join('')}
for(const id of['q','c','s'])$(id).oninput=()=>{page=0;run()};
document.querySelectorAll('th[data-k]').forEach(th=>th.onclick=()=>{dir=key==th.dataset.k?-dir:1;key=th.dataset.k;run()});
$('prev').onclick=()=>{if(page>0){page--;show()}};$('next').onclick=()=>{if((page+1)*P<rows.length){page++;show()}};run();"""


def index_page(rows, failed, fetched, disagree):
    data = json.dumps(rows, separators=(",", ":")).replace("<", "\\u003c")
    opt = lambda vals: "".join('<option value="%s">%s</option>' % (html.escape(k), html.escape(v)) for k, v in vals)  # noqa: E731
    body = ('<h1>cktImg beside the person who drew it</h1><p>Every reference circuit of the '
            '<a href="%s">Analog Canvas</a> gallery (%d circuits): the drawing a person made, beside the one '
            'cktImg makes from the same netlist. The person&rsquo;s side is the gallery&rsquo;s own preview image, cached in '
            '<code>external/examples</code>. cktImg failed on %d decks; %d previews are missing. See also the '
            '<a href="textbook/index.html">textbook circuits</a>.</p>'
            '<p><input id="q" placeholder="search id or name"><select id="c"><option value="">every class</option>%s</select>'
            '<select id="s"><option value="">every source</option>%s</select><button id="prev">&larr;</button>'
            '<button id="next">&rarr;</button> <span id="n" class="muted"></span></p>'
            '<table><thead><tr><th data-k="id">id</th><th data-k="name">name</th><th data-k="source">source</th><th data-k="class">class</th>'
            '<th data-k="hx">person crossings</th><th data-k="ox">cktImg crossings</th><th data-k="dx">difference</th>'
            '<th data-k="hb">person corners</th><th data-k="ob">cktImg corners</th></tr></thead><tbody id="t"></tbody></table>'
            '<p class="muted">Classes: t transistors, p parts, bt blocks and transistors, bp blocks and parts. Difference is '
            'cktImg&rsquo;s crossings minus the person&rsquo;s; click a heading to sort.</p>'
            '<script type="application/json" id="d">%s</script><script>%s</script>') % (
        SITE, len(rows), failed, len(rows) - fetched, opt(CLASSES.items()), opt((s, s) for s in SOURCES), data, INDEX_JS)
    return page("cktImg vs. hand-drawn schematics", body)


def textbook(out):
    d = os.path.join(out, "textbook")
    os.makedirs(d, exist_ok=True)
    subprocess.run([BIN + "/gallery", "--svgs", d], check=True, capture_output=True)
    figs = "".join('<figure><figcaption>%s &middot; <a href="%s.cir">deck</a></figcaption><img src="%s" alt="%s" loading="lazy"></figure>'
                   % (html.escape(f[:-4]), html.escape(f[:-4]), html.escape(f), html.escape(f[:-4]))
                   for f in sorted(os.listdir(d)) if f.endswith(".svg") and os.path.exists(os.path.join(d, f[:-4] + ".cir")))
    with open(os.path.join(d, "index.html"), "w") as f:
        f.write(page("cktImg textbook circuits", '<p><a href="../index.html">&larr; all circuits</a></p><h1>Textbook circuits</h1>'
                     '<p>The circuits of <code>zig build gallery</code>, drawn by cktImg.</p><div class="tb">%s</div>' % figs, "../"))


def main(examples, out):
    for sub in ("c", "img", "deck"):
        os.makedirs(os.path.join(out, sub), exist_ok=True)
    tmp = os.path.join(out, ".tmp")
    os.makedirs(tmp, exist_ok=True)
    entries = []
    for source in SOURCES:
        d = os.path.join(examples, source)
        for e in json.load(open(os.path.join(d, "index.json"))):
            if os.path.exists(os.path.join(d, e["id"] + ".cir")):
                entries.append((source, d, e))
    jobs = [(os.path.join(d, e["id"] + ".cir"), os.path.join(out, "img", e["id"] + ".ours.svg"), os.path.join(tmp, e["id"]))
            for _, d, e in entries]
    with ThreadPoolExecutor(os.cpu_count() or 4) as ex:
        drawn = list(ex.map(draw, jobs))
    rows, fetched, failed, disagree = [], 0, 0, []
    for (source, d, e), (o, agree, err) in zip(entries, drawn):
        cid = e["id"]
        h_doc = json.load(open(os.path.join(d, cid + ".human.json")))
        h = human_metrics(h_doc)
        svg = os.path.join(d, cid + ".svg")
        if os.path.exists(svg):
            shutil.copy(svg, os.path.join(out, "img", cid + ".human.svg"))
            fetched += 1
        shutil.copy(os.path.join(d, cid + ".cir"), os.path.join(out, "deck", cid + ".cir"))
        failed += o is None
        if not agree:
            disagree.append(cid)
        row = dict(id=cid, name=e.get("name") or cid, source=source, **{"class": klass(h_doc)}, hx=h["crossings"], hb=h["corners"],
                   ox=o and o["crossings"], ob=o and o["corners"], dx=o and o["crossings"] - h["crossings"], preview=os.path.exists(svg))
        rows.append(row)
        with open(os.path.join(out, "c", cid + ".html"), "w") as f:
            f.write(circuit_page(e, row, h, o, err))
    shutil.rmtree(tmp)
    for r in rows:
        del r["preview"]
    with open(os.path.join(out, "index.html"), "w") as f:
        f.write(index_page(rows, failed, fetched, disagree))
    with open(os.path.join(out, "style.css"), "w") as f:
        f.write(CSS)
    textbook(out)
    print("%d circuits, %d drawn, %d engine failures, %d previews; report disagrees with the site's measure on %d: %s"
          % (len(rows), len(rows) - failed, failed, fetched, len(disagree), " ".join(disagree[:20])))
    return 1 if disagree else 0


if __name__ == "__main__":
    BIN = os.path.abspath(sys.argv[2])
    sys.exit(main(sys.argv[1], sys.argv[3]))
