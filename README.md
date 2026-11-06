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

本分支基于官方 `v0.3.7.post2` 维护独立 CPU master/Store，提供同版本共享 DRAM 池的构建、运行和协议检查入口。

| 项目 | 值 |
| --- | --- |
| 维护仓库 | `https://github.com/nhcf/Mooncake` |
| 原版分支 / 标签 | `v0.3.7.post2` |
| 维护分支 | `v0.3.7.post2-nhinfer-fix` |
| 官方基线 commit | `b6a841dc78c707ec655a563453277d969fb8f38d` |
| 构建入口 | `scripts/nhinfer/build.sh`、`docker/mooncake-nhinfer.Dockerfile` |
| 平台 | Linux amd64、Python 3.10、non-CUDA |
| 版本范围 | DRAM；未引入 SSD/GPFS 文件层 |

## 修改总览

本版源码补丁集为空。维护增量为固定官方 CPU wheel、独立运行脚本和隔离协议检查，不分配空的 NH 修复编号。镜像使用 `mooncake-transfer-engine-non-cuda==0.3.7.post2`，未从本分支重新编译原生库。

| 官方 wheel 输入 | 值 |
| --- | --- |
| Python / 架构 | cp310 / x86_64 |
| SHA256 | `0d04b01c2ff86f2d72630944c576c6bc82d204f8a11ff2527c5ea7063557be2f` |
| 下载来源 | PyPI 官方文件，完整 URL 固定在 `scripts/nhinfer/manifest.json` |

#1734、#2165、#2818、#2077、#3479、#3246、#3073、#3488 对应新版文件卸载、回读与恢复路径，不纳入本版 DRAM 池。需要 GPFS 时应选择配套的新版本 Client 和服务端，并验证协议与运行环境。

## 构建方法

需要 Git、Docker、Python 3、curl 和依赖下载网络。使用普通 clone，保留 `.git` 目录；源码修改先提交。构建脚本校验工作区与下载输入，完成镜像构建后自动执行 CPU 检查。

```bash
git clone --branch v0.3.7.post2-nhinfer-fix https://github.com/nhcf/Mooncake.git
cd Mooncake
bash scripts/nhinfer/build.sh
```

默认标签为 `local/mooncake:0.3.7.post2-cpu-nhinfer-g<commit前12位>`。可以通过 `IMAGE_TAG` 环境变量指定输出名称。命令只构建和检查镜像，发布由独立流程执行。

下载输入保存在忽略跟踪的 `vendor/` 中，每次构建均校验 SHA256。基础镜像固定 Ubuntu 22.04 digest；apt 依赖未全部固定快照，构建不保证逐字节复现。

官方 wheel 包版本保持 `0.3.7.post2`。镜像内 `/opt/mooncake-build/SOURCE` 的 `repository_commit` 标识封装脚本提交，`base_commit` 标识官方源码对照；二者不声明 wheel 由本分支编译。`manifest.json` 记录固定的 wheel 身份。未来若引入原生代码修复，需另行建立源码构建流程。

## 运行入口

镜像内入口统一为 `/opt/mooncake/bin/master.sh` 与 `/opt/mooncake/bin/store.sh`。两个角色分别运行，Store 的 IP、池地址和 RDMA 设备按实际环境配置。

```bash
# master 容器
bash /opt/mooncake/bin/master.sh
```

```bash
# Store 容器：示例贡献 8 GiB DRAM。
POD_IP=10.0.0.2 \
MOONCAKE_MASTER=mooncake-master:17788 \
MOONCAKE_DEVICE=mlx5_0 \
STORE_MEMORY_BYTES=8589934592 \
bash /opt/mooncake/bin/store.sh
```

master 默认 RPC/HTTP 端口为 17788/19003，可通过 `MASTER_PORT`、`MASTER_METRICS_PORT` 覆盖。Store 默认贡献 128 GiB 内存，部署时应按容器预算显式设置 `STORE_MEMORY_BYTES`，并预留进程开销。传输默认 RDMA，`MOONCAKE_PROTOCOL=tcp` 用于隔离 CPU 验证。Store 重启后的 DRAM 数据按缓存丢失处理。

CPU 镜像不依赖 CUDA；RDMA 设备、memlock 和网络由运行环境提供。不同版本使用独立池地址与实例身份，实际 Client 兼容性按目标环境验证。

## 镜像检查与验证范围

`scripts/nhinfer/verify_image.sh IMAGE_TAG` 检查包版本、封装身份和原生依赖，并运行独立 master/Store 的 TCP 测试。两个零共享段 Client 进程先写后读，覆盖 64 KiB、20 MiB 和多 buffer 对象，确认写入 Client 退出后数据仍由 Store 保留。默认使用同镜像 Client；可用 `CLIENT_IMAGE`、`CLIENT_PYTHON` 指定另一个 Client 环境。

既有 wheel 镜像于 2026-10-20 通过厂商 0.3.7 Client 的上述 TCP 门禁。该历史结果不替代本分支新镜像的检查。RDMA、跨节点、模型 KV 恢复和长期稳定性待目标环境验收。

## 发布与维护约定

原版分支保持官方 tag 的提交；维护分支从同版本基线追加修改，独立修复使用 `[NH-0001]` 等编号，构建和文档维护不占编号。发布使用唯一镜像标签，记录 Git commit、包版本、基础镜像 digest、验证范围、image ID 和推送后的 RepoDigest。

官方项目说明保留为 `README.upstream.md`。对外文档使用仓库相对路径，不依赖个人工作目录或内部实验工程。
