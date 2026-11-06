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

本分支基于官方 `v0.3.13` 维护独立 CPU master/Store，提供共享 DRAM 与 GPFS bucket 文件层的修复版本、构建及运行入口。

| 项目 | 值 |
| --- | --- |
| 维护仓库 | `https://github.com/nhcf/Mooncake` |
| 原版分支 / 标签 | `v0.3.13` |
| 维护分支 | `v0.3.13-nhinfer-fix` |
| 官方基线 commit | `e5598b0992cc258b06d22f24d875480e8931a28e` |
| 构建入口 | `scripts/nhinfer/build.sh`、`docker/mooncake-nhinfer.Dockerfile` |
| 平台 | Linux amd64、Python 3.10、non-CUDA |
| 版本范围 | DRAM、bucket 文件层、HTTP、etcd；文件淘汰策略固定 FIFO |

## 修改总览

| 编号 / 上游 PR | 修改动作 | 未修改的影响 |
| --- | --- | --- |
| NH-0001 / #3009 | 跨心跳保留未成桶任务身份、源引用和冲突处理 | 未达到成桶条件的任务在后续轮次丢失，影响落盘与回读 |

### NH-0001：保留延期卸载任务

修改 `mooncake-store/include/file_storage.h`、`storage_backend.h` 及对应 `src/` 下两个实现文件。生产代码适配来源为上游 #3009 的 head `88a5b5a16aa44edb1e6a0f8f68514bada3b820ef`，上游合入提交为 `20196fc6f77aa5a241cc52a30f64b09d0c91c042`。适配保持现有 RPC 和文件格式，未带入上游测试文件。

输入 patch SHA256 为 `5a15f0c34879ceb876c146f5c7a5ad2a49ea9db6381d6e1af0e15edd1057efcd`。补丁作为独立 commit 合入，`scripts/nhinfer/backports.json` 保存来源与四个产物文件的校验值；构建不重复应用补丁。

#3479、#3246、#3073、#3488、#3069、#2967 已包含在官方基线。#2985 的旧版 LRU 组合补丁未完成本版本适配，运行入口固定使用 FIFO。

## 构建方法

需要 Git、Docker、Python 3、curl 和依赖下载网络。使用普通 clone，保留 `.git` 目录；源码修改先提交。构建脚本校验工作区与下载输入，完成镜像构建后自动执行 CPU 检查。

```bash
git clone --branch v0.3.13-nhinfer-fix https://github.com/nhcf/Mooncake.git
cd Mooncake
bash scripts/nhinfer/build.sh
```

默认标签为 `local/mooncake:0.3.13-cpu-nhinfer-g<commit前12位>`。可以通过 `IMAGE_TAG` 环境变量指定输出名称。命令只构建和检查镜像，发布由独立流程执行。

下载输入保存在忽略跟踪的 `vendor/` 中，每次构建均校验 SHA256。基础镜像固定 Ubuntu 22.04 digest；apt 和 Python 打包工具依赖未全部固定快照，构建不保证逐字节复现。

编译默认 8 个任务，通过 `BUILD_JOBS` 调整。`GO_DOWNLOAD_BASE` 默认 `https://mirrors.aliyun.com/golang`，其他下载参数通过 `--build-arg` 覆盖。pybind11 和 yalantinglibs 使用固定提交与归档校验和，Go 模块和编译结果使用 BuildKit 缓存。

```bash
BUILD_JOBS=8 bash scripts/nhinfer/build.sh \
  --build-arg GOPROXY=https://proxy.golang.org,direct
```

Python 包版本由实际 Git commit 生成：`0.3.13+nhinfer.g<commit前12位>`。镜像内 `/opt/mooncake-build/SOURCE` 记录基线、源码 commit 与包版本；同目录保存源码差异、补丁校验信息、Go 依赖和工具链信息。

## 运行入口

镜像内入口统一为 `/opt/mooncake/bin/master.sh` 与 `/opt/mooncake/bin/store.sh`。两个角色分别运行，Store 的 IP、池地址和 RDMA 设备按实际环境配置。

```bash
# master 容器
bash /opt/mooncake/bin/master.sh
```

```bash
# Store 容器：示例 IP、设备和路径需替换。
POD_IP=10.0.0.2 \
MOONCAKE_MASTER=mooncake-master:17789 \
STORE_ID=store-0 \
STORE_ROOT=/mnt/gpfs/mooncake \
MOONCAKE_DEVICE=mlx5_0 \
STORE_MEMORY_GIB=8 \
bash /opt/mooncake/bin/store.sh
```

master 默认 RPC/HTTP 端口为 17789/19004。默认使用 DRAM；启用文件层时，master 和 Store 同时设置 `STORE_ENABLE_OFFLOAD=1`。Store 检查实际 GPFS 挂载并持有实例目录锁。默认回读区为 1280 MiB，通过 `MOONCAKE_OFFLOAD_LOCAL_BUFFER_SIZE_BYTES` 调整，需额外计入内存预算。文件 IO 默认 POSIX，`MOONCAKE_OFFLOAD_USE_URING=true` 可切换 io_uring。

CPU 镜像不依赖 CUDA；RDMA 设备、memlock 和网络由运行环境提供。不同版本使用独立池地址与实例身份，实际 Client 兼容性按目标环境验证。

## 镜像检查与验证范围

`scripts/nhinfer/verify_image.sh IMAGE_TAG` 检查源码身份、包版本、Store 导入、ELF 依赖、master CLI 及 64 KiB/20 MiB CPU/TCP 写读删除。文件回归另运行：

```bash
bash scripts/nhinfer/run-smoke.sh IMAGE_TAG
```

将 `IMAGE_TAG` 替换为实际镜像。测试使用隔离容器、64 MiB 共享内存、16 MiB 桶和 100×1 MiB 对象，在第 10 个对象后暂停，让任务跨越心跳；要求 Put、存在性、逐字节读取全部通过且生成文件。结果写入临时目录。本地 POSIX 回归与实际 GPFS/RDMA 验收分别记录。

既有候选于 2026-10-27 通过完整构建、CPU/TCP 和上述文件回归，采用相同生产补丁。本分支构建身份重新生成，检查结果单独记录。跨节点 RDMA、GPFS、恢复、HA 和模型联调待目标环境验收。

## 发布与维护约定

原版分支保持官方 tag 的提交；维护分支从同版本基线追加修改，独立修复使用 `[NH-0001]` 等编号，构建和文档维护不占编号。发布使用唯一镜像标签，记录 Git commit、包版本、基础镜像 digest、验证范围、image ID 和推送后的 RepoDigest。

官方项目说明保留为 `README.upstream.md`。对外文档使用仓库相对路径，不依赖个人工作目录或内部实验工程。
