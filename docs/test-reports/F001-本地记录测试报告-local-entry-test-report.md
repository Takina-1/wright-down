# F001：本地文字记录测试报告

- 关联需求：[F001 本地记录](../features/F001-本地记录-local-entry.md)
- 关联计划：[开发计划](../features/F001-本地记录计划-local-entry-plan.md)
- 代码状态：2026-10-28 当前工作区；未初始化 Git，没有提交 SHA。
- 本报告区分宿主自动化验证、Android 构建和真机验收。

## 第 1 轮：测试先行

在仓储和控制器仅有接口骨架、页面未实现时运行 `flutter test --reporter expanded`，14 项测试未通过：持久化未实现、自动保存未发生、导航与页面缺失。随后实施功能。

自动保存实现后的慢写入测试发现遗留 debounce 定时器：新输入在串行保存循环内已经持久化，但其定时器仍未取消。修复完成和失败路径的定时器清理后，底层 10 项测试通过。

## 第 2 轮：实现后验证

环境：Windows 10 Pro 1909；Flutter 3.47.8；Dart 3.13.7；sqflite 2.4.5、sqflite_common 2.5.14；宿主 SQLite 测试使用 sqflite_common_ffi 2.4.5。所有测试数据均为合成内容。

以下命令在 `client` 中通过项目脚本执行：

| 检查 | 命令 | 实际结果 |
|---|---|---|
| 格式化 | `../scripts/dart.ps1 format lib test` | 已完成格式化 |
| 静态分析 | `../scripts/flutter.ps1 analyze` | No issues found |
| 自动化测试 | `../scripts/flutter.ps1 test --reporter expanded` | 17 项通过，0 项失败 |
| 工具链 | `../scripts/flutter.ps1 doctor -v` | Flutter、Android SDK、Java 通过；非目标平台 Chrome 与 Windows C++ 检查未通过 |
| Android APK | `../scripts/flutter.ps1 build apk --debug` | 最后一次构建通过，153.9 秒，产物已核验 |

### 测试覆盖

| 范围 | 验收项 | 已验证场景 | 结果 |
|---|---|---|---|
| SQLite 文件存储（4 项） | AC-02、03、06、07、08 | 中文/换行/emoji 重开恢复；同 ID 更新与时间；相同时间游标分页；拒绝空内容覆盖 | 宿主测试通过 |
| 编辑控制器（6 项） | AC-01、03、04、05、06、07 | 最后输入后 1 秒保存；空白不建条目；失败阻止下一条并可重试；慢写入期间新内容；编辑保留身份；清空已有正文保护 | 通过 |
| Flutter 界面（7 项） | AC-01、04、05、06、07、09 | 输入/保存/回顾/编辑闭环；空状态；失败阻止导航与重试；读取失败重试；后台立即保存；返回失败继续编辑；小屏键盘布局 | 组件测试通过 |

“后台”和“系统返回”使用 Flutter 测试框架模拟事件，不能替代 Android 真机行为验证。

## 独立审查

按 requesting-code-review 技能进行只读审查，没有发现确定的阻塞代码缺陷；检查了串行保存、新输入保护、导航、游标分页及 Android 备份排除。

审查提出 `PRAGMA busy_timeout` 使用 execute 的兼容性疑问。已读取本地锁定版本 sqflite_android 2.4.5 的 `Database.java`：其 execSQL 捕获返回行的 PRAGMA 错误后会按查询执行，因此不认定当前版本存在已复现缺陷。直接改用 rawQuery 属于可后续整理的小项，本轮未改动。

审查未判断的事项由以下验收安排承接：真机 SQLite 与持久化、硬件返回/后台/键盘、OEM 备份行为、实际 APK 构建、极长正文受 CursorWindow 限制的行为。未执行的部分不算通过；极长正文边界记录为当前未验证限制，发布前补充。

## Android 构建产物

- 路径：`client/build/app/outputs/flutter-apk/app-debug.apk`
- 文件大小：150,915,655 字节（约 143.9 MiB，含三个 ABI 的调试包）。
- SHA256：`81fb53e4862e4ec5a6466f1a6733ce22769f08f3154f6572f460c40c9e11526b`
- 版本：0.1.0+1；显示名称：本地日记；包名：`dev.localdiary.local_diary`。
- minSdk 24，targetSdk 36；包含 arm64-v8a、armeabi-v7a、x86_64。
- 使用 aapt 核对权限：调试用 INTERNET 与应用内部接收器权限；无麦克风、相机、相册或外部存储读取权限。
- 此为调试签名开发包，不是正式上架包。

## 尚未完成的必需验证

- Android 真机或模拟器安装启动，断网写入，退出并重启后读取。
- 真机键盘、返回、后台与强杀边界；卸载或清除数据前需明确数据会丢失。

当前没有连接 Android 设备，自动化测试没有替代上述验证。F001 暂不标记“已完成”。

### 2026-10-29 待办与设备检查

- [ ] 使 ADB 能正常列出 Android 设备：当前执行 `flutter devices` 时，ADB 报 `Cannot mkdir '\.android': Permission denied`；项目内已配置 `ANDROID_USER_HOME`，单次设置 `ANDROID_SDK_HOME` 后仍复现。PowerShell 脚本执行策略可通过仅对该进程使用 `-ExecutionPolicy Bypass` 运行，不是设备验收本身的结果。
- [ ] 连接 Android 真机并启用 USB 调试，或安装并启动 Android 模拟器；当前项目 SDK 未安装 emulator 组件。
- [ ] 按下列步骤执行设备验收，记录设备型号、Android 版本、APK 标识、逐项实际结果及缺陷复测结果。
- [x] 整理已纳入版本控制的 `client/test/ui/zz_probe*_test.dart` 与 `client/test/zz_probe_temp_test.dart` 探针：详情页探针先返回主页再点击记录入口；启动探针改用同步临时目录，并只验证仓储延迟打开，避免在组件虚拟异步环境中等待文件 I/O。全量 27 项测试通过。
  - 后续：这些探针在 F004 收尾时进一步清理——4 个只打印不断言的文件已删除，`zz_probe_temp_test.dart` 改名保留为 `client/test/data/sqlite_startup_failure_test.dart`，详见 [F004 测试报告](F004-导出与备份恢复测试报告-export-and-backup-test-report.md)。
- [x] 修正探针文件的两处静态分析问题：移除多余和未使用的导入；`flutter analyze` 通过，0 问题。
- [ ] 完成设备验收后更新本报告与功能台账；在此之前维持“待测试”。

本轮已完成的下一步：使用 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\scripts\flutter.ps1` 运行测试与分析。原有三个正式测试文件共 17 项通过；整理探针后，全量 27 项测试通过、退出码 0；`flutter analyze` 显示 `No issues found`、退出码 0。此次未重新构建 APK，也未完成设备验收。

连接设备后的验收步骤：

1. 安装本次调试 APK，确认打开进入文字记录页。
2. 开启飞行模式，输入中文和换行，等待“已保存”。
3. 点击下一条，再写一条；进入回顾，确认两条分别存在。
4. 编辑其中一条，返回回顾，确认没有生成重复条目。
5. 保存成功后退出并重新启动，确认正文完整。
6. 检查键盘、返回、切到后台再恢复，以及“我的 → 本地数据说明”。
7. 记录设备型号、Android 版本、实际结果；失败则追加复现步骤，不将未执行写成通过。

## 环境问题与处置

- 初始缺少 Flutter、Java 和 Android SDK，已安装到项目 `.tooling/`。
- Flutter 官方 ZIP 通过 SHA256 校验；下载镜像与环境变量见开发环境说明。
- Android SDK 新版 CLI 在 NDK 解压后的临时目录清理阶段报错；已检查 NDK source.properties 与 clang.exe，最终有效性仍以 APK 构建结果判断。
- Gradle 官方分发重定向到本机不可直连的 GitHub，改用腾讯 Gradle 镜像；9.3.1 bin 分发通过官方提供的 SHA256 约束校验，没有降低 TLS 验证。
- 首次 Android 编译失败于宿主测试依赖 sqlite3 的 Android 原生库下载。按该包官方 hook 配置将未被 Android 应用使用的 FFI 库设为 system，宿主保持默认来源；重新运行测试与构建验证这一配置。
- hook 配置调整后，17 项测试再次通过；随后构建出现 Maven Central DNS 解析失败。配置中央仓库 HTTPS 镜像并将 io.flutter 依赖限定在 Flutter 仓库后继续构建。
- 最后一次构建成功，确认 SDK 安装后的临时清理错误没有阻塞本次 APK。分析复检无问题。

## 当前结论

全量 27 项自动化测试与静态分析在 2026-10-29 通过；此前 Android 调试 APK 构建通过。ADB 配置目录权限问题和 Android 设备验收仍待处理，因此 F001 维持“待测试”。正式签名发布、隐私政策和上架审核不在本次交付范围。
