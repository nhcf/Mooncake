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
| [NH-0003](#nh-0003) / [#2818](https://github.com/kvcache-ai/Mooncake/pull/2818) | 本地bucket索引提交后再发布文件副本 | master已公布副本，Store尚不可读，Get返回`INVALID_KEY` |
| [NH-0004](#nh-0004) / [#2077](https://github.com/kvcache-ai/Mooncake/pull/2077) | master重启后重挂segment并重新上报文件副本 | 文件仍在GPFS，master却丢失对象位置 |
| [NH-0005](#nh-0005) / [#3479](https://github.com/kvcache-ai/Mooncake/pull/3479) | 跨轮尾批只装载一次，并对新输入去重 | 同key重复入桶，触发`OBJECT_ALREADY_EXISTS`和整批失败 |
| [NH-0006](#nh-0006) / [#3246](https://github.com/kvcache-ai/Mooncake/pull/3246) | 文件回读缓冲注册远端访问权限与rkey | 远端RDMA READ缺少访问密钥，传输失败 |
| [NH-0007](#nh-0007) / [#3073](https://github.com/kvcache-ai/Mooncake/pull/3073) | 按操作ID接收完成事件，检查实际读取字节数 | io_uring短读被误判成功，返回错误数据 |
| [NH-0008](#nh-0008) / [#3488](https://github.com/kvcache-ai/Mooncake/pull/3488) | 同bucket多key批量提交io_uring读取 | 逐key提交并等待，放大回读开销 |

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

<a id="nh-0003"></a>

### NH-0003：先提交本地索引，再发布副本

修改`mooncake-store/include/storage_backend.h`和`mooncake-store/src/storage_backend.cpp`。

```text
BucketStorageBackend卸载流程归纳：
写bucket数据及元数据
  → 提交本地bucket/key索引
  → 完成回调向master发布副本
发布失败
  → 等待在途读取结束
  → RollbackCommittedBucket回滚索引与文件
```

旧流程在提交索引前发布副本，Get可在两步之间到达。本补丁建立“master可见前，Store已可读”的顺序，并处理发布失败后的回滚。常规回读已通过；竞态放大和发布失败注入未专项验证。

<a id="nh-0004"></a>

### NH-0004：master重启后重报文件副本

master内存元数据丢失后，Store心跳可收到`SEGMENT_NOT_FOUND`。补丁重新挂载内存与文件segment、扫描bucket元数据，并将现存对象重新报告给master。

```cpp
// mooncake-store/src/file_storage.cpp；扫描后的注册摘录。
for (auto& metadata : metadatas) {
    metadata.transport_endpoint = local_rpc_addr_;  // 副本由当前Store提供回读。
}
auto add_object_result = client_->NotifyOffloadSuccess(keys, metadatas);
// 失败由后台任务重试；扫描时重置迭代状态。
```

适配还涉及`client_service.cpp`、`real_client.cpp`及Transfer Engine元数据接口。在`P2PHANDSHAKE`模式下，新增TE元数据发布接口为空操作，保留该模式的原有寻址方式。

历史P5测试只重启master进程，Store进程保持运行。188个对象重新注册，失败数0，后续新Put/Get恢复。故障前指定file-only key的逐字节回读、Pod重建及HA切换需分别验证。

<a id="nh-0005"></a>

### NH-0005：跨轮尾批去重

未达到封桶条件的对象会保留到下一轮。旧实现重复装载尾批，且没有排除本轮输入中的同key。

```cpp
// mooncake-store/src/storage_backend.cpp，GroupOffloadingKeysByBucket；核心摘录。
auto carryover_objects = std::move(ungrouped_offloading_objects);
bool carryover_loaded = false;  // 尾批每轮只装载一次。
// ...本轮输入遍历中跳过已由尾批装载的对象。
if (carryover_objects.find(it->first) != carryover_objects.end()) {
    ++it;
    continue;
}
```

补丁消除该重复分桶来源。更广的重复卸载幂等处理依赖后续状态机，未随本补丁引入。

<a id="nh-0006"></a>

### NH-0006：注册回读缓冲的远端访问权限

仅有文件副本时，Store先读GPFS到本地工作区，再向Client提供数据。远端RDMA READ要求该工作区发布rkey。

```cpp
// mooncake-store/src/file_storage.cpp，RegisterLocalMemory；参数修改摘录。
auto error_code = client_->RegisterLocalMemory(
    client_buffer_allocator_->getBase(), config_.local_buffer_size,
    kWildcardLocation, true, true);  // 原为false,false；允许远端访问并更新注册元数据。
```

#3246修复原路径的`No rkey for MR access`条件。现有字节校验通过，但未用传输计数器排除TCP fallback，不能据此认定所有回读均走RDMA READ。

<a id="nh-0007"></a>

### NH-0007：修复 io_uring 完成事件与短读处理

修改 `mooncake-store/src/uring_file.cpp` 和 `storage_backend.cpp`。每次操作分配单调 `op_id`，仅接收属于该操作的完成事件；按实际读取字节数检查短读，并在检查通过后调整数据指针。

回移保持旧版文件读接口，修复范围为 io_uring 文件路径。历史记录支持顺序应用与代码核对；短读注入尚未专项验证。后续批量读取优化依赖本项正确性修复。

<a id="nh-0008"></a>

### NH-0008：同 bucket 批量提交 io_uring 读取

在 NH-0007 基础上，将同 bucket 的多 key 读取组装成 `ReadDesc`，按队列深度批量提交并收集完成事件。修改 `file_interface.h`、`storage_backend.cpp`、`uring_file.cpp`，新增 `uring_submit.h`。

```cpp
// mooncake-store/src/storage_backend.cpp；省略日志与外围逻辑。
if (!desc.completed) {
    return tl::make_unexpected(ErrorCode::FILE_READ_FAIL);
}
if (desc.bytes_read < batch_plan.min_required) {
    // min_required 包含对齐偏移和目标数据长度。
    return tl::make_unexpected(ErrorCode::FILE_READ_FAIL);
}
```

每 key 使用覆盖完整对齐范围的 SQE，并保留逐对象完成状态与字节数检查。上游 bench/test 依赖较新的 OffsetAllocator 配置，本回移仅纳入生产代码。尚无完整前后性能对照，不将提交次数减少写成实测加速收益。

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
