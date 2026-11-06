"""隔离协议门禁：零共享段厂商Client，分进程验证对象在Store保留。"""
import ctypes,json,sys,urllib.request
from mooncake.store import MooncakeDistributedStore
mode=sys.argv[1]
with urllib.request.urlopen('http://127.0.0.1:19003/get_all_segments',timeout=5) as response:
 assert response.status==200 and response.read()
print('MASTER_SEGMENTS_HTTP_OK',flush=True)
s=MooncakeDistributedStore()
r=s.setup('127.0.0.1','P2PHANDSHAKE',0,64*1024*1024,'tcp','','127.0.0.1:17788')
print('SETUP_RETURN',r,flush=True)
assert r==0
sizes=[65536,20*1024*1024]
for n in sizes:
 key='kimi-probe-'+str(n)
 data=b'k'*n
 if mode=='write':
  r=s.put(key,data);print('PUT',n,r,flush=True);assert r==0
 else:
  result=s.get(key);assert result==data;print('GET_BYTES_OK',n,flush=True)
# 两个buffer组成一个大对象，覆盖KDA/多层KV使用的接口；注册后保持引用。
buffers=[ctypes.create_string_buffer(b'a'*65536,65536),ctypes.create_string_buffer(b'b'*(20*1024*1024),20*1024*1024)]
ptrs=[ctypes.addressof(x) for x in buffers]
for ptr,n in zip(ptrs,sizes): assert s.register_buffer(ptr,n)==0
if mode=='write':
 result=s.batch_put_from_multi_buffers(['kimi-probe-multi'],[ptrs],[sizes]);assert result==[0],result
else:
 for ptr,n in zip(ptrs,sizes): ctypes.memset(ptr,0,n)
 result=s.batch_get_into_multi_buffers(['kimi-probe-multi'],[ptrs],[sizes]);print('MULTI_GET_RETURN',result,flush=True)
 assert buffers[0].raw==b'a'*sizes[0]
 assert buffers[1].raw==b'b'*sizes[1]
print(json.dumps({'status':'PASS','mode':mode,'global_segment_size':0,'sizes':sizes}),flush=True)
