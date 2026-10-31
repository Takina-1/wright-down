# 测试报告索引

已有测试报告如下，功能是否完成仍以任务台账与必需验收项为准。

使用 [测试报告模板](../templates/测试报告模板-test-report-template.md)，文件名与功能编号对应。报告保留每轮执行结果；功能状态统一维护在 [功能任务台账](../features/README.md)。

| 功能编号 | 报告 | 最新执行日期 | 被测版本 | 测试结论与限制 |
|---|---|---|---|---|
| F001 | [本地文字记录](F001-本地记录测试报告-local-entry-test-report.md) | 2026-10-29 | 0.1.0+1，`main`（`a5107f4` 之后重建的调试包） | 27 项测试、静态分析与 APK 构建通过；OnePlus PLZ110（Android 16）真机验收 8 步全部通过 |
| F002 | [特性分支开发流程](F002-特性分支流程测试报告-feature-branch-workflow-test-report.md) | 2026-10-29 | `feat/F002-feature-branch-workflow` | 规则、链接、分支、格式检查及 27 项回归测试通过 |
| F003 | [保留已合并的特性分支](F003-保留特性分支测试报告-retain-feature-branches-test-report.md) | 2026-10-29 | `feat/F003-retain-feature-branches` | 规则、链接、27 项测试和分析通过；合并后分支保留验证通过 |
| F004 | [导出与备份恢复](F004-导出与备份恢复测试报告-export-and-backup-test-report.md) | 2026-10-29 | `main`（`a5107f4`） | 静态分析、91 项自动化测试与调试 APK 构建通过；真机验收 11 类通过（SAF 保存与选择、分享面板、取消行为、损坏文件拒绝、合并恢复、幂等、离线导出），仅 1000 条量级未执行 |
| F005 | [删除记录与回收站](F005-删除记录与回收站测试报告-entry-delete-and-trash-test-report.md) | 2026-10-30 | `feat/F005-entry-delete-and-trash`（`5d18c02`） | 宿主侧：静态分析无问题、235 项自动化测试通过、调试 APK 构建通过；**真机验收未执行**（测试时设备未连接） |
| F006 | [心情打卡](F006-心情打卡测试报告-mood-checkin-test-report.md) | 2026-10-31 | `main`（合并提交 `ea2d7b8`） | 静态分析无问题、275 项自动化测试通过、调试 APK 构建通过；Xiaomi 2211133C（Android 15）真机验收已执行：AC-01~AC-03、AC-05~AC-12 通过，AC-04 位置偏差（emoji 在正文左侧而非上方）经用户接受暂缓 |
| F007 | [连续天数](F007-连续天数测试报告-consecutive-days-test-report.md) | 2026-10-31 | `feat/F007-consecutive-days` | 宿主侧：静态分析无问题、301 项自动化测试通过（含 4 项带时刻的回归测试）、调试 APK 构建通过；Xiaomi 2211133C（Android 15）真机验收 AC-01~AC-11 全部通过。真机验收发现并修复缺陷 D-01（`current` 恒为 0，根因是 `today` 带时刻而 `dayKey` 是 naive 日历日） |
| F008 | [随机一篇](F008-随机一篇测试报告-random-entry-test-report.md) | 2026-11-01 | `feat/F008-random-entry` | 宿主侧：静态分析无问题、314 项自动化测试通过（新增 6 域层 + 7 组件）、调试 APK 构建通过；Xiaomi 2211133C（Android 15）真机验收 AC-01~AC-08 全部通过。实现中修复 3 项缺陷（D-01 文本撞车、D-02 布局溢出、D-03 换一篇排除失效） |
