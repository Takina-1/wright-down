# 安卓真机 TLS 信任自签 CA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Flutter 客户端在真机上信任自签 CA，从而能连上 `https://8.148.158.13` 完成注册/登录/同步 —— 打通 F013 的 T-01/T-02 真机验收。

**Architecture:** 新增 `TlsTrust` 单例，用 `SecurityContext(withTrustedRoots: true)` 起手（系统 CA）再 `setTrustedCertificatesBytes` 追加自签 CA，产出唯一可信 `http.Client`；`main.dart`、`HttpCosGateway` 共用它。CA 证书以 Flutter asset 形式随包分发（`client/assets/diary_ca.crt`）。

**Tech Stack:** Flutter 3.47.8 / Dart 3.13.7 · `dart:io` `SecurityContext` / `HttpClient` · `package:http` 的 `IOClient` · `package:flutter/services` 的 `rootBundle` · OpenSSL（生成测试证书）

**设计文档：** [安卓真机 TLS 信任自签 CA](../specs/安卓真机TLS信任-android-device-tls-trust-design.md)

## Global Constraints

- **分支**：`feat/F013-android-tls-trust`（已创建，从最新 `main` `f6f44d1` 切出）。功能编号复用 **F013**。
- **命令入口**：所有 Flutter/Dart 命令走 `D:/dev/myapp/scripts/flutter.ps1`（PowerShell 包装，已配置 `PUB_CACHE` / `GRADLE_USER_HOME` / `ANDROID_HOME` / `JAVA_HOME` / 国内镜像）。在 `client/` 目录下执行时用 `..\\scripts\\flutter.ps1`。
- **Bash 下的等价调用**（本会话使用）：
  ```bash
  powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" test
  powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" analyze
  ```
- **提交信息格式**：`<type>:<中文说明>,<english summary>`，中英结合，英文用祈使句。需标注功能编号时写成 `fix(F013):...,...`。
- **注释语言**：代码注释用中文，与既有 `client/lib/` 风格一致。
- **文档命名**：`<中文主题>-<english-topic>.md`；功能文档保留最前面的 `F编号-`。
- **不提交**：生产 CA 私钥（`deploy/certs/ca.key` 继续 gitignore、不入库、不上服务器）；会话日志 `.txt` 文件。
- **基线**：改动前 `flutter test` 全量 **458 项通过**、`flutter analyze` 仅有 pre-existing 警告。新增测试后总数应 ≥ 458 + 本计划新增数。
- **已知环境事实**（本会话实测，勿重复踩坑）：
  - `rootBundle.load()` 返回 **`ByteData`**，不是 `List<int>`。取字节须用 `data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)`。
  - `flutter test` 里用 `rootBundle` 必须在 `main()` 首行调 `TestWidgetsFlutterBinding.ensureInitialized()`，否则抛 `BindingBase.checkInstance`。
  - Git Bash 会把 `openssl -subj "/CN=..."` 的 `/CN=` 误转成路径 → 生成证书须加 `export MSYS_NO_PATHCONV=1`。
  - `keyUsage` 扩展值须为 `digitalSignature,keyEncipherment`（写成 `keyUsage=keyEncipherment` 会报 `unknown bit string argument`）。

---

### Task 1: 测试专用 TLS 夹具（CA + localhost 服务器证书）

**Files:**
- Create: `client/test/fixtures/tls/generate.sh`
- Create: `client/test/fixtures/tls/test_ca.crt`
- Create: `client/test/fixtures/tls/test_ca.key`
- Create: `client/test/fixtures/tls/test_server.crt`
- Create: `client/test/fixtures/tls/test_server.key`
- Create: `client/test/fixtures/tls/README.md`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: 夹具文件路径常量，供 Task 2 的测试引用：
  - `client/test/fixtures/tls/test_ca.crt` — 测试专用 CA 证书（公钥）
  - `client/test/fixtures/tls/test_ca.key` — 测试专用 CA 私钥（**仅测试用**，与生产 `deploy/certs/ca.key` 无关）
  - `client/test/fixtures/tls/test_server.crt` — 由测试 CA 签发，SAN `DNS:localhost, IP:127.0.0.1`
  - `client/test/fixtures/tls/test_server.key` — 服务器私钥

- [ ] **Step 1: 写生成脚本**

创建 `client/test/fixtures/tls/generate.sh`：

```bash
#!/usr/bin/env bash
# 生成测试专用 CA 与 localhost 服务器证书。
#
# 用途：tls_trust_test.dart 起一个本地 TLS 服务器，验证客户端的 Dart 侧
# 信任锚点确实生效（dart:io 不读 network_security_config.xml）。
#
# 与生产 CA 完全无关：生产 CA 私钥在 deploy/certs/ca.key（gitignore、
# 不入库、不上服务器）。本目录的私钥仅供自动化测试使用。
#
# 用法：bash client/test/fixtures/tls/generate.sh
set -euo pipefail

# Git Bash 会把 openssl -subj 的 "/CN=..." 误转成 Windows 路径。
export MSYS_NO_PATHCONV=1

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${DIR}"

rm -f ./*.crt ./*.key ./*.csr ./*.srl ./*.ext

echo "==> 生成测试 CA"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout test_ca.key -out test_ca.crt -subj "/CN=Test Diary CA"

echo "==> 生成 localhost 服务器证书"
openssl req -newkey rsa:2048 -nodes \
    -keyout test_server.key -out test_server.csr -subj "/CN=localhost"
cat > test_server.ext <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
EOF
openssl x509 -req -in test_server.csr \
    -CA test_ca.crt -CAkey test_ca.key -CAcreateserial \
    -out test_server.crt -days 3650 -extfile test_server.ext

echo "==> 校验证书链"
openssl verify -CAfile test_ca.crt test_server.crt
openssl x509 -in test_server.crt -noout -subject -ext subjectAltName

rm -f test_server.csr test_server.ext test_ca.srl
echo "==> 完成：${DIR}"
```

- [ ] **Step 2: 执行脚本生成夹具**

Run:
```bash
export MSYS_NO_PATHCONV=1
cd D:/dev/myapp && bash client/test/fixtures/tls/generate.sh
```

Expected 输出（末尾）：
```
==> 校验证书链
test_server.crt: OK
subject=CN=localhost
X509v3 Subject Alternative Name:
    DNS:localhost, IP Address:127.0.0.1
==> 完成：...
```

- [ ] **Step 3: 确认文件齐全**

Run:
```bash
ls -la D:/dev/myapp/client/test/fixtures/tls/
```
Expected: 存在 `test_ca.crt`、`test_ca.key`、`test_server.crt`、`test_server.key`、`generate.sh`；**不存在** `test_server.csr` / `test_server.ext` / `test_ca.srl`（脚本已清理）。

- [ ] **Step 4: 写夹具 README**

创建 `client/test/fixtures/tls/README.md`：

```markdown
# 测试专用 TLS 夹具 · test tls fixtures

本目录为 **自动化测试专用** 的 CA 与 localhost 服务器证书。

## 为什么需要

Flutter 的 `dart:io` 网络栈**不读** `network_security_config.xml`，只信任 Android
系统 CA 库。生产环境用自签 CA（`CN=Local Diary App CA`）时，客户端必须在 Dart 侧
显式追加信任锚点才能连上 `https://8.148.158.13`。

`tls_trust_test.dart` 用本目录的证书起一个本地 TLS 服务器，真实验证「Dart 侧
信任锚点生效」这条路径 —— 只测 asset 存在是测不出来的。

## 与生产 CA 的关系

**完全无关。** 本目录的 `test_ca.key` 仅用于测试；生产 CA 私钥在
`deploy/certs/ca.key`，已被 `.gitignore` 排除，不入库、不上服务器。

## 安全说明

测试私钥入库是业界常规做法（与「生产私钥入库」性质不同）。任何人拿到本目录的
私钥只能伪造 `localhost` 的测试证书，无法冒充生产服务器
（生产 CA 私钥不在库内）。

## 重新生成

```bash
bash client/test/fixtures/tls/generate.sh
```

Git Bash 下需 `export MSYS_NO_PATHCONV=1`（脚本内部已处理），否则 `openssl -subj`
的 `/CN=` 会被误转成 Windows 路径。
```

- [ ] **Step 5: 提交**

```bash
cd D:/dev/myapp
git add client/test/fixtures/tls/
git commit -m "test(F013):新增TLS测试夹具,add TLS test fixtures"
```

---

### Task 2: `TlsTrust` —— Dart 侧信任锚点

**Files:**
- Create: `client/lib/src/data/remote/tls_trust.dart`
- Create: `client/test/data/remote/tls_trust_test.dart`
- Modify: `client/pubspec.yaml`（`flutter:` 下新增 `assets:`）
- Create: `client/assets/diary_ca.crt`

**Interfaces:**
- Consumes: Task 1 的夹具（`test/fixtures/tls/test_ca.crt`、`test_server.crt`、`test_server.key`）
- Produces:
  ```dart
  /// 产出可信 http.Client（系统 CA ∪ 自签 CA）。
  class TlsTrust {
    static final TlsTrust instance = TlsTrust._();

    /// 内嵌自签 CA 的 asset 路径。
    static const String caAssetPath = 'assets/diary_ca.crt';

    /// 构造（并缓存）可信 client。重复调用返回同一实例。
    Future<http.Client> client();

    /// 供测试注入自定义信任锚点：extraPems 每项是一张 PEM 证书的字节，
    /// 与内置自签 CA 一并追加到系统 CA 之上。
    Future<http.Client> clientWithTrustedCerts(List<List<int>> extraPems);
  }
  ```
  Task 3 消费 `TlsTrust.instance.client()`。

- [ ] **Step 1: 把生产 CA 拷进 assets**

Run:
```bash
cd D:/dev/myapp && cp deploy/certs/ca.crt client/assets/diary_ca.crt 2>/dev/null || {
  mkdir -p client/assets && cp deploy/certs/ca.crt client/assets/diary_ca.crt; }
```
Expected: `client/assets/diary_ca.crt` 存在。

若 `deploy/certs/ca.crt` 不存在（开发机未跑过 `deploy/make-cert.sh`），改用已入库的同一份证书：
```bash
cd D:/dev/myapp && mkdir -p client/assets && cp client/android/app/src/main/res/raw/diary_ca.crt client/assets/diary_ca.crt
```
（两者字节相同，SHA-256 指纹均为 `7C:ED:3A:85:76:78:04:44:93:82:7C:1D:74:1B:73:BB:E2:51:2D:D3:79:83:C8:01:43:6E:45:C0:4A:1F:7E:00`。）

- [ ] **Step 2: 在 pubspec 声明 asset**

修改 `client/pubspec.yaml`，把

```yaml
flutter:
  uses-material-design: true
```

改为

```yaml
flutter:
  uses-material-design: true
  # 自签 CA 证书：Dart 侧 TLS 信任锚点来源（dart:io 不读 network_security_config.xml）。
  assets:
    - assets/diary_ca.crt
```

- [ ] **Step 3: 写失败的测试**

创建 `client/test/data/remote/tls_trust_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:local_diary/src/data/remote/tls_trust.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fixtureDir = 'test/fixtures/tls';

  /// 起一个本地 TLS 服务器（测试专用 CA 签发的 localhost 证书）。
  Future<HttpServer> _startTlsServer() async {
    final ctx = SecurityContext()
      ..useCertificateChain('$fixtureDir/test_server.crt')
      ..usePrivateKey('$fixtureDir/test_server.key');
    final server = await HttpServer.bindSecure('127.0.0.1', 0, ctx);
    server.listen((req) async {
      req.response.write('pong');
      await req.response.close();
    });
    return server;
  }

  group('TlsTrust', () {
    test('asset 可加载，且是 PEM 格式的 CA 证书', () async {
      final data = await rootBundle.load('assets/diary_ca.crt');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      expect(bytes.length, greaterThan(100));
      final pem = String.fromCharCodes(bytes);
      expect(pem, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(pem, contains('-----END CERTIFICATE-----'));
    });

    test('asset 与 res/raw 内嵌的那份字节一致（防止 CA 漂移）', () async {
      final data = await rootBundle.load('assets/diary_ca.crt');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final onDisk = await File('android/app/src/main/res/raw/diary_ca.crt')
          .readAsBytes();
      expect(bytes, equals(onDisk));
    });

    test('追加信任锚点后，能连上自签证书的本地 TLS 服务器', () async {
      final server = await _startTlsServer();
      addTearDown(() => server.close(force: true));

      // 不追加任何锚点 → 自签证书不被信任，必须失败。
      final untrusted = http.Client();
      addTearDown(untrusted.close);
      await expectLater(
        untrusted.get(Uri.parse('https://localhost:${server.port}/')),
        throwsA(isA<HandshakeException>()),
      );

      // 追加测试 CA → 握手成功。
      final ca = await File('$fixtureDir/test_ca.crt').readAsBytes();
      final trusted =
          await TlsTrust.instance.clientWithTrustedCerts([ca]);
      addTearDown(trusted.close);
      final r = await trusted.get(Uri.parse('https://localhost:${server.port}/'));
      expect(r.statusCode, 200);
      expect(r.body, 'pong');
    });
  });
}
```

- [ ] **Step 4: 运行测试，确认失败**

Run:
```bash
cd D:/dev/myapp/client && powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" test test/data/remote/tls_trust_test.dart
```
Expected: **FAIL** —— 编译错误 `Target of URI doesn't exist: 'package:local_diary/src/data/remote/tls_trust.dart'`（因为 `tls_trust.dart` 还没建）。

- [ ] **Step 5: 写实现**

创建 `client/lib/src/data/remote/tls_trust.dart`：

```dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// TLS 信任锚点：产出「系统 CA ∪ 自签 CA」的可信 [http.Client]。
///
/// ## 为什么不能用 network_security_config.xml
///
/// `client/android/app/src/main/res/xml/network_security_config.xml` 里的
/// `<certificates src="@raw/diary_ca"/>` **只对 Android 原生网络栈**
/// （OkHttp / HttpsURLConnection / WebView）生效。Flutter 的 `dart:io` 网络栈
/// 直接读 `/system/etc/security/cacerts`，**从不读那份配置**（已实测：
/// `libflutter.so` 中 `networkSecurityConfig` 出现 0 次）。
///
/// 后果：自签 CA 虽随 APK 分发在 `res/raw/diary_ca.crt`，Dart 层却永远看不到，
/// TLS 握手在收到服务器证书后即被中止 —— 真机注册必然失败。
/// 详见 docs/superpowers/specs/安卓真机TLS信任-android-device-tls-trust-design.md。
///
/// ## 信任语义
///
/// 系统 CA 与自签 CA **并列**（与原 `network_security_config.xml` 的意图一致），
/// 不收窄也不放大既有信任面。以 `withTrustedRoots: true` 起手（含平台信任库），
/// 再 `setTrustedCertificatesBytes` 追加自签 CA。
class TlsTrust {
  TlsTrust._();

  static final TlsTrust instance = TlsTrust._();

  /// 内嵌自签 CA 的 asset 路径。
  static const String caAssetPath = 'assets/diary_ca.crt';

  /// 缓存的是 Future 而非 client —— 并发首次调用也只构造一次，
  /// 重复调用返回同一实例。
  Future<http.Client>? _cached;

  /// 构造（并缓存）可信 client。重复调用返回同一实例。
  Future<http.Client> client() => _cached ??= _build(const []);

  /// 构造可信 client，除内嵌自签 CA 外再追加 [extraPems]（每项是一张 PEM 证书的字节）。
  ///
  /// [extraPems] 供测试注入额外锚点；生产路径传空列表。
  /// 带额外锚点时不走缓存（信任集合不同）。
  Future<http.Client> clientWithTrustedCerts(List<List<int>> extraPems) {
    if (extraPems.isEmpty) return client();
    return _build(extraPems);
  }

  Future<http.Client> _build(List<List<int>> extraPems) async {
    final ctx = SecurityContext(withTrustedRoots: true);
    final data = await rootBundle.load(caAssetPath);
    ctx.setTrustedCertificatesBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    for (final pem in extraPems) {
      ctx.setTrustedCertificatesBytes(pem);
    }
    return IOClient(HttpClient(context: ctx));
  }
}
```

- [ ] **Step 6: 运行测试，确认通过**

Run:
```bash
cd D:/dev/myapp/client && powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" test test/data/remote/tls_trust_test.dart
```
Expected: `00:00 +3: All tests passed!`（3 项：asset 格式、CA 漂移、连接自签服务器）

若「追加信任锚点后」这项失败，报 `HandshakeException` → 检查 `test/fixtures/tls/` 证书是否由 Step 2 正确生成（`openssl verify -CAfile test_ca.crt test_server.crt` 应为 `OK`）。

- [ ] **Step 7: 提交**

```bash
cd D:/dev/myapp
git add client/lib/src/data/remote/tls_trust.dart \
        client/test/data/remote/tls_trust_test.dart \
        client/pubspec.yaml client/assets/diary_ca.crt
git commit -m "feat(F013):新增Dart侧TLS信任锚点,add Dart-side TLS trust anchor"
```

---

### Task 3: 接入主流程与照片代理

**Files:**
- Modify: `client/lib/main.dart:52`（`final httpClient = http.Client();`）
- Modify: `client/lib/src/data/sync/cos_gateway_http.dart:26-45`
- Modify: `client/lib/main.dart:99-112`（启动失败文案）
- Test: `client/test/data/sync/cos_gateway_http_test.dart`（既有测试须仍全绿）

**Interfaces:**
- Consumes: Task 2 的 `TlsTrust.instance.client()`
- Produces: 无新公开接口（`main.dart` 与 `HttpCosGateway` 内部改用可信 client）

- [ ] **Step 1: 改 `main.dart` 使用可信 client**

修改 `client/lib/main.dart`，把第 52 行

```dart
    final httpClient = http.Client();
```

改为

```dart
    // TlsTrust：系统 CA ∪ 内嵌自签 CA。dart:io 不读 network_security_config.xml，
    // 自签 CA 必须在 Dart 侧显式信任，否则真机 TLS 握手必失败。
    final httpClient = await TlsTrust.instance.client();
```

并在文件顶部补 import（按既有 import 分组，`import 'app.dart';` 之后）：

```dart
import 'src/data/remote/tls_trust.dart';
```

- [ ] **Step 2: 改 `HttpCosGateway` 的兜底 client**

修改 `client/lib/src/data/sync/cos_gateway_http.dart`。

先把 import 区补上：

```dart
import '../remote/tls_trust.dart';
```

把第 26-45 行整块替换为：

```dart
class HttpCosGateway implements CosGateway {
  HttpCosGateway({
    required this.baseUrl,
    required this.tokenLoader,
    http.Client? client,
    Future<http.StreamedResponse> Function(http.Request request)? handler,
  }) : _client = client,
        this._handler = handler;

  final String baseUrl;
  /// 当前登录 token；未登录返回 null。
  final Future<String?> Function() tokenLoader;

  /// 注入的 client；为空时惰性取可信 client（系统 CA ∪ 自签 CA）。
  /// 不能退化成 `http.Client()` —— 那会走不受信的 TLS 栈，与真机缺陷同款陷阱。
  final http.Client? _client;
  final Future<http.StreamedResponse> Function(
      http.Request request)? _handler;

  Future<http.StreamedResponse> _send(http.Request request) async {
    final handler = _handler;
    if (handler != null) return handler(request);
    final client = _client ?? await TlsTrust.instance.client();
    return client.send(request);
  }
```

- [ ] **Step 3: 改启动失败文案**

修改 `client/lib/main.dart` 第 105-107 行的错误文案，把

```dart
                const Text('暂时无法打开本地存储'),
```

改为

```dart
                const Text('暂时无法准备同步环境'),
```

并把 `snapshot.hasError` 分支的 `Column` 整体替换为下面这段（补上底层原因，便于真机排障）：

```dart
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('暂时无法准备同步环境'),
                      const SizedBox(height: 8),
                      Text('${snapshot.error}',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      TextButton(
                        onPressed: () => setState(() {
                          _engine = _open();
                        }),
                        child: const Text('重试'),
                      ),
                    ],
                  )
                : const Text('正在准备你的记录空间…'),
```

- [ ] **Step 4: 运行既有测试，确认未破坏**

Run:
```bash
cd D:/dev/myapp/client && powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" test test/data/sync/cos_gateway_http_test.dart
```
Expected: `All tests passed!`（既有 5 项 —— `_client` 由 `http.Client?` 改为可空，`handler` 路径先于 client 使用，逻辑等价）

- [ ] **Step 5: 静态分析**

Run:
```bash
cd D:/dev/myapp/client && powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" analyze
```
Expected: 无**新增**问题。若报 `unused_import` 之类，检查 `main.dart` 里 `package:http/http.dart` 是否仍被使用（`main.dart` 仍用 `http.Client` 类型标注的地方若无，需删 import）。

- [ ] **Step 6: 提交**

```bash
cd D:/dev/myapp
git add client/lib/main.dart client/lib/src/data/sync/cos_gateway_http.dart
git commit -m "feat(F013):主流程与照片代理改用可信TLS客户端,use trusted TLS client in app and COS gateway"
```

---

### Task 4: `make-cert.sh` 同步 assets 副本

**Files:**
- Modify: `deploy/make-cert.sh:55-60`（末尾的产物提示）
- Modify: `client/android/app/src/main/res/raw/diary_ca.crt`（由脚本自动覆盖，字节不变）

**Interfaces:**
- Consumes: 无
- Produces: 无新接口。效果：`bash deploy/make-cert.sh` 执行后，`deploy/certs/ca.crt`、`client/assets/diary_ca.crt`、`client/android/app/src/main/res/raw/diary_ca.crt` 三处保持一致。

- [ ] **Step 1: 在 `make-cert.sh` 加自动复制**

修改 `deploy/make-cert.sh`，把末尾的

```bash
echo
echo "产物在 ${OUT}"
echo "  ca.crt     -> 复制到 client/android/app/src/main/res/raw/diary_ca.crt"
echo "  server.key + server.crt -> 上传到服务器 /etc/nginx/ssl/diary-sync/"
echo "  ca.key     -> 留在本机，不要上传"
```

替换为

```bash
# CA 公钥证书分发给客户端两处：
#   - client/assets/diary_ca.crt                    Dart 侧 TLS 信任锚点
#                                                     （dart:io 不读 network_security_config.xml）
#   - client/android/app/src/main/res/raw/diary_ca.crt  Android 原生网络栈用
# 两处内容必须字节一致 —— client/test/data/remote/tls_trust_test.dart 有断言。
CLIENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cp "${OUT}/ca.crt" "${CLIENT_ROOT}/client/assets/diary_ca.crt"
cp "${OUT}/ca.crt" \
   "${CLIENT_ROOT}/client/android/app/src/main/res/raw/diary_ca.crt"

echo
echo "产物在 ${OUT}"
echo "  ca.crt     -> 已复制到 client/assets/diary_ca.crt 与"
echo "                client/android/app/src/main/res/raw/diary_ca.crt"
echo "  server.key + server.crt -> 上传到服务器 /etc/nginx/ssl/diary-sync/"
echo "  ca.key     -> 留在本机，不要上传"
```

- [ ] **Step 2: 验证三处副本一致**

Run:
```bash
cd D:/dev/myapp && bash deploy/make-cert.sh 2>&1 | tail -8
```
Expected: 末尾输出「ca.crt -> 已复制到 …」两行。

Run:
```bash
cd D:/dev/myapp && sha256sum deploy/certs/ca.crt client/assets/diary_ca.crt client/android/app/src/main/res/raw/diary_ca.crt
```
Expected: 三行哈希**完全相同**。

若 `deploy/certs/ca.crt` 不存在，`make-cert.sh` 会自动生成新 CA —— 那会让已装机的 App 与服务器证书失配。**若哈希与先前不同（`7C:ED:3A:...:7E:00` 变成了别的值），不要提交本次改动**，先确认 `deploy/certs/ca.key` 是否还在原处。

- [ ] **Step 3: 确认 res/raw 那份没有意外变化**

Run:
```bash
cd D:/dev/myapp && git diff --stat client/android/app/src/main/res/raw/diary_ca.crt client/assets/diary_ca.crt
```
Expected: `client/assets/diary_ca.crt` 若已是 Task 2 拷入的那份则**无 diff**；`res/raw/diary_ca.crt` 应无 diff（同一份 CA，脚本只是重新拷贝）。

- [ ] **Step 4: 提交**

```bash
cd D:/dev/myapp
git add deploy/make-cert.sh client/assets/diary_ca.crt
git commit -m "chore(F013):make-cert自动同步客户端CA副本,sync client CA copies in make-cert"
```

---

### Task 5: 全量回归

**Files:**
- 无代码改动（仅验证）

**Interfaces:**
- Consumes: Task 1–4 的全部改动
- Produces: 无

- [ ] **Step 1: 全量静态分析**

Run:
```bash
cd D:/dev/myapp/client && powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" analyze
```
Expected: 仅 pre-existing 警告，无新增问题。

- [ ] **Step 2: 全量测试**

Run:
```bash
cd D:/dev/myapp/client && powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" test
```
Expected: `All tests passed!`，总数 **≥ 461**（基线 458 + Task 2 新增 3）。

- [ ] **Step 3: 确认工作区干净（排除已知遗留）**

Run:
```bash
cd D:/dev/myapp && git status --short
```
Expected: 只可能剩下以下两项**本轮之前就存在**的遗留，不应新增其它改动：
- `M client/android/gradle.properties` —— 上一轮为绕开 Kotlin 增量缓存损坏加的 `kotlin.incremental=false`，属本地构建规避，未纳入本分支
- 两个会话日志 `.txt` —— 不入库

若出现 `M client/pubspec.lock`，说明跑测试时 pub 镜像改了传递依赖版本 → 执行 `git checkout -- client/pubspec.lock` 还原。

---

### Task 6: 真机端到端验收（T-01 / T-02）

**Files:**
- 无代码改动（仅验证 + 证据采集）

**Interfaces:**
- Consumes: Task 1–5 的全部改动
- Produces: 真机验收证据（供 Task 7 写进测试报告）

- [ ] **Step 1: 构建 debug APK（注入服务器地址与 COS HTTP 网关）**

Run:
```bash
cd D:/dev/myapp/client && ANDROID_HOME=D:/dev/myapp/.tooling/android-sdk \
  ANDROID_SDK_ROOT=D:/dev/myapp/.tooling/android-sdk \
  JAVA_HOME=D:/dev/myapp/.tooling/java \
  powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" \
  build apk --debug \
  --dart-define=SYNC_BASE_URL=https://8.148.158.13 \
  --dart-define=USE_COS_HTTP=true
```
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`。

若 Gradle 报 Kotlin 增量编译损坏（`Daemon compilation failed` / `AppendableSetBasicMap`），按既有处置：
```bash
cd D:/dev/myapp/client && rm -rf build android/.gradle
# 重跑本步骤
```

- [ ] **Step 2: 确认 APK 内含 CA asset**

Run:
```bash
cd /tmp && rm -rf apkchk && mkdir apkchk && cd apkchk && \
  unzip -o -q D:/dev/myapp/client/build/app/outputs/flutter-apk/app-debug.apk \
    "assets/flutter_assets/assets/diary_ca.crt" && \
  openssl x509 -in assets/flutter_assets/assets/diary_ca.crt -noout -subject -fingerprint -sha256
```
Expected: `subject=CN=Local Diary App CA`，指纹 `7C:ED:3A:85:76:78:04:44:93:82:7C:1D:74:1B:73:BB:E2:51:2D:D3:79:83:C8:01:43:6E:45:C0:4A:1F:7E:00`。

- [ ] **Step 3: 装到真机（MIUI 绕过路径）**

```bash
export MSYS_NO_PATHCONV=1
ADB=D:/dev/myapp/.tooling/android-sdk/platform-tools/adb.exe
$ADB devices -l
$ADB push D:/dev/myapp/client/build/app/outputs/flutter-apk/app-debug.apk \
    /sdcard/Download/local-diary-debug.apk
$ADB shell am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Download/local-diary-debug.apk" \
    -t application/vnd.android.package-archive
```
Expected: MIUI 安装器拉起后自行完成安装。若 10 秒内未装上，检查 `$ADB shell pm list packages | grep local_diary`。

**备选路径**（若 VIEW 方式失效）：`adb install -r -g <apk>` → 若返回 `INSTALL_FAILED_USER_RESTRICTED`，需用户在手机上手动确认 MIUI 弹窗（已确认无法无头绕过）。

- [ ] **Step 4: 启动 App**

```bash
export MSYS_NO_PATHCONV=1
ADB=D:/dev/myapp/.tooling/android-sdk/platform-tools/adb.exe
$ADB shell am force-stop dev.localdiary.local_diary
$ADB shell monkey -p dev.localdiary.local_diary -c android.intent.category.LAUNCHER 1
sleep 5
$ADB shell dumpsys window | grep -i mCurrentFocus
```
Expected: 焦点在 `dev.localdiary.local_diary/...MainActivity`。

- [ ] **Step 5: App 内注册（T-01）**

用 `adb shell input` 驱动 UI（坐标按 1080×2400）：
```bash
export MSYS_NO_PATHCONV=1
ADB=D:/dev/myapp/.tooling/android-sdk/platform-tools/adb.exe
$ADB shell input tap 894 2304   # 底部「我的」
sleep 2
$ADB shell input tap 860 469    # 「登录」
sleep 2
$ADB shell input tap 116 556    # 邮箱输入框
sleep 1
$ADB shell input text "f013-device-$(date +%s)@local.test"
sleep 1
$ADB shell input keyevent KEYCODE_TAB   # 跳到密码框
sleep 1
$ADB shell input text "Accept.Pw2026"
sleep 1
$ADB shell input tap 772 1018   # 「注册」
sleep 6
$ADB shell screencap -p /sdcard/reg.png
$ADB pull /sdcard/reg.png /tmp/reg.png
```
Expected: 截图显示**注册成功**（回到「我的」页，账号卡显示「云同步已开启」），**不再**显示「注册失败，请重试」。

- [ ] **Step 6: 服务端确认收到请求（T-01 证据）**

```bash
export MSYS_NO_PATHCONV=1
workbench exec --instance-id i-7xv4buzm47fxdask0bgz \
  --command "grep -E 'POST /auth/register' /var/log/nginx/access.log | tail -3"
```
Expected: 出现一行 User-Agent 为 `Dart/3.13.7 (dart:io)` 的 `POST /auth/register` 且状态 `200`。

同时确认该用户落库：
```bash
export MSYS_NO_PATHCONV=1
workbench exec --instance-id i-7xv4buzm47fxdask0bgz \
  --command "sudo -u postgres psql -d diary_sync -t -c \"select email from users order by created_at desc limit 3;\""
```
Expected: 能看到刚注册的邮箱。

- [ ] **Step 7: 真机写日记并推送（T-02）**

在 App「记录」页新建一条日记并保存（可用 `adb shell input text` 输入内容后点「下一条」/自动保存），等待 30 秒防抖推送，然后：

```bash
export MSYS_NO_PATHCONV=1
workbench exec --instance-id i-7xv4buzm47fxdask0bgz \
  --command "grep -E 'POST /sync/batch' /var/log/nginx/access.log | tail -3"
```
Expected: 出现 Dart UA 的 `POST /sync/batch` 且状态 `200`。

- [ ] **Step 8: 采集截图证据**

```bash
export MSYS_NO_PATHCONV=1
ADB=D:/dev/myapp/.tooling/android-sdk/platform-tools/adb.exe
$ADB shell screencap -p /sdcard/f013-t01.png
$ADB pull /sdcard/f013-t01.png /tmp/f013-t01.png
```
把 `/tmp/f013-t01.png`、`/tmp/reg.png` 留作测试报告证据（不入库）。

- [ ] **Step 9: 若真机仍失败 —— 排障路径**

```bash
export MSYS_NO_PATHCONV=1
ADB=D:/dev/myapp/.tooling/android-sdk/platform-tools/adb.exe
$ADB logcat -d | grep -iE "HandshakeException|CERTIFICATE|x509|handshake" | tail -10
```
若出现 `HandshakeException` 且日志含 `CERTIFICATE_VERIFY_FAILED` → 说明自签 CA 仍未被信任，回查：
- APK 内 asset 是否存在（Task 6 Step 2）
- `TlsTrust` 是否真的被 `main.dart` 与 `HttpCosGateway` 用上（`grep -rn "TlsTrust" client/lib/`）

---

### Task 7: 文档更新（测试报告 / 待办表 / 台账）

**Files:**
- Modify: `docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md`（追加「第十一轮」）
- Modify: `docs/features/F013-待办-todos.md`（更新 T-01/T-02/T-04/T-24 状态 + 新增 R-1/R-2/R-3 待办）
- Modify: `docs/features/README.md`（F013 台账行追加第十一轮摘要）
- Modify: `client/android/app/src/main/res/xml/network_security_config.xml`（加注释说明其对 Dart 层无效）
- Modify: `docs/superpowers/specs/安卓真机TLS信任-android-device-tls-trust-design.md`（状态改「已实现」）

**Interfaces:**
- Consumes: Task 1–6 的全部结果（含真机证据）
- Produces: 无代码接口

- [ ] **Step 1: 给 `network_security_config.xml` 加注释**

在 `client/android/app/src/main/res/xml/network_security_config.xml` 的 `<base-config>` 上方加注释：

```xml
    <!-- 注意：本文件只对 Android 原生网络栈（OkHttp / HttpsURLConnection / WebView）
         生效。Flutter 的 dart:io 网络栈不读它，直接读 /system/etc/security/cacerts。
         Dart 侧的自签 CA 信任由 lib/src/data/remote/tls_trust.dart 负责 ——
         见 docs/superpowers/specs/安卓真机TLS信任-android-device-tls-trust-design.md -->
```

- [ ] **Step 2: 测试报告追加「第十一轮」**

在 `docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md` 末尾追加一节，格式对齐既有轮次（先读该文件确认既有小节标题格式再写），内容须含：

| 项 | 值 |
|---|---|
| 被测版本 | `feat/F013-android-tls-trust` 分支 + `client/build/app/outputs/flutter-apk/app-debug.apk`（`--dart-define=SYNC_BASE_URL=https://8.148.158.13 --dart-define=USE_COS_HTTP=true`） |
| 环境 | 小米 2211133C（Android 15 / MIUI）、ECS `8.148.158.13`（nginx TLS 443 + systemd `diary-sync` + PostgreSQL） |
| 缺陷根因 | `dart:io` 不读 `network_security_config.xml`；证据链见设计文档 §4 |
| 修复 | `TlsTrust`（`SecurityContext(withTrustedRoots: true)` + `setTrustedCertificatesBytes`） |
| 命令 | `..\scripts\flutter.ps1 analyze` / `test` / `build apk --debug` |
| 预期与实际 | 填 Task 5/6 的**真实**输出（测试总数、analyze 结果、nginx 日志行、截图） |
| 验收编号 | T-01（注册）、T-02（推送）、T-04（跨设备） |
| 失败项 | 无则写「无」 |
| 未测范围 | 双设备交叉同步（T-04 的第二台设备）、release APK（仍用 debug 签名，T-13） |

**未执行的项写「未执行」，不写「通过」** —— 未在本轮实际跑过的命令不得填结果。

- [ ] **Step 3: 待办表更新**

修改 `docs/features/F013-待办-todos.md`：

- A 节 T-01：状态改为「已验证」，依据填 Task 6 Step 5–6 的证据（nginx 日志 Dart UA + 服务端落库）
- A 节 T-02：状态改为「已验证」，依据填 Task 6 Step 7 的证据
- A 节 T-04（真机端到端跨设备，含照片）：若 Task 6 Step 7 只覆盖单机推送未覆盖第二台设备拉回 → 记「部分验证：单机推送已过，跨设备第二台未执行」
- A 节 T-24（真机 COS 代理读写）：本轮未覆盖照片上传 → 保持「代码侧+服务端等效完成」，补注「真机照片链路待第二轮验证」
- 新增三行到 B 节或新增 F 节「F. 本轮新发现（待处理）」：
  | 编号 | 事项 | 状态 | 说明 |
  |---|---|---|---|
  | T-30 | **私有 CA 内嵌 APK 的公开发布风险**：任何人反编译 APK 即可提取该 CA 公钥，APK 外泄时等同于「信任任意人自签证书」的钥匙 | 未处理 | 公开分发前必须改用公开可信证书（域名 + Let's Encrypt 自动续期） |
  | T-31 | **登录/注册失败吞掉真实原因**：`login_page.dart` 的 `catch (_)` 只显示「注册失败，请重试」，`HandshakeException` 等底层原因丢失 | 未处理 | 本轮已让 TLS 修复，但错误透出仍缺 —— 建议显示异常类型与消息 |
  | T-32 | **未登录时状态误显示「已同步」**：`sync_engine.dart` 的 `triggerPull` 在 `_me()` 返回 null 时提前返回、不抛异常，状态被置为 `synced` | 未处理 | 与 T-09/T-10 同类（不静默失败）；建议未登录时不置 synced |
- 更新文件头「最后更新」日期与轮次描述

- [ ] **Step 4: 台账更新**

修改 `docs/features/README.md` 的 F013 行，在「进展」列追加第十一轮摘要，格式对齐既有轮次：

> **第十一轮真机 TLS 信任修复（2026-11-11）**：根因确认 —— Flutter `dart:io` 不读 `network_security_config.xml`，自签 CA 在 Dart 层不可见（`libflutter.so` 中 `networkSecurityConfig` 出现 0 次），真机注册在收到服务器证书后即中止。新增 `TlsTrust`（`SecurityContext(withTrustedRoots:true)` + `setTrustedCertificatesBytes`），CA 以 asset 随包分发，主流程与照片代理共用同一可信 client；MIUI 装机阻塞同步绕过（push 到 `/sdcard/Download/` + `am start` VIEW 意图）。真机注册/推送已验证（nginx 日志出现 `Dart/3.13.7 (dart:io)`）——见测试报告「第十一轮」与待办表 T-30/T-31/T-32

**日期用实际完成日**，不要照抄 2026-11-11 —— 按执行当天填。

- [ ] **Step 5: 设计文档状态更新**

修改 `docs/superpowers/specs/安卓真机TLS信任-android-device-tls-trust-design.md` 的头部：

```markdown
- 状态：已实现（2026-11-11，含真机验收证据）
```

日期同样按实际完成日填。

- [ ] **Step 6: 提交**

```bash
cd D:/dev/myapp
git add docs/test-reports/F013-云同步测试报告-cloud-sync-test-report.md \
        docs/features/F013-待办-todos.md \
        docs/features/README.md \
        docs/superpowers/specs/安卓真机TLS信任-android-device-tls-trust-design.md \
        client/android/app/src/main/res/xml/network_security_config.xml
git commit -m "docs(F013):记录真机TLS信任修复与验收,record device TLS trust fix and acceptance"
```

---

### Task 8: 合并前总检

**Files:**
- 无代码改动

**Interfaces:**
- Consumes: Task 1–7 全部
- Produces: 无

- [ ] **Step 1: 确认提交历史与分支**

```bash
cd D:/dev/myapp && git log --oneline main..HEAD
```
Expected: 提交链为 Task 1–7 的 8 条左右提交，每条信息符合 `<type>:<中文>,<english>` 格式。

- [ ] **Step 2: 确认未混入无关改动**

```bash
cd D:/dev/myapp && git diff --stat main..HEAD
```
Expected: 只含本计划列出的文件（client/lib、client/test、client/assets、client/pubspec.yaml、deploy/make-cert.sh、docs/*）。

**不应包含**：`client/android/gradle.properties`（本地构建规避，属上一轮遗留）、任何 `.txt` 会话日志、`client/pubspec.lock` 的传递依赖漂移。

若含 `client/android/gradle.properties`：
```bash
cd D:/dev/myapp && git checkout main -- client/android/gradle.properties
git commit -m "chore(F013):还原本地构建规避改动,revert local build workaround"
```

- [ ] **Step 3: 最终全量验证（在合并前跑一次）**

```bash
cd D:/dev/myapp/client && powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" analyze
cd D:/dev/myapp/client && powershell -NoProfile -ExecutionPolicy Bypass -File "D:/dev/myapp/scripts/flutter.ps1" test
```
Expected: analyze 无新增问题；test 全量通过（≥ 461 项）。

- [ ] **Step 4: 推送分支**

```bash
cd D:/dev/myapp && git push -u origin feat/F013-android-tls-trust
```

- [ ] **Step 5: 合并到 main（需用户明确授权）**

**合并前必须确认**：测试报告已写入真实验收结果、待办表无「未执行」被写成「通过」、台账已更新。

```bash
cd D:/dev/myapp && git checkout main && git merge --no-ff feat/F013-android-tls-trust \
  -m "merge:合并F013安卓真机TLS信任修复,merge F013 android device TLS trust fix"
git push origin main
```

按项目约定，合并后**保留**本地与远程分支，不自动删除。

---

## 附：本计划的验证缺口与已知风险

| # | 项 | 说明 |
|---|---|---|
| 1 | 方案核心已原型验证 | 本会话在 `/tmp/tlsproto` 实测：不追加锚点 → `HandshakeException`；追加 CA → HTTP 200；`IOClient(HttpClient(context:))` 形状可用 |
| 2 | asset 加载路径已实测 | `flutter test` 中 `rootBundle.load` 返回 `ByteData`，需 `TestWidgetsFlutterBinding.ensureInitialized()`；已实测通过 |
| 3 | 真实 Android 上的行为 | Dart VM 在 Android 上的 `withTrustedRoots: true` 取系统 CA 的实现与桌面略有差异 —— **Task 6 的真机验收是最终判据**。若真机仍失败且报 `HandshakeException`，退路是改用 `SecurityContext()`（不带系统根）+ 只追加自签 CA，但会失去对公开 HTTPS 站点的信任能力 |
| 4 | 双设备交叉同步（T-04） | 本轮只有一台真机；跨设备拉回与照片链路需第二台设备，Task 7 须如实记「未执行」 |
| 5 | `client/pubspec.lock` 漂移 | 跑 `flutter test` 可能因 pub 镜像更新传递依赖 → 每次提交前 `git checkout -- client/pubspec.lock` |
