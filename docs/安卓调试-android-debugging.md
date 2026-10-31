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

### 2026-10-29 实测

该权限错误在本机不再复现：`adb devices -l` 可直接列出设备并返回 `device` 状态。2026-10-29 晚在 OnePlus PLZ110（Android 16 / SDK 36）上完成了 F001 与 F004 的真机验收，结果见对应的测试报告。设备信息可用 `adb shell getprop ro.build.version.release` 与 `ro.product.model` 取得。

## 7. 调试 APK 签名不一致

设备上已装的包与新构建的 APK 签名不同，`adb install -r` 会失败：

```text
Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package dev.localdiary.local_diary signatures do not match newer version; ignoring!]
```

原因：设备上的包用 `.local/android-user/debug.keystore` 签名，而用默认 `flutter build apk` 构建的包用用户目录下的 `C:\Users\<用户>\.android\debug.keystore` 签名，两者指纹不同。

两种处理方式：

- **保留设备数据**：用与设备一致的 keystore 对新 APK 重签名后覆盖安装。

  ```bash
  export JAVA_HOME="D:\dev\myapp\.tooling\java\jdk-21.0.13.0.2+1"
  ".tooling/android-sdk/build-tools/36.0.0/apksigner.bat" sign \
    --ks ".local/android-user/debug.keystore" --ks-key-alias androiddebugkey \
    --ks-pass pass:android --key-pass pass:android \
    --out .local/tmp/app-debug-resigned.apk \
    client/build/app/outputs/flutter-apk/app-debug.apk
  adb install -r .local/tmp/app-debug-resigned.apk
  ```

  keystore 别名是 `androiddebugkey`，口令 `android`。用 `apksigner verify --print-certs` 可比对证书指纹。

- **清空重来**：`adb uninstall dev.localdiary.local_diary` 后再安装，会丢失设备上的本地记录。

## 8. 安全锁屏会拦截 adb 输入

设备处于 MIU/其他厂商的安全锁屏（图案或指纹）时：

- `adb shell input tap` 与 `input text` 不会送达应用（焦点仍在锁屏窗口）。
- `adb exec-out screencap` 可能返回全黑图（系统对锁屏内容做了遮挡）。
- `adb shell wm dismiss-keyguard` 与 `locksettings set-disabled true` 对 MIUI 的自有锁屏无效。

先确认锁屏状态，`deviceLocked=0` 表示已解锁、输入可以送达：

```bash
adb shell dumpsys trust | grep -oE "deviceLocked=[01]"
adb shell dumpsys window | grep mCurrentFocus
```

`deviceLocked=1` 时需要用户在手机上解锁一次。解锁后 `mCurrentFocus` 应指向应用窗口，输入与截屏都恢复正常。

另外注意：不要用 `KEYCODE_POWER` 反复切换屏幕状态——它是开关语义，屏幕已点亮时按下会把它关掉，后续输入与截屏都会失败。先用 `adb shell dumpsys display | grep "Display State="` 确认状态，只在 `OFF` 时才唤醒。

## 9. 用设备日期构造跨日场景

验证依赖「今天」的逻辑（连续天数、跨月跨年跨闰日）时，可临时调整设备日期构造场景：

```bash
# 设置到指定日期（毫秒时间戳）
adb shell "cmd alarm set-time $(( $(date -d "2026-01-02 10:30" +%s) * 1000 ))"
adb shell date
```

应用读取的是系统时间，改完日期后重启应用即可看到新口径。验收结束后务必把日期改回原值。

## 10. 提交调试结果

设备验收完成后：

1. 更新对应的测试报告，记录设备型号、系统版本和逐项结果。
2. 若必需场景全部通过，将 `docs/features/README.md` 中对应功能推进到“待验收”；仍有失败项时保持“待测试”并记录缺陷。
3. 只有验收证据齐全且没有阻塞问题时，才可将功能标为“已完成”。
4. 验收中若在设备上写入或删除了测试数据，结束后要恢复设备原有数据并逐条校验。
