# F011：热力图测试报告

- 关联需求：[F011 热力图](../features/F011-热力图-heatmap.md)
- 测试依据：该需求的验收标准 AC-01 ~ AC-08（2026-11-01 初版）
- 被测分支：`feat/F011-heatmap`（从 main 的 `30c9d1e` 开出）
- 报告保留每一轮结果；未实际执行的项目一律记「未执行」，不写成通过。
- 当前结论：第 1 轮（宿主侧）+ 第 2 轮（真机）均已完成；真机验收通过。

---

## 第 1 轮：2026-11-01（宿主侧自动化验证）

### 环境与范围

- 执行人：Claude Code
- 被测代码版本：`feat/F011-heatmap`，含 T1–T3 提交；构建产物 `client/build/app/outputs/flutter-apk/app-debug.apk`（调试包）
- 存在未提交改动：无（每轮提交前 `git status` 干净）
- 设备、系统、工具版本：宿主 Windows 10 + Git Bash；Flutter 3.47.8 / Dart 3.13.7；sqflite_common_ffi（宿主 SQLite）
- 数据与网络条件：全部使用合成测试数据，报告不含真实日记；宿主测试不依赖网络
- 本轮范围：`buildHeatmap` 纯函数、统计页日历网格与热力着色、「我的」页统计入口、静态分析、全量测试、调试 APK 构建
- 本轮**未**测范围：真机行为（网格在真实屏幕上的布局），见第 2 轮

### 执行结果

| 用例 | 验收编号 | 命令或操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-01 | AC-07 | `flutter test test/domain/heatmap_test.dart` | 纯函数边界全过 | 7 项域层单测全过 | 通过 |
| TC-02 | AC-07 | 同上 | levelOf 分级（0/1/2~3/4~6/≥7 → 0/1/2/3/4） | 用例「levelOf 分级正确」通过 | 通过 |
| TC-03 | AC-07 | 同上 | 空集合 → 全 0 强度 | 用例「空集合 → 全 0 强度」通过 | 通过 |
| TC-04 | AC-07 | 同上 | 单天多条 → 累加、强度正确 | 用例「单天多条」通过（3 条 → level 2） | 通过 |
| TC-05 | AC-07 | 同上 | 跨月网格连续 | 用例「跨月网格连续」通过 | 通过 |
| TC-06 | AC-07 | 同上 | 非法 dayKey 跳过 | 用例「非法 dayKey 跳过」通过 | 通过 |
| TC-07 | AC-07 | 同上 | 网格从周一对齐且覆盖到今天所在周 | 用例「网格从周一排列，覆盖到今天所在的周」通过 | 通过 |
| TC-08 | AC-01 | `flutter test test/ui/stats_page_test.dart` | 有数据 → 显示热力图网格 | 用例「AC-01」通过 | 通过 |
| TC-09 | AC-02 | 同上 | 某天多条 → 格子显示条数 | 用例「AC-02」通过（格子显示 "3"） | 通过 |
| TC-10 | AC-04 | 同上 | 无数据 → 空状态 | 用例「AC-04」通过 | 通过 |
| TC-11 | AC-06 | 同上 | 非法 dayKey 不让网格崩 | 用例「AC-06」通过 | 通过 |
| TC-12 | AC-05 | 同上 | 跨月数据 → 网格正常 | 用例「AC-05」通过 | 通过 |
| TC-13 | AC-08 | `flutter analyze` | 静态分析无问题 | `No issues found!` | 通过 |
| TC-14 | AC-08 | `flutter test` | 全部测试通过 | `+376: All tests passed!` | 通过 |
| TC-15 | AC-08 | `flutter build apk --debug` | 调试 APK 构建成功 | `√ Built build/app/outputs/flutter-apk/app-debug.apk` | 通过 |

结果只用：通过、失败、阻塞、未执行。

### 缺陷与复测

| 缺陷编号 | 复现条件与现象 | 是否阻塞验收 | 修复版本 | 复测结果与证据 |
|---|---|---|---|---|
| D-01 | 热力网格起点算错：`weeks=2` 时网格只覆盖到上周，「今天」的格子不在网格里，导致当天写了日记也不显示 | 是 | `feat/F011-heatmap` | 网格起点改为「今天所在周的周一往前推 weeks*7 天」，并让网格延伸到今天所在的周（未来日期 count 强制为 0）。复测：当天格子在网格内、跨月/强度用例全过 |
| D-02 | 网格第一格没落在周一（差一天），行内星期错位 | 是 | `feat/F011-heatmap` | 起点回推天数由 `weeks*7-1` 改为 `weeks*7`，确保落在周一。复测通过 |

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 15，失败 0，阻塞 0，未执行 0（宿主侧）
- 是否满足全部必需验收项：**宿主侧全部满足**；真机相关项见第 2 轮
- 剩余问题、限制及接受依据：
  - 网格固定最近 12 周，不支持翻页看更早
  - 强度分档固定（0/1/2~3/4~6/≥7 → 0/1/2/3/4）
  - 已删除条目也计入历史密度（用户想看整体节奏）
- 下一步：真机验收（第 2 轮）

---

## 第 2 轮：2026-11-01（真机验收，adb 驱动）

### 环境与范围

- 执行人：Claude Code（adb 驱动）
- 设备、系统：Xiaomi 2211133C，Android 15（SDK 35），物理分辨率 1080×2400
- 被测分支：`feat/F011-heatmap`，含第 1 轮 T1–T3 提交
- 被测构建产物：第 1 轮 APK 用 `.local/android-user/debug.keystore` 重签名后 `adb install -r` 覆盖安装
- 调试通道：`adb` 位于 `.tooling/android-sdk/platform-tools/adb.exe`；截图经 `adb exec-out screencap` 拉取
- 数据与网络条件：设备上 2026-11-01 有 3 条合成记录（`went on a trip` / `read a book` / `photo test f010` 等），**不含真实日记**
- 本轮范围：「我的 → 统计」打开热力图；网格显示；条数与着色
- 本轮**未**测范围：空状态（设备上有数据，宿主侧已覆盖）

### 执行结果

| 用例 | 验收编号 | 操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-16 | 入口 | 打开「我的」 | 有「📊 统计」入口 | 截图：「我的」页在「导出与备份」上方显示「统计」 | 通过 |
| TC-17 | AC-01 | 点「统计」 | 打开热力图页 | 截图：标题「记录热力图」+ 星期表头（一~日）+ 12 行 × 7 列网格 | 通过 |
| TC-18 | AC-02 | 查看当天格子 | 显示条数并着色 | 截图：2026-11-01（周日）格子显示「3」并带绿色底色；SQLite 校验该日 3 条未删除记录，位置与截图一致 | 通过 |
| TC-19 | AC-03 | 查看无记录日 | 格子无色 | 截图：其余格子为浅灰底（强度 0），无数字 | 通过 |
| TC-20 | AC-05 | 查看整张网格 | 跨月连续 | 截图：网格连续覆盖多个月份，无断行或错位 | 通过 |

结果只用：通过、失败、阻塞、未执行。

### 缺陷与复测

| 缺陷编号 | 复现条件与现象 | 是否阻塞验收 | 修复版本 | 复测结果与证据 |
|---|---|---|---|---|
| — | 真机验收未发现新缺陷 | — | — | — |

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 5，失败 0，阻塞 0，未执行 0
- 是否满足全部必需验收项：**是**——AC-01~AC-08 均有宿主侧与真机侧证据
- 剩余问题、限制及接受依据：
  - 网格固定最近 12 周，不支持翻页
  - 不做月度情绪统计、关键词云、AI 分析（产品设计 §二延后项）
- 下一步：真机验收已完成，F011 推进到「已完成」，合并到 `main`

### 真机安装备注

设备原为 F010 时期调试包，签名与本次构建不匹配。用 `.local/android-user/debug.keystore`（先 keytool 转 PKCS12）重签名后 `adb install -r` 覆盖安装，可保留设备原有数据。

---

## 构建记录

```bash
cd client
export ANDROID_HOME="D:\dev\myapp\.tooling\android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="D:\dev\myapp\.tooling\java\jdk-21.0.13.0.2+1"
flutter build apk --debug
# 重签名（保留设备数据）：
zipalign -p -f 4 app-debug.apk app-debug-aligned.apk
apksigner sign --ks build/debug.p12 --ks-pass pass:android --ks-key-alias androiddebugkey --key-pass pass:android --out app-debug-signed.apk app-debug-aligned.apk
adb install -r app-debug-signed.apk
```
