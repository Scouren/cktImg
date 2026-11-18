#!/usr/bin/env python3
"""Independently rasterize the sixth symbol study's exact 33 source/native pairs."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
RUN=ROOT/'.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/ports'
BIN=ROOT/'.objective/human-schematic-equivalence/runs/iteration21-resume1/resistor-output-integrated-common/zig-out/bin/cktimg-json'
EXTRA=[715,784,788,923,1146,1440,1457,2469]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rel(p):return str(p.relative_to(ROOT))

def main():
    census=json.loads((RUN/'sixth-digital-census.json').read_text())
    ids=sorted({int(r['id'][3:]) for r in census['instances']}|set(EXTRA))
    magick=Path(shutil.which('magick')).resolve();rows=[]
    for n in ids:
        cid=f'ag-{n}';source=ROOT/f'external/examples/analoggenie/{cid}.svg'
        native=RUN/f'sixth-native/{cid}.svg';jp=native.with_suffix('.json')
        if n in EXTRA:
            subprocess.run([str(BIN),'--svg',str(native),str(source.with_suffix('.cir')),str(jp)],check=True,capture_output=True)
        raster=[]
        for side,svg in [('source',source),('native',native)]:
            png=HERE/f'figures/ports/sixth-{cid}-{side}.png'
            cmd=[str(magick),'-density','220','-background','white',str(svg),'-alpha','remove','-alpha','off','-resize','1300x1100>',str(png)]
            subprocess.run(cmd,check=True,capture_output=True)
            raster.append(dict(side=side,svg=rel(svg),svg_sha256=sha(svg),png=rel(png),png_sha256=sha(png),command=cmd))
        pair=HERE/f'figures/ports/sixth-{cid}-pair.png'
        # Each SVG was rasterized separately above; only PNGs are combined.
        cmd=[str(magick),*[str(ROOT/r['png']) for r in raster],'-background','white','-gravity','center','+append',str(pair)]
        subprocess.run(cmd,check=True,capture_output=True)
        rows.append(dict(id=cid,renders=raster,pair=rel(pair),pair_sha256=sha(pair),pair_command=cmd,
                         deck_sha256=sha(source.with_suffix('.cir')),native_json_sha256=sha(jp)))
    result=dict(scope='25 exact conventional/opaque-cohort decks plus eight bounded mixed-control decks; no nested SVG contact sheets.',
                binary=rel(BIN),binary_sha256=sha(BIN),magick=str(magick),magick_sha256=sha(magick),renders=rows)
    (HERE/'sixth-symbols-renders.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(pairs=len(rows),ids=[r['id'] for r in rows])))

if __name__=='__main__':main()
