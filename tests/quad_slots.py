"""Compare complete original D/S slots, including raw competitors with ineligible models."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

SOURCE="""Source slot controls
.model nch nmos
.model alt nmos
.subckt dut lo lob a b s t vss
M1 a lo s vss nch
M2 b lob s vss nch
M3 a lob t vss nch
M4 b lo t vss nch
.ends dut
"""


def main(binary,files):
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)/'input.cir'
        def run(text):
            p.write_text(text)
            return json.loads(subprocess.check_output([binary,p]))['switch_rectangles']['rows']
        row,=run(SOURCE)
        assert not row['reasons'] and row['uncontested'] and {d for slot in row['slots'] for d in slot}=={'m1','m2','m3','m4'}
        competing,=run(SOURCE.replace('.ends dut','M5 a bogus s vss alt\n.ends dut'))
        assert competing['reasons']==['competing_slot'] and ['m1','m5'] in [sorted(slot) for slot in competing['slots']]
        overlap=run(SOURCE.replace('.ends dut','M5 c bogus s vss alt\nM6 c bogus t vss alt\n.ends dut'))
        shape,=[r for r in overlap if not r['reasons']]
        assert len(overlap)==3 and not shape['uncontested']
    if files:
        rows=[json.loads(r) for r in subprocess.check_output([binary,*files]).splitlines()]
        names={Path(r['path']).stem: r['switch_rectangles']['rows'] for r in rows}
        assert set(names)=={'ag-80','ag-82','ag-517','ag-1093'}
        for n,rs in names.items():
            shape,=[r for r in rs if not r['reasons']]
            actual={d for slot in shape['slots'] for d in slot}
            expected={'m3','m4','m5','m6'} if n=='ag-517' else {'m5','m6','m7','m8'} if n=='ag-1093' else {'m1','m2','m3','m4'}
            assert actual==expected,(n,actual)
            assert shape['uncontested']


if __name__=='__main__':
    main(sys.argv[1],sys.argv[2:])
