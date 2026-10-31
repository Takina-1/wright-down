# 功能任务台账

从 [功能模板](../templates/功能需求模板-feature-spec-template.md) 创建需求与方案，再登记到本表。流程与命名见 [开发规范](../开发流程-development-workflow.md)。

下一可用编号为 `F013`。模板中的例子不代表已经立项。

| 编号 | 功能名称 | 优先级 | 状态 | 需求与方案 | 测试报告 | 阻塞项／下一步 |
|---|---|---|---|---|---|---|
| F001 | 本地文字记录 | P0 | 待验收 | [需求与方案](F001-本地记录-local-entry.md) · [计划](F001-本地记录计划-local-entry-plan.md) | [测试报告](../test-reports/F001-本地记录测试报告-local-entry-test-report.md) | 全量 27 项测试与分析通过；OnePlus PLZ110（Android 16）真机验收 8 步全部通过；极长正文受 CursorWindow 限制的行为仍未验证 |
| F002 | 特性分支开发流程 | P0 | 已完成 | [需求与方案](F002-特性分支流程-feature-branch-workflow.md) | [测试报告](../test-reports/F002-特性分支流程测试报告-feature-branch-workflow-test-report.md) | 验证通过，已通过合并提交 `c3fab3b` 合并到 `main` |
| F003 | 保留已合并的特性分支 | P0 | 已完成 | [需求与方案](F003-保留特性分支-retain-feature-branches.md) | [测试报告](../test-reports/F003-保留特性分支测试报告-retain-feature-branches-test-report.md) | 合并提交 `5e16b0d` 后确认 F003 分支仍存在；规则与回归检查通过 |
| F004 | 导出与备份恢复 | P1 | 待验收 | [需求与方案](F004-导出与备份恢复-export-and-backup.md) · [计划](F004-导出与备份恢复计划-export-and-backup-plan.md) | [测试报告](../test-reports/F004-导出与备份恢复测试报告-export-and-backup-test-report.md) | 宿主验证通过：静态分析无问题、91 项自动化测试通过、调试 APK 构建成功；真机验收 11 类通过（SAF 保存与选择、分享面板、取消行为、损坏文件拒绝、合并恢复、幂等、离线导出），仅 1000 条量级未执行 |
| F005 | 删除记录与回收站 | P1 | 待测试 | [需求与方案](F005-删除记录与回收站-entry-delete-and-trash.md) · [计划](F005-删除记录与回收站计划-entry-delete-and-trash-plan.md) | [测试报告](../test-reports/F005-删除记录与回收站测试报告-entry-delete-and-trash-test-report.md) | 宿主侧通过：静态分析无问题、235 项自动化测试通过、调试 APK 构建通过；代码随 F006 合并进入 main（F006 分支自 F005 开出）；**真机验收仍未执行**，需连上手机后补做 |
| F006 | 心情打卡 | P1 | 已完成 | [需求与方案](F006-心情打卡-mood-checkin.md) · [计划](F006-心情打卡计划-mood-checkin-plan.md) | [测试报告](../test-reports/F006-心情打卡测试报告-mood-checkin-test-report.md) | 真机验收（Xiaomi 2211133C / Android 15）已执行并合并到 main：AC-01~AC-03、AC-05~AC-12 通过，含 schema v2→v3 升级与幂等、备份导出与旧备份导入、小屏布局；AC-04 位置偏差（时间轴 emoji 实现在正文左侧，与「正文上方」不符）经用户 2026-10-31 接受并暂缓处置；已通过合并提交 `ea2d7b8` 合并到 `main` |
| F007 | 连续天数 | P1 | 已完成 | [需求与方案](F007-连续天数-consecutive-days.md) | [测试报告](../test-reports/F007-连续天数测试报告-consecutive-days-test-report.md) | 宿主侧静态分析无问题、301 项测试通过、调试 APK 构建通过；Xiaomi 2211133C（Android 15）真机验收 AC-01~AC-11 全部通过。真机验收发现并修复缺陷 D-01（`current` 恒为 0，根因是 `today` 带时刻而 `dayKey` 是 naive 日历日），已补 4 项带时刻的回归测试；已通过合并提交 `0d75fda` 合并到 `main` |
| F008 | 随机一篇 | P1 | 待开发 | [需求与方案](F008-随机一篇-random-entry.md) | — | 回顾模块 v1 集合最后一块，纯本地随机抽一篇；产品设计 §11 已规划回顾页顶部「🎲随便看看」卡片 |
| F009 | 标签 | P1 | 待开发 | [需求与方案](F009-标签-tags.md) | — | 给 Entry 加 tags 字段，涉及 schema 迁移；标签增删改 + 按标签筛选 |
| F010 | 随手拍 | P1 | 待开发 | [需求与方案](F010-随手拍-photos.md) | — | 照片关联到条目，涉及图片存储与 schema 迁移 |
| F011 | 热力图 | P1 | 待开发 | [需求与方案](F011-热力图-heatmap.md) | — | 日历热力图，放统计页做辅助；依赖 dayKey 聚合（已有） |
| F012 | 语音输入 | P1 | 待办 | [需求与方案](F012-语音输入-voice-input.md) | — | 端侧录音 + ASR + 云端精修；涉及合规（麦克风权限、隐私弹窗、国内 ASR 选型），暂不处理，仅记录待办 |

状态：待明确、待开发、开发中、待测试、待验收、已完成、阻塞、已取消。新增功能后更新下一可用编号；状态只在此表维护。
