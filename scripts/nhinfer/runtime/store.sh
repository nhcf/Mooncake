#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# 单个独立CPU Store；RDMA设备、锁页能力及GPFS由Pod提供。
set -euo pipefail
export LOCAL_IP=${LOCAL_IP:-${POD_IP:?需注入Store可达IP}}
: "${MOONCAKE_MASTER:?需指定独立0.3.12池host:port}"
: "${STORE_ID:?需指定本Store稳定唯一身份}"
# 每实例共享内存GiB；不包含文件回读工作区和SDK开销。
export STORE_MEMORY_GIB=${STORE_MEMORY_GIB:-8}
# 默认先验DRAM；1启用bucket文件后端，必须与master配置一致。
export STORE_ENABLE_OFFLOAD=${STORE_ENABLE_OFFLOAD:-0}
# STORE_ROOT是新池独立目录，与模型SERVICE_ID缓存key标签无关。
export STORE_ROOT=${STORE_ROOT:-/mnt/si001143bqir/default/mooncakestore-v0312}
export MOONCAKE_DEVICE=${MOONCAKE_DEVICE:-mlx5_bond_2,mlx5_bond_3,mlx5_bond_4,mlx5_bond_5}
export MC_STORE_MEMCPY=0 MOONCAKE_ENABLE_DFS=0
export MOONCAKE_ENABLE_SSD_OFFLOAD=$STORE_ENABLE_OFFLOAD
# 秒；扫描已过期回读缓冲，不清除有效在途对象；该版已包含#2126。
export MOONCAKE_OFFLOAD_CLIENT_BUFFER_GC_INTERVAL_SECONDS=${MOONCAKE_OFFLOAD_CLIENT_BUFFER_GC_INTERVAL_SECONDS:-1}
# 文件回读工作区字节数；默认1280MiB，沿用固定源码，部署内存需额外预留。
export MOONCAKE_OFFLOAD_LOCAL_BUFFER_SIZE_BYTES=${MOONCAKE_OFFLOAD_LOCAL_BUFFER_SIZE_BYTES:-1342177280}
# 文件IO默认POSIX；开启io_uring需专项短读与批量回读验证，布尔值true/false。
export MOONCAKE_OFFLOAD_USE_URING=${MOONCAKE_OFFLOAD_USE_URING:-false}
unset MC_CUSTOM_TOPO_JSON MC_FORCE_TCP MC_FORCE_SHM MOONCAKE_CONFIG_PATH
unset SGLANG_HICACHE_MOONCAKE_CONFIG_PATH MOONCAKE_STANDALONE_STORAGE
exec python3 "$(dirname "$0")/store.py"
