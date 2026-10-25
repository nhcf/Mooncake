"""Read copied seven-patch bucket files with a fresh candidate Master and Store."""
import ctypes,json,os,socket,subprocess,time
from pathlib import Path
r=Path('/result');b=r/'buckets';assert b.is_dir()
M=1024**2
os.environ.update(MOONCAKE_OFFLOAD_STORAGE_BACKEND_DESCRIPTOR='bucket_storage_backend',MOONCAKE_OFFLOAD_BUCKET_KEYS_LIMIT='1',MOONCAKE_OFFLOAD_BUCKET_SIZE_LIMIT_BYTES=str(16*M),MOONCAKE_OFFLOAD_BUCKET_MAX_TOTAL_SIZE=str(1024*M),MOONCAKE_OFFLOAD_TOTAL_SIZE_LIMIT_BYTES=str(1024*M),MOONCAKE_OFFLOAD_LOCAL_BUFFER_SIZE_BYTES=str(32*M),MOONCAKE_OFFLOAD_HEARTBEAT_INTERVAL_SECONDS='1',MOONCAKE_OFFLOAD_BUCKET_EVICTION_POLICY='lru')
from mooncake.store import MooncakeDistributedStore
with (r/'master.log').open('w') as f:
 p=subprocess.Popen(['mooncake_master','--port=17788','--metrics_port=19003','--enable_offload=true','--default_kv_lease_ttl=100'],stdout=f,stderr=f)
 s=None
 try:
  for _ in range(100):
   if p.poll() is not None:raise RuntimeError('master exited')
   try:
    with socket.create_connection(('127.0.0.1',17788),.1):break
   except OSError:time.sleep(.1)
  s=MooncakeDistributedStore();assert s.setup('127.0.0.1','P2PHANDSHAKE',64*M,32*M,'tcp','','127.0.0.1:17788',enable_ssd_offload=True,ssd_offload_path=str(b))==0
  keys=['restart-check-'+str(i) for i in range(24)]
  for _ in range(30):
   present=s.batch_is_exist(keys)
   if all(x==1 for x in present):break
   time.sleep(1)
  buf=ctypes.create_string_buffer(M);ptr=ctypes.addressof(buf);assert s.register_buffer(ptr,M)==0
  bad=[]
  for i,k in enumerate(keys):
   rc=s.batch_get_into([k],[ptr],[M])[0]
   if rc!=M or buf.raw!=bytes([i+1])*M:bad.append({'key':k,'rc':rc})
  s.unregister_buffer(ptr)
  result={'present':sum(x==1 for x in present),'total':24,'byte_errors':bad,'scope':'copied old files, fresh empty Master, CPU/TCP'}
  (r/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
  assert result['present']==24 and not bad
 finally:
  if s is not None:
   s.close() if hasattr(s,'close') else None
  p.terminate();p.wait(timeout=10)
