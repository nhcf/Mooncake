#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# Verify a locally built image; CPU smoke only touches its own temporary master.
set -euo pipefail
image_tag=${1:?Usage: verify_image.sh IMAGE_TAG}
# Use -i to pass the verification program through stdin.
docker run --rm -i --network none --env "EXPECTED_SOURCE_COMMIT=${EXPECTED_SOURCE_COMMIT:-}" --entrypoint python3 "$image_tag" <<'PY'
from pathlib import Path
import importlib.metadata
import os
import subprocess
meta = dict(line.split('=', 1) for line in Path('/opt/mooncake-build/SOURCE').read_text().splitlines() if '=' in line)
if os.environ['EXPECTED_SOURCE_COMMIT']:
    assert meta['source_commit'] == os.environ['EXPECTED_SOURCE_COMMIT']
assert meta['base_commit'] == '6041a609a8c3af35e778f70db344f145c2914980'
assert meta['package_version'] == '0.3.12.post1+nhinfer.g' + meta['source_commit'][:12]
assert importlib.metadata.version('mooncake-transfer-engine-non-cuda') == meta['package_version']
from mooncake.store import MooncakeDistributedStore
for name in ['mooncake_master', 'mooncake_client', 'store.so', 'engine.so']:
    text = subprocess.check_output(['ldd', '/opt/mooncake/mooncake/' + name], text=True).lower()
    assert not any(word in text for word in ['not found', 'libcuda', 'libtorch', 'libxpu']), text
text = subprocess.check_output(['mooncake_master', '--version'], text=True)
assert 'mooncake_master version ' + meta['package_version'] in text
print('PASS image identity, import, ELF dependencies and master CLI')
PY
docker run --rm --shm-size=256m --entrypoint python3 "$image_tag" /opt/mooncake-build/cpu_smoke.py
