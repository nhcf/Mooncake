import os,time,socket,subprocess,json,sys
from pathlib import Path
from mooncake.store import MooncakeDistributedStore
policy=sys.argv[1];assert policy in ('fifo','lru')
r=Path('/result');path='/tmp/lru-test-buckets';Path(path).mkdir()
M=1024**2
os.environ.update(MOONCAKE_OFFLOAD_STORAGE_BACKEND_DESCRIPTOR='bucket_storage_backend',MOONCAKE_OFFLOAD_FILE_STORAGE_PATH=path,MOONCAKE_OFFLOAD_BUCKET_KEYS_LIMIT='1',MOONCAKE_OFFLOAD_BUCKET_SIZE_LIMIT_BYTES=str(256*M),MOONCAKE_OFFLOAD_BUCKET_MAX_TOTAL_SIZE=str(128*M),MOONCAKE_OFFLOAD_TOTAL_SIZE_LIMIT_BYTES=str(129*M),MOONCAKE_OFFLOAD_LOCAL_BUFFER_SIZE_BYTES=str(32*M),MOONCAKE_OFFLOAD_HEARTBEAT_INTERVAL_SECONDS='1',MOONCAKE_OFFLOAD_BUCKET_EVICTION_POLICY=policy)
f=(r/'master.log').open('w');p=subprocess.Popen(['mooncake_master','--port=17788','--metrics_port=19003','--enable_offload=true','--offloading_queue_limit=50000','--offload_on_evict=false','--offload_force_evict=false','--eviction_high_watermark_ratio=0.7','--eviction_ratio=0.2','--default_kv_lease_ttl=100'],stdout=f,stderr=f)
a={'policy':policy,'scope':'isolated CPU/TCP, 1 object per bucket; retention test, not production performance','put_failures':[]}
try:
 for _ in range(100):
  if p.poll() is not None:raise RuntimeError('master exited')
  try:
   with socket.create_connection(('127.0.0.1',17788),.1):break
  except OSError:time.sleep(.1)
 s=MooncakeDistributedStore();assert s.setup('127.0.0.1','P2PHANDSHAKE',16*M,32*M,'tcp','','127.0.0.1:17788',enable_ssd_offload=True,ssd_offload_path=path)==0
 def val(i):return bytes([i%251])*M
 def put(i):
  rc=s.put(f'lru-check-{i}',val(i))
  if rc:a['put_failures'].append([i,rc])
  time.sleep(.2)
 for i in range(90):put(i)
 time.sleep(6)
 a['initial_missing']=[i for i,v in enumerate(s.batch_is_exist([f'lru-check-{j}' for j in range(90)])) if v!=1]
 a['touch_errors']=[]
 for i in range(90):
  if s.get(f'lru-check-{i}')!=val(i):a['touch_errors'].append(i)
 for i in range(90,135):put(i)
 time.sleep(8)
 exists=s.batch_is_exist([f'lru-check-{i}' for i in range(135)])
 a['final_missing']=[i for i,x in enumerate(exists) if x!=1]
 a['hot_retained']=[i for i in range(90) if exists[i]==1]
 a['new_retained']=[i for i in range(90,135) if exists[i]==1]
 a['new_missing']=[i for i in range(90,135) if exists[i]!=1]
 a['hot_byte_errors']=[i for i in a['hot_retained'] if s.get(f'lru-check-{i}')!=val(i)]
 a['new_byte_errors']=[i for i in a['new_retained'] if s.get(f'lru-check-{i}')!=val(i)]
 (r/'result.json').write_text(json.dumps(a,indent=2));print(json.dumps(a),flush=True)
 assert not a['put_failures'] and not a['initial_missing'] and not a['touch_errors'] and not a['hot_byte_errors'] and not a['new_byte_errors']
finally:
 p.terminate();p.wait(timeout=10)
