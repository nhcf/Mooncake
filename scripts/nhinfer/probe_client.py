#!/usr/bin/env python3
"""纯Client写读探针；仅操作本进程生成的唯一key，不启动/停止目标服务。"""
import importlib.metadata
import json
import os
import uuid

# 厂商XPU wheel需要先加载其Torch兼容层；官方CPU镜像保持0。
if os.environ.get('PROBE_IMPORT_TORCH', '0') == '1':
    import torch
from mooncake.store import MooncakeDistributedStore

versions = {}
for package in ('mooncake-transfer-engine', 'mooncake-transfer-engine-non-cuda'):
    try:
        versions[package] = importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        pass
store = MooncakeDistributedStore()
# pure Client：global_segment_size=0；目标池须已有独立Store。
rc = store.setup(os.environ['POD_IP'], 'P2PHANDSHAKE', 0, 32*1024**2,
                 os.environ.get('PROBE_PROTOCOL', 'rdma'),
                 os.environ.get('MOONCAKE_DEVICE', ''), os.environ['MOONCAKE_MASTER'])
report = {'versions': versions, 'master': os.environ['MOONCAKE_MASTER'], 'setup': rc, 'tests': []}
try:
    if rc != 0:
        raise RuntimeError(f'setup={rc}')
    for size in (64*1024, 20*1024**2):
        key = 'cpu312-protocol-' + uuid.uuid4().hex
        value = os.urandom(size)
        test = {'bytes': size, 'put': store.put(key, value)}
        report['tests'].append(test)
        if test['put'] != 0:
            raise RuntimeError(f'put={test["put"]}')
        try:
            test['equal'] = store.get(key) == value
            if not test['equal']:
                raise RuntimeError('get内容不一致')
        finally:
            # 仅删除自己的随机key；Get已同步完成，绕过残余读取租约。
            test['remove'] = store.remove(key, True)
        if test['remove'] != 0:
            raise RuntimeError(f'remove={test["remove"]}')
    report['result'] = 'PASS'
finally:
    print(json.dumps(report, indent=2), flush=True)
    del store
