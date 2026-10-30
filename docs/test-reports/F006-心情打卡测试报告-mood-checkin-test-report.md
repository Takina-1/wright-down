# F006：心情打卡 测试报告

- 关联需求：[F006 心情打卡](../features/F006-心情打卡-mood-checkin.md)
- 测试依据：该需求的验收标准 AC-01 ~ AC-14
- 被测分支：`feat/F006-mood-checkin`（从 F005 的 `0a7e1cc` 开出；F005 未合并到 main）
- 报告保留每一轮结果；未实际执行的项目一律记「未执行」，不写成通过。

---

## 第 1 轮：2026-10-30~31（宿主侧自动化验证）

### 环境与范围

- 执行人：Claude Code（subagent-driven development），每个任务独立实现者 + 任务评审，末尾整分支终审
- 被测代码版本：`feat/F006-mood-checkin`，共 17 个提交；末位提交 `d1723a2`
- 存在未提交改动：无（每轮提交前 `git status` 干净）
- 设备、系统、工具版本：宿主 Windows 10 + Git Bash；Flutter 3.47.8 / Dart 3.13.7；sqflite_common_ffi 2.4.5（宿主 SQLite）
- 数据与网络条件：全部使用合成测试数据，报告不含真实日记；宿主测试不依赖网络
- 本轮范围：domain 层映射表、SQLite schema v3 迁移、mood 字段读写、备份编解码、合并判定、编辑器控制器、两个界面（记录页心情入口、时间轴显示）
- 本轮**未**测范围：真机行为（弹层手势、真实屏幕尺寸布局、跨版本安装升级），见第 2 轮

### 执行结果

| 用例 | 验收编号 | 命令或操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-01 | AC-01 | `flutter test test/ui/home_page_mood_test.dart` | 未设心情时入口显示 😊 占位 | 用例「未设心情时入口显示 😊 占位」通过 | 通过 |
| TC-02 | AC-02 | 同上 | 弹层列 5 种心情+文字；未设无清除 | 用例「点开弹层列出 5 种心情与文字」通过（断言 5 个 label + 清除 findsNothing） | 通过 |
| TC-03 | AC-03 | 同上 | 选择心情后入口显示 emoji 并落库 | 用例「选择心情后入口显示对应 emoji 并落库」通过（断言 `mood == 'happy'`） | 通过 |
| TC-04 | AC-04 | `flutter test test/ui/timeline_page_mood_test.dart` | 已设心情的卡片显示 emoji | 用例「已设心情的卡片显示 emoji」通过 | 通过 |
| TC-05 | AC-05 | 同上 | 未设心情的卡片不显示 emoji | 用例「未设心情的卡片不显示心情 emoji」通过 | 通过 |
| TC-06 | AC-06 | `flutter test test/ui/home_page_mood_test.dart` | 编辑已设心情的条目弹层显示当前心情已选 | 用例「编辑已设心情的条目弹层显示当前心情」通过（断言 check icon） | 通过 |
| TC-07 | AC-07 | `flutter test test/data/sqlite_entry_mood_test.dart` | 清除后 mood 为 null | 用例「AC-07: save 同 id 带 mood=null 能清除已有心情」通过（行级断言 null） | 通过 |
| TC-08 | AC-08 | `flutter test test/data/sqlite_entry_mood_test.dart` | v2 库升级 v3 后老数据完好、mood 为 NULL | 用例「迁移幂等：v2 库升级到 v3」通过（断言数据/schema/索引/行级 NULL 四层） | 通过 |
| TC-09 | AC-09 | 同上 | mood 列已存在再升级不报 duplicate column | 用例「AC-09 幂等重升级」通过 | 通过 |
| TC-10 | AC-10 | `flutter test test/domain/backup_codec_mood_test.dart` | 备份含 mood 字段 | 用例「带 mood 的条目编码后解码能读回 mood」通过 | 通过 |
| TC-11 | AC-11 | 同上 | v1/v2 旧备份（无 mood）解码为 null | 用例「旧 v2 备份（无 mood 键）解码为 null」通过 | 通过 |
| TC-12 | AC-12 | `flutter test test/data/sqlite_entry_mood_test.dart` | 不设心情保存不阻塞，mood 为 null | 用例「mood 为空时列存 NULL」通过 | 通过 |
| TC-13 | AC-13 | 代码审查 | 时间轴心情显示走 `emojiOf` 纯函数，不硬编码 | `timeline_page.dart` 用 `emojiOf(entry.mood)`，无 emoji 字面量；映射表在 `mood.dart` | 通过 |
| TC-14 | AC-14 | `flutter analyze` | 无问题 | `No issues found!` | 通过 |
| TC-15 | AC-14 | `flutter test` | 全部测试通过 | `+275: All tests passed!` | 通过 |
| TC-16 | AC-14 | `grep -rn "UnimplementedError" client/lib` | 无占位实现 | 无输出 | 通过 |
| TC-17 | AC-14 | `flutter build apk --debug` | 调试 APK 构建成功 | `√ Built build/app/outputs/flutter-apk/app-debug.apk` | 通过 |

结果只用：通过、失败、阻塞、未执行。

### 任务评审与修复波次

每个任务独立评审，评审发现的问题在修复波次中解决（提交在特性分支）：

| 任务 | 评审结论 | 修复波次 |
|---|---|---|
| T1 mood.dart 与 Entry.mood | Spec✅ Quality Approved | 修正 brief 编译错误（`<Mood,String,String>` 三元类型参数、`firstWhere(orElse:()=>null)`） |
| T2 schema v3 迁移 | Spec✅（修复后） | Test 1 改 PRAGMA table_info 直接断言 mood 列（消除恒真空洞）；Test 2 手工建 v2 库真正触发 onUpgrade(2→3) |
| T3 mood 读写 | Spec❌（修复后✅） | **Critical**：`save()` 的「非空才写」使 mood 无法清除（AC-07 不可达），用户裁决改为 always-write（null 即清除）；deleted_at 仍「非空才写」未动；替身口径对齐 |
| T4 备份编解码 | Spec✅（修复后） | **Important**：`_decodeEntry` 补 mood 类型校验（非字符串抛 BackupFormatException，对齐 id/content/dayKey） |
| T5 合并规则 | Spec✅ Quality Approved | importAll update+insert 分支均带 mood |
| T6 控制器 mood | Spec❌（修复后✅） | **Critical**：`_dirty` 只比 content，setMood 落库受门控失效；加 `_savedMood`，`_dirty` 纳入 mood 比较；`_saveLoop` 构造 Entry 带 `mood: _mood`（解决 Task 3 跨任务关注：always-write 下文本编辑不静默清除心情） |
| T7 记录页心情入口 | Spec✅ Quality Approved | 两处偏离核实正确：`emojiOf` 返回 `''` 非 null 占位修复；测试先输正文符合架构 |
| T8 时间轴显示 emoji | Spec✅ Quality Approved | 无 |

### 整分支终审（opus，16 提交 19 文件）

**结论：可合并。** 无 Critical、无 Important。AC-01~AC-14 覆盖完整，6 项设计决策口径一致，数据安全路径正确，F005 回归经代码审查未发现破坏。

终审发现 5 条 Minor，合并前修正 4 条（提交 `d1723a2`）：
- `Mood.storage` 死代码 → 删除
- `setMood` 注释不符 → 修正
- AC-06 测试缺口 → 补 check icon 断言
- AC-09 幂等重升级未直测 → 补测试
- 😊 占位 emoji 硬编码 → AC-01 明确指定，可接受，留待后续

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 17，失败 0，阻塞 0，未执行 0（宿主侧）
- 是否满足全部必需验收项：**宿主侧全部满足**；真机相关项见第 2 轮
- 剩余问题、限制及接受依据：
  - 心情为可选附加信息，导入不带 mood 的较新备份会清空本地心情（LWW 语义，见功能文档 §5.4）
  - 不做心情统计、每日心情打卡、按心情筛选
  - 心情表情固定 5 种，不支持自定义
- 下一步：真机验收（第 2 轮）

---

## 第 2 轮：2026-10-31（真机验收）

### 环境与范围

- 执行人：Claude Code（adb 驱动）
- 设备、系统、工具版本：**未连接设备**。`adb devices -l` 返回空列表
- 被测构建产物：`client/build/app/outputs/flutter-apk/app-debug.apk`
- 本轮范围：真机安装后验证记录页心情入口、弹层、时间轴显示、导出导入备份
- 未测原因：测试时用户的手机未通过 USB 连接到本机，无法安装与操作

### 执行结果

| 用例 | 验收编号 | 操作步骤 | 预期结果 | 实际结果 | 结果 |
|---|---|---|---|---|---|
| TC-18 | AC-01~AC-04 | 真机安装后点心情入口、选心情、看时间轴 | 见第 1 轮对应项 | 未连接设备，未执行 | 未执行 |
| TC-19 | AC-05~AC-09 | 真机导出备份、查看 mood 字段、导入旧备份 | 见第 1 轮对应项 | 未连接设备，未执行 | 未执行 |
| TC-20 | AC-17 | 先装旧版本写几条，再装新版本 | 老数据完好且心情功能可用 | 未连接设备，未执行 | 未执行 |
| TC-21 | 小屏布局 | 真实设备确认心情入口与弹层按钮不溢出 | 不裁切 | 宿主组件测试在 320/360 dp 下通过；**真机肉眼确认未执行** | 未执行 |

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 0，失败 0，阻塞 0，**未执行 4**
- 是否满足全部必需验收项：**否**——真机验收未执行
- 剩余问题、限制及接受依据：宿主侧已覆盖全部验收标准的逻辑行为；真机项需要设备连接后补做
- 下一步：连接设备后补做本轮，同一份报告追加「第 3 轮」；**在此之前 F006 不标记为「已完成」**

---

## 第 3 轮：2026-10-31（真机验收，设备已连接）

### 环境与范围

- 执行人：Claude Code（adb 驱动真机，全程截图与数据库行级断言）
- 设备、系统：Xiaomi **2211133C**，Android **15**，物理分辨率 1080×2400，密度 440dpi（约 393×873 dp）
- 被测构建：F006 调试 APK（`client/build/app/outputs/flutter-apk/app-debug.apk`，md5 `7c781a00…`）；迁移对照包：F005 分支（`feat/F005-entry-delete-and-trash`，schema v2）同配置调试 APK
- 数据与网络条件：本地 SQLite，无网络依赖；全部使用合成内容，报告不含真实日记
- 本轮范围：真机上的心情入口／底部弹层／时间轴显示／编辑回显／清除、备份导出与旧备份导入、schema v2→v3 升级与幂等、小屏布局
- 本轮**未**测范围：AC-13（改映射表后显示随之变化）——需要改代码重新构建，不属于真机可观测项，第 1 轮宿主验证已覆盖
- 证据留存：截图见工作区 `.verify/`（本地目录，不入库；数据库副本在核对后已清理）

### 执行结果

| 用例 | 验收编号 | 操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-18 | AC-01 | 冷启动应用，看记录页输入区下方 | 显示 😊 占位 | 入口行显示 😊（`.verify/01_home.png`） | 通过 |
| TC-19 | AC-02 | 点心情入口 | 底部弹层列出 5 种心情；未设时不显示「清除」 | 弹层列出 😄开心／😊不错／🙂一般／😐平淡／😢难过，无「清除」（`.verify/02_sheet.png`） | 通过 |
| TC-20 | AC-03 | 选 😄开心 → 输入正文 | 入口变 😄，自动保存后落库 | 入口变 😄（`.verify/03_selected.png`）；DB 行级断言 `mood='happy'` | 通过 |
| TC-21 | AC-04 | 回顾页看已设心情的卡片 | 卡片正文**上方**显示对应 emoji | 卡片显示 😄，但位置在正文**左侧**（`ListTile.leading`），正文因此整体右移；与 AC-04 的「正文上方」不符（`.verify/05_timeline.png`、`timeline_page.dart:362`） | **失败（位置不符）** |
| TC-22 | AC-05 | 看不设心情的卡片 | 不显示心情图标 | 「no-mood-entry」卡片无 emoji（`.verify/07_timeline_two.png`） | 通过 |
| TC-23 | AC-06 | 编辑已设心情的条目 → 打开弹层 | 弹层显示当前心情为已选 | 开心行右侧显示对勾，底部额外出现「清除」行（`.verify/09_sheet_selected.png`） | 通过 |
| TC-24 | AC-07 | 弹层点「清除」 | 心情恢复未设，时间轴不再显示 emoji | 入口恢复 😊 占位；DB 该行 `mood` 置 NULL；时间轴卡片 emoji 消失（`.verify/10_cleared.png`、`11_timeline_after_clear.png`） | 通过 |
| TC-25 | AC-08 | 先装 F005 包写 2 条记录 → 覆盖装 F006 包 | 老数据完整，`mood` 列为 NULL，读写正常 | `user_version` 2→3；`entries` 新增 `mood` 列；2 条老记录内容完好、`mood` 为 NULL；业务索引（`entries_timeline`／`entries_day`／`entries_deleted`）齐全；logcat 无异常 | 通过 |
| TC-26 | AC-09 | 构造「`user_version=2` 但已有 `mood` 列」的库 → 装 F006 包启动 | 不报 duplicate column，整库可打开 | 未出现 duplicate column；`user_version` 回到 3；2 条记录完好；logcat 无异常（`.verify/41`、`42`） | 通过 |
| TC-27 | AC-10 | 记录页 → 我的 → 导出与备份 → 导出备份 | 备份条目带 `mood` 字段 | 生成 `/sdcard/Download/本地日记-2026-10-31-01-53-38.json`（`version: 2`）；带心情条目含 `"mood": "happy"`，未设心情的条目**不含** `mood` 键 | 通过 |
| TC-28 | AC-11 | 导入 v1 旧备份（无 mood 字段） | 正常导入，条目 mood 为 null | 预览「共有 2 条，新增 1 条，更新 0 条，跳过 1 条」；新条目 `mood=NULL`；较新的本地记录（含 `happy` 心情）未被覆盖（`.verify/20_restore_dialog.png`） | 通过 |
| TC-29 | AC-12 | 不设心情直接保存 | 保存成功，mood 为 null，不阻塞 | 「no-mood-entry」保存成功，`mood` 为 NULL | 通过 |
| TC-30 | TC-21 | `wm size 720x1280` + `wm density 320`（360×640 dp）后打开弹层 | 心情入口与弹层按钮不溢出 | 6 行弹层（含底部「清除」）完整可见，「清除」可点并生效；恢复显示 😊（`.verify/25`、`26`） | 通过 |

补充观察（不单独计用例）：

- F005 包覆盖打开 F006 建的 v3 库：应用正常启动，无崩溃，`user_version` 仍为 3，`mood` 列与数据完好（说明旧版不会破坏新库结构）。
- 迁移验证用的临时数据在测试后已清除，设备上的应用数据已恢复到本轮开始前的状态（4 条合成记录，其中 1 条带 `happy` 心情），F006 调试包已安装。

### 本轮发现

- ⚠️ **AC-04 的显示位置与实现不符**：验收标准写「时间轴卡片正文上方显示 emoji」，用户立项时确认的也是「正文上方」；实现用 `ListTile.leading` 把 emoji 放在正文**左侧**并与正文垂直居中，正文因此整体右移。功能可用、语义清晰，但与已确认的呈现方式不同，需要二选一：改布局为正文上方，或改文档／验收标准为「卡片内显示心情 emoji」。
- 😊 **占位 emoji 与「不错」心情撞脸**：未设心情时入口显示 😊 占位，而 😊 同时是「不错」心情的 emoji，用户选中「不错」后入口外观与未设时完全相同，只能靠打开弹层看对勾区分。
- 📂 **恢复用的系统文件选择器未按扩展名过滤**：应用传了 `extensions: ['json']` 与 `application/json`，但设备上的系统选择器仍列出 PDF、BIN、RAR 等文件，用户要自己在杂乱的下载目录里找备份文件。
- 📱 **MIUI 拦截 adb 安装**：`adb install` 返回 `INSTALL_FAILED_USER_RESTRICTED`，改用系统安装器（推 APK 到 `/sdcard/Download` + `ACTION_VIEW` intent + 手动点「继续更新」）才能覆盖安装，自动化成本高。
- ⚠️ **弹层底部行贴边**：在 360×640 dp 小屏上，「清除」行紧贴屏幕下边缘（可见且可点，但没有底部安全区留白）；在 393×873 dp 的本机上是同样贴边。

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 12，**失败 1**（AC-04 位置不符），阻塞 0，未执行 1（AC-13，非真机可观测项）
- 是否满足全部必需验收项：**否**——AC-04 的可观察结果与实现不一致，需用户裁决后处置
- 剩余问题、限制及接受依据：
  - 导入不带 mood 的较新备份会清空本地心情（LWW 语义，见功能文档 §5.4），本轮在真机上再次确认该行为
  - 心情表情固定 5 种，不支持自定义
- 下一步：AC-04 的呈现方式待裁决。用户 2026-10-31 决定**暂缓处理**（先不改实现，也暂不改文档措辞），AC-04 保持未通过，F006 暂不合并到 `main`；将来处置后需重跑受影响的真机场景

---

## 构建记录

```bash
cd client
flutter analyze          # No issues found!
flutter test             # 275 项全部通过
grep -rn "UnimplementedError" lib   # 无占位实现
flutter build apk --debug # √ Built build/app/outputs/flutter-apk/app-debug.apk
```

构建过程有一条无害告警：`Warning: SDK processing. This version only understands SDK XML versions up to 3 but an SDK XML file of version 4 was encountered.`（命令行工具与 SDK XML 版本不一致，不影响产物。）

---

## 合并状态

**已合并到 main**（2026-10-31，合并提交 `ea2d7b8`「merge:合并F005删除回收站与F006心情打卡,merge F005 delete-trash and F006 mood checkin」）。按 `AGENTS.md`「测试失败、未执行或受阻时不得合并到 main」：第 3 轮真机验收已执行，AC-01~AC-03、AC-05~AC-12 全部通过，**AC-04 未通过**（时间轴 emoji 位置与验收标准不一致）、AC-13 非真机可观测项。用户 2026-10-31 决定暂缓处置 AC-04（既不改实现，也暂不改文档措辞）并授权合并——按 `AGENTS.md`「允许验收包含明确约定的非阻塞限制，但必须记录由谁、何时接受」，该接受已记录在案，本报告不改写 AC-04 的失败结论。特性分支 `feat/F006-mood-checkin` 保留（本地与远程都不删除）。

本次合并同时包含 F005（删除记录与回收站）的代码：F006 分支自 F005 的 `0a7e1cc` 开出，F005 此前未合并到 main。F005 的真机验收仍未执行，其台账状态保持「待测试」。
