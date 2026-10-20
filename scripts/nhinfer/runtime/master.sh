#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# 独立0.3.12池控制面；CPU镜像原生入口，无需Conda。
set -euo pipefail
# RPC/HTTP默认17789/19004，Service与Client须保持一致。
MASTER_PORT=${MASTER_PORT:-17789}
MASTER_METRICS_PORT=${MASTER_METRICS_PORT:-19004}
# 先验证DRAM；文件层验收时master与Store同时设置STORE_ENABLE_OFFLOAD=1。
STORE_ENABLE_OFFLOAD=${STORE_ENABLE_OFFLOAD:-0}
[[ "$STORE_ENABLE_OFFLOAD" =~ ^[01]$ ]] || exit 2
# 内存淘汰高水位和单轮比例；不表示GPFS容量比例。
exec mooncake_master --port="$MASTER_PORT" \
 --metrics_port="$MASTER_METRICS_PORT" \
 --allocation_strategy=free_ratio_first \
 --enable_offload="$STORE_ENABLE_OFFLOAD" \
 --default_kv_lease_ttl=1000 \
 --eviction_high_watermark_ratio="${MASTER_EVICTION_HIGH_WATERMARK_RATIO:-0.95}" \
 --eviction_ratio="${MASTER_EVICTION_RATIO:-0.05}" "$@"
