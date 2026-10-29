# F004：导出与备份恢复测试报告

- 关联需求：[F004 导出与备份恢复](../features/F004-导出与备份恢复-export-and-backup.md)
- 关联计划：[实现计划](../features/F004-导出与备份恢复计划-export-and-backup-plan.md)
- 测试依据：[F004 验收标准 AC-01~AC-10](../features/F004-导出与备份恢复-export-and-backup.md#2-验收标准)（2026-10-29 版本）
- 本报告只记录实际执行结果；未在真机执行的项一律记为「未执行」，不写成通过。

## 第 1 轮：全量验证与文档同步

### 环境与范围

- 执行日期：2026-10-29
- 执行人：Claude（Task 9 全量验证与文档同步）
- 被测分支：`feat/F004-export-and-backup`
- 被测代码版本：工作区快照，相对 `9af0c6d fix(F004): state plaintext exports and cover the settings entry` 增加了调试探针清理与格式化改动；无未提交的临时验证脚本。
- 设备、系统、工具版本：
  - Windows 10 Pro 10.0.18363（Git Bash / PowerShell）
  - Flutter 3.47.8（stable，revision 737ba8f885），Dart 3.13.7（DevTools 2.60.0）
  - Android Gradle Plugin 9.1.0，Kotlin 2.4.0，Gradle 9.3.1（`mirrors.cloud.tencent.com` 分发）
  - compileSdk 36 / targetSdk 36，minSdk 24
- 依赖版本（`client/pubspec.lock` 实际锁定值）：
  - 新增：`file_picker 13.3.0`（保存文件）、`file_selector 1.1.0`（读取备份文件）、`share_plus 13.3.1`（系统分享）、`path_provider 2.1.6`（分享用临时目录）
  - 既有：`sqflite 2.4.5`、`sqflite_common 2.5.14`、`sqflite_common_ffi 2.4.5`（宿主 FFI 测试）、`path 1.9.1`、`uuid 4.6.0`
- 数据与网络条件：全部使用合成测试数据；报告不含真实日记、录音、手机号或密钥。宿主测试通过 `sqflite_common_ffi` 使用真实 SQLite 文件。
- 本轮范围：格式化、静态分析、全量自动化测试、调试 APK 构建、验收标准逐条核对、调试探针清理。
- 未测范围：真机 SAF 保存弹窗、系统文件选择器弹窗、系统分享面板、飞行模式、1000 条量级（本轮没有连接 Android 设备，见下文「真机验收」）。

### 执行结果

所有命令都在 `D:\dev\myapp\client` 目录通过项目内脚本执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\dart.ps1 format lib test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 analyze
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test --reporter expanded
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 build apk --debug
```

| 检查 | 命令 | 实际输出 | 结果 |
|---|---|---|---|
| 格式化 | `dart.ps1 format lib test` | 首次 `Formatted 32 files (12 changed) in 0.07 seconds.`；清理与改名后复跑 `Formatted 32 files (0 changed) in 0.06 seconds.` | 通过 |
| 静态分析 | `flutter.ps1 analyze` | `No issues found! (ran in 3.1s)`（清理前一次为 `No issues found! (ran in 2.6s)`） | 通过 |
| 全量自动化测试 | `flutter.ps1 test --reporter expanded` | `00:02 +80: All tests passed!`，退出码 0 | 通过 |
| 调试 APK 构建 | `flutter.ps1 build apk --debug` | `Running Gradle task 'assembleDebug'... 14.0s` → `√ Built build\app\outputs\flutter-apk\app-debug.apk`，命令实际耗时 15.8 秒 | 通过 |
| 构建产物核验 | `aapt2 dump badging/permissions` | 包名 `dev.localdiary.local_diary`，versionName `0.1.0`，versionCode 1，targetSdk 36，显示名「本地日记」，ABI：arm64-v8a / armeabi-v7a / x86_64 | 通过 |
| 构建产物权限核验 | `aapt2 dump permissions` | 仅 `android.permission.INTERNET`（调试用）与应用自有 `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`；无存储、麦克风、相机、相册权限 | 通过 |

#### 自动化测试分布（80 项，全部通过）

| 测试文件 | 项数 | 覆盖内容 |
|---|---|---|
| `test/data/sqlite_entry_import_test.dart` | 8 | `exportAll` 全量返回与排序；插入 / 更新 / 跳过 / 幂等 / 事务回滚 |
| `test/data/sqlite_entry_repository_test.dart` | 4 | F001 既有：中文与 emoji 重开恢复、upsert、分页、空内容保护 |
| `test/data/sqlite_startup_failure_test.dart` | 2 | 由 `zz_probe_temp_test.dart` 改名而来：数据库打不开时错误只在实际使用时暴露 |
| `test/domain/backup_codec_test.dart` | 10 | 备份编解码往返与全部拒绝路径 |
| `test/domain/markdown_exporter_test.dart` | 8 | Markdown 分组、排序、时区、空集、正文原样 |
| `test/domain/restore_preview_test.dart` | 6 | 恢复预览的新增 / 更新 / 跳过计数 |
| `test/support/entry_merger_test.dart` | 3 | 合并判定口径与失败回滚 |
| `test/ui/app_test.dart` | 7 | F001 既有：自动保存、失败保护、回顾空状态等 |
| `test/ui/entry_editor_controller_test.dart` | 6 | F001 既有：停输延迟、编辑保留身份等 |
| `test/ui/export_controller_test.dart` | 17 | 导出 / 分享 / 选择 / 确认 / 取消 / 失败消息编排 |
| `test/ui/export_page_test.dart` | 6 | 导出页明文说明、导出计数、分享、恢复确认与取消、损坏文件提示 |
| `test/ui/local_data_page_test.dart` | 3 | 「我的」页入口、文件出口传递、本地数据说明文案 |
| **合计** | **80** | 0 失败、0 跳过 |

### 验收标准逐条对照

标注「通过（宿主部分）」的条目只覆盖宿主可验证的部分；依赖真机弹窗的子项在下方「真机验收」中单列为「未执行」，该子项不计入通过。

| 验收编号 | 场景 | 依据（实际执行的用例与观察） | 结果 |
|---|---|---|---|
| AC-01 | 触发备份导出，选定位置后写入 JSON 并提示条数 | `export_controller_test.dart`「exporting a backup writes every entry and reports the count」（`FileGateway` 收到 `.json` 文件名与全部条目字节）、「exporting an empty journal still succeeds and reports zero」；`export_page_test.dart`「exporting a backup shows the exported count」（页面显示「已导出 1 条」）；`local_data_page_test.dart`「the mine page hands its file gateway to the export page」（注入的出口确实被调用） | 通过（宿主部分）；SAF 保存弹窗未执行 |
| AC-02 | 备份含全部字段、条数与本地一致、不受 30 条分页限制 | `sqlite_entry_import_test.dart`「exportAll returns every entry, not only the first page」（写入 40 条，`exportAll` 返回 40 条且按创建时间倒序）；`backup_codec_test.dart`「a decoded backup keeps every field of the original entry」（id、正文、createdAt、updatedAt、dayKey 往返完全一致，含中文与 emoji） | 通过 |
| AC-03 | Markdown 分组倒序、正文原样保留 | `markdown_exporter_test.dart`「days and entries are ordered newest first」「entries are grouped by dayKey rather than by the createdAt date」「utc entries are shown in the local timezone」「line breaks and markdown symbols stay untouched」（正文里的 `# 标题`、`- 列表` 与换行未被转义或改写）、「entries of the same day are separated by a blank line」 | 通过 |
| AC-04 | 导出后从应用内分享 | `export_controller_test.dart`「a markdown export is offered for sharing after it is saved」「a saved export can be shared from the page」「a failing share reports the share failure message」；`export_page_test.dart`「a saved export can be shared from the page」——只验证到「导出后可以发起分享、失败有提示」为止 | 未执行（系统分享面板需真机） |
| AC-05 | 在文件选择器或分享面板取消 | `export_controller_test.dart`「cancelling the save dialog is not reported as a failure」「cancelling the file picker is not reported as a failure」「cancelling the picker drops the previously picked backup」（取消后不留上一份备份）；`export_page_test.dart`「cancelling the confirmation leaves the journal untouched」（取消确认不写入、不显示失败）。临时文件清理见第 2 轮：`saf_file_gateway_test.dart`「the shared copy is deleted after the share call finishes」等用例断言分享流程结束后临时明文副本已被删除 | 通过（宿主部分：分享流程结束后临时文件已被清理）；SAF 弹窗与分享面板本身未执行 |
| AC-06 | 导入含新旧条目的备份 | `sqlite_entry_import_test.dart`「a new id from a backup is inserted」「a newer backup entry updates content but keeps creation time」（正文换成备份的、创建时间保持本地）「an older backup entry never overwrites a newer local entry」；`export_controller_test.dart`「confirming a restore merges the backup into the journal」（新增 1、更新 2、跳过 3，提示文案一致）；`restore_preview_test.dart`「a mixed batch counts insertions, updates and skips separately」 | 通过 |
| AC-07 | 同一备份连续导入两次 | `sqlite_entry_import_test.dart`「importing the same backup twice changes nothing the second time」（第二次 inserted 0、updated 0、skipped 2，条数不变）；`restore_preview_test.dart`「an identical entry is counted as skipped」 | 通过 |
| AC-08 | 导入损坏或不支持的备份 | `backup_codec_test.dart` 第 1 轮实际有 8 个拒绝用例（原文误写为 7 个；「缺 `dayKey`」与「缺 `exportedAt`」是两个独立用例），各自抛出可区分原因：非 JSON →「这不是本应用的备份文件」；`format` 不符 → 同上；`version` 更高 →「备份来自更新的版本，请先升级应用」；缺 `dayKey` →「备份文件已损坏，无法恢复」；缺 `exportedAt` → 同上；`content` 类型错误 → 同上；重复 id → 同上；正文为空或全空白 → 同上。第 2 轮新增第 9 个：`dayKey` 格式非 `YYYY-MM-DD` → 同上（见第 2 轮 AC-08 行）。`export_page_test.dart`「a broken backup shows the reason and changes nothing」（页面显示原因且不写入）；`sqlite_entry_import_test.dart`「a broken entry rolls the whole import back」（事务整体回滚，本地数据不变） | 通过 |
| AC-09 | 恢复完成后查看回顾页 | 仓储层：`sqlite_entry_import_test.dart`「a new id from a backup is inserted」（插入路径写入的条目 ID、创建时间与 dayKey 全部来自备份，不是本地默认值）；「a newer backup entry updates content but keeps creation time」（更新路径按需求保持本地创建时间与 dayKey）；「importing the same backup twice changes nothing the second time」（可反复恢复）。控制器层：`export_controller_test.dart`「confirming a restore merges the backup into the journal」（恢复后条目写入本机仓储、提示新增/更新/跳过）。界面层在第 2 轮补上常驻组件测试 `export_page_test.dart`「a restored entry shows up in the review timeline」（从「我的 → 导出与备份」恢复并确认后回到「回顾」页能看到新恢复的条目） | 通过（宿主部分）；更新路径的创建时间保持本地值，插入路径与备份一致 |
| AC-10 | 新增依赖后静态分析、全部自动化测试、调试 APK 构建 | `flutter analyze` → `No issues found!`；`flutter test --reporter expanded` → 80 项全部通过；`flutter build apk --debug` → 成功，产物 159,487,352 字节 | 通过；SAF 真实弹窗与分享的真机结果另记实测（未执行） |

### 真机验收：未执行项

本轮**没有连接 Android 设备**，以下项目一律记为「未执行」，不计入通过：

| 项目 | 关联验收 | 未执行原因 | 计划验证方式 |
|---|---|---|---|
| SAF 保存弹窗弹出、选定位置后真实写入文件 | AC-01、AC-10 | 无连接的 Android 设备，无法拉起系统文件选择器 | 安装本轮调试 APK，点「导出备份（可恢复）」，在系统弹窗选定目录，确认该位置真实生成 JSON 文件且外部可读 |
| 系统文件选择器弹窗（读取备份文件） | AC-08 | 同上 | 点「从备份恢复」，在系统弹窗选中一个 `.json` 文件，确认能被读入 |
| 系统分享面板弹出与发送 | AC-04 | 同上 | 导出后点「分享」，确认系统面板列出应用并能发出备份或 Markdown 文件 |
| 分享面板取消 | AC-05 | 同上 | 打开分享面板后返回，确认不显示失败信息 |
| 飞行模式下仍可导出与恢复 | 需求第 2 节「恢复为纯本地操作」 | 同上 | 开飞行模式后完整走一遍导出与恢复 |
| 1000 条量级的耗时、内存与文件大小 | 需求第 6 节限制 | 同上（宿主测试只覆盖到 40 条全量导出） | 造 1000 条数据后导出 JSON 与 Markdown，记录耗时与文件大小 |

补充说明：宿主测试用 `FakeFileGateway` / `RecordingFileGateway` 替身覆盖了「保存 / 选择 / 分享」三个接口的调用契约与取消、失败分支，替身不产生系统弹窗，因此**不能**替代上表中的真机结论。

### 缺陷与复测

本轮未发现自动化测试失败或静态分析问题，无缺陷条目。

需要留意的实现与需求描述差异（不阻塞验收）：需求文档第 3.1 节原描述保存流程为「先写临时文件，再复制到用户选定位置，结束后清理临时文件」，实际实现改为由 `file_picker.saveFile(bytes:)` 直接把字节写入用户选定位置，只有分享路径需要在应用缓存目录写一份临时明文副本。本轮曾把需求文档第 3.1 节与第 6 节改写为「分享用的临时明文副本本版本不自动清理」——这是把规格改松来迁就实现，与 AC-05「不残留临时文件」和计划第「全局约束」一节矛盾。该差异已在第 2 轮按原规格修回：实现改为分享流程结束后清理临时副本，需求文档第 3.1 节与第 6 节的表述随之改回与实现一致。

### 探针测试文件清理

F001 收尾时为排查问题留下了 5 个探针文件，本轮按调试残留清理：

| 原文件 | 用例数 | 处置 |
|---|---|---|
| `client/test/ui/zz_probe_test.dart` | 3 | 删除：只有 `debugPrint` 探测输出，没有任何断言 |
| `client/test/ui/zz_probe2_test.dart` | 2 | 删除：同上 |
| `client/test/ui/zz_probe3_test.dart` | 1 | 删除：同上 |
| `client/test/ui/zz_probe4_test.dart` | 2 | 删除：同上 |
| `client/test/zz_probe_temp_test.dart` | 2 | 保留并改名：`client/test/data/sqlite_startup_failure_test.dart`，只把文件头的 “TEMPORARY PROBE” 注释改为正常说明，**用例与断言一字未改** |

清理理由：

- 4 个只打印的探针让全量输出带 `PROBE ...` 噪音，虚增通过条数，且在本功能开发期间两次因为仓储接口扩展（`exportAll` / `importAll`）而编译失败；
- `zz_probe_temp_test.dart` 的 2 个用例有真实断言，守护的是「数据库路径不可用时，启动阶段不弹错误页、错误只在实际使用时暴露」这一行为，属于有价值的回归测试，只是文件名与注释写着「临时探针」，因此改名保留而不是删除。

影响可量化：清理前全量测试为 88 项（`+88: All tests passed!`），清理后为 80 项，减少的 8 项正好是被删除的 4 个探针文件的用例数（3+2+1+2），保留的 2 项启动失败用例仍计入 80 项之内。

### 已知限制

1. **备份与 Markdown 都是明文**：不加密、不设口令，任何文本编辑器都能打开；安全性完全依赖用户自选的存放位置。导出页与「我的 → 本地数据说明」都写明了这一点（`export_page_test.dart`「the page explains that both exports are plaintext」、`local_data_page_test.dart`「the local data note says backups are plaintext to keep safe」）。
2. **Markdown 不转义**：正文里的 `## `、`- ` 等符号在部分阅读器中会被当作标题或列表渲染；正文的换行与符号原样输出（`markdown_exporter_test.dart`「line breaks and markdown symbols stay untouched」）。
3. **备份不含附件与删除标记**：当前版本条目只有正文与时间，备份格式 `version: 1` 不含附件与删除标记；将来新增这两类数据时需扩展格式并递增 `version`，同时保持旧版本可导入。
4. **全量读入内存**：`exportAll()` 一次性读出全部条目，编码后的字符串与字节数组都在内存中；条目数量极大时占用上升，本轮未做 1000 条量级实测。
5. **分享的临时明文副本已改为用完即删**：系统分享需要真实文件路径，导出内容会以明文写入应用缓存目录下的临时文件并交给分享面板；写新副本前先删除同前缀的旧副本，分享调用返回后删除本次副本。该行为由 `saf_file_gateway_test.dart` 在宿主侧验证（见第 2 轮）。`share_plus` 自己在 Android 上还会把文件复制到它的 `cache/share_plus/` 目录，该副本由插件在下一次分享时清理，不在本项目控制范围内。
6. **`file_selector_android` 读取备份时会留下插件自己的缓存副本**：`openFile` 会把用户选中的文件复制进应用缓存目录（`cacheDir/{uuid}/文件名`），这是插件自身的行为，本项目无法控制或删除，由系统按缓存回收策略清理。宿主可验证的只有「读取失败时不导入任何条目」。
7. **Markdown 分组与时间轴排序口径不同**：Markdown 按 `dayKey` 分组，应用内时间轴按 `createdAt` 排序。设备改过时区或从其它时区恢复的备份会让两者顺序不同，本次不合并两种视角。
8. 备份与恢复为纯本地操作，不依赖网络；本轮的飞行模式验证未执行，断网可用性仍待真机确认。

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 80 项自动化测试 + 1 项静态分析 + 1 项调试 APK 构建；失败 0，阻塞 0；真机项 6 类未执行（SAF 保存弹窗、文件选择器弹窗、系统分享面板、分享取消、飞行模式、1000 条量级）。
- 是否满足全部必需验收项：**否**。AC-01~AC-10 的宿主可验证部分全部通过，但依赖真机的子项（SAF 弹窗、分享面板、飞行模式、1000 条量级）尚未执行，因此功能不能标记为「已完成」。
- 剩余问题、限制及接受依据：见上方「已知限制」7 条，均为明文存储、无附件、无转义、内存占用一类的设计取舍，与需求文档第 6 节一致；真机项等待连接 Android 设备后补做。
- 下一步：连接 Android 设备后按「真机验收」表逐项执行并把实际结果补进本报告；同时把功能台账 F004 从「待测试」推进到「待验收」。F004 特性分支按项目约定保留，不推送远程。

### 后续轮次

（设备验收完成后在此追加第 3 轮，注明新的被测版本与逐项实测结果。）

## 第 2 轮：最终评审问题的修复与复核

### 环境与范围

- 执行日期：2026-10-29
- 执行人：Claude（最终评审问题修复轮）
- 被测分支：`feat/F004-export-and-backup`
- 被测代码版本：本轮 4 个提交的快照（`ef6a7ec`、`760618f`、`37ccd1f`、`502d76d`），相对第 1 轮报告记录的版本增加了评审修复
- 工具版本：同第 1 轮（Flutter 3.47.8 / Dart 3.13.7，Windows 10 Pro 10.0.18363）
- 本轮范围：修复最终评审提出的 3 条 Important 与 3 条相关 Minor；补测试；核对文档与实现是否一致
- 未测范围：真机 SAF 保存弹窗、系统文件选择器弹窗、系统分享面板、飞行模式、1000 条量级（本轮仍未连接 Android 设备）

### 修复的问题

| 编号 | 问题 | 修法 | 涉及文件 |
|---|---|---|---|
| Important 1 | `dayKey` 只校验非空，手工改过的备份能让「回顾」页 `substring` 越界崩溃 | 在 `domain/entry.dart` 引入唯一校验入口 `isValidDayKey`（正则 `^\d{4}-\d{2}-\d{2}$`）；备份解码遇到非法 `dayKey` 抛 `BackupFormatException('备份文件已损坏，无法恢复')` 整体拒绝；仓储 `importAll` 导入前校验，非法抛 `ArgumentError` 触发事务整体回滚；测试替身 `entry_merger` 复用同一校验；时间轴取月份改为安全取法（`dayKey` 非法时退回创建时间的本地年月） | `client/lib/src/domain/entry.dart`、`client/lib/src/domain/export/backup_codec.dart`、`client/lib/src/data/local/sqlite_entry_repository.dart`、`client/test/support/entry_merger.dart`、`client/lib/src/ui/timeline_page.dart` |
| Important 2 | 分享用的明文副本永不清理，与 AC-05 和计划全局约束矛盾 | `shareFile` 写新副本前删除临时目录里同前缀（`本地日记-`）的旧副本；分享调用结束后（无论成功与否）删除本次写的副本；临时目录与分享调用改为可注入以便宿主测试 | `client/lib/src/platform/saf_file_gateway.dart`、`client/lib/src/domain/export/file_gateway.dart` |
| Important 3 | AC-09 结论被高估，插入路径的字段语义没有断言 | 插入路径补断言 `createdAt` 与 `dayKey` 来自备份；新增常驻组件测试（恢复后「回顾」页能读到新恢复的条目）；测试报告的 AC-09 结论与依据一并改正 | `client/test/data/sqlite_entry_import_test.dart`、`client/test/ui/export_page_test.dart`、`client/lib/app.dart`、`client/lib/src/ui/home_page.dart`、`client/lib/src/ui/local_data_page.dart` |
| Minor 1 | 导出失败或取消保存后 `canShare` 仍为 true，可能分享到上一次的旧文件 | 导出开始前清空 `_lastExportBytes` 与 `_lastExportName` | `client/lib/src/ui/export_controller.dart` |
| Minor 2 | Markdown 顺序断言用 `indexOf`，缺内容时恒真 | 补 `expect(markdown, contains(...))` 存在性断言 | `client/test/domain/markdown_exporter_test.dart` |
| Minor 3 | 报告写「7 个拒绝用例」，实际列了 8 类 | 改为真实数字（8 个） | 本报告第 1 轮 AC-08 行 |

绑定文案一字未改；未新增与上述无关的功能。

### 执行结果

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\dart.ps1 format lib test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 analyze
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1 build apk --debug
```

| 检查 | 命令 | 实际输出 | 结果 |
|---|---|---|---|
| 格式化 | `dart.ps1 format lib test` | `Formatted 34 files (7 changed) in 0.07 seconds.`；复跑 `Formatted 34 files (0 changed)` | 通过 |
| 静态分析 | `flutter.ps1 analyze` | `No issues found! (ran in 2.4s)` | 通过 |
| 全量自动化测试 | `flutter.ps1 test` | `00:04 +91: All tests passed!`，退出码 0 | 通过 |
| 调试 APK 构建 | `flutter.ps1 build apk --debug` | `Running Gradle task 'assembleDebug'... 7.6s` → `√ Built build\app\outputs\flutter-apk\app-debug.apk` | 通过 |

#### 自动化测试分布（91 项，全部通过；较第 1 轮 80 项增加 11 项）

| 测试文件 | 第 1 轮 | 本轮 | 变化 |
|---|---|---|---|
| `test/data/sqlite_entry_import_test.dart` | 8 | 9 | 插入路径字段语义断言；非法 `dayKey` 触发事务回滚 |
| `test/domain/backup_codec_test.dart` | 10 | 11 | 非法 `dayKey` 的备份被拒绝 |
| `test/domain/markdown_exporter_test.dart` | 8 | 8 | 补存在性断言（不新增用例） |
| `test/support/entry_merger_test.dart` | 3 | 4 | 替身对非法 `dayKey` 整体拒绝 |
| `test/ui/export_controller_test.dart` | 17 | 19 | 导出失败 / 取消后 `canShare` 为 false |
| `test/ui/export_page_test.dart` | 6 | 7 | 恢复后「回顾」页读到新条目 |
| `test/ui/timeline_page_test.dart`（新增文件） | — | 1 | 短 `dayKey` 的历史条目不打崩时间轴 |
| `test/platform/saf_file_gateway_test.dart`（新增文件） | — | 4 | 分享结束后临时副本被删除；旧副本被清理 |
| 其余 6 个文件 | 28 | 28 | 无变化 |
| **合计** | **80** | **91** | **+11** |

其余 6 个文件为 `sqlite_entry_repository_test.dart`(4)、`sqlite_startup_failure_test.dart`(2)、`restore_preview_test.dart`(6)、`app_test.dart`(7)、`entry_editor_controller_test.dart`(6)、`local_data_page_test.dart`(3)。

### 验收标准逐条对照（本轮变化项）

| 验收编号 | 场景 | 依据（实际执行的用例与观察） | 结果 |
|---|---|---|---|
| AC-05 | 在文件选择器或分享面板取消，不残留临时文件 | `saf_file_gateway_test.dart`「the shared copy is deleted after the share call finishes」（分享过程中文件存在、返回后已删除）、「the shared copy is deleted even when the share call fails」（分享失败也删除）、「old copies of the same export are removed before a new one is written」（同前缀旧副本被清理，非本应用文件不动）、「a markdown copy is cleaned up the same way」。`export_controller_test.dart`「cancelling the save dialog is not reported as a failure」「a cancelled export leaves nothing to share」 | 通过（宿主可验证的部分：分享流程结束后临时文件已被清理）；SAF 弹窗与分享面板本身仍未执行 |
| AC-08 | 导入损坏或不支持的备份 | `backup_codec_test.dart`「an entry with a malformed day key is reported as damaged」（`2026`、`x`、`2026-10`、`2026-10-28T00:00:00Z` 四种非法 `dayKey`，其余字段合法，失败原因唯一指向 `dayKey`，reason 为「备份文件已损坏，无法恢复」）；`sqlite_entry_import_test.dart`「an entry with a malformed day key rolls the whole import back」（抛 `ArgumentError` 且本地数据不变）；`entry_merger_test.dart`「an entry with a malformed day key aborts the whole merge」 | 通过 |
| AC-09 | 恢复完成后查看回顾页 | `sqlite_entry_import_test.dart`「a new id from a backup is inserted」（插入路径的 `id`、`createdAt`、`updatedAt`、`dayKey` 全部等于备份值，不是本地默认值）；`export_page_test.dart`「a restored entry shows up in the review timeline」（「我的 → 导出与备份 → 从备份恢复 → 恢复 → 返回 → 回顾」后能看到新恢复条目的正文）；更新路径仍按需求保持本地创建时间与 dayKey（「a newer backup entry updates content but keeps creation time」） | 通过（宿主部分）；更新路径与插入路径的差异已在需求第 3.5 节写明 |

AC-01、AC-02、AC-03、AC-04、AC-06、AC-07、AC-10 的依据与结论本轮无变化。

### 变异检查

每次只改一处，跑对应测试文件确认失败，然后用 `git diff` 确认已还原。

| 变异 | 期望 | 实际输出 | 还原确认 |
|---|---|---|---|
| 把 `backup_codec.dart` 的 `isValidDayKey` 校验去掉 | 新增的编解码用例失败 | `00:00 +10 -1: an entry with a malformed day key is reported as damaged [E]`，`Expected: throws <Instance of 'BackupFormatException'> with reason '备份文件已损坏，无法恢复' / Actual: returned <Instance of 'BackupDocument'>` | `git status --short` 无输出，`git diff --stat` 无输出，已还原 |
| 把 `shareFile` 里「分享结束后删除临时文件」去掉 | 有用例失败 | 3 条失败：`the shared copy is deleted after the share call finishes`、`the shared copy is deleted even when the share call fails`、`a markdown copy is cleaned up the same way`，均为 `Expected: false / Actual: <true>` | `git status --short` 无输出，已还原 |
| 把插入路径的 `created_at` 改成写本地默认值 | 插入路径的新断言失败 | `00:00 +2 -1: a new id from a backup is inserted [E]`，`Expected: DateTime:<2026-10-25 06:30:00.000Z> / Actual: DateTime:<2026-10-29 13:06:29.147Z>` | `git status --short` 无输出，`git diff --stat` 无输出，已还原 |

三次变异均确认失败且均已还原，还原后全量测试仍为 `+91: All tests passed!`。

### 文档一致性核对

- 需求文档第 3.1 节与第 6 节里「本版本不自动清理」的表述已改回与实现一致（写新副本前清旧副本、分享返回后删本次副本），AC-05 那行保持「不残留临时文件」不变。
- 需求文档第 2 节 AC-08 补上「字段格式错误」，第 3.6 节错误表补上格式错误一行；第 6 节补上 `dayKey` 格式规则与 `file_selector_android` 缓存副本这一已知限制。
- 第 1 轮报告里「AC-05 通过」「AC-08 的 7 个拒绝用例」「AC-09 通过（界面层断言未固化为常驻测试）」「临时明文副本不自动清理」四处不实或过期的表述已在本轮改正。
- 产品设计文档第「F004 导出与备份恢复」小节本轮未改动：其决策条目与实现一致。

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 91 项自动化测试 + 1 项静态分析 + 1 项调试 APK 构建；失败 0，阻塞 0；真机项仍为 6 类未执行（SAF 保存弹窗、文件选择器弹窗、系统分享面板、分享取消、飞行模式、1000 条量级）。
- 是否满足全部必需验收项：**否**。AC-01~AC-10 的宿主可验证部分全部通过，但依赖真机的子项尚未执行，功能仍不能标记为「已完成」。
- 剩余限制：见「已知限制」8 条；其中第 6 条（`file_selector_android` 读取备份时的插件缓存副本）是本项目无法控制的插件行为，已如实记录。
- 下一步：连接 Android 设备后按「真机验收」表逐项执行并把实际结果补进本报告；特性分支按项目约定保留，不推送远程。
