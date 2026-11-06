#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# Verify the official wheel and isolated master/Store TCP behavior.
set -euo pipefail
cd "$(dirname "$0")/../.."
image_tag=${1:?Usage: verify_image.sh IMAGE_TAG}
docker run --rm --network none -i --env "EXPECTED_SOURCE_COMMIT=${EXPECTED_SOURCE_COMMIT:-}" --entrypoint python3 "$image_tag" - <<'PY_CHECK'
import importlib.metadata, json, os, subprocess
from pathlib import Path
from mooncake.store import MooncakeDistributedStore
meta=dict(line.split('=',1) for line in Path('/opt/mooncake-build/SOURCE').read_text().splitlines())
assert meta['build_kind']=='official-wheel'
assert meta['base_commit']=='b6a841dc78c707ec655a563453277d969fb8f38d'
if os.environ['EXPECTED_SOURCE_COMMIT']:
    assert meta['repository_commit']==os.environ['EXPECTED_SOURCE_COMMIT']
assert importlib.metadata.version('mooncake-transfer-engine-non-cuda')=='0.3.7.post2'
import mooncake
root=Path(mooncake.__file__).parent
for name in ('mooncake_master','store.so','engine.so'):
    text=subprocess.check_output(['ldd',str(root/name)],text=True).lower()
    assert not any(x in text for x in ('not found','libcuda','libtorch','libxpu')),text
print('PASS official wheel identity and CPU dependencies')
PY_CHECK
IMAGE_TAG="$image_tag" python3 scripts/nhinfer/verify_cpu.py
