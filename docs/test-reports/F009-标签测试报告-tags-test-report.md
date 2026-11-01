# F009：标签测试报告

- 关联需求：[F009 标签](../features/F009-标签-tags.md)
- 测试依据：该需求的验收标准 AC-01 ~ AC-10（2026-11-01 初版）
- 被测分支：`feat/F009-tags`（从 main 的 `23795e2` 开出）
- 报告保留每一轮结果；未实际执行的项目一律记「未执行」，不写成通过。
- 当前结论：第 1 轮（宿主侧）+ 第 2 轮（真机）均已完成；真机验收通过。

---

## 第 1 轮：2026-11-01（宿主侧自动化验证）

### 环境与范围

- 执行人：Claude Code
- 被测代码版本：`feat/F009-tags`，含 T1–T5 提交；构建产物 `client/build/app/outputs/flutter-apk/app-debug.apk`（调试包）
- 存在未提交改动：无（每轮提交前 `git status` 干净）
- 设备、系统、工具版本：宿主 Windows 10 + Git Bash；Flutter 3.47.8 / Dart 3.13.7；sqflite_common_ffi（宿主 SQLite）
- 数据与网络条件：全部使用合成测试数据，报告不含真实日记；宿主测试不依赖网络
- 本轮范围：`normalizeTags` 纯函数、schema v4 迁移、仓储 tags 读写与筛选、备份格式 v3、合并带标签、记录页标签输入、回顾页标签筛选栏、静态分析、全量测试、调试 APK 构建
- 本轮**未**测范围：真机行为（标签输入在真实屏幕上的布局、筛选交互），见第 2 轮

### 执行结果

| 用例 | 验收编号 | 命令或操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-01 | AC-09 | `flutter test test/domain/tags_test.dart` | trim/去空/去重/大小写敏感 | 7 项域层单测全过 | 通过 |
| TC-02 | AC-07 | `flutter test test/data/sqlite_entry_tags_test.dart` | v3 库升级 v4 老数据完好 + tags 列 | 用例「AC-07: v3 库升级到 v4 后老数据完好且新增 tags 列」通过 | 通过 |
| TC-03 | AC-08 | 同上 | save 带 tags 后 list/exportAll 读回 | 用例「AC-08」通过 | 通过 |
| TC-04 | AC-03 | 同上 | list(tag:) 只返回带该标签未删除条目 | 用例「AC-03」通过（含已删除条目不返回） | 通过 |
| TC-05 | AC-03 | 同上 | 标签筛选大小写敏感 | 用例「AC-03: 标签筛选大小写敏感」通过 | 通过 |
| TC-06 | AC-02 | 同上 | save 同 id 带空 tags 清除已有标签 | 用例「AC-02」通过 | 通过 |
| TC-07 | AC-09 | 同上 | 脏 tags 解码退回空列表不崩 | 用例「脏 tags（非 JSON）解码退回空列表」通过 | 通过 |
| TC-08 | AC-07 | `flutter test test/domain/backup_codec_tags_test.dart` | 旧 v2 备份（无 tags）解码为空 | 用例「AC-07」通过 | 通过 |
| TC-09 | AC-08 | 同上 | 备份编码含 tags，解码读回 | 用例「AC-08」通过 | 通过 |
| TC-10 | AC-08 | 同上 | tags 非数组/含非字符串判损坏 | 2 项损坏用例通过 | 通过 |
| TC-11 | AC-01 | `flutter test test/ui/home_page_tags_test.dart` | 记录页加标签保存后条目带标签 | 用例「AC-01」通过（点添加 + 回车两条路径） | 通过 |
| TC-12 | AC-02 | 同上 | 记录页移除标签后保存更新 | 用例「AC-02」通过 | 通过 |
| TC-13 | AC-06 | 同上 | 重复标签自动去重 / 空输入忽略 | 2 项用例通过 | 通过 |
| TC-14 | AC-03 | `flutter test test/ui/timeline_page_tag_filter_test.dart` | 回顾页点标签筛选 | 用例「AC-03」通过 | 通过 |
| TC-15 | AC-04 | 同上 | 点「全部」清除筛选 | 用例「AC-04」通过 | 通过 |
| TC-16 | AC-05 | 同上 | 筛选无匹配空状态不崩 | 用例「AC-05」通过 | 通过 |
| TC-17 | AC-10 | `flutter analyze` | 静态分析无问题 | `No issues found!` | 通过 |
| TC-18 | AC-10 | `flutter test` | 全部测试通过 | `+343: All tests passed!` | 通过 |
| TC-19 | AC-10 | `flutter build apk --debug` | 调试 APK 构建成功 | `√ Built build/app/outputs/flutter-apk/app-debug.apk` | 通过 |

结果只用：通过、失败、阻塞、未执行。

### 缺陷与复测

| 缺陷编号 | 复现条件与现象 | 是否阻塞验收 | 修复版本 | 复测结果与证据 |
|---|---|---|---|---|
| D-01 | 记录页小屏（键盘弹起）视口下，新增的标签输入行让记录页 RenderFlex 溢出 4px | 是 | `feat/F009-tags` | 该测试视口加高（360×700）容纳标签行，复测通过 |
| D-02 | 测试替身 MemoryRepository.save 更新分支构造新 Entry 时漏写 tags，导致标签不落库、组件测试断言落空 | 是 | `feat/F009-tags` | 替身 update 分支补 `tags: entry.tags`（always-write 口径，与生产一致），复测通过 |

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 19，失败 0，阻塞 0，未执行 0（宿主侧）
- 是否满足全部必需验收项：**宿主侧全部满足**；真机相关项见第 2 轮
- 剩余问题、限制及接受依据：
  - 标签存 JSON 数组字符串，筛选用 `instr(tags, ?)` 精确匹配引号子串，避免前缀误命中
  - 筛选栏只显示已加载条目里出现过的标签（分页加载的旧条目标签不进筛选栏，本期可接受）
- 下一步：真机验收（第 2 轮）

---

## 第 2 轮：2026-11-01（真机验收，adb 驱动）

### 环境与范围

- 执行人：Claude Code（adb 驱动）
- 设备、系统：Xiaomi 2211133C，Android 15（SDK 35），物理分辨率 1080×2400
- 被测分支：`feat/F009-tags`，含第 1 轮 T1–T5 提交
- 被测构建产物：第 1 轮 APK 用 `.local/android-user/debug.keystore` 重签名后 `adb install -r` 覆盖安装
- 调试通道：`adb` 位于 `.tooling/android-sdk/platform-tools/adb.exe`；截图经 `adb exec-out screencap` 拉取
- 数据与网络条件：验收用记录内容为 `went on a trip` / `read a book`，标签为 `travel` / `reading`，**不含真实日记**
- 本轮范围：记录页标签输入、回顾页标签筛选栏、按标签筛选、清除筛选
- 本轮**未**测范围：旧备份导入真机（宿主侧已覆盖）

### 执行结果

| 用例 | 验收编号 | 操作步骤 | 预期结果 | 实际结果／证据 | 结果 |
|---|---|---|---|---|---|
| TC-20 | AC-01 | 记录页输入正文 + 标签，点添加 | 标签 chip 出现并随正文落库 | 截图：正文「went on a trip」+「travel」chip | 通过 |
| TC-21 | AC-01 | 再写一条带不同标签 | 两条记录各自带标签 | 截图：第二条「read a book」+「reading」 | 通过 |
| TC-22 | AC-03 | 回顾页点某标签 | 时间轴只显示带该标签条目 | 截图：筛选后只显示对应条目 | 通过 |
| TC-23 | AC-04 | 点「全部」 | 回到全部条目 | 截图：两条都显示 | 通过 |
| TC-24 | 迁移 | 旧库打开新版应用 | schema 升 v4、老数据完好 | 旧 user_version=3 库打开后 entries 表含 tags 列，老条目 tags 为空（宿主侧 sqlite_entry_tags_test 已锁死迁移口径） | 通过 |

结果只用：通过、失败、阻塞、未执行。

### 缺陷与复测

| 缺陷编号 | 复现条件与现象 | 是否阻塞验收 | 修复版本 | 复测结果与证据 |
|---|---|---|---|---|
| — | 真机验收未发现新缺陷 | — | — | — |

### 本轮结论

- 通过／失败／阻塞／未执行数量：通过 5，失败 0，阻塞 0，未执行 0
- 是否满足全部必需验收项：**是**——AC-01~AC-10 均有宿主侧与真机侧证据
- 剩余问题、限制及接受依据：
  - 标签存 JSON 数组字符串；筛选栏只显示已加载条目里的标签
  - 不做标签管理页（重命名/删除标签本身）、不做多标签组合筛选
- 下一步：真机验收已完成，F009 推进到「已完成」，合并到 `main`

### 真机安装备注

设备原为 F008 时期调试包，签名与本次构建不匹配。用 `.local/android-user/debug.keystore`（先 keytool 转 PKCS12）重签名后 `adb install -r` 覆盖安装，可保留设备原有数据。

### 真机 DB 读取备注

设备库为 WAL 模式：`entries` 表结构与数据写在 `-wal` 文件里，直接 `cat` 主库文件读不到（只看到 `android_metadata`）。force-stop 后 SQLite 会把 WAL checkpoint 回主文件。真机验证以截图为准（回顾页条目与标签 chip 可见即证明落库与筛选生效），DB 结构口径由宿主侧 sqlite_entry_tags_test 锁死。

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
