#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# Build from clean committed local source, then run CPU image gates; never push.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
[[ -d .git ]] || { echo 'Use a normal clone with a .git directory' >&2; exit 2; }
[[ -z $(git status --porcelain --untracked-files=normal) ]] || { echo 'Commit source changes before building' >&2; exit 2; }
python3 scripts/nhinfer/verify_source.py
image_tag=${IMAGE_TAG:-local/mooncake:0.3.12.post1-cpu-nhinfer-g$(git rev-parse --short=12 HEAD)}
build_jobs=${BUILD_JOBS:-8}
[[ "$build_jobs" =~ ^[1-9][0-9]*$ ]] || exit 2
docker build \
    --network host \
    --build-arg "GO_DOWNLOAD_BASE=${GO_DOWNLOAD_BASE:-https://mirrors.aliyun.com/golang}" \
    --build-arg "BUILD_JOBS=$build_jobs" \
    --file docker/mooncake-nhinfer.Dockerfile \
    --tag "$image_tag" \
    "$@" \
    .
EXPECTED_SOURCE_COMMIT=$(git rev-parse HEAD) bash scripts/nhinfer/verify_image.sh "$image_tag"
docker image inspect --format 'image_id={{.Id}}' "$image_tag"
