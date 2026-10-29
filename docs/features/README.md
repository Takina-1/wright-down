# 功能任务台账

从 [功能模板](../templates/功能需求模板-feature-spec-template.md) 创建需求与方案，再登记到本表。流程与命名见 [开发规范](../开发流程-development-workflow.md)。

下一可用编号为 `F003`。模板中的例子不代表已经立项。

| 编号 | 功能名称 | 优先级 | 状态 | 需求与方案 | 测试报告 | 阻塞项／下一步 |
|---|---|---|---|---|---|---|
| F001 | 本地文字记录 | P0 | 待测试 | [需求与方案](F001-本地记录-local-entry.md) · [计划](F001-本地记录计划-local-entry-plan.md) | [测试报告](../test-reports/F001-本地记录测试报告-local-entry-test-report.md) | 全量 27 项测试与分析通过；ADB 配置目录权限报错，设备验收待执行 |
| F002 | 特性分支开发流程 | P0 | 已完成 | [需求与方案](F002-特性分支流程-feature-branch-workflow.md) | [测试报告](../test-reports/F002-特性分支流程测试报告-feature-branch-workflow-test-report.md) | 规则、22 个 Markdown 链接、分支和格式检查通过；27 项测试与分析通过，可合并到 `main` |

状态：待明确、待开发、开发中、待测试、待验收、已完成、阻塞、已取消。新增功能后更新下一可用编号；状态只在此表维护。
