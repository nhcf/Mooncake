#!/usr/bin/env python3
"""在厂商Pod内测试解包的CPU产物；随机端口/唯一key/64MiB临时Store。"""
import importlib.metadata
import ctypes
import platform
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
import uuid
import urllib.request

if len(sys.argv) > 1 and sys.argv[1] == 'cpu-store':
    # 此子进程由PYTHONPATH选择解包CPU wheel，不导入Torch。
    import threading
    import mooncake.store as module
    stop = threading.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop.set())
    store = module.MooncakeDistributedStore()
    try:
        rc = store.setup(os.environ['POD_IP'], 'P2PHANDSHAKE', 64*1024**2, 0,
                         'rdma', os.environ['MOONCAKE_DEVICE'], os.environ['PROBE_MASTER'],
                         enable_ssd_offload=False)
        Path(os.environ['PROBE_STORE_READY']).write_text(json.dumps({
            'setup': rc, 'module': module.__file__,
            'version': importlib.metadata.version('mooncake-transfer-engine-non-cuda')}))
        if rc != 0:
            raise SystemExit(rc)
        stop.wait()
    finally:
        del store
    raise SystemExit(0)

# 保留厂商运行库加载顺序；不安装、升级或替换Pod里的包。
import torch
import mooncake.store as vendor_module
version = importlib.metadata.version('mooncake-transfer-engine')
if version != '0.3.12.post1+g7d0b16a14.d20260824124122':
    raise SystemExit('Client不是已核验基线: '+version)
runtime = Path(os.environ['CPU_RUNTIME']).resolve()
root = Path(os.environ['PROBE_RESULTS_DIR']).resolve()
root.mkdir(parents=True, exist_ok=False)
report = {'timestamp_utc': datetime.now(timezone.utc).isoformat(), 'libc': platform.libc_ver(), 'client_version': version, 'client_module': vendor_module.__file__,
          'scope': 'same-Pod protocol=rdma; CPU master + CPU Store + vendor pure Client; no transport-counter proof or GPFS', 'tests': []}

def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def batch_probe(store, multi):
    sizes = [65536, 131072]
    values = [os.urandom(n) for n in sizes]
    source = ctypes.create_string_buffer(b''.join(values), sum(sizes))
    target = ctypes.create_string_buffer(sum(sizes))
    src, dst = ctypes.addressof(source), ctypes.addressof(target)
    registered = []
    keys = ['cpu312-batch-'+uuid.uuid4().hex for _ in sizes]
    result = {'api': 'multi_buffers' if multi else 'flat_buffers', 'sizes': sizes}
    report['batch_tests'].append(result)
    try:
        for addr in (src, dst):
            rc = store.register_buffer(addr, sum(sizes))
            if rc != 0:
                raise RuntimeError(f'register_buffer={rc}')
            registered.append(addr)
        if multi:
            spans = [[32768, 32768], [65536, 65536]]
            puts = [[src, src+32768], [src+65536, src+131072]]
            gets = [[dst, dst+32768], [dst+65536, dst+131072]]
            result['put'] = store.batch_put_from_multi_buffers(keys, puts, spans, vendor_module.ReplicateConfig())
        else:
            result['put'] = store.batch_put_from(keys, [src, src+65536], sizes)
        if list(result['put']) != [0, 0]:
            raise RuntimeError('batch put失败: '+str(result))
        result['exists'] = store.batch_is_exist(keys)
        if list(result['exists']) != [1, 1]:
            raise RuntimeError('batch exists失败: '+str(result))
        result['get'] = (store.batch_get_into_multi_buffers(keys, gets, spans) if multi else
                         store.batch_get_into(keys, [dst, dst+65536], sizes))
        if list(result['get']) != sizes:
            raise RuntimeError('batch get长度不符: '+str(result))
        result['equal'] = [ctypes.string_at(dst, sizes[0]) == values[0],
                           ctypes.string_at(dst+sizes[0], sizes[1]) == values[1]]
        if not all(result['equal']):
            raise RuntimeError('batch数据不一致')
        return result
    finally:
        result['remove'] = [store.remove(key, True) for key in keys]
        result['unregister'] = [store.unregister_buffer(addr) for addr in reversed(registered)]

rpc, metrics = port(), port()
while rpc == metrics:
    metrics = port()
env = dict(os.environ)
for key in ('MC_CUSTOM_TOPO_JSON', 'MC_FORCE_TCP', 'MC_FORCE_SHM', 'MOONCAKE_CONFIG_PATH',
            'SGLANG_HICACHE_MOONCAKE_CONFIG_PATH', 'MOONCAKE_STANDALONE_STORAGE'):
    env.pop(key, None)
    os.environ.pop(key, None)
for key, value in {'MOONCAKE_ENABLE_SSD_OFFLOAD': '0', 'MOONCAKE_ENABLE_DFS': '0', 'MC_STORE_MEMCPY': '0'}.items():
    env[key] = value
    os.environ[key] = value
master_env = dict(env, LD_LIBRARY_PATH='')
address = f'127.0.0.1:{rpc}'
report['master'] = address
master = child = store = None
with (root/'master.log').open('w') as ml, (root/'cpu-store.log').open('w') as sl:
    try:
        master = subprocess.Popen([str(runtime/'mooncake/mooncake_master'), f'--port={rpc}',
                                   f'--metrics_port={metrics}', '--default_kv_lease_ttl=1000'],
                                  env=master_env, stdout=ml, stderr=ml)
        for _ in range(100):
            if master.poll() is not None:
                raise RuntimeError('CPU master提前退出')
            try:
                with socket.create_connection(('127.0.0.1', rpc), timeout=.2):
                    break
            except OSError:
                time.sleep(.1)
        else:
            raise RuntimeError('CPU master启动超时')
        ready = root/'cpu-store.json'
        child_env = dict(env, PYTHONPATH=str(runtime), LD_LIBRARY_PATH='', PROBE_MASTER=address,
                         PROBE_STORE_READY=str(ready))
        child = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), 'cpu-store'],
                                 env=child_env, stdout=sl, stderr=sl)
        for _ in range(300):
            if ready.exists():
                report['cpu_store'] = json.loads(ready.read_text())
                if report['cpu_store']['setup'] != 0:
                    raise RuntimeError('CPU Store setup失败')
                break
            if child.poll() is not None:
                raise RuntimeError('CPU Store提前退出')
            time.sleep(.1)
        else:
            raise RuntimeError('CPU Store启动超时')
        with urllib.request.urlopen(f'http://127.0.0.1:{metrics}/get_all_segments', timeout=5) as response:
            report['http_get_all_segments'] = response.status
        store = vendor_module.MooncakeDistributedStore()
        report['setup'] = store.setup(env['POD_IP'], 'P2PHANDSHAKE', 0, 32*1024**2,
                                     'rdma', env['MOONCAKE_DEVICE'], address,
                                     enable_ssd_offload=False)
        if report['setup'] != 0:
            raise RuntimeError('厂商Client setup失败')
        for size in (64*1024, 20*1024**2):
            key = 'cpu312-vendor-' + uuid.uuid4().hex
            value = os.urandom(size)
            item = {'bytes': size, 'put': store.put(key, value)}
            report['tests'].append(item)
            if item['put'] != 0:
                raise RuntimeError('Put失败')
            try:
                item['equal'] = store.get(key) == value
                if not item['equal']:
                    raise RuntimeError('Get内容不一致')
            finally:
                item['remove'] = store.remove(key, True)
            if item['remove'] != 0:
                raise RuntimeError('删除自己的测试key失败')
        report['batch_tests'] = []
        for multi in (False, True):
            item = batch_probe(store, multi)
            if item['remove'] != [0, 0] or item['unregister'] != [0, 0]:
                raise RuntimeError('batch清理失败')
        report['result'] = 'PASS'
    except Exception as exc:
        report['result'] = 'FAIL'
        report['error'] = repr(exc)
        raise
    finally:
        if store is not None:
            del store
        for proc in (child, master):
            if proc is not None and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        (root/'result.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report), flush=True)
