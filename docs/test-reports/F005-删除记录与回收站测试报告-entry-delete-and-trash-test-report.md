# F005：删除记录与回收站 测试报告

- 关联需求：[F005 删除记录与回收站](../features/F005-删除记录与回收站-entry-delete-and-trash.md)
- 测试依据：该需求的验收标准 AC-01 ~ AC-18（2026-10-30 初版）
- 被测分支：`feat/F005-entry-delete-and-trash`
- 报告保留每一轮结果；未实际执行的项目一律记「未执行」，不写成通过。

---

## 第 1 轮：2026-10-30（宿主侧自动化验证）

### 环境与范围

- 执行人：Claude Code（subagent-driven development），配合每任务独立评审与一次整分支终审
- 被测代码版本：`feat/F005-entry-delete-and-trash`，从 `72956aa`（main）起，共 30 个提交；末位提交 `45b954f`
- 存在未提交改动：无（每轮提交前 `git status` 干净；`client/pubspec.lock` 被 flutter 工具改写后已还原，未入库）
- 设备、系统、工具版本：宿主 Windows 10 + Git Bash；Flutter 3.47.8 / Dart 3.13.7；sqflite_common_ffi 2.4.5（宿主 SQLite）
- 数据与网络条件：全部使用合成测试数据，报告不含真实日记、录音、手机号或密钥；宿主测试不依赖网络
- 本轮范围：domain 层规则、SQLite 仓储、备份编解码、合并判定、Markdown 渲染、编辑器控制器、三个界面的组件行为
- 本轮**未**测范围：真机行为（SAF 弹窗、系统分享面板、真实手势长按、真实屏幕尺寸下的布局、跨版本安装升级），见第 2 轮

### 执行结果

| 用例 | 验收编号 | 命令或操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-01 | AC-01 | `flutter test test/ui/timeline_page_test.dart` | 长按条目弹出含「编辑」「删除」的底部菜单 | 用例「长按条目弹出编辑与删除菜单」通过 | 通过 |
| TC-02 | AC-02 | 同上 | 确认对话框含正文摘要与「删除后可在回收站找回。」；确认后条目离开列表 | 用例「确认删除后条目离开列表并提示可撤销」「取消不删除」「对话框里有正文摘要」通过 | 通过 |
| TC-03 | AC-03 | `flutter test test/ui/app_test.dart` | 编辑已有条目时出现「删除这条」，新记录时不出现 | 用例「编辑已有条目时出现删除按钮，新记录时不出现」通过 | 通过 |
| TC-04 | AC-04 | 同上 | 确认删除后编辑器复位为空白新条目 | 用例「确认删除后编辑器复位并可撤销」通过（断言 `TextField.controller.text` 为空） | 通过 |
| TC-05 | AC-05 | `flutter test test/ui/trash_page_test.dart` | 回收站列出已删除条目、显示正文与删除时间、提供「恢复」「彻底删除」 | 用例「回收站列出已删除条目并显示删除时间」通过（断言精确串「删除于 2026-10-28 03:05」） | 通过 |
| TC-06 | AC-06 | 同上 | 恢复后条目离开回收站，`deletedAt` 变 null | 用例「恢复后条目离开回收站」通过 | 通过 |
| TC-07 | AC-07 | 同上 | 彻底删除需二次确认；取消不删；确认后条目消失 | 用例「彻底删除需要确认」「取消后条目仍在」「确认后条目消失」通过 | 通过 |
| TC-08 | AC-08 | 同上 | 清空回收站清掉全部已删除条目 | 用例「清空回收站会清掉全部已删除条目」通过 | 通过 |
| TC-09 | AC-09 | 同上 | 回收站为空时显示空状态 | 用例「回收站为空时显示空状态」通过 | 通过 |
| TC-10 | AC-10 | `flutter test test/domain/backup_codec_test.dart` | 备份含已删除条目并带 `deletedAt`；`version` 为 2 | 用例「已删除条目编码后带 deletedAt，解码后能读回」「未删除的条目不写 deletedAt 键」通过 | 通过 |
| TC-11 | AC-11 | `flutter test test/domain/merge_decision_test.dart test/data/sqlite_entry_import_test.dart` | 本地已删除条目不被未删除的备份复活 | 用例「本地已删除而备份未删除时跳过，不复活」「本地已删除的条目不会被备份复活」通过；合并表六行全覆盖 | 通过 |
| TC-12 | AC-12 | `flutter test test/data/sqlite_entry_import_test.dart` | 备份带删除标记且更新 → 本地条目标记为已删除 | 用例「备份里带删除标记的条目会把本地条目标记为已删除」通过 | 通过 |
| TC-13 | AC-13 | `flutter test test/domain/backup_codec_test.dart` | `version: 1` 旧备份仍可导入，条目一律视为未删除 | 用例「version 1 的旧备份仍可导入，且条目一律视为未删除」通过 | 通过 |
| TC-14 | AC-14 | `flutter test test/domain/markdown_exporter_test.dart test/ui/export_controller_test.dart` | Markdown 不含已删除条目；头部条数与可见条数一致 | 用例「已删除的条目不进入可读导出」「导出的 Markdown 内容里不含已删除条目的正文」通过 | 通过 |
| TC-15 | AC-15 | `flutter test test/data/sqlite_entry_delete_test.dart test/ui/timeline_page_test.dart` | 时间轴与回收站列表都不出现已删除条目 | 用例「软删除后时间轴不再返回该条目」「回收站只列出已删除条目」通过 | 通过 |
| TC-16 | AC-16 | `flutter test test/ui/timeline_page_test.dart test/ui/app_test.dart test/ui/trash_page_test.dart` | 删除失败时条目仍在、界面给出失败原因 | 用例「删除失败时条目仍在并给出失败提示」「删除失败时保留内容并给出错误」「恢复失败/彻底删除失败/清空失败都有提示」通过 | 通过 |
| TC-17 | AC-17 | `flutter test test/data/sqlite_schema_migration_test.dart` | v1 库升级到 v2 后老数据完整、`deleted_at` 为 NULL | 用例「version 1 的库升级到 version 2 后老数据完好且删除标记为空」通过（用底层 `rawQuery` 断言行级 NULL，非经 `_toEntry`） | 通过 |
| TC-18 | AC-18 | `flutter analyze` | 无问题 | `No issues found! (ran in 2.4s)` | 通过 |
| TC-19 | AC-18 | `flutter test` | 全部测试通过 | `+242: All tests passed!` | 通过 |
| TC-20 | AC-18 | `grep -rn "UnimplementedError" lib` | 无占位实现（Task 1 留下的 5 个占位必须全部替换） | `没有占位实现` | 通过 |
| TC-21 | AC-18 | `flutter build apk --debug` | 调试 APK 构建成功 | `√ Built build\app\outputs\flutter-apk\app-debug.apk`（159,528,119 字节，2026-10-30 16:25） | 通过 |

结果只用：通过、失败、阻塞、未执行。命令执行失败和测试环境缺失需如实记录。

### 自动化测试的鉴别力

本轮每个任务都经过独立评审，多轮评审实际做了**变异测试**（临时改坏实现，确认对应用例变红，再还原）。记录到的关键变异与结果：

| 变异 | 是否被测试抓住 |
|---|---|
| 合并判定去掉「本地已删除不复活」 | 抓住（4 条变红） |
| 合并判定把毫秒比较改回 `isAfter` | 抓住（3 条变红） |
| 合并判定把 `createdAt` / `dayKey` 改取备份的值 | 补测后抓住 |
| SQLite 导入的 insert / update 分支去掉 `deleted_at` 写入 | 抓住 |
| 迁移不幂等（去掉 `PRAGMA table_info` 查列） | 抓住 |
| 迁移写成 `ADD COLUMN ... DEFAULT 0` | 补测后抓住 |
| 备份编解码去掉 `entryCount` 校验 | 抓住 |
| 备份编解码的时间串去掉时区要求 | 抓住 |
| 编码侧不校验重复 ID | 补测后抓住 |
| 时间轴撤销永远插到最前 | 补测后抓住 |
| 时间轴分页游标退一格造成重复/跳过 | 补测后抓住 |
| 编辑器删除不排干在飞行的保存 | 补测后抓住 |
| 编辑器 `canDelete` 去掉 `_persisted` | 补测后抓住 |
| 编辑器删除失败复用 `SaveStatus.error` | 补测后抓住 |
| 记录页删除期间不设 `_transitioning` | 补测后抓住 |
| 回收站删除时间改用 `createdAt` | 补测后抓住 |
| 回收站按钮退回 `ListTile.trailing` | 补测后抓住 |
| 「取消」改成也执行删除 | 补测后抓住 |
| 测试替身 `save()` 去掉空正文／空 ID 校验 | 补测后抓住 |
| 跨页删除不通知编辑器（界面仍显示「已保存」） | 补测后抓住 |

### 缺陷与复测

本轮发现的缺陷全部在特性分支上修复并复测，没有留到 `main`。其中影响数据安全的三条：

| 缺陷编号 | 复现条件与现象 | 是否阻塞验收 | 修复版本 | 复测结果与证据 |
|---|---|---|---|---|
| D-01 | 迁移不幂等：用户用旧版（`version: 1`）打开过已是 v2 结构的库，sqflite 在没有 `onDowngrade` 时只把 `user_version` 改回 1、表结构保留；再升级时 `ALTER TABLE ADD COLUMN` 撞名抛 `duplicate column name`，**整库从此打不开** | 是 | `a75e19e` 之前的 Task 2 修复波次 | `sqlite_schema_migration_test.dart` 新增「迁移幂等」用例，删除列检查后该用例报 `duplicate column name: deleted_at` 变红 |
| D-02 | `restore()` 把 `updated_at` 直接写成当前时刻：设备时钟回拨时版本戳倒退，导入旧备份会把**刚恢复**的条目打回删除状态，条目在时间轴上凭空消失且无任何提示 | 是 | Task 3 修复波次 | 新增「恢复时 `updated_at` 不倒退」用例；`softDelete` / `restore` 均改为 `max(当前值, now)` |
| D-03 | 界面文案「彻底删除后无法通过备份找回」与实现不符：彻底删除是物理 `DELETE`、不留墓碑，导入彻底删除之前导出的旧备份时该记录**仍会重新出现** | 是 | `5d18c02` | 宿主 FFI 实测确认后订正了本地数据说明与两个确认框的文案，并加 `isNot(contains('无法通过备份找回'))` 回归断言 |
| D-04 | 彻底删除的**确认框**没有写明「导入旧备份仍会重新出现」——那句只出现在「本地数据说明」页，没出现在用户真正按下「彻底删除」的那一屏 | 是 | `45b954f` | 两个确认框文案补上该限定；`trash_page_test.dart` 的逐字断言同步更新 |
| D-05 | 记录页可能还持有一条**已在别处被删除**的条目，界面却仍显示「已保存」：用户在记录页编辑 A → 切到回顾页长按 A 删除 → 切回记录页，编辑器仍持有 A，用户接着改字并自动保存，界面持续显示「已保存」，而 A 实际躺在回收站里、回顾页永远看不到 | 是 | `45b954f` | 新增 `EntryEditorController.markDeleted(id)`、`TimelinePage.onDelete` 回调与 `HomePage._entryDeleted`；切回记录页时编辑器复位并提示「这条记录已移入回收站」 |
| D-06 | 测试替身 `MemoryRepository.save()` 不校验空正文／空 ID，而生产 `save()` 会抛 `ArgumentError`——将来若有代码把空正文交给 `save()`，替身静默接受而真机抛异常，测试全绿、真机崩 | 是 | `45b954f` | 替身补上同样的校验（在任何副作用之前），并加两条用例锁定 |

另有测试替身与生产实现口径漂移（`save()` 复活已删除条目、`purge()` 越权删除活条目、`catch (_)` 吞异常等）若干条，均在本轮修复。

### 整分支终审

第 1 轮之后做了一次覆盖全分支（29 个提交）的独立终审，结论是「需要修复后合并」：

- **Critical 1 条**：真机验收未执行（见第 2 轮），按 `AGENTS.md`「测试失败、未执行或受阻时不得合并到 `main`」构成合并阻塞。
- **Important 3 条**：D-03、D-04、D-05、D-06，均已修复并复测。
- **Minor 5 条**：回收站「超出提示」在恰好 30 条时误报（文案改成非断言说法）、备份时区判定注释措辞含混、功能文档 §6 任务完成情况列未更新、测试报告提交数不符、规格 §5.3 的 `purge` 语义未同步——均已修正。

终审逐条核对后**未发现问题**的关键点（下一轮不必重复）：

- 全仓只有 `purge` 与 `purgeAll` 两处物理 `DELETE`，且都带 `deleted_at IS NOT NULL` 条件；所有「删除」入口都走 `softDelete`，没有任何直连 `purge` 的路径。
- 备份 v2 编解码往返一致，`deletedAt` 在 insert 与 update 两条路径上都写对；`save()` 更新分支不带 `deleted_at`，编辑已删条目不会复活。
- 合并表六行逐行与规格 §5.5 一致；预览与实际导入共用同一个 `decideMerge`。
- `importAll` 在单个事务内，失败整体回滚；`softDelete` / `restore` 的「查询 + 更新」在同一事务内。
- `softDelete` / `restore` 的 `updated_at` 取 `max(当前值, now)`，测试替身同口径。
- 迁移幂等，测试用 `PRAGMA table_info` / `PRAGMA index_list` 做行级断言（不经 `_toEntry`，避开「0 等于已删除」的恒真陷阱）。
- 所有 `await` 之后都有 `mounted` 守卫；SnackBar 撤销回调捕获局部 `repository`，不依赖可能已卸载的 `widget`。
- Domain 层零框架依赖；未新增依赖；30 个提交的提交信息全部符合中英结合格式。

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 21，失败 0，阻塞 0，未执行 0（宿主侧）
- 是否满足全部必需验收项：**宿主侧全部满足**；真机相关项见第 2 轮
- 剩余问题、限制及接受依据：
  - 回收站不自动清理，只列出最近 30 条（界面有提示），「清空回收站」会清掉全部——本次范围外的已知限制，见功能文档 §8.3
  - 彻底删除的条目仍可能被旧备份带回——已在界面文案中如实写明
- 下一步：真机验收（第 2 轮）

---

## 第 2 轮：2026-10-30（真机验收）

### 环境与范围

- 执行人：Claude Code（adb 驱动）
- 设备、系统、工具版本：**未连接设备**。`adb devices -l` 返回空列表；重启 adb server（`adb kill-server` / `adb start-server`）后仍为空
- 被测构建产物：`client/build/app/outputs/flutter-apk/app-debug.apk`（本轮重新构建）
- 本轮范围：第 7 节真机清单的全部条目
- 未测原因：测试时用户的手机未通过 USB 连接到本机，无法安装与操作

### 执行结果

| 用例 | 验收编号 | 操作步骤 | 预期结果 | 实际结果 | 结果 |
|---|---|---|---|---|---|
| TC-22 | AC-01 ~ AC-04 | 真机安装后长按条目、确认删除、在记录页删除 | 见第 1 轮对应项 | 未连接设备，未执行 | 未执行 |
| TC-23 | AC-05 ~ AC-09 | 打开「我的 → 回收站」，恢复、彻底删除、清空 | 见第 1 轮对应项 | 未连接设备，未执行 | 未执行 |
| TC-24 | AC-10、AC-12、AC-13 | 真机导出备份、查看 JSON、导入带删除标记的备份与 v1 旧备份 | 见第 1 轮对应项 | 未连接设备，未执行 | 未执行 |
| TC-25 | AC-17 | 先装旧版本写几条，再装新版本 | 老数据完好且删除功能可用 | 未连接设备，未执行 | 未执行 |
| TC-26 | 离线 | 飞行模式下删除与导出 | 照常可用 | 未连接设备，未执行 | 未执行 |
| TC-27 | 小屏布局 | 真实设备上确认「删除这条」与「下一条」并排、回收站两个按钮不被裁掉 | 不溢出、不裁切 | 宿主组件测试在 320 / 360 dp 与 textScale 1.0~2.0 下用 `getRect` 断言通过；**真机肉眼确认未执行** | 未执行 |

### 缺陷与复测

| 缺陷编号 | 复现条件与现象 | 是否阻塞验收 | 修复版本 | 复测结果与证据 |
|---|---|---|---|---|
| — | 真机未执行，暂无真机缺陷 | — | — | — |

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 0，失败 0，阻塞 0，**未执行 6**
- 是否满足全部必需验收项：**否**——真机验收未执行
- 剩余问题、限制及接受依据：宿主侧已覆盖全部验收标准的逻辑行为；真机项需要设备连接后补做，重点是真实手势长按、真实屏幕宽度下的按钮布局、跨版本安装升级，以及「导入旧备份后已删除条目的表现」
- 下一步：连接设备后补做本轮，同一份报告追加「第 3 轮」，注明新的被测版本；**在此之前 F005 不标记为「已完成」**

---

## 构建记录

```bash
cd client
export ANDROID_HOME="D:\dev\myapp\.tooling\android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="D:\dev\myapp\.tooling\java\jdk-21.0.13.0.2+1"
flutter build apk --debug
```

构建过程有一条无害告警：`Warning: SDK processing. This version only understands SDK XML versions up to 3 but an SDK XML file of version 4 was encountered.`（命令行工具与 SDK XML 版本不一致，不影响产物。）

第一次构建**失败**并重试了一次，原因与代码无关：

```
Could not get resource 'https://storage.googleapis.com/download.flutter.io/io/flutter/arm64_v8a_debug/.../arm64_v8a_debug-....jar'
   > Read timed out
```

本机 Gradle 缓存里没有 Flutter 引擎的架构产物（`io.flutter:arm64_v8a_debug` 等），首次构建要联网下载，实测带宽约 76 KB/s，一次下载超时长达 26 分钟。Flutter 自身会重试；第二次构建在引擎产物落盘后成功。**这不是代码缺陷，但换一台新机器或清掉 Gradle 缓存后首次构建可能同样慢或超时。**

另外本机 `flutter` 不在 PATH、且需要同时设置 `ANDROID_HOME` 与 `JAVA_HOME`（`JAVA_HOME` 必须指向 `jdk-21.0.13.0.2+1` 这一层目录），否则 Gradle 会报 `JAVA_HOME is set to an invalid directory`。
