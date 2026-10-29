# 测试报告索引

已有测试报告如下，功能是否完成仍以任务台账与必需验收项为准。

使用 [测试报告模板](../templates/测试报告模板-test-report-template.md)，文件名与功能编号对应。报告保留每轮执行结果；功能状态统一维护在 [功能任务台账](../features/README.md)。

| 功能编号 | 报告 | 最新执行日期 | 被测版本 | 测试结论与限制 |
|---|---|---|---|---|
| F001 | [本地文字记录](F001-本地记录测试报告-local-entry-test-report.md) | 2026-10-29 | 0.1.0+1，`main`（`a5107f4` 之后重建的调试包） | 27 项测试、静态分析与 APK 构建通过；OnePlus PLZ110（Android 16）真机验收 8 步全部通过 |
| F002 | [特性分支开发流程](F002-特性分支流程测试报告-feature-branch-workflow-test-report.md) | 2026-10-29 | `feat/F002-feature-branch-workflow` | 规则、链接、分支、格式检查及 27 项回归测试通过 |
| F003 | [保留已合并的特性分支](F003-保留特性分支测试报告-retain-feature-branches-test-report.md) | 2026-10-29 | `feat/F003-retain-feature-branches` | 规则、链接、27 项测试和分析通过；合并后分支保留验证通过 |
| F004 | [导出与备份恢复](F004-导出与备份恢复测试报告-export-and-backup-test-report.md) | 2026-10-29 | `main`（`a5107f4`） | 静态分析、91 项自动化测试与调试 APK 构建通过；真机验收 11 类通过（SAF 保存与选择、分享面板、取消行为、损坏文件拒绝、合并恢复、幂等、离线导出），仅 1000 条量级未执行 |
