# 腾讯云 COS 对象存储 · tencent cos storage

- 关联功能：F013 云同步最小闭环（本次在其分支上执行，见 §6 分支与编号）
- 关联文档：[云同步设计](云同步设计-cloud-sync-design.md) · [F013 待办登记](../features/F013-待办-todos.md) · [产品设计](../产品设计-product-design.md) · [ECS 部署说明](../../deploy/阿里云部署-aliyun-deploy.md)
- 日期：2026-11-05
- 状态：待实现

## 1. 背景

F013 设计里的照片直传走「预签名 URL + 客户端直连对象存储」，原定对象存储为**阿里云 OSS**。用户已实际购买**腾讯云 COS 标准存储容量包**，对象存储供应商改为腾讯云 COS。

本次只做**文档对齐 + 代码命名对齐**。真机 COS 直传的实现（服务端签预签名 URL、客户端直传直下、真机双设备验收）不在本次范围，作为 F013 待办延后。

## 2. 已确认的决策

| # | 决策 | 理由 |
|---|---|---|
| D-01 | **只换对象存储**；ECS 服务端继续留在阿里云 cn-guangzhou | ECS 已部署跑通（`8.148.158.13`），迁移成本高。照片流量走客户端↔COS 直连，服务端只签 URL 不传字节，跨厂商对主链路影响很小 |
| D-02 | COS 桶地域 **ap-guangzhou（广州）** | 与 ECS 同城；资源包若为「中国大陆通用」规格则不受地域限制，若为指定地域规格必须对齐 |
| D-03 | 代码命名改成 **COS 前缀**：`CosGateway` / `FakeCos` / `cos_gateway.dart` | 用户选择。代价见 §5 已知限制 |
| D-04 | 文档**全部替换**（含已完成的计划与测试报告里的历史表述） | 用户选择。ECS 相关表述保持不动——那是事实 |
| D-05 | 本次范围 = 文档 + 重命名；**真机 COS 实现延后** | 用户选择。真机未连接，无法验证 |
| D-06 | 新增一份 COS 运维文档 `deploy/腾讯云COS配置-tencent-cos-setup.md` | 现有 `deploy/阿里云部署-aliyun-deploy.md` 只覆盖 ECS 侧，桶/凭证/资源包/成本无处安放 |

## 3. 跨厂商的技术差异（影响后续真机实现）

这一节是本次调研的核心产出，直接决定 T-05 / T-24 怎么做。

### 3.1 预签名算法不同

阿里云 OSS 与腾讯云 COS 的签名算法、参数名、请求头要求都不同，**服务端签名代码不能直接搬**。COS 侧要点：

- 签名绑定四要素：HTTP 方法、桶、对象键、有效期 → 换一个对象键不能复用同一个预签名 URL。
- 官方建议用 **STS 临时密钥**生成预签名，而不是永久密钥；预签名有效期尽量短。
- SDK 默认签名会签入 `Host` header；不签入 Host 可能导致请求失败。
- 单个预签名上传最大支持 **5GB**。

### 3.2 内网访问不可用（跨厂商的直接后果）

COS 的内网 endpoint 只对**同地域腾讯云 CVM** 免费开放。本项目 ECS 在阿里云，因此：

| 路径 | 计费方 | 说明 |
|---|---|---|
| 客户端 → COS（上传照片） | 免 | COS 外网流入不计费 |
| **客户端 ← COS（下载照片）** | **腾讯云** | COS **外网下行流量费**，与存储容量包无关 |
| **ECS → COS（pg_dump 备份）** | **腾讯云 + 阿里云双份** | 腾讯云侧算 COS 外网下行流量；阿里云侧算 ECS 公网出方向流量 |
| ECS → COS（生成预签名） | 免 | 纯本地计算签名，不产生对象存储流量 |

**主链路的照片流量由客户端直连产生，不经 ECS**，所以跨厂商对照片同步没有额外代价。真正的代价集中在**备份路径**和**下载流量**两处。

### 3.3 计费项与资源包是三件独立的事

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

### 3.4 CAM 最小权限

私有桶 + 预签名的推荐做法（`deploy/cam-policy.json` 将按此写）：

- CAM 控制台用户策略的 action 前缀是 `name/cos:`（桶策略/元素参考文档用 `cos:`，写错不生效）。
- 只授 `name/cos:PutObject` + `name/cos:GetObject`，**不授 DeleteObject**，防止凭据泄露后数据被批量删除。
- resource 精确到桶内前缀：`qcs::cos:ap-guangzhou:uid/<APPID>:<BUCKET>-<APPID>/<PREFIX>/*`。
- 所有键必须全小写（`version` / `principal` / `statement` / `effect` / `action` / `resource` / `condition`）。
- 避免 `action: "*"` 与 `resource: "*"`。

### 3.5 其他合规约束

- COS 默认桶和对象都是私有的，符合产品设计 §6「私有 bucket，访问单独鉴权」的要求。
- 2024-01-01 后创建的桶不支持用默认域名在浏览器直接预览文件——客户端走预签名 URL 不受影响，但**真机验收时不能靠浏览器打开默认域名看图**。
- 全部数据在 ap-guangzhou 境内，满足 OPPO 上架清单第 18 项「数据境内存储」。

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
| `docs/产品设计-product-design.md` | §3 音频上传 OSS → COS；§4 图片直传 OSS → COS；§6「OSS 必须私有 bucket」→ COS；§9 部署「OSS 托管」→ COS、备份「pg_dump → OSS」→ COS、成本估算「OSS ~50」→ COS；§里程碑表「图片直传 OSS」→ COS |
| `docs/features/F012-语音输入-voice-input.md` | §2「音频上传 OSS」→ COS；§3「OSS 必须私有 bucket」→ COS。ASR 厂商表述「阿里云/腾讯云 ASR」不动（那是转写供应商，不是存储） |
| `docs/features/F013-待办-todos.md` | T-04「无真实 OSS」→「无真实 COS」；T-05 拆分为 T-05（建桶 + CAM 凭证）与 T-24（真机实现与验收），见 §4.3 |
| `docs/features/README.md` | F013 行「照片同步(FakeOSS)」→「(FakeCos)」；「未完成项共 23 条」→「24 条」 |
| `docs/superpowers/specs/云同步设计-cloud-sync-design.md` | §6 照片同步、§9 测试策略、§11 延后项中的 OSS 表述 |
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
| T-05 | **建桶 + CAM 凭证**：ap-guangzhou 私有桶、CAM 子用户 + bucket 级最小权限策略、密钥只存服务端不下发客户端 | 未执行 | 桶尚未创建 | 控制台建桶 → 写 `deploy/cam-policy.json` → 建子用户并绑定策略 → 密钥写入 ECS 环境变量 |
| T-24 | **真机 COS 直传**：服务端签预签名 URL（腾讯云签名算法，与 OSS 不同）、客户端直传直下、真机双设备验收 | 未执行 | 依赖 T-05 + 无真机 | T-05 完成后实现 `CosGateway` 真机版替换 `FakeCos` |

### 4.4 新增文件

- `deploy/腾讯云COS配置-tencent-cos-setup.md`：桶配置、凭证管理、资源包现状与抵扣范围、跨厂商成本说明、真机实现指引。**内容见 §3**。
- `deploy/cam-policy.json`：CAM 用户策略模板，action 为 `name/cos:PutObject` + `name/cos:GetObject`，resource 限定到桶内前缀。APPID 与桶名建桶后填入。

## 5. 已知限制

- **抽象层被绑定到具体厂商**：`CosGateway` 把「COS」写进了 `sync_core` 的公共接口名，而 `sync_core` 原定位是「厂商中立纯逻辑包」。将来换厂商需再改一次。这是 D-03 的直接后果，已知并接受。
- **CAM 策略模板含占位符**：`deploy/cam-policy.json` 的 APPID 与桶名在建桶前无法填写。占位符以 `<APPID>` / `<BUCKET>` 标注，建桶后替换。
- **真机 COS 完全未验证**：本次只改命名与文档，行为未变（仍是 `FakeCos` 本地文件系统实现）。所有真机 COS 结论都还没有证据。
- **外网下行流量成本未知**：用户已购标准存储容量包但未购流量包，照片下载流量按量付费。月流量在有真实数据前无法估算。

## 6. 分支与编号

- 本次在 **`feat/F013-cloud-sync`** 分支执行。原因：`packages/sync_core` 与客户端同步代码**只存在于该分支**，`main` 上尚无这些文件（`git ls-tree main packages/` 为空），无法从 main 另开分支做重命名。
- **不分配新的功能编号**。`CosGateway` 抽象与照片直传本属 F013 的设计范围，本次是其中的供应商变更与命名对齐，按开发流程 §「修复已有功能」记录进 F013 的待办登记与测试报告；跨功能的产品设计同步更新 `docs/产品设计-product-design.md`。
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

- 服务端 COS 预签名 URL 生成（T-24）。
- 客户端真机 COS 直传直下实现（T-24）。
- 建桶、CAM 子用户创建、密钥落地（T-05）。
- 购买外网下行流量包（等月流量数据出来再评估）。
- ECS 迁移到腾讯云（已决定不做）。
- 照片生命周期沉降到低频/归档（等存储成本数据）。
