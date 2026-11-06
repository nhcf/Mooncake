#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2026 (C) Zhejiang Lab. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
# Download immutable build inputs and verify their SHA256.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p vendor
if [[ ! -f vendor/pybind11.tar.gz ]]; then
    curl -fL --retry 3 --connect-timeout 20 --max-time 300 'https://codeload.github.com/pybind/pybind11/tar.gz/58c382a8e3d7081364d2f5c62e7f429f0412743b' -o vendor/pybind11.tar.gz.part
    mv vendor/pybind11.tar.gz.part vendor/pybind11.tar.gz
fi
echo '12cd8028f7ef8f3a58c7c770e4a6c6f82c465e33ff4928aaefc41371ee24bd46  vendor/pybind11.tar.gz' | sha256sum -c -
if [[ ! -f vendor/yalantinglibs.tar.gz ]]; then
    curl -fL --retry 3 --connect-timeout 20 --max-time 300 'https://codeload.github.com/alibaba/yalantinglibs/tar.gz/7801bc9ad9021781f15217552214e325a1cf7373' -o vendor/yalantinglibs.tar.gz.part
    mv vendor/yalantinglibs.tar.gz.part vendor/yalantinglibs.tar.gz
fi
echo '2a4b93c256c09fa84e1507bf4d5b33571ee47a4e2c65316ca255680ad3cdfc1e  vendor/yalantinglibs.tar.gz' | sha256sum -c -
