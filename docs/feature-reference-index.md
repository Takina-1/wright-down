# 功能实现参考索引

更新时间：2026-10-28。

用途：开发某个功能前，先在这里查「看谁 → 搜什么 → 借鉴什么逻辑 → 如何适配 → 如何验证」。

配套：[产品与架构设计](product-design.md) · [仓库资料与许可证](open-source-repositories.md) · [上架合规清单](oppo-release-checklist.md) · [开发流程](development-workflow.md)。

## 使用约定

- 下表是查阅路线，不是源码审查结果。当前五个仓库均仅查阅过公开说明与许可证，未下载运行，未确认具体类名、函数或实现路径。
- 「检索词」用于在目标仓库搜索候选实现，不表示这些符号一定存在。找到实现后，按文末模板补充固定提交的源码链接。
- 「套用逻辑」表示理解流程后适配本项目。直接复制源码需另行检查对应版本、依赖、模型及素材许可。
- 本项目保持本地优先、UI 不直接调用 RemoteRepo、Domain 无框架依赖。表中落点是当前目录骨架中的建议位置，最终随技术栈调整。
- 本文记录了上一轮融合建议；与原设计不同的地方明确列在「设计调整建议」，尚未覆盖原设计或标记为已实现。

## 1. 按功能查仓库

| 要开发什么 | 首选仓库 → 补充仓库 | 建议检索词 | 要研究并适配的逻辑 | 本项目建议落点 |
|---|---|---|---|---|
| 本地日记增删改查、匿名使用 | [Daily You][daily] → [DiaryVault][vault] | `database`、`repository`、`insert`、`update`、`migration` | 条目模型、本地写入、离线读取、升级迁移；按我们的 LocalRepo 接口封装 | `client/lib/src/data/local`、`client/lib/src/domain` |
| 自动保存与草稿恢复 | [DiaryVault][vault] | `autosave`、`debounce`、`draft`、`lifecycle`、`dispose` | 输入变化触发保存、退出时处理、恢复未完成内容；把保存与结束条目区分开 | `client/lib/src/ui`、`client/lib/src/domain`、`client/lib/src/data/local` |
| 时间轴、详情与附件展示 | [StoryPad][story] → [Moodiary][mood] | `timeline`、`story`、`group`、`pagination`、`thumbnail` | 日期分组、长列表加载、缩略图、编辑后的列表刷新；分页按本项目 Keyset 方案实现 | `client/lib/src/ui`、`client/lib/src/data/local` |
| 录音与端侧转写 | [Jiyi][jiyi] | `record`、`recorder`、`sherpa`、`recognizer`、`permission` | 权限、录音生命周期、音频持久化、识别任务、失败恢复；模型与平台依赖隔离到 Platform | `client/lib/src/platform`、`client/lib/src/domain` |
| 音频回放与清理（功能待定） | [Jiyi][jiyi] → [StoryPad][story] | `player`、`audio`、`duration`、`delete` | 播放状态、音频与条目关联、删除清理；实现前确认本项目是否保留回放 | `client/lib/src/platform`、`client/lib/src/data/local` |
| 心情、照片与快捷输入 | [Daily You][daily] → [StoryPad][story] | `mood`、`emotion`、`image`、`picker` | 心情选择、照片导入、附件引用；首页保留一次点击入口 | `client/lib/src/ui`、`client/lib/src/platform` |
| 标签管理与筛选 | [DiaryVault][vault] → [StoryPad][story] | `tag`、`filter`、`search` | 标签关系、重命名、删除和组合筛选；同步时明确标签字段的合并规则 | `client/lib/src/domain`、`client/lib/src/data/local` |
| 回顾卡片与心情日历 | [StoryPad][story] → [Daily You][daily] | `throwback`、`memory`、`calendar`、`mood` | 参考卡片展示和日期导航；随机、连续天数、热力图算法是否存在仍需核查 | `client/lib/src/ui`、`client/lib/src/domain` |
| 本地全文搜索 | [Moodiary][mood] | `FTS5`、`fts`、`tokenizer`、`search` | 索引构建、更新和删除、结果排序；单独验证中文检索效果 | `client/lib/src/data/local`、`client/lib/src/domain` |
| 完整备份与恢复 | [Daily You][daily] → [DiaryVault][vault]、[Moodiary][mood] | `backup`、`restore`、`archive`、`import`、`version` | 正文与附件打包、格式版本、恢复校验、重复导入和失败回滚 | `client/lib/src/domain`、`client/lib/src/data/local`、`client/lib/src/platform` |
| Markdown／PDF 等可阅读导出 | [Moodiary][mood] → [DiaryVault][vault]、[StoryPad][story] | `export`、`markdown`、`pdf`、`attachment` | 正文格式转换、附件路径和日期保留；与完整备份功能分开 | `client/lib/src/domain`、`client/lib/src/platform` |
| 云同步与附件传输 | [Moodiary][mood] → [DiaryVault][vault]、[StoryPad][story] | `sync`、`conflict`、`retry`、`delete`、`webdav`、`s3` | 查任务调度、冲突、重试、删除传播和附件处理；适配我们自己的同步协议 | `client/lib/src/data/sync`、`client/lib/src/data/remote`、`server/src` |
| 应用锁与本地加密 | [Jiyi][jiyi] → [Moodiary][mood]、[DiaryVault][vault] | `encrypt`、`key`、`secure_storage`、`biometric`、`lock` | 区分界面解锁、文件加密和密钥管理；明确哪些数据实际被加密 | `client/lib/src/platform`、`client/lib/src/data/local` |

## 2. 核心链路如何融合

### 文字记录：Daily You 的本地体验 + DiaryVault 的自动保存

建议流程：输入变化 → 延迟保存 → LocalRepo 写入成功 → 显示已保存 → 后台排队同步。

- 未登录和无网络时，记录流程保持可用。
- 停输 1 秒保存来自本项目设计，不是已核实的上游实现。
- 「下一条」负责结束当前条目并开始新条目；自动保存负责持久化。
- 保存失败保留编辑内容并展示原因与重试入口，不显示虚假的已保存状态。
- 验证重点：连续输入、快速切页、应用被系统终止、磁盘不足、重启恢复。

### 语音记录：Jiyi 的端侧链路 + 本项目的云端候选稿

建议流程：按需取得同意和权限 → 开始录音 → 持久化音频 → 端侧转写 → 保存本地文字 → 满足云端授权及开关条件时异步精修 → 用户查看并确认候选稿。

- 录音和识别结果分别管理；识别失败时保留已成功保存的录音，允许重试。
- 用户可以立即修改本地文字，云端结果写入 `cloudTranscript`，确认前不覆盖 `content`。
- 确认精修稿时检查正文是否再次改变，防止旧结果覆盖用户的新编辑。
- 12 秒静默如何处理见下方调整建议；不能假定 Jiyi 已实现本项目分段策略。
- 验证重点：拒绝权限、来电或后台中断、模型不可用、中文效果、识别失败、精修期间用户编辑。

### 回顾：StoryPad 的时间流 + Daily You 的心情记录

建议流程：读取本地条目 → Domain 生成回顾结果 → UI 展示时间轴、随机卡片和统计入口。

- 时间轴突出正文片段、照片和心情，支持回到详情继续编辑。
- 随机一篇、连续天数、热力图按本项目需求实现纯逻辑；参考上游展示方式时不假定算法也可复用。
- 往年今日仍按原设计延后，避免新用户看到长期空白入口。
- 验证重点：零记录、仅一天记录、跨月跨年、时区与 `dayKey`、删除条目后的统计变化。

### 数据管理：Moodiary 的搜索与导出 + 本项目同步协议

- 本地搜索先研究索引更新和中文分词，结果必须与已保存的本地内容一致。
- 完整备份包含恢复所需的正文、元数据与附件；Markdown 等导出用于阅读和迁移，不能默认具有完整恢复能力。
- 同步仍采用本项目的 dirty_queue、字段级 LWW、服务端 seq、删除标记和落库后推进 cursor。
- 不把 Google Drive/WebDAV/S3 适配器直接视为本项目同步引擎；可借鉴传输与重试组织方式，协议须单独核对。
- 验证重点：多设备修改、离线删除、重复推送、上传中断、拉取落库失败、备份恢复后的附件完整性。

## 3. 设计调整建议：与原文的差异

状态：已记录的建议，具体实施时需统一对应设计条目；当前未修改原设计决策。

| 主题 | 原设计 | 上一轮提出的建议 | 目的 |
|---|---|---|---|
| 首页键盘 | 启动聚焦并自动弹键盘 | 点击文字区域再弹键盘，突出录音入口；可考虑记住上次输入方式 | 减少语音入口被键盘挤占 |
| 条目结束 | 自动保存、无保存按钮，录音有下一条 | 文字和语音统一提供「完成／下一条」，与保存状态分开 | 明确一条记录何时结束 |
| 静默分段 | 12 秒静默与下一条按钮共同触发分段 | 先以静默提示分段，避免直接切成新条目 | 减少思考停顿造成的误分段 |
| 精修确认 | 用户确认后替换，但另有待定表述 | 统一为候选稿，确认时检查最新正文 | 保护用户已编辑内容 |
| 回顾优先级 | 随机、连续天数、热力图 | 保留这些功能，优先打磨时间轴与重读；连续天数弱化、热力图置于统计页 | 强调生活回顾体验 |
| 备份时机 | 原开发路线未单列本地备份 | 在账号与云同步之前加入完整备份与恢复 | 保护早期试用期间的真实记录 |
| 写入可靠性 | 写循环「永不失败」 | 改为不依赖网络，失败可见且可恢复 | 正确处理磁盘和数据库异常 |
| 账号归属 | 本地库不按 userId 分库，注册时认领 | 明确匿名与已有账号记录的边界，账号 B 不自动认领账号 A 的记录 | 避免切换账号后数据错绑 |

建议开发顺序：本地文字记录 → 自动保存与恢复 → 时间轴 → 完整备份 → 语音录制与端侧转写 → 回顾 → 云同步。心情、照片与标签可按原路线穿插；这不是新的排期承诺。

## 4. 目前没有确认可直接参考的实现

以下以本项目设计为主，后续找到可靠实现再补充来源：

- 端侧转写 + 云端精修 + 用户确认替换的完整链路。
- 字段级 LWW、服务端单调 seq、删除标记与本地 cursor 原子提交的完整同步协议。
- 匿名日记认领、账号切换隔离、设备管理、账号找回与令牌吊销。
- 国内上架所需的录音单独同意、权限撤回、备案展示及注销后含备份的数据清除。

## 5. 每次查阅后补充的实施记录

目前尚无已完成源码核查的记录。开始具体功能时，先查上表，再按以下模板追加；不要将计划查阅记为已验证。

```text
功能：
参考仓库：
查阅日期与提交 SHA：
源码永久链接（blob/<SHA>/...）、类或函数：
已确认的实现流程：
准备借鉴的部分：
与本项目设计的差异：
本项目实现路径：
采用方式（交互参考／逻辑重写／源码复用）：
许可证及依赖、模型、素材核查（源码复用时）：
验证场景与实际结果：
状态（待查／已定位／已验证／已适配／不采用）：
未解决事项：
```

[daily]: https://github.com/Demizo/Daily_You
[jiyi]: https://github.com/xiaoshihou514/jiyi
[story]: https://github.com/theachoem/storypad
[vault]: https://github.com/SankethBK/diaryvault
[mood]: https://github.com/ZhuJHua/moodiary
