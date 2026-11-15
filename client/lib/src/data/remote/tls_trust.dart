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
