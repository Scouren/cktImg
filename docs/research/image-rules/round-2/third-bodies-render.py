#!/usr/bin/env python3
"""Independently rasterize all 23 raw body-only cases; no viewing claim here."""
import argparse
import json
from pathlib import Path
import subprocess
from bodies_census import ROOT, BASE, sha


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path)
    args=ap.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
    census_path=BASE/'image-rule-round-2/bodies/census.json'
    raw=json.loads(census_path.read_text())
    selected={ident for ident,card in raw['buckets']['internal_body_only']}
    rows=[]
    for circuit in sorted((c for c in raw['circuits'] if c['id'] in selected),key=lambda c:int(c['id'][3:])):
        ident=circuit['id'];cards=[m for m in circuit['mos'] if [ident,m['card']] in raw['buckets']['internal_body_only']]
        paths={key:ROOT/'external/examples/analoggenie'/(ident+suffix) for key,suffix in
               [('deck','.cir'),('source_json','.human.json'),('source_svg','.svg')]}
        paths['native_svg']=BASE/'gallery-preview/img'/(ident+'.ours.svg')
        panels=[]
        for role in ('source_svg','native_svg'):
            p=out/(ident+'-'+role+'.png')
            subprocess.run(['magick','-background','white',str(paths[role]),'-resize','1400x1100',
                            '-gravity','center','-extent','1420x1140',str(p)],check=True)
            panels.append(p)
        pair=out/(ident+'.png')
        subprocess.run(['magick',*map(str,panels),'+append',str(pair)],check=True)
        rows.append(dict(id=ident,body_cards=cards,
                         files={key:dict(path=str(p.relative_to(ROOT)),sha256=sha(p)) for key,p in paths.items()},
                         pair=dict(path=str(pair.relative_to(ROOT)),sha256=sha(pair)),
                         panels=[dict(path=str(p.relative_to(ROOT)),sha256=sha(p)) for p in panels]))
    assert len(rows)==23
    result=dict(scope='All 23 named internal body-only circuits; images must be actually viewed separately',
                census_sha256=sha(census_path),script_sha256=sha(Path(__file__)),
                renderer=subprocess.check_output(['magick','-version'],text=True),cases=rows)
    (out/'manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Rendered all 23 named body-only pairs independently')


if __name__=='__main__':main()
