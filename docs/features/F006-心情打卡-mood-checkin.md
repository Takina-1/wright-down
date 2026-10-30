# F006：心情打卡

> 模板：复制到 `docs/features/F编号-中文主题-english-topic.md` 后填写。占位项不是已确认的需求。

- 创建日期：2026-10-30
- 最近更新：2026-10-30
- 需求来源与授权范围：用户在 F005 完成后选定「F006 做心情打卡」，并确认五项决策——心情绑定单条记录、5 种 emoji+文字、可选不设为空、时间轴正文上方显示 emoji（其他显示方式保留方便变更）、稳定标记+映射表存储（不升备份版本号）。
- 功能状态：见 [任务台账](README.md)
- 特性分支：`feat/F006-mood-checkin`
- 关联测试报告：待创建

## 1. 用户场景与目标

写日记时，想给这一刻标个心情。回顾时，时间轴上的卡片能让人一眼看到当时的情绪。

当前应用只有正文和时间，没有情绪维度。用户写完一段文字，无法快速标记「今天开心／低落」；回顾时间轴时，所有卡片看起来都一样，看不出情绪起伏。

本次要解决两件事：

1. **写的时候能标心情**：在记录页给当前正在写的条目标一个心情（5 种 emoji+文字），一次点击直达。
2. **回顾时看得见心情**：时间轴上已标心情的卡片显示对应 emoji，未标的干净显示，不增加负担。

心情绑定到**单条记录**（不是每日心情打卡），是记录的一个可选附加信息。

## 2. 范围与边界

- 本次实现：
  - `Entry` 新增可选 `mood` 字段（稳定标记字符串，非 emoji）。
  - `domain/mood.dart`：5 种心情的标记常量 + 映射表（标记 → emoji + 文字）+ 解析与查询函数。
  - SQLite `entries` 表新增 `mood TEXT` 可空列，schema v2 → v3，**幂等迁移**。
  - 记录页输入区下方新增心情入口，点击弹出**底部弹层**选心情／清除。
  - 时间轴卡片正文上方显示已设心情的 emoji；显示逻辑抽成 `mood.dart` 的纯函数，**不硬编码在页面里**。
  - 备份 v2 加**可选 `mood` 字段**，不升版本号。
  - 心情随条目一起编辑、保存、导出、恢复。

- 本次不实现：
  - 心情统计（连续心情天数、热力图、情绪分析、月度回顾）——见 [产品设计](../产品设计-product-design.md) §三「未做清单」。
  - 每日心情打卡（独立于具体记录的每日心情）。
  - 心情与回顾模块的联动（如按心情筛选、心情日历）。
  - 语音、拍照、标签等其他快捷动作（后续功能编号）。
  - 心情表情自定义（用固定的 5 种）。

- 前置依赖：F001（本地记录与时间轴）、F005（删除与回收站，schema v2 基础）。

- 未决定的问题及影响：无。

## 3. 验收标准

| 编号 | 前置条件 | 用户操作或触发事件 | 可观察的预期结果 |
|---|---|---|---|
| AC-01 | 记录页正在写一条新记录，未设心情 | 查看输入区下方 | 显示心情入口，未设心情时显示 😊 占位 |
| AC-02 | 记录页心情入口可见 | 点击心情入口 | 弹出底部弹层，列出 5 种心情（emoji+文字）；已设心情时额外显示「清除」 |
| AC-03 | 弹层已打开 | 选择一种心情（如 😄开心） | 弹层关闭，心情入口显示该 emoji，随自动保存落库 |
| AC-04 | 一条记录已设心情 | 打开回顾页时间轴 | 该卡片正文上方显示对应 emoji |
| AC-05 | 一条记录未设心情 | 打开回顾页时间轴 | 该卡片不显示心情图标 |
| AC-06 | 一条记录已设心情 | 编辑该记录时点开心情弹层 | 弹层显示当前心情为已选状态 |
| AC-07 | 一条记录已设心情 | 在弹层点「清除」 | 心情恢复为未设，时间轴不再显示该 emoji |
| AC-08 | 数据库处于 schema v2 且有数据 | 应用升级到 v3 | 老数据完整，`mood` 列为 NULL，读写正常 |
| AC-09 | 迁移幂等：用户用旧版打开过已是 v3 结构的库 | 再次升级 | 不报 `duplicate column`，整库可打开 |
| AC-10 | 本地有带 mood 的条目 | 导出备份 | 备份条目带 `mood` 字段 |
| AC-11 | 一份 v1／v2 旧备份（无 mood） | 导入 | 正常导入，条目 `mood` 为 null |
| AC-12 | 心情为可选 | 不设心情直接保存 | 保存成功，条目 `mood` 为 null，不阻塞 |
| AC-13 | 修改 `mood.dart` 映射表 | 查看时间轴与记录页 | 心情 emoji 的显示随之一致变化，无需改页面代码 |
| AC-14 | 全部改动完成 | 质量检查 | 静态分析无问题、全部测试通过、调试 APK 构建通过 |

## 4. 参考实现

查 [功能参考索引](../功能参考索引-feature-reference-index.md)。心情对应「Daily You → StoryPad」，检索词 `mood`／`emotion`。

索引明确记录：这些仓库仅查阅过公开说明与许可证，未下载运行，未确认具体类名、函数或实现路径。本项目按自有数据模型与合并规则实现，**未复用上游源码，也未引入上游依赖与素材**。

本项目取其「心情作为记录附加信息、时间轴展示心情」的思路，但存储采用**稳定标记+映射表**（非直接存 emoji），不依赖任何上游实现。

## 5. 实现方案

### 5.1 数据模型

`Entry` 新增可选字段：

```dart
class Entry {
  const Entry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.dayKey,
    this.deletedAt,
    this.mood,              // 可选；稳定标记字符串，非 emoji
  });
  // ...
  final String? mood;
}
```

`domain/mood.dart` 定义 5 种心情的稳定标记与显示：

| 标记 | emoji | 文字 |
|---|---|---|
| happy | 😄 | 开心 |
| good | 😊 | 不错 |
| neutral | 🙂 | 一般 |
| plain | 😐 | 平淡 |
| sad | 😢 | 难过 |

提供函数：
- `Mood? parseMood(String?)`：标记 → 枚举，非法值 → null。
- `String emojiOf(String? mood)`：标记 → emoji，null → 空串。
- `String labelOf(String? mood)`：标记 → 文字，null → 空串。

选字符串存储而非枚举：与项目 `dayKey` 存字符串的先例一致，备份编解码直接序列化字符串，新增心情种类只改映射表不动数据模型与备份格式。

### 5.2 数据层

SQLite `entries` 表新增 `mood TEXT`（可空），schema **v2 → v3**。迁移**幂等**（参照 F005 的 `deleted_at` 做法）：先 `PRAGMA table_info` 查列，没有 `mood` 才 `ALTER TABLE ADD COLUMN mood TEXT`。新建库（`onCreate`）直接建带该列的表。

`LocalEntryRepository` 接口**不变**——mood 是 `Entry` 字段，`save`／`list`／`exportAll`／`importAll` 自动携带。`save()` 写入 mood（非空才写，与 `deleted_at` 同口径），`_toEntry` 读回 mood。

### 5.3 UI

**记录页**（HomePage 写作区）：
- 输入区下方新增一行心情入口：已设心情显示对应 emoji，未设显示 😊 占位。
- 点击弹出 `ModalBottomSheet`：列出 5 种心情（emoji+文字），已设时额外显示「清除」。
- 选择／清除后，心情写入当前编辑的条目，随自动保存落库。

**时间轴卡片**（TimelinePage）：
- 已设心情的条目，正文上方显示 emoji（用 `emojiOf`）。
- 未设心情不显示。
- 显示逻辑用 `mood.dart` 的纯函数，不硬编码在页面里（对应 AC-13）。

**编辑态**：心情随条目一起载入，编辑时可改。

### 5.4 备份格式与恢复合并

备份 v2 加**可选 `mood` 字段**，**不升版本号**（参照 F005 的 `deletedAt`）：
- 编码：mood 非空才写 `"mood": "happy"`。
- 解码：缺失即 null。
- v1／v2 旧备份（无 mood）解码为 null，完全兼容。

**恢复合并规则**（`decideMerge`）：mood 随 `updatedAt` 一起判定，走 LWW 简单语义——备份 `updatedAt` 更新时，mood 跟备份走：
- 备份带 mood → 用备份的 mood。
- 备份不带 mood（null）→ 本地 mood 被清空（写 null）。

这是「备份更更新就覆盖」的字段级 LWW 自然结果，与 F005 的 `deleted_at` 处理口径一致。mood 是可选附加信息，被清空的影响小（用户可重新设）；代价是导入一份不带 mood 的较新备份会清掉本地心情，属预期行为，界面不单独提示。

### 5.5 数据流

```text
记录页设心情：
  心情入口点击 → ModalBottomSheet → 选心情／清除
    → EntryEditorController 记录当前条目的 mood（随内容一起保存）
    → repository.save(entry) → SQLite 写入 mood

时间轴显示：
  TimelinePage.build → _entries 每条 entry
    → emojiOf(entry.mood) → 正文上方显示 emoji（非空才显示）

备份导出：
  exportAll() → BackupCodec.encode → mood 非空才写

备份恢复：
  BackupCodec.decode → importAll → decideMerge（mood 跟 updatedAt 走）
```

### 5.6 错误处理

| 场景 | 表现 |
|---|---|
| 用户在弹层点「取消」 | 什么也不做，不提示失败 |
| 心情为可选，不设心情保存 | 正常保存，mood 为 null，不阻塞 |
| 保存失败（含 mood） | 提示保存失败，条目保留原心情与正文 |
| 心情选择本身 | 纯 UI 选择，无独立失败路径，落库走已有 save |

### 5.7 数据迁移与兼容性

- 数据库 schema v2 → v3，`ALTER TABLE ADD COLUMN mood TEXT` 可空列，幂等迁移，老库直接升级。
- 备份 v2 加可选 mood 字段，向后兼容（v1／v2 旧备份可读）；v2 带 mood 的备份在旧版本应用上无法导入，属预期。
- 与 [产品设计](../产品设计-product-design.md) 的差异：产品设计 §11 已把「😊心情」列为记录页快捷动作、「心情选择用底部弹层」，本次落实该决策；未改变共用架构。

### 5.8 受影响模块／文件

```text
client/lib/src/domain/entry.dart                   新增 mood 字段
client/lib/src/domain/mood.dart                    新增：心情标记、映射表、解析函数
client/lib/src/domain/export/backup_codec.dart     编码／解码 mood 字段
client/lib/src/domain/export/merge_decision.dart   合并时 mood 跟 updatedAt 走
client/lib/src/data/local/sqlite_entry_repository.dart  schema v3、迁移、mood 读写
client/lib/src/ui/entry_editor_controller.dart     记录／清除当前条目的 mood
client/lib/src/ui/home_page.dart                   记录页心情入口与弹层
client/lib/src/ui/timeline_page.dart               时间轴卡片显示心情 emoji
```

新增依赖：无。

## 6. 开发任务

| 任务 | 依赖 | 产出 | 检查方式 | 完成情况 |
|---|---|---|---|---|
| T1 | — | `Entry.mood` 与 `mood.dart` 映射表 | 域层单测 | 未开始 |
| T2 | T1 | SQLite schema v3 与幂等迁移 | 宿主 FFI 集成测试：v2 库升级后老数据完好 | 未开始 |
| T3 | T1 | mood 字段读写（save／list／exportAll／_toEntry） | 集成测试 | 未开始 |
| T4 | T1 | 备份编解码 mood 字段 | 编解码单测覆盖带／不带 mood | 未开始 |
| T5 | T3、T4 | 合并规则（mood 跟 updatedAt 走） | 集成测试 | 未开始 |
| T6 | T1 | `EntryEditorController` 记录／清除 mood | 控制器单测 | 未开始 |
| T7 | T3、T6 | 记录页心情入口与弹层 | 组件测试 | 未开始 |
| T8 | T1 | 时间轴卡片显示心情 emoji | 组件测试 | 未开始 |
| T9 | T1~T8 | 全量检查与构建 | 静态分析、全部测试、调试 APK | 未开始 |

## 7. 测试计划

**单元测试（纯 Dart）**
- `mood.dart`：5 种心情标记 ↔ emoji ↔ 文字一致；`parseMood` 对合法值／非法值／null 的行为；`emojiOf`／`labelOf` 对 null 返回空。

**集成测试（宿主 sqflite FFI）**
- schema 迁移：v2 库写入数据，升 v3 后老数据完整、`mood` 为 NULL；迁移幂等（用旧版打开过 v3 结构再升级不报 duplicate column）。
- mood 字段读写：`save` 带 mood、`list` 读回、`exportAll` 含 mood。
- 备份编解码：带 mood 往返一致；v1／v2 旧备份 mood 为 null；mood 非空才写键。
- 合并：备份 `updatedAt` 更新时 mood 跟备份走；备份不带 mood 时本地 mood 被清空的边界。

**组件测试**
- 记录页心情入口显示（已设 emoji／未设 😊）；弹层列出 5 种 + 清除；选择后落库；清除后恢复未设；编辑已设心情的条目弹层显示当前心情。
- 时间轴卡片：已设显示 emoji、未设不显示；改映射表显示随之变（AC-13）。

**构建检查**
- `flutter analyze`、`flutter test`、`flutter build apk --debug` 全部通过。

## 8. 实施变化与交付

- 实际实现路径：完成后填写
- 实际检查命令：执行后填写
- 已知限制与未完成项：如实填写
- 测试报告与交付物：创建后链接

| 日期 | 需求或方案变化 | 原因与决策来源 | 影响的验收标准 |
|---|---|---|---|
| 2026-10-30 | 初版：心情绑定单条记录、5 种 emoji+文字、可选不设为空、时间轴正文上方显示 emoji、稳定标记+映射表存储、备份 v2 加可选 mood 不升版本 | 用户在 F006 立项时确认 | AC-01 ~ AC-14 |
| 2026-10-30 | mood 恢复合并采用 LWW 简单语义：备份 updatedAt 更新时 mood 跟备份走，备份不带 mood 则清空本地 mood | 字段级 LWW 的自然结果，与 deleted_at 口径一致；mood 为可选附加信息 | AC-10、AC-11 |
