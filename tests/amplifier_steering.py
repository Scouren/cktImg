"""Rejected positional requests preserve the public amplifier drawing and signal-placement decisions."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main(binary, fixture):
    source = Path(fixture).read_text()
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        def draw(directive):
            text = source.replace('.ends dut', f'*@ {directive}\n.ends dut') if directive else source
            (d/'input.cir').write_text(text)
            proc = subprocess.run([binary, '--report', d/'report', '--decisions', '2', d/'input.cir', d/'drawing'],
                                  check=True, capture_output=True)
            report = json.loads((d/'report').read_bytes())
            assert not report['gates'],directive
            line=next((r for r in report['requests'] if r['text']=='*@ '+directive.lower()), {})
            return (d/'drawing').read_bytes(),proc.stdout,line
        drawing,decisions,_=draw('')
        assert decisions.count(b'*@ at ')==7
        for line,code in [('row absent m1','unknown_name'),('bridge absent','unknown_name'),('at absent 2 3','unknown_name'),
                          ('at m1 nan 3','bad_args'),('row m1 m2','not_placeable')]:
            actual,again,request=draw(line)
            assert request['state']=='rejected' and request['code']==code,(line,request)
            assert actual==drawing and again==decisions,(line,'rejection changed geometry or decisions')
        actual,again,request=draw('weak at m1 100 100 R0')
        assert request['state']=='dropped' and actual==drawing and again==decisions
        for line in ['at m1 -20 10 R0','upright c1']:
            actual,again,request=draw(line)
            assert request['state']=='honoured' and actual!=drawing and b'*@ at ' not in again
            if line.startswith('at '):
                m1=next(d for d in json.loads(actual)['devices'] if d['name']=='m1')
                assert m1['pos']==[-800,400]


if __name__=='__main__':
    main(*sys.argv[1:])
