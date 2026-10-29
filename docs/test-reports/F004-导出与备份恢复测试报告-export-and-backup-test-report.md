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
| AC-05 | 在文件选择器或分享面板取消 | `export_controller_test.dart`「cancelling the save dialog is not reported as a failure」「cancelling the file picker is not reported as a failure」「cancelling the picker drops the previously picked backup」（取消后不留上一份备份）；`export_page_test.dart`「cancelling the confirmation leaves the journal untouched」（取消确认不写入、不显示失败） | 通过（宿主部分）；SAF 取消未执行 |
| AC-06 | 导入含新旧条目的备份 | `sqlite_entry_import_test.dart`「a new id from a backup is inserted」「a newer backup entry updates content but keeps creation time」（正文换成备份的、创建时间保持本地）「an older backup entry never overwrites a newer local entry」；`export_controller_test.dart`「confirming a restore merges the backup into the journal」（新增 1、更新 2、跳过 3，提示文案一致）；`restore_preview_test.dart`「a mixed batch counts insertions, updates and skips separately」 | 通过 |
| AC-07 | 同一备份连续导入两次 | `sqlite_entry_import_test.dart`「importing the same backup twice changes nothing the second time」（第二次 inserted 0、updated 0、skipped 2，条数不变）；`restore_preview_test.dart`「an identical entry is counted as skipped」 | 通过 |
| AC-08 | 导入损坏或不支持的备份 | `backup_codec_test.dart` 7 个拒绝用例各自抛出可区分原因：非 JSON →「这不是本应用的备份文件」；`format` 不符 → 同上；`version` 更高 →「备份来自更新的版本，请先升级应用」；缺 `dayKey` / 缺 `exportedAt` →「备份文件已损坏，无法恢复」；`content` 类型错误 → 同上；重复 id → 同上；正文为空或全空白 → 同上。`export_page_test.dart`「a broken backup shows the reason and changes nothing」（页面显示原因且不写入）；`sqlite_entry_import_test.dart`「a broken entry rolls the whole import back」（事务整体回滚，本地数据不变） | 通过 |
| AC-09 | 恢复完成后查看回顾页 | 仓储与控制器层：`export_controller_test.dart`「confirming a restore merges the backup into the journal」（恢复后条目写入本机仓储、提示新增/更新/跳过）；`sqlite_entry_import_test.dart`「a newer backup entry updates content but keeps creation time」（恢复的条目 ID 与创建时间与备份一致，dayKey 保持本地）；「importing the same backup twice changes nothing the second time」（可反复恢复）。界面层用一次性脚本验证：恢复后时间轴能读到该条目、切换回「回顾」页会重新读取仓储——该脚本按本任务范围未纳入仓库，属一次性核对 | 通过（宿主部分）；界面层断言未固化为常驻测试 |
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

需要留意的实现与需求描述差异（不阻塞验收）：需求文档第 3.1 节原描述保存流程为「先写临时文件，再复制到用户选定位置，结束后清理临时文件」，实际实现改为由 `file_picker.saveFile(bytes:)` 直接把字节写入用户选定位置，只有分享路径会在应用缓存目录留下明文副本，且不自动清理。本轮已把需求文档第 3.1 节与第 6 节改写为与最终实现一致，并把「分享用的临时明文副本不自动清理」补进限制清单。

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
5. **分享的临时明文副本留在应用缓存目录**：系统分享需要真实文件路径，导出内容会以明文写入应用缓存目录下的临时文件并交给分享面板；该副本本轮不自动清理，系统通常会随缓存回收，但用户主动清理应用数据前它一直存在。
6. **Markdown 分组与时间轴排序口径不同**：Markdown 按 `dayKey` 分组，应用内时间轴按 `createdAt` 排序。设备改过时区或从其它时区恢复的备份会让两者顺序不同，本次不合并两种视角。
7. 备份与恢复为纯本地操作，不依赖网络；本轮的飞行模式验证未执行，断网可用性仍待真机确认。

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 80 项自动化测试 + 1 项静态分析 + 1 项调试 APK 构建；失败 0，阻塞 0；真机项 6 类未执行（SAF 保存弹窗、文件选择器弹窗、系统分享面板、分享取消、飞行模式、1000 条量级）。
- 是否满足全部必需验收项：**否**。AC-01~AC-10 的宿主可验证部分全部通过，但依赖真机的子项（SAF 弹窗、分享面板、飞行模式、1000 条量级）尚未执行，因此功能不能标记为「已完成」。
- 剩余问题、限制及接受依据：见上方「已知限制」7 条，均为明文存储、无附件、无转义、内存占用一类的设计取舍，与需求文档第 6 节一致；真机项等待连接 Android 设备后补做。
- 下一步：连接 Android 设备后按「真机验收」表逐项执行并把实际结果补进本报告；同时把功能台账 F004 从「待测试」推进到「待验收」。F004 特性分支按项目约定保留，不推送远程。

### 后续轮次

（设备验收完成后在此追加第 2 轮，注明新的被测版本与逐项实测结果。）
