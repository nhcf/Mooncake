# Mooncake 0.3.12.post1 nhinfer 维护分支

本分支 `v0.3.12.post1-nhinfer-fix` 为独立 CPU master/Store 提供六项源码回移、运行入口和本地源码镜像构建。官方基线为 `v0.3.12.post1`，commit `6041a609a8c3af35e778f70db344f145c2914980`。官方项目说明保留在 [README.upstream.md](README.upstream.md)。

模型继续使用厂商0.3.12 Client，新池使用独立地址、Store身份及文件目录。原 `v0.3.10.post2-nhinfer-fix` 分支继续维护旧池。

## 补丁与源码身份

补丁来自既有0.3.12 CPU镜像工程，按以下顺序分别提交。完整上游commit、输入patch SHA256和六个产物源码文件SHA256见 [backports.json](scripts/nhinfer/backports.json)。源码已合入Git，构建直接使用当前提交。

| 顺序 | 来源 | 修改 |
| --- | --- | --- |
| NH-0001 | #3479 | 跨轮尾批去重，避免重复对象进入bucket |
| NH-0002 | #3246 | 文件回读缓冲注册远端RDMA访问权限 |
| NH-0003 | #3073 | io_uring完成事件按操作ID匹配，检查短读 |
| NH-0004 | #3488 | 同bucket批量读取，包含新增的 `uring_submit.h`；依赖NH-0003 |
| NH-0005 | #3069 | master恢复后重新上报SSD容量 |
| NH-0006 | #2967 | 区分软错误并缩小卸载任务失败范围 |

#1734、#2165、#2818、#2077和#2126已包含在官方基线。#3135在镜像工程中存在应用冲突，留待专项适配。六项回移保持官方RPC定义，完整厂商兼容性仍需实际接口测试。

etcd `go.mod/go.sum` 单独提交已有CPU镜像构建捕获的解析结果：`x/sys v0.45.0`、`x/text v0.37.0`及相关校验和。官方依赖脚本安装Go 1.25.9，etcd模块声明工具链1.25.10；构建允许Go自动下载工具链，并将实际二进制工具链信息保存到镜像。

## 本地构建

使用普通clone及干净、已提交的源码，`.git`须为目录。需要Docker BuildKit及依赖下载网络。默认基础镜像锁定Ubuntu 22.04 digest，关闭CUDA/EP，保留HTTP、etcd和Store etcd能力；Python打包工具版本固定，apt依赖未锁定仓库快照。

```bash
cd /data/zhuyilin/git-code/work/Mooncake
# 默认标签含当前commit，避免覆盖已发布的fix.1。
BUILD_JOBS=8 bash scripts/nhinfer/build.sh
# Go下载默认使用阿里镜像，可通过GO_DOWNLOAD_BASE环境变量覆盖。
# 可通过参数覆盖其他Docker build参数：
# bash scripts/nhinfer/build.sh --build-arg GOPROXY=https://proxy.golang.org,direct
```

[Dockerfile](docker/mooncake-nhinfer.Dockerfile)读取当前commit，生成包版本 `0.3.12.post1+nhinfer.g<commit前12位>`。镜像内 `/opt/mooncake-build/SOURCE` 记录基线、提交、包版本和子模块；`build-generated.diff`、`etcd-go.mod`、`etcd-go.sum`和`etcd-go-build.txt`保存构建期变化及工具链信息。

构建脚本先校验六项源码，再构建镜像，最后执行[镜像门禁](scripts/nhinfer/verify_image.sh)：被测commit、包版本、Store导入、ELF依赖、master CLI和64KiB/20MiB CPU/TCP写读删除。脚本只构建本地镜像。

## 运行入口

镜像内脚本位于 `/opt/mooncake/bin/`，对应仓库 [runtime](scripts/nhinfer/runtime)。master默认RPC17789、HTTP19004；Store默认贡献8GiB内存，回读工作区额外预算1280MiB。

```bash
bash /opt/mooncake/bin/master.sh
# 在Store容器注入可达IP、独立池地址及唯一实例身份。
POD_IP=10.0.0.2 MOONCAKE_MASTER=master-host:17789 STORE_ID=shared-0 \
    bash /opt/mooncake/bin/store.sh
```

示例IP和地址需替换为实际部署值。默认 `STORE_ENABLE_OFFLOAD=0` 先运行DRAM；验证文件层时master和Store同时设为1，提供独立GPFS `STORE_ROOT`。每个Store持有目录排他锁。`MOONCAKE_DEVICE`须按目标节点RDMA设备配置；`MOONCAKE_OFFLOAD_USE_URING=false`默认使用POSIX路径。

[probe_client.py](scripts/nhinfer/probe_client.py)和[vendor_probe.py](scripts/nhinfer/vendor_probe.py)用于厂商Client互通测试。设备、memlock、网络与GPFS挂载由部署环境提供。

## 本轮验证与发布边界

2026-10-20本地验证：

| 检查 | 结果 |
| --- | --- |
| 六补丁独立应用，与本分支六个业务文件逐字节比较 | 通过，包含新文件 `uring_submit.h` |
| 源码hash、Git差异空白检查、Python及Shell语法 | 通过 |
| 实际提交辅助函数CPU故障注入 | 7项通过：空队列、部分提交、瞬态重试、重试耗尽、永久失败、零返回和异常计数 |
| 当前分支完整Docker构建及镜像CPU门禁 | 通过：原构建 `2bc3a83cd61f`、优化构建 `c6bcfffea742`；身份、包版本、导入、ELF、CLI及64KiB/20MiB CPU/TCP Put/Get/Remove均通过 |
| 新产物跨节点RDMA/GPFS、厂商批量接口、恢复及性能 | 未执行 |

复验命令在仓库根目录执行；C++测试只检查提交辅助函数，不调用内核io_uring：

```bash
python3 scripts/nhinfer/verify_source.py
check_dir=$(mktemp -d)
g++ -std=c++17 -Wall -Wextra -Werror -I. \
    scripts/nhinfer/tests/uring_submit_test.cpp -o "$check_dir/uring-submit-test"
"$check_dir/uring-submit-test"
```

既有已推送镜像 `10.200.53.208/model_test/mooncake:0.3.12.post1-cpu-nhinfer-fix.1` 属于镜像工程产物。仓库化构建采用新的commit包版本，后续发布使用新标签，并记录源码commit、包版本、image ID、RepoDigest及本轮验证结果。本轮完成完整编译与镜像CPU门禁；实际RDMA、GPFS文件回读、短读、重复桶和master恢复验证仍待执行。

## 2026-10-20本地镜像构建记录

- 被测源码：`2bc3a83cd61f1ee396f1a8a9116a6132e625894c`；本节回填是后续文档提交。
- 本地镜像：`local/mooncake:0.3.12.post1-cpu-nhinfer-g2bc3a83cd61f`。
- 包版本：`0.3.12.post1+nhinfer.g2bc3a83cd61f`。
- image ID：`sha256:3ae583a8086cbfab830b4f43201f2a4e24de0c5d0501aedb680a14b4d727dfda`。
- [构建结果及日志](/data/zhuyilin/mooncake-build-results/v0312-20261020-155505/result.json)：退出码0，未推送、未部署。目录同时保存输入hash、镜像inspect、源码及Go构建元数据。

磁盘空间恢复后执行完整构建。首轮因Go下载慢主动停止，日志保留在 `/data/zhuyilin/mooncake-build-results/v0312-20261020-154703/`；第二轮通过已有参数切换下载源：

```bash
bash scripts/nhinfer/build.sh \
    --build-arg GO_DOWNLOAD_BASE=https://mirrors.aliyun.com/golang
```

CMake配置及编译用时925.5秒，wheel及元数据阶段236.4秒。首次系统依赖安装341.3秒；重试时该层命中缓存。Go安装187.4秒，子模块及依赖脚本156.0秒。历史镜像工程冷编译约933秒，最终复验的编译层命中缓存。

## 构建缓存优化

优化代码提交为 `c6bcfffea742da71753f2c0f80333cffabed2221`。六项业务补丁保持原样；关闭examples/benchmarks后，默认镜像不再包含 `transfer_engine_bench`。master、Store、HTTP和etcd编译能力保留。

- 子模块及官方依赖脚本在复制业务源码前执行；该层的源码输入限于依赖脚本、`.gitmodules`和[子模块锁定文件](scripts/nhinfer/submodules.lock)，业务源码和文档变更可复用该层。更新子模块时同步锁定文件；构建会核对它与Git gitlink是否一致。
- C/C++使用BuildKit持久ccache，缓存ID为 `mooncake-nhinfer-cxx-v0312`，上限10GB。相同构建器复用该缓存；清理BuildKit缓存或换构建器后需重新填充。
- [打包工具清单](scripts/nhinfer/build-requirements.txt)固定版本并预装。wheel使用 `WHEEL_OFFLINE_BUILD=1`、`--no-isolation`，Docker打包步骤禁网运行；其他调用者保持原脚本默认行为。
- 构建仍复制真实Git元数据并更新包版本和master版本。文档提交会使源码层失效，但ccache复用无关编译结果；`master.cpp`、`rpc_service.cpp`、`master_client.cpp`因版本头变化重新编译，链接也需重新执行。

默认命令仍为 `BUILD_JOBS=8 bash scripts/nhinfer/build.sh`。首次构建需要下载依赖；相同提交再次构建复用Docker层。镜像内 `/opt/mooncake-build/ccache-stats.txt`保存对应编译阶段的缓存统计。

### 优化实测（2026-10-20）

同一台本机构建器、`BUILD_JOBS=8`连续测试，每组均执行完整镜像CPU门禁。总耗时包含Docker前端解析、构建、导出和门禁；阶段耗时采用BuildKit的 `DONE` 数值，包含保存层的成本。首次优化构建已有系统/子模块依赖层和Go缓存，C++缓存基本为空，因此本表不代表全新机器从零安装的耗时。

| 场景 | 总耗时 | CMake配置及编译阶段 | wheel及元数据阶段 | C++缓存命中 |
| --- | ---: | ---: | ---: | ---: |
| 优化后首次填充缓存 `c6bcfffea742` | 1041.13秒 | 900.9秒 | 80.0秒 | 3/112 |
| 相同提交重建 | 82.83秒 | Docker层命中 | Docker层命中 | 未执行编译 |
| 仅修改README并提交 `42eca57ac3b8` | 594.55秒 | 521.3秒 | 15.8秒 | 109/112（97.32%） |
| 再修改单个C++文件并提交 `5356f50531e1` | 597.97秒 | 508.2秒 | 17.6秒 | 108/112（96.43%） |

最后一组在 `mooncake-common/src/environ.cpp`追加无运行时行为的 `static_assert`，验证单个编译单元变化时的缓存失效。两个测试提交仅位于结果目录的独立克隆。每次提交仍改变包版本和master版本；文档组的3次未命中、单文件组的4次未命中与此一致。大文件 `master_client.cpp`和最终链接使增量构建仍需约10分钟。

原构建历史编译阶段925.5秒、wheel阶段236.4秒；本轮首次分别为900.9秒、80.0秒。缓存填充后，两组变更构建总耗时较本轮首次减少约43%。这些是单轮实测，依赖安装缓存和网络状态不同，不能据此推导全冷构建的固定加速比。

正式本地产物为 `local/mooncake:0.3.12.post1-cpu-nhinfer-gc6bcfffea742`，包版本 `0.3.12.post1+nhinfer.gc6bcfffea742`，image ID为 `sha256:da926f1d4211ba9106281a7a7d928e82bcbf35f5215a6ad37fd7635680716244`。本节为后续文档回填，未重新构建文档提交的镜像。

[首次构建结果](/data/zhuyilin/mooncake-build-results/optimized-20261020-163741/result.json)、[三组对照结果](/data/zhuyilin/mooncake-build-results/optimized-20261020-163741/matrix-result.json)及同目录日志保存退出码、源码身份、输入hash、镜像ID和缓存统计。四次构建及CPU门禁全部通过；源码六文件校验、Shell语法和Git差异检查通过。环境未安装pre-commit，本轮未执行其hooks。此前 `optimized-20261020-163220`尝试在发现关闭examples后打包脚本仍强制复制benchmark时主动停止；修复已包含在被测提交中。

本轮仅在本地提交和构建，未推送或部署。RDMA/GPFS等真实路径的验证范围沿用上文。
