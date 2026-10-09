<div align="center">
  <img src=image/mooncake-icon.png width=44% />
  <h2 align="center">
      A KVCache-centric Disaggregated Architecture for LLM Serving
  </h2>
  <a href="https://www.usenix.org/system/files/fast25-qin.pdf" target="_blank"><strong>Paper</strong></a>
  | <a href="https://www.usenix.org/system/files/fast25_slides-qin.pdf" target="_blank"><strong>Slides</strong></a>
  | <a href="FAST25-release/traces" target="_blank"><strong>Traces</strong></a>
  | <a href="https://arxiv.org/abs/2407.00079" target="_blank"><strong>Technical Report</strong></a>
  | <a href="https://kvcache-ai.github.io/Mooncake/" target="_blank"><strong>Blog</strong></a>
  | <a href="https://join.slack.com/t/mooncake-project/shared_invite/zt-3qx4x35ea-zSSTqTHItHJs9SCoXLOSPA" target="_blank"><strong>Slack</strong></a>
  <br />
  <br />
</div>
<br/>

# Mooncake NanHuInfer

本分支基于官方 `v0.3.10.post2` 持续维护，为 `HiCache + Mooncake + GPFS` 多级缓存方案 提供 Mooncake 修复版本和 CPU master/Store 镜像构建入口。

该方案通过共享 L3 缓存复用模型实例的前缀 KV，减少重复计算。L3 使用 Mooncake Store 内存保存热数据，并将缓存卸载到 GPFS 扩展容量。

本分支集中维护各模型服务在该场景下测试发现的问题修复。每项修复以独立 commit 保存，Dockerfile 直接编译当前源码，使镜像中的修改可追溯。

本分支的官方基线版本与 xSGLang 镜像内的 Mooncake 版本保持一致。当前基线对齐 V5000 厂商提供的 `10.200.53.208/model_test/xsglang:v0.5.10-v4-rc1` 镜像。

| 项目 | 值 |
| --- | --- |
| 维护仓库 | `https://github.com/nhcf/Mooncake` |
| 维护分支 | `v0.3.10.post2-nhinfer-fix` |
| 官方基线 | [v0.3.10.post2](https://github.com/kvcache-ai/Mooncake/tree/v0.3.10.post2)，[e1d6d6f6f49fbbd77b7ee6e5d0c77349f341b3e3](https://github.com/kvcache-ai/Mooncake/commit/e1d6d6f6f49fbbd77b7ee6e5d0c77349f341b3e3) |
| 构建入口 | [docker/mooncake-nhinfer.Dockerfile](docker/mooncake-nhinfer.Dockerfile) |
| 运行能力 | non-CUDA、HTTP、etcd、Store etcd；Linux amd64、Python 3.10 |
| 当前状态 | 已完成本地构建、静态检查及CPU行为验证；目标环境验收未完成，尚未发布 |

## 修改总览

编号标识源码修复或优化。每个修复 commit 标题包含对应的 `[NH-0001]`，并同步更新此表和逐项说明；编号不重排、不复用。

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

在本仓库根目录执行以下命令，构建当前提交的 CPU master/Store 镜像。需要 Docker 和依赖下载网络；源码修改应先提交，因为 Dockerfile 会检查工作区是否干净。构建前将 `{n}` 替换为本次镜像版本号，例如 `1`、`2`。

```bash
git switch v0.3.10.post2-nhinfer-fix
image_tag=local/mooncake:0.3.10.post2-cpu-nhinfer-fix.{n}

docker build -f docker/mooncake-nhinfer.Dockerfile \
  -t "$image_tag" .
```

成功后，镜像保存在本地。构建日志直接显示在终端，该命令不推送镜像或部署服务。

构建默认使用华为云 apt 源、阿里云 pip 源和 Go 官方模块代理。基础镜像先通过 HTTP 源安装 CA 证书，再使用 HTTPS 源安装其余依赖；apt 签名校验保持开启。系统依赖和 Go 工具链安装层可在后续源码修改时复用，Go 模块和 Go 编译结果也保存在构建缓存中。首次构建仍需下载并安装完整依赖。

Dockerfile 自动读取当前 Git commit，并生成 Python 包版本 `0.3.10.post2+nhinfer.g<commit前12位>`，统一记录到镜像内的 `/opt/mooncake-build/SOURCE`。镜像 tag 中的 `{n}` 由构建者指定，不影响上述源码和包版本。

使用普通 Git clone，保留 `.git` 目录；当前入口不支持源码压缩包或关联 worktree。子模块由容器内的 `dependencies.sh` 自动初始化，无需在宿主机单独执行。建议使用无编译残留的工作目录。

### 可选参数

默认使用 Ubuntu 22.04、8 个编译任务。需要调整时，在 `docker build` 中追加 `--build-arg 参数=值`。

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| `BASE_IMAGE` | `ubuntu:22.04` | 构建和运行阶段的基础镜像 |
| `BUILD_JOBS` | `8` | 并行编译数；内存不足时调小 |
| `UBUNTU_MIRROR` | `https://repo.huaweicloud.com/ubuntu` | apt 源 |
| `UBUNTU_BOOTSTRAP_MIRROR` | `http://archive.ubuntu.com/ubuntu` | 首次安装 CA 证书的 apt 源 |
| `PIP_INDEX_URL` | `https://mirrors.aliyun.com/pypi/simple/` | pip 源 |
| `GO_DOWNLOAD_BASE` | `https://go.dev/dl` | Go 工具链下载入口，版本跟随官方依赖脚本 |
| `GOPROXY` | `https://proxy.golang.org,direct` | Go 模块下载代理 |
| `GITHUB_BASE` | `https://github.com/` | 容器内 Git URL 改写和依赖下载代理；不改变宿主机配置 |

编译开启 HTTP、etcd 和 Store etcd，关闭 CUDA、EP 和单元测试。Python 包名为 `mooncake-transfer-engine-non-cuda`，安装内容位于 `/opt/mooncake`，master/client 已加入镜像的 `PATH`。

## 镜像检查与源码身份

Dockerfile 在构建时检查包版本、Store import、动态库依赖和 master CLI。构建成功表示这些检查通过，真实 GPFS、RDMA、恢复和 HA 路径仍需另行验证。

需要查看版本时，在构建使用的 Shell 中执行：

```bash
# 镜像内记录官方基线、实际 commit、包版本、内部提交和子模块版本。
docker run --rm "$image_tag" cat /opt/mooncake-build/SOURCE
# 查看镜像 ID。
docker image inspect --format 'image_id={{.Id}}' "$image_tag"
```

NH 编号从修复提交标题追溯；完整 commit 同时覆盖构建和文档变更。最终运行镜像不包含源码和 Git 元数据。

### 本地验证记录（2026-10-09）

使用干净源码副本（commit `a6c1ef771eaa5e49e9281fa65f6ecf971b7c340d`）和外部指定的当前 Dockerfile 完成构建，未传入源码或包版本参数。生成包版本为 `0.3.10.post2+nhinfer.ga6c1ef771eaa`，镜像 ID 为 `sha256:1f69b8110fdbbd3c23e6635674c57dc848ad3dcaf8a2d9f525b0cade48525522`。包版本、Store 导入、动态库依赖和 master CLI 检查通过；Dockerfile 的 SHA256 为 `9e9be1479b7e59b0e4f041ec614d46352d70146f4e4d680107546e6534a75387`。

前一轮相同源码构建已通过 TCP put/get（1 B至20 MiB）及本地文件 io_uring 回读（4 KiB、5 MiB、20 MiB）测试。简化命令后未重跑这些行为测试；新镜像的17个ELF文件与前一轮及原镜像 `10.200.53.208/model_test/mooncake:0.3.10.post2-cpu-nhinfer-fix.1`（image ID：`sha256:d298164d5bd71e1e10be308d7afa64aa8ea72931bb0bb2fb256bfb7d00824d6a`）逐字节一致。包版本及部分系统包版本存在差异，整个镜像并非逐字节一致。

本轮未执行真实 RDMA、GPFS、P/D 集成、master 重启恢复、带KV的HA及性能测试。提交当前文档和Dockerfile后，构建会自动使用新的commit和包版本；上述镜像仍对应所记录的测试输入。


## 逐项说明

以下代码路径相对本仓库。逐项历史实验结论来自原镜像工程；本分支的本地验证范围见上节，目标环境功能和性能验收仍需另行执行。

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

正式发布时，通过 `BASE_IMAGE` 固定已核验的基础镜像 digest，将构建日志保存在仓库外，并记录构建退出码。当前 apt/pip 等依赖未全部锁定，不承诺逐字节复现。未推送的本地镜像可能没有 RepoDigest；不要用 image ID 代替 RepoDigest。

RDMA 设备、memlock、GPFS 挂载和网络由运行环境提供。回读工作区的大小应结合共享内存、进程开销和 Pod 内存上限配置；现有方案未提供总在途限额、按字节分批或有界等待。

本基线未纳入上游 #2126 的 GC 默认值修正。历史运行库核验建议显式设置 `MOONCAKE_OFFLOAD_CLIENT_BUFFER_GC_INTERVAL_SECONDS=1`，实际发布镜像仍需核验。#2967、#3135 依赖较新卸载状态机，未在本次导入；#3069 所需容量报告 RPC 不存在于此基线。

已编入 etcd HA 不代表带 KV 的故障切换已验证。本基线没有 `--enable_oplog` 参数；历史空池控制面切换结果不能证明旧 KV 在切换后保留。部署参数和完整证据见原工程记录。

## 来源与维护约定

- [官方基线说明](README.upstream.md)：保留原 README 内容。

后续独立修复追加 NH 编号，补充提交沿用所属项编号；回退分配新编号并引用原项。已有编号不重排、不复用。构建与文档维护不占修复编号。

```bash
# 查询当前历史中某项修复的提交；不依赖 README 自引用 commit hash。
git log --oneline --fixed-strings --grep='[NH-0001]'
```
