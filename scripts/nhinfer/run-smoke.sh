#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# 本地CPU/TCP自测；独立网络与临时文件，不连接线上池。
set -euo pipefail
cd "$(dirname "$0")"
IMAGE_TAG=${IMAGE_TAG:-${1:?Usage: run-smoke.sh IMAGE_TAG}}
RESULT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mooncake-smoke-$(date +%Y%m%d-%H%M%S)-XXXX")
TEST_NAME="mc0313-smoke-$$"
trap 'docker rm -f "$TEST_NAME" >/dev/null 2>&1 || true' EXIT
printf '%s\n' "$IMAGE_TAG" > "$RESULT_DIR/image-tag.txt"
docker image inspect "$IMAGE_TAG" --format '{{.Id}}' > "$RESULT_DIR/image-id.txt"
for probe in cpu_smoke carry_regression_probe; do
    args=()
    if [[ $probe == carry_regression_probe ]]; then args=(false 50000); fi
    set +e
    timeout --signal=TERM 240 docker run --rm --init \
        --name "$TEST_NAME" \
        --network none \
        --memory 2g \
        --pids-limit 256 \
        -v "$PWD/$probe.py:/probe.py:ro" \
        -v "$RESULT_DIR:/result" \
        --entrypoint python3 \
        "$IMAGE_TAG" /probe.py "${args[@]}" \
        > "$RESULT_DIR/$probe.log" 2>&1
    rc=$?
    set -e
    printf '%s\n' "$rc" > "$RESULT_DIR/$probe.exit"
    if [[ $rc != 0 ]]; then tail -60 "$RESULT_DIR/$probe.log"; exit "$rc"; fi
    echo "PASS: $probe"
done
python3 - "$RESULT_DIR" <<'PY'
import json,sys
from pathlib import Path
r=Path(sys.argv[1]); v=json.loads((r/'carry16m-false-q50000-result.json').read_text())
assert v['put_success']==100 and not v['put_failures'] and not v['missing'] and not v['read_failures'],v
assert v['file_count']>0,v
print(json.dumps(v,indent=2))
PY
printf 'RESULT_DIR=%s\n' "$RESULT_DIR"
