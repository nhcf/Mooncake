#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
# 独立Store贡献DRAM；128GiB为初始值，容器限额需覆盖该段及额外开销。
: "${POD_IP:?必须提供Store可达地址}"
: "${MOONCAKE_MASTER:?必须提供独立0.3.7 master的host:port}"
export POD_IP MOONCAKE_MASTER
export STORE_MEMORY_BYTES=${STORE_MEMORY_BYTES:-137438953472}
# 正式网络为rdma；tcp仅用于隔离CPU验证。HCA按实际节点填写。
export MOONCAKE_PROTOCOL=${MOONCAKE_PROTOCOL:-rdma}
export MOONCAKE_DEVICE=${MOONCAKE_DEVICE:-mlx5_bond_2,mlx5_bond_3,mlx5_bond_4,mlx5_bond_5}
exec python3 -u - <<'PY_STORE'
import os,signal,threading
from mooncake.store import MooncakeDistributedStore
size=int(os.environ['STORE_MEMORY_BYTES'])
if size<=0: raise SystemExit('STORE_MEMORY_BYTES必须为正整数字节数')
s=MooncakeDistributedStore()
r=s.setup(os.environ['POD_IP'],'P2PHANDSHAKE',size,0,os.environ['MOONCAKE_PROTOCOL'],os.environ['MOONCAKE_DEVICE'],os.environ['MOONCAKE_MASTER'])
if r: raise SystemExit(f'Store setup失败: {r}')
print('Store ready',size,flush=True)
stop=threading.Event()
for sig in [signal.SIGTERM,signal.SIGINT]: signal.signal(sig,lambda *_:stop.set())
stop.wait()
PY_STORE
