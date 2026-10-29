# 功能任务台账

从 [功能模板](../templates/功能需求模板-feature-spec-template.md) 创建需求与方案，再登记到本表。流程与命名见 [开发规范](../开发流程-development-workflow.md)。

下一可用编号为 `F005`。模板中的例子不代表已经立项。

| 编号 | 功能名称 | 优先级 | 状态 | 需求与方案 | 测试报告 | 阻塞项／下一步 |
|---|---|---|---|---|---|---|
| F001 | 本地文字记录 | P0 | 待测试 | [需求与方案](F001-本地记录-local-entry.md) · [计划](F001-本地记录计划-local-entry-plan.md) | [测试报告](../test-reports/F001-本地记录测试报告-local-entry-test-report.md) | 全量 27 项测试与分析通过；ADB 配置目录权限报错，设备验收待执行 |
| F002 | 特性分支开发流程 | P0 | 已完成 | [需求与方案](F002-特性分支流程-feature-branch-workflow.md) | [测试报告](../test-reports/F002-特性分支流程测试报告-feature-branch-workflow-test-report.md) | 验证通过，已通过合并提交 `c3fab3b` 合并到 `main` |
| F003 | 保留已合并的特性分支 | P0 | 已完成 | [需求与方案](F003-保留特性分支-retain-feature-branches.md) | [测试报告](../test-reports/F003-保留特性分支测试报告-retain-feature-branches-test-report.md) | 合并提交 `5e16b0d` 后确认 F003 分支仍存在；规则与回归检查通过 |
| F004 | 导出与备份恢复 | P1 | 待开发 | [需求与方案](F004-导出与备份恢复-export-and-backup.md) | 待创建 | 方案已确认：JSON 完整备份、Markdown 可读导出、SAF 保存加系统分享、按 ID 加修改时间合并恢复、不加密；特性分支 `feat/F004-export-and-backup` 已创建，待实现 |

状态：待明确、待开发、开发中、待测试、待验收、已完成、阻塞、已取消。新增功能后更新下一可用编号；状态只在此表维护。
