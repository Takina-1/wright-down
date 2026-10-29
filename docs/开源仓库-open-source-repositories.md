# 开源日记 App 参考仓库

记录日期：2026-10-28。

开发时先查：[功能实现参考索引](功能参考索引-feature-reference-index.md)，包含按功能选仓库、源码检索词、适配流程及设计调整建议。本文保留仓库基本资料与来源。

用于后续实现 [产品与架构设计](产品设计-product-design.md) 中的功能。以下功能信息来自本次查阅的官方仓库 README、官方文档和许可证；尚未下载运行或审查源码。参考方向是本项目的评估，不代表对应实现已经验证。

这些仓库作为功能与实现参考，尚未决定采用某个项目作为基础，客户端现已选择 Flutter，服务端技术尚未确定。现有架构约束和 [上架合规清单](OPPO上架清单-oppo-release-checklist.md) 继续作为本项目的设计依据；其中平台合规规则仍需按提交时的官方要求核验。

## 仓库清单

| 项目 | 官方仓库 | 技术栈 | 官方说明中的相关能力 | 优先参考方向 | 仓库声明的许可证 |
|---|---|---|---|---|---|
| Moodiary | [ZhuJHua/moodiary](https://github.com/ZhuJHua/moodiary) | Flutter + Rust | 离线日记、富文本、图片/音频/视频、全文搜索、分类、WebDAV 与 S3/MinIO 同步、局域网传输、可选端到端加密、导入导出 | 综合功能、本地搜索、附件处理、同步与备份 | AGPL-3.0 |
| StoryPad | [theachoem/storypad](https://github.com/theachoem/storypad) | Flutter | 时间轴、往年今日、心情历史与日历、图片、标签、搜索、语音记录、Google Drive 同步、本地导出；部分功能列为 Pro 功能 | 生活流时间轴、回顾交互、心情记录、语音记录体验 | GPL-3.0 |
| Daily You | [Demizo/Daily_You](https://github.com/Demizo/Daily_You) | Flutter | 离线记录、心情追踪、照片、Markdown、自选存储位置、备份导入；无需账号 | 纯本地模式、轻量记录、心情和照片体验 | GPL-3.0 + 附加条款 |
| Jiyi／记忆 | [xiaoshihou514/jiyi](https://github.com/xiaoshihou514/jiyi) | Flutter + sherpa-onnx | 本地语音识别、加密语音日志、录音位置记录 | 端侧录音与识别、音频管理、本地加密 | GPL-3.0 |
| DiaryVault | [SankethBK/diaryvault](https://github.com/SankethBK/diaryvault) | Flutter | 富文本、图片/视频/录音、自动保存、标签、云备份与多设备同步、PIN/指纹锁、文本/PDF 导出 | 自动保存、编辑器、标签、导出；可进一步评估为二次开发基础 | MIT |

## 与本项目功能的对应关系

| 本项目需求 | 优先查看 | 读源码或体验时要确认的内容 |
|---|---|---|
| Phase 1：本地记录、离线可用 | Daily You、DiaryVault | 本地数据模型、写入入口、错误处理、重启后恢复；是否符合我们的分层约束 |
| 停输后自动保存、退出保护 | DiaryVault | 保存时机、草稿与正式条目边界、并发写入、应用被终止时的数据恢复；不要假定它采用我们的 1 秒策略 |
| 时间轴与日记详情 | StoryPad、Moodiary | 时间分组、列表分页、附件加载、编辑返回后的列表更新；是否使用 Keyset 分页待查 |
| 语音优先与离线转写 | Jiyi | 录音生命周期、权限时机、识别模型、中文识别效果、模型体积、耗电和低端机性能 |
| 音频附件与回放 | Jiyi、StoryPad、DiaryVault | 音频文件和条目的关联、播放状态、删除清理；本项目是否提供回放仍按设计中的待定项处理 |
| 心情、照片与标签 | Daily You、StoryPad、DiaryVault | 快捷输入、筛选、编辑和删除、附件引用；避免将丰富功能全部搬到首页 |
| 回顾、连续天数、热力图 | StoryPad、Daily You | 参考已有回顾和心情日历交互；随机一篇、连续天数算法与热力图实现是否存在需另查，不能视为已具备 |
| 本地搜索 | Moodiary | 全文索引、中文搜索、索引更新、结果跳转；官方文档介绍了 SQLite FTS5 |
| 云同步、附件上传与备份 | Moodiary、DiaryVault、StoryPad | 同步协议、冲突策略、删除传播、重试、附件去重、备份恢复；不假定其具备我们的字段级 LWW 或服务端 seq 游标 |
| 导入导出与迁移 | DiaryVault、Moodiary、Daily You | 导出格式、附件打包、导入去重、版本兼容、失败恢复 |
| 本地隐私与应用锁 | Jiyi、Moodiary、DiaryVault、StoryPad | 密钥保存、解锁流程、加密覆盖范围；应用锁不等同于数据加密 |

## 参考边界与待核实事项

- 端侧转写、云端精修、用户确认替换这一完整链路，目前没有确认上述任何项目已全部实现。
- Jiyi 的端侧识别使用 sherpa-onnx，可作为研究入口；具体模型和中文效果需要实测。
- StoryPad 的 Google Drive 同步不直接等同于我们计划的国内 OSS + 自建同步 API。DiaryVault 的 README 与发布说明对 Google Drive 支持存在差异，需以选定版本源码和运行结果为准。
- 账号认领、设备管理、找回密码、令牌吊销和注销数据清除等能力，尚未确认可从这些项目复用。
- 国内市场上架所需的隐私弹窗、录音单独同意、权限撤回、备案信息展示和删除期限，需要针对我们的实际实现检查。
- 分别评估交互参考、架构参考和源码复用。实际引入源码前，应记录来源路径、提交 SHA、修改内容及适用许可，并核对依赖、模型和素材许可证。
- Daily You 还有明确的附加条款，涉及修改版本的名称、应用 ID、来源说明与署名。不要只看 GitHub 的 GPL 标签。

## 后续查阅顺序

1. 开发本地记录时，先看 Daily You 和 DiaryVault。
2. 开发时间轴与回顾时，先看 StoryPad。
3. 开发语音输入时，先看 Jiyi。
4. 开发搜索、同步与导出时，再深入 Moodiary 及 DiaryVault。

每次深入评估时补充所查看的分支/提交 SHA、源码路径、实测结果与最终取舍；当前清单未锁定代码版本。

## 补充来源

- [Moodiary 官方功能介绍](https://docs.moodiary.net/guide/)
- [Moodiary 官方首页：本地 SQLite 与全文搜索](https://docs.moodiary.net/)
- [DiaryVault MIT 许可证](https://github.com/SankethBK/diaryvault/blob/master/license.md)
- [DiaryVault 发布记录](https://github.com/SankethBK/diaryvault/releases)
- [Daily You 附加条款](https://github.com/Demizo/Daily_You/blob/master/ADDITIONAL_TERMS.md)
