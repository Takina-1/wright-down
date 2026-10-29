# Android 调试与设备验收

适用范围：在 Windows 上使用 Android 真机调试当前 Flutter 客户端，并完成 F001 本地文字记录的设备验收。

## 1. 准备 Android 设备

1. 在手机中开启“开发者选项”和“USB 调试”。
2. 使用可传输数据的 USB 线连接电脑。
3. 解锁手机；出现 USB 调试授权提示时选择允许。
4. 如设备只显示充电模式，将 USB 用途切换为文件传输后重试。

## 2. 检查设备连接

在普通 PowerShell 中运行：

```powershell
Set-Location D:\dev\myapp\client

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ..\scripts\flutter.ps1 devices
```

设备列表应包含 Android 设备 ID。若状态为 `unauthorized`，解锁手机并接受 USB 调试授权；若没有设备，重新连接 USB 并检查手机的 USB 模式。

## 3. 启动 Flutter 调试

把 `<设备ID>` 替换为上一步显示的 Android 设备 ID：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ..\scripts\flutter.ps1 run -d <设备ID>
```

运行期间常用按键：

- `r`：热重载。
- `R`：完全重启应用。
- `q`：结束调试。

终端会显示 Flutter 异常、数据库错误和生命周期日志。需要查看 Android 系统日志时运行：

```powershell
D:\dev\myapp\.tooling\android-sdk\platform-tools\adb.exe logcat
```

## 4. 安装已有调试 APK

不需要热重载时，可以直接安装已构建的调试包：

```powershell
D:\dev\myapp\.tooling\android-sdk\platform-tools\adb.exe install -r `
  D:\dev\myapp\client\build\app\outputs\flutter-apk\app-debug.apk
```

`-r` 表示保留应用数据并覆盖安装。调试 APK 使用开发签名，不是正式发布包。

## 5. F001 设备验收

按顺序执行并把设备型号、Android 版本和实际结果写入 [F001 测试报告](test-reports/F001-本地记录测试报告-local-entry-test-report.md)：

1. 安装并启动应用，确认进入文字记录页。
2. 开启飞行模式，输入中文和换行，等待出现“已保存”。
3. 点击“下一条”，输入第二条记录。
4. 进入“回顾”，确认两条记录分别存在。
5. 编辑其中一条并返回回顾，确认原记录被更新且没有重复条目。
6. 完全退出并重新启动应用，确认正文和记录时间仍然存在。
7. 检查软键盘、系统返回、切到后台再恢复的行为。
8. 打开“我的 → 本地数据说明”，确认本地存储和数据丢失说明可见。

失败时记录操作步骤、预期结果、实际结果和终端日志；修复后重测同一场景。未执行的项目不能记为通过。

## 6. ADB 配置目录权限错误

当前受限执行环境曾出现：

```text
Cannot mkdir '\.android': Permission denied
```

优先在本机普通 PowerShell 中运行调试命令。如果仍然报错，执行：

```powershell
New-Item -ItemType Directory -Force D:\dev\myapp\.local\android-user
New-Item -ItemType Directory -Force D:\dev\myapp\.local\.android

$env:ANDROID_USER_HOME = 'D:\dev\myapp\.local\android-user'
$env:ANDROID_SDK_HOME = 'D:\dev\myapp\.local'

$adbPath = 'D:\dev\myapp\.tooling\android-sdk\platform-tools\adb.exe'
& $adbPath kill-server
& $adbPath start-server
& $adbPath devices -l
```

若错误仍然存在，保存上述命令的完整输出，并检查当前 PowerShell 用户是否能写入 `D:\dev\myapp\.local`。不要把设备验收标为通过。

## 7. 提交调试结果

设备验收完成后：

1. 更新 `docs/test-reports/F001-本地记录测试报告-local-entry-test-report.md` 的设备、系统版本和逐项结果。
2. 若必需场景全部通过，将 `docs/features/README.md` 中 F001 推进到“待验收”；仍有失败项时保持“待测试”并记录缺陷。
3. 只有验收证据齐全且没有阻塞问题时，才可将功能标为“已完成”。
