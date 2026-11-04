# F013 云同步实现计划 · Part 5：ECS 部署链路

**Goal:** 把 F013 服务端部署到广州 ECS（`i-7xv4buzm47fxdask0bgz`），用真机 + curl 模拟第二设备跑通「客户端 → nginx TLS → Dart 服务 → 存储」的完整链路；同时把口令哈希从 `sha256(salt+password)` 换成 bcrypt。

**状态：** 设计已确认，待实现。

**前置环境（2026-11-05 实测）：** Alibaba Cloud Linux 4.0.6（内核 6.6.102-8.alnx4）、PostgreSQL 15.19、Dart SDK 3.13.7、nginx 1.30.4、2 GiB swap、swap 已挂载、安全组仅放行 22。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## 全局约束

- Dart SDK `^3.13.7`（`packages/*/pubspec.yaml` 与服务端必须一致），只从 `https://pub.flutter-io.cn` 拉依赖
- 服务器 Dart SDK 固定在 `/opt/dart-sdk`，pub 镜像通过 `PUB_HOSTED_URL=https://pub.flutter-io.cn` 注入
- 应用进程只监听 `127.0.0.1:8080`；对外只暴露 nginx 的 443；安全组不放行 8080
- 服务端运行用户 `diary`（shell `/sbin/nologin`）；手动 `su` 需 `su -s /bin/bash diary -c '...'`
- 证书与私钥：CA 私钥只在开发机，`deploy/certs/` 与 `*.key`/`*.pem` 不入库（`.gitignore` 已配）
- 提交信息格式 `<type>:<中文说明>,<english summary>`，标注功能编号写作 `feat(F013):...`
- 行尾：`.sh`/`.sql`/`.service`/`.conf` 强制 LF（`.gitattributes` 已配）
- 本轮不引入 `postgres` Dart 依赖（服务端用 FakeSyncStore）

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
| `deploy/diary-sync.service` | `ExecStart` 对齐到编译产物路径；`User=diary`；`EnvironmentFile=-/etc/diary-sync/server.env`（可选覆盖，缺省走代码默认的 8080） |
| `deploy/nginx/diary-sync.conf` | 443 TLS + `proxy_pass http://127.0.0.1:8080`；证书路径 `/etc/nginx/ssl/diary-sync/server.key` 与 `server.crt` |

nginx **不另建 systemd 单元**——`postgresql`/`nginx` 等软件包已自带 `nginx.service`（实测 `/usr/lib/systemd/system/nginx.service` 存在、preset 为 disabled），另建单元会与服务包自带的抢同一进程和端口。做法是 `systemctl enable --now nginx` 直接用自带单元，配置文件放在 `/etc/nginx/conf.d/diary-sync.conf`。

`deploy/provision-alinux4.sh` 已在 Alinux 4 上跑通，本轮不改。

---

## 8. 验收标准

编号用 `DP-xx`，与 F013 主文档的 `AC-01`~`AC-08` 区分，避免编号冲突。

| 编号 | 场景 | 验收 |
| --- | --- | --- |
| DP-01 | 证书链正确 | `curl --cacert ca.crt --resolve 8.148.158.13:443:127.0.0.1 https://8.148.158.13/...` 校验通过，**不**用 `curl -k` 跳过。`--cacert` 必须指向签发者 `ca.crt`，不是叶子证书 `server.crt` |
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

---

## 10. 实现计划

### 文件结构

| 文件 | 职责 |
| --- | --- |
| `packages/server/lib/src/server_config.dart` | 服务监听配置（host/port），从环境变量解析 |
| `packages/server/lib/src/main.dart` | 路由装配 `createApp` + 启动函数 `serveDiarySync` |
| `packages/server/lib/src/password.dart` | bcrypt 哈希与校验、token 生成 |
| `packages/server/lib/src/fake_sync_store.dart` | 内存版 `SyncStore` 实现 |
| `packages/server/lib/src/handlers.dart` | HTTP 薄适配层，含超长密码的 400 分支 |
| `packages/server/bin/server.dart` | package 入口，供 `dart compile exe` 编译 |
| `client/lib/src/config/sync_config.dart` | 同步服务端基址（编译期注入） |
| `client/android/app/src/main/res/xml/network_security_config.xml` | 网络安全策略：禁明文、信任自签 CA |
| `client/android/app/src/main/res/raw/diary_ca.crt` | 内置的自签 CA 证书 |
| `deploy/make-cert.sh` | 本地生成 CA 与服务器证书 |
| `deploy/deploy-app.sh` | 服务器端部署脚本 |
| `deploy/nginx/diary-sync.conf` | nginx 443 TLS 反代配置 |
| `deploy/diary-sync.service` | Dart 服务 systemd 单元 |

### Task 1: 服务端监听配置与 package 入口

**Files:**
- Create: `packages/server/lib/src/server_config.dart`
- Create: `packages/server/bin/server.dart`
- Create: `packages/server/test/server_config_test.dart`
- Modify: `packages/server/lib/src/main.dart`
- Modify: `packages/server/lib/server.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class ServerConfig { final String host; final int port; static ServerConfig fromEnv(Map<String, String> env); }`
- Produces: `Future<void> serveDiarySync({Map<String, String>? env, SyncStore? store})`（由 `package:server/server.dart` 导出）

- [ ] **Step 1: 写失败测试**

`packages/server/test/server_config_test.dart`：

```dart
import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  group('ServerConfig.fromEnv', () {
    test('缺省时绑定回环地址与 8080', () {
      final c = ServerConfig.fromEnv(const {});
      expect(c.host, '127.0.0.1');
      expect(c.port, 8080);
    });

    test('PORT 可覆盖', () {
      expect(ServerConfig.fromEnv(const {'PORT': '9090'}).port, 9090);
    });

    test('PORT 非法时回落默认端口', () {
      expect(ServerConfig.fromEnv(const {'PORT': 'abc'}).port, 8080);
      expect(ServerConfig.fromEnv(const {'PORT': ''}).port, 8080);
    });

    test('HOST 可覆盖', () {
      expect(ServerConfig.fromEnv(const {'HOST': '0.0.0.0'}).host, '0.0.0.0');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd packages/server && dart test test/server_config_test.dart`
Expected: FAIL —— `ServerConfig` 未定义（编译错误）

- [ ] **Step 3: 实现 `ServerConfig`**

`packages/server/lib/src/server_config.dart`：

```dart
/// 服务监听配置。
///
/// 默认只绑回环地址：8080 不对公网暴露，对外由 nginx 走 443 反代。
class ServerConfig {
  const ServerConfig({this.host = defaultHost, this.port = defaultPort});

  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 8080;

  final String host;
  final int port;

  /// 从环境变量解析。PORT 缺失或非法时回落默认端口。
  static ServerConfig fromEnv(Map<String, String> env) => ServerConfig(
        host: env['HOST'] ?? defaultHost,
        port: int.tryParse(env['PORT'] ?? '') ?? defaultPort,
      );
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd packages/server && dart test test/server_config_test.dart`
Expected: PASS —— 4 项通过

- [ ] **Step 5: 改 `main.dart` 为可配置启动，并导出**

`packages/server/lib/src/main.dart` 全文替换为：

```dart
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';

import 'fake_sync_store.dart';
import 'handlers.dart';
import 'server_config.dart';
import 'sync_store.dart';

/// 装配 4 个路由。生产用 PostgresSyncStore；本 Part 用 FakeSyncStore（内存）。
Handler createApp(SyncStore store) {
  final router = Router()
    ..post('/auth/register', registerHandler(store))
    ..post('/auth/login', loginHandler(store))
    ..get('/sync', pullHandler(store))
    ..post('/sync/batch', pushHandler(store));
  return router;
}

/// 启动服务。监听地址与端口由环境变量决定，默认只绑回环。
Future<void> serveDiarySync({Map<String, String>? env, SyncStore? store}) async {
  final cfg = ServerConfig.fromEnv(env ?? Platform.environment);
  final s = store ?? FakeSyncStore();
  await serve(createApp(s), cfg.host, cfg.port);
}
```

`packages/server/lib/server.dart` 追加两行导出：

```dart
export 'src/server_config.dart';
export 'src/main.dart';
```

- [ ] **Step 6: 建 package 入口**

`packages/server/bin/server.dart`：

```dart
import 'package:server/server.dart';

/// `dart compile exe bin/server.dart` 的编译入口。
Future<void> main(List<String> args) => serveDiarySync();
```

- [ ] **Step 7: 静态检查与全量测试**

Run: `cd packages/server && dart analyze && dart test`
Expected: analyze 无问题；13 项既有测试 + 4 项新测试全部通过

- [ ] **Step 8: 提交**

```bash
git add packages/server
git commit -m "feat(F013):服务端监听配置与入口,add server config and package entry"
```

### Task 2: bcrypt 密码哈希

**Files:**
- Modify: `packages/server/lib/src/password.dart`
- Modify: `packages/server/lib/src/fake_sync_store.dart`
- Modify: `packages/server/lib/src/handlers.dart`
- Modify: `packages/server/pubspec.yaml`
- Create: `packages/server/test/password_test.dart`

**Interfaces:**
- Consumes: Task 1 产出的 `package:server/server.dart` 导出
- Produces: `String hashPassword(String password)`、`bool verifyPassword(String password, String hash)`、`String newToken()`

- [ ] **Step 1: 加依赖**

`packages/server/pubspec.yaml` 的 `dependencies` 段改为：

```yaml
dependencies:
  shelf: ^1.4.0
  shelf_router: ^1.1.0
  bcrypt: ^1.2.0
  sync_core:
    path: ../sync_core
```

Run: `cd packages/server && dart pub get`
Expected: `+ bcrypt 1.2.0`，`crypto` 被移除（`crypto` 仅 sha256 用到，`newToken()` 走 `Random.secure()`）

- [ ] **Step 2: 写失败测试**

`packages/server/test/password_test.dart`：

```dart
import 'package:server/server.dart';
import 'package:test/test.dart';

void main() {
  group('hashPassword', () {
    test('产出 bcrypt 格式串并内嵌 salt', () {
      final h = hashPassword('correct horse');
      expect(h, startsWith(r'$2b$10$'));
      expect(h.length, 60);
    });

    test('同一密码两次哈希不同（salt 随机）', () {
      expect(hashPassword('same'), isNot(hashPassword('same')));
    });

    test('超过 72 字节抛 ArgumentError（不静默截断）', () {
      expect(() => hashPassword('a' * 73), throwsArgumentError);
    });
  });

  group('verifyPassword', () {
    test('正确密码通过', () {
      expect(verifyPassword('correct horse', hashPassword('correct horse')), isTrue);
    });

    test('错误密码不通过', () {
      expect(verifyPassword('wrong', hashPassword('correct horse')), isFalse);
    });

    test('哈希格式非法返回 false 而非抛异常', () {
      expect(verifyPassword('x', 'not-a-hash'), isFalse);
    });
  });

  group('newToken', () {
    test('返回 48 位十六进制随机串且互不相同', () {
      final t = newToken();
      expect(t.length, 48);
      expect(RegExp(r'^[0-9a-f]{48}$').hasMatch(t), isTrue);
      expect(newToken(), isNot(t));
    });
  });
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `cd packages/server && dart test test/password_test.dart`
Expected: FAIL —— `hashPassword` / `verifyPassword` 未定义

- [ ] **Step 4: 实现 bcrypt 版 `password.dart`**

`packages/server/lib/src/password.dart` 全文替换为：

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:bcrypt/bcrypt.dart';

/// bcrypt 计算强度。实测目标机（2 vCPU）单次 106 ms，登录接口可接受。
const int kBcryptLogRounds = 10;

/// bcrypt 前缀。用 `$2b` 而非默认的 `$2a`——`$2a` 存在高位字符符号扩展缺陷。
const String kBcryptPrefix = r'$2b';

/// 口令最大字节数。bcrypt 只取前 72 字节，超过则拒绝而非静默截断。
const int kMaxPasswordBytes = 72;

/// 生成 bcrypt 哈希。salt 内嵌于返回值（`$2b$10$<salt><hash>`）。
///
/// 抛 [ArgumentError] 当口令超过 72 字节。
String hashPassword(String password) => BCrypt.hashpw(
    password,
    BCrypt.gensalt(prefix: kBcryptPrefix, logRounds: kBcryptLogRounds));

/// 校验口令与哈希。哈希格式非法时返回 false，不抛异常。
bool verifyPassword(String password, String hash) {
  try {
    return BCrypt.checkpw(password, hash);
  } on Object {
    return false;
  }
}

/// 随机 token（hex，48 字符）。
String newToken() => _hex(_randomBytes(24));

Uint8List _randomBytes(int n) {
  final rng = Random.secure();
  final bytes = Uint8List(n);
  for (var i = 0; i < n; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return bytes;
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd packages/server && dart test test/password_test.dart`
Expected: PASS —— 7 项通过

- [ ] **Step 6: 改 `FakeSyncStore` 用新 API，并加时序防护**

`packages/server/lib/src/fake_sync_store.dart` 中，`_User` 去掉 `salt` 字段，构造改为 `_User(this.userId, this.email, this.hash);`

`register` 改为：

```dart
  Future<AuthResult> register(String email, String password) async {
    if (_users.containsKey(email)) {
      throw StateError('email already registered');
    }
    final userId = 'u${_seq++}';
    _users[email] = _User(userId, email, hashPassword(password));
    final token = newToken();
    _tokens[token] = userId;
    return AuthResult(userId: userId, token: token);
  }
```

`login` 改为（邮箱不存在时也跑一次 bcrypt，避免用响应时间枚举已注册邮箱）：

```dart
  Future<AuthResult?> login(String email, String password) async {
    final u = _users[email];
    if (u == null) {
      // 对不存在的邮箱同样执行一次 bcrypt，使响应耗时与"密码错误"不可区分。
      hashPassword(password);
      return null;
    }
    if (!verifyPassword(password, u.hash)) return null;
    final token = newToken();
    _tokens[token] = u.userId;
    return AuthResult(userId: u.userId, token: token);
  }
```

- [ ] **Step 7: 改 handler 增加超长密码的 400 分支**

`packages/server/lib/src/handlers.dart` 中，`registerHandler` 改为：

```dart
Handler registerHandler(SyncStore store) => (req) async {
  final j = await _json(req);
  final email = j['email'] as String;
  final password = j['password'] as String;
  try {
    final r = await store.register(email, password);
    return _okJson({'userId': r.userId, 'token': r.token});
  } on StateError catch (_) {
    return _err(409, 'email already registered');
  } on ArgumentError catch (_) {
    return _err(400, 'password too long');
  }
};
```

`loginHandler` 同样补 `on ArgumentError` 分支，返回 `_err(400, 'password too long')`。

- [ ] **Step 8: 静态检查与全量测试**

Run: `cd packages/server && dart analyze && dart test`
Expected: analyze 无问题；全部测试通过（既有 13 项中密码相关用例需按新 API 调整断言）

- [ ] **Step 9: 提交**

```bash
git add packages/server
git commit -m "feat(F013):口令哈希改bcrypt,replace sha256 password hashing with bcrypt"
```

### Task 3: 库表去 salt 列

**Files:**
- Modify: `deploy/sql/schema.sql`

**Interfaces:**
- Consumes: Task 2 的 bcrypt 哈希串格式
- Produces: `users` 表结构为 `(id, email, password_hash, created_at)`

- [ ] **Step 1: 改 schema**

`deploy/sql/schema.sql` 中 `users` 表定义改为（删掉 `salt` 列）：

```sql
CREATE TABLE IF NOT EXISTS users (
    id            TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

同时更新该文件顶部注释中关于 `salt` 的描述。

- [ ] **Step 2: 在服务器重建空库**

生产库当前 0 个用户，直接删表重建无迁移负担。

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command \
  "source /root/.diary-sync-pg-credentials && export PGPASSWORD=\$PG_PASSWORD && \
   psql -h \$PG_HOST -U \$PG_USER -d \$PG_DB -c 'DROP TABLE IF EXISTS entries, tokens, users, sync_seq CASCADE'"
```

Expected: `DROP TABLE`

- [ ] **Step 3: 上传并应用新 schema**

```bash
workbench upload deploy/sql/schema.sql /root/provision/sql/schema.sql --instance-id i-7xv4buzm47fxdask0bgz
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command \
  "source /root/.diary-sync-pg-credentials && export PGPASSWORD=\$PG_PASSWORD && \
   psql -h \$PG_HOST -U \$PG_USER -d \$PG_DB -v ON_ERROR_STOP=1 -f /root/provision/sql/schema.sql"
```

Expected: 全部 `CREATE TABLE` / `CREATE INDEX` 成功

- [ ] **Step 4: 验证表结构**

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command \
  "source /root/.diary-sync-pg-credentials && export PGPASSWORD=\$PG_PASSWORD && \
   psql -h \$PG_HOST -U \$PG_USER -d \$PG_DB -c '\d users'"
```

Expected: 列只有 `id` / `email` / `password_hash` / `created_at`，**无 `salt`**

- [ ] **Step 5: 提交**

```bash
git add deploy/sql/schema.sql
git commit -m "feat(F013):users表去salt列,drop salt column from users table"
```

### Task 4: 证书签发脚本

**Files:**
- Create: `deploy/make-cert.sh`

**Interfaces:**
- Consumes: 无
- Produces: `deploy/certs/ca.key`、`deploy/certs/ca.crt`、`deploy/certs/server.key`、`deploy/certs/server.crt`、`deploy/certs/server.csr`

- [ ] **Step 1: 写脚本**

`deploy/make-cert.sh`：

```bash
#!/usr/bin/env bash
# 生成自签 CA 与服务器证书。CA 私钥只留在本机，不上传服务器。
#
# 用法：
#   bash deploy/make-cert.sh                          # 默认为 8.148.158.13
#   bash deploy/make-cert.sh --ip 1.2.3.4 --cn host  # 指定 IP 与 CN
#
# 产物在 deploy/certs/（已 .gitignore）。

set -euo pipefail

HOST_IP="8.148.158.13"
COMMON_NAME="8.148.158.13"
DAYS=3650

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip) HOST_IP="$2"; COMMON_NAME="$2"; shift 2 ;;
        --cn) COMMON_NAME="$2"; shift 2 ;;
        --days) DAYS="$2"; shift 2 ;;
        *) echo "未知参数: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${SCRIPT_DIR}/certs"
mkdir -p "${OUT}"
cd "${OUT}"

if [[ ! -f ca.key ]]; then
    echo "==> 生成 CA（私钥仅存本机）"
    openssl req -x509 -newkey rsa:4096 -nodes -days "${DAYS}" \
        -keyout ca.key -out ca.crt -subj "/CN=Local Diary App CA"
    chmod 600 ca.key
fi

echo "==> 生成服务器证书（SAN: IP:${HOST_IP}）"
openssl req -newkey rsa:2048 -nodes \
    -keyout server.key -out server.csr -subj "/CN=${COMMON_NAME}"
cat > server.ext <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:${HOST_IP}
EOF
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days "${DAYS}" -extfile server.ext
chmod 600 server.key

echo "==> 校验证书链"
openssl verify -CAfile ca.crt server.crt
openssl x509 -in server.crt -noout -subject -ext subjectAltName

echo
echo "产物在 ${OUT}"
echo "  ca.crt     -> 复制到 client/android/app/src/main/res/raw/diary_ca.crt"
echo "  server.key + server.crt -> 上传到服务器 /etc/nginx/ssl/diary-sync/"
echo "  ca.key     -> 留在本机，不要上传"
```

- [ ] **Step 2: 运行并验证**

Run: `bash deploy/make-cert.sh`
Expected: 输出 `server.crt: OK` 与 `subjectAltName=IP:8.148.158.13`

- [ ] **Step 3: 确认私钥未被 git 跟踪**

Run: `git status --short deploy/certs/`
Expected: 无输出（已被 `.gitignore` 忽略）

- [ ] **Step 4: 提交**

```bash
git add deploy/make-cert.sh
git commit -m "feat(F013):证书签发脚本,add self-signed CA and server cert script"
```

### Task 5: 客户端接入真实服务器

**Files:**
- Create: `client/lib/src/config/sync_config.dart`
- Create: `client/test/config/sync_config_test.dart`
- Create: `client/android/app/src/main/res/xml/network_security_config.xml`
- Create: `client/android/app/src/main/res/raw/diary_ca.crt`（由 Task 4 产出后复制）
- Modify: `client/android/app/src/main/AndroidManifest.xml`
- Modify: `client/lib/main.dart`

**Interfaces:**
- Consumes: Task 4 产出的 `deploy/certs/ca.crt`
- Produces: `String syncBaseUrl()`（编译期 `--dart-define=SYNC_BASE_URL` 注入）

- [ ] **Step 1: 写失败测试**

`client/test/config/sync_config_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_diary/src/config/sync_config.dart';

void main() {
  test('未注入 SYNC_BASE_URL 时回落模拟器别名', () {
    expect(syncBaseUrl(), 'http://10.0.2.2:8080');
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && powershell -NoProfile -ExecutionPolicy Bypass -File ../scripts/flutter.ps1 test test/config/sync_config_test.dart`
Expected: FAIL —— `sync_config.dart` 不存在

- [ ] **Step 3: 实现基址解析**

`client/lib/src/config/sync_config.dart`：

```dart
/// 同步服务端基址。
///
/// 编译期通过 `--dart-define=SYNC_BASE_URL=https://8.148.158.13` 注入；
/// 未注入时回落安卓模拟器访问宿主机的别名（10.0.2.2 映射到本机）。
String syncBaseUrl() => const String.fromEnvironment(
      'SYNC_BASE_URL',
      defaultValue: 'http://10.0.2.2:8080',
    );
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && powershell -NoProfile -ExecutionPolicy Bypass -File ../scripts/flutter.ps1 test test/config/sync_config_test.dart`
Expected: PASS

- [ ] **Step 5: 改 `client/lib/main.dart` 使用解析函数**

删除 `const String kSyncBaseUrl = 'http://10.0.2.2:8080';`，改为引入 `import 'src/config/sync_config.dart';`，并把两处 `kSyncBaseUrl` 替换为 `syncBaseUrl()`：

```dart
    final baseUrl = syncBaseUrl();
    final auth = EmailPasswordProvider(
      httpClient,
      baseUrl,
      InMemoryTokenStore(),
    );
    final engine = SyncEngine(
      repository: repository,
      remote: RemoteRepo(httpClient, baseUrl, const SyncCodec()),
```

- [ ] **Step 6: 建网络安全配置**

`client/android/app/src/main/res/xml/network_security_config.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- 生产环境全程禁明文 -->
    <base-config cleartextTrafficPermitted="false" />

    <!-- 安卓模拟器访问宿主机的别名，仅开发用 -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">10.0.2.2</domain>
    </domain-config>

    <!-- 系统 CA 与自签 CA 并列：只追加自签，不顶掉系统信任库 -->
    <certificates>
        <certificates src="system" />
        <certificates src="@raw/diary_ca" />
    </certificates>
</network-security-config>
```

- [ ] **Step 7: 补 INTERNET 权限并挂网络安全配置**

`client/android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 标签内加：

```xml
    <uses-permission android:name="android.permission.INTERNET"/>
```

`<application>` 标签内加：

```xml
        android:networkSecurityConfig="@xml/network_security_config"
```

- [ ] **Step 8: 把 CA 证书装进资源目录**

```bash
mkdir -p client/android/app/src/main/res/raw
cp deploy/certs/ca.crt client/android/app/src/main/res/raw/diary_ca.crt
```

- [ ] **Step 9: 静态检查与测试**

Run: `cd client && powershell -NoProfile -ExecutionPolicy Bypass -File ../scripts/flutter.ps1 analyze && powershell -NoProfile -ExecutionPolicy Bypass -File ../scripts/flutter.ps1 test`
Expected: analyze 无问题；全部测试通过

- [ ] **Step 10: 构建 release APK 验证配置生效**

```bash
cd client && powershell -NoProfile -ExecutionPolicy Bypass -File ../scripts/flutter.ps1 build apk --release --dart-define=SYNC_BASE_URL=https://8.148.158.13
```

Expected: 构建成功，产物 `build/app/outputs/flutter-apk/app-release.apk`

- [ ] **Step 11: 提交**

```bash
git add client/lib client/test client/android/app/src/main/AndroidManifest.xml \
  client/android/app/src/main/res/xml client/android/app/src/main/res/raw/diary_ca.crt
git commit -m "feat(F013):客户端接入真实服务器,wire client to real sync server"
```

### Task 6: 部署产物

**Files:**
- Create: `deploy/nginx/diary-sync.conf`
- Modify: `deploy/diary-sync.service`
- Create: `deploy/deploy-app.sh`

**Interfaces:**
- Consumes: Task 1 产出的 `bin/server.dart` 入口与 `PORT` 环境变量；Task 4 产出的证书
- Produces: 可在服务器一键执行的部署脚本 `deploy/deploy-app.sh`

- [ ] **Step 1: 写 nginx 配置**

`deploy/nginx/diary-sync.conf`：

```nginx
# F013 同步服务反向代理。只对外暴露 443，应用本身只听 127.0.0.1:8080。
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/diary-sync/server.crt;
    ssl_certificate_key /etc/nginx/ssl/diary-sync/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # 日记正文可能较长，放宽请求体上限
    client_max_body_size 8m;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }
}
```

- [ ] **Step 2: 改 systemd 单元**

`deploy/diary-sync.service` 全文替换为：

```ini
[Unit]
Description=F013 云同步服务端 (Dart shelf)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=diary
Group=diary
WorkingDirectory=/opt/diary-sync
EnvironmentFile=-/etc/diary-sync/server.env
ExecStart=/opt/diary-sync/bin/server
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/var/lib/diary-sync

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: 写部署脚本**

`deploy/deploy-app.sh`：

```bash
#!/usr/bin/env bash
# 在服务器上部署 F013 同步服务：拉代码 → 装依赖 → 静态检查 → 测试 → 编译 → 装服务 → 启动。
# 幂等：重复执行安全。
#
# 用法：bash deploy-app.sh [仓库地址] [分支]
set -euo pipefail

REPO="${1:-https://github.com/Takina-1/wright-down.git}"
BRANCH="${2:-feat/F013-cloud-sync}"

APP_DIR=/opt/diary-sync
SRC_DIR="${APP_DIR}/src"
RUN_USER=diary

log() { printf '\n==> %s\n' "$*"; }

[[ "$(id -u)" -eq 0 ]] || { echo "必须以 root 运行" >&2; exit 1; }

export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PATH=/opt/dart-sdk/bin:$PATH

log "拉取代码（${BRANCH}）"
if [[ -d "${SRC_DIR}/.git" ]]; then
    git -C "${SRC_DIR}" fetch --all --prune
    git -C "${SRC_DIR}" checkout "${BRANCH}"
    git -C "${SRC_DIR}" pull --ff-only origin "${BRANCH}"
else
    mkdir -p "${APP_DIR}"
    git clone --branch "${BRANCH}" "${REPO}" "${SRC_DIR}"
fi

log "安装依赖"
cd "${SRC_DIR}/packages/server"
dart pub get

log "静态检查"
dart analyze

log "跑测试"
dart test

log "编译可执行文件"
mkdir -p "${APP_DIR}/bin"
dart compile exe bin/server.dart -o "${APP_DIR}/bin/server"
chown -R "${RUN_USER}:${RUN_USER}" "${APP_DIR}"

log "安装 systemd 单元"
install -m 644 "${SRC_DIR}/deploy/diary-sync.service" /etc/systemd/system/diary-sync.service
install -d -m 755 /etc/diary-sync
[[ -f /etc/diary-sync/server.env ]] || echo "PORT=8080" > /etc/diary-sync/server.env
chmod 644 /etc/diary-sync/server.env
systemctl daemon-reload
systemctl enable diary-sync
systemctl restart diary-sync

log "健康检查"
sleep 3
curl -sS -o /dev/null -w "本机 8080 返回 %{http_code}\n" "http://127.0.0.1:8080/sync?cursor=0"
systemctl is-active --quiet diary-sync && echo "diary-sync 运行中" || { echo "diary-sync 未运行" >&2; exit 1; }

log "完成"
```

- [ ] **Step 4: 语法检查**

Run: `bash -n deploy/deploy-app.sh && bash -n deploy/make-cert.sh`
Expected: 无输出（语法通过）

- [ ] **Step 5: 提交**

```bash
git add deploy/nginx/diary-sync.conf deploy/diary-sync.service deploy/deploy-app.sh
git commit -m "feat(F013):服务端部署产物,add nginx config systemd unit and deploy script"
```

### Task 7: 服务器部署与接口级验证

**Files:** 无代码改动（验证任务）

- [ ] **Step 1: 上传证书并安装 nginx 配置**

`ca.crt` 是签发者证书（公钥，客户端也用它），必须一并上传——校验证书链时 `--cacert` 要指向它，不是 `server.crt`。

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command "mkdir -p /etc/nginx/ssl/diary-sync"
workbench upload deploy/certs/ca.crt     /etc/nginx/ssl/diary-sync/ca.crt     --instance-id i-7xv4buzm47fxdask0bgz
workbench upload deploy/certs/server.crt /etc/nginx/ssl/diary-sync/server.crt --instance-id i-7xv4buzm47fxdask0bgz
workbench upload deploy/certs/server.key /etc/nginx/ssl/diary-sync/server.key --instance-id i-7xv4buzm47fxdask0bgz
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command "chmod 600 /etc/nginx/ssl/diary-sync/server.key"
```

```bash
workbench upload deploy/nginx/diary-sync.conf /etc/nginx/conf.d/diary-sync.conf --instance-id i-7xv4buzm47fxdask0bgz
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command "nginx -t && systemctl enable --now nginx && systemctl reload nginx"
```

Expected: `nginx: configuration file /etc/nginx/nginx.conf test is successful`

> 上传前先 `workbench exec` 删除远端同名文件——`workbench upload` 对已存在文件会提示覆盖确认，非交互下直接中止。

> **证书名与连接地址**：服务器证书的 SAN 是 `IP:8.148.158.13`，用 `https://127.0.0.1` 访问会因主机名不匹配而校验失败。后续所有本机 curl 一律用 `--resolve 8.148.158.13:443:127.0.0.1`——照样连本机，但按 `8.148.158.13` 做证书名校验。

- [ ] **Step 2: 跑部署脚本**

```bash
workbench upload deploy/deploy-app.sh /root/deploy-app.sh --instance-id i-7xv4buzm47fxdask0bgz
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command "bash /root/deploy-app.sh"
```

Expected: 拉代码、装依赖、analyze、test、编译、装单元、启动全部成功，最后打印 `本机 8080 返回 401`（无 token 的 `/sync` 应返回 401）

> 部署脚本用 `git clone` 拉仓库，要求本轮改动已 push 到远端 `feat/F013-cloud-sync`。若尚未 push，先在本地 `git push`。

- [ ] **Step 3: 验证 DP-01 证书链**

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command \
  "curl -sS --cacert /etc/nginx/ssl/diary-sync/ca.crt \
   --resolve 8.148.158.13:443:127.0.0.1 \
   -o /dev/null -w 'TLS 校验结果 %{http_code}\n' 'https://8.148.158.13/sync?cursor=0'"
```

Expected: `TLS 校验结果 401`（401 说明 TLS 握手与证书链校验都通过了，401 是业务层的缺 token）

> 若报 `SSL certificate problem`，多半是 `--cacert` 指到了 `server.crt`（那是叶子证书不是签发者），或 `server.crt` 不是由 `ca.crt` 签发。核对 `openssl verify -CAfile ca.crt server.crt`。
> 若报 `certificate is not valid for 8.148.158.13`，说明证书的 SAN 没带 `IP:8.148.158.13`，需重跑 `make-cert.sh` 并重新上传。

- [ ] **Step 4: 验证 DP-02 四个接口**

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command "
set -e
BASE=https://8.148.158.13
CA=/etc/nginx/ssl/diary-sync/ca.crt
RESOLVE=8.148.158.13:443:127.0.0.1
echo '--- 注册 ---'
REG=\$(curl -sS --cacert \$CA --resolve \$RESOLVE -H 'Content-Type: application/json' \
  -d '{\"email\":\"dp@local.test\",\"password\":\"correct horse battery staple\"}' \
  \$BASE/auth/register)
echo \$REG
TOKEN=\$(echo \$REG | sed -n 's/.*\"token\":\"\([^\"]*\)\".*/\1/p')
echo \"token=\$TOKEN\"
echo '--- 登录 ---'
curl -sS --cacert \$CA --resolve \$RESOLVE -H 'Content-Type: application/json' \
  -d '{\"email\":\"dp@local.test\",\"password\":\"correct horse battery staple\"}' \
  \$BASE/auth/login
echo
echo '--- 推送 ---'
curl -sS --cacert \$CA --resolve \$RESOLVE -H 'Content-Type: application/json' \
  -H \"Authorization: Bearer \$TOKEN\" \
  -d '{\"patches\":[{\"id\":\"e-dp-1\",\"createdAt\":1700000000,\"fields\":{\"content\":{\"v\":\"链路验证\",\"t\":1}}}]}' \
  \$BASE/sync/batch
echo
echo '--- 拉取 ---'
curl -sS --cacert \$CA --resolve \$RESOLVE -H \"Authorization: Bearer \$TOKEN\" \"\$BASE/sync?cursor=0\"
"
```

Expected: 注册返回 `{"userId":...,"token":...}`；登录返回 `{"userId":...,"token":...}`；推送返回 `{"ok":true}`；拉取返回 `{"cursor":1,"entries":[{"id":"e-dp-1",...}]}`

- [ ] **Step 5: 验证 DP-09 重复注册返回 409**

> 注意：FakeSyncStore 是内存实现，**不写数据库**，所以本轮无法从 `users` 表验证 bcrypt 落库。DP-09 的落库验证要等 PostgresSyncStore 落地。本步改为验证接口行为：注册成功后重复注册返回 409，说明邮箱唯一性与 bcrypt 哈希-校验链路都通。

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command \
  "curl -sS -o /dev/null -w '重复注册返回 %{http_code}\n' --cacert /etc/nginx/ssl/diary-sync/ca.crt \
   --resolve 8.148.158.13:443:127.0.0.1 -H 'Content-Type: application/json' \
   -d '{\"email\":\"dp@local.test\",\"password\":\"another one\"}' https://8.148.158.13/auth/register"
```

Expected: `重复注册返回 409`

- [ ] **Step 6: 验证 DP-10 超长密码返回 400**

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command "
LONG=\$(printf 'a%.0s' \$(seq 1 73))
curl -sS -o /dev/null -w '超长密码注册返回 %{http_code}\n' --cacert /etc/nginx/ssl/diary-sync/ca.crt \
  --resolve 8.148.158.13:443:127.0.0.1 -H 'Content-Type: application/json' \
  -d \"{\\\"email\\\":\\\"long@local.test\\\",\\\"password\\\":\\\"\$LONG\\\"}\" https://8.148.158.13/auth/register"
```

Expected: `超长密码注册返回 400`（不是 500）

- [ ] **Step 7: 验证 DP-11 时序防护**

不存在的邮箱与错误密码的响应耗时应无显著差异（两者都跑一次 bcrypt）。

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command "
CURL='curl -sS -o /dev/null --cacert /etc/nginx/ssl/diary-sync/ca.crt --resolve 8.148.158.13:443:127.0.0.1 -H Content-Type:application/json'
echo '--- 不存在的邮箱 ---'
for i in 1 2 3; do
  /usr/bin/time -f '  用时 %e s' \$CURL -d '{\"email\":\"nobody@local.test\",\"password\":\"whatever\"}' https://8.148.158.13/auth/login
done
echo '--- 错误密码 ---'
for i in 1 2 3; do
  /usr/bin/time -f '  用时 %e s' \$CURL -d '{\"email\":\"dp@local.test\",\"password\":\"wrong password\"}' https://8.148.158.13/auth/login
done
"
```

Expected: 两组耗时都落在同一量级（bcrypt cost 10 约 0.1 s）。若「不存在的邮箱」明显快于「错误密码」，说明时序防护没生效，回查 `FakeSyncStore.login` 是否在 `u == null` 分支调用了 `hashPassword`。

> `/usr/bin/time` 若不存在，用 `date +%s%N` 前后相减代替。

- [ ] **Step 8: 验证 DP-03 服务自启**

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command \
  "systemctl restart diary-sync && sleep 3 && systemctl is-active diary-sync && \
   curl -sS -o /dev/null -w '重启后 8080 返回 %{http_code}\n' 'http://127.0.0.1:8080/sync?cursor=0'"
```

Expected: `active` + `重启后 8080 返回 401`

- [ ] **Step 9: 验证 DP-04 端口边界**

从本地探测外部：

```bash
for p in 443 8080; do timeout 4 bash -c "exec 3<>/dev/tcp/8.148.158.13/$p" 2>/dev/null && echo "  $p OPEN" || echo "  $p closed"; done
```

Expected: `443 OPEN`、`8080 closed`

> 若 443 未开，说明阿里云安全组尚未放行 443，需在控制台安全组加 TCP 443 入方向规则（源 `0.0.0.0/0`）。

- [ ] **Step 10: 记录验证结果**

### Task 8: 真机验证

**Files:** 无代码改动（验证任务）

- [ ] **Step 1: 构建并安装 APK**

```bash
cd client && powershell -NoProfile -ExecutionPolicy Bypass -File ../scripts/flutter.ps1 build apk --release --dart-define=SYNC_BASE_URL=https://8.148.158.13
.tooling/android-sdk/platform-tools/adb.exe install -r client/build/app/outputs/flutter-apk/app-release.apk
```

Expected: `Success`

- [ ] **Step 2: 启动应用并确认无证书错误**

```bash
.tooling/android-sdk/platform-tools/adb.exe shell am start -n dev.localdiary.local_diary/.MainActivity
.tooling/android-sdk/platform-tools/adb.exe logcat -d -t 300 | grep -iE "SSL|Handshake|CERT|UnknownHost" | head -20
```

Expected: 无 SSL / 握手 / 证书错误日志

- [ ] **Step 3: 验证 DP-05 登录**

在应用内用 `dp@local.test` / `correct horse battery staple` 登录。

Expected: 登录成功，界面进入同步就绪状态

- [ ] **Step 4: 验证 DP-06 推送**

在应用内新建一篇日记并保存。

- [ ] **Step 5: 验证 DP-07 curl 充当第二设备**

用真机登录取得的 token 从服务端拉取：

```bash
workbench exec --instance-id i-7xv4buzm47fxdask0bgz --command \
  "curl -sS --cacert /etc/nginx/ssl/diary-sync/ca.crt --resolve 8.148.158.13:443:127.0.0.1 \
   -H 'Authorization: Bearer <真机token>' 'https://8.148.158.13/sync?cursor=0'"
```

Expected: 返回的 `entries` 中能看到真机刚写的日记，`cursor` 大于 0

> 取 token 的办法：应用未提供查看入口时，在服务端临时打日志；或用同一账号在服务端重新登录换一枚 token——FakeSyncStore 每次登录都发新 token，故重新登录得到的 token 同样有效。

- [ ] **Step 6: 验证 DP-08 模拟器开发不受影响**

静态确认 `client/lib/src/config/sync_config.dart` 的默认值仍为 `http://10.0.2.2:8080`，且 `network_security_config.xml` 中 `10.0.2.2` 仍在 `cleartextTrafficPermitted="true"` 的 domain-config 里。

### Task 9: 测试报告与台账更新

**Files:**
- Modify: `docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md`
- Modify: `docs/features/README.md`

- [ ] **Step 1: 在测试报告新增本轮章节**

记录：执行时间、被测 commit、DP-01~DP-11 逐项的实际输出与结论、已知代价（FakeSyncStore 内存存储、客户端 token 无过期）、未执行项（跨设备真机同步、真机 OSS、DP-09 的落库验证）。

**未执行的项不得写「通过」**，按项目规范记「未执行」。

- [ ] **Step 2: 更新台账 F013 行**

`docs/features/README.md` 中 F013 状态按实际推进情况更新，注明本轮完成：ECS 部署链路打通 + bcrypt 替换；仍延后：PostgresSyncStore（含 DP-09 落库验证）、真机 OSS、token 刷新、跨设备真机验收。

- [ ] **Step 3: 提交**

```bash
git add docs/test-reports docs/features/README.md
git commit -m "docs(F013):登记部署链路与bcrypt验收,record deployment chain and bcrypt acceptance"
```

---

## 11. 已知限制与后续

- 本轮服务端用 FakeSyncStore（内存），重启丢数据；PostgresSyncStore 与真机 OSS 是下一轮
- 客户端 `InMemoryTokenStore`，App 重启需重新登录；token 无过期与刷新（AC-08）仍延后
- 客户端 release 构建目前用 debug keys 签名，正式发布前需配置真实签名
- 服务器证书绑死 IP `8.148.158.13`；IP 变更需重签并更新 App 内置 CA
- 实例仍是 `ecs.e-c1m1.large`（1.6 GiB 突发型），正式承载数据库前建议变配到 `ecs.g7.large`
