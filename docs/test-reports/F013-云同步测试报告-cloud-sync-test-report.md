# F013：云同步测试报告

- 关联需求：[F013 云同步设计](../superpowers/specs/云同步设计-cloud-sync-design.md)
- 关联计划：sync_core / 服务端 / 客户端同步引擎 / 客户端 UI 与触发 / 照片同步（五份实现计划）
- 代码状态：`feat/F013-cloud-sync` 分支；宿主自动化测试全过
- 本报告分两轮：**第一轮**为宿主自动化验证、Android 构建与真机验收（真机未执行）；**第二轮**为 ECS 部署链路验收（2026-11-05），DP-01 ~ DP-11 逐项见「第二轮」章节，其中 DP-05 / DP-06 因真机未连接记「未执行」。

## 范围

Phase 4 第一里程碑：邮箱+密码最小身份、同步引擎（字段级 LWW）、照片同步（FakeCos）。
- 包含：sync_core 共享包、服务端（Dart shelf + FakeSyncStore）、客户端同步引擎（RemoteRepo + SyncEngine + 触发/退避/状态）、鉴权 UI + 认领、照片同步（schema v7 photo_key + FakeCos + 上传/下载）。
- 不包含（延后）：PostgresSyncStore（环境无 postgres）、真机腾讯云 COS（环境无 bucket）、SMS/找回、真机端到端验收。

## 宿主验证

环境：Windows 10 Pro；Flutter 3.47.8 / Dart 3.13.7；sqflite_common_ffi（宿主 FFI 测试）。

### 自动化测试分布

| 包/模块 | 测试数 | 覆盖 |
|---|---|---|
| sync_core | 13 | 字段级 LWW、协议编解码、鉴权/COS 抽象契约 |
| server（FakeSyncStore + shelf handler） | 13 | 鉴权、同步合并、seq 游标、handler |
| client（同步引擎核心 + UI + 触发 + 照片） | 415 | schema v6/v7 迁移、时间戳维护、Entry↔SyncEntry 映射、RemoteRepo、SyncEngine 推拉/触发/退避、鉴权 UI、认领、同步状态、照片上传/下载、缩略图 |
| **合计** | **441** | 0 失败 |

> client 415 项含 F001–F011 既有回归（全部不回归）+ F013 新增。

### 检查命令与结果

| 检查 | 命令 | 结果 |
|---|---|---|
| sync_core 静态分析 | `dart analyze`（packages/sync_core） | No issues found |
| server 静态分析 | `dart analyze`（packages/server） | No issues found |
| client 静态分析 | `flutter analyze` | 3 个 pre-existing warning（非 F013 引入，见下） |
| client 调试 APK 构建 | `flutter build apk --debug` | 成功 |

### pre-existing analyze warning（非 F013 引入）

- `client/lib/src/ui/home_page.dart:51` `unused_field _undoableEntryId`（来自 F005 commit 43dfe46）。
- `client/test/data/sync/sync_engine_stamps_test.dart` 两个 unused import。

### 关键修复记录

- **M-16（save 覆盖远端时间戳）**：终审发现 pull 调 save 会用 updatedAt 重算 sync_stamps，丢弃远端字段 t。修：新增 `saveMerged` 保留调用方 syncStamps，SyncEngine.pullOnce 用 saveMerged。TDD RED(5000/1000)→GREEN。
- **Critical（pushOnce 跳过软删除条目）**：终审发现 pushOnce 过滤 `!isDeleted`，导致删除标记不同步。修：移除过滤 + 回归测试。
- **photoKey 持久化**：编辑器 _saveLoop 必须携带 photoKey，否则编辑同步的照片条目会清空 COS key。修：EntryEditorController 携带 photoKey。

## 验收标准对照（AC-01~AC-08，宿主部分）

| 编号 | 场景 | 宿主验证 | 真机 |
|---|---|---|---|
| AC-01 | 邮箱+密码注册登录 | FakeSyncStore + handler 测试通过 | 未执行 |
| AC-02 | 认领机制 | LoginPage 认领弹窗测试通过 | 未执行 |
| AC-03 | 两设备文本同步 | SyncEngine 推拉测试通过 | 未执行 |
| AC-04 | 离线写入→联网推送 | triggerPush 测试通过 | 未执行 |
| AC-05 | 字段级冲突 | mergeFieldLww/applyRemote 测试通过 | 未执行 |
| AC-06 | 照片同步 | FakeCos 上传/下载 + SyncEngine 照片测试通过 | 未执行 |
| AC-07 | 游标原子性 | FakeSyncStore 内存单线程（非真事务） | 未执行（PostgresSyncStore 延后） |
| AC-08 | 401 处理 | 未完整实现（延后） | 未执行 |

## 真机验收：未执行

本轮**未连接 Android 设备**做端到端真机验收。以下项一律记「未执行」，不计入通过：
- 真机注册/登录（FakeSyncStore 无真实服务端）。
- 真机两设备文本/照片同步（无真实服务端 + 无真实 COS）。
- 真机同步状态 UI、认领弹窗实际交互。
- schema v7 迁移在真机库上的表现。

宿主测试用 FakeSyncStore / FakeCos / 替身覆盖逻辑契约，**不能**替代真机结论。

## 已知限制

1. **服务端用 FakeSyncStore（内存）**：环境无 postgres/Docker。PostgresSyncStore（真实 SQL + 事务游标，满足 AC-07）延后。服务端逻辑已宿主测试，真实持久化未验证。
2. **照片用 FakeCos（本地文件系统）**：环境无腾讯云 COS bucket。真机 COS（服务端代理读写、私有 bucket、境内 region）延后。CosGateway 抽象已就位，届时替换实现。
3. **密码哈希是 sha256+salt**：非 bcrypt/argon2。生产部署前必须换。
   → **第二轮已解决**：服务端改用 bcrypt（cost 10，`$2b` 前缀），见「第二轮」章节。
4. **Token 无过期/刷新**：InMemoryTokenStore 重启失 token。AC-08 的 refresh 流程未实现。
5. **baseUrl 硬编码**（`http://10.0.2.2:8080`）：配置化是后续工作。
   → **第二轮已解决**：改为 `--dart-define=SYNC_BASE_URL` 编译期注入，缺省回落 `http://10.0.2.2:8080`。
6. **照片设计缺口**：setPhoto 保留旧 photoKey → 同步条目上新选的照片不重传；远端 photoKey 变更不清本地 BLOB 缓存。后续修。
7. **推送失败静默**：triggerPush 吞掉推送失败，状态显示 synced（违反「不静默失败」）。后续加 push 失败状态。

## 本轮结论

- 通过：441 项宿主自动化测试 + 三包静态分析 + 调试 APK 构建。
- 未执行：真机端到端验收（无连接设备 + 无真实服务端/COS）。
- 是否满足全部必需验收项：宿主可验证部分全部通过；AC-07/AC-08 及真机项未执行，不计入通过。
- 下一步：连接 Android 设备 + 部署真实服务端/COS 后补做真机端到端验收；实现 PostgresSyncStore、真机 COS、bcrypt、token 刷新。

## 环境发现（终审记录）

- 本机 Dart 3.13.7 SDK 的集合 `==` 是身份比较（非 const 的 `['a'] == ['a']` 为 false）。sync_core FieldValue.== 已加深度比较修复。
- `dart:crypto` 在本 SDK 缺失，服务端与 FakeCos 用 `package:crypto`。

---

# 第二轮：ECS 部署链路验收（2026-11-05）

- 关联计划：[云同步-部署链路-ecs-deploy](../superpowers/plans/云同步-部署链路-ecs-deploy.md)
- 被测 commit：`3ea8e91`（分支 `feat/F013-cloud-sync`）
- 服务端：阿里云 ECS `i-7xv4buzm47fxdask0bgz`（cn-guangzhou，公网 `8.148.158.13`），Alibaba Cloud Linux 4.0.6 / kernel 6.6.102，Dart SDK `/opt/dart-sdk`
- 客户端：release APK（`--dart-define=SYNC_BASE_URL=https://8.148.158.13`），小米 2211133C / Android 15
- 验收项：DP-01 ~ DP-11

## 部署结果

`bash /root/deploy-app.sh` 执行成功：`git clone` → `dart pub get` → `dart analyze`（No issues found）→ `dart test`（28 项全过）→ 编译 `/opt/diary-sync/bin/server` → 安装 systemd 单元 → 健康检查 `本机 8080 返回 401` / `diary-sync 运行中`。

服务进程只监听 `127.0.0.1:8080`，对外由 nginx 提供 443 TLS 反代：

```
LISTEN 0 128 127.0.0.1:8080  users:(("dart:server",pid=29362,fd=7))
LISTEN 0 511 0.0.0.0:443      users:(("nginx",pid=29019,fd=6), ...)
```

## DP 验收结果

| DP | 名称 | 结果 | 实际输出 |
|---|---|---|---|
| DP-01 | TLS 证书链校验 | 通过 | `curl --cacert ca.crt https://8.148.158.13/sync?cursor=0` → `401`（握手成功且证书链通过） |
| DP-02 | 服务端四接口 | 通过 | 注册 → 登录 → 推送 `{"ok":true}` → 拉取 `{"cursor":2,"entries":[{"id":"e-dp-1",...}]}` |
| DP-03 | 服务自启 | 通过 | `systemctl restart diary-sync` → `active` + 8080 返回 401 |
| DP-04 | 端口边界 | 通过 | dev 机外部探测：`22 OPEN / 443 OPEN / 8080 CLOSED / 80 CLOSED`；服务端 8080 仅回环可达 |
| DP-05 | 真机可连 | **未执行** | 真机未连接（USB 拔除）。替代证据见下 |
| DP-06 | 真机推送 | **未执行** | 真机未连接。替代证据见下 |
| DP-07 | curl 充当第二设备 | 通过 | 设备B 用另一枚 token 从 `cursor=0` 拉到设备A 推送的 `e-dp-8`（`cursor=2`）；用推进后的 cursor 再拉 → `{"cursor":2,"entries":[]}` |
| DP-08 | 模拟器不受影响 | 通过 | 静态：`sync_config.dart` 缺省仍为 `http://10.0.2.2:8080`；`network_security_config.xml` 的 `10.0.2.2` 仍在 `cleartextTrafficPermitted="true"` 的 domain-config 内 |
| DP-09 | 重复注册 → 409 | 通过 | `重复注册返回 409`（DB 级唯一性落库验证未执行，见「已知代价」） |
| DP-10 | 超长密码 → 400 | 通过 | 73 字节密码注册 → `400`（非 500） |
| DP-11 | 时序防护 | 通过 | 不存在邮箱 140/119/129 ms vs 错误密码 125/128/127 ms，差异在抖动范围内（bcrypt cost 10） |

## DP-05 / DP-06 未执行说明与替代证据

真机未连接，以下两项按项目规范记「**未执行**」，不计入通过：

- **DP-05 真机可连**：release APK 装到真机后能否连 `https://8.148.158.13` 完成登录（内置 CA 生效、不报证书错误）——**未执行**。
  替代证据（仅证明信任链材料一致，不替代真机结论）：
  - APK 内 CA 资源（AGP 混淆后路径 `res/Mc.crt`）与 `deploy/certs/ca.crt` **sha256 完全一致**：`19c76c01be8cbdcefaffd6e421da14db9d0d6119f93e2f70114c67bcd95fa117`
  - APK `libapp.so` 内含 `https://8.148.158.13`、**不含**默认的 `http://10.0.2.2:8080`（dart-define 生效）
  - dev 机公网路径 TLS 校验通过（`401` / 登录成功）
- **DP-06 真机推送**：真机写一篇日记并触发推送、服务端可查到该条目——**未执行**。
  替代证据：请求层（与 App 同一 sync_core 协议、同样的字段形状）全链路通过。

## 请求层全链路验证输出（替代 DP-05/DP-06/DP-07 的协议部分）

设备A 登录 → 推送 → 设备B 重新登录（另一枚 token）→ 拉取：

```
T1 设备A登录 uid=u0 tokenLen=48
T2 设备A推送 {"ok":true}
T3 设备B登录 uid=u0 tokenLen=48 与A不同=yes
T4 设备B全量拉取 {"cursor":2,"entries":[{"id":"e-dp-8","createdAt":1793862888729,
   "fields":{"content":{"v":"验证日记","t":1793862888729},"mood":{"v":"开心","t":1793862888729}}}]}
   e-dp-8出现次数=1 cursor=2
T5 设备B增量拉取 {"cursor":2,"entries":[]}
T6 设备B推送更新字段 {"ok":true}
T7 设备A增量拉取 {"cursor":3,"entries":[{"id":"e-dp-8",...,"fields":{"content":{"v":"验证日记",...},"mood":{"v":"平静","t":1793862948729}}}]}
T8a 设备B推送软删除 {"ok":true}
T8b 设备A拉取软删除 {"cursor":4,"entries":[{"id":"e-dp-8",...,"fields":{...,"deletedAt":{"v":1793863008729,"t":1793863008729}}}]}
T9 鉴权边界 无token=401 错误token=401
```

额外覆盖：**字段级 LWW**（设备B 更新 mood → 设备A 拉到 `mood=平静`，`content` 保留原值）、**软删除传播**（`deletedAt` 能同步到另一设备）、**鉴权边界**、**外部 80/8080 端口不通**。

dev 机走**公网路径**复验同样通过：登录 + `GET /sync?cursor=0` 返回对方推送的条目。

## 本轮关键变更

- **bcrypt 替换 sha256**（Task 2）：`hashPassword` / `verifyPassword`，cost 10、`$2b` 前缀、72 字节上限；`users` 表去掉 `salt` 列（schema.sql 同步）。不存在邮箱也执行一次等价 bcrypt 以抹平时序差异。
- **消除邮箱枚举**（评审发现）：`login` 对已注册邮箱 + 超 72 字节密码原会因 `verifyPassword` 吞掉 `ArgumentError` 返回 401（而未注册邮箱返回 400），状态码泄露注册状态。修：`login` 先做长度预检抛 `ArgumentError` → 400，附回归测试。
- **客户端配置化**（Task 5）：`SYNC_BASE_URL` 编译期注入 + 网络安全配置（系统 CA 与自签 CA 并列追加，不顶掉系统信任库）。
- **部署产物**（Task 6）：nginx TLS 配置、systemd 单元（含 `ProtectSystem=full` / `NoNewPrivileges` / `PrivateTmp` 加固）、幂等部署脚本。

## 已知代价

1. **服务端仍是 FakeSyncStore（内存）**：进程重启后账号与全部同步数据清空（本次验证中已实际发生一次——服务重启后 `dp@local.test` 不存在，需重新注册）。PostgresSyncStore 未接入，生产不可用。
2. **DP-09 的 DB 级落库验证未执行**：当前只验到 409 行为，bcrypt 哈希是否真的以 `$2b$` 形式落进 `users.password_hash` 未验（需 PostgresSyncStore 接入后补）。
3. **证书绑死 IP** `8.148.158.13`，且 CA 私钥只在开发机；IP 变更需重签并重新发版 APK。
4. **release APK 仍用 debug keys 签名**，正式发布前需配置真实签名。
5. **服务端 nginx 已被公网扫描器探测到**（日志见 `195.96.139.110` 扫 `/` → 404）；当前未做额外加固，仅 443 对外且需证书。
6. **实例规格**：`ecs.e-c1m1.large`（1.6 GiB 突发型），正式承载数据库前建议变配到 `ecs.g7.large`（跨规格族不可直接变配）。
7. **真机 COS**、**token 刷新（AC-08）**、**真机端到端验收**均未执行/未实现。

## 本轮结论

- 通过：DP-01、DP-02、DP-03、DP-04、DP-07、DP-08、DP-09、DP-10、DP-11（9 项）。
- 未执行：DP-05、DP-06（真机未连接）；DP-09 的 DB 落库部分；真机 COS；跨设备真机同步。
- 是否满足全部必需验收项：**否**。真机相关的 DP-05 / DP-06 未执行，不计入通过；其余部署链路验收项全部通过。
- 下一步：连接真机补做 DP-05 / DP-06；接入 PostgresSyncStore 后补做 DP-09 落库验证与真机 COS；实现 token 刷新（AC-08）。
- 未完成项的逐条登记见 [F013 待办登记表](../features/F013-待办-todos.md)。

## 第三轮：对象存储供应商迁移与命名对齐（2026-11-05）

- 关联设计：[腾讯云 COS 对象存储](../superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md)
- 被测 commit：`9400896`（分支 `feat/F013-cloud-sync`；本节记录于其后的报告提交）
- 改动性质：纯机械重命名 + 文档替换，**运行行为不变**

| 检查 | 结果 |
|---|---|
| sync_core 静态分析 | No issues found |
| server 静态分析 | No issues found |
| client 静态分析 | 无新增 warning |
| sync_core 测试 | 13 项全过 |
| server 测试 | 31 项全过 |
| client 测试 | 442 项全过 |
| client 调试 APK 构建 | 成功 |

- 命名：`OSSGateway`→`CosGateway`、`FakeOSS`→`FakeCos`、`oss_gateway.dart`→`cos_gateway.dart`、`fake_oss.dart`→`fake_cos.dart`、`SyncEngine.oss`→`SyncEngine.cos`。
- 文档：产品设计、F012、F013 待办与台账、云同步设计、三份实现计划、测试报告、OPPO 上架清单、开源仓库资料中的对象存储表述统一为腾讯云 COS；ECS 侧事实表述保持不动。
- 新增：`deploy/腾讯云COS配置-tencent-cos-setup.md`、`deploy/cam-policy.json`。
- **未执行**：真机腾讯云 COS 读写（T-05 / T-24）。桶尚未创建，本次不含任何真实 COS 链路的验证证据。

---

## 第四轮：在线缺陷修复与部署脚本加固（2026-11-09）

- 被测 commit：`887ed06`（FakeSyncStore 修复）、`4cebc3d`（deploy-app.sh 加固），分支 `feat/F013-cloud-sync`；经合并提交合入 `main`
- 变动性质：缺陷修复 + 脚本加固，无对外行为新增

### 缺陷与修复

1. **FakeSyncStore 跨用户条目覆盖**：`FakeSyncStore._entries` 此前以条目 `id` 全局索引，与
   `deploy/sql/schema.sql` 中 `entries` 的 `(user_id, id)` 主键口径不一致——两个用户推送相同
   `id` 条目时后者覆盖前者，造成跨用户数据丢失。修：条目按 `(userId, id)` 复合键存储，用户 id
   分配改用独立计数器（不再占用条目 seq），首个 push 的条目 seq 从 1 开始（与 DP-02 期望一致）。
   新增 3 项回归测试：
   - 跨用户同 id 不互相覆盖：A 的条目不会被 B 的同名条目顶掉
   - 跨用户同 id 各自独立合并：A 的后续更新不会污染 B
   - 用户 id 分配不占用条目 seq：首个 push 的 seq 从 1 开始

   同步更新 `schema.sql` 头部注释，消除「内存实现缺陷」的过时描述。
2. **deploy-app.sh 健康检查断言（对应待办 T-21）**：未带 token 访问 `/sync` 断言返回 401（鉴权生效）；
   curl 失败或状态码不符时先输出 systemctl/journalctl 诊断再退出；git 仓库目录归 root 归属（解决
   "dubious ownership"）；运行用户 diary 只持有二进制与状态目录 `/var/lib/diary-sync`；新增 `STATE_DIR`。

### 验证结果（本机）

| 检查 | 结果 |
|---|---|
| packages/server 全量 `dart test` | 31 项全过（含新增 3 项回归） |
| `bash -n deploy/deploy-app.sh` | 语法检查通过 |

### 未执行

- ECS 上重新部署执行新脚本（文档化的健康检查断言/权限链路尚未在 ECS 实测，T-21 记「已改待部署」）。
- DP-05 / DP-06 真机验收（真机仍未连接）、真机 COS（T-05 / T-24 未启动）。

---

## 第五轮：腾讯云 COS 代理实现与 ECS 冒烟（2026-11-10）

- 关联：[COS 设计](../superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md) · [待办](../features/F013-待办-todos.md)
- 被测 commit：`9fa68f5`（分支 `feat/F013-cos-proxy`）；ECS 部署镜像 = 同分支
- 凭证：COS 桶 `write-down-1341994447`（ap-guangzhou，私有）；CAM 子用户最小权限（PutObject/GetObject/HeadObject，仅 `photos/*`）；密钥仅存 ECS `/etc/diary-sync/cos.env`（0600），不入库、不下发客户端

### 实现

- 服务端 `packages/server/lib/src/cos_proxy.dart`：腾讯云 COS v1 签名（`q-sign-algorithm=sha1`，对照官方 SDK `cos-go-sdk-v5 auth.go` 逐行验证）+ 照片代理端点：
  - `POST /sync/photo/upload`：body = 照片字节 → 服务端算 sha256 → 签名 PUT `photos/<sha256>` → 返回 `{"ok":true,"key":...}`
  - `GET /sync/photo/<key>`：签名 GET 透传字节
  - `HEAD /sync/photo/<key>`：秒传判存 → 200 / 404
  - 全部端点走与 `/sync` 相同的 Bearer token 鉴权；COS 调用异常归一为 502 并打日志
- 客户端 `client/lib/src/data/sync/cos_gateway_http.dart`：`HttpCosGateway`（`--dart-define=USE_COS_HTTP=true` 启用，缺省回落 FakeCos），零云 SDK、零预签名。
- 部署：nginx `client_max_body_size` 8m → 16m；`diary-sync.service` 新增 `EnvironmentFile=-/etc/diary-sync/cos.env`；`deploy-app.sh` 编译前先停服务（避免 ETXTBSY）。

### 验证

| 检查 | 结果 |
|---|---|
| server `dart analyze` / `dart test` | No issues found / 48 项全过 |
| client `flutter analyze` / `flutter test` | 仅 pre-existing 警告 / 447 项全过 |
| ECS 部署（deploy-app.sh 全链路） | 拉分支 → pub get → analyze → 48 测试 → 编译 → 安装 → 重启 → 健康检查 401 全过 |
| ECS 冒烟（真实 COS） | 注册 → 上传 `{"ok":true,"key":"photos/b84a387b…"}` → 下载字节与原文件 `cmp` 一致 → HEAD 判存 200 / 404 全过 |

### 冒烟中暴露并修复的缺陷（回归测试已补）

- **D-01**：COS URL 缺主机/路径分隔符（`myqcloud.comphotos`）→ DNS 失败（`144ef0e`）
- **D-02**：systemd unit 行内中文注释使 `EnvironmentFile` 被静默跳过，COS 凭证不加载（`7d22850`）
- **D-03**：`getObject` 对非 200 状态把 COS 错误响应体当数据返回（`c2bd43a`）
- **D-04**：签名 `uriPath` 缺前导 `/`，与请求路径不一致 → SignatureDoesNotMatch 403（`093efdf`）
- **D-05**：shelf_router 通配路由误用 `<...>`（应为正则参数 `<any|.*>`）→ 下载/判存 404（`9fa68f5`）

### 未执行

- 真机双设备照片同步验收（T-24 真机子项）：需连真机 + `--dart-define=USE_COS_HTTP=true` 构建 release APK；T-01/T-02 真机验收同轮补做。
- 客户端上传前压缩（T-25 缓解）并入真机轮评估。
- 冒烟残留对象（`photos/probe.txt`、`photos/b84a387b…`）：CAM 策略刻意不授 DeleteObject，清理走控制台单独流程。
