#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# Download immutable build inputs and verify their SHA256.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p vendor
if [[ ! -f vendor/mooncake_transfer_engine_non_cuda-0.3.7.post2-cp310-cp310-manylinux_2_17_x86_64.manylinux_2_35_x86_64.whl ]]; then
    curl -fL --retry 3 --connect-timeout 20 --max-time 300 'https://files.pythonhosted.org/packages/84/5f/92cb95fd7327501a37ea604b19f131da04ed6123c05c6fdd94f5fe0e8a81/mooncake_transfer_engine_non_cuda-0.3.7.post2-cp310-cp310-manylinux_2_17_x86_64.manylinux_2_35_x86_64.whl' -o vendor/mooncake_transfer_engine_non_cuda-0.3.7.post2-cp310-cp310-manylinux_2_17_x86_64.manylinux_2_35_x86_64.whl.part
    mv vendor/mooncake_transfer_engine_non_cuda-0.3.7.post2-cp310-cp310-manylinux_2_17_x86_64.manylinux_2_35_x86_64.whl.part vendor/mooncake_transfer_engine_non_cuda-0.3.7.post2-cp310-cp310-manylinux_2_17_x86_64.manylinux_2_35_x86_64.whl
fi
echo '0d04b01c2ff86f2d72630944c576c6bc82d204f8a11ff2527c5ea7063557be2f  vendor/mooncake_transfer_engine_non_cuda-0.3.7.post2-cp310-cp310-manylinux_2_17_x86_64.manylinux_2_35_x86_64.whl' | sha256sum -c -
