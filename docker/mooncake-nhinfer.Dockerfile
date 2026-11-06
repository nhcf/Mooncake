# syntax=docker/dockerfile:1
# Mooncake 0.3.13 CPU候选；延期任务保留修复。
ARG BASE_IMAGE=ubuntu:22.04@sha256:0e0a0fc6d18feda9db1590da249ac93e8d5abfea8f4c3c0c849ce512b5ef8982

# apt 默认使用华为云，pip 默认使用阿里云；均可按环境覆盖。
# GITHUB_BASE 同时用于子模块 URL 重写和 dependencies.sh 的 GITHUB_PROXY 前缀；
# 默认定向 github.com；可设为内网 git 镜像或代理前缀（如 https://ghproxy.net/https://github.com/）。
ARG UBUNTU_MIRROR=https://repo.huaweicloud.com/ubuntu
ARG UBUNTU_BOOTSTRAP_MIRROR=http://archive.ubuntu.com/ubuntu
ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
ARG GITHUB_BASE=https://github.com/

FROM ${BASE_IMAGE} AS ca_base
ARG UBUNTU_BOOTSTRAP_MIRROR
RUN cp /etc/apt/sources.list /tmp/ubuntu-sources.list \
    && printf 'deb %s jammy main\n' "${UBUNTU_BOOTSTRAP_MIRROR}" > /etc/apt/sources.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates \
    && mv /tmp/ubuntu-sources.list /etc/apt/sources.list \
    && rm -rf /var/lib/apt/lists/*

FROM ca_base AS wheel_builder

ARG UBUNTU_MIRROR
ARG PIP_INDEX_URL
ARG GITHUB_BASE

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    NON_CUDA_BUILD=1 \
    PIP_INDEX_URL=${PIP_INDEX_URL}

# CA 已安装，后续依赖下载使用配置的 HTTPS 镜像。
RUN sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" \
        -e "s|http://security.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" \
        /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates git python3 python3-dev python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# 固定基线的依赖安装位于补丁复制之前，补丁及包版本变化可复用这些层。
COPY dependencies.sh /tmp/mooncake-dependencies.sh
RUN python3 - <<'PYPACKAGES'
import re
import subprocess
from pathlib import Path
script = Path('/tmp/mooncake-dependencies.sh').read_text()
match = re.search(r'^\s*SYSTEM_PACKAGES="([^"$`]+)"', script, re.MULTILINE)
assert match, 'dependencies.sh SYSTEM_PACKAGES format changed'
packages = match.group(1).replace(chr(92) + chr(10), ' ').split()
subprocess.run(['apt-get', 'update'], check=True)
subprocess.run(['apt-get', 'install', '-y', *packages], check=True)
PYPACKAGES
# Ubuntu 22.04 仓库的 patchelf 0.14.3 低于新版 auditwheel 的 0.14.5
# 下限；先安装固定版本，避免在 wheel repair 末尾才失败。
RUN python3 -m pip install --no-cache-dir 'patchelf==0.17.2.1' \
    && test "$(patchelf --version | awk '{print $2}')" = '0.17.2'

# Go 版本跟随官方脚本，工具链安装层不随业务源码变化。
# curl 可协商 HTTP/2；原脚本的 wget 在本机构建网络中下载较慢。
ARG GO_DOWNLOAD_BASE=https://go.dev/dl
RUN apt-get install -y --no-install-recommends curl \
    && go_version="$(sed -n 's/^GOVER=//p' /tmp/mooncake-dependencies.sh)" \
    && test -n "${go_version}" \
    && curl -fSL --retry 3 --connect-timeout 20 \
        "${GO_DOWNLOAD_BASE}/go${go_version}.linux-$(dpkg --print-architecture).tar.gz" \
        -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm /tmp/go.tar.gz \
    && /usr/local/go/bin/go version | grep -F "go${go_version} "
ENV PATH=/usr/local/go/bin:${PATH}

WORKDIR /src/mooncake
COPY . .
RUN test -d .git && test -z "$(git status --porcelain --untracked-files=normal)"
COPY vendor/pybind11.tar.gz /tmp/pybind11.tar.gz
RUN echo '12cd8028f7ef8f3a58c7c770e4a6c6f82c465e33ff4928aaefc41371ee24bd46  /tmp/pybind11.tar.gz' | sha256sum -c - \
    && tar -xzf /tmp/pybind11.tar.gz --strip-components=1 -C extern/pybind11

RUN python3 scripts/nhinfer/verify_source.py
RUN mkdir -p /build-meta && { \
        echo 'base_ref=v0.3.13'; \
        echo 'base_commit=e5598b0992cc258b06d22f24d875480e8931a28e'; \
        echo "source_commit=$(git rev-parse HEAD)"; \
        echo "package_version=0.3.13+nhinfer.g$(git rev-parse --short=12 HEAD)"; \
    } > /build-meta/SOURCE \
    && package_version="$(sed -n 's/^package_version=//p' /build-meta/SOURCE)" \
    && sed -i "s/version = \"0.3.13\"/version = \"${package_version}\"/" mooncake-wheel/pyproject.toml

# 与官方 v0.3.13 non-CUDA 发布工作流保持同一组选项：保留 HTTP/etcd
# 编译能力以及 Store 的 etcd HA 能力，但不链接 CUDA、Torch 或模型设备运行时。
# YLT版本与FindYLT.cmake一致；固定归档避免CMake重复联网下载。
COPY vendor/yalantinglibs.tar.gz /tmp/yalantinglibs.tar.gz
RUN echo '2a4b93c256c09fa84e1507bf4d5b33571ee47a4e2c65316ca255680ad3cdfc1e  /tmp/yalantinglibs.tar.gz' | sha256sum -c - \
    && mkdir -p /opt/yalantinglibs \
    && tar -xzf /tmp/yalantinglibs.tar.gz --strip-components=1 -C /opt/yalantinglibs \
    && rm /tmp/yalantinglibs.tar.gz
ARG BUILD_JOBS=8
ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY}
# 源码变化后复用 Go 模块及编译缓存，Go 按 go.sum 校验模块内容。
RUN --mount=type=cache,id=mooncake-nhinfer-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=mooncake-nhinfer-go-build,target=/root/.cache/go-build,sharing=locked \
    PATH="/usr/local/go/bin:${PATH}" cmake -S . -B build -G Ninja \
        -DFETCHCONTENT_SOURCE_DIR_YALANTINGLIBS=/opt/yalantinglibs \
        -DUSE_HTTP=ON \
        -DUSE_ETCD=ON \
        -DUSE_CUDA=OFF \
        -DWITH_EP=OFF \
        -DSTORE_USE_ETCD=ON \
        -DBUILD_UNIT_TESTS=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DPython3_EXECUTABLE=/usr/bin/python3 \
    && PATH="/usr/local/go/bin:${PATH}" cmake --build build --parallel "${BUILD_JOBS}"

# 生成与官方 non-CUDA wheel 相同布局的修复产物。local version 让运行时可以直接
# 区分补丁包和未修改的 0.3.13，Store RPC定义保持0.3.13基线。
# pip 源由 ENV PIP_INDEX_URL 统一控制，build_wheel.sh 内部的调用同样生效。
RUN PYTHON_VERSION=3.10 OUTPUT_DIR=dist ./scripts/build_wheel.sh

RUN cp scripts/nhinfer/backports.json /build-meta/backports.json

# 保存实际Go依赖解析和完整源码diff，涵盖go mod tidy产生的调整。
RUN git diff --binary > /build-meta/source.diff \
    && echo 'extern/pybind11 58c382a8e3d7081364d2f5c62e7f429f0412743b archive_sha256=12cd8028f7ef8f3a58c7c770e4a6c6f82c465e33ff4928aaefc41371ee24bd46' > /build-meta/SUBMODULES \
    && cp mooncake-common/etcd/go.mod /build-meta/etcd.go.mod \
    && cp mooncake-common/etcd/go.sum /build-meta/etcd.go.sum \
    && go version -m build/mooncake-common/etcd/libetcd_wrapper.so > /build-meta/etcd-go-build.txt

FROM ca_base AS final

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONPATH=/opt/mooncake \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH=/opt/mooncake/mooncake:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# CPU Store 的运行依赖。RDMA 设备节点、memlock、GPFS 挂载和网络由 Pod 提供。
ARG UBUNTU_MIRROR
RUN sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" \
        -e "s|http://security.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" \
        /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 ca-certificates openssl libstdc++6 libcurl4 libnuma1 \
        libibverbs1 ibverbs-providers librdmacm1 rdma-core liburing2 libyaml-0-2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=wheel_builder /src/mooncake/mooncake-wheel/dist/*.whl /tmp/mooncake.whl
COPY --from=wheel_builder /build-meta /opt/mooncake-build
COPY scripts/nhinfer/cpu_smoke.py /opt/mooncake-build/cpu_smoke.py

# 按 wheel 原布局解包到固定目录，保留 auditwheel 生成的相邻 .libs；不安装
# aiohttp/requests 等本轮 master/Store 原生入口不使用的 Python 辅助依赖。
RUN python3 - <<'PY'
import zipfile
from pathlib import Path

wheel = Path('/tmp/mooncake.whl')
with zipfile.ZipFile(wheel) as archive:
    archive.extractall('/opt/mooncake')
for name in ('mooncake_master', 'mooncake_client'):
    Path('/opt/mooncake/mooncake', name).chmod(0o755)
wheel.unlink()
PY

RUN python3 - <<'PY'
import importlib.metadata
import os
import subprocess
from pathlib import Path

from mooncake.store import MooncakeDistributedStore  # noqa: F401

version = importlib.metadata.version('mooncake-transfer-engine-non-cuda')
meta = dict(line.split('=', 1) for line in Path('/opt/mooncake-build/SOURCE').read_text().splitlines())
assert version == meta['package_version'], (version, meta)
for name in ('mooncake_master', 'mooncake_client', 'store.so', 'engine.so'):
    result = subprocess.run(
        ['ldd', str(Path('/opt/mooncake/mooncake', name))],
        check=True,
        text=True,
        capture_output=True,
    )
    output = result.stdout.lower()
    assert 'not found' not in output, result.stdout
    assert not any(lib in output for lib in ('libcuda', 'libtorch', 'libxpu')), result.stdout
print(f'PASS: patched Mooncake CPU runtime {version}')
PY
RUN ! grep -aFq 'sizes[i] <= kMaxSliceSize' /opt/mooncake/mooncake/store.so
# #3488 后 BatchLoad 走 UringFile::batch_read 批量提交；符号名出现在 store.so 中。
RUN grep -aFq 'batch_read' /opt/mooncake/mooncake/store.so

LABEL org.opencontainers.image.title="Mooncake nhinfer CPU master and Store" \
      org.opencontainers.image.source="https://github.com/nhcf/Mooncake"
COPY scripts/nhinfer/runtime /opt/mooncake/bin
WORKDIR /opt/mooncake
CMD ["/bin/bash"]
