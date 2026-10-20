"""镜像内CPU/TCP基本行为门禁；不使用线上master，不证明RDMA/GPFS。"""
import json
import os
import socket
import subprocess
import tempfile
import time
import uuid
from mooncake.store import MooncakeDistributedStore

def port():
    with socket.socket() as s:
        s.bind(('', 0))
        return s.getsockname()[1]

rpc, metrics = port(), port()
while metrics == rpc:
    metrics = port()
local_ip = socket.gethostbyname(socket.gethostname())
with tempfile.TemporaryFile(mode='w+') as log:
    master = subprocess.Popen(['mooncake_master', f'--port={rpc}',
                               f'--metrics_port={metrics}', '--default_kv_lease_ttl=1000'], stdout=log, stderr=log)
    try:
        for _ in range(100):
            if master.poll() is not None:
                raise RuntimeError('master提前退出')
            try:
                with socket.create_connection(('127.0.0.1', rpc), timeout=.2):
                    break
            except OSError:
                time.sleep(.1)
        else:
            raise RuntimeError('master启动超时')
        store = MooncakeDistributedStore()
        rc = store.setup(local_ip, 'P2PHANDSHAKE', 64*1024**2, 32*1024**2,
                         'tcp', '', f'127.0.0.1:{rpc}')
        assert rc == 0, ('setup', rc)
        results = []
        for size in (64*1024, 20*1024**2):
            key = 'cpu-candidate-' + uuid.uuid4().hex
            value = os.urandom(size)
            rc = store.put(key, value)
            assert rc == 0, ('put', size, rc)
            assert store.get(key) == value, ('get', size)
            # Get已同步完成；只对本测试独占的随机key绕过残余租约。
            rc = store.remove(key, True)
            assert rc == 0, ('remove', size, rc)
            results.append({'bytes': size, 'put_get_remove': 'PASS'})
        del store
        print(json.dumps({'transport': 'tcp', 'results': results, 'rdma_gpfs': 'NOT_RUN'}))
    finally:
        master.terminate()
        try:
            master.wait(timeout=15)
        except subprocess.TimeoutExpired:
            master.kill()
            master.wait()
        log.seek(0)
        print(log.read())
