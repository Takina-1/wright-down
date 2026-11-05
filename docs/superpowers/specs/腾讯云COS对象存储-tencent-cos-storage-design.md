# 腾讯云 COS 对象存储 · tencent cos storage

- 关联功能：F013 云同步最小闭环（本次在其分支上执行，见 §6 分支与编号）
- 关联文档：[云同步设计](云同步设计-cloud-sync-design.md) · [F013 待办登记](../features/F013-待办-todos.md) · [产品设计](../产品设计-product-design.md) · [ECS 部署说明](../../deploy/阿里云部署-aliyun-deploy.md)
- 日期：2026-11-05
- 状态：待实现

## 1. 背景

F013 设计里的照片同步走「服务端代理对象存储」，原定对象存储为**阿里云 OSS**。用户已实际购买**腾讯云 COS 标准存储容量包**，对象存储供应商改为腾讯云 COS。

本次只做**文档对齐 + 代码命名对齐**。真机 COS 的实现（建桶、CAM 凭证、服务端代理端点、客户端真机版、真机双设备验收）不在本次范围，作为 F013 待办延后。

**数据路径已定为 ECS 代理收发字节（D-07）**：客户端 ↔ ECS ↔ COS，后端存对象 key。ECS 留在阿里云，与 COS 无内网，照片字节两次跨公网，且实测本机 ECS 公网出向仅 ~428 KB/s——相关约束与成本见 §3.2、§3.3。

## 2. 已确认的决策

| # | 决策 | 理由 |
|---|---|---|
| D-01 | **只换对象存储**；ECS 服务端继续留在阿里云 cn-guangzhou | ECS 已部署跑通（`8.148.158.13`），迁移成本高。代价是跨厂商无内网，照片字节两次跨公网——见 §3.2、§3.3 |
| D-02 | COS 桶地域 **ap-guangzhou（广州）** | 与 ECS 同城；资源包若为「中国大陆通用」规格则不受地域限制，若为指定地域规格必须对齐 |
| D-03 | 代码命名改成 **COS 前缀**：`CosGateway` / `FakeCos` / `cos_gateway.dart` | 用户选择。代价见 §5 已知限制 |
| D-04 | 文档**全部替换**（含已完成的计划与测试报告里的历史表述） | 用户选择。ECS 相关表述保持不动——那是事实 |
| D-05 | 本次范围 = 文档 + 重命名；**真机 COS 实现延后** | 用户选择。真机未连接，无法验证 |
| D-06 | 新增一份 COS 运维文档 `deploy/腾讯云COS配置-tencent-cos-setup.md` | 现有 `deploy/阿里云部署-aliyun-deploy.md` 只覆盖 ECS 侧，桶/凭证/资源包/成本无处安放 |
| D-07 | **照片字节经 ECS 代理收发**：客户端 → ECS → COS，客户端 ← ECS ← COS；后端存**对象 key**（不是完整 URL） | 用户选择。凭证与鉴权统一在服务端，客户端拿不到对象存储凭据；后端存 key 而非 URL，桶名/域名变更不影响存量数据 |

## 3. 跨厂商的技术差异（影响后续真机实现）

这一节是本次调研的核心产出，直接决定 T-05 / T-24 怎么做。

### 3.1 服务端需要 COS 访问能力（签名算法与 OSS 不同）

阿里云 OSS 与腾讯云 COS 的签名算法、参数名、请求头要求都不同，**服务端访问代码不能直接搬**。COS 侧要点：

- 签名绑定四要素：HTTP 方法、桶、对象键、有效期 → 换一个对象键不能复用同一个签名。
- 官方建议用 **STS 临时密钥**而非永久密钥；有效期尽量短。
- SDK 默认签名会签入 `Host` header；不签入 Host 可能导致请求失败。
- 单个预签名上传最大支持 **5GB**；代理上传还需注意 ECS 侧 `client_max_body_size`（当前 nginx 配置为 **8m**），超过 8 MB 的照片会被 nginx 拒绝——见 §5 已知限制。
- **Dart 生态注意**：pub.dev 上**没有腾讯云官方 COS Dart SDK**。可用的是社区包 `tencent_cos_dart`（0.1.x，非官方）与插件 `tencentcloud_cos_sdk_plugin`（含 `getPresignedUrl`，面向 Flutter 端）。服务端若走 HTTP 直调 COS，可用 `package:crypto` 自行实现 COS 签名（`q-sign-algorithm=sha1`），避免引入非官方依赖。

### 3.2 数据路径：ECS 代理收发字节（D-07）

```
上传：客户端 ──POST 照片──▶ ECS ──PUT──▶ COS      后端存 key
下载：客户端 ◀──GET 照片── ECS ◀──GET── COS      后端按 key 查
```

COS 的内网 endpoint 只对**同地域腾讯云 CVM** 免费开放。本项目 ECS 在阿里云，两家之间无内网，因此**每一份照片字节都要跨两次公网**：

| 段 | 计费方 | 计费项 |
|---|---|---|
| 客户端 → ECS（上传请求体） | 阿里云 | ECS 公网**入**方向流量（通常免费） |
| ECS → COS（PUT 对象） | 阿里云 | ECS 公网**出**方向流量（约 0.8 元/GB） |
| ECS → COS（PUT 对象，COS 侧） | 腾讯云 | COS 外网**流入**（不计费） |
| COS → ECS（GET 对象） | 腾讯云 | COS 外网**下行**流量（与存储容量包无关） |
| ECS → 客户端（回传响应体） | 阿里云 | ECS 公网**出**方向流量（约 0.8 元/GB） |

**一份照片的下载要付两份流量费**：腾讯云的 COS 外网下行 + 阿里云的 ECS 公网出向。存储容量包一份都不抵扣。

> 与「客户端直连 COS」相比，后者只需付腾讯云一份下行流量费，且完全不占 ECS 带宽。用户已知悉并选择 ECS 代理（D-07），理由是凭证与鉴权统一在服务端、客户端拿不到对象存储长期密钥。代价见 §3.3。

### 3.3 带宽约束（2026-11-05 实测，本设计的关键约束）

在 `8.148.158.13`（`ecs.e-c1m1.large`，cn-guangzhou）实测：

| 路径 | 实测速度 | 换算 |
|---|---|---|
| ECS → 客户端（nginx 443 出向） | **428 KB/s** | ≈ 3.4 Mbps |
| ECS → 公网（腾讯云镜像上传） | 390 KB/s | ≈ 3.1 Mbps |
| 公网 → ECS（入向，阿里云/腾讯云镜像） | 1.1–1.26 MB/s | ≈ 10 Mbps |
| ECS → 阿里云内网镜像 | 19.7 MB/s | 内网，不计费 |

- 4 条并发连接合计仍为 ~1.3 MB/s，单连接 ~1.1 MB/s → **是峰值封顶，不是单连接限速**。
- 同线路本机下载 7 MB/s → 排除测试端网络限制。
- 部署文档里的「基础带宽 0.2 Gbit/s」是**内网**带宽，不代表公网。

**换算到用户体验**（手机照片典型 3–5 MB）：

| 场景 | 耗时 |
|---|---|
| 下载 1 张 4 MB 照片（ECS 出向 428 KB/s） | **≈ 10 秒** |
| 两台设备同步 100 张照片（400 MB） | **≈ 16 分钟** |

上传走 ECS 入向 + ECS 出向，虽各段较快，但客户端上传本身受移动网络限制。

**结论**：ECS 代理在本架构下可用，但**不适合大量照片的批量同步**。缓解手段见 §9。

### 3.4 计费项与资源包是三件独立的事

腾讯云 COS 的资源包分三类，**互不抵扣**：

| 类别 | 品种 | 抵扣范围 |
|---|---|---|
| 存储容量包 | 标准 / 低频 / 归档 / 深度归档 / 智能分层 | 对应存储类型的**容量费** |
| 流量包 | 外网下行 / CDN 回源 / 全球加速 / 跨地域复制 | 对应的**流量费** |
| 请求包 | 标准 / 低频读写请求包 | **请求次数**费 |

要点：

- 用户已购**标准存储容量包** → 只抵扣标准存储容量费。
- **外网下行流量包未购** → 照片下载流量当前按量付费（单价以腾讯云 COS 定价页为准，本文不写死数字，避免价格变动后文档失真）。
- 免费额度资源包**只能抵扣标准存储容量**，不能抵扣流量、请求次数、低频/归档容量——「领了免费额度仍欠费」的常见原因。
- 不同存储类型的容量包不能混用；存储容量包暂不支持抵扣多 AZ 存储类型。
- 抵扣顺序：免费额度包 → 自购包（同为自购包时先到期先抵扣）→ 按量计费。
- 存储容量包**每日**按当天平均存储量抵扣；流量包/请求包**每月**重置抵扣额度，当月未用完不累计。
- 资源包**有地域限制**（「中国大陆通用」/「中国香港及境外通用」两档），不支持金融云地域。
- **用户需核实已购容量包的地域规格**：若买的是指定地域包而桶建在别的地域则不抵扣。

### 3.5 CAM 最小权限

服务端代持凭证、代理读写，因此 CAM 子用户需要**读写**权限（不是仅预签名用的读权限）：

- CAM 控制台用户策略的 action 前缀是 `name/cos:`（桶策略/元素参考文档用 `cos:`，写错不生效）。
- 授 `name/cos:PutObject` + `name/cos:GetObject`，**不授 DeleteObject**，防止凭据泄露后数据被批量删除。
- resource 精确到桶内前缀：`qcs::cos:ap-guangzhou:uid/<APPID>:<BUCKET>-<APPID>/<PREFIX>/*`。
- 所有键必须全小写（`version` / `principal` / `statement` / `effect` / `action` / `resource` / `condition`）。
- 避免 `action: "*"` 与 `resource: "*"`。

**凭证存放**：只写 ECS 服务端环境变量，**绝不下发客户端**（这是 D-07 选 ECS 代理的核心收益）。客户端全程只见 ECS 的 443。

### 3.6 其他合规约束

- COS 默认桶和对象都是私有的，符合产品设计 §6「私有 bucket，访问单独鉴权」的要求。D-07 下鉴权全部在 ECS 一侧，客户端无法构造任意对象的 URL。
- 全部数据在 ap-guangzhou 境内，满足 OPPO 上架清单第 18 项「数据境内存储」。
- 客户端**不集成任何云存储 SDK**（Dart 侧无官方 COS SDK，本就不打算引入），对 OPPO 第 19 项「第三方 SDK 清单」无新增负担。

## 4. 改动清单

### 4.1 代码重命名

| 现在 | 改为 | 涉及文件 |
|---|---|---|
| `packages/sync_core/lib/src/oss_gateway.dart` | `cos_gateway.dart` | 1（重命名） |
| `OSSGateway` | `CosGateway` | 5 个 dart 文件：`oss_gateway.dart`、`fake_oss.dart`、`sync_engine.dart`、`interfaces_test.dart`、`home_page_photo_sync_test.dart` |
| `client/lib/src/data/sync/fake_oss.dart` | `fake_cos.dart` | 1（重命名） |
| `FakeOSS` | `FakeCos` | 9 个 dart 文件：`main.dart`、`fake_oss.dart` + 7 个测试文件（`fake_oss_test.dart`、`sync_engine_test.dart`、`sync_engine_photo_test.dart`、`sync_engine_runtime_test.dart`、`sync_engine_stamps_test.dart`、`home_page_photo_sync_test.dart`、`login_page_test.dart`） |
| `client/test/data/sync/fake_oss_test.dart` | `fake_cos_test.dart` | 1（重命名） |
| `SyncEngine.oss` 字段 / 构造参数 `oss:` | `cos` / `cos:` | 7 个 dart 文件：`sync_engine.dart`、`home_page.dart`、`main.dart` + 5 个测试文件（`sync_engine_test.dart`、`sync_engine_photo_test.dart`、`sync_engine_runtime_test.dart`、`sync_engine_stamps_test.dart`、`home_page_photo_sync_test.dart`、`login_page_test.dart`） |
| `_InMemoryOSS` | `_InMemoryCos` | `client/test/ui/home_page_photo_sync_test.dart` |
| `_FakeOss` | `_FakeCos` | `packages/sync_core/test/interfaces_test.dart` |
| 注释「照片 OSS key」 | 「照片 COS key」 | `entry.dart`、`sqlite_entry_repository.dart`、`memory_repository.dart` |
| `sync_core/pubspec.yaml` 描述「鉴权/OSS 抽象」 | 「鉴权/COS 抽象」 | 1 |

**不改动**：

- `Entry.photoKey` 字段名与 `photo_key` 数据库列名——本身与厂商无关。
- `deploy/ram-policy.json`——阿里云 ECS 只读策略，与对象存储无关。
- 任何 ECS 侧内容（`deploy/` 下的阿里云脚本、`aliyun-deploy.md` 正文）。

### 4.2 文档替换

| 文件 | 改动 |
|---|---|
| `docs/产品设计-product-design.md` | §3 音频上传 OSS → COS；§4「图片：sha256 秒传 → 预签名 URL 直传 OSS → 库里只存 key」→ 改为「sha256 秒传 → **经服务端代理 COS** → 库里只存 key」（D-07）；§6「OSS 必须私有 bucket」→ COS；§9 部署「OSS 托管」→ COS、备份「pg_dump → OSS」→ COS、成本估算「OSS ~50」→ COS；§里程碑表「图片直传 OSS」→ COS |
| `docs/features/F012-语音输入-voice-input.md` | §2「音频上传 OSS」→ COS；§3「OSS 必须私有 bucket」→ COS。ASR 厂商表述「阿里云/腾讯云 ASR」不动（那是转写供应商，不是存储） |
| `docs/features/F013-待办-todos.md` | T-04「无真实 OSS」→「无真实 COS」；T-05 拆分为 T-05（建桶 + CAM 凭证）与 T-24（真机实现与验收）；新增 T-25 记录 ECS 带宽实测限制。详见 §4.3 |
| `docs/features/README.md` | F013 行「照片同步(FakeOSS)」→「(FakeCos)」；「未完成项共 23 条」→「24 条」 |
| `docs/superpowers/specs/云同步设计-cloud-sync-design.md` | §6 照片同步（`OSSGateway`→`CosGateway`、真机改为腾讯云 COS 且经 ECS 代理）、§9 测试策略、§11 延后项中的 OSS 表述 |
| `docs/superpowers/plans/云同步-照片同步-photo-sync.md` | 全文 OSS 表述与 `oss_gateway.dart` / `fake_oss.dart` 文件名 |
| `docs/superpowers/plans/云同步-sync-core共享包-sync-core-package.md` | §Part 表、Task 4、代码片段中的 OSS 表述与文件名 |
| `docs/superpowers/plans/云同步-部署链路-ecs-deploy.md` | 范围表「真机阿里云 OSS」一行、结尾延后项清单 |
| `docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md` | 范围、已知限制、结论、AC-06 行中的 OSS 表述 |
| `docs/test-reports/README.md` | F013 行「无真实服务端/OSS」→「/COS」 |
| `docs/OPPO上架清单-oppo-release-checklist.md` | 第 18 项「OSS + 数据库」→「COS + 数据库」 |
| `docs/开源仓库-open-source-repositories.md` | 「国内 OSS + 自建同步 API」→「国内对象存储 + 自建同步 API」 |
| `docs/README.md` | 索引新增一行，指向两份部署文档（现无任何入口能找到部署文档） |

**保持不动**：`docs/开发环境-development-environment.md` 里的「阿里云 central HTTPS 镜像」是 Maven 镜像，与云厂商无关。

### 4.3 F013 待办拆分

原 T-05 一行拆为两行：

| 编号 | 事项 | 状态 | 阻塞原因 | 下一步 |
|---|---|---|---|---|
| T-05 | **建桶 + CAM 凭证**：ap-guangzhou 私有桶、CAM 子用户 + bucket 级最小权限策略、密钥只存 ECS 服务端环境变量 | 未执行 | 桶尚未创建 | 控制台建桶 → 写 `deploy/cam-policy.json` → 建子用户并绑定策略 → 密钥写入 ECS 环境变量 |
| T-24 | **真机 COS 代理读写**：服务端加照片上传/下载端点（代理 COS PUT/GET）、客户端 `CosGateway` 真机版替换 `FakeCos`、真机双设备验收 | 未执行 | 依赖 T-05 + 无真机 | T-05 完成后实现；**注意 §3.3 带宽限制与 nginx 8 MB 请求体上限** |

### 4.4 新增文件

- `deploy/腾讯云COS配置-tencent-cos-setup.md`：桶配置、凭证管理、资源包现状与抵扣范围、跨厂商成本说明、**实测带宽数据**、真机实现指引。**内容见 §3**。
- `deploy/cam-policy.json`：CAM 用户策略模板，action 为 `name/cos:PutObject` + `name/cos:GetObject`，resource 限定到桶内前缀。APPID 与桶名建桶后填入。

## 5. 已知限制

- **ECS 代理带宽不足**（最重要）：实测 ECS 公网出向仅 ~428 KB/s（3.4 Mbps），下载一张 4 MB 照片约 10 秒，100 张照片批量同步约 16 分钟。这是 D-07 直接选型的代价，已知并接受。缓解方向见 §9。
- **流量费双份**：照片下载一次付腾讯云 COS 外网下行 + 阿里云 ECS 公网出向两份。已购标准存储容量包一份都不抵扣。
- **nginx 请求体上限 8 MB**：当前 `deploy/nginx` 配置 `client_max_body_size 8m`，超过 8 MB 的照片经 ECS 上传会被拒绝。手机照片常见 3–5 MB，但 HDR/长焦可能超标，需在 T-24 一并处理。
- **抽象层被绑定到具体厂商**：`CosGateway` 把「COS」写进了 `sync_core` 的公共接口名，而 `sync_core` 原定位是「厂商中立纯逻辑包」。将来换厂商需再改一次。这是 D-03 的直接后果，已知并接受。
- **CAM 策略模板含占位符**：`deploy/cam-policy.json` 的 APPID 与桶名在建桶前无法填写。占位符以 `<APPID>` / `<BUCKET>` 标注，建桶后替换。
- **真机 COS 完全未验证**：本次只改命名与文档，行为未变（仍是 `FakeCos` 本地文件系统实现）。所有真机 COS 结论都还没有证据。
- **月流量成本未知**：已购标准存储容量包但未购流量包。实际月流量在有真实数据前无法估算。

## 6. 分支与编号

- 本次在 **`feat/F013-cloud-sync`** 分支执行。原因：`packages/sync_core` 与客户端同步代码**只存在于该分支**，`main` 上尚无这些文件（`git ls-tree main packages/` 为空），无法从 main 另开分支做重命名。
- **不分配新的功能编号**。`CosGateway` 抽象与照片存储本属 F013 的设计范围，本次是其中的供应商变更与命名对齐，按开发流程 §「修复已有功能」记录进 F013 的待办登记与测试报告；跨功能的产品设计同步更新 `docs/产品设计-product-design.md`。
- 工作区当前有未提交改动（`packages/server/`、`deploy/deploy-app.sh` 等），与本次重命名文件基本不重叠（仅 `packages/sync_core/pubspec.lock` 同时被修改，但重命名只动 `pubspec.yaml` 的 description 字段）。实施时不改动既有未提交内容。

## 7. 验证方式

| 检查 | 命令 | 期望 |
|---|---|---|
| sync_core 静态分析 | `dart analyze`（packages/sync_core） | No issues found |
| server 静态分析 | `dart analyze`（packages/server） | No issues found |
| client 静态分析 | `flutter analyze` | 无新增 warning（现有 3 个 pre-existing warning 不计） |
| sync_core 测试 | `dart test` | 13 项全过 |
| server 测试 | `dart test` | 13 项全过 |
| client 测试 | `flutter test` | 415 项全过（合计仍为 441） |
| client 构建 | `flutter build apk --debug` | 成功 |

重命名是纯机械改动，**行为不变**，因此期望所有测试数量与结果与重命名前一致。任何一项失败或数量变化都视为重命名引入的问题，必须修复。

文档改动为纯文本替换，核对方式是：改完后全仓库搜索 `OSS`、`oss`、`FakeOSS`、`OSSGateway` 应只剩下「对象存储」的通用语义用法与本文档 §5 的限制描述。

## 8. 不在本次范围

- 服务端 COS 代理读写端点实现（T-24）。
- 客户端真机 `CosGateway` 实现（T-24）。
- 建桶、CAM 子用户创建、密钥落地（T-05）。
- 购买外网下行流量包（等月流量数据出来再评估）。
- ECS 迁移到腾讯云（已决定不做）。
- 照片生命周期沉降到低频/归档（等存储成本数据）。

## 9. ECS 代理带宽的缓解方向（记录，不在本次实施）

§3.3 的带宽限制在用户量上来后会变成体验问题。可能的缓解方向，按侵入性从低到高：

| 方向 | 效果 | 代价 |
|---|---|---|
| nginx `client_max_body_size` 调大 + 上传流式化 | 支持大照片 | 不解决出向带宽 |
| ECS 升配 / 加公网带宽（按固定带宽计费） | 直接抬高出向上限 | 阿里云费用上升；固定带宽比按流量贵 |
| 照片客户端压缩后再传（如长边 1920、JPEG q80） | 传输量降一个数量级，4 MB → 约 300 KB | 需评估画质取舍；可保留原图在本地 |
| 下载时服务端生成缩略图并缓存 | 列表页只传缩略图 | 增加服务端 CPU 与缓存存储 |
| 回退到「预签名 URL 直连 COS」 | 照片不占 ECS 带宽，只付腾讯云一份流量费 | 客户端能拿到短期签名 URL；需重新评估 D-07 |

其中「客户端上传前压缩」对当前 3 Mbps 的出向最有效，且不增加云成本。列入 T-24 一并评估。
