# F005：删除记录与回收站

- 创建日期：2026-10-30
- 需求来源与授权范围：用户在 F001、F004 完成后选定「F005 做删除记录」，并确认两项决策——删除语义采用**软删除 + 回收站**，入口同时放在**回顾页长按**与**记录页编辑态**。
- 功能状态：见 [功能任务台账](README.md)
- 特性分支：`feat/F005-entry-delete-and-trash`
- 关联测试报告：[F005 测试报告](../test-reports/F005-删除记录与回收站测试报告-entry-delete-and-trash-test-report.md)

## 1. 用户场景与目标

写错了、重复了、或者只是不想再看到的一条记录，需要能删掉。

当前应用只能新增、编辑、导出和恢复，**没有任何删除入口**。用户 F001 与 F004 做的都是「能写、能带走」，但「写错了删不掉」在 7 天自用前是硬伤：唯一的数据都在本机，没有云端副本，误写一条只能留着。

本次要解决两件事：

1. **能删**：在回顾页长按一条记录，或在记录页编辑某条记录时，都能删除它，删除前有明确确认。
2. **删错能救**：删除不是物理抹除，而是移到回收站。条目从时间轴消失，但数据仍在库里，可以恢复，也可以随时彻底删除。

「删错能救」还牵动 F004 的备份恢复：恢复一份旧备份时，已经在本地删掉的条目**不能诈尸**。这要求备份格式能表达「这条已被删除」，因此备份格式从 `version: 1` 升到 `version: 2`。

## 2. 范围与边界

- 本次实现：
  - 软删除语义：条目标记删除时间后从时间轴隐藏，数据保留。
  - 回收站：列出已删除条目，支持单条恢复、单条彻底删除、清空回收站。
  - 两个删除入口：回顾页长按条目弹出「编辑／删除」；记录页编辑已有条目时出现「删除这条」按钮。
  - SQLite 表新增 `deleted_at` 列，schema 版本 1 → 2，带迁移。
  - 备份格式升到 `version: 2`，条目可带 `deletedAt`；`version: 1` 的旧备份仍可导入。
  - 恢复合并规则调整为：本地已删除的条目不会被未删除的备份复活。
  - Markdown 可读导出只含未删除条目。
  - 「我的」页新增「回收站」入口；本地数据说明文案补充删除与回收站行为。

- 本次不实现：
  - 回收站自动过期清理（条目一直保留到用户手动彻底删除或清空）。
  - 批量选择删除、批量恢复。
  - 撤销栈跨进程重启保留（删除后的撤销只在当前会话有效，跨重启靠回收站）。
  - 云端同步、账号、跨设备删除传播（删除标记只随手动导出的备份文件走）。
  - 编辑器内富文本附件、图片、标签。

- 前置依赖：F001（本地记录与时间轴）、F004（导出与备份恢复，备份格式在此基础上升版）。

- 未决定的问题及影响：无。

## 3. 验收标准

| 编号 | 前置条件 | 用户操作或触发事件 | 可观察的预期结果 |
|---|---|---|---|
| AC-01 | 回顾页有若干条目 | 长按其中一条 | 弹出操作菜单，含「编辑」和「删除」 |
| AC-02 | 已通过长按菜单选择「删除」 | 确认删除 | 弹出确认对话框，写明条目内容摘要与「删除后可在回收站找回」；确认后条目从时间轴消失，其余条目不受影响 |
| AC-03 | 记录页正在编辑一条已保存的条目 | 查看编辑界面 | 出现「删除这条」按钮；编辑一条尚未保存的新记录时不出现 |
| AC-04 | 在记录页点击「删除这条」并确认 | 确认删除 | 该条目被删除，编辑器回到空白的新记录状态，正文框清空 |
| AC-05 | 回收站有已删除条目 | 打开「我的 → 回收站」 | 列出已删除条目，显示正文摘要与删除时间，每条提供「恢复」和「彻底删除」 |
| AC-06 | 回收站有已删除条目 | 点击「恢复」 | 条目回到时间轴，正文、创建时间、dayKey 与删除前一致 |
| AC-07 | 回收站有已删除条目 | 点击「彻底删除」 | 条目从数据库物理移除，回收站不再显示，也无法再恢复 |
| AC-08 | 回收站有多个条目 | 点击「清空回收站」并确认 | 回收站清空，时间轴未删除的条目不受影响 |
| AC-09 | 回收站为空 | 打开回收站 | 显示空状态说明，不出现异常 |
| AC-10 | 本地已删除条目 A | 导出备份 | 备份文件包含 A，条目带 `deletedAt` 删除时间标记 |
| AC-11 | 本地已删除条目 A，备份中 A 未被删除 | 导入该备份 | A 不出现在时间轴，不会被复活 |
| AC-12 | 备份中条目 B 带 `deletedAt`，本地 B 存在且未删除，且备份中的删除时间更新 | 导入该备份 | 本地 B 被标记为已删除，出现在回收站 |
| AC-13 | 有一份 `version: 1` 的旧备份（条目无删除标记） | 导入该备份 | 正常导入成功，旧格式不被拒绝 |
| AC-14 | 本地已删除条目 A | 导出 Markdown | Markdown 只含未删除条目，不含 A |
| AC-15 | 回顾页、记录页 | 查看所有入口 | 已删除条目在任何列表里都不出现 |
| AC-16 | 删除操作在存储层抛出异常 | 执行删除 | 删除失败，条目仍在原位，界面给出失败原因，不静默消失 |
| AC-17 | 模拟数据库在 `version: 1` 状态下已有数据 | 应用升级到新版本 | 老数据完整保留，读写正常，删除标记初始为空 |
| AC-18 | 全部改动完成 | 质量检查 | 静态分析无问题、全部自动化测试通过、调试 APK 构建通过 |

恢复为纯本地操作，不依赖网络，断网状态下同样可用。

## 4. 参考实现

查 [功能参考索引](../功能参考索引-feature-reference-index.md)。本次按本项目自有格式与合并规则实现，未复用上游源码，也未引入上游依赖与素材。

索引中已记录的日记类应用普遍提供「删除后进入回收站、保留若干天」的做法，本项目取其**保留与可恢复**的思路，但**不引入自动过期清理**（本次不实现，且明确记录为已知限制）。删除标记随备份文件传播的做法在本项目自有备份格式内实现，不依赖任何上游实现。

## 5. 实现方案

### 5.1 页面与状态变化

```text
我的 → 回收站（新增二级页 TrashPage）
        列表：已删除条目（按删除时间倒序）
        每条：[恢复] [彻底删除]
        顶部：[清空回收站]（二次确认）

回顾页 TimelinePage
        长按条目 → 底部弹窗 [编辑] [删除]
        删除 → 确认对话框 → 软删除 → 移除出列表
        底部提示「已移到回收站」+ [撤销]（撤销 = 从回收站恢复）

记录页（HomePage 写作区）
        编辑已有条目时，底部出现文字按钮「删除这条」
        确认删除 → 软删除 → 编辑器复位为空白新条目
```

### 5.2 数据模型

SQLite `entries` 表新增一列：

```sql
deleted_at INTEGER  -- 可空；epoch 毫秒 UTC。NULL 表示未删除
```

schema 版本从 1 升到 2。迁移（`onUpgrade`）执行 `ALTER TABLE entries ADD COLUMN deleted_at INTEGER`，可空列无默认值，老行读出即为 `NULL`，老数据不受影响。新建库（`onCreate`）直接建带该列的表。

domain 层的 `Entry` 增加可选字段：

```dart
class Entry {
  const Entry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.dayKey,
    this.deletedAt,          // 可选；非空表示已删除
  });
  final DateTime? deletedAt;
}
```

`deletedAt` 是可选命名参数，域内现有构造点无需改动。

### 5.3 仓库接口

`LocalEntryRepository` 新增五个方法，`list()` 与 `exportAll()` 的语义随之调整：

| 方法 | 语义 |
|---|---|
| `Future<List<Entry>> list({before, limit})` | **只返回未删除条目**（`deleted_at IS NULL`），排序不变 |
| `Future<List<Entry>> exportAll()` | **返回全部条目，含已删除条目**，供备份携带删除标记 |
| `Future<List<Entry>> listDeleted({int limit = 30})` | 回收站列表，按 `deleted_at DESC, id DESC` |
| `Future<void> softDelete(String id)` | 软删除：置 `deleted_at` 与 `updated_at` 为当前时刻 |
| `Future<void> restore(String id)` | 从回收站恢复：清空 `deleted_at`，`updated_at` 置为当前时刻 |
| `Future<void> purge(String id)` | 彻底删除：`DELETE FROM entries WHERE id = ?` |
| `Future<int> purgeAll()` | 清空回收站：删除所有已删除条目，返回删除条数 |

软删除与恢复都更新 `updated_at`，是为了让备份合并的「谁的版本更新」判定对删除同样成立。

### 5.4 备份格式 v2

```json
{
  "format": "local-diary-backup",
  "version": 2,
  "exportedAt": "2026-10-30T02:00:00.000Z",
  "entryCount": 3,
  "entries": [
    {
      "id": "0f0c2f6a-1f2e-4a1b-9d3c-2b7a5e9f1c22",
      "content": "正文第一段\n正文第二段",
      "createdAt": "2026-10-28T02:00:00.000Z",
      "updatedAt": "2026-10-28T02:05:00.000Z",
      "dayKey": "2026-10-28",
      "deletedAt": "2026-10-30T01:00:00.000Z"
    }
  ]
}
```

`deletedAt` 只在该条目已删除时出现；未删除的条目不写这个字段。解码时缺失即视为未删除。

**v1 兼容**：`version: 1` 的备份没有 `deletedAt`，解码后所有条目一律视为未删除，仍可正常导入。`version` 大于 2 时拒绝导入并提示升级；`version` 小于 1 视为损坏。

### 5.5 恢复合并规则

| 本地状态 | 备份状态 | 动作 |
|---|---|---|
| 不存在 | 未删除 | 插入 |
| 不存在 | 已删除 | 插入，但保持已删除状态（保留删除记录，避免更旧的备份让它复活） |
| 存在，未删除 | 未删除 | 备份 `updatedAt` 更新则更新 `content` 与 `updatedAt`，否则跳过 |
| 存在，未删除 | 已删除 | 备份 `updatedAt` 更新则置为已删除，否则跳过 |
| 存在，已删除 | 未删除 | **跳过，不复活**（无论备份 `updatedAt` 多新） |
| 存在，已删除 | 已删除 | 备份 `updatedAt` 更新则更新 `deletedAt`，否则跳过 |

「存在，已删除 + 未删除 → 跳过」是本次的核心承诺：本地删掉的条目不会被任何备份恢复回来。代价是跨设备删除不传播（本次不实现同步，该限制照实记录）。

导入仍在单个事务内完成，任一条目出错整体回滚。

### 5.6 备份编解码的额外校验

本次顺带修掉 F004 遗留评审记录中的编解码问题（见 [F004 计划](F004-导出与备份恢复计划-export-and-backup-plan.md) 的 Minor 清单）：

- `entryCount` 必须与 `entries` 实际条数一致，否则判损坏。
- `version < 1` 判损坏，不再当作合法旧版本放行。
- 时间串必须带 `Z` 或显式时区偏移，否则判损坏（避免同一文件在不同设备解出不同绝对时刻）。
- 解码时对 JSON 结构异常（如畸形 JSON 抛出非 `FormatException`）统一转成 `BackupFormatException`，保证界面能映射成用户文案。
- 编码侧与解码侧口径对齐：编码前校验 `id` 非空、`content` 非空白、`dayKey` 合法。
- `BackupDocument.entries` 改为不可变列表。

### 5.7 Markdown 导出

Markdown 是「可读导出」，只渲染未删除条目。`MarkdownExporter` 内部过滤 `deletedAt != null` 的条目，其余分组与排序规则不变。

### 5.8 数据流

```text
回顾页长按删除：
  TimelinePage → 确认对话框 → repository.softDelete(id)
    → 从 _entries 移除 → SnackBar「已移到回收站」+ [撤销]
    → 撤销：repository.restore(id) → 插回 _entries

记录页删除：
  HomePage → 确认对话框 → EntryEditorController.deleteCurrent()
    → repository.softDelete(id) → 编辑器复位为空白新条目
    → SnackBar「已移到回收站」+ [撤销]

回收站：
  TrashPage → repository.listDeleted() → 列表
    [恢复] → repository.restore(id) → 移出列表
    [彻底删除] → 确认 → repository.purge(id) → 移出列表
    [清空] → 确认 → repository.purgeAll() → 清空列表
```

### 5.9 错误处理

| 场景 | 表现 |
|---|---|
| 用户在确认对话框点「取消」 | 什么也不做，不提示失败 |
| 删除失败（存储层异常） | 提示「删除失败，这条记录仍在」，条目留在原位 |
| 恢复失败 | 提示「恢复失败」，条目仍在回收站 |
| 彻底删除失败 | 提示「彻底删除失败」，条目仍在回收站 |
| 清空回收站失败 | 提示「清空失败」，回收站内容不变 |
| 删除的条目正被编辑（记录页） | 删除成功后编辑器复位，不会留下指向已删条目的编辑态 |
| 回收站条目数量多 | 分页加载，默认每页 30 条 |

### 5.10 受影响模块／文件

```text
client/lib/src/domain/entry.dart                    新增 deletedAt 字段
client/lib/src/domain/local_entry_repository.dart   新增 5 个方法，list/exportAll 语义变化
client/lib/src/data/local/sqlite_entry_repository.dart   schema v2、迁移、5 个新方法、list 过滤
client/lib/src/domain/export/backup_codec.dart       v1/v2 解码、编码 v2、额外校验
client/lib/src/domain/export/backup_document.dart     不可变 entries
client/lib/src/domain/export/markdown_exporter.dart  过滤已删除条目
client/lib/src/ui/entry_editor_controller.dart        canDelete、deleteCurrent
client/lib/src/ui/timeline_page.dart                 长按菜单、删除、撤销提示
client/lib/src/ui/home_page.dart                     记录页删除按钮、回收站入口与回调
client/lib/src/ui/trash_page.dart                    新增回收站页
client/lib/src/ui/local_data_page.dart               回收站入口
```

新增依赖：无。

### 5.11 数据迁移与兼容性

- 数据库 schema 1 → 2，用 `ALTER TABLE ADD COLUMN` 加可空列，无数据重写，老库直接升级。
- 备份格式 1 → 2，向后兼容（v1 可读）；v2 文件在旧版本应用上无法导入，属预期。
- 与 [产品设计](../产品设计-product-design.md) 的差异：产品设计需补充「删除采用软删除 + 回收站」这一决策。

## 6. 开发任务

| 任务 | 依赖 | 产出 | 检查方式 | 完成情况 |
|---|---|---|---|---|
| T1 | — | `Entry.deletedAt` 与仓库接口扩展 | 域层单测与静态分析 | 未开始 |
| T2 | T1 | SQLite schema v2 与迁移 | 宿主 FFI 集成测试：v1 库升级后老数据完好 | 未开始 |
| T3 | T2 | 软删除／恢复／彻底删除／清空／回收站列表 | 集成测试覆盖全部方法与边界 | 未开始 |
| T4 | T1 | 备份编解码 v2 与 v1 兼容 | 编解码单测覆盖两种版本与全部拒绝分支 | 未开始 |
| T5 | T3、T4 | 恢复合并规则调整 | 集成测试覆盖合并表全部六行与幂等 | 未开始 |
| T6 | T1 | Markdown 过滤已删除条目 | 渲染单测 | 未开始 |
| T7 | T1、T3 | `EntryEditorController.deleteCurrent` 与 `canDelete` | 控制器单测 | 未开始 |
| T8 | T3 | 回顾页长按菜单与删除 | 组件测试 | 未开始 |
| T9 | T3、T7 | 记录页删除按钮 | 组件测试 | 未开始 |
| T10 | T3 | 回收站页 | 组件测试 | 未开始 |
| T11 | T8~T10 | 「我的」页入口与本地数据说明文案 | 组件测试 | 未开始 |
| T12 | T1~T11 | 全量检查与构建 | 静态分析、全部测试、调试 APK | 未开始 |
| T13 | T12 | 真机验收并更新报告与台账 | 按第 7 节执行 | 未开始 |

## 7. 测试计划

**单元测试（纯 Dart）**

- `BackupCodec`：v2 编解码往返（含 `deletedAt`）；v1 备份解码后 `deletedAt` 全为 `null`；拒绝 `version` 为 0、3、非整数、非 JSON、`format` 不符、`entryCount` 与实际条数不符、条目缺字段、字段类型错误、`dayKey` 非法、时间串缺时区偏移、重复 ID、空白正文。
- `MarkdownExporter`：已删除条目不渲染；未删除条目的分组与排序不变。
- `EntryEditorController`：新条目不可删（`canDelete` 为假）；已有条目可删；删除后编辑器复位；删除失败时状态不变且有错误提示。

**集成测试（宿主 sqflite FFI）**

- schema 迁移：用 `version: 1` 建库写入数据，再以 `version: 2` 打开，老数据完整、`deleted_at` 为 `NULL`。
- `list()` 不返回已删除条目；`listDeleted()` 只返回已删除条目且按删除时间倒序。
- `softDelete` 后条目仍可在 `exportAll()` 中见到且带 `deletedAt`；`restore` 后 `deleted_at` 为 `NULL`；`purge` 后物理移除。
- `importAll` 覆盖合并表六行全部分支、幂等、事务回滚。
- 删除失败（用会抛异常的替身）时条目仍在。

**组件测试**

- 回顾页长按弹菜单、确认对话框含内容摘要、取消不删除、确认后条目消失、撤销后条目回来。
- 记录页编辑态显示删除按钮、空白新记录不显示、确认后编辑器复位。
- 回收站列表、空状态、恢复、彻底删除、清空。

**真机手动测试（Android）**

- 真实删除一条记录并确认时间轴更新、回收站可见、恢复后内容与时间不变。
- 彻底删除后重启应用，条目确实不在。
- 导出含删除标记的备份，用另一台干净安装或清空数据后导入，验证删除标记生效。
- 升级安装：先装旧版本写几条，再装新版本，验证老数据完好且删除功能可用。

**构建检查**

- `flutter analyze`、`flutter test`、`flutter build apk --debug` 全部通过。

## 8. 实施变化与交付

- 实际实现路径：完成后填写
- 实际检查命令：执行后填写
- 已知限制与未完成项：如实填写
- 测试报告与交付物：创建后链接

| 日期 | 需求或方案变化 | 原因与决策来源 | 影响的验收标准 |
|---|---|---|---|
| 2026-10-30 | 初版：软删除 + 回收站，两处删除入口，备份格式升 v2 | 用户在 F005 立项时确认 | AC-01 ~ AC-18 |
