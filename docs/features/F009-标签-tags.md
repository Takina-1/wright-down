# F009：标签

> 模板：复制到 `docs/features/F编号-中文主题-english-topic.md` 后填写。占位项不是已确认的需求。

- 创建日期：2026-11-01
- 最近更新：2026-11-01
- 需求来源与授权范围：用户 2026-11-01 确认处理 Phase 2 剩余功能。本功能给日记条目加标签，支持增删改与按标签筛选。
- 功能状态：见 [任务台账](../features/README.md)
- 关联测试报告：创建后填写相对链接

## 1. 用户场景与目标

日记越写越多后，用户想按主题（如「旅行」「读书」「工作」）回顾某类日记。当前回顾页只有时间轴，无法按标签筛选。本次给条目加标签：写日记时可加标签，回顾页可按标签筛选时间轴。纯本地数据，不依赖网络、不引入服务器。

## 2. 范围与边界

- 本次实现：
  - `Entry` 增加可选 `tags` 字段（`List<String>`，去重、trim）。
  - schema 升到 v4：`entries` 加可空列 `tags TEXT`（存 JSON 数组字符串），迁移幂等。
  - 记录页（写日记）：输入正文后可添加/移除标签，标签为自由文本（不建预设词库）。
  - 回顾页：顶部新增标签筛选栏，点某个标签过滤时间轴只看带该标签的条目；可清除筛选回到全部。
  - 备份格式随标签升到 `version: 3`：条目可带 `tags`；`version: 2` 旧备份仍可导入（无 tags）。
  - 边界（空标签、重复标签、含空白、超长标签、导入旧备份、筛选无结果）写进验收标准并配测试。

- 本次不实现：
  - 标签管理页（重命名/删除标签本身、查看标签使用次数）——标签是条目上的字符串，不单独建标签实体。
  - 多标签组合筛选（AND/OR）——本期单标签筛选。
  - 云端同步标签（Phase 4 账号+同步时统一处理）。

- 前置依赖：F001（本地记录）、F004（备份格式）、F005（删除记录与回收站）。

- 未决定的问题及影响：标签上限本期不设硬限制，但 UI 上单条记录建议不超过 5 个标签，超长标签截断。

## 3. 验收标准

| 编号 | 前置条件 | 用户操作或触发事件 | 可观察的预期结果 |
|---|---|---|---|
| AC-01 | 记录页写日记 | 输入正文并添加标签 | 保存后条目带标签，回顾页该条目显示标签 |
| AC-02 | 记录页已加标签的条目 | 移除一个标签后保存 | 标签更新，回顾页同步 |
| AC-03 | 回顾页有若干带标签条目 | 点某标签 | 时间轴只显示带该标签的条目 |
| AC-04 | 回顾页已按标签筛选 | 点「清除筛选」或点空 | 回到全部条目 |
| AC-05 | 回顾页筛选某标签 | 该标签无匹配条目 | 显示空状态提示，不崩溃 |
| AC-06 | 添加标签 | 输入重复标签或含空白标签 | 自动去重、trim，不存重复 |
| AC-07 | 导入 `version: 2` 旧备份 | 恢复备份 | 旧备份无 tags，导入后条目 tags 为空，不报错 |
| AC-08 | 导出带标签条目 | 备份 | 备份 JSON 含 tags，重新导入保留标签 |
| AC-09 | domain 层标签规范化 | 单元测试 | trim、去重、空标签过滤、大小写敏感全部有对应用例且通过 |
| AC-10 | 全部改动完成 | 质量检查 | 静态分析无问题、全部测试通过、调试 APK 构建通过 |

## 4. 参考实现

查 [功能参考索引](../功能参考索引-feature-reference-index.md)「标签管理与筛选」。参考索引明确记录：标签关系、重命名、删除和组合筛选需按本项目需求实现；同步时明确标签字段的合并规则。

本项目标签是**条目上的字符串列表**（JSON 存 TEXT 列），不建单独标签实体。本次**不下载、不运行、不复用上游源码**，也未引入上游依赖与素材。

| 仓库与固定提交 | 源码永久链接 | 已确认逻辑 | 借鉴方式与差异 | 许可核查（源码复用时） |
|---|---|---|---|---|
| 无（纯逻辑自实现） | — | — | — | — |

## 5. 实现方案

### 5.1 页面与状态变化

记录页（HomePage 的编辑器）：正文输入区下方加标签输入行，可加标签（回车或点「添加」），已加标签显示为可移除的 chip。

回顾页（TimelinePage）：顶部（页眉下方、随机一篇卡片上方）加标签筛选栏，显示「全部 / 标签A / 标签B …」，点某标签筛选，点「全部」或空回到全量。筛选时时间轴只显示带该标签的未删除条目。

### 5.2 数据流、模型与接口

`Entry` 增加字段：

```dart
class Entry {
  const Entry({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.dayKey,
    this.deletedAt,
    this.mood,
    this.tags,   // 新增：可选标签列表
  });
  final List<String> tags;
}
```

domain 层新增纯函数（零框架依赖）：

```dart
/// 规范化标签：trim、去空、去重（保序）。大小写敏感（"Travel" 与 "travel" 视为不同）。
List<String> normalizeTags(List<String> raw);
```

仓储层：`entries` 表加可空列 `tags TEXT`，存 `jsonEncode(normalizeTags(...))`。读回时 `jsonDecode`，失败退回空列表（脏数据不崩）。筛选按标签：`list({tag: String?})` 增加可选参数，WHERE 子句用 `tags LIKE ?`（匹配 JSON 数组里含该字符串）。

备份格式升 `version: 3`：`_encodeEntry` 写 `tags`（仅非空时），`_decodeEntry` 读 `tags`（缺失视为空）。`version: 2` 旧备份仍可解码（tags 缺失→空）。

合并规则：标签跟 `updatedAt` 走（与 mood 一致）。

### 5.3 受影响模块／文件

```text
client/lib/src/domain/entry.dart                 Entry 加 tags 字段
client/lib/src/domain/tags.dart                  新增：normalizeTags 纯函数
client/lib/src/data/local/sqlite_entry_repository.dart   schema v4 + tags 列 + list(tag) + save/import
client/lib/src/domain/local_entry_repository.dart  list 增加 tag 参数
client/lib/src/domain/export/backup_codec.dart   备份格式 v3 + tags 编码解码
client/lib/src/domain/export/merge_decision.dart  合并带 tags
client/lib/src/ui/home_page.dart                  记录页标签输入
client/lib/src/ui/timeline_page.dart              回顾页标签筛选栏
client/test/domain/tags_test.dart                 新增：normalizeTags 单测
client/test/ui/timeline_page_tag_filter_test.dart  新增：筛选组件测试
```

新增依赖：无。

### 5.4 离线、权限拒绝、失败与恢复

- 纯本地数据，无网络依赖，离线照常可用。
- 标签规范化失败（非法 JSON 等）不抛异常，退回空列表，不让回顾页崩溃（与 F004 脏数据退回口径一致）。

### 5.5 数据迁移与兼容性

- schema v3→v4：`entries` 加可空列 `tags TEXT`，迁移幂等（同 v2/v3 的 ALTER 口径）。
- 备份格式 v2→v3：新增 tags 键，旧 v2 备份可导入（tags 缺失→空）。
- 与 [产品设计](../产品设计-product-design.md) 的差异：产品设计 §二未做清单未列标签；本功能属 Phase 2「标签」范围，本次落实。

## 6. 开发任务

| 任务 | 依赖 | 产出 | 检查方式 | 完成情况 |
|---|---|---|---|---|
| T1 | — | `domain/tags.dart` normalizeTags + Entry 加 tags | 域层单测（trim/去重/空/大小写） | 已完成 |
| T2 | T1 | schema v4 + 仓储 tags 读写 + backup v3 + merge | 仓储/备份单测 | 已完成（v4 迁移幂等、list(tag) 筛选、备份往返、合并带标签） |
| T3 | T2 | 记录页标签输入 | 组件测试 | 已完成（加/移除/去重/空输入） |
| T4 | T2 | 回顾页标签筛选栏 | 组件测试 | 已完成（筛选/清除/空状态/无标签不显示筛选栏） |
| T5 | T1-T4 | 全量检查与构建 | 静态分析、全部测试、调试 APK | 已完成（analyze 无问题、343 项测试通过、APK 构建成功） |
| T6 | T5 | 真机验收并更新报告与台账 | 按第 7 节执行 | 已完成（Xiaomi 2211133C / Android 15；AC-01~AC-10 全部通过） |

## 7. 测试计划

| 验收编号 | 场景（正常／异常／边界） | 测试层级 | 环境或设备要求 |
|---|---|---|---|
| AC-09 | normalizeTags 边界 | 单测 | 宿主 flutter_test |
| AC-07、AC-08 | 旧备份导入 / 导出带标签 | 仓储+备份单测 | 宿主 flutter_test |
| AC-01、AC-02 | 记录页加/移除标签 | 组件测试 | 宿主 flutter_test |
| AC-03、AC-04、AC-05 | 回顾页筛选/清除/空状态 | 组件测试 | 宿主 flutter_test |
| AC-10 | 静态分析、全量测试、构建 | 构建检查 | 宿主 flutter |

真机验收在 T6 进行：在真机记录页加标签、回顾页筛选、清除筛选、导入旧备份。

## 8. 实施变化与交付

- 实际实现路径：按第 6 节任务表顺序完成 T1–T6，全部在 `feat/F009-tags` 分支（从 main 的 `23795e2` 开出）。T1 纯函数 + 域层单测；T2 schema v4 + 仓储 + 备份 v3 + 合并；T3 记录页标签输入；T4 回顾页标签筛选栏；T5 全量检查与构建；T6 真机验收（Xiaomi 2211133C / Android 15，adb 驱动）。
- 实际检查命令（第 1 轮，宿主侧）：
  ```bash
  cd client
  flutter analyze                      # No issues found!
  flutter test                         # 343 项全部通过
  flutter build apk --debug            # √ Built build/app/outputs/flutter-apk/app-debug.apk
  ```
- 实现细节与偏差：
  - 标签存 JSON 数组字符串（`jsonEncode`），读回 `jsonDecode`，解码失败退回空列表（脏数据不崩，与 F004 口径一致）。空列表存 `'[]'`，避免 NULL 与空串混淆。
  - 标签筛选用 `instr(tags, ?)` 精确匹配引号子串（如 `["旅行","读书"]` 里找 `"旅行"`），避免「旅行」误命中「旅行记」这类前缀串；大小写敏感，与 `normalizeTags` 一致。不用 LIKE 是因为 LIKE 通配符需 ESCAPE 子句，`instr` 更简单且无需转义。
  - 筛选栏只显示已加载条目里出现过的标签（保序去重）；分页加载的旧条目标签不进筛选栏，本期可接受。
  - 标签 always-write 口径（与 mood 一致）：save 总是写传入列表，空列表即清除；合并时标签跟 `updatedAt` 走。
  - 记录页标签输入：回车或点「添加」提交，空输入忽略，重复标签自动去重（`normalizeTags`）。标签 chip 可点移除。
  - 回顾页条目 tile 的 subtitle 里显示标签 chip。
  - 测试替身 `MemoryRepository.save` 更新分支补了 `tags`（与生产 always-write 口径一致），否则标签不落库、组件测试断言落空。
- 已知限制与未完成项：
  - 不做标签管理页（重命名/删除标签本身、查看标签使用次数）。
  - 不做多标签组合筛选（AND/OR），本期单标签筛选。
  - 筛选栏只显示已加载条目里的标签。
- 测试报告与交付物：[F009 标签测试报告](../test-reports/F009-标签测试报告-tags-test-report.md)

| 日期 | 需求或方案变化 | 原因与决策来源 | 影响的验收标准 |
|---|---|---|---|
| 2026-11-01 | 初版：条目加 tags 字段，JSON 存 TEXT 列，回顾页按标签筛选 | 用户确认处理 Phase 2 剩余功能 | AC-01 ~ AC-10 |
| 2026-11-01 | 标签筛选用 `instr(tags, ?)` 精确匹配引号子串，不用 LIKE | LIKE 通配符需 ESCAPE 子句，instr 更简单且无需转义；避免前缀误命中 | AC-03 |
| 2026-11-01 | 标签 always-write 口径（save 总是写、空列表即清除），与 mood 一致 | 与 mood 同口径，避免「非空才写」导致无法清除标签 | AC-02 |
