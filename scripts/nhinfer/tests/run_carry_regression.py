import os, tempfile
import json,subprocess,sys
from pathlib import Path
r=Path(__file__).resolve().parent
out=Path(tempfile.mkdtemp(prefix='mooncake-carry-', dir=os.environ.get('RESULT_ROOT')))
print('RESULT_DIR='+str(out),flush=True)
for n in range(2):
 d=out/f'carry-regression-{n}';d.mkdir()
 cmd=['docker','run','--rm','--memory=2g','--name',f'mc-admission-carry-{n}','-v',str(d)+':/result','-v',str(r/'carry_regression_probe.py')+':/probe.py:ro','--entrypoint','python3',sys.argv[1],'/probe.py','false','50000']
 (d/'command.json').write_text(json.dumps(cmd))
 with (d/'run.log').open('w') as f:q=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
 (d/'exit-code').write_text(str(q.returncode))
 assert q.returncode==0
 j=json.loads((d/'carry16m-false-q50000-result.json').read_text())
 assert j['put_success']==100 and not j['put_failures'] and not j['missing'] and not j['read_failures'],j
 print('PASS',n,'100/100 byte equal',flush=True)
