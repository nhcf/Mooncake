import os, tempfile
"""Run isolated CPU/TCP admission regression; does not access online pools."""
import argparse,json,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('image');a=p.parse_args()
r=Path(__file__).resolve().parent
out=Path(tempfile.mkdtemp(prefix='mooncake-lru-', dir=os.environ.get('RESULT_ROOT')))
identity=subprocess.check_output(['docker','image','inspect',a.image]);(out/'image-identity.json').write_bytes(identity)
summary={'image':a.image,'cases':{},'scope':'CPU/TCP isolated, 1MiB objects, 1 object/bucket; no production changes'}
for policy in ('lru','fifo'):
 d=out/policy;d.mkdir();cmd=['docker','run','--rm','--name','mc-lru-regression-'+policy+'-'+str(int(time.time())),'--entrypoint','python3','-v',str(r/'lru_admission_probe.py')+':/probe.py:ro','-v',str(d)+':/result',a.image,'/probe.py',policy]
 (d/'command.json').write_text(json.dumps(cmd))
 with (d/'run.log').open('w') as f:result=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
 (d/'exit-code').write_text(str(result.returncode)+'\n')
 if result.returncode:raise SystemExit('Probe failed: '+str(d))
 j=json.loads((d/'result.json').read_text());summary['cases'][policy]=j
 print(policy,'old_retained',len(j['hot_retained']),'new_retained',len(j['new_retained']),flush=True)
(out/'summary.json').write_text(json.dumps(summary,indent=2));print('RESULT_DIR='+str(out),flush=True)
# New admissions must survive this load; older objects must be evicted to make room.
for policy,j in summary['cases'].items():
 assert len(j['new_retained'])==45,(policy,j['new_missing'])
 assert j['final_missing'],(policy,'no eviction observed')
 assert not any(j[k] for k in ('put_failures','initial_missing','touch_errors','hot_byte_errors','new_byte_errors'))
print('LRU_REGRESSION=PASS',flush=True)
