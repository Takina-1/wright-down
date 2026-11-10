# 阿里云部署 · aliyun deploy

F013 云同步服务端在阿里云 ECS 上的部署说明。

## 1. 环境现状

2026-11-05 已完成换盘，以下为换盘后的实测状态：

| 项 | 值 |
| --- | --- |
| 实例 ID | `i-7xv4buzm47fxdask0bgz` |
| 地域 | cn-guangzhou（广州） |
| 镜像 | Alibaba Cloud Linux 4.0.6（OpenAnolis Edition），`aliyun_4_x64_20G_alibase_20260901.vhd` |
| 内核 | 6.6.102-8.alnx4.x86_64 |
| 规格 | 2 vCPU / 1.6 GiB 内存（`ecs.e-c1m1.large`，突发型入门规格，**尚未变配**） |
| 系统盘 | 40 GiB ext4 |
| swap | 2 GiB（`/swapfile`，脚本创建） |
| 公网 IP | 8.148.158.13（实测仅 22 端口对外可达） |
| PostgreSQL | 15.19，监听 `127.0.0.1:5432`，`scram-sha-256` |
| Dart SDK | 3.13.7（`/opt/dart-sdk`） |
| SELinux | Disabled（Alinux 4 镜像默认关闭） |
| 账号 UID | `1508982677716316` |
| RAM 用户 ID | `208395793804891250` |

> 规格仍是 `e-c1m1.large`（1.6 GiB）。配合 2 GiB swap 目前够用，但 Postgres + Dart
> 服务正式上线后建议变配到 `ecs.g7.large`（2C4G），突发型规格的基线性能不适合常驻数据库。

## 2. 镜像选型：Alibaba Cloud Linux 4 LTS

原 CentOS 8.5 已 EOL（2021-12-31），仓库为 `Centos-vault-8.5.2111` + `epel-archive-8` 冻结归档，无安全更新。正式环境存用户日记与照片，故更换为 **Alibaba Cloud Linux 4 LTS 64位**（2025-07 发布，内核 6.6，对标 RHEL 9）。

### 为什么是 Alinux 4 而不是 Alinux 3

两者都在支持期内，但 Alinux 4 更合适：

| | Alinux 3 | **Alinux 4 LTS** |
| --- | --- | --- |
| 发布 | 2021-04 | **2025-07** |
| 内核 / 基线 | 4.19，≈RHEL 8 | **6.6，≈RHEL 9** |
| 生命周期 | 至 2034-03-31 | **至 2038-06-30（13 年）** |
| 当前阶段 | 维护支持（2026-04 起） | **开发支持（至 2030-06）** |
| PostgreSQL | 12.1 | **15.12** |
| nginx | 1.18.0 | **1.26.2** |
| glibc | 2.32 | **2.38** |
| git | 2.27.0 | **2.47.1** |
| Python 3 | 源里没有 | **3.11.6** |

关键差异是 **PostgreSQL 12.1**：PG12 已于 2024-11 结束生命周期，而 Alinux 3 基础仓里只有这一个版本（公共镜像源下未见更高版本模块流）。Alinux 4 基础仓直接提供 PG 15.12，省去启用模块流的步骤。

Alinux 4 较新（发布一年多），但本项目技术栈全是纯用户态组件（Dart + PostgreSQL + nginx），不涉及闭源 GPU 驱动、DKMS 内核模块或老旧二进制 glibc 兼容问题——这是第三方评测提示的 ALinux 4 主要风险点，对我们不适用。

### 更换方式

走「更换系统盘」，不新建实例，以保留实例 ID、公网 IP、安全组与带宽计费：

1. ECS 控制台 → 实例 → 更多 → 磁盘 → 更换系统盘
2. 选择 **Alibaba Cloud Linux 4 LTS 64位**（不要选 Agentic 版或容器优化版）
3. 确认停机窗口后执行

换盘会重置系统盘（当前无应用与数据，无损失）。RAM 用户凭证是账号级的，换实例无需重新授权。

**建议同时变配**：`ecs.e-c1m1.large` → `ecs.g7.large`（2C4G）。1.7 GiB 内存跑 PostgreSQL + Dart 服务偏紧。

### Alinux 4 特有的两处适配

脚本已处理：

- **`postgresql-setup` 参数形式变了**。RHEL 8 系是 `postgresql-setup --initdb`，RHEL 9 系（Alinux 4）改成 `postgresql-setup initdb`。脚本两种都试，再不行退回手动 `initdb`。
- **仓库路径不同**。公共镜像源上 Alinux 3 是 `alinux/3/os/x86_64/repodata/`，Alinux 4 改成 `alinux/4/os/x86_64/os/repodata/`。镜像自带 `aliyun-linux-release` 会写好正确的 repo 配置，一般无需干预；脚本末尾会打印 `yum repolist` 便于核对。

## 3. 换盘后的初始化

```bash
# 上传并执行（本地仓库 deploy/ 目录）
workbench upload deploy/provision-alinux4.sh deploy/sql/schema.sql <远程路径>
bash provision-alinux4.sh
```

脚本幂等，重复执行安全。做的事：

1. 建立 2 GiB swap（写入 `/etc/fstab`）
2. 安装 PostgreSQL / nginx / git / gcc / policycoreutils
3. 初始化 PostgreSQL 集群，按小规格保守调优（`shared_buffers=256MB` 等）
4. `pg_hba.conf` 只允许本地连接，数据库不暴露公网
5. 建库 `diary_sync`、建用户，凭证写入 `/root/.diary-sync-pg-credentials`（0600）并复制到 `/etc/diary-sync/pg.env`
6. 应用 `deploy/sql/schema.sql` 建表
7. 安装 Dart SDK 3.13.7（sha256 校验），配置 pub 镜像
8. 建应用用户 `diary`、目录 `/opt/diary-sync`
9. SELinux 打标签；firewalld 只放行 ssh 与 80/443，**8080 不对外开放**

> 应用端口 8080 不开放，因此 Dart 服务必须监听 `127.0.0.1` 而不是 `0.0.0.0`，
> 对外只由 nginx 走 443。`packages/server/lib/src/main.dart` 目前写的是
> `0.0.0.0`，改代码时一并调整。

## 4. 库表结构

见 `deploy/sql/schema.sql`。与设计文档第 5 节的两处有意偏差：

1. **`entries` 主键为 `(user_id, id)`**，而非单列 `id`。`FakeSyncStore` 的 `_entries` 以 `p.id` 全局索引，跨用户同 id 会互相覆盖——这是内存实现的缺陷，真实库不能照抄。
2. **`seq` 由 `sync_seq` 行锁自增，而非 `BIGSERIAL`**。序列 `nextval` 在事务提交前即分配值，客户端可能先拉到 `seq=6` 却漏掉仍未提交的 `seq=5`，cursor 直接跳过该条目。改用 `UPDATE sync_seq SET value = value + 1 ... RETURNING value`，行锁持有至提交，推送事务间串行化，`seq` 顺序等于提交顺序。

## 5. 服务端代码现状（2026-11-10 第七轮更新）

`packages/server/` 的存储已从 FakeSyncStore（内存）迁移到 PostgreSQL：

- `PostgresSyncStore` 实现 `SyncStore` 接口（真实 SQL，见
  `packages/server/lib/src/postgres_sync_store.dart`）：行锁取 seq（AC-07）、
  字段级 LWW、payload JSONB、created_at 冻结。
- `main()` 从环境变量 `PG_HOST/PG_PORT/PG_DB/PG_USER/PG_PASSWORD` 装配
  `PostgresSyncStore`（`pg_config.dart`）；凭证缺失回退 FakeSyncStore（开发模式）。
- `packages/server/pubspec.yaml` 已增加 `postgres` 依赖。
- systemd 单元 `deploy/diary-sync.service` 已挂 `/etc/diary-sync/pg.env`
  （凭证由 provision 脚本生成，0600，owner diary）。
- 连接显式 `SslMode.disable`：postgres 包默认要求 SSL，本机 PG 未启用 SSL。
- 已知限制：单连接演示环境（并发正确性已验证；吞吐上限再评估连接池）。
- nginx 反代 + HTTPS 已在 §3/§4 完成（TLS 443 + 自签 CA）。

## 6. 已知环境约束

- **Dart SDK 必须走中国镜像**。官方源 `storage.googleapis.com` 从广州实测吞吐仅 ~115 KB/s（227 MB 要半小时），`storage.flutter-io.cn` 实测 ~1.2 MB/s（3 分 12 秒完成）。两处文件 sha256 完全一致（`eb99aed2...67229`）。注意 `storage.flutter-io.cn` 的 `latest` 指针停在 3.13.2，但 **3.13.7 的历史版本文件存在**，满足 pubspec 的 `sdk: ^3.13.7`。脚本的做法是：期望哈希始终取自官方源，字节允许从任一镜像取。
- pub 用 `https://pub.flutter-io.cn` 镜像，与本地开发一致
- `mirrors.cloud.aliyuncs.com` 用 curl 会因证书 SAN 不匹配报 SSL 错，但 yum 走内网直连（100.100.2.148）不受影响
- Git Bash 下调用 `workbench upload/download` 必须加 `MSYS_NO_PATHCONV=1`，否则路径被改写导致 `[InvalidParameter.Path]`
- `workbench upload` 到远端已存在的文件会提示覆盖确认，非交互下直接中止。上传前先 `rm -f` 远端文件

## 7. 脚本验证记录

`deploy/provision-alinux4.sh` 已在待替换的 CentOS 8 机器上完整跑通（PG 10.17），全程发现并修复 4 个缺陷：

| # | 缺陷 | 现象 | 修复 |
| --- | --- | --- | --- |
| 1 | `conf.d` 目录属主为 root | postmaster 拒绝启动 | `install -d -o postgres -g postgres` |
| 2 | 角色已存在时跳过 `CREATE ROLE` | 凭证文件密码与库里不符，psql 认证失败 | 改用 `ALTER ROLE ... PASSWORD` 强制对齐 |
| 3 | `include_dir` 用无锚点 grep 判断 | PG15 的 `#include_dir = 'conf.d'` 被误判为已配置，调优参数根本没加载 | 只匹配生效行 `^[[:space:]]*include_dir` |
| 4 | 汇总行末尾用了全角 `）` 闭合 `$(` | `$(` 跨行吞掉后续内容，汇总块被当命令执行 | 改写该行；全文件已加括号配对检查 |

另外把 `password_encryption` 显式设为 `scram-sha-256` 并与 `pg_hba.conf` 的 host 行方法对齐——PG10 默认存 md5 哈希，若 `pg_hba` 写 scram 会认证失败；且 `ALTER SYSTEM` 需重启才生效，设密码必须在其之后。

建表语句与 `PostgresSyncStore` 将来要用的查询已用真实 Postgres 验证：建表、LWW 合并（`created_at` 保持不变）、游标推进、用户隔离（同 id 不同用户互不覆盖）、token 查找全部通过。并发验证：两个事务并发取 seq 时第二个**阻塞 3023 ms** 直到第一个提交，确认 `sync_seq` 行锁使 seq 顺序等于提交顺序，pull 不会漏条目。

测试期间写入的数据已清空（`users`/`entries`/`tokens` 均为 0，`sync_seq` 归零）。

## 8. 规格变配：e-c1m1.large → g7.large

### 现状与约束

`ecs.e-c1m1.large` 是**共享型**（经济型 e）：

| 项 | e-c1m1.large | e-c1m2.large | e-c1m2.xlarge | g7.large |
| --- | --- | --- | --- | --- |
| vCPU / 内存 | 2 / 2 GiB | 2 / 4 GiB | 4 / 8 GiB | 2 / 4 GiB |
| CPU | 共享非独占 | 共享非独占 | 共享非独占 | **企业级独享** |
| 基础带宽 | 0.2 Gbit/s | 0.2 Gbit/s | 0.4 Gbit/s | 更高 |
| 云盘 IOPS 基础 | 0.8 万（无突发） | 0.8 万 | 1.6 万 | 更高上限 |

e 族只有 `large` 一个规格是 2C2G，族内向上的选择是 `e-c1m2.large`(2C4G)、`e-c1m2.xlarge`(4C8G)、`e-c1m4.large`(2C8G)。

### 跨族变配 e → g 是否可行

《规格变更限制与自检》写的是「仅支持同一规格族内的变更」，控制台通常不列出 g 系列目标。但 `DescribeResourcesModification` 接口带有 `MigrateAcrossZone=true` 参数，用于「跨系列（跨族）升级实例规格」，因此**不能只凭文档下结论**，需要以接口返回的 `AvailableResources` 为准。

同时还有云盘类型约束：目标规格若要求更高等级的云盘（如 g7 要求 ESSD 类，而 e 实例默认用 ESSD Entry），需要先把系统盘云盘类型升上去，否则变配不可选。查询方式是 `DestinationResource=SystemDisk` + 目标 `InstanceType`。

### 结论判定方法

用 `ecs:DescribeResourcesModification` 查询（需先给 RAM 用户加只读权限，见 `deploy/ram-policy.json` 的 `ReadOnlyInstanceInspection` 语句）：

```bash
# 1. 同可用区可选目标规格
Action=DescribeResourcesModification&ResourceId=<iid>&DestinationResource=InstanceType&OperationType=Upgrade
# 2. 含跨系列变配
...&MigrateAcrossZone=true
# 3. 目标规格要求的云盘类型
...&DestinationResource=SystemDisk&InstanceType=ecs.g7.large
```

### 备选路径

若跨族变配确实不可用，有两条路：

1. **族内变配** `e-c1m1.large` → `e-c1m2.large`(2C4G) 或 `e-c1m2.xlarge`(4C8G)。保留实例 ID 与公网 IP，系统盘是云盘故数据保留，需停机。代价是 CPU 仍为共享非独占、IOPS 上限偏低。
2. **新建实例 + 迁移**。本项目的环境完全由 `deploy/provision-alinux4.sh` 脚本生成，数据库为空表，代码在仓库里，RAM 凭证是账号级的，安全组可复用——迁移成本接近于零，只需重跑一次脚本。代价是实例 ID 与公网 IP 会变（客户端目前 `kSyncBaseUrl` 仍指向安卓模拟器 `http://10.0.2.2:8080`，尚未指向本机，故不影响）。


脚本在 Alinux 4 上跑通，两处 RHEL 9 适配均生效：

- `postgresql-setup initdb`（无短横线）成功初始化 PG 15.19
- `postgresql.conf` 第 815 行追加了 `include_dir = 'conf.d'`，`conf.d/99-sync.conf` 的调优参数**确实被加载**——`SHOW shared_buffers` 返回 256MB、`work_mem` 4MB、`max_connections` 50、`password_encryption` scram-sha-256。若沿用旧的无锚点 grep，这几项会静默不生效

Dart 工具链在服务器上验证：

- `dart pub get` 两个包均成功（server 52 个依赖、sync_core 49 个），走 `pub.flutter-io.cn` 镜像
- `dart analyze` 两个包均 **No issues found**
- `dart test` 两个包均 **13 项全部通过**

安全配置实测：

- Postgres 只监听 `127.0.0.1:5432` 和 `[::1]:5432`，不对外暴露
- `pg_hba.conf` 仅放行本地 peer + 127.0.0.1/::1 的 scram
- 外部扫描 22/80/443/5432/8080，只有 22 可达
- 应用凭证 `/etc/diary-sync/pg.env`（0600，owner `diary`），备份 `/root/.diary-sync-pg-credentials`（0600，owner `root`）

> 应用用户 `diary` 的登录 shell 是 `/sbin/nologin`（system account）。用 `su` 进去跑命令需要
> `su -s /bin/bash diary -c '...'`；systemd 单元直接执行二进制，不受影响。

