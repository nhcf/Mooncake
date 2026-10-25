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

本分支基于官方 `v0.3.12.post1` 持续维护，为 `HiCache + Mooncake + GPFS` 多级缓存方案提供 Mooncake 修复版本、CPU master/Store 镜像构建和运行入口。

该方案通过共享 L3 缓存复用模型实例的前缀 KV。Mooncake Store 内存保存热数据，bucket 文件后端通过 GPFS 扩展缓存容量。本分支集中维护重复分桶、文件回读、卸载任务错误处理和 master 恢复相关修复；每项修改以独立 commit 保存，Dockerfile 直接编译当前源码。

| 项目 | 值 |
| --- | --- |
| 维护仓库 | [nhcf/Mooncake](https://github.com/nhcf/Mooncake) |
| 维护分支 | `v0.3.12.post1-nhinfer-fix` |
| 官方基线 | [v0.3.12.post1](https://github.com/kvcache-ai/Mooncake/tree/v0.3.12.post1)，commit `6041a609a8c3af35e778f70db344f145c2914980` |
| 构建入口 | [build.sh](scripts/nhinfer/build.sh)、[Dockerfile](docker/mooncake-nhinfer.Dockerfile) |
| 运行能力 | non-CUDA、HTTP、etcd、Store etcd；Linux amd64、Python 3.10 |
| 验证状态 | 六补丁仓库构建已通过；八补丁源码已与已发布镜像工程逐文件核验，当前提交构建结果见下文；HA未验收 |

`v0.3.10.post2-nhinfer-fix` 继续作为独立维护线。迁移到本版本时使用独立池地址、Store 身份和文件目录，并验证实际 Client 与服务端的接口兼容性。

## 修改总览

NH 编号标识本维护分支的独立修复，各版本分支分别编号。完整上游 commit 和源码校验值见 [backports.json](scripts/nhinfer/backports.json)。补丁已合入源码，构建阶段直接编译。

| 编号 / 上游 PR | 修改动作 | 未修改的影响 |
| --- | --- | --- |
| [NH-0001](#nh-0001) / [#3479](https://github.com/kvcache-ai/Mooncake/pull/3479) | 跨轮尾批只装载一次，并排除重复输入 | 同 key 重复入桶，触发重复对象错误和批次失败 |
| [NH-0002](#nh-0002) / [#3246](https://github.com/kvcache-ai/Mooncake/pull/3246) | 文件回读缓冲注册远端访问权限 | 远端 RDMA READ 缺少访问密钥，传输失败 |
| [NH-0003](#nh-0003) / [#3073](https://github.com/kvcache-ai/Mooncake/pull/3073) | 按操作 ID 匹配 io_uring 完成事件并检查短读 | 完成事件错配或短读被误判成功 |
| [NH-0004](#nh-0004) / [#3488](https://github.com/kvcache-ai/Mooncake/pull/3488) | 同 bucket 多 key 批量提交 io_uring 读取 | 逐 key 提交并等待，增加回读开销 |
| [NH-0005](#nh-0005) / [#3069](https://github.com/kvcache-ai/Mooncake/pull/3069) | master 恢复后重新报告配置的 SSD 容量 | master 丢失文件容量统计 |
| [NH-0006](#nh-0006) / [#2967](https://github.com/kvcache-ai/Mooncake/pull/2967) | 按 bucket 隔离软错误并统一回报失败任务 | 局部失败中断整轮卸载，任务及副本引用释放延迟 |
| [NH-0007](#nh-0007) / [#3009](https://github.com/kvcache-ai/Mooncake/pull/3009) | 保留延期尾桶任务及跨轮任务身份 | 尾桶封装时找不到原任务，对象无法进入文件层 |
| [NH-0008](#nh-0008) / [#2985](https://github.com/kvcache-ai/Mooncake/pull/2985) | 新桶写入完成时登记LRU时间，并维护双向索引 | 新桶首次读取前被当作最旧对象提前驱逐 |

官方基线已包含 #1734、#2165、#2818、#2077 和 #2126 对应修改。#3135 尚未纳入，需单独适配当前卸载实现。

## 构建方法

需要 Docker BuildKit、Python 3 和依赖下载网络。使用普通 Git clone，保留 `.git` 目录；源码修改先提交，构建脚本会检查工作区并校验八项补丁覆盖的全部产物文件。

```bash
git clone --branch v0.3.12.post1-nhinfer-fix https://github.com/nhcf/Mooncake.git
cd Mooncake
BUILD_JOBS=8 bash scripts/nhinfer/build.sh
```

默认镜像标签为 `local/mooncake:0.3.12.post1-cpu-nhinfer-g<commit前12位>`。脚本完成构建后自动执行镜像检查及 CPU/TCP 写读删除测试，最后输出 image ID；镜像保存在执行构建的 Docker 环境中。

需要指定标签或调整下载代理时，在仓库根目录执行：

```bash
IMAGE_TAG=local/mooncake:0.3.12.post1-cpu-nhinfer-test \
BUILD_JOBS=8 \
bash scripts/nhinfer/build.sh \
  --build-arg GOPROXY=https://proxy.golang.org,direct
```

当前入口要求 `.git` 为目录，不支持源码压缩包或关联 worktree。子模块在容器内按固定 gitlink 初始化；更新子模块时同步 [submodules.lock](scripts/nhinfer/submodules.lock)，构建会核对二者是否一致。

### 可选参数

`IMAGE_TAG`、`BUILD_JOBS` 和 `GO_DOWNLOAD_BASE` 可通过构建脚本的环境变量指定。其他参数通过 `--build-arg 参数=值` 传入。

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| `BASE_IMAGE` | Ubuntu 22.04，digest 固定在 Dockerfile | 构建和运行阶段基础镜像 |
| `BUILD_JOBS` | `8` | 并行编译数；内存不足时调小 |
| `UBUNTU_MIRROR` | `https://repo.huaweicloud.com/ubuntu` | apt 源 |
| `UBUNTU_BOOTSTRAP_MIRROR` | `http://archive.ubuntu.com/ubuntu` | 首次安装 CA 证书的 apt 源，保留签名校验 |
| `PIP_INDEX_URL` | `https://mirrors.aliyun.com/pypi/simple/` | pip 源 |
| `GO_DOWNLOAD_BASE` | `https://mirrors.aliyun.com/golang` | build.sh 默认 Go 下载源；直接调用 Dockerfile 时默认为 `https://go.dev/dl` |
| `GOPROXY` | `https://proxy.golang.org,direct` | Go 模块代理 |
| `GITHUB_BASE` | `https://github.com/` | 容器内子模块及依赖下载代理 |

构建开启 HTTP、etcd 和 Store etcd，关闭 CUDA、EP、单元测试、examples 和 benchmarks。镜像包含 master、client、Store 与 Transfer Engine 扩展，不包含 `transfer_engine_bench`。

### 构建缓存与依赖

系统依赖、Go 工具链、子模块和 Python 打包工具在复制业务源码前安装，后续业务修改可复用这些 Docker 层。C/C++ 使用 BuildKit 持久 ccache，缓存 ID 为 `mooncake-nhinfer-cxx-v0312`，容量上限 10 GB；Go 模块和编译结果也使用持久缓存。更换构建器或清理缓存后需重新填充。

[Python 打包工具](scripts/nhinfer/build-requirements.txt)固定版本并预装。wheel 打包使用 `WHEEL_OFFLINE_BUILD=1` 和 `--no-isolation`，该 Docker 步骤禁网执行，避免重复创建环境及下载工具。

构建始终记录实际 Git commit。文档提交也会更新包版本和 master 版本，因此引用版本头的 `master.cpp`、`rpc_service.cpp`、`master_client.cpp` 仍需重编，链接也会重新执行。相同提交重建可以直接命中 Docker 层。

etcd 的 `go.mod/go.sum` 固定在源码中。依赖脚本安装 Go 1.25.9，etcd 模块声明工具链 1.25.10，允许 Go 自动下载所需工具链。apt 软件源未固定快照，当前构建不保证镜像逐字节复现。

## 运行入口

运行脚本位于镜像内 `/opt/mooncake/bin/`，源码见 [runtime](scripts/nhinfer/runtime)。master 默认 RPC 端口为 17789，HTTP 端口为 19004。

在已配置网络和 RDMA 设备的容器中分别启动 master 与 Store。以下 IP、主机名、设备名和挂载路径为示例，部署时替换为实际值：

```bash
# master 容器：默认仅启用 DRAM。
bash /opt/mooncake/bin/master.sh
```

```bash
# Store 容器：注入可达 IP、池地址和稳定且唯一的实例身份。
POD_IP=10.0.0.2 \
MOONCAKE_MASTER=mooncake-master:17789 \
STORE_ID=store-0 \
MOONCAKE_DEVICE=mlx5_0 \
STORE_ROOT=/mnt/gpfs/mooncake \
bash /opt/mooncake/bin/store.sh
```

Store 入口使用 RDMA 传输；CPU 镜像表示不依赖 CUDA，不表示运行时无需 RDMA 设备。设备节点、memlock、网络和 GPFS 挂载由部署环境提供。

| 配置 | 默认值或要求 | 含义 |
| --- | --- | --- |
| `STORE_MEMORY_GIB` | `8` | 每实例贡献的共享内存，单位 GiB |
| `STORE_ENABLE_OFFLOAD` | `0` | master 和 Store 同时设为 `1` 后启用文件层 |
| `STORE_ROOT` | 部署时显式指定 | 新池独立 GPFS 根目录；每个 Store 使用其下的 `STORE_ID` 子目录 |
| `MOONCAKE_DEVICE` | 部署时显式指定 | 当前节点可用的 RDMA 设备 |
| `MOONCAKE_OFFLOAD_LOCAL_BUFFER_SIZE_BYTES` | `1342177280` | 文件回读工作区，1280 MiB，需额外计入内存预算 |
| `MOONCAKE_OFFLOAD_CLIENT_BUFFER_GC_INTERVAL_SECONDS` | `1` | 过期回读缓冲扫描间隔，单位秒 |
| `MOONCAKE_OFFLOAD_USE_URING` | `false` | 文件 IO 默认使用 POSIX；设为 `true` 使用 io_uring |

启用文件层时，Store 入口检查目录确实位于 GPFS，并持有实例目录的排他锁。共享内存、回读工作区和进程开销需共同纳入容器内存预算。

## 镜像检查与源码身份

Python 包名为 `mooncake-transfer-engine-non-cuda`，版本格式为 `0.3.12.post1+nhinfer.g<commit前12位>`。镜像内 `/opt/mooncake-build/SOURCE` 记录官方基线、实际 commit、包版本和子模块版本；同目录保存构建期源码差异、etcd 模块文件、Go 工具链信息和 ccache 统计。

在仓库根目录复验指定镜像：

```bash
image_tag=local/mooncake:0.3.12.post1-cpu-nhinfer-g$(git rev-parse --short=12 HEAD)
EXPECTED_SOURCE_COMMIT=$(git rev-parse HEAD) \
  bash scripts/nhinfer/verify_image.sh "$image_tag"
docker run --rm "$image_tag" cat /opt/mooncake-build/SOURCE
docker image inspect --format 'image_id={{.Id}}' "$image_tag"
```

[镜像检查脚本](scripts/nhinfer/verify_image.sh)校验源码身份、包版本、Store 导入、ELF 依赖和 master CLI，并通过临时 master 执行 64 KiB、20 MiB 对象的 CPU/TCP 写入、逐字节读取及删除。运行镜像不包含源码和 Git 元数据。

### 验证范围

2026-10-20，源码提交 `c6bcfffea742da71753f2c0f80333cffabed2221` 完成镜像构建与上述全部检查。对应包版本为 `0.3.12.post1+nhinfer.gc6bcfffea742`，image ID 为 `sha256:da926f1d4211ba9106281a7a7d928e82bcbf35f5215a6ad37fd7635680716244`。后续文档提交的镜像需按实际 commit 重新构建。

| 验证项 | 结果 |
| --- | --- |
| 六项补丁产物源码校验 | 六个文件一致，包含新增的 `uring_submit.h` |
| io_uring 提交辅助函数 CPU 故障注入 | 7 项通过：空队列、部分提交、瞬态重试、重试耗尽、永久失败、零返回、异常计数 |
| 完整镜像构建、版本及依赖检查、CPU/TCP 写读删除 | 通过 |
| 相同提交、文档变更、单 C++ 文件变更的构建缓存检查 | 三组完整构建及 CPU 验证通过 |
| 跨节点 RDMA、GPFS 回读、真实短读、恢复、HA、模型集成及性能 | 尚未完成目标环境验收 |

源码与提交辅助函数可独立复验；辅助函数测试不调用内核 io_uring：

```bash
python3 scripts/nhinfer/verify_source.py
check_dir=$(mktemp -d)
g++ -std=c++17 -Wall -Wextra -Werror -I. \
  scripts/nhinfer/tests/uring_submit_test.cpp -o "$check_dir/uring-submit-test"
"$check_dir/uring-submit-test"
```

## 逐项说明

<a id="nh-0001"></a>

### NH-0001：跨轮尾批去重

修改 [storage_backend.cpp](mooncake-store/src/storage_backend.cpp) 的 `GroupOffloadingKeysByBucket`。将上一轮未封桶对象移入独立的 carryover 集合，每轮只装载一次；遍历本轮输入时排除已由 carryover 装载的 key，避免同一个对象重复进入 bucket。

<a id="nh-0002"></a>

### NH-0002：注册回读缓冲的远端访问权限

修改 [file_storage.cpp](mooncake-store/src/file_storage.cpp) 的回读缓冲注册，将 `RegisterLocalMemory` 的远端访问和元数据更新参数设为 `true`。Store 从文件读取到工作区后，远端 Client 可获得 RDMA READ 所需的注册信息。

<a id="nh-0003"></a>

### NH-0003：匹配 io_uring 完成事件并检查短读

修改 [uring_file.cpp](mooncake-store/src/uring_file.cpp) 和 [storage_backend.cpp](mooncake-store/src/storage_backend.cpp)。为操作分配 ID，按 ID 识别完成事件，并使用实际读取字节数判断是否覆盖目标范围。仅在读取完整后调整数据指针，避免将短读误判为成功。

<a id="nh-0004"></a>

### NH-0004：同 bucket 批量提交 io_uring 读取

依赖 NH-0003。扩展 [file_interface.h](mooncake-store/include/file_interface.h)，将同 bucket 多 key 的读取组装成 `ReadDesc`，按队列深度提交并收集完成事件。新增 [uring_submit.h](mooncake-store/src/uring_submit.h) 处理部分提交与瞬态重试，保留逐对象完成状态及字节数检查。

本回移纳入生产代码，上游依赖较新接口的测试与 benchmark 未一并引入。批量提交的性能收益需通过实际文件路径对照测试评估。

<a id="nh-0005"></a>

### NH-0005：master 恢复后重报 SSD 容量

修改 [file_storage.cpp](mooncake-store/src/file_storage.cpp) 的 `Heartbeat`。重新挂载磁盘 segment 成功后，如果配置的容量上限大于零，调用 `ReportSsdCapacity` 重报容量，再继续对象心跳。该修改恢复 master 的容量统计；重报失败记录告警。

<a id="nh-0006"></a>

### NH-0006：按 bucket 隔离软错误

修改 [file_storage.h](mooncake-store/include/file_storage.h) 和 [file_storage.cpp](mooncake-store/src/file_storage.cpp)。将 `INVALID_READ`、`OBJECT_ALREADY_EXISTS` 归为当前 bucket 的软错误，记录失败任务后继续处理其他 bucket。整轮硬错误先统一回报失败任务，再返回错误，减少卸载任务和源副本引用滞留。全部对象暂存失败时释放暂存缓冲并跳过空 bucket。

## 发布与维护约定

构建脚本只生成镜像并执行检查。发布镜像时使用唯一版本标签，记录完整源码 commit、包版本、基础镜像 digest、构建与验证结果、image ID 及仓库返回的 RepoDigest。Git 分支、发布 tag 和镜像 tag 分别管理；部署前按上文验证范围完成目标环境验收。

后续独立修复追加 NH 编号，补充提交沿用所属项编号；已有编号不重排、不复用。构建和文档维护不占修复编号。修改受校验的源码文件时，审阅差异后同步更新 [backports.json](scripts/nhinfer/backports.json) 中的产物 hash，保留原上游来源记录。

```bash
# 查询某项修复及后续补充提交。
git log --oneline --fixed-strings --grep='[NH-0001]'
```

官方项目说明保留在 [README.upstream.md](README.upstream.md)。贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 2026-10-25八补丁维护与发布

本分支新增NH-0007、NH-0008，生产源码及测试与正式镜像工程八项补丁在固定基线独立应用后的文件逐字节一致。NH-0007采用四个生产文件回移，NH-0008包含两个生产文件及storage_backend_test.cpp。原有六项补丁与构建缓存优化保留。

### NH-0007：保留延期尾桶卸载任务
<a id="nh-0007"></a>

上游PR #3009固定head为`88a5b5a16aa44edb1e6a0f8f68514bada3b820ef`，合入commit为`20196fc6f77aa5a241cc52a30f64b09d0c91c042`。后端将未满桶的key延至后续轮次时，同时保留其offload task；后续封桶仍能找到对应任务。跳过对象与延期对象分别处理，避免提前NACK释放任务后形成无任务的缓存对象。

### NH-0008：新桶按准入时间进入LRU
<a id="nh-0008"></a>

采用PR #2985的固定head `4671e2963115519380142c0212328b9f93c8d4d7`，不将PR-head回移表述为官方已合入。成功写入的新桶以当前steady-clock时间加入LRU，删除、恢复和回滚同步维护时间到bucket及bucket到时间索引。避免新桶以时间0加入后，在首次读取前被优先驱逐。

### 已发布产物与验证范围

正式镜像为`10.200.53.208/model_test/zyl-mooncake:0.3.12.post1-cpu-nhinfer-fix.2`，RepoDigest为`sha256:4a1b5310c376f9e1b83b12f97df6b4169f7ab4703710cd23a741a1ba2d59217e`，image ID为`sha256:c710b78a8820d9a97447f6c3e2983034dfb6de30a81f52e973d61963ea71fd05`。该产物来自官方基线加八补丁的镜像工程，正式标签与原20261025日期标签指向同一产物；不是本仓库新提交重建的镜像。

镜像工程完整构建、84项存储单测、LRU/FIFO回归通过；新写入对象45/45保留，旧七补丁对照为23/45。尾桶回归两次100/100逐字节一致，旧文件24/24恢复一致。prod-mc0312p1-02的RDMA/GPFS探针与Kimi 80会话×10轮通过，800/800成功，末轮输入Token命中率88.89%。模型结果还依赖Kimi引擎修复和运行配置，不能归因于服务端单项补丁。

本仓库新增隔离CPU回归入口，输出写入临时目录，可通过RESULT_ROOT指定已有结果父目录：

```bash
python3 scripts/nhinfer/tests/run_lru_regression.py <镜像标签>
python3 scripts/nhinfer/tests/run_carry_regression.py <镜像标签>
```

当前源码构建仍使用commit派生的local标签，避免覆盖正式fix.2产物。更新Git分支、构建镜像、推送镜像和切换线上服务分别记录。
