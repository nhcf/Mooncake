#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
# 独立0.3.7池；RPC17788和HTTP19003须与Client一致，不连接其他版本的master。
exec mooncake_master \
    --rpc_port="${MASTER_PORT:-17788}" \
    --metrics_port="${MASTER_METRICS_PORT:-19003}" \
    --rpc_address="${MASTER_BIND_ADDRESS:-0.0.0.0}"
