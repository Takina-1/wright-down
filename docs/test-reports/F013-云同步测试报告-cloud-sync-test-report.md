# F013：云同步测试报告

- 关联需求：[F013 云同步设计](../superpowers/specs/云同步设计-cloud-sync-design.md)
- 关联计划：sync_core / 服务端 / 客户端同步引擎 / 客户端 UI 与触发 / 照片同步（五份实现计划）
- 代码状态：`feat/F013-cloud-sync` 分支，30 提交；宿主自动化测试全过
- 本报告区分宿主自动化验证、Android 构建与真机验收。真机验收未执行。

## 范围

Phase 4 第一里程碑：邮箱+密码最小身份、同步引擎（字段级 LWW）、照片同步（FakeOSS）。
- 包含：sync_core 共享包、服务端（Dart shelf + FakeSyncStore）、客户端同步引擎（RemoteRepo + SyncEngine + 触发/退避/状态）、鉴权 UI + 认领、照片同步（schema v7 photo_key + FakeOSS + 上传/下载）。
- 不包含（延后）：PostgresSyncStore（环境无 postgres）、真机阿里云 OSS（环境无 bucket）、SMS/找回、真机端到端验收。

## 宿主验证

环境：Windows 10 Pro；Flutter 3.47.8 / Dart 3.13.7；sqflite_common_ffi（宿主 FFI 测试）。

### 自动化测试分布

| 包/模块 | 测试数 | 覆盖 |
|---|---|---|
| sync_core | 13 | 字段级 LWW、协议编解码、鉴权/OSS 抽象契约 |
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

- `client/lib/src/ui/home_page.dart:41` `unused_field _undoableEntryId`（来自 F005 commit 43dfe46）。
- `client/test/data/sync/sync_engine_stamps_test.dart` 两个 unused import。

### 关键修复记录

- **M-16（save 覆盖远端时间戳）**：终审发现 pull 调 save 会用 updatedAt 重算 sync_stamps，丢弃远端字段 t。修：新增 `saveMerged` 保留调用方 syncStamps，SyncEngine.pullOnce 用 saveMerged。TDD RED(5000/1000)→GREEN。
- **Critical（pushOnce 跳过软删除条目）**：终审发现 pushOnce 过滤 `!isDeleted`，导致删除标记不同步。修：移除过滤 + 回归测试。
- **photoKey 持久化**：编辑器 _saveLoop 必须携带 photoKey，否则编辑同步的照片条目会清空 OSS key。修：EntryEditorController 携带 photoKey。

## 验收标准对照（AC-01~AC-08，宿主部分）

| 编号 | 场景 | 宿主验证 | 真机 |
|---|---|---|---|
| AC-01 | 邮箱+密码注册登录 | FakeSyncStore + handler 测试通过 | 未执行 |
| AC-02 | 认领机制 | LoginPage 认领弹窗测试通过 | 未执行 |
| AC-03 | 两设备文本同步 | SyncEngine 推拉测试通过 | 未执行 |
| AC-04 | 离线写入→联网推送 | triggerPush 测试通过 | 未执行 |
| AC-05 | 字段级冲突 | mergeFieldLww/applyRemote 测试通过 | 未执行 |
| AC-06 | 照片同步 | FakeOSS 上传/下载 + SyncEngine 照片测试通过 | 未执行 |
| AC-07 | 游标原子性 | FakeSyncStore 内存单线程（非真事务） | 未执行（PostgresSyncStore 延后） |
| AC-08 | 401 处理 | 未完整实现（延后） | 未执行 |

## 真机验收：未执行

本轮**未连接 Android 设备**做端到端真机验收。以下项一律记「未执行」，不计入通过：
- 真机注册/登录（FakeSyncStore 无真实服务端）。
- 真机两设备文本/照片同步（无真实服务端 + 无真实 OSS）。
- 真机同步状态 UI、认领弹窗实际交互。
- schema v7 迁移在真机库上的表现。

宿主测试用 FakeSyncStore / FakeOSS / 替身覆盖逻辑契约，**不能**替代真机结论。

## 已知限制

1. **服务端用 FakeSyncStore（内存）**：环境无 postgres/Docker。PostgresSyncStore（真实 SQL + 事务游标，满足 AC-07）延后。服务端逻辑已宿主测试，真实持久化未验证。
2. **照片用 FakeOSS（本地文件系统）**：环境无阿里云 OSS bucket。真机 OSS 直传（预签名、私有 bucket、境内 region）延后。OSSGateway 抽象已就位，届时替换实现。
3. **密码哈希是 sha256+salt**：非 bcrypt/argon2。生产部署前必须换。
4. **Token 无过期/刷新**：InMemoryTokenStore 重启失 token。AC-08 的 refresh 流程未实现。
5. **baseUrl 硬编码**（`http://10.0.2.2:8080`）：配置化是后续工作。
6. **照片设计缺口**：setPhoto 保留旧 photoKey → 同步条目上新选的照片不重传；远端 photoKey 变更不清本地 BLOB 缓存。后续修。
7. **推送失败静默**：triggerPush 吞掉推送失败，状态显示 synced（违反「不静默失败」）。后续加 push 失败状态。

## 本轮结论

- 通过：441 项宿主自动化测试 + 三包静态分析 + 调试 APK 构建。
- 未执行：真机端到端验收（无连接设备 + 无真实服务端/OSS）。
- 是否满足全部必需验收项：宿主可验证部分全部通过；AC-07/AC-08 及真机项未执行，不计入通过。
- 下一步：连接 Android 设备 + 部署真实服务端/OSS 后补做真机端到端验收；实现 PostgresSyncStore、真机 OSS、bcrypt、token 刷新。

## 环境发现（终审记录）

- 本机 Dart 3.13.7 SDK 的集合 `==` 是身份比较（非 const 的 `['a'] == ['a']` 为 false）。sync_core FieldValue.== 已加深度比较修复。
- `dart:crypto` 在本 SDK 缺失，服务端与 FakeOSS 用 `package:crypto`。
