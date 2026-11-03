# F013 云同步最小闭环设计

- 状态：设计已批准（2026-11-03 brainstorming）
- 关联：[产品设计](../产品设计-product-design.md) 第 4、7、9、10 节
- 范围：Phase 4 第一里程碑——最小身份 + 同步引擎 + 照片同步（fake OSS）

## 1. 目标与范围

Phase 1–3 已完成（本地记录、回顾、心情、标签、随手拍、热力图等）。Phase 4 是账号 + 同步 + 图片直传 OSS。本设计覆盖 Phase 4 的第一个里程碑，让多设备同步闭环跑通。

本里程碑**包含**：邮箱+密码最小身份、同步引擎（文本字段）、照片同步（fake OSS）。
本里程碑**不包含**（延后）：SMS/手机号注册、找回密码、设备信任链、真机阿里云 OSS 端到端、推送通知。

## 2. 已确定的约束

| 维度 | 决定 |
|---|---|
| 里程碑 | 最小身份(邮箱+密码) + 同步引擎 + 照片同步(fake OSS) |
| 服务端 | Dart (shelf + postgres) |
| 账号模型 | 多凭证可扩展，SMS 将后续加入（不破坏现有模型） |
| 首次同步 | 认领机制（登录后询问，是则上传本机日记） |
| 照片 | 本次含，fake OSS 开发，真机端到端延后到 bucket 就绪 |
| 冲突 | 字段级 LWW（产品设计"绝不整条覆盖"） |
| 同步协议 | `GET /sync?cursor=N` + `POST /sync/batch`，游标用 BIGSERIAL seq |
| 合并位置 | 服务端解析合并，客户端拉取已合并态（方案 A） |
| 架构铁律 | LocalRepo 是唯一真相源；UI 不碰 RemoteRepo；Domain 不依赖框架/SDK |

## 3. 共享 Dart 包 `sync_core`

客户端和服务端都引用，是"单一真相源"的载体。纯 Dart，不依赖 flutter/shelf/postgres，可宿主测试。

| 模块 | 职责 |
|---|---|
| `entry_sync.dart` | 同步字段模型：`FieldValue {v, t}`、`SyncEntry`（字段级 `{field: FieldValue}`） |
| `merge_decision.dart` | 字段级 LWW 纯函数：给定两字段值取 `t` 大的，`t` 相等取推送方 |
| `sync_protocol.dart` | 请求/响应类型：`SyncPullRequest/Response`、`SyncPushBatch`、`Cursor`、`EntryPatch` |
| `auth_provider.dart` | `AuthProvider` 抽象 + `EmailPasswordProvider`（SMS 将加 `SmsProvider`） |
| `oss_gateway.dart` | `OSSGateway` 抽象：`upload/download/presign`——接口共享，实现客户端侧（fake 开发，真机 OSS 时 presign 由服务端生成） |

`merge_decision` 是核心：服务端合并推送用它，客户端合并拉取用它，两端逻辑一致不漂移。

SyncEngine、RemoteRepo 是客户端实现（依赖 LocalRepo/HTTP），不进 `sync_core`，放在 `client/lib/src/data/sync/` 与 `data/remote/`，只引用 `sync_core` 的类型。

## 4. 客户端架构

- **LocalRepo（SQLite）仍是唯一真相源**，写入永不失败——架构铁律不变。
- **SyncEngine 作为异步旁路**，三个独立循环（产品设计第 10 节）：
  - 写循环：用户写入 → LocalRepo → 标 dirty → 不阻塞
  - 推循环：后台读 dirty 队列 → `RemoteRepo.push` → 成功移出、失败留队
  - 拉循环：后台 `GET /sync?cursor` → 合并到 LocalRepo
- **RemoteRepo**：HTTP 客户端，用 `sync_core` 协议类型，UI 不直接调用。
- **认领机制**：登录后询问"要把本机 N 篇日记同步到云端吗"→ 是则批量 `set userId` + 入 dirty 队列（上传，非下载）；否则本机日记不上传，仅从此开始新同步。
- **同步状态 UI**：⟳ 同步中 / ✓ 已同步（显示最后同步时间）/ ⚠ 同步失败（点开看原因 + 手动重试）。不静默失败。
- **OSS 客户端**走 `OSSGateway` 抽象，fake 实现开发。

## 5. 服务端架构

Dart `shelf` + `postgres`，合并逻辑调 `sync_core.merge_decision`。服务端是 dumb store + merge logic。

**表结构**：

```
users    (id, email UNIQUE, password_hash, created_at)
entries  (id, user_id, payload JSONB, seq BIGSERIAL)
         -- payload 存字段级已合并态 {content:{v,t}, mood:{v,t}, ...}
         -- seq 每次推送递增, 用于游标
```

**接口**：

| 接口 | 说明 |
|---|---|
| `POST /auth/register {email,password}` | 创建账号，返回 token |
| `POST /auth/login {email,password}` | 登录，返回 token |
| `GET /sync?cursor=N` | 返回 `seq > N` 的条目已合并态 + 新 cursor（=结果最大 seq） |
| `POST /sync/batch` | 接收字段级 `EntryPatch`，LWW 合并入 payload，递增 seq |

**合并规则**：推送某字段 `{v,t}` 时，若 `t > payload[field].t` 则替换，否则保留；`t` 相等取推送方。整条不覆盖。

**游标原子推进**：`GET /sync` 返回的新 cursor 与 `POST /sync/batch` 落库在同一事务提交，保证不丢不重。

## 6. 照片同步

- `OSSGateway` 抽象：`upload(bytes)→key`、`download(key)→bytes`、`presign(key)→url`
- **Fake OSS**：本地文件系统模拟预签名直传（开发/测试用），不依赖云
- 流程：选照片 → 算 sha256 → `OSSGateway.upload` 直传（fake 写本地临时区）→ 得 key → `entry.photo = key` → 同步传播 key
- 其他设备拉取 → 见 key → `OSSGateway.download`（fake 读本地）
- **真机阿里云 OSS**（预签名 URL 直传、私有 bucket、境内 region）延后到 bucket 就绪，届时替换 fake 实现
- **照片字段 LWW**：照片是引用（key），整字段替换（取 updatedAt 大的），不做 BLOB 合并

## 7. 数据流与冲突处理

**推送**：客户端字段级 `{v,t}` → 服务端 LWW 合并入 payload → 递增 seq → 返回确认 → 客户端移出 dirty 队列。

**拉取**：客户端 cursor → 服务端返回已合并态 + 新 cursor → 客户端逐字段 LWW 合并入 LocalRepo（字段 `t` 大于本地才应用）。

**冲突**：字段级，每字段独立 updatedAt，取大；**绝不整条覆盖**。设备 A 改心情、设备 B 改正文，双方改动都保留。

**离线**：dirty 队列保留，重试退避 2→4→8→16→32 秒 + 抖动，第 6 次放弃本轮等下个触发点（产品设计第 10 节）。

**触发时机**：App 启动、进入后台、回到前台、写完延迟 30 秒、网络恢复、定时每 5 分钟、手动下拉。

## 8. 错误处理

| 场景 | 行为 |
|---|---|
| 推送/拉取网络超时、5xx、429 | 退避重试，dirty 队列保留 |
| 403（账号/设备失效） | 停止同步，提示重新登录，本地数据仍可用 |
| 401 | 先用 refresh token 换新 token 重试一次；再失败 → 停止同步 + 提示重新登录，**绝不自动登出**，本地数据不丢 |
| 400（格式错） | 记日志，不重试（是 bug） |
| 本地写入 | 永不失败，不依赖网络 |

## 9. 测试策略

- `sync_core`：纯函数宿主测试（`merge_decision` 边界、protocol 编解码往返、字段级冲突）
- 客户端：SyncEngine 用 fake RemoteRepo + fake OSS + `sqflite_common_ffi` 宿主测试（复用现有测试模式）
- 服务端：shelf 路由测试 + postgres（testcontainers 或 fake store）
- 真机端到端：文本同步可真机验证；**照片同步延后到 OSS bucket 就绪**

## 10. 验收标准

| 编号 | 场景 | 验收 |
|---|---|---|
| AC-01 | 邮箱+密码注册与登录 | 注册后能登录，返回可用 token |
| AC-02 | 认领机制 | 登录后询问"同步本机 N 篇"，是则上传、否则本机日记不上传 |
| AC-03 | 两设备文本同步 | 设备 A 写 → 设备 B 拉取可见，正文/心情/标签一致 |
| AC-04 | 离线写入→联网推送 | 飞行模式写入 → 联网后自动推送，服务端可见 |
| AC-05 | 字段级冲突 | A 改心情、B 改正文，合并后双方改动都保留，不整条覆盖 |
| AC-06 | 照片同步（fake OSS） | A 拍照 → 同步 → B 拉取可见照片 |
| AC-07 | 游标原子性 | 推送与 cursor 推进同事务，不丢不重 |
| AC-08 | 401 处理 | token 失效 → 换 token 重试一次 → 仍失败停同步提示重登录，不自动登出 |

## 11. 范围外与延后项

- SMS/手机号注册、验证码找回、设备信任链、登录历史（账号体系第二里程碑）
- 真机阿里云 OSS 端到端照片同步（bucket 就绪后补）
- 推送通知、多设备实时推送（产品设计已决定不做）
- 服务端端到端加密、服务端全文搜索、团队协作（产品设计已决定不做或延后）
