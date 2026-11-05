# F013 云同步 · 待办登记

- 功能编号：F013
- 关联：[设计](../superpowers/specs/云同步设计-cloud-sync-design.md) · [部署链路计划](../superpowers/plans/云同步-部署链路-ecs-deploy.md) · [任务台账](README.md) · [测试报告](../test-reports/F013-云同步测试报告-cloud-sync-test-report.md)
- 最后更新：2026-11-05（对象存储供应商由阿里云改为腾讯云 COS，数据路径定为 ECS 代理收发字节后）
- 记录规则：未执行 / 未验证的项一律记「未执行」，不写「通过」。本表是 F013 未完成项的**唯一维护位置**；功能状态仍维护在 [任务台账](README.md) 的 F013 行，测试结果维护在 [测试报告](../test-reports/F013-云同步测试报告-cloud-sync-test-report.md)。

## A. 验收未执行（真机 / 落库）

| 编号 | 事项 | 状态 | 阻塞原因 | 下一步 | 关联 |
|---|---|---|---|---|---|
| T-01 | **DP-05 真机可连**：release APK 装到小米 2211133C 后能连 `https://8.148.158.13` 完成登录（内置 CA 生效，不报证书错误） | 未执行 | 真机 USB 未连接（用户 2026-11-05 暂时拔除），本轮改用请求做等价验证 | 连上手机 → 装 APK → 启动查 SSL/证书日志 → App 内登录 | 部署计划 Task 8 Step 2–3 |
| T-02 | **DP-06 真机推送**：真机写一篇日记并触发推送，服务端能查到该条目 | 未执行 | 同 T-01 | App 内新建并保存日记 → 服务端用 curl 查该条目 | 部署计划 Task 8 Step 4 |
| T-03 | **DP-09 落库验证**：bcrypt 哈希以 `$2b$` 形式落进 `users.password_hash`，DB 级邮箱唯一性约束生效 | 未执行 | 服务端仍是 FakeSyncStore（内存），无真实 DB | 接入 PostgresSyncStore 后查 `select email, password_hash from users` | 部署计划 DP-09 |
| T-04 | 真机端到端跨设备同步（含照片） | 未执行 | 无真机 + 无真实 COS | T-01 / T-02 完成后补做 | 设计 AC-03 / AC-06 |
| T-05 | **建桶 + CAM 凭证**：腾讯云 COS ap-guangzhou 私有桶、CAM 子用户 + bucket 级最小权限策略（只授 PutObject/GetObject，不授 DeleteObject）、密钥只存 ECS 服务端环境变量 | 未执行 | 桶尚未创建 | 控制台建桶 → 写 `deploy/cam-policy.json` → 建子用户绑定策略 → 密钥写入 ECS 环境变量 | [COS 设计](../superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md) §3.4 |
| T-24 | **真机腾讯云 COS 代理读写**：服务端加照片上传/下载端点（代理 COS PUT/GET）、客户端 `CosGateway` 真机版替换 `FakeCos`、真机双设备验收 | 未执行 | 依赖 T-05 + 无真机 | T-05 完成后实现；**注意 ECS 出向带宽仅 ~428 KB/s 与 nginx 8 MB 请求体上限** | COS 设计 §3.2 / §3.3 |

## B. 功能延后（未实现）

| 编号 | 事项 | 状态 | 影响 | 关联 |
|---|---|---|---|---|
| T-06 | **PostgresSyncStore**（真实 SQL + 事务游标，满足 AC-07 游标原子性） | 未实现 | 当前内存实现**服务重启即丢全部账号与同步数据**（本轮已实际发生一次：重启后 `dp@local.test` 不存在，登录 401）。生产不可用 | 设计 AC-07 |
| T-07 | **Token 过期与刷新**（AC-08）：token 失效 → 换 token 重试一次 → 仍失败则停同步提示重登录，不自动登出 | 未实现 | 当前 token 无过期 | 设计 AC-08 |
| T-08 | 客户端 `InMemoryTokenStore` → SharedPreferences 持久化 | 未实现 | App 重启需重新登录 | Part 3b |
| T-09 | 触发循环缺陷 I-2：`triggerPush` 吞掉推送失败，状态仍显示 synced（违反「不静默失败」） | 未修 | 推送失败对用户不可见 | Part 3b 终审 |
| T-10 | 触发循环缺陷 I-3：`stop()` 永久关闭流，`start()` 复用死流（App 目前从不调 stop，属潜伏） | 未修 | 潜伏缺陷 | Part 3b 终审 |
| T-11 | 触发循环缺陷 I-1：未登录时 `pushOnce` 跳过，但 `triggerPush` 定时器仍触发，登出后浪费一次推送 | 未修 | 轻微 | Part 3b 终审 |
| T-12 | 照片缺口：`setPhoto` 保留旧 photoKey → 同条目新选照片不重传；远端 photoKey 变更不清本地 BLOB 缓存 | 未修 | 照片同步在改图场景下不一致 | Part 4 终审 |

## C. 运维与部署

| 编号 | 事项 | 状态 | 下一步 | 关联 |
|---|---|---|---|---|
| T-13 | release APK 仍用 debug keys 签名 | 未处理 | 正式发布前配置真实签名 | 部署计划 §11 |
| T-14 | 服务器证书绑死 IP `8.148.158.13`；CA 私钥只在开发机，不入库不上服务器 | 已知限制 | IP 变更需重签并重新发版 APK | 部署计划 §11 |
| T-15 | 实例规格 `ecs.e-c1m1.large`（1.6 GiB 突发型）承载数据库 | 未变配 | e→g 跨规格族不能直接变配，需变配 + 重启流程，或换新实例 | 部署计划 §11 |
| T-16 | `deploy/ram-policy.json`（只读 RAM 策略）尚未附加到 RAM 子用户 | 未附加 | 附加后才能查询 `DescribeResourcesModification` 等只读接口 | 部署链路 |
| T-17 | nginx 443 已被公网扫描器探测到（访问日志见 `195.96.139.110` 扫 `/` → 404） | 已记录未处理 | 视需要加限流或屏蔽 | 本轮部署 |

## D. 质量改进（评审 Minor）

| 编号 | 事项 | 位置 | 说明 |
|---|---|---|---|
| T-18 | `PORT` 接受可解析但非法的值（-1 / 0 / 65536），在 bind 时失败而非回落 8080 | `packages/server/lib/src/server_config.dart` | 补端口范围校验 |
| T-19 | `verifyPassword` 用 `on Object` 宽捕获，吞掉 `ArgumentError` 等 | `packages/server/lib/src/password.dart` | 已被 T-02 的登录预检绕开；可评估收窄 |
| T-20 | CA-pair guard 只查 `ca.key` 不查 `ca.crt` | `deploy/make-cert.sh` | 上次签发失败残留时需手动清理 |
| T-21 | 健康检查只打印 HTTP 码，不断言 401 | `deploy/deploy-app.sh` | 服务异常返回非 401 时脚本仍继续 |
| T-22 | `deploy-app.sh` 无执行位（用法为 `bash deploy-app.sh`，功能无碍） | `deploy/deploy-app.sh` | 报告措辞与实际不一致 |
| T-23 | pre-existing analyze warning：`unused_field _undoableEntryId` | `client/lib/src/ui/home_page.dart:41` | 来自 F005（非 F013 引入），合并前应清理 |
| T-25 | **ECS 公网带宽不足**：实测出向 ~428 KB/s（3.4 Mbps）、入向 ~10 Mbps。ECS 代理方案下下载一张 4 MB 照片约 10 秒，100 张批量同步约 16 分钟 | 已实测记录 | 已知限制，用户已知悉并选择维持 ECS 代理 | 缓解方向见 COS 设计 §9（客户端上传前压缩最有效）；或在 T-24 一并评估升配/加带宽 | COS 设计 §3.3 |

## 合并门槛

按 [开发流程](../开发流程-development-workflow.md)：测试失败、未执行或受阻时不得合并。

F013 当前的 T-01 / T-02（真机验收）处于「未执行」状态 → 若按「全部必需验收项均须有证据」的口径，本轮**不满足合并到 `main` 的门槛**。是否先合入、把真机验收留到下一轮，由功能负责人在 [任务台账](README.md) 决定并记录。
