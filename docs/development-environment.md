# 本地开发环境

配置日期：2026-10-28。目标：Windows 上开发 Flutter Android 客户端。

## 已配置工具

| 工具 | 版本 | 项目内位置 |
|---|---|---|
| Flutter | 3.47.8 stable | `.tooling/flutter` |
| Dart | 3.13.7，随 Flutter 提供 | `.tooling/flutter/bin` |
| Java | Microsoft OpenJDK 21.0.13.0.2 | `.tooling/java/jdk-21.0.13.0.2+1` |
| Android SDK | Platform 36 / Build Tools 36.0.0 | `.tooling/android-sdk` |
| Android NDK | 28.2.13676358 | `.tooling/android-sdk/ndk` |

SDK 不依赖全局 PATH。`scripts/toolchain.ps1` 只为当前进程设置环境，将 Pub、Gradle 与 Android 用户配置放在 `.local/`，工具和缓存均被根 `.gitignore` 排除。

## 日常命令

在项目根目录的 PowerShell 中执行：

```powershell
Set-Location client
..\scripts\flutter.ps1 doctor -v
..\scripts\flutter.ps1 pub get
..\scripts\dart.ps1 format lib test
..\scripts\flutter.ps1 analyze
..\scripts\flutter.ps1 test
..\scripts\flutter.ps1 build apk --debug
..\scripts\flutter.ps1 devices
..\scripts\flutter.ps1 run -d <设备ID>
```

`<设备ID>` 替换为 `devices` 列出的 Android 设备 ID。当前未连接 Android 设备，Windows/Edge 设备不代表 Android 已可运行。此工程仅生成 Android 平台目录。

调试 APK 的默认输出位置为 `client/build/app/outputs/flutter-apk/app-debug.apk`，只有构建成功时该文件才可用于安装。调试包带开发用网络权限供 Flutter 工具连接，不等同于发布包；本功能没有业务网络请求。

## 更换电脑时如何恢复

工具目录未纳入源码，需要重新安装：

1. 按 [Flutter 官方安装指南](https://docs.flutter.dev/install/manual) 下载指定版本 Windows SDK，解压到 `.tooling/flutter`。本次下载使用 Flutter 中国镜像，SHA256 与官方发布索引核对一致。
2. 从 [Microsoft OpenJDK 下载页](https://learn.microsoft.com/java/openjdk/download) 获取 JDK 21 Windows ZIP，解压到 `.tooling/java/`。脚本自动寻找其中的 `bin/java.exe`。
3. 从 [Android 开发工具页面](https://developer.android.com/studio) 安装命令行工具到 `.tooling/android-sdk/cmdline-tools/latest`，安装 Platform 36、Build Tools 36.0.0、Platform Tools 和 NDK 28.2.13676358。
4. 运行上面的 doctor、pub get、测试和构建命令。依赖版本由 `client/pubspec.lock` 锁定。

本次 Android Command-line Tools 23 已使用新的 `android.exe`；安装包路径使用斜杠。安装命令示例（项目根目录）：

```powershell
. .\scripts\toolchain.ps1
& "$env:ANDROID_HOME/cmdline-tools/latest/bin/android.exe" --no-metrics --sdk=$env:ANDROID_HOME sdk install 'platform-tools' 'platforms/android-36' 'build-tools/36.0.0' 'ndk/28.2.13676358'
```

安装器在本机曾因删除 NDK 解压临时目录失败返回非零状态，不能仅凭安装器退出码判断安装是否完整；需检查 SDK 文件并实际构建。

Gradle Wrapper 使用腾讯镜像的 9.3.1 bin ZIP，`distributionSha256Sum` 固定为从 Gradle 官方校验入口取得的 `b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06`。这是为解决官方分发重定向到 GitHub 后的连接失败；不会跳过完整性校验。

Android 项目仓库配置为 Flutter 引擎依赖只查询 Flutter 仓库，其余 Maven Central 依赖优先使用阿里云 central HTTPS 镜像，保留原仓库作为后备。原因是本机首次构建出现 Maven Central DNS 解析失败。未来在其他网络环境下调整仓库时，应保持 Flutter 依赖分组与版本约束。

`sqflite_common_ffi` 只用于宿主测试，但它的 sqlite3 原生资源 hook 也会参与 Android 构建。因此 pubspec 按 sqlite3 官方的分平台配置，将 Android 的 hook source 设置为 system，避免下载未使用的 FFI SQLite；宿主测试仍使用默认的校验二进制。实际 Android 应用通过 sqflite 平台插件访问数据库，不导入 sqlite3 FFI。未来若在应用中引入 FFI，需要重新评估 Android 原生库可用性，不能沿用此配置作为可用性保证。

## 工程约定

- 应用显示名称暂为“本地日记”，开发包名为 `dev.localdiary.local_diary`；正式名称、包名和签名待发布前确定。
- 当前使用 `client/lib/src/` 四层目录与 `client/test/`。早期通用骨架中的 `client/src/`、`client/tests/` 已迁移，不作为源码入口。
- 当前未初始化 Git，不存在已提交版本。开始使用版本控制时，应保留根和客户端 `.gitignore`，提交 `pubspec.lock`，不要提交 SDK、缓存或真实日记。
- Android 工具链检查不要求 Web Chrome 或 Windows C++ 桌面工具链通过；这些平台不属于 F001。
