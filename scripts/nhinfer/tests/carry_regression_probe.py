import os,time,socket,subprocess,json,sys
from pathlib import Path
from mooncake.store import MooncakeDistributedStore
mode=sys.argv[1];queue=int(sys.argv[2]) if len(sys.argv)>2 else 1;label='carry16m-'+mode+'-q'+str(queue);root=Path('/result');Path('/tmp/buckets').mkdir(exist_ok=True)
os.environ.update(MOONCAKE_OFFLOAD_STORAGE_BACKEND_DESCRIPTOR='bucket_storage_backend',MOONCAKE_OFFLOAD_FILE_STORAGE_PATH='/tmp/buckets',MOONCAKE_OFFLOAD_BUCKET_KEYS_LIMIT='500',MOONCAKE_OFFLOAD_BUCKET_SIZE_LIMIT_BYTES=str(16*1024**2),MOONCAKE_OFFLOAD_BUCKET_MAX_TOTAL_SIZE=str(1024**3),MOONCAKE_OFFLOAD_TOTAL_SIZE_LIMIT_BYTES=str(1024**3),MOONCAKE_OFFLOAD_LOCAL_BUFFER_SIZE_BYTES=str(32*1024**2),MOONCAKE_OFFLOAD_HEARTBEAT_INTERVAL_SECONDS='1')
log=open(root/f'{label}-master.log','w');p=subprocess.Popen(['mooncake_master','--port=17788','--metrics_port=19003','--enable_offload=true',f'--offloading_queue_limit={queue}',f'--offload_on_evict={mode}','--offload_force_evict=false','--eviction_high_watermark_ratio=0.7','--eviction_ratio=0.2','--default_kv_lease_ttl=100'],stdout=log,stderr=log)
try:
 for _ in range(100):
  if p.poll() is not None:raise RuntimeError('master exited')
  try:
   with socket.create_connection(('127.0.0.1',17788),.1):break
  except OSError:time.sleep(.1)
 s=MooncakeDistributedStore();assert s.setup('127.0.0.1','P2PHANDSHAKE',64*1024**2,32*1024**2,'tcp','','127.0.0.1:17788',enable_ssd_offload=True,ssd_offload_path='/tmp/buckets')==0
 keys=[];failed=[];value=b'x'*(1024**2)
 for i in range(100):
  key=f'isolated-{mode}-{i}';rc=s.put(key,value)
  if rc==0:keys.append(key)
  else:failed.append([key,rc])
  time.sleep(.025)
  if i == 9:time.sleep(3)  # Force a partial bucket to cross heartbeat cycles.
 time.sleep(15)
 exists=s.batch_is_exist(keys)
 read_failures=[]
 for key,exists_rc in zip(keys,exists):
  if exists_rc == 1 and s.get(key) != value:read_failures.append(key)
 result={'scope':'isolated CPU/TCP test; queue limit recorded separately; not production root-cause proof','mode':mode,'bucket_keys_limit':500,'bucket_size_limit':16*1024**2,'offloading_queue_limit':queue,'read_failures':read_failures,'put_success':len(keys),'put_failures':failed,'missing':[k for k,e in zip(keys,exists) if e!=1]}
 (root/f'{label}-result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
finally:
 p.terminate();p.wait(timeout=10)
