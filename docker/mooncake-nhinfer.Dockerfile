# syntax=docker/dockerfile:1
# Build from a clean local checkout; see README.md for source identity arguments.
ARG BASE_IMAGE=ubuntu:22.04

# 网络源配置：默认值均为国内可达镜像，可按环境覆盖。
# GITHUB_BASE 同时用于子模块 URL 重写和 dependencies.sh 的 GITHUB_PROXY 前缀；
# 默认定向 github.com；可设为内网 git 镜像或代理前缀（如 https://ghproxy.net/https://github.com/）。
ARG UBUNTU_MIRROR=https://mirrors.aliyun.com/ubuntu
ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
ARG GITHUB_BASE=https://github.com/

FROM ${BASE_IMAGE} AS wheel_builder

# SOURCE_COMMIT and PACKAGE_VERSION are required; no branch is fetched here.
ARG SOURCE_COMMIT
ARG PACKAGE_VERSION
ARG UBUNTU_MIRROR
ARG PIP_INDEX_URL
ARG GITHUB_BASE

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    NON_CUDA_BUILD=1 \
    PIP_INDEX_URL=${PIP_INDEX_URL}

# apt 镜像替换必须在第一个 apt-get 之前，保证全构建期 apt 都走镜像。
RUN sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" \
        -e "s|http://security.ubuntu.com/ubuntu|${UBUNTU_MIRROR}|g" \
        /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates git python3 python3-dev python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Git metadata is needed by dependencies.sh and source identity checks.
# Use a normal clone with a .git directory, not a linked worktree.
WORKDIR /src/mooncake
COPY . .
RUN test -d .git \
    && test -n "${SOURCE_COMMIT}" \
    && test "$(git rev-parse HEAD)" = "${SOURCE_COMMIT}" \
    && test -z "$(git status --porcelain --untracked-files=normal)" \
    && test -n "${PACKAGE_VERSION}" \
    && if [ "${GITHUB_BASE}" != "https://github.com/" ]; then \
        git config --global url."${GITHUB_BASE}".insteadOf "https://github.com/"; \
    fi

ENV GITHUB_PROXY=${GITHUB_BASE%/}
RUN bash dependencies.sh -y

# Capture the committed source identity before the wheel build changes files.
RUN mkdir -p /build-meta \
    && { \
        echo 'base_ref=v0.3.10.post2'; \
        echo 'base_commit=e1d6d6f6f49fbbd77b7ee6e5d0c77349f341b3e3'; \
        echo "source_commit=${SOURCE_COMMIT}"; \
        echo "package_version=${PACKAGE_VERSION}"; \
        git log --reverse --format='%s' e1d6d6f6f49fbbd77b7ee6e5d0c77349f341b3e3..HEAD; \
        git submodule status --recursive; \
    } > /build-meta/SOURCE
RUN PACKAGE_VERSION="${PACKAGE_VERSION}" python3 - <<'PYVERSION'
import os
import re
from pathlib import Path
version = os.environ['PACKAGE_VERSION']
assert re.fullmatch(r'0\.3\.10\.post2\+nhinfer\.[a-z0-9.]+', version), version
path = Path('mooncake-wheel/pyproject.toml')
text = path.read_text()
assert text.count('version = "0.3.10.post2"') == 1
path.write_text(text.replace('version = "0.3.10.post2"', f'version = "{version}"'))
PYVERSION

# 与官方 v0.3.10.post2 non-CUDA 发布工作流保持同一组选项：保留 HTTP/etcd
# 编译能力以及 Store 的 etcd HA 能力，但不链接 CUDA、Torch 或模型设备运行时。
ARG BUILD_JOBS=8
RUN PATH="/usr/local/go/bin:${PATH}" cmake -S . -B build -G Ninja \
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
# 区分补丁包和未修改的 0.3.10.post2，Store 内部 RPC 版本仍保持 0.3.10 基线。
# Ubuntu 22.04 仓库的 patchelf 0.14.3 低于新版 auditwheel 的 0.14.5
# 下限；先安装固定版本，避免在 wheel repair 末尾才失败。
# pip 源由 ENV PIP_INDEX_URL 统一控制，build_wheel.sh 内部的 pip 调用同样生效。
RUN python3 -m pip install --no-cache-dir 'patchelf==0.17.2.1' \
    && test "$(patchelf --version | awk '{print $2}')" = '0.17.2'
RUN PYTHON_VERSION=3.10 OUTPUT_DIR=dist ./scripts/build_wheel.sh

FROM ${BASE_IMAGE} AS final

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
        python3 ca-certificates libstdc++6 libcurl4 libnuma1 \
        libibverbs1 ibverbs-providers librdmacm1 rdma-core liburing2 libyaml-0-2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=wheel_builder /src/mooncake/mooncake-wheel/dist/*.whl /tmp/mooncake.whl
COPY --from=wheel_builder /build-meta/SOURCE /opt/mooncake-build/SOURCE

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

# 版本相关 ARG 推迟到验收阶段声明，保持前面运行环境层的缓存稳定。
ARG SOURCE_COMMIT
ARG PACKAGE_VERSION

# 镜像构建阶段只验收可加载性、依赖闭合和包版本。RDMA、GPFS 与真实 2P2D
# 数据路径必须在目标 K8s 环境中另行验收。
RUN EXPECTED_VERSION="${PACKAGE_VERSION}" python3 - <<'PY'
import importlib.metadata
import os
import subprocess
from pathlib import Path

from mooncake.store import MooncakeDistributedStore  # noqa: F401

version = importlib.metadata.version('mooncake-transfer-engine-non-cuda')
assert version == os.environ['EXPECTED_VERSION'], (version, os.environ['EXPECTED_VERSION'])
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
# gflags --help returns 1 on this baseline; --version checks CLI loading.
RUN mooncake_master --version | grep -Fxq mooncake_master

LABEL org.opencontainers.image.title="Mooncake nhinfer CPU master and Store" \
      org.opencontainers.image.version="${PACKAGE_VERSION}" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.source="https://github.com/nhcf/Mooncake" \
      ai.nhinfer.mooncake.base-revision="e1d6d6f6f49fbbd77b7ee6e5d0c77349f341b3e3"

WORKDIR /opt/mooncake
CMD ["/bin/bash"]
