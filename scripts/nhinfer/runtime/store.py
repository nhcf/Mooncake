"""CPU Store：DRAM与GPFS验证共用入口；不删除数据文件。"""
import fcntl
import ipaddress
import os
from pathlib import Path
import re
import signal
import subprocess
import threading
from mooncake.store import MooncakeDistributedStore

e = os.environ
ipaddress.ip_address(e['LOCAL_IP'])
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', e['STORE_ID']):
    raise SystemExit('STORE_ID非法')
if e['STORE_ENABLE_OFFLOAD'] not in ('0', '1'):
    raise SystemExit('STORE_ENABLE_OFFLOAD只允许0/1')
size = int(e['STORE_MEMORY_GIB']) * 1024**3
if size <= 0:
    raise SystemExit('STORE_MEMORY_GIB必须为正整数')
offload = e['STORE_ENABLE_OFFLOAD'] == '1'
directory = Path(e['STORE_ROOT']) / e['STORE_ID'] if offload else Path('/run/mooncake') / e['STORE_ID']
directory.mkdir(parents=True, exist_ok=True)
if offload:
    if subprocess.check_output(['stat','-f','-c','%T',str(directory)], text=True).strip() != 'gpfs':
        raise SystemExit('文件层必须使用实际GPFS挂载')
    e['MOONCAKE_OFFLOAD_STORAGE_BACKEND_DESCRIPTOR'] = 'bucket_storage_backend'
    e['MOONCAKE_OFFLOAD_FILE_STORAGE_PATH'] = str(directory)
else:
    e.pop('MOONCAKE_OFFLOAD_STORAGE_BACKEND_DESCRIPTOR', None)
    e.pop('MOONCAKE_OFFLOAD_FILE_STORAGE_PATH', None)
stop = threading.Event()
for sig in (signal.SIGTERM, signal.SIGINT):
    signal.signal(sig, lambda *_: stop.set())
with (directory / '.store-owner.lock').open('a+') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    store = MooncakeDistributedStore()
    try:
        rc = store.setup(e['LOCAL_IP'], 'P2PHANDSHAKE', size, 0, 'rdma',
                         e['MOONCAKE_DEVICE'], e['MOONCAKE_MASTER'],
                         enable_ssd_offload=offload,
                         ssd_offload_path=str(directory) if offload else '')
        if rc != 0:
            raise SystemExit(f'Store setup失败: {rc}')
        print(f'STORE_READY endpoint={store.get_hostname()} bytes={size} file={offload}', flush=True)
        stop.wait()
    finally:
        close = getattr(store, 'close', None)
        if close is not None:
            close()
        del store
