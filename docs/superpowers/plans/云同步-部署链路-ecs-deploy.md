# F013 云同步实现计划 · Part 5：ECS 部署链路

**Goal:** 把 F013 服务端部署到广州 ECS（`i-7xv4buzm47fxdask0bgz`），用真机 + curl 模拟第二设备跑通「客户端 → nginx TLS → Dart 服务 → 存储」的完整链路；同时把口令哈希从 `sha256(salt+password)` 换成 bcrypt。

**状态：** 设计已确认，待实现。

**前置环境（2026-11-05 实测）：** Alibaba Cloud Linux 4.0.6（内核 6.6.102-8.alnx4）、PostgreSQL 15.19、Dart SDK 3.13.7、nginx 1.30.4、2 GiB swap、swap 已挂载、安全组仅放行 22。

---

## 1. 范围

### 本轮做

- 服务端代码部署到 ECS：编译 → systemd → nginx TLS
- 客户端指向真实服务器：证书信任、INTERNET 权限、服务器地址注入
- **bcrypt 密码哈希**替换 `sha256(salt+password)`
- 真机验证：安装 APK、登录、写日记、推送；用 curl 充当第二设备拉取确认
- 产出可复用的部署脚本与证书签发脚本

### 本轮不做（已在 F013 测试报告登记为延后项）

| 项 | 影响 |
| --- | --- |
| PostgresSyncStore | 服务端仍用 FakeSyncStore（内存），数据库空置 |
| Token 过期/刷新 | AC-08 未实现，token 永久有效 |
| 真机阿里云 OSS | 照片走 FakeOSS（本地文件系统） |
| 跨设备真机同步 | 需第二台 Android 设备 |
| 实例变配到 g7.large | e→g 跨规格族不支持，见部署文档第 8 节 |

### 已知代价（写进测试报告，不计通过）

- FakeSyncStore 内存存储：systemd 或服务器重启后用户与日记全丢
- 客户端 `InMemoryTokenStore`：App 重启后需重新登录

---

## 2. 关键决策

| # | 决策 | 选择 | 理由 |
| --- | --- | --- | --- |
| D1 | 传输方案 | 自签 CA + App 内置信任 | `targetSdk=36`（Android 9+）默认禁明文 HTTP；正式环境不该开明文口子 |
| D2 | CA 私钥位置 | **只留开发机，永不上服务器** | CA 私钥是信任链的根。服务器只需「被信任」，不需要「能签发」；私钥上服务器意味着该机被入侵即可签发任意证书做中间人。加机器用 `make-cert.sh` 本地签发即可，成本一条命令 |
| D3 | 服务器地址配置 | `--dart-define` 注入，不进设置页 | 编译期注入不污染源码、不引入产品可见的新界面。「设置页可填地址」是产品决策，留到 F013 收尾时定 |
| D4 | nginx 与 Dart 服务 | 分开管理 | 两者是独立进程与独立 systemd 单元，nginx 重启/升级不影响 Dart 服务，反之亦然 |
| D5 | 代码投递 | 服务器 `git pull`（HTTPS 匿名，已实测可达） | 可追溯到 commit、可回滚；打包上传留作兜底 |
| D6 | 编译位置 | 服务器上 `dart compile exe` | Dart 不支持交叉编译；目标机已装 SDK，实测编译耗时 3.5 s、产物 7.2 MB |
| D7 | 密码哈希 | `bcrypt` 1.2.0，cost **10**，前缀 `$2b` | 纯 Dart（无 `dart:ffi`），实测可 AOT 编译；cost 10 单次 106 ms。选 `$2b` 是修正 `$2a` 的高位字符符号扩展缺陷 |

---

## 3. 架构

```
真机 Android 15（小米 2211133C，adb 已连）
  │  HTTPS  https://8.148.158.13
  │  证书链：服务器证书 ← 自签 CA（App 内置 ca.crt 信任）
  ▼
nginx :443（TLS）
  │  proxy_pass http://127.0.0.1:8080
  ▼
Dart shelf 服务（仅监听 127.0.0.1:8080）
  │  FakeSyncStore（内存）
  ▼
PostgreSQL 15.19 —— 本轮不使用
```

**安全边界**

- 8080 只绑回环地址，不进安全组
- 安全组放行 443（22 保留给 SSH）
- App 端 `base-config cleartextTrafficPermitted="false"`；明文仅对 `10.0.2.2` 放行，保住模拟器开发体验

---

## 4. 客户端改动

| # | 文件 | 改动 | 性质 |
| --- | --- | --- | --- |
| C1 | `client/android/app/src/main/AndroidManifest.xml` | 补 `<uses-permission android:name="android.permission.INTERNET"/>` | **硬阻塞**：现仅 debug/profile 的 manifest 有该权限，release 装到真机完全无网络能力 |
| C2 | `client/android/app/src/main/res/xml/network_security_config.xml` | 新建。禁全局明文；`10.0.2.2` 单独放行明文；`<certificates src="system"/>` 与 `src="@raw/diary_ca"` 并列（保留系统 CA，只追加自签 CA） | 新增 |
| C3 | `client/android/app/src/main/res/raw/diary_ca.crt` | 新建。自签 CA 证书（公钥） | 新增 |
| C4 | `client/lib/main.dart` | `kSyncBaseUrl` 改为读取 `--dart-define=SYNC_BASE_URL`，未注入时回落 `http://10.0.2.2:8080` | 改动 |
| C5 | `client/android/app/src/main/AndroidManifest.xml` | `android:networkSecurityConfig="@xml/network_security_config"` | 引用 C2 |

C2 内容：

```xml
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <!-- 安卓模拟器访问宿主机的别名，仅开发用 -->
        <domain includeSubdomains="false">10.0.2.2</domain>
    </domain-config>
    <certificates>
        <certificates src="system" />
        <certificates src="@raw/diary_ca" />
    </certificates>
</network-security-config>
```

---

## 5. 服务端改动

| # | 文件 | 改动 |
| --- | --- | --- |
| S1 | `packages/server/lib/src/main.dart` | `serve(createApp(store), '0.0.0.0', 8080)` → `'127.0.0.1'`；端口读 `PORT` 环境变量，默认 8080 |
| S2 | `packages/server/bin/server.dart` | 新建 package 入口。`dart compile exe lib/src/main.dart` 虽可运行，但 `lib/src` 属私有目录，不应对外暴露 |
| S3 | `packages/server/lib/src/password.dart` | 换 bcrypt，见第 5.1 节 |
| S4 | `packages/server/lib/src/fake_sync_store.dart` | 改用 `hashPassword` / `verifyPassword`；登录时对不存在的邮箱也跑一次 bcrypt（见 5.2） |
| S5 | `packages/server/pubspec.yaml` | 增 `bcrypt: ^1.2.0`；移除 `crypto: ^3.0.3`（仅 sha256 用到；`newToken()` 走 `Random.secure()`） |

`packages/server/pubspec.yaml` 本轮**不新增** `postgres` 依赖（用 FakeSyncStore）。

### 5.1 密码哈希改 bcrypt

实测（在目标机 2 vCPU 上跑真实尖刺）：

| 项 | 结果 |
| --- | --- |
| 包 | `bcrypt` 1.2.0，**纯 Dart**（无 `dart:ffi`） |
| `dart compile exe` | 成功，产物 6.4 MB |
| cost 8 / 10 / 12 | 26 ms / **106 ms** / 425 ms |
| 密码 > 72 字节 | 抛 `ArgumentError`（非静默截断） |
| 前缀 | `$2b` |

API 变更：

```dart
/// bcrypt 哈希，salt 内嵌于返回值（$2b$10$<salt><hash>）。
String hashPassword(String password);

/// 校验密码；哈希格式非法或密码超 72 字节时返回 false。
bool verifyPassword(String password, String hash);
```

- 删除 `newSalt()`——bcrypt 的 salt 本就内嵌在哈希串里
- `newToken()` 保留不动

### 5.2 业务层处理

1. **超 72 字节**：捕获 `ArgumentError`，转成 400 友好提示，不得漏成 500
2. **登录时邮箱不存在也要跑一次 bcrypt 再返回失败**：否则登录响应时间差异可枚举出哪些邮箱已注册。代价是「查不存在的邮箱」也需 106 ms，属有意为之

### 5.3 schema 变更

`users.salt` 列删除——bcrypt 下该列无意义。生产库当前 **0 个用户**，无迁移负担，直接 `DROP TABLE` 重建后重跑 `deploy/sql/schema.sql`。

---

## 6. 证书方案

**本地生成，CA 私钥不出开发机。**

```
开发机：ca.key（永久留本地，不上传）+ ca.crt（公钥，给客户端打包）
        server.key + server.crt（SAN 含 IP:8.148.158.13，有效期 10 年）
服务器：仅 server.key + server.crt + ca.crt
```

- CA 签发脚本 `deploy/make-cert.sh` 支持给任意 IP/域名签发子证书，加机器时本地跑一条命令即可
- 服务器证书的 SAN 必须包含 `IP:8.148.158.13`，否则客户端按 IP 访问会证书名不匹配
- 客户端只内置 `ca.crt`（公钥），私钥不进入仓库、不进 APK
- `ca.key` 与 `server.key` 加进 `.gitignore`

---

## 7. 部署产物

| 文件 | 作用 |
| --- | --- |
| `deploy/make-cert.sh` | 本地生成 CA 与服务器证书，输出 `deploy/certs/` |
| `deploy/deploy-app.sh` | 服务器执行：git pull → `dart pub get` → `dart analyze` → `dart test` → `dart compile exe` → 装 systemd → start → 健康检查 |
| `deploy/diary-sync.service` | `ExecStart` 对齐到编译产物路径；`User=diary`；`EnvironmentFile=/etc/diary-sync/pg.env` |
| `deploy/nginx/diary-sync.conf` | 443 TLS + `proxy_pass http://127.0.0.1:8080`；证书路径 `/etc/nginx/ssl/diary-sync/server.key` 与 `server.crt` |

nginx **不另建 systemd 单元**——`postgresql`/`nginx` 等软件包已自带 `nginx.service`（实测 `/usr/lib/systemd/system/nginx.service` 存在、preset 为 disabled），另建单元会与服务包自带的抢同一进程和端口。做法是 `systemctl enable --now nginx` 直接用自带单元，配置文件放在 `/etc/nginx/conf.d/diary-sync.conf`。

`deploy/provision-alinux4.sh` 已在 Alinux 4 上跑通，本轮不改。

---

## 8. 验收标准

编号用 `DP-xx`，与 F013 主文档的 `AC-01`~`AC-08` 区分，避免编号冲突。

| 编号 | 场景 | 验收 |
| --- | --- | --- |
| DP-01 | 证书链正确 | `openssl s_client -connect 8.148.158.13:443 -CAfile ca.crt` 校验通过，**不**用 `curl -k` 跳过 |
| DP-02 | 服务端四接口 | 经 HTTPS 完成注册 → 登录 → push → pull，响应符合 sync_core 协议 |
| DP-03 | 服务自启 | `systemctl restart diary-sync` 与 `nginx` 后，服务自动恢复监听 |
| DP-04 | 端口边界 | 安全组与宿主均只暴露 443；8080 仅 127.0.0.1 可达；外部探测 8080 不通 |
| DP-05 | 真机可连 | release APK 装到真机后能连 `https://8.148.158.13` 完成登录（内置 CA 生效，不报证书错误） |
| DP-06 | 真机推送 | 真机写一篇日记并触发推送，服务端能查到该条目 |
| DP-07 | curl 充当第二设备 | 用真机 token 从服务端 pull，能拉到真机刚写的日记，cursor 正确推进 |
| DP-08 | 模拟器开发不受影响 | 未注入 `SYNC_BASE_URL` 时，模拟器仍能连 `http://10.0.2.2:8080` |
| DP-09 | bcrypt 落库 | 注册后 `users.password_hash` 为 `$2b$10$` 开头、60 字符的 bcrypt 串；`users` 表无 `salt` 列 |
| DP-10 | 超长密码被拒 | 超过 72 字节的密码注册返回 400，不出现 500，也不截断后入库 |
| DP-11 | 登录与时序防护 | 用 bcrypt 串登录成功、错误密码失败；不存在的邮箱与错误密码的响应耗时无显著差异 |

DP-05 用 release 构建验证而非 debug——自签 CA 方案的意义就是 release 也能连，debug 放行明文反而验证不到 CA 信任链。

客户端 release 构建目前用 debug keys 签名（`client/android/app/build.gradle.kts` 的 `signingConfig = signingConfigs.getByName("debug")`，Flutter 模板默认）。本轮验证不受影响，但该 APK 不可上架，正式发布前需配置真实签名。

---

## 9. 风险与已知问题

| 风险 | 影响 | 处置 |
| --- | --- | --- |
| FakeSyncStore 内存存储 | 重启丢全部数据 | 本轮已知代价，写入测试报告；下轮换 PostgresSyncStore |
| 客户端 token 无过期 | token 泄露长期有效 | 本轮延后项，与 token 刷新一并无 |
| 服务器证书绑死 IP | IP 变更需重签并更新 App | 签发脚本支持域名；如需固定入口可后续接域名 + 正式证书 |
| bcrypt 纯 Dart 性能 | 单次 106 ms，登录接口可接受；成本约原生实现的 5 倍 | 已实测；该机 2 vCPU 下仍有余量。若将来成本压测不达标，可换 `crypt` 包绑系统 libxcrypt（需随包分发 .so） |
| 客户端 release 用 debug keys 签名 | APK 不可上架 | 正式发布前配置真实签名，本轮验证不受影响 |
