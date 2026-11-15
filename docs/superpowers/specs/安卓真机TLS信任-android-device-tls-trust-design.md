# 安卓真机 TLS 信任自签 CA · android device tls trust

- 关联功能：F013 云同步最小闭环（本次在其分支上执行，见 §7 分支与编号）
- 关联文档：[云同步设计](云同步设计-cloud-sync-design.md) · [腾讯云 COS 设计](腾讯云COS对象存储-tencent-cos-storage-design.md) · [F013 待办登记](../features/F013-待办-todos.md) · [F013 测试报告](../test-reports/F013-云同步测试报告-cloud-sync-test-report.md) · [部署链路计划](../superpowers/plans/云同步-部署链路-ecs-deploy.md)
- 日期：2026-11-10
- 状态：已实现（2026-11-15，含真机验收证据）

## 1. 背景

F013 真机验收（T-01/T-02）在 2026-11-10 第十轮被标记为「服务端等效已过 / 真机 UI 待补」，阻塞原因是 MIUI 装机弹窗。2026-11-10 第十一轮真机调试中，MIUI 阻塞已绕过（见 §2），App 成功装到小米 2211133C 并启动 —— 但**真机注册失败**，暴露出一个此前从未被触达的真实代码缺陷。

### 2. MIUI 装机阻塞的绕过方式（已验证）

`adb install` / `pm install` 在本机（非 root）均返回 `INSTALL_FAILED_USER_RESTRICTED`，MIUI 定制安装器强制人工确认。绕过方式（2026-11-10 实测）：

1. `adb push <apk> /sdcard/Download/local-diary-debug.apk`
2. `adb shell am start -a android.intent.action.VIEW -d file:///sdcard/Download/local-diary-debug.apk -t application/vnd.android.package-archive`
3. MIUI 安装器 UI 拉起后自行完成安装（本次无需人工点按）

`pm install-create` / `pm install-write` / `pm install-commit` 的 session 路径同样被 `INSTALL_FAILED_USER_RESTRICTED` 拦截，不可用。

### 3. 缺陷现象

App 内填邮箱密码 → 点「注册」→ 立即显示「注册失败，请重试」。服务端 `nginx access.log` 中**没有任何来自 Dart 客户端的请求**（仅有 `curl/8.19.0` 与 `curl/8.8.0-DEV`），`journalctl -u diary-sync` 无条目。

### 4. 根因（实测证据链）

客户端**确实建立了 TCP 连接**并完成了 ClientHello，服务器也回发了证书链，但客户端**在收到证书后直接 FIN**，握手未完成 —— 典型的证书校验失败中止。

| # | 证据 | 结论 |
|---|---|---|
| E-1 | 服务端 `tcpdump -i eth0 'tcp port 443'`：App 发起 SYN → 发 ClientHello（1640 B）→ 服务器回发证书链（1650 B）→ **客户端发 FIN**，握手未完成 | 失败发生在 TLS 证书校验阶段，非 DNS/路由/明文拦截 |
| E-2 | 设备 `curl -sk https://8.148.158.13/sync` → HTTP 401（通）；`curl` 不加 `-k` → `SSL certificate problem: unable to get local issuer certificate` | 设备**系统信任库**不含 `CN=Local Diary App CA` |
| E-3 | 设备 `/system/etc/security/cacerts/` 有 145 个系统 CA、无本 CA；`/data/misc/user/0/cacerts-added` 为 0；MIUI 无 `cmd credential` 子命令 | 无法把 CA 装进设备信任库（方案 B 不可行） |
| E-4 | `client/android/app/src/main/res/raw/diary_ca.crt` 与 `deploy/certs/ca.crt` **字节完全相同**，SHA-256 指纹均为 `7C:ED:3A:85:76:78:04:44:93:82:7C:1D:74:1B:73:BB:E2:51:2D:D3:79:83:C8:01:43:6E:45:C0:4A:1F:7E:00`；服务器证书 `CN=8.148.158.13`（SAN 含 `IP:8.148.158.13`），`openssl verify -CAfile ca.crt` → `Verification: OK` | 证书链本身正确，问题在**客户端信任该 CA 的机制** |
| E-5 | `libflutter.so` 中 `networkSecurityConfig` 出现 **0** 次；`dart:io` 直接读 `/system/etc/security/cacerts` | **Flutter 的 Dart 网络层不读 `network_security_config.xml`** |

**根因**：现有方案依赖 `network_security_config.xml` 的 `<certificates src="@raw/diary_ca"/>` 来信任自签 CA。该文件**只对 Android 原生网络栈（OkHttp / `HttpsURLConnection` / WebView）生效**，对 Flutter 的 `dart:io` 网络栈**完全无效** —— 后者直接读系统信任库。于是 App 的所有 Dart 出站请求都无法验证服务器证书。

这解释了为什么此前六轮验收全部「服务端等效通过、真机 UI 待补」：服务端链路从未被真正质疑，而真机一次都没真正跑通。

## 5. 方案选型

| 方案 | 说明 | 结论 |
|---|---|---|
| **A. Dart 侧显式信任锚点** | `SecurityContext(withTrustedRoots: true)` + `setTrustedCertificatesBytes(caPem)`，`HttpClient(context: ctx)` → `IOClient` | **采纳**。一次构造全链路生效；无需 root / 无需每台设备配置 / 不改服务端 |
| B. 把 CA 装进设备信任库 | 依赖 `cmd credential install-ca-cert` 或手动导入 | 拒绝：MIUI 无该子命令（E-3）；需每台设备手动操作，与「一个 APK 多人测试」冲突 |
| C. 服务器换公开可信证书 | 域名 + Let's Encrypt，自动续期 | 延后：公开分发前的正解，但需域名与证书运维，非本轮范围 |
| D. 固定服务器叶证书（而非 CA） | 只信任某一张 server.crt | 拒绝：证书重签即失效；`deploy/make-cert.sh` 的模型本就是 CA |

## 6. 设计

### 6.1 信任语义

**系统 CA ∪ 自签 CA**，与现有 `network_security_config.xml` 中「`<certificates src="system"/>` 与 `src="@raw/diary_ca"` 并列」的意图一致 —— 不收窄也不放大既有信任面，只补上缺失的一条。

实现上以 `SecurityContext(withTrustedRoots: true)` 起手（等价 `defaultContext`，含平台信任库），再 `setTrustedCertificatesBytes` 追加自签 CA。Dart SDK `security_context.dart` 明确说明：当需要在可信根之上追加证书时用 `withTrustedRoots` 而非 `defaultContext`。

### 6.2 CA 分发

```
deploy/certs/ca.crt                  （源，gitignore，CA 私钥仅存本机）
      ├─ make-cert.sh 自动复制 ─→ client/android/app/src/main/res/raw/diary_ca.crt   （已入库，原生栈用，保留）
      └─ make-cert.sh 自动复制 ─→ client/assets/diary_ca.crt                          （本轮新增，入库，Dart 层用）
```

`res/raw/diary_ca.crt` **保留不动**：原生栈（OkHttp / WebView）仍可能需要它，删除反而缩小可用面。

`client/assets/diary_ca.crt` 是 CA **公钥证书**，本身已在 `res/raw/diary_ca.crt` 入库，新增它**不扩大密钥面**；生产 CA 私钥 `deploy/certs/ca.key` 继续 gitignore、不入库、不上服务器。

### 6.3 组件

**新增 `client/lib/src/data/remote/tls_trust.dart`** —— 唯一职责：产出可信 `http.Client`。

```dart
/// TLS 信任锚点：系统 CA ∪ 自签 CA。
///
/// 为什么不用 network_security_config.xml：那份配置只对 Android 原生网络栈
/// 生效，Flutter 的 dart:io 直接读 /system/etc/security/cacerts，不看它。
/// 详见 docs/superpowers/specs/安卓真机TLS信任-android-device-tls-trust-design.md。
class TlsTrust {
  static final TlsTrust instance = TlsTrust._();

  Future<http.Client>? _client;   // 幂等：重复调用返回同一实例

  /// 构造（并缓存）可信 client。
  Future<http.Client> client() async => _client ??= _build();

  Future<http.Client> _build() async {
    final pem = await rootBundle.load('assets/diary_ca.crt');
    final ctx = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(pem.buffer.asUint8List());
    return IOClient(HttpClient(context: ctx));
  }
}
```

**`client/pubspec.yaml`**：`flutter:` 下新增 `assets: - assets/diary_ca.crt`。

**`client/lib/main.dart`**：`http.Client()` → `await TlsTrust.instance.client()`。

**`client/lib/src/data/sync/cos_gateway_http.dart`**：无参兜底 `http.Client()` 改为惰性取同一可信 client（`_send` 已是 async，构造器保持同步，**现有测试零改动**）。不改会让照片代理静默走不受信 client —— 与本缺陷同款陷阱。

### 6.4 数据流

```
main.dart  _open()
  └─ await TlsTrust.instance.client()
        └─ rootBundle.load('assets/diary_ca.crt')      ← 唯一 CA 读取点
        └─ SecurityContext(withTrustedRoots:true) + 追加自签 CA
        └─ IOClient(HttpClient(context: ctx))
              ├─→ EmailPasswordProvider   （注册 / 登录 / 刷新）
              ├─→ RemoteRepo              （push / pull）
              └─→ HttpCosGateway          （照片上传 / 下载）
```

三个出口共用同一 client：一次 trust 构造，全链路生效。

### 6.5 错误处理

`TlsTrust._build()` 抛出的异常**不吞**：由 `main.dart` 的 `FutureBuilder` 走既有 `hasError` 分支。但该分支现文案为「暂时无法打开本地存储」，会把 TLS 问题误导成存储问题 → **改为「暂时无法准备同步环境」并带出底层原因**。

单请求失败（证书仍不被信任等）：`RemoteRepo._send` 抛出的 `HandshakeException` 目前被 `login_page` 的 `catch (_)` 吞掉，只显示「注册失败，请重试」。**本轮不修**（范围仅核心 TLS），但登记为 F013 待办项 —— 否则下次同类问题又要从头排查。

## 7. 分支与编号

- 功能编号：复用 **F013**（不新开编号）
- 分支：`feat/F013-android-tls-trust`，从最新 `main` 创建
- 提交：`fix(F013):真机TLS信任自签CA,fix device TLS trust for self-signed CA`

## 8. 测试策略

| 层 | 手段 | 验证内容 |
|---|---|---|
| 单元 | `client/test/data/remote/tls_trust_test.dart` | asset 存在且为合法 PEM；用 `TlsTrust` 构造的 client 能成功连接**本地 TLS 测试服务器**（`HttpServer.bindSecure`，测试专用 CA 签发的证书） |
| 集成 | 真机重装 APK → App 内注册 | 端到端：TLS 握手通过、服务端收到 `POST /auth/register`、nginx 日志出现 Dart UA |
| 回归 | `flutter test` 全量 + `dart analyze` | 不破坏既有 458 项测试；静态分析干净 |

**本地 TLS 测试服务器**：起一个 `HttpServer.bindSecure`，其证书由**测试专用 CA** 签发（SAN 含 `localhost`），客户端用 `TlsTrust` 构造的 client 连接。测试专用 CA 与私钥入库 `client/test/fixtures/tls/`，与生产 CA 完全无关（生产 `ca.key` 继续 gitignore 且不在服务器上）。业界常规做法；本仓库的先例是「私钥入库」。

**CA 指纹一致性**：测试断言 `assets/diary_ca.crt` 与 `android/app/src/main/res/raw/diary_ca.crt` 字节相同 —— 二者同源于 `make-cert.sh`，防止手工编辑导致漂移。

## 9. 验收标准

1. `dart analyze` 干净；`flutter test` 全量通过（含新增测试）
2. 真机安装 debug APK，App 内注册**成功**，服务端数据库可查到该用户
3. nginx `access.log` 出现 `POST /auth/register`，User-Agent 为 `Dart/3.13.7 (dart:io)`（`dart:io` 默认 UA；此前日志里只有 `curl/8.19.0` 与 `curl/8.8.0-DEV`）
4. 真机写一篇日记 → `POST /sync/batch` 到达服务端 → 拉回可见（顺带覆盖 T-02）
5. `make-cert.sh` 重新执行后，CA 三处副本（`deploy/certs/ca.crt`、`res/raw/diary_ca.crt`、`assets/diary_ca.crt`）保持一致

## 10. 风险与后续

| # | 风险 / 后续项 | 说明 |
|---|---|---|
| R-1 | **私有 CA 内嵌于 APK** | 任何人反编译 APK 即可提取该 CA 公钥。若 APK 外泄，它等同于「信任任意人自签证书」的钥匙。本轮定位为内测分发可接受；**公开分发前必须改用公开可信证书**（方案 C）→ 登记为 F013 待办 |
| R-2 | 登录/注册失败吞掉真实原因 | `login_page` 的 `catch (_)` 只显示「注册失败，请重试」→ 登记为 F013 待办 |
| R-3 | 未登录时状态误显示「已同步」 | `triggerPull` 在 `_me()` 返回 null 时提前返回、不抛异常，状态被置为 `synced` → 登记为 F013 待办 |
| R-4 | 服务器证书绑死 IP `8.148.158.13` | IP 变更需重签并重发 APK（既有 T-14，本轮不变） |
