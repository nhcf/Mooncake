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

使用普通clone及干净、已提交的源码，`.git`须为目录。需要Docker BuildKit及依赖下载网络。默认基础镜像锁定Ubuntu 22.04 digest，关闭CUDA/EP，保留HTTP、etcd和Store etcd能力；apt/pip依赖未全部锁定快照。

```bash
cd /data/zhuyilin/git-code/work/Mooncake
# 默认标签含当前commit，避免覆盖已发布的fix.1。
BUILD_JOBS=8 bash scripts/nhinfer/build.sh
# 可通过参数覆盖下载源等Docker build参数：
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
| 当前分支完整Docker构建及镜像CPU门禁 | 未执行：本机 `/data` 仅余约7.8GiB，先完成源码迁入与轻量验证 |
| 新产物跨节点RDMA/GPFS、厂商批量接口、恢复及性能 | 未执行 |

复验命令在仓库根目录执行；C++测试只检查提交辅助函数，不调用内核io_uring：

```bash
python3 scripts/nhinfer/verify_source.py
check_dir=$(mktemp -d)
g++ -std=c++17 -Wall -Wextra -Werror -I. \
    scripts/nhinfer/tests/uring_submit_test.cpp -o "$check_dir/uring-submit-test"
"$check_dir/uring-submit-test"
```

既有已推送镜像 `10.200.53.208/model_test/mooncake:0.3.12.post1-cpu-nhinfer-fix.1` 属于镜像工程产物。仓库化构建采用新的commit包版本，后续发布使用新标签，并记录源码commit、包版本、image ID、RepoDigest及本轮验证结果。本地迁入完成后仍需完整编译与镜像门禁，再开展实际RDMA、GPFS文件回读、短读、重复桶和master恢复验证。
