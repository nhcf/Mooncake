"""运行前先构建本地CPU镜像。仅使用Docker隔离network namespace，无生产连接。"""
import datetime,hashlib,json,os,pathlib,subprocess,time,uuid
root=pathlib.Path(__file__).resolve().parent
result=pathlib.Path(os.environ.get('RESULT_ROOT','/tmp'))/('protocol-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]);result.mkdir(parents=True)
image=os.environ.get('IMAGE_TAG','local/mooncake:0.3.7.post2-cpu-nhinfer-test')
client=os.environ.get('CLIENT_IMAGE',image)
master='kimi037-master-'+uuid.uuid4().hex[:8];store=master+'-store'
client_names=[master+'-write',master+'-read']
commands=[]
def run(args,timeout=90):
 try:
  p=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 except subprocess.TimeoutExpired as exc:
  commands.append({'command':args,'exit_code':124})
  output=exc.stdout or b''
  (result/f'{len(commands):02d}.log').write_bytes(output.encode() if isinstance(output,str) else output)
  raise
 commands.append({'command':args,'exit_code':p.returncode})
 (result/f'{len(commands):02d}.log').write_text(p.stdout)
 if p.returncode: raise RuntimeError(p.stdout[-3000:])
 return p.stdout
status='FAIL'
try:
 for tag in [image,client]: run(['docker','image','inspect',tag])
 run(['docker','run','-d','--name',master,'--network','none',image,'bash','/opt/mooncake/bin/master.sh'])
 time.sleep(2)
 run(['docker','run','-d','--name',store,'--network','container:'+master,'-e','POD_IP=127.0.0.1','-e','MOONCAKE_MASTER=127.0.0.1:17788','-e','MOONCAKE_PROTOCOL=tcp','-e','MOONCAKE_DEVICE=','-e','STORE_MEMORY_BYTES=134217728',image,'bash','/opt/mooncake/bin/store.sh'])
 for _ in range(30):
  out=run(['docker','logs',store])
  if 'Store ready' in out: break
  time.sleep(1)
 else: raise RuntimeError('Store未就绪')
 for mode in ['write','read']:
  run(['docker','run','--rm','--name',master+'-'+mode,'--network','container:'+master,'-v',str(root/'probe_client.py')+':/probe.py:ro','--entrypoint',os.environ.get('CLIENT_PYTHON','python3'),client,'-u','/probe.py',mode],timeout=90)
 status='PASS'
finally:
 for name in client_names+[store,master]:
  if subprocess.run(['docker','inspect',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode:
   continue
  subprocess.run(['docker','logs',name],stdout=(result/(name+'.log')).open('w'),stderr=subprocess.STDOUT)
  subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL)
 (result/'result.json').write_text(json.dumps({'status':status,'commands':commands,'probe_sha256':hashlib.sha256((root/'probe_client.py').read_bytes()).hexdigest()},indent=2)+'\n')
 print(result,status,flush=True)
