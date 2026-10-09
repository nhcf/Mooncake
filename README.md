# Mooncake nhinfer

本分支在官方 `v0.3.10.post2` 上维护内部修复，提供 CPU master/Store 镜像构建入口。修复直接提交到源码，Dockerfile 编译当前检出的提交，不再下载官方源码后应用外部 patch。

| 项目 | 值 |
| --- | --- |
| 维护仓库 | `https://github.com/nhcf/Mooncake` |
| 维护分支 | `v0.3.10.post2-nhinfer-fix` |
| 官方基线 | `v0.3.10.post2`，`e1d6d6f6f49fbbd77b7ee6e5d0c77349f341b3e3` |
| 构建入口 | [docker/mooncake-nhinfer.Dockerfile](docker/mooncake-nhinfer.Dockerfile) |
| 运行能力 | non-CUDA、HTTP、etcd、Store etcd；Linux amd64、Python 3.10 |
| 当前状态 | 本地源码维护；尚未通过此入口完成新镜像构建与运行验收，尚未发布 |

## 修改总览

编号标识源码修复或优化。构建、文档准备提交不编号。每个修复 commit 标题包含对应的 `[NH-0001]`，并同步更新此表和逐项说明；编号不重排、不复用。

| 编号 / 上游 PR | 修改动作 | 未修改的影响 |
| --- | --- | --- |
| [NH-0001](#nh-0001) / [#1734](https://github.com/kvcache-ai/Mooncake/pull/1734) | 阻塞文件回读投递到工作线程 | 慢回读占满RPC线程，拖延心跳与新请求 |
| [NH-0002](#nh-0002) / [#2165](https://github.com/kvcache-ai/Mooncake/pull/2165) | 单对象回读上限由4 MiB断言改为实际缓冲容量检查 | 大对象回读触发断言，Store退出 |

## 构建方法

在普通 Git clone 的根目录构建，要求 `.git` 为目录且工作区干净。Dockerfile 使用 Git 元数据检查 `SOURCE_COMMIT`，旧版 `dependencies.sh` 也需要 Git 初始化子模块，因此不支持直接使用 GitHub 源码压缩包或关联 worktree。Git 元数据只存在于构建阶段，最终镜像仅复制 wheel 和源码身份记录。

首次准备子模块需要访问其 Git 源；构建还需要 Ubuntu、pip、Go 和其他依赖下载通道。建议使用专用干净 clone，避免把本地忽略文件或编译残留带入上下文。

以下命令在已检出目标提交的仓库根目录执行，只构建本地镜像。基础镜像默认 tag 可变；正式发布前将 `BASE_IMAGE` 替换为已核验的 `ubuntu:22.04@sha256:...`。

```bash
set -euo pipefail
git submodule update --init --recursive
test -z "$(git status --porcelain --untracked-files=normal)"
source_commit=$(git rev-parse HEAD)
source_short=$(git rev-parse --short=12 HEAD)
package_version="0.3.10.post2+nhinfer.g${source_short}"
image_tag="local/mooncake:0.3.10.post2-nhinfer-g${source_short}"
base_image="${BASE_IMAGE:-ubuntu:22.04}"
# 日志写到仓库外，避免污染构建上下文。
result_dir=$(mktemp -d /tmp/mooncake-nhinfer-build-XXXXXX)
set +e
docker build --platform linux/amd64 \
  --build-arg "SOURCE_COMMIT=${source_commit}" \
  --build-arg "PACKAGE_VERSION=${package_version}" \
  --build-arg "BASE_IMAGE=${base_image}" \
  --build-arg BUILD_JOBS=8 \
  -f docker/mooncake-nhinfer.Dockerfile \
  -t "$image_tag" . >"$result_dir/build.log" 2>&1
build_rc=$?
set -e
printf '%s\n' "$build_rc" >"$result_dir/build.exit-code"
printf 'results=%s\n' "$result_dir"
if [ "$build_rc" -ne 0 ]; then
  tail -n 80 "$result_dir/build.log"
  exit "$build_rc"
fi
docker image inspect "$image_tag" >"$result_dir/image-identity.json"
```

| 构建参数 | 默认值或要求 | 用途 |
| --- | --- | --- |
| `SOURCE_COMMIT` | 必填，完整 Git commit | 必须等于构建上下文的 HEAD，写入 OCI revision |
| `PACKAGE_VERSION` | 必填，`0.3.10.post2+nhinfer.<后缀>` | 区分官方包及内部源码版本；本地构建使用 `g<12位commit>` 后缀 |
| `BASE_IMAGE` | `ubuntu:22.04` | 构建与运行阶段使用同一基底；发布时固定 digest |
| `BUILD_JOBS` | `8` | CMake 并行编译数 |
| `UBUNTU_MIRROR` | `https://mirrors.aliyun.com/ubuntu` | apt 源 |
| `PIP_INDEX_URL` | `https://mirrors.aliyun.com/pypi/simple/` | pip 源 |
| `GITHUB_BASE` | `https://github.com/` | 容器内 Git URL 改写及依赖脚本代理前缀；不改变宿主机 Git 配置 |

保留的 CMake 选项为 `USE_HTTP=ON`、`USE_ETCD=ON`、`USE_CUDA=OFF`、`WITH_EP=OFF`、`STORE_USE_ETCD=ON`、`BUILD_UNIT_TESTS=OFF`。包名为 `mooncake-transfer-engine-non-cuda`，包解包到 `/opt/mooncake`，master/client 位于 `/opt/mooncake/mooncake`。基础镜像及 apt/pip 等依赖尚未全部锁定，不承诺逐字节复现。

## 镜像检查与源码身份

Dockerfile 检查包版本、Store import、ELF 依赖闭合与非 CUDA 依赖要求，以及 master CLI。构建不执行单元测试，也不验证真实 GPFS、RDMA、恢复和 HA 路径。无需独立验证脚本。

构建记录写入 `/opt/mooncake-build/SOURCE`，包含官方基线、实际 commit、包版本、内部提交标题及子模块提交。NH 编号可从内部修复提交标题追溯。完整 commit 同时覆盖不编号的构建和文档变更。

构建完成后，在上述 Shell 中手动核对：

```bash
test "$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image_tag")" = "$source_commit"
docker run --rm "$image_tag" cat /opt/mooncake-build/SOURCE
docker run --rm "$image_tag" python3 -c \
  'from mooncake.store import MooncakeDistributedStore; import importlib.metadata; print(importlib.metadata.version("mooncake-transfer-engine-non-cuda"))'
docker run --rm "$image_tag" mooncake_master --version
docker image inspect --format 'image_id={{.Id}} repo_digests={{json .RepoDigests}}' "$image_tag"
```

本地未推送镜像可能没有 RepoDigest；image ID 与 RepoDigest 分开记录。

## 逐项说明

以下代码路径相对本仓库。历史实验结论来自原镜像工程，不是本分支新镜像的验收结果。本次导入仅验证 patch 可应用及源码一致性，功能和性能验证仍需在目标环境执行。

<a id="nh-0001"></a>

### NH-0001：隔离阻塞回读与RPC线程

修改`mooncake-store/include/real_client.h`和`mooncake-store/src/real_client.cpp`。将offload Get及相关dummy helper改为协程，通过`coro_io::post`执行阻塞工作。

```cpp
// mooncake-store/src/real_client.cpp；关键调用，省略lambda主体。
auto try_result = co_await coro_io::post([this, s]() {
    // 在线程池执行原阻塞工作；s保存跨异步等待所需状态。
    // ...
});
```

本地按#1734语义适配0.3.10函数上下文，保留RPC请求与响应类型。异步等待期间继续持有调用数据与必要资源，避免提前销毁缓冲或锁。

目标是让RPC线程继续处理心跳。持续回读与心跳压力尚未形成独立A/B结果。

<a id="nh-0002"></a>

### NH-0002：允许大对象文件回读

[Issue #2156](https://github.com/kvcache-ai/Mooncake/issues/2156)对应`FileStorage::AllocateBatch`的错误断言。历史DSV4测试回读20 MiB C128 state时，原版因超过4 MiB退出。

```cpp
// mooncake-store/src/file_storage.cpp，AllocateBatch；补丁核心摘录。
if (keys.size() != sizes.size()) {
    return tl::make_unexpected(ErrorCode::INVALID_PARAMS);
}
// ...逐对象检查，替代assert(sizes[i] <= kMaxSliceSize)。
if (sizes[i] < 0 || sizes[i] > config_.local_buffer_size) {
    // ...记录非法大小。
    return tl::make_unexpected(ErrorCode::INVALID_PARAMS);
}
```

上限对应单对象，并允许大小为0。该检查没有实现整批按字节切分、全局在途限额或等待空闲工作区；多个合法对象合计仍可触发`BUFFER_OVERFLOW`。

## 发布记录与运行限制

本分支尚未发布新镜像或发布 tag。正式发布可使用 `v0.3.10.post2-nhinfer-fix.1` 等固定 tag，发布记录同时保存完整 commit、包版本、基础镜像 digest、构建和验证日志、image ID 及推送后的 RepoDigest。发布 tag、包版本和镜像 tag 分别记录，不从可变分支名推断产物内容。

RDMA 设备、memlock、GPFS 挂载和网络由运行环境提供。回读工作区的大小应结合共享内存、进程开销和 Pod 内存上限配置；现有方案未提供总在途限额、按字节分批或有界等待。

本基线未纳入上游 #2126 的 GC 默认值修正。历史运行库核验建议显式设置 `MOONCAKE_OFFLOAD_CLIENT_BUFFER_GC_INTERVAL_SECONDS=1`，实际发布镜像仍需核验。#2967、#3135 依赖较新卸载状态机，未在本次导入；#3069 所需容量报告 RPC 不存在于此基线。

已编入 etcd HA 不代表带 KV 的故障切换已验证。本基线没有 `--enable_oplog` 参数；历史空池控制面切换结果不能证明旧 KV 在切换后保留。部署参数和完整证据见原工程记录。

## 来源与维护约定

- [官方基线说明](README.upstream.md)：保留原 README 内容。
- [原镜像工程说明](/data/zhuyilin/git-code/survey/llm-infer-survey-private/dynamo/v5000/test-l3/output/mooncake_image/build/README.md)：现有补丁机制、原镜像身份和实验边界。该链接是内部本地路径，其他机器需使用 survey 仓库对应目录。
- 历史材料相对 survey 仓库的位置：`dynamo/v5000/test-l3/output/mooncake_image/build/`。原 patch 的 SHA256 写入相应提交描述，源码不再依赖该目录构建。

后续独立修复追加 NH 编号，补充提交沿用所属项编号；回退分配新编号并引用原项。已有编号不重排、不复用。构建与文档维护不占修复编号。

```bash
# 查询当前历史中某项修复的提交；不依赖 README 自引用 commit hash。
git log --oneline --fixed-strings --grep='[NH-0001]'
```
