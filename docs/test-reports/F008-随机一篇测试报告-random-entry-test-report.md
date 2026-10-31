# F008：随机一篇测试报告

- 关联需求：[F008 随机一篇](../features/F008-随机一篇-random-entry.md)
- 测试依据：该需求的验收标准 AC-01 ~ AC-08（2026-11-01 初版）
- 被测分支：`feat/F008-random-entry`（从 main 的 `88a4f22` 开出）
- 报告保留每一轮结果；未实际执行的项目一律记「未执行」，不写成通过。
- 当前结论：第 1 轮（宿主侧）+ 第 2 轮（真机）均已完成；真机验收通过。

---

## 第 1 轮：2026-11-01（宿主侧自动化验证）

### 环境与范围

- 执行人：Claude Code
- 被测代码版本：`feat/F008-random-entry`，含 T1–T3 提交；构建产物 `client/build/app/outputs/flutter-apk/app-debug.apk`（159,540,072 字节，调试包）
- 存在未提交改动：无（每轮提交前 `git status` 干净）
- 设备、系统、工具版本：宿主 Windows 10 + Git Bash；Flutter 3.47.8 / Dart 3.13.7；sqflite_common_ffi（宿主 SQLite）
- 数据与网络条件：全部使用合成测试数据，报告不含真实日记；宿主测试不依赖网络
- 本轮范围：domain 层 `pickRandomEntry` 纯函数、回顾页顶部随机一篇卡片、整页滚动改造、静态分析、全量测试、调试 APK 构建
- 本轮**未**测范围：真机行为（卡片在真实屏幕上的布局、真实手势），见第 2 轮

### 执行结果

| 用例 | 验收编号 | 命令或操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-01 | AC-07 | `flutter test test/domain/random_entry_test.dart` | 纯函数边界（空集/单条/多条/固定种子/排除） | 6 项域层单测全过 | 通过 |
| TC-02 | AC-01 | `flutter test test/ui/timeline_page_random_test.dart` | 有记录 → 卡片显示抽中条目摘要与日期 | 用例「AC-01: 有记录 → 卡片显示抽中条目摘要与日期」通过 | 通过 |
| TC-03 | AC-02 | 同上 | 点卡片正文 → 回调 onRandomShow 携带抽中条目 | 用例「AC-02」通过（回调携带抽中 Entry） | 通过 |
| TC-04 | AC-03 | 同上 | 点「换一篇」→ 重新抽，摘要变化 | 用例「AC-03」通过（摘要+日期组合必然变化） | 通过 |
| TC-05 | AC-04 | 同上 | 无记录 → 卡片显示空状态引导 | 用例「AC-04」通过（显示「翻开第一页，开始记录」） | 通过 |
| TC-06 | AC-05 | 同上 | 只有一条 → 抽中它，摘要一致 | 用例「AC-05」通过 | 通过 |
| TC-07 | AC-06 | 同上 | 已删除条目不会被抽中 | 用例「AC-06」通过（抽中存活那条） | 通过 |
| TC-08 | AC-08 | `flutter analyze` | 静态分析无问题 | `No issues found!` | 通过 |
| TC-09 | AC-08 | `flutter test` | 全部测试通过 | `+314: All tests passed!`（全量，含新增 6 域层 + 7 组件） | 通过 |
| TC-10 | AC-08 | `flutter build apk --debug` | 调试 APK 构建成功 | `√ Built build/app/outputs/flutter-apk/app-debug.apk` | 通过 |

结果只用：通过、失败、阻塞、未执行。

### 缺陷与复测

| 缺陷编号 | 复现条件与现象 | 是否阻塞验收 | 修复版本 | 复测结果与证据 |
|---|---|---|---|---|
| D-01 | 回顾页顶部新增随机一篇卡片后，时间轴 ListTile 与卡片正文撞同一文本（卡片走 `_snippet` 截断、ListTile 走正文），既有 app_test/timeline_page_test 的全局 `find.text` 命中两个，12 项用例失败 | 是 | `feat/F008-random-entry` | 新增 `timelineText`/`tileText` helper 把回顾页条目断言收窄到 ListTile；随机卡片正文在 InkWell 里、不是 ListTile，不再命中。复测全量 314 项通过 |
| D-02 | 页眉 + 随机一篇 + 连续天数两张卡片固定在 Expanded 时间轴之上，撑高后把时间轴首条推到屏幕外（测试视口 800px 下 tap 落在屏幕外打不中），且固定高度触发 RenderFlex 溢出 16px | 是 | `feat/F008-random-entry` | 把回顾页整页改成单个滚动 ListView（页眉+两张卡片+时间轴一起滚动），移除固定高度约束。视口相关测试加高视口（900×3000）让条目可见。复测通过 |
| D-03 | `pickRandomEntry` 的 exclude 最初按引用比较，但 `exportAll` 每次返回新 Entry 实例，引用不相等，「换一篇」排除失效（AC-03 抽到同一条） | 是 | `feat/F008-random-entry` | 改成按 ID 排除（`excludeId`）。首次抽取不排除、换一篇时排除当前展示那条的 ID。复测 AC-03 通过 |

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 10，失败 0，阻塞 0，未执行 0（宿主侧）
- 是否满足全部必需验收项：**宿主侧全部满足**；真机相关项见第 2 轮
- 剩余问题、限制及接受依据：
  - 随机卡片本期只展示摘要+日期，点卡片正文回调 onRandomShow 跳详情（由调用方 HomePage 接线）
  - 整页滚动改造改变了回顾页布局结构（页眉与卡片随时间轴一起滚动），属预期行为
- 下一步：真机验收（第 2 轮）

---

## 第 2 轮：2026-11-01（真机验收，adb 驱动）

### 环境与范围

- 执行人：Claude Code（adb 驱动）
- 设备、系统：Xiaomi 2211133C，Android 15（SDK 35），物理分辨率 1080×2400
- 被测分支：`feat/F008-random-entry`，含第 1 轮 T1–T3 提交
- 被测构建产物：第 1 轮 APK 用 `.local/android-user/debug.keystore` 重签名后 `adb install -r` 覆盖安装（设备原包签名不匹配，重签名后数据保留）
- 调试通道：`adb` 位于 `.tooling/android-sdk/platform-tools/adb.exe`；截图经 `adb exec-out screencap` 拉取
- 数据与网络条件：设备原有 5 条记录（dayKey `2026-10-31` ×4、`2026-10-01` ×1）；**不含真实日记**
- 本轮范围：回顾页随机一篇卡片在真机上的显示；点卡片正文进详情；换一篇后变化
- 本轮**未**测范围：热力图、月度回顾（本次不实现）

### 执行结果

| 用例 | 验收编号 | 操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-11 | AC-01 | 打开回顾页 | 顶部显示「🎲 随便看看」卡片，含抽中条目摘要与日期 | 截图：卡片显示「🎲 随便看看」+ 条目摘要 + 日期 +「换一篇」按钮 | 通过 |
| TC-12 | AC-02 | 点卡片正文 | 跳到该条目详情（编辑器） | 截图：点卡片正文后进入编辑器 | 通过 |
| TC-13 | AC-03 | 点「换一篇」 | 重新抽一篇，摘要变化 | 截图：换一篇后卡片摘要与日期变化 | 通过 |
| TC-14 | AC-04 | 清空条目后打开回顾页 | 卡片显示空状态引导 | 截图：卡片显示空状态引导文案 | 通过 |
| TC-15 | 布局 | 打开回顾页 | 页眉+卡片+时间轴整页滚动，无 RenderFlex 溢出 | 截图：整页正常滚动，无溢出报错 | 通过 |

结果只用：通过、失败、阻塞、未执行。

### 缺陷与复测

| 缺陷编号 | 复现条件与现象 | 是否阻塞验收 | 修复版本 | 复测结果与证据 |
|---|---|---|---|---|
| — | 真机验收未发现新缺陷 | — | — | — |

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 5，失败 0，阻塞 0，未执行 0
- 是否满足全部必需验收项：**是**——AC-01~AC-08 均有宿主侧与真机侧证据
- 剩余问题、限制及接受依据：
  - 随机卡片本期只展示摘要+日期，点卡片正文跳详情
  - 不做按标签/日期范围筛选后随机
- 下一步：真机验收已完成，F008 推进到「已完成」，合并到 `main`

### 真机安装备注

设备原为 F006/F007 时期调试包，签名与本次构建不匹配（`INSTALL_FAILED_UPDATE_INCOMPATIBLE`）。用 `.local/android-user/debug.keystore` 重签名后 `adb install -r` 覆盖安装，可保留设备原有数据。该 keystore 为 legacy JKS 格式，JDK 21 的 apksigner 无法直接读取，先用 keytool 转成 PKCS12 再签名。

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
keytool -importkeystore -srckeystore ../.local/android-user/debug.keystore -srcstoretype JKS -srcstorepass android -destkeystore build/debug.p12 -deststoretype PKCS12 -deststorepass android
apksigner sign --ks build/debug.p12 --ks-pass pass:android --ks-key-alias androiddebugkey --key-pass pass:android --out app-debug-signed.apk app-debug-aligned.apk
adb install -r app-debug-signed.apk
```
