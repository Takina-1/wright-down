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
- 未执行：DP-05、DP-06（真机 UI 交互；服务端等价链路已在第六轮以 API 等效验收覆盖，真机点击待补）；DP-09 的 DB 落库部分；真机 COS UI 链路；跨设备真机同步。
- 是否满足全部必需验收项：**否**。真机相关的 DP-05 / DP-06 UI 交互未执行。
- 下一步：真机可点按装机弹窗时补做 DP-05/DP-06；接入 PostgresSyncStore 后补做 DP-09 落库验证；实现 token 刷新（AC-08）。
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

## 第六轮：真机验收尝试与服务端 API 等效验收（2026-11-10）

### 尝试与受阻（真机装机）

- 真机在线（Xiaomi 2211133C，Android 15，MIUI，adb 授权正常）；T-01 前置条件全部满足：
  - ECS 在线，`GET /sync` 无 token 返回 **401**（鉴权生效，T-21 断言链路与线上一致）
  - CA 信任链三级校验一致：服务器 `/etc/nginx/ssl/diary-sync/ca.crt` sha256 指纹
    （`7C:ED:3A:85:…`）= 本机 `deploy/certs/ca.crt` = APK 内嵌 `res/raw/diary_ca.crt`
- 客户端 `network_security_config.xml` 信任 `@raw/diary_ca`（系统 CA + 自签并列），
  **无需 root** 导入系统证书。
- debug APK 构建成功（`flutter build apk --debug`，已注入
  `--dart-define=SYNC_BASE_URL=https://8.148.158.13 --dart-define=USE_COS_HTTP=true`）。
- **安装受阻（环境限制，非代码缺陷）**：MIUI 定制安装器强制弹人工确认框，
  `adb install`（含 `-r -g -t`）、`pm install`（`-r -g`，路径 `/data/local/tmp` 已避开
  SELinux FUSE 拦截）均返回 `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user`；
  adbd 非 root 无法代点；本机无 `sdkmanager` 可用模拟器镜像（安装中 Flutter 占用解包目录
  致 sdkmanager 崩溃，且无 KVM 验证路径）。

### 服务端 API 等效验收（脚本：`scripts/f013-api-acceptance.sh`）

真机弹窗不可绕过后，对 T-01/T-02/T-04/T-24 所覆盖的**服务端链路**用真实 HTTP
（经 nginx 443）做了等效验收：

| 检查 | 结果 |
|---|---|
| TLS 链（本地 CA 指纹三级一致 + 401 即证明握手与鉴权链建立） | 通过 |
| 注册（curl ↔ `/auth/register`） | 200，返回 userId/token |
| 登录负路径（错误密码） | 401，符合预期 |
| **推送**（`POST /sync/batch`，字段 `content`，t=毫秒戳，等效 DP-06 真机新建日记） | **200** |
| **拉取回流**（`GET /sync?cursor=0`，等效第二台设备拉取） | 拉到刚推送的 `e-acc-1`，cursor=1 |
| 鉴权断言（坏 token） | 401 |
| COS 上传（X-Photo-Hash 裸 sha256 → `photos/<sha256>`） | 200 + 正确 key |
| COS 下载字节比对 | 一致 |
| COS HEAD 判存 | 存在 200 / 不存在 404 |

> 等效性边界：本验收证明**服务端侧**（TLS/鉴权/协议/推送拉取/COS 代理）全链路可用，
> 但不替代真机 UI 交互验收（登录页点击、写日记保存、双设备同步）——
> 真机弹窗确认仍留待用户到场时补做，待办表如实保留「真机 UI 未执行」状态。

### 退出时已知事实

- FakeSyncStore 内存态：`u1`/`u2` 等历史注册数据与本次验收数据在不同运行实例间不持久
  （服务多次重启，日志可见），再次印证 T-06 PostgresSyncStore 的优先级。

### 未执行

- 真机 UI 交互验收（登录、写日记、双设备照片同步）：待真机可点按安装弹窗时补做。
- 客户端上传前压缩（T-25 缓解）。
- T-03 落库验证：**第七轮已补**（见下）——FakeSyncStore 无真实 DB 的阻塞随 T-06 关闭而解除。

## 第七轮：PostgresSyncStore 落库（2026-11-10）

### 目标与背景

FakeSyncStore 是内存实现，ECS 上服务每次重启，全部注册账号与已同步日记即清空
（日志实证：`dp@local.test`、第六轮验收用户 `u1/u2/u3` 重启后登录 401）。
本轮回填设计文档 AC-07（推送与游标推进同事务、不丢不重）。

### 实现（分支 `feat/F013-server-postgres`，commit `0189ea2` / `73ba49a`）

- `packages/server/lib/src/postgres_sync_store.dart`：`PostgresSyncStore implements
  SyncStore`，语义与 FakeSyncStore 逐条等价：
  - register：邮箱冲突 → StateError（handler 409）；id 生成 `u<ms><4hex>`；bcrypt `$2b$10`。
  - login：邮箱不存在也跑一次 bcrypt（防时序）；超长口令抛 ArgumentError（400）；
    校验失败返回 null（401）。
  - pull：`seq > cursor` 升序；空批 cursor 不变；非空推进到本批 max seq。
  - push：**单事务**；逐 patch 经 `sync_seq` 行锁 `UPDATE ... RETURNING` 取号
    （锁持有至提交——AC-07 串行化）；字段级 LWW（`FieldValue.t` 毫秒戳）；
    `ON CONFLICT (user_id, id) DO UPDATE` 覆盖 payload/seq，created_at 首次写入后冻结；
    payload 存 JSONB（`payload::text` 读回后 Dart `jsonDecode`，与 sync_core 编码一致）。
- `packages/server/lib/src/pg_config.dart`：`PG_*` 环境变量 → 连接配置。
- `packages/server/lib/src/main.dart`：PG 凭证齐全 → `PostgresSyncStore.connect`，
  缺任一 → FakeSyncStore 回退 + `[warn]`。
- `packages/server/test/postgres_sync_store_test.dart`：5 项集成测试
  （无 PG env 时 `skip` 不 fail）。
- `deploy/diary-sync.service`：加 `EnvironmentFile=-/etc/diary-sync/pg.env`。
- **SSL**：postgres 包 3.6 默认要求 SSL；ECS 本地 PG 未启用，连接显式
  `SslMode.disable`（commit `73ba49a`）。

### 验证（ECS 真实 PostgreSQL 15.19）

| 检查 | 结果 |
|---|---|
| `dart analyze`（本机） | No issues found |
| `dart test`（本机，无 PG env） | 48 过 + 5 skip（PG 集成按设计跳过） |
| ECS `deploy-app.sh` 全链路（`feat/F013-server-postgres`） | 拉代码 → pub get → analyze → 48 过 → 编译 → 装单元 → 401 健康检查 全过 |
| ECS 真实 PG 集成测试（`source pg.env && dart test`） | **5/5 全过**：注册/登录/token/鉴权、push/pull/游标、字段级 LWW+created_at 冻结、跨用户同 id 隔离+payload 往返、并发 push 不丢条目 |
| DP-09 落库验证 | `select left(password_hash,4)` → `$2b$`；重复邮箱注册 409；entries 10 行 seq 全部唯一 |
| **重启持久化**（`scripts/pg-persistence-verify.sh`） | register → push → pull → `systemctl restart` → login 成功 → pull 条目仍在（FakeSyncStore 时代必挂） |

### 未执行 / 遗留

- 连接管理为单连接演示环境（并发正确性已验证；吞吐上限评估后再升级 ConnectionPool）。
- T-07 token 过期刷新、T-08 客户端 token 持久化、T-13~T-23 运维事项见待办表。
- 真机 UI 交互（T-01/T-02/T-04）仍待装机弹窗可点时补做。

## 第八轮：触发循环与照片同步缺陷修复（2026-11-10）

### 目标

修复 Part 3b/Part 4 终审发现的四个缺陷（T-09~T-12）：三个触发循环缺陷与两个照片同步缺口。

### 实现（分支 `feat/F013-trigger-photo-fixes`，commit `10cb47a`）

全部改动在 `client/lib/src/data/sync/sync_engine.dart`：

- **T-09（I-2）**：`triggerPush` 的定时器回调——推送失败时 `_setState(SyncState.failed)`
  （原实现 try/catch 吞掉异常，状态停留在 synced）。与 `triggerPull` 的状态语义对称。
- **T-10（I-3）**：`start()` 检测 `_stateController.isClosed` 时重建流并重置
  `SyncState.idle`（原实现 stop 关流后 start 复用死流，广播被静默丢弃）。
- **T-11（I-1）**：`triggerPush` 拆出 `_schedulePush`，安排前登录态预检
  （`_me()` 异步判定，未登录直接返回——登出后不浪费一次推送循环）。
- **T-12（照片）**：新增 `_photoHash`（sha256 hex，与 FakeCos/HttpCosGateway
  的 photoKey 口径一致）：
  - pushOnce 上传条件改为 `photo != null && (photoKey == null || _photoHash(photo) != photoKey)`——
    同条目换照片后 hash 不匹配即重传；
  - pullOnce 下载条件改为 `photoKey != null && (photo == null || _photoHash(photo) != photoKey)`——
    远端 photoKey 变更时本地旧 BLOB 被新照片覆盖。
- `triggerPush` 接受可选 `debounce` 参数（默认 30s 不变；测试传短时长）。

### 测试（新增 5 项，全部通过）

| 缺陷 | 测试 | 结果 |
|---|---|---|
| T-09 | push 注入异常 → triggerPush → 状态置 failed | 通过 |
| T-10 | start → stop → start → 新流可广播状态 | 通过 |
| T-11 | 未登录 triggerPush → pushes 为空 | 通过 |
| T-12 | 同条目换照片 → push 重传，photoKey 更新为新 hash | 通过 |
| T-12 | 远端 photoKey 变更 → pull 重下覆盖本地 BLOB | 通过 |

### 验证

| 检查 | 结果 |
|---|---|
| `flutter analyze client` | 干净（仅 pre-existing 警告/info） |
| `flutter test client` 全量 | **452 项全过**（447 原有 + 5 新增） |
| ECS 部署 | 无需——纯客户端逻辑，服务端不变 |

### 遗留

- T-07 token 过期刷新、T-08 客户端 token 持久化：**第九轮已补**（见下）。
- 真机 UI 交互（T-01/T-02/T-04）仍待装机弹窗可点时补做。

## 第九轮：Token 过期刷新与持久化（T-07/T-08，2026-11-10）

### 目标

AC-08 完整落地：服务端 refresh token 机制；客户端 401 → refresh → 重试一次 → 停同步提示；token 经 SharedPreferences 持久化（App 重启免登录）。

### 实现（分支 `feat/F013-token-refresh-persistence`，commit `1f6d09e`）

**服务端**：
- `deploy/sql/schema.sql`：`tokens` 表加 `expires_at`（NULL 兼容存量）；新增 `refresh_tokens` 表（30 天过期）。
- `PostgresSyncStore`/`FakeSyncStore`：register/login 签发 access(7d)+refresh(30d)；`userIdForToken` 校验 expires_at（过期→401）；新增 `refresh()`——校验→轮换（DELETE 旧+INSERT 新）→新 access+refresh。
- `handlers`：新增 `POST /auth/refresh` 端点；register/login 响应带 refreshToken。
- `sync_core` `AuthResult`：加可选 `refreshToken`（向后兼容）。

**客户端**：
- `AuthSession` 模型（access+refresh+expiresAt）+ `SharedPreferencesTokenStore`（T-08）+ `InMemoryTokenStore` 改存 AuthSession。
- `EmailPasswordProvider.refresh()`：调 `/auth/refresh` → 存新 AuthSession。
- `RemoteRepo`：pull/push 收到 401 → `tokenRefresher` 换新 access → 重试一次 → 仍 401 → 抛 StateError；新增 `refresh()` 方法。
- `main.dart`：装配 SharedPreferencesTokenStore + tokenRefresher。

### 验证（ECS 真实 PostgreSQL）

| 检查 | 结果 |
|---|---|
| `dart analyze`（server/sync_core） | 干净 |
| `dart test`（本机，无 PG env） | 48 过 + 8 skip |
| `flutter analyze client` | 干净（仅 pre-existing） |
| `flutter test client` 全量 | **458 项全过**（452 原有 + 6 新增） |
| ECS schema 变更（ALTER+CREATE） | 幂等执行成功 |
| ECS `deploy-app.sh` 全链路 | 拉代码→pub get→analyze→48 过→编译→装单元→401 健康检查 全过 |
| ECS 真实 PG 集成测试 | **8/8 全过**（含 refresh/轮换/过期 3 项新增） |
| **curl 冒烟**（`scripts/t07-refresh-smoke.sh`） | register→access+refresh→pull 200→refresh 换新→pull 200→旧 refresh 作废 401→过期 access 401→refresh 重试→pull 200 全链路通过 |

### 遗留

- SharedPreferences 明文存 token——未来可加加密。
- 403 处理（账号/设备失效）——设计文档第 8 节——当前服务端不返回 403——留待后续。
- 真机 UI 交互（T-01/T-02/T-04）仍待装机弹窗可点时补做。

## 第十轮：D 节质量改进（2026-11-10）

### 目标

清理评审 Minor 项（T-18~T-23）——纯代码/脚本小改，无服务端行为变更。

### 改动（分支 `feat/F013-quality-minors`，commit `30aa251`）

| 编号 | 改动 | 位置 |
|---|---|---|
| T-18 | `PORT` 范围校验（1–65535），非法值回落 8080 | `server_config.dart` |
| T-19 | `verifyPassword` 捕获从 `on Object` 收窄为 `on ArgumentError` | `password.dart` |
| T-20 | CA-pair guard 同时检查 `ca.key` 与 `ca.crt` | `make-cert.sh` |
| T-21 | 健康检查断言 401——第四轮已实现，T-06/T-07 ECS 部署健康检查均验证通过——关闭 | `deploy-app.sh` |
| T-22 | `deploy-app.sh` 加执行位（100644 → 100755） | `deploy-app.sh` |
| T-23 | 清理 `unused_field _undoableEntryId`（F005 遗留） | `home_page.dart` |

### 验证

| 检查 | 结果 |
|---|---|
| `dart analyze packages/server` | No issues found |
| `dart test packages/server` | 48 过 + 8 skip |
| `flutter analyze client` | 0 error（仅 pre-existing warning/info） |
| `flutter test client` 全量 | 458 项全过 |
| `bash -n deploy/make-cert.sh` | 语法检查通过 |
| ECS 部署 | 无需——纯代码/脚本小改，无服务端行为变更 |

### 遗留

- C 节运维事项（T-13 release 签名、T-15 规格变配、T-16 RAM 策略附加）需用户输入/停机决策。
- T-17 nginx 扫描器限流——线上变更，待用户确认后执行。
- T-25 ECS 带宽——已知限制，用户已知悉。
- 真机 UI 交互（T-01/T-02/T-04）仍待装机弹窗可点时补做。

## 第十一轮：安卓真机 TLS 信任修复与端到端验收（2026-11-15）

### 目标与根因

打通 F013 T-01/T-02 真机验收。根因确认 —— Flutter `dart:io` 网络栈**不读**
`network_security_config.xml`，自签 CA 虽随 APK 分发在 `res/raw/diary_ca.crt`，Dart 层却看不到，
TLS 握手在收到服务器证书后即中止，真机注册必然失败（证据链：`libflutter.so` 中
`networkSecurityConfig` 出现 0 次，见设计文档 §4）。

### 修复

新增 `TlsTrust`（`SecurityContext(withTrustedRoots: true)` + `setTrustedCertificatesBytes`），
CA 以 asset 随包分发，主流程与照片代理共用同一可信 client；`deploy/make-cert.sh` 自动同步两处 CA 副本。
详见设计文档与分支 `feat/F013-android-tls-trust`。

### 验证

| 项 | 值 |
|---|---|
| 被测版本 | `feat/F013-android-tls-trust` + `client/build/app/outputs/flutter-apk/app-debug.apk`（`--dart-define=SYNC_BASE_URL=https://8.148.158.13 --dart-define=USE_COS_HTTP=true`） |
| 环境 | 小米 2211133C（Android 15 / MIUI）、ECS `8.148.158.13`（nginx TLS 443 + systemd `diary-sync` + PostgreSQL） |
| 缺陷根因 | `dart:io` 不读 `network_security_config.xml`；证据链见设计文档 §4 |
| 修复 | `TlsTrust`（`SecurityContext(withTrustedRoots: true)` + `setTrustedCertificatesBytes`） |
| 命令 | `..\scripts\flutter.ps1 analyze` / `test` / `build apk --debug` |
| 宿主结果 | analyze 仅 pre-existing 警告/info、无新增；`flutter test` **461 项全过**（基线 458 + TlsTrust 3） |
| 真机 T-01 | nginx `POST /auth/register` **200**，UA `Dart/3.13 (dart:io)`（19:22:59）；psql 用户 `f013-device-1794741769@local.test` 落库（`$2b$` bcrypt）——**已验证** |
| 真机 T-02 | nginx `POST /sync/batch` **200**，UA `Dart/3.13 (dart:io)`（19:27:17）；psql 条目 `9267c356-…` 落库，payload `{"v":"T02-device-push-test-…"}`，seq 24——**已验证** |
| APK 内嵌 CA | `assets/flutter_assets/assets/diary_ca.crt`，`subject=CN=Local Diary App CA`，sha256 指纹 `7C:ED:3A:…:7E:00`，与服务器/本机一致 |
| logcat | 无 `HandshakeException`/`CERTIFICATE_VERIFY`（与 nginx 200 一致） |
| 验收编号 | T-01（注册）、T-02（推送）已验证；T-04（跨设备）、T-24（真机照片）未执行 |
| 失败项 | 无 |
| 未测范围 | 双设备交叉同步（T-04 第二台设备）、真机照片链路（T-24）、release APK（仍 debug 签名，T-13） |

> 装机说明：旧 APK（11-10 debug 签名）与新 APK 签名不匹配，`adb install -r` 报
> `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，先卸载再全新安装；MIUI 安装弹窗需人工点确认
> （无法无头绕过，经 `am start` VIEW 意图拉起安装器完成）。

### 遗留

新增待办 T-30（私有 CA 内嵌 APK 公开分发风险）/ T-31（登录失败吞掉底层原因）/ T-32（未登录状态误显「已同步」），见 [待办表](../features/F013-待办-todos.md)。

## 第十二轮：T-31 登录错误透出与 T-32 未登录状态语义（2026-11-15）

### 目标

清理第十一轮新发现的两项客户端问题：登录/注册失败吞掉底层原因（T-31）、未登录时同步状态误显「已同步」（T-32）。

### 修复（分支 `feat/F013-sync-error-transparency`）

- **T-31**（`client/lib/src/ui/sync/login_page.dart`）：`_submit` 的 `catch (_)` 改为 `catch (e)`，新增 `_describe(e)` 把异常转成可读描述——`HandshakeException`→「TLS 握手失败（服务器证书未通过校验）」、`SocketException`→「网络连接失败」、`StateError`→其消息、其余回退 `e.toString()`。错误文案由笼统「注册失败，请重试」改为「注册失败：${_describe(e)}」，透出底层原因便于真机排障。
- **T-32**（`client/lib/src/data/sync/sync_engine.dart`）：`triggerPull` 增加登录预检——`_me()` 返回 null 时直接返回，不置 `synced`，与 `triggerPush` 的 T-11 登录预检对称。此前未登录时 `pullOnce` 提前返回不抛异常，`triggerPull` 会把状态置为 `synced`（误显「已同步」）。

### 测试（新增 2 项，全部通过）

| 编号 | 测试 | 结果 |
|---|---|---|
| T-31 | 登录失败透出 TLS 握手异常原因（`HandshakeException` → TLS 文案） | 通过 |
| T-32 | 未登录 `triggerPull` 不置 `synced`（状态保持 idle、不发起拉取） | 通过 |

> T-31 同时更新了 `login_page_test` 既有 2 处失败文案断言（`StateError` 消息透出）。

### 验证

| 检查 | 结果 |
|---|---|
| `flutter analyze` | 仅 pre-existing 4 项（无新增） |
| `flutter test` 全量 | **463 项全过**（461 原有 + 2 新增） |

### 遗留

- T-30（私有 CA 内嵌 APK 公开分发风险）留待公开发布前处理。
- T-04（跨设备第二台）、T-24（真机照片链路）仍待第二台设备。

## 第十三轮：Cloudflare 公网证书与域名迁移（2026-11-18）

### 目标

把自签 CA + IP 直连（`https://8.148.158.13`）迁移到 Cloudflare 代理 + 公网证书 + 域名（`https://sync.takina.dpdns.org`），解决 T-14（证书绑死 IP）、T-30（私有 CA 内嵌 APK 公开分发风险），并绕开备案网关对 Cloudflare→源站入站 443 的拦截（525）。

### 根因与方案

- **备案网关拦截**：Cloudflare 代理模式连源站 443 时用域名 SNI，备案网关按域名拦截非备案域名 → TLS 握手失败 → HTTP 525。设备直连 IP 可用（SNI 是 IP，不匹配域名）。
- **方案**：改用 **Cloudflare Tunnel（cloudflared）**——ECS 上 cloudflared 出站连 Cloudflare，不经过入站 443，备案网关拦不到。cloudflared 转发到本地 Dart（`127.0.0.1:8080`），绕过 nginx 与自签证书。Cloudflare 提供 Let's Encrypt 公网证书。

### 客户端改动（分支 `feat/F013-cloudflare-domain-migration`）

- `TlsTrust` 退化为仅信任系统 CA（`withTrustedRoots: true`），去掉 `rootBundle` 加载自签 CA；`clientWithTrustedCerts` 保留供测试注入。
- 删除 `assets/diary_ca.crt`、`res/raw/diary_ca.crt`；`pubspec.yaml` 去掉 assets 入口；`network_security_config.xml` 去掉 `@raw/diary_ca`。
- `make-cert.sh` 去掉客户端 CA 同步（云端走 Cloudflare 公网证书）。
- `tls_trust_test` 删掉 2 个依赖自签 asset 的用例。

### 服务器侧

- ECS 安装 cloudflared 2026.11.1，systemd 常驻，`--config /etc/cloudflared/config.yml`。
- ingress：`sync.takina.dpdns.org → http://127.0.0.1:8080`；Cloudflare DNS 建 CNAME 指向隧道。
- cloudflared 日志：4 条 `Registered tunnel connection`，precheck 全 PASS，无 503。

### 验证（真机：小米 2211133C / Android 15 / MIUI）

| 项 | 证据 | 结果 |
|---|---|---|
| 公网访问 | `https://sync.takina.dpdns.org/sync` → 401（`/` → 404，Dart 无根路由） | 通过 |
| 证书 | issuer = Let's Encrypt（公网 CA，非自签） | 通过 |
| logcat | 无 `HandshakeException`/`CERTIFICATE_VERIFY` | 通过 |
| **T-01 注册** | psql 用户 `f013-cloud-1794933416@local.test` 落库（`$2b$` bcrypt）——请求经 Cloudflare 隧道到达 Dart | **通过** |
| **T-02 推送** | psql 条目 `13e71999-…` 落库，payload `{"v":"T02-cloud-push-test-…"}`，seq 26 | **通过** |
| **T-04 拉取** | PG 插入模拟他设备推送的条目 `t04-pull-test-0001`（seq 28），真机重启触发 pull，本地 SQLite 查得该条目——拉取链路（设备→Cloudflare→隧道→Dart→PG→拉回本地）验证通过 | **通过**（拉取链路；严格双物理机仍待第二台） |

### 宿主验证

| 检查 | 结果 |
|---|---|
| `flutter analyze` | 仅 pre-existing 4 项（无新增） |
| `flutter test` 全量 | 461 项全过（删 2 个自签 asset 用例） |

### 遗留

- T-04（跨设备第二台拉回）、T-24（真机照片链路）仍待第二台设备。
- T-13（release 签名）、T-15（实例变配）等运维项不变。

## 第十四轮：T-24 真机照片链路验证（2026-11-19）

### 目标

验证 F013 最后一块未闭环的功能：真机照片随日记推送 → 经 ECS 代理写入腾讯云 COS → 拉回时字节一致（AC-06 / T-24）。

### 验证（真机：小米 2211133C / Android 15 / MIUI；云端：Cloudflare 隧道 → ECS `diary-sync` → 腾讯云 COS）

| 环节 | 证据 | 结果 |
|---|---|---|
| 真机选照片 | 设备相册选图（543KB JPEG），编辑器出现缩略图 | 通过 |
| 照片上传 | `POST /sync/photo/upload` → HTTP **200**，key `photos/b45d866019c05b22bea004a46e03ca9967c8b01e8ab1907f76a704f1fa9b092c` | 通过 |
| photoKey 落库 | PG 条目 seq 58 的 `photo` 字段 = `{"v":"photos/b45d8660…92c"}` | 通过 |
| COS 对象命名 | 对象 key 后缀 == 照片实际 sha256（`b45d8660…92c`） | 通过 |
| 照片拉回 | 经隧道 `GET /sync/photo/<key>` → 200，543037 字节 | 通过 |
| **字节一致性** | 下载字节 sha256 == 设备本地 BLOB sha256 == `b45d8660…92c`，**逐字节一致** | **通过** |

> 隧道链路：App → Cloudflare（Let's Encrypt 公网证书）→ cloudflared 隧道 → Dart `127.0.0.1:8080` → COS 代理 → 腾讯云 COS → 原路返回。543KB 照片经隧道上传实测 **18 秒**（ECS 出向 ~428 KB/s，T-25 已知限制）。

### 同轮新发现的两个真实缺陷（已登记待办）

| 编号 | 现象 | 影响 |
|---|---|---|
| **T-33** | 服务端返回的 photoKey 带 `photos/` 前缀，客户端却用**裸** sha256 比对 → 永不相等 → **每次推送都重传照片** | 543KB/张 × 每次推送 ≈ 18 秒白等 + 流量浪费 |
| **T-34** | 推送触发点为退后台/退出与切标签；**切标签在前台 → 5.2 秒推送完成；退后台 → Dart isolate 被 Android 挂起，`await` 迟迟不返回**（实测条目约 40 分钟后才落库），状态停在 `synced` 误示已同步 | 用户写完日记直接切走/退出时，日记可能长时间同步不出去 |

**定位方法**：给 `SyncEngine.triggerPush`/`_schedulePush`/`pushOnce` 与 `HttpCosGateway.upload` 加临时 `print`（debug APK 的 Dart print 可在 logcat 的 `flutter` 标签看到），配合 cloudflared `--loglevel debug` 看请求是否到达隧道——确认退后台期间设备只发 GET（拉取，前台触发）不发 POST（推送）。调试 print 已在验证后全部还原，cloudflared 日志级别已恢复 `info`。

### 严格双设备部分

T-24 的**双设备互传**（A 设备推 → B 设备拉回照片）仍需第二台设备，本轮未执行，已如实登记。

### 宿主验证

| 检查 | 结果 |
|---|---|
| `flutter analyze` | 仅 pre-existing 4 项（无新增） |
| `flutter test` 全量 | 463 项全过（本轮无代码改动） |

## 第十五轮：T-33 / T-34 缺陷修复与真机复验（2026-11-23）

### 目标

修复第十四轮真机照片验证中发现的两个真实缺陷，并真机复验。

### 缺陷与修复

| 编号 | 根因 | 修复 |
|---|---|---|
| **T-33** | 服务端 COS 代理返回的 photoKey 带前缀（`photos/<sha256>`），客户端却用**裸** sha256 比对 → 永不相等 → 每次推送都重传照片（dev 态 FakeCos 返回裸 sha256、prod 态返回带前缀，两边行为不一致） | 客户端比较 photoKey 时统一取**裸 sha256**（新增 `_bareHash`）：带前缀与裸两种形态都认，dev/prod 口径就此一致 |
| **T-34** | 推送触发点含退后台/退出；此时 Android 会挂起后台 Dart isolate，HTTP 请求的 `await` 迟迟不返回 → 推送挂起（实测约 40 分钟才落库），且状态停在 `synced` 误示已同步 | 推送改为**只在 App 前台触发**（切标签 / 回前台 / 引擎启动）；退后台与退出**只落盘**（新增 `_flushOnly`），由「回前台」与「引擎启动」补推 |

### 新增回归测试（4 项）

| 用例 | 覆盖 |
|---|---|
| T-33 带前缀的 photoKey 不触发重复上传 | `pushOnce` 的上传判定 |
| T-33 pull 时带前缀的 photoKey 不触发重复下载 | `pullOnce` 的下载判定 |
| T-34 退后台只落盘不发网络推送，回前台才补推 | widget 生命周期（`didChangeAppLifecycleState`） |
| T-34 `start()` 安排一次推送 | 引擎启动补推退后台/退出前落盘的条目 |

### 真机复验（小米 2211133C；cloudflared `--loglevel debug` 观察请求）

| 时刻(UTC) | 请求 | 判读 |
|---|---|---|
| 14:00:33 | `POST /sync/batch` ×1 | 引擎启动即补推（T-34） |
| 14:01:05 | **退到后台** | — |
| 14:01:05 → 14:01:50 | **无任何 POST**（仅 45 秒静默） | 退后台不发网络推送 ✅（修复前此处会挂起） |
| 14:01:55 | `GET /sync?cursor=0` ×2 | 回前台拉取 |
| 14:02:24 | `POST /sync/batch` ×1 | 回前台 30 秒防抖后补推 ✅ |

- **T-33 复验**：整个窗口 `POST /sync/photo/upload` 次数 **0**——同一张 543KB 照片不再重传（修复前每次推送都传、每次约 18 秒）。
- **T-34 复验**：退后台期间无 POST，回前台后正常发出。

> 复验用完已把 cloudflared 日志级别恢复 `info`；调试用的临时 `print` 在第十四轮即已全部还原。

### 宿主验证

| 检查 | 结果 |
|---|---|
| `flutter analyze` | 仅 pre-existing 4 项（无新增） |
| `flutter test` 全量 | **465 项全过**（461 原有 + 4 新增） |

### 遗留

- T-04 / T-24 的**严格双设备**部分仍需第二台设备。
- T-25（ECS 出向带宽 ~428 KB/s）待评估。
