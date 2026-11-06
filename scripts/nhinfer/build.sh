#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# Build committed inputs and verify the resulting CPU image.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ -d .git ]] || { echo 'Build from a normal clone with a .git directory' >&2; exit 2; }
[[ -z $(git status --porcelain --untracked-files=normal) ]] || { echo 'Commit changes before building' >&2; exit 2; }
bash scripts/nhinfer/prepare-deps.sh
printf 'base_ref=v0.3.7.post2\nbase_commit=b6a841dc78c707ec655a563453277d969fb8f38d\nrepository_commit=%s\npackage_version=0.3.7.post2\nbuild_kind=official-wheel\n' "$(git rev-parse HEAD)" > vendor/SOURCE
image_tag=${IMAGE_TAG:-local/mooncake:0.3.7.post2-cpu-nhinfer-g$(git rev-parse --short=12 HEAD)}
docker build \
    --network host \
    --build-arg "GO_DOWNLOAD_BASE=${GO_DOWNLOAD_BASE:-https://mirrors.aliyun.com/golang}" \
    --build-arg "BUILD_JOBS=${BUILD_JOBS:-8}" \
    --file docker/mooncake-nhinfer.Dockerfile \
    --tag "$image_tag" \
    "$@" .
EXPECTED_SOURCE_COMMIT=$(git rev-parse HEAD) bash scripts/nhinfer/verify_image.sh "$image_tag"
docker image inspect --format 'image_id={{.Id}}' "$image_tag"
