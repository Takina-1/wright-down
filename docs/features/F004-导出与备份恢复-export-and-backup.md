# F004：导出与备份恢复

- 创建日期：2026-10-29
- 授权来源：用户在 F001~F003 完成后选定「F004 做导出与备份恢复」，并确认双产物、SAF 保存加分享、按 ID 加修改时间合并、不加密四项决策。
- 状态：[功能任务台账](README.md)
- 特性分支：`feat/F004-export-and-backup`

## 1. 目标与范围

让用户在本地记录之外，能把日记以两种形式带走：

- **完整备份（可恢复）**：JSON 文件，含条目 ID、正文、创建时间、修改时间、dayKey，可从文件恢复到本机。
- **可读导出**：Markdown 文件，按日期分组、按时间倒序排列，正文原样保留，仅供阅读。

恢复采用合并而非覆盖：同一份备份可反复导入且结果幂等，不会因为导入旧备份而抹掉手机上更新的日记。

本次不实现定时自动备份、备份加密与口令管理、Markdown 反向导入、附件与图片、备份文件签名、云端备份接口、跨设备自动同步。当前版本条目只有正文与时间，因此备份不含附件与删除标记。

入口位于「我的 → 导出与备份」二级页。导出文件通过系统文件选择器（SAF）保存到用户自选位置，并可从应用内发起系统分享。

## 2. 验收标准

| 编号 | 场景 | 预期结果 |
|---|---|---|
| AC-01 | 在「导出与备份」页触发备份导出 | 弹出系统文件选择器；选定位置后写入 JSON 备份文件，并提示导出条数 |
| AC-02 | 导出备份后核对内容 | 备份含全部条目的 ID、正文、创建时间、修改时间、dayKey；条数与本地条数一致，不受时间轴 30 条分页限制 |
| AC-03 | 导出 Markdown 并打开阅读 | 按日期倒序分组、组内按创建时间倒序；正文换行、emoji 与 Markdown 符号原样保留 |
| AC-04 | 导出后从应用内分享 | 弹出系统分享面板，可把备份文件或 Markdown 文件发送到其他应用 |
| AC-05 | 在文件选择器或分享面板取消 | 不显示失败信息，页面状态保持可用，不产生空文件，不残留临时文件 |
| AC-06 | 导入一份包含新旧条目的备份 | 本地没有的条目被插入；本地存在且备份更新的一条被更新为备份正文；本地更新的一条保持本地内容不变 |
| AC-07 | 同一备份文件连续导入两次 | 第二次导入不改变任何条目，结果幂等 |
| AC-08 | 导入损坏或不支持的备份文件 | 文件非 JSON、字段缺失或类型错误、`format` 不符、`version` 高于当前支持时，不导入任何条目并给出可区分的原因；导入过程出错时本地数据保持不变 |
| AC-09 | 恢复完成后查看回顾页 | 能读到恢复的条目，条目 ID 与创建时间与备份一致，可继续编辑 |
| AC-10 | Android 工程与真机 | 新增依赖后静态分析无问题、全部自动化测试通过、调试 APK 构建通过；SAF 真实弹窗与分享的真机结果另记实测 |

恢复为纯本地操作，不依赖网络，断网状态下同样可用。

## 3. 方案

### 3.1 分层与新增文件

沿用 `LocalEntryRepository` 的既有模式：接口定义在 domain，实现在 data 或 platform。Domain 层保持零框架、零 SDK 依赖。

```text
client/lib/src/domain/export/
  backup_document.dart      备份文档模型：format、version、exportedAt、entries
  backup_codec.dart         Entry 列表与 JSON 文本互转（纯 Dart）
  markdown_exporter.dart    Entry 列表渲染为 Markdown 文本（纯 Dart）
  file_gateway.dart         FileGateway 抽象接口
client/lib/src/data/local/
  sqlite_entry_repository.dart   新增 exportAll() 与 importAll()
client/lib/src/platform/
  saf_file_gateway.dart    FileGateway 实现：file_selector + share_plus + path_provider
client/lib/src/ui/
  export_controller.dart    编排：读条目、编码、交给 FileGateway
  export_page.dart          「导出与备份」二级页
```

新增依赖：`file_selector`（SAF 保存与选择）、`share_plus`（系统分享）、`path_provider`（临时目录）。三个插件均不申请运行时权限。

导出的落盘路径固定为「先写临时文件，再复制到用户选定位置」：`FileGateway` 先把内容写入应用临时目录的临时文件，SAF 保存时复制过去；系统分享复用同一个临时文件，因为 `share_plus` 分享的是文件路径而不是 SAF 返回的内容地址。分享或保存结束后清理临时文件；用户取消时不保留临时文件，也不产生空文件。

### 3.2 数据流

导出：

```text
ExportPage → ExportController
  → LocalEntryRepository.exportAll()      全量读取，不分页
  → BackupCodec.encode / MarkdownExporter.render   纯 Dart 编码
  → FileGateway.saveFile(...)              SAF 弹选择器，用户选位置后写入
  → 提示「已导出 N 条」
```

恢复：

```text
ExportPage → ExportController
  → FileGateway.pickFile()                 SAF 选择 .json 文件
  → BackupCodec.decode(text)               校验 format、version 与字段
  → 预览「新增 K 条 · 更新 M 条 · 跳过 N 条」
  → 用户确认
  → LocalEntryRepository.importAll(entries) 单事务合并
  → 成功后刷新时间轴
```

### 3.3 备份文件格式

```json
{
  "format": "local-diary-backup",
  "version": 1,
  "exportedAt": "2026-10-29T12:00:00Z",
  "entryCount": 3,
  "entries": [
    {
      "id": "0f0c2f6a-1f2e-4a1b-9d3c-2b7a5e9f1c22",
      "content": "正文第一段\n正文第二段",
      "createdAt": "2026-10-28T02:00:00.000Z",
      "updatedAt": "2026-10-28T02:05:00.000Z",
      "dayKey": "2026-10-28"
    }
  ]
}
```

时间统一使用 UTC ISO-8601，与 SQLite 中保存的 epoch 毫秒一一对应。`dayKey` 保留写入当天的本地日期，跨时区迁移后分组不乱。`version: 1` 不含附件与删除标记；将来扩展这两项时递增 version，并保持旧版本可导入。

### 3.4 Markdown 格式

```markdown
---
exportedAt: 2026-10-29T12:00:00Z
entryCount: 3
---

# 本地日记导出

## 2026-10-28

**10:05**　正文第一段

正文第二段

**09:12**　另一条
```

日期倒序分组、组内按创建时间倒序，与应用内时间轴顺序一致。正文原样输出，不做 Markdown 转义。

### 3.5 恢复合并规则

在单个事务内按条目 ID 合并：

| 本地状态 | 动作 |
|---|---|
| ID 不存在 | 插入 |
| 存在且备份 `updatedAt` 晚于本地 | 更新 `content` 与 `updatedAt`；`createdAt` 与 `dayKey` 以本地为准，创建时属性不可变 |
| 存在且备份 `updatedAt` 不晚于本地 | 跳过 |
| 完全相同 | 跳过，重复导入幂等 |

### 3.6 错误处理

| 场景 | 表现 |
|---|---|
| 用户在文件选择器取消 | 静默返回，不算失败，不写空文件 |
| 写文件失败（空间不足或权限） | 提示「导出失败：<原因>」，不吞掉错误 |
| 读文件失败 | 提示「无法读取所选文件」 |
| 非 JSON 或 `format` 不符 | 提示「这不是本应用的备份文件」 |
| `version` 高于当前支持 | 提示「备份来自更新的版本，请先升级应用」 |
| 条目字段缺失或类型错误 | 提示「备份文件已损坏」，整体拒绝，不做部分导入 |
| 导入事务中途失败 | 回滚，提示「恢复失败，未导入任何条目」 |
| 导入成功 | 提示「恢复完成：新增 K 条，更新 M 条，跳过 N 条」 |

本地没有任何条目时仍允许导出，生成 `entryCount` 为 0 的合法备份与只含标题的 Markdown；导入空备份不改变本地数据，提示「备份里没有记录」。

原则是不静默失败；恢复要么全部成功，要么一条不写入。

### 3.7 参考实现

按 [功能参考索引](../功能参考索引-feature-reference-index.md)，完整备份与恢复可参考 Daily You、DiaryVault、Moodiary，可读导出可参考 Moodiary、StoryPad。索引第 4 节记录目前没有已完成源码核查的实现，本次按本项目自有格式与合并规则实现，未复用上游源码，也未引入上游依赖与素材。

## 4. 开发任务

| 编号 | 任务 | 依赖 | 完成判据 |
|---|---|---|---|
| T1 | 接入 file_selector、share_plus、path_provider | — | 依赖解析成功，静态分析无问题 |
| T2 | `BackupDocument` 与 `BackupCodec` | T1 | 编解码往返单测通过；异常输入抛出可区分错误 |
| T3 | `MarkdownExporter` | — | 渲染单测通过：空集、单条、多组排序、正文特殊字符 |
| T4 | `FileGateway` 接口 | — | 接口不引用任何 SDK 类型 |
| T5 | `exportAll` 与 `importAll` | T4 | 集成测试覆盖全量导出、四种合并分支、幂等、事务回滚 |
| T6 | `saf_file_gateway.dart` 实现 | T1、T4 | 宿主可编译；真机验证保存、选择、分享 |
| T7 | `ExportController` 与 `ExportPage` | T3、T5、T6 | 组件测试覆盖空状态、导出成功、恢复预览与确认、取消、损坏文件；页面写明备份为明文、取决于用户自选的存放位置 |
| T8 | 「我的」页新增入口并更新本地数据说明文案 | T7 | 入口可达；不再出现「尚未提供导出与备份」的说法 |
| T9 | 全量检查与构建 | T1~T8 | 静态分析无问题、全部测试通过、调试 APK 构建通过 |
| T10 | 真机验收并更新报告与台账 | T9 | 按第 5 节执行并记录实际结果 |
| T11 | 同步产品设计与文档索引 | T7 | 产品设计记录本次决策；台账与报告索引更新 |

## 5. 测试计划

**单元测试（纯 Dart，不依赖 SDK）**

- `BackupCodec`：编码后解码的条目字段完全相等，覆盖中文、换行、emoji 与特殊字符。
- `BackupCodec` 异常路径：非 JSON、`format` 不符、字段缺失、字段类型错误、`version` 高于当前支持，各自抛出可区分的错误。
- `MarkdownExporter`：空集合、单条、跨日多组的分组与排序、正文含 Markdown 符号与换行。
- 合并判定：新增、更新、跳过、完全相同四种分支。

**集成测试（宿主 sqflite FFI）**

- `exportAll` 在条数超过 30 时仍返回全部条目。
- `importAll`：新增、更新、跳过、重复导入幂等、混合批次后本地状态正确。
- `importAll` 过程中抛错时事务回滚，本地数据保持不变。

**组件测试**

- 导出页空状态、导出成功提示、恢复预览与确认、取消导入不报错、损坏文件给出明确原因。

**真机手动测试（Android，SAF 真实弹窗）**

- 选择目录保存后，文件真实存在于所选位置，内容可被外部读取。
- 分享面板可列出并成功发送文件。
- 选择备份文件恢复后，回顾页出现对应条目。
- 飞行模式下仍可导出与恢复。
- 条目数量达到 1000 条时导出与恢复的耗时、内存与文件大小。

**构建检查**

- `flutter analyze`、`flutter test`、`flutter build apk --debug` 全部通过。

## 6. 环境与限制

- SAF 与系统分享的真机行为无法由宿主测试替代，未执行的场景如实记为未执行，不写成通过。
- 备份文件为明文，安全性依赖用户自选的存放位置与系统目录权限；应用不提供口令与加密，界面与本地数据说明需写明这一点。
- Markdown 导出不对正文做转义，正文中形如 `## ` 的行在部分阅读器里会被渲染为标题，属已知限制。
- 备份不包含附件与删除标记（当前版本没有这两类数据）；将来新增删除功能时需扩展备份格式并递增 `version`。
- 备份与恢复一次性读入内存，条目数量极大时占用上升，真机验收记录 1000 条量级的实际表现。
- 本次只覆盖条目正文与时间字段，不涉及云端、账号与同步；这些属于后续功能编号。
