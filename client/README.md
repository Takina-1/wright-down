# 本地日记客户端

Flutter Android 开发预览版：本地文字记录、停输 1 秒自动保存、按月分组的回顾列表与已有记录编辑。

入口：[环境与命令](../docs/development-environment.md) · [F001 需求](../docs/features/F001-local-entry.md) · [计划](../docs/features/F001-local-entry-plan.md) · [测试报告](../docs/test-reports/F001-local-entry-test-report.md)。

在当前 `client` 目录运行：

```powershell
..\scripts\flutter.ps1 pub get
..\scripts\flutter.ps1 analyze
..\scripts\flutter.ps1 test
..\scripts\flutter.ps1 build apk --debug
..\scripts\flutter.ps1 devices
..\scripts\flutter.ps1 run -d <Android设备ID>
```

## 代码入口

| 路径 | 职责 |
|---|---|
| `lib/main.dart` | 本地存储路径与依赖装配 |
| `lib/app.dart` | 应用主题与根页面 |
| `lib/src/domain/` | 无框架依赖的数据模型与仓储接口 |
| `lib/src/data/local/` | SQLite 存储、更新、游标分页 |
| `lib/src/ui/` | 自动保存状态、记录页、回顾页、本地数据说明 |
| `test/data/` | 真实 SQLite 文件重开与查询测试 |
| `test/ui/` | 自动保存与界面行为测试 |

当前没有账号、语音、云同步或导出功能。仅用于开发体验；卸载或清除数据会丢失本地记录。
