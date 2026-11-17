# F013 云同步 · 待办登记

- 功能编号：F013
- 关联：[设计](../superpowers/specs/云同步设计-cloud-sync-design.md) · [部署链路计划](../superpowers/plans/云同步-部署链路-ecs-deploy.md) · [任务台账](README.md) · [测试报告](../test-reports/F013-云同步测试报告-cloud-sync-test-report.md)
- 最后更新：2026-11-15（第十一轮真机 TLS 信任验收已合并；第十二轮：T-31/T-32 错误透出与状态语义修复）
- 记录规则：未执行 / 未验证的项一律记「未执行」，不写「通过」。本表是 F013 未完成项的**唯一维护位置**；功能状态仍维护在 [任务台账](README.md) 的 F013 行，测试结果维护在 [测试报告](../test-reports/F013-云同步测试报告-cloud-sync-test-report.md)。

## A. 验收未执行（真机 / 落库）

| 编号 | 事项 | 状态 | 阻塞原因 | 下一步 | 关联 |
|---|---|---|---|---|---|
| T-01 | **DP-05 真机可连**：release APK 装到小米 2211133C 后能连 `https://8.148.158.13` 完成登录（内置 CA 生效，不报证书错误） | 已验证 | —（TlsTrust 修复后真机注册成功） | 2026-11-15 第十一轮：debug APK（注入 SYNC_BASE_URL/USE_COS_HTTP）装真机，nginx `POST /auth/register` 200（UA `Dart/3.13 (dart:io)`），psql 用户落库（`$2b$` bcrypt）；logcat 无 HandshakeException——见测试报告「第十一轮」 | 测试报告「第十一轮」；部署计划 Task 8 Step 2–3 |
| T-02 | **DP-06 真机推送**：真机写一篇日记并触发推送，服务端能查到该条目 | 已验证 | — | 2026-11-15 第十一轮：真机「记录」页写日记自动保存，nginx `POST /sync/batch` 200（UA `Dart/3.13 (dart:io)`），psql 条目 `9267c356-…` 落库（payload `T02-device-push-test-…`，seq 24）——见测试报告「第十一轮」 | 测试报告「第十一轮」；部署计划 Task 8 Step 4 |
| T-03 | **DP-09 落库验证**：bcrypt 哈希以 `$2b$` 形式落进 `users.password_hash`，DB 级邮箱唯一性约束生效 | 已验证 | 第七轮：`select left(password_hash,4)` → `$2b$`；重复邮箱注册 409（集成测试）；entries seq 无重复（10 行 10 唯一） | 已随 T-06 验证 | 部署计划 DP-09 |
| T-04 | 真机端到端跨设备同步（含照片） | 部分验证：单机推送已过，跨设备第二台未执行 | 仅一台真机；第二台设备拉回未做 | T-01 / T-02 已验证（单机）；第二台设备拉回与照片同步待补 | 设计 AC-03 / AC-06；第六轮服务端等效已覆盖推送/拉取/COS 链路 |
| T-05 | **建桶 + CAM 凭证**：腾讯云 COS ap-guangzhou 私有桶、CAM 子用户 + bucket 级最小权限策略（只授 PutObject/GetObject，不授 DeleteObject）、密钥只存 ECS 服务端环境变量 | 已完成 | 2026-11-10 冒烟通过：桶/凭证/策略生效，密钥落 /etc/diary-sync/cos.env（0600） | 控制台建桶 → 写 `deploy/cam-policy.json` → 建子用户绑定策略 → 密钥写入 ECS 环境变量 | [COS 设计](../superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md) §3.4 |
| T-24 | **真机腾讯云 COS 代理读写**：服务端加照片上传/下载端点（代理 COS PUT/GET）、客户端 `CosGateway` 真机版替换 `FakeCos`、真机双设备验收 | 代码侧+服务端等效完成 | 服务端代理端点 + 客户端 `HttpCosGateway` 实现完毕，ECS 冒烟 + 第六轮服务端 API 等效（上传/下载比对/HEAD 判存）全过；**真机装机弹窗已可点按（T-01/T-02 已过），真机照片链路待第二轮验证** | T-05 完成后实现；**注意 ECS 出向带宽仅 ~428 KB/s 与 nginx 请求体上限（已调至 16m）** | COS 设计 §3.2 / §3.3 |

## B. 功能延后（未实现）

| 编号 | 事项 | 状态 | 影响 | 关联 |
|---|---|---|---|---|
| T-06 | **PostgresSyncStore**（真实 SQL + 事务游标，满足 AC-07 游标原子性） | 已关闭 | 第七轮（2026-11-10）：`PostgresSyncStore` 落地——行锁取 seq、字段级 LWW、created_at 冻结；ECS 真实 PG 集成测试 5 项全过、并发 push 无丢无重、重启持久化验证通过（register→push→pull→restart→login→pull 全活）；FakeSyncStore 时代「重启即丢」缺陷关闭 | 设计 AC-07；测试报告「第七轮」 |
| T-07 | **Token 过期与刷新**（AC-08）：token 失效 → 换 token 重试一次 → 仍失败则停同步提示重登录，不自动登出 | 已关闭 | 第九轮（2026-11-10）：服务端 access(7天)/refresh(30天) 双 token——expires_at 校验、`/auth/refresh` 端点、轮换防重放；客户端 RemoteRepo 401 → tokenRefresher 重试一次 → 停同步置 failed（AC-08 完整落地）；ECS 真实 PG 集成 8/8 全过 + 冒烟全链路通过 | 设计 AC-08；测试报告「第九轮」 |
| T-08 | 客户端 `InMemoryTokenStore` → SharedPreferences 持久化 | 已关闭 | 第九轮：AuthSession 模型 + SharedPreferencesTokenStore——App 重启免登录；flutter test 458 全过 | Part 3b；测试报告「第九轮」 |

## C. 运维与部署

| 编号 | 事项 | 状态 | 下一步 | 关联 |
|---|---|---|---|---|
| T-13 | release APK 仍用 debug keys 签名 | 未处理 | 正式发布前配置真实签名 | 部署计划 §11 |
| T-14 | 服务器证书绑死 IP `8.148.158.13`；CA 私钥只在开发机，不入库不上服务器 | 已关闭 | 第十三轮（2026-11-18）：改用 Cloudflare 代理 + 公网证书（Let's Encrypt），证书不再绑 IP——IP 变更只改 Cloudflare DNS，无需重签重发 APK；客户端不再内嵌自签 CA，私钥不再随包分发 | 测试报告「第十三轮」；部署计划 §11 |
| T-15 | 实例规格 `ecs.e-c1m1.large`（1.6 GiB 突发型）承载数据库 | 未变配 | e→g 跨规格族不能直接变配，需变配 + 重启流程，或换新实例 | 部署计划 §11 |
| T-16 | `deploy/ram-policy.json`（只读 RAM 策略）尚未附加到 RAM 子用户 | 未附加 | 附加后才能查询 `DescribeResourcesModification` 等只读接口 | 部署链路 |
| T-17 | nginx 443 已被公网扫描器探测到（访问日志见 `195.96.139.110` 扫 `/` → 404） | 已记录未处理 | 视需要加限流或屏蔽 | 本轮部署 |

## D. 质量改进（评审 Minor）

| 编号 | 事项 | 位置 | 说明 |
|---|---|---|---|
| T-18 | `PORT` 接受可解析但非法的值（-1 / 0 / 65536），在 bind 时失败而非回落 8080 | `packages/server/lib/src/server_config.dart` | 已关闭：第十轮补端口范围校验（1–65535），非法值回落 8080 |
| T-19 | `verifyPassword` 用 `on Object` 宽捕获，吞掉 `ArgumentError` 等 | `packages/server/lib/src/password.dart` | 已关闭：第十轮收窄为 `on ArgumentError`（调用方预检已拦超长） |
| T-20 | CA-pair guard 只查 `ca.key` 不查 `ca.crt` | `deploy/make-cert.sh` | 已关闭：第十轮同时检查 ca.key 与 ca.crt |
| T-21 | 健康检查只打印 HTTP 码，不断言 401 | `deploy/deploy-app.sh` | 已关闭：第四轮已断言 401，T-06/T-07 ECS 部署健康检查均验证通过 |
| T-22 | `deploy-app.sh` 无执行位（用法为 `bash deploy-app.sh`，功能无碍） | `deploy/deploy-app.sh` | 已关闭：第十轮加执行位（./deploy-app.sh 可直接执行） |
| T-23 | pre-existing analyze warning：`unused_field _undoableEntryId` | `client/lib/src/ui/home_page.dart:51` | 已关闭：第十轮清理（F005 遗留未使用字段） |
| T-25 | **ECS 公网带宽不足**：实测出向 ~428 KB/s（3.4 Mbps）、入向 ~10 Mbps。ECS 代理方案下下载一张 4 MB 照片约 10 秒，100 张批量同步约 16 分钟 | `docs/superpowers/specs/腾讯云COS对象存储-tencent-cos-storage-design.md` §3.3 | 已知限制，用户已知悉并选择维持 ECS 代理。缓解方向见同文档 §9（客户端上传前压缩最有效）；或在 T-24 一并评估升配/加带宽 |

## E. 本轮已关闭

| 编号 | 事项 | 状态 | 依据 | 关联 |
|---|---|---|---|---|
| T-26 | **FakeSyncStore 跨用户条目覆盖缺陷**：条目主键 (user_id, id) 与 schema.sql 一致，用户 id 分配不再占用条目 seq | 已关闭 | 服务端 31 项测试全过（新增 3 项回归，2026-11-09）；schema.sql 头部注释同步更新 | 缺陷修复；测试报告「第四轮」 |
| T-27 | **第五轮 COS 代理缺陷修复**：URL 主机/路径分隔符缺失、systemd 行内中文注释跳过 EnvironmentFile、getObject 非 200 返回错误体、签名 uriPath 缺前导斜杠、shelf_router 通配符语法 | 已关闭 | 各 commit `144ef0e`/`7d22850`/`c2bd43a`/`093efdf`/`9fa68f5`；回归测试已补；ECS 真实 COS 冒烟通过 | 缺陷修复；测试报告「第五轮」 |
| T-28 | **真机装机验收尝试（2026-11-10）**：CA 指纹三级一致（服务器=本机=APK 内嵌）、debug APK 构建成功；装机受阻于 MIUI 安装弹窗（`INSTALL_FAILED_USER_RESTRICTED`，shell/非 root 均无法绕过）；随后完成服务端 API 等效验收（注册/登录负路径/推送/拉取/坏 token 401/COS 上传下载判存全过） | 已验证（等效） | 脚本 `scripts/f013-api-acceptance.sh`；测试报告「第六轮」 | 真机 UI 交互验收（T-01/T-02）仍留待用户可点按弹窗时补做 |
| T-29 | **T-06 PostgresSyncStore 落库**：服务端数据从 FakeSyncStore 内存态迁移至真实 PostgreSQL——行锁取 seq（AC-07）、字段级 LWW、created_at 冻结、payload JSONB 往返；装配 PG 凭证探测 + Fake 回退；systemd 挂 pg.env | 已关闭 | ECS 真实 PG 集成测试 5 项全过（含并发 push 无丢无重）；重启持久化验证通过（register→push→pull→restart→login→pull）；bcrypt `$2b$` 落库、entries seq 无重复；本机 48 过 5 skip | 测试报告「第七轮」；commit `0189ea2`/`73ba49a`（SSL 修复） |
| T-09 | 触发循环缺陷 I-2：`triggerPush` 吞掉推送失败，状态仍显示 synced（违反「不静默失败」） | 已关闭 | 第八轮：triggerPush 回调失败置 `SyncState.failed`（与 triggerPull 对称）；新增测试验证失败后状态 | 测试报告「第八轮」 |
| T-10 | 触发循环缺陷 I-3：`stop()` 永久关闭流，`start()` 复用死流 | 已关闭 | 第八轮：`start()` 检测 `_stateController.isClosed` 重建流并重置 idle；新增测试验证 stop→start 后状态流恢复广播 | 测试报告「第八轮」 |
| T-11 | 触发循环缺陷 I-1：未登录时 `triggerPush` 定时器仍触发，登出后浪费一次推送 | 已关闭 | 第八轮：triggerPush 登录态预检（`_me()` 异步判定，未登录不安排定时器）；新增测试验证未登录时 pushes 为空 | 测试报告「第八轮」 |
| T-12 | 照片缺口：同条目新选照片不重传；远端 photoKey 变更不清本地 BLOB 缓存 | 已关闭 | 第八轮：pushOnce 按 sha256 校验重传（photoKey 恒为内容 hash）；pullOnce 本地 BLOB 与远端 key 不匹配时重下覆盖；新增 2 项测试 | 测试报告「第八轮」 |

## F. 本轮新发现（待处理）

| 编号 | 事项 | 状态 | 说明 |
|---|---|---|---|
| T-30 | **私有 CA 内嵌 APK 的公开发布风险**：任何人反编译 APK 即可提取该 CA 公钥，APK 外泄时等同于「信任任意人自签证书」的钥匙 | 已关闭 | 第十三轮（2026-11-18）：改走 Cloudflare 公网证书（Let's Encrypt），客户端 `TlsTrust` 退化为仅信任系统 CA，删除 `assets/diary_ca.crt` 与 `res/raw/diary_ca.crt`，APK 不再内嵌私有 CA——信任委托给 Cloudflare 公共体系，私有 CA 风险消除 | 测试报告「第十三轮」 |
| T-31 | **登录/注册失败吞掉真实原因**：`login_page.dart` 的 `catch (_)` 只显示「注册失败，请重试」，`HandshakeException` 等底层原因丢失 | 已关闭 | 第十二轮（2026-11-15）：`catch (e)` 透出异常描述（`_describe`：`HandshakeException`→TLS 握手失败、`SocketException`→网络连接失败、`StateError`→消息），不再只显示笼统「失败，请重试」；新增 TLS 透出测试 |
| T-32 | **未登录时状态误显示「已同步」**：`sync_engine.dart` 的 `triggerPull` 在 `_me()` 返回 null 时提前返回、不抛异常，状态被置为 `synced` | 已关闭 | 第十二轮（2026-11-15）：`triggerPull` 增加登录预检（`_me()` 返回 null 直接返回），未登录不再置 `synced`，与 `triggerPush` 的 T-11 对称；新增测试验证未登录不置 synced |

## 合并门槛

按 [开发流程](../开发流程-development-workflow.md)：测试失败、未执行或受阻时不得合并。

F013 的 T-01 / T-02（真机验收）已于第十一轮（2026-11-15）在真机上验证通过（见测试报告「第十一轮」）；T-04（跨设备第二台）与 T-24（真机照片）仍为「未执行/部分验证」。

**功能负责人裁决（2026-11-06）**：T-01 / T-02 真机验收**留到下一轮**，本轮先合入 `main`。本轮合入的是**对象存储供应商迁移与命名对齐**（腾讯云 COS + ECS 代理路径），宿主侧证据齐全（sync_core 13 + server 31 + client 442 = 486 项测试全过、三包静态分析与基线一致、调试 APK 构建成功），且**纯机械重命名、零行为变动**；真机验收的缺失不影响这部分成果的可信度。

**第四轮裁决（2026-11-09）**：FakeSyncStore 复合键缺陷修复 + deploy-app.sh 健康检查加固**合入 `main`**。依据：服务端 31 项测试全过（含新增 3 项回归，无对外行为新增）、`bash -n` 语法通过、测试报告与台账已更新；ECS 部署实测与 DP-05/DP-06 真机验收仍记「未执行」，不以此掩盖。

**第五轮裁决（2026-11-10）**：COS 代理代码侧完成并经 ECS 真实 COS 冒烟（注册→上传→下载字节比对→HEAD 判存 200/404 全过）**合入 `main`**。依据：server 48 项 / client 447 项测试全过、三包静态分析干净、部署脚本全链路绿、签名被真实 COS 接受。**真机双设备验收（T-24 真机子项）与 T-01/T-02 真机验收留到下一轮**（当前无真机连接）；客户端上传前压缩（T-25 缓解）同样并入真机轮评估。

**第七轮裁决（2026-11-10）**：PostgresSyncStore 落库**合入 `main`**。依据：ECS 真实 PG 集成测试 5 项全过（语义与 FakeSyncStore 等价 + 并发 seq 串行化）、bcrypt 落库 `$2b$`、重启持久化验证通过（FakeSyncStore 时代重启即丢的缺陷关闭）；`dart analyze` 干净、本机 48 过 5 skip（PG 集成测试无 PG env 时按设计跳过）。T-01/T-02 真机 UI 交互仍留待装机弹窗可点时补做。

**第八轮裁决（2026-11-10）**：触发循环缺陷 T-09/T-10/T-11 与照片缺口 T-12**合入 `main`**。依据：flutter analyze 干净（仅 pre-existing 警告）、flutter test 全量 452 项通过（新增 5 项缺陷测试）；纯客户端逻辑无服务端改动，无需 ECS 部署。真机 UI 交互验收仍留待装机弹窗可点时补做。

**第九轮裁决（2026-11-10）**：T-07 refresh token 过期刷新 + T-08 token 持久化**合入 `main`**。依据：ECS 真实 PG 集成测试 8/8 全过（含 refresh/轮换/过期 3 项新增）、curl 冒烟全链路通过（register→pull→refresh→轮换→过期→重试）、本机 server 48 过 8 skip / client 458 全过、analyze 干净。AC-08 完整落地。

**第十轮裁决（2026-11-10）**：D 节质量改进 T-18/T-19/T-20/T-22/T-23**合入 `main`**，T-21 验证关闭。依据：server 48 过 8 skip、client 458 全过、analyze 干净、make-cert 语法检查通过；纯代码/脚本小改，无服务端行为变更，无需 ECS 部署。

真机 COS 相关的 T-05 / T-24 / T-25 同样留到下一轮，其中 **T-25（ECS 公网带宽不足）的缓解措施由 T-24 一并评估**（客户端上传前压缩最有效且不加云成本；备选是升配或加公网带宽）。

**第十一轮裁决（2026-11-15）**：安卓真机 TLS 信任修复（`TlsTrust`）+ T-01/T-02 真机验收**合入 `main`**。依据：根因确认为 `dart:io` 不读 `network_security_config.xml`，新增 `TlsTrust` 使自签 CA 在 Dart 层被信任；宿主 analyze 无新增问题、`flutter test` 461 项全过；真机注册（`POST /auth/register` 200，Dart UA）与推送（`POST /sync/batch` 200，条目落库）均已验证，logcat 无握手异常。T-04（跨设备第二台）与 T-24（真机照片）留待下一轮。

**第十二轮裁决（2026-11-15）**：T-31 登录/注册失败透出底层原因 + T-32 未登录不置 synced**合入 `main`**。依据：`login_page` 的 `catch` 改为透出异常描述（TLS/网络/StateError 分型），`sync_engine.triggerPull` 增加登录预检与 `triggerPush` 对称；宿主 analyze 无新增、`flutter test` 463 项全过（新增 2 项缺陷测试）。纯客户端小改，无服务端行为变更。

**第十三轮裁决（2026-11-18）**：改走 Cloudflare 代理 + 公网证书，去掉内嵌自签 CA**合入 `main`**。依据：根因是备案网关拦 Cloudflare→源站入站 443（525），改用 Cloudflare Tunnel（cloudflared 出站）绕开；客户端 `TlsTrust` 退化为仅信任系统 CA，删除自签 CA 资产，APK 不再内嵌私有 CA；真机注册（用户落库 `$2b$`）与推送（条目落库 payload 正确）经 Cloudflare 隧道全部验证，logcat 无 TLS 异常。T-14（证书绑 IP）、T-30（私有 CA 公开分发风险）关闭。

下一轮补做 T-04（跨设备第二台拉回）与 T-24（真机照片链路），再评估 T-25 带宽缓解。

