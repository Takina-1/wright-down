# wright-down

语音优先、方便回顾生活的本地优先日记应用。

## 项目目录

```text
client/                 客户端
  lib/src/
    ui/                 页面、组件与界面状态
    domain/             实体、仓储接口、用例与回顾逻辑；不依赖框架或 SDK
    data/
      local/            本地数据库与 LocalRepo
      remote/           HTTP 接口与 RemoteRepo
      sync/             同步引擎、脏队列与冲突合并
    platform/           录音、语音识别、相机与系统权限适配
  assets/               图片、字体等静态资源
  test/                 客户端测试
  android/              Android 工程
scripts/                项目内 Flutter / Dart 命令入口
server/
  src/                  账号、同步接口与存储实现
  tests/                服务端测试
deploy/                 Docker Compose、Nginx 等部署配置
docs/                   产品设计、开发流程、功能需求、测试报告与参考资料
AGENTS.md               AI 开发助手的项目工作约定
CLAUDE.md               Claude 开发助手的项目工作约定
```

客户端已初始化为 Flutter Android 工程，F001 实现本地文字记录、自动保存和回顾列表，F004 实现导出与备份恢复：可以把全部记录导出成可恢复的 JSON 备份文件，或导出成按日期分组的 Markdown 供阅读，也可以从备份文件合并恢复到本机（按条目 ID 与修改时间合并，本机较新的记录不会被覆盖）。入口在「我的 → 导出与备份」。备份与 Markdown 均为明文、不做加密。服务器暂未实现。开发工具与运行命令见 [开发环境说明](docs/开发环境-development-environment.md)，验收状态以功能台账和测试报告为准。

在 PowerShell 中运行检查：

```powershell
Set-Location client
..\scripts\flutter.ps1 analyze
..\scripts\flutter.ps1 test
..\scripts\flutter.ps1 build apk --debug
```

其中 `test` 运行全部自动化测试，`build apk --debug` 生成调试安装包。

连接开启 USB 调试的 Android 设备后，使用 `..\scripts\flutter.ps1 devices` 查看设备，再执行 `..\scripts\flutter.ps1 run -d <设备ID>`。

当前已构建的调试包：`client/build/app/outputs/flutter-apk/app-debug.apk`。具体测试结果、校验值和手机验收步骤见 [F001 测试报告](docs/test-reports/F001-本地记录测试报告-local-entry-test-report.md) 与 [F004 测试报告](docs/test-reports/F004-导出与备份恢复测试报告-export-and-backup-test-report.md)。

## 架构约定

- 本地数据库是唯一真相源；用户写入走 LocalRepo，同步异步执行。
- UI 不直接访问 RemoteRepo；Domain 不导入框架或 SDK。
- 回顾与统计在客户端计算。
- 先实现本地记录、时间轴与隐私页，再逐步加入语音、回顾和云同步。

空目录使用 `.gitkeep` 占位，便于后续纳入 Git 管理。

## 开发入口

从 [文档总索引](docs/README.md) 开始。流程为：明确需求与验收标准 → 查询参考实现 → 拆分任务并开发 → 测试与修复 → 验收归档 → 发布。

- [开发流程与命名规范](docs/开发流程-development-workflow.md)
- [开发环境与实际命令](docs/开发环境-development-environment.md)
- [功能任务台账](docs/features/README.md)
- [测试报告索引](docs/test-reports/README.md)
- [产品与架构设计](docs/产品设计-product-design.md)
- [功能实现参考索引：开发某个功能先查谁、套用什么逻辑](docs/功能参考索引-feature-reference-index.md)
- [开源仓库资料](docs/开源仓库-open-source-repositories.md)
- [OPPO 上架合规清单](docs/OPPO上架清单-oppo-release-checklist.md)
