# 本地日记客户端

Flutter Android 开发预览版：本地文字记录、停输 1 秒自动保存、按月分组的回顾列表、已有记录编辑，以及导出与备份恢复（JSON 备份、Markdown 可读导出、从备份合并恢复）。

入口：[环境与命令](../docs/开发环境-development-environment.md) · [F001 需求](../docs/features/F001-本地记录-local-entry.md) · [计划](../docs/features/F001-本地记录计划-local-entry-plan.md) · [测试报告](../docs/test-reports/F001-本地记录测试报告-local-entry-test-report.md) · [F004 需求](../docs/features/F004-导出与备份恢复-export-and-backup.md) · [F004 测试报告](../docs/test-reports/F004-导出与备份恢复测试报告-export-and-backup-test-report.md)。

在当前 `client` 目录运行：

```powershell
..\scripts\flutter.ps1 pub get
..\scripts\flutter.ps1 analyze
..\scripts\flutter.ps1 test
..\scripts\flutter.ps1 build apk --debug
..\scripts\flutter.ps1 devices
..\scripts\flutter.ps1 run -d <Android设备ID>
```

## 依赖

除 Flutter SDK 自带项外，`pubspec.yaml` 中的依赖及用途：

| 依赖 | 用途 |
|---|---|
| `sqflite` | Android 端 SQLite 存储（应用运行时使用） |
| `sqflite_common` | sqflite 的跨平台抽象层，配合 `sqflite` 使用 |
| `sqflite_common_ffi`（dev） | 宿主测试用 SQLite FFI，让测试跑在真实 SQLite 文件上 |
| `file_picker` | 导出时弹出系统保存对话框，把字节写入用户选定位置（`file_selector` 在 Android 上没有实现保存接口） |
| `file_selector` | 恢复时打开系统文件选择器读取备份文件内容 |
| `share_plus` | 调用系统分享面板，把导出的文件发给其他应用 |
| `path_provider` | 取应用缓存目录，作为分享时临时文件的位置 |
| `path` | 拼接临时文件路径等字符串处理 |
| `uuid` | 生成条目 ID |

`file_picker`、`file_selector`、`share_plus`、`path_provider` 都不申请运行时权限。

## 代码入口

| 路径 | 职责 |
|---|---|
| `lib/main.dart` | 本地存储路径与依赖装配 |
| `lib/app.dart` | 应用主题与根页面 |
| `lib/src/domain/` | 无框架依赖的数据模型与仓储接口 |
| `lib/src/domain/export/` | 备份文档、编解码、Markdown 渲染、恢复预览与文件出口接口 |
| `lib/src/data/local/` | SQLite 存储、更新、游标分页、全量导出与合并导入 |
| `lib/src/platform/` | SAF 保存、选择文件与系统分享的实现 |
| `lib/src/ui/` | 自动保存状态、记录页、回顾页、本地数据说明、导出与备份页 |
| `test/data/` | 真实 SQLite 文件重开、查询与导入测试 |
| `test/domain/` | 备份编解码、Markdown 渲染与恢复预览测试 |
| `test/ui/` | 自动保存、界面行为与导出恢复测试 |

当前没有账号、语音或云同步功能。导出与备份均为手动操作，不做加密；卸载或清除数据会丢失尚未导出的本地记录。
