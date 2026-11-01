# F010：随手拍

> 模板：复制到 `docs/features/F编号-中文主题-english-topic.md` 后填写。占位项不是已确认的需求。

- 创建日期：2026-11-01
- 最近更新：2026-11-01
- 需求来源与授权范围：用户 2026-11-01 确认处理 Phase 2 剩余功能。本功能给日记条目加一张照片。
- 功能状态：见 [任务台账](../features/README.md)
- 关联测试报告：创建后填写相对链接

## 1. 用户场景与目标

写日记时不只打字，有时想配上一张照片（拍下的瞬间、看到的风景）。当前应用只有文字，无法给条目配图。本次给条目加一张照片：写日记时从相册选一张图，回顾页条目显示缩略图。纯本地数据，不依赖网络、不引入服务器。

## 2. 范围与边界

- 本次实现：
  - `Entry` 增加可选 `photo` 字段（`Uint8List?`，存图片原始字节）。
  - schema 升到 v5：`entries` 加可空列 `photo BLOB`，迁移幂等。
  - 记录页（写日记）：正文区下方加「📷 拍照」按钮，点开系统相册选一张图，选中后显示缩略图，可替换或移除。
  - 回顾页：条目 tile 显示照片缩略图（有图时显示在正文上方）。
  - 备份格式随照片升到 `version: 4`：条目可带 `photo`（base64 字符串）；`version: 3` 旧备份仍可导入（无 photo）。
  - 边界（无图、大图、非图片文件、导入旧备份、缩略图显示）写进验收标准并配测试。

- 本次不实现：
  - 多张照片（本期每条只配一张）。
  - 相机直接拍摄（本期只从相册选图，不调相机；用 `file_picker` 的 `FileType.images`）。
  - 照片裁剪、滤镜、旋转。
  - 云端同步照片（Phase 4 账号+同步时统一处理）。

- 前置依赖：F001（本地记录）、F004（备份格式）、F005（删除记录与回收站）、F009（标签，同表新列）。

- 未决定的问题及影响：照片大小本期不设硬限制，但单张建议不超过 5MB；超限在选图时提示。

## 3. 验收标准

| 编号 | 前置条件 | 用户操作或触发事件 | 可观察的预期结果 |
|---|---|---|---|
| AC-01 | 记录页写日记 | 点「📷 拍照」从相册选一张图 | 条目带照片，记录页显示缩略图 |
| AC-02 | 记录页已选照片 | 点「移除」清除照片后保存 | 照片清除，回顾页不显示缩略图 |
| AC-03 | 记录页已选照片 | 再选一张替换 | 照片替换为新图 |
| AC-04 | 回顾页有带照片条目 | 打开回顾页 | 条目 tile 显示照片缩略图 |
| AC-05 | 回顾页条目无照片 | 打开回顾页 | 条目不显示缩略图区域 |
| AC-06 | 选非图片文件 | 从相册选一个非图片文件 | 拒绝并提示「请选择图片」 |
| AC-07 | 导入 `version: 3` 旧备份 | 恢复备份 | 旧备份无 photo，导入后条目 photo 为空，不报错 |
| AC-08 | 导出带照片条目 | 备份 | 备份 JSON 含 photo（base64），重新导入保留照片 |
| AC-09 | domain/仓储层照片读写 | 单元测试 | 照片字节往返、空照片、损坏 base64 全部有对应用例且通过 |
| AC-10 | 全部改动完成 | 质量检查 | 静态分析无问题、全部测试通过、调试 APK 构建通过 |

## 4. 参考实现

查 [功能参考索引](../功能参考索引-feature-reference-index.md)「心情、照片与快捷输入」。参考索引明确记录：心情选择、照片导入、附件引用；首页保留一次点击入口。

本项目照片是**条目上的单张图片**（原始字节存 BLOB 列），不建附件表。本次**不下载、不运行、不复用上游源码**，也未引入上游依赖与素材。

| 仓库与固定提交 | 源码永久链接 | 已确认逻辑 | 借鉴方式与差异 | 许可核查（源码复用时） |
|---|---|---|---|---|
| 无（纯逻辑自实现） | — | — | — | — |

## 5. 实现方案

### 5.1 页面与状态变化

记录页（HomePage 的编辑器）：正文区下方加一行「📷 拍照」按钮（与心情按钮并排）。点开系统相册选图，选中后正文上方显示缩略图，缩略图右上角「✕」移除，点缩略图可重新选图替换。

回顾页（TimelinePage）：条目 tile 的 leading 位置（心情 emoji 旁）或正文上方显示照片缩略图。有图时显示，无图时不显示该区域。

### 5.2 数据流、模型与接口

`Entry` 增加字段：

```dart
class Entry {
  const Entry({..., this.photo});
  final Uint8List? photo;   // 新增：可选照片原始字节
}
```

schema v5：`entries` 加可空列 `photo BLOB`。仓储层 `save`/`importAll` 读写 `photo`（`entry.photo?.toList()` 存 BLOB，读回 `Uint8List.fromList`）。`_toEntry` 解码 BLOB 为 `Uint8List?`。

备份格式升 `version: 4`：`_encodeEntry` 写 `photo`（base64 字符串，仅非空时），`_decodeEntry` 读 `photo`（缺失视为空，非 base64 判损坏）。`version: 3` 旧备份仍可解码（photo 缺失→空）。

合并规则：照片跟 `updatedAt` 走（与 mood/tags 一致）。

照片选择：`file_picker` 的 `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg','jpeg','png','webp','gif'], withData: true)`，取 `file.bytes`。非图片（扩展名不符或字节无效）拒绝。

### 5.3 受影响模块／文件

```text
client/lib/src/domain/entry.dart                 Entry 加 photo 字段
client/lib/src/data/local/sqlite_entry_repository.dart   schema v5 + photo 列 + save/import/_toEntry
client/lib/src/domain/export/backup_document.dart 备份格式 v4
client/lib/src/domain/export/backup_codec.dart   备份 photo 编码解码（base64）
client/lib/src/domain/export/merge_decision.dart  合并带 photo
client/lib/src/ui/home_page.dart                  记录页照片选择与缩略图
client/lib/src/ui/timeline_page.dart              回顾页条目缩略图
client/test/data/sqlite_entry_photo_test.dart     新增：photo 读写/迁移/筛选单测
client/test/domain/backup_codec_photo_test.dart   新增：备份照片往返单测
client/test/ui/home_page_photo_test.dart          新增：记录页选图组件测试
```

新增依赖：无（复用已有 `file_picker`）。

### 5.4 离线、权限拒绝、失败与恢复

- 选图不申请运行时权限（`file_picker` 用 SAF，Android 13+ 无需存储权限）。
- 照片字节存本地库，离线照常可用。
- 损坏 base64、非图片文件、BLOB 解码失败一律拒绝或退回空，不让界面崩溃（与 F004/F009 脏数据退回口径一致）。

### 5.5 数据迁移与兼容性

- schema v4→v5：`entries` 加可空列 `photo BLOB`，迁移幂等（同 v2/v3/v4 的 ALTER 口径）。
- 备份格式 v3→v4：新增 photo 键（base64），旧 v3 备份可导入（photo 缺失→空）。
- 与 [产品设计](../产品设计-product-design.md) 的差异：产品设计 §二未做清单未列照片；本功能属 Phase 2「随手拍」范围，本次落实。

## 6. 开发任务

| 任务 | 依赖 | 产出 | 检查方式 | 完成情况 |
|---|---|---|---|---|
| T1 | — | Entry 加 photo 字段 | 域层单测（空/非空） | 未开始 |
| T2 | T1 | schema v5 + 仓储 photo 读写 + backup v4 + merge | 仓储/备份单测 | 未开始 |
| T3 | T2 | 记录页照片选择与缩略图 | 组件测试 | 未开始 |
| T4 | T2 | 回顾页条目缩略图 | 组件测试 | 未开始 |
| T5 | T1-T4 | 全量检查与构建 | 静态分析、全部测试、调试 APK | 未开始 |
| T6 | T5 | 真机验收并更新报告与台账 | 按第 7 节执行 | 未开始 |

## 7. 测试计划

| 验收编号 | 场景（正常／异常／边界） | 测试层级 | 环境或设备要求 |
|---|---|---|---|
| AC-09 | photo 字段边界 | 单测 | 宿主 flutter_test |
| AC-07、AC-08 | 旧备份导入 / 导出带照片 | 仓储+备份单测 | 宿主 flutter_test |
| AC-01、AC-02、AC-03、AC-06 | 记录页选图/移除/替换/拒绝非图 | 组件测试 | 宿主 flutter_test |
| AC-04、AC-05 | 回顾页缩略图显示/不显示 | 组件测试 | 宿主 flutter_test |
| AC-10 | 静态分析、全量测试、构建 | 构建检查 | 宿主 flutter |

真机验收在 T6 进行：在真机记录页选图、回顾页看缩略图、移除照片、导入旧备份。

## 8. 实施变化与交付

- 实际实现路径：完成后填写
- 实际检查命令：执行后填写
- 已知限制与未完成项：如实填写
- 测试报告与交付物：创建后链接

| 日期 | 需求或方案变化 | 原因与决策来源 | 影响的验收标准 |
|---|---|---|---|
| 2026-11-01 | 初版：条目加 photo 字段，BLOB 存原始字节，备份 base64 | 用户确认处理 Phase 2 剩余功能 | AC-01 ~ AC-10 |
